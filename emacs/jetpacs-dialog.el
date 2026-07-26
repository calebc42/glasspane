;;; jetpacs-dialog.el --- Emacs prompts as Companion dialogs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JC-4a of docs/PLAN-jetpacs-consumers.md: the prompt floor.  A REBUILD
;; of poc-v1 `jetpacs-minibuffer.el' (~90% new), because the dialog
;; contract inverted underneath it: `dialog.show' is a REQUEST that
;; concludes at user action (SPEC 18.1), dialog inputs emit no
;; `state.changed', a same-`dialog_id' repaint is `1201', and the
;; `prompt.*' custom actions ceased to exist.
;;
;; What bridges: the core prompt functions, advised `:around', each
;; gated by `jetpacs-dialog--bridge-p' — bridging happens ONLY inside a
;; device-originated continuation (`jetpacs-device-flow-p', the D2
;; marker `jetpacs-flow-continue' carries), never inside a dispatch
;; extent (the no-prompts regime governs there and MUST keep winning),
;; and never when `inhibit-interaction' is set.  Everywhere else the
;; original function runs untouched, so desktop Emacs behaves normally.
;;
;; The decisions this file implements (Caleb, 2026-07-25, recorded in
;; the plan's JC-4 section):
;; - `completing-read' has three behaviors.  A closed collection at or
;;   under `jetpacs-dialog-enum-threshold' renders as a native
;;   `enum_list' (multi -> :multi-select, non-require-match ->
;;   :allow-add).  Anything larger or dynamic takes the JC-4b capf
;;   PICKER: a dialog-hosted synchronized `editor' whose keystrokes flow
;;   through SPEC 19 and whose `edit.complete' requests this module
;;   answers from the collection being completed.  A Companion that
;;   cannot host a dialog editor (no `editor.sync', or `editor' not
;;   advertised for dialogs) still gets the JC-4a text stopgap — one
;;   round trip per attempt, same RET-picks-top resolution.
;; - Context-buffer cards render INSIDE the dialog as budgeted
;;   `section_header' + Tier-0 spans (both dialog-profile types),
;;   stripped of interactive attributes: context is evidence, not
;;   controls.
;;
;; Synchronous return over an async request: `jetpacs-dialog--ask'
;; pumps `accept-process-output' under `with-local-quit' until the
;; dialog concludes.  A local C-g is ABANDONMENT (SPEC 7.1): it sends
;; `rpc.cancel' via `ebp-client-abandon' — SPEC 18.1 concludes the
;; dialog with 1301 and dismisses it on the device — and then quits,
;; exactly like C-g at a minibuffer.  A device dismissal quits too.
;; Prompts are single-flight: SPEC 18.1 serializes outstanding dialogs,
;; but two pumped prompts would nest waits, so the inner one refuses.

;;; Code:

(require 'cl-lib)
(require 'ebp)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)

(defgroup jetpacs-dialog nil
  "Emacs prompts bridged to Companion dialogs."
  :group 'jetpacs)

(defcustom jetpacs-dialog-enum-threshold 50
  "Largest closed collection rendered as a native `enum_list'.
Above this (or for any function collection) `completing-read' uses the
JC-4a text-dialog stopgap until the JC-4b picker lands.  The value is
a UI judgement, not a wire limit: every option is rendered (the dialog
profile has no lazy_column), so this bounds dialog height and spec
size, and the host window scrolls past one screenful."
  :type 'natnum)

(defcustom jetpacs-dialog-context-buffers 2
  "How many recorded context buffers render into one prompt dialog."
  :type 'natnum)

(defcustom jetpacs-dialog-context-bytes 4096
  "Byte budget for ONE context buffer's rendered text."
  :type 'natnum)

;;;; The pump

(defvar jetpacs-dialog--counter 0
  "Monotonic dialog-id counter; SPEC 18.1 forbids same-id repaints, so
every prompt gets a fresh `jprompt-N'.")

(defvar jetpacs-dialog--pending nil
  "Non-nil while a bridged prompt is outstanding (single-flight).")

(defun jetpacs-dialog--bridge-p ()
  "Non-nil when a prompt should bridge to a Companion dialog.
Order matters: the no-prompts regime (`inhibit-interaction') and the
dispatch extent must win over bridging — a handler that prompts is a
D2 violation and MUST fail as one, not sneak out through a dialog."
  (and (jetpacs-device-flow-p)
       (not jetpacs--in-action-handler)
       (not inhibit-interaction)
       (not jetpacs-dialog--pending)
       (jetpacs-connected-p)
       ;; SPEC 10.2: dialog.show is capability-gated on surfaces.dialog.
       ;; The node-advertisement gate cannot stand in for this — the
       ;; welcome carries a `dialog' profile ONLY when the capability was
       ;; granted, so advertisement is unanswerable in exactly the case
       ;; that matters.  Ungated, an ungranted session sends dialog.show,
       ;; earns -32601, and the caller's command aborts instead of
       ;; prompting in a perfectly usable minibuffer.
       (jetpacs-granted-p "surfaces.dialog")))

(defun jetpacs-dialog--gate-spec (node)
  "Signal unless every node type in NODE is advertised for dialogs.
SPEC 18.1: every node in a dialog spec MUST be advertised by the
`dialog' surface profile — a sender MUST, so the failure is loud
\(house rule: the shell's four gates), never a silent strip."
  (let ((type (plist-get node :t)))
    (unless (jetpacs-node-advertised-p type :dialog)
      (error "jetpacs-dialog: node type %S is not advertised for dialogs \
(SPEC 18.1/10.2)" type))
    ;; SPEC 14.1: a dialog button's descriptor reaches the wire by this
    ;; path, not the shell's, so the policy gate must run here too.
    (dolist (key '(:on_tap :on_long_tap :on_change :on_submit :on_enter))
      (jetpacs--gate-descriptor-policy (plist-get node key)))
    (mapc #'jetpacs-dialog--gate-spec (plist-get node :children))
    node))

(defun jetpacs-dialog--ask (spec)
  "Show SPEC as a modal dialog; block until it concludes.
Returns the conclusion as (STATUS RESULT): STATUS is \"submitted\" or
\"dismissed\", RESULT the full result plist.  Signals `quit' on local
abandonment (C-g — the dialog is cancelled on the device per SPEC
18.1/7.5) and on error conclusions, so callers read only clean
conclusions.  Runs the SPEC 18.1 advertisement gate before sending."
  (jetpacs-dialog--gate-spec spec)
  (let* ((client (jetpacs-client-or-error))
         (dialog-id (format "jprompt-%d" (cl-incf jetpacs-dialog--counter)))
         (cell nil)
         (abandoned nil)
         (jetpacs-dialog--pending dialog-id)
         (request-id
          (ebp-client-dialog-show
           client dialog-id spec
           :callback (lambda (status result error)
                       (unless abandoned
                         (setq cell (list (or status :error) result error)))))))
    (unless (with-local-quit
              (while (not cell)
                (accept-process-output nil 0.1))
              t)
      ;; Local C-g: abandon per SPEC 7.1 — the Companion concludes 1301
      ;; and dismisses (SPEC 18.1); our callback then no-ops.
      (setq abandoned t)
      (ignore-errors (ebp-client-abandon client request-id))
      (setq quit-flag nil)
      (keyboard-quit))
    (pcase-let ((`(,status ,result ,error) cell))
      (when (or error (eq status :error))
        ;; 1301 after a race, transport loss, 1401 overload: for the
        ;; PROMPT's caller every one of these is \"no answer\" — quit.
        (keyboard-quit))
      (list status result))))

;;;; Context cards (decision 2: budgeted rich text inside the dialog)

(defvar jetpacs-dialog--context-buffers nil
  "Buffer names recorded while a device flow displayed them, newest first.")

(defun jetpacs-dialog--record-context (buffer-or-name)
  "Record BUFFER-OR-NAME when a device flow displays a special buffer."
  (when (jetpacs-device-flow-p)
    (when-let* ((buf (get-buffer buffer-or-name)))
      (when (string-prefix-p "*" (buffer-name buf))
        (cl-pushnew (buffer-name buf) jetpacs-dialog--context-buffers
                    :test #'equal)))))

(defun jetpacs-dialog--display-buffer-advice (orig buffer-or-name &rest args)
  (jetpacs-dialog--record-context buffer-or-name)
  (apply orig buffer-or-name args))

(defun jetpacs-dialog--temp-buffer-show ()
  (jetpacs-dialog--record-context (current-buffer)))

(defun jetpacs-dialog--strip-actions (node)
  "NODE without interactive attributes, recursively.
Context is evidence, not controls: a span's `on_tap' would dispatch a
remote action from inside a dialog — legal per SPEC 18.1 but wrong for
a card whose buffer may be gone by the time the user taps."
  (let ((clean nil))
    (cl-loop for (key value) on node by #'cddr
             unless (memq key '(:on_tap :on_change :on_submit))
             do (setq clean
                      (nconc clean
                             (list key
                                   (cond
                                    ((eq key :children)
                                     (vconcat
                                      (mapcar #'jetpacs-dialog--strip-actions
                                              (append value nil))))
                                    ((eq key :spans)
                                     (vconcat
                                      (mapcar #'jetpacs-dialog--strip-actions
                                              (append value nil))))
                                    (t value))))))
    clean))

(defun jetpacs-dialog--context-ok-p (node)
  "Non-nil when NODE's whole tree is dialog-advertised."
  (and (jetpacs-node-advertised-p (plist-get node :t) :dialog)
       (cl-every #'jetpacs-dialog--context-ok-p
                 (append (plist-get node :children) nil))))

;; `jetpacs-buffer' is an OPTIONAL dependency: context cards use its
;; Tier-0 renderer when it is loaded and degrade to plain text when it
;; is not, so it must not be required at the top.  These declarations
;; give the byte-compiler the dynamic binding and the arities without
;; creating that dependency.
(declare-function jetpacs-buffer-render "jetpacs-buffer" (&optional buffer))
(declare-function jetpacs-buffer-budgets "jetpacs-buffer" ())
(defvar jetpacs-buffer-budget)

(defun jetpacs-dialog--context-nodes ()
  "Nodes for the recorded context buffers, then clear the record.
Each buffer becomes a `section_header' plus its Tier-0 render under
`jetpacs-dialog-context-bytes', with interactive attributes stripped.
A render that uses any node the dialog profile does not advertise
degrades to plain budgeted text — SPEC 18.1's sender MUST, discharged
by degrade rather than by refusing the whole prompt."
  (let ((names (prog1 (seq-take jetpacs-dialog--context-buffers
                                jetpacs-dialog-context-buffers)
                 (setq jetpacs-dialog--context-buffers nil)))
        (nodes nil))
    (dolist (name (reverse names))
      (when-let* ((buf (get-buffer name)))
        (let* ((rendered
                (when (require 'jetpacs-buffer nil t)
                  (ignore-errors
                    ;; The renderer's budget is (MAX-SPANS . MAX-BYTES);
                    ;; bind BYTES to the context allowance so a huge
                    ;; context buffer cannot crowd out the prompt itself.
                    (let ((jetpacs-buffer-budget
                           (cons (car (jetpacs-buffer-budgets))
                                 jetpacs-dialog-context-bytes)))
                      (mapcar #'jetpacs-dialog--strip-actions
                              (jetpacs-buffer-render buf))))))
               (usable (and rendered
                            (cl-every #'jetpacs-dialog--context-ok-p
                                      rendered))))
          (push (jetpacs-section-header (buffer-name buf)) nodes)
          (if usable
              (setq nodes (append (reverse rendered) nodes))
            (push (jetpacs-text
                   (with-current-buffer buf
                     (buffer-substring-no-properties
                      (point-min)
                      (min (point-max)
                           (+ (point-min) jetpacs-dialog-context-bytes))))
                   :style "caption")
                  nodes)))))
    (nreverse nodes)))

;;;; Spec builders

(defun jetpacs-dialog--title (prompt)
  "PROMPT as a dialog headline, minibuffer furniture trimmed."
  (jetpacs-text (string-trim-right prompt "[ :：]+") :style "headline"))

(defun jetpacs-dialog--frame (prompt &rest body)
  "The shared dialog skeleton: title, context cards, BODY, Cancel."
  (apply #'jetpacs-column
         (append (list (jetpacs-dialog--title prompt))
                 (jetpacs-dialog--context-nodes)
                 (list (jetpacs-with-attrs (jetpacs-spacer) :height 8))
                 (delq nil body)
                 (list (jetpacs-with-attrs (jetpacs-spacer) :height 8)
                       (jetpacs-button "Cancel" (jetpacs-dialog-dismiss)
                                       :variant "text")))))

(defun jetpacs-dialog--submitted-value (conclusion)
  "The authored `:value' of a submitted CONCLUSION; quit on dismissal."
  (pcase-let ((`(,status ,result) conclusion))
    (if (equal status "submitted")
        (plist-get result :value)
      (keyboard-quit))))

(defun jetpacs-dialog--submitted-field (conclusion field)
  "Captured FIELD of a submitted CONCLUSION; quit on dismissal."
  (pcase-let ((`(,status ,result) conclusion))
    (if (equal status "submitted")
        (plist-get (plist-get result :fields) field)
      (keyboard-quit))))

;;;; y-or-n-p family

(defun jetpacs-dialog--ask-yn (prompt yes no)
  "Bridge a yes/no PROMPT; YES and NO are the button labels."
  (let ((v (jetpacs-dialog--submitted-value
            (jetpacs-dialog--ask
             (jetpacs-dialog--frame
              prompt
              (jetpacs-row
               (jetpacs-button yes (jetpacs-dialog-submit :value t))
               (jetpacs-with-attrs (jetpacs-spacer) :height 8)
               (jetpacs-button no (jetpacs-dialog-submit
                                   :value :json-false))))))))
    (eq v t)))

(defun jetpacs-dialog--y-or-n-p (orig prompt &rest args)
  (if (jetpacs-dialog--bridge-p)
      (jetpacs-dialog--ask-yn prompt "Yes" "No")
    (apply orig prompt args)))

(defun jetpacs-dialog--yes-or-no-p (orig prompt &rest args)
  (if (jetpacs-dialog--bridge-p)
      (jetpacs-dialog--ask-yn prompt "Yes" "No")
    (apply orig prompt args)))

;;;; String family

(defun jetpacs-dialog--ask-string (prompt &optional initial default)
  "Bridge a string PROMPT; INITIAL seeds the field, DEFAULT covers empty."
  (let* ((raw (jetpacs-dialog--submitted-field
               (jetpacs-dialog--ask
                (jetpacs-dialog--frame
                 prompt
                 (jetpacs-text-input
                  "in" :label prompt :single-line t
                  :value (and initial (not (string-empty-p initial)) initial)
                  :on-submit (jetpacs-dialog-submit :capture-fields '("in")))
                 (jetpacs-with-attrs (jetpacs-spacer) :height 8)
                 (jetpacs-button "OK" (jetpacs-dialog-submit
                                       :capture-fields '("in")))))
               :in))
         (s (if (stringp raw) raw "")))
    (if (string-empty-p s)
        (or (if (consp default) (car default) default) "")
      s)))

(defun jetpacs-dialog--read-string (orig prompt &optional initial history
                                         default inherit)
  (if (jetpacs-dialog--bridge-p)
      (jetpacs-dialog--ask-string
       prompt (cond ((stringp initial) initial)
                    ((consp initial) (car initial)))
       default)
    (funcall orig prompt initial history default inherit)))

(defun jetpacs-dialog--read-from-minibuffer (orig prompt &optional initial
                                                  keymap read hist default
                                                  inherit)
  (if (not (jetpacs-dialog--bridge-p))
      (funcall orig prompt initial keymap read hist default inherit)
    (let ((s (jetpacs-dialog--ask-string
              prompt (cond ((stringp initial) initial)
                           ((consp initial) (car initial)))
              default)))
      ;; READ non-nil wants the string read as a Lisp object, exactly as
      ;; the minibuffer would have.
      (if read (car (read-from-string s)) s))))

;;;; read-passwd

(defun jetpacs-dialog--ask-passwd (prompt)
  "One bridged password entry.  The secret rides `fields' (SPEC 18.1);
the transient copy the conclusion plist holds is cleared here, so the
only surviving string is the one returned to the caller."
  (let* ((conclusion
          (jetpacs-dialog--ask
           (jetpacs-dialog--frame
            prompt
            (jetpacs-text-input
             "pw" :label prompt :single-line t :password t
             :on-submit (jetpacs-dialog-submit :capture-fields '("pw")))
            (jetpacs-with-attrs (jetpacs-spacer) :height 8)
            (jetpacs-button "OK" (jetpacs-dialog-submit
                                  :capture-fields '("pw"))))))
         (raw (jetpacs-dialog--submitted-field conclusion :pw))
         (s (if (stringp raw) (copy-sequence raw) "")))
    (when (stringp raw) (clear-string raw))
    s))

(defun jetpacs-dialog--read-passwd (orig prompt &optional confirm default)
  (if (not (jetpacs-dialog--bridge-p))
      (funcall orig prompt confirm default)
    (if (not confirm)
        (let ((s (jetpacs-dialog--ask-passwd prompt)))
          (if (string-empty-p s) (or default "") s))
      ;; The CONFIRM loop, minibuffer-faithful: re-ask until both
      ;; entries match, clearing every intermediate copy.
      (let (result)
        (while (not result)
          (let ((first (jetpacs-dialog--ask-passwd prompt))
                (second (jetpacs-dialog--ask-passwd
                         (concat prompt "(again) "))))
            (if (string= first second)
                (progn (clear-string second) (setq result first))
              (clear-string first)
              (clear-string second)
              (message "Password not repeated accurately; please start over")
              (sit-for 1))))
        (if (string-empty-p result) (or default "") result)))))

;;;; Char family

(defun jetpacs-dialog--ask-char (prompt chars)
  "Bridge a char PROMPT.  CHARS non-nil limits the answer to that set,
one button each; nil offers a one-character field."
  (if chars
      (let ((v (jetpacs-dialog--submitted-value
                (jetpacs-dialog--ask
                 (jetpacs-dialog--frame
                  prompt
                  (apply #'jetpacs-row
                         (mapcan
                          (lambda (ch)
                            (list (jetpacs-button
                                   (key-description (vector ch))
                                   (jetpacs-dialog-submit
                                    :value (string ch)))
                                  (jetpacs-with-attrs (jetpacs-spacer) :height 8)))
                          chars)))))))
        (if (and (stringp v) (= (length v) 1))
            (aref v 0)
          (keyboard-quit)))
    (let ((s (jetpacs-dialog--ask-string prompt)))
      (if (string-empty-p s) ?\r (aref s 0)))))

(defun jetpacs-dialog--read-char (orig &optional prompt &rest args)
  (if (and prompt (jetpacs-dialog--bridge-p))
      (jetpacs-dialog--ask-char prompt nil)
    (apply orig prompt args)))

(defun jetpacs-dialog--read-char-choice (orig prompt chars &rest args)
  (if (jetpacs-dialog--bridge-p)
      (jetpacs-dialog--ask-char prompt (append chars nil))
    (apply orig prompt chars args)))

;;;; The capf picker (JC-4b): a dialog-hosted synchronized editor

(defcustom jetpacs-dialog-picker-candidates 12
  "Candidates offered per `edit.complete' answer in a picker."
  :type 'natnum)

(defvar jetpacs-dialog--picker-counter 0
  "Monotonic counter for picker DOCUMENT ids.
Separate from `jetpacs-dialog--counter' on purpose: that one belongs to
`jetpacs-dialog--ask', which increments it itself, so deriving a
document name from it made two functions authorities for one number and
they disagreed the moment anything else opened a dialog first.")

(defvar jetpacs-dialog--picker nil
  "The live picker's completion source, or nil.
A plist (:document D :editor-id E :collection C :predicate P).  Bound
for one prompt: `jetpacs-dialog--complete' reads it to answer
`edit.complete' from the collection being completed, so no state has to
be threaded through ebp.el's client-wide hook.")

(defun jetpacs-dialog--complete (document editor-id text cursor)
  "Answer `edit.complete' for the live picker (SPEC 19.3).
Called by ebp.el with (DOCUMENT EDITOR-ID TEXT CURSOR) — no client, the
`:edit-complete-function' contract.
Returns (PREFIX . CANDIDATES) where PREFIX is the text the candidates
replace — `completion-boundaries' decides where it starts, which is what
makes a file-name table complete one path component instead of the whole
path.  CURSOR is a scalar offset; Emacs characters are scalar values,
so it indexes TEXT directly."
  (if (not (and jetpacs-dialog--picker
                (equal document (plist-get jetpacs-dialog--picker :document))
                (equal editor-id (plist-get jetpacs-dialog--picker :editor-id))))
      (cons "" nil)
    (let* ((collection (plist-get jetpacs-dialog--picker :collection))
           (predicate (plist-get jetpacs-dialog--picker :predicate))
           (input (substring text 0 (min (or cursor (length text))
                                         (length text))))
           (bounds (ignore-errors
                     (completion-boundaries input collection predicate "")))
           (start (or (car bounds) 0))
           (prefix (substring input start))
           (cands (ignore-errors
                    (all-completions input collection predicate))))
      (cons prefix
            (mapcar (lambda (c) (list :label c))
                    (seq-take (sort (or cands nil) #'string<)
                              jetpacs-dialog-picker-candidates))))))

(defun jetpacs-dialog--picker-available-p ()
  "Non-nil when a dialog can host a synchronized editor.
Needs the `editor.sync' capability granted AND `editor' advertised for
the dialog target — a Companion that advertises neither still gets the
JC-4a text stopgap rather than a spec violation."
  (when-let* ((client (jetpacs-client)))
    (and (jetpacs-granted-p "editor.sync" client)
         (jetpacs-node-advertised-p "editor" :dialog))))

(defun jetpacs-dialog--ask-picker (prompt collection predicate require-match
                                          initial default)
  "Bridge a large/dynamic COLLECTION as a live capf picker.
The dialog hosts a synchronized `editor' whose keystrokes flow through
SPEC 19; each pause asks Emacs for completions, which
`jetpacs-dialog--complete' answers from COLLECTION.  A tapped candidate
is a local edit replacing the completion prefix.

The picked value comes from the MIRROR, not from `capture_fields': a
synchronized editor is never a stateful node (SPEC 19), so
`dialog.submit' cannot capture it.  SPEC 18.1 closes a dialog's editor
sessions BEFORE the submit response is sent, so the mirror entry is
already gone by then — the text is shadowed on every `edit.delta'
instead, and the last shadow is what the user submitted."
  (let* ((client (jetpacs-client-or-error))
         (document (format "doc:jpick-%d" (cl-incf jetpacs-dialog--picker-counter)))
         (editor-id "pick")
         (shadow (or initial ""))
         (jetpacs-dialog--picker
          (list :document document :editor-id editor-id
                :collection collection :predicate predicate))
         ;; ebp.el's completion hook is client-wide; bind it for this
         ;; prompt only and restore whatever the application had.
         (config (ebp-client-config client))
         (prior-complete (plist-get config :edit-complete-function))
         (watch (lambda (_c doc eid text)
                  ;; A `stringp' check, not just an identity check, and it
                  ;; is load-bearing: `edit.close' fires this SAME hook
                  ;; after removing the session (ebp.el:1259-1264), so it
                  ;; arrives with text nil — and SPEC 18.1 closes a
                  ;; dialog's editor sessions BEFORE the submit response is
                  ;; sent. Without the guard the close wipes the shadow at
                  ;; exactly the moment the picker reads it, and the prompt
                  ;; dies on `stringp nil' with the answer already typed.
                  ;; Device-caught: no stub fires a close.
                  (when (and (equal doc document) (equal eid editor-id)
                             (stringp text))
                    (setq shadow text)))))
    (setf (ebp-client-config client)
          (plist-put (copy-sequence config) :edit-complete-function
                     #'jetpacs-dialog--complete))
    (push watch (ebp-client-edit-change-functions client))
    (unwind-protect
        (let ((answer nil))
          (while (not answer)
            (let* ((conclusion
                    (jetpacs-dialog--ask
                     (jetpacs-dialog--frame
                      prompt
                      (jetpacs-editor
                       editor-id :document document :value shadow
                       :complete t :chromeless t)
                      (jetpacs-with-attrs (jetpacs-spacer) :height 8)
                      (jetpacs-button "OK" (jetpacs-dialog-submit)))))
                   (status (car conclusion))
                   (typed (string-trim shadow)))
              (unless (equal status "submitted") (keyboard-quit))
              (cond
               ((string-empty-p typed)
                (setq answer (or default "")))
               ;; RET-picks-top, exactly as at the minibuffer: an exact
               ;; completion wins, else the top match.
               ((jetpacs-dialog--top-match typed collection predicate)
                (setq answer (jetpacs-dialog--top-match
                              typed collection predicate)))
               ((not require-match) (setq answer typed))
               (t (setq prompt (format "%s (no match for %S)" prompt typed))))))
          answer)
      (setq jetpacs-dialog--picker nil)
      (setf (ebp-client-edit-change-functions client)
            (delq watch (ebp-client-edit-change-functions client)))
      (setf (ebp-client-config client)
            (plist-put (ebp-client-config client) :edit-complete-function
                       prior-complete)))))

;;;; completing-read: the enum fast path, then the picker

(defun jetpacs-dialog--static-candidates (collection predicate)
  "COLLECTION's candidates when it is closed and static, else nil."
  (unless (functionp collection)
    (ignore-errors
      (sort (all-completions "" collection predicate) #'string<))))

(defun jetpacs-dialog--enum-options (candidates)
  (vconcat (mapcar (lambda (c) (list :label c :value c)) candidates)))

(defun jetpacs-dialog--top-match (input collection predicate)
  "Resolve INPUT against COLLECTION like RET-picks-top would.
Exact completions win; otherwise the first completion of INPUT, with
`completion-boundaries' rebuilding the full value for tables that
complete in fields (file names).  nil when nothing matches."
  (cond
   ((ignore-errors (test-completion input collection predicate)) input)
   (t (let* ((bounds (ignore-errors
                       (completion-boundaries input collection predicate "")))
             (prefix (substring input 0 (or (car bounds) 0)))
             (top (car (ignore-errors
                         (all-completions input collection predicate)))))
        (and top (concat prefix top))))))

(defun jetpacs-dialog--completing-read
    (orig prompt collection &optional predicate require-match initial
          hist def inherit)
  (if (not (jetpacs-dialog--bridge-p))
      (funcall orig prompt collection predicate require-match initial
               hist def inherit)
    (let* ((initial (cond ((stringp initial) initial)
                          ((consp initial) (car initial))))
           (default (if (consp def) (car def) def))
           (candidates (jetpacs-dialog--static-candidates
                        collection predicate)))
      (if (and candidates
               (<= (length candidates) jetpacs-dialog-enum-threshold))
          ;; The native picker: one enum_list, one conclusion.
          (let ((v (jetpacs-dialog--submitted-field
                    (jetpacs-dialog--ask
                     (jetpacs-dialog--frame
                      prompt
                      (jetpacs-enum-list
                       "pick" (jetpacs-dialog--enum-options candidates)
                       :value (and initial (member initial candidates)
                                   initial)
                       :allow-add (if require-match :json-false t))
                      (jetpacs-with-attrs (jetpacs-spacer) :height 8)
                      (jetpacs-button "OK" (jetpacs-dialog-submit
                                            :capture-fields '("pick")))))
                    :pick)))
            (cond ((and (stringp v) (not (string-empty-p v))) v)
                  (default default)
                  (t "")))
        ;; Large or dynamic: the JC-4b capf picker when the Companion can
        ;; host a dialog editor, else the JC-4a text stopgap (same
        ;; RET-picks-top resolution, one round trip per attempt).
        (if (jetpacs-dialog--picker-available-p)
            (jetpacs-dialog--ask-picker prompt collection predicate
                                        require-match initial default)
          (let ((caption (if candidates
                             (format "%d candidates — type to match"
                                     (length candidates))
                           "type to match"))
                (answer nil))
            (while (not answer)
              (let ((s (jetpacs-dialog--ask-string
                        prompt initial
                        (concat prompt caption))))
                (cond
                 ((string-empty-p s)
                  (setq answer (or default "")))
                 ((jetpacs-dialog--top-match s collection predicate)
                  (setq answer (jetpacs-dialog--top-match
                                s collection predicate)))
                 ((not require-match) (setq answer s))
                 (t (setq initial s
                          caption (format "no match for %S" s))))))
            answer))))))

(defun jetpacs-dialog--completing-read-multiple
    (orig prompt collection &optional predicate require-match initial
          hist def inherit)
  (if (not (jetpacs-dialog--bridge-p))
      (funcall orig prompt collection predicate require-match initial
               hist def inherit)
    (let ((candidates (jetpacs-dialog--static-candidates
                       collection predicate)))
      (if (and candidates
               (<= (length candidates) jetpacs-dialog-enum-threshold))
          (let ((v (jetpacs-dialog--submitted-field
                    (jetpacs-dialog--ask
                     (jetpacs-dialog--frame
                      prompt
                      (jetpacs-enum-list
                       "picks" (jetpacs-dialog--enum-options candidates)
                       :multi-select t
                       :allow-add (if require-match :json-false t))
                      (jetpacs-with-attrs (jetpacs-spacer) :height 8)
                      (jetpacs-button "OK" (jetpacs-dialog-submit
                                            :capture-fields '("picks")))))
                    :picks)))
            (cond ((vectorp v) (append v nil))
                  ((listp v) v)
                  ((stringp v) (list v))
                  (t nil)))
        ;; Stopgap: comma-separated text, split on crm-separator.
        (let ((s (jetpacs-dialog--ask-string prompt
                                             (cond ((stringp initial) initial)
                                                   ((consp initial)
                                                    (car initial))))))
          (if (string-empty-p s) nil
            (split-string s "[ \t]*,[ \t]*" t)))))))

;;;; map-y-or-n-p

(defun jetpacs-dialog--map-y-or-n-p (orig prompter actor list &rest args)
  "Bridge `map-y-or-n-p' as sequential yes/no dialogs.
The batch keys (!, q, ...) are not offered — each item is its own
dialog; a dismissal quits the whole map, like C-g would.  Returns the
number of actions taken (the original's contract)."
  (if (not (jetpacs-dialog--bridge-p))
      (apply orig prompter actor list args)
    (let ((actions 0))
      (catch 'jetpacs-dialog--map-done
        (dolist (object (cond ((listp list) list)
                              ((arrayp list) (append list nil))
                              (t (error "map-y-or-n-p: unsupported LIST"))))
          (let ((prompt (cond ((functionp prompter) (funcall prompter object))
                              ((stringp prompter) (format prompter object))
                              (t (error "map-y-or-n-p: bad PROMPTER")))))
            (cond
             ;; A non-string prompt means the prompter already acted (or
             ;; skipped): nil skips, t acts without asking.
             ((null prompt))
             ((eq prompt t) (funcall actor object) (cl-incf actions))
             ((not (stringp prompt))
              (funcall actor object) (cl-incf actions))
             ((condition-case nil
                  (jetpacs-dialog--ask-yn prompt "Yes" "No")
                (quit (throw 'jetpacs-dialog--map-done nil)))
              (funcall actor object)
              (cl-incf actions))))))
      actions)))

;;;; Install / uninstall

(defconst jetpacs-dialog--advice
  '((y-or-n-p . jetpacs-dialog--y-or-n-p)
    (yes-or-no-p . jetpacs-dialog--yes-or-no-p)
    (read-string . jetpacs-dialog--read-string)
    (read-from-minibuffer . jetpacs-dialog--read-from-minibuffer)
    (read-passwd . jetpacs-dialog--read-passwd)
    (read-char . jetpacs-dialog--read-char)
    (read-char-exclusive . jetpacs-dialog--read-char)
    (read-char-choice . jetpacs-dialog--read-char-choice)
    (completing-read . jetpacs-dialog--completing-read)
    (completing-read-multiple . jetpacs-dialog--completing-read-multiple)
    (map-y-or-n-p . jetpacs-dialog--map-y-or-n-p))
  "The advised prompt functions and their bridges.")

(defun jetpacs-dialog-install ()
  "Advise the prompt functions and the context-recording seams.
Idempotent.  Outside a device flow every advice is a passthrough, so
desktop behavior is untouched."
  (pcase-dolist (`(,sym . ,fn) jetpacs-dialog--advice)
    (advice-add sym :around fn))
  (advice-add 'display-buffer :around #'jetpacs-dialog--display-buffer-advice)
  (add-hook 'temp-buffer-show-hook #'jetpacs-dialog--temp-buffer-show))

(defun jetpacs-dialog-uninstall ()
  "Remove every advice and hook `jetpacs-dialog-install' added."
  (pcase-dolist (`(,sym . ,fn) jetpacs-dialog--advice)
    (advice-remove sym fn))
  (advice-remove 'display-buffer #'jetpacs-dialog--display-buffer-advice)
  (remove-hook 'temp-buffer-show-hook #'jetpacs-dialog--temp-buffer-show))

(jetpacs-dialog-install)

(provide 'jetpacs-dialog)
;;; jetpacs-dialog.el ends here
