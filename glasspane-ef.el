;;; glasspane-ef.el --- Ef-themes control screen -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; A Glasspane screen for Prot's ef-themes — the "colorful" companion to
;; the austere modus themes.  Unlike modus, ef-themes ship as a
;; third-party package rather than inside Emacs, so this lives in the
;; app tier (an opinion Glasspane offers) even though the scaffold it
;; instantiates is foundation now (jetpacs-theme-picker, the §3 step-3
;; promotion) — ef-themes is in the APP's package set, and app-tier is
;; where a package opinion belongs.  It offers:
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
;; Everything reads ef-themes through its public API, so the screen
;; tracks whatever ef-themes version the user has installed and degrades
;; to an install prompt when ef-themes is absent.
;;
;; G8 port of v1 glasspane-ef.el (docs/PLAN-glasspane-app.md).  Retired
;; against v1, per the plan's retirement list:
;;  - The overlay machinery — the `glasspane-ef--open' flag, the
;;    `:when'/`:overlay'/`:order' view registration, and the
;;    view-switched close hook: the screen is ONE
;;    `jetpacs-chrome-push-screen' and the chrome stack owns its
;;    lifecycle (S1).
;;  - The `jetpacs-connected-p' fboundp probe in the entry command:
;;    hard dep in v3 (T5).
;; Rewrites:
;;  - `jetpacs-theme-mode' `emacs' → `mirror' (T2); jetpacs-theme is a
;;    hard require, so ef.mirror needs no boundp guard.
;;  - v1's `jetpacs-settings-watch-toggle' registration for the style
;;    switches is REPLACED by an `:on-change' action (`ef.option'):
;;    v3 state watches key on (surface . id) and this screen pushes on
;;    whatever surface the user tapped from — the Settings root or the
;;    app's own — so a watch pinned to one owner surface would lose the
;;    other's toggles.  The glasspane-detail Properties switch is the
;;    in-tree precedent.  Registered handlers still replay a toggle
;;    queued offline before the screen first renders.
;;  - Every handler answers a SPEC 14.4 status (S4); a failed or
;;    unknown load answers `rejected', never a swallowed `accepted'.
;;  - The Settings satellite link is a chrome row at order 81, right
;;    after the app's own settings link (80) — v1's anchor (the core
;;    Modus link at 25) does not exist in v3.

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
  "A human-friendly label for THEME: drop the `ef-' prefix, then
title-case, so `ef-melissa-dark' reads as \"Melissa Dark\"."
  (jetpacs-theme-picker-display-name "ef-" theme))

(defun glasspane-ef--current-card (current)
  "The header card: the active theme's name, polarity, palette, mirror status."
  (jetpacs-theme-picker-current-card current
                                       :display-fn #'symbol-name
                                       :dark-p-fn #'glasspane-ef--dark-p
                                       :color-fn #'glasspane-ef--color
                                       :mirror-action "ef.mirror"
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
  "The theme picker: cards grouped Light then Dark."
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
The install tap exists only while the packages rung's verb is live —
its handler-table entry is the capability probe, so the button never
dispatches into the action shim's `rejected' (the srs install-body
precedent)."
  (let ((installable (gethash "glasspane.packages.install"
                              jetpacs-action-handlers)))
    (jetpacs-empty-state
     :icon "colorize"
     :title "ef-themes isn't installed yet"
     :caption "It installs automatically on a connected device (with the app's other packages)."
     :action-label (when installable "Install")
     :on-tap (when installable
               (jetpacs-action "glasspane.packages.install")))))

(defun glasspane-ef-screen (back)
  "The pushed Ef Themes screen; back returns to wherever the user was."
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
  "Push the Ef Themes screen onto the tapped surface."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       ;; A deferred `jetpacs-chrome-push-screen' must catch its own
       ;; re-signal or a refused gate dies in a timer.
       (condition-case err
           (jetpacs-chrome-push-screen surface "glasspane-ef"
                                       #'glasspane-ef-screen)
         (error (message "glasspane: ef push failed: %s"
                         (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-ef--on-load (args params)
  "Load the ef theme named by `:theme'."
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
  (glasspane-ef--surprise 'ef-themes-load-random params))

(defun glasspane-ef--on-random-dark (_args params)
  (glasspane-ef--surprise 'ef-themes-load-random-dark params))

(defun glasspane-ef--on-random-light (_args params)
  (glasspane-ef--surprise 'ef-themes-load-random-light params))

(defun glasspane-ef--on-mirror (_args params)
  "Flip the companion into mirror mode.
`jetpacs-settings-apply' validates against the defcustom's choice type
and persists; the mode's own `:set' pushes the current theme on a live
connection."
  (if (jetpacs-settings-apply 'jetpacs-theme-mode 'mirror)
      (progn (jetpacs-app-defer-refresh params)
             'accepted)
    'rejected))

(defun glasspane-ef--on-option (args params)
  "Set the style option named by `:name' to the switch's injected `:value'."
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

(defun glasspane-ef--settings-link ()
  "The Settings-root satellite row leading to the Ef Themes screen.
Satellite screens live in Settings, not the drawer (the drawer-UX
rule, unchanged from v1)."
  (jetpacs-chrome-row "Ef Themes"
                      :subtitle "Pick, preview, and tune the colorful ef-themes"
                      :icon "colorize"
                      :on-tap (jetpacs-action "ef.show")
                      :key "glasspane-ef-link"))

(defun glasspane-ef-register ()
  "Register the ef verbs and the Settings satellite link.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent: re-registration replaces handlers in
place and the link is re-added exactly once."
  ;; :any-surface — D1 GLOBAL verbs, deliberately: the only way in is
  ;; the satellite row on the Settings root, a surface Settings owns,
  ;; and the screen then pushes onto whatever surface was tapped (the
  ;; Commentary's watch-vs-action rationale) — so EVERY tap this file
  ;; handles arrives on a foreign surface, and the owned-surface gate
  ;; would reject it before the handler ran (the clock precedent).
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "ef.show" #'glasspane-ef--on-show
                       :any-surface t
                       :doc "Push the Ef Themes screen")
    (jetpacs-defaction "ef.load" #'glasspane-ef--on-load
                       :any-surface t
                       :doc "Load the named ef theme")
    (jetpacs-defaction "ef.random" #'glasspane-ef--on-random
                       :any-surface t
                       :doc "Load a random ef theme")
    (jetpacs-defaction "ef.random-dark" #'glasspane-ef--on-random-dark
                       :any-surface t
                       :doc "Load a random dark ef theme")
    (jetpacs-defaction "ef.random-light" #'glasspane-ef--on-random-light
                       :any-surface t
                       :doc "Load a random light ef theme")
    (jetpacs-defaction "ef.mirror" #'glasspane-ef--on-mirror
                       :any-surface t
                       :doc "Mirror the Emacs theme onto the companion")
    (jetpacs-defaction "ef.option" #'glasspane-ef--on-option
                       :any-surface t
                       :doc "Set an ef style option from its switch")
    (setq jetpacs-settings-links
          (cl-remove #'glasspane-ef--settings-link jetpacs-settings-links
                     :key #'cadr))
    ;; Right after the app's own settings link (order 80): the two
    ;; Glasspane rows sit together, the v3 reading of v1's
    ;; next-to-Modus placement.
    (jetpacs-settings-add-link 81 #'glasspane-ef--settings-link)))

(defun glasspane-ef-unregister ()
  "Drop the ef verbs and the Settings satellite link."
  (dolist (name glasspane-ef--verbs)
    (jetpacs-undefaction name))
  (setq jetpacs-settings-links
        (cl-remove #'glasspane-ef--settings-link jetpacs-settings-links
                   :key #'cadr)))

;;;###autoload
(defun glasspane-ef-open ()
  "Open the Ef Themes screen on the connected phone.
Disconnected, the push is kept and renders on the next connection —
chrome keeps the stack mutation; nil from the push is not failure."
  (interactive)
  (jetpacs-chrome-push-screen "glasspane" "glasspane-ef"
                              #'glasspane-ef-screen)
  (message (if (jetpacs-connected-p)
               "Ef Themes opened on the phone"
             "Ef Themes staged — it renders when a phone connects")))

(provide 'glasspane-ef)
;;; glasspane-ef.el ends here
