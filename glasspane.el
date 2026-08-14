;;; glasspane.el --- Glasspane: org knowledge on Jetpacs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The v3 rebuild of the v1 reference app — notes, agenda, capture,
;; journal, SRS, the org reader — on the jetpacs foundation.  The
;; ladder is docs/PLAN-glasspane-app.md; this file is G0: the thin
;; entry in the M3 template (jetpacs-m3-catalog.el), owning exactly the
;; app identity — the "glasspane" owner claim, the chrome root (a
;; placeholder home until the later rungs' screens give a hub
;; something to point at — v1's ui was tab fabric and had none), the
;; dock destination, and one owner verb.  The sibling `require' list below
;; grows one rung at a time; nothing here reaches for org yet.
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
;; G4, the reader + detail: the reader claims the files body seam and
;; owns the refile list; detail requires it softly, so it loads first.
(require 'glasspane-org-reader)
(require 'glasspane-detail)
;; G5, the daily surfaces: dates is the pure helper both halves lean
;; on, agenda and journal build on detail's shared card and the reader
;; (already above), capture is verbs + sheets only.
(require 'glasspane-dates)
(require 'glasspane-agenda)
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

(defconst glasspane-owner "glasspane"
  "The D1 owner whose surface hosts the app.
Not under `jetpacs-reserved-owner-prefix': Glasspane is a Tier-1
application, not base chrome — the M3 catalog's precedent, and the
second real `jetpacs-defapp' caller there is.")

(defconst glasspane-title "Glasspane"
  "The home top-bar title and the dock label.")

(defconst glasspane-icon "menu_book"
  "The dock/launcher icon.  A knowledge base is a book you keep open.")

;;;; The placeholder home (a later rung's hub replaces this builder)

(defun glasspane-home-screen (back)
  "The G0 root screen: the identity, and the ladder's own state.
Exists so registration, the dock, and `M-x glasspane' have a real
screen behind them from the first rung.  v1 had no home to port — its
ui was tab fabric (S1-retired) — so the placeholder stands until the
later rungs' screens give a hub something to point at; swapping the
builder then must not change the registration's shape."
  (jetpacs-chrome-screen
   glasspane-title
   (jetpacs-column
    (jetpacs-text "Glasspane" :style "headline")
    (jetpacs-text "Org knowledge on Jetpacs — rebuild in progress."
                  :style "body")
    (jetpacs-text "Ladder: docs/PLAN-glasspane-app.md (G0 landed)."
                  :style "label" :color "muted")
    :spacing 8)
   :back back))

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
                :on-tap (jetpacs-action "jetpacs.launcher.open"
                                        :args (list :surface home))
                :selected (equal surface home)))))

(defun glasspane-register ()
  "Register the owner's verbs, the chrome root, and the app identity.
Idempotent: re-evaluation replaces the handlers and RESETS the screen
stack to home — the live-reload path; `jetpacs-defapp' replaces its
registry entry in place."
  (with-jetpacs-owner glasspane-owner
    (jetpacs-defaction "glasspane.home" #'glasspane--on-home)
    (jetpacs-chrome-define-root glasspane-owner "home"
                                #'glasspane-home-screen))
  ;; After the root exists: the app claims a surface that is really
  ;; there, and its dock destination names one the launcher's
  ;; membership guard recognizes (the M3 ordering).
  (jetpacs-defapp glasspane-owner
                  :label glasspane-title
                  :icon glasspane-icon
                  :surfaces (list glasspane-owner)
                  :dock #'glasspane--dock-items)
  ;; The CREATED/MODIFIED stampers are GLOBAL org hooks, so they attach
  ;; at app enable — never at glasspane-org's load (a bare `require'
  ;; must not mutate the user's `before-save-hook').  Teardown of this
  ;; owner detaches them; install self-registers that removal.  The
  ;; clock mirror's org-clock/READY hooks follow the same rule — and
  ;; every sibling VERB registers through here too, never at module
  ;; load, so `glasspane-unregister' can sweep what only this pair
  ;; creates and restore it without a re-require.
  (glasspane-org-install-hooks)
  (glasspane-clock-install-hooks)
  (glasspane-config-register)
  (glasspane-packages-register)
  (glasspane-ui-register)
  (glasspane-org-reader-register)
  (glasspane-detail-register)
  (glasspane-agenda-register)
  (glasspane-journal-register)
  (glasspane-capture-register)
  (glasspane-views-register)
  (glasspane-search-register)
  (glasspane-table-register)
  (glasspane-notes-register)
  (glasspane-srs-register))

(defun glasspane-unregister ()
  "Deregister every verb, the chrome root, and the app identity.
The G0 gate contract: no glasspane handler and no claim survives this
— the sibling modules' verbs (clock's org.clock.*, config.sync,
glasspane.packages.install) sweep with the entry's own."
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
  (glasspane-journal-unregister)
  (glasspane-capture-unregister)
  (glasspane-views-unregister)
  (glasspane-search-unregister)
  (glasspane-table-unregister)
  (glasspane-notes-unregister)
  (glasspane-srs-unregister))

(glasspane-register)

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
