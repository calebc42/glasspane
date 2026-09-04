;;; glasspane-navigation-test.el --- Contract tests for one document route -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; These tests guard a semantic boundary that static applet validation cannot
;; infer: different identity adapters may name a document, but none may create
;; its own Files presentation policy.  See ../NAVIGATION.org.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'seq)
(require 'glasspane)

(defconst glasspane-navigation-test--source-directory
  (expand-file-name ".."
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "Glasspane's flat applet source directory.")

(ert-deftest glasspane-navigation-test-declares-material-renderer ()
  "Glasspane, rather than Jetpacs foundation, selects Material 3."
  (let ((entry (assoc glasspane-owner jetpacs-apps--registry)))
    (should entry)
    (should (equal (plist-get (cdr entry) :requires-extensions)
                   '("glasspane.material3")))))

(ert-deftest glasspane-navigation-test-canonical-document-policy ()
  "A document open fixes Files, reader, Back screen, and return policy."
  (let ((glasspane-ui-legacy-ia nil)
        events)
    (cl-letf (((symbol-function 'jetpacs-feature-advertised-p)
               (lambda (feature target)
                 (and (equal feature "action.open_surface")
                      (eq target :app))))
              ((symbol-function 'jetpacs-files-open-path)
               (lambda (path surface &optional position browser-id browser-fab
                             return-action)
                 (push (list 'open path surface position browser-id browser-fab
                             return-action)
                       events)
                 'accepted))
              ((symbol-function 'glasspane-org-reader-prepare-landing)
               (lambda (path) (push (list 'prepare path) events))))
      (should (eq (glasspane-navigation-open-document
                   "/vault/work.org" 37)
                  'accepted)))
    (setq events (nreverse events))
    ;; Files validates and accepts first; reader state changes before its
    ;; deferred render, but never for a refused path.
    (should (equal (caar events) 'open))
    (should (equal (cadr events) '(prepare "/vault/work.org")))
    (let* ((open (car events))
           (return (nth 6 open)))
      (should (equal (seq-take open 6)
                     '(open "/vault/work.org" "app:jetpacs.files" 37
                            "files-return" nil)))
      (should (equal (plist-get return :action)
                     "glasspane.files.return"))
      (should (equal (plist-get return :open_surface) "app:glasspane")))
    (setq events nil)
    (cl-letf (((symbol-function 'jetpacs-feature-advertised-p)
               (lambda (&rest _) t))
              ((symbol-function 'jetpacs-files-open-path)
               (lambda (&rest _) 'rejected))
              ((symbol-function 'glasspane-org-reader-prepare-landing)
               (lambda (path) (push path events))))
      (should (eq (glasspane-navigation-open-document
                   "/outside/refused.org")
                  'rejected))
      (should-not events))
    (should (eq (glasspane-navigation-open-document nil) 'rejected))
    (should (eq (glasspane-navigation-open-document "/vault/work.org" "37")
                'rejected))))

(ert-deftest glasspane-navigation-test-entry-builders-name-authority-only ()
  "Heading cards and file rows choose identity, never presentation policy.
Every builder that opens a document is named here: the detail card and the
Area declaring card carry a durable heading token (`heading.visit'); the
Area file row and the Archive row carry a validated path
\(`glasspane.document.open').  All of them present the one Files surface."
  (cl-letf (((symbol-function 'jetpacs-feature-advertised-p)
             (lambda (&rest _) t)))
    (let* ((project (glasspane-detail-agenda-card
                     '((headline . "Ship it") (token . "heading-token"))))
           (project-action (plist-get project :on_tap))
           (declaring (glasspane-areas--declaring-card
                       '((headline . "Tech") (todo . nil) (tags . ["tech"])
                         (areas . ["tech"]) (file . "/vault/areas.org")
                         (pos . 1) (token . "decl-token"))))
           (declaring-action (plist-get declaring :on_tap))
           (file-row (glasspane-areas--file-row "/vault/work.org"))
           (file-action (plist-get file-row :on_tap))
           (archive-row (glasspane-resources--archive-row
                         (list :path "/vault/work.org_archive"
                               :mtime (encode-time 0 30 9 2 1 2026))))
           (archive-action (plist-get archive-row :on_tap)))
      (should (equal (plist-get project-action :action) "heading.visit"))
      (should (equal (plist-get project-action :args)
                     '(:token "heading-token")))
      (should (equal (plist-get declaring-action :action) "heading.visit"))
      (should (equal (plist-get declaring-action :args)
                     '(:token "decl-token")))
      (should (equal (plist-get file-action :action)
                     "glasspane.document.open"))
      (should (equal (plist-get file-action :args)
                     '(:path "/vault/work.org")))
      (should (equal (plist-get archive-action :action)
                     "glasspane.document.open"))
      (should (equal (plist-get archive-action :args)
                     '(:path "/vault/work.org_archive")))
      (dolist (action (list project-action declaring-action
                            file-action archive-action))
        (should (equal (plist-get action :open_surface)
                       "app:jetpacs.files"))))))

(ert-deftest glasspane-navigation-test-authority-adapters-converge ()
  "Token, path, and compatibility verbs call one document presenter."
  (let (calls)
    (cl-letf (((symbol-function 'ebp-org-token-ref)
               (lambda (_token &rest _) 'durable-ref))
              ((symbol-function 'glasspane-detail--ref-location)
               (lambda (_ref) '(buffer "/vault/work.org" 73)))
              ((symbol-function 'glasspane-navigation-open-document)
               (lambda (path &optional position)
                 (push (list path position) calls)
                 'accepted)))
      (should (eq (glasspane-detail--on-visit
                   '(:token "project-token") nil)
                  'accepted))
      (should (eq (glasspane-detail--on-open-file
                   '(:token "cached-detail-token") nil)
                  'accepted))
      (should (eq (glasspane-navigation--on-document-open
                   '(:path "/vault/work.org") nil)
                  'accepted))
      (should (eq (glasspane-resources--on-open-file
                   '(:path "/vault/work.org") nil)
                  'accepted)))
    (should (equal (nreverse calls)
                   '(("/vault/work.org" 73)
                     ("/vault/work.org" 73)
                     ("/vault/work.org" nil)
                     ("/vault/work.org" nil))))))

(ert-deftest glasspane-navigation-test-real-org-token-preserves-position ()
  "A real durable heading token resolves to canonical PATH and POSITION."
  (let* ((root (make-temp-file "glasspane-navigation" t))
         (path (expand-file-name "project.org" root))
         (org-directory root)
         (ebp-org-roots (list root))
         buffer token expected opened)
    (unwind-protect
        (progn
          (with-temp-file path
            (insert "* Project\n** TODO Canonical target\nBody\n"))
          (setq buffer (find-file-noselect path))
          (with-current-buffer buffer
            (org-mode)
            (org-with-wide-buffer
             (goto-char (point-min))
             (re-search-forward "^\\*\\* TODO Canonical target$")
             (goto-char (line-beginning-position))
             (let ((ref (ebp-org-ref-at-point)))
               (setq expected (plist-get ref :pos)
                     token (car (ebp-org-ref-tokens
                                 (list ref) :set "navigation-real"
                                 :owner "glasspane"))))))
          (cl-letf (((symbol-function 'glasspane-navigation-open-document)
                     (lambda (file &optional position)
                       (setq opened (list file position))
                       'accepted)))
            (should (eq (glasspane-detail--on-visit
                         (list :token token) nil)
                        'accepted)))
          (should (equal opened (list (file-truename path) expected))))
      (ebp-org-ref-tokens nil :set "navigation-real" :owner "glasspane")
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest glasspane-navigation-test-one-low-level-files-boundary ()
  "Only glasspane-navigation.el may call `jetpacs-files-open-path'."
  (let ((sources
         (directory-files glasspane-navigation-test--source-directory
                          t "\\.el\\'"))
        owners)
    (dolist (source sources)
      (with-temp-buffer
        (insert-file-contents source)
        (goto-char (point-min))
        (when (re-search-forward
               "([ \t\n]*jetpacs-files-open-path\\_>" nil t)
          (push (file-name-nondirectory source) owners))))
    (should (equal (nreverse owners) '("glasspane-navigation.el")))))

(ert-deftest glasspane-navigation-test-lifecycle-is-symmetric ()
  "Canonical actions and the Back observer register and unregister together."
  (unwind-protect
      (progn
        (glasspane-navigation-register)
        (dolist (verb glasspane-navigation--verbs)
          (should (gethash verb jetpacs-action-handlers))
          (should (equal (jetpacs--owner-of "action" verb) "glasspane")))
        (should (memq #'glasspane-navigation--on-view-change
                      jetpacs-shell-view-change-functions))
        (glasspane-navigation-unregister)
        (dolist (verb glasspane-navigation--verbs)
          (should-not (gethash verb jetpacs-action-handlers)))
        (should-not (memq #'glasspane-navigation--on-view-change
                          jetpacs-shell-view-change-functions)))
    (glasspane-navigation-register)))

(provide 'glasspane-navigation-test)
;;; glasspane-navigation-test.el ends here
