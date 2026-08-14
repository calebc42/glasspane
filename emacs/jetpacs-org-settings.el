;;; jetpacs-org-settings.el --- The org/calendar settings sections -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The ratified settings relocation (docs/PLAN-jetpacs-debt-and-scaffold
;; §3, step 1 + the step-4 ruling): the schema-driven org sections
;; Glasspane's G6 rung used to register — Org Workflow, Org Agenda, Org
;; Editing & Display, User Defaults, Calendar & Location, and the
;; reader's two Reader rows — are foundation content, because every
;; symbol in them is a built-in or foundation defcustom.  Only the babel
;; timeout was app opinion; it stays with the app.  `jetpacs-' prefix by
;; the 2026-08-06 naming rule: this module renders companion widgets
;; (through jetpacs-settings) and writes a floor registry.
;;
;; Registration happens at LOAD, never behind an app's register gate —
;; the device/init.el curated-block rule: a queued toggle can replay
;; before any screen renders, so the sections (and the state.changed
;; handlers registration installs for their boolean switches) must
;; exist from boot.
;;
;; The one redesigned seam: `:after-set' is foundation-owned now and
;; calls `ebp-org-cache-invalidate' with NO namespace.  Dropping the
;; whole memo table is deliberately broader than the app's old
;; per-namespace bust — a settings write over org/calendar state stales
;; EVERY consumer's org-derived views, not just the writer's, and a
;; full drop is benign: the next render recomputes.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'ebp-org)                      ; the memo table + ebp-org-roots
(require 'jetpacs-settings)

;;;; The after-set seam

(defun jetpacs-org-settings-after-set (_sym _value)
  "Registry `:after-set' for org/calendar-derived entries.
Org-derived views are memoised (`ebp-org-with-cache'), so a settings
write over their inputs must drop the memo or the device keeps
rendering stale data.  No namespace on purpose: the write stales every
consumer's extractions, not just one app's, and the whole-table drop
is benign — the next render recomputes."
  (ebp-org-cache-invalidate))

;;;; The sections

(defun jetpacs-org-settings-sections ()
  "The schema-driven org/calendar sections as (TITLE . ENTRIES).
The registry is the security boundary: only symbols listed here can be
modified from the wire.  Every org/calendar entry carries the
after-set memo-buster; the user-identity rows feed no memoised
extraction and stay bare.  `ebp-org-roots' and
`org-default-notes-file' are the relocation plan's two previously
unsurfaced foundation rows — the roots gate every bridge resolve, and
the notes file is where phone capture lands, so both bust the memo."
  (cl-flet ((org-entry (sym label)
              (list sym :label label
                    :after-set #'jetpacs-org-settings-after-set))
            (plain (sym label) (list sym :label label)))
    (list
     (cons "Org Workflow"
           (list (org-entry 'org-directory "Org directory")
                 (org-entry 'org-default-notes-file "Default notes file")
                 (org-entry 'ebp-org-roots "Bridge org roots")
                 (org-entry 'org-log-done "Log task completion")
                 (org-entry 'org-log-into-drawer "Log into drawer")
                 (org-entry 'org-archive-location "Archive location")))
     (cons "Org Agenda"
           (list (org-entry 'org-agenda-span "Agenda span")
                 (org-entry 'org-deadline-warning-days
                            "Deadline warning days")
                 (org-entry 'org-extend-today-until
                            "Extend today until (hour)")))
     (cons "Org Editing & Display"
           (list (org-entry 'org-startup-folded "Initial folding")
                 (org-entry 'org-startup-indented "Indent to outline level")
                 (org-entry 'org-hide-emphasis-markers
                            "Hide emphasis markers")
                 (org-entry 'org-return-follows-link "Enter follows links")))
     (cons "User Defaults"
           (list (plain 'user-full-name "Author (Name)")
                 (plain 'user-mail-address "Email")))
     (cons "Calendar & Location"
           (list (org-entry 'calendar-week-start-day
                            "Week start day (0=Sun, 1=Mon)")
                 (org-entry 'calendar-latitude "Latitude (e.g. 40.7)")
                 (org-entry 'calendar-longitude
                            "Longitude (e.g. -74.0)")))
     (cons "Reader"
           (list (org-entry 'ebp-org-outline-show-deadline
                            "Deadline on headings")
                 (org-entry 'ebp-org-outline-show-clocked
                            "Clocked time on headings"))))))

(defun jetpacs-org-settings-register ()
  "Register (or replace) every org/calendar section.
Idempotent — sections replace in place; called at this file's load so
a queued toggle replays through handlers that registration, not
rendering, installs."
  (dolist (section (jetpacs-org-settings-sections))
    (jetpacs-settings-register-section (car section) (cdr section))))

;;;; Load effects

(jetpacs-org-settings-register)

(defun jetpacs-org-settings-unload-function ()
  "Unload hygiene: drop the sections this module registered."
  (dolist (section (jetpacs-org-settings-sections))
    (jetpacs-settings-remove-section (car section)))
  nil)

(provide 'jetpacs-org-settings)
;;; jetpacs-org-settings.el ends here
