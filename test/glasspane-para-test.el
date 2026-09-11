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
  (expand-file-name "../glasspane-areas.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The Areas source inspected by its architectural gate.")

(defconst glasspane-para-test--resources-source
  (expand-file-name "../glasspane-resources.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The Resources source inspected by its architectural gate.")

(defconst glasspane-para-test--projects-source
  (expand-file-name "../glasspane-projects.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The Projects source inspected by its architectural gate.")

(defconst glasspane-para-test--agenda-source
  (expand-file-name "../glasspane-agenda.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The Agenda source inspected after the Tasks promotion.")

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

(defun glasspane-para-test--builder-routes-p (builder screen)
  "Return non-nil when BUILDER is SCREEN or a Tier-1 wrapper around it.
`glasspane-ui-open-destination' hides the back arrow on a Tier-1 peer by
wrapping the screen builder and calling it with a nil BACK; a drill keeps
the builder itself."
  (or (eq builder screen)
      (and (functionp builder)
           (let (called)
             (cl-letf (((symbol-function screen)
                        (lambda (back) (setq called (list 'called back)))))
               (funcall builder 'probe))
             (equal called '(called nil))))))

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

(defun glasspane-para-test--actions (value)
  "Return every action descriptor nested anywhere inside VALUE."
  (let (actions)
    (cl-labels ((walk (item)
                  (cond
                   ((vectorp item) (mapc #'walk item))
                   ((consp item)
                    (when (and (keywordp (car item)) (plistp item)
                               (stringp (plist-get item :action)))
                      (push item actions))
                    (walk (car item))
                    (walk (cdr item))))))
      (walk value))
    (nreverse actions)))

(defun glasspane-para-test--node-texts (node)
  "Return every text-node payload below NODE, in document order."
  (let (texts)
    (cl-labels
        ((walk (value)
           (cond
            ((vectorp value) (mapc #'walk value))
            ((consp value)
             (when (and (keywordp (car-safe value))
                        (equal (plist-get value :t) "text"))
               (push (plist-get value :text) texts))
             (mapc #'walk value)))))
      (walk node))
    (nreverse texts)))

(defun glasspane-para-test--nodes-of-type (node type)
  "Return every node below NODE whose wire type is TYPE."
  (let (nodes)
    (cl-labels
        ((walk (value)
           (cond
            ((vectorp value) (mapc #'walk value))
            ((consp value)
             (when (and (keywordp (car-safe value))
                        (equal (plist-get value :t) type))
               (push value nodes))
             (mapc #'walk value)))))
      (walk node))
    (nreverse nodes)))

(ert-deftest glasspane-para-areas-group-tags-inheritance-and-open-counts ()
  "Area-group members use FILETAGS and inherited heading tags.
Unused declared Areas remain visible, non-TODO headings classify Resources,
done headings do not inflate project counts, and CATEGORY creates no Area."
  (glasspane-para-test--with-vault
      '(("work.org"
         "#+CATEGORY: LegacyWork\n#+TAGS: [ Area : Work Home Empty Unused ]\n#+FILETAGS: :Work:\n* TODO File task\n* DONE Finished\n* Parent :Home:\n** TODO Inherited task\n* Reference material :Empty:\n")
        ("reading.org"
         "#+TAGS: [ Area : Reading ]\n* TODO Read a chapter :Reading:\n")
        ("category-only.org"
         "#+CATEGORY: Inbox\n* TODO Not an Area\n"))
    (let* ((index (glasspane-areas--index))
           (names (mapcar (lambda (area) (plist-get area :name)) index))
           (work (glasspane-para-test--area "Work" index))
           (home (glasspane-para-test--area "Home" index))
           (reading (glasspane-para-test--area "Reading" index))
           (empty (glasspane-para-test--area "Empty" index))
           (unused (glasspane-para-test--area "Unused" index)))
      (should (equal names '("Empty" "Home" "Reading" "Unused" "Work")))
      (should (equal (mapcar (lambda (item) (alist-get 'headline item))
                             (plist-get work :items))
                     '("File task" "Inherited task")))
      (should (equal (mapcar (lambda (item) (alist-get 'headline item))
                             (plist-get home :items))
                     '("Inherited task")))
      (should (equal (alist-get 'areas (car (plist-get home :items)))
                     ["Work" "Home"]))
      (should (= (length (plist-get work :files)) 1))
      (should (= (length (plist-get home :files)) 1))
      (should (= (length (plist-get reading :items)) 1))
      (should-not (plist-get empty :items))
      (should (= (length (plist-get empty :files)) 1))
      (should-not (plist-get unused :items))
      (should-not (plist-get unused :files))
      (should-not (glasspane-para-test--area "LegacyWork" index))
      (should-not (glasspane-para-test--area "Inbox" index))
      (should (equal (glasspane-areas--count-label work)
                     "2 open TODOs · 1 file")))))

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
      '(("good.org"
         "#+TAGS: [ Area : Good ]\n* TODO Survives :Good:\n"))
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

(ert-deftest glasspane-para-areas-global-group-declares-unused-members ()
  "The global Area group supplies rows; categories still supply none."
  (glasspane-para-test--with-vault
      '(("global.org"
         "#+CATEGORY: Ignored\n* TODO Tagged :House:\n"))
    (let ((org-tag-alist
           '((:startgrouptag) ("Area") (:grouptags)
             ("House") ("Auto") (:endgrouptag))))
      (ebp-org-cache-invalidate)
      (let* ((index (glasspane-areas--index))
             (house (glasspane-para-test--area "House" index))
             (auto (glasspane-para-test--area "Auto" index)))
        (should (equal (mapcar (lambda (area) (plist-get area :name)) index)
                       '("Auto" "House")))
        (should (equal (mapcar (lambda (item) (alist-get 'headline item))
                               (plist-get house :items))
                       '("Tagged")))
        (should-not (plist-get auto :items))
        (should-not (plist-get auto :files))
        (should-not (glasspane-para-test--area "Ignored" index))))))

(ert-deftest glasspane-para-areas-plain-arg-and-drill-routing ()
  "The list mints no tokens; rows use strings and route by stable id."
  (let* ((glasspane-areas--filter-state (make-hash-table :test #'equal))
         (glasspane-areas--todo-filter-state (make-hash-table :test #'equal))
         (area '(:name "Home" :files ("/vault/home.org") :items nil))
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
      (should (glasspane-para-test--builder-routes-p
               pushed-builder #'glasspane-areas-screen))
      (puthash "Home" "NEXT" glasspane-areas--todo-filter-state)
      (should (eq (glasspane-areas--on-drill
                   '(:category "Home") '(:surface "app:glasspane"))
                  'accepted))
      (should (equal pushed-id (jetpacs-wire-id "area" "Home")))
      (should (functionp pushed-builder))
      (should (equal (gethash "Home" glasspane-areas--filter-state)
                     '("Home")))
      (should (equal (gethash "Home" glasspane-areas--todo-filter-state)
                     "ALL"))
      (should (eq (glasspane-areas--on-drill
                   '(:category 7) '(:surface "app:glasspane"))
                  'rejected))
      (should (eq (glasspane-areas--on-drill
                   '(:category "") '(:surface "app:glasspane"))
                  'rejected)))))

(ert-deftest glasspane-para-areas-drill-content-and-vanish-degrade ()
  "Area sections use PARA names and scoped handoffs; vanished Areas are inert."
  (let* ((glasspane-areas--filter-state (make-hash-table :test #'equal))
         (item '((headline . "Keep house") (todo . "TODO")
                 (tags . ["Home"]) (areas . ["Home"])
                 (file . "/vault/home.org")))
         (area `(:name "Home" :files ("/vault/home.org") :items (,item)))
         (archive (list :path "/vault/home.org_archive"
                        :mtime (encode-time 0 30 9 2 1 2026)))
         archive-files
         token-sets)
    (cl-letf (((symbol-function 'glasspane-areas--index)
               (lambda () (list area)))
              ((symbol-function 'glasspane-resources-archives-for-files)
               (lambda (files)
                 (setq archive-files files)
                 (list archive)))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (items set)
                 (push (cons set items) token-sets)
                 items)))
      (let* ((body (glasspane-areas--drill-body "Home"))
             (json (jetpacs-node->canonical-json body))
             (actions (glasspane-para-test--actions body)))
        (should (member "glasspane.document.open"
                        (glasspane-para-test--action-names body)))
        (dolist (action actions)
          (when (equal (plist-get action :action) "glasspane.document.open")
            (should (equal (plist-get action :open_surface)
                           "app:jetpacs.files"))))
        (should (string-search "Projects" json))
        (should (string-search "Resources" json))
        (should (string-search "Archives" json))
        (should (string-search "areas.filter" json))
        (should-not (string-search "Open TODOs" json))
        (should (equal archive-files '("/vault/home.org")))
        (should (cl-some
                 (lambda (action)
                   (equal (plist-get (plist-get action :args) :path)
                          "/vault/home.org_archive"))
                 actions))
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

(ert-deftest glasspane-para-areas-intersection-filters-all-sections ()
  "Area chips apply AND membership to Projects, Resources, and Archives."
  (let* ((glasspane-areas--filter-state (make-hash-table :test #'equal))
         (inbox-only
          '((headline . "Inbox only") (todo . "TODO") (tags . ["Inbox"])
            (areas . ["Inbox"])
            (file . "/vault/inbox.org")))
         (inbox-house
          '((headline . "Shared house project") (todo . "NEXT")
            (tags . ["Inbox" "House"]) (areas . ["Inbox" "House"])
            (file . "/vault/inbox.org")))
         (house-only
          '((headline . "House only") (todo . "TODO") (tags . ["House"])
            (areas . ["House"])
            (file . "/vault/house.org")))
         (index `((:name "Bills" :files ("/vault/bills.org") :items nil)
                  (:name "House"
                   :files ("/vault/house.org" "/vault/inbox.org")
                   :items (,house-only ,inbox-house))
                  (:name "Inbox" :files ("/vault/inbox.org")
                   :items (,inbox-only ,inbox-house))))
         archive-files)
    (cl-letf (((symbol-function 'glasspane-areas--index) (lambda () index))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (items _set) items))
              ((symbol-function 'glasspane-resources-archives-for-files)
               (lambda (files)
                 (setq archive-files files)
                 (mapcar (lambda (file)
                           (list :path (concat file "_archive")
                                 :mtime (encode-time 0 0 9 1 1 2026)))
                         files))))
      (let* ((body (glasspane-areas--drill-body "Inbox"))
             (flow (aref (plist-get body :children) 0))
             (chips (append (plist-get flow :children) nil))
             (json (jetpacs-node->canonical-json body)))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label)) chips)
                       '("Inbox" "Bills" "House")))
        (should (equal (mapcar (lambda (chip) (plist-get chip :selected))
                               chips)
                       '(t :json-false :json-false)))
        (should (equal
                 (mapcar (lambda (chip)
                           (plist-get (plist-get chip :on_tap) :args))
                         chips)
                 '((:category "Inbox" :area "Inbox")
                   (:category "Inbox" :area "Bills")
                   (:category "Inbox" :area "House"))))
        (should (string-search "Inbox only" json))
        (should (string-search "Shared house project" json))
        (should-not (string-search "House only" json)))
      (puthash "Inbox" '("Inbox" "House")
               glasspane-areas--filter-state)
      (let* ((body (glasspane-areas--drill-body "Inbox"))
             (flow (aref (plist-get body :children) 0))
             (chips (append (plist-get flow :children) nil))
             (json (jetpacs-node->canonical-json body)))
        (should (equal (mapcar (lambda (chip) (plist-get chip :selected))
                               chips)
                       '(t :json-false t)))
        (should-not (string-search "Inbox only" json))
        (should (string-search "Shared house project" json))
        (should-not (string-search "House only" json))
        (should (equal archive-files '("/vault/inbox.org")))
        (should (string-search "/vault/inbox.org_archive" json))
        (should-not (string-search "/vault/house.org" json))))))

(ert-deftest glasspane-para-areas-projects-todo-filter-chips-and-token-boundary ()
  "Area Project chips show represented states and filter before tokenization."
  (let* ((glasspane-areas--filter-state (make-hash-table :test #'equal))
         (glasspane-areas--todo-filter-state (make-hash-table :test #'equal))
         (todo '((headline . "Inbox task") (todo . "TODO")
                 (areas . ["Inbox"]) (file . "/vault/inbox.org")))
         (next '((headline . "Next inbox task") (todo . "NEXT")
                 (areas . ["Inbox"]) (file . "/vault/inbox.org")))
         (waiting '((headline . "Waiting inbox task") (todo . "WAITING")
                    (areas . ["Inbox"]) (file . "/vault/inbox.org")))
         (area `(:name "Inbox" :files ("/vault/inbox.org")
                        :items (,todo ,next ,waiting)))
         tokenized)
    (puthash "Inbox" "NEXT" glasspane-areas--todo-filter-state)
    (cl-letf (((symbol-function 'glasspane-areas--index)
               (lambda () (list area)))
              ((symbol-function 'glasspane-org-workflow-keywords)
               (lambda (_items) '("TODO" "NEXT" "WAITING" "DONE")))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (items _set)
                 (setq tokenized items)
                 items))
              ((symbol-function 'glasspane-resources-archives-for-files)
               (lambda (_files) nil)))
      (let* ((body (glasspane-areas--drill-body "Inbox"))
             (children (append (plist-get body :children) nil))
             (row (nth 2 children))
             (chips (append (plist-get row :children) nil))
             (json (jetpacs-node->canonical-json body)))
        (should (equal (plist-get row :t) "row"))
        (should (eq (plist-get row :scroll) t))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label)) chips)
                       '("ALL" "TODO" "NEXT" "WAITING")))
        (should (equal (mapcar (lambda (chip) (plist-get chip :selected))
                               chips)
                       '(:json-false :json-false t :json-false)))
        (should
         (equal
          (mapcar (lambda (chip)
                    (plist-get (plist-get chip :on_tap) :args))
                  chips)
          '((:category "Inbox" :filter "ALL")
            (:category "Inbox" :filter "TODO")
            (:category "Inbox" :filter "NEXT")
            (:category "Inbox" :filter "WAITING"))))
        (should (equal tokenized (list next)))
        (should (string-search "Next inbox task" json))
        (should-not (string-search "Inbox task" json))
        (should-not (string-search "Waiting inbox task" json))))))

(ert-deftest glasspane-para-areas-todo-filter-action-is-per-area ()
  "Area TODO filters select independently, reset to ALL, and validate input."
  (let* ((glasspane-areas--todo-filter-state (make-hash-table :test #'equal))
         (index '((:name "House" :files nil :items nil)
                  (:name "Inbox" :files nil :items nil)))
         refreshes)
    (puthash "House" "TODO" glasspane-areas--todo-filter-state)
    (cl-letf (((symbol-function 'glasspane-areas--index) (lambda () index))
              ((symbol-function 'jetpacs-app-defer-refresh)
               (lambda (params) (push params refreshes))))
      (should (eq (glasspane-areas--on-todo-filter
                   '(:category "Inbox" :filter "NEXT") '(:surface "areas"))
                  'accepted))
      (should (equal (glasspane-areas--todo-filter "Inbox") "NEXT"))
      (should (equal (glasspane-areas--todo-filter "House") "TODO"))
      (should (eq (glasspane-areas--on-todo-filter
                   '(:category "Inbox" :filter "ALL") '(:surface "areas"))
                  'accepted))
      (should (equal (glasspane-areas--todo-filter "Inbox") "ALL"))
      (should (eq (glasspane-areas--on-todo-filter
                   '(:category "Gone" :filter "TODO") nil)
                  'rejected))
      (should (eq (glasspane-areas--on-todo-filter
                   '(:category "Inbox" :filter "") nil)
                  'rejected))
      (should (eq (glasspane-areas--on-todo-filter
                   '(:category "Inbox" :filter 7) nil)
                  'rejected))
      (should (= (length refreshes) 2)))))

(ert-deftest glasspane-para-areas-filter-action-toggles-and-resets ()
  "Secondary chips toggle; tapping the primary chip clears the intersection."
  (let* ((glasspane-areas--filter-state (make-hash-table :test #'equal))
         (index '((:name "House" :files nil :items nil)
                  (:name "Inbox" :files nil :items nil)))
         refreshes)
    (cl-letf (((symbol-function 'glasspane-areas--index) (lambda () index))
              ((symbol-function 'jetpacs-app-defer-refresh)
               (lambda (params) (push params refreshes))))
      (should (eq (glasspane-areas--on-filter
                   '(:category "Inbox" :area "House") '(:surface "areas"))
                  'accepted))
      (should (equal (gethash "Inbox" glasspane-areas--filter-state)
                     '("Inbox" "House")))
      (should (eq (glasspane-areas--on-filter
                   '(:category "Inbox" :area "House") '(:surface "areas"))
                  'accepted))
      (should (equal (gethash "Inbox" glasspane-areas--filter-state)
                     '("Inbox")))
      (glasspane-areas--on-filter
       '(:category "Inbox" :area "House") '(:surface "areas"))
      (should (eq (glasspane-areas--on-filter
                   '(:category "Inbox" :area "Inbox") '(:surface "areas"))
                  'accepted))
      (should (equal (gethash "Inbox" glasspane-areas--filter-state)
                     '("Inbox")))
      (should (eq (glasspane-areas--on-filter
                   '(:category "Inbox" :area "Gone") '(:surface "areas"))
                  'rejected))
      (should (eq (glasspane-areas--on-filter
                   '(:category 7 :area "House") '(:surface "areas"))
                  'rejected))
      (should (= (length refreshes) 4)))))

(ert-deftest glasspane-para-areas-archives-match-source-resources ()
  "An Area receives only standard sibling archives for its source files."
  (let ((records (list (list :path "/vault/home.org_archive" :mtime '(1 2))
                       (list :path "/vault/work.org_archive" :mtime '(3 4))
                       (list :path "/vault/nested/home.org_archive" :mtime '(5 6)))))
    (cl-letf (((symbol-function 'glasspane-resources--archive-files)
               (lambda () records)))
      (should
       (equal (mapcar (lambda (record) (plist-get record :path))
                      (glasspane-resources-archives-for-files
                       '("/vault/home.org" "/vault/absent.org")))
              '("/vault/home.org_archive"))))))

(ert-deftest glasspane-para-areas-lifecycle-and-navigation ()
  "Glasspane owns its opener, drill route, and drill filter controls."
  (should (eq (symbol-function 'glasspane-agenda-tokenize)
              'glasspane-agenda--tokenize))
  (dolist (name glasspane-areas--verbs)
    (should (gethash name jetpacs-action-handlers))
    (should (equal (jetpacs--owner-of "action" name) "glasspane")))
  (should (member "areas.open"
                  (glasspane-para-test--action-names
                   (glasspane-ui-home-screen nil))))
  (unwind-protect
      (progn
        (glasspane-areas-unregister)
        (dolist (name glasspane-areas--verbs)
          (should-not (gethash name jetpacs-action-handlers))))
    (glasspane-areas-register))
  (dolist (name glasspane-areas--verbs)
    (should (gethash name jetpacs-action-handlers))))

(ert-deftest glasspane-para-areas-source-boundaries ()
  "Areas consumes tag groups/public seams and has no category fallback."
  (with-temp-buffer
    (insert-file-contents glasspane-para-test--areas-source)
    (should (search-forward "glasspane-org-agenda-scope" nil t))
    (goto-char (point-min))
    (should (search-forward "glasspane-agenda-tokenize" nil t))
    (goto-char (point-min))
    (should (search-forward "glasspane-org-workflow-keywords" nil t))
    (goto-char (point-min))
    (should (search-forward "org-tag-groups-alist" nil t))
    (goto-char (point-min))
    (should (search-forward "org-get-tags" nil t))
    (goto-char (point-min))
    (should-not (search-forward "org-get-category" nil t))
    (goto-char (point-min))
    (should-not (re-search-forward "\\_<org-agenda-files\\_>" nil t))
    (goto-char (point-min))
    (should-not (search-forward "jetpacs-files--" nil t))
    (goto-char (point-min))
    (should-not (search-forward "glasspane-projects--" nil t))
    (goto-char (point-min))
    (should-not (search-forward "vulpea-db-" nil t))))

(ert-deftest glasspane-para-resources-delegates-every-path-to-files ()
  "Vault, Org, and non-Org paths all take the one public Files route."
  (let ((org-directory "/vault")
        (glasspane-ui-legacy-ia nil)
        calls)
    (cl-letf (((symbol-function 'jetpacs-feature-advertised-p)
               (lambda (&rest _) t))
              ((symbol-function 'jetpacs-files-open-path)
               (lambda (path surface &optional mark-pos browser-id browser-fab
                             return-action)
                 (push (list path surface mark-pos browser-id browser-fab
                             return-action)
                       calls)
                 'accepted)))
      (should (eq (glasspane-resources--on-open nil nil) 'accepted))
      (should (eq (glasspane-resources--on-open-file
                   '(:path "/vault/notes.org") nil)
                  'accepted))
      (should (eq (glasspane-resources--on-open-file
                   '(:path "/vault/reference.pdf") nil)
                  'accepted)))
    (setq calls (nreverse calls))
    (should (equal (mapcar (lambda (call) (seq-take call 4)) calls)
                   '(("/vault" "app:jetpacs.files" nil "files-resources")
                     ("/vault/notes.org" "app:jetpacs.files"
                      nil "files-return")
                     ("/vault/reference.pdf" "app:jetpacs.files"
                      nil "files-return"))))
    (should (equal (glasspane-para-test--action-names (nth 4 (car calls)))
                   '("org.capture.show")))
    (should-not (nth 4 (cadr calls)))
    (should-not (nth 4 (caddr calls)))
    ;; NAVIGATION.org: every Files trip returns to the untouched Glasspane
    ;; stack through the one cross-surface return verb.
    (dolist (call calls)
      (should (equal (plist-get (nth 5 call) :action)
                     "glasspane.files.return"))
      (should (equal (plist-get (nth 5 call) :open_surface)
                     "app:glasspane")))))

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
              ((symbol-function 'jetpacs-feature-advertised-p)
               (lambda (&rest _) t))
              ((symbol-function 'jetpacs-owned-surface-p)
               (lambda (surface owner)
                 (and (equal surface "app:glasspane")
                      (equal owner "glasspane"))))
              ((symbol-function 'jetpacs-files-open-path)
               (lambda (path surface &optional mark-pos browser-id browser-fab
                             return-action)
                 (setq captured
                       (list path surface mark-pos browser-id browser-fab
                             return-action))
                 'accepted))
              ((symbol-function 'jetpacs-shell-push)
               (lambda (surface &rest _)
                 (push surface pushed))))
      (should (eq (jetpacs-apps--action-open
                   '(:app "glasspane" :route "resources") nil)
                  'accepted)))
    (should (equal (seq-take captured 4)
                   '("/vault" "app:jetpacs.files" nil "files-resources")))
    (should (equal (glasspane-para-test--action-names (nth 4 captured))
                   '("org.capture.show")))
    (should (equal (plist-get (nth 5 captured) :action)
                   "glasspane.files.return"))
    (should (equal (plist-get (nth 5 captured) :open_surface)
                   "app:glasspane"))
    (should-not pushed)
    (should (equal jetpacs-apps--current "glasspane"))
    (should (equal jetpacs-apps--current-route "resources"))
    (let ((item (car (jetpacs-apps-dock-items "app:jetpacs.files"))))
      (should (equal (plist-get item :label) "Resources"))
      (should (plist-get item :selected)))))

(ert-deftest glasspane-para-resources-local-back-handoffs-are-bounded ()
  "Files returns direct rows to their exact origin and Resources to Agenda."
  (let ((glasspane-ui-legacy-ia nil)
        (jetpacs-apps--current "glasspane")
        (jetpacs-apps--current-route "areas")
        (files (glasspane-resources--files-surface))
        opened pushed continued)
    (cl-letf (((symbol-function 'glasspane-ui-open-destination)
               (lambda (&rest args) (setq opened args) 'accepted))
              ((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (setq continued t) (funcall fn)))
              ((symbol-function 'jetpacs-shell-push)
               (lambda (surface &rest _) (push surface pushed) 1)))
      ;; Back from a direct Areas/Archive file reaches the caller-owned
      ;; return screen, then re-presents the untouched Glasspane stack.
      ;; NAVIGATION.org: the navigation module alone owns that return.
      (glasspane-navigation--on-view-change
       files (jetpacs-chrome-guest-screen-id "glasspane" "files-return"))
      (glasspane-resources--on-view-change
       files (jetpacs-chrome-guest-screen-id "glasspane" "files-return"))
      (should continued)
      (should (equal pushed '("app:glasspane")))
      (should-not opened)
      ;; The Resources browser's own Back reaches Files' root, then resets
      ;; the cross-surface destination to Agenda exactly once.
      (setq continued nil pushed nil
            jetpacs-apps--current-route "resources")
      (glasspane-resources--on-view-change files "browser")
      (should (equal (seq-take opened 2)
                     '("agenda" "glasspane-agenda")))
      (should (eq (nth 2 opened) #'glasspane-agenda-screen))
      (should (equal (nth 3 opened) '(:surface "app:glasspane")))
      (should-not continued)
      (should-not pushed)
      ;; Foreign views and a non-Glasspane current app cannot hijack Back.
      (setq opened nil jetpacs-apps--current "other")
      (glasspane-resources--on-view-change files "browser")
      (glasspane-resources--on-view-change
       "app:other"
       (jetpacs-chrome-guest-screen-id "glasspane" "files-return"))
      (should-not opened)
      (should-not continued)
      (should-not pushed))))

(ert-deftest glasspane-para-resources-lifecycle-and-navigation ()
  "Glasspane owns both delegates while PA-3 exposes only the place opener."
  (dolist (name '("resources.open" "resources.open-file" "resources.return"))
    (should (gethash name jetpacs-action-handlers))
    (should (equal (jetpacs--owner-of "action" name) "glasspane")))
  (should (equal
           (plist-get (jetpacs-action-schema "resources.open-file") :args)
           '((:name path :type "text" :required t))))
  (let ((home-actions
         (glasspane-para-test--action-names (glasspane-ui-home-screen nil))))
    (should (member "resources.open" home-actions))
    (should-not (member "resources.open-file" home-actions)))
  (unwind-protect
      (progn
        (glasspane-resources-unregister)
        (dolist (name '("resources.open" "resources.open-file"
                        "resources.return"))
          (should-not (gethash name jetpacs-action-handlers))))
    (glasspane-resources-register))
  (dolist (name '("resources.open" "resources.open-file" "resources.return"))
    (should (gethash name jetpacs-action-handlers))))

(ert-deftest glasspane-para-resources-source-boundaries ()
  "The Resources section stays a delegate despite Archive sharing its file."
  (with-temp-buffer
    (insert-file-contents glasspane-para-test--resources-source)
    ;; NAVIGATION.org: the applet's only low-level Files boundary is
    ;; glasspane-navigation; Resources never names Files' seam itself.
    (should (search-forward "glasspane-navigation-open-files-path" nil t))
    (goto-char (point-min))
    (should (search-forward "glasspane-navigation-files-surface" nil t))
    (goto-char (point-min))
    (should-not (search-forward "jetpacs-files-open-path" nil t))
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
  "Archive renders file handoffs and is exposed as a drawer destination."
  (let* ((mtime (encode-time 0 30 14 16 8 2026))
         (record (list :path "/vault/work.org_archive" :mtime mtime))
         (row (glasspane-resources--archive-row record))
         (tap (plist-get row :on_tap))
         pushed)
    (should (equal (plist-get tap :action) "glasspane.document.open"))
    (should (equal (plist-get tap :open_surface) "app:jetpacs.files"))
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
    (should (glasspane-para-test--builder-routes-p
             (nth 2 pushed) #'glasspane-resources-archive-screen)))
  (should (gethash "archive.open" jetpacs-action-handlers))
  (should (equal (jetpacs--owner-of "action" "archive.open") "glasspane"))
  (let ((jetpacs-apps--current glasspane-owner))
    (should
     (cl-some
      (lambda (action)
        (and (equal (plist-get action :action) "app.open")
             (equal (plist-get (plist-get action :args) :route) "archive")))
      (glasspane-para-test--actions
       (jetpacs-apps-drawer (jetpacs-shell-surface-for glasspane-owner))))))
  (unwind-protect
      (progn
        (glasspane-resources-unregister)
        (dolist (name '("resources.open" "resources.open-file"
                        "resources.return" "archive.open" "archive.filter"))
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

(ert-deftest glasspane-para-projects-groups-both-todo-extractor-arms ()
  "File and Vulpea TODO item shapes receive the same by-file fold."
  (glasspane-para-test--with-vault
      '(("alpha.org" "* TODO Alpha one\n* TODO Alpha two\n")
        ("beta.org" "* TODO Beta one\n"))
    (let* ((file-items
            (cl-letf (((symbol-function 'glasspane-org--vulpea-p)
                       (lambda () nil)))
              (glasspane-org-todo-items)))
           (file-groups (glasspane-projects--group-by-file file-items)))
      (should (equal (mapcar (lambda (group)
                               (file-name-nondirectory (car group)))
                             file-groups)
                     '("alpha.org" "beta.org")))
      (should (equal (mapcar (lambda (item) (alist-get 'headline item))
                             (cdar file-groups))
                     '("Alpha one" "Alpha two"))))
    (let* ((indexed-items
            (cl-letf (((symbol-function 'glasspane-org--vulpea-p)
                       (lambda () t))
                      ((symbol-function 'vulpea-db-query)
                       (lambda (&optional _predicate) '(one two three)))
                      ((symbol-function 'glasspane-org--vulpea-note-to-item)
                       (lambda (note)
                         `((headline . ,(symbol-name note))
                           (todo . "TODO")
                           (file . ,(expand-file-name
                                     (if (eq note 'two)
                                         "beta.org"
                                       "alpha.org")
                                     vault))))))
              (glasspane-org-todo-items)))
           (indexed-groups
            (glasspane-projects--group-by-file indexed-items)))
      (should (equal (mapcar (lambda (group)
                               (file-name-nondirectory (car group)))
                             indexed-groups)
                     '("alpha.org" "beta.org")))
      (should (equal (mapcar (lambda (item) (alist-get 'headline item))
                             (cdar indexed-groups))
                     '("one" "three"))))))

(ert-deftest glasspane-para-projects-archive-filter-precedes-tokenization ()
  "Both explicit-scope and indexed archive leaks die before token minting."
  (let* ((live '((headline . "Live") (todo . "TODO")
                 (file . "/vault/live.org")))
         (explicit '((headline . "Explicit archive") (todo . "TODO")
                     (file . "/vault/explicit.org_archive")))
         (indexed '((headline . "Indexed archive") (todo . "TODO")
                    (file . "/vault/indexed.ORG_ARCHIVE")))
         (glasspane-projects--filter "ALL")
         tokenized set)
    (cl-letf (((symbol-function 'glasspane-org-todo-items)
               (lambda () (list live explicit indexed)))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (items set-name)
                 (setq tokenized items set set-name)
                 items)))
      (let ((json (jetpacs-node->canonical-json
                   (glasspane-projects--body))))
        (should (string-search "Live" json))
        (should-not (string-search "Explicit archive" json))
        (should-not (string-search "Indexed archive" json))))
    (should (equal tokenized (list live)))
    (should (equal set "tasks"))))

(ert-deftest glasspane-para-projects-filter-chips-and-grouped-render ()
  "Keyword chips include observed file-local states and filter shared cards."
  (let ((glasspane-projects--filter "TODO")
        (glasspane-projects--area-filter nil)
        (refreshes 0)
        (items '(((headline . "Alpha TODO") (todo . "TODO")
                  (file . "/vault/alpha.org"))
                 ((headline . "Alpha done") (todo . "DONE")
                  (file . "/vault/alpha.org"))
                 ((headline . "Beta TODO") (todo . "TODO")
                  (file . "/vault/beta.org"))
                 ((headline . "Beta next") (todo . "NEXT")
                  (file . "/vault/beta.org")))))
    (cl-letf (((symbol-function 'glasspane-org-todo-items)
               (lambda () items))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (visible _set) visible))
              ((symbol-function 'jetpacs-org-settings-global-todo-keywords)
               (lambda () '("TODO" "DONE")))
              ((symbol-function 'jetpacs-app-defer-refresh)
               (lambda (_params) (cl-incf refreshes)))
              ((symbol-function 'jetpacs-window-class)
               (lambda (_axis) "expanded")))
      (let* ((filter-row (glasspane-projects--filter-row items))
             (labels (mapcar (lambda (chip) (plist-get chip :label))
                             (append (plist-get filter-row :children) nil)))
             (body (glasspane-projects--body))
             (json (jetpacs-node->canonical-json body))
             (actions (glasspane-para-test--action-names body)))
        (should (equal (plist-get filter-row :t) "row"))
        (should (eq (plist-get filter-row :scroll) t))
        (should (= (plist-get filter-row :content_padding) 12))
        (should (equal labels '("ALL" "TODO" "DONE" "NEXT")))
        (should (string-search "alpha.org" json))
        (should (string-search "beta.org" json))
        (should (string-search "Alpha TODO" json))
        (should (string-search "Beta TODO" json))
        (should-not (string-search "Alpha done" json))
        (should-not (string-search "Beta next" json))
        (should (member "tasks.filter" actions))
        (should (member "projects.area-filter" actions))
        (should (member "projects.group" actions)))
      (should (eq (glasspane-projects--on-filter
                   '(:filter "DONE") '(:surface "app:glasspane"))
                  'accepted))
      (should (equal glasspane-projects--filter "DONE"))
      (should (= refreshes 1))
      (should (eq (glasspane-projects--on-filter
                   '(:filter 7) '(:surface "app:glasspane"))
                  'rejected))
      (should (equal glasspane-projects--filter "DONE"))
      (should (= refreshes 1)))))

(ert-deftest glasspane-para-projects-area-filter-row-and-many-to-many-match ()
  "Area chips are deterministic and shared Projects match each membership."
  (let* ((shared '((headline . "Shared") (todo . "TODO")))
         (house '((headline . "House only") (todo . "TODO")))
         (work '((headline . "Work only") (todo . "TODO")))
         (items (list shared house work))
         (members `((,shared . ("House" "Auto"))
                    (,house . ("House"))
                    (,work . ("Work"))))
         (glasspane-projects--filter "ALL")
         (glasspane-projects--area-filter "House")
         (glasspane-area-icons '(("Auto" . "directions_car")
                                 ("House" . "home")
                                 ("Work" . "work"))))
    (cl-letf (((symbol-function 'glasspane-projects--item-areas)
               (lambda (item) (cdr (assoc item members)))))
      (let* ((row (glasspane-projects--area-filter-row items))
             (chips (append (plist-get row :children) nil)))
        (should (equal (plist-get row :t) "row"))
        (should (eq (plist-get row :scroll) t))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label)) chips)
                       '("All Areas" "Auto" "House" "Work")))
        (should (equal (mapcar (lambda (chip) (plist-get chip :icon)) chips)
                       '("category" "directions_car" "home" "work")))
        (should (equal (mapcar (lambda (chip) (plist-get chip :selected))
                               chips)
                       '(:json-false :json-false t :json-false)))
        (should-not (plist-get (plist-get (car chips) :on_tap) :args))
        (should (equal
                 (mapcar (lambda (chip)
                           (plist-get (plist-get (plist-get chip :on_tap) :args)
                                      :area))
                         (cdr chips))
                 '("Auto" "House" "Work"))))
      (should (equal (mapcar (lambda (item) (alist-get 'headline item))
                             (glasspane-projects--filter-items items))
                     '("Shared" "House only")))
      (setq glasspane-projects--area-filter "Auto")
      (should (equal (glasspane-projects--filter-items items)
                     (list shared))))))

(ert-deftest glasspane-para-projects-area-filter-precedes-tokenization ()
  "Projects hidden by the Area facet never consume detail tokens."
  (let* ((house '((headline . "House") (todo . "TODO")
                  (file . "/vault/house.org")))
         (work '((headline . "Work") (todo . "TODO")
                 (file . "/vault/work.org")))
         (glasspane-projects--filter "ALL")
         (glasspane-projects--area-filter "House")
         tokenized)
    (cl-letf (((symbol-function 'glasspane-org-todo-items)
               (lambda () (list house work)))
              ((symbol-function 'glasspane-projects--item-areas)
               (lambda (item)
                 (if (eq item house) '("House") '("Work"))))
              ((symbol-function 'glasspane-org-workflow-keywords)
               (lambda (_items) '("TODO")))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (items _set)
                 (setq tokenized items)
                 items)))
      (glasspane-projects--body)
      (should (equal tokenized (list house))))))

(ert-deftest glasspane-para-projects-area-filter-action-selects-and-clears ()
  "Area-filter taps select one facet, clear it, and reject malformed input."
  (let ((glasspane-projects--area-filter nil)
        (refreshes 0))
    (cl-letf (((symbol-function 'jetpacs-app-defer-refresh)
               (lambda (_params) (cl-incf refreshes))))
      (should (eq (glasspane-projects--on-area-filter
                   '(:area "House") '(:surface "app:glasspane"))
                  'accepted))
      (should (equal glasspane-projects--area-filter "House"))
      (should (eq (glasspane-projects--on-area-filter
                   nil '(:surface "app:glasspane"))
                  'accepted))
      (should-not glasspane-projects--area-filter)
      (should (eq (glasspane-projects--on-area-filter
                   '(:area 7) '(:surface "app:glasspane"))
                  'rejected))
      (should-not glasspane-projects--area-filter)
      (should (= refreshes 2)))))

(ert-deftest glasspane-para-projects-controls-share-one-trailing-aligned-row ()
  "Workflow chips share a row with a trailing segmented grouping control."
  (let ((glasspane-projects--group "area")
        (items '(((todo . "TODO") (file . "/vault/projects.org")))))
    (cl-letf (((symbol-function 'glasspane-org-workflow-keywords)
               (lambda (_items) '("TODO" "DONE")))
              ((symbol-function 'jetpacs-node-advertised-p)
               (lambda (type &optional _target)
                 (equal type "segmented_button"))))
      (let* ((row (glasspane-projects--controls-row items))
             (children (append (plist-get row :children) nil))
             (filters (car children))
             (grouping (cadr children))
             (options (append (plist-get grouping :options) nil)))
        (should (equal (plist-get row :t) "row"))
        (should (eq (plist-get row :fill) t))
        (should (equal (plist-get row :align) "top"))
        (should (= (plist-get filters :weight) 1))
        (should (equal (plist-get filters :t) "row"))
        (should (eq (plist-get filters :scroll) t))
        (should (equal (plist-get grouping :pad) '(:end 12)))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label))
                               (append (plist-get filters :children) nil))
                       '("ALL" "TODO" "DONE")))
        (should (equal (plist-get grouping :t) "segmented_button"))
        (should (equal (plist-get grouping :id) "projects-grouping"))
        (should (equal (plist-get grouping :value) "area"))
        (should (equal (mapcar (lambda (option) (plist-get option :label))
                               options)
                       '("By File" "By Area")))
        (should (equal (mapcar (lambda (option) (plist-get option :value))
                               options)
                       '("file" "area")))
        (should (equal (mapcar (lambda (option) (plist-get option :icon))
                               options)
                       '("folder" "category")))
        (should (equal (plist-get (plist-get grouping :on_change) :action)
                       "projects.group"))))))

(ert-deftest glasspane-para-projects-compact-window-moves-grouping-to-top-bar ()
  "A compact width drops the grouping control from the body into the top bar.
Both rails stay; the icon button shows the current grouping and its tap
dispatches the other one through the existing `projects.group' verb."
  (let ((glasspane-projects--filter "ALL")
        (glasspane-projects--area-filter nil)
        (glasspane-projects--group "file")
        (glasspane-ui-legacy-ia nil)
        (items '(((headline . "Alpha") (todo . "TODO")
                  (file . "/vault/alpha.org")))))
    (cl-letf (((symbol-function 'glasspane-org-todo-items)
               (lambda () items))
              ((symbol-function 'glasspane-agenda-tokenize)
               (lambda (visible _set) visible))
              ((symbol-function 'glasspane-org-workflow-keywords)
               (lambda (_items) '("TODO" "DONE")))
              ((symbol-function 'glasspane-projects--item-areas)
               (lambda (_item) '("House")))
              ((symbol-function 'jetpacs-window-class)
               (lambda (axis) (if (eq axis :width) "compact" "medium"))))
      (let* ((body (glasspane-projects--body))
             (children (append (plist-get body :children) nil))
             (workflow (nth 0 children))
             (areas (nth 1 children))
             (actions (glasspane-projects--top-actions))
             (toggle (car actions)))
        (should (equal (plist-get workflow :t) "row"))
        (should (eq (plist-get workflow :scroll) t))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label))
                               (append (plist-get workflow :children) nil))
                       '("ALL" "TODO" "DONE")))
        (should (equal (plist-get areas :t) "row"))
        (should (eq (plist-get areas :scroll) t))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label))
                               (append (plist-get areas :children) nil))
                       '("All Areas" "House")))
        (should-not (member "projects.group"
                            (glasspane-para-test--action-names body)))
        (should (equal (plist-get toggle :t) "icon_button"))
        (should (equal (plist-get toggle :icon) "folder"))
        (should (equal (plist-get toggle :content_description)
                       "Group by Area"))
        (should (equal (plist-get (plist-get toggle :on_tap) :action)
                       "projects.group"))
        (should (equal (plist-get (plist-get (plist-get toggle :on_tap) :args)
                                  :by)
                       "area"))
        (should (equal (plist-get (plist-get (cadr actions) :on_tap) :action)
                       "search.open")))
      (let ((glasspane-projects--group "area"))
        (let ((toggle (car (glasspane-projects--top-actions))))
          (should (equal (plist-get toggle :icon) "category"))
          (should (equal (plist-get toggle :content_description)
                         "Group by File"))
          (should (equal (plist-get (plist-get (plist-get toggle :on_tap)
                                               :args)
                                    :by)
                         "file")))))))

(ert-deftest glasspane-para-agenda-area-rail-filters-pages-and-elevates-chips ()
  "Agenda shares the Projects Area rail and card: chips elevate, the filter
narrows every page, and the verb answers a status."
  (let* ((house '((headline . "House chore") (todo . "TODO")
                  (date . "2026-09-07") (file . "/vault/house.org")))
         (work '((headline . "Work task") (todo . "TODO")
                 (date . "2026-09-07") (file . "/vault/work.org")))
         (items (list house work))
         (members `((,house . ("House")) (,work . ("Work"))))
         (glasspane-agenda--mode "day")
         (glasspane-agenda--area-filter nil)
         (glasspane-org-custom-agendas nil)
         (glasspane-ui-agenda-anchor "2026-09-07")
         (glasspane-area-icons '(("House" . "home") ("Work" . "work")))
         (refreshes 0))
    (cl-letf (((symbol-function 'glasspane-org-agenda-items)
               (lambda (&rest _) items))
              ((symbol-function 'glasspane-agenda--tokenize)
               (lambda (visible _set) visible))
              ((symbol-function 'glasspane-ui-item-areas)
               (lambda (item) (cdr (assoc item members))))
              ((symbol-function 'jetpacs-node-advertised-p)
               (lambda (&rest _) nil))
              ((symbol-function 'jetpacs-app-defer-refresh)
               (lambda (_params) (cl-incf refreshes))))
      (let* ((body (glasspane-agenda-body))
             (children (append (plist-get body :children) nil))
             (rail (car children))
             (chips (append (plist-get rail :children) nil))
             (modes (car (append (plist-get (cadr children) :children) nil)))
             (json (jetpacs-node->canonical-json body))
             (area-chips (glasspane-para-test--nodes-of-type
                          body "material3.assist_chip")))
        (should (equal (plist-get body :t) "column"))
        (should (equal (plist-get rail :t) "row"))
        (should (eq (plist-get rail :scroll) t))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label)) chips)
                       '("All Areas" "House" "Work")))
        (should (equal (mapcar (lambda (chip) (plist-get chip :icon)) chips)
                       '("category" "home" "work")))
        (should (equal (mapcar (lambda (chip) (plist-get chip :selected))
                               chips)
                       '(t :json-false :json-false)))
        (should (equal (plist-get (plist-get (cadr chips) :on_tap) :action)
                       "agenda.area-filter"))
        (should (equal (plist-get (plist-get (plist-get (cadr chips) :on_tap)
                                             :args)
                                  :area)
                       "House"))
        ;; The mode chips fall back to the same scrolling rail.
        (should (equal (plist-get modes :t) "row"))
        (should (eq (plist-get modes :scroll) t))
        (should (equal (plist-get (car (append (plist-get modes :children) nil))
                                  :label)
                       "Day"))
        (should (string-search "House chore" json))
        (should (string-search "Work task" json))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label))
                               area-chips)
                       '("House" "Work")))
        (should (equal (mapcar (lambda (chip) (plist-get chip :variant))
                               area-chips)
                       '("elevated" "elevated"))))
      (should (eq (glasspane-agenda--on-area-filter
                   '(:area "House") '(:surface "app:glasspane"))
                  'accepted))
      (should (equal glasspane-agenda--area-filter "House"))
      (should (= refreshes 1))
      (let* ((body (glasspane-agenda-body))
             (json (jetpacs-node->canonical-json body))
             (chips (append (plist-get (car (append (plist-get body :children)
                                                    nil))
                                       :children)
                            nil)))
        (should (string-search "House chore" json))
        (should-not (string-search "Work task" json))
        (should (equal (mapcar (lambda (chip) (plist-get chip :selected))
                               chips)
                       '(:json-false t :json-false))))
      (should (eq (glasspane-agenda--on-area-filter
                   nil '(:surface "app:glasspane"))
                  'accepted))
      (should-not glasspane-agenda--area-filter)
      (should (eq (glasspane-agenda--on-area-filter
                   '(:area 7) '(:surface "app:glasspane"))
                  'rejected))
      (should (= refreshes 2))
      (should (member "agenda.area-filter" glasspane-agenda--verbs)))))

(ert-deftest glasspane-para-shared-area-presentation-across-views-search-archive ()
  "Views and Search cards elevate Areas like the agenda card; the Archive
rail is the shared Area rail; the Search row compacts to icon buttons."
  (let* ((item '((headline . "Fix roof") (todo . "TODO")
                 (file . "/vault/house.org") (tags . ["House" "urgent"])
                 (token . "tok")))
         (glasspane-area-icons '(("House" . "home")))
         (glasspane-resources--archive-filter nil))
    (cl-letf (((symbol-function 'glasspane-ui-item-areas)
               (lambda (_item) '("House"))))
      (dolist (class '("expanded" "compact"))
        (cl-letf (((symbol-function 'jetpacs-window-class)
                   (lambda (_axis) class)))
          (dolist (card (list (glasspane-views--card item)
                              (glasspane-detail-result-card item)))
            (let* ((chips (glasspane-para-test--nodes-of-type
                           card "material3.assist_chip"))
                   (house (cl-find "House" chips
                                   :key (lambda (c) (plist-get c :label))
                                   :test #'equal))
                   (urgent (cl-find "urgent" chips
                                    :key (lambda (c) (plist-get c :label))
                                    :test #'equal))
                   (groups (glasspane-para-test--nodes-of-type
                            card "flow_row")))
              (should (= (length chips) 2))
              (should (equal (plist-get house :variant) "elevated"))
              (should (equal (plist-get house :icon) "home"))
              (should-not (plist-get urgent :variant))
              (should (equal (plist-get (car groups) :arrange)
                             (if (equal class "compact") "start" "end")))
              (should (equal (plist-get (plist-get house :on_tap) :action)
                             "search.by-tag"))))
          ;; A board column is narrow on every window: Areas always stack.
          (let* ((board (glasspane-views--board-card item '("TODO" "DONE")))
                 (groups (glasspane-para-test--nodes-of-type board "flow_row")))
            (should (equal (plist-get (car groups) :arrange) "start")))
          ;; The Search row: icon buttons on a phone, labeled otherwise.
          (let* ((row (glasspane-search--query-row
                       (jetpacs-text-input "search-query" :value "q") "q"))
                 (kids (append (plist-get row :children) nil)))
            (should (= (length kids) 3))
            (should (equal (plist-get (cadr kids) :t)
                           (if (equal class "compact") "icon_button" "button")))
            (should (equal (plist-get (plist-get (cadr kids) :on_tap) :action)
                           "org.search.run"))
            (should (equal (plist-get (plist-get (caddr kids) :on_tap) :action)
                           "agenda.save-custom")))))
      ;; The Archive rail is the shared one and its handler accepts the
      ;; shared "All Areas" chip, which sends no argument.
      (let* ((rail (glasspane-resources--archive-filter-row '("House")))
             (chips (append (plist-get rail :children) nil))
             (refreshes 0))
        (should (equal (plist-get rail :t) "row"))
        (should (eq (plist-get rail :scroll) t))
        (should (equal (mapcar (lambda (c) (plist-get c :label)) chips)
                       '("All Areas" "House")))
        (should (equal (plist-get (plist-get (car chips) :on_tap) :action)
                       "archive.filter"))
        (should-not (plist-get (plist-get (car chips) :on_tap) :args))
        (cl-letf (((symbol-function 'jetpacs-app-defer-refresh)
                   (lambda (_params) (cl-incf refreshes))))
          (setq glasspane-resources--archive-filter "House")
          (should (eq (glasspane-resources--on-archive-filter
                       nil '(:surface "app:glasspane"))
                      'accepted))
          (should-not glasspane-resources--archive-filter)
          (should (eq (glasspane-resources--on-archive-filter
                       '(:area 3) '(:surface "app:glasspane"))
                      'rejected))
          (should (= refreshes 1)))))))

(ert-deftest glasspane-para-projects-group-control-degrades-to-chips ()
  "Receivers without segmented_button retain both grouping actions."
  (let ((glasspane-projects--group "file"))
    (cl-letf (((symbol-function 'jetpacs-node-advertised-p)
               (lambda (_type &optional _target) nil)))
      (let* ((control (glasspane-projects--group-control))
             (chips (append (plist-get control :children) nil)))
        (should (equal (plist-get control :t) "flow_row"))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label)) chips)
                       '("By File" "By Area")))
        (should (equal
                 (mapcar (lambda (chip)
                           (plist-get (plist-get (plist-get chip :on_tap) :args)
                                      :by))
                         chips)
                 '("file" "area")))))))

(ert-deftest glasspane-para-projects-group-action-accepts-control-and-fallback ()
  "Segmented values and legacy chip arguments share the validated handler."
  (let ((glasspane-projects--group "file")
        (refreshes 0))
    (cl-letf (((symbol-function 'jetpacs-app-defer-refresh)
               (lambda (_params) (cl-incf refreshes))))
      (should (eq (glasspane-projects--on-group
                   '(:value "area") '(:surface "app:glasspane"))
                  'accepted))
      (should (equal glasspane-projects--group "area"))
      (should (eq (glasspane-projects--on-group
                   '(:by "file") '(:surface "app:glasspane"))
                  'accepted))
      (should (equal glasspane-projects--group "file"))
      (should (eq (glasspane-projects--on-group
                   '(:value "other") '(:surface "app:glasspane"))
                  'rejected))
      (should (equal glasspane-projects--group "file"))
      (should (= refreshes 2)))))

(ert-deftest glasspane-para-projects-file-local-todo-workflow-chips ()
  "Every keyword in a file-local #+TODO workflow becomes a filter chip."
  (glasspane-para-test--with-vault
      '(("workflow.org"
         "#+TODO: TODO NEXT WAIT | DONE CANCELED\n* TODO One\n* NEXT Two\n"))
    (let ((items (cl-letf (((symbol-function 'glasspane-org--vulpea-p)
                            (lambda () nil)))
                   (glasspane-org-todo-items))))
      (should (equal (glasspane-org-workflow-keywords items)
                     '("TODO" "NEXT" "WAIT" "DONE" "CANCELED"))))))

(ert-deftest glasspane-para-projects-distinguishes-native-area-tags ()
  "Project cards elevate Area-group tags without duplicating ordinary tags."
  (glasspane-para-test--with-vault
      '(("areas.org"
         "#+TAGS: [ Area : House Auto Bills ]\n#+FILETAGS: :House:\n* Household :Auto:\n** TODO Pay repair invoice :Bills:urgent:\n"))
    (let* ((items (cl-letf (((symbol-function 'glasspane-org--vulpea-p)
                             (lambda () nil)))
                    (glasspane-org-todo-items)))
           (item (car items))
           (areas (glasspane-org-item-tag-group-members
                   item glasspane-area-tag-group))
           (card (cl-letf (((symbol-function 'jetpacs-window-class)
                            (lambda (_axis) "expanded")))
                   (glasspane-projects--card item)))
           (compact-card (cl-letf (((symbol-function 'jetpacs-window-class)
                                    (lambda (_axis) "compact")))
                           (glasspane-projects--card item)))
           (chips (glasspane-para-test--nodes-of-type card "material3.assist_chip")))
      (should (equal areas '("House" "Auto" "Bills")))
      (dolist (area areas)
        (let ((chip (cl-find area chips :key (lambda (node)
                                                (plist-get node :label))
                             :test #'equal)))
          (should chip)
          (should (equal (plist-get chip :icon) "category"))
          (should (equal (plist-get chip :variant) "elevated"))
          (should (equal (plist-get (plist-get chip :on_tap) :action)
                         "search.by-tag"))
          (should (equal (plist-get
                          (plist-get (plist-get chip :on_tap) :args) :tag)
                         area))))
      (let ((ordinary (cl-find "urgent" chips
                               :key (lambda (node) (plist-get node :label))
                               :test #'equal)))
        (should ordinary)
        (should-not (plist-get ordinary :icon))
        (should-not (plist-get ordinary :variant)))
      (should (= (length chips) 4))
      (let* ((groups (glasspane-para-test--nodes-of-type card "flow_row"))
             (area-group (car groups))
             (ordinary (cadr groups))
             (column (car (glasspane-para-test--nodes-of-type card "column")))
             (rows (append (plist-get column :children) nil))
             (header (car rows))
             (header-children (append (plist-get header :children) nil)))
        (should (= (length groups) 2))
        (should (equal (plist-get header :t) "row"))
        (should (eq (plist-get header :fill) t))
        (should (equal (plist-get (car header-children) :t) "rich_text"))
        (should (eq (cadr header-children) area-group))
        (should (eq (car (last rows)) ordinary))
        (should-not (plist-get ordinary :weight))
        (should (= (plist-get area-group :weight) 1))
        (should (equal (plist-get area-group :arrange) "end"))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label))
                              (append (plist-get ordinary :children) nil))
                       '("urgent")))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label))
                              (append (plist-get area-group :children) nil))
                       areas)))
      ;; Compact: the headline keeps the full width and the Area chips
      ;; stack beneath it, start-aligned, ahead of the caption.
      (let* ((groups (glasspane-para-test--nodes-of-type compact-card "flow_row"))
             (area-group (car groups))
             (column (car (glasspane-para-test--nodes-of-type compact-card "column")))
             (rows (append (plist-get column :children) nil)))
        (should (= (length groups) 2))
        (should (equal (plist-get (car rows) :t) "rich_text"))
        (should (eq (cadr rows) area-group))
        (should-not (plist-get area-group :weight))
        (should (equal (plist-get area-group :arrange) "start"))
        (should (equal (mapcar (lambda (chip) (plist-get chip :label))
                              (append (plist-get area-group :children) nil))
                       areas))
        (should (equal (mapcar (lambda (chip) (plist-get chip :variant))
                              (append (plist-get area-group :children) nil))
                       '("elevated" "elevated" "elevated"))))))
  ;; A global group is effective even when the source file has no local
  ;; declaration; a position-less indexed item falls back to its tag payload.
  (let ((org-tag-alist
         '((:startgrouptag) ("Area") (:grouptags)
           ("Work") ("Digital") (:endgrouptag))))
    (glasspane-para-test--with-vault
        '(("global.org" "* TODO Ship release :Work:plain:\n"))
      (let* ((file (expand-file-name "global.org" vault))
             (item `((file . ,file) (tags . ["Work" "plain"]))))
        (should (equal (glasspane-org-item-tag-group-members
                        item glasspane-area-tag-group)
                       '("Work")))))))

(ert-deftest glasspane-para-projects-tag-layout-single-group-and-empty ()
  "Single chip groups retain their edge alignment; no tags emit no row."
  (let ((ordinary (glasspane-detail--agenda-tag-chips '("plain")))
        (areas (glasspane-detail--agenda-tag-chips '("Work") t)))
    (should (equal (plist-get ordinary :t) "flow_row"))
    (should-not (plist-get ordinary :arrange))
    (should (equal (plist-get areas :arrange) "end"))
    (should-not (glasspane-detail--agenda-tag-chips nil))
    (should-not (glasspane-detail--agenda-tag-chips nil t))))

(ert-deftest glasspane-para-projects-alias-route-lifecycle-and-navigation ()
  "The durable Tasks alias and visible Projects opener share one route."
  (dolist (name '("projects.open" "tasks.open"))
    (should (eq (gethash name jetpacs-action-handlers)
                #'glasspane-projects--on-open))
    (should (equal (jetpacs--owner-of "action" name) "glasspane")))
  (let ((home-actions
         (glasspane-para-test--action-names (glasspane-ui-home-screen nil))))
    (should-not (member "tasks.open" home-actions))
    (should (member "projects.open" home-actions)))
  (let (pushed)
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-chrome-push-screen)
               (lambda (surface id builder &rest _)
                 (push (list surface id builder) pushed))))
      (dolist (name '("projects.open" "tasks.open"))
        (should (eq (funcall (gethash name jetpacs-action-handlers)
                             nil '(:surface "app:glasspane"))
                    'accepted))))
    (should (= (length pushed) 2))
    (dolist (push pushed)
      (should (equal (seq-take push 2)
                     '("app:glasspane" "glasspane-projects")))
      (should (glasspane-para-test--builder-routes-p
               (nth 2 push) #'glasspane-projects-screen))))
  (should (jetpacs-check-profile (glasspane-projects-screen nil) 'app))
  (unwind-protect
      (progn
        (glasspane-projects-unregister)
        (dolist (name glasspane-projects--verbs)
          (should-not (gethash name jetpacs-action-handlers)))
        (should (gethash "agenda.open" jetpacs-action-handlers)))
    (glasspane-projects-register))
  (dolist (name glasspane-projects--verbs)
    (should (gethash name jetpacs-action-handlers))))

(ert-deftest glasspane-para-projects-source-boundaries ()
  "Tasks moved whole while Projects consumes only public sibling seams."
  (with-temp-buffer
    (insert-file-contents glasspane-para-test--projects-source)
    (dolist (needle '("seq-group-by" "glasspane-org-todo-items"
                      "glasspane-agenda-tokenize"
                      "glasspane-detail-agenda-card"))
      (goto-char (point-min))
      (should (search-forward needle nil t)))
    (goto-char (point-min))
    (should-not (re-search-forward
                 "\\_<glasspane-\\(?:agenda\\|detail\\|org\\|ui\\)--"
                 nil t)))
  (with-temp-buffer
    (insert-file-contents glasspane-para-test--agenda-source)
    (dolist (needle '("glasspane-agenda--tasks" "\"tasks.open\""
                      "\"tasks.filter\"" "\"projects.open\""))
      (goto-char (point-min))
      (should-not (search-forward needle nil t)))))

(ert-deftest glasspane-para-review-both-engines-absent-combined-empty ()
  "Two missing Review engines collapse to one actionable empty state."
  (let ((jetpacs-action-handlers (copy-hash-table jetpacs-action-handlers))
        (stale-section-calls 0))
    (puthash "glasspane.packages.install" #'ignore jetpacs-action-handlers)
    (cl-letf (((symbol-function 'glasspane-srs-available-p)
               (lambda () nil))
              ((symbol-function 'glasspane-srs--stale-available-p)
               (lambda () nil))
              ((symbol-function 'glasspane-srs--habits-row)
               (lambda () nil))
              ((symbol-function 'glasspane-srs-stale-section)
               (lambda () (cl-incf stale-section-calls) nil)))
      (let* ((body (glasspane-srs--review-body))
             (json (jetpacs-node->canonical-json body))
             (actions (glasspane-para-test--action-names body)))
        (should (string-search "Review needs engines" json))
        (should (string-search
                 "org-srs for flashcards, vulpea for stale notes." json))
        (should (string-search "Install engines" json))
        (should (member "glasspane.packages.install" actions))
        (should-not (string-search "org-srs not installed" json))
        (should-not (string-search "Flashcards" json))
        (should (= stale-section-calls 0)))
      (remhash "glasspane.packages.install" jetpacs-action-handlers)
      (let* ((body (glasspane-srs--review-body))
             (json (jetpacs-node->canonical-json body)))
        (should-not (string-search "Install engines" json))
        (should-not (member "glasspane.packages.install"
                            (glasspane-para-test--action-names body)))))))

(ert-deftest glasspane-para-review-habits-row-gating-and-handoff ()
  "The Habits link follows module presence and calls Jetpacs' public entry."
  (let* ((symbol 'jetpacs-org-habits)
         (had-definition (fboundp symbol))
         (old-definition (and had-definition (symbol-function symbol)))
         (real-featurep (symbol-function 'featurep))
         (continuations nil)
         (calls 0))
    (unwind-protect
        (progn
          (fmakunbound symbol)
          (should (eq (funcall (gethash "review.habits.open"
                                        jetpacs-action-handlers)
                               nil '(:surface "app:glasspane"))
                      'rejected))
          (cl-letf (((symbol-function 'glasspane-srs-available-p)
                     (lambda () t))
                    ((symbol-function 'glasspane-srs--stale-available-p)
                     (lambda () nil))
                    ((symbol-function 'glasspane-srs--idle-body)
                     (lambda () (jetpacs-text "Flashcards live"))))
            (cl-letf (((symbol-function 'featurep)
                       (lambda (feature &optional subfeature)
                         (if (eq feature symbol)
                             nil
                           (funcall real-featurep feature subfeature)))))
              (let ((body (glasspane-srs--review-body)))
                (should-not (member
                             "review.habits.open"
                             (glasspane-para-test--action-names body)))))
            (fset symbol (lambda () (cl-incf calls)))
            (cl-letf (((symbol-function 'featurep)
                       (lambda (feature &optional subfeature)
                         (if (eq feature symbol)
                             t
                           (funcall real-featurep feature subfeature)))))
              (let* ((body (glasspane-srs--review-body))
                     (json (jetpacs-node->canonical-json body)))
                (should (string-search "Habits" json))
                (should (member "review.habits.open"
                                (glasspane-para-test--action-names body))))))
          (cl-letf (((symbol-function 'jetpacs-flow-continue)
                     (lambda (fn) (push fn continuations))))
            (should (eq (funcall (gethash "review.habits.open"
                                          jetpacs-action-handlers)
                                 nil '(:surface "app:glasspane"))
                        'accepted)))
          (should (= (length continuations) 1))
          (funcall (car continuations))
          (should (= calls 1)))
      (if had-definition
          (fset symbol old-definition)
        (fmakunbound symbol)))))

(ert-deftest glasspane-para-review-session-resumes-after-destination-hop ()
  "Leaving an active Review session and reopening it preserves its card."
  (let ((glasspane-srs--active t)
        (glasspane-srs--current '((card back) "card-1" "cards.org"))
        (glasspane-srs--revealed t)
        (glasspane-srs--undo '((snapshot)))
        pushes)
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-chrome-push-screen)
               (lambda (surface id builder &rest _)
                 (push (list surface id builder) pushes)))
              ((symbol-function 'glasspane-srs--session-body)
               (lambda () (jetpacs-text "Resumed current card"))))
      (dolist (name '("review.open" "projects.open" "review.open"))
        (should (eq (funcall (gethash name jetpacs-action-handlers)
                             nil '(:surface "app:glasspane"))
                    'accepted)))
      (should (= (length pushes) 3))
      (let* ((review-push
              (cl-find "glasspane-review" pushes :key #'cadr :test #'equal)))
        (should review-push)
        (let* ((screen (funcall (nth 2 review-push) nil))
               (json (jetpacs-node->canonical-json screen)))
          (should (string-search "Resumed current card" json))))
      (should glasspane-srs--active)
      (should (equal glasspane-srs--current
                     '((card back) "card-1" "cards.org")))
      (should glasspane-srs--revealed)
      (should (equal glasspane-srs--undo '((snapshot)))))))

;;;; PA-3a — primary pole and authoritative PARA table

(ert-deftest glasspane-para-pa3a-destination-table-flips-exactly ()
  "The one table names exactly five bar places plus drawer-only Archive."
  (should-not glasspane-ui-legacy-ia)
  (should
   (equal
    (mapcar (lambda (dest)
              (list (plist-get dest :key)
                    (plist-get dest :label)
                    (plist-get dest :icon)
                    (plist-get dest :verb)
                    (plist-get dest :open-surface)
                    (plist-get dest :badge)
                    (plist-get dest :bar)))
            glasspane-ui-destinations)
    '(("agenda" "Agenda" "event" "agenda.open" nil
       glasspane-agenda-dock-badge t)
      ("projects" "Projects" "task_alt" "projects.open" nil nil t)
      ("areas" "Areas" "category" "areas.open" nil nil t)
      ("resources" "Resources" "topic" "resources.open"
       "app:jetpacs.files" nil t)
      ("review" "Review" "school" "review.open" nil nil t)
      ("archive" "Archive" "archive" "archive.open" nil nil nil))))
  (should (cl-every (lambda (dest) (plist-member dest :bar))
                    glasspane-ui-destinations))
  (should (plist-member (car glasspane-ui-destinations) :badge))
  (should-not (cl-some (lambda (dest)
                         (plist-member dest :badge))
                       (cdr glasspane-ui-destinations)))
  (should (equal (glasspane--destinations) glasspane-ui-destinations))
  ;; Jetpacs owns only the generic fallback seam.  This downstream app is
  ;; where the root's PARA meaning is declared.
  (should (equal (plist-get (cdr (assoc glasspane-owner
                                         jetpacs-apps--registry))
                            :home-route)
                 "agenda"))
  (let* ((screen (glasspane-ui-home-screen nil))
         (body-actions
          (glasspane-para-test--action-names (plist-get screen :body)))
         (drawer-actions
          (glasspane-para-test--action-names (plist-get screen :drawer))))
    (should (equal (sort (copy-sequence body-actions) #'string<)
                   '("agenda.open" "areas.open" "projects.open"
                     "resources.open" "review.open")))
    (should-not (member "archive.open" body-actions))
    (should-not drawer-actions)
    (should-not (plist-member screen :drawer))
    (dolist (verb '("tasks.open" "journal.open" "org.capture.show"
                    "search.open" "views.hub"))
      (should-not (member verb
                          (glasspane-para-test--action-names screen))))
    ;; The registry owns capture now; an absent member, not an authored
    ;; nil, is what lets the chrome join fill the slot.
    (should-not (plist-member screen :fab))))

(ert-deftest glasspane-para-resources-actions-select-native-files-locally ()
  "Every Resources handoff carries the receiver-local Files destination."
  (let* ((dest (cl-find "resources" glasspane-ui-destinations
                        :key (lambda (item) (plist-get item :key))
                        :test #'equal))
         (home-tap (plist-get (glasspane-ui--destination-row dest "test-")
                              :on_tap))
         (host-tap (plist-get
                    (jetpacs-apps--destination-row glasspane-owner dest)
                    :on_tap)))
    (should (equal (plist-get home-tap :action) "resources.open"))
    (should (equal (plist-get home-tap :open_surface)
                   "app:jetpacs.files"))
    (should (equal (plist-get host-tap :action) "app.open"))
    (should (equal (plist-get host-tap :open_surface)
                   "app:jetpacs.files"))))

(ert-deftest glasspane-para-pa3a-legacy-rollback-restores-old-ia ()
  "The soak flag restores the old table, hand dock, and authored FAB."
  (let ((original glasspane-ui-legacy-ia))
    (unwind-protect
        (progn
          (setq glasspane-ui-legacy-ia t)
          (glasspane-register)
          (let* ((entry (assoc glasspane-owner jetpacs-apps--registry))
                 (plist (cdr entry))
                 (screen (glasspane-ui-home-screen nil)))
            (should (equal (jetpacs-chrome-stack glasspane-owner)
                           '("home")))
            (should-not
             (plist-get (cdr (assoc (jetpacs-shell-surface-for
                                     glasspane-owner)
                                    jetpacs-shell--roots))
                        :required))
            (should-not (plist-get plist :chrome))
            (should (plist-get plist :dock-core))
            (should (eq (plist-get plist :dock) #'glasspane--dock-items))
            (should-not (plist-get plist :fab))
            (should
             (equal (mapcar (lambda (dest) (plist-get dest :key))
                            (glasspane-ui-active-destinations))
                    '("agenda" "tasks" "journal" "capture" "search"
                      "views" "review")))
            (should
             (equal (mapcar (lambda (dest) (plist-get dest :key))
                            (jetpacs-apps-destinations glasspane-owner))
                    '("agenda" "tasks" "journal" "search" "views"
                      "review")))
            (should (plist-member screen :fab))
            (should (member "org.capture.show"
                            (glasspane-para-test--action-names screen)))
            (should (memq #'glasspane-journal--apply-landing
                          jetpacs-ready-functions))
            (should (memq #'glasspane-journal--on-view-change
                          jetpacs-shell-view-change-functions))
            (should-not (memq #'glasspane-ui--on-view-change
                              jetpacs-shell-view-change-functions))
            (should (assq 'glasspane-journal-landing
                          (alist-get "Glasspane" jetpacs-settings-registry
                                     nil nil #'equal)))))
      (setq glasspane-ui-legacy-ia original)
      (glasspane-register)))
  (let ((plist (cdr (assoc glasspane-owner jetpacs-apps--registry))))
    (should (equal (jetpacs-chrome-stack glasspane-owner)
                   '("glasspane-agenda")))
    (should
     (plist-get (cdr (assoc (jetpacs-shell-surface-for glasspane-owner)
                            jetpacs-shell--roots))
                :required))
    (should (eq (plist-get plist :chrome) 'primary))
    (should-not (plist-get plist :dock-core))
    (should-not (plist-get plist :dock))
    (should-not (memq #'glasspane-journal--apply-landing
                      jetpacs-ready-functions))
    (should-not (memq #'glasspane-journal--on-view-change
                      jetpacs-shell-view-change-functions))
    (should (memq #'glasspane-ui--on-view-change
                  jetpacs-shell-view-change-functions))
    (should-not (assq 'glasspane-journal-landing
                      (alist-get "Glasspane" jetpacs-settings-registry
                                 nil nil #'equal)))))

(ert-deftest glasspane-para-pa3a-primary-bar-and-drawer-composition ()
  "The real Glasspane metadata yields the exact bar and selective drawer."
  (let* ((entry (assoc glasspane-owner jetpacs-apps--registry))
         (plist (cdr entry)))
    (should (eq (plist-get plist :chrome) 'primary))
    (should-not (plist-get plist :dock-core))
    (should (equal (plist-get plist :drawer-core) '("eval")))
    (should-not (plist-get plist :dock))
    (should (eq (plist-get plist :fab) #'glasspane-ui-capture-fab))
    (let ((jetpacs-apps--registry (list entry))
          (jetpacs-apps--current glasspane-owner)
          (jetpacs-apps--current-route "areas")
          (jetpacs-apps-core-drawer-rows nil)
          (jetpacs-apps-core-dock-items
           (lambda (_surface)
             (list (list :key "eval" :label "Eval" :icon "code"
                         :on-tap (jetpacs-action "eval.open"))
                   (list :key "files" :label "Files" :icon "folder"
                         :on-tap (jetpacs-action "files.open"))))))
      (cl-letf (((symbol-function 'glasspane-agenda-dock-badge)
                 (lambda () "7")))
        (let* ((items (jetpacs-apps-dock-items "app:glasspane"))
               (labels (mapcar (lambda (item) (plist-get item :label))
                               items))
               (drawer (jetpacs-apps-drawer "app:glasspane"))
               (texts (glasspane-para-test--node-texts drawer)))
          (should (equal labels
                         '("Agenda" "Projects" "Areas" "Resources"
                           "Review")))
          (should (equal (mapcar (lambda (item) (plist-get item :badge))
                                 items)
                         '("7" nil nil nil nil)))
          (should (equal (mapcar (lambda (item)
                                  (plist-get item :selected))
                                items)
                         '(nil nil t nil nil)))
          (should
           (equal
            (mapcar (lambda (item)
                      (plist-get (plist-get (plist-get item :on-tap) :args)
                                 :route))
                    items)
            '("agenda" "projects" "areas" "resources" "review")))
          (dolist (label '("Agenda" "Projects" "Areas" "Resources"
                           "Review" "Archive" "Apps" "Eval"))
            (should (= 1 (cl-count label texts :test #'equal))))
          (should (= 0 (cl-count "Files" texts :test #'equal)))
          (dolist (label '("Archive" "Apps" "Eval" "Files"))
            (should-not (member label labels))))))))

(ert-deftest glasspane-para-pa3a-registry-fab-four-arms ()
  "Glasspane re-runs the native, authored, foreign, and guest FAB arms."
  (let* ((surface (jetpacs-shell-surface-for glasspane-owner))
         (jetpacs-chrome-app-fab-function #'jetpacs-apps-default-fab)
         (jetpacs-chrome--guests (make-hash-table :test #'equal))
         (plain (jetpacs-chrome-screen "Plain" (jetpacs-text "plain")))
         (authored-fab
          (jetpacs-icon-button "edit" (jetpacs-action "jetpacs.noop")
                               :content-description "Edit"))
         (authored (jetpacs-chrome-screen
                    "Authored" (jetpacs-text "authored")
                    :fab authored-fab))
         (default (jetpacs-apps-default-fab glasspane-owner surface)))
    (should-not (plist-member (glasspane-ui-home-screen nil) :fab))
    (should default)
    (should (equal (glasspane-para-test--action-names default)
                   '("org.capture.show")))
    ;; Native Glasspane screen, free slot: registry default lands.
    (should
     (equal (plist-get (jetpacs-chrome--join-app-fab
                        surface "home" plain)
                       :fab)
            default))
    ;; Authored screen: authored action wins unchanged.
    (should
     (equal (plist-get (jetpacs-chrome--join-app-fab
                        surface "authored" authored)
                       :fab)
            authored-fab))
    ;; Glasspane metadata may not cross onto a foreign surface.
    (should-not
     (plist-member
      (jetpacs-chrome--join-app-fab "app:foreign" "root" plain) :fab))
    ;; A sanctioned foreign guest on Glasspane's surface keeps its owner
    ;; identity and therefore cannot inherit the host's capture action.
    (puthash surface '(("guest" . "foreign")) jetpacs-chrome--guests)
    (should-not
     (plist-member
      (jetpacs-chrome--join-app-fab surface "guest" plain) :fab))
    (should-not (jetpacs-apps-default-fab glasspane-owner "app:foreign"))
    (should-not (jetpacs-apps-default-fab "foreign" surface))))

;;;; PA-3b — Agenda root, Saved page, and route honesty

(ert-deftest glasspane-para-pa3b-agenda-is-root-and-home-reset ()
  "Agenda's opener and glasspane.home both truncate to the same root id."
  (let ((surface (jetpacs-shell-surface-for glasspane-owner))
        (jetpacs-apps--current glasspane-owner)
        (jetpacs-apps--current-route "projects")
        pushes)
    (glasspane-register)
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (funcall fn)))
                  ((symbol-function 'jetpacs-shell-push)
                   (lambda (&rest args) (push args pushes))))
          (should (equal (jetpacs-chrome-stack surface)
                         '("glasspane-agenda")))
          (should (plist-get (cdr (assoc surface jetpacs-shell--roots))
                             :required))
          ;; Put one peer above the root, then tap Agenda.  Its duplicate
          ;; root id truncates in one push; no reset+push pair is needed.
          (jetpacs-chrome-push-screen
           surface "glasspane-projects" #'glasspane-projects-screen)
          (setq pushes nil)
          (should (eq (glasspane-agenda--on-open
                       nil (list :surface surface))
                      'accepted))
          (should (equal (jetpacs-chrome-stack surface)
                         '("glasspane-agenda")))
          (should (= (length pushes) 1))
          (should (equal jetpacs-apps--current-route "agenda"))
          ;; The explicit home contract names the same root and selection.
          (jetpacs-chrome-push-screen
           surface "glasspane-projects" #'glasspane-projects-screen)
          (jetpacs-apps-note-route glasspane-owner "projects")
          (setq pushes nil)
          (should (eq (glasspane--on-home nil (list :surface surface))
                      'accepted))
          (should (equal (jetpacs-chrome-stack surface)
                         '("glasspane-agenda")))
          (should (= (length pushes) 1))
          (should (equal jetpacs-apps--current-route "agenda")))
      (glasspane-register))))

(ert-deftest glasspane-para-pa3b-destination-slot-resets-and-keeps-drills ()
  "A drill stays over its destination; the next destination evicts both."
  (let ((surface (jetpacs-shell-surface-for glasspane-owner))
        (jetpacs-apps--current glasspane-owner)
        (jetpacs-apps--current-route "agenda")
        pushes)
    (glasspane-register)
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (funcall fn)))
                  ((symbol-function 'jetpacs-shell-push)
                   (lambda (&rest args) (push args pushes))))
          (should (eq (glasspane-ui-open-destination
                       "projects" "glasspane-projects"
                       #'glasspane-projects-screen (list :surface surface))
                      'accepted))
          (should (equal (jetpacs-chrome-stack surface)
                         '("glasspane-projects" "glasspane-agenda")))
          (should (equal jetpacs-apps--current-route "projects"))
          ;; A detail navigation is Tier 2 and preserves its origin.
          (jetpacs-chrome-push-screen
           surface "glasspane-detail"
           (lambda (back)
             (jetpacs-chrome-screen "Detail" (jetpacs-text "x")
                                    :back back)))
          (should (equal (jetpacs-chrome-stack surface)
                         '("glasspane-detail" "glasspane-projects"
                           "glasspane-agenda")))
          (setq pushes nil)
          (should (eq (glasspane-ui-open-destination
                       "areas" (jetpacs-wire-id "area" "Home")
                       (lambda (back)
                         (glasspane-areas-drill-screen "Home" back))
                       (list :surface surface))
                      'accepted))
          (should (equal (jetpacs-chrome-stack surface)
                         (list (jetpacs-wire-id "area" "Home")
                               "glasspane-agenda")))
          (should (equal jetpacs-apps--current-route "areas"))
          ;; Only the destination is sent; presenting the root flashes Agenda.
          (should (= (length pushes) 1))
          (should (equal (plist-get (cdar pushes) :current-view)
                         (jetpacs-wire-id "area" "Home")))
          (let* ((items (jetpacs-apps-dock-items surface))
                 (selected
                  (cl-remove-if-not
                   (lambda (item) (plist-get item :selected)) items)))
            (should (equal (mapcar (lambda (item)
                                     (plist-get item :label))
                                   selected)
                           '("Areas")))))
      (glasspane-register))))

(ert-deftest glasspane-para-destination-switch-sends-only-selected-view ()
  "Projects and Areas transitions send one frame with the requested view."
  (let ((surface (jetpacs-shell-surface-for glasspane-owner))
        (jetpacs-apps--current glasspane-owner)
        (jetpacs-apps--current-route "agenda")
        (glasspane-ui-legacy-ia nil)
        pending pushes)
    (glasspane-register)
    (unwind-protect
        (cl-letf (((symbol-function 'jetpacs-flow-continue)
                   (lambda (fn) (setq pending fn)))
                  ((symbol-function 'jetpacs-shell-push)
                   (lambda (&rest args) (push args pushes))))
          (dolist (route '("projects" "areas" "projects" "areas"))
            (let ((before (jetpacs-chrome-stack surface))
                  (id (concat "glasspane-" route)))
              (setq pushes nil pending nil)
              (should (eq (funcall (if (equal route "projects")
                                       #'glasspane-projects--on-open
                                     #'glasspane-areas--on-open)
                                   nil (list :surface surface))
                          'accepted))
              (should-not pushes)
              (should (equal before (jetpacs-chrome-stack surface)))
              (funcall pending)
              (should (= (length pushes) 1))
              (should (equal (plist-get (cdar pushes) :current-view) id))
              (should (equal (jetpacs-chrome-stack surface)
                             (list id "glasspane-agenda")))
              (should (equal jetpacs-apps--current-route route)))))
      (glasspane-register))))

(ert-deftest glasspane-para-pa3b-back-route-mapping-is-bounded ()
  "Back notes only represented destinations and repushes only on change."
  (let ((surface (jetpacs-shell-surface-for glasspane-owner))
        (jetpacs-apps--current glasspane-owner)
        (jetpacs-apps--current-route "projects")
        scheduled)
    (should (equal (glasspane-ui--route-for-screen "glasspane-agenda")
                   "agenda"))
    (should (equal (glasspane-ui--route-for-screen "glasspane-projects")
                   "projects"))
    (should (equal (glasspane-ui--route-for-screen "glasspane-areas")
                   "areas"))
    (should (equal (glasspane-ui--route-for-screen
                    (jetpacs-wire-id "area" "Home"))
                   "areas"))
    (should (equal (glasspane-ui--route-for-screen "glasspane-archive")
                   "archive"))
    (should (equal (glasspane-ui--route-for-screen "glasspane-review")
                   "review"))
    (should (equal (glasspane-ui--route-for-screen
                    (jetpacs-wire-id "view" "Inbox"))
                   "agenda"))
    (dolist (view '("glasspane-detail" "glasspane-search" "drill-tag"))
      (should-not (glasspane-ui--route-for-screen view)))
    (cl-letf (((symbol-function 'jetpacs-shell--schedule-repush)
               (lambda (seen) (push seen scheduled))))
      ;; Re-reporting the already-selected destination is free.
      (glasspane-ui--on-view-change surface "glasspane-projects")
      (glasspane-ui--on-view-change surface "glasspane-detail")
      (should-not scheduled)
      ;; Back to root changes route exactly once.
      (glasspane-ui--on-view-change surface "glasspane-agenda")
      (glasspane-ui--on-view-change surface "glasspane-agenda")
      (should (equal scheduled (list surface)))
      (should (equal jetpacs-apps--current-route "agenda"))
      ;; A foreign surface cannot rewrite Glasspane's route.
      (glasspane-ui--on-view-change "app:foreign" "glasspane-review")
      (should (equal scheduled (list surface)))
      (should (equal jetpacs-apps--current-route "agenda")))))

(ert-deftest glasspane-para-pa3b-saved-page-keeps-both-registries ()
  "Saved lists custom agendas and view peers without merging the two."
  (let ((glasspane-org-custom-agendas
         '(("Errands" . "tags:errand") ("Waiting" . "todo:WAIT")))
        (glasspane-saved-views
         '(((name . "Work board") (query . "tags:work")
            (rendering . "board"))
           ((name . "Calendar") (query . "todo:TODO")
            (rendering . "calendar")))))
    (should (equal (glasspane-agenda--modes)
                   '("day" "week" "month" "Errands" "Waiting" "saved")))
    (cl-letf (((symbol-function 'glasspane-agenda--tokenize)
               (lambda (&rest _) (ert-fail "Saved minted an Org token set"))))
      (let* ((page (glasspane-agenda--page
                    glasspane-agenda--saved-mode "2026-08-16"))
             (texts (glasspane-para-test--node-texts page))
             (json (jetpacs-node->canonical-json page))
             (actions (glasspane-para-test--actions page))
             (agenda-jump
              (cl-find-if
               (lambda (action)
                 (and (equal (plist-get action :action) "agenda.set-mode")
                      (equal (plist-get (plist-get action :args) :mode)
                             "Errands")))
               actions))
             (view-open
              (cl-find-if
               (lambda (action)
                 (and (equal (plist-get action :action) "views.open")
                      (equal (plist-get (plist-get action :args) :name)
                             "Work board")))
               actions)))
        (dolist (text '("Errands" "Waiting" "Work board" "Calendar"))
          (should (member text texts)))
        (should (string-search "Custom agendas" json))
        (should (string-search "Saved views" json))
        (should agenda-jump)
        (should view-open)))
    ;; The actual tabs include the user-facing trailing label.
    (cl-letf (((symbol-function 'glasspane-agenda--items-for)
               (lambda (&rest _) nil))
              ((symbol-function 'glasspane-agenda--tokenize)
               (lambda (&rest _) nil)))
      (should (string-search
               "Saved"
               (jetpacs-node->canonical-json
                (glasspane-agenda--body-tabs "day" "2026-08-16")))))))

(ert-deftest glasspane-para-pa3c-slot-eviction-and-detail-reentry ()
  "Area peers replace; search evicts the peer; detail re-entry truncates."
  (let ((surface (jetpacs-shell-surface-for glasspane-owner))
        (glasspane-ui-legacy-ia nil)
        (jetpacs-apps--current glasspane-owner)
        (jetpacs-apps--current-route "agenda"))
    (glasspane-register)
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-shell-push)
               (lambda (&rest _) t)))
      (should (eq (glasspane-areas--on-open nil (list :surface surface))
                  'accepted))
      (should (equal (jetpacs-chrome-stack surface)
                     '("glasspane-areas" "glasspane-agenda")))
      ;; The drill is a Tier-1 peer, not a second Areas tier.
      (should (eq (glasspane-areas--on-drill
                   '(:category "Home") (list :surface surface))
                  'accepted))
      (let ((area-id (jetpacs-wire-id "area" "Home")))
        (should (equal (jetpacs-chrome-stack surface)
                       (list area-id "glasspane-agenda"))))
      ;; Detail consumes the third slot.  Search is a plain drill, so the
      ;; max-three insertion retains search + detail + the pinned root and
      ;; evicts the Area destination.
      (glasspane-detail--push-screen surface '(:file "unused" :pos 1))
      (should (equal (jetpacs-chrome-stack surface)
                     (list "glasspane-detail"
                           (jetpacs-wire-id "area" "Home")
                           "glasspane-agenda")))
      (should (eq (glasspane-search--on-open nil (list :surface surface))
                  'accepted))
      (should (equal (jetpacs-chrome-stack surface)
                     '("glasspane-search" "glasspane-detail"
                       "glasspane-agenda")))
      ;; The constant detail id finds its existing entry, replaces it, and
      ;; truncates Search instead of allocating a fourth conceptual tier.
      (glasspane-detail--push-screen surface '(:file "unused-2" :pos 2))
      (should (equal (jetpacs-chrome-stack surface)
                     '("glasspane-detail" "glasspane-agenda")))
      (should (equal jetpacs-apps--current-route "areas")))))

(ert-deftest glasspane-para-pa3c-resources-handoff-and-return ()
  "Resources owns selection; Files hosts it; a bar peer returns home-side."
  (let ((surface (jetpacs-shell-surface-for glasspane-owner))
        (files-surface (jetpacs-shell-surface-for jetpacs-files-owner))
        (glasspane-ui-legacy-ia nil)
        (org-directory "/vault")
        opened)
    (glasspane-register)
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-feature-advertised-p)
               (lambda (&rest _) t))
              ((symbol-function 'jetpacs-shell-push)
               (lambda (&rest _) t))
              ((symbol-function 'jetpacs-files-open-path)
               (lambda (path target &optional mark-pos browser-id browser-fab
                             return-action)
                 (setq opened
                       (list path target mark-pos browser-id browser-fab
                             return-action))
                 'accepted)))
      (should (eq (jetpacs-apps--action-open
                   '(:app "glasspane" :route "resources") nil)
                  'accepted))
      (should (equal (seq-take opened 4)
                     (list "/vault" files-surface nil "files-resources")))
      (should (equal (glasspane-para-test--action-names (nth 4 opened))
                     '("org.capture.show")))
      (should (equal (plist-get (nth 5 opened) :action)
                     "glasspane.files.return"))
      (should (equal (plist-get (nth 5 opened) :open_surface)
                     "app:glasspane"))
      (should (equal jetpacs-apps--current-route "resources"))
      (let ((selected
             (cl-find-if (lambda (item) (plist-get item :selected))
                         (jetpacs-apps-dock-items files-surface))))
        (should (equal (plist-get selected :label) "Resources")))
      ;; This tap originates on the foreign Files surface, but app.open's
      ;; sanctioned redispatch supplies Glasspane's own home surface.
      (should (eq (jetpacs-apps--action-open
                   '(:app "glasspane" :route "areas") nil)
                  'accepted))
      (should (equal (jetpacs-chrome-stack surface)
                     '("glasspane-areas" "glasspane-agenda")))
      (should (equal jetpacs-apps--current-route "areas"))
      ;; Direct/M-x Resources entry records its route too; an Area/Archive
      ;; row handoff intentionally preserves the origin route.
      (should (eq (glasspane-resources--on-open nil nil) 'accepted))
      (should (equal jetpacs-apps--current-route "resources"))
      (setq jetpacs-apps--current-route "areas")
      (should (eq (glasspane-resources--on-open-file
                   '(:path "/vault/work.org") nil)
                  'accepted))
      (should (equal jetpacs-apps--current-route "areas")))))

(ert-deftest glasspane-para-pa3c-delete-live-view-pops-only-its-top ()
  "The surviving views.delete audit row leaves no dead view on top."
  (let* ((surface (jetpacs-shell-surface-for glasspane-owner))
         (glasspane-saved-views
          '(((name . "Focus") (query . "todo:TODO")
             (rendering . "list"))))
         (id (jetpacs-wire-id "view" "Focus")))
    (glasspane-register)
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-shell-push)
               (lambda (&rest _) t))
              ((symbol-function 'glasspane-views--persist) #'ignore)
              ((symbol-function 'jetpacs-shell-notify) #'ignore))
      (glasspane-ui-open-destination
       "agenda" id
       (lambda (back) (glasspane-views--screen "Focus" back))
       (list :surface surface))
      (should (equal (jetpacs-chrome-stack surface)
                     (list id "glasspane-agenda")))
      (should (eq (glasspane-views--on-delete
                   '(:name "Focus") (list :surface surface))
                  'accepted))
      (should (equal (jetpacs-chrome-stack surface)
                     '("glasspane-agenda")))
      (should-not glasspane-saved-views))))

(ert-deftest glasspane-para-pa3c-mark-position-navigation-family ()
  "Heading tokens reach the one document presenter with their position.
NAVIGATION.org: `heading.visit' resolves the token, then Files hosts the
document at the heading's position with the reader landing prepared; the
cached `detail.open-file' verb is the same route, and neither turns the
current route into Resources."
  (glasspane-para-test--with-vault
      '(("tasks.org" "* TODO First\n** NEXT Target\nBody\n"))
    (let* ((file (expand-file-name "tasks.org" vault))
           (buf (find-file-noselect file))
           (ref (with-current-buffer buf
                  (org-with-wide-buffer
                   (goto-char (point-min))
                   (re-search-forward "^\\*\\* NEXT Target")
                   (goto-char (line-beginning-position))
                   (ebp-org-ref-at-point))))
           (pos (plist-get ref :pos))
           (token (car (ebp-org-ref-tokens
                        (list ref) :set "pa3c-jump" :owner "glasspane")))
           (jetpacs-apps--current-route "projects")
           (glasspane-ui-legacy-ia nil)
           opened)
      (unwind-protect
          (cl-letf (((symbol-function 'jetpacs-flow-continue)
                     (lambda (fn) (funcall fn)))
                    ((symbol-function 'jetpacs-feature-advertised-p)
                     (lambda (&rest _) t))
                    ((symbol-function 'jetpacs-files-open-path)
                     (lambda (path surface &optional mark-pos browser-id
                                   browser-fab return-action)
                       (setq opened (list path surface mark-pos browser-id
                                          browser-fab return-action))
                       'accepted)))
            (jetpacs-reader-state-set file :presentation 'editor)
            (jetpacs-reader-state-set file :gp-fold-mode 'refile)
            (jetpacs-reader-state-set file :gp-filter-query "todo:DONE")
            (should (eq (glasspane-detail--on-visit
                         (list :token token) '(:surface "app:glasspane"))
                        'accepted))
            (should (equal (seq-take opened 5)
                           (list (file-truename file) "app:jetpacs.files"
                                 pos "files-return" nil)))
            (should (equal (plist-get (nth 5 opened) :action)
                           "glasspane.files.return"))
            (should (equal (plist-get (nth 5 opened) :open_surface)
                           "app:glasspane"))
            (should (eq (jetpacs-reader-state-get file :presentation)
                        'reader))
            (should (eq (jetpacs-reader-state-get file :gp-fold-mode)
                        'tree))
            (should (equal (jetpacs-reader-state-get
                            file :gp-filter-query)
                           ""))
            ;; The cached compatibility verb is the very same route.
            (setq opened nil)
            (jetpacs-reader-state-set file :presentation 'editor)
            (should (eq (glasspane-detail--on-open-file
                         (list :token token) nil)
                        'accepted))
            (should (equal (seq-take opened 4)
                           (list (file-truename file) "app:jetpacs.files"
                                 pos "files-return")))
            (should (eq (jetpacs-reader-state-get file :presentation)
                        'reader))
            ;; A contextual Files handoff is not the Resources destination.
            (should (equal jetpacs-apps--current-route "projects"))
            (should (eq (glasspane-detail--on-visit
                         '(:token 7) nil)
                        'rejected))
            (should (eq (glasspane-detail--on-open-file
                         '(:token "gone") nil)
                        'stale)))
        (ebp-org-ref-tokens nil :set "pa3c-jump" :owner "glasspane")))))

(ert-deftest glasspane-para-pa3c-glasspane-token-budget-is-24 ()
  "Worst-case PARA composition retains eight free owner token-set slots."
  (let* ((agenda-sets
          (mapcar (lambda (mode) (concat "agenda-" mode))
                  (append '("day" "week" "month")
                          (mapcar (lambda (n) (format "custom-%d" n))
                                  (number-sequence
                                   1 glasspane-agenda--custom-max)))))
         (sets
          (append agenda-sets
                  '("tasks" "areas" "search-results" "views"
                    "detail" "detail-subtree" "detail-props"
                    "clock-recent" "notes-detail" "notes-toolbar"
                    "notes-stale" "srs-detail" "reader-file")))
         (ebp-org--tokens (make-hash-table :test #'equal))
         (ebp-org--token-sets (make-hash-table :test #'equal))
         (ebp-org--token-counter 0)
         (count 0))
    (should (= (length sets) 24))
    (should (= (length sets) (length (delete-dups (copy-sequence sets)))))
    (should (>= (- ebp-org-token-sets-max (length sets)) 6))
    (should-not (member "journal-carried" sets))
    (should-not (member "journal-day" sets))
    ;; Exercise the engine cap rather than checking arithmetic alone.
    (dolist (set sets)
      (ebp-org-ref-tokens nil :set set :owner "glasspane"))
    (maphash (lambda (key _tokens)
               (when (equal (car key) "glasspane")
                 (cl-incf count)))
             ebp-org--token-sets)
    (should (= count 24))
    (should (= (- ebp-org-token-sets-max count) 8))))

;;;; PA-3d — host drawer, top-bar Search, and compatibility aliases

(ert-deftest glasspane-para-pa3d-host-drawer-composes-on-agenda-root ()
  "The active root authors no drawer; Jetpacs composes the complete host one."
  (glasspane-register)
  (let* ((surface (jetpacs-shell-surface-for glasspane-owner))
         (glasspane-entry (assoc glasspane-owner jetpacs-apps--registry))
         (other-entry
          '("other" :label "Other" :icon "extension"
            :surfaces ("other")
            :destinations ((:key "elsewhere" :label "Elsewhere"
                            :icon "explore" :verb "other.open"))))
         (jetpacs-apps--registry (list glasspane-entry other-entry))
         (jetpacs-apps--current glasspane-owner)
         (jetpacs-apps--current-route "agenda")
         (jetpacs-apps-core-dock-items
          (lambda (_surface)
            (list (list :key "eval" :label "Eval" :icon "code"
                        :on-tap (jetpacs-action "eval.open"))
                  (list :key "files" :label "Files" :icon "folder"
                        :on-tap (jetpacs-action "files.open")))))
         (jetpacs-apps-core-drawer-rows
          (lambda (_surface)
            (list (jetpacs-chrome-row "Tools" :icon "build"
                                      :on-tap (jetpacs-action "tools.open")
                                      :key "test-tools")
                  (jetpacs-divider)
                  (jetpacs-chrome-row "Settings" :icon "settings"
                                      :on-tap (jetpacs-action "settings.open")
                                      :key "test-settings"))))
         (jetpacs-chrome-drawer-function #'jetpacs-apps-drawer))
    (cl-letf (((symbol-function 'glasspane-agenda--today-count)
               (lambda () 0))
              ((symbol-function 'glasspane-agenda-body)
               (lambda () (jetpacs-text "Agenda body"))))
      (let* ((raw (glasspane-agenda-screen nil))
             (built (jetpacs-chrome--build surface))
             (root (gethash "glasspane-agenda" (plist-get built :views)))
             (drawer (plist-get root :drawer))
             (texts (glasspane-para-test--node-texts drawer)))
        (should-not (plist-member raw :drawer))
        (should (plist-member root :drawer))
        (dolist (label '("Apps" "Glasspane" "Agenda" "Projects" "Areas"
                         "Resources" "Review" "Archive" "Other"
                         "Elsewhere" "Eval" "Tools" "Settings"))
          (should (= 1 (cl-count label texts :test #'equal))))
        (should (= 0 (cl-count "Files" texts :test #'equal)))))))

(ert-deftest glasspane-para-pa3d-search-is-destination-action-only ()
  "Search appears once on every authored destination, never on Search/detail."
  (let ((glasspane-ui-legacy-ia nil)
        (glasspane-srs--active nil))
    (cl-letf (((symbol-function 'glasspane-agenda--today-count)
               (lambda () 0))
              ((symbol-function 'glasspane-agenda-body)
               (lambda () (jetpacs-text "agenda")))
              ((symbol-function 'glasspane-projects--body)
               (lambda () (jetpacs-text "projects")))
              ((symbol-function 'glasspane-areas--list-body)
               (lambda () (jetpacs-text "areas")))
              ((symbol-function 'glasspane-areas--drill-body)
               (lambda (_category) (jetpacs-text "area")))
              ((symbol-function 'glasspane-resources--archive-body)
               (lambda () (jetpacs-text "archive")))
              ((symbol-function 'glasspane-srs--review-body)
               (lambda () (jetpacs-text "review")))
              ((symbol-function 'glasspane-search--body)
               (lambda () (jetpacs-text "search"))))
      (dolist (screen
               (list (glasspane-agenda-screen nil)
                     (glasspane-projects-screen nil)
                     (glasspane-areas-screen nil)
                     (glasspane-areas-drill-screen "Work" nil)
                     (glasspane-resources-archive-screen nil)
                     (glasspane-srs-screen nil)
                     (glasspane-views--screen "Vanished" nil)))
        (should (= 1 (cl-count "search.open"
                               (glasspane-para-test--action-names screen)
                               :test #'equal)))
        (should-not (plist-member screen :drawer)))
      (should-not (member "search.open"
                          (glasspane-para-test--action-names
                           (glasspane-search-screen nil))))
      (should-not (member "search.open"
                          (glasspane-para-test--action-names
                           (glasspane-detail--screen nil nil)))))))

(ert-deftest glasspane-para-pa3d-aliases-land-on-current-destinations ()
  "Tasks and Views remain accepted aliases; only capture remains of Journal."
  (should (eq (gethash "tasks.open" jetpacs-action-handlers)
              #'glasspane-projects--on-open))
  (should (eq (gethash "views.hub" jetpacs-action-handlers)
              #'glasspane-agenda-open-saved))
  (should (eq (gethash "journal.capture" jetpacs-action-handlers)
              #'glasspane-journal--on-capture))
  (dolist (name '("journal.open" "journal.nav" "journal.goto"
                  "journal.today"))
    (should-not (gethash name jetpacs-action-handlers)))
  (let ((glasspane-agenda--mode "day")
        (jetpacs-apps--current glasspane-owner)
        (jetpacs-apps--current-route "projects")
        pushed)
    (cl-letf (((symbol-function 'jetpacs-flow-continue)
               (lambda (fn) (funcall fn)))
              ((symbol-function 'jetpacs-chrome-push-screen)
               (lambda (surface id builder &rest _)
                 (setq pushed (list surface id builder)))))
      (should (eq (funcall (gethash "views.hub" jetpacs-action-handlers)
                           nil '(:surface "app:glasspane"))
                  'accepted)))
    (should (equal glasspane-agenda--mode "saved"))
    (should (equal jetpacs-apps--current-route "agenda"))
    (should (equal (seq-take pushed 2)
                   '("app:glasspane" "glasspane-agenda")))
    (should (glasspane-para-test--builder-routes-p
             (nth 2 pushed) #'glasspane-agenda-screen))))

(ert-deftest glasspane-para-pa3d-queued-journal-alias-replays-to-datetree ()
  "A queue-shaped event reaches the live alias and commits before acceptance."
  (glasspane-para-test--with-vault nil
    (let* ((glasspane-journal-file (expand-file-name "journal.org" vault))
           (receipt-file (make-temp-file "glasspane-pa3d-receipts"))
           (client (ebp-client-create :receipt-file receipt-file))
           (event-id (make-string 32 ?a)))
      (unwind-protect
          (progn
            (ebp-client-register-action
             client "journal.capture" (jetpacs--action-shim "journal.capture"))
            (cl-letf (((symbol-function 'jetpacs-shell-notify) #'ignore)
                      ((symbol-function 'jetpacs-app-defer-refresh) #'ignore))
              (should
               (equal
                (ebp-client--handle-event-action
                 client
                 (list :event_id event-id
                       :action "journal.capture"
                       :args '(:value "Queued field note"
                               :date "2026-08-17")
                       :surface "app:glasspane"
                       :revision_seen 0
                       :occurred_at_ms 1786946400000))
                '(:status "accepted"))))
            (with-temp-buffer
              (insert-file-contents glasspane-journal-file)
              (should (string-search "2026-08-17" (buffer-string)))
              (should (re-search-forward "^- Queued field note$" nil t)))
            ;; A replay retry with the same durable event id cannot append twice.
            (should
             (equal
              (ebp-client--handle-event-action
               client
               (list :event_id event-id
                     :action "journal.capture"
                     :args '(:value "Queued field note"
                             :date "2026-08-17")
                     :surface "app:glasspane"
                     :revision_seen 0
                     :occurred_at_ms 1786946400000))
              '(:status "duplicate"))))
        (ebp-client-close client 'test-finished)
        (when (file-exists-p receipt-file)
          (delete-file receipt-file))))))

;;;; PM-2 — substrate arms (glasspane-org.el)

(ert-deftest glasspane-para-pm2-file-tags-without-headings ()
  "A file carrying an Area only in #+FILETAGS is a member with no headings."
  (glasspane-para-test--with-vault
      '(("notes.org"
         "#+TAGS: [ Area : Work Home ]\n#+FILETAGS: :Work:\nJust prose.\n"))
    (let ((index (glasspane-org--file-tag-group-index
                  (expand-file-name "notes.org" vault) "Area")))
      (should (equal (plist-get index :members) '("Work" "Home")))
      (should (equal (plist-get index :file-tags) '("Work")))
      (should-not (plist-get index :positions)))))

(ert-deftest glasspane-para-pm2-inheritance-forced-for-membership ()
  "Membership honors inherited tags even when inheritance is off globally."
  (glasspane-para-test--with-vault
      '(("work.org"
         "#+TAGS: [ Area : Home ]\n* Parent :Home:\n** Child\n"))
    (let* ((org-use-tag-inheritance nil)
           (index (glasspane-org--file-tag-group-index
                   (expand-file-name "work.org" vault) "Area"))
           (memberships (mapcar #'cdr (plist-get index :positions))))
      (should (equal memberships '(("Home") ("Home")))))))

(ert-deftest glasspane-para-pm2-open-todo-predicate ()
  "Only a not-done TODO keyword counts as open work."
  (let ((org-done-keywords nil))
    (should (glasspane-org-open-todo-p '((todo . "TODO"))))
    (should (glasspane-org-open-todo-p '((todo . "IN-PROGRESS"))))
    (should-not (glasspane-org-open-todo-p '((todo . "DONE"))))
    (should-not (glasspane-org-open-todo-p '((todo . nil))))
    (should-not (glasspane-org-open-todo-p '((headline . "Plain"))))))

(ert-deftest glasspane-para-pm2-indexed-area-declarations ()
  "Declarations are nil without vulpea and shaped from the property query."
  (glasspane-para-test--with-vault '(("empty.org" "* Nothing\n"))
    (cl-letf (((symbol-function 'glasspane-org--vulpea-p) (lambda () nil)))
      (should-not (glasspane-org-indexed-area-declarations)))
    (ebp-org-cache-invalidate)
    (let (queried)
      (cl-letf (((symbol-function 'glasspane-org--vulpea-p) (lambda () t))
                ((symbol-function 'vulpea-db-query-by-property-key)
                 (lambda (key) (setq queried key) '(tech blank)))
                ((symbol-function 'vulpea-note-properties)
                 (lambda (note)
                   (if (eq note 'tech) '(("AREA" . " tech ")) '(("AREA" . "")))))
                ((symbol-function 'vulpea-note-path)
                 (lambda (_note) "/vault/areas.org"))
                ((symbol-function 'vulpea-note-pos) (lambda (_note) 42))
                ((symbol-function 'vulpea-note-title) (lambda (_note) "Tech"))
                ((symbol-function 'vulpea-note-level) (lambda (_note) 1)))
        (should (equal (glasspane-org-indexed-area-declarations)
                       '((:name "tech" :file "/vault/areas.org" :pos 42
                                :headline "Tech" :level 1))))
        (should (equal queried "AREA"))))))

;;;; PM-5 — declaring notes and index merge

(ert-deftest glasspane-para-pm5-heading-declaration-is-a-member-of-itself ()
  "A heading declaring AREA opens as the Area's note and counts as a member."
  (glasspane-para-test--with-vault
      '(("areas.org"
         "#+TAGS: [ Area : tech ]\n* Tech :tech:\n:PROPERTIES:\n:AREA: tech\n:END:\nStanding notes.\n** TODO Upgrade kernel\n")
        ("notes.org"
         "#+TAGS: [ Area : tech ]\n#+FILETAGS: :tech:\nProse only, no headings.\n"))
    (let* ((glasspane-areas--filter-state (make-hash-table :test #'equal))
           (index (glasspane-areas--index))
           (tech (glasspane-para-test--area "tech" index))
           (decl (car (plist-get tech :declares))))
      (should (= (length (plist-get tech :files)) 2))
      (should (equal (mapcar (lambda (item) (alist-get 'headline item))
                             (plist-get tech :items))
                     '("Upgrade kernel")))
      (should (equal (plist-get decl :level) 1))
      (should (equal (alist-get 'headline (plist-get decl :item)) "Tech"))
      (should (string-search "2 files"
                             (jetpacs-node->canonical-json
                              (glasspane-areas--area-row tech))))
      (should (string-search "note\""
                             (jetpacs-node->canonical-json
                              (glasspane-areas--area-row tech))))
      (cl-letf (((symbol-function 'jetpacs-feature-advertised-p)
                 (lambda (&rest _) t))
                ((symbol-function 'glasspane-agenda-tokenize)
                 (lambda (items _set)
                   (mapcar (lambda (item) (cons '(token . "note-token") item))
                           items)))
                ((symbol-function 'glasspane-resources-archives-for-files)
                 (lambda (_files) nil)))
        (let* ((body (glasspane-areas--drill-body "tech"))
               (actions (glasspane-para-test--actions body))
               (visit (cl-find "heading.visit" actions
                               :key (lambda (a) (plist-get a :action))
                               :test #'equal)))
          (should visit)
          (should (equal (plist-get visit :args) '(:token "note-token")))
          (should (string-search "Area note" (jetpacs-node->canonical-json body))))))))

(ert-deftest glasspane-para-pm5-file-declaration-opens-as-document ()
  "A file-level AREA drawer declares the Area; its row opens by path."
  (glasspane-para-test--with-vault
      '(("home.org"
         ":PROPERTIES:\n:AREA: home\n:END:\n#+TAGS: [ Area : home ]\n#+FILETAGS: :home:\n* TODO Fix sink\n"))
    (let* ((glasspane-areas--filter-state (make-hash-table :test #'equal))
           (index (glasspane-areas--index))
           (home (glasspane-para-test--area "home" index))
           (decl (car (plist-get home :declares))))
      (should (equal (plist-get decl :level) 0))
      (should-not (plist-get decl :item))
      (should (equal (glasspane-areas--count-label home) "1 open TODO · 1 file"))
      (cl-letf (((symbol-function 'jetpacs-feature-advertised-p)
                 (lambda (&rest _) t))
                ((symbol-function 'glasspane-agenda-tokenize)
                 (lambda (items _set) items))
                ((symbol-function 'glasspane-resources-archives-for-files)
                 (lambda (_files) nil)))
        (let* ((body (glasspane-areas--drill-body "home"))
               (json (jetpacs-node->canonical-json body))
               (opens (cl-remove "glasspane.document.open"
                                 (glasspane-para-test--actions body)
                                 :key (lambda (a) (plist-get a :action))
                                 :test-not #'equal)))
          (should (string-search "Open home note" json))
          (should (cl-some (lambda (a)
                             (equal (plist-get (plist-get a :args) :path)
                                    (plist-get decl :file)))
                           opens)))))))

(ert-deftest glasspane-para-pm5-indexed-declarations-merge-behind-the-scan ()
  "Index-only declarations annotate members; the file walk wins on a name.
A declaration for a name outside the group never invents an Area."
  (glasspane-para-test--with-vault
      '(("areas.org"
         "#+TAGS: [ Area : tech ops ]\n* Tech :tech:\n:PROPERTIES:\n:AREA: tech\n:END:\n* Stray\n:PROPERTIES:\n:AREA: phantom\n:END:\n")
        ("ops.org" "* Ops\n"))
    (let ((ops (expand-file-name "ops.org" vault)))
      (cl-letf (((symbol-function 'glasspane-org-indexed-area-declarations)
                 (lambda ()
                   (list (list :name "tech" :file ops :pos 1
                               :headline "Stale" :level 1)
                         (list :name "ops" :file ops :pos 1
                               :headline "Ops" :level 1)
                         (list :name "bad" :file "/nowhere/x.org" :pos 1
                               :headline "Bad" :level 1)))))
        (let* ((index (glasspane-areas--index-1))
               (tech (glasspane-para-test--area "tech" index))
               (ops-area (glasspane-para-test--area "ops" index)))
          (should (equal (alist-get 'headline
                                    (plist-get (car (plist-get tech :declares))
                                               :item))
                         "Tech"))
          (should (= (length (plist-get tech :declares)) 1))
          (should ops-area)
          (should (equal (plist-get (car (plist-get ops-area :declares))
                                    :headline)
                         "Ops"))
          (should-not (glasspane-para-test--area "bad" index))
          (should-not (glasspane-para-test--area "phantom" index)))))))

(provide 'glasspane-para-test)
;;; glasspane-para-test.el ends here
