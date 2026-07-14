;;; glasspane-config-test.el --- Tests for glasspane-config
;;; Code:

(require 'glasspane-test-helpers)

;; ─── App-managed config directory ────────────────────────────────────────────

(ert-deftest glasspane-config-sync-and-ensure ()
  "Managed defaults merge softly; ensure never rewrites an existing dir."
  (let* ((root (make-temp-file "glasspane-config" t))
         (jetpacs-root (file-name-as-directory (expand-file-name "root" root)))
         (managed (jetpacs-app-dir "glasspane"))
         (org-directory (expand-file-name "org/" root))
         (org-default-notes-file (convert-standard-filename "~/.notes"))
         (org-capture-templates '(("t" "Mine" entry (file "x.org") "* %?")))
         (org-agenda-files nil)
         (org-log-into-drawer nil))
    (unwind-protect
        (progn
          ;; First run: directory missing -> created and loaded.
          (glasspane-config-ensure)
          (should (file-directory-p managed))
          ;; Soft merge: the user's "t" survives, missing keys append.
          (should (equal "Mine" (nth 1 (assoc "t" org-capture-templates))))
          (should (assoc "n" org-capture-templates))
          (should (assoc "l" org-capture-templates))
          ;; Stock values get seeded with the app's opinions.
          (should (equal org-default-notes-file
                         (expand-file-name "inbox.org" org-directory)))
          (should (equal org-agenda-files (list org-directory)))
          (should org-log-into-drawer)
          ;; Configured values survive a reload untouched.
          (setq org-agenda-files '("/tmp/keep"))
          (glasspane-config-load)
          (should (equal org-agenda-files '("/tmp/keep")))
          ;; `ensure' never rewrites an existing directory; `sync' does.
          (let ((file (expand-file-name "org-defaults.el" managed))
                (mangled ";; user mangled\n"))
            (write-region mangled nil file nil 'silent)
            (glasspane-config-ensure)
            (should (equal mangled
                           (with-temp-buffer
                             (insert-file-contents file) (buffer-string))))
            (glasspane-config-sync)
            (should-not (equal mangled
                               (with-temp-buffer
                                 (insert-file-contents file) (buffer-string))))))
      (delete-directory root t))))

(ert-deftest glasspane-config-startup-ensures-only-when-installed ()
  "The bundle's own load seeds the defaults only under the foundation
flow — being listed in `jetpacs-installed-bundles' (apps.el) is the
install consent.  A bare require (desktop init, batch) writes nothing."
  (let* ((root (make-temp-file "glasspane-config" t))
         (jetpacs-root (file-name-as-directory (expand-file-name "root" root)))
         (managed (jetpacs-app-dir "glasspane"))
         (org-directory (expand-file-name "org/" root))
         (org-default-notes-file (convert-standard-filename "~/.notes"))
         (org-capture-templates nil)
         (org-agenda-files nil)
         (org-log-into-drawer nil))
    (unwind-protect
        (progn
          ;; Not installed: startup is read-only — the subtree stays absent.
          (let ((jetpacs-installed-bundles nil))
            (glasspane-config-startup)
            (should-not (file-directory-p managed)))
          ;; Installed via apps.el: first startup creates and loads it —
          ;; the phone comes up with capture templates and agenda files.
          (let ((jetpacs-installed-bundles '("glasspane.el")))
            (glasspane-config-startup)
            (should (file-directory-p managed))
            (should (assoc "t" org-capture-templates))
            (should (equal org-agenda-files (list org-directory)))))
      (delete-directory root t))))

(provide 'glasspane-config-test)
