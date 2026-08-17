;;; glasspane.el --- Glasspane: org knowledge on Jetpacs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The v3 rebuild of the v1 reference app — notes, agenda, capture,
;; journal, SRS, the org reader — on the jetpacs foundation.  The
;; ladder is docs/PLAN-glasspane-app.md; this file is G0: the thin
;; entry in the M3 template (jetpacs-m3-catalog.el), owning exactly the
;; app identity — the "glasspane" owner claim, the chrome root (the
;; hub, built by glasspane-ui and merely NAMED here), the dock
;; destination, and one owner verb, `glasspane.home', which the hub's
;; drawer taps to come back.  The sibling `require' list below grew one
;; rung at a time and is now the whole app.
;;
;; Client hooks (clock notification, window class, save refresh) attach
;; at READY starting with G2 — G0 registers surfaces and verbs only,
;; which is connection-independent by design (`jetpacs-defaction' and
;; `jetpacs-chrome-define-root' are registries, not pushes).

;;; Code:

;; The sibling modules live FLAT beside this file both in the repo
;; (emacs/apps/glasspane/) and on the device (one directory), so the
;; entry adds its own directory — the M3 shim's shape
;; (jetpacs-m3-catalog.el:31-36), kept even while this file is alone so
;; G1's first sibling require works the day it lands.
(eval-and-compile
  (let* ((here (or load-file-name buffer-file-name))
         (dir (and here (file-name-directory here))))
    (when (and dir (file-directory-p dir))
      (add-to-list 'load-path dir))))

(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-widgets)
(require 'jetpacs-apps)

;; The rung ladder's sibling modules, in the plan's load order (G1: the
;; data layer).  glasspane-vulpea is the extractor's worker-lib —
;; definitions only, safe to load with vulpea absent; registration
;; happens where vulpea is DETECTED (glasspane-org's load tail, G2's
;; packages light-up), never here.
(require 'glasspane-org)
(require 'glasspane-vulpea)
;; G2, the services: clock has zero siblings; packages soft-requires
;; config's dir seam, so config loads first and its helper wins.
(require 'glasspane-clock)
(require 'glasspane-config)
(require 'glasspane-packages)
;; G3, the keystone: the settings surface, the shared view state, and
;; the at-ref funnel.  Requires glasspane-org, so it loads last.
(require 'glasspane-ui)
;; G4/GR-2, the reader + detail: the reader replaces the reusable host's
;; Org adapter slot and owns the refile list; detail requires it softly,
;; so it loads first.
(require 'glasspane-org-reader)
(require 'glasspane-detail)
;; G5 plus the staged PARA screens: the foundation date helper supports both
;; daily halves; agenda, Projects, and journal build on detail's shared card
;; and the reader (already above), while capture is verbs + sheets only.
(require 'jetpacs-dates)
(require 'glasspane-agenda)
(require 'glasspane-projects)
(require 'glasspane-areas)
(require 'glasspane-resources)
(require 'glasspane-journal)
(require 'glasspane-capture)
;; G6, the query surfaces: views leans on the reader's reorder table
;; and the agenda's shared date row, so it loads after both; search and
;; table depend only on landed G1/G3/G4 modules — the plan's order.
(require 'glasspane-views)
(require 'glasspane-search)
(require 'glasspane-table)
;; G7, the knowledge arms: srs soft-requires notes (the Review screen's
;; stale-files half calls its section builder), so notes loads first.
;; Both degrade to absent without vulpea/org-srs — the requires are
;; unconditional, the runtime probes are theirs.
(require 'glasspane-notes)
(require 'glasspane-srs)
;; G8, the satellites + fixtures: demo loads before gallery (gallery's
;; entry command leans on the demo seeder being in the image — the
;; plan's DEMO-BEFORE-GALLERY order).  The theme-picker scaffold ef
;; instantiates is foundation now (jetpacs-theme-picker, the §3 step-3
;; promotion), and ef requires it itself — no entry-point ordering to
;; hold.
(require 'glasspane-demo)
(require 'glasspane-ef)
(require 'glasspane-gallery)

(defconst glasspane-owner "glasspane"
  "The D1 owner whose surface hosts the app.
Not under `jetpacs-reserved-owner-prefix': Glasspane is a Tier-1
application, not base chrome — the M3 catalog's precedent, and the
second real `jetpacs-defapp' caller there is.")

(defconst glasspane-title "Glasspane"
  "The home top-bar title and the dock label.")

(defconst glasspane-icon "menu_book"
  "The dock/launcher icon.  A knowledge base is a book you keep open.")

;;;; Verbs

(defun glasspane--on-home (_args params)
  "Return to the root screen (the dock row's second tap)."
  (let ((surface (plist-get params :surface)))
    (jetpacs-flow-continue
     (lambda ()
       (jetpacs-chrome-reset-screens (or surface glasspane-owner))))
    'accepted))

;;;; App identity

(defun glasspane--dock-items (surface)
  "The app's dock destination, in the chrome seam's item shape.
A function so `:selected' tracks SURFACE (jetpacs-m3-core.el:1195's
rationale); the tap rides the GLOBAL `jetpacs.launcher.open' because it
arrives from whatever surface the user is looking at."
  (let ((home (jetpacs-shell-surface-for glasspane-owner)))
    (list (list :label glasspane-title
                :icon glasspane-icon
                ;; Gap #5 landed: today's agenda count rides the dock
                ;; icon (v1's Agenda tab badge on the one destination
                ;; v3 has).  Memoised — a table lookup per render.
                :badge (glasspane-agenda-dock-badge)
                :on-tap (jetpacs-action "jetpacs.launcher.open"
                                        :args (list :surface home))
                :selected (equal surface home)))))

(defun glasspane--destinations ()
  "The app's S1 route registry: the PLACES of `glasspane-ui-destinations'.
One source of truth minus one row — capture opens a DIALOG, and the
chrome contract types destinations as places, never actions
\(docs/CHROME-VOCABULARY.md); routing it would also flip the current
app under the host with no visible switch.  The host's capture
affordance is the FAB story, not a drawer row."
  (cl-remove "capture" glasspane-ui-destinations
             :key (lambda (d) (plist-get d :key)) :test #'equal))

(defun glasspane-register ()
  "Register the owner's verbs, the chrome root, and the app identity.
Idempotent: re-evaluation replaces the handlers and RESETS the screen
stack to home — the live-reload path; `jetpacs-defapp' replaces its
registry entry in place."
  (with-jetpacs-owner glasspane-owner
    (jetpacs-defaction "glasspane.home" #'glasspane--on-home)
    ;; The root is glasspane-ui's hub (the #26 rung): the entry names
    ;; the screen, the keystone builds it — the same split the dock
    ;; item keeps, identity here and content there.
    (jetpacs-chrome-define-root glasspane-owner "home"
                                #'glasspane-ui-home-screen))
  ;; After the root exists: the app claims a surface that is really
  ;; there, and its dock destination names one the launcher's
  ;; membership guard recognizes (the M3 ordering).
  (jetpacs-defapp glasspane-owner
                  :label glasspane-title
                  :icon glasspane-icon
                  :surfaces (list glasspane-owner)
                  :dock #'glasspane--dock-items
                  ;; S1: the same destination table the hub renders,
                  ;; CONTRIBUTED to the host — its rows open through
                  ;; the global app.open `:route', so the verbs stay
                  ;; owner-scoped (no :any-surface).
                  :destinations #'glasspane--destinations)
  ;; The CREATED/MODIFIED stampers are GLOBAL org hooks, so they attach
  ;; at app enable — never at glasspane-org's load (a bare `require'
  ;; must not mutate the user's `before-save-hook').  Teardown of this
  ;; owner detaches them; install self-registers that removal.  The
  ;; The disabled clock rollback adapter follows the same rule.  Native
  ;; chronometer hooks live in the upstream Org Mode app; every downstream
  ;; sibling verb registers through here, never at module load.
  (glasspane-org-install-hooks)
  (glasspane-clock-install-hooks)
  (glasspane-config-register)
  (glasspane-packages-register)
  (glasspane-ui-register)
  (glasspane-org-reader-register)
  (glasspane-detail-register)
  (glasspane-agenda-register)
  (glasspane-projects-register)
  (glasspane-areas-register)
  (glasspane-resources-register)
  (glasspane-journal-register)
  (glasspane-capture-register)
  (glasspane-views-register)
  (glasspane-search-register)
  (glasspane-table-register)
  (glasspane-notes-register)
  (glasspane-srs-register)
  (glasspane-demo-register)
  (glasspane-ef-register)
  (glasspane-gallery-register))

(defun glasspane-unregister ()
  "Deregister every downstream verb, the chrome root, and app identity.
The G0 gate contract: no Glasspane handler or claim survives this.  Native
Org clock handlers are upstream and deliberately survive."
  (jetpacs-undefaction "glasspane.home")
  (jetpacs-apps-unregister glasspane-owner)
  (jetpacs-chrome-remove glasspane-owner)
  ;; The live-reload/unload path: teardown of the owner would detach
  ;; the org stampers too, but unregister must not leave them behind
  ;; when no teardown ever runs (M-x unload-feature).
  (glasspane-org-remove-hooks)
  (glasspane-clock-remove-hooks)
  (glasspane-config-unregister)
  (glasspane-packages-unregister)
  (glasspane-ui-unregister)
  (glasspane-org-reader-unregister)
  (glasspane-detail-unregister)
  (glasspane-agenda-unregister)
  (glasspane-projects-unregister)
  (glasspane-areas-unregister)
  (glasspane-resources-unregister)
  (glasspane-journal-unregister)
  (glasspane-capture-unregister)
  (glasspane-views-unregister)
  (glasspane-search-unregister)
  (glasspane-table-unregister)
  (glasspane-notes-unregister)
  (glasspane-srs-unregister)
  (glasspane-demo-unregister)
  (glasspane-ef-unregister)
  (glasspane-gallery-unregister))

(glasspane-register)

;; App-private managed configuration is downstream policy, so the app loads it
;; itself instead of relying on the Jetpacs composition root to know this app
;; exists.  Batch loads stay side-effect-free for byte compilation and ERT.
(unless noninteractive
  (glasspane-config-ensure))

;;;###autoload
(defun glasspane ()
  "Open Glasspane on the device: reset its stack to the home screen."
  (interactive)
  (jetpacs-chrome-reset-screens glasspane-owner))

(defun glasspane-unload-function ()
  "Unload hygiene: drop the verbs, the chrome root, and the identity."
  (glasspane-unregister)
  nil)

(provide 'glasspane)
;;; glasspane.el ends here
