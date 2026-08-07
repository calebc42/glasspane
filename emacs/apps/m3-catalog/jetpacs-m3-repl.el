;;; jetpacs-m3-repl.el --- The Catalog Playground -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The catalog's third non-upstream section, after the identity header
;; and "View elisp".  Those two let you READ what a sample is; this one
;; lets you CHANGE it.
;;
;; Every Example screen grows a bottom sheet resting at a peek over the
;; sample.  Drag it up and it holds the sample's own authored elisp,
;; seeded into a synchronized editor with real `elisp-completion-at-point'
;; answering from Emacs, and a history of what you have evaluated.  Send
;; a form that returns a node and the SAMPLE ABOVE YOU RE-RENDERS as
;; that node.  Send anything else and its printed value lands in a card.
;;
;; WHY A SHEET AND NOT A SCREEN.  A fourth screen works — "View elisp"
;; is one, and `jetpacs-chrome--stack-insert' evicts from the middle to
;; make room.  But a REPL over a component has to keep the component ON
;; SCREEN while you change it; that is the whole difference between a
;; viewer and a loop.  The sheet is the only surface that does.
;;
;; THE SAMPLE STAYS THE SAMPLE.  An override is per example, keyed by
;; `jetpacs-m3-example-screen-id', so nothing you do here leaks into a
;; sibling — and it is discarded by the Reset row, which every panel
;; carries, because a catalog whose samples have quietly stopped being
;; upstream's samples is no longer a catalog.  Nothing is persisted:
;; reloading the module is a reset.
;;
;; THREE EXAMPLES CANNOT HAVE THE SHEET.  Bottom Sheet's own samples ARE
;; the sheet slot, and `jetpacs-scaffold' keeps the first of a duplicate
;; keyword silently.  So the core seam tells this module whether the
;; slot is free, and where it is not the panel rides an in-body
;; `collapsible' instead — which §17.3 keeps expanded across the
;; re-pushes the loop is made of, so it behaves the same way.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'jetpacs-widgets)
(require 'jetpacs-repl)
(require 'jetpacs-m3-core)

(defconst jetpacs-m3-repl-peek-height 96
  "The peek height of the Playground sheet, in dp.
Enough to read the handle and the title and know it is there; small
enough that the sample it is about is not the thing it covers.")

(defvar jetpacs-m3-repl--overrides (make-hash-table :test #'equal)
  "Example screen id -> the node last evaluated for it.
The catalog's other live state — `jetpacs-m3--flags',
`jetpacs-m3-fn-registry' — is authored BY a sample.  This is authored by
the user, over a sample, and is the only state here that can make a
screen stop showing what upstream ships.  Hence per-example, hence
never persisted, hence a Reset on every panel.")

(defun jetpacs-m3-repl-session (id index)
  "The `jetpacs-repl' session id for component ID's example INDEX."
  (format "m3:%s/%d" id index))

(defun jetpacs-m3-repl-document (id index)
  "The synchronized document id for component ID's example INDEX.
Ends `.el' because `ebp-complete--mode-for' matches the document against
`auto-mode-alist' to choose the shadow buffer's major mode — that suffix
is what makes the elisp capfs answer.  Per example, so a half-typed
form cannot follow you into the next one."
  (format "m3-%s-%d.el" id index))

(defun jetpacs-m3-repl-editor-id (id index)
  "The editor node id for component ID's example INDEX."
  (format "%s-repl-%d" id index))

(defun jetpacs-m3-repl-override (id index)
  "The node last evaluated for component ID's example INDEX, or nil."
  (gethash (jetpacs-m3-example-screen-id id index)
           jetpacs-m3-repl--overrides))

;;;; Knobs, derived from the builders' own validators

;; No hand-authored knob tables anywhere.  Every node builder validates
;; its own keywords, and the validator call carries the keyword's NAME
;; as its last argument — `(jetpacs-check-enum variant
;; jetpacs--button-variants ":variant")'.  So the schema is already
;; written down, in the one place that cannot drift from the truth: if a
;; builder grows a member, its validator grows with it and the knob
;; appears.  A table would have to be remembered.

(defvar jetpacs-m3-repl--knobs (make-hash-table :test #'equal)
  "Example screen id -> a plist of knob KEYWORD -> value.
Layered OVER the sample's authored call, never merged into it, so Reset
is a `remhash' and the sample is upstream's again.")

(defun jetpacs-m3-repl--key-params (form)
  "The `&key' parameter names of a `cl-defun' FORM, as keywords."
  (let ((tail (memq '&key (nth 2 form))))
    (cl-loop for p in (cdr tail)
             until (memq p '(&optional &rest &aux))
             collect (intern (concat ":" (symbol-name
                                          (if (consp p) (car p) p)))))))

(defun jetpacs-m3-repl-knob-schema (ctor)
  "The knobs CTOR validates, as a list of (KEYWORD KIND DATA).
KIND is `enum' (DATA is the legal values) or `bool'.  Read off CTOR's own
source, so a builder that has never heard of this module still describes
itself completely.

CONSTRAINED TO THE ARGLIST, which is not belt and braces.  A validator's
last argument is a DIAGNOSTIC LABEL, and several of them spell the WIRE
member rather than the lisp keyword — `jetpacs-button' checks
`\":animate_shape\"' for a parameter called `animate-shape'.  Deriving
blind produced a knob that would hand `jetpacs-button' a keyword it does
not take, i.e. an error card for every turn of it.  So a derived knob
counts only when the constructor really accepts that keyword."
  (when-let* ((text (jetpacs-m3--defun-text ctor))
              (form (ignore-errors (car (read-from-string text))))
              (accepted (jetpacs-m3-repl--key-params form)))
    (let (out)
      (cl-labels
          ((keyword-of (what)
             (and (stringp what) (string-prefix-p ":" what)
                  (let ((key (intern what)))
                    (cond
                     ((memq key accepted) key)
                     ;; The wire spells members with underscores; the
                     ;; lisp keyword uses dashes.  Try the translation
                     ;; before giving up on the knob.
                     ((memq (setq key (intern (string-replace "_" "-" what)))
                            accepted)
                      key)))))
           (walk (x)
             (when (consp x)
               (pcase x
                 (`(jetpacs-check-enum ,_ ,const ,what)
                  (when-let* ((key (keyword-of what)))
                    (when (and (symbolp const) (boundp const))
                      (push (list key 'enum (symbol-value const)) out))))
                 (`(jetpacs-check-bool ,_ ,what)
                  (when-let* ((key (keyword-of what)))
                    (push (list key 'bool nil) out)))
                 (_ nil))
               (walk (car x))
               (walk (cdr x)))))
        (walk form))
      (cl-delete-duplicates (nreverse out) :key #'car :from-end t))))

(defun jetpacs-m3-repl--call (component index)
  "The sample's outermost `jetpacs-' node-constructor call, or nil.
A sample whose body is a `let', a `cl-loop' or a column of several nodes
has no single call to turn knobs on, and says so rather than guessing —
the catalog's own idiom for an honest gap."
  (when-let* ((example (nth index (plist-get component :examples)))
              (builder (jetpacs-m3--example-builder example))
              (text (jetpacs-m3--defun-text builder))
              (form (ignore-errors (car (read-from-string text)))))
    ;; (defun NAME ARGS [DOC] BODY...) — the last top-level body form is
    ;; what the builder returns, and only a bare constructor call qualifies.
    (let ((last (car (last form))))
      (and (consp last)
           (symbolp (car last))
           (string-prefix-p "jetpacs-" (symbol-name (car last)))
           (not (string-prefix-p "jetpacs-m3-" (symbol-name (car last))))
           (jetpacs-m3-repl-knob-schema (car last))
           last))))

(defun jetpacs-m3-repl--apply-knobs (call knobs)
  "CALL with KNOBS layered over its keyword arguments."
  (let* ((ctor (car call))
         (rest (cdr call))
         (positional nil))
    (while (and rest (not (keywordp (car rest))))
      (push (pop rest) positional))
    (let ((keywords (copy-sequence rest)))
      (cl-loop for (key value) on knobs by #'cddr
               do (setq keywords (plist-put keywords key value)))
      (append (list ctor) (nreverse positional) keywords))))

(defun jetpacs-m3-repl-knobs-for (call)
  "CALL's knobs, minus the ones THIS sample cannot actually take.
The arglist says which keywords a constructor accepts; it cannot say
which combinations it accepts.  Several members are conditional on
another — `jetpacs-text-input' refuses `:hide-keyboard-on-submit'
without an `:on-submit', and a password field refuses
`:clear-on-submit' outright — so a knob derived from the arglist alone
is offered on samples where every turn of it is an error card.  81 of
506 were, measured.

So each candidate is TRIED against this sample's own other arguments,
at EVERY value it offers, and kept only if all of them build.  Every
value, not a representative one: probing only the first missed
`jetpacs-dropdown''s `:editable', which takes `t' happily and refuses
`:json-false' when the sample has no `:on-change' — a knob that worked
until you turned it back.  The node constructors are pure, so a couple
of dozen trials per panel cost microseconds and nothing else."
  (cl-loop
   for knob in (jetpacs-m3-repl-knob-schema (car call))
   for values = (pcase (nth 1 knob)
                  ('enum (nth 2 knob))
                  ('bool (list t :json-false)))
   when (and values
             (cl-every
              (lambda (v)
                (condition-case nil
                    (jetpacs-root-node-p
                     (eval (jetpacs-m3-repl--apply-knobs
                            call (list (car knob) v))
                           t))
                  (error nil)))
              values))
   collect knob))

(defun jetpacs-m3-repl--knob-row (component index key kind data current)
  "One control for knob KEY of COMPONENT's example INDEX."
  (let* ((id (plist-get component :id))
         (widget-id (format "%s-knob-%d-%s" id index
                            (substring (symbol-name key) 1)))
         (action (jetpacs-action "m3catalog.repl.knob"
                                 :args (list :component id :index index
                                             :key (symbol-name key)))))
    (pcase kind
      ('enum (jetpacs-dropdown
              widget-id
              (mapcar (lambda (v) (jetpacs-enum-option v v)) data)
              :label (symbol-name key)
              :value (and (member current data) current)
              :on-change action))
      ('bool (jetpacs-switch widget-id
                             :label (symbol-name key)
                             :checked (and current (not (eq current :json-false)))
                             :on-change action))
      (_ nil))))

(defun jetpacs-m3-repl--knob-panel (component index)
  "The knob controls for COMPONENT's example INDEX — a LIST of nodes."
  (let* ((id (plist-get component :id))
         (call (jetpacs-m3-repl--call component index))
         (schema (and call (jetpacs-m3-repl-knobs-for call)))
         (state (gethash (jetpacs-m3-example-screen-id id index)
                         jetpacs-m3-repl--knobs)))
    (if (null schema)
        (list (jetpacs-text
               "No knobs: this sample is not a single node builder call."
               :style "caption"))
      (cl-loop for (key kind data) in schema
               for row = (jetpacs-m3-repl--knob-row
                          component index key kind data
                          (plist-get state key))
               when row collect row))))

;;;; The panel

(defun jetpacs-m3-repl--seed (component index)
  "COMPONENT's example INDEX authored elisp, as prompt seed text.
The sample's own defun, so the first thing the field holds is the thing
it is about — the difference between a REPL you can start using and an
empty box over a component whose vocabulary you do not know yet."
  (let* ((example (nth index (plist-get component :examples)))
         (builder (jetpacs-m3--example-builder example)))
    (or (and builder (jetpacs-m3--defun-text builder))
        (format ";; %s has no authored elisp to seed.\n"
                (plist-get example :name)))))

(defun jetpacs-m3-repl-panel (component index)
  "The Playground panel for COMPONENT's example INDEX."
  (let* ((id (plist-get component :id))
         (session (jetpacs-m3-repl-session id index))
         (overridden (jetpacs-m3-repl-override id index)))
    (jetpacs-column
     (jetpacs-row
      (jetpacs-with-attrs
       (jetpacs-text "Playground" :style "title") :weight 1)
      (jetpacs-icon-button
       "restart_alt"
       (jetpacs-action "m3catalog.repl.reset"
                       :args (list :component id :index index))
       :content-description "Reset the sample"
       :variant (and overridden "tonal"))
      :align "center" :fill t)
     (jetpacs-text
      (if overridden
          "Showing your node. Reset restores the upstream sample."
          "Edit the sample and send it. A node replaces what is above.")
      :style "caption")
     (jetpacs-divider)
     ;; The knobs, then the prompt: the panel reads top to bottom from
     ;; "change one member" to "write whatever you like", which is also
     ;; the order in which someone learns the vocabulary.
     (apply #'jetpacs-column
            (append (jetpacs-m3-repl--knob-panel component index)
                    (list :spacing 4)))
     (jetpacs-divider)
     ;; ARGS is what makes the verb multi-session: the send button
     ;; dispatches with no value and reads the mirror, so this pair is
     ;; the only thing on that dispatch saying WHICH example it is for.
     ;; Without it every send was rejected in silence — found on
     ;; hardware, by a Playground whose button did nothing.
     (jetpacs-with-attrs
      (if-let* ((cards (jetpacs-repl-cards
                        session :verb "m3catalog.repl"
                        :args (list :component id :index index))))
          (apply #'jetpacs-lazy-column cards)
        (jetpacs-repl-empty-state))
      :weight 1)
     (jetpacs-repl-input-row
      :editor-id (jetpacs-m3-repl-editor-id id index)
      :document (jetpacs-m3-repl-document id index)
      :verb "m3catalog.repl"
      :args (list :component id :index index)
      :value (jetpacs-m3-repl--seed component index))
     :spacing 8 :fill t)))

(defun jetpacs-m3-repl-extras (component index sheet-free-p)
  "The Playground, as `jetpacs-m3-example-extras-function' answers it.
On the sheet when the slot is free; in an in-body `collapsible' when the
example's own sample IS the sheet, which §17.3 keeps expanded across the
re-pushes the loop is made of."
  (let* ((id (plist-get component :id))
         (panel (jetpacs-m3--guard "playground"
                                   (lambda () (jetpacs-m3-repl-panel
                                               component index))))
         (override (jetpacs-m3-repl-override id index)))
    (append
     (and override (list :override override))
     (if sheet-free-p
         (list :scaffold (list :sheet panel
                               :sheet-peek-height jetpacs-m3-repl-peek-height))
       (list :body
             (list (jetpacs-collapsible
                    (format "%s-playground-%d" id index)
                    (jetpacs-text "Playground" :style "title")
                    panel :collapsed t)))))))

;;;; The verbs

(defun jetpacs-m3-repl--on-eval (args params)
  "Evaluate the Playground's input for one example and re-render it.

Mirrors `hub.eval': the send button arrives WITHOUT a value and reads
the synchronized mirror, because the editor carries a `:document' and is
therefore not a stateful draft; on-enter and the re-run button carry
`:value'.

A returned NODE becomes the sample.  Anything else is a card.  That is
the whole loop, and the node case is the one the catalog exists for: the
print step of this REPL is a rendering."
  (let* ((id (plist-get args :component))
         (index (plist-get args :index))
         (surface (plist-get params :surface))
         (component (and (stringp id) (jetpacs-m3-component id))))
    (cond
     ((not (and (stringp id) (integerp index))) 'rejected)
     ((null component) 'stale)
     ((not (< -1 index (length (plist-get component :examples)))) 'stale)
     (t
      (let ((input (or (plist-get args :value)
                       (when-let* ((client (jetpacs-client)))
                         (ebp-client-editor-text
                          client
                          (jetpacs-m3-repl-document id index)
                          (jetpacs-m3-repl-editor-id id index))))))
        (if (not (and (stringp input) (not (string-blank-p input))))
            'rejected
          (jetpacs-flow-continue
           (lambda ()
             (pcase-let ((`(,value ,_output ,errorp)
                          (jetpacs-repl-run
                           (jetpacs-m3-repl-session id index) input)))
               ;; A node replaces the sample; a value that is not a node
               ;; stays in its card, and an ERROR never touches the
               ;; sample at all — the screen you were looking at is the
               ;; one thing a failed experiment must not cost you.
               (when (and (not errorp) (jetpacs-root-node-p value))
                 (puthash (jetpacs-m3-example-screen-id id index) value
                          jetpacs-m3-repl--overrides))
               (condition-case err
                   (jetpacs-shell-push (or surface jetpacs-m3-owner))
                 (error (message "jetpacs-m3-repl: refresh failed: %s"
                                 (jetpacs-error-label err)))))))
          'accepted))))))

(defun jetpacs-m3-repl--on-knob (args params)
  "Turn one knob and re-render the sample through its own builder.

The value arrives INJECTED (SPEC 14.3) — the option a dropdown picked,
the boolean a switch flipped — and is checked against the schema the
BUILDER declares before it is used, so the wire cannot introduce a
member the constructor would refuse.  It would refuse it loudly, which
is the backstop; this is the guard that keeps a fat-fingered enum from
turning a whole screen into an error card."
  (let* ((id (plist-get args :component))
         (index (plist-get args :index))
         (key (plist-get args :key))
         (surface (plist-get params :surface))
         (component (and (stringp id) (jetpacs-m3-component id)))
         (call (and component (integerp index)
                    (jetpacs-m3-repl--call component index)))
         (schema (and call (jetpacs-m3-repl-knobs-for call)))
         (spec (and (stringp key) (assq (intern key) schema))))
    (cond
     ((not (and (stringp id) (integerp index) (stringp key))) 'rejected)
     ((null component) 'stale)
     ((null spec) 'stale)
     (t
      (let* ((value (plist-get args :value))
             (value (pcase (nth 1 spec)
                      ('enum (and (member value (nth 2 spec)) value))
                      ('bool (if (eq value :json-false) :json-false
                               (and value t)))
                      (_ nil)))
             (screen (jetpacs-m3-example-screen-id id index)))
        (if (null value)
            'rejected
          (let ((state (plist-put (copy-sequence
                                   (gethash screen jetpacs-m3-repl--knobs))
                                  (intern key) value)))
            (puthash screen state jetpacs-m3-repl--knobs)
            ;; The knob's whole effect is one re-evaluation of the
            ;; sample's OWN call with the member layered on, so what you
            ;; see is what that builder does — not a second rendering
            ;; path that could disagree with it.
            (let ((node (jetpacs-m3--guard
                         "knob"
                         (lambda ()
                           (eval (jetpacs-m3-repl--apply-knobs call state) t)))))
              (puthash screen node jetpacs-m3-repl--overrides)))
          (jetpacs-flow-continue
           (lambda ()
             (condition-case err
                 (jetpacs-shell-push (or surface jetpacs-m3-owner))
               (error (message "jetpacs-m3-repl: knob refresh failed: %s"
                               (jetpacs-error-label err))))))
          'accepted))))))

(defun jetpacs-m3-repl--on-reset (args params)
  "Discard one example's override and re-render it as upstream's."
  (let ((id (plist-get args :component))
        (index (plist-get args :index))
        (surface (plist-get params :surface)))
    (cond
     ((not (and (stringp id) (integerp index))) 'rejected)
     ((null (jetpacs-m3-component id)) 'stale)
     (t (remhash (jetpacs-m3-example-screen-id id index)
                 jetpacs-m3-repl--overrides)
        (remhash (jetpacs-m3-example-screen-id id index)
                 jetpacs-m3-repl--knobs)
        (jetpacs-flow-continue
         (lambda ()
           (condition-case err
               (jetpacs-shell-push (or surface jetpacs-m3-owner))
             (error (message "jetpacs-m3-repl: reset refresh failed: %s"
                             (jetpacs-error-label err))))))
        'accepted))))

(defun jetpacs-m3-repl--read-example (prompt)
  "Read a component and example index interactively, as (COMPONENT INDEX)."
  (let* ((name (completing-read
                prompt
                (mapcar (lambda (c) (plist-get c :name)) jetpacs-m3-components)
                nil t))
         (component (cl-find name jetpacs-m3-components
                             :key (lambda (c) (plist-get c :name))
                             :test #'equal))
         (examples (plist-get component :examples))
         (pick (completing-read
                "Example: "
                (cl-loop for e in examples collect (plist-get e :name))
                nil t)))
    (list component
          (cl-position pick examples
                       :key (lambda (e) (plist-get e :name)) :test #'equal))))

;;;###autoload
(defun jetpacs-m3-repl-eval (component index form)
  "Evaluate FORM as COMPONENT's example INDEX and show the result there.
The M-x projection of the Playground's send button, and the reason it
exists is not symmetry: the device prompt is a phone keyboard, and a
form worth more than a few words is one you would rather type here.
Both doors reach the same session, so the history is the same history.

A node becomes the sample; anything else lands in a card, exactly as on
the device."
  (interactive
   (append (jetpacs-m3-repl--read-example "Component: ")
           (list (read-string "Eval in the Playground: "))))
  (let ((id (plist-get component :id)))
    (pcase-let ((`(,value ,output ,errorp)
                 (jetpacs-repl-run (jetpacs-m3-repl-session id index) form)))
      (when (and (not errorp) (jetpacs-root-node-p value))
        (puthash (jetpacs-m3-example-screen-id id index) value
                 jetpacs-m3-repl--overrides))
      (when (jetpacs-connected-p)
        (ignore-errors (jetpacs-shell-push jetpacs-m3-owner)))
      (message "%s" output))))

;;;###autoload
(defun jetpacs-m3-repl-reset (component index)
  "Discard COMPONENT's example INDEX overrides — the Reset row, as a command."
  (interactive (jetpacs-m3-repl--read-example "Reset component: "))
  (let ((screen (jetpacs-m3-example-screen-id
                 (plist-get component :id) index)))
    (remhash screen jetpacs-m3-repl--overrides)
    (remhash screen jetpacs-m3-repl--knobs)
    (when (jetpacs-connected-p)
      (ignore-errors (jetpacs-shell-push jetpacs-m3-owner)))
    (message "jetpacs-m3: %s is upstream's again" screen)))

;;;###autoload
(defun jetpacs-m3-repl-reset-all ()
  "Discard every Playground override — M-x parity for the Reset rows.
`docs/CHROME-VOCABULARY.md': chrome is a projection of commands, so
every affordance is reachable without it."
  (interactive)
  (clrhash jetpacs-m3-repl--overrides)
  (clrhash jetpacs-m3-repl--knobs)
  (when (jetpacs-connected-p)
    (ignore-errors (jetpacs-shell-push jetpacs-m3-owner)))
  (message "jetpacs-m3: every sample is upstream's again"))

(defun jetpacs-m3-repl-register ()
  "Attach the Playground to the catalog's Example screens."
  (with-jetpacs-owner jetpacs-m3-owner
    (jetpacs-defaction "m3catalog.repl" #'jetpacs-m3-repl--on-eval)
    (jetpacs-defaction "m3catalog.repl.knob" #'jetpacs-m3-repl--on-knob)
    (jetpacs-defaction "m3catalog.repl.reset" #'jetpacs-m3-repl--on-reset))
  (setq jetpacs-m3-example-extras-function #'jetpacs-m3-repl-extras))

(jetpacs-m3-repl-register)

(provide 'jetpacs-m3-repl)
;;; jetpacs-m3-repl.el ends here
