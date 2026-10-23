;;; glasspane.el --- Glasspane: org knowledge on Jetpacs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The v3 rebuild of the v1 reference app — notes, agenda, capture,
;; journal, SRS, the org reader — on the jetpacs foundation.  The
;; ladder is docs/PLAN-glasspane-app.md; this file is G0: the thin
;; entry in the M3 template (jetpacs-m3-catalog.el), owning exactly the
;; app identity — the "glasspane" owner claim, the Agenda chrome root, the
;; PA-3 primary composition metadata, and one owner verb,
;; `glasspane.home', which resets to that root.  The sibling `require'
;; list below grew one rung at a time and is now the whole app.
;;
;; Client hooks (clock notification, window class, save refresh) attach
;; at READY starting with G2 — G0 registers surfaces and verbs only,
;; which is connection-independent by design (`jetpacs-defaction' and
;; `jetpacs-chrome-define-root' are registries, not pushes).
;;
;; `require' only loads: nothing registers at load.  The `glasspane'
;; command or the Apps screen activates the app.  A desktop init that
;; loads Glasspane adds `(glasspane-register)' after the `require'.

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
(require 'jetpacs-material3)
(require 'jetpacs-apps)

;; The rung ladder's sibling modules, in the plan's load order (G1: the
;; data layer).  glasspane-vulpea is the extractor's worker-lib —
;; definitions only, safe to load with vulpea absent; registration
;; happens where vulpea is DETECTED (glasspane-org's load tail, G2's
;; packages light-up), never here.
(require 'glasspane-org)
(require 'glasspane-vulpea)
;; G2, the services: packages soft-requires config's dir seam, so config
;; loads first and its helper wins.
(require 'glasspane-config)
(require 'glasspane-packages)
;; G3, the keystone: the settings surface, the shared view state, and
;; the at-ref funnel.  Requires glasspane-org, so it loads last.
(require 'glasspane-ui)
;; G4/GR-2, the reader + detail: the reader replaces the reusable host's
;; Org adapter slot and owns the refile list.  Navigation then fixes the one
;; canonical Files-backed document route that detail and every later entry
;; point share; detail still degrades when the reader itself is absent.
(require 'glasspane-org-reader)
(require 'glasspane-navigation)
(require 'glasspane-detail)
;; G5 plus the PARA screens: the foundation date helper supports both daily
;; halves; agenda, Projects, and journal build on detail's shared card and the
;; reader (already above).
(require 'jetpacs-dates)
(require 'glasspane-agenda)
(require 'glasspane-projects)
(require 'glasspane-areas)
(require 'glasspane-resources)
(require 'glasspane-journal)
;; G6, the query surfaces: views leans on the reader's reorder table
;; and the agenda's shared date row, so it loads after both; search
;; depends only on landed G1/G3/G4 modules — the plan's order.  The
;; table/Babel verbs are upstream now (jetpacs-org-table.el).
(require 'glasspane-views)
(require 'glasspane-search)
;; G7, the knowledge arms: srs soft-requires notes (the Review screen's
;; stale-files half calls its section builder), so notes loads first.
;; Both degrade to absent without vulpea/org-srs — the requires are
;; unconditional, the runtime probes are theirs.
(require 'glasspane-notes)
(require 'glasspane-srs)
;; EF is a Glasspane package opinion contributed to Jetpacs' Modus-family Theme
;; Settings registry.  The generic widget gallery remains Jetpacs-owned.
(require 'glasspane-ef)
(require 'glasspane-demo)

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
  "Return PARAMS' surface to the root screen on the dock row's second tap."
  (let ((surface (plist-get params :surface)))
    (jetpacs-apps-note-route glasspane-owner "agenda")
    (jetpacs-flow-continue
     (lambda ()
       (jetpacs-chrome-reset-screens (or surface glasspane-owner))))
    'accepted))

;;;; App identity

(defun glasspane--destinations ()
  "Return the app's S1 route registry from `glasspane-ui-destinations'."
  glasspane-ui-destinations)

(defun glasspane-register ()
  "Register the owner's verbs, the chrome root, and the app identity.
Idempotent: re-evaluation replaces the handlers and RESETS the screen
stack to the selected app root — the live-reload path; `jetpacs-defapp'
replaces its registry entry in place.  Declares `jetpacs.material3'
explicitly; see RENDERER.org."
  (with-jetpacs-owner glasspane-owner
    (jetpacs-defaction "glasspane.home" #'glasspane--on-home
                       :doc "Return Glasspane to its registered root screen")
    ;; PA-3b pins Agenda as both app home and destination one.  Its root id
    ;; deliberately equals agenda.open's pushed id, so a bar tap truncates
    ;; straight to the root.
    (jetpacs-chrome-define-root glasspane-owner "glasspane-agenda"
                                #'glasspane-agenda-screen
                                :required t))
  ;; After the root exists: the app claims a surface that is really there.
  (jetpacs-defapp glasspane-owner
                  :label glasspane-title
                  :icon glasspane-icon
                  :surfaces (list glasspane-owner)
                  :requires-extensions '("jetpacs.material3")
                  ;; PA-3a: Glasspane owns the full five-item bar.  Eval
                  ;; is the one native core place it relocates; Files is
                  ;; replaced by the downstream Resources destination.
                  :chrome 'primary
                  :dock-core nil
                  :drawer-core '("eval")
                  :fab #'glasspane-ui-capture-fab
                  ;; Glasspane alone decides that its root represents
                  ;; Agenda.  Jetpacs only consumes this generic route
                  ;; metadata when a deep link falls back to the root.
                  :home-route "agenda"
                  ;; The table is CONTRIBUTED to the host.  Rows open
                  ;; through global app.open, so their verbs stay scoped
                  ;; to Glasspane's own surface.
                  :destinations #'glasspane--destinations)
  ;; The CREATED/MODIFIED stampers are GLOBAL org hooks, so they attach
  ;; at app enable — never at glasspane-org's load (a bare `require'
  ;; must not mutate the user's `before-save-hook').  They are ledgered
  ;; under this owner, so its teardown detaches them.  Native
  ;; chronometer and capture handlers live in the upstream Org Mode app;
  ;; every downstream sibling verb registers through here, never at
  ;; module load.
  (glasspane-org-install-hooks)
  (glasspane-config-register)
  (glasspane-packages-register)
  (glasspane-ui-register)
  (glasspane-org-reader-register)
  (glasspane-navigation-register)
  (glasspane-detail-register)
  (glasspane-agenda-register)
  (glasspane-projects-register)
  (glasspane-areas-register)
  (glasspane-resources-register)
  (glasspane-journal-register)
  (glasspane-views-register)
  (glasspane-search-register)
  (glasspane-notes-register)
  (glasspane-srs-register)
  (glasspane-ef-register)
  (glasspane-demo-register))

(defun glasspane-unregister ()
  "Unregister Glasspane: the app's whole teardown, then its private state.
`jetpacs-apps-unregister' tears down everything attributed to the
owner: every verb, the chrome root, ledgered hooks (the Org stampers
included), the reader and editor adapters (the stock Org reader comes
back), settings rows, the theme provider, the dialog slot and the app
entry.  The module unregisters below reset only state those modules
hold.  Native Org clock and capture handlers are upstream and
deliberately survive."
  (jetpacs-apps-unregister glasspane-owner)
  (glasspane-ui-unregister)
  (glasspane-org-reader-unregister)
  (glasspane-views-unregister)
  (glasspane-notes-unregister)
  (glasspane-srs-unregister))

;; App-private managed configuration is downstream policy, so the app loads it
;; itself instead of relying on the Jetpacs composition root to know this app
;; exists.  Batch loads stay side-effect-free for byte compilation and ERT.
(unless noninteractive
  (glasspane-config-ensure))

;;;###autoload
(defun glasspane ()
  "Open Glasspane on the device: register it, reset its stack to the root.
Registration is idempotent, so the command is also how a desktop user
activates the app."
  (interactive)
  (glasspane-register)
  (jetpacs-apps-note-route glasspane-owner "agenda")
  (jetpacs-chrome-reset-screens glasspane-owner))

(defun glasspane-unload-function ()
  "Unload hygiene: drop the verbs, the chrome root, and the identity."
  (glasspane-unregister)
  nil)

(provide 'glasspane)
;;; glasspane.el ends here
