;;; jetpacs-package-browser-test.el --- ERT for the package skin -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Batch-safe: no network, no real package operations.  Column readers,
;; the deferral seam, the refresh seam, and toasts are stubbed; the
;; tests pin filter logic, wire-shape of the row actions, validation
;; statuses, and the D2 contract (slow work deferred, status immediate).

(require 'ert)
(require 'jetpacs-package-browser)

(defun jetpacs-pkg-test--desc (name &optional summary)
  (package-desc-create :name name :version '(1 0)
                       :summary (or summary "") :kind 'single))

(defmacro jetpacs-pkg-test--env (&rest body)
  "Neutral filter state, immediate deferrals, collected toasts/refreshes."
  (declare (indent 0))
  `(let ((jetpacs-pkg--search "") (jetpacs-pkg--status "all")
         (toasts nil) (refreshes 0))
     (cl-letf (((symbol-function 'jetpacs-toast)
                (cl-function (lambda (text &key duration-s)
                               (ignore duration-s) (push text toasts))))
               ((symbol-function 'jetpacs-flow-continue)
                (lambda (fn) (funcall fn)))
               ((symbol-function 'jetpacs-tablist--refresh-view)
                (lambda (_params) (cl-incf refreshes)))
               ((symbol-function 'jetpacs-pkg--revert-and-refresh)
                (lambda (_params) (cl-incf refreshes))))
       (ignore toasts refreshes)
       ,@body)))

(ert-deftest jetpacs-pkg-filter-matches-search-and-status ()
  "Search hits name or summary; chips admit their status lists."
  (jetpacs-pkg-test--env
    (cl-letf (((symbol-function 'jetpacs-tablist-entry-col)
               (lambda (_e col) (and (equal col "Status") "available")))
              ((symbol-function 'jetpacs-tablist-col-string)
               (lambda (_c) "vertico")))
      (let ((desc (jetpacs-pkg-test--desc 'vertico "Vertical completion")))
        (should (jetpacs-pkg--filter desc ["vertico"]))
        (setq jetpacs-pkg--search "completion")
        (should (jetpacs-pkg--filter desc ["vertico"]))
        (setq jetpacs-pkg--search "nomatch")
        (should-not (jetpacs-pkg--filter desc ["vertico"]))
        (setq jetpacs-pkg--search "" jetpacs-pkg--status "installed")
        (should-not (jetpacs-pkg--filter desc ["vertico"]))
        (setq jetpacs-pkg--status "available")
        (should (jetpacs-pkg--filter desc ["vertico"]))))))

(ert-deftest jetpacs-pkg-row-carries-semantic-install-action ()
  "An uninstalled package's row offers packages.install with its name."
  (jetpacs-pkg-test--env
    (cl-letf (((symbol-function 'jetpacs-tablist-entry-col)
               (lambda (_e col) (if (equal col "Status") "available" "1.0"))))
      (let* ((package-alist nil)
             (row (jetpacs-pkg--row (jetpacs-pkg-test--desc 'vertico)
                                    ["vertico"] 0))
             (found nil))
        (cl-labels ((walk (n)
                      (when-let* ((tap (plist-get n :on_tap)))
                        (when (equal (plist-get tap :action)
                                     "packages.install")
                          (setq found (plist-get tap :args))))
                      (mapc #'walk (append (plist-get n :children) nil))))
          (walk row))
        (should (equal (plist-get found :package) "vertico"))))))

(ert-deftest jetpacs-pkg-install-validates-against-archive ()
  "Unknown packages reject; known ones defer, install, toast, refresh."
  (jetpacs-pkg-test--env
    (let ((package-archive-contents nil))
      (should (eq (jetpacs-pkg--action-install '(:package "ghost") nil)
                  'rejected)))
    (let ((package-archive-contents
           (list (list 'vertico (jetpacs-pkg-test--desc 'vertico))))
          (installed nil))
      (cl-letf (((symbol-function 'package-install)
                 (lambda (sym &rest _) (setq installed sym))))
        (should (eq (jetpacs-pkg--action-install '(:package "vertico") nil)
                    'accepted))
        (should (eq installed 'vertico))
        (should (cl-find "Installed vertico" toasts :test #'equal))
        (should (> refreshes 0))))))

(ert-deftest jetpacs-pkg-delete-requires-installed ()
  "Deleting something not installed rejects without side effects."
  (jetpacs-pkg-test--env
    (let ((package-alist nil))
      (should (eq (jetpacs-pkg--action-delete '(:package "vertico") nil)
                  'rejected)))))

(ert-deftest jetpacs-pkg-status-filter-validates-chip ()
  "Only chips from the fixed set are accepted."
  (jetpacs-pkg-test--env
    (should (eq (jetpacs-pkg--action-status-filter '(:status "bogus") nil)
                'rejected))
    (should (eq (jetpacs-pkg--action-status-filter '(:status "installed") nil)
                'accepted))
    (should (equal jetpacs-pkg--status "installed"))))

(provide 'jetpacs-package-browser-test)
;;; jetpacs-package-browser-test.el ends here