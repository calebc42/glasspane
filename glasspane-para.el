;;; glasspane-para.el --- PARA model and workflows for Glasspane -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Glasspane's presentation adapter for vulpea-para's PARA model.  The model
;; and mutations are adapted from https://github.com/d12frosted/vulpea-para
;; (GPL-3.0): roles are tags rather than folders, buckets are overlapping
;; facets, Resource is the live file-note baseline, Archive follows Org and
;; Vulpea's archive semantics, and agenda membership is derived from open
;; work.
;;
;; Unlike the desktop package, Glasspane must still load on a fresh phone
;; before its optional Vulpea engine has been installed.  This module therefore
;; declares the Vulpea API without requiring it.  Reads return no model rows
;; until `glasspane-packages' lights Vulpea up; file browsing and the rest of
;; Glasspane continue to work.  It never hardcodes a development checkout.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-archive)
(require 'org-element)
(require 'org-id)
(require 'org-refile)
(require 'seq)
(require 'subr-x)
(require 'ebp-org)
(require 'glasspane-org)

(defgroup glasspane-para nil
  "PARA workflows in Glasspane."
  :group 'jetpacs
  :prefix "glasspane-para-")

;;;; Optional Vulpea declarations

(declare-function vulpea-buffer-tags-get "ext:vulpea-buffer" (&optional local))
(declare-function vulpea-buffer-tags-add "ext:vulpea-buffer" (&rest tags))
(declare-function vulpea-buffer-tags-remove "ext:vulpea-buffer" (&rest tags))
(declare-function vulpea-create "ext:vulpea"
                  (title &optional file-name &rest args))
(declare-function vulpea-db-get-by-id "ext:vulpea-db-query" (id))
(declare-function vulpea-db-query "ext:vulpea-db-query" (&optional predicate))
(declare-function vulpea-db-query-by-file-paths "ext:vulpea-db-query"
                  (file-paths &optional level))
(declare-function vulpea-db-query-by-level "ext:vulpea-db-query" (level))
(declare-function vulpea-db-query-by-tags-some "ext:vulpea-db-query" (tags))
(declare-function vulpea-db-sync-tracked-file-p "ext:vulpea-db-sync" (path))
(declare-function vulpea-note-id "ext:vulpea-note" (note))
(declare-function vulpea-note-level "ext:vulpea-note" (note))
(declare-function vulpea-note-meta-get "ext:vulpea-note"
                  (note property &optional type))
(declare-function vulpea-note-path "ext:vulpea-note" (note))
(declare-function vulpea-note-pos "ext:vulpea-note" (note))
(declare-function vulpea-note-properties "ext:vulpea-note" (note))
(declare-function vulpea-note-tags "ext:vulpea-note" (note))
(declare-function vulpea-note-title "ext:vulpea-note" (note))
(declare-function vulpea-note-todo "ext:vulpea-note" (note))

;;;; The PARA vocabulary and predicates

(defcustom glasspane-para-area-tag "area"
  "Tag marking a file-level note as a PARA Area."
  :type 'string :group 'glasspane-para)

(defcustom glasspane-para-project-tag "project"
  "Tag marking a heading-level note as a PARA Project."
  :type 'string :group 'glasspane-para)

(defcustom glasspane-para-agenda-tag "agenda"
  "Derived file tag meaning that the note currently holds open work."
  :type 'string :group 'glasspane-para)

(defcustom glasspane-para-people-tag "people"
  "Tag marking person notes used by person-oriented workflows."
  :type 'string :group 'glasspane-para)

(defcustom glasspane-para-done-keywords '("DONE" "CANCELLED")
  "TODO keywords treated as complete by database-only checks."
  :type '(repeat string) :group 'glasspane-para)

(defun glasspane-para-ready-p ()
  "Return non-nil when the Vulpea read API needed by PARA is live."
  (and (featurep 'vulpea)
       (fboundp 'vulpea-db-query)
       (fboundp 'vulpea-db-query-by-level)
       (fboundp 'vulpea-db-query-by-tags-some)
       (fboundp 'vulpea-note-level)
       (fboundp 'vulpea-note-tags)))

(defun glasspane-para--note-tagged-p (note tag)
  "Return non-nil when NOTE carries TAG."
  (and (stringp tag) (member tag (vulpea-note-tags note))))

(defun glasspane-para-area-p (note)
  "Return non-nil when NOTE is a file-level Area note."
  (and (= (vulpea-note-level note) 0)
       (glasspane-para--note-tagged-p note glasspane-para-area-tag)))

(defun glasspane-para-project-p (note)
  "Return non-nil when NOTE is a heading-level Project note."
  (and (> (vulpea-note-level note) 0)
       (glasspane-para--note-tagged-p note glasspane-para-project-tag)))

(defun glasspane-para-archived-p (note)
  "Return non-nil when NOTE follows Org/Vulpea archive semantics."
  (let ((archive-tag (or (bound-and-true-p org-archive-tag) "ARCHIVE")))
    (or (and (assoc "ARCHIVE_TIME" (vulpea-note-properties note)) t)
        (and (member archive-tag (vulpea-note-tags note)) t))))

(defun glasspane-para-resource-p (note)
  "Return non-nil when NOTE is a live file-level Resource note.
Areas intentionally satisfy this predicate too: PARA buckets are facets."
  (and (= (vulpea-note-level note) 0)
       (not (glasspane-para-archived-p note))))

(defun glasspane-para-note-buckets (note)
  "Return NOTE's PARA facets in stable display order."
  (let (buckets)
    (when (glasspane-para-area-p note) (push 'area buckets))
    (when (glasspane-para-project-p note) (push 'project buckets))
    (when (glasspane-para-resource-p note) (push 'resource buckets))
    (when (glasspane-para-archived-p note) (push 'archive buckets))
    (nreverse buckets)))

;;;; Database-backed reads

(defun glasspane-para--sort-notes (notes)
  "Return NOTES sorted by title and then path."
  (sort notes
        (lambda (a b)
          (let ((at (or (vulpea-note-title a) ""))
                (bt (or (vulpea-note-title b) "")))
            (if (string-equal at bt)
                (string-lessp (or (vulpea-note-path a) "")
                              (or (vulpea-note-path b) ""))
              (string-lessp at bt))))))

(defun glasspane-para-areas ()
  "Return all Area notes, or nil while Vulpea is unavailable."
  (when (glasspane-para-ready-p)
    (condition-case nil
        (glasspane-para--sort-notes
         (seq-filter
          #'glasspane-para-area-p
          (vulpea-db-query-by-tags-some (list glasspane-para-area-tag))))
      (error nil))))

(defun glasspane-para-projects ()
  "Return all Project notes, or nil while Vulpea is unavailable."
  (when (glasspane-para-ready-p)
    (condition-case nil
        (glasspane-para--sort-notes
         (seq-filter
          #'glasspane-para-project-p
          (vulpea-db-query-by-tags-some (list glasspane-para-project-tag))))
      (error nil))))

(defun glasspane-para-resources ()
  "Return all live file-level Resource notes, Areas included."
  (when (glasspane-para-ready-p)
    (condition-case nil
        (glasspane-para--sort-notes
         (seq-filter #'glasspane-para-resource-p
                     (vulpea-db-query-by-level 0)))
      (error nil))))

(defun glasspane-para-area-of (note)
  "Return the Area containing NOTE, or nil for an orphan."
  (when (and (glasspane-para-ready-p) (vulpea-note-path note))
    (condition-case nil
        (when-let* ((file-note
                     (car (vulpea-db-query-by-file-paths
                           (list (vulpea-note-path note)) 0))))
          (and (glasspane-para-area-p file-note) file-note))
      (error nil))))

(defun glasspane-para-projects-in-area (area)
  "Return the Project headings living in AREA's file."
  (when (and (glasspane-para-ready-p) (glasspane-para-area-p area))
    (condition-case nil
        (glasspane-para--sort-notes
         (seq-filter
          #'glasspane-para-project-p
          (vulpea-db-query-by-file-paths (list (vulpea-note-path area)))))
      (error nil))))

(defun glasspane-para-note-item (note)
  "Convert Vulpea NOTE to the item alist shared by Glasspane cards."
  (glasspane-org--vulpea-note-to-item note))

(defun glasspane-para-note-by-id (id predicate)
  "Return ID's current note when it satisfies PREDICATE."
  (when (and (glasspane-para-ready-p) (stringp id)
             (not (string-empty-p id)) (fboundp 'vulpea-db-get-by-id))
    (condition-case nil
        (when-let* ((note (vulpea-db-get-by-id id)))
          (and (funcall predicate note) note))
      (error nil))))

;;;; Capture mutations

(defcustom glasspane-para-capture-area-file-name
  "area/${timestamp}-${slug}.org"
  "Vulpea file-name template used for a new Area."
  :type 'string :group 'glasspane-para)

(defcustom glasspane-para-capture-area-body
  "* Notes\n\n* Tasks\n\n* Archive :ARCHIVE:"
  "Body seeded into a new Area note."
  :type 'string :group 'glasspane-para)

(defun glasspane-para-category (area-title project-title)
  "Return the readable category for PROJECT-TITLE inside AREA-TITLE."
  (format "%s > %s" area-title project-title))

(defun glasspane-para--clean-title (title kind)
  "Validate and normalize TITLE, reporting KIND in user errors."
  (unless (stringp title)
    (user-error "%s title must be text" kind))
  (setq title (string-trim title))
  (when (string-empty-p title)
    (user-error "%s title cannot be empty" kind))
  (when (string-match-p "[\n\r]" title)
    (user-error "%s title must fit on one line" kind))
  title)

(defun glasspane-para--goto-tasks-end ()
  "Move point to the insertion point below the file's top-level Tasks."
  (goto-char (point-min))
  (if (re-search-forward "^\\* Tasks\\(?:[ \t]+:.*:\\)?[ \t]*$" nil t)
      (progn
        (org-back-to-heading t)
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n")))
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "* Tasks\n")))

(defun glasspane-para-capture-project (area title)
  "Create Project TITLE under AREA and return its new Org id."
  (unless (glasspane-para-area-p area)
    (user-error "Project target is not a PARA Area"))
  (setq title (glasspane-para--clean-title title "Project"))
  (let* ((file (ebp-org--check-file (vulpea-note-path area)))
         (id (org-id-new))
         (area-title (or (and (fboundp 'vulpea-note-meta-get)
                              (vulpea-note-meta-get area "short name"))
                         (vulpea-note-title area)
                         "Area"))
         (category (glasspane-para-category area-title title)))
    (with-current-buffer (find-file-noselect file t)
      (unless (derived-mode-p 'org-mode) (org-mode))
      (org-with-wide-buffer
       (save-excursion
         (glasspane-para--goto-tasks-end)
         (insert (format
                  "** TODO %s :%s:\n:PROPERTIES:\n:ID:       %s\n:CATEGORY: %s\n:END:\n"
                  title glasspane-para-project-tag id category))))
      (glasspane-org-save-and-invalidate (current-buffer)))
    (glasspane-org-vulpea-refresh-file file)
    id))

(defun glasspane-para-capture-area (title)
  "Create and return an Area note titled TITLE."
  (setq title (glasspane-para--clean-title title "Area"))
  (unless (and (glasspane-para-ready-p) (fboundp 'vulpea-create))
    (user-error "Vulpea is required to create an Area"))
  (let ((note (vulpea-create
               title glasspane-para-capture-area-file-name
               :tags (list glasspane-para-area-tag)
               :body glasspane-para-capture-area-body)))
    (glasspane-org-vulpea-refresh-file (vulpea-note-path note))
    (ebp-org-cache-invalidate 'glasspane)
    note))

;;;; Project archiving and Archive reads

(defcustom glasspane-para-archive-location "::* Archive"
  "Same-file location used when a Project is archived."
  :type 'string :group 'glasspane-para)

(defcustom glasspane-para-archive-file-cap 500
  "Maximum number of Resource files scanned for the Archive screen."
  :type 'integer :group 'glasspane-para)

(defun glasspane-para--archive-tag ()
  "Return Org's archive tag with its conventional fallback."
  (or (bound-and-true-p org-archive-tag) "ARCHIVE"))

(defun glasspane-para--ensure-archive-heading ()
  "Ensure the current Org buffer has a tagged top-level Archive heading."
  (org-with-wide-buffer
   (goto-char (point-min))
   (if (re-search-forward "^\\* Archive\\(?:[ \t]+:.*:\\)?[ \t]*$" nil t)
       (org-back-to-heading t)
     (goto-char (point-max))
     (unless (bolp) (insert "\n"))
     (insert "* Archive\n")
     (org-back-to-heading t))
   (let ((tag (glasspane-para--archive-tag))
         (tags (org-get-tags nil t)))
     (unless (member tag tags)
       (org-set-tags (cons tag tags))))))

(defun glasspane-para-archive-project-ref (ref)
  "Archive the Project at REF under its Area's Archive subtree."
  (let ((marker (ebp-org-resolve-ref ref)))
    (unwind-protect
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (org-back-to-heading t)
           (unless (member glasspane-para-project-tag (org-get-tags nil t))
             (user-error "That heading is no longer a PARA Project"))
           (let ((project-marker (copy-marker (point)))
                 (org-archive-location glasspane-para-archive-location)
                 (org-archive-subtree-save-file-p nil))
             (unwind-protect
                 (progn
                   (glasspane-para--ensure-archive-heading)
                   (goto-char project-marker)
                   (org-archive-subtree)
                   (glasspane-org-save-and-invalidate (current-buffer)))
               (set-marker project-marker nil)))))
      (set-marker marker nil))))

(defun glasspane-para--archive-item-at-p ()
  "Return non-nil when point is an archived Project heading."
  (let ((local-tags (org-get-tags nil t))
        (all-tags (org-get-tags)))
    (and (member glasspane-para-project-tag local-tags)
         (or (member (glasspane-para--archive-tag) all-tags)
             (org-entry-get nil "ARCHIVE_TIME")))))

(defun glasspane-para--archive-items-in-file (file)
  "Return archived Project items found in FILE."
  (condition-case nil
      (let ((true (ebp-org--check-file file)))
        (ebp-org--with-clamped-io
          (with-current-buffer (find-file-noselect true t)
            (unless (derived-mode-p 'org-mode) (org-mode))
            (org-with-wide-buffer
             (let (items)
               (org-map-entries
                (lambda ()
                  (when (glasspane-para--archive-item-at-p)
                    (push (cons '(archived . t)
                                (glasspane-org--heading-item-at))
                          items)))
                nil 'file)
               (nreverse items))))))
    (error nil)))

(defun glasspane-para--archive-source-files ()
  "Return the bounded set of files whose archived Projects can be scanned."
  (let ((files
         (if (glasspane-para-ready-p)
             (mapcar #'vulpea-note-path (glasspane-para-resources))
           (condition-case nil (glasspane-org-agenda-scope) (error nil)))))
    (seq-take (delete-dups (delq nil files))
              (max 0 glasspane-para-archive-file-cap))))

(defun glasspane-para-archive-items (&optional files)
  "Return archived Project card items from FILES or the Resource set."
  (let ((scope (or files (glasspane-para--archive-source-files))))
    (ebp-org-with-cache 'glasspane (list 'para-archives scope)
      (mapcan #'glasspane-para--archive-items-in-file scope))))

;;;; The self-updating derived agenda tag

(defcustom glasspane-para-open-work-tags '("REFILE")
  "Tags that count as open work independently of TODO state."
  :type '(repeat string) :group 'glasspane-para)

(defcustom glasspane-para-open-work-files nil
  "Files pinned to the agenda even when they contain no open TODO.
Entries may be bare names, absolute paths, or predicates of an absolute path."
  :type '(repeat (choice file function)) :group 'glasspane-para)

(defun glasspane-para--open-work-path-p (path)
  "Return non-nil when PATH matches `glasspane-para-open-work-files'."
  (when path
    (let ((absolute (expand-file-name path)))
      (seq-some
       (lambda (entry)
         (cond
          ((functionp entry) (funcall entry absolute))
          ((not (stringp entry)) nil)
          ((file-name-absolute-p entry)
           (string-equal (expand-file-name entry) absolute))
          (t (string-equal entry (file-name-nondirectory absolute)))))
       glasspane-para-open-work-files))))

(defun glasspane-para-buffer-open-work-p ()
  "Return non-nil when the current Org buffer holds open work."
  (or
   (glasspane-para--open-work-path-p (buffer-file-name))
   (org-element-map (org-element-parse-buffer 'headline) 'headline
     (lambda (heading)
       (let ((todo-type (org-element-property :todo-type heading)))
         (or
          (eq todo-type 'todo)
          (seq-intersection (org-element-property :tags heading)
                            glasspane-para-open-work-tags)
          (and
           (not (eq todo-type 'done))
           (org-element-property :contents-begin heading)
           (save-excursion
             (goto-char (org-element-property :contents-begin heading))
             (let ((end (save-excursion
                          (or (re-search-forward
                               org-element-headline-re
                               (org-element-property :contents-end heading) t)
                              (org-element-property :contents-end heading)))))
               (re-search-forward org-ts-regexp end t)))))))
     nil 'first-match)))

(defun glasspane-para-update-agenda-tag ()
  "Synchronize the current file's derived agenda tag with its open work."
  (when (and (derived-mode-p 'org-mode)
             (fboundp 'vulpea-buffer-tags-get)
             (fboundp 'vulpea-buffer-tags-add)
             (fboundp 'vulpea-buffer-tags-remove))
    (save-excursion
      (goto-char (point-min))
      (let* ((tags (vulpea-buffer-tags-get t))
             (tagged (and (member glasspane-para-agenda-tag tags) t))
             (has-work (and (glasspane-para-buffer-open-work-p) t)))
        (cond
         ((and has-work (not tagged))
          (vulpea-buffer-tags-add glasspane-para-agenda-tag))
         ((and (not has-work) tagged)
          (vulpea-buffer-tags-remove glasspane-para-agenda-tag)))))))

(defun glasspane-para-vault-buffer-p ()
  "Return non-nil when the current file belongs to the configured vault."
  (when-let* ((file (buffer-file-name)))
    (if (fboundp 'vulpea-db-sync-tracked-file-p)
        (vulpea-db-sync-tracked-file-p file)
      (ebp-org-file-allowed-p file))))

(defun glasspane-para--maybe-update-agenda-tag ()
  "Maintain the derived tag for a save inside the vault."
  (when (glasspane-para-vault-buffer-p)
    (glasspane-para-update-agenda-tag)))

(defun glasspane-para--install-buffer-hook ()
  "Install the file-local agenda updater in the current Org buffer."
  (add-hook 'before-save-hook #'glasspane-para--maybe-update-agenda-tag nil t))

(defun glasspane-para-agenda-files ()
  "Return distinct paths of file notes carrying the derived agenda tag."
  (when (glasspane-para-ready-p)
    (condition-case nil
        (seq-uniq
         (mapcar #'vulpea-note-path
                 (seq-filter
                  (lambda (note) (= 0 (vulpea-note-level note)))
                  (vulpea-db-query-by-tags-some
                   (list glasspane-para-agenda-tag)))))
      (error nil))))

(defun glasspane-para--note-open-p (note)
  "Return non-nil when NOTE is open work in a database-only check."
  (let ((todo (vulpea-note-todo note)))
    (and todo (not (member todo glasspane-para-done-keywords)))))

(defun glasspane-para-agenda-missing-files ()
  "Return open-work paths that have not acquired the derived agenda tag."
  (when (glasspane-para-ready-p)
    (condition-case nil
        (let ((tagged (make-hash-table :test #'equal))
              paths)
          (dolist (note (vulpea-db-query-by-tags-some
                         (list glasspane-para-agenda-tag)))
            (puthash (vulpea-note-path note) t tagged))
          (dolist (note
                   (vulpea-db-query
                    (lambda (candidate)
                      (or (glasspane-para--note-open-p candidate)
                          (seq-intersection (vulpea-note-tags candidate)
                                            glasspane-para-open-work-tags)))))
            (push (vulpea-note-path note) paths))
          (when glasspane-para-open-work-files
            (dolist (note (vulpea-db-query-by-level 0))
              (when (glasspane-para--open-work-path-p
                     (vulpea-note-path note))
                (push (vulpea-note-path note) paths))))
          (sort
           (seq-remove (lambda (path) (gethash path tagged))
                       (seq-uniq paths))
           #'string-lessp))
      (error nil))))

(defvar glasspane-para--warned-missing nil
  "Non-nil after this session has warned about untagged agenda files.")

(defun glasspane-para-effective-agenda-files (fallback)
  "Return derived agenda files, temporarily merged with FALLBACK on drift.
FALLBACK is a zero-argument function.  The merge keeps an existing vault
usable until `glasspane-para-agenda-backfill' has been run once."
  (if (not (glasspane-para-ready-p))
      (funcall fallback)
    (let ((tagged (glasspane-para-agenda-files))
          (missing (glasspane-para-agenda-missing-files)))
      (when (and missing (not glasspane-para--warned-missing))
        (setq glasspane-para--warned-missing t)
        (display-warning
         'glasspane-para
         (format "%d file%s with open work lack%s the derived agenda tag; run M-x glasspane-para-agenda-backfill"
                 (length missing) (if (= 1 (length missing)) "" "s")
                 (if (= 1 (length missing)) "s" ""))))
      (if missing
          (delete-dups (append tagged (funcall fallback)))
        tagged))))

;;;###autoload
(defun glasspane-para-agenda-backfill ()
  "Add the derived agenda tag to pre-existing files with open work."
  (interactive)
  (unless (glasspane-para-ready-p)
    (user-error "Vulpea is not available"))
  (let ((paths (glasspane-para-agenda-missing-files))
        (saved 0))
    (dolist (path paths)
      (let* ((existing (find-buffer-visiting path))
             (buffer (or existing (find-file-noselect path t))))
        (with-current-buffer buffer
          (let ((modified (buffer-modified-p)))
            (glasspane-para-update-agenda-tag)
            (when (and (buffer-modified-p) (not modified))
              (glasspane-org-save-and-invalidate buffer)
              (setq saved (1+ saved)))))
        (unless existing
          (kill-buffer buffer))))
    (setq glasspane-para--warned-missing nil)
    (message "glasspane-para: tagged %d of %d missing agenda file%s"
             saved (length paths) (if (= 1 (length paths)) "" "s"))
    saved))

;;;; Whole-vault refile targets

(defcustom glasspane-para-refile-files-filter nil
  "Predicate retaining file-level Resource notes as refile candidates."
  :type '(choice (const nil) function) :group 'glasspane-para)

(defun glasspane-para-refile--file-paths (notes)
  "Filter and order file-level NOTES with Areas first."
  (let ((live (seq-filter #'glasspane-para-resource-p notes)))
    (when glasspane-para-refile-files-filter
      (setq live (seq-filter glasspane-para-refile-files-filter live)))
    (seq-uniq
     (append
      (mapcar #'vulpea-note-path (seq-filter #'glasspane-para-area-p live))
      (mapcar #'vulpea-note-path live)))))

(defun glasspane-para-refile-files ()
  "Return every live note path, with Area files first."
  (when (glasspane-para-ready-p)
    (glasspane-para-refile--file-paths (vulpea-db-query-by-level 0))))

(defun glasspane-para-refile-verify-target ()
  "Return non-nil when point is outside an archived subtree."
  (if (member (glasspane-para--archive-tag) (org-get-tags))
      (progn (org-end-of-subtree t t) nil)
    t))

(defun glasspane-para-refile--spec-levels (spec)
  "Return SPEC's inclusive heading-level bounds, or nil."
  (when (and (listp spec) (listp (cdr spec)) (null (cddr spec)))
    (setq spec (cons (car spec) (cadr spec))))
  (pcase spec
    (`t (cons 1 most-positive-fixnum))
    (`(:maxlevel . ,(and (pred integerp) level)) (cons 1 level))
    (`(:level . ,(and (pred integerp) level)) (cons level level))))

(defun glasspane-para-refile--file-targets (path notes levels)
  "Build Org refile target rows for PATH from indexed NOTES and LEVELS."
  (let* ((style org-refile-use-outline-path)
         (file-note (seq-find (lambda (note)
                                (= 0 (vulpea-note-level note)))
                              notes))
         (base (pcase style
                 (`file (file-name-nondirectory path))
                 (`full-file-path path)
                 (`title (or (and file-note (vulpea-note-title file-note))
                             (file-name-nondirectory path)))
                 (`buffer-name
                  (if-let* ((buffer (find-buffer-visiting path)))
                      (buffer-name buffer)
                    (file-name-nondirectory path)))
                 (_ nil)))
         (headings
          (sort (seq-filter (lambda (note) (> (vulpea-note-level note) 0))
                            notes)
                (lambda (a b) (< (vulpea-note-pos a)
                                 (vulpea-note-pos b)))))
         stack targets)
    (when base (push (list base path nil nil) targets))
    (dolist (note headings)
      (let ((level (vulpea-note-level note)))
        (while (and stack (>= (caar stack) level)) (pop stack))
        (push (cons level (vulpea-note-title note)) stack)
        (when (and (<= (car levels) level) (<= level (cdr levels)))
          (let ((outline
                 (mapcar
                  (lambda (title)
                    (replace-regexp-in-string "/" "\\/" title nil t))
                  (reverse (mapcar #'cdr stack)))))
            (push
             (list (if style
                       (mapconcat #'identity
                                  (if base (cons base outline) outline) "/")
                     (vulpea-note-title note))
                   path org-outline-regexp (vulpea-note-pos note))
             targets)))))
    (nreverse targets)))

(defun glasspane-para-refile-target-table (&optional spec)
  "Build Org's refile target table from one Vulpea query."
  (let ((levels
         (or (glasspane-para-refile--spec-levels
              (or spec '(:maxlevel . 3)))
             (user-error "Unsupported refile spec: %S" spec)))
        (gc-cons-threshold most-positive-fixnum))
    (let ((notes (vulpea-db-query))
          (by-path (make-hash-table :test #'equal)))
      (dolist (note notes)
        (push note (gethash (vulpea-note-path note) by-path)))
      (mapcan
       (lambda (path)
         (glasspane-para-refile--file-targets
          path (gethash path by-path) levels))
       (glasspane-para-refile--file-paths
        (seq-filter (lambda (note) (= 0 (vulpea-note-level note))) notes))))))

(defun glasspane-para-refile--get-targets (original &rest args)
  "Use the Vulpea target table for Glasspane's exact refile spec."
  (let ((entry (and (null (cdr org-refile-targets))
                    (car-safe org-refile-targets))))
    (if (and (glasspane-para-ready-p)
             (consp entry)
             (eq (car entry) 'glasspane-para-refile-files)
             (glasspane-para-refile--spec-levels (cdr entry)))
        (glasspane-para-refile-target-table (cdr entry))
      (apply original args))))

(define-minor-mode glasspane-para-refile-mode
  "Answer Glasspane PARA refile target lists from Vulpea's database."
  :global t :group 'glasspane-para
  (if glasspane-para-refile-mode
      (advice-add 'org-refile-get-targets :around
                  #'glasspane-para-refile--get-targets)
    (advice-remove 'org-refile-get-targets
                   #'glasspane-para-refile--get-targets)))

;;;; Diagnostics and lifecycle

(defun glasspane-para-doctor-orphan-projects ()
  "Return Projects whose file-level note is not an Area."
  (seq-remove #'glasspane-para-area-of (glasspane-para-projects)))

(defun glasspane-para-doctor-stale-agenda-files ()
  "Return agenda-tagged paths with no database-visible open work."
  (when (glasspane-para-ready-p)
    (let ((open-paths (make-hash-table :test #'equal)))
      (dolist (note (vulpea-db-query #'glasspane-para--note-open-p))
        (puthash (vulpea-note-path note) t open-paths))
      (seq-remove
       (lambda (path)
         (or (gethash path open-paths)
             (glasspane-para--open-work-path-p path)))
       (glasspane-para-agenda-files)))))

;;;###autoload
(defun glasspane-para-doctor ()
  "Report orphan Projects and stale agenda tags in a desktop buffer."
  (interactive)
  (unless (glasspane-para-ready-p)
    (user-error "Vulpea is not available"))
  (let ((orphans (glasspane-para-doctor-orphan-projects))
        (stale (glasspane-para-doctor-stale-agenda-files)))
    (with-current-buffer (get-buffer-create "*glasspane-para-doctor*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Glasspane PARA doctor\n=====================\n\n")
        (insert (format "Projects outside an Area: %d\n" (length orphans)))
        (dolist (project orphans)
          (insert (format "  - %s (%s)\n"
                          (vulpea-note-title project)
                          (vulpea-note-path project))))
        (insert (format "\nStale agenda tags: %d\n" (length stale)))
        (dolist (path stale) (insert (format "  - %s\n" path)))
        (when (and (null orphans) (null stale))
          (insert "\nAll good. Nothing to fix.\n")))
      (special-mode)
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

(defun glasspane-para-install-hooks ()
  "Enable PARA's save-time agenda and database-backed refile hooks."
  (add-hook 'org-mode-hook #'glasspane-para--install-buffer-hook)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (derived-mode-p 'org-mode)
        (glasspane-para--install-buffer-hook))))
  (glasspane-para-refile-mode 1))

(defun glasspane-para-remove-hooks ()
  "Remove everything installed by `glasspane-para-install-hooks'."
  (remove-hook 'org-mode-hook #'glasspane-para--install-buffer-hook)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (remove-hook 'before-save-hook
                   #'glasspane-para--maybe-update-agenda-tag t)))
  (glasspane-para-refile-mode -1))

(provide 'glasspane-para)
;;; glasspane-para.el ends here
