;;; glasspane-agenda.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

(require 'glasspane-ui)

(defvar glasspane-ui--tasks-filter "ALL"
  "Current filter for the Tasks tab.")

;; ─── Reminders & home-screen widget (piggybacked on each shell push) ────────

(defvar glasspane-ui--last-reminders 'unset
  "Reminder list from the previous sync, to suppress identical sends.")

(defun glasspane-ui--sync-reminders ()
  "Send upcoming timed items to the companion as owner-scoped exact alarms."
  (let ((rems (condition-case nil (glasspane-org--upcoming-reminders) (error nil))))
    (unless (equal rems glasspane-ui--last-reminders)
      ;; Cache only on a successful arm.  `jetpacs-reminders-owner-set' arms
      ;; nothing (returns nil) when the companion can't scope reminders per
      ;; app and another app is present — retry next push rather than pretend
      ;; it landed.  Owner "glasspane" keeps our alarms off other apps' sets.
      (when (jetpacs-reminders-owner-set rems "glasspane")
        (setq glasspane-ui--last-reminders rems)))))

(defun glasspane-ui--widget-item-meta (it hm)
  "Compose the widget metadata line for agenda item IT.
Leads with the time HM or the agenda's own qualifier (\"Sched. 3x\",
\"In 3 d.\", \"2 d. ago\"), then the file name — the Orgzly-style
second row. A bare \"Scheduled\"/\"Deadline\" qualifier restates what
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

(defun glasspane-ui--widget-agenda-icon (type)
  "Map an org agenda TYPE to a widget metadata icon name."
  (cond ((not (stringp type)) "event")
        ((string-match-p "deadline" type) "deadline")
        ((string-match-p "scheduled" type) "scheduled")
        (t "event")))

(defun glasspane-ui--widget-items ()
  "Today's agenda as widget rows, overdue grouped under dividers."
  (let* ((today (org-today))
         ;; The widget list scrolls, so the cap is just a sanity bound on
         ;; spec size, not a display limit.
         (raw (seq-take (condition-case nil
                            (glasspane-org--agenda-items 'day nil)
                          (error nil))
                        20))
         (overdue-p (lambda (it)
                      (let ((ts (alist-get 'ts-date it)))
                        (and (numberp ts) (< ts today)))))
         (overdue (seq-filter overdue-p raw))
         (current (seq-remove overdue-p raw)))
    (if (null overdue)
        (mapcar #'glasspane-ui--widget-row raw)
      (append
       (cons (jetpacs-widget-divider "Overdue")
             (mapcar #'glasspane-ui--widget-row overdue))
       (when current
         (cons (jetpacs-widget-divider "Today")
               (mapcar #'glasspane-ui--widget-row current)))))))

;; ─── Shell views ─────────────────────────────────────────────────────────────

(defun glasspane-ui--agenda-view (snackbar)
  (jetpacs-shell-tab-view "glasspane.agenda" (glasspane-ui--agenda-body)
                       :snackbar snackbar))

(defun glasspane-ui--tasks-view (snackbar)
  (jetpacs-shell-tab-view "glasspane.tasks" (glasspane-ui--tasks-body)
                       :snackbar snackbar))

(defun glasspane-ui--clock-view (snackbar)
  (jetpacs-shell-tab-view "glasspane.clock" (glasspane-ui--clock-body)
                       :snackbar snackbar))

(defun glasspane-ui--agenda-badge ()
  "Today's agenda item count (overdue included) for the Agenda tab badge.
Reads the memoised day extraction, so a push recomputes nothing; nil
\(no badge) when the day is clear."
  (let ((n (length (condition-case nil
                       (glasspane-org--agenda-items 'day)
                     (error nil)))))
    (and (> n 0) n)))

(jetpacs-shell-define-view "glasspane.agenda" :builder #'glasspane-ui--agenda-view
                        :tab '(:icon "event" :label "Agenda"
                               :badge glasspane-ui--agenda-badge)
                        :order 10)

(jetpacs-shell-define-view "glasspane.tasks" :builder #'glasspane-ui--tasks-view
                        :tab '(:icon "checklist" :label "Tasks") :order 20)

;; The clock lost its tab 2026-07-06 (user decision: six tabs was
;; crowded and the screen alone felt barren) — its body now renders as
;; a section of the Journal view.  The view stays registered so cached
;; `view.switch' targets from older pushes still resolve.  (Targets
;; cached before the 2026-07-10 "glasspane." namespacing name the bare
;; views and drop harmlessly; one fresh push re-caches.)
(jetpacs-shell-define-view "glasspane.clock" :builder #'glasspane-ui--clock-view
                        :order 30)

;; ─── Tab Bodies ──────────────────────────────────────────────────────────────

;; ── Agenda navigation ──
;; The agenda is anchored on a date (UI state "agenda-anchor", nil = today).
;; The ‹ › buttons shift the anchor by one day/week/month according to the
;; active span, and the anchor feeds `glasspane-org--agenda-items' as START-DAY —
;; whose cache keys already include it, so each visited range memoises
;; independently.

(defun glasspane-ui--agenda-anchor ()
  "The agenda's anchor date as \"YYYY-MM-DD\"; today when unset."
  (let ((a (jetpacs-ui-state "agenda-anchor")))
    (if (and (stringp a) (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" a))
        a
      (format-time-string "%Y-%m-%d"))))

(defun glasspane-ui--shift-date (date n unit)
  "Shift DATE (\"YYYY-MM-DD\") by N UNITs (`day', `week', or `month').
Month arithmetic clamps the day into the target month, so Jan 31 + 1
month is Feb 28, not an invalid date."
  (pcase-let ((`(,y ,m ,d) (mapcar #'string-to-number (split-string date "-"))))
    (if (eq unit 'month)
        (let* ((total (+ (* 12 y) (1- m) n))
               (ny (/ total 12))
               (nm (1+ (% total 12))))
          (format "%04d-%02d-%02d" ny nm
                  (min d (calendar-last-day-of-month nm ny))))
      (let ((days (* n (if (eq unit 'week) 7 1))))
        ;; Noon avoids DST-transition off-by-one-day surprises.
        (format-time-string "%Y-%m-%d"
                            (time-add (encode-time 0 0 12 d m y)
                                      (* days 86400)))))))

(defun glasspane-ui--format-date (date fmt)
  "Render DATE (\"YYYY-MM-DD\") through `format-time-string' FMT."
  (pcase-let ((`(,y ,m ,d) (mapcar #'string-to-number (split-string date "-"))))
    (format-time-string fmt (encode-time 0 0 12 d m y))))

(defun glasspane-ui--agenda-nav-row (mode anchor)
  "The ‹ [range label] [today] › navigation row for the agenda header."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (at-today (pcase mode
                     ("month" (equal (substring anchor 0 7) (substring today 0 7)))
                     (_ (equal anchor today))))
         (label (pcase mode
                  ("month" (glasspane-ui--format-date anchor "%B %Y"))
                  ("week" (concat "Week of "
                                  (glasspane-ui--format-date anchor "%b %d")))
                  (_ (if at-today
                         (concat "Today · " (glasspane-ui--format-date anchor "%a, %b %d"))
                       (glasspane-ui--format-date anchor "%a, %b %d"))))))
    (apply #'jetpacs-row
           (delq nil
                 (list
                  (jetpacs-icon-button "chevron_left"
                                    (jetpacs-action "agenda.nav" :args '((dir . -1)))
                                    :content-description "Previous")
                  (jetpacs-box (list (jetpacs-text label 'label))
                            :weight 1 :alignment "center")
                  (unless at-today
                    (jetpacs-icon-button "today" (jetpacs-action "agenda.today")
                                      :content-description "Back to today"))
                  (jetpacs-icon-button "chevron_right"
                                    (jetpacs-action "agenda.nav" :args '((dir . 1)))
                                    :content-description "Next"))))))

;; ── Agenda cards ──

(defun glasspane-ui--agenda-type-icon (type)
  "Return (ICON . COLOR) for an agenda item TYPE string (color may be nil)."
  (cond
   ((null type) nil)
   ((string-match-p "past-scheduled" type) '("history" . "#E53935"))
   ((string-match-p "deadline" type) '("flag" . nil))
   ((string-match-p "scheduled" type) '("schedule" . nil))
   (t nil)))

(defun glasspane-ui--agenda-type-label (type)
  "Short human label for an agenda item TYPE string, or nil to omit."
  (pcase type
    ("past-scheduled" "overdue")
    ("upcoming-deadline" "deadline soon")
    ("deadline" "deadline")
    ("scheduled" "scheduled")
    (_ nil)))

(defun glasspane-ui--card-date-label (ts)
  "Format org timestamp TS as a compact \"Mon D\" (or \"Mon D HH:MM\") string."
  (when (and (stringp ts)
             (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)" ts))
    (let* ((month (string-to-number (match-string 2 ts)))
           (day   (string-to-number (match-string 3 ts)))
           (mon   (jetpacs-month-abbrev month))
           (time  (glasspane-ui--ts-time ts)))
      (if time (format "%s %d %s" mon day time)
        (format "%s %d" mon day)))))

(defun glasspane-ui--card-date-row (it)
  "An inline scheduling indicator for card item IT.
Shows compact icon + text labels for SCHEDULED and/or DEADLINE when present.
Returns nil when neither is set."
  (let* ((scheduled (alist-get 'scheduled it))
         (deadline  (alist-get 'deadline it))
         (slabel (glasspane-ui--card-date-label scheduled))
         (dlabel (glasspane-ui--card-date-label deadline))
         (children (delq nil
                         (list
                          (when slabel (jetpacs-icon "schedule" :size 14 :color "#9E9E9E"))
                          (when slabel (jetpacs-text (concat " " slabel) 'caption))
                          (when (and slabel dlabel) (jetpacs-spacer :width 16))
                          (when dlabel (jetpacs-icon "flag" :size 14 :color "#EF5350"))
                          (when dlabel (jetpacs-text (concat " " dlabel) 'caption))))))
    (when children
      (apply #'jetpacs-row children))))

(defun glasspane-ui--agenda-day-view (items)
  (let ((cards (mapcar #'glasspane-ui--agenda-card items)))
    (if cards
        (apply #'jetpacs-lazy-column cards)
      (jetpacs-empty-state :icon "event_busy"
                        :title "No agenda items"
                        :caption "Nothing scheduled for this day."))))

(defun glasspane-ui--agenda-week-view (items)
  (let ((elements nil)
        (current-date nil))
    (dolist (it items)
      (let ((date (alist-get 'date it)))
        (unless (equal date current-date)
          (setq current-date date)
          (push (jetpacs-section-header (or date "Unknown Date")) elements))
        (push (glasspane-ui--agenda-card it) elements)))
    (if elements
        (apply #'jetpacs-lazy-column (nreverse elements))
      (jetpacs-empty-state :icon "event_busy"
                        :title "No agenda items"
                        :caption "Nothing scheduled for this week."))))

(defun glasspane-ui--agenda-month-view (items anchor)
  "Month calendar for ITEMS, showing the month containing ANCHOR (YYYY-MM-DD).
The grid is the curated `month_grid' node when the companion has it
\(month swipe, today/selection states, a11y grid semantics); an older
companion gets `glasspane-ui--agenda-month-fallback' — the composed
`flow_row'-style grid, the documented fallback recipe."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (month-prefix (substring anchor 0 7))
         (sel (jetpacs-ui-state "agenda-selected-date"))
         ;; A remembered selection only counts inside the shown month;
         ;; otherwise select today (when visible) or the anchor day.
         (selected-date (cond
                         ((and (stringp sel) (string-prefix-p month-prefix sel)) sel)
                         ((string-prefix-p month-prefix today) today)
                         (t anchor)))
         (items-by-date (seq-group-by (lambda (it) (alist-get 'date it)) items))
         (selected-items (cdr (assoc selected-date items-by-date))))
    (jetpacs-column
     (if (jetpacs-node-supported-p "month_grid")
         (jetpacs-month-grid month-prefix
                          ;; One mark per date, dots = item count (the
                          ;; companion caps the render at 3).
                          :marks (delq nil
                                       (mapcar (lambda (g)
                                                 (and (stringp (car g))
                                                      (cons (car g)
                                                            (length (cdr g)))))
                                               items-by-date))
                          :selected selected-date
                          ;; Taps arrive with the ISO date as args.value.
                          :on-day-tap (jetpacs-action "agenda.select-date")
                          ;; Companion-local swipe/chevrons report the shown
                          ;; month; the handler re-anchors and pushes fresh
                          ;; marks for it.
                          :on-month-change (jetpacs-action "agenda.set-month"))
       (glasspane-ui--agenda-month-fallback items-by-date anchor selected-date))
     (jetpacs-divider)
     (jetpacs-section-header (format "Events for %s" selected-date))
     (if selected-items
         (apply #'jetpacs-lazy-column (mapcar #'glasspane-ui--agenda-card selected-items))
       (jetpacs-text "No events" 'caption)))))

(defun glasspane-ui--agenda-month-fallback (items-by-date anchor selected-date)
  "The composed month grid for companions that predate `month_grid'."
  (let* ((month (string-to-number (substring anchor 5 7)))
         (year (string-to-number (substring anchor 0 4)))
         (days-in-month (calendar-last-day-of-month month year))
         (first-day-of-month (calendar-day-of-week (list month 1 year)))
         (grid-rows nil)
         (current-day 1)
         (week-header (apply #'jetpacs-row
                             (mapcar (lambda (d) (jetpacs-box (list (jetpacs-text d 'caption)) :weight 1 :alignment "center"))
                                     '("S" "M" "T" "W" "T" "F" "S")))))
    (while (<= current-day days-in-month)
      (let ((row-cells nil))
        (dotimes (dow 7)
          (if (or (and (= current-day 1) (< dow first-day-of-month))
                  (> current-day days-in-month))
              (push (jetpacs-box (list (jetpacs-spacer)) :weight 1) row-cells)
            (let* ((date-str (format "%04d-%02d-%02d" year month current-day))
                   (day-items (cdr (assoc date-str items-by-date)))
                   (is-selected (equal date-str selected-date))
                   (text-color (if is-selected "#FFFFFF" nil))
                   (bg-color (if is-selected "#1976D2" nil))
                   (cell-content (list
                                  (jetpacs-surface
                                   (list
                                    (jetpacs-text (number-to-string current-day) 'body nil text-color)
                                    (if day-items
                                        (jetpacs-icon "circle" :size 6 :color (if is-selected "#FFFFFF" "#1976D2") :padding 2)
                                      (jetpacs-spacer :height 8)))
                                   :color bg-color :shape "rounded" :padding 4))))
              (push (jetpacs-box cell-content :weight 1 :alignment "center"
                              :on-tap (jetpacs-action "agenda.select-date" :args `((date . ,date-str))))
                    row-cells)
              (setq current-day (1+ current-day)))))
        (push (apply #'jetpacs-row (nreverse row-cells)) grid-rows)))
    (jetpacs-column
     week-header
     (jetpacs-spacer :height 8)
     (apply #'jetpacs-column (nreverse grid-rows)))))

(defun glasspane-ui--agenda-modes ()
  "The agenda's mode names in display order: the spans, then customs."
  (append '("day" "week" "month") (mapcar #'car glasspane-org-custom-agendas)))

(defun glasspane-ui--agenda-items-for (mode anchor)
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
          ("day" (glasspane-org--agenda-items 'day start-day))
          ("week" (glasspane-org--agenda-items 'week start-day))
          ("month" (glasspane-org--agenda-items 'month start-day))
          (_ (glasspane-org--search
              (cdr (assoc mode glasspane-org-custom-agendas)))))
      (error nil))))

(defun glasspane-ui--agenda-nav-affordance (mode anchor)
  "MODE's date-navigation row, or nil when the view navigates itself.
The curated month grid carries its own header, chevrons, and swipe —
only the jump-home chip remains ours there; custom agendas have no
anchor to navigate."
  (cond
   ((and (equal mode "month") (jetpacs-node-supported-p "month_grid"))
    (unless (equal (substring anchor 0 7) (format-time-string "%Y-%m"))
      (jetpacs-row
       (jetpacs-spacer :weight 1)
       (jetpacs-assist-chip "Today" :icon "today"
                         :on-tap (jetpacs-action "agenda.today")))))
   ((member mode '("day" "week" "month"))
    (glasspane-ui--agenda-nav-row mode anchor))))

(defun glasspane-ui--agenda-mode-view (mode items anchor)
  "MODE's item rendering, chrome-free."
  (pcase mode
    ("day" (glasspane-ui--agenda-day-view items))
    ("week" (glasspane-ui--agenda-week-view items))
    ("month" (glasspane-ui--agenda-month-view items anchor))
    (_ (if items
           (apply #'jetpacs-lazy-column (mapcar #'glasspane-ui--agenda-card items))
         (jetpacs-empty-state :icon "event_busy"
                           :title "No results"
                           :caption "This custom agenda found no items.")))))

(defun glasspane-ui--agenda-page (mode anchor)
  "One agenda page: MODE's nav affordance above its body."
  (apply #'jetpacs-column
         (delq nil
               (list (glasspane-ui--agenda-nav-affordance mode anchor)
                     (jetpacs-spacer :height 4)
                     (glasspane-ui--agenda-mode-view
                      mode (glasspane-ui--agenda-items-for mode anchor)
                      anchor)))))

(defun glasspane-ui--agenda-body ()
  (let ((mode (or (jetpacs-ui-state "agenda-mode") "day"))
        (anchor (glasspane-ui--agenda-anchor)))
    (if (jetpacs-node-supported-p "tabs")
        (glasspane-ui--agenda-body-tabs mode anchor)
      (glasspane-ui--agenda-body-chips mode anchor))))

(defun glasspane-ui--agenda-body-tabs (mode anchor)
  "The agenda as native tabs: swipe between the spans and custom agendas.
Switching is companion-local — every page ships in the push, which the
memoised extractions keep cheap — and works offline; on_change keeps
Emacs's mode state in step so the anchor and nav logic follow on the
next push. No :id — a background re-push must not yank the user's tab."
  (let* ((modes (glasspane-ui--agenda-modes))
         (initial (or (seq-position modes mode) 0)))
    (jetpacs-tabs
     (mapcar (lambda (m)
               (jetpacs-tab-item (pcase m
                                   ("day" "Day") ("week" "Week")
                                   ("month" "Month") (_ m))))
             modes)
     (mapcar (lambda (m) (glasspane-ui--agenda-page m anchor)) modes)
     :initial initial
     :scrollable (> (length modes) 3)
     :on-change (jetpacs-action "agenda.set-mode" :when-offline "drop"))))

(defun glasspane-ui--agenda-body-chips (mode anchor)
  "The chip-row agenda for companions predating the `tabs' node."
  (let ((custom-chips
         (mapcar (lambda (ca)
                   (let ((name (car ca)))
                     (jetpacs-chip name
                                :selected (equal mode name)
                                :on-tap (jetpacs-action "agenda.set-mode"
                                                     :args `((mode . ,name))))))
                 glasspane-org-custom-agendas)))
    (jetpacs-column
     (apply #'jetpacs-flow-row
            (jetpacs-chip "Day"
                       :selected (equal mode "day")
                       :on-tap (jetpacs-action "agenda.set-mode" :args '((mode . "day"))))
            (jetpacs-chip "Week"
                       :selected (equal mode "week")
                       :on-tap (jetpacs-action "agenda.set-mode" :args '((mode . "week"))))
            (jetpacs-chip "Month"
                       :selected (equal mode "month")
                       :on-tap (jetpacs-action "agenda.set-mode" :args '((mode . "month"))))
            custom-chips)
     (glasspane-ui--agenda-page mode anchor))))

(defun glasspane-ui--tasks-body ()
  (let* ((items (condition-case nil
                    (glasspane-org--todo-items)
                  (error nil)))
         (filtered (if (equal glasspane-ui--tasks-filter "ALL") items
                     (cl-remove-if-not
                      (lambda (it)
                        (equal (alist-get 'todo it) glasspane-ui--tasks-filter))
                      items)))
         (cards (mapcar #'glasspane-ui--agenda-card filtered)))
    (jetpacs-column
     (apply #'jetpacs-flow-row
            (mapcar (lambda (kw)
                      (jetpacs-chip kw
                                 :selected (equal glasspane-ui--tasks-filter kw)
                                 :on-tap (jetpacs-action "tasks.filter"
                                                      :args `((filter . ,kw)))))
                    (cons "ALL" (or (glasspane-ui--global-todo-keywords)
                                    '("TODO" "DONE")))))
     (if cards
         (apply #'jetpacs-lazy-column cards)
       (jetpacs-empty-state :icon "task_alt"
                         :title "No tasks"
                         :caption "Nothing matches this filter.")))))

(defun glasspane-ui--ts-date (ts)
  "Return the YYYY-MM-DD date inside org timestamp string TS, or nil."
  (when (and (stringp ts)
             (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" ts))
    (match-string 1 ts)))

(defun glasspane-ui--ts-time (ts)
  "Return the HH:MM time inside org timestamp string TS, or nil."
  (when (and (stringp ts)
             (string-match "\\([0-9]\\{1,2\\}:[0-9]\\{2\\}\\)" ts))
    (match-string 1 ts)))

(defun glasspane-ui--ts-repeater (ts)
  "Return the repeater cookie (e.g. \"+1w\", \".+2d\") inside TS, or nil.
The one part of a timestamp the date-stamp chip can't display."
  (when (and (stringp ts)
             (string-match "\\([.+]?\\+[0-9]+[hdwmy]\\)" ts))
    (match-string 1 ts)))

(jetpacs-defaction "tasks.filter"
  (lambda (args _)
    (setq glasspane-ui--tasks-filter (alist-get 'filter args))
    (jetpacs-shell-push)))

(defun glasspane-ui--todo-keywords-apply (seqs)
  "Make SEQS the effective and persisted `org-todo-keywords'.
Live org buffers cache the keywords buffer-locally at mode init
(`org-todo-keywords-1', `org-todo-regexp', ...), so each one is
restarted, and the org memo cache is dropped so task views re-render
with the new states.  Returns non-nil when persisting succeeded."
  (customize-set-variable 'org-todo-keywords seqs)
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'org-mode)
        (ignore-errors (org-mode-restart)))))
  (glasspane-org-cache-invalidate)
  (glasspane-ui--customize-save 'org-todo-keywords seqs))

(jetpacs-defaction "settings.todo.save"
  (lambda (args _)
    (let* ((idx (alist-get 'index args))
           (type (intern (alist-get 'type args)))
           (parse (lambda (id)
                    (delq nil
                          (mapcar (lambda (x)
                                    (let ((x (replace-regexp-in-string "^[ \t\n\r]+\\|[ \t\n\r]+$" "" x)))
                                      (if (equal x "") nil x)))
                                  (split-string (or (jetpacs-ui-state id) "") ",")))))
           (active (funcall parse "todo-active"))
           (finished (funcall parse "todo-finished"))
           (seqs (copy-sequence (or (default-value 'org-todo-keywords) '((sequence "TODO" "DONE")))))
           (new-seq (append (list type) active (when finished (cons "|" finished)))))
      (cond
       ((and (null active) (null finished))
        (jetpacs-shell-notify "A sequence needs at least one state"))
       ((>= idx (length seqs))
        ;; Stale index: the list changed since the dialog was built.
        (jetpacs-shell-notify "Sequences changed underneath; reopen the editor")
        (jetpacs-dismiss-dialog)
        (jetpacs-shell-push))
       (t
        (if (>= idx 0)
            (setcar (nthcdr idx seqs) new-seq)
          (setq seqs (append seqs (list new-seq))))
        (when (glasspane-ui--todo-keywords-apply seqs)
          (jetpacs-shell-notify "TODO sequence saved"))
        (jetpacs-dismiss-dialog)
        (jetpacs-shell-push))))))

(jetpacs-defaction "settings.todo.delete"
  (lambda (args _)
    (let* ((idx (alist-get 'index args))
           (seqs (or (default-value 'org-todo-keywords) '((sequence "TODO" "DONE")))))
      (when (and (>= idx 0) (< idx (length seqs)))
        (setq seqs (or (append (cl-subseq seqs 0 idx) (cl-subseq seqs (1+ idx)))
                       ;; Org misbehaves with no keywords at all; deleting
                       ;; the last sequence falls back to the stock one.
                       '((sequence "TODO" "|" "DONE"))))
        (when (glasspane-ui--todo-keywords-apply seqs)
          (jetpacs-shell-notify "TODO sequence deleted"))
        (jetpacs-dismiss-dialog)
        (jetpacs-shell-push)))))

(jetpacs-defaction "agenda.set-mode"
  ;; `mode' names come from the fallback chips; `value' (a page index)
  ;; from the tabs body's on_change. Either way the result must name a
  ;; mode we actually offer.
  (lambda (args _)
    (let* ((modes (glasspane-ui--agenda-modes))
           (idx (alist-get 'value args))
           (mode (or (alist-get 'mode args)
                     (and (integerp idx) (nth idx modes)))))
      (when (member mode modes)
        (jetpacs-ui-state-put "agenda-mode" mode)
        (jetpacs-shell-push)))))

(jetpacs-defaction "agenda.nav"
  ;; Shift the agenda anchor by DIR (±1) in units of the active span.
  (lambda (args _)
    (let* ((dir (alist-get 'dir args))
           (dir (if (numberp dir) dir 1))
           (mode (or (jetpacs-ui-state "agenda-mode") "day"))
           (unit (pcase mode ("week" 'week) ("month" 'month) (_ 'day)))
           (anchor (glasspane-ui--agenda-anchor)))
      ;; Month steps walk 1st → 1st so ±1 never skips a short month.
      (when (eq unit 'month)
        (setq anchor (concat (substring anchor 0 7) "-01")))
      (jetpacs-ui-state-put "agenda-anchor"
                         (glasspane-ui--shift-date anchor dir unit))
      (jetpacs-shell-push))))

(defun glasspane-ui--org-editor-body (file)
  "Reader body for org FILE while read mode is on; nil = plain editor.
A filter row narrows the headings by the standard query syntax — the
orgro sparse-filter parity item."
  (when (and glasspane-ui--files-read-mode (glasspane-ui--org-file-p file))
    (if glasspane-ui--files-refile-mode
        (or (glasspane-org-reader-refile-list file)
            (jetpacs-text "No headings to show." 'caption))
      (let* ((items (glasspane-org--file-heading-items file))
             (query (string-trim glasspane-ui--files-filter))
             (active (not (string-empty-p query)))
             (filtered (if (not active) items
                         (condition-case err
                             (glasspane-org--filter-items items query)
                           (user-error
                            (list 'error (error-message-string err))))))
             (broken (eq (car-safe filtered) 'error)))
        (apply #'jetpacs-lazy-column
               (append
                (list (jetpacs-text-input "files-filter"
                                       :value glasspane-ui--files-filter
                                       :hint "Filter: todo:TODO tags:work text…"
                                       :single-line t
                                       :on-submit
                                       (jetpacs-action "files.filter"
                                                    :when-offline "drop")))
                (when (and active (not broken))
                  (list (jetpacs-row
                         (jetpacs-box
                          (list (jetpacs-text
                                 (format "%d of %d headings"
                                         (length filtered) (length items))
                                 'caption))
                          :weight 1)
                         (jetpacs-chip "Clear"
                                    :on-tap (jetpacs-action
                                             "files.filter"
                                             :args '((value . ""))
                                             :when-offline "drop")))))
                (cond
                 (broken (list (jetpacs-text (cadr filtered) 'caption)))
                 ((null filtered)
                  (list (jetpacs-empty-state
                         :icon "description"
                         :title (if active "No matches" "Empty file")
                         :caption (if active query "No headings found."))))
                 (t (mapcar #'glasspane-ui--agenda-card filtered)))))))))

(provide 'glasspane-agenda)
