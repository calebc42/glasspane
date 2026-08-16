;;; jetpacs-project-sql-test.el --- ERT for the project + SQL skins -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Batch-safe: continuations run immediately, navigation and snackbars
;; are collected, and no real project/SQL command executes.

(require 'ert)
(require 'jetpacs-chrome)
(require 'jetpacs-project)
(require 'jetpacs-sql)

(defmacro jetpacs-psql-test--env (&rest body)
  "BODY with continuations inline, navigation/snackbars collected, and
the two modules' chrome STACKS restored afterwards — the sub-screens
are real pushed screens since S9, so an action mutates global stack
state that must not leak between tests."
  (declare (indent 0))
  `(let ((jetpacs-project--current nil)
         (jetpacs-project--find-filter "")
         (jetpacs-files-roots nil)
         (navigated nil) (notified nil)
         (psql--proj (gethash "app:jetpacs.project" jetpacs-chrome--stacks))
         (psql--sql (gethash "app:jetpacs.sql" jetpacs-chrome--stacks)))
     (cl-letf (((symbol-function 'jetpacs-flow-continue)
                (lambda (fn) (funcall fn)))
               ((symbol-function 'jetpacs-navigate-buffer)
                (lambda (target &rest _) (push target navigated)))
               ((symbol-function 'jetpacs-shell-notify)
                (lambda (text &rest _) (push text notified)))
               ((symbol-function 'jetpacs-shell-push)
                (lambda (&rest _) nil)))
       (ignore navigated notified)
       (unwind-protect
           (progn ,@body)
         (puthash "app:jetpacs.project" psql--proj jetpacs-chrome--stacks)
         (puthash "app:jetpacs.sql" psql--sql jetpacs-chrome--stacks)))))

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
            ;; The pick RESETS the stack to the dashboard (S9): the
            ;; sub-screens are pushed screens now, not a state flip.
            (should (equal (jetpacs-chrome-stack "jetpacs.project")
                           '("home"))))
        (delete-directory dir t)))))

(ert-deftest jetpacs-project-find-file-sets-filter-and-screen ()
  "Find file is a REAL pushed screen since S9 — its back arrow is the
stack's companion-local `view.switch'; a refilter re-pushes the same
id (truncate-and-replace), never deepening the stack."
  (jetpacs-psql-test--env
    (should (eq (jetpacs-project--action-find-file '(:value "core") nil)
                'accepted))
    (should (equal jetpacs-project--find-filter "core"))
    (should (equal (jetpacs-chrome-stack "jetpacs.project")
                   '("find" "home")))
    (should (eq (jetpacs-project--action-find-file '(:value "elisp") nil)
                'accepted))
    (should (equal jetpacs-project--find-filter "elisp"))
    (should (equal (jetpacs-chrome-stack "jetpacs.project")
                   '("find" "home")))))

(ert-deftest jetpacs-sql-new-screen-pushes-the-picker ()
  "The product picker is a REAL pushed screen since S9; `sql.show'
survives as the stack RESET (M-x parity, the settings link); and
picking a product RESETS before the drill, so back-from-REPL lands
on the hub, never the spent picker."
  (jetpacs-psql-test--env
    (should (eq (jetpacs-sql--action-new-screen nil nil) 'accepted))
    (should (equal (jetpacs-chrome-stack "jetpacs.sql") '("new" "home")))
    (should (eq (jetpacs-sql--action-show nil nil) 'accepted))
    (should (equal (jetpacs-chrome-stack "jetpacs.sql") '("home")))
    (should (eq (jetpacs-sql--action-new-screen nil nil) 'accepted))
    (cl-letf (((symbol-function 'sql-product-interactive) #'ignore)
              ((symbol-function 'jetpacs-sql--sqli-buffer)
               (lambda () (get-buffer-create "*SQL*"))))
      (should (eq (jetpacs-sql--action-new '(:product "sqlite") nil)
                  'accepted)))
    (should (equal (jetpacs-chrome-stack "jetpacs.sql") '("home")))))

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