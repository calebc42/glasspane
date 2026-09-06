;;; glasspane-projects.el --- PARA Projects over Org TODO stages -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; PM-6 of docs/PLAN-glasspane-para.md (the 2026-09-04 amendment).  A
;; Project is any heading carrying an Org TODO keyword — nothing else
;; makes something a Project, and no tag, directory, or Area file is
;; required.  The module keeps the shared data source whole:
;; `glasspane-org-todo-items' retains both its whole-vault index arm and
;; its agenda-scope fallback.  Projects only filters (archive files out,
;; then the workflow keyword and one optional Area facet), groups — by source
;; file, or by the Areas a heading carries through the native tag group — and
;; renders the shared cards with Area chips elevated.  `projects.open' is the
;; destination; `tasks.open' survives as its compatibility alias.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ebp-org)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'glasspane-org)
(require 'glasspane-agenda)
(require 'glasspane-detail)
(require 'glasspane-ui)

(defvar glasspane-projects--filter "ALL"
  "Current TODO-keyword filter for Projects (\"ALL\" means every stage).")

(defvar glasspane-projects--group "file"
  "Current Projects grouping: \"file\" (source file) or \"area\".")

(defvar glasspane-projects--area-filter nil
  "Current Projects Area filter, or nil to include every Area.")

(defconst glasspane-projects--no-area "No Area"
  "Group label for a Project carrying no Area tag.")

;;;; Filtering and grouping

(defun glasspane-projects--archive-item-p (item)
  "Return non-nil when ITEM came from an Org archive file."
  (when-let* ((file (alist-get 'file item))
              ((stringp file)))
    (let ((case-fold-search t))
      (string-match-p "_archive\\'" file))))

(defun glasspane-projects--filter-items (items)
  "Apply archive, workflow, and Area filters to ITEMS, in that order."
  (let* ((visible (cl-remove-if #'glasspane-projects--archive-item-p items))
         (workflow
          (if (equal glasspane-projects--filter "ALL")
              visible
            (cl-remove-if-not
             (lambda (item)
               (equal (alist-get 'todo item) glasspane-projects--filter))
             visible))))
    (if (null glasspane-projects--area-filter)
        workflow
      (cl-remove-if-not
       (lambda (item)
         (member glasspane-projects--area-filter
                 (glasspane-projects--item-areas item)))
       workflow))))

(defun glasspane-projects--group-by-file (items)
  "Group ITEMS by full source-file identity in deterministic path order.
Item order within each file remains the extractor's order."
  (sort (seq-group-by (lambda (item) (alist-get 'file item)) items)
        (lambda (a b)
          (let ((afile (car a)) (bfile (car b)))
            (string-lessp (if (stringp afile) afile "")
                          (if (stringp bfile) bfile ""))))))

(defun glasspane-projects--item-areas (item)
  "Return ITEM's Area-group memberships, resolved at its source position."
  (condition-case nil
      (glasspane-org-item-tag-group-members item glasspane-area-tag-group)
    (error nil)))

(defun glasspane-projects--group-by-area (items)
  "Group ITEMS by every Area each carries; unassigned Projects come last.
A heading in two Areas appears under both, which is the facets model:
buckets are not walls."
  (let ((table (make-hash-table :test #'equal))
        groups)
    (dolist (item items)
      (let ((areas (or (glasspane-projects--item-areas item)
                       (list glasspane-projects--no-area))))
        (dolist (area areas)
          (push item (gethash area table)))))
    (maphash (lambda (name members) (push (cons name (nreverse members)) groups))
             table)
    (sort groups
          (lambda (a b)
            (let ((ak (car a)) (bk (car b)))
              (cond
               ((equal ak glasspane-projects--no-area) nil)
               ((equal bk glasspane-projects--no-area) t)
               (t (string-lessp ak bk))))))))

(defun glasspane-projects--file-title (file)
  "Return FILE's section title, degrading for a missing source path."
  (if (and (stringp file) (not (string-empty-p file)))
      (file-name-nondirectory file)
    "Unknown file"))

(defun glasspane-projects--area-names (items)
  "Return the distinct Area memberships represented by ITEMS, sorted."
  (let (names)
    (dolist (item items)
      (dolist (area (glasspane-projects--item-areas item))
        (when (and (stringp area) (not (string-empty-p area)))
          (cl-pushnew area names :test #'equal))))
    (sort names #'string-lessp)))

;;;; Rendering

(defun glasspane-projects--filter-row (items)
  "Build the workflow filter chips for ITEMS."
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
     (cons "ALL" (glasspane-org-workflow-keywords items)))
    (list :spacing 4 :run-spacing 4))))

(defun glasspane-projects--group-chips ()
  "Build the grouping-chip fallback for receivers without segmented buttons."
  (jetpacs-flow-row
   (jetpacs-chip "By File"
                 :selected (jetpacs-bool (equal glasspane-projects--group "file"))
                 :on-tap (jetpacs-action "projects.group" :args '(:by "file")))
   (jetpacs-chip "By Area"
                 :selected (jetpacs-bool (equal glasspane-projects--group "area"))
                 :on-tap (jetpacs-action "projects.group" :args '(:by "area")))
   :spacing 4 :run-spacing 4))

(defun glasspane-projects--group-control ()
  "Build the visually connected File/Area grouping control.
Use a stable stateful ID so the Companion can reconcile the selected segment;
older receivers retain the equivalent chip actions."
  (if (jetpacs-node-advertised-p "segmented_button")
      (jetpacs-segmented-button
       "projects-grouping"
       (list (jetpacs-enum-option "By File" "file" :icon "folder")
             (jetpacs-enum-option "By Area" "area" :icon "category"))
       :value glasspane-projects--group
       :on-change (jetpacs-action "projects.group"))
    (glasspane-projects--group-chips)))

(defun glasspane-projects--controls-row (items)
  "Place ITEMS' workflow filters left and the grouping control right.
The weighted flow row consumes remaining width and wraps its own chips without
displacing the grouping control from the row's trailing edge."
  (jetpacs-row
   (jetpacs-with-attrs (glasspane-projects--filter-row items) :weight 1)
   (glasspane-projects--group-control)
   :spacing 12 :align "top" :fill t))

(defun glasspane-projects--area-filter-row (items)
  "Build the single-select Area filter row over Project ITEMS."
  (apply
   #'jetpacs-flow-row
   (append
    (list
     (jetpacs-chip
      "All Areas"
      :icon "category"
      :selected (jetpacs-bool (null glasspane-projects--area-filter))
      :on-tap (jetpacs-action "projects.area-filter")))
    (mapcar
     (lambda (area)
       (jetpacs-chip
        area
        :icon (glasspane-area-icon area)
        :selected (jetpacs-bool
                   (equal glasspane-projects--area-filter area))
        :on-tap (jetpacs-action "projects.area-filter"
                                :args (list :area area))))
     (glasspane-projects--area-names items))
    (list :spacing 4 :run-spacing 4))))

(defun glasspane-projects--card (item)
  "Render tokenized ITEM as the shared card with its Area chips elevated."
  (glasspane-detail-agenda-card item (glasspane-projects--item-areas item)))

(defun glasspane-projects--groups (items)
  "Group tokenized ITEMS per the current grouping, titled for headers."
  (if (equal glasspane-projects--group "area")
      (glasspane-projects--group-by-area items)
    (mapcar (lambda (group)
              (cons (glasspane-projects--file-title (car group))
                    (cdr group)))
            (glasspane-projects--group-by-file items))))

(defun glasspane-projects--grouped-cards (items)
  "Render tokenized ITEMS as shared cards under group headers."
  (let ((groups (glasspane-projects--groups items)))
    (if groups
        (apply
         #'jetpacs-lazy-column
         (append
          (apply
           #'append
           (mapcar
            (lambda (group)
              (cons (jetpacs-section-header (car group))
                    (mapcar #'glasspane-projects--card (cdr group))))
            groups))
          (list :spacing 8 :content-padding 12)))
      (jetpacs-empty-state
       :icon "task_alt"
       :title "No projects"
       :caption
       (cond
        ((and (equal glasspane-projects--filter "ALL")
              (null glasspane-projects--area-filter))
         "Give any heading a TODO keyword and it lands here.")
        ((and glasspane-projects--area-filter
              (not (equal glasspane-projects--filter "ALL")))
         "Nothing matches this workflow state and Area.")
        (glasspane-projects--area-filter
         "No Projects belong to this Area.")
        (t "Nothing matches this workflow state."))))))

(defun glasspane-projects--body ()
  "Build Projects from the shared TODO walk, filter, and card seams."
  (let* ((items (condition-case nil
                    (glasspane-org-todo-items)
                  (error nil)))
         (filtered (glasspane-projects--filter-items items))
         ;; Keep the established set name: promotion adds no token set.
         (tokenized (glasspane-agenda-tokenize filtered "tasks")))
    (jetpacs-column (glasspane-projects--controls-row items)
                    (glasspane-projects--area-filter-row items)
                    (glasspane-projects--grouped-cards tokenized)
                    :spacing 8)))

(defun glasspane-projects-screen (back)
  "Build the Projects screen with BACK navigation."
  (jetpacs-chrome-screen "Projects" (glasspane-projects--body)
                         :back back
                         :actions (glasspane-ui-top-actions)
                         :fab (and glasspane-ui-legacy-ia
                                   (glasspane-ui-capture-fab))))

;;;; Actions and lifecycle

(defun glasspane-projects--on-open (_args params)
  "Open Projects in the one Tier-1 destination slot.
PARAMS is the originating action event."
  (glasspane-ui-open-destination
   "projects" "glasspane-projects" #'glasspane-projects-screen params))

(defun glasspane-projects--on-filter (args params)
  "Select ARGS' workflow filter and refresh the current screen.
PARAMS carry the surface for the deferred refresh."
  (let ((filter (plist-get args :filter)))
    (if (not (stringp filter))
        'rejected
      (setq glasspane-projects--filter filter)
      (jetpacs-app-defer-refresh params)
      'accepted)))

(defun glasspane-projects--on-group (args params)
  "Select ARGS' grouping and refresh the screen.
`:value' is injected by the segmented control; `:by' preserves the chip
fallback and actions already rendered by an older screen.  PARAMS carry the
surface for the deferred refresh."
  (let ((by (or (plist-get args :value) (plist-get args :by))))
    (if (not (member by '("file" "area")))
        'rejected
      (setq glasspane-projects--group by)
      (jetpacs-app-defer-refresh params)
      'accepted)))

(defun glasspane-projects--on-area-filter (args params)
  "Select ARGS' optional `:area' Project facet and refresh.
An absent value means all Areas.  PARAMS carry the surface for the deferred
refresh."
  (let ((area (plist-get args :area)))
    (if (not (or (null area)
                 (and (stringp area) (not (string-empty-p area)))))
        'rejected
      (setq glasspane-projects--area-filter area)
      (jetpacs-app-defer-refresh params)
      'accepted)))

(defconst glasspane-projects--verbs
  '("projects.open" "tasks.open" "tasks.filter" "projects.group"
    "projects.area-filter")
  "The Projects verb, its legacy opener alias, and the screen controls.")

(defun glasspane-projects-register ()
  "Register Projects and its legacy Tasks contracts, idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "projects.open" #'glasspane-projects--on-open
                       :doc "Open the PARA Projects screen")
    (jetpacs-defaction "tasks.open" #'glasspane-projects--on-open
                       :doc "Deprecated alias for projects.open")
    (jetpacs-defaction
     "tasks.filter" #'glasspane-projects--on-filter
     :doc "Select the Projects workflow filter"
     :args '((:name filter :type "text" :required t)))
    (jetpacs-defaction
     "projects.group" #'glasspane-projects--on-group
     :doc "Group Projects by source file or by Area"
     :args '((:name value :type "text")
             (:name by :type "text")))
    (jetpacs-defaction
     "projects.area-filter" #'glasspane-projects--on-area-filter
     :doc "Filter Projects to one Area, or clear the Area filter"
     :args '((:name area :type "text")))))

(defun glasspane-projects-unregister ()
  "Drop every verb owned by the Projects module."
  (dolist (name glasspane-projects--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-projects)
;;; glasspane-projects.el ends here
