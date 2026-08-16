;;; glasspane-config.el --- App-managed org defaults on disk -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; Glasspane's opinionated defaults — the capture templates — live as
;; small elisp files in Glasspane's config subtree, written and
;; refreshed by the app rather than hand-maintained in init.el.  (The
;; org-defaults.el half — inbox seeding, agenda-files fallback,
;; LOGBOOK drawer, babel languages — was phone-generic, not app
;; opinion, and moved to the foundation under the §3 step-4 ruling:
;; jetpacs-org-settings.el seeds it at load with the same
;; only-while-stock guards.  Its managed file survives as a stub so a
;; `config.sync' overwrites stale copies on already-provisioned
;; devices.)  The contract is v1's, unchanged:
;;
;;   - `glasspane-config-sync' (or the allowlisted `config.sync' action)
;;     rewrites every managed file to the bundle's current defaults, so
;;     an app update can evolve them; edits to the files themselves are
;;     expected to be lost.
;;   - Personal configuration belongs in init.el or Customize — both win
;;     because they run after these files load.
;;   - The defaults are deliberately soft: capture templates merge by key
;;     and never replace one the user already defined; variables are
;;     seeded only while still at their stock values.
;;
;; Retired against v1 (docs/PLAN-glasspane-app.md T2 + G2): the
;; foundation config seam — `jetpacs-app-dir' /
;; `jetpacs-app-config-{load,sync,ensure}' — has no v3 port target
;; (FOUNDATION-GAPS #4, decided DEFER: POC 3 dropped the managed-config
;; layer deliberately, jetpacs-settings.el:26), so the subtree contract
;; is app-local below, promoted to the store only if a second app wants
;; it.  The install-consent register `jetpacs-installed-bundles' is now
;; `jetpacs-app-store-installed', and dev/in-tree loads NEVER appear
;; there.  Loading this helper alone remains load-only; the full Glasspane
;; entry owns first-boot `glasspane-config-ensure', while store-adopted
;; installs keep the automatic helper-level path.  The handler's `fboundp'
;; guards on shell notify/push are
;; dropped (hard deps, T5) and its trailing inline push moved into the
;; deferred continuation (D2).

;;; Code:

(require 'jetpacs-surfaces)
(require 'jetpacs-shell)

(defconst glasspane-config-app-id "glasspane"
  "App-id keying Glasspane's config subtree.
The managed files live under `glasspane-config-dir'; the key matches
the D1 owner so on-disk config and in-memory registrations share one
name.")

(defconst glasspane-config-version 1
  "Version of the managed defaults; stamped into every written file.")

(defconst glasspane-config--files
  '(("capture-templates.el" . "\
;;; capture-templates.el --- Glasspane-managed capture templates
;; APP-MANAGED (glasspane-config v1): rewritten by `glasspane-config-sync'.
;; Don't edit here — define your own templates in init.el; these merge
;; by key and never replace one you already have.

(require 'org-capture)

(defvar glasspane-config-capture-templates
  '((\"t\" \"Todo\" entry (file+headline org-default-notes-file \"Tasks\")
     \"* TODO %?\\n%U\\n%i\" :empty-lines 1)
    (\"n\" \"Note\" entry (file+headline org-default-notes-file \"Notes\")
     \"* %? :note:\\n%U\\n%i\" :empty-lines 1)
    (\"l\" \"Link\" entry (file+headline org-default-notes-file \"Links\")
     \"* %?\\n%U\\n%a\" :empty-lines 1))
  \"Glasspane's default capture templates (phone capture reads these).\")

(dolist (tpl glasspane-config-capture-templates)
  (unless (assoc (car tpl) org-capture-templates)
    (setq org-capture-templates
          (append org-capture-templates (list tpl)))))
")
    ("org-defaults.el" . "\
;;; org-defaults.el --- Glasspane-managed org wiring (relocated)
;; APP-MANAGED (glasspane-config v1): rewritten by `glasspane-config-sync'.
;; Emptied on purpose: the phone-generic org seeding this file carried
;; (inbox capture target, the org-directory mkdir, the agenda-files
;; fallback, the LOGBOOK drawer, babel languages) is FOUNDATION-owned
;; now -- emacs/jetpacs-org-settings.el seeds it at load with the same
;; only-while-stock guards.  The file stays managed so a config.sync on
;; an already-provisioned device OVERWRITES the old duplicate copy
;; instead of leaving it to shadow the foundation's seeding.
"))
  "Alist of (FILENAME . CONTENT) written by `glasspane-config-sync'.")

;;;; The app-local subtree seam (FOUNDATION-GAPS #4: no core owner)

(defun glasspane-config-dir ()
  "Return Glasspane's config-subtree directory, trailing slash included.
Sits under jetpacs/apps/ beside the app-store's adopted bundles —
the same tree, keyed by `glasspane-config-app-id' — but is app-owned:
the store's flat *.el bundle scan never descends into it.  Computed
per call so a rebound `user-emacs-directory' (tests, portable homes)
is honored.  Not created here — the sync/ensure verbs do that when
the app opts in."
  (file-name-as-directory
   (expand-file-name glasspane-config-app-id
                     (expand-file-name "jetpacs/apps/" user-emacs-directory))))

(defun glasspane-config-load ()
  "Load every elisp file in Glasspane's config subtree, in name order.
A missing subtree is fine — nothing loads until the user opts in via
`glasspane-config-ensure' or `glasspane-config-sync'.  Name order makes
extra user files sort predictably among the managed ones; an error in
one file is reported and skipped, never fatal — one broken default must
not take the app's whole load down with it."
  (let ((dir (glasspane-config-dir)))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\.el\\'"))
        (condition-case err
            (load file nil 'nomessage)
          ;; SPEC 23.3: a config file's own text is user data, and an
          ;; error datum from `load' quotes it; the FILE name is what
          ;; identifies the failure, the datum may not be logged.
          (error (message "glasspane-config: error loading %s: %s"
                          file (jetpacs-error-label err))))))))

;;;###autoload
(defun glasspane-config-sync ()
  "Rewrite Glasspane's app-managed defaults and load them.
Every file in `glasspane-config--files' is overwritten — the
reset-to-current-bundle semantics are the point, so an app update can
evolve its defaults.  Returns the subtree directory."
  (interactive)
  (let ((dir (glasspane-config-dir))
        (coding-system-for-write 'utf-8))
    (make-directory dir t)
    (dolist (spec glasspane-config--files)
      (write-region (cdr spec) nil (expand-file-name (car spec) dir)
                    nil 'silent))
    (glasspane-config-load)
    dir))

;;;###autoload
(defun glasspane-config-ensure ()
  "Create the app-managed defaults on first run; load them afterwards.
A missing subtree is populated via `glasspane-config-sync'; an existing
one is only loaded, never rewritten — a user's edits to the seeded
files survive an app that merely re-runs this at load time.  The
overwrite/upgrade path is explicit: `glasspane-config-sync', or the
allowlisted `config.sync' action."
  (interactive)
  (if (file-directory-p (glasspane-config-dir))
      (glasspane-config-load)
    (glasspane-config-sync)))

(defun glasspane-config-startup ()
  "Load the managed defaults; on a store-adopted install, create them first.
Adoption via the app store (\"glasspane.el\" listed in
`jetpacs-app-store-installed') IS the install consent: a freshly
installed Glasspane must come up with capture templates or the phone
shows an empty capture sheet.
Everywhere else this helper stays load-only; the full app entry invokes
`glasspane-config-ensure' after registration.  Batch loads remain inert.
`bound-and-true-p' rather than a require: with the store not loaded there
was no adoption, and the conservative helper-level arm is the right answer."
  (if (member "glasspane.el" (bound-and-true-p jetpacs-app-store-installed))
      (glasspane-config-ensure)
    (glasspane-config-load)))

;;;; The verb

(defun glasspane-config--on-sync (_args _params)
  "Rewrite the managed defaults; the allowlisted `config.sync' body.
Argument-free by design: nothing on the wire chooses paths or content —
the fixed file set goes into the fixed subtree.  The write runs
synchronously inside the dispatch (fast, local, and \\='accepted must
mean durable); a failed write signals out and the dispatch answers
\\='rejected, never a swallowed-error accept.  The snackbar queues
without blocking, and the re-push rides the deferred continuation —
zero-arg `jetpacs-shell-push' resolves through the flow's owner (D2)."
  (let ((dir (glasspane-config-sync)))
    (jetpacs-shell-notify
     (format "App defaults refreshed in %s" (abbreviate-file-name dir))))
  (jetpacs-flow-continue #'jetpacs-shell-push)
  'accepted)

(defun glasspane-config-register ()
  "Register the `config.sync' verb.
Called from `glasspane-register', not at this file's load: the entry's
unregister must leave no glasspane handler behind, and its re-register
must restore every verb without a re-require (the G0 gate contract)."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "config.sync" #'glasspane-config--on-sync)))

(defun glasspane-config-unregister ()
  "Drop the `config.sync' verb."
  (jetpacs-undefaction "config.sync"))

;; v1's entry called this after its requires; in v3 the require itself
;; is the bundle load, so the startup arm runs here — a bare desktop
;; `require' still only loads what already exists (see startup's doc).
;; Interactive-only: a batch load (byte-compile, the ERT suite, an
;; offline replay) runs under the REAL `user-emacs-directory' and would
;; EXECUTE whatever an earlier `glasspane-config-ensure' left in the
;; managed subtree.  The on-device Emacs and the desktop daemon are
;; both interactive, so the device path is unaffected; batch callers
;; that want the defaults call `glasspane-config-startup' themselves.
(unless noninteractive
  (glasspane-config-startup))

(defun glasspane-config-unload-function ()
  "Unload hygiene: drop the verb, wherever registration stands."
  (glasspane-config-unregister)
  nil)

(provide 'glasspane-config)
;;; glasspane-config.el ends here
