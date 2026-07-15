;;; glasspane.el --- Glasspane: the reference org app on Jetpacs -*- lexical-binding: t; -*-

;; The one-require entry point for the full reference app.  Pulls in the
;; Jetpacs core (transport, shell, renderers, editor bridge) plus every
;; Glasspane module (org views, clock notification, magit pie, package
;; browser, demo tour):
;;
;;   (require 'glasspane)
;;
;; The pre-built single-file bundle at the repo root carries the same
;; feature name, so init files work unchanged with either install option.

;;; Code:

(require 'glasspane-ui)
(require 'glasspane-source)
(require 'glasspane-agenda)
(require 'glasspane-capture)
(require 'glasspane-detail)
(require 'glasspane-search)
(require 'glasspane-table)
(require 'glasspane-journal)
(require 'glasspane-views)
(require 'glasspane-automations)
(require 'glasspane-notes)
(require 'glasspane-srs)
(require 'glasspane-gallery)
(require 'glasspane-config)
(require 'glasspane-packages)
(require 'glasspane-pack)

;; The app-managed defaults (capture templates, agenda wiring): under
;; the foundation flow (listed in ~/.emacs.d/jetpacs/apps.el) a missing
;; subtree is created — first boot on a device must yield a working
;; capture sheet and agenda.  Elsewhere this only loads what exists —
;; and either way init.el code after (require 'glasspane) still runs
;; later, so personal settings always win.
(glasspane-config-startup)

;; A device install also provisions the optional engines the starter
;; init used to install (org-ql, vulpea, org-srs): one idle attempt per
;; session, batch and desktop requires never reach for MELPA — see
;; glasspane-packages.el.
(glasspane-packages-maybe-auto-install)

(provide 'glasspane)
;;; glasspane.el ends here
