;;; jetpacs-package-browser.el --- Package browser skin (parity P3) -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; The stock tablist skin, and the worked example of the pattern:
;; package-menu-mode derives from tabulated-list-mode, so the generic
;; walk in jetpacs-tablist.el is reused; this file registers the three
;; skin hooks (header, row, filter) plus curated actions.  It ships in
;; the core because package management, like Settings, is chrome every
;; app's user needs.  (Behavior reference: POC 1's browser; the actions
;; are rebuilt for the D2 dispatch contract — slow package operations
;; defer through `jetpacs-flow-continue' and report by toast, and every
;; handler returns a status without blocking.)
;;
;; Entry: `M-x list-packages' from the palette renders through the skin
;; like any tabulated-list buffer, or the `packages.show' action.  The
;; wire stays semantic: actions validate package names against the
;; archive/installed lists — nothing on the wire names arbitrary code.

;;; Code:

(require 'cl-lib)
(require 'package)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-tablist)
(require 'jetpacs-chrome)

;; Soft-coupled entry card; the browser works without the settings module.
(declare-function jetpacs-settings-add-link "jetpacs-settings" (order builder))

(defvar jetpacs-pkg--search ""
  "Current package search string (matches name and summary).")

(defvar jetpacs-pkg--status "all"
  "Current package status filter chip.")

(defconst jetpacs-pkg--statuses
  '(("all")
    ("installed" "installed" "dependency" "unsigned" "external" "held")
    ("available" "available" "new")
    ("built-in" "built-in")
    ("upgradable" "obsolete"))
  "Chip name -> package-menu status strings it admits.")

;;;; Skin hooks

(defun jetpacs-pkg--filter (id entry)
  "Keep package row (ID ENTRY) when it matches the search and status chips."
  (let ((statuses (cdr (assoc jetpacs-pkg--status jetpacs-pkg--statuses)))
        (status (or (jetpacs-tablist-entry-col entry "Status") ""))
        (hay (concat (jetpacs-tablist-col-string (aref entry 0)) " "
                     (and (package-desc-p id)
                          (or (package-desc-summary id) "")))))
    (and (or (null statuses) (member status statuses))
         (or (string-empty-p jetpacs-pkg--search)
             (string-match-p (regexp-quote jetpacs-pkg--search)
                             (downcase hay))))))

(defun jetpacs-pkg--header (_buf)
  (list
   (jetpacs-text-input "pkg-search"
                       :value jetpacs-pkg--search
                       :label "Search packages" :single-line t
                       :on-submit (jetpacs-action "packages.search"))
   (apply #'jetpacs-flow-row
          (mapcar (lambda (chip)
                    (let ((s (car chip)))
                      (jetpacs-chip (capitalize s)
                                    :selected (equal jetpacs-pkg--status s)
                                    :on-tap (jetpacs-action
                                             "packages.status-filter"
                                             :args `(:status ,s)
                                             :when-offline "drop"))))
                  jetpacs-pkg--statuses))
   (jetpacs-row
    (jetpacs-button "Refresh archives"
                    (jetpacs-action "packages.refresh-archives"
                                    :when-offline "drop")
                    :variant "text")
    (jetpacs-with-attrs (jetpacs-spacer) :weight 1)
    (when (fboundp 'package-upgrade-all)
      (jetpacs-button "Upgrade all"
                      (jetpacs-action "packages.upgrade-all"
                                      :when-offline "drop")
                      :variant "text")))))

(defun jetpacs-pkg--row (id entry _pos)
  (when (package-desc-p id)
    (let* ((sym (package-desc-name id))
           (name (symbol-name sym))
           (version (or (jetpacs-tablist-entry-col entry "Version") ""))
           (status (or (jetpacs-tablist-entry-col entry "Status") ""))
           (summary (or (package-desc-summary id) ""))
           (installed (assq sym package-alist)))
      (jetpacs-card
       (jetpacs-row
        (jetpacs-with-attrs
         (jetpacs-column
          (jetpacs-row (jetpacs-text name :style "label")
                       (jetpacs-text version :style "caption")
                       (jetpacs-text status :style "caption"))
          (jetpacs-text summary :style "caption"))
         :weight 1)
        (cond
         (installed
          (jetpacs-icon-button "delete"
                               (jetpacs-action "packages.delete"
                                               :args `(:package ,name)
                                               :when-offline "drop")
                               :content-description
                               (format "Uninstall %s" name)))
         ((not (equal status "built-in"))
          (jetpacs-icon-button "download"
                               (jetpacs-action "packages.install"
                                               :args `(:package ,name)
                                               :when-offline "drop")
                               :content-description
                               (format "Install %s" name)))))
       :on-tap (jetpacs-action "packages.describe"
                               :args `(:package ,name)
                               :when-offline "drop")))))

(setf (alist-get 'package-menu-mode jetpacs-tablist-header-functions)
      #'jetpacs-pkg--header)
(setf (alist-get 'package-menu-mode jetpacs-tablist-row-functions)
      #'jetpacs-pkg--row)
(setf (alist-get 'package-menu-mode jetpacs-tablist-filter-functions)
      #'jetpacs-pkg--filter)

;;;; Actions

(defun jetpacs-pkg--buffer ()
  "The live *Packages* menu buffer, creating (without fetching) if needed."
  (unless package--initialized (package-initialize))
  (or (get-buffer "*Packages*")
      (save-window-excursion
        (list-packages t)
        (get-buffer "*Packages*"))))

(defun jetpacs-pkg--revert-and-refresh (params)
  "Re-generate the package menu after a package operation and re-push."
  (let ((buf (get-buffer "*Packages*")))
    (when buf
      (with-current-buffer buf
        ;; noconfirm: a prompting revert would block, and this runs in a
        ;; deferred continuation where a dialog could otherwise appear.
        (ignore-errors (revert-buffer nil t)))))
  (jetpacs-tablist--refresh-view params))

(defun jetpacs-pkg--action-show (_args _params)
  (let ((buf (jetpacs-pkg--buffer)))
    (cond
     ((null buf) 'rejected)
     ((null jetpacs-tablist-view-buffer-function) 'rejected)
     (t
      (when (null package-archive-contents)
        (jetpacs-toast "Archives not fetched yet - tap Refresh archives"))
      (funcall jetpacs-tablist-view-buffer-function (buffer-name buf))
      'accepted))))

(defun jetpacs-pkg--action-search (args params)
  (let ((q (plist-get args :value)))
    (setq jetpacs-pkg--search (downcase (or (and (stringp q) q) "")))
    (jetpacs-tablist--refresh-view params)
    'accepted))

(defun jetpacs-pkg--action-status-filter (args params)
  (let ((s (plist-get args :status)))
    (if (not (assoc s jetpacs-pkg--statuses))
        'rejected
      (setq jetpacs-pkg--status s)
      (jetpacs-tablist--refresh-view params)
      'accepted)))

(defmacro jetpacs-pkg--deferred (params progress &rest body)
  "Toast PROGRESS, run BODY in a continuation, revert + re-push after.
The dispatch extent returns immediately (D2); BODY toasts its own
outcome."
  (declare (indent 2))
  `(progn
     (jetpacs-toast ,progress)
     (jetpacs-flow-continue
      (lambda ()
        ,@body
        (jetpacs-pkg--revert-and-refresh ,params)))
     'accepted))

(defun jetpacs-pkg--action-install (args params)
  (let* ((name (plist-get args :package))
         (sym (and (stringp name) (intern-soft name))))
    (if (not (and sym (assq sym package-archive-contents)))
        'rejected
      (jetpacs-pkg--deferred params (format "Installing %s..." name)
        (condition-case err
            (progn (package-install sym)
                   (jetpacs-toast (format "Installed %s" name)))
          (error (jetpacs-toast
                  (format "Install failed: %s"
                          (error-message-string err)))))))))

(defun jetpacs-pkg--action-delete (args params)
  (let* ((name (plist-get args :package))
         (sym (and (stringp name) (intern-soft name)))
         (desc (and sym (cadr (assq sym package-alist)))))
    (if (not desc)
        'rejected
      (jetpacs-pkg--deferred params (format "Deleting %s..." name)
        (condition-case err
            (progn (package-delete desc)
                   (jetpacs-toast (format "Deleted %s" name)))
          ;; Typically: something still depends on it.
          (error (jetpacs-toast
                  (format "Delete failed: %s"
                          (error-message-string err)))))))))

(defun jetpacs-pkg--action-refresh (_args params)
  (jetpacs-pkg--deferred params "Refreshing package archives..."
    (condition-case err
        (progn
          (unless package--initialized (package-initialize))
          (package-refresh-contents)
          (jetpacs-toast "Archives refreshed"))
      (error (jetpacs-toast
              (format "Refresh failed: %s" (error-message-string err)))))))

(defun jetpacs-pkg--action-upgrade-all (_args params)
  (if (not (fboundp 'package-upgrade-all))
      'rejected
    (jetpacs-pkg--deferred params "Upgrading all packages..."
      (condition-case err
          (progn (package-upgrade-all nil)
                 (jetpacs-toast "Upgrades complete"))
        (error (jetpacs-toast
                (format "Upgrade failed: %s"
                        (error-message-string err))))))))

(defun jetpacs-pkg--action-describe (args _params)
  (let* ((name (plist-get args :package))
         (sym (and (stringp name) (intern-soft name))))
    (if (not (and sym
                  (or (assq sym package-archive-contents)
                      (assq sym package-alist)
                      (assq sym package--builtins))
                  jetpacs-tablist-view-buffer-function))
        'rejected
      (save-window-excursion (describe-package sym))
      (funcall jetpacs-tablist-view-buffer-function "*Help*")
      'accepted)))

(jetpacs-defaction "packages.show" #'jetpacs-pkg--action-show)
(jetpacs-defaction "packages.search" #'jetpacs-pkg--action-search)
(jetpacs-defaction "packages.status-filter" #'jetpacs-pkg--action-status-filter)
(jetpacs-defaction "packages.install" #'jetpacs-pkg--action-install)
(jetpacs-defaction "packages.delete" #'jetpacs-pkg--action-delete)
(jetpacs-defaction "packages.refresh-archives" #'jetpacs-pkg--action-refresh)
(jetpacs-defaction "packages.upgrade-all" #'jetpacs-pkg--action-upgrade-all)
(jetpacs-defaction "packages.describe" #'jetpacs-pkg--action-describe)

;; Entry card on the settings screen (order 10, ahead of Customize).
;; Soft-coupled: the browser works without the settings module loaded.
(with-eval-after-load 'jetpacs-settings
  (jetpacs-settings-add-link
   10 (lambda ()
        (jetpacs-chrome-row "Packages"
                            :subtitle "Install and manage Emacs packages"
                            :icon "archive"
                            :trailing (jetpacs-icon "chevron_right")
                            :on-tap (jetpacs-action "packages.show"
                                                    :when-offline "drop")
                            :key "link-packages"))))

(defun jetpacs-package-browser-unload-function ()
  "Unload hygiene: drop the skin hooks."
  (setf (alist-get 'package-menu-mode jetpacs-tablist-header-functions
                   nil 'remove) nil)
  (setf (alist-get 'package-menu-mode jetpacs-tablist-row-functions
                   nil 'remove) nil)
  (setf (alist-get 'package-menu-mode jetpacs-tablist-filter-functions
                   nil 'remove) nil)
  nil)

(provide 'jetpacs-package-browser)
;;; jetpacs-package-browser.el ends here