;;; jetpacs-org.el --- The org engine's registration with the floor -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; This file exports nothing.  It exists for its LOAD EFFECT, and the
;; effect is two lines: the org engine's token sweep is registered on the
;; floor's teardown hook, and the engine's reset on the floor's reset
;; hook.

;; The engine itself is `ebp-org.el' now (docs/PLAN-ebp-org-split.md,
;; G6 + G7).  By the rule ratified 2026-08-06 — `jetpacs-' names what
;; cannot exist without Kotlin, Android, and Compose; `ebp-' names what
;; only ever touches the wire and Emacs — every line of it was `ebp-'
;; work: org is built-in Emacs, a heading is a buffer position, and the
;; refusal vocabulary is SPEC 14.4/14.5 wire.  Call `ebp-org-' names
;; directly; there are no aliases here and there will not be any.

;; What is left is the one thing the engine genuinely could not do for
;; itself.  `jetpacs-teardown-functions' and `jetpacs-reset-functions'
;; are floor state — they live with owners, actions and surfaces — while
;; `ebp-org-teardown-owner' and `ebp-org-reset' are engine machinery that
;; answers to an opaque scope key and reads nothing of the floor at all.
;; Neither file may require the other's world, so the add-hook is a THIRD
;; thing: an adapter, and this is it.

;; The reset registration is the newer of the two and arrives by the same
;; rule.  The floor used to reach the engine through an `fboundp' probe
;; on the name `ebp-org-reset' — a bridge that fails SILENT, since a
;; probe finding nothing does not complain.  Now the hook carries it and
;; the membership is assertable.  What did NOT change is which file may
;; write the add-hook: an `ebp-' file may not name a `jetpacs-' symbol at
;; all, and the delineation guard loads `emacs/ebp-org.el' alone to prove
;; it, so the registration is HERE or it is nowhere.

;; Consequence, deliberate and recorded in the plan: requiring
;; `jetpacs-org-render' no longer drags the registration in, because
;; render requires only the engine.  The registration arrives with
;; `jetpacs-org-dialogs' and `jetpacs-org-habits', which require this
;; file for exactly that reason and say so at their require lines.  On
;; device, `device/init.el' loads org-render and org-habits, so the hook
;; is installed there by the habits path.

;;; Code:

(require 'ebp-org)
(require 'jetpacs-surfaces)             ; both floor hooks live here

(add-hook 'jetpacs-teardown-functions #'ebp-org-teardown-owner)
(add-hook 'jetpacs-reset-functions #'ebp-org-reset)

(defun jetpacs-org-unload-function ()
  "Unload hygiene: take back the registrations, and only those.
The engine's own tables are `ebp-org-unload-function's business."
  (remove-hook 'jetpacs-teardown-functions #'ebp-org-teardown-owner)
  (remove-hook 'jetpacs-reset-functions #'ebp-org-reset)
  nil)

(provide 'jetpacs-org)
;;; jetpacs-org.el ends here
