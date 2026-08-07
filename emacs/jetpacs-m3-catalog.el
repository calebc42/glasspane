;;; jetpacs-m3-catalog.el --- The Material 3 Compose Catalog -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The Material 3 Compose Catalog -- the Jetpacs component vocabulary.
;; A Tier-1 application recreating upstream's Compose Material 3
;; Expressive Catalog (resources/android/Compose-Material-3-Expressive-
;; Catalog) entirely in Elisp: 41 components, 279 examples, three
;; screens deep.  Material 3 is not a theme this app demonstrates; it
;; is the design language Jetpacs IS (docs/ARCHITECTURE-POC3.md).
;;
;; This file is the ENTRY POINT and nothing else -- the model, the
;; screens and the verbs live in `jetpacs-m3-core', and each component
;; is its own `apps/m3-catalog/jetpacs-m3-<slug>.el' module, required
;; below in the upstream `Components' order (which is the order Home
;; lists them in).  A module registers itself by calling
;; `jetpacs-m3-defcomponent' at load time, so requiring it IS the
;; registration; re-evaluating one live replaces its entry in place.
;;
;; Reach it from the launcher, or M-x jetpacs-m3-catalog.

;;; Code:

;; The component modules live one directory down in the repo and FLAT
;; beside this file on the device (device/install.sh pushes every .el
;; into one /sdcard directory), so the entry is added only when it is
;; really there.
(eval-and-compile
  (let* ((here (or load-file-name buffer-file-name))
         (dir (and here (expand-file-name
                         "apps/m3-catalog" (file-name-directory here)))))
    (when (and dir (file-directory-p dir))
      (add-to-list 'load-path dir))))

(require 'jetpacs-m3-core)

(require 'jetpacs-m3-adaptive)
(require 'jetpacs-m3-badge)
(require 'jetpacs-m3-bottom-app-bar)
(require 'jetpacs-m3-bottom-sheet)
(require 'jetpacs-m3-buttons)
(require 'jetpacs-m3-button-groups)
(require 'jetpacs-m3-card)
(require 'jetpacs-m3-carousel)
(require 'jetpacs-m3-checkboxes)
(require 'jetpacs-m3-chips)
(require 'jetpacs-m3-date-pickers)
(require 'jetpacs-m3-dialogs)
(require 'jetpacs-m3-extended-fab)
(require 'jetpacs-m3-floating-action-buttons)
(require 'jetpacs-m3-fab-menu)
(require 'jetpacs-m3-floating-toolbar)
(require 'jetpacs-m3-icon-buttons)
(require 'jetpacs-m3-lists)
(require 'jetpacs-m3-loading-indicators)
(require 'jetpacs-m3-menus)
(require 'jetpacs-m3-navigation-bar)
(require 'jetpacs-m3-navigation-drawer)
(require 'jetpacs-m3-navigation-rail)
(require 'jetpacs-m3-navigation-suite-scaffold)
(require 'jetpacs-m3-progress-indicators)
(require 'jetpacs-m3-pull-to-refresh-indicator)
(require 'jetpacs-m3-radio-buttons)
(require 'jetpacs-m3-search-bars)
(require 'jetpacs-m3-segmented-button)
(require 'jetpacs-m3-sliders)
(require 'jetpacs-m3-snackbars)
(require 'jetpacs-m3-split-button)
(require 'jetpacs-m3-switches)
(require 'jetpacs-m3-tabs)
(require 'jetpacs-m3-text-fields)
(require 'jetpacs-m3-time-picker)
(require 'jetpacs-m3-togglebuttons)
(require 'jetpacs-m3-tooltips)
(require 'jetpacs-m3-top-app-bar)
(require 'jetpacs-m3-material-shapes)
(require 'jetpacs-m3-swipe-to-dismiss)
(jetpacs-m3-register)
;; The Playground, AFTER the registration: it is not a component but a
;; section over all of them, and it reaches the Example screen through
;; the core's own seam rather than by the core knowing it exists.
(require 'jetpacs-m3-repl)

;;;###autoload
(defun jetpacs-m3-catalog ()
  "Open the Material 3 catalog on the device.
Resets to Home first, then re-opens the pinned screen when there is one
-- upstream `maybeNavigate', which pushes the Component screen before
the Example so back lands where the user expects."
  (interactive)
  (jetpacs-chrome-reset-screens jetpacs-m3-owner)
  (when-let* ((pinned jetpacs-m3-favorite))
    (cond
     ((string-prefix-p "c-" pinned)
      (jetpacs-m3-show-component (substring pinned 2)))
     ((string-match "\\`e-\\(.*\\)-\\([0-9]+\\)\\'" pinned)
      (let ((id (match-string 1 pinned))
            (index (string-to-number (match-string 2 pinned))))
        (jetpacs-m3-show-component id)
        (jetpacs-m3-show-example id index)))
     ((equal pinned "theme") (jetpacs-m3-show-theme)))))

(defun jetpacs-m3-catalog-unload-function ()
  "Unload hygiene: drop the verbs and the chrome root."
  (jetpacs-m3-unregister)
  nil)

(provide 'jetpacs-m3-catalog)
;;; jetpacs-m3-catalog.el ends here
