;;; jetpacs-icon-lint-test.el --- every icon literal must resolve -*- lexical-binding: t; -*-

;;; Commentary:

;; SPEC 17.1 makes an unresolved icon name render a harmless
;; placeholder — correct on the wire, which means a MISSPELLED icon in
;; the Emacs modules never fails anything: it silently ships
;; HelpOutline.  This lint closes that hole using the lookup table as
;; ground truth: every icon literal in emacs/*.el and device/init.el
;; must name something IconMap can resolve (the generated
;; M3-ICON-REFERENCE.org table, union the IconMap pre-seed cache).
;;
;; The companion pin guards the table itself: the IconMap pre-seed is
;; the set of names KNOWN rendering on device, so every one of them
;; must appear in the table — the first cut of the table was generated
;; from the extended AAR alone and silently lacked the entire
;; material-icons-core set (arrow_back, menu, close, search...).

;;; Code:

(require 'ert)

(defconst jetpacs-icon-lint--root
  (expand-file-name ".." (file-name-directory
                          (or load-file-name buffer-file-name))))

(defun jetpacs-icon-lint--file (rel)
  (expand-file-name rel jetpacs-icon-lint--root))

(defun jetpacs-icon-lint--app-files ()
  "Every .el under emacs/apps/<app>/, or nil when there are no apps."
  (let ((apps (jetpacs-icon-lint--file "emacs/apps"))
        (out nil))
    (when (file-directory-p apps)
      (dolist (dir (directory-files apps t
                                    directory-files-no-dot-files-regexp))
        (when (file-directory-p dir)
          (setq out (append out (directory-files dir t "\\.el\\'"))))))
    out))

(defun jetpacs-icon-lint--table-names ()
  "Icon names from the generated lookup table."
  (let ((names (make-hash-table :test #'equal)))
    (with-temp-buffer
      (insert-file-contents
       (jetpacs-icon-lint--file "docs/lookup-tables/M3-ICON-REFERENCE.org"))
      (goto-char (point-min))
      (while (re-search-forward
              "^| \\([a-z_0-9]+\\) | ~Icons" nil t)
        (puthash (match-string 1) t names)))
    names))

(defun jetpacs-icon-lint--preseed-names ()
  "Names IconMap.kt pre-seeds (known rendering on device)."
  (let ((names nil))
    (with-temp-buffer
      (insert-file-contents
       (jetpacs-icon-lint--file
        "companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/IconMap.kt"))
      (goto-char (point-min))
      (while (re-search-forward "cache\\[\"\\([a-z_0-9]+\\)\"\\]" nil t)
        (push (match-string 1) names)))
    names))

(defun jetpacs-icon-lint--used-icons ()
  "((FILE NAME) ...) for every icon literal in the Emacs modules."
  (let ((files (append (directory-files
                        (jetpacs-icon-lint--file "emacs") t "\\.el\\'")
                       ;; A Tier-1 app that modularizes one level down
                       ;; (emacs/apps/<app>/) must not escape the lint —
                       ;; the M3 catalog alone is 42 files full of icons.
                       (jetpacs-icon-lint--app-files)
                       (list (jetpacs-icon-lint--file "device/init.el"))))
        (used nil))
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward
                (concat "\\(?::icon\\|(jetpacs-icon\\|(jetpacs-icon-button\\)"
                        " \"\\([a-z_0-9]+\\)\"")
                nil t)
          (push (list (file-name-nondirectory file) (match-string 1))
                used))))
    used))

(ert-deftest jetpacs-icon-lint-preseed-subset-of-table ()
  "Every IconMap pre-seeded name appears in the lookup table.
Fails when the table is regenerated from an incomplete artifact set
\(the missing-icons-core regression)."
  (let ((table (jetpacs-icon-lint--table-names))
        (missing nil))
    (dolist (name (jetpacs-icon-lint--preseed-names))
      (unless (gethash name table)
        (push name missing)))
    (should-not missing)))

(ert-deftest jetpacs-icon-lint-every-used-icon-resolves ()
  "Every icon literal in the Emacs modules names a resolvable icon."
  (let ((table (jetpacs-icon-lint--table-names))
        (preseed (jetpacs-icon-lint--preseed-names))
        (used (jetpacs-icon-lint--used-icons))
        (bad nil))
    ;; Sanity: the extraction must see the codebase (an empty result
    ;; would vacuously pass).
    (should (> (length used) 20))
    (pcase-dolist (`(,file ,name) used)
      (unless (or (gethash name table) (member name preseed))
        (push (format "%s: %s" file name) bad)))
    (should-not bad)))

(provide 'jetpacs-icon-lint-test)
;;; jetpacs-icon-lint-test.el ends here
