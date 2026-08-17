;;; glasspane-projects.el --- PARA Projects over Org TODO stages -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; PA-2d of docs/PLAN-glasspane-para.md.  Projects is the downstream PARA
;; opinion that every heading carrying an Org TODO stage belongs here.  The
;; module promotes the former Tasks body without replacing its upstream data
;; source: `glasspane-org-todo-items' retains both its whole-vault Vulpea arm
;; and canonical agenda-scope fallback.  Projects only filters, groups by
;; source file, and renders the shared cards.  It remains staged until PA-3.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-org-settings)
(require 'glasspane-org)
(require 'glasspane-agenda)
(require 'glasspane-detail)
(require 'glasspane-ui)

(defvar glasspane-projects--filter "ALL"
  "Current TODO-keyword filter for Projects (\"ALL\" means every stage).")

(defun glasspane-projects--archive-item-p (item)
  "Return non-nil when ITEM came from an Org archive file."
  (when-let* ((file (alist-get 'file item))
              ((stringp file)))
    (let ((case-fold-search t))
      (string-match-p "_archive\\'" file))))

(defun glasspane-projects--filter-items (items)
  "Apply the archive guard and active TODO filter to ITEMS."
  (let ((visible (cl-remove-if #'glasspane-projects--archive-item-p items)))
    (if (equal glasspane-projects--filter "ALL")
        visible
      (cl-remove-if-not
       (lambda (item)
         (equal (alist-get 'todo item) glasspane-projects--filter))
       visible))))

(defun glasspane-projects--group-by-file (items)
  "Group ITEMS by full source-file identity in deterministic path order.
Item order within each file remains the extractor's order."
  (sort (seq-group-by (lambda (item) (alist-get 'file item)) items)
        (lambda (a b)
          (let ((afile (car a)) (bfile (car b)))
            (string-lessp (if (stringp afile) afile "")
                          (if (stringp bfile) bfile ""))))))

(defun glasspane-projects--file-title (file)
  "Return FILE's section title, degrading for a missing source path."
  (if (and (stringp file) (not (string-empty-p file)))
      (file-name-nondirectory file)
    "Unknown file"))

(defun glasspane-projects--filter-row ()
  "Build the existing TODO-stage filter chips."
  (apply
   #'jetpacs-flow-row
   (append
    (mapcar
     (lambda (keyword)
       (jetpacs-chip
        keyword
        :selected (jetpacs-bool
                   (equal glasspane-projects--filter keyword))
        :on-tap (jetpacs-action "tasks.filter"
                                :args (list :filter keyword))))
     (cons "ALL" (or (jetpacs-org-settings-global-todo-keywords)
                     '("TODO" "DONE"))))
    (list :spacing 4))))

(defun glasspane-projects--grouped-cards (items)
  "Render tokenized ITEMS as shared cards under basename headers."
  (let ((groups (glasspane-projects--group-by-file items)))
    (if groups
        (apply
         #'jetpacs-lazy-column
         (append
          (apply
           #'append
           (mapcar
            (lambda (group)
              (cons (jetpacs-section-header
                     (glasspane-projects--file-title (car group)))
                    (mapcar #'glasspane-detail-agenda-card (cdr group))))
            groups))
          (list :spacing 8 :content-padding 12)))
      (jetpacs-empty-state :icon "task_alt"
                           :title "No projects"
                           :caption "Nothing matches this TODO filter."))))

(defun glasspane-projects--body ()
  "Build Projects from the shared TODO walk, filter, and card seams."
  (let* ((items (condition-case nil
                    (glasspane-org-todo-items)
                  (error nil)))
         (filtered (glasspane-projects--filter-items items))
         ;; Keep the established set name: promotion adds no token set.
         (tokenized (glasspane-agenda-tokenize filtered "tasks")))
    (jetpacs-column (glasspane-projects--filter-row)
                    (glasspane-projects--grouped-cards tokenized))))

(defun glasspane-projects-screen (back)
  "Build the staged Projects screen with BACK navigation."
  (jetpacs-chrome-screen "Projects" (glasspane-projects--body)
                         :back back :fab (glasspane-ui-capture-fab)))

(defun glasspane-projects--on-open (_args params)
  "Push the staged Projects screen onto the tapped surface."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       (condition-case err
           (jetpacs-chrome-push-screen
            surface "glasspane-projects" #'glasspane-projects-screen)
         (error (message "glasspane: projects push failed: %s"
                         (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-projects--on-filter (args params)
  "Select ARGS' TODO-stage filter and refresh the current screen."
  (let ((filter (plist-get args :filter)))
    (if (not (stringp filter))
        'rejected
      (setq glasspane-projects--filter filter)
      (jetpacs-app-defer-refresh params)
      'accepted)))

(defconst glasspane-projects--verbs
  '("projects.open" "tasks.open" "tasks.filter")
  "The staged Projects verb, legacy opener alias, and screen control.")

(defun glasspane-projects-register ()
  "Register Projects and its legacy Tasks contracts, idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "projects.open" #'glasspane-projects--on-open
                       :doc "Open the PARA Projects screen")
    (jetpacs-defaction "tasks.open" #'glasspane-projects--on-open
                       :doc "Deprecated alias for projects.open")
    (jetpacs-defaction "tasks.filter" #'glasspane-projects--on-filter)))

(defun glasspane-projects-unregister ()
  "Drop every verb owned by the Projects module."
  (dolist (name glasspane-projects--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-projects)
;;; glasspane-projects.el ends here
