;;; glasspane-resources.el --- PARA Resources route into Files, and Archive -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Resources are the PARA baseline: every live file in the vault.  Glasspane
;; owns only the name, the landing scope (`org-directory'), and the selected
;; route; Jetpacs Files owns the browser, listing, search, file operations,
;; editing, and reader selection.  Both Resources verbs therefore delegate
;; through `glasspane-navigation', the applet's one low-level Files boundary.
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

(declare-function glasspane-agenda-screen "glasspane-agenda" (back))

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
   :browser-fab (and (not glasspane-ui-legacy-ia)
                     (glasspane-ui-capture-fab))
   :return-action (glasspane-navigation-return-action)))

(defun glasspane-resources--on-open (_args _params)
  "Open `org-directory' in Files as the PARA Resources landing scope."
  (let ((status (glasspane-resources--browse-vault org-directory)))
    ;; `app.open' records the route before redispatching the destination
    ;; verb, but direct/M-x entry reaches the owner verb without it.
    (when (and (eq status 'accepted) (not glasspane-ui-legacy-ia))
      (jetpacs-apps-note-route "glasspane" "resources"))
    status))

(defun glasspane-resources--on-browse (_args _params)
  "Open the whole Org vault through native Files."
  (glasspane-resources--browse-vault org-directory))

(defun glasspane-resources--on-open-file (args _params)
  "Open the path in cached `resources.open-file' ARGS canonically."
  (glasspane-navigation-open-document (plist-get args :path)))

(defun glasspane-resources--on-return (args params)
  "Delegate cached `resources.return' ARGS and PARAMS canonically."
  (glasspane-navigation-return args params))

(defun glasspane-resources--on-view-change (surface view)
  "Complete a Companion-local Back handoff reported as SURFACE and VIEW.
Back from the Resources browser reaches Files' native root; that
destination-level Back resets the cross-surface destination to the Agenda
root exactly once, as the PA-3 contract requires.  Back from a direct
document is `glasspane-navigation''s alone (NAVIGATION.org): its observer
re-presents Glasspane's untouched stack, so this handler never touches the
files-return view."
  (when (and (not glasspane-ui-legacy-ia)
             (equal jetpacs-apps--current "glasspane")
             (equal surface (glasspane-resources--files-surface)))
    (cond
     ((and (equal view "browser")
           (equal jetpacs-apps--current-route "resources"))
      (glasspane-ui-open-destination
       "agenda" "glasspane-agenda" #'glasspane-agenda-screen
       (list :surface (jetpacs-shell-surface-for "glasspane")))))))

;;;; Archive index and screen

(defcustom glasspane-resources-archive-scan-cap 500
  "Maximum directory entries one Archive index build examines.
The walk stops at this ceiling instead of collecting the whole vault and
truncating afterward.  Pull-to-refresh invalidates the memoized result."
  :type 'integer :group 'jetpacs)

(defvar glasspane-resources--archive-filter nil
  "The Area whose archives the Archive screen shows, or nil for all.")

(defun glasspane-resources--archive-root ()
  "Return a local, existing `org-directory' root, or nil."
  (when-let* ((configured (and (stringp org-directory) org-directory))
              (root (file-name-as-directory (expand-file-name configured)))
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
  (ebp-org-cache-invalidate 'glasspane))

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
  (let ((wanted (mapcar (lambda (file) (concat file "_archive"))
                        (delq nil (cl-remove-if-not #'stringp files)))))
    (when wanted
      (cl-remove-if-not
       (lambda (record) (member (plist-get record :path) wanted))
       (condition-case nil (glasspane-resources--archive-files)
         (error nil))))))

(defun glasspane-resources--archive-areas (record)
  "Return the Areas RECORD's source file belongs to, in declaration order.
Membership is read from the live source file through the memoized tag-group
index; a source that no longer exists has no Areas."
  (let ((source (glasspane-resources--archive-source-path
                 (plist-get record :path))))
    (when (and (stringp source)
               (condition-case nil (file-readable-p source) (error nil)))
      ;; PM-6 lifts the 2026-08-27 obsolescence marker from the group
      ;; variable; until then the reference compiles without the warning.
      (when-let* ((index (glasspane-org--file-tag-group-index
                          source glasspane-area-tag-group)))
        (let ((used (copy-sequence (plist-get index :file-tags))))
          (dolist (entry (plist-get index :positions))
            (dolist (member (cdr entry))
              (cl-pushnew member used :test #'equal)))
          (cl-remove-if-not (lambda (member) (member member used))
                            (plist-get index :members)))))))

(defun glasspane-resources--archive-row (record)
  "Render one Archive RECORD as a handoff to the canonical document route."
  (let ((path (plist-get record :path))
        (mtime (plist-get record :mtime)))
    (jetpacs-chrome-row
     (glasspane-resources--archive-source-name path)
     :subtitle (format "Modified %s"
                       (format-time-string "%Y-%m-%d %H:%M" mtime))
     :icon "archive"
     :trailing (jetpacs-icon "chevron_right")
     :on-tap (glasspane-navigation-document-action path)
     :key (jetpacs-wire-id "archive" path))))

(defun glasspane-resources--archive-filter-row (areas)
  "Build the Archive Area filter chips over AREAS."
  (apply
   #'jetpacs-flow-row
   (append
    (mapcar
     (lambda (area)
       (let ((selected (if (equal area "All")
                           (null glasspane-resources--archive-filter)
                         (equal glasspane-resources--archive-filter area))))
         (jetpacs-chip
          area
          :selected (jetpacs-bool selected)
          :on-tap (jetpacs-action "archive.filter"
                                  :args (list :area (if (equal area "All")
                                                        ""
                                                      area))))))
     (cons "All" areas))
    (list :spacing 4 :run-spacing 4))))

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
                       (mapcar #'glasspane-resources--archive-row shown)
                       (list :spacing 8 :content-padding 12)))
      (jetpacs-empty-state
       :icon "archive"
       :title "Archive is empty"
       :caption
       "Archive a heading and Org writes its sibling _archive file."))))

(defun glasspane-resources-archive-screen (back)
  "Build the Archive screen with BACK navigation."
  (jetpacs-chrome-screen "Archive" (glasspane-resources--archive-body)
                         :back back
                         :actions (glasspane-ui-top-actions)
                         :fab (and glasspane-ui-legacy-ia
                                   (glasspane-ui-capture-fab))))

(defun glasspane-resources--on-archive-open (_args params)
  "Open Archive in its drawer-only destination slot with dispatch PARAMS."
  (glasspane-ui-open-destination
   "archive" "glasspane-archive"
   #'glasspane-resources-archive-screen params))

(defun glasspane-resources--on-archive-filter (args params)
  "Select the Area named in ARGS for the Archive screen; \"\" shows all.
PARAMS carry the dispatch context for the deferred refresh."
  (let ((area (plist-get args :area)))
    (cond
     ((not (stringp area)) 'rejected)
     ((string-empty-p area)
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

;;;; Lifecycle

(defconst glasspane-resources--verbs
  '("resources.open" "resources.browse" "resources.open-file"
    "resources.return" "archive.open" "archive.filter")
  "The Resource and Archive actions owned by this module.")

(defun glasspane-resources-register ()
  "Register Resource and Archive actions idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "resources.open" #'glasspane-resources--on-open
                       :doc "Open the Org vault in native Jetpacs Files")
    (jetpacs-defaction "resources.browse" #'glasspane-resources--on-browse
                       :doc "Browse the complete Org vault in Files")
    (jetpacs-defaction
     "resources.open-file" #'glasspane-resources--on-open-file
     :doc "Compatibility alias for cached Resource document opens"
     :args '((:name path :type "text" :required t)))
    (jetpacs-defaction "resources.return" #'glasspane-resources--on-return
                       :doc "Compatibility alias for cached Files returns")
    (jetpacs-defaction "archive.open"
                       #'glasspane-resources--on-archive-open
                       :doc "Open the Org archive files, filterable by Area")
    (jetpacs-defaction "archive.filter"
                       #'glasspane-resources--on-archive-filter
                       :doc "Filter the Archive screen by one Area tag"
                       :args '((:name area :type "text" :required t))))
  (add-hook 'jetpacs-shell-refresh-hook
            #'glasspane-resources--refresh-invalidate)
  (remove-hook 'jetpacs-shell-view-change-functions
               #'glasspane-resources--on-view-change)
  (unless glasspane-ui-legacy-ia
    (add-hook 'jetpacs-shell-view-change-functions
              #'glasspane-resources--on-view-change)))

(defun glasspane-resources-unregister ()
  "Drop every Resource/Archive action and hook."
  (dolist (name glasspane-resources--verbs)
    (jetpacs-undefaction name))
  (remove-hook 'jetpacs-shell-refresh-hook
               #'glasspane-resources--refresh-invalidate)
  (remove-hook 'jetpacs-shell-view-change-functions
               #'glasspane-resources--on-view-change))

(provide 'glasspane-resources)
;;; glasspane-resources.el ends here
