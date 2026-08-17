;;; glasspane-para-test.el --- Gates for the Glasspane PARA ladder -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Focused gates for docs/PLAN-glasspane-para.md.  PA-2a creates this
;; explicitly-wired suite; later PARA rungs add their arms here.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'glasspane)

(defconst glasspane-para-test--areas-source
  (expand-file-name "../emacs/apps/glasspane/glasspane-areas.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The Areas source inspected by its architectural gate.")

(defconst glasspane-para-test--resources-source
  (expand-file-name "../emacs/apps/glasspane/glasspane-resources.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The Resources source inspected by its architectural gate.")

(defmacro glasspane-para-test--with-vault (files &rest body)
  "Create FILES in a temporary local Org vault and evaluate BODY.
FILES is a list of (RELATIVE-NAME CONTENT)."
  (declare (indent 1) (debug t))
  `(let* ((vault (make-temp-file "glasspane-areas" t))
          (org-directory vault)
          (org-agenda-files (list vault))
          (ebp-org-roots (list vault)))
     (unwind-protect
         (progn
           (dolist (spec ,files)
             (let ((path (expand-file-name (car spec) vault)))
               (make-directory (file-name-directory path) t)
               (with-temp-file path (insert (cadr spec)))))
           (ebp-org-cache-invalidate)
           ,@body)
       (ebp-org-cache-invalidate)
       (dolist (buffer (buffer-list))
         (when-let* ((file (buffer-file-name buffer)))
           (when (string-prefix-p (file-name-as-directory
                                   (file-truename vault))
                                  (file-truename file))
             (with-current-buffer buffer (set-buffer-modified-p nil))
             (kill-buffer buffer))))
       (delete-directory vault t))))

(defun glasspane-para-test--area (name index)
  "Find area NAME in INDEX."
  (cl-find name index :key (lambda (area) (plist-get area :name))
           :test #'equal))

(defun glasspane-para-test--action-names (value)
  "Return every action name nested anywhere inside VALUE."
  (let (names)
    (cl-labels ((walk (item)
                  (cond
                   ((vectorp item) (mapc #'walk item))
                   ((consp item)
                    (when (and (keywordp (car item)) (plistp item))
                      (when-let* ((name (plist-get item :action)))
                        (push name names)))
                    (walk (car item))
                    (walk (cdr item))))))
      (walk value))
    (delete-dups names)))

(ert-deftest glasspane-para-areas-bucket-layers-and-open-counts ()
  "Keyword, inherited-property, and basename categories form buckets.
File-only categories survive, done headings do not inflate open counts, and
one file may honestly participate in both its file Area and a nested Area."
  (glasspane-para-test--with-vault
      '(("work.org"
         "#+CATEGORY: Work\n* TODO File task\n* DONE Finished\n* Parent\n:PROPERTIES:\n:CATEGORY: Home\n:END:\n** TODO Inherited task\n")
        ("Reading.org" "* TODO Read a chapter\n")
        ("empty.org" "#+CATEGORY: Empty\n* Reference material\n"))
    (let* ((index (glasspane-areas--index))
           (names (mapcar (lambda (area) (plist-get area :name)) index))
           (work (glasspane-para-test--area "Work" index))
           (home (glasspane-para-test--area "Home" index))
           (reading (glasspane-para-test--area "Reading" index))
           (empty (glasspane-para-test--area "Empty" index)))
      (should (equal names '("Empty" "Home" "Reading" "Work")))
      (should (equal (mapcar (lambda (item) (alist-get 'headline item))
                             (plist-get work :items))
                     '("File task")))
      (should (equal (mapcar (lambda (item) (alist-get 'headline item))
                             (plist-get home :items))
                     '("Inherited task")))
      (should (= (length (plist-get work :files)) 1))
      (should (= (length (plist-get home :files)) 1))
      (should (= (length (plist-get reading :items)) 1))
      (should-not (plist-get empty :items))
      (should (equal (glasspane-areas--count-label work)
                     "1 open TODO · 1 file")))))

(ert-deftest glasspane-para-areas-index-is-memoised ()
  "The named Areas cache key computes its worker once per generation."
  (let ((org-agenda-files nil)
        (calls 0)
        (fixture '((:name "A" :files nil :items nil))))
    (unwind-protect
        (progn
          (ebp-org-cache-invalidate)
          (cl-letf (((symbol-function 'glasspane-areas--index-1)
                     (lambda () (cl-incf calls) fixture)))
            (should (eq (glasspane-areas--index) fixture))
            (should (eq (glasspane-areas--index) fixture))
            (should (= calls 1))))
      (ebp-org-cache-invalidate))))

(ert-deftest glasspane-para-areas-rotten-file-is-local ()
  "A vanished file is skipped while a healthy peer still contributes."
  (glasspane-para-test--with-vault
      '(("good.org" "#+CATEGORY: Good\n* TODO Survives\n"))
    (let ((good (expand-file-name "good.org" vault))
          (gone (expand-file-name "gone.org" vault)))
      (cl-letf (((symbol-function 'glasspane-org-agenda-scope)
                 (lambda () (list gone good))))
        (let ((index (glasspane-areas--index-1)))
          (should (= (length index) 1))
          (should (equal (plist-get (car index) :name) "Good"))
          (should (equal (alist-get 'headline
                                    (car (plist-get (car index) :items)))
                         "Survives")))))))

(ert-deftest glasspane-para-areas-primes-category-before-heading-read ()
  "The Emacs 30.1 category workaround runs before `org-get-category'."
  (glasspane-para-test--with-vault
      '(("prime.org" "#+CATEGORY: Primed\n* TODO Cache path\n"))
    (let ((real-element (symbol-function 'org-element-at-point))
          (real-category (symbol-function 'org-get-category))
          primed early-category-read)
      (cl-letf (((symbol-function 'org-element-at-point)
                 (lambda (&rest args)
                   (save-excursion
                     (beginning-of-line)
                     (when (looking-at-p "[ \t]*#\\+CATEGORY:")
                       (setq primed t)))
                   (apply real-element args)))
                ((symbol-function 'org-get-category)
                 (lambda (&rest args)
                   (unless primed (setq early-category-read t))
                   (apply real-category args))))
        (let ((index (glasspane-areas--index-1)))
          (should primed)
          (should-not early-category-read)
          (should (= (length (plist-get (car index) :items)) 1)))))))

(ert-deftest glasspane-para-areas-plain-arg-and-drill-routing ()
  "The list mints no tokens; rows use strings and route by stable id."
  (let* ((area '(:name "Home" :files ("/vault/home.org") :items nil))
         (row (glasspane-areas--area-row area))
         (tap (plist-get row :on_tap))
         pushed-id pushed-builder token-calls)
    (should (equal (plist-get tap :action) "areas.drill"))
    (should (equal (plist-get tap :args) '(:category "Home")))
    (should-not (plist-member (plist-get tap :args) :token))
    (cl-letf (((symbol-function 'glasspane-areas--index)
               (lambda () (list area)))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (&rest _) (cl-incf token-calls))))
      (should (jetpacs-node-p (glasspane-areas--list-body)))
      (should-not token-calls))
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-chrome-push-screen)
               (lambda (_surface id builder &rest _)
                 (setq pushed-id id pushed-builder builder))))
      (should (eq (glasspane-areas--on-open
                   nil '(:surface "app:glasspane"))
                  'accepted))
      (should (equal pushed-id "glasspane-areas"))
      (should (eq pushed-builder #'glasspane-areas-screen))
      (should (eq (glasspane-areas--on-drill
                   '(:category "Home") '(:surface "app:glasspane"))
                  'accepted))
      (should (equal pushed-id (jetpacs-wire-id "area" "Home")))
      (should (functionp pushed-builder))
      (should (eq (glasspane-areas--on-drill
                   '(:category 7) '(:surface "app:glasspane"))
                  'rejected))
      (should (eq (glasspane-areas--on-drill
                   '(:category "") '(:surface "app:glasspane"))
                  'rejected)))))

(ert-deftest glasspane-para-areas-drill-content-and-vanish-degrade ()
  "The drill has shared cards + Files handoffs; a vanished Area is inert."
  (let* ((item '((headline . "Keep house") (todo . "TODO")
                 (tags . []) (file . "/vault/home.org")))
         (area `(:name "Home" :files ("/vault/home.org") :items (,item)))
         token-sets)
    (cl-letf (((symbol-function 'glasspane-areas--index)
               (lambda () (list area)))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (items set)
                 (push (cons set items) token-sets)
                 items)))
      (let* ((body (glasspane-areas--drill-body "Home"))
             (json (jetpacs-node->canonical-json body)))
        (should (member "resources.open-file"
                        (glasspane-para-test--action-names body)))
        (should (string-search "Open TODOs" json))
        (should (string-search "Files" json))
        (should (equal (caar token-sets) "areas"))
        (let ((screen (glasspane-areas-drill-screen "Home" nil)))
          (should (jetpacs-check-profile screen 'app))
          (should (stringp (jetpacs-node->canonical-json screen))))))
    (setq token-sets nil)
    (cl-letf (((symbol-function 'glasspane-areas--index) (lambda () nil))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (items set)
                 (push (cons set items) token-sets)
                 items)))
      (let ((body (glasspane-areas--drill-body "Gone")))
        (should (equal (plist-get body :t) "empty_state"))
        (should (equal (plist-get body :title) "Area no longer exists"))
        (should (equal token-sets '(("areas"))))))))

(ert-deftest glasspane-para-areas-lifecycle-and-staging ()
  "Glasspane owns both verbs, while the legacy hub does not expose PA-3 early."
  (should (eq (symbol-function 'glasspane-agenda-tokenize)
              'glasspane-agenda--tokenize))
  (dolist (name '("areas.open" "areas.drill"))
    (should (gethash name jetpacs-action-handlers))
    (should (equal (jetpacs--owner-of "action" name) "glasspane")))
  (should-not (member "areas.open"
                      (glasspane-para-test--action-names
                       (glasspane-ui-home-screen nil))))
  (unwind-protect
      (progn
        (glasspane-areas-unregister)
        (dolist (name '("areas.open" "areas.drill"))
          (should-not (gethash name jetpacs-action-handlers))))
    (glasspane-areas-register))
  (dolist (name '("areas.open" "areas.drill"))
    (should (gethash name jetpacs-action-handlers))))

(ert-deftest glasspane-para-areas-source-boundaries ()
  "Areas consumes public seams and contains no duplicate scope/browser path."
  (with-temp-buffer
    (insert-file-contents glasspane-para-test--areas-source)
    (should (search-forward "glasspane-org-agenda-scope" nil t))
    (goto-char (point-min))
    (should (search-forward "glasspane-agenda-tokenize" nil t))
    (goto-char (point-min))
    (should-not (re-search-forward "\\_<org-agenda-files\\_>" nil t))
    (goto-char (point-min))
    (should-not (search-forward "jetpacs-files--" nil t))
    (goto-char (point-min))
    (should-not (search-forward "vulpea-db-" nil t))))

(ert-deftest glasspane-para-resources-delegates-every-path-to-files ()
  "Vault, Org, and non-Org paths all take the one public Files route."
  (let ((org-directory "/vault")
        calls)
    (cl-letf (((symbol-function 'jetpacs-files-open-path)
               (lambda (path surface)
                 (push (list path surface) calls)
                 'accepted)))
      (should (eq (glasspane-resources--on-open nil nil) 'accepted))
      (should (eq (glasspane-resources--on-open-file
                   '(:path "/vault/notes.org") nil)
                  'accepted))
      (should (eq (glasspane-resources--on-open-file
                   '(:path "/vault/reference.pdf") nil)
                  'accepted)))
    (should (equal (nreverse calls)
                   '(("/vault" "app:jetpacs.files")
                     ("/vault/notes.org" "app:jetpacs.files")
                     ("/vault/reference.pdf" "app:jetpacs.files"))))))

(ert-deftest glasspane-para-resources-files-root-refusal-propagates ()
  "The native Files guard rejects both landing and direct paths unchanged."
  (let* ((root (make-temp-file "glasspane-resources-root" t))
         (outside (make-temp-file "glasspane-resources-outside" t))
         (outside-file (expand-file-name "outside.org" outside))
         (org-directory outside)
         (jetpacs-files-roots (list root))
         (jetpacs-files-shared-storage nil)
         notes)
    (unwind-protect
        (progn
          (with-temp-file outside-file (insert "* Outside\n"))
          (cl-letf (((symbol-function 'jetpacs-files-shared-dir) #'ignore)
                    ((symbol-function 'jetpacs-shell-notify)
                     (lambda (text &optional surface)
                       (push (list text surface) notes))))
            (should (eq (glasspane-resources--on-open nil nil) 'rejected))
            (should (eq (glasspane-resources--on-open-file
                         (list :path outside-file) nil)
                        'rejected))
            (should (= (length notes) 2))
            (should (cl-every
                     (lambda (note)
                       (and (string-match-p "outside-roots" (car note))
                            (equal (cadr note) "app:jetpacs.files")))
                     notes))))
      (delete-directory root t)
      (delete-directory outside t))))

(ert-deftest glasspane-para-resources-route-stays-selected-on-files ()
  "A Resources deep link remains selected after the native surface handoff."
  (let ((jetpacs-apps--registry nil)
        (jetpacs-apps--current nil)
        (jetpacs-apps--current-route nil)
        (jetpacs-apps-core-dock-items nil)
        (org-directory "/vault")
        captured pushed)
    (jetpacs-defapp
     "glasspane" :label "Glasspane" :surfaces '("glasspane")
     :chrome 'primary :dock-core nil
     :destinations
     '((:key "resources" :label "Resources" :icon "topic"
        :verb "resources.open")))
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-owned-surface-p)
               (lambda (surface owner)
                 (and (equal surface "app:glasspane")
                      (equal owner "glasspane"))))
              ((symbol-function 'jetpacs-files-open-path)
               (lambda (path surface)
                 (setq captured (list path surface))
                 'accepted))
              ((symbol-function 'jetpacs-shell-push)
               (lambda (surface &rest _)
                 (push surface pushed))))
      (should (eq (jetpacs-apps--action-open
                   '(:app "glasspane" :route "resources") nil)
                  'accepted)))
    (should (equal captured '("/vault" "app:jetpacs.files")))
    (should-not pushed)
    (should (equal jetpacs-apps--current "glasspane"))
    (should (equal jetpacs-apps--current-route "resources"))
    (let ((item (car (jetpacs-apps-dock-items "app:jetpacs.files"))))
      (should (equal (plist-get item :label) "Resources"))
      (should (plist-get item :selected)))))

(ert-deftest glasspane-para-resources-lifecycle-and-staging ()
  "Glasspane owns both delegates while the legacy hub exposes neither."
  (dolist (name '("resources.open" "resources.open-file"))
    (should (gethash name jetpacs-action-handlers))
    (should (equal (jetpacs--owner-of "action" name) "glasspane")))
  (should (equal
           (plist-get (jetpacs-action-schema "resources.open-file") :args)
           '((:name path :type "text" :required t))))
  (let ((home-actions
         (glasspane-para-test--action-names (glasspane-ui-home-screen nil))))
    (should-not (member "resources.open" home-actions))
    (should-not (member "resources.open-file" home-actions)))
  (unwind-protect
      (progn
        (glasspane-resources-unregister)
        (dolist (name '("resources.open" "resources.open-file"))
          (should-not (gethash name jetpacs-action-handlers))))
    (glasspane-resources-register))
  (dolist (name '("resources.open" "resources.open-file"))
    (should (gethash name jetpacs-action-handlers))))

(ert-deftest glasspane-para-resources-source-boundaries ()
  "The Resources section stays a delegate despite Archive sharing its file."
  (with-temp-buffer
    (insert-file-contents glasspane-para-test--resources-source)
    (should (search-forward "jetpacs-files-open-path" nil t))
    (goto-char (point-min))
    (should (search-forward "jetpacs-files-owner" nil t))
    (goto-char (point-min))
    (should-not (search-forward "jetpacs-files--" nil t))
    (let ((start (progn
                   (goto-char (point-min))
                   (search-forward ";;;; Resources delegation")
                   (point)))
          (end (progn
                 (search-forward ";;;; Archive index and screen")
                 (line-beginning-position))))
      (save-restriction
        (narrow-to-region start end)
        (goto-char (point-min))
        (should-not (re-search-forward
                     "\\_<\\(directory-files\\(?:-recursively\\)?\\|file-expand-wildcards\\)\\_>"
                     nil t))
        (goto-char (point-min))
        (should-not (re-search-forward
                     "\\_<\\(jetpacs-chrome-screen\\|jetpacs-chrome-row\\|jetpacs-lazy-column\\)\\_>"
                     nil t))))))

(ert-deftest glasspane-para-archive-index-includes-metadata-and-stops-at-cap ()
  "The bounded walk includes `_archive' files with one metadata read each."
  (glasspane-para-test--with-vault
      '(("a.org_archive" "* Archived A\n")
        ("b.org_archive" "* Archived B\n")
        ("c.org_archive" "* Archived C\n")
        ("z.org" "* Live\n"))
    (let ((real-attributes (symbol-function 'file-attributes))
          (attribute-calls 0))
      (cl-letf (((symbol-function 'file-attributes)
                 (lambda (path &rest args)
                   (when (string-suffix-p "_archive" path t)
                     (cl-incf attribute-calls))
                   (apply real-attributes path args))))
        (let* ((glasspane-resources-archive-scan-cap 2)
               (records (glasspane-resources--archive-files-1)))
          (should (equal (mapcar (lambda (record)
                                  (file-name-nondirectory
                                   (plist-get record :path)))
                                records)
                         '("a.org_archive" "b.org_archive")))
          (should (cl-every (lambda (record) (plist-get record :mtime))
                            records))
          (should (= attribute-calls 2)))
        (setq attribute-calls 0)
        (let* ((glasspane-resources-archive-scan-cap 20)
               (records (glasspane-resources--archive-files-1)))
          (should (equal (mapcar (lambda (record)
                                  (file-name-nondirectory
                                   (plist-get record :path)))
                                records)
                         '("a.org_archive" "b.org_archive" "c.org_archive")))
          (should (= attribute-calls 3)))))))

(ert-deftest glasspane-para-archive-cache-refreshes-outside-agenda-stamp ()
  "Archive membership is memoized until its explicit refresh hook runs."
  (let ((org-agenda-files nil)
        (calls 0))
    (unwind-protect
        (progn
          (ebp-org-cache-invalidate)
          (should (memq #'glasspane-resources--refresh-invalidate
                        jetpacs-shell-refresh-hook))
          (cl-letf (((symbol-function 'glasspane-resources--archive-files-1)
                     (lambda ()
                       (cl-incf calls)
                       (list (list :path (format "/archive-%d" calls)
                                   :mtime (current-time))))))
            (should (equal (glasspane-resources--archive-files)
                           (glasspane-resources--archive-files)))
            (should (= calls 1))
            (let ((jetpacs-shell-refresh-hook
                   '(glasspane-resources--refresh-invalidate)))
              (run-hooks 'jetpacs-shell-refresh-hook))
            (glasspane-resources--archive-files)
            (should (= calls 2))))
      (ebp-org-cache-invalidate))))

(ert-deftest glasspane-para-archive-screen-route-and-lifecycle ()
  "Archive renders file handoffs and remains a staged drawer destination."
  (let* ((mtime (encode-time 0 30 14 16 8 2026))
         (record (list :path "/vault/work.org_archive" :mtime mtime))
         (row (glasspane-resources--archive-row record))
         (tap (plist-get row :on_tap))
         pushed)
    (should (equal (plist-get tap :action) "resources.open-file"))
    (should (equal (plist-get tap :args)
                   '(:path "/vault/work.org_archive")))
    (should (string-search "work.org"
                           (jetpacs-node->canonical-json row)))
    (should (string-search "Modified 2026-08-16 14:30"
                           (jetpacs-node->canonical-json row)))
    (cl-letf (((symbol-function 'glasspane-resources--archive-files)
               (lambda () (list record))))
      (let ((screen (glasspane-resources-archive-screen nil)))
        (should (jetpacs-check-profile screen 'app))
        (should (stringp (jetpacs-node->canonical-json screen)))))
    (cl-letf (((symbol-function 'glasspane-resources--archive-files)
               (lambda () nil)))
      (should (equal (plist-get (glasspane-resources--archive-body) :t)
                     "empty_state")))
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-chrome-push-screen)
               (lambda (surface id builder &rest _)
                 (setq pushed (list surface id builder)))))
      (should (eq (glasspane-resources--on-archive-open
                   nil '(:surface "app:glasspane"))
                  'accepted)))
    (should (equal (seq-take pushed 2)
                   '("app:glasspane" "glasspane-archive")))
    (should (eq (nth 2 pushed) #'glasspane-resources-archive-screen)))
  (should (gethash "archive.open" jetpacs-action-handlers))
  (should (equal (jetpacs--owner-of "action" "archive.open") "glasspane"))
  (should-not (member "archive.open"
                      (glasspane-para-test--action-names
                       (glasspane-ui-home-screen nil))))
  (unwind-protect
      (progn
        (glasspane-resources-unregister)
        (dolist (name '("resources.open" "resources.open-file"
                        "archive.open"))
          (should-not (gethash name jetpacs-action-handlers)))
        (should-not (memq #'glasspane-resources--refresh-invalidate
                          jetpacs-shell-refresh-hook)))
    (glasspane-resources-register))
  (should (gethash "archive.open" jetpacs-action-handlers))
  (should (memq #'glasspane-resources--refresh-invalidate
                jetpacs-shell-refresh-hook)))

(ert-deftest glasspane-para-archive-native-recognition-and-root-policy ()
  "Org archives pass both native predicates and the real Files root guard."
  (glasspane-para-test--with-vault
      '(("project.org_archive" "* Archived project\n"))
    (let* ((archive (expand-file-name "project.org_archive" vault))
           (jetpacs-files-roots (list vault))
           (jetpacs-files-shared-storage nil)
           queued)
      (should (ebp-org-file-allowed-p archive))
      (should (jetpacs-reader-org-path-p archive))
      (should (jetpacs-org-render--org-path-p archive))
      (cl-letf (((symbol-function 'jetpacs-files-shared-dir) #'ignore)
                ((symbol-function 'jetpacs-flow-continue)
                 (lambda (fn) (push fn queued))))
        (should (eq (glasspane-resources--on-open-file
                     (list :path archive) nil)
                    'accepted))
        (should (= (length queued) 1))))))

(ert-deftest glasspane-para-archive-source-has-no-unarchive-path ()
  "Archive is a read/open index; no speculative reverse operation exists."
  (with-temp-buffer
    (insert-file-contents glasspane-para-test--resources-source)
    (should (search-forward "_archive" nil t))
    (goto-char (point-min))
    (should (search-forward "resources.open-file" nil t))
    (goto-char (point-min))
    (should-not (search-forward "unarchive" nil t))))

(provide 'glasspane-para-test)
;;; glasspane-para-test.el ends here
