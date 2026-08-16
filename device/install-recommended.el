;;; install-recommended.el --- One-time local Jetpacs bootstrap -*- lexical-binding: t; -*-

;; The Companion prepares this file and payload in shared Documents.  Android
;; Emacs evaluates it from the small package-entry block in the user's
;; ~/.emacs.d/init.el.  Emacs itself creates the private bundled tree.

(require 'cl-lib)
(require 'subr-x)

(defvar jetpacs-bootstrap-vault-directory "/sdcard"
  "Vault used by the Recommended local bootstrap.")

(let* ((bootstrap-file (or load-file-name buffer-file-name))
       (kit-root (and bootstrap-file
                      (file-name-as-directory
                       (file-name-directory bootstrap-file))))
       (payload (and kit-root (expand-file-name "payload/" kit-root)))
       (dotdir (file-name-as-directory
                (expand-file-name user-emacs-directory)))
       (root (expand-file-name "jetpacs/" dotdir))
       (home (directory-file-name
              (file-name-directory (directory-file-name dotdir))))
       (vault (directory-file-name
               (expand-file-name jetpacs-bootstrap-vault-directory)))
       (required
        '("init.el" "emacs/ebp.el" "emacs/jetpacs-files.el"
          "org/org-mode-walkthrough")))
  (unless (and bootstrap-file kit-root payload)
    (error "Jetpacs could not locate its prepared installer"))
  (unless (and (file-name-absolute-p dotdir)
               (not (file-remote-p dotdir))
               (not (equal (directory-file-name dotdir) "/"))
               (equal root (expand-file-name "jetpacs/" dotdir)))
    (error "Jetpacs refuses unsafe user-emacs-directory: %s" dotdir))
  (dolist (relative required)
    (unless (file-exists-p (expand-file-name relative payload))
      (error "The prepared Jetpacs files are incomplete: missing %s" relative)))
  (unless (file-directory-p vault)
    (error "Jetpacs cannot use the /sdcard Vault until shared storage is available"))

  (cl-labels
      ((replace-tree
        (relative destination)
        (let* ((source (expand-file-name relative payload))
               (target (directory-file-name
                        (expand-file-name destination root)))
               (staged (concat target ".jetpacs-new")))
          (when (file-exists-p staged)
            (if (file-directory-p staged)
                (delete-directory staged t)
              (delete-file staged)))
          (copy-directory source staged nil t t)
          (when (file-exists-p target)
            (if (file-directory-p target)
                (delete-directory target t)
              (delete-file target)))
          (rename-file staged target)))
       (replace-file
        (relative destination)
        (let* ((source (expand-file-name relative payload))
               (target (expand-file-name destination root))
               (staged (concat target ".jetpacs-new")))
          (copy-file source staged t t)
          (rename-file staged target t))))
    (make-directory root t)
    ;; Only distribution-owned paths are refreshed.  apps/, apps.el, var/,
    ;; user.el, and migration/ belong to the installation and survive repair.
    (replace-tree "emacs/" "emacs/")
    (replace-tree "org/" "org/")
    (when (file-directory-p (expand-file-name "examples/" payload))
      (replace-tree "examples/" "examples/"))
    (replace-file "init.el" "init.el")
    (make-directory (expand-file-name "apps/" root) t)
    (make-directory (expand-file-name "var/" root) t)
    (make-directory (expand-file-name "org/" vault) t)
    (let ((receipt (expand-file-name "install.conf" root))
          (staged-receipt (expand-file-name "install.conf.jetpacs-new" root)))
      (with-temp-file staged-receipt
        (insert "format=3\n"
                "vault_mode=shared\n"
                "vault=" vault "\n"
                "home_mode=emacs\n"
                "home=" home "\n"
                "emacs_home=" home "\n"
                "root=" (directory-file-name root) "\n"))
      (rename-file staged-receipt receipt t)))

  ;; The package entry remains in init.el; the transport does not.  A future
  ;; Repair action prepares a fresh copy here, which the same entry consumes.
  (condition-case nil
      (delete-directory kit-root t)
    (file-error nil))
  (message "Jetpacs installed in %s with Vault %s" root vault))

;;; install-recommended.el ends here
