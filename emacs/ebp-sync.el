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
;; zero-based splice start, so buffer position = start + 1.
;;
;; THE DOCUMENT IS THE WHOLE BUFFER.  A narrowing is a VIEW, and the
;; §19 document never is one: it has no wire representation, no
;; `edit.close' to signal when it changes, and the file the save writes
;; is whole.  So every operation here runs under `save-restriction' +
;; `widen' — the seed comparison, both adoptions, every content
;; snapshot, both annotation walks, the caret's `goto-char', and every
;; `track-changes' touch (register included: the tracker's state is
;; created with the ACCESSIBLE bounds in force, and one created narrowed
;; asserts on the first change outside that restriction, however
;; carefully the change itself widens).  A restriction that can survive
;; is restored; one whose anchoring text a full adoption deletes cannot
;; be, and the buffer is left wide rather than showing an arbitrary
;; window into foreign text.
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
(require 'eldoc)
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
(defvar-local ebp-sync--eldoc-stamp 'unset
  "(SESSION SEQ TEXT) of the last eldoc push.  No timer beside it: the
rider answers each caret report inline, because SPEC 19.3 puts the
throttling duty on the Companion, at the source.")

(defun ebp-sync--scalar-clean-p (s)
  "Non-nil when S is losslessly representable as Unicode scalar values.
Emacs buffers can carry raw bytes (chars above #x10FFFF); those cannot
cross the wire (SPEC 19.1), so they refuse sync instead of corrupting."
  (cl-every (lambda (c) (<= c #x10FFFF)) s))

;;;###autoload
(defun ebp-sync-attach (client document editor-id &optional buffer)
  "Bind BUFFER (default current) to CLIENT's DOCUMENT/EDITOR-ID session.
If the mirror already holds a session, and its text DIFFERS from the
buffer's, the buffer adopts it; an identical seed is not re-inserted.
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
        ;; THE SAME EQUALITY GUARD `ebp-sync--on-open' carries, for the
        ;; same reason: a real-file buffer usually already holds exactly
        ;; the mirror's text, and re-inserting it is a no-op that costs
        ;; the user a modified flag and hands eglot a phantom change.
        ;; Adoption over a DIFFERENT seed is still this function's
        ;; contract — only the identity case is skipped.
        ;;
        ;; ONE `save-restriction' spans the comparison AND the adoption,
        ;; because they must answer about the same text.  Unwidened, the
        ;; guard compared the visible region against a whole-document
        ;; mirror, called that a difference, and adopted — replacing the
        ;; whole buffer with text it already held, marking it modified
        ;; and dropping the user's restriction.  `delete-region' rather
        ;; than `erase-buffer': same result here (erase-buffer widens
        ;; too), but inside a `save-restriction' the widen must be the
        ;; visible one, not a side effect of the primitive.
        (save-restriction
          (widen)
          (unless (equal seed (buffer-substring-no-properties
                               (point-min) (point-max)))
            (let ((inhibit-read-only t))
              (delete-region (point-min) (point-max))
              (insert seed))))))
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
          ;;
          ;; REGISTERED WIDE.  `track-changes' seeds its state from the
          ;; ACCESSIBLE bounds at registration and then asserts against
          ;; them; a tracker registered under a narrowing signals
          ;; `cl-assertion-failed' on the first change outside that
          ;; restriction — including OUR OWN widened inbound splice —
          ;; and no arithmetic anywhere else can reach that.
          ebp-sync--tracker (let ((buf (current-buffer)))
                              (save-restriction
                                (widen)
                                (track-changes-register
                                 (lambda (_id &optional _distance)
                                   (when (buffer-live-p buf)
                                     (ebp-sync-flush buf)))
                                 :disjoint t))))
    (puthash (list client document editor-id) (current-buffer)
             ebp-sync--table)
    (cl-pushnew #'ebp-sync--on-splice
                (ebp-client-edit-splice-functions client))
    (cl-pushnew #'ebp-sync--on-open
                (ebp-client-edit-open-functions client))
    (cl-pushnew #'ebp-sync--on-change
                (ebp-client-edit-change-functions client))
    (cl-pushnew #'ebp-sync--on-caret
                (ebp-client-edit-caret-functions client))
    (add-hook 'kill-buffer-hook #'ebp-sync-detach nil t)
    ;; R1: the mode's language tooling arms with the session.  The
    ;; elisp backend swap runs BEFORE the riders arm — the arm enables
    ;; flymake and kicks the first check, which must never spawn
    ;; "emacs -batch".  The eglot connect is async and throttled.
    (ebp-sync--swap-elisp-backend)
    (ebp-sync--ensure-eglot)
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
    ;; The backend swap is a property of the SESSION: desktop editing
    ;; after detach sees the stock backend again.
    (ebp-sync--restore-elisp-backend)
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
      ;; The widen wraps the FETCH, not the callback: `track-changes'
      ;; asserts `(<= (point-min) beg end (point-max))' before it hands
      ;; the change over, so by the time the callback runs the signal
      ;; has already fired.  BEG/END are absolute buffer positions
      ;; either way, which is why `(1- beg)' below needs no arithmetic
      ;; change — only a buffer wide enough to read them out of.
      (save-restriction
        (widen)
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
                 (ebp-sync--resync (current-buffer))))))))
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

;;;###autoload
(defun ebp-sync-attached-buffer (document editor-id)
  "The live buffer attached to DOCUMENT/EDITOR-ID under any client, or nil.
The table's keys carry the client, but the JC-0 single-client floor
means (DOCUMENT . EDITOR-ID) names at most one session, so the scan is
sound.  The clientless form exists for callers answering ebp's
clientless `:edit-complete-function' contract — `ebp-complete's
live-buffer arm above all — which hold a document and an editor id and
nothing else."
  (catch 'ebp-sync--attached
    (maphash (lambda (key buf)
               (when (and (equal (nth 1 key) document)
                          (equal (nth 2 key) editor-id)
                          (buffer-live-p buf))
                 (throw 'ebp-sync--attached buf)))
             ebp-sync--table)
    nil))

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
                ;; START is a DOCUMENT offset, so `(1+ start)' is an
                ;; absolute buffer position and needs no rebasing — but
                ;; `delete-region' validates against the accessible
                ;; portion and signals for a target outside it, which
                ;; turned every phone keystroke outside the user's
                ;; restriction into a resync the reseed could not
                ;; repair.  `save-excursion' outermost, per its own
                ;; docstring; neither it nor `atomic-change-group' saves
                ;; the restriction.
                (atomic-change-group
                  (save-excursion
                    (save-restriction
                      (widen)
                      (delete-region (1+ start) (+ 1 start del))
                      (goto-char (1+ start))
                      (insert text))))
                ;; Consume our own known change so it is not echoed —
                ;; widened, because the change we just made may lie
                ;; outside the restriction we just restored.
                (save-restriction
                  (widen)
                  (track-changes-fetch ebp-sync--tracker #'ignore))
                (ebp-sync--arm-annotations buf))
            ;; Write protection is honored, never overridden (SPEC 19.3);
            ;; the refusing side recovers through resync.
            (error (ebp-sync--resync buf))))))))

(defun ebp-sync--fetch-pending-into-queue ()
  "Pull any not-yet-signaled tracker changes into the outbound queue."
  (when ebp-sync--tracker
    (save-restriction
      (widen)
      (track-changes-fetch
       ebp-sync--tracker
       (lambda (beg end before)
         (setq ebp-sync--queue
               (nconc ebp-sync--queue
                      (list (list (1- beg)
                                  (if (stringp before) (length before) 0)
                                  (buffer-substring-no-properties
                                   beg end))))))))))

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
        ;; MINE is the DOCUMENT.  It answers three questions and all
        ;; three are whole-document ones: is the seed already our text,
        ;; is our text carriable, and — on the refusing leg — what does
        ;; the device's whole document become.  Taken from the
        ;; accessible portion, that last one sent `0 (length seed) mine'
        ;; built from a fragment and truncated the DEVICE's document to
        ;; whatever the user happened to be narrowed to.
        (let ((mine (save-restriction
                      (widen)
                      (buffer-substring-no-properties
                       (point-min) (point-max)))))
          (cond
           ((equal seed-text mine))
           (buffer-read-only
            ;; One restoring apply, no retry: a refusal leaves the mirror
            ;; where it is and the next reseed asks again — never a loop.
            (when (ebp-sync--scalar-clean-p mine)
              (ebp-client-edit-apply client document editor-id
                                     0 (length seed-text) mine)))
           (t
            ;; The SAME adoption `ebp-sync-attach' performs, and now the
            ;; same shape: unwidened this emptied only the visible region
            ;; and refilled it, splicing the Companion's whole document
            ;; INTO the narrowing with the invisible prefix and suffix
            ;; left around it.  The restriction does not come back — its
            ;; markers were anchored in the text this deletes — and that
            ;; is the honest outcome for a whole-document replacement.
            (let ((inhibit-read-only t))
              (save-excursion
                (save-restriction
                  (widen)
                  (delete-region (point-min) (point-max))
                  (insert seed-text)))))))
        (when ebp-sync--tracker
          (save-restriction
            (widen)
            (track-changes-fetch ebp-sync--tracker #'ignore)))
        (setq ebp-sync--diag-stamp 'unset
              ebp-sync--font-stamp 'unset
              ebp-sync--eldoc-stamp 'unset)
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
      (save-restriction
        (widen)
        (track-changes-fetch ebp-sync--tracker #'ignore)))
    (when ebp-sync--client
      (ebp-client-edit-resync ebp-sync--client ebp-sync--document
                              ebp-sync--editor-id))))

;; ------------------------------------------------- language tooling arm --
;;
;; POC 1 port (PLAN-glasspane-completion.md R1; behavior reference
;; jetpacs-sync.el).  This bridge binds real buffers, so eglot needs no
;; special buffer strategy — the LSP session lives in the very buffer
;; being synced — but three of POC 1's mobile lessons apply verbatim:
;;
;; 1. `eglot-ensure' defers its connect to `post-command-hook'
;;    (emacs-30.1 eglot.el:1455-1476), which never fires in an Emacs
;;    driven headless through a socket.  Connect DIRECTLY, fully async.
;; 2. Android's phantom-process killer reaps backgrounded language
;;    servers.  Attach runs on every open, so the throttled connect
;;    attempt there is what revives a reaped server the next time the
;;    file opens on the device.
;; 3. `elisp-flymake-byte-compile' spawns "emacs -batch" per check —
;;    impossible on the Android port, where Emacs is a shared library
;;    inside an app process with no executable to spawn, and a
;;    subprocess per typing pause everywhere else once the arm below
;;    kicks a check per edit.  Attached elisp buffers get an in-process
;;    backend instead; detach restores the stock one.

(defcustom ebp-sync-eglot t
  "When non-nil, attaching an LSP-able buffer also connects eglot.
Buffers whose `major-mode' is in `ebp-sync-eglot-modes' get a direct,
asynchronous language-server connect at attach, so the device editor
completes, squiggles, and documents with everything the desktop has.
Servers must be findable on `exec-path' (on Android, Termux's usr/bin
via the shared-uid build).  Set to nil to sync without language
servers."
  :type 'boolean :group 'ebp)

(defcustom ebp-sync-eglot-modes
  '(python-mode python-ts-mode sh-mode bash-ts-mode
    c-mode c-ts-mode c++-mode c++-ts-mode rust-mode rust-ts-mode)
  "Major modes whose attached buffers get an eglot connect attempt.
Elisp and org are absent on purpose: their in-process backends are
better than any language server, and never cost a subprocess."
  :type '(repeat symbol) :group 'ebp)

(declare-function eglot-current-server "eglot")
(declare-function eglot--guess-contact "eglot")
(declare-function eglot--connect "eglot")
(defvar eglot-sync-connect)

(declare-function project-root "project" (project))

(defvar ebp-sync--eglot-attempts (make-hash-table :test #'equal)
  "Project root -> float-time of the last eglot connect attempt.
Keyed by PROJECT, never by buffer (the R1 review's headline): with
`eglot-sync-connect' nil the server reaches `eglot-current-server'
only after the async initialize handshake, so during a cold server's
multi-second startup EVERY buffer of the project passes the no-server
gate — a buffer-local stamp then lets a second file of the same
project spawn a second server, leaking a process and silently
splitting the project's buffers across two servers.  One pending
connect per project is the actual invariant.  Never cleared: a stale
stamp only delays a reconnect by its 30s window.")

(defun ebp-sync--eglot-project-key ()
  "The throttle key for the current buffer's eglot project.
The same root eglot's own contact guess will use; projectless files
fall back to their directory, which is also how eglot scopes its
transient projects."
  (expand-file-name
   (or (when-let* ((pr (project-current))) (project-root pr))
       default-directory)))

(defun ebp-sync--ensure-eglot ()
  "Connect the current buffer to its language server, if it should have one.
NOT `eglot-ensure': that defers the connect to `post-command-hook',
which never fires in an Emacs driven headless through a socket — the
same trap as flymake's deferred start.  Connect directly instead,
fully async (`eglot-sync-connect' nil) so attach never blocks on a
cold server.  No server program, or a missing executable, degrades
silently to the non-LSP experience.  The 30s per-PROJECT throttle
(`ebp-sync--eglot-attempts') stops any open — same buffer reattached,
same file revisited, a SECOND file of the same project — from racing a
still-initializing connect into a second server process, while still
letting a later open revive a server the OS reaped.
Remote-before-stat: `file-remote-p' answers from the NAME, so a
TRAMP-visiting buffer is refused before any stat can dial."
  (when (and ebp-sync-eglot
             (memq major-mode ebp-sync-eglot-modes)
             buffer-file-name
             (not (file-remote-p buffer-file-name))
             (file-exists-p buffer-file-name)
             (require 'eglot nil t)
             (not (ignore-errors (eglot-current-server))))
    (let ((key (ebp-sync--eglot-project-key)))
      (when (> (- (float-time) (gethash key ebp-sync--eglot-attempts 0)) 30)
        (puthash key (float-time) ebp-sync--eglot-attempts)
        (condition-case err
            (let ((eglot-sync-connect nil))
              (apply #'eglot--connect (eglot--guess-contact)))
          ;; The error SYMBOL only (SPEC 23.3): a contact guess embeds
          ;; paths and command lines in the datum.
          (error (message "ebp-sync: eglot connect failed (%s)"
                          (car err))))))))

(defcustom ebp-sync-elisp-inprocess (eq system-type 'android)
  "When non-nil, attached elisp buffers use the in-process flymake backend.
Default: only where Emacs cannot spawn itself — the Android port is a
shared library inside an app process with no executable to run, and
the phantom-process killer reaps children anyway.  Everywhere else the
stock `elisp-flymake-byte-compile' keeps its subprocess isolation: the
in-process backend runs macro expansion and `eval-when-compile' in the
LIVE session, so a pathological form can wedge a headless Emacs (no
C-g arrives over a socket) — a trade worth making only where the
alternative is no compile diagnostics at all."
  :type 'boolean :group 'ebp)

(defvar-local ebp-sync--elisp-swapped nil
  "Non-nil when attach swapped this buffer's elisp flymake backend.")

(defvar-local ebp-sync-elisp-repl nil
  "Non-nil in an attached buffer holding REPL input rather than a file.
REPL input evaluates with lexical binding, so the diagnostics copy
byte-compiles under a prepended `lexical-binding: t' cookie: warnings
match eval semantics, and the no-cookie warning — noise against a
one-expression REPL line — can never fire.  Positions shift back by
the cookie's length.  A REPL attacher sets this before attach.")

(defun ebp-sync--swap-elisp-backend ()
  "Replace `elisp-flymake-byte-compile' with the in-process backend.
Buffer-local and recorded, so `ebp-sync--restore-elisp-backend' can
put the stock backend back at detach — the swap is a property of the
SESSION, not of the buffer, and desktop editing after detach must see
stock behavior.  `elisp-flymake-checkdoc' stays: it is in-process
already."
  (when (and ebp-sync-elisp-inprocess
             (derived-mode-p 'emacs-lisp-mode)
             (memq #'elisp-flymake-byte-compile flymake-diagnostic-functions)
             (not ebp-sync--elisp-swapped))
    (setq ebp-sync--elisp-swapped t)
    (remove-hook 'flymake-diagnostic-functions #'elisp-flymake-byte-compile t)
    (add-hook 'flymake-diagnostic-functions #'ebp-sync--flymake-elisp nil t)))

(defun ebp-sync--restore-elisp-backend ()
  "Reverse `ebp-sync--swap-elisp-backend', if it ran."
  (when ebp-sync--elisp-swapped
    (setq ebp-sync--elisp-swapped nil)
    (remove-hook 'flymake-diagnostic-functions #'ebp-sync--flymake-elisp t)
    (add-hook 'flymake-diagnostic-functions
              #'elisp-flymake-byte-compile nil t)))

(declare-function byte-compile-dest-file "bytecomp" (filename))
(defvar byte-compile-log-warning-function)

(defun ebp-sync--elisp-paren-diags ()
  "Unbalanced-paren diagnostics for the current buffer, or nil."
  (save-excursion
    (condition-case err
        (let ((pos (point-min)))
          (while (setq pos (scan-sexps pos 1)))
          nil)
      (scan-error
       (let* ((beg (min (max (point-min) (or (nth 2 err) (point-min)))
                        (point-max)))
              (end (min (max (1+ beg) (or (nth 3 err) beg)) (point-max))))
         (list (flymake-make-diagnostic
                (current-buffer) beg end :error
                (or (nth 1 err) "Unbalanced parentheses"))))))))

(defun ebp-sync--elisp-compile-diags ()
  "In-process byte-compile diagnostics for the current buffer.
Compiles a temp copy so nothing touches the user's files.  File
buffers copy the text verbatim, so warning positions map straight
back; REPL buffers (`ebp-sync-elisp-repl') get a `lexical-binding: t'
cookie line prepended — matching how the REPL evaluates — and
positions are shifted back by the cookie's length."
  (require 'bytecomp)
  (let* ((cookie (if ebp-sync-elisp-repl
                     ";;; -*- lexical-binding: t; -*-\n"
                   ""))
         (shift (length cookie))
         (src (concat cookie (buffer-substring-no-properties
                              (point-min) (point-max))))
         (buf (current-buffer))
         (tmp (make-temp-file "ebp-sync-flymake" nil ".el"))
         diags)
    (unwind-protect
        (let ((coding-system-for-write 'utf-8))
          (write-region src nil tmp nil 'silent)
          (let ((byte-compile-log-warning-function
                 (lambda (string &optional position _fill level)
                   (with-current-buffer buf
                     (let* ((beg (min (max (point-min)
                                           (- (if (numberp position) position 1)
                                              shift))
                                      (point-max)))
                            ;; Underline the whole form at the position.
                            (end (min (or (ignore-errors (scan-sexps beg 1))
                                          (1+ beg))
                                      (point-max))))
                       (push (flymake-make-diagnostic
                              buf beg (max end (min (1+ beg) (point-max)))
                              (if (eq level :error) :error :warning)
                              string)
                             diags)))))
                (inhibit-message t))
            (ignore-errors (byte-compile-file tmp))))
      (ignore-errors (delete-file tmp))
      (ignore-errors (delete-file (byte-compile-dest-file tmp))))
    (nreverse diags)))

(defun ebp-sync--flymake-elisp (report-fn &rest _)
  "Flymake backend for attached elisp buffers: no subprocesses, ever.
Reports against the whole DOCUMENT (`save-restriction' + `widen', the
module invariant — the stock backend this replaces widens too, and the
wire ships absolute offsets).  Unbalanced parens report an :error
directly, and the compile pass still runs — an unescaped `?(' char
literal false-positives the pre-scan (write `?\\(') and must not cost
the real warnings; the useless end-of-file error a truly unbalanced
compile yields is dropped as the pre-scan's duplicate.  Untrusted
content (`trusted-content-p' — the same 30.1 gate the stock backend
applies, because macro expansion IS evaluation) skips the compile and
says so in one :note.

Deltas from the stock subprocess backend, stated so the decision is
visible: compile-time evaluation (`eval-when-compile', macro
expansion, top-level `require') runs in the LIVE session, and sibling
`require's are not resolved (no \"-L .\" equivalent) — both are why
`ebp-sync-elisp-inprocess' defaults to Android-only."
  (funcall
   report-fn
   (save-restriction
     (widen)
     (let ((parens (ebp-sync--elisp-paren-diags)))
       (if (not (trusted-content-p))
           (cons (flymake-make-diagnostic
                  (current-buffer) (point-min)
                  (min (1+ (point-min)) (point-max)) :note
                  (concat "byte-compile diagnostics disabled: untrusted "
                          "content (see `trusted-content')"))
                 parens)
         (let ((compile (ebp-sync--elisp-compile-diags)))
           (append parens
                   (if parens
                       (cl-remove-if
                        (lambda (d)
                          (string-match-p "End of file"
                                          (flymake-diagnostic-text d)))
                        compile)
                     compile))))))))

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
      (unless flymake-mode
        ;; Enable WITHOUT flymake's enable-time check: the arm runs on
        ;; the jsonrpc dispatch path (attach, accepted results), and a
        ;; backend pass — stock spawns a compiler, in-process compiles
        ;; right here — does not belong on it.  The settle timer's kick
        ;; in `ebp-sync--push-diagnostics' is the sole scheduler.
        (let ((flymake-start-on-flymake-mode nil))
          (flymake-mode 1)))
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
          ;; The explicit kick lives HERE, on the settle timer, never
          ;; per edit: flymake's own idle/post-command rescheduling is
          ;; unreliable while Emacs runs headless (POC 1 lesson), but a
          ;; plain `run-at-time' timer — this one — fires fine, and
          ;; settle cadence coalesces one backend pass per typing pause
          ;; instead of one synchronous compile per keystroke inside
          ;; the jsonrpc callback.  Synchronous backends (the
          ;; in-process elisp one) report before `flymake-diagnostics'
          ;; below reads; async ones are caught by the quiet-round
          ;; chase.  Gated on real backends so a backend-less buffer
          ;; (org, plain text) never pays for an empty pass.
          (when (remq t flymake-diagnostic-functions)
            (ignore-errors (flymake-start)))
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
nothing.  WIDENED: the offsets were always absolute, so nothing was
ever misplaced here — but `font-lock-ensure' and the walk both stopped
at the restriction, and the phone renders the whole document, so
everything outside the user's narrowing arrived unstyled."
  (save-restriction
    (widen)
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
      (nreverse runs))))

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

;; ---------------------------------------------------------- eldoc rider --

;; SPEC 19.5: the caret report is answered with the buffer's OWN eldoc
;; backends, pushed as `eldoc.show'.  The third rider and the only one
;; that is not driven by a text change — documentation is a question
;; about a position, so its trigger is `edit.caret' and there is no
;; settle timer: SPEC 19.3 puts throttling on the Companion, at the
;; source.  (Behavior reference: POC 1's jetpacs-sync.el, which ran the
;; same inline.)

(defcustom ebp-sync-eldoc t
  "When non-nil, answer the editor's caret reports with eldoc content.
The phone shows the result (e.g. an elisp function signature with the
current argument) in a line above the keyboard.  Every backend on
`eldoc-documentation-functions' runs; asynchronous ones — eglot's LSP
hover — re-deliver when their reply lands."
  :type 'boolean :group 'ebp)

(defun ebp-sync--format-docs (docs)
  "Join collected eldoc DOCS into one capped line, or nil when empty.
Each doc is (STRING . PLIST); rendered as \"THING: FIRST-LINE\".  Only
the first line of each survives — a multi-line docstring does not fit a
strip above a phone keyboard — and the 200 is display COLUMNS, so wide
glyphs count double.  A product bound, not a SPEC one: `eldoc.show'
caps only at `max_frame_bytes'."
  (when docs
    (truncate-string-to-width
     (mapconcat
      (lambda (d)
        (let ((line (car (split-string (substring-no-properties (car d))
                                       "\n")))
              (thing (plist-get (cdr d) :thing)))
          (if thing (format "%s: %s" thing line) line)))
      (reverse docs) "  •  ")
     200)))

(defun ebp-sync--push-eldoc (buffer text)
  "Push TEXT as BUFFER's eldoc line when it changed since the last push.
Safe to call any number of times per caret round: synchronous backends
deliver during the round, async ones whenever their reply lands, and
the phone simply renders the latest.  A nil TEXT is a real transition,
not a no-op — it pushes the empty string so the doc line CLEARS when
the caret leaves a symbol; the stamp suppresses the repeat."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      ;; The mirror entry is the first gate on purpose.  No entry means
      ;; no session, and `ebp-client-notify' fails CLOSED — it signals
      ;; `ebp-ungranted' for a method the session has not granted, and a
      ;; signal raised here would abort the rest of the caret fan-out.
      (let ((ed (and ebp-sync--client
                     (gethash (cons ebp-sync--document ebp-sync--editor-id)
                              (ebp-client-editors ebp-sync--client)))))
        (when ed
          (let ((stamp (list (plist-get ed :session)
                             (plist-get ed :seq) text)))
            (unless (equal stamp ebp-sync--eldoc-stamp)
              (setq ebp-sync--eldoc-stamp stamp)
              (ebp-client-notify
               ebp-sync--client 'eldoc.show
               (list :editor_id ebp-sync--editor-id
                     :session (plist-get ed :session)
                     :seq (plist-get ed :seq)
                     :text (or text ""))))))))))

(defun ebp-sync--run-eldoc (buffer)
  "Run BUFFER's eldoc backends at point and deliver the result.
`run-hook-wrapped' with a wrapper returning nil runs EVERY backend
rather than stopping at the first, and `condition-case' per backend
keeps one throwing backend from killing the round.  The collecting
closure captures only strings — never the buffer — so a late async
reply is safe long after point has moved on."
  (let (docs)
    (run-hook-wrapped
     'eldoc-documentation-functions
     (lambda (fn)
       (condition-case nil
           (let ((r (funcall fn (lambda (doc &rest plist)
                                  (when (stringp doc)
                                    (push (cons doc plist) docs)
                                    (ebp-sync--push-eldoc
                                     buffer (ebp-sync--format-docs docs)))))))
             (when (stringp r) (push (cons r nil) docs)))
         (error nil))
       nil))                            ; nil → run every backend
    (ebp-sync--push-eldoc buffer (ebp-sync--format-docs docs))))

(defun ebp-sync--on-caret (client document editor-id cursor sel-start sel-end)
  "Answer an accepted caret report with documentation at that position.
Two gates: the `ebp-sync-eldoc' toggle, and a COLLAPSED caret — a
selection drag is not a request for documentation.  Point is restored;
CURSOR is a 0-based scalar offset and Emacs point is 1-based."
  (let ((buf (and ebp-sync-eldoc
                  (not (and (numberp sel-start) (numberp sel-end)
                            (/= sel-start sel-end)))
                  (numberp cursor)
                  (ebp-sync--buffer client document editor-id))))
    (when buf
      (with-current-buffer buf
        ;; The one site that misplaced SILENTLY: `goto-char' clamps to
        ;; BOTH accessible bounds without signalling, so every caret the
        ;; phone reported below the restriction collapsed onto
        ;; `point-min' and eldoc answered confidently about the wrong
        ;; symbol.  The widen spans `ebp-sync--run-eldoc' too — the
        ;; backends read around point and their syntax context is
        ;; bounded by the restriction, and leaving the restriction with
        ;; point outside it would silently clamp point right back.
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (min (1+ (max 0 (truncate cursor))) (point-max)))
            (ebp-sync--run-eldoc buf)))))))

(provide 'ebp-sync)
;;; ebp-sync.el ends here
