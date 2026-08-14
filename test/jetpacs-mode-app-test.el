;;; jetpacs-mode-app-test.el --- ERT for reader/editor mode apps -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'jetpacs-org-mode)

(defmacro jetpacs-mode-app-test--with-org-file (binding content &rest body)
  "Bind BINDING to a temporary Org file containing CONTENT during BODY."
  (declare (indent 2) (debug (symbolp form body)))
  `(let ((,binding (make-temp-file "jetpacs-mode-app-" nil ".org"
                                    ,content)))
     (unwind-protect
         (progn ,@body)
       (when-let* ((buffer (get-file-buffer ,binding)))
         (with-current-buffer buffer (set-buffer-modified-p nil))
         (kill-buffer buffer))
       (delete-file ,binding))))

(defun jetpacs-mode-app-test--toolbar-commands (items)
  "Return every command string nested one level below toolbar ITEMS."
  (cl-loop for item in items
           append
           (append
            (when-let* ((command (plist-get item :command)))
              (list command))
            (when-let* ((menu (plist-get item :menu)))
              (jetpacs-mode-app-test--toolbar-commands
               (append menu nil))))))

(defun jetpacs-mode-app-test--toolbar-snippets (items)
  "Return every snippet string nested below toolbar ITEMS."
  (cl-loop for item in items
           append
           (append
            (when-let* ((snippet (plist-get item :snippet)))
              (list snippet))
            (when-let* ((menu (plist-get item :menu)))
              (jetpacs-mode-app-test--toolbar-snippets
               (append menu nil))))))

(ert-deftest jetpacs-reader-registry-and-toggle-are-document-scoped ()
  "The generic host selects an adapter and refuses a replay for another file."
  (jetpacs-mode-app-test--with-org-file file "* One\n"
    (let ((jetpacs-reader--adapters nil)
          (jetpacs-reader--state (make-hash-table :test #'equal))
          (jetpacs-files--edit (list :path file))
          refreshed)
      (jetpacs-reader-register
       'fixture
       :predicate (lambda (path) (string-suffix-p ".org" path))
       :render (lambda (_path) (jetpacs-text "rendered")))
      (should (jetpacs-reader-active-p file))
      (cl-letf (((symbol-function 'jetpacs-buffer-defer-refresh)
                 (lambda (surface) (setq refreshed surface))))
        (should (eq (jetpacs-reader--toggle
                     (list :path file) '(:surface "app:files"))
                    'accepted))
        (should-not (jetpacs-reader-active-p file))
        (should (equal refreshed "app:files"))
        (should (eq (jetpacs-reader--toggle
                     '(:path "/tmp/not-the-open-file.org")
                     '(:surface "app:files"))
                    'stale))))))

(ert-deftest jetpacs-reader-org-rents-built-in-search-and-visibility ()
  "Plain/regexp search uses org-occur; sparse filters use Org's matcher."
  (jetpacs-mode-app-test--with-org-file
      file "* TODO Alpha :work:\nNeedle one\n* Beta :home:\nNeedle two\n"
    (let ((jetpacs-reader--state (make-hash-table :test #'equal)))
      (should (= (jetpacs-reader-org--apply-search file "Needle") 2))
      (with-current-buffer (get-file-buffer file)
        (should (= (length org-occur-highlights) 2)))
      (jetpacs-reader-state-set file :org-search-mode 'regexp)
      (should (= (jetpacs-reader-org--apply-search file "Needle \\(one\\|two\\)")
                 2))
      (jetpacs-reader-state-set file :org-search-mode 'sparse)
      (should (eq (jetpacs-reader-org--apply-search file "+work") 'sparse))
      (should-error (progn
                      (jetpacs-reader-state-set file :org-search-mode 'regexp)
                      (jetpacs-reader-org--apply-search file "["))
                    :type 'user-error)
      (jetpacs-reader-state-set file :org-visibility 'contents)
      (jetpacs-reader-org--clear-search-in-buffer
       file (jetpacs-reader-org--buffer file))
      (should (eq (jetpacs-reader-org--visibility file) 'contents)))))

(ert-deftest jetpacs-reader-org-reader-mode-is-buffer-local ()
  "Reader mode hides markup and prettifies entities without global mutation."
  (jetpacs-mode-app-test--with-org-file file "* A *bold* \\alpha\n"
    (let ((jetpacs-reader--state (make-hash-table :test #'equal))
          (global-hide (default-value 'org-hide-emphasis-markers)))
      (let ((buffer (jetpacs-reader-org--buffer file)))
        (jetpacs-reader-org--apply-reader-mode file buffer)
        (with-current-buffer buffer
          (should org-hide-emphasis-markers)
          (should org-pretty-entities)
          (should org-hide-leading-stars))
        (should (eq (default-value 'org-hide-emphasis-markers) global-hide))))))

(ert-deftest jetpacs-editor-org-commands-require-sync-but-snippets-do-not ()
  "Plain editors get local helpers; synchronized editors also get Org commands."
  (let* ((jetpacs-files-editor-context '(:path "/tmp/a.org"))
         (plain (jetpacs-editor-org--toolbar "/tmp/a.org"))
         (plain-commands (jetpacs-mode-app-test--toolbar-commands plain))
         (snippets (jetpacs-mode-app-test--toolbar-snippets plain)))
    (should-not plain-commands)
    (should (member "_${selection}_" snippets))
    (should (member "_{${selection}}" snippets))
    (should (member "[cite:@${input:Key}]" snippets))
    (let* ((jetpacs-files-editor-context
            '(:path "/tmp/a.org" :document "doc:a.org" :editor-id "body"))
           (synced (jetpacs-editor-org--toolbar "/tmp/a.org"))
           (commands (jetpacs-mode-app-test--toolbar-commands synced)))
      (should (member "org-todo" commands))
      (should (member "org-refile" commands))
      (should (member "jetpacs-editor-org-encrypt-entry" commands)))))

(ert-deftest jetpacs-editor-org-installs-buffer-local-crypt-save-hook ()
  "A live Org editor re-encrypts decrypted crypt entries before save."
  (jetpacs-mode-app-test--with-org-file file "* Secret :crypt:\ntext\n"
    (let ((buffer (find-file-noselect file)))
      (jetpacs-editor-org--setup file)
      (with-current-buffer buffer
        (should (memq #'org-encrypt-entries before-save-hook))))))

(ert-deftest jetpacs-editor-org-prewrite-runs-org-crypt-explicitly ()
  "Files' write-region path invokes Org Crypt without relying on save-buffer."
  (with-temp-buffer
    (org-mode)
    (let (called)
      (cl-letf (((symbol-function 'org-encrypt-entries)
                 (lambda () (setq called (current-buffer)))))
        (jetpacs-editor-org--before-save "/tmp/a.org" (current-buffer))
        (should (eq called (current-buffer)))))))

(ert-deftest jetpacs-editor-org-narrowed-body-is-plain-section-editor ()
  "A narrowed Org buffer edits only its subtree with no sync commands."
  (jetpacs-mode-app-test--with-org-file
      file "* One\nfirst\n* Two\nsecond\n"
    (let ((jetpacs-reader--state (make-hash-table :test #'equal))
          (jetpacs-files-editor-context
           (list :path file :mtime "stamp"
                 :document "doc:test.org" :editor-id "body")))
      (let ((buffer (jetpacs-reader-org--buffer file)))
        (with-current-buffer buffer
          (goto-char (point-min))
          (org-narrow-to-subtree))
        (jetpacs-reader-state-set file :presentation 'editor)
        (let* ((node (jetpacs-editor-org--body file))
               (commands
                (jetpacs-mode-app-test--toolbar-commands
                 (append (plist-get node :toolbar) nil))))
          (should (equal (plist-get node :t) "editor"))
          (should-not (plist-get node :document))
          (should (string-search "* One\nfirst" (plist-get node :value)))
          (should-not (string-search "* Two" (plist-get node :value)))
          (should-not commands)
          (should (equal (plist-get (plist-get node :on_save) :action)
                         "jetpacs.editor.org.save-narrowed")))))))

(ert-deftest jetpacs-reader-org-narrow-transition-downgrades-sync ()
  "Switching a narrowed reader to edit removes whole-document sync identity."
  (jetpacs-mode-app-test--with-org-file file "* One\nbody\n* Two\nrest\n"
    (let* ((buffer (jetpacs-reader-org--buffer file))
           (jetpacs-files--edit
            (list :path (file-truename file) :seed "stale"
                  :mtime "stamp" :document "doc:test.org"
                  :editor-id "body" :buffer buffer)))
      (with-current-buffer buffer
        (goto-char (point-min))
        (org-narrow-to-subtree))
      (jetpacs-reader-org--transition file 'editor)
      (should-not (plist-get jetpacs-files--edit :document))
      (should-not (plist-get jetpacs-files--edit :buffer))
      (should (string-search "* Two\nrest"
                             (plist-get jetpacs-files--edit :seed))))))

(ert-deftest jetpacs-editor-org-narrowed-save-splices-only-section ()
  "A validated section save preserves the rest of the Org file."
  (jetpacs-mode-app-test--with-org-file
      file "* One\nfirst\n* Two\nsecond\n"
    (let* ((true (file-truename file))
           (root (file-name-directory true))
           (jetpacs-files-roots (list root))
           (jetpacs-reader--state (make-hash-table :test #'equal))
           (buffer (jetpacs-reader-org--buffer true))
           (jetpacs-files--edit
            (list :path true :seed "" :mtime (jetpacs-files--mtime-stamp true)
                  :coding nil)))
      (with-current-buffer buffer
        (goto-char (point-min))
        (org-narrow-to-subtree))
      (jetpacs-reader-state-set true :presentation 'editor)
      ;; The body records the Emacs-owned bounds and modification tick.
      (let ((jetpacs-files-editor-context jetpacs-files--edit))
        (jetpacs-editor-org--body true))
      (cl-letf (((symbol-function 'jetpacs-shell-notify) #'ignore)
                ((symbol-function 'jetpacs-buffer-defer-refresh) #'ignore))
        (should
         (eq (jetpacs-editor-org--save-narrowed
              (list :path true :mtime (jetpacs-files--mtime-stamp true)
                    :value "* One\nchanged")
              '(:surface "app:jetpacs.files"))
             'accepted)))
      (with-temp-buffer
        (insert-file-contents true)
        (should (equal (buffer-string)
                       "* One\nchanged\n* Two\nsecond\n")))
      (with-current-buffer buffer
        (should (buffer-narrowed-p))
        ;; `org-narrow-to-subtree' excludes the separator newline before
        ;; the next heading; the section editor preserves those exact
        ;; accessible bounds.
        (should (equal (buffer-string) "* One\nchanged"))))))

(ert-deftest jetpacs-editor-org-narrowed-save-rolls-back-before-write-error ()
  "A failed pre-write transform changes neither disk nor visiting buffer."
  (jetpacs-mode-app-test--with-org-file file "* One\nfirst\n* Two\nsecond\n"
    (let* ((true (file-truename file))
           (jetpacs-files-roots (list (file-name-directory true)))
           (jetpacs-reader--state (make-hash-table :test #'equal))
           (buffer (jetpacs-reader-org--buffer true))
           (jetpacs-files--edit
            (list :path true :seed "" :mtime (jetpacs-files--mtime-stamp true)
                  :coding nil)))
      (with-current-buffer buffer
        (goto-char (point-min))
        (org-narrow-to-subtree))
      (jetpacs-reader-state-set true :presentation 'editor)
      (let ((jetpacs-files-editor-context jetpacs-files--edit))
        (jetpacs-editor-org--body true))
      (cl-letf (((symbol-function 'jetpacs-editor--files-before-save)
                 (lambda (&rest _) (error "encryption failed")))
                ((symbol-function 'jetpacs-shell-notify) #'ignore))
        (should
         (eq (jetpacs-editor-org--save-narrowed
              (list :path true :mtime (jetpacs-files--mtime-stamp true)
                    :value "* One\nclear text\n")
              '(:surface "app:jetpacs.files"))
             'rejected)))
      (with-temp-buffer
        (insert-file-contents true)
        (should (equal (buffer-string)
                       "* One\nfirst\n* Two\nsecond\n")))
      (with-current-buffer buffer
        (should (equal (buffer-string) "* One\nfirst"))))))

(ert-deftest jetpacs-org-mode-capture-rents-headless-org-engine ()
  "App capture collects built-in template fields and passes shared text safely."
  (let ((org-capture-templates
         '(("t" "Task" entry (file "/tmp/inbox.org")
            "* TODO %^{Title}\n%?")))
        captured
        notices)
    (cl-letf (((symbol-function 'jetpacs-connected-p) (lambda () t))
              ((symbol-function 'completing-read)
               (lambda (&rest _) "t — Task"))
              ((symbol-function 'read-string)
               (lambda (prompt &optional initial &rest _)
                 (if (string-prefix-p "Headline" prompt)
                     initial
                   "Typed title")))
              ((symbol-function 'ebp-org-capture-run)
               (lambda (key values extra)
                 (setq captured (list key values extra))))
              ((symbol-function 'jetpacs-shell-notify)
               (lambda (text &rest _) (push text notices))))
      (jetpacs-org-mode--capture-now "Shared body" "Shared subject")
      (should (equal captured
                     '("t" (("Headline" . "Shared subject")
                            ("Title" . "Typed title"))
                       "Shared body")))
      (should (member "Captured ✓" notices)))))

(ert-deftest jetpacs-org-mode-share-defers-with-trimmed-payload ()
  "The global share handler preserves its flow and normalizes payload text."
  (let (continued captured)
    (cl-letf (((symbol-function 'jetpacs-connected-p) (lambda () t))
              ((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (setq continued fn)))
              ((symbol-function 'jetpacs-org-mode--capture-now)
               (lambda (text subject) (setq captured (list text subject)))))
      (should (eq (jetpacs-org-mode--on-share
                   '(:text "  Body  " :subject "  Subject ") nil)
                  'accepted))
      (should (functionp continued))
      (funcall continued)
      (should (equal captured '("Body" "Subject"))))))

(ert-deftest jetpacs-org-mode-share-recognizes-org-protocol-capture ()
  "Modern org-protocol capture URLs are decoded by Org's own parser."
  (let ((info
         (jetpacs-org-mode--protocol-info
          (concat
           "org-protocol://capture?template=t&"
           "url=https%3A%2F%2Fexample.org%2Fx&"
           "title=Hello+World&body=Selected"))))
    (should (equal (plist-get info :template) "t"))
    (should (equal (plist-get info :url) "https://example.org/x"))
    (should (equal (plist-get info :title) "Hello World"))
    (should (equal (plist-get info :body) "Selected"))))

(ert-deftest jetpacs-org-mode-reminders-filter-time-and-deduplicate ()
  "Timed Agenda rows become alarms; duplicate schedule/deadline rows do not."
  (let* ((now (encode-time 0 0 12 14 8 2026))
         (items
          (list
           '(:headline "Meeting" :file "/vault/a.org" :pos 42
             :time "13:30......" :date "2026-08-14" :type "scheduled")
           '(:headline "Meeting" :file "/vault/a.org" :pos 42
             :time "13:30......" :date "2026-08-14" :type "deadline")
           '(:headline "Date only" :file "/vault/a.org" :pos 90
             :time nil :date "2026-08-14" :type "scheduled")
           '(:headline "Too late" :file "/vault/b.org" :pos 7
             :time "13:30" :date "2026-08-15" :type "scheduled"))))
    (cl-letf (((symbol-function 'jetpacs-org-mode--agenda-items)
               (lambda (_days) items)))
      (let ((reminders (jetpacs-org-mode--upcoming-reminders 24 now)))
        (should (= 1 (length reminders)))
        (should (equal (plist-get (car reminders) :title) "Meeting"))
        (should (equal (plist-get (car reminders) :body)
                       "13:30 · scheduled"))
        (should (string-match-p "\\`org-rem-[[:xdigit:]]\\{20\\}\\'"
                                (plist-get (car reminders) :id)))))))

(ert-deftest jetpacs-org-mode-seeds-manual-and-inbox-without-overwrite ()
  "The complete manual bundle lands once and user edits always win."
  (let ((org-directory (make-temp-file "jetpacs-org-seed-" t)))
    (unwind-protect
        (let* ((paths (jetpacs-org-mode-seed))
               (inbox (plist-get paths :inbox))
               (manual (plist-get paths :manual))
               (attachment
                (expand-file-name
                 "data/C2/59CE94-D4C8-4C4F-9C9E-9ABE446E7DA3/hello-world.pdf"
                 (plist-get paths :manual-directory))))
          (should (file-readable-p inbox))
          (should (file-readable-p manual))
          (should (file-readable-p attachment))
          (should (file-readable-p
                   (expand-file-name "LICENSE"
                                     (plist-get paths :manual-directory))))
          (with-temp-file inbox (insert "user inbox\n"))
          (with-temp-file manual (insert "user manual note\n"))
          (jetpacs-org-mode-seed)
          (should (equal (with-temp-buffer
                           (insert-file-contents inbox)
                           (buffer-string))
                         "user inbox\n"))
          (should (equal (with-temp-buffer
                           (insert-file-contents manual)
                           (buffer-string))
                         "user manual note\n")))
      (delete-directory org-directory t))))

(ert-deftest jetpacs-org-mode-open-seed-uses-known-path-and-surface ()
  "Seed navigation accepts only known documents and retains the tap surface."
  (let ((file (make-temp-file "jetpacs-seed-open-" nil ".org" "* Manual\n"))
        captured)
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-org-mode-seed)
                   (lambda () (list :manual file :inbox file)))
                  ((symbol-function 'jetpacs-navigate-thunk)
                   (lambda (thunk surface label)
                     (setq captured (list thunk surface label)))))
          (should (eq 'accepted
                      (jetpacs-org-mode--on-open-seed
                       '(:document "manual")
                       '(:surface "app:org-mode"))))
          (should (equal (nth 1 captured) "app:org-mode"))
          (should (equal (nth 2 captured) "Orgro manual"))
          (should (bufferp (funcall (car captured))))
          (should (eq 'rejected
                      (jetpacs-org-mode--on-open-seed
                       '(:document "forged")
                       '(:surface "app:org-mode")))))
      (when-let* ((buffer (get-file-buffer file)))
        (kill-buffer buffer))
      (delete-file file))))

(ert-deftest jetpacs-org-mode-is-a-real-composed-app ()
  "The app claims home, Files, and Habits and installs both Org adapters."
  (let ((entry (assoc jetpacs-org-mode-owner jetpacs-apps--registry)))
    (should entry)
    (should (equal (plist-get (cdr entry) :label) "Org Mode"))
    (should (equal (plist-get (cdr entry) :surfaces)
                   (list jetpacs-org-mode-owner
                         jetpacs-files-owner
                         jetpacs-org-habits-owner)))
    (should (cl-find 'org jetpacs-reader--adapters
                     :key #'jetpacs-reader-adapter-id))
    (should (cl-find 'org jetpacs-editor--adapters
                     :key #'jetpacs-editor-adapter-id))
    (should (memq #'jetpacs-reader--files-body
                  jetpacs-files-editor-body-functions))
    (should (memq #'jetpacs-editor--files-toolbar
                  jetpacs-files-editor-toolbar-functions))
    (should (gethash "org-mode.capture" jetpacs-action-handlers))
    (should (gethash "org-mode.open-seed" jetpacs-action-handlers))
    (should (memq #'jetpacs-org-mode--sync-reminders
                  jetpacs-shell-after-push-hook))))

(provide 'jetpacs-mode-app-test)
;;; jetpacs-mode-app-test.el ends here
