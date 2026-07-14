;;; glasspane-config.el --- App-managed org defaults on disk -*- lexical-binding: t; -*-

;; Glasspane's opinionated defaults — capture templates, agenda wiring,
;; babel languages — live as small elisp files in Glasspane's config
;; subtree, written and refreshed by the app rather than hand-maintained in
;; init.el.  As of the jetpacs foundation-root work the subtree and its
;; sync/ensure/load contract are owned by core: this file is a thin caller
;; of `jetpacs-app-config-*', keyed by the app-id "glasspane", so the files
;; live under `(jetpacs-app-dir "glasspane")' (i.e.
;; ~/.emacs.d/jetpacs/apps/glasspane/) alongside every other app's subtree.
;; The contract is unchanged:
;;
;;   - `glasspane-config-sync' (or the allowlisted `config.sync' action)
;;     rewrites every managed file to the bundle's current defaults, so an
;;     app update can evolve them; edits to the files themselves are
;;     expected to be lost.
;;   - Personal configuration belongs in init.el or ~/.emacs.d/jetpacs/user.el
;;     (both load after these files, so they win) or in Customize.
;;   - The defaults are deliberately soft: capture templates merge by key
;;     and never replace one the user already defined; variables are seeded
;;     only while still at their stock values.
;;
;; Who writes the subtree the first time depends on the install flow:
;; the legacy starter init calls `glasspane-config-ensure' itself, and
;; under the foundation flow (jetpacs-init + apps.el) the bundle's own
;; load does it via `glasspane-config-startup' — being listed in
;; ~/.emacs.d/jetpacs/apps.el IS the install consent.  A bare
;; (require 'glasspane) anywhere else only loads what already exists;
;; nothing is written until asked.

;;; Code:

(require 'jetpacs-config)
(require 'jetpacs-surfaces)

(defconst glasspane-config-app-id "glasspane"
  "App-id keying Glasspane's config subtree and its foundation ownership.
The managed files live under `(jetpacs-app-dir glasspane-config-app-id)'.")

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
;;; org-defaults.el --- Glasspane-managed org wiring
;; APP-MANAGED (glasspane-config v1): rewritten by `glasspane-config-sync'.
;; Personal settings belong in init.el or Customize — they win because
;; init.el runs after this file loads.

(require 'org)

;; Capture lands in the inbox inside `org-directory' (only seeded while
;; still at org's stock ~/.notes default).
(when (equal org-default-notes-file
             (convert-standard-filename \"~/.notes\"))
  (setq org-default-notes-file
        (expand-file-name \"inbox.org\" org-directory)))
(make-directory org-directory t)

;; The phone's agenda tab needs agenda files; default to the whole
;; org directory when nothing is configured yet.
(unless org-agenda-files
  (setq org-agenda-files (list org-directory)))

;; State changes and clocks go into LOGBOOK drawers — the heading
;; detail view shows them as a structured section.
(setq org-log-into-drawer t)

;; Languages the demo corpus executes from the phone; the run button
;; only appears for languages loaded here.
(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t) (shell . t) (python . t)))
"))
  "Alist of (FILENAME . CONTENT) written by `glasspane-config-sync'.")

;;;###autoload
(defun glasspane-config-sync ()
  "Rewrite Glasspane's app-managed defaults and load them.
Delegates to `jetpacs-app-config-sync' under the app-id
`glasspane-config-app-id'; every file in `glasspane-config--files' is
overwritten — the reset-to-current-bundle semantics are the point.
Returns the subtree directory."
  (interactive)
  (jetpacs-app-config-sync glasspane-config-app-id glasspane-config--files))

(defun glasspane-config-load ()
  "Load every elisp file in Glasspane's config subtree, in name order.
A missing subtree is fine — nothing loads until the user opts in via
`glasspane-config-ensure' or `glasspane-config-sync'."
  (jetpacs-app-config-load glasspane-config-app-id))

;;;###autoload
(defun glasspane-config-ensure ()
  "Create the app-managed defaults on first run; load them afterwards.
Delegates to `jetpacs-app-config-ensure': a missing subtree is populated
via `glasspane-config-sync'; an existing one is only loaded, never
rewritten."
  (jetpacs-app-config-ensure glasspane-config-app-id glasspane-config--files))

(defun glasspane-config-startup ()
  "Load the managed defaults; under the foundation flow, create them first.
Being listed in ~/.emacs.d/jetpacs/apps.el (`jetpacs-installed-bundles')
is the install consent: the bundle's require during
`jetpacs-config-bootstrap' is Glasspane starting up on a device, and a
fresh one must come up with capture templates and agenda wiring or the
phone shows an empty Agenda and an empty capture sheet.  Bootstrap loads
custom.el and user.el after the app bundles, so personal settings still
win.  Anywhere else — a desktop `require', batch loads (tests, the pack
build) — nothing is written until the user opts in explicitly via
`glasspane-config-ensure'."
  (if (member "glasspane.el" (bound-and-true-p jetpacs-installed-bundles))
      (glasspane-config-ensure)
    (glasspane-config-load)))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "config.sync"
    ;; Allowlisted and argument-free: rewrites the fixed file set into
    ;; Glasspane's config subtree — nothing on the wire chooses paths or
    ;; content.
    (lambda (_ _)
      (let ((dir (glasspane-config-sync)))
        (when (fboundp 'jetpacs-shell-notify)
          (jetpacs-shell-notify
           (format "App defaults refreshed in %s"
                   (abbreviate-file-name dir)))))
      (when (fboundp 'jetpacs-shell-push)
        (jetpacs-shell-push)))))

(provide 'glasspane-config)
;;; glasspane-config.el ends here
