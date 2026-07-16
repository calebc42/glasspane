;;; glasspane-packages.el --- Self-provisioning of the optional org engines -*- lexical-binding: t; -*-

;; org-ql (the full search language), vulpea (backlinks, note
;; completion, the stale-file half of Review), org-srs (the Review
;; screen), ef-themes (the Ef Themes picker — a MELPA package, unlike the
;; built-in modus themes): all optional, all degrading cleanly — and all
;; installed by the LEGACY starter init at boot.  Under the foundation flow
;; (jetpacs-init + apps.el) nothing installed them, so a fresh device
;; dead-ended degraded forever: no Review entry, no backlinks, and
;; nothing on the device ever attempted the install — restarting could
;; never help.  Ported from jetpacs-composer's engine self-provisioning
;; (jetpacs-crud-vulpea.el): the app provisions its OWN engines.  One
;; automatic attempt per interactive session when the app is installed
;; as a device app and something is missing, the allowlisted
;; `packages.install' action as the on-demand path, and
;; `M-x glasspane-packages-ensure' as the desktop path.  Success lights
;; features up live — probes re-ask, vulpea autosync wired, shell
;; refreshed — no restart.
;;
;; Trust boundary (the same lock composer's Stage 4 keeps): only this
;; closed, app-owned set ever auto-installs.  Nothing on the wire and
;; nothing in org data can name a package.

;;; Code:

(require 'cl-lib)
(require 'jetpacs)
(require 'jetpacs-shell)
(require 'jetpacs-settings)
(require 'jetpacs-config)
(require 'glasspane-config)

(declare-function vulpea-db-autosync-mode "vulpea-db" (&optional arg))
(declare-function vulpea-db-sync-full-scan "vulpea-db" ())
(declare-function glasspane-vulpea-register "glasspane-vulpea" ())
(declare-function org-srs-item-confirm-command "org-srs" ())

;; Forward-declared: `org-directory' lives in org, which this file must not
;; force-load — the references in `--light-up' only run once the optional
;; engines are present.
(defvar org-directory)

(defcustom glasspane-packages-auto-install t
  "When non-nil, a device install with missing engines schedules one
automatic install attempt per session (on an idle timer, so boot is
never blocked).  The `packages.install' action and
`glasspane-packages-ensure' work regardless.  Set to nil (in user.el
or from Settings) to manage packages yourself."
  :type 'boolean :group 'jetpacs)

(defconst glasspane-packages--set '(org-ql vulpea org-srs ef-themes)
  "The closed MELPA set the app's optional features read through.
The starter init's package list, now owned by the bundle, plus ef-themes
for the Ef Themes picker.  Deliberately not extensible from app data or
the wire — see the trust note above.")

(defvar glasspane-packages--attempted nil
  "Non-nil once this session has scheduled its automatic install attempt.")

(defvar glasspane-packages--installing nil
  "Non-nil while an engine install is in flight.
Load-bearing re-entrancy guard: `package-refresh-contents' pumps the
event loop (`accept-process-output'), so a second tap could otherwise
re-enter mid-install.")

(defun glasspane-packages--wanted ()
  "The subset of `glasspane-packages--set' this Emacs build can run.
vulpea's index rides SQLite; on a build without it no package install
can help, so vulpea is simply not wanted — search (org-ql) and review
\(org-srs) still are."
  (if (and (fboundp 'sqlite-available-p) (sqlite-available-p))
      glasspane-packages--set
    (remq 'vulpea glasspane-packages--set)))

(defun glasspane-packages--missing ()
  "The wanted packages not currently loadable, freshly probed."
  (cl-remove-if (lambda (pkg) (require pkg nil t))
                (glasspane-packages--wanted)))

(defun glasspane-packages--light-up ()
  "Wire what is now loadable and refresh the shell.
The wiring the starter init used to carry: vulpea autosync over the
vault (additive — user directories are kept, one index, and the
initial full scan runs once per device via a marker file) and the
command-style org-srs confirm phone-driven review needs.  Then a shell
refresh, which re-asks the memoised probes and rebuilds every pushed
view — the Review drawer entry and the notes sections appear live."
  (when (require 'vulpea nil t)
    (defvar vulpea-db-sync-directories)
    (when (and (stringp org-directory) (file-directory-p org-directory))
      (add-to-list 'vulpea-db-sync-directories org-directory))
    ;; The mobile-context extractor must be in the registry before
    ;; autosync or the once-per-device full scan index anything.
    (when (require 'glasspane-vulpea nil t)
      (glasspane-vulpea-register))
    (when (fboundp 'vulpea-db-autosync-mode)
      (vulpea-db-autosync-mode 1))
    ;; Autosync watches for changes; a vault that predates vulpea still
    ;; needs one full index build.
    (let ((marker (expand-file-name ".vulpea-scanned"
                                    (jetpacs-app-dir glasspane-config-app-id))))
      (unless (file-exists-p marker)
        (when (fboundp 'vulpea-db-sync-full-scan)
          (ignore-errors (vulpea-db-sync-full-scan)))
        (make-directory (file-name-directory marker) t)
        (write-region "" nil marker nil 'silent))))
  (when (require 'org-srs nil t)
    (defvar org-srs-item-confirm)
    ;; Upstream's own recommendation for Emacs on Android: the default
    ;; confirm reads a key, which phone-driven review can never answer.
    (setq org-srs-item-confirm #'org-srs-item-confirm-command))
  (when (fboundp 'jetpacs-shell-refresh)
    (jetpacs-shell-refresh)))

(defun glasspane-packages-ensure ()
  "Install any missing engine from MELPA, then light features up.
Synchronous (package.el is), idempotent, and never signals: returns
non-nil when everything wanted is loadable afterwards, else nil with
the reason in *Messages*.  The retry story is calling this again —
each device boot's automatic attempt and every `packages.install' tap
do exactly that."
  (interactive)
  (cond
   (glasspane-packages--installing
    (message "glasspane-packages: install already in progress")
    nil)
   ((null (glasspane-packages--missing))
    (glasspane-packages--light-up)
    t)
   (t
    (setq glasspane-packages--installing t)
    (unwind-protect
        (condition-case err
            (progn
              (require 'package)
              (defvar package-archives)
              (add-to-list 'package-archives
                           '("melpa" . "https://melpa.org/packages/") t)
              (unless (bound-and-true-p package--initialized)
                (package-initialize))
              (package-refresh-contents)
              (dolist (pkg (glasspane-packages--missing))
                (unless (package-installed-p pkg)
                  (message "glasspane-packages: installing %s…" pkg)
                  (package-install pkg)))
              (let ((still (glasspane-packages--missing)))
                (if still
                    (progn
                      (message "glasspane-packages: %s installed but not loadable — see *Messages*"
                               (mapconcat #'symbol-name still ", "))
                      nil)
                  (glasspane-packages--light-up)
                  (message "glasspane-packages: engines ready — views refreshed")
                  t)))
          (error
           (message "glasspane-packages: install failed: %s"
                    (error-message-string err))
           nil))
      (setq glasspane-packages--installing nil)))))

(defun glasspane-packages-maybe-auto-install ()
  "Schedule this session's one automatic install when a device needs it.
Called from the bundle entry at load; fires on an idle timer so boot
cost is zero.  Only in an interactive session (batch/CI must never
reach for MELPA), only when the app is installed as a device app
\(listed in `jetpacs-installed-bundles' — the same consent that seeds
the managed config), at most once a session, and only when something
wanted is actually missing.  Restart = the natural retry."
  (when (and glasspane-packages-auto-install
             (not noninteractive)
             (not glasspane-packages--attempted)
             (member "glasspane.el" (bound-and-true-p jetpacs-installed-bundles))
             (glasspane-packages--missing))
    (setq glasspane-packages--attempted t)
    (run-with-idle-timer
     3 nil
     (lambda ()
       (message "glasspane-packages: engines missing — attempting install (%s)…"
                (mapconcat #'symbol-name (glasspane-packages--missing) ", "))
       (glasspane-packages-ensure)))))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "packages.install"
    ;; Allowlisted and argument-free: installs the closed engine set —
    ;; nothing on the wire chooses packages.  package.el is synchronous,
    ;; so feedback rides toasts around the (possibly long) install.
    (lambda (_ _)
      (jetpacs-send "toast.show" '((text . "Installing packages…")))
      (if (glasspane-packages-ensure)
          (jetpacs-send "toast.show" '((text . "Packages ready — views refreshed")))
        (jetpacs-send "toast.show" '((text . "Install failed — check *Messages* in Emacs"))))))

  (jetpacs-settings-register-section
   "Packages"
   '((glasspane-packages-auto-install
      :label "Auto-install packages (org-ql, vulpea, org-srs, ef-themes)"))))

(provide 'glasspane-packages)
;;; glasspane-packages.el ends here
