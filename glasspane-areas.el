;;; glasspane-areas.el --- PARA Area notes on Glasspane -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; An Area is one file-level Vulpea note carrying the configurable `area'
;; tag.  Its title is the responsibility's name, and tagged Project headings
;; in that same file belong to it.  This replaces the former interpretation
;; of every member in an Org tag-group named "Area" as a separate Area.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-settings)
(require 'glasspane-para)
(require 'glasspane-agenda)
(require 'glasspane-detail)
(require 'glasspane-resources)
(require 'glasspane-ui)

(declare-function vulpea-note-id "ext:vulpea-note" (note))
(declare-function vulpea-note-path "ext:vulpea-note" (note))
(declare-function vulpea-note-title "ext:vulpea-note" (note))

(defun glasspane-areas--area-by-title (title)
  "Return the uniquely titled Area named TITLE, or nil."
  (let ((matches (cl-remove-if-not
                  (lambda (area)
                    (equal (vulpea-note-title area) title))
                  (glasspane-para-areas))))
    (and (= 1 (length matches)) (car matches))))

(defun glasspane-areas--resolve (id legacy-title)
  "Resolve an Area by ID, with LEGACY-TITLE as compatibility fallback."
  (or (and id (glasspane-para-note-by-id id #'glasspane-para-area-p))
      (and legacy-title (glasspane-areas--area-by-title legacy-title))))

(defun glasspane-areas--count-label (area)
  "Return AREA's compact Project count and facet reminder."
  (let ((count (length (glasspane-para-projects-in-area area))))
    (format "%d project%s · also a resource"
            count (if (= count 1) "" "s"))))

(defun glasspane-areas--area-row (area)
  "Render AREA as a drill row."
  (let ((id (vulpea-note-id area))
        (title (or (vulpea-note-title area) "Untitled Area")))
    (jetpacs-chrome-row
     title
     :subtitle (glasspane-areas--count-label area)
     :icon "category"
     :trailing (jetpacs-icon "chevron_right")
     :on-tap (jetpacs-action "areas.drill" :args (list :area id))
     :key (jetpacs-wire-id "area-row" (or id title)))))

(defun glasspane-areas--list-body ()
  "Render file-level Area notes."
  (cond
   ((not (glasspane-para-ready-p))
    (jetpacs-empty-state
     :icon "database"
     :title "Vulpea is not ready"
     :caption "Install Glasspane's optional packages to index PARA notes."))
   ((glasspane-para-areas)
    (apply #'jetpacs-lazy-column
           (append (mapcar #'glasspane-areas--area-row
                           (glasspane-para-areas))
                   (list :spacing 8 :content-padding 12))))
   (t
    (jetpacs-empty-state
     :icon "category"
     :title "No areas"
     :caption "Tag a file-level note with :area: or create one here."))))

(defun glasspane-areas--project-items (area)
  "Return AREA's Projects as shared card items."
  (mapcar
   (lambda (project)
     (append
      (list (cons 'para-project t)
            (cons 'area-title (vulpea-note-title area))
            (cons 'area-id (vulpea-note-id area)))
      (glasspane-para-note-item project)))
   (glasspane-para-projects-in-area area)))

(defun glasspane-areas--archive-cards (area)
  "Return tappable archived Project cards from AREA."
  (mapcar #'glasspane-detail-result-card
          (glasspane-ui-tokenize-tap
           (glasspane-para-archive-items (list (vulpea-note-path area)))
           "area-archives")))

(defun glasspane-areas--drill-body (area)
  "Render AREA's overlapping Project, Resource, and Archive facets."
  (let* ((projects
          (mapcar #'glasspane-detail-agenda-card
                  (glasspane-agenda-tokenize
                   (glasspane-areas--project-items area) "area-projects")))
         (resource (glasspane-resources-note-row area "area-resource"))
         (archives (glasspane-areas--archive-cards area)))
    (apply
     #'jetpacs-lazy-column
     (append
      (list (jetpacs-section-header "Projects"))
      (or projects
          (list (jetpacs-text "No tagged Projects in this Area."
                              :style "caption")))
      (list (jetpacs-divider)
            (jetpacs-section-header "Resources")
            resource
            (jetpacs-divider)
            (jetpacs-section-header "Archive"))
      (or archives
          (list (jetpacs-text "No archived Projects in this Area."
                              :style "caption")))
      (list :spacing 8 :content-padding 12)))))

(defun glasspane-areas--list-actions ()
  "Return Areas destination top-bar actions."
  (append
   (glasspane-ui-top-actions)
   (list
    (jetpacs-icon-button
     "add" (jetpacs-action "areas.capture")
     :content-description "New area"))))

(defun glasspane-areas--drill-actions (area)
  "Return AREA drill top-bar actions."
  (append
   (glasspane-ui-top-actions)
   (list
    (jetpacs-icon-button
     "add"
     (jetpacs-action "projects.capture"
                     :args (list :area (vulpea-note-id area)))
     :content-description "New project"))))

(defun glasspane-areas-screen (back)
  "Build the Areas list screen with BACK navigation."
  (jetpacs-chrome-screen
   "Areas" (glasspane-areas--list-body)
   :back back :actions (glasspane-areas--list-actions)
   :fab (and glasspane-ui-legacy-ia (glasspane-ui-capture-fab))))

(defun glasspane-areas-drill-screen (area back)
  "Build AREA's drill screen with BACK navigation."
  (jetpacs-chrome-screen
   (or (vulpea-note-title area) "Area")
   (glasspane-areas--drill-body area)
   :back back :actions (glasspane-areas--drill-actions area)
   :fab (and glasspane-ui-legacy-ia (glasspane-ui-capture-fab))))

;;;; Area capture dialog

(defun glasspane-areas--show-capture-dialog (params)
  "Show a one-field new-Area dialog."
  (jetpacs-settings-show-dialog
   "glasspane-area-create"
   (jetpacs-column
    (jetpacs-text "New Area" :style "title")
    (jetpacs-text
     "An Area is a tagged note for an ongoing responsibility."
     :style "caption")
    (jetpacs-text-input "para-area-title" :label "Area"
                        :single-line t :autofocus t)
    (jetpacs-row
     (jetpacs-spacer :weight 1)
     (jetpacs-button "Cancel" (jetpacs-dialog-dismiss) :variant "text")
     (jetpacs-spacer :width 8)
     (jetpacs-button
      "Create"
      (jetpacs-dialog-submit :capture-fields '("para-area-title"))))
    :spacing 8)
   :params params
   :on-submit
   (lambda (fields)
     (condition-case err
         (progn
           (glasspane-para-capture-area (plist-get fields :para-area-title))
           (jetpacs-shell-notify "Area created" (plist-get params :surface))
           (jetpacs-app-defer-refresh params))
       (error
        (message "glasspane-areas: capture failed: %s"
                 (jetpacs-error-label err))
        (jetpacs-toast "Area could not be created"))))))

;;;; Actions and lifecycle

(defun glasspane-areas--on-open (_args params)
  "Open the Areas list in the Tier-1 destination slot."
  (glasspane-ui-open-destination
   "areas" "glasspane-areas" #'glasspane-areas-screen params))

(defun glasspane-areas--on-drill (args params)
  "Open the Area identified by ARGS."
  (let ((id (plist-get args :area))
        (legacy (plist-get args :category)))
    (if (not (and (or (null id) (stringp id))
                  (or (null legacy) (stringp legacy))))
        'rejected
      (if-let* ((area (glasspane-areas--resolve id legacy)))
          (progn
            (glasspane-ui-open-destination
             "areas"
             (jetpacs-wire-id "area" (vulpea-note-id area))
             (lambda (back) (glasspane-areas-drill-screen area back))
             params)
            'accepted)
        'stale))))

(defun glasspane-areas--on-capture (_args params)
  "Open the Area capture dialog."
  (cond
   ((not (glasspane-para-ready-p))
    (jetpacs-toast "Vulpea is not ready")
    'rejected)
   ((null (jetpacs-client)) 'rejected)
   (t
    (jetpacs-flow-continue
     (lambda () (glasspane-areas--show-capture-dialog params)))
    'accepted)))

(defconst glasspane-areas--verbs
  '("areas.open" "areas.drill" "areas.capture")
  "The Area destination, drill, and capture actions.")

(defun glasspane-areas-register ()
  "Register Area actions idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "areas.open" #'glasspane-areas--on-open
                       :doc "Open file-level PARA Areas")
    (jetpacs-defaction
     "areas.drill" #'glasspane-areas--on-drill
     :doc "Open a PARA Area"
     :args '((:name area :type "text")
             (:name category :type "text")))
    (jetpacs-defaction "areas.capture" #'glasspane-areas--on-capture
                       :doc "Create a file-level PARA Area")))

(defun glasspane-areas-unregister ()
  "Drop every action owned by the Areas module."
  (dolist (name glasspane-areas--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-areas)
;;; glasspane-areas.el ends here
