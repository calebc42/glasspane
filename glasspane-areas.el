;;; glasspane-areas.el --- PARA Areas as tag-group queries -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; PM-5 of docs/PLAN-glasspane-para.md (the 2026-09-04 amendment).  An
;; Area is a member of the native, non-exclusive Org tag group named by
;; `glasspane-area-tag-group' — never a file, directory, or category.
;; Anything carrying the tag locally, by inheritance, or through
;; `#+FILETAGS' is a member, so one note may belong to many Areas.  The
;; Areas list is the set of declared members; a drill is an agenda-style
;; query over one member, intersected with any further members the user
;; selects.  An Area MAY additionally be a first-class note: a heading or
;; file whose property drawer declares `AREA' with the Area's tag.  That
;; note opens as a document from the drill and, when it carries its own
;; tag, is a member of itself.  Membership is always resolved from the
;; files (`org-get-tags' with inheritance forced on); the vault index is
;; consulted only for declarations, through `glasspane-org'.

;;; Code:

(require 'cl-lib)
(require 'org)
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
(require 'glasspane-resources)
(require 'glasspane-navigation)
(require 'glasspane-ui)

;;;; Extraction

(defun glasspane-areas--members-here ()
  "Return the Area group's members visible in the current Org buffer.
The buffer-local `org-tag-groups-alist' already merges the persistent
alist, the file's own `#+TAGS' lines or the global alist, so per-file
declarations and the settings-managed group both count."
  (glasspane-org--clean-tag-strings
   (cdr (assoc-string glasspane-area-tag-group org-tag-groups-alist t))))

(defun glasspane-areas--global-members ()
  "Return the Area group's members declared outside any file."
  (condition-case nil
      (glasspane-org--clean-tag-strings
       (cdr (assoc-string
             glasspane-area-tag-group
             (org-tag-alist-to-groups
              (append org-tag-persistent-alist org-tag-alist))
             t)))
    (error nil)))

(defun glasspane-areas--file-declaration (file)
  "Return FILE's file-level AREA declaration when the drawer precedes text.
The current buffer is FILE's widened Org content."
  (save-excursion
    (goto-char (point-min))
    (let ((value (org-entry-get (point-min) "AREA")))
      (and (stringp value)
           (not (string-empty-p (string-trim value)))
           (list :name (string-trim value) :file file :level 0)))))

(defun glasspane-areas--scan-file (file)
  "Return FILE's Area memberships, declarations, and open work.
The result is a plist (:file PATH :areas MEMBERS-USED :file-areas
FILE-TAG-MEMBERS :declares DECLARATIONS :items OPEN-TODO-ITEMS).  Every
item carries an `areas' vector in the group's declaration order.  FILE is
validated against the Org roots and visited under clamped I/O."
  (let ((true (ebp-org--check-file file)))
    (ebp-org--with-clamped-io
      (with-current-buffer (find-file-noselect true t)
        (unless (derived-mode-p 'org-mode) (org-mode))
        (org-with-wide-buffer
         (let* ((org-use-tag-inheritance t)
                (members (glasspane-areas--members-here))
                (file-tags (glasspane-org--clean-tag-strings org-file-tags))
                (file-areas (cl-remove-if-not
                             (lambda (member) (member member file-tags))
                             members))
                (used (copy-sequence file-areas))
                (declares (let ((decl (glasspane-areas--file-declaration true)))
                            (and decl (list decl))))
                items)
           (org-map-entries
            (lambda ()
              (let* ((tags (glasspane-org--clean-tag-strings (org-get-tags)))
                     (areas (cl-remove-if-not
                             (lambda (member) (member member tags))
                             members))
                     (decl (org-entry-get (point) "AREA"))
                     (item (glasspane-org--heading-item-at)))
                (dolist (area areas) (cl-pushnew area used :test #'equal))
                (push (cons 'areas (vconcat areas)) item)
                (when (and (stringp decl)
                           (not (string-empty-p (string-trim decl))))
                  (push (list :name (string-trim decl) :file true
                              :level (alist-get 'level item) :item item)
                        declares))
                (when (glasspane-org-open-todo-p item)
                  (push item items))))
            nil 'file)
           (list :file true
                 :members members
                 :areas (nreverse used)
                 :file-areas file-areas
                 :declares (nreverse declares)
                 :items (nreverse items))))))))

(defun glasspane-areas--bucket (table name)
  "Return NAME's mutable bucket in TABLE, creating it when absent."
  (or (gethash name table)
      (let ((bucket (list :name name :files nil :items nil :declares nil)))
        (puthash name bucket table)
        bucket)))

(defun glasspane-areas--index-1 ()
  "Build the uncached Areas index over the canonical local Org scope.
Every declared member of the group is a bucket, even one nothing carries
yet.  A file is in a bucket when its file tags or any heading carry the
member; items are the open TODO headings carrying it; declarations are
the notes whose AREA property names a member (a declaration never
creates an Area — the group is the registry).  One rotten file is
skipped without costing every other Area."
  (let ((table (make-hash-table :test #'equal))
        areas)
    (dolist (name (glasspane-areas--global-members))
      (glasspane-areas--bucket table name))
    (dolist (file (delete-dups
                   (copy-sequence (or (glasspane-org-agenda-scope) nil))))
      (when-let* ((scan (condition-case nil
                            (glasspane-areas--scan-file file)
                          (error nil)))
                  (true (plist-get scan :file)))
        (dolist (name (plist-get scan :members))
          (glasspane-areas--bucket table name))
        (dolist (name (plist-get scan :areas))
          (let ((bucket (glasspane-areas--bucket table name)))
            (cl-pushnew true (plist-get bucket :files) :test #'equal)))
        (dolist (item (plist-get scan :items))
          (dolist (name (append (alist-get 'areas item) nil))
            (let ((bucket (glasspane-areas--bucket table name)))
              (push item (plist-get bucket :items)))))
        ;; A declaration annotates a member of the group; it never mints
        ;; an Area on its own, so a stray AREA property elsewhere in the
        ;; vault cannot invent one.
        (dolist (decl (plist-get scan :declares))
          (when-let* ((bucket (gethash (plist-get decl :name) table)))
            (push decl (plist-get bucket :declares))))))
    ;; Declarations the vault index knows about but the local scope did
    ;; not visit (a note outside the agenda scope).  The scan wins on a
    ;; name the walk already declared.
    (dolist (decl (condition-case nil
                      (glasspane-org-indexed-area-declarations)
                    (error nil)))
      (let ((file (plist-get decl :file)))
        (when-let* (((and (stringp file) (ebp-org-file-allowed-p file)))
                    (bucket (gethash (plist-get decl :name) table)))
          (unless (plist-get bucket :declares)
            (push decl (plist-get bucket :declares))))))
    (maphash
     (lambda (_name bucket)
       (setf (plist-get bucket :files)
             (sort (plist-get bucket :files) #'string-lessp)
             (plist-get bucket :items)
             (nreverse (plist-get bucket :items))
             (plist-get bucket :declares)
             (nreverse (plist-get bucket :declares)))
       (push bucket areas))
     table)
    (sort areas
          (lambda (a b)
            (string-lessp (plist-get a :name) (plist-get b :name))))))

(defun glasspane-areas--index ()
  "Return the memoised Areas index."
  (ebp-org-with-cache 'glasspane '(areas-index)
    (glasspane-areas--index-1)))

(defun glasspane-areas--find (name)
  "Return NAME's current Area record, or nil when it vanished."
  (cl-find name (glasspane-areas--index)
           :key (lambda (area) (plist-get area :name))
           :test #'equal))

;;;; Rendering — the list

(defun glasspane-areas--count-label (area)
  "Return AREA's compact open-TODO and file counts."
  (let ((todos (length (plist-get area :items)))
        (files (length (plist-get area :files))))
    (format "%d open TODO%s · %d file%s"
            todos (if (= todos 1) "" "s")
            files (if (= files 1) "" "s"))))

(defun glasspane-areas--area-row (area)
  "Render AREA as a drill row with plain string arguments.
The list mints no tokens: a row names its Area by tag and nothing else."
  (let* ((name (plist-get area :name))
         (subtitle (glasspane-areas--count-label area)))
    (jetpacs-chrome-row
     name
     :subtitle (if (plist-get area :declares)
                   (concat subtitle " · note")
                 subtitle)
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
       :title "No Areas yet"
       :caption (format
                 "Add members to the %s tag group in Settings → Glasspane → Area Tags, then tag headings or files with them."
                 glasspane-area-tag-group)))))

;;;; Rendering — the drill

(defvar glasspane-areas--filter-state (make-hash-table :test #'equal)
  "Selected Area intersection per drill, keyed by the primary Area.
Each value is the list of selected member names with the primary first.")

(defun glasspane-areas--selected (category)
  "Return CATEGORY's selected intersection, primary first."
  (or (gethash category glasspane-areas--filter-state)
      (list category)))

(defun glasspane-areas--file-row (file &optional title subtitle)
  "Render FILE as a validated-path handoff to the one Files route.
TITLE and SUBTITLE override the basename and abbreviated path."
  (jetpacs-chrome-row
   (or title (file-name-nondirectory file))
   :subtitle (or subtitle (abbreviate-file-name file))
   :icon "description"
   :trailing (jetpacs-icon "chevron_right")
   :on-tap (glasspane-navigation-document-action file)
   :key (jetpacs-wire-id "area-file" file)))

(defun glasspane-areas--declaring-card (item)
  "Render the tokenized declaring-note ITEM as the Area's own note.
ITEM carries a durable heading token, so the card names identity only and
`heading.visit' chooses presentation."
  (jetpacs-chrome-row
   (or (alist-get 'headline item) "Area note")
   :subtitle (concat "Area note · "
                     (file-name-nondirectory (or (alist-get 'file item) "")))
   :icon "article"
   :trailing (jetpacs-icon "chevron_right")
   :on-tap (glasspane-navigation-heading-action (alist-get 'token item))
   :key (jetpacs-wire-id "area-note" (or (alist-get 'token item) ""))))

(defun glasspane-areas--declaration-rows (area tokenized-decls)
  "Render AREA's declaring notes: TOKENIZED-DECLS cards, then file rows.
Heading-level declarations arrive tokenized; file-level and index-only
declarations are path-authority rows."
  (append
   (mapcar #'glasspane-areas--declaring-card tokenized-decls)
   (delq nil
         (mapcar
          (lambda (decl)
            (unless (plist-get decl :item)
              (when-let* ((file (plist-get decl :file)))
                (glasspane-areas--file-row
                 file
                 (format "Open %s note" (plist-get decl :name))
                 (if (> (or (plist-get decl :level) 0) 0)
                     (concat (or (plist-get decl :headline) "")
                             " · " (file-name-nondirectory file))
                   (file-name-nondirectory file))))))
          (plist-get area :declares)))))

(defun glasspane-areas--chip-row (category selected)
  "Build the intersection chips for CATEGORY with SELECTED members first."
  (let ((names (cons category
                     (cl-remove category
                                (mapcar (lambda (area) (plist-get area :name))
                                        (glasspane-areas--index))
                                :test #'equal))))
    (apply #'jetpacs-flow-row
           (append
            (mapcar
             (lambda (name)
               (jetpacs-chip
                name
                :selected (jetpacs-bool (member name selected))
                :on-tap (jetpacs-action
                         "areas.filter"
                         :args (list :category category :area name))))
             names)
            (list :spacing 4 :run-spacing 4)))))

(defun glasspane-areas--item-in-all-p (item selected)
  "Return non-nil when ITEM's areas cover every name in SELECTED."
  (let ((areas (append (alist-get 'areas item) nil)))
    (cl-every (lambda (name) (member name areas)) selected)))

(defun glasspane-areas--files-in-all (selected)
  "Return the files every Area in SELECTED shares, path-sorted."
  (let ((files nil) (first t))
    (dolist (name selected)
      (let ((own (plist-get (glasspane-areas--find name) :files)))
        (setq files (if first own
                      (cl-remove-if-not (lambda (f) (member f own)) files))
              first nil)))
    (sort (copy-sequence files) #'string-lessp)))

(defun glasspane-areas--drill-body (category)
  "Render CATEGORY's intersection chips, note, Projects, Resources, Archives.
An Area that vanished between row render and tap degrades in place and
sweeps the prior Areas token generation."
  (let ((area (condition-case nil (glasspane-areas--find category)
                (error nil))))
    (if (null area)
        (progn
          (glasspane-agenda-tokenize nil "areas")
          (jetpacs-empty-state
           :icon "category"
           :title "Area no longer exists"
           :caption "Refresh Areas to see the current tag-group members."))
      (let* ((selected (glasspane-areas--selected category))
             (decl-items (delq nil (mapcar (lambda (decl)
                                             (plist-get decl :item))
                                           (plist-get area :declares))))
             (items (cl-remove-if-not
                     (lambda (item)
                       (glasspane-areas--item-in-all-p item selected))
                     (plist-get area :items)))
             (tokenized (glasspane-agenda-tokenize
                         (append decl-items items) "areas"))
             (decl-count (length decl-items))
             (decl-tokenized (seq-take tokenized decl-count))
             (project-items (seq-drop tokenized decl-count))
             (cards (mapcar (lambda (item)
                              (glasspane-detail-agenda-card
                               item (append (alist-get 'areas item) nil)))
                            project-items))
             (files (glasspane-areas--files-in-all selected))
             (file-rows (mapcar #'glasspane-areas--file-row files))
             (archive-rows (mapcar #'glasspane-resources--archive-row
                                   (glasspane-resources-archives-for-files
                                    files)))
             (note-rows (glasspane-areas--declaration-rows
                         area decl-tokenized)))
        (apply #'jetpacs-lazy-column
               (append
                (list (glasspane-areas--chip-row category selected))
                note-rows
                (list (jetpacs-section-header "Projects"))
                (or cards
                    (list (jetpacs-text "Nothing actionable here yet."
                                        :style "caption")))
                (list (jetpacs-divider)
                      (jetpacs-section-header "Resources"))
                (or file-rows
                    (list (jetpacs-text "No files carry this Area."
                                        :style "caption")))
                (list (jetpacs-divider)
                      (jetpacs-section-header "Archives"))
                (or archive-rows
                    (list (jetpacs-text "No archived siblings for these files."
                                        :style "caption")))
                (list :spacing 8 :content-padding 12)))))))

(defun glasspane-areas-screen (back)
  "Build the Areas list screen with BACK navigation."
  (jetpacs-chrome-screen "Areas" (glasspane-areas--list-body)
                         :back back
                         :actions (glasspane-ui-top-actions)
                         :fab (and glasspane-ui-legacy-ia
                                   (glasspane-ui-capture-fab))))

(defun glasspane-areas-drill-screen (category back)
  "Build CATEGORY's Area drill screen with BACK navigation."
  (jetpacs-chrome-screen category (glasspane-areas--drill-body category)
                         :back back
                         :actions (glasspane-ui-top-actions)
                         :fab (and glasspane-ui-legacy-ia
                                   (glasspane-ui-capture-fab))))

;;;; Actions and lifecycle

(defun glasspane-areas--on-open (_args params)
  "Open the Areas list in the one Tier-1 destination slot.
PARAMS is the originating action event."
  (glasspane-ui-open-destination
   "areas" "glasspane-areas" #'glasspane-areas-screen params))

(defun glasspane-areas--on-drill (args params)
  "Open ARGS' plain-string `:category', even if it just vanished.
The drill seeds its own intersection so a stale chip state never leaks
between visits.  PARAMS is the originating action event."
  (let ((category (plist-get args :category)))
    (if (not (and (stringp category) (not (string-empty-p category))))
        'rejected
      (puthash category (list category) glasspane-areas--filter-state)
      (glasspane-ui-open-destination
       "areas" (jetpacs-wire-id "area" category)
       (lambda (back) (glasspane-areas-drill-screen category back))
       params))))

(defun glasspane-areas--on-filter (args params)
  "Toggle ARGS' `:area' in the `:category' drill's intersection.
Tapping the primary Area resets to it alone; an unknown Area is rejected.
PARAMS carry the surface for the deferred refresh."
  (let ((category (plist-get args :category))
        (area (plist-get args :area)))
    (cond
     ((not (and (stringp category) (not (string-empty-p category))
                (stringp area) (not (string-empty-p area))))
      'rejected)
     ((not (glasspane-areas--find area)) 'rejected)
     (t
      (let ((selected (glasspane-areas--selected category)))
        (puthash category
                 (cond
                  ((equal area category) (list category))
                  ((member area selected)
                   (cl-remove area selected :test #'equal))
                  (t (append selected (list area))))
                 glasspane-areas--filter-state)
        (jetpacs-app-defer-refresh params)
        'accepted)))))

(defconst glasspane-areas--verbs '("areas.open" "areas.drill" "areas.filter")
  "The Areas verbs owned by this module.")

(defun glasspane-areas-register ()
  "Register the Areas verbs, idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "areas.open" #'glasspane-areas--on-open
                       :doc "Open the PARA Areas screen")
    (jetpacs-defaction "areas.drill" #'glasspane-areas--on-drill
                       :doc "Open one PARA Area by tag-group member"
                       :args '((:name category :type "text")))
    (jetpacs-defaction "areas.filter" #'glasspane-areas--on-filter
                       :doc "Toggle an Area in a drill's intersection"
                       :args '((:name category :type "text")
                               (:name area :type "text")))))

(defun glasspane-areas-unregister ()
  "Drop every verb owned by the Areas module."
  (dolist (name glasspane-areas--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-areas)
;;; glasspane-areas.el ends here
