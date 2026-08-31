;;; glasspane-ef.el --- Ef-themes control screen -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Glasspane's optional screen for Prot's ef-themes, the colorful companion
;; to the built-in Modus themes.  EF implements the Modus semantic palette API,
;; so Glasspane contributes it to Jetpacs' Modus-family Theme Settings registry
;; while retaining ownership of the package policy, actions, and screen.  It
;; offers:
;;
;;  - a light/dark grouped picker, each row previewing a theme's
;;    background and identity accent as swatches; the active theme is
;;    marked, a tap loads another (`ef-themes-load-theme');
;;  - the current theme's palette strip;
;;  - "Random", "Random dark", "Random light" — ef-themes' surprise-me
;;    loaders;
;;  - the everyday style options (bold, italic, mixed fonts,
;;    variable-pitch UI) as switches, each reloading the theme so the
;;    change shows at once.
;;
;; ef-themes 2.0+ are built on the modus 5.0 palette API, so an ef theme
;; is a registered modus derivative: the theme mirror
;; (`jetpacs-theme-mode' `mirror') already reflects it faithfully onto
;; the companion, reading its semantic roles.  When mirroring is on,
;; switching a theme here re-pushes it; when it is off, a one-tap
;; "Mirror on phone" flips it.
;;
;; Everything reads ef-themes through its public API, so the screen tracks
;; the installed provider version and delegates installation to Glasspane's
;; package module when it is absent.  The Theme Settings row is the only
;; cross-surface opener; once pushed as a sanctioned guest, its controls remain
;; owner-scoped.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-settings)
(require 'jetpacs-theme)
(require 'jetpacs-theme-picker)
(require 'jetpacs-modus)

;; ef-themes is an optional runtime dependency loaded on demand; every
;; use is guarded, and the `ext:' pseudo-file keeps the error-on-warn
;; byte-compile honest with the package absent.
(declare-function ef-themes-get-color-value "ext:ef-themes"
                  (color &optional with-overrides theme))
(declare-function ef-themes-load-theme "ext:ef-themes" (theme &optional hook))
(declare-function ef-themes-load-random "ext:ef-themes" (&optional variant))
(declare-function ef-themes-load-random-dark "ext:ef-themes" ())
(declare-function ef-themes-load-random-light "ext:ef-themes" ())
(defvar ef-themes-items)

;;;; Availability and loading

(defun glasspane-ef--available-p ()
  "Non-nil when the ef-themes package is installed in this Emacs."
  (and (seq-some (lambda (theme)
                   (string-prefix-p "ef-" (symbol-name theme)))
                 (custom-available-themes))
       t))

(defun glasspane-ef--ensure ()
  "Load the ef-themes library; non-nil on success.
ef-themes is a package, so a plain `require' finds it once the package
system has initialised; `require-theme' is the fallback for the case
where only its theme directory is on the load path."
  (or (featurep 'ef-themes)
      (require 'ef-themes nil t)
      (and (ignore-errors (require-theme 'ef-themes t))
           (featurep 'ef-themes))))

;;;; Theme queries

(defun glasspane-ef--themes ()
  "The list of selectable ef themes."
  (and (boundp 'ef-themes-items) ef-themes-items))

(defun glasspane-ef--current ()
  "The active ef theme symbol, or nil."
  (let ((known (glasspane-ef--themes)))
    (seq-find (lambda (theme) (memq theme known)) custom-enabled-themes)))

(defun glasspane-ef--dark-p (theme)
  "Non-nil when THEME is a dark ef theme.
ef derivatives register a `:background-mode' theme property (the modus
5.0 API), so this needs no name-guessing."
  (eq (plist-get (get theme 'theme-properties) :background-mode) 'dark))

(defun glasspane-ef--color (key &optional theme)
  "Hex value of ef palette KEY for THEME (or the current theme), or nil."
  (when (fboundp 'ef-themes-get-color-value)
    (let ((value (ignore-errors
                   (if theme
                       (ef-themes-get-color-value key nil theme)
                     (ef-themes-get-color-value key :with-overrides)))))
      (and (stringp value) value))))

;;;; View sections (the shared scaffold, instantiated for ef)

(defun glasspane-ef--display-name (theme)
  "Return a human-friendly label for THEME.
Drop the `ef-' prefix, then title-case, so `ef-melissa-dark' reads as
\"Melissa Dark\"."
  (jetpacs-theme-picker-display-name "ef-" theme))

(defun glasspane-ef--current-card (current)
  "Build CURRENT's header card with polarity, palette, and mirror status."
  (jetpacs-theme-picker-current-card current
                                       :display-fn #'symbol-name
                                       :dark-p-fn #'glasspane-ef--dark-p
                                       :color-fn #'glasspane-ef--color
                                       :mirror-action "ef.mirror"
                                       :theme-mode jetpacs-theme-mode
                                       :none-label "No ef theme active"))

(defun glasspane-ef--actions-row ()
  "The surprise-me loaders ef-themes is known for."
  (jetpacs-row
   (jetpacs-button "Random" (jetpacs-action "ef.random")
                   :icon "shuffle" :variant "tonal")
   (jetpacs-button "Random dark" (jetpacs-action "ef.random-dark")
                   :icon "dark_mode" :variant "tonal")
   (jetpacs-button "Random light" (jetpacs-action "ef.random-light")
                   :icon "light_mode" :variant "tonal")))

(defun glasspane-ef--themes-section (current)
  "Build the theme picker around CURRENT, grouped Light then Dark."
  (jetpacs-theme-picker-themes-section (glasspane-ef--themes) current
                                         :dark-p-fn #'glasspane-ef--dark-p
                                         :display-fn #'glasspane-ef--display-name
                                         :color-fn #'glasspane-ef--color
                                         :load-action "ef.load"))

(defconst glasspane-ef--options
  '((ef-themes-bold-constructs    . "Bold keywords")
    (ef-themes-italic-constructs  . "Italic comments")
    (ef-themes-mixed-fonts        . "Mixed fonts in code")
    (ef-themes-variable-pitch-ui  . "Variable-pitch UI"))
  "Ef style options exposed as switches, each with a friendly label.
Presence here is what authorizes `ef.option' for a symbol.")

(defun glasspane-ef--style-section ()
  "The style options as switch cards.
ef-themes' options carry no reified `custom-type', so the switch
renders directly rather than through `jetpacs-settings-item' (which
classifies by type); each switch re-seeds `:checked' from the live
variable every render (S2) and dispatches `ef.option' on change."
  (cons
   (jetpacs-section-header "Style")
   (mapcar (lambda (opt)
             (let ((sym (car opt)) (label (cdr opt)))
               (jetpacs-card
                (if (boundp sym)
                    (jetpacs-switch (concat "ef-opt/" (symbol-name sym))
                                    :checked (jetpacs-bool (symbol-value sym))
                                    :label label
                                    :on-change
                                    (jetpacs-action
                                     "ef.option"
                                     :args (list :name (symbol-name sym))))
                  (jetpacs-text (concat label " — not available")
                                :style "caption")))))
           glasspane-ef--options)))

(defun glasspane-ef--body ()
  "The screen body, assuming the ef-themes library is loaded."
  (let ((current (glasspane-ef--current)))
    (apply #'jetpacs-lazy-column
           (delq nil
                 (append
                  (list (glasspane-ef--current-card current)
                        (glasspane-ef--actions-row))
                  (glasspane-ef--themes-section current)
                  (glasspane-ef--style-section)
                  (list (jetpacs-theme-picker-more-link "ef-themes")))))))

(defun glasspane-ef--not-installed ()
  "The ef-themes-absent placeholder.
The install affordance exists only while Glasspane's package action is live."
  (let ((available (gethash "glasspane.packages.install"
                            jetpacs-action-handlers)))
    (jetpacs-empty-state
     :icon "colorize"
     :title "ef-themes isn't installed yet"
     :caption "Install it with Glasspane's other optional Emacs packages."
     :action-label (when available "Install")
     :on-tap (when available
               (jetpacs-action "glasspane.packages.install")))))

(defun glasspane-ef-screen (back)
  "Build the pushed Ef Themes screen with BACK as its return target."
  (jetpacs-chrome-screen
   "Ef Themes"
   (if (glasspane-ef--ensure)
       (glasspane-ef--body)
     (glasspane-ef--not-installed))
   :back back))

;;;; Live re-apply

(defun glasspane-ef--reload (&rest _)
  "Reload the active ef theme so a just-changed option takes effect.
The reload also drives `enable-theme-functions', re-pushing the mirror
when `jetpacs-theme-mode' is `mirror'.  Hook-safe arity: doubles as a
`jetpacs-settings-apply' after-set."
  (when-let* ((theme (glasspane-ef--current)))
    (when (fboundp 'ef-themes-load-theme)
      (ignore-errors (ef-themes-load-theme theme)))))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-ef--on-show (_args params)
  "Push the Ef Themes screen onto the surface named by PARAMS."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       ;; A deferred `jetpacs-chrome-push-screen' must catch its own
       ;; re-signal or a refused gate dies in a timer.
       (condition-case err
           (jetpacs-chrome-push-screen surface "glasspane-ef"
                                       #'glasspane-ef-screen)
         (error (message "glasspane-ef: push failed: %s"
                         (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-ef--on-load (args params)
  "Load the ef theme named by `:theme' in ARGS, then refresh via PARAMS."
  (let* ((name (plist-get args :theme))
         (sym (and (stringp name) (intern-soft name)))
         (surface (plist-get params :surface)))
    (cond
     ((not (stringp name)) 'rejected)
     ((not (glasspane-ef--ensure))
      (jetpacs-shell-notify "ef-themes is not installed" surface)
      'rejected)
     ((not (and sym (memq sym (glasspane-ef--themes))))
      (jetpacs-shell-notify (format "Unknown ef theme: %s" name) surface)
      'rejected)
     (t
      (condition-case err
          (progn
            (ef-themes-load-theme sym)
            (jetpacs-app-defer-refresh params)
            'accepted)
        (error
         (jetpacs-shell-notify (format "Ef theme: %s"
                                       (jetpacs-error-label err))
                               surface)
         'rejected))))))

(defun glasspane-ef--surprise (loader params)
  "Run surprise-me LOADER (an ef-themes random function) and refresh.
PARAMS supplies the invoking surface and deferred refresh context.
The SPEC 14.4 status for the three random verbs: `rejected' when the
package (or this version's LOADER) is absent or the load signals —
never a swallowed `accepted' (the G7 engine-wrapper lesson)."
  (if (not (and (glasspane-ef--ensure) (fboundp loader)))
      (progn
        (jetpacs-shell-notify "ef-themes is not installed"
                              (plist-get params :surface))
        'rejected)
    (condition-case err
        (progn
          (funcall loader)
          (jetpacs-app-defer-refresh params)
          'accepted)
      (error
       (jetpacs-shell-notify (format "Ef theme: %s" (jetpacs-error-label err))
                             (plist-get params :surface))
       'rejected))))

(defun glasspane-ef--on-random (_args params)
  "Load any random ef theme and refresh via PARAMS."
  (glasspane-ef--surprise 'ef-themes-load-random params))

(defun glasspane-ef--on-random-dark (_args params)
  "Load a random dark ef theme and refresh via PARAMS."
  (glasspane-ef--surprise 'ef-themes-load-random-dark params))

(defun glasspane-ef--on-random-light (_args params)
  "Load a random light ef theme and refresh via PARAMS."
  (glasspane-ef--surprise 'ef-themes-load-random-light params))

(defun glasspane-ef--on-mirror (_args params)
  "Flip the companion into mirror mode.
PARAMS supplies the deferred refresh context.
`jetpacs-settings-apply' validates against the defcustom's choice type
and persists; the mode's own `:set' pushes the current theme on a live
connection."
  (if (jetpacs-settings-apply 'jetpacs-theme-mode 'mirror)
      (progn (jetpacs-app-defer-refresh params)
             'accepted)
    'rejected))

(defun glasspane-ef--on-option (args params)
  "Apply the style option in ARGS, then refresh using PARAMS.
ARGS must name the option with `:name' and carry the switch's injected
`:value'."
  (let* ((name (plist-get args :name))
         (sym (and (stringp name) (intern-soft name)))
         (value (plist-get args :value)))
    (cond
     ((not (and sym (assq sym glasspane-ef--options))) 'rejected)
     ((not (memq value '(t :json-false))) 'rejected)
     ((not (boundp sym))
      (jetpacs-shell-notify "ef-themes is not installed"
                            (plist-get params :surface))
      'rejected)
     ((jetpacs-settings-apply sym (eq value t) #'glasspane-ef--reload)
      (jetpacs-app-defer-refresh params)
      'accepted)
     (t 'rejected))))

;;;; Registration

(defconst glasspane-ef--verbs
  '("ef.show" "ef.load" "ef.random" "ef.random-dark" "ef.random-light"
    "ef.mirror" "ef.option")
  "The verbs this module owns, for the register/unregister sweep.")

(defun glasspane-ef--theme-provider-link ()
  "Build Glasspane's EF row for the Modus-family Theme Settings screen."
  (jetpacs-chrome-row "Ef Themes"
                      :subtitle "Pick, preview, and tune"
                      :icon "colorize"
                      :on-tap (jetpacs-action "ef.show")
                      :key "glasspane-ef-themes-link"))

(defun glasspane-ef-register ()
  "Register Glasspane's EF verbs and Modus-family Theme Settings row.
Called from `glasspane-register'.  Re-registration replaces handlers and the
provider contribution in place."
  (with-jetpacs-owner "glasspane"
    ;; This opener is emitted by Jetpacs' Theme screen before the Glasspane
    ;; guest screen exists.  The push sanctions that guest; every inner action
    ;; then passes through screen-lifetime delegation.
    (jetpacs-defaction "ef.show" #'glasspane-ef--on-show
                       :any-surface t
                       :doc "Push the Ef Themes screen")
    (jetpacs-defaction "ef.load" #'glasspane-ef--on-load
                       :args '((:name theme :type "text" :required t))
                       :doc "Load the named ef theme")
    (jetpacs-defaction "ef.random" #'glasspane-ef--on-random
                       :doc "Load a random ef theme")
    (jetpacs-defaction "ef.random-dark" #'glasspane-ef--on-random-dark
                       :doc "Load a random dark ef theme")
    (jetpacs-defaction "ef.random-light" #'glasspane-ef--on-random-light
                       :doc "Load a random light ef theme")
    (jetpacs-defaction "ef.mirror" #'glasspane-ef--on-mirror
                       :doc "Mirror the Emacs theme onto the companion")
    (jetpacs-defaction "ef.option" #'glasspane-ef--on-option
                       :args '((:name name :type "text" :required t)
                               (:name value :type "bool" :required t))
                       :doc "Set an ef style option from its switch")
    (jetpacs-modus-register-theme-provider
     81 #'glasspane-ef--theme-provider-link)))

(defun glasspane-ef-unregister ()
  "Drop Glasspane's EF verbs and Theme Settings provider row."
  (dolist (name glasspane-ef--verbs)
    (jetpacs-undefaction name))
  (jetpacs-modus-unregister-theme-provider
   #'glasspane-ef--theme-provider-link))

;;;###autoload
(defun glasspane-ef-open ()
  "Open the Ef Themes screen on the connected phone.
Disconnected, the push is kept and renders on the next connection —
chrome keeps the stack mutation; nil from the push is not failure."
  (interactive)
  (with-jetpacs-owner "glasspane"
    (jetpacs-chrome-push-screen "glasspane"
                                "glasspane-ef"
                                #'glasspane-ef-screen))
  (message (if (jetpacs-connected-p)
               "Ef Themes opened on the phone"
             "Ef Themes staged — it renders when a phone connects")))

(provide 'glasspane-ef)
;;; glasspane-ef.el ends here
