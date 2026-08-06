;;; jetpacs-customize.el --- Customize browser over the defcustom group tree -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; The M-x customize counterpart of the tablist story.  A Custom-mode
;; buffer is widget.el *layout* — positions and markers, not data — and
;; the wrong thing to scrape.  The declarative framework behind
;; Customize is the metadata: the defgroup tree plus each variable's
;; `custom-type' schema, and jetpacs-settings.el already renders those
;; schemas as native controls.  So this app skips Custom-mode entirely:
;; `custom-group-members' provides the structure, the shared settings
;; item renderer and apply pipeline provide the leaves, and edits
;; persist through Customize like every other setting.
;;
;; Boundary (SPEC §5): `customize.set'/`customize.reset' accept any
;; symbol satisfying `custom-variable-p' — deliberately wider than the
;; `settings.*' registry gate, and exactly as powerful as M-x customize
;; itself (which the M-x escape hatch already exposes).  Values remain
;; plain data validated against the variable's declared type before
;; they are applied; nothing off the wire is funcalled.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'cus-edit)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-settings)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)

(defconst jetpacs-customize-surface "jetpacs.customize"
  "The customize browser's root surface (owner and surface name).")

(defcustom jetpacs-customize-max-items 50
  "Maximum subgroups and maximum variables rendered per screen.
Huge groups (or a broad search) are capped with a trailing note; narrow
with the search box rather than paging."
  :type 'integer :group 'jetpacs)

(defvar jetpacs-customize--path '(emacs)
  "Breadcrumb of group symbols from the root to the group being shown.")

(defvar jetpacs-customize--search ""
  "Current search string; non-empty switches to the flat variable list.")

(defvar jetpacs-customize--modified-only nil
  "Non-nil limits the view to variables changed from their defaults.")

(defun jetpacs-customize--group ()
  (car (last jetpacs-customize--path)))

(defun jetpacs-customize--flat-p ()
  (or jetpacs-customize--modified-only
      (not (string-empty-p jetpacs-customize--search))))

;;;; Reading the group tree

(defun jetpacs-customize--group-p (sym)
  "Non-nil when SYM names a customization group, loading it if deferred."
  (when sym
    (ignore-errors (custom-load-symbol sym))
    (and (or (get sym 'custom-group)
             (get sym 'group-documentation))
         t)))

(defun jetpacs-customize--members (group)
  "GROUP's members as (GROUPS VARIABLES FACES), each a list of symbols."
  (let (groups vars faces)
    (dolist (m (custom-group-members group nil))
      (pcase (cadr m)
        ('custom-group (push (car m) groups))
        ('custom-variable (push (car m) vars))
        ('custom-face (push (car m) faces))))
    (list (nreverse groups) (nreverse vars) (nreverse faces))))

(defun jetpacs-customize--flat-vars ()
  "All customizable variables passing the search and modified filters."
  (let ((q jetpacs-customize--search) out)
    (mapatoms
     (lambda (sym)
       (when (and (custom-variable-p sym)
                  (or (string-empty-p q)
                      (string-match-p (regexp-quote q) (symbol-name sym)))
                  (or (not jetpacs-customize--modified-only)
                      (jetpacs-settings-modified-p sym)))
         (push sym out))))
    (sort out #'string-lessp)))

;;;; Rendering

(defvar jetpacs-customize--watched (make-hash-table :test 'eq)
  "Symbols whose switch state handler has been registered this session.
The settings registry registers its handlers at load, so queued toggles
always replay; customize covers arbitrary variables, so handlers are
registered when a variable first renders.  A toggle queued offline
against a variable this session has never rendered lands unapplied —
the documented cost of not enumerating every defcustom up front.")

(defun jetpacs-customize--watch (sym)
  (unless (gethash sym jetpacs-customize--watched)
    (puthash sym t jetpacs-customize--watched)
    (jetpacs-settings-watch-toggle sym (concat "custom/" (symbol-name sym)))))

(defun jetpacs-customize--var-item (sym)
  "SYM as a native settings card dispatching customize.* actions."
  (if (not (boundp sym))
      ;; Autoloaded defcustom whose library isn't loaded: no type
      ;; schema to render a control from yet.
      (jetpacs-card
       (jetpacs-text (symbol-name sym) :style "label")
       (jetpacs-text "Not loaded — tap to load its library" :style "caption")
       :on-tap (jetpacs-action "customize.load"
                               :args `(:name ,(symbol-name sym))
                               :when-offline "drop"))
    (jetpacs-customize--watch sym)
    (jetpacs-card (jetpacs-settings-item
                   sym
                   :id-prefix "custom/"
                   :set-action "customize.set"
                   :reset-action "customize.reset"))))

(defun jetpacs-customize--group-card (sym)
  "A tappable card descending into group SYM."
  (let ((doc (get sym 'group-documentation)))
    (jetpacs-card
     (jetpacs-row
      (jetpacs-with-attrs
       (apply #'jetpacs-column
              (delq nil
                    (list (jetpacs-text (symbol-name sym) :style "label")
                          (when doc
                            (jetpacs-text (car (split-string doc "\n"))
                                          :style "caption")))))
       :weight 1)
      (jetpacs-icon "chevron_right"))
     :on-tap (jetpacs-action "customize.browse"
                             :args `(:group ,(symbol-name sym))
                             :when-offline "drop"))))

(defun jetpacs-customize--crumbs ()
  "Breadcrumbs: link-styled ancestors, bold current; taps pop back."
  (let ((current (jetpacs-customize--group)))
    (jetpacs-rich-text
     (cl-loop for g in jetpacs-customize--path
              for i from 0
              unless (zerop i) collect (jetpacs-span " › ")
              collect
              (if (eq g current)
                  (jetpacs-span (capitalize (symbol-name g))
                                :font-weight "bold")
                (jetpacs-span (capitalize (symbol-name g))
                              :on-tap (jetpacs-action
                                       "customize.browse"
                                       :args `(:group ,(symbol-name g))
                                       :when-offline "drop"))))
     :style "body")))

(defun jetpacs-customize--cap-note (total what)
  (when (> total jetpacs-customize-max-items)
    (list (jetpacs-text
           (format "Showing %d of %d %s — narrow with the search."
                   jetpacs-customize-max-items total what)
           :style "caption"))))

(defun jetpacs-customize--group-nodes ()
  "The browse view: breadcrumbs, subgroup cards, variable items."
  (pcase-let* ((group (jetpacs-customize--group))
               (`(,groups ,vars ,faces) (jetpacs-customize--members group))
               (doc (get group 'group-documentation)))
    (append
     (list (jetpacs-customize--crumbs))
     (when doc
       (list (jetpacs-text (car (split-string doc "\n")) :style "caption")))
     (when groups
       (append
        (list (jetpacs-section-header (format "Groups (%d)" (length groups))))
        (mapcar #'jetpacs-customize--group-card
                (cl-subseq groups 0 (min (length groups)
                                         jetpacs-customize-max-items)))
        (jetpacs-customize--cap-note (length groups) "groups")))
     (when vars
       (append
        (list (jetpacs-section-header
               (format "Variables (%d)" (length vars))))
        (mapcar #'jetpacs-customize--var-item
                (cl-subseq vars 0 (min (length vars)
                                       jetpacs-customize-max-items)))
        (jetpacs-customize--cap-note (length vars) "variables")))
     (when faces
       (list (jetpacs-text (format "%d face%s — edit faces in Emacs"
                                   (length faces)
                                   (if (= (length faces) 1) "" "s"))
                           :style "caption")))
     (unless (or groups vars faces)
       (list (jetpacs-empty-state :icon "tune" :title "Nothing here"
                                  :caption
                                  "This group declares no members."))))))

(defun jetpacs-customize--flat-nodes ()
  "The search/modified view: a flat, capped list of variable items."
  (let* ((syms (jetpacs-customize--flat-vars))
         (total (length syms)))
    (if (null syms)
        (list (jetpacs-empty-state
               :icon "search" :title "No matching variables"
               :caption "Search matches customizable variable names."))
      (append
       (list (jetpacs-text (format "%d variable%s" total
                                   (if (= total 1) "" "s"))
                           :style "caption"))
       (mapcar #'jetpacs-customize--var-item
               (cl-subseq syms 0 (min total jetpacs-customize-max-items)))
       (jetpacs-customize--cap-note total "variables")))))

(defun jetpacs-customize--view ()
  ;; A scaffold so chrome docks the view switcher; lazy_column, not
  ;; column: a plain column taller than the screen is unreachable
  ;; below the fold.
  (jetpacs-scaffold
   :body
   (apply #'jetpacs-lazy-column
         (append
          (list
           (jetpacs-row
            (unless (and (null (cdr jetpacs-customize--path))
                         (not (jetpacs-customize--flat-p)))
              (jetpacs-icon-button "arrow_back"
                                   (jetpacs-action "customize.up"
                                                   :when-offline "drop")
                                   :content-description "Up one level"))
            (jetpacs-text "Customize" :style "title"))
           ;; The framing: Settings is the curated experience; this
           ;; browser is the escape hatch to everything else, and
           ;; "everything else" is desktop-oriented.
           (jetpacs-text
            (concat "These are desktop Emacs's own options — many won't "
                    "affect the phone experience. Curated options live "
                    "in Settings.")
            :style "caption")
           (jetpacs-text-input "customize-search"
                               :value jetpacs-customize--search
                               :label "Search all variables" :single-line t
                               :on-submit (jetpacs-action "customize.search"))
           (jetpacs-flow-row
            (jetpacs-chip "Modified"
                          :selected jetpacs-customize--modified-only
                          :on-tap (jetpacs-action "customize.modified-filter"
                                                  :when-offline "drop"))))
          (if (jetpacs-customize--flat-p)
              (jetpacs-customize--flat-nodes)
            (jetpacs-customize--group-nodes))))))

(defun jetpacs-customize--refresh ()
  "Re-push the browser surface (deferred; safe from dispatch)."
  (jetpacs-flow-continue
   (lambda ()
     (ignore-errors (jetpacs-shell-push jetpacs-customize-surface)))))

;;;; Actions

(defun jetpacs-customize--action-show (args _params)
  "Open the browser, optionally at :group; else resume where it was."
  (let* ((name (plist-get args :group))
         (sym (and (stringp name) (intern-soft name))))
    (when (jetpacs-customize--group-p sym)
      (setq jetpacs-customize--path (if (eq sym 'emacs) '(emacs)
                                      (list 'emacs sym))
            jetpacs-customize--search ""
            jetpacs-customize--modified-only nil)))
  (jetpacs-customize--refresh)
  'accepted)

(defun jetpacs-customize--action-browse (args _params)
  (let* ((name (plist-get args :group))
         (sym (and (stringp name) (intern-soft name))))
    (if (not (jetpacs-customize--group-p sym))
        'rejected
      (setq jetpacs-customize--search ""
            jetpacs-customize--modified-only nil
            jetpacs-customize--path
            (let ((at (cl-position sym jetpacs-customize--path)))
              (if at ; a breadcrumb tap: pop back to that depth
                  (cl-subseq jetpacs-customize--path 0 (1+ at))
                (append jetpacs-customize--path (list sym)))))
      (jetpacs-customize--refresh)
      'accepted)))

(defun jetpacs-customize--action-up (_args _params)
  "Dismiss the flat list first, then pop one group."
  (cond ((jetpacs-customize--flat-p)
         (setq jetpacs-customize--search ""
               jetpacs-customize--modified-only nil))
        ((cdr jetpacs-customize--path)
         (setq jetpacs-customize--path (butlast jetpacs-customize--path))))
  (jetpacs-customize--refresh)
  'accepted)

(defun jetpacs-customize--action-search (args _params)
  (let ((q (plist-get args :value)))
    (setq jetpacs-customize--search
          (downcase (string-trim (or (and (stringp q) q) "")))))
  (jetpacs-customize--refresh)
  'accepted)

(defun jetpacs-customize--action-modified-filter (_args _params)
  (setq jetpacs-customize--modified-only
        (not jetpacs-customize--modified-only))
  (jetpacs-customize--refresh)
  'accepted)

(defun jetpacs-customize--action-load (args _params)
  (let* ((name (plist-get args :name))
         (sym (and (stringp name) (intern-soft name))))
    (if (not (and sym (custom-variable-p sym)))
        'rejected
      (condition-case err
          (custom-load-symbol sym)
        (error (jetpacs-toast (error-message-string err))))
      (jetpacs-customize--refresh)
      'accepted)))

(defun jetpacs-customize--action-set (args _params)
  (let* ((name (plist-get args :name))
         (sym (and (stringp name) (intern-soft name))))
    (if (not (and sym (custom-variable-p sym)))
        'rejected
      ;; A deferred defcustom must load before its type can validate.
      (ignore-errors (custom-load-symbol sym))
      (jetpacs-settings-apply-wire sym (plist-get args :value))
      (jetpacs-customize--refresh)
      'accepted)))

(defun jetpacs-customize--action-reset (args _params)
  (let* ((name (plist-get args :name))
         (sym (and (stringp name) (intern-soft name))))
    (if (not (and sym (custom-variable-p sym)))
        'rejected
      (jetpacs-settings-reset sym)
      (jetpacs-customize--refresh)
      'accepted)))

(with-jetpacs-owner "jetpacs.customize"
  (jetpacs-chrome-define-root jetpacs-customize-surface "home"
                              (lambda (_back) (jetpacs-customize--view))))
(jetpacs-defaction "customize.show" #'jetpacs-customize--action-show)
(jetpacs-defaction "customize.browse" #'jetpacs-customize--action-browse)
(jetpacs-defaction "customize.up" #'jetpacs-customize--action-up)
(jetpacs-defaction "customize.search" #'jetpacs-customize--action-search)
(jetpacs-defaction "customize.modified-filter"
                   #'jetpacs-customize--action-modified-filter)
(jetpacs-defaction "customize.load" #'jetpacs-customize--action-load)
(jetpacs-defaction "customize.set" #'jetpacs-customize--action-set)
(jetpacs-defaction "customize.reset" #'jetpacs-customize--action-reset)

;; Entry: a card in the settings screen leading here.
(jetpacs-settings-add-link
 20 (lambda ()
      (jetpacs-card
       (jetpacs-row
        (jetpacs-icon "tune")
        (jetpacs-with-attrs
         (jetpacs-column
          (jetpacs-text "Customize" :style "label")
          (jetpacs-text "Browse and edit any Emacs option" :style "caption"))
         :weight 1)
        (jetpacs-icon "chevron_right"))
       :on-tap (jetpacs-action "customize.show" :when-offline "drop"))))

(provide 'jetpacs-customize)
;;; jetpacs-customize.el ends here