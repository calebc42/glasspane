;;; jetpacs-app-store-test.el --- ERT for Manage Apps -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; Batch-safe: staging and adopt dirs are temp trees, persistence lands
;; in a temp file, loads are stubbed where a real load would execute
;; bundle code.

(require 'ert)
(require 'jetpacs-app-store)
(require 'jetpacs-apps)

(defmacro jetpacs-app-store-test--env (&rest body)
  "Temp staging/adopt/persist trees, immediate continuations."
  (declare (indent 0))
  `(let* ((stage (make-temp-file "jetpacs-stage" t))
          (home (make-temp-file "jetpacs-home" t))
          (user-emacs-directory (file-name-as-directory home))
          (jetpacs-app-store-staging-dirs (list stage))
          (jetpacs-app-store-file (expand-file-name "apps.el" home))
          (jetpacs-app-store-installed nil)
          (toasts nil) (pushed 0))
     (cl-letf (((symbol-function 'jetpacs-flow-continue)
                (lambda (fn) (funcall fn)))
               ((symbol-function 'jetpacs-toast)
                (cl-function (lambda (text &key duration-s)
                               (ignore duration-s) (push text toasts))))
               ((symbol-function 'jetpacs-shell-push)
                (lambda (&rest _) (cl-incf pushed))))
       (ignore toasts pushed)
       (unwind-protect (progn ,@body)
         (delete-directory stage t)
         (delete-directory home t)))))

(defun jetpacs-app-store-test--stage (dir name &rest lines)
  (let ((path (expand-file-name name dir)))
    (with-temp-file path
      (insert (string-join lines "\n")))
    path))

(ert-deftest jetpacs-app-store-scan-strips-mediastore-rename ()
  "A shared \"name.el.txt\" scans as \"name.el\" - the rename trap."
  (jetpacs-app-store-test--env
    (jetpacs-app-store-test--stage
     stage "notes.el.txt"
     ";;; notes.el --- A notes app -*- lexical-binding: t; -*-")
    (let ((entries (jetpacs-app-store--scan)))
      (should (= 1 (length entries)))
      (should (equal (plist-get (car entries) :name) "notes.el"))
      (should (equal (plist-get (car entries) :summary) "A notes app")))))

(ert-deftest jetpacs-app-store-entry-refuses-paths ()
  "The wire names bundles, never paths."
  (jetpacs-app-store-test--env
    (jetpacs-app-store-test--stage stage "notes.el" ";;; notes.el ---")
    (should (jetpacs-app-store--entry "notes.el"))
    (should-not (jetpacs-app-store--entry "../notes.el"))
    (should-not (jetpacs-app-store--entry "/etc/passwd"))
    (should-not (jetpacs-app-store--entry "ghost.el"))))

(ert-deftest jetpacs-app-store-install-adopts-and-persists ()
  "Install copies into the adopt dir, loads, records, persists."
  (jetpacs-app-store-test--env
    (jetpacs-app-store-test--stage
     stage "notes.el" ";;; notes.el --- Notes -*- lexical-binding: t; -*-"
     "(defvar jetpacs-app-store-test--loaded t)")
    (should (eq (jetpacs-app-store--action-install '(:bundle "notes.el") nil)
                'accepted))
    (should (member "notes.el" jetpacs-app-store-installed))
    (should (file-exists-p (expand-file-name
                            "notes.el" (jetpacs-app-store--adopt-dir))))
    (should (file-exists-p jetpacs-app-store-file))
    (should (cl-find "Installed notes.el" toasts :test #'equal))
    ;; The persisted file round-trips.
    (setq jetpacs-app-store-installed nil)
    (load jetpacs-app-store-file nil 'nomessage)
    (should (equal jetpacs-app-store-installed '("notes.el")))))

(ert-deftest jetpacs-app-store-install-validates-and-uninstall-reverses ()
  "Unknown bundles reject; uninstall removes record and adopted copy."
  (jetpacs-app-store-test--env
    (should (eq (jetpacs-app-store--action-install '(:bundle "ghost.el") nil)
                'rejected))
    (jetpacs-app-store-test--stage
     stage "notes.el" ";;; notes.el --- Notes -*- lexical-binding: t; -*-")
    (jetpacs-app-store--action-install '(:bundle "notes.el") nil)
    (should (eq (jetpacs-app-store--action-uninstall
                 '(:bundle "notes.el") nil)
                'accepted))
    (should-not jetpacs-app-store-installed)
    (should-not (file-exists-p (expand-file-name
                                "notes.el" (jetpacs-app-store--adopt-dir))))
    (should (eq (jetpacs-app-store--action-uninstall
                 '(:bundle "notes.el") nil)
                'rejected))))

(ert-deftest jetpacs-app-store-boot-isolates-broken-bundles ()
  "One bundle that fails to load never costs the next one."
  (jetpacs-app-store-test--env
    (let ((dir (jetpacs-app-store--adopt-dir)))
      (make-directory dir t)
      (with-temp-file (expand-file-name "broken.el" dir)
        (insert "(error \"boom\")"))
      (with-temp-file (expand-file-name "fine.el" dir)
        (insert "(defvar jetpacs-app-store-test--fine t)"))
      (setq jetpacs-app-store-installed '("broken.el" "fine.el"))
      (jetpacs-app-store--persist)
      (makunbound 'jetpacs-app-store-test--fine)
      (jetpacs-app-store-boot)
      (should (bound-and-true-p jetpacs-app-store-test--fine)))))

(ert-deftest jetpacs-app-store-install-action-carries-consent ()
  "The install affordance rides a :confirm gate - installing runs code."
  (jetpacs-app-store-test--env
    (jetpacs-app-store-test--stage
     stage "notes.el" ";;; notes.el --- Notes -*- lexical-binding: t; -*-")
    (let ((confirm nil))
      (cl-labels ((walk (n)
                    (when-let* ((tap (plist-get n :on_tap)))
                      (when (equal (plist-get tap :action) "apps.install")
                        (setq confirm (plist-get tap :confirm))))
                    (dolist (slot '(:children :trailing :header :body))
                      (let ((v (plist-get n slot)))
                        (cond ((vectorp v) (mapc #'walk (append v nil)))
                              ((and v (listp v) (keywordp (car v)))
                               (walk v))
                              ((listp v) (mapc #'walk v)))))))
        (walk (jetpacs-app-store--row (car (jetpacs-app-store--scan)))))
      (should confirm)
      (should (string-match-p "full permissions"
                              (plist-get confirm :text))))))

(ert-deftest jetpacs-apps-drawer-entry-consolidates ()
  "One collapsible: Manage Apps and App Launcher, collapsed by default."
  (let ((entry (jetpacs-apps-drawer-entry))
        (labels nil))
    (should (equal (plist-get entry :t) "collapsible"))
    (should (eq (plist-get entry :collapsed) t))
    (cl-labels ((walk (n)
                  (when (equal (plist-get n :t) "text")
                    (push (plist-get n :text) labels))
                  (dolist (slot '(:children :header :trailing))
                    (let ((v (plist-get n slot)))
                      (cond ((vectorp v) (mapc #'walk (append v nil)))
                            ((and v (listp v) (keywordp (car v))) (walk v))
                            ((listp v) (mapc #'walk v)))))))
      (walk entry))
    (should (member "Apps" labels))
    (should (member "Manage Apps" labels))
    (should (member "App Launcher" labels))))

(provide 'jetpacs-app-store-test)
;;; jetpacs-app-store-test.el ends here