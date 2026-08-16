;;; jetpacs-entry-test.el --- Public package entry point -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)

(defconst jetpacs-entry-test--temporary-home
  (make-temp-file "jetpacs-entry-test-" t))
(defconst jetpacs-entry-test--user-emacs-directory
  (file-name-as-directory
   (expand-file-name ".emacs.d" jetpacs-entry-test--temporary-home)))
(defconst jetpacs-entry-test--vault
  (file-name-as-directory
   (expand-file-name "my-vault" jetpacs-entry-test--temporary-home)))
(defconst jetpacs-entry-test--default-directory
  (file-name-as-directory jetpacs-entry-test--temporary-home))

(defun jetpacs-entry-test--actions (_surface)
  'custom-actions)

(defun jetpacs-entry-test--dock (_surface)
  'custom-dock)

;; This is the shape of an existing user's init immediately before its final
;; `(require 'jetpacs)'.  Package defaults must not replace any of it.
(setq user-emacs-directory jetpacs-entry-test--user-emacs-directory
      default-directory jetpacs-entry-test--default-directory
      jetpacs-vault-directory jetpacs-entry-test--vault
      org-directory (expand-file-name "existing-org" jetpacs-entry-test--vault)
      jetpacs-theme-mode 'dark
      jetpacs-clip-auto-refresh t
      jetpacs-apps-core-global-actions #'jetpacs-entry-test--actions
      jetpacs-apps-core-dock-items #'jetpacs-entry-test--dock)

(make-directory (expand-file-name "jetpacs" user-emacs-directory) t)
(with-temp-file (expand-file-name "jetpacs/user.el" user-emacs-directory)
  (insert "(setq jetpacs-entry-test--user-file-loaded t)\n"))

(require 'jetpacs)

(ert-deftest jetpacs-entry-require-preserves-existing-init-and-separates-state ()
  "The public entry loads anywhere on `load-path' without owning user config."
  (unwind-protect
      (progn
        (should (featurep 'jetpacs))
        (should (featurep 'jetpacs-init))
        (should (equal jetpacs-install-root
                       (expand-file-name "jetpacs/" user-emacs-directory)))
        (should (equal jetpacs-vault-directory jetpacs-entry-test--vault))
        (should (equal org-directory
                       (expand-file-name "existing-org"
                                         jetpacs-entry-test--vault)))
        (should (equal ebp-org-roots (jetpacs-files-effective-roots)))
        ;; Files may open Org documents anywhere in the selected Vault, not
        ;; only beneath `org-directory'.  Their structured actions must use
        ;; that same policy or the rendered menu becomes a dead affordance.
        (let ((outside-org (expand-file-name "vault-document.org"
                                             jetpacs-entry-test--vault)))
          (make-directory jetpacs-entry-test--vault t)
          (with-temp-file outside-org (insert "* Vault document\n"))
          (should (equal (ebp-org-file-allowed-p outside-org)
                         (file-truename outside-org))))
        (should (eq jetpacs-theme-mode 'dark))
        (should jetpacs-clip-auto-refresh)
        (should (eq jetpacs-apps-core-global-actions
                    #'jetpacs-entry-test--actions))
        (should (eq jetpacs-apps-core-dock-items
                    #'jetpacs-entry-test--dock))
        (should (equal default-directory
                       jetpacs-entry-test--default-directory))
        (should jetpacs-entry-test--user-file-loaded))
    (delete-directory jetpacs-entry-test--temporary-home t)))

(provide 'jetpacs-entry-test)
;;; jetpacs-entry-test.el ends here
