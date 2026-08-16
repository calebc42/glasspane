;;; jetpacs.el --- Emacs UI on an Android companion -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: Caleb Cushing
;; Maintainer: Caleb Cushing
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: comm, tools
;; URL: https://github.com/calebc42/jetpacs

;;; Commentary:

;; This is the one public loading entry point for package-manager users and
;; the Companion's bundled offline installation alike:
;;
;;   (package-vc-install
;;    '(jetpacs :url "https://github.com/calebc42/jetpacs"
;;              :lisp-dir "emacs"))
;;   (require 'jetpacs)

;;; Code:

;; Package activation adds only the package's Lisp root to `load-path'.
;; Jetpacs apps are intentionally kept in separate directories, so make those
;; directories available before package.el byte-compiles the installed tree.
;;;###autoload
(let* ((jetpacs-package-directory
        (file-name-directory
         (or load-file-name (locate-library "jetpacs"))))
       (jetpacs-apps-directory
        (and jetpacs-package-directory
             (expand-file-name "apps" jetpacs-package-directory))))
  (when (file-directory-p jetpacs-apps-directory)
    (dolist (directory
             (directory-files jetpacs-apps-directory t
                              directory-files-no-dot-files-regexp))
      (when (file-directory-p directory)
        (add-to-list 'load-path directory)))))

;; `require' forms are evaluated while a file is byte-compiled.  Compiling or
;; installing Jetpacs must not start the application; loading this entry point
;; at runtime should.
(unless (bound-and-true-p byte-compile-current-file)
  (require 'jetpacs-init))

(provide 'jetpacs)
;;; jetpacs.el ends here
