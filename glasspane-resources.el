;;; glasspane-resources.el --- PARA Resources and Archive views -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Resources are the baseline PARA facet: every live file-level note,
;; including Areas.  The destination lists those indexed notes and delegates
;; actual browsing/editing to Jetpacs Files.  Archive lists Projects moved
;; under an in-file `* Archive :ARCHIVE:' subtree; sibling `_archive' files
;; are not a PARA bucket.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'glasspane-para)
(require 'glasspane-detail)
(require 'glasspane-ui)
(require 'glasspane-navigation)

(declare-function vulpea-note-id "ext:vulpea-note" (note))
(declare-function vulpea-note-path "ext:vulpea-note" (note))
(declare-function vulpea-note-tags "ext:vulpea-note" (note))
(declare-function vulpea-note-title "ext:vulpea-note" (note))

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

;;;; Resource list

(defun glasspane-resources-note-row (note key-prefix)
  "Render Resource NOTE as a native Files handoff using KEY-PREFIX."
  (let* ((path (vulpea-note-path note))
         (title (or (vulpea-note-title note)
                    (and path (file-name-nondirectory path))
                    "Untitled note"))
         (area (glasspane-para-area-p note))
         (tags (cl-remove glasspane-para-agenda-tag
                          (copy-sequence (vulpea-note-tags note))
                          :test #'equal))
         (kind (if area "Area + Resource" "Resource"))
         (subtitle (string-join
                    (delq nil
                          (list kind
                                (and tags (string-join tags " · "))
                                (and path (abbreviate-file-name path))))
                    "  ·  ")))
    (jetpacs-chrome-row
     title :subtitle subtitle
     :icon (if area "category" "description")
     :trailing (jetpacs-icon "chevron_right")
     :on-tap
     (glasspane-navigation-document-action path)
     :key (jetpacs-wire-id key-prefix
                           (or (vulpea-note-id note) path title)))))

(defun glasspane-resources--browse-row ()
  "Return the explicit full-vault browser row."
  (jetpacs-chrome-row
   "Browse vault"
   :subtitle "Open the complete folder tree in native Files"
   :icon "folder_open" :trailing (jetpacs-icon "chevron_right")
   :on-tap
   (jetpacs-shell-action-opening-surface
    "resources.browse" (glasspane-resources--files-surface))
   :key "resource-browse-vault"))

(defun glasspane-resources--body ()
  "Render indexed Resource notes plus the native browser escape hatch."
  (let ((notes (and (glasspane-para-ready-p)
                    (glasspane-para-resources))))
    (apply
     #'jetpacs-lazy-column
     (append
      (list (glasspane-resources--browse-row)
            (jetpacs-divider)
            (jetpacs-section-header "Notes"))
      (cond
       (notes
        (mapcar (lambda (note)
                  (glasspane-resources-note-row note "resource-note"))
                notes))
       ((not (glasspane-para-ready-p))
        (list
         (jetpacs-text
          "Vulpea is not ready; the native vault browser is still available."
          :style "caption")))
       (t
        (list (jetpacs-text "No live file-level notes are indexed."
                            :style "caption"))))
      (list :spacing 8 :content-padding 12)))))

(defun glasspane-resources-screen (back)
  "Build the Resource note destination screen."
  (jetpacs-chrome-screen
   "Resources" (glasspane-resources--body)
   :back back :actions (glasspane-ui-top-actions)
   :fab (and glasspane-ui-legacy-ia (glasspane-ui-capture-fab))))

;;;; Archive list

(defun glasspane-resources--archive-body ()
  "Render Projects archived under their Area notes."
  (let* ((items (glasspane-para-archive-items))
         (tokenized (glasspane-ui-tokenize-tap items "para-archive")))
    (if tokenized
        (apply #'jetpacs-lazy-column
               (append (mapcar #'glasspane-detail-result-card tokenized)
                       (list :spacing 8 :content-padding 12)))
      (jetpacs-empty-state
       :icon "archive"
       :title "Archive is empty"
       :caption "Archived Projects stay searchable inside their Area."))))

(defun glasspane-resources-archive-screen (back)
  "Build the Archive destination screen."
  (jetpacs-chrome-screen
   "Archive" (glasspane-resources--archive-body)
   :back back :actions (glasspane-ui-top-actions)
   :fab (and glasspane-ui-legacy-ia (glasspane-ui-capture-fab))))

;;;; Actions and cross-surface return

(defun glasspane-resources--on-open (_args params)
  "Open the indexed Resources destination on Glasspane's surface."
  (glasspane-ui-open-destination
   "resources" "glasspane-resources" #'glasspane-resources-screen params))

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
  "Complete the Resources browse handoff reported as SURFACE and VIEW."
  (when (and (not glasspane-ui-legacy-ia)
             (equal jetpacs-apps--current "glasspane")
             (equal surface (glasspane-resources--files-surface)))
    (when (and (equal view "browser")
               (equal jetpacs-apps--current-route "resources"))
      (glasspane-ui-open-destination
       "resources" "glasspane-resources" #'glasspane-resources-screen
       (list :surface (jetpacs-shell-surface-for "glasspane"))))))

(defun glasspane-resources--on-archive-open (_args params)
  "Open Archive in its drawer-only destination slot."
  (glasspane-ui-open-destination
   "archive" "glasspane-archive"
   #'glasspane-resources-archive-screen params))

(defun glasspane-resources--refresh-invalidate ()
  "Invalidate Resource and Archive projections on explicit refresh."
  (ebp-org-cache-invalidate 'glasspane))

(defconst glasspane-resources--verbs
  '("resources.open" "resources.browse" "resources.open-file"
    "resources.return" "archive.open")
  "The Resource and Archive actions owned by this module.")

(defun glasspane-resources-register ()
  "Register Resource and Archive actions idempotently."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "resources.open" #'glasspane-resources--on-open
                       :doc "Open live PARA Resource notes")
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
                       :doc "Open Projects archived inside their Areas"))
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
