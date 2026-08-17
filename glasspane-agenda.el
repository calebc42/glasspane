;;; glasspane-agenda.el --- Glasspane agenda surfaces -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The daily surfaces rung, agenda half (docs/PLAN-glasspane-app.md,
;; G5): the day/week/month/custom agenda as a pushed chrome screen, the
;; reminder sync riding the shell push, and the global-TODO-sequence writers
;; the G3 settings dialog dispatches to.  Day/week/month stays an in-body
;; `jetpacs-tabs' (the S1 ruling);
;; every list renders through `glasspane-detail-agenda-card' over
;; SPEC 23.1 tokens minted one set per page (S5); every handler
;; answers a SPEC 14.4 status (S4).
;;
;; Retired against v1 (the plan's retirement list + G5 section):
;;
;; - The tab fabric (`jetpacs-shell-tab-view'/`-define-view', the tab
;;   badge closure): S1 — Agenda became a chrome screen behind
;;   `agenda.open'; the badge count surfaces IN-SCREEN and,
;;   since the gap-#5 thread-through landed, on the app's dock item
;;   (`glasspane-agenda-dock-badge').
;; - The clock tombstone view (v1 agenda:105-113): dies with the tab
;;   fabric; the clock body renders inside Journal (its own rung).
;; - The home-screen widget list + dividers (`--widget-items', v1
;;   agenda:51-72): no widget node vocabulary (FOUNDATION-GAPS #1).
;;   The pure meta/icon FORMATTERS stay — the cards and any future
;;   widget rung read them.
;; - `jetpacs-ui-state' writes for agenda-mode/anchor (S2): mode is an
;;   app defvar here; anchor/selected-date are G3's shared defvars,
;;   written only by the agenda.* handlers.
;; - The TODO-sequence WRITERS left with §3 step 2: they manage org's
;;   own state and are jetpacs-org-settings.el's ownerless
;;   jetpacs.org.todo.* family now, closing through the foundation's
;;   settings-dialog slot.
;; - PA-2d promotes the former Tasks body, state, and verbs into
;;   `glasspane-projects'; this module retains only the public tokenization
;;   seam its sibling consumes.
;; - `jetpacs-node-or' (T2): `jetpacs-node-advertised-p' conditionals.
;; - The trimodal reader block (v1 agenda:552-602,
;;   `glasspane-ui--org-editor-body'): PORTED IN G4 — the reader owns
;;   the jetpacs-files seam surfacing now, not this file.
;;
;; The pure, locale-stable calendar arithmetic is foundation-owned in
;; `jetpacs-dates'; this module supplies only Glasspane's agenda policy.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'calendar)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-device)
(require 'jetpacs-org-dialogs)          ; the archive-token scope (S5)
(require 'jetpacs-dates)
(require 'glasspane-org)
(require 'glasspane-ui)                 ; shared anchor/selected defvars,
                                        ; capture FAB, dialog close (S2/S3)
(require 'glasspane-detail)             ; the shared agenda card (G4)

;;;; State (S2 — the handlers below are the only writers)

(defvar glasspane-agenda--mode "day"
  "The active agenda mode: a span name or a saved-search name.
Replaces the v1 ui-state \"agenda-mode\"; the body re-seeds the tab
strip's `:initial' from it each render.")

;; `glasspane-views' loads after Agenda (and itself requires Agenda for the
;; shared card/calendar seams).  Declaring its public registry here avoids a
;; load cycle while the Saved page consumes the data directly.
(defvar glasspane-saved-views nil
  "Saved view definitions contributed by `glasspane-views'.")

(defconst glasspane-agenda--saved-mode "saved"
  "Internal mode key for Agenda's trailing Saved page.")

;;;; Reminders (piggybacked on each shell push)

(defvar glasspane-agenda--last-reminders 'unset
  "Reminder list from the previous sync, to suppress identical sends.")

(defvar glasspane-agenda-reminders-enabled t
  "Non-nil when Glasspane owns the reminder-sync hook.
This device-verified pipeline remains the sole active owner until the
reminder cutover explicitly flips the flag and clears its durable set.")

(defun glasspane-agenda--sync-reminders ()
  "Send upcoming timed items to the device as owner-scoped alarms.
Runs on `jetpacs-shell-after-push-hook': the extraction is memoised
and identical sets are suppressed, so the piggyback costs nothing on
a quiet vault.  `jetpacs-reminders-set' SIGNALS on a missing client
or the ungranted \"reminders.owner\" capability, so both gate here —
a hook member must never throw into the push path.  The cache adopts
in the callback, only on the confirmed arm (the v1 rule: never
pretend an unconfirmed set landed; the next push retries)."
  (when (and glasspane-agenda-reminders-enabled
             (not jetpacs-org-reminders-enabled)
             (jetpacs-client)
             (jetpacs-granted-p "reminders.owner"))
    (let ((rems (condition-case nil
                    (glasspane-org-upcoming-reminders)
                  (error nil))))
      (unless (equal rems glasspane-agenda--last-reminders)
        (condition-case err
            (jetpacs-reminders-set
             rems :owner "glasspane"
             :callback (lambda (_count err)
                         (unless err
                           (setq glasspane-agenda--last-reminders rems))))
          (error (message "glasspane: reminder sync failed: %s"
                          (jetpacs-error-label err))))))))

;;;; Pure formatters (the shared card's vocabulary; detail declares these)

(defun glasspane-agenda-widget-item-meta (it hm)
  "Compose the compact metadata line for agenda item IT.
Leads with the time HM or the agenda's own qualifier (\"Sched. 3x\",
\"In 3 d.\", \"2 d. ago\"), then the file name — the Orgzly-style
second row.  A bare \"Scheduled\"/\"Deadline\" qualifier restates what
the row's type icon already says, so it is dropped."
  (let* ((extra (alist-get 'extra it))
         (extra (and (stringp extra)
                     (replace-regexp-in-string
                      "[ \t]+" " "
                      (string-trim (replace-regexp-in-string
                                    ":[ \t]*\\'" "" (string-trim extra))))))
         (extra (and extra (not (member extra '("" "Scheduled" "Deadline")))
                     extra))
         (file (alist-get 'file it)))
    (string-join (delq nil (list (or hm extra)
                                 (and file (file-name-nondirectory file))))
                 " · ")))

(defun glasspane-agenda-widget-icon (type)
  "Map an org agenda TYPE to a compact metadata icon name."
  (cond ((not (stringp type)) "event")
        ((string-match-p "deadline" type) "deadline")
        ((string-match-p "scheduled" type) "scheduled")
        (t "event")))

(defun glasspane-agenda-type-icon (type)
  "Return (ICON . COLOR) for an agenda item TYPE string (color may be nil)."
  (cond
   ((null type) nil)
   ((string-match-p "past-scheduled" type) '("history" . "#E53935"))
   ((string-match-p "deadline" type) '("flag" . nil))
   ((string-match-p "scheduled" type) '("schedule" . nil))
   (t nil)))

(defun glasspane-agenda-type-label (type)
  "Short human label for an agenda item TYPE string, or nil to omit."
  (pcase type
    ("past-scheduled" "overdue")
    ("upcoming-deadline" "deadline soon")
    ("deadline" "deadline")
    ("scheduled" "scheduled")
    (_ nil)))

(defun glasspane-agenda-card-date-label (ts)
  "Format org timestamp TS as a compact \"Mon D\" (or \"Mon D HH:MM\")."
  (when (and (stringp ts)
             (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)" ts))
    (let* ((month (string-to-number (match-string 2 ts)))
           (day   (string-to-number (match-string 3 ts)))
           (mon   (jetpacs-dates-month-abbrev month))
           (time  (ebp-org-ts-time ts)))
      (if time (format "%s %d %s" mon day time)
        (format "%s %d" mon day)))))

(defun glasspane-agenda-card-date-row (it)
  "An inline scheduling indicator for card item IT.
Compact icon + text labels for SCHEDULED and/or DEADLINE when present;
nil when neither is set."
  (let* ((scheduled (alist-get 'scheduled it))
         (deadline  (alist-get 'deadline it))
         (slabel (glasspane-agenda-card-date-label scheduled))
         (dlabel (glasspane-agenda-card-date-label deadline))
         (children
          (delq nil
                (list
                 (when slabel
                   (jetpacs-icon "schedule" :size 14 :color "#9E9E9E"))
                 (when slabel (jetpacs-text (concat " " slabel)
                                            :style "caption"))
                 (when (and slabel dlabel) (jetpacs-spacer :width 16))
                 (when dlabel (jetpacs-icon "flag" :size 14 :color "#EF5350"))
                 (when dlabel (jetpacs-text (concat " " dlabel)
                                            :style "caption"))))))
    (when children
      (apply #'jetpacs-row children))))

;;;; Token minting (S5 — one :set per rendered list, replace semantics)

(defun glasspane-agenda--tokenize (items set)
  "ITEMS with `token'/`archive-token' cells attached; one bulk mint (S5).
Refs whose file left the org roots would SIGNAL at mint time
(ebp-org.el's policy-at-mint rule), so they are filtered first — the
item still renders, just untappable — as is any overflow past the
per-set cap.  Two sets because the base `jetpacs.org.archive' resolves
only `jetpacs-org-dialogs-owner' tokens: the app rents the disjoint
\"glasspane-SET\" name in that scope (the G4 reader's shape).  Minted
even when ITEMS is empty — the replace sweep is what retires the
previous render's tokens."
  (let* ((mintable (cl-remove-if-not
                    (lambda (it)
                      (let ((f (plist-get (alist-get 'ref it) :file)))
                        (and (stringp f) (not (string-empty-p f))
                             (ebp-org-file-allowed-p f))))
                    items))
         (mintable (seq-take mintable ebp-org-token-set-max))
         (refs (mapcar (lambda (it) (alist-get 'ref it)) mintable))
         (taps (ebp-org-ref-tokens refs :set set :owner "glasspane"))
         (archives (ebp-org-ref-tokens refs :set (concat "glasspane-" set)
                                       :owner jetpacs-org-dialogs-owner))
         (table (make-hash-table :test #'eq)))
    (cl-loop for it in mintable for tap in taps for arch in archives
             do (puthash it (cons tap arch) table))
    (mapcar (lambda (it)
              (let ((cell (gethash it table)))
                (if cell
                    (append (list (cons 'token (car cell))
                                  (cons 'archive-token (cdr cell)))
                            it)
                  it)))
            items)))

(defalias 'glasspane-agenda-tokenize
  #'glasspane-agenda--tokenize
  "Public shared-card tokenization for a Glasspane item list.")

;;;; Agenda navigation
;;
;; The agenda is anchored on a date (`glasspane-ui-agenda-anchor',
;; nil = today).  The ‹ › buttons shift the anchor by one
;; day/week/month according to the active span, and the anchor feeds
;; `glasspane-org-agenda-items' as START-DAY — whose cache keys
;; already include it, so each visited range memoises independently.

(defun glasspane-agenda--anchor ()
  "The agenda's anchor date as \"YYYY-MM-DD\"; today when unset."
  (let ((a glasspane-ui-agenda-anchor))
    (if (and (stringp a)
             (string-match-p
              "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" a))
        a
      (format-time-string "%Y-%m-%d"))))

(defconst glasspane-agenda--custom-max 8
  "How many saved searches the agenda offers as pages.
A token budget, not a taste call: every Org-result page mints TWO sets —
the tap set under \"glasspane\" and the archive set under
`jetpacs-org-dialogs-owner' — while `ebp-org-token-sets-max' is 32 PER
OWNER, shared with every other glasspane screen.  The mint SIGNALS on
overflow, which kills the whole body build, so the page count is
bounded here rather than by however many agendas the user saved.
`glasspane-ui''s saved-search list still shows all of them; a selected
mode past the cap coerces back to \"day\"
(`glasspane-agenda--current-mode').  The trailing Saved registry page
mints no Org tokens and therefore does not consume this budget.")

(defun glasspane-agenda--modes ()
  "Agenda page keys in display order: spans, customs, then Saved."
  (append '("day" "week" "month")
          (mapcar #'car (seq-take glasspane-org-custom-agendas
                                  glasspane-agenda--custom-max))
          (list glasspane-agenda--saved-mode)))

(defun glasspane-agenda--current-mode ()
  "The active mode, coerced back to one that still exists.
A saved search deleted while selected must not wedge the body."
  (if (member glasspane-agenda--mode (glasspane-agenda--modes))
      glasspane-agenda--mode
    "day"))

(defun glasspane-agenda--nav-row (mode anchor)
  "The ‹ [range label] [today] › navigation row for the agenda header."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (at-today (pcase mode
                     ("month" (equal (substring anchor 0 7)
                                     (substring today 0 7)))
                     (_ (equal anchor today))))
         (label (pcase mode
                  ("month" (jetpacs-dates-format anchor "%B %Y"))
                  ("week" (concat "Week of "
                                  (jetpacs-dates-format anchor "%b %d")))
                  (_ (if at-today
                         (concat "Today · "
                                 (jetpacs-dates-format anchor "%a, %b %d"))
                       (jetpacs-dates-format anchor "%a, %b %d"))))))
    (apply #'jetpacs-row
           (delq nil
                 (list
                  (jetpacs-icon-button "chevron_left"
                                       (jetpacs-action "agenda.nav"
                                                       :args '(:dir -1))
                                       :content-description "Previous")
                  (jetpacs-with-attrs
                   (jetpacs-box (list (jetpacs-text label :style "label"))
                                :alignment "center")
                   :weight 1)
                  (unless at-today
                    (jetpacs-icon-button "today"
                                         (jetpacs-action "agenda.today")
                                         :content-description
                                         "Back to today"))
                  (jetpacs-icon-button "chevron_right"
                                       (jetpacs-action "agenda.nav"
                                                       :args '(:dir 1))
                                       :content-description "Next"))))))

;;;; Mode bodies (items arrive already tokenized)

(defun glasspane-agenda--day-view (items)
  "The flat day list for tokenized ITEMS."
  (let ((cards (mapcar #'glasspane-detail-agenda-card items)))
    (if cards
        (apply #'jetpacs-lazy-column cards)
      (jetpacs-empty-state :icon "event_busy"
                           :title "No agenda items"
                           :caption "Nothing scheduled for this day."))))

(defun glasspane-agenda--week-view (items)
  "Tokenized ITEMS grouped under per-date section headers."
  (let ((elements nil)
        (current-date nil))
    (dolist (it items)
      (let ((date (alist-get 'date it)))
        (unless (equal date current-date)
          (setq current-date date)
          (push (jetpacs-section-header (or date "Unknown Date")) elements))
        (push (glasspane-detail-agenda-card it) elements)))
    (if elements
        (apply #'jetpacs-lazy-column (nreverse elements))
      (jetpacs-empty-state :icon "event_busy"
                           :title "No agenda items"
                           :caption "Nothing scheduled for this week."))))

(defun glasspane-agenda--month-view (items anchor)
  "Month calendar for tokenized ITEMS, showing ANCHOR's month.
The grid is the curated `month_grid' node when the device advertises
it (month swipe, today/selection states, a11y grid semantics); an
older device gets `glasspane-agenda-month-fallback' — the composed
grid, the documented fallback recipe."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (month-prefix (substring anchor 0 7))
         (sel glasspane-ui-agenda-selected-date)
         ;; A remembered selection only counts inside the shown month;
         ;; otherwise select today (when visible) or the anchor day.
         (selected-date (cond
                         ((and (stringp sel)
                               (string-prefix-p month-prefix sel))
                          sel)
                         ((string-prefix-p month-prefix today) today)
                         (t anchor)))
         (items-by-date (seq-group-by (lambda (it) (alist-get 'date it))
                                      items))
         (selected-items (cdr (assoc selected-date items-by-date))))
    (jetpacs-column
     (if (jetpacs-node-advertised-p "month_grid")
         (jetpacs-month-grid
          month-prefix
          ;; One mark per date, dots = item count (capped at the
          ;; node's 0..3 grammar).
          :marks (delq nil
                       (mapcar (lambda (g)
                                 (and (stringp (car g))
                                      (cons (car g)
                                            (jetpacs-month-mark
                                             (min 3 (length (cdr g)))))))
                               items-by-date))
          :selected selected-date
          ;; Taps arrive with the ISO date as args :value.
          :on-day-tap (jetpacs-action "agenda.select-date")
          ;; Device-local swipe/chevrons report the shown month; the
          ;; handler re-anchors and pushes fresh marks for it.
          :on-month-change (jetpacs-action "agenda.set-month"))
       (glasspane-agenda-month-fallback items-by-date anchor selected-date))
     (jetpacs-divider)
     (jetpacs-section-header (format "Events for %s" selected-date))
     (if selected-items
         (apply #'jetpacs-lazy-column
                (mapcar #'glasspane-detail-agenda-card selected-items))
       (jetpacs-text "No events" :style "caption")))))

(defun glasspane-agenda-month-fallback (items-by-date anchor selected-date
                                                       &optional select-action)
  "The composed month grid for devices that predate `month_grid'.
SELECT-ACTION (default \"agenda.select-date\") receives the tapped
day as its `:date' arg — saved views pass their own handler."
  (let* ((month (string-to-number (substring anchor 5 7)))
         (year (string-to-number (substring anchor 0 4)))
         (days-in-month (calendar-last-day-of-month month year))
         (first-day-of-month (calendar-day-of-week (list month 1 year)))
         (grid-rows nil)
         (current-day 1)
         (week-header
          (apply #'jetpacs-row
                 (mapcar (lambda (d)
                           (jetpacs-with-attrs
                            (jetpacs-box (list (jetpacs-text d
                                                             :style "caption"))
                                         :alignment "center")
                            :weight 1))
                         '("S" "M" "T" "W" "T" "F" "S")))))
    (while (<= current-day days-in-month)
      (let ((row-cells nil))
        (dotimes (dow 7)
          (if (or (and (= current-day 1) (< dow first-day-of-month))
                  (> current-day days-in-month))
              (push (jetpacs-with-attrs (jetpacs-box (list (jetpacs-spacer)))
                                        :weight 1)
                    row-cells)
            (let* ((date-str (format "%04d-%02d-%02d" year month current-day))
                   (day-items (cdr (assoc date-str items-by-date)))
                   (is-selected (equal date-str selected-date))
                   (text-color (if is-selected "#FFFFFF" nil))
                   (bg-color (if is-selected "#1976D2" nil))
                   (cell-content
                    (list
                     (jetpacs-with-attrs
                      (jetpacs-surface
                       (list
                        (jetpacs-text (number-to-string current-day)
                                      :style "body" :color text-color)
                        (if day-items
                            (jetpacs-with-attrs
                             (jetpacs-icon "circle" :size 6
                                           :color (if is-selected
                                                      "#FFFFFF" "#1976D2"))
                             :padding 2)
                          (jetpacs-spacer :height 8)))
                       :color bg-color :shape "rounded")
                      :padding 4))))
              (push (jetpacs-with-attrs
                     (jetpacs-box cell-content
                                  :alignment "center"
                                  :on-tap (jetpacs-action
                                           (or select-action
                                               "agenda.select-date")
                                           :args (list :date date-str)))
                     :weight 1)
                    row-cells)
              (setq current-day (1+ current-day)))))
        (push (apply #'jetpacs-row (nreverse row-cells)) grid-rows)))
    (jetpacs-column
     week-header
     (jetpacs-spacer :height 8)
     (apply #'jetpacs-column (nreverse grid-rows)))))

;;;; Pages and the body

(defun glasspane-agenda--items-for (mode anchor)
  "Extract MODE's items anchored at ANCHOR (span extraction or search).
Every branch is memoised, so building several mode pages per push (the
tabs body) re-extracts nothing after each page's first build."
  ;; The month span always starts on the 1st so the grid and the
  ;; extraction agree on the visible range.
  (let ((start-day (cond ((equal mode "month")
                          (concat (substring anchor 0 7) "-01"))
                         ((member mode '("day" "week")) anchor))))
    (condition-case nil
        (pcase mode
          ("day" (glasspane-org-agenda-items 'day start-day))
          ("week" (glasspane-org-agenda-items 'week start-day))
          ("month" (glasspane-org-agenda-items 'month start-day))
          (_ (glasspane-org-search
              (cdr (assoc mode glasspane-org-custom-agendas)))))
      (error nil))))

(defun glasspane-agenda--nav-affordance (mode anchor)
  "MODE's date-navigation row, or nil when the view navigates itself.
The curated month grid carries its own header, chevrons, and swipe —
only the jump-home chip remains ours there; custom agendas have no
anchor to navigate."
  (cond
   ((equal mode "month")
    (if (jetpacs-node-advertised-p "month_grid")
        (unless (equal (substring anchor 0 7) (format-time-string "%Y-%m"))
          (jetpacs-row
           (jetpacs-spacer :weight 1)
           (jetpacs-assist-chip "Today" :icon "today"
                                :on-tap (jetpacs-action "agenda.today"))))
      (glasspane-agenda--nav-row mode anchor)))
   ((member mode '("day" "week"))
    (glasspane-agenda--nav-row mode anchor))))

(defun glasspane-agenda--mode-view (mode items anchor)
  "MODE's item rendering, chrome-free; ITEMS arrive tokenized."
  (pcase mode
    ("day" (glasspane-agenda--day-view items))
    ("week" (glasspane-agenda--week-view items))
    ("month" (glasspane-agenda--month-view items anchor))
    (_ (if items
           (apply #'jetpacs-lazy-column
                  (mapcar #'glasspane-detail-agenda-card items))
         (jetpacs-empty-state :icon "event_busy"
                              :title "No results"
                              :caption
                              "This custom agenda found no items.")))))

(defun glasspane-agenda--saved-custom-row (entry)
  "Render custom-agenda ENTRY as a jump to its existing Agenda page."
  (let ((name (car entry))
        (query (cdr entry)))
    (jetpacs-chrome-row
     name
     :subtitle (format "%s" query)
     :icon "event_note"
     :trailing (jetpacs-icon "chevron_right")
     :on-tap (jetpacs-action "agenda.set-mode" :args (list :mode name))
     :key (jetpacs-wire-id "saved-agenda" name))))

(defun glasspane-agenda--saved-view-row (view)
  "Render saved VIEW as a Tier-1 peer-screen opener."
  (let ((name (alist-get 'name view))
        (query (alist-get 'query view))
        (rendering (or (alist-get 'rendering view) "list")))
    (jetpacs-chrome-row
     name
     :subtitle (format "%s · %s" rendering query)
     :icon "manage_search"
     :trailing (jetpacs-icon "chevron_right")
     :on-tap (jetpacs-action "views.open" :args (list :name name))
     :key (jetpacs-wire-id "saved-view" name))))

(defun glasspane-agenda--saved-page ()
  "List both saved-search registries without merging their semantics."
  (let ((agendas
         (cl-remove-if-not
          (lambda (entry)
            (and (consp entry) (stringp (car entry))
                 (not (string-empty-p (car entry)))))
          (seq-take glasspane-org-custom-agendas
                    glasspane-agenda--custom-max)))
        (views
         (cl-remove-if-not
          (lambda (view)
            (let ((name (alist-get 'name view)))
              (and (stringp name) (not (string-empty-p name)))))
          glasspane-saved-views)))
    (apply #'jetpacs-lazy-column
           (append
            (list (jetpacs-section-header "Custom agendas"))
            (if agendas
                (mapcar #'glasspane-agenda--saved-custom-row agendas)
              (list (jetpacs-text "No custom agendas" :style "caption")))
            (list (jetpacs-divider)
                  (jetpacs-section-header "Saved views"))
            (if views
                (mapcar #'glasspane-agenda--saved-view-row views)
              (list (jetpacs-text "No saved views" :style "caption")))
            (list :spacing 8 :content-padding 12)))))

(defun glasspane-agenda--page (mode anchor)
  "One agenda page: MODE's nav affordance above its tokenized body.
One mint set per page — the tabs body builds every page each push, so
a shared set would sweep its siblings' tokens mid-render.  Set names
therefore track mode names, so the live set count per owner is
bounded by the three spans plus `glasspane-agenda--custom-max'.  Saved
is registry navigation, not an Org result list, and therefore mints no set."
  (if (equal mode glasspane-agenda--saved-mode)
      (glasspane-agenda--saved-page)
    (let ((items (glasspane-agenda--tokenize
                  (glasspane-agenda--items-for mode anchor)
                  (concat "agenda-" mode))))
      (apply #'jetpacs-column
             (delq nil
                   (list (glasspane-agenda--nav-affordance mode anchor)
                         (jetpacs-spacer :height 4)
                         (glasspane-agenda--mode-view mode items anchor)))))))

(defun glasspane-agenda--body-tabs (mode anchor)
  "The agenda as native tabs: swipe between spans and custom agendas.
Switching is device-local — every page ships in the push, which the
memoised extractions keep cheap — and works offline; on_change keeps
Emacs's mode state in step so the anchor and nav logic follow on the
next push.  No :id — a background re-push must not yank the user's
tab."
  (let* ((modes (glasspane-agenda--modes))
         (initial (or (seq-position modes mode) 0)))
    (jetpacs-tabs
     (mapcar (lambda (m)
               (jetpacs-tab-item (pcase m
                                   ("day" "Day") ("week" "Week")
                                   ("month" "Month")
                                   ("saved" "Saved") (_ m))))
             modes)
     (mapcar (lambda (m) (glasspane-agenda--page m anchor)) modes)
     :initial initial
     :scrollable (jetpacs-bool (> (length modes) 3))
     :on-change (jetpacs-action "agenda.set-mode"))))

(defun glasspane-agenda--body-chips (mode anchor)
  "The chip-row agenda for devices predating the `tabs' node."
  (let ((chips
         (mapcar (lambda (m)
                   (jetpacs-chip (pcase m
                                   ("day" "Day") ("week" "Week")
                                   ("month" "Month")
                                   ("saved" "Saved") (_ m))
                                 :selected (jetpacs-bool (equal mode m))
                                 :on-tap (jetpacs-action
                                          "agenda.set-mode"
                                          :args (list :mode m))))
                 (glasspane-agenda--modes))))
    (jetpacs-column
     (apply #'jetpacs-flow-row (append chips (list :spacing 4)))
     (glasspane-agenda--page mode anchor))))

(defun glasspane-agenda-body ()
  "The whole agenda body: tabs when advertised, chips otherwise."
  (let ((mode (glasspane-agenda--current-mode))
        (anchor (glasspane-agenda--anchor)))
    (if (jetpacs-node-advertised-p "tabs")
        (glasspane-agenda--body-tabs mode anchor)
      (glasspane-agenda--body-chips mode anchor))))

;;;; Screens

(defun glasspane-agenda--today-count ()
  "Today's agenda item count (overdue included).
Reads the memoised day extraction, so a render recomputes nothing.
The v1 tab badge's successor — surfaced IN-SCREEN here, and on the
app's dock item through `glasspane-agenda-dock-badge' now that the
gap-#5 thread-through landed."
  (length (condition-case nil
              (glasspane-org-agenda-items 'day)
            (error nil))))

(defun glasspane-agenda-dock-badge ()
  "Today's count as a destination `:badge' string, or nil when zero.
nil keeps the icon bare — a zero-count badge is noise — and the memoised
extraction keeps the per-render cost at a table lookup.  Public: the PARA
Agenda destination and the legacy dock builder both call it."
  (let ((n (glasspane-agenda--today-count)))
    (and (> n 0) (number-to-string n))))

(defun glasspane-agenda-screen (back)
  "The pushed Agenda screen."
  (let ((n (glasspane-agenda--today-count)))
    (jetpacs-chrome-screen
     "Agenda"
     (apply #'jetpacs-column
            (delq nil
                  (list (when (> n 0)
                          (jetpacs-text (format "%d scheduled today" n)
                                        :style "caption"))
                        (glasspane-agenda-body))))
     :back back
     :fab (and glasspane-ui-legacy-ia (glasspane-ui-capture-fab)))))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-agenda--on-open (_args params)
  "Reset to the pinned Agenda root on the tapped surface."
  (glasspane-ui-open-destination "agenda" "glasspane-agenda"
                                 #'glasspane-agenda-screen params))

(defun glasspane-agenda--on-set-mode (args params)
  "Select an agenda mode.  `:mode' names come from the fallback chips;
`:value' (a page index) from the tabs body's on_change.  Either way
the result must name a mode we actually offer."
  (let* ((modes (glasspane-agenda--modes))
         (idx (plist-get args :value))
         ;; A whole-valued integer can arrive as a float after the
         ;; JSON round trip (org.json emits the trailing .0) — that
         ;; float, and only that one, is coerced back.  A genuinely
         ;; fractional index is a malformed event, not a rounding job:
         ;; it stays a float and the `integerp' test below rejects it.
         (idx (if (and (floatp idx) (= idx (truncate idx)))
                  (truncate idx)
                idx))
         (mode (or (plist-get args :mode)
                   (and (integerp idx) (nth idx modes)))))
    (if (not (member mode modes))
        'rejected
      (setq glasspane-agenda--mode mode)
      (jetpacs-app-defer-refresh params)
      'accepted)))

(defun glasspane-agenda--on-nav (args params)
  "Shift the agenda anchor by `:dir' (±1) in units of the active span."
  (let* ((dir (plist-get args :dir))
         ;; Same JSON round trip as `--on-set-mode': a whole-valued
         ;; integer can arrive as a float, and only that float coerces
         ;; back.  A fractional direction is a malformed event, not a
         ;; rounding job — it stays a float for `integerp' to reject.
         (dir (if (and (floatp dir) (= dir (truncate dir)))
                  (truncate dir)
                dir)))
    (if (not (integerp dir))
        'rejected
      (let* ((mode (glasspane-agenda--current-mode))
             (unit (pcase mode ("week" 'week) ("month" 'month) (_ 'day)))
             (anchor (glasspane-agenda--anchor)))
        ;; Month steps walk 1st → 1st so ±1 never skips a short month.
        (when (eq unit 'month)
          (setq anchor (concat (substring anchor 0 7) "-01")))
        (setq glasspane-ui-agenda-anchor
              (jetpacs-dates-shift anchor dir unit))
        (jetpacs-app-defer-refresh params)
        'accepted))))

(defconst glasspane-agenda--verbs
  '("agenda.open"
    "agenda.set-mode"
    "agenda.nav")
  "The verbs this file owns, for the register/unregister sweep.
agenda.today/select-date/set-month live with the anchor defvars (G3).
The sequence writers left with §3 step 2 — the foundation's ownerless
jetpacs.org.todo.* family owns them now.")

(defun glasspane-agenda-remove-hooks ()
  "Detach everything `glasspane-agenda-register' hooked."
  (remove-hook 'jetpacs-shell-after-push-hook
               #'glasspane-agenda--sync-reminders)
  (remove-hook 'jetpacs-teardown-functions #'glasspane-agenda--on-teardown))

(defun glasspane-agenda--on-teardown (owner)
  "Drop the agenda hooks when OWNER is the Glasspane app.
`glasspane-owner' is read late and defensively: the entry file defines
it and `require's this one, so a back-`require' would cycle — and by
the time any teardown runs, the entry has long finished loading."
  (when (equal owner (bound-and-true-p glasspane-owner))
    (glasspane-agenda-remove-hooks)))

(defun glasspane-agenda-register ()
  "Register the Agenda verbs and the reminder-sync hook.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent: re-registration replaces handlers in
place and the hooks are add-hook-deduplicated."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "agenda.open" #'glasspane-agenda--on-open
                       :doc "Open the agenda screen")
    (jetpacs-defaction "agenda.set-mode" #'glasspane-agenda--on-set-mode)
    (jetpacs-defaction "agenda.nav" #'glasspane-agenda--on-nav))
  (remove-hook 'jetpacs-shell-after-push-hook
               #'glasspane-agenda--sync-reminders)
  (when (and glasspane-agenda-reminders-enabled
             (not jetpacs-org-reminders-enabled))
    (add-hook 'jetpacs-shell-after-push-hook
              #'glasspane-agenda--sync-reminders))
  (add-hook 'jetpacs-teardown-functions #'glasspane-agenda--on-teardown))

(defun glasspane-agenda-unregister ()
  "Drop the Agenda verbs and hooks; forget the reminder cache.
The forgotten cache makes the next register's first push re-arm the
device set rather than trusting alarms a torn-down session sent."
  (dolist (name glasspane-agenda--verbs)
    (jetpacs-undefaction name))
  (glasspane-agenda-remove-hooks)
  (setq glasspane-agenda--last-reminders 'unset))

(provide 'glasspane-agenda)
;;; glasspane-agenda.el ends here
