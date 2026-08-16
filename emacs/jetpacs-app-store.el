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
;; Edit means EDIT: an installed bundle opens in a writable plain
;; editor (`value'+`on_save', never `:document' — synchronizing a
;; buffer is another program's business), and the save rides
;; `jetpacs.app-store.save', whose containment check names the ADOPT
;; DIR and nothing else.  The Files rung has its own roots allowlist
;; and this route does not widen it: the app-store writes into the one
;; directory it adopts into.
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
(require 'ebp-path)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)

(defconst jetpacs-app-store-surface "jetpacs.app-store"
  "The Manage Apps screen's root surface (owner and surface name).")

(defcustom jetpacs-app-store-staging-dirs
  '("/sdcard/Download" "/sdcard/Documents/jetpacs-apps")
  "Directories scanned for app bundles, in priority order.
Download is where self-distributed bundles land (possibly renamed
\"name.el.txt\" by MediaStore); Documents/jetpacs-apps is the explicit
side-load staging folder.  Neither is an active Elisp load path."
  :type '(repeat directory) :group 'jetpacs)

(defcustom jetpacs-app-store-file
  (expand-file-name "jetpacs/apps.el" user-emacs-directory)
  "The create-once file persisting the installed-bundle list."
  :type 'file :group 'jetpacs)

(defcustom jetpacs-app-store-max-bytes (* 48 1024)
  "Upper bound on a bundle the Edit screen will host, in bytes.
A FLAT conservative cap, deliberately NOT the files rung's wire-derived
derivation (`jetpacs-files--editor-cap'): the seed rides a surface push
and the save must come back as one `event.action', and on the
minimum-conforming floor that derivation lands near 60 KiB.  48 KiB sits
under it by construction, so the app-store never probes the session's
limits to know whether it may open a bundle — and a bundle that big is
not one anyone edits on a phone.  Larger bundles are refused, loudly."
  :type 'integer :group 'jetpacs)

(defvar jetpacs-app-store-installed nil
  "Installed bundle names (\"name.el\"), the persisted list.")

(defvar jetpacs-app-store--edit nil
  "The bundle the Edit screen shows:
\(:name NAME :path TRUENAME :seed S :mtime T :coding C).  C is the
coding system the file was READ with — the save writes it back in the
same one.  Written by `jetpacs-app-store--action-edit' once eligibility
passed, and by a successful save (fresh seed and stamp).  The screen
BUILDER reads only this, never the disk, so a re-push while editing
re-renders the same seed and what actually shows is the Companion's
SPEC 13.6 draft: the user's typing.")

(defun jetpacs-app-store--adopt-dir ()
  (expand-file-name "jetpacs/apps/" user-emacs-directory))

(defun jetpacs-app-store--check (path)
  "PATH through the shared guard against the ADOPT DIR ALONE.
Returns the truename; signals `ebp-path-refused' (one symbol, no path —
§23.1) otherwise.  Containment only: existence and staleness are the
mtime stamp's job, and a bundle deleted underneath must answer `stale'
rather than a guard reason.

THE ONE root is the point.  `jetpacs-files-roots' is a different
allowlist for a different rung, and the writable editor added here does
not widen it: the app-store may write into the directory it adopts
into, and nowhere else."
  (ebp-check-path path (list (jetpacs-app-store--adopt-dir)) :require nil))

(defun jetpacs-app-store--mtime-stamp (path)
  "PATH's modification time as an opaque comparable string, or nil.
Compared by `equal' only and never parsed; nil (the bundle is gone) can
never equal a stamp.  Local rather than borrowed from the files rung:
this is a formatting helper, not a guard, and the app-store does not
take a dependency on the file browser to save a file it owns."
  (when-let* ((mt (file-attribute-modification-time (file-attributes path))))
    (format-time-string "%s.%6N" mt)))

(defconst jetpacs-app-store--foundation-files
  '("jetpacs-core.el" "jetpacs-init.el" "init.el")
  "Foundation bundles: not apps, never listed.
POC 1's rule, kept — a staged copy of the platform itself must not be
installable over the running one.")

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
            (unless (member name jetpacs-app-store--foundation-files)
              (let ((prev (gethash name best)))
                (when (or (null prev) (file-newer-than-file-p path prev))
                  (puthash name path best))))))))
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
  ";;; apps.el --- installed Jetpacs app bundles -*- lexical-binding: t; -*-
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
         ;; Installed rows carry the whole lifecycle: edit the adopted
         ;; source, or uninstall (launching lives on the Running rows —
         ;; a bundle that registered an app via `jetpacs-defapp').
         (list
          (jetpacs-icon-button
           "edit"
           (jetpacs-action "apps.edit" :args `(:bundle ,name)
                           :when-offline "drop")
           :content-description (format "Edit %s" name))
          (jetpacs-icon-button
           "delete"
           (jetpacs-action "apps.uninstall" :args `(:bundle ,name)
                           :when-offline "drop")
           :content-description (format "Uninstall %s" name)))
       (jetpacs-icon-button
        "download"
        (jetpacs-action
         "apps.install" :args `(:bundle ,name)
         :when-offline "drop"
         ;; §14.1 object form (amendment #168): installing is running
         ;; code; the gate says so, wearing an authored face.
         :confirm (list :title "Install app?"
                        :icon "download"
                        :text (format "Installing runs %s with your Emacs's full permissions."
                                      name)
                        :confirm-label "Install"
                        :dismiss-label "Cancel"))
        :content-description (format "Install %s" name)))
     :key (jetpacs-wire-id "as" name))))

(defun jetpacs-app-store--view ()
  "The combined Apps view (owner decision 2026-08-06 pass 2):
installing, removing, editing, and launching in one screen.  Running =
Tier 1 apps registered via `jetpacs-defapp' (tap to launch); Installed
= adopted bundles (edit/uninstall); Available = staged bundles
(install, behind the consent gate)."
  (let* ((entries (jetpacs-app-store--scan))
         (installed (cl-remove-if-not
                     (lambda (e) (plist-get e :installed)) entries))
         (available (cl-remove-if
                     (lambda (e) (plist-get e :installed)) entries)))
    (jetpacs-chrome-screen
     "Apps"
     (apply #'jetpacs-lazy-column
            (append
             (when jetpacs-apps--registry
               (cons (jetpacs-section-header "Running")
                     (mapcar #'jetpacs-apps--card jetpacs-apps--registry)))
             (when installed
               (cons (jetpacs-section-header "Installed")
                     (mapcar #'jetpacs-app-store--row installed)))
             (when available
               (cons (jetpacs-section-header "Available")
                     (mapcar #'jetpacs-app-store--row available)))
             (unless (or jetpacs-apps--registry entries)
               (list (jetpacs-empty-state
                      :icon "apps" :title "No apps"
                      :caption
                      (format "Drop a bundle .el into %s and refresh."
                              (car jetpacs-app-store-staging-dirs)))))))
     :on-refresh (jetpacs-action "apps.refresh-store" :when-offline "drop"))))

(defun jetpacs-app-store--refresh ()
  (jetpacs-flow-continue
   (lambda ()
     (ignore-errors (jetpacs-shell-push jetpacs-app-store-surface)))))

;;;; The editor
;;
;; A PLAIN editor — `value' seeded once, the whole content coming back
;; on `on_save' as one event — and pointedly not the synchronized §19
;; shape: an adopted bundle is a file this screen owns, not a buffer
;; two programs are holding open, and `:document' would make it one.
;; The mtime stamp rides the save descriptor so a bundle reinstalled
;; underneath answers `stale' instead of being clobbered.

(defun jetpacs-app-store--edit-screen (back)
  "Builder for the pushed Edit screen; reads `jetpacs-app-store--edit'."
  (let ((req jetpacs-app-store--edit))
    (if (null req)
        (jetpacs-chrome-screen
         "Edit"
         (jetpacs-empty-state :icon "info" :title "Nothing being edited")
         :back back)
      (let ((path (plist-get req :path)))
        (jetpacs-chrome-screen
         (jetpacs-scalar-text (plist-get req :name))
         (jetpacs-editor
          (jetpacs-claim-node-id (jetpacs-wire-id "asedit" path))
          :value (plist-get req :seed)
          :syntax "elisp"
          ;; No `:when-offline "drop"' here, unlike every descriptor on
          ;; the list screen: a refresh is cheap to retake, and a
          ;; dropped SAVE is the user's typing thrown away.
          :on-save (jetpacs-action "jetpacs.app-store.save"
                                   :args (list :path path
                                               :mtime (plist-get req :mtime))))
         :back back)))))

;;;; Actions

(defun jetpacs-app-store--action-refresh (_args _params)
  (jetpacs-app-store--refresh)
  'accepted)

(defun jetpacs-app-store--action-edit (args params)
  "Open an installed bundle's adopted source in a WRITABLE editor.
The wire still only names a BUNDLE from the installed list, never a
path; the path this resolves to is re-validated against the adopt dir
anyway, because the resolution and the write are two different moments.
An unreadable, irregular or oversize bundle is refused rather than
silently downgraded — the read-only projection this screen used to open
answered a question nobody asked."
  (let ((name (plist-get args :bundle))
        (surface (or (plist-get params :surface) jetpacs-app-store-surface)))
    (if (not (member name jetpacs-app-store-installed))
        'rejected
      (condition-case err
          (let* ((true (jetpacs-app-store--check
                        (expand-file-name name (jetpacs-app-store--adopt-dir))))
                 (size (or (file-attribute-size (file-attributes true)) 0)))
            (cond
             ((not (and (file-regular-p true) (file-readable-p true)))
              'rejected)
             ((> size jetpacs-app-store-max-bytes)
              (jetpacs-shell-notify "Too large to edit here" surface)
              'rejected)
             (t
              (let (coding)
                (let ((content (with-temp-buffer
                                 (insert-file-contents true)
                                 (setq coding last-coding-system-used)
                                 (buffer-string))))
                  (setq jetpacs-app-store--edit
                        (list :name name :path true :seed content
                              :mtime (jetpacs-app-store--mtime-stamp true)
                              :coding coding))))
              (jetpacs-flow-continue
               (lambda ()
                 ;; push-screen is transactional and RE-SIGNALS; a
                 ;; deferred caller must catch or the signal dies in a
                 ;; timer (its own docstring's rule).
                 (condition-case perr
                     (jetpacs-chrome-push-screen
                      surface "edit" #'jetpacs-app-store--edit-screen)
                   (error (jetpacs-toast
                           (format "Edit failed: %s"
                                   (jetpacs-error-label perr)))))))
              'accepted)))
        (ebp-path-refused
         (jetpacs-shell-notify (format "Edit refused: %s" (cadr err)) surface)
         'rejected)))))

(defun jetpacs-app-store--action-save (args params)
  "Write the edited bundle back — inside the adopt dir, or not at all.
SPEC 14.3: `on_save' injects the editor's full content as `value' into
a copy of the descriptor's args; the path and the open-time mtime stamp
ride the descriptor itself.

THE CONTAINMENT PIN.  The path arrives over the wire, so it is checked
by `jetpacs-app-store--check' — `ebp-check-path' against the adopt dir
ALONE — and a path outside it is refused LOUDLY, before anything is
read, written or compiled.  This route is not a second Files editor and
must never be usable as one.

After a durable write the bundle is byte-compiled best-effort (the
install path's idiom: a bundle that will not compile is still saved)
and the snackbar says what is true — the running Emacs keeps the code
it already loaded, and the edit takes effect on the next boot.  Nothing
is hot-reloaded here: re-loading a live bundle over itself is the
install action's decision to make, not a save's."
  (let ((surface (or (plist-get params :surface) jetpacs-app-store-surface))
        (value (plist-get args :value))
        (stamp (plist-get args :mtime)))
    (condition-case err
        (let ((true (jetpacs-app-store--check (plist-get args :path))))
          (cond
           ((not (stringp value)) 'rejected)
           ((> (string-bytes value) jetpacs-app-store-max-bytes)
            ;; The write is the interpretation; bound it even though a
            ;; conforming Companion could not have sent this.
            (jetpacs-shell-notify "Save too large" surface)
            'rejected)
           ((not (equal stamp (jetpacs-app-store--mtime-stamp true)))
            ;; Reinstalled — or uninstalled — since the editor opened.
            (jetpacs-shell-notify "Bundle changed on disk — not saved" surface)
            'stale)
           ((not (file-writable-p true))
            (jetpacs-shell-notify "Save refused: unwritable" surface)
            'rejected)
           (t
            (let ((coding-system-for-write
                   (and (equal (plist-get jetpacs-app-store--edit :path) true)
                        (plist-get jetpacs-app-store--edit :coding))))
              (write-region value nil true nil 'silent))
            (ignore-errors (byte-compile-file true))
            ;; Effect durable -> accepted (14.4).  Keep the edit record
            ;; coherent for the NEXT save: fresh seed and stamp, taken
            ;; after the compile so a touched .el cannot go stale here.
            (when (equal (plist-get jetpacs-app-store--edit :path) true)
              (setq jetpacs-app-store--edit
                    (list :name (plist-get jetpacs-app-store--edit :name)
                          :path true :seed value
                          :mtime (jetpacs-app-store--mtime-stamp true)
                          :coding (plist-get jetpacs-app-store--edit :coding))))
            (jetpacs-shell-notify
             (format "Saved %s — reloads on the next boot"
                     (jetpacs-scalar-text (file-name-nondirectory true)))
             surface)
            'accepted)))
      (ebp-path-refused
       (jetpacs-shell-notify (format "Save refused: %s" (cadr err)) surface)
       'rejected)
      (error
       (jetpacs-shell-notify
        (format "Save failed: %s" (jetpacs-error-label err)) surface)
       'rejected))))

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
(jetpacs-defaction "apps.edit" #'jetpacs-app-store--action-edit)
(jetpacs-defaction "jetpacs.app-store.save" #'jetpacs-app-store--action-save)

(defvar jetpacs-launcher-row-icons)
(defvar jetpacs-launcher-row-labels)
(with-eval-after-load 'jetpacs-launcher
  (setf (alist-get (concat "app:" jetpacs-app-store-surface)
                   jetpacs-launcher-row-icons nil nil #'equal)
        "apps")
  (setf (alist-get (concat "app:" jetpacs-app-store-surface)
                   jetpacs-launcher-row-labels nil nil #'equal)
        "Apps"))

(provide 'jetpacs-app-store)
;;; jetpacs-app-store.el ends here
