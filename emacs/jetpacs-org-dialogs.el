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
;; `ebp-org-toggle-todo' (NEVER raw `org-todo' — its log note
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
(require 'ebp-org)
(require 'jetpacs-org)                  ; NOT the engine: the shim, for its load
                                        ; effect — it registers the engine's token
                                        ; sweep on `jetpacs-teardown-functions'
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
                      (jetpacs-error-label err))
             (jetpacs-org-dialogs--notify "That did not work" params)))))

(defun jetpacs-org-dialogs--ref-label (ref)
  "REF's headline as a dialog title, scrubbed and bounded."
  (jetpacs-truncate-text
   (jetpacs-scalar-text (or (plist-get ref :headline) "Heading"))
   80))

(defun jetpacs-org-dialogs--ref-at (buf pos)
  "The heading ref when POS still sits ON a heading line, else nil.
Deliberately NOT `org-back-to-heading': the exposure was minted for a
run on a heading LINE, and a rotted pos that drifted into some other
subtree's body must answer \"gone\", not silently resolve to whatever
heading now encloses it (the checkbox and timestamp arms re-verify the
same way — AUDIT-ja5)."
  (with-current-buffer buf
    (org-with-wide-buffer
     (goto-char (min (max (point-min) pos) (point-max)))
     (when (org-at-heading-p)
       (ebp-org-ref-at-point)))))

;;;; The footnote dialog (poc 1578-1694)

(defun jetpacs-org-dialogs--footnote-info (buf pos)
  "Footnote facts at POS in BUF, or nil when no reference is there.
Plist: :label (nil for anonymous), :inline, :definition (string or
nil), :def-line (definition's line number, labelled file-backed only)."
  (with-current-buffer buf
    (org-with-wide-buffer
     (goto-char (min (max (point-min) pos) (point-max)))
     (when-let* ((ctx (org-footnote-at-reference-p)))
       ;; org-footnote.el (emacs-30.1): the return is (LABEL BEGIN END
       ;; DEFINITION), where nth 3 IS the inline definition STRING —
       ;; nth 1/2 bound the whole [fn:...] reference.  Reading nth 3 as
       ;; a boolean and substringing 1..2 showed the bracket wrapper as
       ;; the "definition" (AUDIT-ja5).
       (let* ((label (car ctx))
              (inline-def (nth 3 ctx))
              (def (or inline-def
                       (and label
                            (nth 3 (org-footnote-get-definition label)))))
              (def-line (and label (not inline-def)
                             (when-let* ((d (org-footnote-get-definition
                                             label)))
                               (line-number-at-pos (nth 1 d))))))
         (list :label label :inline (and inline-def t)
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
                  ;; The DIALOG profile's advertisement, not the app's:
                  ;; SPEC 18.1 validates every builtin in a dialog spec
                  ;; against the dialog profile, and the reference
                  ;; Companion's dialog profile carries only the two
                  ;; dialog builtins — an app-gated Copy button 1201'd
                  ;; the whole footnote dialog (AUDIT-ja5 P1).
                  (when (and def (jetpacs-builtin-advertised-p
                                  "clipboard.copy" :dialog))
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
                          ;; The TAPPED surface — a bare navigate from a
                          ;; timer resolves to the shell default and the
                          ;; drill lands where the user is not looking
                          ;; (AUDIT-ja5).
                          (jetpacs-navigate-buffer
                           buf (plist-get params :surface))
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
the buffer's live state."
  (ignore ref)
  (append
   '(("todo" . "Cycle TODO")
     ("set-todo" . "Set TODO…")
     ("schedule" . "Schedule…")
     ("deadline" . "Deadline…")
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
      (let* ((token (car (ebp-org-ref-tokens
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
          ;; :params rides along — the Archive event arrives in DIALOG
          ;; context (dialog_id, no :surface per 14.4's exclusive
          ;; contexts), so its feedback/refresh need the surface the
          ;; sheet was OPENED from (AUDIT-ja5).
          (setq jetpacs-org-dialogs--sheet
                (list :request-id request-id :token token
                      :params params))))))))

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
           (ebp-org-toggle-todo ref 'org nil)
           (jetpacs-org-dialogs--maybe-log-note ref params)
           (jetpacs-org-dialogs--refresh params))
          ((or "schedule" "deadline")
           ;; An explicit map, never string surgery: (upcase "schedule")
           ;; is "SCHEDULE", which no engine entry point accepts — the
           ;; arm shipped unable to write (AUDIT-ja5 P1).
           (let ((which (if (equal value "schedule") "SCHEDULED"
                          "DEADLINE")))
             (run-at-time 0 nil
                          (lambda ()
                            (jetpacs-org-dialogs--ts-open
                             (list :kind 'planning :ref ref :which which)
                             (condition-case nil
                                 (let ((m (ebp-org-resolve-ref ref)))
                                   (unwind-protect
                                       (with-current-buffer (marker-buffer m)
                                         (org-with-wide-buffer
                                          (org-entry-get m which)))
                                     (set-marker m nil)))
                               (error nil))
                             params)))))
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
           (let ((m (ebp-org-resolve-ref ref)))
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
           (ebp-org-with-mutation ref 'org
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
      (ebp-org-unresolved
       (jetpacs-org-dialogs--notify "That heading is gone" params)
       (jetpacs-org-dialogs--refresh params))
      (error
       (message "jetpacs-org-dialogs: %s failed: %s"
                value (jetpacs-error-label err))
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
                 (progn
                   (cond
                    ((equal v "__none__")
                     (ebp-org-toggle-todo ref 'org 'none))
                    ;; 23.2: only a keyword the buffer defines NOW.
                    ((member v (with-current-buffer buf org-todo-keywords-1))
                     (ebp-org-toggle-todo ref 'org v)))
                   (jetpacs-org-dialogs--maybe-log-note ref params))
               (error (message "jetpacs-org-dialogs: set-todo failed: %s"
                               (jetpacs-error-label err))
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
                     (ebp-org-with-mutation ref 'org
                       (org-priority 'remove)))
                    ((and (stringp v) (= 1 (length v))
                          (<= hi (aref v 0) lo))
                     (ebp-org-with-mutation ref 'org
                       (org-priority (aref v 0)))))
                 (error (message "jetpacs-org-dialogs: priority failed: %s"
                                 (jetpacs-error-label err))
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
                     (let ((m (ebp-org-resolve-ref ref)))
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
                   (ebp-org-with-mutation ref 'org
                     (org-set-tags good)))
               (error (message "jetpacs-org-dialogs: tags failed: %s"
                               (jetpacs-error-label err))
                      (jetpacs-org-dialogs--notify "That did not work"
                                                   params)))
             (jetpacs-org-dialogs--refresh params))))))))

;;;; The timestamp editor (poc 2031-2266 rebuilt: one-shot dialogs, sessions)
;;
;; The poc kept a live satellite view with module-global state — one
;; editor per Emacs, every keystroke a round trip.  Rebuilt as ONE
;; `dialog.show' whose repeater fields ride `capture_fields' and whose
;; date/time picks CANNOT (SPEC 17.4: `date_button'/`time_button' carry
;; no id — they are not stateful nodes, and 14.1 rejects a non-stateful
;; capture name), so a pick arrives as the remote `jetpacs.org.ts-pick'
;; with the value injected (14.3), and the dialog is abandoned and
;; RE-PRESENTED under a fresh id seeded from the session — the only
;; conformant way to reflect a pick.  Sessions are the 23.1 record for
;; that verb: `:sid' must name a live session AND the event's
;; `:dialog_id' must be the session's current dialog.
;;
;; Delay cookies (-1d) are deliberately absent: the engine has no
;; delay writer (only `ebp-org-set-repeater'), and they stay
;; plain-text-editable — the Orgro two-tier line.  Habit min/max
;; repeaters (+1w/2w) seed their leading part and round-trip the rest
;; untouched only when the repeater fields are unedited.

(defcustom jetpacs-org-ts-session-ttl 900
  "Seconds an unconcluded timestamp session survives before sweeping."
  :type 'integer :group 'jetpacs-org)

(defvar jetpacs-org-dialogs--ts-sessions (make-hash-table :test #'equal)
  "SID -> session plist (:target :date :time :rep-type :rep-n :rep-unit
:dialog-id :request-id :params :created).")

(defvar jetpacs-org-dialogs--ts-timer nil
  "The session sweep timer, armed while sessions exist.")

(defun jetpacs-org-dialogs--ts-sweep ()
  "Drop sessions older than `jetpacs-org-ts-session-ttl'; re-arm if any."
  (setq jetpacs-org-dialogs--ts-timer nil)
  (let ((cutoff (- (float-time) jetpacs-org-ts-session-ttl))
        dead)
    (maphash (lambda (sid s)
               (when (< (plist-get s :created) cutoff) (push sid dead)))
             jetpacs-org-dialogs--ts-sessions)
    (dolist (sid dead) (remhash sid jetpacs-org-dialogs--ts-sessions)))
  (when (> (hash-table-count jetpacs-org-dialogs--ts-sessions) 0)
    (setq jetpacs-org-dialogs--ts-timer
          (run-at-time jetpacs-org-ts-session-ttl nil
                       #'jetpacs-org-dialogs--ts-sweep))))

(defun jetpacs-org-dialogs--ts-seed (stamp)
  "Session fields seeded from org timestamp string STAMP (or nil).
Every seeded value must be LEGAL for the dialog nodes it lands in —
`jetpacs-time-button' rejects a 1-digit hour and the unit enum offers
only d/w/m/y, and a signaling spec build inside the show timer is a
silently dead tap (AUDIT-ja5).  So: times are zero-padded, an
UNSUPPORTED repeater (hourly unit) seeds `none' and is carried whole
in :rep-raw, a habit's /max tail in :rep-tail, a delay cookie in
:delay — the body rewrite re-appends all three, so opening the editor
never destroys cookie data it cannot represent."
  (let* ((rep (and stamp (ebp-org-ts-repeater stamp)))
         (parts (and rep
                     (string-match
                      "\\`\\(\\.\\+\\|\\+\\+\\|\\+\\)\\([0-9]+\\)\\([hdwmy]\\)\\'"
                      rep)
                     (list (match-string 1 rep)
                           (match-string 2 rep)
                           (match-string 3 rep))))
         (supported (member (nth 2 parts) '("d" "w" "m" "y")))
         (time (and stamp (ebp-org-ts-time stamp)))
         (rep-tail (and stamp supported
                        (string-match "[.+]?\\+[0-9]+[hdwmy]\\(/[0-9]+[hdwmy]\\)"
                                      stamp)
                        (match-string 1 stamp)))
         (rep-raw (and rep (not supported)
                       (progn (string-match
                               "\\([.+]?\\+[0-9]+[hdwmy]\\(?:/[0-9]+[hdwmy]\\)?\\)"
                               stamp)
                              (match-string 1 stamp))))
         (delay (and stamp
                     (string-match " \\(--?[0-9]+[hdwmy]\\)" stamp)
                     (match-string 1 stamp))))
    (list :date (or (and stamp (ebp-org-ts-date stamp))
                    (format-time-string "%Y-%m-%d"))
          :time (and time (if (= (length time) 4) (concat "0" time) time))
          :rep-type (if supported (nth 0 parts) "none")
          :rep-n (if supported (nth 1 parts) "1")
          :rep-unit (if supported (nth 2 parts) "w")
          :rep-tail rep-tail
          :rep-raw rep-raw
          :delay delay)))

(defconst jetpacs-org-dialogs--ts-rep-types
  '(("none" . "No repeat") ("+" . "+ every")
    ("++" . "++ next from today") (".+" . ".+ next from done"))
  "Repeater types with the poc's labels.")

(defun jetpacs-org-dialogs--ts-cookies (session)
  "SESSION's full cookie string (\" +1w/2w -1d\" style), or \"\".
An edited repeater wins over :rep-raw; the /max tail and delay carry
through either way, so the editor never destroys what it cannot show."
  (let* ((rep (jetpacs-org-dialogs--ts-rep session))
         (rep-part (cond (rep (concat rep (or (plist-get session :rep-tail)
                                              "")))
                         ((plist-get session :rep-raw))))
         (delay (plist-get session :delay)))
    (concat (if rep-part (concat " " rep-part) "")
            (if delay (concat " " delay) ""))))

(defun jetpacs-org-dialogs--ts-preview (session)
  "The stamp SESSION would write, for the preview line."
  (let* ((target (plist-get session :target))
         (bracket (if (eq (plist-get target :kind) 'body)
                      (plist-get target :bracket)
                    ?<)))
    (format "%c%s%s%s%c"
            (if (eq bracket ?\[) ?\[ ?<)
            (plist-get session :date)
            (if (plist-get session :time)
                (concat " " (plist-get session :time)) "")
            (jetpacs-org-dialogs--ts-cookies session)
            (if (eq bracket ?\[) ?\] ?>))))

(defun jetpacs-org-dialogs--ts-rep (session)
  "SESSION's repeater cookie string, or nil for none.
Every member is validated — type against the closed set, the count as
1-4 digits, the UNIT against d/w/m/y.  The unit arrives as a captured
device field and was concatenated into the org file unvalidated; a
crafted \"unit\" smuggled arbitrary text, headings included, into the
buffer (AUDIT-ja5 P1, SPEC 23.1)."
  (let ((type (plist-get session :rep-type))
        (n (plist-get session :rep-n))
        (unit (plist-get session :rep-unit)))
    (when (and (member type '("+" "++" ".+"))
               (stringp n) (string-match-p "\\`[0-9]\\{1,4\\}\\'" n)
               (> (string-to-number n) 0)
               (member unit '("d" "w" "m" "y")))
      (concat type n unit))))

(defconst jetpacs-org-dialogs--ts-field-shapes
  '((:ts-rep-type :rep-type "\\`\\(?:none\\|\\+\\|\\+\\+\\|\\.\\+\\)\\'")
    (:ts-rep-n :rep-n "\\`[0-9]\\{1,4\\}\\'")
    (:ts-rep-unit :rep-unit "\\`[dwmy]\\'"))
  "Captured field -> session key -> the shape a device value must match.")

(defun jetpacs-org-dialogs--ts-merge-fields (session fields)
  "SESSION with the captured FIELDS merged in — shape-checked, 23.1.
A member that fails its shape is DROPPED (the seed value stands); it
is never written anywhere."
  (let ((out (copy-sequence session)))
    (pcase-dolist (`(,field ,key ,shape) jetpacs-org-dialogs--ts-field-shapes)
      (let ((v (plist-get fields field)))
        (when (and (stringp v) (string-match-p shape v))
          (setq out (plist-put out key v)))))
    out))

(defun jetpacs-org-dialogs--ts-spec (sid session)
  "The timestamp dialog spec for SESSION under SID."
  (let ((target (plist-get session :target)))
    (jetpacs-column
     (jetpacs-text (pcase (plist-get target :kind)
                     ('planning (capitalize
                                 (downcase (plist-get target :which))))
                     (_ "Timestamp"))
                   :style "title")
     ;; The picks CAPTURE the repeater trio (SPEC 14.1: a remote action
     ;; whose outcome depends on stateful values must name them) — the
     ;; re-present would otherwise reseed the fields and silently wipe
     ;; the user's uncommitted repeater edits (AUDIT-ja5).
     (jetpacs-row
      (jetpacs-date-button (or (plist-get session :date) "Pick date")
                           (jetpacs-action "jetpacs.org.ts-pick"
                                           :args (list :sid sid
                                                       :field "date")
                                           :capture-fields
                                           '("ts-rep-type" "ts-rep-n"
                                             "ts-rep-unit"))
                           :value (plist-get session :date))
      (jetpacs-time-button (or (plist-get session :time) "Add time")
                           (jetpacs-action "jetpacs.org.ts-pick"
                                           :args (list :sid sid
                                                       :field "time")
                                           :capture-fields
                                           '("ts-rep-type" "ts-rep-n"
                                             "ts-rep-unit"))
                           :value (plist-get session :time)))
     (jetpacs-enum-list "ts-rep-type"
                        (mapcar (lambda (c)
                                  (jetpacs-enum-option (cdr c) (car c)))
                                jetpacs-org-dialogs--ts-rep-types)
                        :value (plist-get session :rep-type))
     (jetpacs-row
      (jetpacs-text-input "ts-rep-n" :value (plist-get session :rep-n)
                          :label "Every" :keyboard "number"
                          :single-line t)
      (jetpacs-enum-list "ts-rep-unit"
                         (mapcar (lambda (u)
                                   (jetpacs-enum-option (cdr u) (car u)))
                                 '(("d" . "days") ("w" . "weeks")
                                   ("m" . "months") ("y" . "years")))
                         :value (plist-get session :rep-unit)))
     (jetpacs-text (concat "Preview: "
                           (jetpacs-org-dialogs--ts-preview session))
                   :style "caption")
     (jetpacs-button "Save"
                     (jetpacs-dialog-submit
                      :value "save"
                      :capture-fields '("ts-rep-type" "ts-rep-n"
                                        "ts-rep-unit"))
                     :variant "text")
     (jetpacs-button "Clear"
                     (jetpacs-dialog-submit :value "clear")
                     :variant "text")
     (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)))))

(defun jetpacs-org-dialogs--ts-present (sid)
  "Show (or RE-show under a fresh id) the dialog for session SID."
  (when-let* ((client (jetpacs-client))
              (session (gethash sid jetpacs-org-dialogs--ts-sessions)))
    (let* ((dialog-id (jetpacs-org-dialogs--id "ts" nil sid))
           (request-id
            (ebp-client-dialog-show
             client dialog-id
             (jetpacs-org-dialogs--ts-spec sid session)
             :callback
             (lambda (status result _error)
               (let ((live (gethash sid jetpacs-org-dialogs--ts-sessions)))
                 ;; A superseded dialog (abandoned by a pick's
                 ;; re-present) concludes too — only the session's
                 ;; CURRENT dialog may conclude the session.
                 (when (and live
                            (equal (plist-get live :dialog-id) dialog-id))
                   (remhash sid jetpacs-org-dialogs--ts-sessions)
                   (when (equal status "submitted")
                     (jetpacs-org-dialogs--ts-conclude
                      live
                      (plist-get result :value)
                      (plist-get result :fields)))))))))
      (when request-id
        (puthash sid
                 (plist-put (plist-put (copy-sequence session)
                                       :dialog-id dialog-id)
                            :request-id request-id)
                 jetpacs-org-dialogs--ts-sessions)))))

(defun jetpacs-org-dialogs--ts-open (target stamp params)
  "Open a timestamp session for TARGET seeded from STAMP."
  (let* ((sid (format "ts-%d" (cl-incf jetpacs-org-dialogs--seq)))
         (session (append (list :target target :params params
                                :created (float-time))
                          (jetpacs-org-dialogs--ts-seed stamp))))
    (puthash sid session jetpacs-org-dialogs--ts-sessions)
    (unless (timerp jetpacs-org-dialogs--ts-timer)
      (setq jetpacs-org-dialogs--ts-timer
            (run-at-time jetpacs-org-ts-session-ttl nil
                         #'jetpacs-org-dialogs--ts-sweep)))
    (jetpacs-org-dialogs--ts-present sid)))

(defun jetpacs-org-dialogs--ts-pick (args params)
  "Store a date/time pick and re-present the session's dialog fresh."
  (let* ((sid (plist-get args :sid))
         (field (plist-get args :field))
         (value (plist-get args :value))
         (session (and (stringp sid)
                       (gethash sid jetpacs-org-dialogs--ts-sessions))))
    (cond
     ((not (and (stringp sid) (member field '("date" "time"))))
      'rejected)
     ((null session) 'stale)
     ;; The pick must come from the session's CURRENT dialog.
     ((not (equal (plist-get params :dialog_id)
                  (plist-get session :dialog-id)))
      'stale)
     ;; 23.1: the injected value is device data — shape-check it.
     ((not (and (stringp value)
                (string-match-p (if (equal field "date")
                                    "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'"
                                  "\\`[0-9]\\{2\\}:[0-9]\\{2\\}\\'")
                                value)))
      'rejected)
     (t
      ;; Merge the captured repeater fields FIRST (shape-checked), then
      ;; the pick — the re-present must reflect both.
      (puthash sid
               (plist-put (jetpacs-org-dialogs--ts-merge-fields
                           session (plist-get params :fields))
                          (if (equal field "date") :date :time) value)
               jetpacs-org-dialogs--ts-sessions)
      (let ((old-request (plist-get session :request-id)))
        (run-at-time 0 nil
                     (lambda ()
                       (when-let* ((client (jetpacs-client)))
                         (ignore-errors
                           (ebp-client-abandon client old-request)))
                       (jetpacs-org-dialogs--ts-present sid))))
      'accepted))))

(defun jetpacs-org-dialogs--ts-conclude (session value fields)
  "Apply a submitted timestamp dialog: VALUE is \"save\" or \"clear\".
FIELDS carries the captured repeater members keyed by node id."
  (let* ((target (plist-get session :target))
         (params (plist-get session :params))
         ;; Shape-checked merge — never a raw append of device fields
         ;; (a crafted "unit" reached the org file verbatim, AUDIT-ja5).
         (session (jetpacs-org-dialogs--ts-merge-fields session fields)))
    (condition-case err
        (pcase (plist-get target :kind)
          ('planning
           (let ((ref (plist-get target :ref))
                 (which (plist-get target :which)))
             (pcase value
               ("save"
                (let ((rep (jetpacs-org-dialogs--ts-rep session))
                      (datetime (concat (plist-get session :date)
                                        (if (plist-get session :time)
                                            (concat " "
                                                    (plist-get session :time))
                                          ""))))
                  (ebp-org-set-planning ref 'org which datetime)
                  ;; The two-step cookie write pinned at JA-4:
                  ;; `org-add-planning-info' drops repeaters.
                  (ebp-org-with-mutation ref 'org
                    (ebp-org-set-repeater which rep))))
               ("clear"
                (ebp-org-set-planning ref 'org which nil)))))
          ('body
           (jetpacs-org-dialogs--ts-body-write target session value)))
      (ebp-org-unresolved
       (jetpacs-org-dialogs--notify "That heading is gone" params))
      (error
       (message "jetpacs-org-dialogs: timestamp %s failed: %s"
                value (jetpacs-error-label err))
       (jetpacs-org-dialogs--notify "That did not work" params)))
    (jetpacs-org-dialogs--refresh params)))

(defun jetpacs-org-dialogs--ts-body-write (target session value)
  "Rewrite (or clear) the body stamp TARGET addresses.
Re-verifies a stamp still BEGINS at the recorded position — the buffer
may have moved under the dialog; a miss is a silent no-op plus a
snackbar, the stale-tap ethic."
  (let* ((name (plist-get target :buffer))
         (pos (plist-get target :pos))
         (buf (and (stringp name) (get-buffer name))))
    (if (null buf)
        (jetpacs-org-dialogs--notify "That buffer is gone"
                                     (plist-get session :params))
      (with-current-buffer buf
        (org-with-wide-buffer
         (goto-char (min (max (point-min) pos) (point-max)))
         (if (not (and (memq (char-after pos) '(?< ?\[))
                       (org-in-regexp org-ts-regexp-both)
                       (= (match-beginning 0) pos)))
             (jetpacs-org-dialogs--notify "That timestamp moved"
                                          (plist-get session :params))
           (let ((beg (match-beginning 0))
                 (end (match-end 0)))
             (pcase value
               ("save"
                (let* ((day (let ((system-time-locale "C"))
                              (format-time-string
                               "%a" (org-time-string-to-time
                                     (plist-get session :date)))))
                       (stamp (format "%c%s %s%s%s%c"
                                      (plist-get target :bracket)
                                      (plist-get session :date)
                                      day
                                      (if (plist-get session :time)
                                          (concat " "
                                                  (plist-get session :time))
                                        "")
                                      ;; Repeater + preserved /max tail
                                      ;; + delay — the editor never
                                      ;; destroys cookies it cannot
                                      ;; represent (AUDIT-ja5).
                                      (jetpacs-org-dialogs--ts-cookies
                                       session)
                                      (if (eq (plist-get target :bracket)
                                              ?\[)
                                          ?\] ?>))))
                  (delete-region beg end)
                  (goto-char beg)
                  (insert stamp)))
               ("clear"
                (delete-region beg end)
                (when (and (eq (char-before beg) ?\s)
                           (memq (char-after beg) '(?\s ?\n nil)))
                  (delete-char -1))))
             (ebp-org-cache-invalidate)
             (when buffer-file-name (ebp-org-defer-save)))))))))

;;;; The log-note dialog (the base docstring's promised follow-up)

(defun jetpacs-org-dialogs--maybe-log-note (ref params)
  "When the last toggle cancelled a free-text note, ask for it.
Reads `ebp-org-toggle-todo-cancelled-note' (the JA-5e engine seam)."
  (when ebp-org-toggle-todo-cancelled-note
    (setq ebp-org-toggle-todo-cancelled-note nil)
    (run-at-time 0 nil
                 (lambda ()
                   (jetpacs-org-dialogs--show-log-note ref params)))))

(defun jetpacs-org-dialogs--show-log-note (ref params)
  "Offer a one-field note dialog for REF's just-changed state."
  (when-let* ((client (jetpacs-client)))
    (ebp-client-dialog-show
     client
     (jetpacs-org-dialogs--id "note" nil (plist-get ref :pos))
     (jetpacs-column
      (jetpacs-text "State change note" :style "title")
      (jetpacs-text-input "org-note" :label "Note" :min-lines 3)
      (jetpacs-button "Save"
                      (jetpacs-dialog-submit
                       :value "save" :capture-fields '("org-note"))
                      :variant "text")
      (jetpacs-button "Skip" (jetpacs-dialog-dismiss)))
     :callback
     (lambda (status result _error)
       (when (and (equal status "submitted")
                  (equal (plist-get result :value) "save"))
         (let ((text (plist-get (plist-get result :fields) :org-note)))
           (when (and (stringp text)
                      (not (string-blank-p text)))
             (condition-case err
                 (ebp-org-with-mutation ref 'org
                   ;; org's own drawer placement (creates LOGBOOK per
                   ;; `org-log-into-drawer'); the format is the one
                   ;; `ebp-org-parse-logbook' reads back.
                   (goto-char (org-log-beginning t))
                   (insert
                    (format "- Note taken on %s \\\\\n  %s\n"
                            (format-time-string (org-time-stamp-format t t))
                            (replace-regexp-in-string
                             "\n" "\n  "
                             (jetpacs-scalar-text (string-trim text))))))
               (error (message "jetpacs-org-dialogs: note failed: %s"
                               (jetpacs-error-label err))
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
     (let ((m (ebp-org-resolve-ref ref)))
       (unwind-protect
           (with-current-buffer (marker-buffer m)
             (org-with-wide-buffer
              (goto-char m)
              (call-interactively #'org-refile)))
         (set-marker m nil)))
     (ebp-org-cache-invalidate)
     (org-save-all-org-buffers)
     (jetpacs-org-dialogs--notify "Refiled" params)
     (jetpacs-org-dialogs--refresh params))
   params))

;;;; add-heading (poc 2658-2680 rebuilt on the flow seam)

(defun jetpacs-org-add-heading-descriptor (buffer-name)
  "Mint the add-heading descriptor AND its 23.1 record, atomically.
The one sanctioned way to offer the affordance (the files FAB seam and
the Tier-1 outline view both call this), so a descriptor can never ship
without its whole-buffer record.  Calls the buffer's supersession
first, making the mint order-independent within one document —
`jetpacs-buffer-forget-exposed' is first-clear-wins there."
  (jetpacs-buffer-forget-exposed buffer-name)
  (jetpacs-buffer-expose-buffer buffer-name "jetpacs.org.add-heading")
  (jetpacs-action "jetpacs.org.add-heading"
                  :args (list :buffer buffer-name)))

(defun jetpacs-org-dialogs--add-heading-flow (buf params)
  "The bridged prompt half: ask for a title, append `* TITLE'.
The poc called `read-string' INSIDE the handler; here it runs from the
flow continuation behind the can-bridge gate.  The title is scrubbed
and newline-flattened — a multi-line title would smuggle structure."
  (jetpacs-org-dialogs--with-prompting
   (lambda ()
     (let ((title (condition-case nil
                      (read-string "New heading: ")
                    (quit ""))))
       (if (or (not (stringp title)) (string-blank-p title))
           (jetpacs-org-dialogs--notify "Heading cancelled" params)
         (with-current-buffer buf
           (org-with-wide-buffer
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (insert "* "
                    (replace-regexp-in-string
                     "[\n\r]+" " "
                     (jetpacs-scalar-text (string-trim title)))
                    "\n"))
           ;; The seam the engine publishes for exactly this tail: apps
           ;; rebind it for a synchronous save + index refresh.
           (funcall ebp-org-file-save-function (current-buffer)))
         (jetpacs-org-dialogs--notify "Heading added" params))
       (jetpacs-org-dialogs--refresh params)))
   params))

(defun jetpacs-org-dialogs--add-heading (args params)
  "Append a heading to the buffer the render offered the affordance on."
  (let* ((name (plist-get args :buffer))
         (buf (and (stringp name) (get-buffer name))))
    (cond
     ((not buf) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-buffer-p name "jetpacs.org.add-heading"))
      'rejected)
     ;; The target must be a WRITABLE file inside the org roots —
     ;; 23.1 on the effect, not just the addressing.
     ((not (with-current-buffer buf
             (and buffer-file-name
                  (file-writable-p buffer-file-name)
                  (ebp-org-file-allowed-p buffer-file-name))))
      'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (jetpacs-org-dialogs--add-heading-flow buf params)))
      'accepted))))

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

(defun jetpacs-org-dialogs--stamp-at (buf pos)
  "The (STAMP-STRING . BRACKET) beginning exactly at POS in BUF, or nil."
  (with-current-buffer buf
    (org-with-wide-buffer
     (goto-char (min (max (point-min) pos) (point-max)))
     (save-match-data
       (when (and (memq (char-after pos) '(?< ?\[))
                  (org-in-regexp org-ts-regexp-both)
                  (= (match-beginning 0) pos))
         (cons (buffer-substring-no-properties (match-beginning 0)
                                               (match-end 0))
               (char-after pos)))))))

(defun jetpacs-org-dialogs--timestamp-action (args params)
  "A tapped body/planning stamp opens the one-shot editor.
The stamp must still BEGIN at the armed position (else `stale'); the
editor addresses it as a body target and rewrites it literally in
place — which serves planning-line stamps identically, the keyword
staying untouched."
  (let* ((name (plist-get args :buffer))
         (pos (plist-get args :pos))
         (buf (and (stringp name) (get-buffer name))))
    (cond
     ((not (and buf (integerp pos))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer-exposed-p name pos "jetpacs.org.timestamp"))
      'rejected)
     ((not (jetpacs-granted-p "surfaces.dialog")) 'rejected)
     (t
      (let ((stamp (jetpacs-org-dialogs--stamp-at buf pos)))
        (if (null stamp)
            'stale
          (run-at-time 0 nil
                       (lambda ()
                         (jetpacs-org-dialogs--ts-open
                          (list :kind 'body :buffer name :pos pos
                                :bracket (cdr stamp))
                          (car stamp) params)))
          'accepted))))))

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
      (let* ((ref (ebp-org-token-ref
                   token :owner jetpacs-org-dialogs-owner))
             ;; Dialog-context events carry :dialog_id, never :surface
             ;; (14.4 exclusive contexts) — feedback and the re-push
             ;; target the surface the sheet was opened FROM.
             (sheet jetpacs-org-dialogs--sheet)
             (eff (if (plist-get params :surface)
                      params
                    (or (and sheet
                             (equal token (plist-get sheet :token))
                             (plist-get sheet :params))
                        params))))
        (if (null ref)
            'stale
          (condition-case err
              (progn
                (ebp-org-with-mutation ref 'org
                  (let ((org-archive-subtree-save-file-p t))
                    (org-archive-subtree)))
                (when-let* ((sheet jetpacs-org-dialogs--sheet)
                            (client (jetpacs-client)))
                  (when (equal token (plist-get sheet :token))
                    (ignore-errors
                      (ebp-client-abandon client
                                          (plist-get sheet :request-id)))
                    (setq jetpacs-org-dialogs--sheet nil)))
                (jetpacs-org-dialogs--notify "Archived" eff)
                (jetpacs-org-dialogs--refresh eff)
                'accepted)
            (ebp-org-unresolved 'stale)
            (ebp-org-refused 'rejected)
            (error (message "jetpacs-org-dialogs: archive failed: %s"
                            (jetpacs-error-label err))
                   'rejected))))))))

;; Ownerless, the render skin's precedent: an org buffer renders on
;; whatever surface drilled into it, and the sheet/archive must answer
;; there.  Tokens carry their own owner scope.
(jetpacs-defaction "jetpacs.org.footnote"
                   #'jetpacs-org-dialogs--footnote-action)
(jetpacs-defaction "jetpacs.org.heading"
                   #'jetpacs-org-dialogs--heading-action)
(jetpacs-defaction "jetpacs.org.archive" #'jetpacs-org-dialogs--archive)
(jetpacs-defaction "jetpacs.org.timestamp"
                   #'jetpacs-org-dialogs--timestamp-action)
(jetpacs-defaction "jetpacs.org.ts-pick" #'jetpacs-org-dialogs--ts-pick)
(jetpacs-defaction "jetpacs.org.add-heading"
                   #'jetpacs-org-dialogs--add-heading)

;;;; Reset / teardown / unload

(defun jetpacs-org-dialogs-reset ()
  "Reset dialog-module state (the test seam)."
  (setq jetpacs-org-dialogs--seq 0
        jetpacs-org-dialogs--sheet nil)
  (clrhash jetpacs-org-dialogs--ts-sessions)
  (when (timerp jetpacs-org-dialogs--ts-timer)
    (cancel-timer jetpacs-org-dialogs--ts-timer))
  (setq jetpacs-org-dialogs--ts-timer nil))

(defun jetpacs-org-dialogs--on-teardown (owner)
  "Tearing down the org owner sweeps the sessions its dialogs hold."
  (when (equal owner jetpacs-org-dialogs-owner)
    (jetpacs-org-dialogs-reset)))

(add-hook 'jetpacs-teardown-functions #'jetpacs-org-dialogs--on-teardown)
;; Two seams, one reset: teardown fires only for THIS owner, the floor's
;; reset seam fires for every fixture that resets the floor at all.
(add-hook 'jetpacs-reset-functions #'jetpacs-org-dialogs-reset)

(defun jetpacs-org-dialogs-unload-function ()
  "Unload hygiene: deregister the verbs and the hook subscribers."
  (remove-hook 'jetpacs-teardown-functions
               #'jetpacs-org-dialogs--on-teardown)
  (remove-hook 'jetpacs-reset-functions #'jetpacs-org-dialogs-reset)
  (jetpacs-undefaction "jetpacs.org.footnote")
  (jetpacs-undefaction "jetpacs.org.heading")
  (jetpacs-undefaction "jetpacs.org.archive")
  (jetpacs-undefaction "jetpacs.org.timestamp")
  (jetpacs-undefaction "jetpacs.org.ts-pick")
  (jetpacs-undefaction "jetpacs.org.add-heading")
  (jetpacs-org-dialogs-reset)
  nil)

(provide 'jetpacs-org-dialogs)
;;; jetpacs-org-dialogs.el ends here
