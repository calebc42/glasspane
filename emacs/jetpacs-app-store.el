;;; jetpacs-app-store.el --- Manage Apps: install/uninstall staged bundles -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;; The on-phone half of app distribution (behavior reference: POC 1's
;; jetpacs-app-store.el, on POC 3's layout): a Manage Apps screen
;; listing every bundle staged under `jetpacs-app-store-staging-dirs' —
;; one row per file name, newest copy wins — with an install or
;; uninstall affordance according to membership in the persisted
;; install list.
;;
;; Install ADOPTS: the staged file is copied into the private adopt
;; directory (stripping the \".txt\" MediaStore appends to shared
;; .el files — the device-verified rename trap), byte-compiled
;; best-effort, loaded live, and recorded; the app's surfaces appear in
;; the launcher with no restart.  Uninstall removes the record and the
;; adopted copy and unloads what it can — elisp cannot truly unload, so
;; the screen says "fully gone after a restart" when that is the honest
;; answer.
;;
;; Trust: installing IS running code.  The install action carries a
;; §14.1 :confirm gate that says so plainly, and the wire only ever
;; names a bundle FILE NAME, validated against a fresh scan — never a
;; path.  The staging dirs are dedicated, so the foundation's own
;; modules never appear by construction.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)

(defconst jetpacs-app-store-surface "jetpacs.app-store"
  "The Manage Apps screen's root surface (owner and surface name).")

(defcustom jetpacs-app-store-staging-dirs
  '("/sdcard/Download" "/sdcard/Documents/jetpacs/apps")
  "Directories scanned for app bundles, in priority order.
Download is where self-distributed bundles land (possibly renamed
\"name.el.txt\" by MediaStore); the apps subtree is the adb-push path."
  :type '(repeat directory) :group 'jetpacs)

(defcustom jetpacs-app-store-file
  (expand-file-name "jetpacs-apps.el" user-emacs-directory)
  "The create-once file persisting the installed-bundle list."
  :type 'file :group 'jetpacs)

(defvar jetpacs-app-store-installed nil
  "Installed bundle names (\"name.el\"), the persisted list.")

(defun jetpacs-app-store--adopt-dir ()
  (expand-file-name "jetpacs/apps/" user-emacs-directory))

;;;; The scan

(defun jetpacs-app-store--canonical (file)
  "FILE's bundle name: the base name with MediaStore's .txt stripped."
  (let ((name (file-name-nondirectory file)))
    (if (string-suffix-p ".el.txt" name)
        (substring name 0 -4)
      name)))

(defun jetpacs-app-store--summary (path)
  "The bundle's own one-line description, from its first header line."
  (with-temp-buffer
    (insert-file-contents path nil 0 300)
    (goto-char (point-min))
    (when (looking-at ";;;[^\n]*?--- *\\(.*?\\) *\\(?:-\\*-.*\\)?$")
      (match-string 1))))

(defun jetpacs-app-store--scan ()
  "Staged bundles, sorted by name: one plist per distinct bundle name.
Duplicates resolve newest-wins, so the row shown is the copy that
would install."
  (let ((best (make-hash-table :test 'equal)))
    (dolist (dir jetpacs-app-store-staging-dirs)
      (when (file-directory-p dir)
        (dolist (path (directory-files dir t "\\.el\\(\\.txt\\)?\\'"))
          (let ((name (jetpacs-app-store--canonical path)))
            (let ((prev (gethash name best)))
              (when (or (null prev) (file-newer-than-file-p path prev))
                (puthash name path best)))))))
    (let (entries)
      (maphash
       (lambda (name path)
         (push (list :name name :path path
                     :installed (and (member name jetpacs-app-store-installed)
                                     t)
                     :summary (ignore-errors
                                (jetpacs-app-store--summary path)))
               entries))
       best)
      (sort entries (lambda (a b) (string< (plist-get a :name)
                                           (plist-get b :name)))))))

(defun jetpacs-app-store--entry (name)
  "The fresh-scan entry for bundle NAME, or nil.
The validation gate every wire action passes through: an action names a
bundle, this resolves it against what is actually staged right now."
  (and (stringp name)
       (not (string-search "/" name))
       (seq-find (lambda (e) (equal (plist-get e :name) name))
                 (jetpacs-app-store--scan))))

;;;; Persistence (the create-once list file)

(defconst jetpacs-app-store--template
  ";;; jetpacs-apps.el --- installed app bundles -*- lexical-binding: t; -*-
;; Yours to edit — but the phone's Manage Apps screen also writes it,
;; and each install/uninstall rewrites this whole file from the list
;; below (hand comments do not survive that).

(setq jetpacs-app-store-installed '(%s))
")

(defun jetpacs-app-store--persist ()
  (let ((coding-system-for-write 'utf-8))
    (write-region (format jetpacs-app-store--template
                          (mapconcat (lambda (b) (format "%S" b))
                                     jetpacs-app-store-installed " "))
                  nil jetpacs-app-store-file nil 'silent)))

(defun jetpacs-app-store-boot ()
  "Load the persisted list, then every adopted bundle — each isolated.
One broken bundle costs itself, never the boot (the session-hook
lesson)."
  (when (file-readable-p jetpacs-app-store-file)
    (ignore-errors (load jetpacs-app-store-file nil 'nomessage)))
  (dolist (name jetpacs-app-store-installed)
    (let ((adopted (expand-file-name name (jetpacs-app-store--adopt-dir))))
      (condition-case err
          (load adopted nil 'nomessage)
        (error (message "jetpacs-app-store: %s failed to load: %s"
                        name (error-message-string err)))))))

;;;; Install / uninstall

(defun jetpacs-app-store--install (entry)
  "Adopt, byte-compile best-effort, load, and record ENTRY's bundle."
  (let* ((name (plist-get entry :name))
         (dir (jetpacs-app-store--adopt-dir))
         (dest (expand-file-name name dir)))
    (make-directory dir t)
    (copy-file (plist-get entry :path) dest t)
    (ignore-errors (byte-compile-file dest))
    (load dest nil 'nomessage)
    (cl-pushnew name jetpacs-app-store-installed :test #'equal)
    (jetpacs-app-store--persist)))

(defun jetpacs-app-store--uninstall (name)
  "Unrecord NAME, delete its adopted copies, unload what elisp can."
  (setq jetpacs-app-store-installed
        (delete name jetpacs-app-store-installed))
  (jetpacs-app-store--persist)
  (let ((dest (expand-file-name name (jetpacs-app-store--adopt-dir))))
    (ignore-errors (delete-file dest))
    (ignore-errors (delete-file (concat dest "c"))))
  (ignore-errors (unload-feature (intern (file-name-base name)) t)))

;;;; The view

(defun jetpacs-app-store--row (entry)
  (let* ((name (plist-get entry :name))
         (installed (plist-get entry :installed)))
    (jetpacs-chrome-row
     (file-name-base name)
     :subtitle (or (plist-get entry :summary) name)
     :icon (if installed "check_circle" "apps")
     :trailing
     (if installed
         (jetpacs-icon-button
          "delete"
          (jetpacs-action "apps.uninstall" :args `(:bundle ,name)
                          :when-offline "drop")
          :content-description (format "Uninstall %s" name))
       (jetpacs-icon-button
        "download"
        (jetpacs-action
         "apps.install" :args `(:bundle ,name)
         :when-offline "drop"
         ;; §14.1: installing is running code; the gate says so.  The
         ;; STRING form: the deployed Companion's validator does not yet
         ;; accept the ratified object form (conformance drift, tracked)
         ;; and refused the whole surface over it.
         :confirm (format "Installing runs %s with your Emacs's full permissions. Install it?"
                          name))
        :content-description (format "Install %s" name)))
     :key (jetpacs-wire-id "as" name))))

(defun jetpacs-app-store--view ()
  (let ((entries (jetpacs-app-store--scan)))
    (jetpacs-chrome-screen
     "Manage Apps"
     (apply #'jetpacs-lazy-column
            (if (null entries)
                (list (jetpacs-empty-state
                       :icon "apps" :title "No staged bundles"
                       :caption
                       (format "Drop a bundle .el into %s and refresh."
                               (car jetpacs-app-store-staging-dirs))))
              (mapcar #'jetpacs-app-store--row entries)))
     :on-refresh (jetpacs-action "apps.refresh-store" :when-offline "drop"))))

(defun jetpacs-app-store--refresh ()
  (jetpacs-flow-continue
   (lambda ()
     (ignore-errors (jetpacs-shell-push jetpacs-app-store-surface)))))

;;;; Actions

(defun jetpacs-app-store--action-refresh (_args _params)
  (jetpacs-app-store--refresh)
  'accepted)

(defun jetpacs-app-store--action-install (args _params)
  (let ((entry (jetpacs-app-store--entry (plist-get args :bundle))))
    (cond
     ((null entry) 'rejected)
     ((plist-get entry :installed) 'accepted) ; idempotent
     (t
      ;; Adoption reads, compiles, and LOADS: continuation work, and its
      ;; outcome reports by toast (D2 keeps the dispatch immediate).
      (jetpacs-flow-continue
       (lambda ()
         (condition-case err
             (progn (jetpacs-app-store--install entry)
                    (jetpacs-toast (format "Installed %s"
                                           (plist-get entry :name))))
           (error (jetpacs-toast (format "Install failed: %s"
                                         (error-message-string err)))))
         (ignore-errors (jetpacs-shell-push jetpacs-app-store-surface))))
      'accepted))))

(defun jetpacs-app-store--action-uninstall (args _params)
  (let ((name (plist-get args :bundle)))
    (if (not (member name jetpacs-app-store-installed))
        'rejected
      (jetpacs-flow-continue
       (lambda ()
         (jetpacs-app-store--uninstall name)
         (jetpacs-toast (format "%s removed - fully gone after a restart"
                                name))
         (ignore-errors (jetpacs-shell-push jetpacs-app-store-surface))))
      'accepted)))

(with-jetpacs-owner "jetpacs.app-store"
  (jetpacs-chrome-define-root jetpacs-app-store-surface "home"
                              (lambda (_back) (jetpacs-app-store--view))))
(jetpacs-defaction "apps.refresh-store" #'jetpacs-app-store--action-refresh)
(jetpacs-defaction "apps.install" #'jetpacs-app-store--action-install)
(jetpacs-defaction "apps.uninstall" #'jetpacs-app-store--action-uninstall)

(defvar jetpacs-launcher-row-icons)
(defvar jetpacs-launcher-row-labels)
(with-eval-after-load 'jetpacs-launcher
  (setf (alist-get (concat "app:" jetpacs-app-store-surface)
                   jetpacs-launcher-row-icons nil nil #'equal)
        "download")
  (setf (alist-get (concat "app:" jetpacs-app-store-surface)
                   jetpacs-launcher-row-labels nil nil #'equal)
        "Manage Apps"))

(provide 'jetpacs-app-store)
;;; jetpacs-app-store.el ends here