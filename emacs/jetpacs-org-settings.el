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
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
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

;;;; The org-workflow editors (§3 step 2: TODO sequences + global tags)
;;
;; Managed-UI settings the schema registry cannot express: a LIST of
;; TODO sequences edited through a dialog, and the tag vocabulary as an
;; editable chip set.  Moved from Glasspane's G3/G5 rungs — every
;; symbol they manage is org's own.  The verbs register OWNERLESS at
;; load (the settings.set precedent), which is what dissolves the
;; app-era `:any-surface' dance: the editors draw on the Settings root
;; and their events arrive from whatever surface composed it (or from
;; dialog context, which carries no surface at all), and an ownerless
;; handler is gate-exempt on both.

;;;; TODO keyword helpers (pure)

(defun jetpacs-org-settings--bare-keyword (word)
  "WORD without its fast-access annotation: \"TODO(t!)\" -> \"TODO\"."
  (if (string-match "^\\([a-zA-Z0-9_-]+\\)" word)
      (match-string 1 word)
    word))

(defun jetpacs-org-settings-global-todo-keywords ()
  "Flat list of all global TODO keywords from `org-todo-keywords'.
Public: task-filter chips (glasspane-agenda) build from it too."
  (let ((kws nil))
    (dolist (seq (default-value 'org-todo-keywords))
      (dolist (w (cdr seq))
        (unless (string-equal w "|")
          (push (jetpacs-org-settings--bare-keyword w) kws))))
    (nreverse kws)))

(defun jetpacs-org-settings--split-todo-sequence (seq)
  "Split `org-todo-keywords' entry SEQ into (ACTIVE . FINISHED) lists.
Keywords keep their fast-access annotations (\"TODO(t!)\").  Mirrors
org's rule for sequences without an explicit \"|\": the last keyword
is the finished state."
  (let ((words (cdr seq))
        (active nil)
        (finished nil)
        (target 'active))
    (dolist (w words)
      (if (equal w "|")
          (setq target 'finished)
        (if (eq target 'active)
            (push w active)
          (push w finished))))
    (setq active (nreverse active)
          finished (nreverse finished))
    (when (and (null finished) (not (member "|" words)))
      (setq finished (last active)
            active (butlast active)))
    (cons active finished)))

(defun jetpacs-org-settings--parse-keywords (s)
  "Comma-separated keyword string S as a clean list; nil when empty."
  (and (stringp s)
       (delq nil (mapcar (lambda (x)
                           (let ((x (string-trim x)))
                             (unless (string-empty-p x) x)))
                         (split-string s ",")))))

(defun jetpacs-org-settings--todo-keywords-apply (seqs)
  "Make SEQS the effective and persisted `org-todo-keywords'.
Live org buffers cache the keywords buffer-locally at mode init
(`org-todo-keywords-1', `org-todo-regexp', ...), so each one is
restarted, and the whole org memo is dropped — the foundation seam's
rule: new states stale EVERY consumer's task views, not one app's.
Returns non-nil when persisting succeeded."
  (prog1 (jetpacs-settings-save-variable 'org-todo-keywords seqs)
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (derived-mode-p 'org-mode)
          (ignore-errors (org-mode-restart)))))
    (ebp-org-cache-invalidate)))

;;;; Tag vocabulary

(defun jetpacs-org-settings-tag-options ()
  "The global tag names from `org-tag-alist', strings only, distinct.
Public: the workflow chip list here and Glasspane's detail-view tag
picker both build from the same vocabulary.
Group markers (`:startgroup' and friends) are cons-free symbols the
enum cannot carry; duplicates would fail the widget's SPEC 4.3
distinctness check at build time."
  (cl-remove-duplicates
   (cl-remove-if-not #'stringp
                     (mapcar (lambda (x) (if (consp x) (car x) x))
                             org-tag-alist))
   :test #'equal :from-end t))

(defun jetpacs-org-settings--tags-enum ()
  "The editable global-tags chip list."
  (let ((tags (jetpacs-org-settings-tag-options)))
    (jetpacs-enum-list "org-tags"
                       (mapcar (lambda (tg) (jetpacs-enum-option tg tg))
                               tags)
                       :value tags
                       :multi-select t
                       :allow-add t
                       :on-change (jetpacs-action "jetpacs.org.tags"))))

;;;; The sequence cards + editor dialog

(defun jetpacs-org-settings--sequence-cards ()
  "One card per global TODO sequence, with edit/delete affordances.
The error arm costs the section, never the screen — and shows the
SPEC 23.3 label, not the raw error text."
  (condition-case err
      (cl-loop for seq in (or (default-value 'org-todo-keywords)
                              '((sequence "TODO" "DONE")))
               for i from 0
               collect
               (let* ((split (jetpacs-org-settings--split-todo-sequence seq))
                      (active (mapcar #'jetpacs-org-settings--bare-keyword
                                      (car split)))
                      (finished (mapcar #'jetpacs-org-settings--bare-keyword
                                        (cdr split))))
                 (jetpacs-card
                  (list
                   (jetpacs-row
                    (jetpacs-with-attrs
                     (jetpacs-column
                      (jetpacs-text (format "Sequence %d" (1+ i))
                                    :style "label")
                      (jetpacs-text
                       (concat (mapconcat #'identity active ", ")
                               " | "
                               (mapconcat #'identity finished ", "))
                       :style "body")
                      :spacing 2)
                     :weight 1)
                    (jetpacs-icon-button
                     "edit"
                     (jetpacs-action "jetpacs.org.todo.edit"
                                     :args (list :index i))
                     :content-description "Edit sequence")
                    (jetpacs-icon-button
                     "delete"
                     (jetpacs-action "jetpacs.org.todo.delete"
                                     :args (list :index i))
                     :content-description "Delete sequence")
                    :align "center")))))
    (error (list (jetpacs-text (format "Error loading sequences: %s"
                                       (jetpacs-error-label err))
                               :style "caption")))))

(defun jetpacs-org-settings--show-todo-dialog (idx params)
  "Show the TODO-sequence editor for sequence IDX (-1 = new).
The sequence is re-read HERE, not in the dispatching handler: the
show runs deferred, and the list may have changed in between."
  (let* ((seqs (or (default-value 'org-todo-keywords)
                   '((sequence "TODO" "DONE"))))
         (seq (if (>= idx 0) (nth idx seqs) '(sequence "TODO" "|" "DONE"))))
    (if (null seq)
        (jetpacs-toast "That sequence no longer exists")
      ;; Raw keyword strings, fast-access keys and all ("TODO(t!)"),
      ;; so an untouched save round-trips losslessly.  Seeding is the
      ;; field's `:value' (S2): no state round-trip — the Save action
      ;; captures the fields and echoes them back in its event.
      (let* ((type (car seq))
             (split (jetpacs-org-settings--split-todo-sequence seq))
             (active (mapconcat #'identity (car split) ", "))
             (finished (mapconcat #'identity (cdr split) ", ")))
        (jetpacs-settings-show-dialog
         "jetpacs-org-todo-edit"
         (apply #'jetpacs-column
                (append
                 (list
                  (jetpacs-text (if (>= idx 0) "Edit Sequence" "New Sequence")
                                :style "title")
                  (jetpacs-text
                   "Comma-separated states; fast keys like TODO(t) are kept."
                   :style "caption")
                  (jetpacs-text-input "todo-active" :label "Active States"
                                      :value active :single-line t)
                  (jetpacs-text-input "todo-finished"
                                      :label "Finished States"
                                      :value finished :single-line t)
                  (apply #'jetpacs-row
                         (append
                          (list (jetpacs-spacer :weight 1))
                          (when (>= idx 0)
                            (list (jetpacs-button
                                   "Delete"
                                   (jetpacs-action "jetpacs.org.todo.delete"
                                                   :args (list :index idx))
                                   :variant "text")))
                          (list (jetpacs-button "Cancel"
                                                (jetpacs-dialog-dismiss)
                                                :variant "text")
                                (jetpacs-spacer :width 8)
                                (jetpacs-button
                                 "Save"
                                 (jetpacs-action
                                  "jetpacs.org.todo.save"
                                  :args (list :index idx
                                              :type (symbol-name type))
                                  :capture-fields '("todo-active"
                                                    "todo-finished")))))))
                 (list :spacing 8)))
         :params params)))))

;;;; The Org-workflow satellite screen

(defun jetpacs-org-settings--workflow-body ()
  "The managed org-workflow screen body: sequences, then tags.
lazy_column, not column: the scaffold body has no scroll container on
the client, and the sequence list grows without bound."
  (apply #'jetpacs-lazy-column
         (append
          (list (jetpacs-section-header "Global TODO Sequences")
                (jetpacs-text
                 "Manage your global TODO states and workflows."
                 :style "caption"))
          (jetpacs-org-settings--sequence-cards)
          (list (jetpacs-button "Add Sequence"
                                (jetpacs-action "jetpacs.org.todo.edit"
                                                :args (list :index -1))
                                :variant "outlined")
                (jetpacs-divider)
                (jetpacs-section-header "Global Org Tags")
                (jetpacs-text
                 "Manage the global tag list (org-tag-alist)."
                 :style "caption")
                (jetpacs-org-settings--tags-enum)))))

(defun jetpacs-org-settings--workflow-screen (back)
  "The pushed Org-workflow screen."
  (jetpacs-chrome-screen "Org workflow"
                         (jetpacs-org-settings--workflow-body)
                         :back back))

(defun jetpacs-org-settings--link ()
  "The Settings-root satellite row leading to the workflow screen."
  (jetpacs-chrome-row "Org workflow"
                      :subtitle "TODO sequences, global org tags"
                      :icon "checklist"
                      :on-tap (jetpacs-action "jetpacs.org.workflow.open")
                      :key "jetpacs-org-workflow-link"))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun jetpacs-org-settings--on-workflow-open (_args params)
  "Push the org-workflow screen onto the tapped surface."
  (let ((surface (or (plist-get params :surface)
                     jetpacs-settings-surface)))
    (jetpacs-flow-continue
     (lambda ()
       ;; A deferred `jetpacs-chrome-push-screen' must catch its own
       ;; re-signal or a refused gate dies in a timer.
       (condition-case err
           (jetpacs-chrome-push-screen surface "jetpacs-org-workflow"
                                       #'jetpacs-org-settings--workflow-screen)
         (error (message "jetpacs-org-settings: workflow push failed: %s"
                         (jetpacs-error-label err))))))
    'accepted))

(defun jetpacs-org-settings--on-tags (args _params)
  "Rebuild `org-tag-alist' from the multi-select `:value' (a vector).
Existing alist entries keep their fast-select keys.  Deselecting every
chip sends a well-formed empty vector and writes nothing (the v1
contract — clearing every chip is not a bulk delete): that is
`accepted', with the refresh re-seeding the chips from the untouched
alist; `rejected' is reserved for non-sequence junk and non-string
members."
  (let ((val (plist-get args :value)))
    (if (not (or (vectorp val) (proper-list-p val)))
        'rejected
      (let ((tags (append val nil)))
        (if (not (cl-every #'stringp tags))
            'rejected
          (when tags
            (setq org-tag-alist
                  (mapcar (lambda (tg) (or (assoc tg org-tag-alist) tg))
                          tags))
            (jetpacs-settings-save-variable 'org-tag-alist org-tag-alist)
            (jetpacs-shell-notify "Settings saved"))
          (jetpacs-settings-refresh)
          'accepted)))))

(defun jetpacs-org-settings--on-todo-edit (args params)
  "Open the sequence editor dialog for `:index' (-1 = new)."
  (let ((idx (plist-get args :index)))
    ;; A whole-valued integer can arrive as a float after the JSON
    ;; round trip (org.json emits the trailing .0).
    (when (numberp idx) (setq idx (truncate idx)))
    (cond
     ((not (integerp idx)) 'rejected)
     ((and (>= idx 0)
           (null (nth idx (or (default-value 'org-todo-keywords)
                              '((sequence "TODO" "DONE"))))))
      ;; The card outlived the list it was rendered from.
      (jetpacs-toast "That sequence no longer exists")
      (jetpacs-settings-refresh)
      'stale)
     ((null (jetpacs-client)) 'rejected)
     (t
      (jetpacs-flow-continue
       (lambda () (jetpacs-org-settings--show-todo-dialog idx params)))
      'accepted))))

(defun jetpacs-org-settings--close-dialog-and-refresh ()
  "Retire the live settings dialog and re-push the settings surface.
A Save/Delete fired from inside the dialog arrives in dialog context
with no `:surface' (SPEC 14.4); the workflow screen lives on the
settings surface, so the plain settings refresh re-renders it —
the app-era origin-params tracking has no successor here."
  (jetpacs-settings-dialog-close)
  (jetpacs-settings-refresh))

(defun jetpacs-org-settings--on-todo-save (args params)
  "Write one global TODO sequence from the editor dialog's capture.
`:index'/`:type' ride the Save action's args; the states arrive as
captured fields (S2/S3) — no ui-state round trip."
  (let* ((idx (plist-get args :index))
         (idx (if (numberp idx) (truncate idx) idx))
         (type (pcase (plist-get args :type)
                 ("sequence" 'sequence)
                 ("type" 'type)))
         (fields (plist-get params :fields))
         (active (jetpacs-org-settings--parse-keywords
                  (plist-get fields :todo-active)))
         (finished (jetpacs-org-settings--parse-keywords
                    (plist-get fields :todo-finished)))
         (seqs (copy-sequence (or (default-value 'org-todo-keywords)
                                  '((sequence "TODO" "DONE"))))))
    (cond
     ((or (not (integerp idx)) (null type)) 'rejected)
     ((and (null active) (null finished))
      (jetpacs-shell-notify "A sequence needs at least one state")
      'rejected)
     ((>= idx (length seqs))
      ;; Stale index: the list changed while the dialog was up.
      (jetpacs-shell-notify "Sequences changed underneath; reopen the editor")
      (jetpacs-org-settings--close-dialog-and-refresh)
      'stale)
     (t
      (let ((new-seq (append (list type) active
                             (when finished (cons "|" finished)))))
        (if (>= idx 0)
            (setcar (nthcdr idx seqs) new-seq)
          (setq seqs (append seqs (list new-seq))))
        (when (jetpacs-org-settings--todo-keywords-apply seqs)
          (jetpacs-shell-notify "TODO sequence saved"))
        (jetpacs-org-settings--close-dialog-and-refresh)
        'accepted)))))

(defun jetpacs-org-settings--on-todo-delete (args _params)
  "Delete the global TODO sequence at `:index'.
Fired from a workflow card or the edit dialog's Delete button."
  (let* ((idx (plist-get args :index))
         (idx (if (numberp idx) (truncate idx) idx))
         (seqs (or (default-value 'org-todo-keywords)
                   '((sequence "TODO" "DONE")))))
    (cond
     ((not (integerp idx)) 'rejected)
     ((or (< idx 0) (>= idx (length seqs)))
      ;; The card outlived the list it was rendered from.
      (jetpacs-shell-notify "Sequences changed underneath")
      (jetpacs-org-settings--close-dialog-and-refresh)
      'stale)
     (t
      (let ((rest (or (append (cl-subseq seqs 0 idx)
                              (cl-subseq seqs (1+ idx)))
                      ;; Org misbehaves with no keywords at all;
                      ;; deleting the last sequence falls back to the
                      ;; stock one.
                      '((sequence "TODO" "|" "DONE")))))
        (when (jetpacs-org-settings--todo-keywords-apply rest)
          (jetpacs-shell-notify "TODO sequence deleted"))
        (jetpacs-org-settings--close-dialog-and-refresh)
        'accepted)))))

;;;; Load effects

(jetpacs-org-settings-register)

;; The workflow verbs, OWNERLESS at load (the settings.set precedent):
;; no owner claim, no surface gate — exactly what lets the editors draw
;; on the Settings root and answer taps from whatever surface composed
;; it.  An offline-queued app-era verb (settings.todo.save &c.) answers
;; -32601-rejected after this upgrade; benign, its dialog is long gone.
(jetpacs-defaction "jetpacs.org.workflow.open"
                   #'jetpacs-org-settings--on-workflow-open
                   :doc "Open the managed org-workflow settings screen")
(jetpacs-defaction "jetpacs.org.tags" #'jetpacs-org-settings--on-tags)
(jetpacs-defaction "jetpacs.org.todo.edit"
                   #'jetpacs-org-settings--on-todo-edit)
(jetpacs-defaction "jetpacs.org.todo.save"
                   #'jetpacs-org-settings--on-todo-save)
(jetpacs-defaction "jetpacs.org.todo.delete"
                   #'jetpacs-org-settings--on-todo-delete)
(jetpacs-settings-add-link 50 #'jetpacs-org-settings--link)

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
  "Unload hygiene: drop the sections, verbs, and link this module owns."
  (dolist (section (jetpacs-org-settings-sections))
    (jetpacs-settings-remove-section (car section)))
  (dolist (verb '("jetpacs.org.workflow.open" "jetpacs.org.tags"
                  "jetpacs.org.todo.edit" "jetpacs.org.todo.save"
                  "jetpacs.org.todo.delete"))
    (jetpacs-undefaction verb))
  (setq jetpacs-settings-links
        (cl-remove #'jetpacs-org-settings--link jetpacs-settings-links
                   :key #'cadr))
  nil)

(provide 'jetpacs-org-settings)
;;; jetpacs-org-settings.el ends here
