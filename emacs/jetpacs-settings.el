;;; jetpacs-settings.el --- Schema-driven settings from defcustom metadata -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Renders an allowlisted set of defcustom variables as companion widgets
;; derived from their `custom-type' schemas, and applies edits through
;; Customize: candidate values are validated with the type's widget
;; `:match', set via `customize-set-variable' (so `:set' setters run),
;; and persisted via `customize-save-variable'.
;;
;; The registry is the security boundary: `settings.set'/`settings.reset'
;; only touch symbols present in `jetpacs-settings-registry', never
;; arbitrary names off the wire.  Exposing a new setting is one registry
;; entry.  The rendering/apply machinery itself is public and
;; gate-agnostic — jetpacs-customize.el reuses it under its own
;; `customize.*' actions with a `custom-variable-p' gate; the registry
;; rule binds `settings.*' only.
;;
;; Widget mapping by type: boolean -> switch (the switch publishes
;; state.changed rather than dispatching an action, so per-id handlers
;; register with the section), choice-of-consts -> single-select enum
;; list, string/file/directory -> text input, integer/number -> numeric
;; text input, anything else -> a raw elisp expression read with `read'.
;;
;; (Behavior reference: POC 1's jetpacs-settings.el.  Dropped here: the
;; jetpacs-config custom-file management — POC 3 warns once instead —
;; and the settings-hub split bodies, which wait on the app-identity
;; design pass recorded in PLAN-poc1-parity.)

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'wid-edit)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)

(defconst jetpacs-settings-surface "jetpacs.settings"
  "The settings root surface (owner and surface name).")

(defvar jetpacs-settings-registry nil
  "Alist of (TITLE . ENTRIES); each entry (SYMBOL . PLIST).
PLIST keys: :label, :after-set, :render (a nullary node builder that
replaces the schema-derived control).  Presence here is what authorizes
`settings.set'/`settings.reset' for a symbol.")

;;;; Registry

(defun jetpacs-settings-register-section (title entries)
  "Register (or replace) settings section TITLE with ENTRIES.
Also registers the state.changed handlers for its boolean switches —
a queued toggle can replay before the screen ever renders, so handlers
belong to registration, not to rendering."
  (setf (alist-get title jetpacs-settings-registry nil nil #'equal) entries)
  (dolist (entry entries)
    (unless (plist-get (cdr entry) :render)
      (jetpacs-settings-watch-toggle
       (car entry)
       (concat "setting/" (symbol-name (car entry)))
       (plist-get (cdr entry) :after-set)))))

(defun jetpacs-settings-remove-section (title)
  "Remove settings section TITLE."
  (setf (alist-get title jetpacs-settings-registry nil 'remove #'equal) nil))

(defun jetpacs-settings--entry (sym)
  "SYM's registry entry (SYMBOL . PLIST), or nil when not exposed."
  (cl-loop for (_title . entries) in jetpacs-settings-registry
           thereis (assq sym entries)))

;;;; Applying values through Customize

(defvar jetpacs-settings--custom-file-warned nil)

(defun jetpacs-settings-save-variable (symbol value)
  "Set SYMBOL to VALUE via Customize and persist it.
Without a `custom-file', `customize-save-variable' writes the init
file; warn once so the owner knows where edits are landing."
  (unless (or custom-file jetpacs-settings--custom-file-warned)
    (setq jetpacs-settings--custom-file-warned t)
    (message "jetpacs-settings: no custom-file set; saving to init file"))
  (customize-save-variable symbol value))

(defun jetpacs-settings--type (sym)
  (or (get sym 'custom-type) 'sexp))

(defun jetpacs-settings--const-option (alt)
  "The (LABEL . VALUE) of a const choice arm ALT, or nil."
  (pcase alt
    (`(const . ,rest)
     (let* ((plist (and (keywordp (car-safe rest)) rest))
            (value (if plist (car (last rest)) (car rest)))
            (tag (and plist (plist-get plist :tag))))
       (cons (or tag (prin1-to-string value)) value)))
    (_ nil)))

(defun jetpacs-settings--choice-options (type)
  "The (LABEL . VALUE) list of a choice-of-consts TYPE, or nil."
  (when (eq (car-safe type) 'choice)
    (let ((opts (mapcar #'jetpacs-settings--const-option (cdr type))))
      (and (not (memq nil opts)) opts))))

(defun jetpacs-settings--kind (type)
  "One of boolean/choice/string/number/sexp for schema TYPE."
  (pcase (car-safe (if (consp type) type (list type)))
    ('boolean 'boolean)
    ((or 'string 'file 'directory 'regexp) 'string)
    ((or 'integer 'number 'natnum 'float) 'number)
    ('choice (if (jetpacs-settings--choice-options type) 'choice 'sexp))
    (_ 'sexp)))

(defun jetpacs-settings--valid-p (sym value)
  "Whether VALUE matches SYM's custom-type widget schema."
  (condition-case nil
      (widget-apply (widget-convert (jetpacs-settings--type sym))
                    :match value)
    (error nil)))

(defun jetpacs-settings-apply (sym value &optional after-set)
  "Validate VALUE against SYM's schema, set and persist it; t on success."
  (if (not (jetpacs-settings--valid-p sym value))
      (progn
        (jetpacs-toast (format "Invalid value for %s" sym))
        nil)
    (jetpacs-settings-save-variable sym value)
    (when after-set (funcall after-set sym value))
    t))

(defun jetpacs-settings--decode (sym wire)
  "Decode WIRE (a state/submit payload) into SYM's value domain.
Booleans arrive as t/:json-false; numbers and sexps as strings to
`read'; choice labels map back through the const table.  Returns
(VALUE) on success, nil on a parse failure — a nil VALUE is legal."
  (let ((kind (jetpacs-settings--kind (jetpacs-settings--type sym))))
    (pcase kind
      ('boolean (list (eq wire t)))
      ('choice
       (let* ((opts (jetpacs-settings--choice-options
                     (jetpacs-settings--type sym)))
              (label (if (and (vectorp wire) (> (length wire) 0))
                         (aref wire 0)
                       wire))
              (hit (assoc label opts)))
         (and hit (list (cdr hit)))))
      ('string (and (stringp wire) (list wire)))
      ('number (let ((n (and (stringp wire)
                             (ignore-errors (read wire)))))
                 (and (numberp n) (list n))))
      (_ (let ((v (and (stringp wire)
                       (condition-case nil (list (read wire))
                         (error nil)))))
           v)))))

(defun jetpacs-settings-apply-wire (sym wire &optional after-set)
  "Apply a wire payload WIRE to SYM; non-nil on success."
  (let ((decoded (jetpacs-settings--decode sym wire)))
    (if (not decoded)
        (progn (jetpacs-toast (format "Cannot parse value for %s" sym)) nil)
      (jetpacs-settings-apply sym (car decoded) after-set))))

(defun jetpacs-settings--standard-value (sym)
  (eval (car (get sym 'standard-value)) t))

(defun jetpacs-settings-modified-p (sym)
  "Whether SYM's current global value differs from its standard default.
Safe on any symbol: unbound means unmodified, and a standard-value form
that fails to evaluate counts as unmodified rather than erroring (the
customize browser calls this across arbitrary defcustoms)."
  (and (boundp sym)
       (get sym 'standard-value)
       (not (equal (default-value sym)
                   (condition-case nil (jetpacs-settings--standard-value sym)
                     (error (default-value sym)))))))

(defun jetpacs-settings-reset (sym &optional after-set)
  "Reset SYM to its defcustom standard value; non-nil on success."
  (if (not (get sym 'standard-value))
      (progn (jetpacs-toast "Cannot reset this setting") nil)
    (when (jetpacs-settings-apply
           sym (jetpacs-settings--standard-value sym) after-set)
      (jetpacs-toast (format "%s reset to default" sym))
      t)))

;;;; Rendering

(defun jetpacs-settings--doc-line (sym)
  "First line of SYM's docstring, or nil."
  (let ((doc (documentation-property sym 'variable-documentation)))
    (and doc (car (split-string (substitute-command-keys doc) "\n" t)))))

(cl-defun jetpacs-settings-item (sym &key label (id-prefix "setting/")
                                     (set-action "settings.set")
                                     (reset-action "settings.reset"))
  "Widget column rendering SYM's control from its `custom-type' schema.
LABEL defaults to the symbol name.  ID-PREFIX keys the control's widget
id; a switch under it publishes state.changed, so pair a non-default
prefix with `jetpacs-settings-watch-toggle'.  SET-ACTION and
RESET-ACTION name the wire actions, each carrying the symbol name under
`:name' — the settings screen uses the registry-gated `settings.*', the
customize browser the `custom-variable-p'-gated `customize.*'."
  (if (not (boundp sym))
      (jetpacs-text (format "%s is not loaded yet" sym) :style "caption")
    (let* ((name (symbol-name sym))
           (label (or label name))
           (doc (jetpacs-settings--doc-line sym))
           (value (default-value sym))
           (type (jetpacs-settings--type sym))
           (kind (jetpacs-settings--kind type))
           (wid-id (concat id-prefix name))
           (set (jetpacs-action set-action :args `(:name ,name)))
           (reset (and (jetpacs-settings-modified-p sym)
                       (jetpacs-icon-button
                        "history"
                        (jetpacs-action reset-action :args `(:name ,name))
                        :content-description
                        (format "Reset %s to default" label))))
           (control
            (pcase kind
              ('boolean
               (jetpacs-switch wid-id :checked (and value t) :label label))
              ('choice
               (let* ((opts (jetpacs-settings--choice-options type))
                      (current (car (rassoc value opts)))
                      (labels (mapcar #'car opts)))
                 (unless current
                   ;; A value outside the const arms (set from lisp):
                   ;; show it, printed, as the selection.
                   (setq current (prin1-to-string value)
                         labels (append labels (list current))))
                 ;; The wire value IS the label; `--decode' maps it back
                 ;; through the const table (option values must be wire
                 ;; scalars, and the elisp values here are symbols).
                 (jetpacs-enum-list
                  wid-id
                  (mapcar (lambda (l) (jetpacs-enum-option l l)) labels)
                  :value current :on-change set)))
              ('string
               (jetpacs-text-input wid-id :value (and (stringp value) value)
                                   :label label :single-line t
                                   :on-submit set))
              ('number
               (jetpacs-text-input wid-id
                                   :value (and (numberp value)
                                               (number-to-string value))
                                   :label label :single-line t
                                   :on-submit set))
              (_
               (jetpacs-text-input wid-id :value (prin1-to-string value)
                                   :label label :single-line t
                                   :hint "Elisp expression"
                                   :on-submit set)))))
      (apply #'jetpacs-column
             (delq nil
                   (list
                    ;; Booleans carry their label inside the switch row;
                    ;; everything else gets a plain label row.  The
                    ;; weighted wrap keeps the reset button on-screen.
                    (jetpacs-row
                     (jetpacs-with-attrs
                      (if (eq kind 'boolean)
                          control
                        (jetpacs-text label :style "label"))
                      :weight 1)
                     reset)
                    (when doc (jetpacs-text doc :style "caption"))
                    (unless (eq kind 'boolean) control)))))))

(defun jetpacs-settings--item (entry)
  "Widget column for registry ENTRY (a :render row renders itself)."
  (let ((render (plist-get (cdr entry) :render)))
    (if render
        (funcall render)
      (jetpacs-settings-item (car entry)
                             :label (plist-get (cdr entry) :label)))))

(defvar jetpacs-settings-links nil
  "Ordered list of (ORDER BUILDER . OWNER) satellite entries.
BUILDER is a nullary node builder (usually a tappable card leading to
another screen).  Apps register satellite screens here — the package
browser, Customize — instead of each claiming chrome of its own.")

(defun jetpacs-settings-add-link (order builder)
  "Add BUILDER (a nullary node builder) to the settings screen at ORDER.
Registrations made under `with-jetpacs-owner' are attributed to that
owner for the app-identity layer to filter once it exists."
  (setq jetpacs-settings-links
        (sort (cons (cons order
                          (cons builder
                                (bound-and-true-p jetpacs-current-owner)))
                    jetpacs-settings-links)
              (lambda (a b) (< (car a) (car b))))))

(defun jetpacs-settings-sections ()
  "The settings body: registry sections, then the satellite links."
  (append
   (cl-loop for (title . entries) in jetpacs-settings-registry
            append (append (list (jetpacs-section-header title))
                           (mapcar #'jetpacs-settings--item entries)))
   (mapcar (lambda (e) (funcall (cadr e))) jetpacs-settings-links)))

(defun jetpacs-settings--view ()
  "The settings root: a scaffold, so chrome docks the view switcher."
  (jetpacs-scaffold
   :body
   (apply #'jetpacs-lazy-column
          (cons (jetpacs-text "Settings" :style "title")
                (jetpacs-settings-sections)))))

(defun jetpacs-settings-refresh ()
  "Re-push the settings surface (deferred; safe from dispatch)."
  (jetpacs-flow-continue
   (lambda ()
     (ignore-errors (jetpacs-shell-push jetpacs-settings-surface)))))

;;;; Actions and state handlers

(defun jetpacs-settings--action-set (args _params)
  (let* ((name (plist-get args :name))
         (sym (and (stringp name) (intern-soft name)))
         (entry (and sym (jetpacs-settings--entry sym))))
    (if (not entry)
        'rejected
      (jetpacs-settings-apply-wire sym (plist-get args :value)
                                   (plist-get (cdr entry) :after-set))
      (jetpacs-settings-refresh)
      'accepted)))

(defun jetpacs-settings--action-reset (args _params)
  (let* ((name (plist-get args :name))
         (sym (and (stringp name) (intern-soft name)))
         (entry (and sym (jetpacs-settings--entry sym))))
    (if (not entry)
        'rejected
      (jetpacs-settings-reset sym (plist-get (cdr entry) :after-set))
      (jetpacs-settings-refresh)
      'accepted)))

(defun jetpacs-settings-watch-toggle (sym id &optional after-set)
  "Register the state.changed handler applying SYM's switch under ID.
The switch widget publishes state.changed instead of dispatching an
action, so a boolean setting only works once a handler exists for its
widget id.  Non-boolean payloads under ID are ignored; those save
through their submit action instead."
  (jetpacs-on-state-change
   id (lambda (val)
        (when (memq val '(t :json-false))
          (jetpacs-settings-apply sym (eq val t) after-set)
          (jetpacs-settings-refresh)))))

(with-jetpacs-owner "jetpacs.settings"
  (jetpacs-shell-define-root jetpacs-settings-surface
                             #'jetpacs-settings--view))
(jetpacs-defaction "settings.set" #'jetpacs-settings--action-set)
(jetpacs-defaction "settings.reset" #'jetpacs-settings--action-reset)

(provide 'jetpacs-settings)
;;; jetpacs-settings.el ends here