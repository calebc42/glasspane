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
          (jetpacs-app-store--edit nil)
          (toasts nil) (notices nil) (pushed 0))
     (cl-letf (((symbol-function 'jetpacs-flow-continue)
                (lambda (fn) (funcall fn)))
               ((symbol-function 'jetpacs-toast)
                (cl-function (lambda (text &key duration-s)
                               (ignore duration-s) (push text toasts))))
               ((symbol-function 'jetpacs-shell-notify)
                (lambda (text &rest _) (push text notices)))
               ((symbol-function 'jetpacs-chrome-push-screen)
                (lambda (&rest _) (cl-incf pushed)))
               ((symbol-function 'jetpacs-shell-push)
                (lambda (&rest _) (cl-incf pushed))))
       (ignore toasts notices pushed)
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

(ert-deftest jetpacs-app-store-foundation-is-never-listed ()
  "A staged copy of the platform itself is not an installable app."
  (jetpacs-app-store-test--env
    (jetpacs-app-store-test--stage stage "jetpacs-core.el" ";;; core")
    (jetpacs-app-store-test--stage stage "jetpacs-core.el.txt" ";;; core")
    (jetpacs-app-store-test--stage stage "notes.el" ";;; notes.el ---")
    (let ((names (mapcar (lambda (e) (plist-get e :name))
                         (jetpacs-app-store--scan))))
      (should (equal names '("notes.el"))))
    (should-not (jetpacs-app-store--entry "jetpacs-core.el"))))

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
      ;; The ratified §14.1 OBJECT form (amendment #168): an authored
      ;; face over the consent text.
      (should (consp confirm))
      (let ((text (plist-get confirm :text)))
        (should (stringp text))
        (should (string-match-p "full permissions" text)))
      (should (stringp (plist-get confirm :title)))
      (should (stringp (plist-get confirm :confirm_label)))
      (should (stringp (plist-get confirm :dismiss_label))))))

;;;; The combined Apps view (pass 2)

(ert-deftest jetpacs-app-store-combined-view-sections ()
  "Running (registered apps), Installed, and Available section as one
screen; each renders only when it has members."
  (jetpacs-app-store-test--env
    (jetpacs-app-store-test--stage
     stage "staged.el" ";;; staged.el --- Staged -*- lexical-binding: t; -*-")
    (jetpacs-app-store-test--stage
     stage "mine.el" ";;; mine.el --- Mine -*- lexical-binding: t; -*-")
    (setq jetpacs-app-store-installed '("mine.el"))
    (let ((jetpacs-apps--registry
           '(("noter" . (:label "Noter" :icon "apps"
                         :surfaces ("noter.main") :order 100))))
          (jetpacs-apps--current nil)
          (headers nil))
      (cl-labels ((walk (n)
                    (when (equal (plist-get n :t) "section_header")
                      (push (plist-get n :title) headers))
                    (dolist (slot '(:children :body :header))
                      (let ((v (plist-get n slot)))
                        (cond ((vectorp v) (mapc #'walk (append v nil)))
                              ((and v (listp v) (keywordp (car v)))
                               (walk v))
                              ((listp v) (mapc #'walk v)))))))
        (walk (jetpacs-app-store--view)))
      (should (member "Running" headers))
      (should (member "Installed" headers))
      (should (member "Available" headers)))))

;;;; The writable editor, scoped to the adopt dir

(defun jetpacs-app-store-test--editor (node)
  "The first `editor' node in NODE, or nil."
  (let ((found nil))
    (cl-labels ((walk (n)
                  (when (and (null found) (listp n) (keywordp (car n)))
                    (when (equal (plist-get n :t) "editor") (setq found n))
                    (cl-loop for (_k v) on n by #'cddr do (walk v)))
                  (cond ((vectorp n) (mapc #'walk (append n nil)))
                        ((and (consp n) (not (keywordp (car n))))
                         (mapc #'walk n)))))
      (walk node))
    found))

(defun jetpacs-app-store-test--install-mine ()
  "Stage and install \"mine.el\"; returns its adopted path."
  (jetpacs-app-store--action-install '(:bundle "mine.el") nil)
  (expand-file-name "mine.el" (jetpacs-app-store--adopt-dir)))

(ert-deftest jetpacs-app-store-edit-screen-carries-a-writable-editor ()
  "apps.edit seeds the edit record and the screen renders the plain
`value'+`on_save' editor — no `:document': synchronizing a buffer is
another program's business."
  (jetpacs-app-store-test--env
    (should (eq (jetpacs-app-store--action-edit '(:bundle "ghost.el") nil)
                'rejected))
    (jetpacs-app-store-test--stage
     stage "mine.el" ";;; mine.el --- Mine -*- lexical-binding: t; -*-")
    (let ((adopted (jetpacs-app-store-test--install-mine)))
      (should (eq (jetpacs-app-store--action-edit '(:bundle "mine.el") nil)
                  'accepted))
      (should (equal (plist-get jetpacs-app-store--edit :name) "mine.el"))
      (should (string-match-p "Mine" (plist-get jetpacs-app-store--edit :seed)))
      (let ((editor (jetpacs-app-store-test--editor
                     (jetpacs-app-store--edit-screen nil))))
        (should editor)
        (should-not (plist-get editor :document))
        (should (equal (plist-get editor :value)
                       (plist-get jetpacs-app-store--edit :seed)))
        (let ((save (plist-get editor :on_save)))
          (should (equal (plist-get save :action) "jetpacs.app-store.save"))
          (should (equal (plist-get (plist-get save :args) :path)
                         (file-truename adopted)))
          (should (stringp (plist-get (plist-get save :args) :mtime))))))))

(ert-deftest jetpacs-app-store-save-writes-inside-the-adopt-dir ()
  "The save verb writes the bundle and says the reload waits for a boot."
  (jetpacs-app-store-test--env
    (jetpacs-app-store-test--stage
     stage "mine.el" ";;; mine.el --- Mine -*- lexical-binding: t; -*-")
    ;; Backdate the adopted bundle before the editor stamps it.  The
    ;; staleness gate compares mtimes, and the kernel hands out file
    ;; timestamps from the COARSE clock — one tick per jiffy, 4ms on
    ;; the kernel this suite runs under — while install, open and save
    ;; here take about 3ms end to end.  So the open-time stamp and the
    ;; post-save stamp landed inside the SAME tick on roughly half of
    ;; runs, came back byte-identical, and the stale leg below answered
    ;; `accepted'.  A minute of backdating puts the two stamps in
    ;; different ticks whatever the tick is.  It weakens nothing: the
    ;; save still writes through the real verb and the gate still
    ;; compares what production recorded — the test just stops racing
    ;; the filesystem clock.  (The files rung's twin of this assertion
    ;; buys the same margin with `sleep-for'; this one costs no wall
    ;; clock and does not assume the tick is under 20ms.)
    (set-file-times (jetpacs-app-store-test--install-mine)
                    (time-subtract (current-time) 60))
    (jetpacs-app-store--action-edit '(:bundle "mine.el") nil)
    (let* ((path (plist-get jetpacs-app-store--edit :path))
           (stamp (plist-get jetpacs-app-store--edit :mtime))
           (new ";;; mine.el --- Mine, edited -*- lexical-binding: t; -*-\n"))
      (should (eq (jetpacs-app-store--action-save
                   (list :path path :mtime stamp :value new) nil)
                  'accepted))
      (should (equal new (with-temp-buffer
                           (insert-file-contents path) (buffer-string))))
      (should (cl-find-if (lambda (s) (string-match-p "next boot" s)) notices))
      ;; The record carried forward: the STALE stamp is refused, the
      ;; fresh one the save recorded is not.
      (should (eq (jetpacs-app-store--action-save
                   (list :path path :mtime stamp :value new) nil)
                  'stale))
      (should (eq (jetpacs-app-store--action-save
                   (list :path path
                         :mtime (plist-get jetpacs-app-store--edit :mtime)
                         :value new)
                   nil)
                  'accepted)))))

(ert-deftest jetpacs-app-store-save-refuses-outside-the-adopt-dir ()
  "THE CONTAINMENT PIN.  The path rides the wire, so a path outside the
adopt dir is refused loudly and nothing is written — the app-store's
save route is scoped to the directory it adopts into and is not a
second Files editor."
  (jetpacs-app-store-test--env
    (jetpacs-app-store-test--stage
     stage "mine.el" ";;; mine.el --- Mine -*- lexical-binding: t; -*-")
    (jetpacs-app-store-test--install-mine)
    (jetpacs-app-store--action-edit '(:bundle "mine.el") nil)
    (dolist (outside (list (expand-file-name "escape.el" home)
                           (expand-file-name "staged.el" stage)
                           (expand-file-name
                            "../escape.el" (jetpacs-app-store--adopt-dir))
                           "/etc/jetpacs-escape.el"))
      (should (eq (jetpacs-app-store--action-save
                   (list :path outside
                         :mtime (plist-get jetpacs-app-store--edit :mtime)
                         :value "(setq jetpacs-app-store-test--escaped t)")
                   nil)
                  'rejected))
      (should-not (file-exists-p outside)))
    (should (cl-find-if (lambda (s) (string-prefix-p "Save refused:" s))
                        notices))
    ;; A relative path is not absolute, and never became one.
    (should (eq (jetpacs-app-store--action-save
                 '(:path "mine.el" :mtime "0.0" :value "x") nil)
                'rejected))))

(ert-deftest jetpacs-app-store-edit-refuses-an-oversize-bundle ()
  "A bundle past the cap is refused, not silently downgraded."
  (jetpacs-app-store-test--env
    (jetpacs-app-store-test--stage
     stage "mine.el" ";;; mine.el --- Mine -*- lexical-binding: t; -*-")
    (jetpacs-app-store-test--install-mine)
    (let ((jetpacs-app-store-max-bytes 8))
      (should (eq (jetpacs-app-store--action-edit '(:bundle "mine.el") nil)
                  'rejected))
      (should-not jetpacs-app-store--edit)
      (should (cl-find "Too large to edit here" notices :test #'equal)))
    ;; And the save leg bounds the write independently of the seed.
    (jetpacs-app-store--action-edit '(:bundle "mine.el") nil)
    (let ((jetpacs-app-store-max-bytes 8))
      (should (eq (jetpacs-app-store--action-save
                   (list :path (plist-get jetpacs-app-store--edit :path)
                         :mtime (plist-get jetpacs-app-store--edit :mtime)
                         :value "a much longer replacement body")
                   nil)
                  'rejected)))))

(provide 'jetpacs-app-store-test)
;;; jetpacs-app-store-test.el ends here