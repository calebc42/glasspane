;;; glasspane-projects.el --- PARA Project facets on Glasspane -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Projects are heading-level Vulpea notes carrying
;; `glasspane-para-project-tag'.  A TODO keyword is workflow state, not what
;; makes the heading a Project.  This is the mobile projection of
;; vulpea-para's model; projects are grouped by their containing Area and
;; orphans remain visible for repair.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ebp-org)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-org-settings)
(require 'jetpacs-settings)
(require 'glasspane-org)
(require 'glasspane-para)
(require 'glasspane-agenda)
(require 'glasspane-detail)
(require 'glasspane-ui)

(defconst glasspane-projects--no-state "NO STATE"
  "Filter label used for a tagged Project without a TODO keyword.")

(defvar glasspane-projects--filter "ALL"
  "Current Project workflow filter; ALL includes every tagged Project.")

(defun glasspane-projects--project-items ()
  "Return Project card items enriched with their containing Area."
  (let ((areas-by-path (make-hash-table :test #'equal)))
    (dolist (area (glasspane-para-areas))
      (puthash (vulpea-note-path area) area areas-by-path))
    (mapcar
     (lambda (project)
       (let ((area (gethash (vulpea-note-path project) areas-by-path)))
         (append
          (list (cons 'para-project t)
                (cons 'area-title (and area (vulpea-note-title area)))
                (cons 'area-id (and area (vulpea-note-id area))))
          (glasspane-para-note-item project))))
     (glasspane-para-projects))))

(defun glasspane-projects--filter-items (items)
  "Apply the active workflow filter to Project ITEMS."
  (if (equal glasspane-projects--filter "ALL")
      items
    (cl-remove-if-not
     (lambda (item)
       (equal (or (alist-get 'todo item) glasspane-projects--no-state)
              glasspane-projects--filter))
     items)))

(defun glasspane-projects--group-by-area (items)
  "Group ITEMS by Area title with orphans last."
  (sort
   (seq-group-by
    (lambda (item) (or (alist-get 'area-title item) "No area")) items)
   (lambda (a b)
     (let ((ak (car a)) (bk (car b)))
       (cond
        ((equal ak "No area") nil)
        ((equal bk "No area") t)
        (t (string-lessp ak bk)))))))

(defun glasspane-projects--file-todo-keywords (file)
  "Return FILE's effective TODO keywords without trusting another buffer."
  (when (stringp file)
    (ebp-org-with-cache 'glasspane (list 'projects-todo-keywords file)
      (condition-case nil
          (let ((true (ebp-org--check-file file)))
            (ebp-org--with-clamped-io
              (with-current-buffer (find-file-noselect true t)
                (unless (derived-mode-p 'org-mode) (org-mode))
                (copy-sequence org-todo-keywords-1))))
        (error nil)))))

(defun glasspane-projects--todo-keywords (items)
  "Return stable workflow filters represented by Project ITEMS."
  (let ((files (sort (delete-dups
                      (delq nil (mapcar
                                 (lambda (item) (alist-get 'file item))
                                 items)))
                     #'string-lessp))
        keywords
        no-state)
    (cl-labels ((add (keyword)
                  (when (and (stringp keyword)
                             (not (string-empty-p keyword))
                             (not (member keyword keywords)))
                    (setq keywords (append keywords (list keyword))))))
      (dolist (file files)
        (dolist (keyword (glasspane-projects--file-todo-keywords file))
          (add keyword)))
      (dolist (keyword (jetpacs-org-settings-global-todo-keywords))
        (add keyword))
      (dolist (item items)
        (if-let* ((todo (alist-get 'todo item)))
            (add todo)
          (setq no-state t))))
    (append keywords (and no-state (list glasspane-projects--no-state)))))

(defun glasspane-projects--filter-row (items)
  "Build Project workflow filter chips for ITEMS."
  (apply
   #'jetpacs-flow-row
   (append
    (mapcar
     (lambda (keyword)
       (jetpacs-chip
        keyword
        :selected (jetpacs-bool (equal glasspane-projects--filter keyword))
        :on-tap (jetpacs-action "tasks.filter"
                                :args (list :filter keyword))))
     (cons "ALL" (glasspane-projects--todo-keywords items)))
    (list :spacing 4 :run-spacing 4))))

(defun glasspane-projects--grouped-cards (items)
  "Render tokenized Project ITEMS under Area headers."
  (let ((groups (glasspane-projects--group-by-area items)))
    (if groups
        (apply
         #'jetpacs-lazy-column
         (append
          (apply
           #'append
           (mapcar
            (lambda (group)
              (cons
               (jetpacs-section-header (car group))
               (mapcar #'glasspane-detail-agenda-card (cdr group))))
            groups))
          (list :spacing 8 :content-padding 12)))
      (jetpacs-empty-state
       :icon "task_alt"
       :title "No projects"
       :caption (if (equal glasspane-projects--filter "ALL")
                    "Tag a heading with :project: or create one here."
                  "Nothing matches this workflow state.")))))

(defun glasspane-projects--body ()
  "Build the Project screen from the PARA read API."
  (if (not (glasspane-para-ready-p))
      (jetpacs-empty-state
       :icon "database"
       :title "Vulpea is not ready"
       :caption "Install Glasspane's optional packages to index PARA notes.")
    (let* ((items (glasspane-projects--project-items))
           (filtered (glasspane-projects--filter-items items))
           (tokenized (glasspane-agenda-tokenize filtered "projects")))
      (jetpacs-column
       (glasspane-projects--filter-row items)
       (glasspane-projects--grouped-cards tokenized)))))

(defun glasspane-projects--actions ()
  "Return top-bar actions for the Project destination."
  (append
   (glasspane-ui-top-actions)
   (list
    (jetpacs-icon-button
     "add" (jetpacs-action "projects.capture")
     :content-description "New project"))))

(defun glasspane-projects-screen (back)
  "Build the Projects screen with BACK navigation."
  (jetpacs-chrome-screen
   "Projects" (glasspane-projects--body)
   :back back :actions (glasspane-projects--actions)
   :fab (and glasspane-ui-legacy-ia (glasspane-ui-capture-fab))))

;;;; Capture dialog

(defun glasspane-projects--area-options (areas)
  "Build dropdown options for AREA notes."
  (mapcar (lambda (area)
            (jetpacs-enum-option (or (vulpea-note-title area) "Untitled")
                                 (vulpea-note-id area)))
          areas))

(defun glasspane-projects--show-capture-dialog (preferred-id params)
  "Show the new-Project dialog, preferring Area PREFERRED-ID."
  (let* ((areas (glasspane-para-areas))
         (preferred (and preferred-id
                         (glasspane-para-note-by-id
                          preferred-id #'glasspane-para-area-p)))
         (selected (or preferred (car areas))))
    (if (null areas)
        (jetpacs-shell-notify
         "Create a PARA Area before adding a Project"
         (plist-get params :surface))
      (jetpacs-settings-show-dialog
       "glasspane-project-create"
       (jetpacs-column
        (jetpacs-text "New Project" :style "title")
        (jetpacs-text
         "Projects live as tagged headings inside an Area."
         :style "caption")
        (jetpacs-dropdown
         "para-project-area" (glasspane-projects--area-options areas)
         :value (vulpea-note-id selected) :label "Area")
        (jetpacs-text-input
         "para-project-title" :label "Project" :single-line t
         :autofocus t)
        (jetpacs-row
         (jetpacs-spacer :weight 1)
         (jetpacs-button "Cancel" (jetpacs-dialog-dismiss) :variant "text")
         (jetpacs-spacer :width 8)
         (jetpacs-button
          "Create"
          (jetpacs-dialog-submit
           :capture-fields '("para-project-area" "para-project-title"))))
        :spacing 8)
       :params params
       :on-submit
       (lambda (fields)
         (let* ((area-id (plist-get fields :para-project-area))
                (title (plist-get fields :para-project-title))
                (area (glasspane-para-note-by-id
                       area-id #'glasspane-para-area-p)))
           (condition-case err
               (if (null area)
                   (jetpacs-toast "That Area is no longer available")
                 (glasspane-para-capture-project area title)
                 (jetpacs-shell-notify "Project created"
                                       (plist-get params :surface))
                 (jetpacs-app-defer-refresh params))
             (error
              (message "glasspane-projects: capture failed: %s"
                       (jetpacs-error-label err))
              (jetpacs-toast "Project could not be created")))))))))

;;;; Actions and lifecycle

(defun glasspane-projects--on-open (_args params)
  "Open Projects in the one Tier-1 destination slot."
  (glasspane-ui-open-destination
   "projects" "glasspane-projects" #'glasspane-projects-screen params))

(defun glasspane-projects--on-filter (args params)
  "Select ARGS' Project workflow filter."
  (let ((filter (plist-get args :filter)))
    (if (not (stringp filter))
        'rejected
      (setq glasspane-projects--filter filter)
      (jetpacs-app-defer-refresh params)
      'accepted)))

(defun glasspane-projects--on-capture (args params)
  "Open the project capture dialog, optionally preselecting ARGS' Area."
  (let ((area-id (plist-get args :area)))
    (cond
     ((and area-id (not (stringp area-id))) 'rejected)
     ((not (glasspane-para-ready-p))
      (jetpacs-toast "Vulpea is not ready")
      'rejected)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (glasspane-projects--show-capture-dialog area-id params)))
      'accepted))))

(defun glasspane-projects--on-archive (args params)
  "Archive the Project named by ARGS' app-scoped token."
  (let ((token (plist-get args :token)))
    (cond
     ((not (stringp token)) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     (t
      (let ((ref (ebp-org-token-ref token :owner "glasspane")))
        (if (null ref)
            'stale
          (condition-case err
              (progn
                (glasspane-para-archive-project-ref ref)
                (jetpacs-shell-notify "Project archived"
                                      (plist-get params :surface))
                (jetpacs-app-defer-refresh params)
                'accepted)
            (ebp-org-unresolved 'stale)
            (ebp-org-refused 'rejected)
            (error
             (message "glasspane-projects: archive failed: %s"
                      (jetpacs-error-label err))
             (jetpacs-toast "Project could not be archived")
             'rejected))))))))

(defconst glasspane-projects--verbs
  '("projects.open" "tasks.open" "tasks.filter"
    "projects.capture" "projects.archive")
  "The Projects actions and compatibility aliases.")

(defun glasspane-projects-register ()
  "Register Project actions idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "projects.open" #'glasspane-projects--on-open
                       :doc "Open tagged PARA Projects")
    (jetpacs-defaction "tasks.open" #'glasspane-projects--on-open
                       :doc "Deprecated alias for projects.open")
    (jetpacs-defaction
     "tasks.filter" #'glasspane-projects--on-filter
     :doc "Select the Project workflow filter"
     :args '((:name filter :type "text" :required t)))
    (jetpacs-defaction
     "projects.capture" #'glasspane-projects--on-capture
     :doc "Create a tagged Project inside an Area"
     :args '((:name area :type "text")))
    (jetpacs-defaction
     "projects.archive" #'glasspane-projects--on-archive
     :doc "Archive a Project under its Area"
     :args '((:name token :type "text" :required t)))))

(defun glasspane-projects-unregister ()
  "Drop every action owned by the Projects module."
  (dolist (name glasspane-projects--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-projects)
;;; glasspane-projects.el ends here
