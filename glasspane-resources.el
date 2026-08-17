;;; glasspane-resources.el --- PARA Resources route into Files -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; PA-2c of docs/PLAN-glasspane-para.md.  Resources is a Glasspane name
;; and starting-scope opinion over Jetpacs' native Files app.  It owns no
;; browser, screen, file walk, or path policy: both verbs delegate directly
;; to the public Files opener on the canonical Files surface.  The module is
;; staged until PA-3 adds Resources to Glasspane's persistent navigation.

;;; Code:

(require 'org)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-files)

(defun glasspane-resources--files-surface ()
  "Return the canonical Jetpacs Files surface."
  (jetpacs-shell-surface-for jetpacs-files-owner))

(defun glasspane-resources--open-path (path)
  "Open PATH through Jetpacs Files and return its action status.
Files owns containment validation, browsing, document hosting, and every
resulting operation; this downstream wrapper deliberately adds no policy."
  (jetpacs-files-open-path path (glasspane-resources--files-surface)))

(defun glasspane-resources--on-open (_args _params)
  "Open `org-directory' as the PARA Resources landing scope."
  (glasspane-resources--open-path org-directory))

(defun glasspane-resources--on-open-file (args _params)
  "Open ARGS' `:path' through the same native Files route."
  (glasspane-resources--open-path (plist-get args :path)))

(defconst glasspane-resources--verbs
  '("resources.open" "resources.open-file")
  "The staged Resources verbs owned by this module.")

(defun glasspane-resources-register ()
  "Register the staged Resources delegation verbs, idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "resources.open" #'glasspane-resources--on-open
                       :doc "Open the Org vault in native Jetpacs Files")
    (jetpacs-defaction
     "resources.open-file" #'glasspane-resources--on-open-file
     :doc "Open one path in native Jetpacs Files"
     :args '((:name path :type "text" :required t)))))

(defun glasspane-resources-unregister ()
  "Drop every verb owned by the Resources module."
  (dolist (name glasspane-resources--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-resources)
;;; glasspane-resources.el ends here
