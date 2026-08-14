;;; jetpacs-org-settings.el --- The org/calendar settings sections + seeding -*- lexical-binding: t; -*-

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
;;
;; The seeding tail is the step-4 ruling: the phone-generic half of
;; Glasspane's managed org-defaults.el (the inbox capture target while
;; `org-default-notes-file' is still org's stock ~/.notes, the
;; org-directory mkdir, the agenda-files fallback, the LOGBOOK drawer,
;; babel languages) seeds HERE at load, each arm guarded so a
;; customized or already-divergent value is never touched.  Capture
;; templates are NOT here — they stay Glasspane's opinion, in its
;; managed config subtree.  The load-time call is interactive-only (the
;; glasspane-config precedent): a batch load must not mkdir the
;; runner's `org-directory' or pull babel language files.

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

;;;; Seeding (step 4: the phone-generic org wiring)

(defun jetpacs-org-settings-seed ()
  "Seed the phone-generic org wiring, only where still at stock values.
The step-4 content of Glasspane's managed org-defaults.el, foundation-
owned now.  Every arm is guarded, which also makes the call idempotent
— after one pass each guard turns false:
- capture lands in an inbox inside `org-directory', only while
  `org-default-notes-file' is still org's stock ~/.notes;
- `org-directory' must exist or that inbox can never be created;
- a device agenda needs agenda files, so an empty list falls back to
  the whole org directory;
- state changes and clocks go into LOGBOOK drawers (heading detail
  views render them as a structured section), unless the option was
  already moved off its standard value;
- the babel languages a phone run button executes, unless the language
  list was already curated — the button only appears for loaded
  languages."
  (when (equal org-default-notes-file
               (convert-standard-filename "~/.notes"))
    (setopt org-default-notes-file
            (expand-file-name "inbox.org" org-directory)))
  (make-directory org-directory t)
  (unless org-agenda-files
    (setopt org-agenda-files (list org-directory)))
  (unless (jetpacs-settings-modified-p 'org-log-into-drawer)
    (setopt org-log-into-drawer t))
  (unless (jetpacs-settings-modified-p 'org-babel-load-languages)
    (org-babel-do-load-languages
     'org-babel-load-languages
     '((emacs-lisp . t) (shell . t) (python . t)))))

;;;; Load effects

(jetpacs-org-settings-register)

;; Interactive-only, the glasspane-config.el precedent: a batch load
;; (the ERT suites, byte-compile closure walks) runs under the REAL
;; HOME and would mkdir `org-directory' and load babel language files
;; there.  The device Emacs and the desktop daemon are both
;; interactive, so the path that needs seeding is unaffected; batch
;; callers that want the defaults call `jetpacs-org-settings-seed'
;; themselves.
(unless noninteractive
  (jetpacs-org-settings-seed))

(defun jetpacs-org-settings-unload-function ()
  "Unload hygiene: drop the sections this module registered."
  (dolist (section (jetpacs-org-settings-sections))
    (jetpacs-settings-remove-section (car section)))
  nil)

(provide 'jetpacs-org-settings)
;;; jetpacs-org-settings.el ends here
