;;; glasspane-resources.el --- PARA Resources route into Files -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; PA-2b/2c of docs/PLAN-glasspane-para.md.  Resources is a Glasspane name
;; and starting-scope opinion over Jetpacs' native Files app.  It owns no
;; browser, screen, file walk, or path policy: both Resources verbs delegate
;; directly to the public Files opener on the canonical Files surface.
;; Archive is the app-side exception: an opinionated, bounded index of Org's
;; sibling archive files and one screen whose rows hand straight back to the
;; same native Files route.  Both destinations stay staged until PA-3.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'subr-x)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-files)
(require 'glasspane-ui)

;;;; Resources delegation

(defun glasspane-resources--files-surface ()
  "Return the canonical Jetpacs Files surface."
  (jetpacs-shell-surface-for jetpacs-files-owner))

(defun glasspane-resources--open-path (path)
  "Open PATH through Jetpacs Files and return its action status.
Files owns containment validation, browsing, document hosting, and every
resulting operation; this downstream wrapper deliberately adds no policy."
  (jetpacs-files-open-path path (glasspane-resources--files-surface)))

(defun glasspane-resources--on-open (_args _params)
  "Open `org-directory' as the PARA Resources landing scope."
  (glasspane-resources--open-path org-directory))

(defun glasspane-resources--on-open-file (args _params)
  "Open ARGS' `:path' through the same native Files route."
  (glasspane-resources--open-path (plist-get args :path)))

;;;; Archive index and screen

(defcustom glasspane-resources-archive-scan-cap 500
  "Maximum directory entries one Archive index build examines.
The walk stops at this ceiling instead of collecting the whole vault and
truncating afterward.  Pull-to-refresh invalidates the memoized result."
  :type 'integer :group 'jetpacs)

(defun glasspane-resources--archive-root ()
  "Return a local, existing `org-directory' root, or nil."
  (when-let* ((configured (car (ebp-local-paths (list org-directory))))
              (root (file-name-as-directory (expand-file-name configured)))
              ((condition-case nil (file-directory-p root) (error nil))))
    root))

(defun glasspane-resources--archive-files-1 ()
  "Build the uncached bounded Archive records below `org-directory'.
Each record is `(:path PATH :mtime TIME)'.  Symlinked directories are not
followed, one unreadable directory costs only itself, and each matching
file incurs exactly one explicit `file-attributes' call."
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
                                      directory-files-no-dot-files-regexp)
                   (file-error nil))))
            (while (and entries (< seen cap))
              (let ((entry (pop entries)))
                (cl-incf seen)
                (cond
                 ((condition-case nil (file-directory-p entry) (error nil))
                  (unless (file-symlink-p entry)
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

(defun glasspane-resources--archive-source-name (path)
  "Return PATH's source filename, removing Org's `_archive' suffix."
  (let ((name (file-name-nondirectory path)))
    (if (string-suffix-p "_archive" name t)
        (substring name 0 (- (length name) (length "_archive")))
      name)))

(defun glasspane-resources--archive-row (record)
  "Render one Archive RECORD as a handoff to native Files."
  (let ((path (plist-get record :path))
        (mtime (plist-get record :mtime)))
    (jetpacs-chrome-row
     (glasspane-resources--archive-source-name path)
     :subtitle (format "Modified %s"
                       (format-time-string "%Y-%m-%d %H:%M" mtime))
     :icon "archive"
     :trailing (jetpacs-icon "chevron_right")
     :on-tap (jetpacs-action "resources.open-file" :args (list :path path))
     :key (jetpacs-wire-id "archive-file" path))))

(defun glasspane-resources--archive-body ()
  "Render the bounded Archive index or its empty state."
  (let ((records
         (condition-case nil (glasspane-resources--archive-files)
           (error nil))))
    (if records
        (apply #'jetpacs-lazy-column
               (append (mapcar #'glasspane-resources--archive-row records)
                       (list :spacing 8 :content-padding 12)))
      (jetpacs-empty-state
       :icon "archive"
       :title "Archive is empty"
       :caption "No Org archive files were found in the vault."))))

(defun glasspane-resources-archive-screen (back)
  "Build the staged Archive screen with BACK navigation."
  (jetpacs-chrome-screen "Archive" (glasspane-resources--archive-body)
                         :back back :fab (glasspane-ui-capture-fab)))

(defun glasspane-resources--on-archive-open (_args params)
  "Push the staged Archive screen onto the tapped surface."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       (condition-case err
           (jetpacs-chrome-push-screen
            surface "glasspane-archive" #'glasspane-resources-archive-screen)
         (error (message "glasspane: archive push failed: %s"
                         (jetpacs-error-label err))))))
    'accepted))

(defconst glasspane-resources--verbs
  '("resources.open" "resources.open-file" "archive.open")
  "The staged Resources and Archive verbs owned by this module.")

(defun glasspane-resources-register ()
  "Register the staged Resources delegation verbs, idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "resources.open" #'glasspane-resources--on-open
                       :doc "Open the Org vault in native Jetpacs Files")
    (jetpacs-defaction
     "resources.open-file" #'glasspane-resources--on-open-file
     :doc "Open one path in native Jetpacs Files"
     :args '((:name path :type "text" :required t)))
    (jetpacs-defaction "archive.open" #'glasspane-resources--on-archive-open
                       :doc "Open the PARA Archive index"))
  (add-hook 'jetpacs-shell-refresh-hook
            #'glasspane-resources--refresh-invalidate))

(defun glasspane-resources-unregister ()
  "Drop every verb owned by the Resources module."
  (dolist (name glasspane-resources--verbs)
    (jetpacs-undefaction name))
  (remove-hook 'jetpacs-shell-refresh-hook
               #'glasspane-resources--refresh-invalidate))

(provide 'glasspane-resources)
;;; glasspane-resources.el ends here
