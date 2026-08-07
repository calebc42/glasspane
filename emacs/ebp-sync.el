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
;; adopts it — unless the seed is already its text (nothing to do) or
;; the buffer is write-protected, which answers with the restoring
;; `edit.apply' instead.  Never guess a splice, never send a blind
;; whole-document replacement (SPEC 19.3).  Local edits still queued
;; when a race forces resync are lost by design — bounded by one
;; command's coalesced edit — because replaying them against adopted
;; foreign text WOULD be a guess.

;;; Code:

(require 'cl-lib)
(require 'ebp)
(require 'flymake)
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

;; Diagnostics rider state (the rider itself lives at the bottom of the
;; file; the vars sit here because attach/detach manage their lifecycle).
(defvar-local ebp-sync--diag-timer nil)
(defvar-local ebp-sync--diag-stamp 'unset
  "(SESSION SEQ DIAGS) of the last push.  The seq is part of the stamp
on purpose: content-identical diagnostics recomputed after an edit must
still go out — the Companion discarded the old seq's squiggles, and
without a re-send they would never reappear.")
(defvar-local ebp-sync--diag-quiet 0
  "Consecutive settled collections with nothing new.  Async backends
publish late; a bounded chase (three quiet rounds) catches them at zero
steady-state cost.")
(defvar-local ebp-sync--font-timer nil)
(defvar-local ebp-sync--font-stamp 'unset
  "(SESSION SEQ RUNS) of the last fontify push; seq in the stamp for
the same reason as diagnostics — the Companion hid the old seq's runs.")

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
    ;; Detach by KEY as well as by buffer: the `puthash' below overwrites
    ;; the routing entry, and a previous holder of this key would keep its
    ;; tracker and its locals — still sending `edit.apply' for a session
    ;; `ebp-sync--buffer' no longer routes back to.
    (let ((prior (ebp-sync--buffer client document editor-id)))
      (when (and prior (not (eq prior (current-buffer))))
        (ebp-sync-detach prior)))
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
    ;; Arm the riders here too.  They gate on `ebp-sync--client', so an
    ;; attach that FOLLOWS `edit.open' otherwise pushes nothing until the
    ;; first keystroke on either side; an attach that precedes it costs
    ;; only an early `flymake-mode' and one push the mirror lookup drops.
    (ebp-sync--arm-annotations (current-buffer))
    (current-buffer)))

(defun ebp-sync-detach (&optional buffer)
  "Release BUFFER (default current) from its session.
Safe to call when not attached.  The tracker is unregistered
(track-changes requires this on close, document change, mode disable,
and buffer death)."
  (with-current-buffer (or buffer (current-buffer))
    (when ebp-sync--diag-timer
      (cancel-timer ebp-sync--diag-timer)
      (setq ebp-sync--diag-timer nil))
    (when ebp-sync--font-timer
      (cancel-timer ebp-sync--font-timer)
      (setq ebp-sync--font-timer nil))
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
                   (progn
                     (ebp-sync--pump buffer)
                     (ebp-sync--arm-annotations buffer))
                 ;; Refused, stale, or transport error: local pending
                 ;; state is no longer trustworthy.  One resync; the
                 ;; reseed adopts the Companion's text.
                 (ebp-sync--resync buffer))))))))))

;; -------------------------------------------------------------- inbound --

(defun ebp-sync--buffer (client document editor-id)
  (let ((buf (gethash (list client document editor-id) ebp-sync--table)))
    (and (buffer-live-p buf) buf)))

;;;###autoload
(defun ebp-sync-buffer (client document editor-id)
  "The live buffer bound to CLIENT's DOCUMENT/EDITOR-ID session, or nil.
The public form of the routing lookup: an application asking \"is this
editor backed by a real buffer\" — and therefore whether the buffer or
the frame's `value' is authoritative — must not reach into a `--' name."
  (ebp-sync--buffer client document editor-id))

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
                (track-changes-fetch ebp-sync--tracker #'ignore)
                (ebp-sync--arm-annotations buf))
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
  "Adopt a reseed (fresh session or post-resync) into the bound buffer.
Three answers, not one.  An IDENTICAL seed is not re-inserted: a real
file buffer usually already holds exactly this text (the phone was
seeded from it), and the no-op replacement would mark a clean buffer
modified and hand eglot a phantom change.  A WRITE-PROTECTED buffer
does not adopt at all — `ebp-sync--on-splice' already refuses the
splice, and force-adopting the reseed afterwards handed the device the
win anyway; SPEC 19.3 makes the refusing endpoint issue, at the fresh
seq, the `edit.apply' that restores its own authoritative text (and
such an editor SHOULD be presented `read_only').  Everything else
adopts as before."
  (let ((buf (ebp-sync--buffer client document editor-id)))
    (when buf
      (with-current-buffer buf
        (setq ebp-sync--queue nil ebp-sync--inflight nil)
        (let ((mine (buffer-substring-no-properties (point-min) (point-max))))
          (cond
           ((equal seed-text mine))
           (buffer-read-only
            ;; One restoring apply, no retry: a refusal leaves the mirror
            ;; where it is and the next reseed asks again — never a loop.
            (when (ebp-sync--scalar-clean-p mine)
              (ebp-client-edit-apply client document editor-id
                                     0 (length seed-text) mine)))
           (t
            (let ((inhibit-read-only t))
              (save-excursion
                (delete-region (point-min) (point-max))
                (insert seed-text))))))
        (when ebp-sync--tracker
          (track-changes-fetch ebp-sync--tracker #'ignore))
        (setq ebp-sync--diag-stamp 'unset
              ebp-sync--font-stamp 'unset)
        (ebp-sync--arm-annotations buf)))))

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

;; ---------------------------------------------------- diagnostics rider --

;; SPEC 19.5: flymake results ride the synced session as
;; `diagnostics.show' notifications — latest-wins, stamped with the seq
;; they were computed against so the Companion refuses to draw squiggles
;; over text that has moved on.  Annotations never delay text sync: the
;; push is a fire-and-forget notification from a settle timer.
;; (Behavior reference: POC 1's jetpacs-sync.el; its shadow-buffer
;; backend surgery is gone because this bridge binds real buffers, where
;; the mode's own flymake backends already work.)

(defcustom ebp-sync-diagnostics t
  "When non-nil, run flymake over synced buffers and push results.
Checks may spawn subprocesses (byte-compile, external linters), which
costs CPU on the machine running Emacs — set to nil on battery-
constrained setups to keep sync without diagnostics."
  :type 'boolean :group 'ebp)

(defcustom ebp-sync-diagnostics-delay 3.0
  "Seconds after an edit settles before diagnostics are pushed.
Long enough for flymake's own idle timeout plus a typical backend run."
  :type 'number :group 'ebp)

(defun ebp-sync--severity (type)
  "Map a flymake TYPE to a SPEC 19.5 severity string."
  (pcase (condition-case nil
             (flymake--lookup-type-property type 'flymake-category)
           (error nil))
    ('flymake-error "error")
    ('flymake-note "info")
    (_ "warning")))

(defun ebp-sync--diag->wire (d)
  "One flymake diagnostic D as SPEC 19.5 members, 0-based scalar offsets."
  (list :start (1- (flymake-diagnostic-beg d))
        :end (1- (flymake-diagnostic-end d))
        :severity (ebp-sync--severity (flymake-diagnostic-type d))
        :message (or (flymake-diagnostic-text d) "")))

(defun ebp-sync--arm-annotations (buffer)
  "(Re)arm both annotation riders after an accepted text change."
  (ebp-sync--arm-diagnostics buffer)
  (ebp-sync--arm-fontify buffer))

(defun ebp-sync--arm-diagnostics (buffer)
  "(Re)start BUFFER's settle timer after an accepted text change."
  (with-current-buffer buffer
    (when (and ebp-sync-diagnostics ebp-sync--client)
      (unless flymake-mode (flymake-mode 1))
      (setq ebp-sync--diag-quiet 0)
      (when ebp-sync--diag-timer (cancel-timer ebp-sync--diag-timer))
      (setq ebp-sync--diag-timer
            (run-at-time ebp-sync-diagnostics-delay nil
                         #'ebp-sync--push-diagnostics buffer)))))

(defun ebp-sync--push-diagnostics (buffer)
  "Push BUFFER's current diagnostics when they changed since last push."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((ed (and ebp-sync--client
                     (gethash (cons ebp-sync--document ebp-sync--editor-id)
                              (ebp-client-editors ebp-sync--client)))))
        (when ed
          (let* ((diags (mapcar #'ebp-sync--diag->wire (flymake-diagnostics)))
                 (stamp (list (plist-get ed :session)
                              (plist-get ed :seq) diags))
                 (changed (not (equal stamp ebp-sync--diag-stamp))))
            (when changed
              (setq ebp-sync--diag-stamp stamp)
              (ebp-client-notify
               ebp-sync--client 'diagnostics.show
               (list :editor_id ebp-sync--editor-id
                     :session (plist-get ed :session)
                     :seq (plist-get ed :seq)
                     :diagnostics (vconcat diags))))
            (setq ebp-sync--diag-quiet
                  (if changed 0 (1+ ebp-sync--diag-quiet)))
            (when (< ebp-sync--diag-quiet 3)
              (setq ebp-sync--diag-timer
                    (run-at-time ebp-sync-diagnostics-delay nil
                                 #'ebp-sync--push-diagnostics buffer)))))))))

;; -------------------------------------------------------- fontify rider --

;; SPEC 19.5: the buffer's real font-lock state ships as `fontify.show'
;; ROLE runs — sorted, non-overlapping, seq-stamped — and the Companion
;; styles each role from the active theme.  POC 1 sent literal colors
;; per span; the role indirection is what lets one push look right in
;; both light and dark themes.

(defcustom ebp-sync-fontify t
  "When non-nil, push font-lock results over synced sessions.
The editor then shows the user's real major-mode highlighting."
  :type 'boolean :group 'ebp)

(defcustom ebp-sync-fontify-delay 0.2
  "Seconds after an accepted change before fontification is pushed.
Short: font-lock is cheap at `ebp-sync-fontify-max-chars' scale, and a
long delay leaves freshly typed code visibly unstyled."
  :type 'number :group 'ebp)

(defcustom ebp-sync-fontify-max-chars 65536
  "Buffers larger than this skip fontify pushes.
Sync and diagnostics still work; only the highlighting stays local."
  :type 'natnum :group 'ebp)

(defconst ebp-sync--face-roles
  '((font-lock-comment-face . "comment")
    (font-lock-comment-delimiter-face . "comment")
    (font-lock-doc-face . "string")
    (font-lock-string-face . "string")
    (font-lock-keyword-face . "keyword")
    (font-lock-builtin-face . "keyword")
    (font-lock-function-name-face . "function")
    (font-lock-function-call-face . "function")
    (font-lock-constant-face . "constant")
    (font-lock-variable-name-face . "variable")
    (font-lock-variable-use-face . "variable")
    (font-lock-type-face . "type")
    (font-lock-number-face . "number")
    (font-lock-operator-face . "operator")
    (font-lock-preprocessor-face . "preprocessor")
    (outline-1 . "heading") (outline-2 . "heading")
    (outline-3 . "heading") (outline-4 . "heading")
    (outline-5 . "heading") (outline-6 . "heading")
    (outline-7 . "heading") (outline-8 . "heading")
    (link . "link")
    (org-todo . "todo")
    (org-done . "done")
    (org-tag . "tag"))
  "Built-in faces to contract `syntax_roles'.
Only faces Emacs itself ships (font-lock, outline, org, `link') appear;
anything else resolves through its `:inherit' chain or ships unstyled.")

(defun ebp-sync--face-role (face)
  "The syntax role for text property FACE, or nil for unstyled.
FACE may be a symbol, an anonymous plist, or a list of either; the
first element that reaches a known face — directly or through
`:inherit' — wins."
  (catch 'role
    (dolist (f (if (and (listp face) (not (keywordp (car-safe face))))
                   face (list face)))
      (while (and f (symbolp f))
        (when-let* ((role (cdr (assq f ebp-sync--face-roles))))
          (throw 'role role))
        (let ((parent (and (facep f) (face-attribute f :inherit))))
          (setq f (if (consp parent) (car parent) parent)
                f (and (symbolp f) (not (eq f 'unspecified)) f)))))
    nil))

(defun ebp-sync--fontify-runs ()
  "The buffer's face runs as SPEC 19.5 wire plists.
Sorted and non-overlapping by construction (a walk over face property
changes); adjacent same-role runs merge; unstyled stretches ship
nothing."
  (ignore-errors (font-lock-ensure))
  (let ((pos (point-min)) runs)
    (while (< pos (point-max))
      (let ((next (next-single-property-change pos 'face nil (point-max)))
            (role (ebp-sync--face-role (get-text-property pos 'face))))
        (when role
          (let ((prev (car runs)))
            (if (and prev (equal (plist-get prev :role) role)
                     (= (plist-get prev :end) (1- pos)))
                (setf (car runs) (plist-put prev :end (1- next)))
              (push (list :start (1- pos) :end (1- next) :role role)
                    runs))))
        (setq pos next)))
    (nreverse runs)))

(defun ebp-sync--arm-fontify (buffer)
  "(Re)start BUFFER's fontify push timer after an accepted change."
  (with-current-buffer buffer
    (when (and ebp-sync-fontify ebp-sync--client)
      (when ebp-sync--font-timer (cancel-timer ebp-sync--font-timer))
      (setq ebp-sync--font-timer
            (run-at-time ebp-sync-fontify-delay nil
                         #'ebp-sync--push-fontify buffer)))))

(defun ebp-sync--push-fontify (buffer)
  "Push BUFFER's fontification when it changed since the last push."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((ed (and ebp-sync--client
                     (<= (buffer-size) ebp-sync-fontify-max-chars)
                     (gethash (cons ebp-sync--document ebp-sync--editor-id)
                              (ebp-client-editors ebp-sync--client)))))
        (when ed
          (let* ((runs (ebp-sync--fontify-runs))
                 (stamp (list (plist-get ed :session)
                              (plist-get ed :seq) runs)))
            (unless (equal stamp ebp-sync--font-stamp)
              (setq ebp-sync--font-stamp stamp)
              (ebp-client-notify
               ebp-sync--client 'fontify.show
               (list :editor_id ebp-sync--editor-id
                     :session (plist-get ed :session)
                     :seq (plist-get ed :seq)
                     :runs (vconcat runs))))))))))

(provide 'ebp-sync)
;;; ebp-sync.el ends here
