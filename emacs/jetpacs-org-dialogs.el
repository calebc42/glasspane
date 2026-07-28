;;; jetpacs-org-dialogs.el --- Org dialogs: footnote, header sheet (JA-5) -*- lexical-binding: t; -*-

;;; Commentary:

;; The dialog half of the org rung: the footnote dialog and the header
;; action sheet, rebuilt from the poc (1578-1694, 1897-2029) as single
;; SPEC 18.1 dialogs on the shape JA-6 confirmed — a FRESH dialog id
;; per press (18.1 answers a reused outstanding id with 1201, and an
;; impatient double-tap is exactly that), `ebp-client-dialog-show'
;; called directly (the sections/files precedent; every spec here is
;; ERT-pinned against the dialog profile), item taps concluding as
;; `dialog.submit' values re-validated against a freshly built
;; candidate list at dispatch time (SPEC 23.2), and prompting flows
;; re-entering through `jetpacs-flow-begin' — an ebp callback's stack
;; has no dispatch to inherit a flow from — behind the can-bridge gate
;; (the JA-6 audit's P2 :284: a prompt with no bridge wedges a headless
;; Emacs while the device shows `accepted').
;;
;; The sheet's mutations ride the JA-4 engine: Cycle TODO through
;; `jetpacs-org-toggle-todo' (NEVER raw `org-todo' — its log note
;; arrives on `post-command-hook', which never fires in the socket
;; filter), Set TODO/Priority as native chained dialogs (`org-priority'
;; and org's fast tag selection read chars with NO prompt argument, so
;; the bridge advice never engages and a device tap would hang a
;; desktop-less Emacs — verified against emacs-30.1 org.el), tags as a
;; plain text field (the Orgro two-tier model), Refile as the ONE
;; bridged command (`org-refile' funnels through `completing-read').
;; Archive is not a submit value at all: a remote descriptor carrying
;; the ref as an opaque per-owner TOKEN (D-4) plus SPEC 14.1 `:confirm'
;; — the poc archived with no confirmation — whose replace-set sweep
;; makes a stale sheet's Archive answer `stale' honestly.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-archive)
(require 'jetpacs-org)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)
(require 'jetpacs-shell)
(require 'jetpacs-dialog)
(require 'jetpacs-navigate)
(require 'ebp)

(defconst jetpacs-org-dialogs-owner "jetpacs.org"
  "The owner scoping org ref tokens (R1: base reserves the prefix).")

;;;; Shared machinery

(defvar jetpacs-org-dialogs--seq 0
  "Monotonic suffix keeping every dialog id fresh (the sections lesson).")

(defun jetpacs-org-dialogs--id (kind buf pos)
  "A fresh SPEC 18.1 dialog id for KIND at POS in BUF."
  (format "org-%s-%s-%d" kind
          (abs (sxhash (list (and (bufferp buf) (buffer-name buf)) pos)))
          (cl-incf jetpacs-org-dialogs--seq)))

(defun jetpacs-org-dialogs--refresh (params)
  "Re-push the tapped surface from a zero-delay continuation."
  (jetpacs-buffer-defer-refresh (plist-get params :surface)))

(defun jetpacs-org-dialogs--notify (text params)
  "Queue TEXT as the tapped surface's next-push snackbar."
  (jetpacs-shell-notify text (plist-get params :surface)))

(defun jetpacs-org-dialogs--with-prompting (fn params)
  "Run FN only if a prompt raised now would reach the device.
The `jetpacs-emacs-ui--with-prompting' shape: refusing loudly beats
wedging silently, and a flow error surfaces as a symbol, never text
(SPEC 23.3)."
  (if (not (jetpacs-dialog-can-bridge-p))
      (jetpacs-org-dialogs--notify
       (if (bound-and-true-p jetpacs-dialog--pending)
           "Busy — finish the open dialog first"
         "Dialogs are not available in this session")
       params)
    (condition-case err
        (funcall fn)
      (error (message "jetpacs-org-dialogs: flow failed: %s"
                      (jetpacs--error-label err))
             (jetpacs-org-dialogs--notify "That did not work" params)))))

(defun jetpacs-org-dialogs--ref-label (ref)
  "REF's headline as a dialog title, scrubbed and bounded."
  (jetpacs-truncate-text
   (jetpacs-scalar-text (or (plist-get ref :headline) "Heading"))
   80))

(defun jetpacs-org-dialogs--ref-at (buf pos)
  "The heading ref at POS in BUF, or nil when no heading is there."
  (with-current-buffer buf
    (org-with-wide-buffer
     (goto-char (min (max (point-min) pos) (point-max)))
     (when (ignore-errors (org-back-to-heading t) t)
       (jetpacs-org-ref-at-point)))))

;;;; The footnote dialog (poc 1578-1694)

(defun jetpacs-org-dialogs--footnote-info (buf pos)
  "Footnote facts at POS in BUF, or nil when no reference is there.
Plist: :label (nil for anonymous), :inline, :definition (string or
nil), :def-line (definition's line number, labelled file-backed only)."
  (with-current-buffer buf
    (org-with-wide-buffer
     (goto-char (min (max (point-min) pos) (point-max)))
     (when-let* ((ctx (org-footnote-at-reference-p)))
       (let* ((label (car ctx))
              (inline (nth 3 ctx))
              (def (if inline
                       (and (nth 1 ctx) (nth 2 ctx)
                            (buffer-substring-no-properties
                             (nth 1 ctx) (nth 2 ctx)))
                     (and label
                          (nth 3 (org-footnote-get-definition label)))))
              (def-line (and label (not inline)
                             (when-let* ((d (org-footnote-get-definition
                                             label)))
                               (line-number-at-pos (nth 1 d))))))
         (list :label label :inline (and inline t)
               :definition (and def (string-trim def))
               :def-line def-line))))))

(defun jetpacs-org-dialogs--footnote-spec (info)
  "The footnote dialog spec for INFO (dialog-profile nodes only)."
  (let* ((label (plist-get info :label))
         (def (plist-get info :definition))
         (title (cond ((plist-get info :inline) "Inline footnote")
                      (label (format "Footnote [fn:%s]"
                                     (jetpacs-scalar-text label)))
                      (t "Footnote"))))
    (apply #'jetpacs-column
           (jetpacs-text title :style "title")
           (delq nil
                 (list
                  (jetpacs-text (if def
                                    (jetpacs-truncate-text
                                     (jetpacs-scalar-text def) 1000)
                                  "No definition found."))
                  (when (and def (jetpacs-builtin-advertised-p
                                  "clipboard.copy"))
                    (jetpacs-button "Copy"
                                    (jetpacs-clipboard-copy
                                     (jetpacs-truncate-text
                                      (jetpacs-scalar-text def) 4096))
                                    :variant "text"))
                  (when (plist-get info :def-line)
                    (jetpacs-button "Go to definition"
                                    (jetpacs-dialog-submit :value "edit")
                                    :variant "text"))
                  (jetpacs-button "Close" (jetpacs-dialog-dismiss)
                                  :variant "text"))))))

(defun jetpacs-org-dialogs--show-footnote (buf pos params)
  "Offer the footnote dialog for the reference at POS in BUF."
  (let ((client (jetpacs-client))
        (info (jetpacs-org-dialogs--footnote-info buf pos)))
    (cond
     ((null info)
      (jetpacs-org-dialogs--notify "No footnote there" params)
      (jetpacs-org-dialogs--refresh params))
     ((null client) nil)
     (t
      (ebp-client-dialog-show
       client
       (jetpacs-org-dialogs--id "fn" buf pos)
       (jetpacs-org-dialogs--footnote-spec info)
       :callback
       (lambda (status result _error)
         (when (and (equal status "submitted")
                    (equal (plist-get result :value) "edit")
                    (plist-get info :def-line))
           ;; No cursor-seek exists: navigate to the buffer and put the
           ;; definition's line number in the snackbar (the poc's own
           ;; affordance, minus its private files dependency).
           (run-at-time 0 nil
                        (lambda ()
                          (jetpacs-navigate-buffer buf)
                          (jetpacs-org-dialogs--notify
                           (format "Definition of [fn:%s] is at line %d"
                                   (jetpacs-scalar-text
                                    (or (plist-get info :label) ""))
                                   (plist-get info :def-line))
                           params))))))))))

;;;; The header action sheet (poc 1897-2029)

(defvar jetpacs-org-dialogs--sheet nil
  "The outstanding sheet, (:request-id ID :token TOKEN), or nil.
Single-slot: `max_dialogs' floors at one and a second sheet supersedes
the first's tokens anyway (the replace-set sweep).")

(defun jetpacs-org-dialogs--sheet-candidates (ref buf)
  "Fresh (VALUE . LABEL) candidates for REF's sheet.
Rebuilt at dispatch time too — the submitted value must name a
candidate the sheet WOULD offer now (SPEC 23.2).  Narrow/widen follow
the buffer's live state.  Schedule/Deadline join at JA-5e."
  (ignore ref)
  (append
   '(("todo" . "Cycle TODO")
     ("set-todo" . "Set TODO…")
     ("priority" . "Priority…")
     ("tags" . "Set tags…")
     ("refile" . "Refile…"))
   (if (with-current-buffer buf (buffer-narrowed-p))
       '(("widen" . "Widen"))
     '(("narrow" . "Narrow to subtree")))
   '(("duplicate" . "Duplicate"))))

(defun jetpacs-org-dialogs--show-sheet (buf pos params)
  "Offer the header action sheet for the heading at POS in BUF."
  (let ((client (jetpacs-client))
        (ref (jetpacs-org-dialogs--ref-at buf pos)))
    (cond
     ((null ref)
      (jetpacs-org-dialogs--notify "No heading there" params)
      (jetpacs-org-dialogs--refresh params))
     ((null client) nil)
     (t
      (let* ((token (car (jetpacs-org-ref-tokens
                          (list ref) :set "sheet"
                          :owner jetpacs-org-dialogs-owner)))
             (request-id
              (ebp-client-dialog-show
               client
               (jetpacs-org-dialogs--id "sheet" buf pos)
               (apply #'jetpacs-column
                      (jetpacs-text (jetpacs-org-dialogs--ref-label ref)
                                    :style "title")
                      (append
                       (mapcar (lambda (c)
                                 (jetpacs-button
                                  (cdr c)
                                  (jetpacs-dialog-submit :value (car c))
                                  :variant "text"))
                               (jetpacs-org-dialogs--sheet-candidates ref buf))
                       (list
                        ;; A REMOTE descriptor, not a submit value: the
                        ;; Companion presents the 14.1 confirmation
                        ;; before creating the event (the poc archived
                        ;; with no confirm), and the token — not a
                        ;; position — addresses the subtree.
                        (jetpacs-button
                         "Archive"
                         (jetpacs-action "jetpacs.org.archive"
                                         :args (list :token token)
                                         :confirm "Archive this subtree?")
                         :variant "text")
                        (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)))))
               :style "sheet"
               :callback
               (lambda (status result _error)
                 (setq jetpacs-org-dialogs--sheet nil)
                 (when (and (equal status "submitted")
                            (stringp (plist-get result :value)))
                   (jetpacs-org-dialogs--sheet-dispatch
                    ref buf (plist-get result :value) params))))))
        (if (null request-id)
            (jetpacs-org-dialogs--notify "Busy — try again" params)
          (setq jetpacs-org-dialogs--sheet
                (list :request-id request-id :token token))))))))

(defun jetpacs-org-dialogs--sheet-dispatch (ref buf value params)
  "Run the sheet item VALUE for REF; every arm ends in a refresh.
Bounded mutations run here (a dialog callback is bounded local work
under D2); the prompting arm (Refile) re-enters through
`jetpacs-flow-begin'.  VALUE is re-validated against a freshly built
candidate list first (23.2)."
  (if (not (assoc value (jetpacs-org-dialogs--sheet-candidates ref buf)))
      (jetpacs-org-dialogs--refresh params)
    (condition-case err
        (pcase value
          ("todo"
           (jetpacs-org-toggle-todo ref 'org nil)
           (jetpacs-org-dialogs--refresh params))
          ("set-todo"
           (run-at-time 0 nil (lambda ()
                                (jetpacs-org-dialogs--show-set-todo
                                 ref buf params))))
          ("priority"
           (run-at-time 0 nil (lambda ()
                                (jetpacs-org-dialogs--show-priority
                                 ref buf params))))
          ("tags"
           (run-at-time 0 nil (lambda ()
                                (jetpacs-org-dialogs--show-tags
                                 ref buf params))))
          ("refile"
           (jetpacs-flow-begin (plist-get params :surface)
                               (lambda ()
                                 (jetpacs-org-dialogs--refile ref params))))
          ("narrow"
           ;; The poc's lesson kept: never inside `org-with-wide-buffer'
           ;; — it would restore the restriction and undo the narrow.
           (let ((m (jetpacs-org-resolve-ref ref)))
             (unwind-protect
                 (with-current-buffer (marker-buffer m)
                   (widen)
                   (goto-char m)
                   (org-narrow-to-subtree))
               (set-marker m nil)))
           (jetpacs-org-dialogs--refresh params))
          ("widen"
           (with-current-buffer buf (widen))
           (jetpacs-org-dialogs--refresh params))
          ("duplicate"
           (jetpacs-org-with-mutation ref 'org
             (org-back-to-heading t)
             (let* ((beg (point))
                    (end (progn (org-end-of-subtree t t) (point)))
                    (text (buffer-substring-no-properties beg end)))
               (goto-char end)
               (unless (bolp) (insert "\n"))
               (let ((ins (point)))
                 (insert text)
                 (unless (bolp) (insert "\n"))
                 ;; The copy must not share org-id identity.
                 (save-restriction
                   (narrow-to-region ins (point))
                   (org-map-entries
                    (lambda () (org-entry-delete (point) "ID")))))))
           (jetpacs-org-dialogs--refresh params)))
      (jetpacs-org-unresolved
       (jetpacs-org-dialogs--notify "That heading is gone" params)
       (jetpacs-org-dialogs--refresh params))
      (error
       (message "jetpacs-org-dialogs: %s failed: %s"
                value (jetpacs--error-label err))
       (jetpacs-org-dialogs--notify "That did not work" params)
       (jetpacs-org-dialogs--refresh params)))))

;;;; Chained mini-dialogs

(defun jetpacs-org-dialogs--show-set-todo (ref buf params)
  "Offer REF's TODO keywords (document-local `#+TODO:' included, free
from org itself) as buttons.  Native, not bridged: org's fast selection
reads chars with no prompt argument and would hang under a flow."
  (when-let* ((client (jetpacs-client)))
    (let ((kws (with-current-buffer buf org-todo-keywords-1)))
      (ebp-client-dialog-show
       client
       (jetpacs-org-dialogs--id "todo" buf 0)
       (apply #'jetpacs-column
              (jetpacs-text "TODO state" :style "title")
              (append
               (mapcar (lambda (kw)
                         (jetpacs-button (jetpacs-scalar-text kw)
                                         (jetpacs-dialog-submit :value kw)
                                         :variant "text"))
                       kws)
               (list (jetpacs-button "Clear"
                                     (jetpacs-dialog-submit :value "__none__")
                                     :variant "text")
                     (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)))))
       :callback
       (lambda (status result _error)
         (when (equal status "submitted")
           (let ((v (plist-get result :value)))
             (condition-case err
                 (cond
                  ((equal v "__none__")
                   (jetpacs-org-toggle-todo ref 'org 'none))
                  ;; 23.2: only a keyword the buffer defines NOW.
                  ((member v (with-current-buffer buf org-todo-keywords-1))
                   (jetpacs-org-toggle-todo ref 'org v)))
               (error (message "jetpacs-org-dialogs: set-todo failed: %s"
                               (jetpacs--error-label err))
                      (jetpacs-org-dialogs--notify "That did not work"
                                                   params)))
             (jetpacs-org-dialogs--refresh params))))))))

(defun jetpacs-org-dialogs--show-priority (ref buf params)
  "Offer REF's priority range as buttons.  Native by necessity:
`org-priority' reads with a promptless `read-char-exclusive' the
bridge advice never sees (emacs-30.1 org.el:11172)."
  (when-let* ((client (jetpacs-client)))
    (let* ((hi (with-current-buffer buf org-priority-highest))
           (lo (with-current-buffer buf org-priority-lowest))
           (chars (and (integerp hi) (integerp lo) (<= hi lo)
                       (cl-loop for c from hi to lo collect c))))
      (when chars
        (ebp-client-dialog-show
         client
         (jetpacs-org-dialogs--id "prio" buf 0)
         (apply #'jetpacs-column
                (jetpacs-text "Priority" :style "title")
                (append
                 (mapcar (lambda (c)
                           (jetpacs-button (format "#%c" c)
                                           (jetpacs-dialog-submit
                                            :value (char-to-string c))
                                           :variant "text"))
                         chars)
                 (list (jetpacs-button "Clear"
                                       (jetpacs-dialog-submit
                                        :value "__remove__")
                                       :variant "text")
                       (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)))))
         :callback
         (lambda (status result _error)
           (when (equal status "submitted")
             (let ((v (plist-get result :value)))
               (condition-case err
                   (cond
                    ((equal v "__remove__")
                     (jetpacs-org-with-mutation ref 'org
                       (org-priority 'remove)))
                    ((and (stringp v) (= 1 (length v))
                          (<= hi (aref v 0) lo))
                     (jetpacs-org-with-mutation ref 'org
                       (org-priority (aref v 0)))))
                 (error (message "jetpacs-org-dialogs: priority failed: %s"
                                 (jetpacs--error-label err))
                        (jetpacs-org-dialogs--notify "That did not work"
                                                     params)))
               (jetpacs-org-dialogs--refresh params)))))))))

(defconst jetpacs-org-dialogs--tag-re "\\`[[:alnum:]_@#%]+\\'"
  "Org's own tag charset; anything else corrupts the :tag: string.")

(defun jetpacs-org-dialogs--show-tags (ref buf params)
  "Offer REF's tags as one editable text field (the Orgro two-tier
model: a structured gesture for the common case, plain text for the
rest — and org's fast tag selection cannot bridge)."
  (when-let* ((client (jetpacs-client)))
    (let* ((seed (condition-case nil
                     (let ((m (jetpacs-org-resolve-ref ref)))
                       (unwind-protect
                           (with-current-buffer (marker-buffer m)
                             (org-with-wide-buffer
                              (goto-char m)
                              (let ((tags (org-get-tags nil t)))
                                (if tags
                                    (concat ":" (string-join tags ":") ":")
                                  ""))))
                         (set-marker m nil)))
                   (error ""))))
      (ebp-client-dialog-show
       client
       (jetpacs-org-dialogs--id "tags" buf 0)
       (jetpacs-column
        (jetpacs-text "Tags" :style "title")
        (jetpacs-text-input "org-tags" :value seed
                            :label "Colon-separated: :work:next:"
                            :single-line t)
        (jetpacs-button "Save"
                        (jetpacs-dialog-submit
                         :value "save" :capture-fields '("org-tags"))
                        :variant "text")
        (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)))
       :callback
       (lambda (status result _error)
         (when (and (equal status "submitted")
                    (equal (plist-get result :value) "save"))
           (let* ((raw (or (plist-get (plist-get result :fields) :org-tags)
                           ""))
                  (tags (and (stringp raw) (split-string raw ":" t "[ \t]+")))
                  (good (seq-filter
                         (lambda (tag)
                           (string-match-p jetpacs-org-dialogs--tag-re tag))
                         tags)))
             (condition-case err
                 (if (and tags (null good))
                     (jetpacs-org-dialogs--notify "No valid tags in that"
                                                  params)
                   (jetpacs-org-with-mutation ref 'org
                     (org-set-tags good)))
               (error (message "jetpacs-org-dialogs: tags failed: %s"
                               (jetpacs--error-label err))
                      (jetpacs-org-dialogs--notify "That did not work"
                                                   params)))
             (jetpacs-org-dialogs--refresh params))))))))

;;;; Refile — the one bridged command

(defun jetpacs-org-dialogs--refile (ref params)
  "Run `org-refile' at REF under the device flow; its `completing-read'
bridges to the device picker.  Saving afterward is org's own answer —
`org-save-all-org-buffers' — because refile touches a target buffer
this module never sees."
  (jetpacs-org-dialogs--with-prompting
   (lambda ()
     (let ((m (jetpacs-org-resolve-ref ref)))
       (unwind-protect
           (with-current-buffer (marker-buffer m)
             (org-with-wide-buffer
              (goto-char m)
              (call-interactively #'org-refile)))
         (set-marker m nil)))
     (jetpacs-org-cache-invalidate)
     (org-save-all-org-buffers)
     (jetpacs-org-dialogs--notify "Refiled" params)
     (jetpacs-org-dialogs--refresh params))
   params))

;;;; The verbs

(defun jetpacs-org-dialogs--dialog-tap (verb show args params)
  "The shared gate for the two dialog-raising taps (sections order)."
  (let* ((name (plist-get args :buffer))
         (pos (plist-get args :pos))
         (buf (and (stringp name) (get-buffer name))))
    (cond
     ((not (and buf (integerp pos))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-p name pos verb)) 'rejected)
     ((not (jetpacs-granted-p "surfaces.dialog")) 'rejected)
     (t
      ;; The dialog is itself a request; a continuation keeps this
      ;; handler's reply prompt (D2).
      (run-at-time 0 nil (lambda () (funcall show buf pos params)))
      'accepted))))

(defun jetpacs-org-dialogs--footnote-action (args params)
  (jetpacs-org-dialogs--dialog-tap
   "jetpacs.org.footnote" #'jetpacs-org-dialogs--show-footnote args params))

(defun jetpacs-org-dialogs--heading-action (args params)
  (jetpacs-org-dialogs--dialog-tap
   "jetpacs.org.heading" #'jetpacs-org-dialogs--show-sheet args params))

(defun jetpacs-org-dialogs--archive (args params)
  "Archive the subtree the TOKEN names; SPEC 14.4 status.
Token miss (swept sheet, re-mint, stale device) → `stale'; a policy
refusal → `rejected'.  The effect is synchronous — `accepted' names a
completed archive — and the spent sheet is abandoned."
  (let ((token (plist-get args :token)))
    (cond
     ((not (stringp token)) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     (t
      (let ((ref (jetpacs-org-token-ref
                  token :owner jetpacs-org-dialogs-owner)))
        (if (null ref)
            'stale
          (condition-case err
              (progn
                (jetpacs-org-with-mutation ref 'org
                  (let ((org-archive-subtree-save-file-p t))
                    (org-archive-subtree)))
                (when-let* ((sheet jetpacs-org-dialogs--sheet)
                            (client (jetpacs-client)))
                  (when (equal token (plist-get sheet :token))
                    (ignore-errors
                      (ebp-client-abandon client
                                          (plist-get sheet :request-id)))
                    (setq jetpacs-org-dialogs--sheet nil)))
                (jetpacs-org-dialogs--notify "Archived" params)
                (jetpacs-org-dialogs--refresh params)
                'accepted)
            (jetpacs-org-unresolved 'stale)
            (jetpacs-org-refused 'rejected)
            (error (message "jetpacs-org-dialogs: archive failed: %s"
                            (jetpacs--error-label err))
                   'rejected))))))))

;; Ownerless, the render skin's precedent: an org buffer renders on
;; whatever surface drilled into it, and the sheet/archive must answer
;; there.  Tokens carry their own owner scope.
(jetpacs-defaction "jetpacs.org.footnote"
                   #'jetpacs-org-dialogs--footnote-action)
(jetpacs-defaction "jetpacs.org.heading"
                   #'jetpacs-org-dialogs--heading-action)
(jetpacs-defaction "jetpacs.org.archive" #'jetpacs-org-dialogs--archive)

;;;; Reset / unload

(defun jetpacs-org-dialogs-reset ()
  "Reset dialog-module state (the test seam)."
  (setq jetpacs-org-dialogs--seq 0
        jetpacs-org-dialogs--sheet nil))

(defun jetpacs-org-dialogs-unload-function ()
  "Unload hygiene: deregister the verbs."
  (jetpacs-undefaction "jetpacs.org.footnote")
  (jetpacs-undefaction "jetpacs.org.heading")
  (jetpacs-undefaction "jetpacs.org.archive")
  (jetpacs-org-dialogs-reset)
  nil)

(provide 'jetpacs-org-dialogs)
;;; jetpacs-org-dialogs.el ends here
