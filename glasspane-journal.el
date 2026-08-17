;;; glasspane-journal.el --- Daily-note landing surface -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The Logseq bootstrapping habit, org-native: open the app -> today's
;; page, ready to type.  One datetree day at a time — capture row on
;; top, the day's content through the G4 foldable reader, and (on
;; today) a "Carried over" section of unfinished TODOs scheduled
;; before today with one-tap reschedule, plus the clock body (the v1
;; ruling: its own tab felt barren — today's time is journal matter).
;;
;; Engine decision unchanged from v1: plain `org-datetree' (builtin,
;; standard, importable — the file layout every journal tool
;; understands).  The seam is `glasspane-journal--append' /
;; `--day-pos', one code path either way if vulpea-journal ever lands.
;; The journal file defaults to journal.org in `org-directory'; nothing
;; is seeded until the first capture creates the datetree.
;;
;; Retired against v1 (docs/PLAN-glasspane-app.md, G5 + the retirement
;; list):
;;
;; - The `jetpacs-form' capture registry and its id-rotation clear
;;   trick ("jetpacs-form registry usage everywhere"): the input
;;   clears device-side via `:clear-on-submit' (S2).
;; - The tab fabric (`jetpacs-shell-define-view'/`-tab-view'/`:order')
;;   and its `:snackbar' thread: S1 — the journal is a pushed chrome
;;   screen behind `journal.open'; snackbars are foundation-owned
;;   (FOUNDATION-GAPS #13).
;; - The landing block's raw `jetpacs-shell--current-tab' seed and its
;;   connect-depth apology: obsolete — a push that lands in the
;;   SYNCING window becomes navigation debt the surface's next push
;;   re-asserts (jetpacs-shell.el, `--unasserted-view'), so landing is
;;   an ordinary screen push at READY.
;; - The `fboundp' guard on the clock body: it lives in landed G4
;;   (glasspane-detail) — a hard require now (T5 kills speculative
;;   guards).
;; - Explicit `:when-offline "drop"' (T4 — it is the default).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-datetree)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-settings)
(require 'jetpacs-dates)
(require 'glasspane-org)
(require 'glasspane-org-reader)
(require 'glasspane-ui)                 ; capture FAB
;; `glasspane-detail-clock-body' moved into the detail module in G4.
(require 'glasspane-detail)

(defcustom glasspane-journal-file nil
  "The journal file holding the datetree.
nil means journal.org inside `org-directory'."
  :type '(choice (const :tag "journal.org in org-directory" nil) file)
  :group 'jetpacs)

(defcustom glasspane-journal-landing nil
  "When non-nil the app opens on the Journal screen at session READY."
  :type 'boolean :group 'jetpacs)

(defconst glasspane-journal--screen-id "glasspane-journal"
  "The journal's chrome screen id — also what the view-change reset
matches, so navigation and state hygiene can never drift apart.")

(defconst glasspane-journal--ttl-s 86400
  "Offline ttl for queued capture/reschedule (T4): an entry composed
on the train must survive the commute, not a week of drift.")

(defvar glasspane-journal--date nil
  "The day being viewed (\"YYYY-MM-DD\"), or nil for today.
Single writer: the journal.* handlers (S2); every render re-reads it.")

(defun glasspane-journal--file ()
  "The journal file path."
  (or glasspane-journal-file
      (expand-file-name "journal.org" org-directory)))

(defun glasspane-journal--today ()
  (format-time-string "%Y-%m-%d"))

(defun glasspane-journal--current ()
  "The date the view shows."
  (or glasspane-journal--date (glasspane-journal--today)))

;;;; The datetree seam

(defun glasspane-journal--day-pos (date)
  "Position of DATE's day heading in the journal file, or nil.
Datetree day headings read \"*** 2026-07-05 Saturday\"; the full
Y-m-d makes the match unambiguous against month/year levels.  The
visit runs clamped: render happens inside the dispatch extent, where
a lock/revert prompt would wedge the bridge (D2)."
  (let ((file (glasspane-journal--file)))
    (when (file-readable-p file)
      (ebp-org--with-clamped-io
        (with-current-buffer (find-file-noselect file t)
          (org-with-wide-buffer
           (goto-char (point-min))
           (when (re-search-forward
                  (format "^\\*+[ \t]+%s\\(?:[ \t]\\|$\\)" (regexp-quote date))
                  nil t)
             (line-beginning-position))))))))

(defun glasspane-journal--append (text &optional date)
  "Append TEXT as a plain list item under DATE's (default today) day.
Creates the datetree levels (and the file) on first use.  Saves NOW
through `glasspane-org-save-and-invalidate' — the capture handler's
`accepted' promises on-disk, never on-timer (S4)."
  (let ((date (or date (glasspane-journal--today)))
        (file (glasspane-journal--file)))
    (pcase-let ((`(,y ,m ,d) (mapcar #'string-to-number
                                     (split-string date "-"))))
      (ebp-org--with-clamped-io
        (with-current-buffer (find-file-noselect file t)
          (org-with-wide-buffer
           (org-datetree-find-date-create (list m d y))
           (org-back-to-heading t)
           (org-end-of-subtree t t)
           (unless (bolp) (insert "\n"))
           (insert "- " text "\n"))
          (glasspane-org-save-and-invalidate))))))

(defun glasspane-journal--carried-over ()
  "Unfinished TODOs scheduled before today — the carry-over list.
The tree stays inside the wire grammar (`ebp-org--vet-query' passes
it), so the same query could ride a saved view verbatim."
  (glasspane-org-query '(and (todo) (scheduled :to -1))))

;;;; The view

(defun glasspane-journal--nav-row (date today-p)
  "The < yesterday | day (a native date picker) | tomorrow > chrome."
  (apply #'jetpacs-row
         (delq nil
               (list
                (jetpacs-icon-button
                 "chevron_left"
                 (jetpacs-action "journal.nav" :args (list :delta -1))
                 :content-description "Previous day")
                ;; :weight is a universal attr — inline on the box it
                ;; would signal at build (jetpacs--check-options).
                (jetpacs-with-attrs
                 (jetpacs-box
                  (jetpacs-date-button
                   (jetpacs-dates-format
                    date (if today-p "Today · %a, %b %e" "%a, %b %e, %Y"))
                   (jetpacs-action "journal.goto")
                   :value date)
                  :alignment "center")
                 :weight 1)
                (unless today-p
                  (jetpacs-chip "Today"
                                :on-tap (jetpacs-action "journal.today")))
                (jetpacs-icon-button
                 "chevron_right"
                 (jetpacs-action "journal.nav" :args (list :delta 1))
                 :content-description "Next day")))))

(defun glasspane-journal--capture-row (date)
  "The always-on-top quick-capture input for DATE.
`:clear-on-submit' clears the field on the device; a queued submit
still carries its text, so offline capture costs nothing."
  (jetpacs-text-input
   "journal-capture"
   :hint "Add to this day…"
   :single-line t
   :clear-on-submit t
   :on-submit (jetpacs-action "journal.capture"
                              :args (list :date date)
                              :when-offline "queue"
                              :ttl-s glasspane-journal--ttl-s)))

(defun glasspane-journal--day-nodes (date)
  "DATE's datetree content through the foldable reader, or a placeholder.
A reader failure (root policy, a drifted file) costs the day section,
never the screen — and shows the SPEC 23.3 label, not the raw error.
The token set is the journal's own: the default \"reader-subtree\" set
belongs to screens that replace each other, and a detail drill pushed
on top of this one must not sweep the day's still-visible taps."
  (or (condition-case err
          (when-let* ((pos (glasspane-journal--day-pos date)))
            (glasspane-org-reader-subtree (glasspane-journal--file) pos t
                                          "journal-day"))
        (error (list (jetpacs-text (format "Journal unreadable: %s"
                                           (jetpacs-error-label err))
                                   :style "caption"))))
      (list (jetpacs-text "Nothing here yet — the row above starts the day."
                          :style "caption"))))

(defun glasspane-journal--carried-card (item token)
  "One carried-over TODO with one-tap reschedule.
The buttons ride G4's `heading.schedule' DIRECT arms — computed args
only; the picker flows belong to the foundation dialogs (the G4
retirement split)."
  (jetpacs-card
   (list
    (jetpacs-column
     (jetpacs-text (or (alist-get 'headline item) "?") :style "body")
     (jetpacs-text (format "%s · %s"
                           (or (alist-get 'todo item) "TODO")
                           (or (alist-get 'scheduled item) ""))
                   :style "caption")
     (jetpacs-row
      (jetpacs-spacer :weight 1)
      (jetpacs-button "Today"
                      (jetpacs-action "heading.schedule"
                                      :args (list :when "+0d" :token token)
                                      :when-offline "queue"
                                      :ttl-s glasspane-journal--ttl-s)
                      :variant "text")
      (jetpacs-date-button "Pick"
                           (jetpacs-action "heading.schedule"
                                           :args (list :token token)
                                           :when-offline "queue"
                                           :ttl-s glasspane-journal--ttl-s)))))))

(defun glasspane-journal--carried-section ()
  "The carried-over nodes, or nil; tokens mint into set \"journal-carried\".
A broken query must cost the section, not the day (the v1 rule — the
condition-case is that decision, not defensiveness).  Refs are
filtered through the TOTAL root policy before the bulk mint, which
signals on a file outside the roots; replace-set semantics (S5) make
a card from a previous render answer `stale' for free."
  (condition-case nil
      (let* ((items (glasspane-journal--carried-over))
             (items (cl-remove-if-not
                     (lambda (it)
                       (let ((f (plist-get (alist-get 'ref it) :file)))
                         (and (stringp f) (not (string-empty-p f))
                              (ebp-org-file-allowed-p f))))
                     items))
             (tokens (and items
                          (ebp-org-ref-tokens
                           (mapcar (lambda (it) (alist-get 'ref it)) items)
                           :set "journal-carried" :owner "glasspane"))))
        (when items
          (append
           (list (jetpacs-divider)
                 (jetpacs-section-header
                  (format "Carried over (%d)" (length items))))
           (cl-mapcar #'glasspane-journal--carried-card items tokens))))
    (error nil)))

(defun glasspane-journal--body ()
  "The journal body for the current date."
  (let* ((date (glasspane-journal--current))
         (today-p (equal date (glasspane-journal--today))))
    (apply #'jetpacs-lazy-column
           (append
            (list (glasspane-journal--nav-row date today-p)
                  (glasspane-journal--capture-row date)
                  (jetpacs-spacer :height 4))
            (glasspane-journal--day-nodes date)
            (when today-p (glasspane-journal--carried-section))
            (when today-p
              (list (jetpacs-divider)
                    (jetpacs-section-header "Clock")
                    (glasspane-detail-clock-body)))))))

(defun glasspane-journal-screen (back)
  "The journal chrome screen; BACK is chrome's descriptor for the arrow."
  (jetpacs-chrome-screen "Journal" (glasspane-journal--body)
                         :back back
                         :fab (and glasspane-ui-legacy-ia
                                   (glasspane-ui-capture-fab))))

;;;; Landing & state resets

(defun glasspane-journal--apply-landing (_client)
  "Land on the journal when configured and no screen was chosen.
A root-only stack is the v3 reading of v1's \"no tab chosen this
session\" — screens outlive reconnects, so an earlier choice stands.
A push refused by the SYNCING window is kept as navigation debt and
re-asserted by the surface's next push; the gate re-signal is the only
thing to catch here."
  (let ((stack (jetpacs-chrome-stack "glasspane")))
    (when (and glasspane-journal-landing stack (null (cdr stack)))
      (condition-case err
          (jetpacs-chrome-push-screen "glasspane"
                                      glasspane-journal--screen-id
                                      #'glasspane-journal-screen)
        (error (message "glasspane: journal landing failed: %s"
                        (jetpacs-error-label err)))))))

(defun glasspane-journal--on-view-change (surface view)
  "Leaving the journal resets it to today — returning starts fresh.
Companion-local switches only (the device back arrow), which is the
leave that matters: an Emacs push ON TOP (a heading drill) keeps the
day, exactly the v1 tab feel."
  ;; ANY surface this owner holds, not just the D1 primary:
  ;; `jetpacs-chrome-push-screen' accepts any surface, so the journal
  ;; can live on a claimed secondary one and must still reset its day
  ;; on leave.
  (when (and (jetpacs-owned-surface-p surface "glasspane")
             (not (equal view glasspane-journal--screen-id)))
    (setq glasspane-journal--date nil)))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-journal--on-open (_args params)
  "Push the journal screen onto the tapped surface."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       ;; A deferred `jetpacs-chrome-push-screen' must catch its own
       ;; re-signal or a refused gate dies in a timer.
       (condition-case err
           (jetpacs-chrome-push-screen surface glasspane-journal--screen-id
                                       #'glasspane-journal-screen)
         (error (message "glasspane: journal push failed: %s"
                         (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-journal--on-nav (args params)
  "Shift the viewed day by `:delta' days."
  (let ((delta (plist-get args :delta)))
    ;; A whole-valued integer can arrive as a float after the JSON
    ;; round trip (org.json emits the trailing .0) — that float, and
    ;; only that one, is coerced back.  A genuinely fractional value is
    ;; a malformed event, not a rounding job: it stays a float and the
    ;; `integerp' check below rejects it.
    (when (and (floatp delta) (= delta (truncate delta)))
      (setq delta (truncate delta)))
    (if (not (integerp delta))
        'rejected
      (setq glasspane-journal--date
            (jetpacs-dates-shift (glasspane-journal--current) delta 'day))
      (jetpacs-app-defer-refresh params)
      'accepted)))

(defun glasspane-journal--on-goto (args params)
  "Jump to the picker's `:value' day."
  (let ((date (plist-get args :value)))
    (if (and (stringp date)
             (string-match-p
              "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date))
        (progn
          (setq glasspane-journal--date date)
          (jetpacs-app-defer-refresh params)
          'accepted)
      'rejected)))

(defun glasspane-journal--on-today (_args params)
  "Snap back to today."
  (setq glasspane-journal--date nil)
  (jetpacs-app-defer-refresh params)
  'accepted)

(defun glasspane-journal--on-capture (args params)
  "Append the submitted text to `:date' (default today).
`accepted' only after the append is saved (S4 durable — this is also
what makes the queued replay honest); a failed append logs and toasts
the SPEC 23.3 label, never the raw error."
  (let ((raw (plist-get args :value))
        (date (plist-get args :date)))
    (if (or (not (stringp raw)) (string-empty-p (string-trim raw)))
        'rejected
      ;; SPEC 23.2 — neutralize wire text before it becomes org
      ;; structure.  The append lands at end-of-subtree, so an embedded
      ;; newline would promote the payload out of the list item into a
      ;; heading, a keyword line or a local-variables block.  Collapsed
      ;; HERE and not in `glasspane-journal--append': that path is
      ;; M-x/internal, its text is not wire input.
      (let ((text (string-trim
                   (replace-regexp-in-string "[ \t\n\r]+" " " raw))))
        (condition-case err
            (progn
              (glasspane-journal--append
               text
               (and (stringp date) (not (string-empty-p date)) date))
              (jetpacs-shell-notify "Added to journal")
              (jetpacs-app-defer-refresh params)
              'accepted)
          (error
           (message "glasspane: journal capture failed: %s"
                    (jetpacs-error-label err))
           (jetpacs-toast "Capture failed")
           'rejected))))))

;;;; Registration

(defconst glasspane-journal--verbs
  '("journal.open" "journal.nav" "journal.goto" "journal.today"
    "journal.capture")
  "The verbs this module owns, for the register/unregister sweep.")

(defun glasspane-journal--on-teardown (owner)
  "Drop the journal hooks when OWNER is the Glasspane app.
`glasspane-owner' is read late and defensively: the entry file defines
it and `require's this one, so a back-`require' would cycle — and by
the time any teardown runs, the entry has long finished loading."
  (when (equal owner (bound-and-true-p glasspane-owner))
    (glasspane-journal-remove-hooks)))

(defun glasspane-journal-remove-hooks ()
  "Detach everything `glasspane-journal-register' hooked."
  (remove-hook 'jetpacs-ready-functions #'glasspane-journal--apply-landing)
  (remove-hook 'jetpacs-shell-view-change-functions
               #'glasspane-journal--on-view-change)
  (remove-hook 'jetpacs-teardown-functions #'glasspane-journal--on-teardown))

(defun glasspane-journal-register ()
  "Register the journal verbs, the settings section, and the hooks.
Called from `glasspane-register', never at this file's load (the G0
gate contract).  Idempotent: re-registration replaces handlers and
the registry entry in place."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "journal.open" #'glasspane-journal--on-open
                       :doc "Open the journal screen.")
    (jetpacs-defaction "journal.nav" #'glasspane-journal--on-nav
                       :doc "Shift the journal day by :delta days."
                       :args '((:name delta :type "number" :required t)))
    (jetpacs-defaction "journal.goto" #'glasspane-journal--on-goto
                       :doc "Show a specific journal day."
                       :args '((:name value :type "date" :required t)))
    (jetpacs-defaction "journal.today" #'glasspane-journal--on-today
                       :doc "Snap the journal back to today.")
    (jetpacs-defaction "journal.capture" #'glasspane-journal--on-capture
                       :doc "Append text to the current journal day."
                       :args '((:name value :type "text" :required t)
                               (:name date :type "date"))))
  ;; The landing row registers with the app's CONSOLIDATED "Glasspane"
  ;; section (glasspane-ui-register, §3 step 2): one app block on the
  ;; Settings root, not three orphan single-entry headers.
  (add-hook 'jetpacs-ready-functions #'glasspane-journal--apply-landing)
  (add-hook 'jetpacs-shell-view-change-functions
            #'glasspane-journal--on-view-change)
  (add-hook 'jetpacs-teardown-functions #'glasspane-journal--on-teardown))

(defun glasspane-journal-unregister ()
  "Drop the journal verbs, the settings section, and the hooks."
  (dolist (name glasspane-journal--verbs)
    (jetpacs-undefaction name))
  (glasspane-journal-remove-hooks))

(provide 'glasspane-journal)
;;; glasspane-journal.el ends here
