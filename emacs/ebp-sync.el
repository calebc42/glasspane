;;; ebp-sync.el --- Live buffer sync over EBP Section 19 -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; The buffer bridge for synchronized editors (ARCHITECTURE-POC3 Step 3;
;; behavior reference: POC 1's jetpacs-sync.el, rebuilt against Section
;; 19's first-class methods).  ebp.el keeps the string mirror; this
;; module binds one real buffer to one (document . editor-id) session:
;;
;;   outbound — built-in track-changes.el watches the buffer; each
;;     fetched change becomes ONE `edit.apply' splice, sent strictly one
;;     at a time (one operation contends for seq+1, SPEC 19.4);
;;   inbound — accepted `edit.delta' splices land in the buffer through
;;     ebp.el's splice hook as ONE atomic change, then are consumed from
;;     the tracker so they are never echoed back.
;;
;; Positions are Unicode scalar values = Emacs chars; `start' is the
;; zero-based splice start, so buffer position = start + 1.  Synced
;; buffers must not be narrowed.
;;
;; Resynchronization is the ONLY recovery: a fetch reporting `error', a
;; refused or stale apply, a write-protected buffer, or a remote splice
;; racing unsent local edits each drop local pending state and request
;; one `edit.resync'; the reseed arrives as `edit.open' and the buffer
;; adopts it.  Never guess a splice, never send a blind whole-document
;; replacement (SPEC 19.3).  Local edits still queued when a race forces
;; resync are lost by design — bounded by one command's coalesced edit —
;; because replaying them against adopted foreign text WOULD be a guess.

;;; Code:

(require 'cl-lib)
(require 'ebp)
(require 'track-changes)

(defvar ebp-sync--table (make-hash-table :test #'equal)
  "Routing table: (CLIENT DOCUMENT EDITOR-ID) -> live attached buffer.")

(defvar-local ebp-sync--client nil)
(defvar-local ebp-sync--document nil)
(defvar-local ebp-sync--editor-id nil)
(defvar-local ebp-sync--tracker nil)
(defvar-local ebp-sync--queue nil
  "Pending outbound splices, oldest first: (START DEL TEXT).")
(defvar-local ebp-sync--inflight nil
  "Non-nil while one `edit.apply' awaits its result.")

(defun ebp-sync--scalar-clean-p (s)
  "Non-nil when S is losslessly representable as Unicode scalar values.
Emacs buffers can carry raw bytes (chars above #x10FFFF); those cannot
cross the wire (SPEC 19.1), so they refuse sync instead of corrupting."
  (cl-every (lambda (c) (<= c #x10FFFF)) s))

;;;###autoload
(defun ebp-sync-attach (client document editor-id &optional buffer)
  "Bind BUFFER (default current) to CLIENT's DOCUMENT/EDITOR-ID session.
If the mirror already holds a session, the buffer adopts its text.
Returns the buffer, or signals if it carries non-scalar bytes."
  (with-current-buffer (or buffer (current-buffer))
    (when ebp-sync--tracker (ebp-sync-detach))
    (let ((seed (ebp-client-editor-text client document editor-id)))
      (when seed
        (unless (ebp-sync--scalar-clean-p seed)
          (error "ebp-sync: mirror text is not scalar-clean"))
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert seed))))
    (setq ebp-sync--client client
          ebp-sync--document document
          ebp-sync--editor-id editor-id
          ebp-sync--queue nil
          ebp-sync--inflight nil
          ;; Deferred signal (never :immediate) + :disjoint, per the
          ;; Step 3 recipe: encoding and transport stay out of the
          ;; low-level change hooks, and two far-apart edits are fetched
          ;; separately instead of widened into one huge replacement.
          ;; The closure anchors the buffer: on the :disjoint pre-warning
          ;; the fetch MUST happen before the signal returns, and the
          ;; plain deferred call shares the same flush.
          ebp-sync--tracker (let ((buf (current-buffer)))
                              (track-changes-register
                               (lambda (_id &optional _distance)
                                 (when (buffer-live-p buf)
                                   (ebp-sync-flush buf)))
                               :disjoint t)))
    (puthash (list client document editor-id) (current-buffer)
             ebp-sync--table)
    (cl-pushnew #'ebp-sync--on-splice
                (ebp-client-edit-splice-functions client))
    (cl-pushnew #'ebp-sync--on-open
                (ebp-client-edit-open-functions client))
    (cl-pushnew #'ebp-sync--on-change
                (ebp-client-edit-change-functions client))
    (add-hook 'kill-buffer-hook #'ebp-sync-detach nil t)
    (current-buffer)))

(defun ebp-sync-detach (&optional buffer)
  "Release BUFFER (default current) from its session.
Safe to call when not attached.  The tracker is unregistered
(track-changes requires this on close, document change, mode disable,
and buffer death)."
  (with-current-buffer (or buffer (current-buffer))
    (when ebp-sync--tracker
      (track-changes-unregister ebp-sync--tracker)
      (setq ebp-sync--tracker nil))
    (when ebp-sync--client
      (remhash (list ebp-sync--client ebp-sync--document ebp-sync--editor-id)
               ebp-sync--table)
      (setq ebp-sync--client nil ebp-sync--document nil
            ebp-sync--editor-id nil ebp-sync--queue nil
            ebp-sync--inflight nil))
    (remove-hook 'kill-buffer-hook #'ebp-sync-detach t)))

;; ------------------------------------------------------------- outbound --

(defun ebp-sync-flush (&optional buffer)
  "Fetch pending buffer changes as splices and pump the send queue.
The fetch callback only copies and enqueues — no buffer modification,
no I/O (the track-changes contract for the disjoint callback)."
  (with-current-buffer (or buffer (current-buffer))
    (when ebp-sync--tracker
      (track-changes-fetch
       ebp-sync--tracker
       (lambda (beg end before)
         (if (or (eq before 'error)
                 (track-changes-inconsistent-state-p))
             (ebp-sync--resync (current-buffer))
           (let ((text (buffer-substring-no-properties beg end)))
             (if (and (ebp-sync--scalar-clean-p text)
                      (or (stringp before) (null before)))
                 (setq ebp-sync--queue
                       (nconc ebp-sync--queue
                              (list (list (1- beg)
                                          (length (or before ""))
                                          text))))
               (ebp-sync--resync (current-buffer)))))))
      (ebp-sync--pump (current-buffer)))))

(defun ebp-sync--pump (buffer)
  "Send the oldest queued splice unless one is already in flight.
Without a live mirror session there is nothing to contend for seq+1
against: pending splices are dropped, and the eventual `edit.open'
reseeds the buffer."
  (with-current-buffer buffer
    (when (and ebp-sync--client ebp-sync--queue (not ebp-sync--inflight)
               (not (ebp-client-editor-text ebp-sync--client
                                            ebp-sync--document
                                            ebp-sync--editor-id)))
      (setq ebp-sync--queue nil))
    (when (and ebp-sync--client ebp-sync--queue (not ebp-sync--inflight))
      (pcase-let ((`(,start ,del ,text) (pop ebp-sync--queue)))
        (setq ebp-sync--inflight t)
        (ebp-client-edit-apply
         ebp-sync--client ebp-sync--document ebp-sync--editor-id
         start del text
         :callback
         (lambda (status error)
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (setq ebp-sync--inflight nil)
               (if (and (null error) (equal status "applied"))
                   (ebp-sync--pump buffer)
                 ;; Refused, stale, or transport error: local pending
                 ;; state is no longer trustworthy.  One resync; the
                 ;; reseed adopts the Companion's text.
                 (ebp-sync--resync buffer))))))))))

;; -------------------------------------------------------------- inbound --

(defun ebp-sync--buffer (client document editor-id)
  (let ((buf (gethash (list client document editor-id) ebp-sync--table)))
    (and (buffer-live-p buf) buf)))

(defun ebp-sync--on-splice (client document editor-id start del text)
  "Apply an accepted inbound `edit.delta' splice to the bound buffer.
An unsent local edit racing this splice makes local positions a guess —
drop them and resync instead (SPEC 19.3: never a wrong edit)."
  (let ((buf (ebp-sync--buffer client document editor-id)))
    (when buf
      (with-current-buffer buf
        ;; Anything the tracker has seen but we have not flushed is a
        ;; local edit the Companion did not know about when it spliced.
        (ebp-sync--fetch-pending-into-queue)
        (if (or ebp-sync--queue ebp-sync--inflight)
            (ebp-sync--resync buf)
          (condition-case nil
              (progn
                (atomic-change-group
                  (save-excursion
                    (delete-region (1+ start) (+ 1 start del))
                    (goto-char (1+ start))
                    (insert text)))
                ;; Consume our own known change so it is not echoed.
                (track-changes-fetch ebp-sync--tracker #'ignore))
            ;; Write protection is honored, never overridden (SPEC 19.3);
            ;; the refusing side recovers through resync.
            (error (ebp-sync--resync buf))))))))

(defun ebp-sync--fetch-pending-into-queue ()
  "Pull any not-yet-signaled tracker changes into the outbound queue."
  (when ebp-sync--tracker
    (track-changes-fetch
     ebp-sync--tracker
     (lambda (beg end before)
       (setq ebp-sync--queue
             (nconc ebp-sync--queue
                    (list (list (1- beg)
                                (if (stringp before) (length before) 0)
                                (buffer-substring-no-properties beg end)))))))))

(defun ebp-sync--on-open (client document editor-id seed-text _prior)
  "Adopt a reseed (fresh session or post-resync) into the bound buffer."
  (let ((buf (ebp-sync--buffer client document editor-id)))
    (when buf
      (with-current-buffer buf
        (setq ebp-sync--queue nil ebp-sync--inflight nil)
        (let ((inhibit-read-only t))
          (save-excursion
            (delete-region (point-min) (point-max))
            (insert seed-text)))
        (when ebp-sync--tracker
          (track-changes-fetch ebp-sync--tracker #'ignore))))))

(defun ebp-sync--on-change (client document editor-id text)
  "Detach when the session closes (TEXT nil after `edit.close')."
  (when (null text)
    (let ((buf (ebp-sync--buffer client document editor-id)))
      (when buf (ebp-sync-detach buf)))))

(defun ebp-sync--resync (buffer)
  "Drop local pending state and request one resynchronization."
  (with-current-buffer buffer
    (setq ebp-sync--queue nil ebp-sync--inflight nil)
    (when ebp-sync--tracker
      (track-changes-fetch ebp-sync--tracker #'ignore))
    (when ebp-sync--client
      (ebp-client-edit-resync ebp-sync--client ebp-sync--document
                              ebp-sync--editor-id))))

(provide 'ebp-sync)
;;; ebp-sync.el ends here
