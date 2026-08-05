;;; jetpacs-project-sql-test.el --- ERT for the project + SQL skins -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Batch-safe: continuations run immediately, navigation and snackbars
;; are collected, and no real project/SQL command executes.

(require 'ert)
(require 'jetpacs-project)
(require 'jetpacs-sql)

(defmacro jetpacs-psql-test--env (&rest body)
  (declare (indent 0))
  `(let ((jetpacs-project--current nil)
         (jetpacs-project--screen 'dashboard)
         (jetpacs-project--find-filter "")
         (jetpacs-sql--screen 'hub)
         (jetpacs-files-roots nil)
         (navigated nil) (notified nil))
     (cl-letf (((symbol-function 'jetpacs-flow-continue)
                (lambda (fn) (funcall fn)))
               ((symbol-function 'jetpacs-navigate-buffer)
                (lambda (target &rest _) (push target navigated)))
               ((symbol-function 'jetpacs-shell-notify)
                (lambda (text &rest _) (push text notified)))
               ((symbol-function 'jetpacs-shell-push)
                (lambda (&rest _) nil)))
       (ignore navigated notified)
       ,@body)))

;;;; Project

(ert-deftest jetpacs-project-switch-validates-directory ()
  "Switching validates the root and widens the files sandbox to it."
  (jetpacs-psql-test--env
    (should (eq (jetpacs-project--action-switch '(:root "/no/such/dir") nil)
                'rejected))
    (let ((dir (make-temp-file "jetpacs-proj" t)))
      (unwind-protect
          (progn
            (should (eq (jetpacs-project--action-switch
                         `(:root ,dir) nil)
                        'accepted))
            (should (equal jetpacs-project--current
                           (file-name-as-directory dir)))
            (should (equal (car (assoc "Project" jetpacs-files-roots))
                           "Project"))
            (should (eq jetpacs-project--screen 'dashboard)))
        (delete-directory dir t)))))

(ert-deftest jetpacs-project-find-file-sets-filter-and-screen ()
  (jetpacs-psql-test--env
    (should (eq (jetpacs-project--action-find-file '(:value "core") nil)
                'accepted))
    (should (equal jetpacs-project--find-filter "core"))
    (should (eq jetpacs-project--screen 'find))))

(ert-deftest jetpacs-project-view-buffer-of-navigates-and-degrades ()
  "The runner navigates to the returned buffer; a signal costs only
the navigation and lands as a snackbar."
  (jetpacs-psql-test--env
    (setq jetpacs-project--current temporary-file-directory)
    (jetpacs-project--view-buffer-of (lambda () "*scratch*"))
    (should (equal navigated '("*scratch*")))
    (jetpacs-project--view-buffer-of (lambda () (error "boom")))
    (should (= 1 (length navigated)))
    (should (cl-find-if (lambda (s) (string-match-p "boom" s)) notified))))

(ert-deftest jetpacs-project-view-buffer-of-needs-a-project ()
  (jetpacs-psql-test--env
    (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil)))
      (jetpacs-project--view-buffer-of (lambda () "*scratch*"))
      (should-not navigated)
      (should (cl-find "No project selected" notified :test #'equal)))))

(ert-deftest jetpacs-project-dashboard-carries-the-command-cards ()
  (jetpacs-psql-test--env
    (setq jetpacs-project--current temporary-file-directory)
    (let ((actions nil))
      (cl-labels ((walk (n)
                    (when-let* ((tap (plist-get n :on_tap)))
                      (push (plist-get tap :action) actions))
                    (mapc #'walk (append (plist-get n :children) nil))))
        (mapc #'walk (jetpacs-project--dashboard-nodes)))
      (dolist (a '("project.grep" "project.compile" "project.shell"
                   "project.vc" "sql.show"))
        (should (member a actions))))))

;;;; SQL

(ert-deftest jetpacs-sql-connect-validates-the-connection ()
  "Unknown connections reject; known ones connect and navigate."
  (jetpacs-psql-test--env
    (let ((sql-connection-alist nil))
      (should (eq (jetpacs-sql--action-connect '(:connection "prod") nil)
                  'rejected)))
    (let ((sql-connection-alist '((devdb (sql-product 'sqlite))))
          (connected nil))
      (cl-letf (((symbol-function 'sql-connect)
                 (lambda (name &rest _) (setq connected name)))
                ((symbol-function 'jetpacs-sql--sqli-buffer)
                 (lambda () (get-buffer-create "*SQL*"))))
        (should (eq (jetpacs-sql--action-connect '(:connection "devdb") nil)
                    'accepted))
        (should (eq connected 'devdb))
        (should (= 1 (length navigated)))))))

(ert-deftest jetpacs-sql-new-validates-the-product ()
  (jetpacs-psql-test--env
    (should (eq (jetpacs-sql--action-new '(:product "not-a-db") nil)
                'rejected))))

(ert-deftest jetpacs-sql-session-actions-require-a-session ()
  (jetpacs-psql-test--env
    (cl-letf (((symbol-function 'jetpacs-sql--sqli-buffer) (lambda () nil)))
      (should (eq (jetpacs-sql--action-open nil nil) 'rejected))
      (should (eq (jetpacs-sql--action-list-tables nil nil) 'rejected)))))

(ert-deftest jetpacs-sql-hub-lists-real-products ()
  "The product picker finds at least sqlite among Emacs's sql products."
  (should (assq 'sqlite (jetpacs-sql--products))))

(provide 'jetpacs-project-sql-test)
;;; jetpacs-project-sql-test.el ends here