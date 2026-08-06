;;; jetpacs-sync.el --- Live bidirectional editor sync via track-changes -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Restores the powerful remote IDE layer from poc-v1 into llm-poc-2 without
;; violating v2's strict SPEC 19 editor synchronization boundaries.
;;
;; Driven by Emacs 30's `track-changes.el', this module implements robust,
;; echo-free bidirectional synchronization:
;;   * When Android edits arrive via `edit.delta' or `edit.open', changes are
;;     applied locally while silently draining `track-changes-fetch' so incoming
;;     edits never bounce back as redundant echoes.
;;   * When Emacs desktop commands or language servers mutate buffer contents
;;     independently, `track-changes-fetch' extracts exact `(start, del, text)'
;;     splices and pushes incremental `edit.apply' requests to Android.
;;
;; Riding on the synchronized session buffer:
;;   * Opt-in Real Buffer Eglot (`jetpacs-sync-eglot'): supported code files
;;     attach to real file buffers under `eglot-ensure', enabling true language
;;     server completion and automated didChange notifications.
;;   * Theme Fontification (`fontify.show'): debounced syntax highlighting
;;     emits sorted, non-overlapping style spans mapping faces to semantic
;;     `role' strings for caching and offline fallback in the Companion.
;;   * Live Linters (`diagnostics.show'): Flymake diagnostics ship structured
;;     squiggles (`error', `warning', `info', `hint').
;;   * ElDoc Hints (`eldoc.show'): caret position reports trigger synchronous
;;     documentation lookups pushed directly above the mobile keyboard.

;;; Code:

(require 'cl-lib)
(require 'track-changes)
(require 'flymake)
(require 'eldoc)
(require 'ebp)

(defgroup jetpacs-sync nil
  "Live bidirectional editor sync and remote IDE services for EBP."
  :group 'jetpacs)

(defcustom jetpacs-sync-diagnostics t
  "When non-nil, push collected Flymake squiggles."
  :type 'boolean :group 'jetpacs-sync)

(defcustom jetpacs-sync-diagnostics-delay 2.0
  "Seconds after an edit before pushing collected Flymake diagnostics."
  :type 'number :group 'jetpacs-sync)

(defcustom jetpacs-sync-eldoc t
  "When non-nil, answer caret motion reports with synchronous ElDoc strings."
  :type 'boolean :group 'jetpacs-sync)

(defcustom jetpacs-sync-fontify t
  "When non-nil, push debounced font-lock role spans to the mobile editor."
  :type 'boolean :group 'jetpacs-sync)

(defcustom jetpacs-sync-fontify-delay 0.1
  "Debounce delay in seconds before pushing fontification spans after typing."
  :type 'number :group 'jetpacs-sync)

(defcustom jetpacs-sync-fontify-max-chars 65536
  "Buffers larger than this skip full-buffer fontify pushes."
  :type 'integer :group 'jetpacs-sync)

(defcustom jetpacs-sync-eglot t
  "When non-nil, supported file types attach to real buffers with Eglot."
  :type 'boolean :group 'jetpacs-sync)

(defcustom jetpacs-sync-eglot-modes
  '(python-mode python-ts-mode sh-mode bash-ts-mode
    c-mode c-ts-mode c++-mode c++-ts-mode rust-mode rust-ts-mode)
  "Major modes that opt into real-buffer Eglot synchronization when enabled."
  :type '(repeat symbol) :group 'jetpacs-sync)

(defvar jetpacs-sync-shadow-setup-hook nil
  "Hook run in each freshly initialized session buffer after major-mode setup.")

;; ─── Session State Table ──────────────────────────────────────────────────────

(defvar jetpacs-sync--sessions (make-hash-table :test #'equal)
  "Map (CLIENT . (DOCUMENT . EDITOR-ID)) to active synchronization session state.")

(defun jetpacs-sync--session-key (client document editor-id)
  (cons client (cons document editor-id)))

;; ─── Mode Resolution & Eglot Linking ─────────────────────────────────────────

(defun jetpacs-sync--guess-mode (id)
  "Resolve major mode for editor ID or document name."
  (let ((name (file-name-nondirectory (or id ""))))
    (or (assoc-default name auto-mode-alist #'string-match)
        'fundamental-mode)))

(defun jetpacs-sync--eglot-target-p (mode)
  "Non-nil when MODE should synchronize in a real buffer with Eglot."
  (and jetpacs-sync-eglot
       (memq mode jetpacs-sync-eglot-modes)
       (fboundp 'eglot-ensure)))

(declare-function eglot-ensure "eglot" ())

;; ─── Bidirectional Delta Engine (track-changes) ──────────────────────────────

(defun jetpacs-sync--on-buffer-change (key tid)
  "Signal callback triggered by `track-changes' when buffer mutates autonomously."
  (let ((session (gethash key jetpacs-sync--sessions)))
    (when (and session (not (plist-get session :in-apply-p)))
      (let ((client (plist-get session :client))
            (doc (plist-get session :document))
            (eid (plist-get session :editor-id))
            (buf (plist-get session :buffer)))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (track-changes-fetch
             tid
             (lambda (begin end before)
               (if (eq before 'error)
                   (ebp-client-edit-resync client doc eid)
                 (let* ((start (1- begin))
                        (del (if (stringp before) (length before) before))
                        (text (buffer-substring-no-properties begin end)))
                   (ebp-client-edit-apply client doc eid start del text)))))))))))

(defun jetpacs-sync--setup-buffer (client document editor-id text)
  "Initialize session buffer, major mode, Eglot connection, and change tracking."
  (let* ((mode (jetpacs-sync--guess-mode editor-id))
         (use-real-eglot (jetpacs-sync--eglot-target-p mode))
         (buf-name (format " *jetpacs-sync:%s:%s*" document editor-id))
         (buf (get-buffer-create buf-name))
         (key (jetpacs-sync--session-key client document editor-id)))
    (with-current-buffer buf
      (let ((inhibit-read-only t)
            (inhibit-modification-hooks t))
        (erase-buffer)
        (insert text))
      (if use-real-eglot
          (progn
            (setq-local buffer-file-name (expand-file-name editor-id temporary-file-directory))
            (funcall mode)
            (ignore-errors (eglot-ensure)))
        (let ((delay-mode-hooks t))
          (funcall mode)))
      (run-hooks 'jetpacs-sync-shadow-setup-hook)
      (let* ((tracker (track-changes-register
                       (lambda (tid) (jetpacs-sync--on-buffer-change key tid))
                       :immediate nil))
             (session (list :client client :document document :editor-id editor-id
                            :buffer buf :tracker tracker :in-apply-p nil
                            :fontify-timer nil :diag-timer nil)))
        (puthash key session jetpacs-sync--sessions)
        (jetpacs-sync--schedule-annotations session)
        session))))

;; ─── Wire Event Handlers ─────────────────────────────────────────────────────

(defun jetpacs-sync-on-edit-open (client document editor-id seed-text _prior-text)
  "Handle inbound `edit.open' session initialization."
  (let* ((key (jetpacs-sync--session-key client document editor-id))
         (existing (gethash key jetpacs-sync--sessions)))
    (when existing
      (when-let* ((buf (plist-get existing :buffer))
                  (live-p (buffer-live-p buf)))
        (with-current-buffer buf
          (when-let* ((tid (plist-get existing :tracker)))
            (ignore-errors (track-changes-unregister tid))))
        (kill-buffer buf))
      (remhash key jetpacs-sync--sessions))
    (jetpacs-sync--setup-buffer client document editor-id seed-text)))

(defun jetpacs-sync-on-edit-change (client document editor-id text)
  "Handle inbound `edit.delta' or reconciling applied changes from wire."
  (let* ((key (jetpacs-sync--session-key client document editor-id))
         (session (gethash key jetpacs-sync--sessions)))
    (when session
      (when-let* ((buf (plist-get session :buffer)))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (unless (string= (buffer-string) text)
              (setf (plist-get session :in-apply-p) t)
              (let ((inhibit-read-only t))
                (erase-buffer)
                (insert text))
              ;; Draining track-changes to prevent echoing mobile edits
              (when-let* ((tid (plist-get session :tracker)))
                (track-changes-fetch tid (lambda (_ _ _) nil)))
              (setf (plist-get session :in-apply-p) nil)
              (jetpacs-sync--schedule-annotations session))))))))

(defun jetpacs-sync-on-edit-close (client document editor-id)
  "Handle inbound `edit.close' session cleanup."
  (let* ((key (jetpacs-sync--session-key client document editor-id))
         (session (gethash key jetpacs-sync--sessions)))
    (when session
      (when-let* ((buf (plist-get session :buffer)))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (when-let* ((tid (plist-get session :tracker)))
              (ignore-errors (track-changes-unregister tid))))
          (kill-buffer buf)))
      (when-let* ((timer (plist-get session :fontify-timer)))
        (cancel-timer timer))
      (when-let* ((timer (plist-get session :diag-timer)))
        (cancel-timer timer))
      (remhash key jetpacs-sync--sessions))))

;; ─── Annotation Builders (Fontification, Flymake, ElDoc) ─────────────────────

(defun jetpacs-sync--role-for-face (face)
  "Map Emacs face symbol or property to a clean semantic role string."
  (let ((sym (cond ((symbolp face) face)
                   ((listp face) (car face))
                   (t nil))))
    (pcase sym
      ('font-lock-keyword-face "keyword")
      ((or 'font-lock-string-face 'font-lock-doc-face) "string")
      ((or 'font-lock-comment-face 'font-lock-comment-delimiter-face) "comment")
      ((or 'font-lock-function-name-face 'font-lock-function-call-face) "function")
      ((or 'font-lock-variable-name-face 'font-lock-variable-use-face) "variable")
      ('font-lock-type-face "type")
      ((or 'font-lock-constant-face 'font-lock-builtin-face) "constant")
      ('font-lock-warning-face "warning")
      (_ (if sym
             (let ((name (symbol-name sym)))
               (if (string-match "\\`font-lock-\\(.*\\)-face\\'" name)
                   (match-string 1 name)
                 name))
           "default")))))

(defun jetpacs-sync--fontify-runs (buf)
  "Extract sorted, non-overlapping semantic role runs from BUF."
  (with-current-buffer buf
    (ignore-errors (font-lock-ensure))
    (let ((pos (point-min))
          runs)
      (while (< pos (point-max))
        (let ((next (next-single-property-change pos 'face nil (point-max)))
              (face (get-text-property pos 'face)))
          (when face
            (push (list :start (1- pos)
                        :end (1- next)
                        :role (jetpacs-sync--role-for-face face))
                  runs))
          (setq pos next)))
      (nreverse runs))))

(defun jetpacs-sync--push-fontify (session)
  "Deliver debounced fontification runs to the Companion."
  (when (and jetpacs-sync-fontify session)
    (let ((buf (plist-get session :buffer))
          (client (plist-get session :client))
          (doc (plist-get session :document))
          (eid (plist-get session :editor-id)))
      (when (and (buffer-live-p buf)
                 (<= (buffer-size buf) jetpacs-sync-fontify-max-chars))
        (let ((runs (jetpacs-sync--fontify-runs buf)))
          (ebp-client-fontify-show client doc eid runs))))))

(defun jetpacs-sync--severity-string (sev)
  "Convert Flymake diagnostic severity to EBP schema string."
  (pcase sev
    ((or 'error ':error) "error")
    ((or 'warning ':warning) "warning")
    ((or 'note ':note) "info")
    (_ "hint")))

(defun jetpacs-sync--push-diagnostics (session)
  "Collect active Flymake diagnostics and emit squiggles."
  (when (and jetpacs-sync-diagnostics session)
    (let ((buf (plist-get session :buffer))
          (client (plist-get session :client))
          (doc (plist-get session :document))
          (eid (plist-get session :editor-id)))
      (when (and (buffer-live-p buf) (fboundp 'flymake-diagnostics))
        (with-current-buffer buf
          (let* ((diags (ignore-errors (flymake-diagnostics)))
                 (formatted
                  (mapcar (lambda (d)
                            (list :start (1- (flymake-diagnostic-beg d))
                                  :end (1- (flymake-diagnostic-end d))
                                  :severity (jetpacs-sync--severity-string
                                             (flymake-diagnostic-type d))
                                  :message (or (flymake-diagnostic-text d) "error")))
                          diags)))
            (ebp-client-diagnostics-show client doc eid formatted)))))))

(defun jetpacs-sync--schedule-annotations (session)
  "Schedule debounced fontify and diagnostics updates after an edit."
  (when-let* ((t1 (plist-get session :fontify-timer)))
    (cancel-timer t1))
  (when-let* ((t2 (plist-get session :diag-timer)))
    (cancel-timer t2))
  (setf (plist-get session :fontify-timer)
        (run-at-time jetpacs-sync-fontify-delay nil
                     #'jetpacs-sync--push-fontify session))
  (setf (plist-get session :diag-timer)
        (run-at-time jetpacs-sync-diagnostics-delay nil
                     #'jetpacs-sync--push-diagnostics session)))

(defun jetpacs-sync-on-caret (client document editor-id cursor)
  "Handle peer caret report and answer with synchronous ElDoc string."
  (when jetpacs-sync-eldoc
    (let* ((key (jetpacs-sync--session-key client document editor-id))
           (session (gethash key jetpacs-sync--sessions)))
      (when session
        (when-let* ((buf (plist-get session :buffer)))
          (when (buffer-live-p buf)
            (with-current-buffer buf
              (goto-char (min (1+ cursor) (point-max)))
              (let ((doc-str (ignore-errors
                               (if (fboundp 'eldoc--documentation-progn)
                                   (eldoc--documentation-progn)
                                 (and (boundp 'eldoc-documentation-function)
                                      (funcall eldoc-documentation-function))))))
                (when (stringp doc-str)
                  (ebp-client-eldoc-show client document editor-id doc-str))))))))))

;; ─── EBP Client Hook Installation ────────────────────────────────────────────

(defun jetpacs-sync-install (client)
  "Register `jetpacs-sync' hooks and handlers onto CLIENT."
  (add-hook (make-local-variable 'ebp-client-edit-open-functions) #'jetpacs-sync-on-edit-open nil t)
  (add-hook (make-local-variable 'ebp-client-edit-change-functions) #'jetpacs-sync-on-edit-change nil t)
  (ebp-client-register-handler client "edit.caret"
                               (lambda (c p)
                                 (jetpacs-sync-on-caret c (plist-get p :document)
                                                        (plist-get p :editor_id)
                                                        (or (plist-get p :cursor) 0))))
  (ebp-client-register-handler client "edit.close"
                               (lambda (c p)
                                 (jetpacs-sync-on-edit-close c (plist-get p :document)
                                                             (plist-get p :editor_id)))))

(provide 'jetpacs-sync)
;;; jetpacs-sync.el ends here
