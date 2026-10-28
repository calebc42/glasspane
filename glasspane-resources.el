;;; glasspane-resources.el --- PARA Resources route into Files, and Archive -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Resources are the PARA baseline: every live file in the vault.  The
;; destination is a Glasspane screen on the app's own surface: the Org files
;; in the canonical agenda scope, titled by `#+TITLE', tagged with their
;; Areas, filterable by Area, newest edits read in words.  A row opens its
;; document through the canonical route; "Browse in Files" still hands the
;; whole vault to Jetpacs Files, which owns the browser, file operations,
;; editing, and reader selection.  Every Files trip delegates through
;; `glasspane-navigation', the applet's one low-level Files boundary.
;;
;; Archive follows plain Org semantics: a bounded index of the sibling
;; `FILE.org_archive' files Org writes on `org-archive-subtree', filterable by
;; the Areas its source file belongs to (the non-exclusive Area tag group;
;; see glasspane-org.el).  No in-file `* Archive :ARCHIVE:' subtree is
;; required and no reverse operation exists.  Rows hand straight back to the
;; canonical document route.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'subr-x)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'glasspane-org)
(require 'glasspane-ui)
(require 'glasspane-navigation)

;;;; Resources delegation

(defconst glasspane-resources--browser-screen "files-resources"
  "Files guest screen used below the full-vault browser.")

(defun glasspane-resources--files-surface ()
  "Return the canonical Jetpacs Files surface."
  (glasspane-navigation-files-surface))

(defun glasspane-resources--browse-vault (path)
  "Open directory PATH in Files with Resources' browser adornments.
Directory browsing is not a document entry point, but it still crosses the
single low-level Files boundary owned by `glasspane-navigation'."
  (glasspane-navigation-open-files-path
   path
   :browser-id glasspane-resources--browser-screen
   :browser-fab (glasspane-ui-capture-fab)
   :return-action (glasspane-navigation-return-action)))

(defun glasspane-resources--on-browse (_args _params)
  "Open the whole Org vault through native Files."
  (glasspane-resources--browse-vault org-directory))

;;;; Archive index and screen

(defcustom glasspane-resources-archive-scan-cap 500
  "Maximum directory entries one Archive index build examines.
The walk stops at this ceiling instead of collecting the whole vault and
truncating afterward.  Pull-to-refresh invalidates the memoized result."
  :type 'integer :group 'jetpacs)

(defvar glasspane-resources--archive-filter nil
  "The Area whose archives the Archive screen shows, or nil for all.")

(defun glasspane-resources--archive-root ()
  "Return a local, existing `org-directory' root as a truename, or nil.
The walk records truenames so a sibling matches the truenamed `file' an
item carries even when `org-directory' is spelled through a symlink (the
tablet's /sdcard is one)."
  (when-let* ((configured (and (stringp org-directory) org-directory))
              (root (file-name-as-directory
                     (condition-case nil
                         (file-truename (expand-file-name configured))
                       (error (expand-file-name configured)))))
              ((condition-case nil (file-directory-p root) (error nil))))
    root))

(defun glasspane-resources--archive-files-1 ()
  "Build the uncached bounded Archive records below `org-directory'.
Each record is `(:path PATH :mtime TIME)'.  Hidden and symlinked
directories are not followed, one unreadable directory costs only itself,
and each matching file incurs exactly one explicit `file-attributes' call."
  (when-let* ((root (glasspane-resources--archive-root)))
    (ebp-org--with-clamped-io
      (let ((directories (list root))
            (seen 0)
            (cap (max 0 glasspane-resources-archive-scan-cap))
            archives)
        (while (and directories (< seen cap))
          (let ((entries
                 (condition-case nil
                     (directory-files (pop directories) t
                                      directory-files-no-dot-files-regexp
                                      t)
                   (file-error nil))))
            (setq entries (sort entries #'string-lessp))
            (while (and entries (< seen cap))
              (let ((entry (pop entries)))
                (cl-incf seen)
                (cond
                 ((condition-case nil (file-directory-p entry) (error nil))
                  (unless (or (file-symlink-p entry)
                              (string-prefix-p
                               "." (file-name-nondirectory entry)))
                    (push (file-name-as-directory entry) directories)))
                 ((string-suffix-p "_archive" entry t)
                  (when-let* ((attrs (ignore-errors (file-attributes entry)))
                              (mtime (file-attribute-modification-time attrs)))
                    (push (list :path entry :mtime mtime) archives))))))))
        (sort archives
              (lambda (a b)
                (string-lessp (plist-get a :path)
                              (plist-get b :path))))))))

(defun glasspane-resources--archive-files ()
  "Return the memoized bounded Archive records."
  (ebp-org-with-cache 'glasspane '(archive-files)
    (glasspane-resources--archive-files-1)))

(defun glasspane-resources--refresh-invalidate ()
  "Invalidate Archive membership before an explicit refresh push.
Archive files normally sit outside the agenda stamp carried by the shared
cache, so pull-to-refresh is their deliberate freshness boundary."
  (ebp-org-cache-invalidate))

(defun glasspane-resources--archive-source-path (path)
  "Return the source file PATH archives, removing Org's `_archive' suffix."
  (if (string-suffix-p "_archive" path t)
      (substring path 0 (- (length path) (length "_archive")))
    path))

(defun glasspane-resources--archive-source-name (path)
  "Return PATH's source filename, removing Org's `_archive' suffix."
  (file-name-nondirectory (glasspane-resources--archive-source-path path)))

(defun glasspane-resources-archives-for-files (files)
  "Return the Archive records that are exact `_archive' siblings of FILES."
  (let ((wanted (mapcar (lambda (file)
                          (concat (condition-case nil (file-truename file)
                                    (error file))
                                  "_archive"))
                        (delq nil (cl-remove-if-not #'stringp files)))))
    (when wanted
      (cl-remove-if-not
       (lambda (record) (member (plist-get record :path) wanted))
       (condition-case nil (glasspane-resources--archive-files)
         (error nil))))))

(defun glasspane-resources-file-areas (source)
  "Return the Areas Org file SOURCE belongs to, in declaration order.
Membership is read through the memoized tag-group index: the file's own
tags plus every member a heading carries.  An unreadable or vanished
SOURCE has no Areas."
  (when (and (stringp source)
             (condition-case nil (file-readable-p source) (error nil)))
    (when-let* ((index (glasspane-org-file-tag-group-index
                        source glasspane-area-tag-group)))
      (let ((used (copy-sequence (plist-get index :file-tags))))
        (dolist (entry (plist-get index :positions))
          (dolist (member (cdr entry))
            (cl-pushnew member used :test #'equal)))
        (cl-remove-if-not (lambda (member) (member member used))
                          (plist-get index :members))))))

(defun glasspane-resources--archive-areas (record)
  "Return the Areas RECORD's source file belongs to, in declaration order."
  (glasspane-resources-file-areas
   (glasspane-resources--archive-source-path (plist-get record :path))))

(defun glasspane-resources-archive-row (record)
  "Render one Archive RECORD as a handoff to the canonical document route."
  (let ((path (plist-get record :path))
        (mtime (plist-get record :mtime)))
    (jetpacs-chrome-row
     (glasspane-resources--archive-source-name path)
     :subtitle (or (glasspane-ui-age-words mtime) "Archived")
     :icon "archive"
     :on-tap (glasspane-navigation-document-action path)
     :key (jetpacs-opaque-id "archive-" path 16))))

(defun glasspane-resources--archive-filter-row (areas)
  "Build the Archive Area filter rail over AREAS, shared with Projects."
  (glasspane-ui-area-filter-rail areas glasspane-resources--archive-filter
                                 "archive.filter"))

(defun glasspane-resources--archive-body ()
  "Render the bounded Archive index, filtered by Area, or its empty state."
  (let* ((records
          (condition-case nil (glasspane-resources--archive-files)
            (error nil)))
         (tagged (mapcar (lambda (record)
                           (cons record
                                 (glasspane-resources--archive-areas record)))
                         records))
         (areas (sort (delete-dups (apply #'append (mapcar #'cdr tagged)))
                      #'string-lessp))
         (filter (and (member glasspane-resources--archive-filter areas)
                      glasspane-resources--archive-filter))
         (shown (if filter
                    (mapcar #'car
                            (cl-remove-if-not
                             (lambda (entry) (member filter (cdr entry)))
                             tagged))
                  records)))
    (if records
        (apply #'jetpacs-lazy-column
               (append (and areas
                            (list (glasspane-resources--archive-filter-row
                                   areas)))
                       (mapcar #'glasspane-resources-archive-row shown)
                       (list :spacing 8 :content-padding 12)))
      (jetpacs-empty-state
       :icon "archive"
       :title "Archive is empty"
       :caption
       "Archive a heading and Org writes its sibling _archive file."))))

(defun glasspane-resources-archive-screen (back)
  "Build the Archive screen with BACK navigation."
  (jetpacs-chrome-screen "Archive"
                         (glasspane-ui-measure
                          (glasspane-resources--archive-body))
                         :back back
                         :on-back (unless back (glasspane-ui-peer-on-back))
                         :on-refresh (glasspane-ui-refresh-action)
                         :actions (glasspane-ui-top-actions)))

(defun glasspane-resources--on-archive-open (_args params)
  "Open Archive in its drawer-only destination slot with dispatch PARAMS."
  (glasspane-ui-open-destination
   "archive" "glasspane-archive"
   #'glasspane-resources-archive-screen params))

(defun glasspane-resources--on-archive-filter (args params)
  "Select the Area named in ARGS for the Archive screen.
An absent or empty `:area' shows all (the shared rail sends none; older
renders sent \"\").  PARAMS carry the dispatch context for the deferred
refresh."
  (let ((area (plist-get args :area)))
    (cond
     ((not (or (null area) (stringp area))) 'rejected)
     ((or (null area) (string-empty-p area))
      (setq glasspane-resources--archive-filter nil)
      (jetpacs-app-defer-refresh params)
      'accepted)
     ((not (member area
                   (delete-dups
                    (apply #'append
                           (mapcar #'glasspane-resources--archive-areas
                                   (condition-case nil
                                       (glasspane-resources--archive-files)
                                     (error nil)))))))
      'rejected)
     (t
      (setq glasspane-resources--archive-filter area)
      (jetpacs-app-defer-refresh params)
      'accepted))))

;;;; Resources index and screen

(defconst glasspane-resources--screen-id "glasspane-resources"
  "The Resources destination's peer screen id.")

(defconst glasspane-resources--title-bytes 4096
  "How much of a file's head the title read examines.
`#+TITLE' is a preamble keyword; reading whole files for a list of the
vault would make every first paint proportional to the vault's size.")

(defvar glasspane-resources--filter nil
  "The Area whose files the Resources screen shows, or nil for all.")

(defun glasspane-resources--file-title-1 (path)
  "Read PATH's `#+TITLE', or its base name without extension."
  (or (condition-case nil
          (with-temp-buffer
            (insert-file-contents path nil 0 glasspane-resources--title-bytes)
            (goto-char (point-min))
            (let ((case-fold-search t))
              (when (re-search-forward
                     "^#\\+title:[ \t]*\\(.+?\\)[ \t]*$" nil t)
                (let ((title (string-trim (match-string 1))))
                  (and (not (string-empty-p title)) title)))))
        (error nil))
      (file-name-sans-extension (file-name-nondirectory path))))

(defun glasspane-resources--file-title (path)
  "Return PATH's display title, memoised under the shared Org stamp.
Resources are agenda-scope files, so an edit moves the stamp and busts
the memo; pull-to-refresh drops it outright."
  (ebp-org-with-cache 'glasspane (list 'resource-title path)
    (glasspane-resources--file-title-1 path)))

(defun glasspane-resources--index-1 ()
  "Build the uncached Resources records over the canonical Org scope.
Each record is `(:path PATH :title TITLE :areas AREAS :mtime TIME)`,
sorted by title.  One unreadable file costs only itself."
  (let (records)
    (dolist (file (delete-dups
                   (copy-sequence (or (jetpacs-org-mode-agenda-scope) nil))))
      (when-let* ((attrs (and (stringp file)
                              (condition-case nil (file-attributes file)
                                (error nil)))))
        (push (list :path file
                    :title (glasspane-resources--file-title file)
                    :areas (condition-case nil
                               (glasspane-resources-file-areas file)
                             (error nil))
                    :mtime (file-attribute-modification-time attrs))
              records)))
    (sort records
          (lambda (a b)
            (let ((ta (downcase (plist-get a :title)))
                  (tb (downcase (plist-get b :title))))
              (if (equal ta tb)
                  (string-lessp (plist-get a :path) (plist-get b :path))
                (string-lessp ta tb)))))))

(defun glasspane-resources--index ()
  "Return the memoised Resources records with current Org tag settings."
  (ebp-org-with-cache 'glasspane
      (list 'resources-index glasspane-area-tag-group
            (jetpacs-org-mode-tag-settings-stamp
             (jetpacs-org-mode-agenda-scope)))
    (glasspane-resources--index-1)))

(defun glasspane-resources--relative-dir (path)
  "PATH's directory relative to `org-directory', or nil at the top level."
  (when-let* ((root (and (stringp org-directory)
                         (file-name-as-directory
                          (expand-file-name org-directory))))
              (dir (file-name-directory (expand-file-name path))))
    (when (and (string-prefix-p root dir) (not (equal root dir)))
      (directory-file-name (substring dir (length root))))))

(defun glasspane-resources-row (record)
  "Render one Resources RECORD as a handoff to the canonical document route.
The title line is the file's title; beneath it, when it was edited, its
folder when nested, and its Areas.  A file in exactly one Area wears that
Area's icon."
  (let* ((path (plist-get record :path))
         (areas (plist-get record :areas))
         (parts (delq nil
                      (list (glasspane-ui-age-words (plist-get record :mtime))
                            (glasspane-resources--relative-dir path)
                            (and areas (string-join areas ", "))))))
    (jetpacs-chrome-row
     (plist-get record :title)
     :subtitle (and parts (string-join parts " · "))
     :icon (or (and (= (length areas) 1) (glasspane-area-icon (car areas)))
               "description")
     :on-tap (glasspane-navigation-document-action path)
     :key (jetpacs-opaque-id "resource-" path 16))))

(defun glasspane-resources--body ()
  "Render the Resources index, filtered by Area, or its empty state."
  (let* ((records (condition-case nil (glasspane-resources--index)
                    (error nil)))
         (areas (sort (delete-dups
                       (apply #'append
                              (mapcar (lambda (r) (copy-sequence
                                                   (plist-get r :areas)))
                                      records)))
                      #'string-lessp))
         (filter (and (member glasspane-resources--filter areas)
                      glasspane-resources--filter))
         (shown (if filter
                    (cl-remove-if-not
                     (lambda (r) (member filter (plist-get r :areas)))
                     records)
                  records)))
    (if records
        (apply #'jetpacs-lazy-column
               (append (and areas
                            (list (glasspane-ui-area-filter-rail
                                   areas filter "resources.filter")))
                       (mapcar #'glasspane-resources-row shown)
                       (list :spacing 8 :content-padding 12)))
      (jetpacs-empty-state
       :icon "topic"
       :title "No files yet"
       :caption "Org files in your agenda scope appear here."
       :action-label "Browse in Files"
       :on-tap (jetpacs-action "resources.browse")))))

(defun glasspane-resources--top-actions ()
  "Browse the vault in Files, then the shared Search."
  (cons (jetpacs-icon-button "folder_open" (jetpacs-action "resources.browse")
                             :content-description "Browse in Files")
        (glasspane-ui-top-actions)))

(defun glasspane-resources-screen (back)
  "Build the Resources screen with BACK navigation."
  (jetpacs-chrome-screen "Resources"
                         (glasspane-ui-measure (glasspane-resources--body))
                         :back back
                         :on-back (unless back (glasspane-ui-peer-on-back))
                         :on-refresh (glasspane-ui-refresh-action)
                         :actions (glasspane-resources--top-actions)))

(defun glasspane-resources--on-open (_args params)
  "Open Resources in its Tier-1 destination slot with dispatch PARAMS."
  (glasspane-ui-open-destination
   "resources" glasspane-resources--screen-id
   #'glasspane-resources-screen params))

(defun glasspane-resources--on-filter (args params)
  "Select the Area named in ARGS for the Resources screen; none shows all.
PARAMS carry the dispatch context for the deferred refresh."
  (let ((area (plist-get args :area)))
    (cond
     ((not (or (null area) (stringp area))) 'rejected)
     ((or (null area) (string-empty-p area))
      (setq glasspane-resources--filter nil)
      (jetpacs-app-defer-refresh params)
      'accepted)
     ((not (cl-some (lambda (r) (member area (plist-get r :areas)))
                    (condition-case nil (glasspane-resources--index)
                      (error nil))))
      'rejected)
     (t
      (setq glasspane-resources--filter area)
      (jetpacs-app-defer-refresh params)
      'accepted))))

;;;; Lifecycle

(defconst glasspane-resources--verbs
  '("resources.open" "resources.browse" "resources.filter"
    "archive.open" "archive.filter")
  "The Resource and Archive actions owned by this module.")

(defun glasspane-resources-register ()
  "Register Resource and Archive actions idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "resources.open" #'glasspane-resources--on-open
                       :doc "Open the PARA Resources screen")
    (jetpacs-defaction "resources.browse" #'glasspane-resources--on-browse
                       :doc "Browse the complete Org vault in Files")
    (jetpacs-defaction "resources.filter" #'glasspane-resources--on-filter
                       :doc "Filter the Resources screen by one Area tag"
                       :strict t
                       :args '((:name area :type "text")))
    (jetpacs-defaction "archive.open"
                       #'glasspane-resources--on-archive-open
                       :doc "Open the Org archive files, filterable by Area")
    (jetpacs-defaction "archive.filter"
                       #'glasspane-resources--on-archive-filter
                       :doc "Filter the Archive screen by one Area tag"
                       ;; Not required: the shared rail's "All" sends none.
                       :strict t
                       :args '((:name area :type "text")))
    (jetpacs-add-hook 'jetpacs-shell-refresh-hook
                      #'glasspane-resources--refresh-invalidate)))

(defun glasspane-resources-unregister ()
  "Drop every Resource/Archive action and hook."
  (dolist (name glasspane-resources--verbs)
    (jetpacs-undefaction name))
  (jetpacs-remove-hook 'jetpacs-shell-refresh-hook
                       #'glasspane-resources--refresh-invalidate))

(provide 'glasspane-resources)
;;; glasspane-resources.el ends here
