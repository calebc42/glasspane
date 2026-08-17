;;; glasspane-areas.el --- PARA Areas over Org categories -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; PA-2a of docs/PLAN-glasspane-para.md.  Areas is the downstream PARA
;; opinion that an Org category is a persistent responsibility.  Native Org
;; scope, references, and mutation machinery stay in Jetpacs/EBP; this module
;; only groups the canonical local scope, renders the two Areas screens, and
;; owns their route verbs.  PA-3a exposes `areas.open' through Glasspane's
;; authoritative persistent-navigation table.

;;; Code:

(require 'cl-lib)
(require 'org)
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

;;;; Extraction

(defun glasspane-areas--category-name (value fallback)
  "Normalize category VALUE, using FALLBACK when it is empty."
  (let ((name (and (stringp value) (string-trim value))))
    (if (and name (not (string-empty-p name))) name fallback)))

(defun glasspane-areas--file-category (file)
  "Return FILE's keyword category, falling back to its basename.
The current buffer is widened Org content for FILE."
  (let* ((keywords (org-collect-keywords '("CATEGORY")))
         (declared (cadr (assoc-string "CATEGORY" keywords t)))
         (fallback (file-name-base file)))
    (glasspane-areas--category-name declared fallback)))

(defun glasspane-areas--prime-category-cache ()
  "Prime a file keyword category into Org's element cache when present.
Stock Emacs 30.1 can mis-compile the category cache-miss arm.  Touching the
keyword element before the heading walk keeps subsequent `org-get-category'
calls on the working cached path."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^[ \t]*#\\+CATEGORY:" nil t)
      (ignore-errors (org-element-at-point)))))

(defun glasspane-areas--heading-item (category)
  "Build the standard Glasspane item at point, tagged with CATEGORY."
  (let* ((components (org-heading-components))
         (todo (nth 2 components))
         (priority (nth 3 components))
         (headline (nth 4 components))
         (tags (org-get-tags))
         (scheduled (org-entry-get (point) "SCHEDULED"))
         (deadline (org-entry-get (point) "DEADLINE")))
    `((headline . ,headline)
      (todo . ,todo)
      (priority . ,(and priority (char-to-string priority)))
      (tags . ,(vconcat tags))
      (scheduled . ,scheduled)
      (deadline . ,deadline)
      (level . ,(nth 0 components))
      (category . ,category)
      (file . ,(buffer-file-name))
      (pos . ,(point))
      (ref . ,(ebp-org-ref-at-point)))))

(defun glasspane-areas--scan-file (file)
  "Return FILE's base category and open TODO items.
The result is `(:file PATH :base NAME :items ITEMS)'.  FILE is validated
against the Org roots and all visiting runs under clamped I/O."
  (let ((true (ebp-org--check-file file)))
    (ebp-org--with-clamped-io
      (with-current-buffer (find-file-noselect true t)
        (unless (derived-mode-p 'org-mode) (org-mode))
        (org-with-wide-buffer
         (let ((base (glasspane-areas--file-category true))
               items)
           (glasspane-areas--prime-category-cache)
           (org-map-entries
            (lambda ()
              (let ((todo (nth 2 (org-heading-components))))
                (when (and todo (not (org-entry-is-done-p)))
                  (let ((category
                         (glasspane-areas--category-name
                          (org-get-category) base)))
                    (push (glasspane-areas--heading-item category) items)))))
            "TODO<>\"\"" 'file)
           (list :file true :base base :items (nreverse items))))))))

(defun glasspane-areas--bucket (table category)
  "Return CATEGORY's mutable bucket in TABLE, creating it when absent."
  (or (gethash category table)
      (let ((bucket (list :name category :files nil :items nil)))
        (puthash category bucket table)
        bucket)))

(defun glasspane-areas--index-1 ()
  "Build the uncached category index over the canonical local Org scope.
One rotten file is skipped without costing every other Area."
  (let ((table (make-hash-table :test #'equal))
        areas)
    ;; Deliberately no Vulpea arm: its note rows do not preserve inherited
    ;; heading categories, so using it when available would silently change
    ;; the PARA buckets for the same vault.
    (dolist (file (delete-dups
                   (copy-sequence (or (glasspane-org-agenda-scope) nil))))
      (when-let* ((scan (condition-case nil
                            (glasspane-areas--scan-file file)
                          (error nil)))
                  (true (plist-get scan :file))
                  (base (plist-get scan :base)))
        (let ((bucket (glasspane-areas--bucket table base)))
          (cl-pushnew true (plist-get bucket :files) :test #'equal))
        (dolist (item (plist-get scan :items))
          (let* ((category (alist-get 'category item))
                 (bucket (glasspane-areas--bucket table category)))
            (cl-pushnew true (plist-get bucket :files) :test #'equal)
            (push item (plist-get bucket :items))))))
    (maphash
     (lambda (_name bucket)
       (setf (plist-get bucket :files)
             (sort (plist-get bucket :files) #'string-lessp)
             (plist-get bucket :items)
             (nreverse (plist-get bucket :items)))
       (push bucket areas))
     table)
    (sort areas
          (lambda (a b)
            (string-lessp (plist-get a :name) (plist-get b :name))))))

(defun glasspane-areas--index ()
  "Return the memoised Areas index."
  (ebp-org-with-cache 'glasspane '(areas-index)
    (glasspane-areas--index-1)))

(defun glasspane-areas--find (category)
  "Return CATEGORY's current area record, or nil when it vanished."
  (cl-find category (glasspane-areas--index)
           :key (lambda (area) (plist-get area :name))
           :test #'equal))

;;;; Rendering

(defun glasspane-areas--count-label (area)
  "Return AREA's compact open-TODO and file counts."
  (let ((todos (length (plist-get area :items)))
        (files (length (plist-get area :files))))
    (format "%d open TODO%s · %d file%s"
            todos (if (= todos 1) "" "s")
            files (if (= files 1) "" "s"))))

(defun glasspane-areas--area-row (area)
  "Render AREA as a drill row with plain string arguments."
  (let ((name (plist-get area :name)))
    (jetpacs-chrome-row
     name
     :subtitle (glasspane-areas--count-label area)
     :icon "category"
     :trailing (jetpacs-icon "chevron_right")
     :on-tap (jetpacs-action "areas.drill" :args (list :category name))
     :key (jetpacs-wire-id "area-row" name))))

(defun glasspane-areas--list-body ()
  "Render the sorted Areas index or its empty state."
  (let ((areas (condition-case nil (glasspane-areas--index) (error nil))))
    (if areas
        (apply #'jetpacs-lazy-column
               (append (mapcar #'glasspane-areas--area-row areas)
                       (list :spacing 8 :content-padding 12)))
      (jetpacs-empty-state
       :icon "category"
       :title "No areas"
       :caption "No Org categories were found in the local agenda scope."))))

(defun glasspane-areas--file-row (file)
  "Render FILE as a handoff to the forthcoming Resources wrapper."
  (jetpacs-chrome-row
   (file-name-nondirectory file)
   :subtitle (abbreviate-file-name file)
   :icon "description"
   :trailing (jetpacs-icon "chevron_right")
   :on-tap (jetpacs-action "resources.open-file" :args (list :path file))
   :key (jetpacs-wire-id "area-file" file)))

(defun glasspane-areas--drill-body (category)
  "Render CATEGORY's open TODO cards and files.
A category that vanished between row render and tap degrades in place and
sweeps the prior Areas token generation."
  (let ((area (condition-case nil (glasspane-areas--find category)
                (error nil))))
    (if (null area)
        (progn
          (glasspane-agenda-tokenize nil "areas")
          (jetpacs-empty-state
           :icon "category"
           :title "Area no longer exists"
           :caption "Refresh Areas to see the current Org categories."))
      (let* ((items (glasspane-agenda-tokenize
                     (plist-get area :items) "areas"))
             (cards (mapcar #'glasspane-detail-agenda-card items))
             (files (mapcar #'glasspane-areas--file-row
                            (plist-get area :files))))
        (apply #'jetpacs-lazy-column
               (append
                (list (jetpacs-section-header "Open TODOs"))
                (or cards
                    (list (jetpacs-text "No open TODOs in this area."
                                        :style "caption")))
                (list (jetpacs-divider)
                      (jetpacs-section-header "Files"))
                (or files
                    (list (jetpacs-text "No files in this area."
                                        :style "caption")))
                (list :spacing 8 :content-padding 12)))))))

(defun glasspane-areas-screen (back)
  "Build the Areas list screen with BACK navigation."
  (jetpacs-chrome-screen "Areas" (glasspane-areas--list-body)
                         :back back
                         :fab (and glasspane-ui-legacy-ia
                                   (glasspane-ui-capture-fab))))

(defun glasspane-areas-drill-screen (category back)
  "Build CATEGORY's Area drill screen with BACK navigation."
  (jetpacs-chrome-screen category (glasspane-areas--drill-body category)
                         :back back
                         :fab (and glasspane-ui-legacy-ia
                                   (glasspane-ui-capture-fab))))

;;;; Actions and lifecycle

(defun glasspane-areas--push-screen (params id builder)
  "Defer-push screen ID via BUILDER onto PARAMS' surface."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       (condition-case err
           (jetpacs-chrome-push-screen surface id builder)
         (error (message "glasspane: %s push failed: %s"
                         id (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-areas--on-open (_args params)
  "Push the Areas list onto the tapped surface."
  (glasspane-areas--push-screen params "glasspane-areas"
                                #'glasspane-areas-screen))

(defun glasspane-areas--on-drill (args params)
  "Open ARGS' plain-string `:category', even if it just vanished."
  (let ((category (plist-get args :category)))
    (if (not (and (stringp category) (not (string-empty-p category))))
        'rejected
      (glasspane-areas--push-screen
       params (jetpacs-wire-id "area" category)
       (lambda (back) (glasspane-areas-drill-screen category back))))))

(defconst glasspane-areas--verbs '("areas.open" "areas.drill")
  "The Areas verbs owned by this module.")

(defun glasspane-areas-register ()
  "Register the Areas verbs, idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "areas.open" #'glasspane-areas--on-open
                       :doc "Open the PARA Areas screen")
    (jetpacs-defaction "areas.drill" #'glasspane-areas--on-drill
                       :doc "Open one PARA Area by Org category")))

(defun glasspane-areas-unregister ()
  "Drop every verb owned by the Areas module."
  (dolist (name glasspane-areas--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-areas)
;;; glasspane-areas.el ends here
