;;; glasspane-ui.el --- The Glasspane org app for Jetpacs -*- lexical-binding: t; -*-

;; The reference Tier 1 app: registers the org views (agenda, tasks, clock,
;; search, detail, settings) into the generic shell (jetpacs-shell.el) and
;; handles their semantic actions.  Everything here is one opinionated take
;; built on the core seams — shell views, the files module's editor hooks,
;; the settings registry, the render-buffer skin registry.  Nothing below
;; is required for the core bridge to function.

;;; Code:

(require 'jetpacs)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-apps)
(require 'glasspane-org)
(require 'glasspane-clock)
(require 'glasspane-org-reader)
(require 'jetpacs-files)
(require 'jetpacs-keymap)
(require 'jetpacs-magit)
(require 'jetpacs-settings)
;; Not used directly — pulled in so (require 'glasspane-ui) still assembles
;; the complete reference app for init-file users.
(require 'jetpacs-emacs-ui)
(require 'jetpacs-package-browser)
(require 'cl-lib)

(defvar glasspane-ui--detail-ref nil
  "Reference alist (id/file/pos/headline) of the heading being viewed, or nil.")

(defvar glasspane-ui--detail-read-mode t
  "When non-nil, detail view shows the foldable reader instead of the editor.")

(defvar glasspane-ui--tasks-filter "ALL"
  "Current filter for the Tasks tab.")

(defvar glasspane-ui--search-query ""
  "Last submitted query for the Search view.")

(defcustom glasspane-org-custom-agendas nil
  "Alist of custom agenda views (Name . Query) for Jetpacs."
  :type '(alist :key-type string :value-type string)
  :group 'jetpacs)

(defvar glasspane-ui--search-results nil
  "Cached heading items from the last search.")

(defvar glasspane-ui--search-error nil
  "Human-readable message when the last search query failed, else nil.")

;; ─── Reminders & home-screen widget (piggybacked on each shell push) ────────

(defvar glasspane-ui--last-reminders 'unset
  "Reminder list from the previous sync, to suppress identical sends.")

(defun glasspane-ui--sync-reminders ()
  "Send upcoming timed items to the companion as exact-alarm reminders."
  (let ((rems (condition-case nil (glasspane-org--upcoming-reminders) (error nil))))
    (unless (equal rems glasspane-ui--last-reminders)
      (setq glasspane-ui--last-reminders rems)
      (jetpacs-send "reminders.set" `((reminders . ,(vconcat rems)))))))

(defvar glasspane-ui--last-widget 'unset
  "Widget views from the previous push, to suppress identical pushes.")

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

(defun glasspane-ui--widget-row (it)
  "Build one generic widget row from agenda item IT.
All semantics live here: the row tap opens the heading in the app, the
trailing circle todo-cycles silently — the companion just renders."
  (let* ((hm (glasspane-org--item-hm (alist-get 'time it)))
         (todo (alist-get 'todo it))
         (done (and todo
                    (member todo (or (default-value 'org-done-keywords)
                                     '("DONE" "CANCELLED")))
                    t))
         (ref (alist-get 'ref it))
         (meta (glasspane-ui--widget-item-meta it hm))
         (meta (unless (string-empty-p meta) meta)))
    (jetpacs-widget-item
     (or (alist-get 'headline it) "Untitled")
     :todo todo :done done
     :meta meta
     :icon (and meta (glasspane-ui--widget-agenda-icon (alist-get 'type it)))
     :on-tap (jetpacs-action "heading.tap" :args ref) :in-app t
     :button (and todo (if done "todo_done" "todo_open"))
     :on-button (and todo (jetpacs-action "heading.todo-cycle" :args ref)))))

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

(defun glasspane-ui--widget-query-items (query)
  "Custom-agenda QUERY results as widget rows.
Search hits carry no agenda qualifiers — the metadata line is the file
name under a folder icon. `glasspane-org--search' is memoised, so
re-pushing is cheap."
  (mapcar
   (lambda (it)
     (let* ((todo (alist-get 'todo it))
            (done (and todo
                       (member todo (or (default-value 'org-done-keywords)
                                        '("DONE" "CANCELLED")))
                       t))
            (file (alist-get 'file it))
            (ref (alist-get 'ref it)))
       (jetpacs-widget-item
        (or (alist-get 'headline it) "Untitled")
        :todo todo :done done
        :meta (and file (file-name-nondirectory file))
        :icon (and file "folder")
        :on-tap (jetpacs-action "heading.tap" :args ref) :in-app t
        :button (and todo (if done "todo_done" "todo_open"))
        :on-button (and todo (jetpacs-action "heading.todo-cycle" :args ref)))))
   (seq-take (condition-case nil (glasspane-org--search query) (error nil))
             20)))

(defun glasspane-ui--push-widget ()
  "Push the `widget:agenda' surface backing the home-screen widget.
A multi-view spec: \"today\" (the day agenda) plus one view per
`glasspane-org-custom-agendas' entry. The widget's header selector
switches between them companion-side from cache, so it works offline.
View keys are interned because `json-serialize' requires symbol keys."
  (let ((views
         (cons
          (cons 'today
                `((title . ,(format-time-string "Agenda · %a %b %d"))
                  (items . ,(vconcat (glasspane-ui--widget-items)))))
          (mapcar (lambda (ca)
                    (cons (intern (car ca))
                          `((title . ,(car ca))
                            (items . ,(vconcat (glasspane-ui--widget-query-items
                                                (cdr ca)))))))
                  glasspane-org-custom-agendas))))
    (unless (equal views glasspane-ui--last-widget)
      (setq glasspane-ui--last-widget views)
      (jetpacs-surface-push
       "widget:agenda"
       `((views . ,views)
         (initial_view . "today"))))))

;; Both are memo-guarded, so unchanged data sends nothing.
(add-hook 'jetpacs-shell-after-push-hook #'glasspane-ui--sync-reminders)
(add-hook 'jetpacs-shell-after-push-hook #'glasspane-ui--push-widget)

(defun glasspane-ui--forget-widget-memo ()
  "Force the next widget push even when the items are unchanged.
An explicit refresh (`dashboard.refresh', e.g. the widget's refresh
button) must visibly bump the widget's \"Synced\" caption, and a
suppressed identical push would leave it frozen."
  (setq glasspane-ui--last-widget 'unset))

(add-hook 'jetpacs-shell-refresh-hook #'glasspane-ui--forget-widget-memo)

;; ─── Shell views ─────────────────────────────────────────────────────────────

(defun glasspane-ui--agenda-view (snackbar)
  (jetpacs-shell-tab-view "agenda" (glasspane-ui--agenda-body)
                       :snackbar snackbar))

(defun glasspane-ui--tasks-view (snackbar)
  (jetpacs-shell-tab-view "tasks" (glasspane-ui--tasks-body)
                       :snackbar snackbar))

(defun glasspane-ui--clock-view (snackbar)
  (jetpacs-shell-tab-view "clock" (glasspane-ui--clock-body)
                       :snackbar snackbar))

(defun glasspane-ui--search-view (snackbar)
  (jetpacs-shell-nav-view "Search" (glasspane-ui--search-body)
                       :snackbar snackbar))

(defun glasspane-ui--settings-view (snackbar)
  (jetpacs-shell-nav-view "Settings" (glasspane-ui--settings-body)
                       :snackbar snackbar))

(defun glasspane-ui--detail-view (snackbar)
  "The heading drill-in: reader/editor body under curated heading actions."
  (let* ((ref glasspane-ui--detail-ref)
         (file (and ref (alist-get 'file ref)))
         (pos (and ref (alist-get 'pos ref)))
         (buf (and file (find-buffer-visiting file)))
         (is-clocked-in (and buf
                             (bound-and-true-p org-clock-hd-marker)
                             (marker-buffer org-clock-hd-marker)
                             (equal buf (marker-buffer org-clock-hd-marker))
                             (with-current-buffer buf
                               (= (line-number-at-pos pos)
                                  (line-number-at-pos org-clock-hd-marker))))))
    (jetpacs-shell-nav-view
     "Detail" (glasspane-ui--detail-body-with-notes ref)
     ;; Back is pure navigation: builtin = instant, local, works offline.
     ;; heading.back stays registered for compatibility but nothing emits
     ;; it anymore.
     :actions (delq nil
                    (list
                     (when ref
                       (if is-clocked-in
                           (jetpacs-icon-button "timer_off" (jetpacs-action "org.clock.out")
                                             :content-description "Clock Out")
                         (jetpacs-icon-button "timer" (jetpacs-action "heading.clock-in" :args ref)
                                           :content-description "Clock In")))
                     (jetpacs-icon-button
                      (if glasspane-ui--detail-read-mode "edit" "visibility")
                      (jetpacs-action "detail.toggle-read")
                      :content-description
                      (if glasspane-ui--detail-read-mode "Edit" "Read"))
                     (when (and ref (glasspane-ui--org-file-p file))
                       (jetpacs-icon-button
                        "tune"
                        (jetpacs-action "files.properties.show"
                                     :args `((file . ,file)))
                        :content-description "Properties"))))
   :bottom-bar (when glasspane-ui--detail-read-mode
                 (jetpacs-bottom-bar
                  (list
                   (jetpacs-nav-item
                    "note_add" "New Note"
                    (jetpacs-action "heading.add-note"
                                 :args glasspane-ui--detail-ref
                                 :when-offline "drop")))))
   :floating-toolbar (when glasspane-ui--detail-read-mode
                       (vconcat
                        (list
                         (jetpacs-nav-item
                          "drive_file_move" "Refile"
                          (jetpacs-action "heading.refile"
                                       :args glasspane-ui--detail-ref
                                       :when-offline "drop"))
                         (jetpacs-nav-item
                          "archive" "Archive"
                          (jetpacs-action "heading.archive"
                                       :args glasspane-ui--detail-ref
                                       :when-offline "drop")))))
   :snackbar snackbar)))

(jetpacs-shell-define-view "agenda" :builder #'glasspane-ui--agenda-view
                        :tab '(:icon "event" :label "Agenda") :order 10)
(jetpacs-shell-define-view "tasks" :builder #'glasspane-ui--tasks-view
                        :tab '(:icon "checklist" :label "Tasks") :order 20)
;; The clock lost its tab 2026-07-06 (user decision: six tabs was
;; crowded and the screen alone felt barren) — its body now renders as
;; a section of the Journal view.  The view stays registered so cached
;; `view.switch' targets from older pushes still resolve.
(jetpacs-shell-define-view "clock" :builder #'glasspane-ui--clock-view
                        :order 30)
(jetpacs-shell-define-view "search" :builder #'glasspane-ui--search-view
                        :order 70)
(jetpacs-shell-define-view "settings" :builder #'glasspane-ui--settings-view
                        :order 80)
(jetpacs-shell-define-view "detail" :builder #'glasspane-ui--detail-view
                        :when (lambda () (and glasspane-ui--detail-ref t))
                        :overlay (lambda () (and glasspane-ui--detail-ref t))
                        :order 110)

;; Glasspane is the first `jetpacs-defapp'. Zero visible change while it is
;; the only app; load a second app (jetpacs-hello.el) and the launcher home
;; appears with these views grouped as Glasspane's own.
(jetpacs-defapp "glasspane" :label "Glasspane" :icon "event"
             :views '("agenda" "journal" "tasks" "clock" "search" "views"
                      "srs" "settings" "detail")
             :order 10)

;; Landing on any non-overlay view closes the detail drill-in.
(add-hook 'jetpacs-shell-view-switched-hook
          (lambda (_view) (setq glasspane-ui--detail-ref nil)))

;; Capture is this app's global affordance: the default FAB on every tab
;; view that doesn't define its own.
(setq jetpacs-shell-default-fab-function
      (lambda (_name)
        (jetpacs-fab "add" :label "Capture"
                  :on-tap (jetpacs-action "org.capture.show"))))

;; Search from every tab's top bar; Settings from the drawer.  (There
;; used to be a second filter_list icon here doing the same switch —
;; one affordance per destination.)
(jetpacs-shell-add-top-action
 10 (lambda () (jetpacs-icon-button "search" (jetpacs-shell-switch-view "search")
                                 :content-description "Search")))
(jetpacs-shell-add-drawer-item
 60 (lambda () (jetpacs-drawer-item "settings" "Settings"
                                 (jetpacs-shell-switch-view "settings"))))

;; The org extractions are memoised; an explicit refresh (pull-to-refresh,
;; the drawer item, a queue drain) must drop them.
(add-hook 'jetpacs-shell-refresh-hook #'glasspane-org-cache-invalidate)

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
           (mon   (aref jetpacs--month-abbrevs (1- month)))
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

(defun glasspane-ui--agenda-card (it)
  "A detail-rich agenda card for item IT.
Leading time (or a type icon), priority-prefixed headline (struck
through when done), a todo/type/file caption, tag chips when present,
and a quick complete button for open todos."
  (let* ((headline (or (alist-get 'headline it) "Untitled"))
         (todo (alist-get 'todo it))
         ;; Normalized "HH:MM" — the raw property is a time-grid string
         ;; like " 9:15......".
         (time (glasspane-org--item-hm (alist-get 'time it)))
         (type (alist-get 'type it))
         (file (alist-get 'file it))
         (priority (alist-get 'priority it))
         (tags (append (alist-get 'tags it) nil))
         (ref (alist-get 'ref it))
         (done (and todo (member todo (or (default-value 'org-done-keywords)
                                          '("DONE" "CANCELLED")))))
         (icon+color (glasspane-ui--agenda-type-icon type))
         (caption (string-join
                   (delq nil (list todo
                                   (and (stringp type)
                                        (glasspane-ui--agenda-type-label type))
                                   (and file (file-name-nondirectory file))))
                   "  ·  "))
         (lead (cond ((and (stringp time) (not (string-empty-p time)))
                      (jetpacs-text time 'label))
                     (icon+color
                      (jetpacs-icon (car icon+color) :size 18 :color (cdr icon+color)))))
         (headline-node
          (jetpacs-rich-text
           (delq nil
                 (list
                  (when priority
                    (jetpacs-span (format "[%s] " priority) :bold t :color "#F57C00"))
                  (if done
                      (jetpacs-span headline :strike t)
                    (jetpacs-span headline))))))
         (middle
          (apply #'jetpacs-column
                 (delq nil
                       (list
                        headline-node
                        (unless (string-empty-p caption)
                          (jetpacs-text caption 'caption))
                        (glasspane-ui--card-date-row it)
                        (when tags
                          (apply #'jetpacs-flow-row
                                 (mapcar (lambda (tg)
                                           (jetpacs-assist-chip tg :on-tap (jetpacs-action "search.by-tag" :args `((tag . ,tg)))))
                                         tags))))))))
    (jetpacs-card
     (list (apply #'jetpacs-row
                  (delq nil (list lead
                                  (jetpacs-box (list middle) :weight 1)))))
     :on-tap (jetpacs-action "heading.tap" :args ref)
     :on-swipe (jetpacs-action "heading.todo-cycle" :args ref))))

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
  "Month grid for ITEMS, showing the month containing ANCHOR (YYYY-MM-DD)."
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
         (selected-items (cdr (assoc selected-date items-by-date)))
         (month (string-to-number (substring anchor 5 7)))
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
     (apply #'jetpacs-column (nreverse grid-rows))
     (jetpacs-divider)
     (jetpacs-section-header (format "Events for %s" selected-date))
     (if selected-items
         (apply #'jetpacs-lazy-column (mapcar #'glasspane-ui--agenda-card selected-items))
       (jetpacs-text "No events" 'caption)))))

(defun glasspane-ui--agenda-body ()
  (let* ((mode (or (jetpacs-ui-state "agenda-mode") "day"))
         (is-span (member mode '("day" "week" "month")))
         (anchor (glasspane-ui--agenda-anchor))
         ;; The month span always starts on the 1st so the grid and the
         ;; extraction agree on the visible range.
         (start-day (cond ((equal mode "month") (concat (substring anchor 0 7) "-01"))
                          (is-span anchor)))
         (items (cond
                 ((equal mode "day") (condition-case nil (glasspane-org--agenda-items 'day start-day) (error nil)))
                 ((equal mode "week") (condition-case nil (glasspane-org--agenda-items 'week start-day) (error nil)))
                 ((equal mode "month") (condition-case nil (glasspane-org--agenda-items 'month start-day) (error nil)))
                 (t (condition-case nil (glasspane-org--search (cdr (assoc mode glasspane-org-custom-agendas))) (error nil)))))
         (custom-chips (mapcar (lambda (ca)
                                 (let ((name (car ca)))
                                   (jetpacs-chip name
                                              :selected (equal mode name)
                                              :on-tap (jetpacs-action "agenda.set-mode" :args `((mode . ,name))))))
                               glasspane-org-custom-agendas)))
    (apply #'jetpacs-column
           (delq nil
                 (list
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
                  (when is-span
                    (glasspane-ui--agenda-nav-row mode anchor))
                  (jetpacs-spacer :height 4)
                  (cond
                   ((equal mode "day")
                    (glasspane-ui--agenda-day-view items))
                   ((equal mode "week")
                    (glasspane-ui--agenda-week-view items))
                   ((equal mode "month")
                    (glasspane-ui--agenda-month-view items anchor))
                   (t
                    (if items
                        (apply #'jetpacs-lazy-column (mapcar #'glasspane-ui--agenda-card items))
                      (jetpacs-empty-state :icon "event_busy"
                                        :title "No results"
                                        :caption "This custom agenda found no items.")))))))))

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

;; The old agenda-files-only "files" body is superseded by the full
;; browser in jetpacs-files.el (jetpacs-files-browser-body).

(defun glasspane-ui--clock-body ()
  (let* ((status (glasspane-org--clock-status))
         (recent (condition-case nil
                     (glasspane-org--recent-clocks 5)
                   (error nil)))
         (status-card
          (if status
              (let* ((start (alist-get 'start status))
                     (mins (when start
                             (max 0 (floor (/ (- (float-time) start) 60))))))
                (jetpacs-card
                 (list (jetpacs-column
                        (jetpacs-text "Currently Clocked In" 'caption)
                        (jetpacs-text (or (alist-get 'task status) "?") 'headline)
                        (jetpacs-text (if mins (format "%d min elapsed" mins) "")
                                   'caption)
                        (jetpacs-button "Clock Out" (jetpacs-action "org.clock.out"))))))
            (jetpacs-empty-state :icon "schedule"
                              :title "Not clocked in"
                              :caption "Pick a recent task below to start.")))
         (recent-cards
          (mapcar (lambda (r)
                    (jetpacs-card
                     (list (jetpacs-text (or (alist-get 'headline r) "?") 'body))
                     :on-tap (jetpacs-action "heading.clock-in"
                                          :args (alist-get 'ref r))))
                  recent))
         (all-children (append (list status-card)
                               (when recent-cards
                                 (cons (jetpacs-section-header "Recent Tasks")
                                       recent-cards)))))
    (apply #'jetpacs-column all-children)))

(defun glasspane-ui--result-card (it)
  "Render a search/heading item IT to a tappable card with tag chips."
  (let* ((headline (or (alist-get 'headline it) "?"))
         (todo (alist-get 'todo it))
         (file (alist-get 'file it))
         (tags (append (alist-get 'tags it) nil))
         (ref (alist-get 'ref it))
         (caption (string-join
                   (delq nil (list todo (when file (file-name-nondirectory file))))
                   "  ·  "))
         (children (delq nil
                         (list
                          (jetpacs-text headline 'body)
                          (unless (string-empty-p caption)
                            (jetpacs-text caption 'caption))
                          (when tags
                            (apply #'jetpacs-flow-row
                                   (mapcar (lambda (tg)
                                             (jetpacs-assist-chip tg :on-tap (jetpacs-action "search.by-tag" :args `((tag . ,tg)))))
                                           tags)))))))
    (jetpacs-card (list (apply #'jetpacs-column children))
               :on-tap (jetpacs-action "heading.tap" :args ref))))

(defun glasspane-ui--filter-values (id)
  "Selected values for builder filter ID, as a list of strings.
UI state for an enum may hold the parsed vector from an action's
args, the raw JSON text a `state.changed' event delivered, or a
plain seed string — normalise them all."
  (let ((v (jetpacs-ui-state id)))
    (cond
     ((null v) nil)
     ((vectorp v) (append v nil))
     ((and (stringp v) (string-prefix-p "[" v))
      (condition-case nil
          (append (json-parse-string v) nil)
        (error (list v))))
     ((stringp v) (list v))
     ((listp v) v))))

(defun glasspane-ui--search-builder-section (key label summary widget)
  "One collapsible filter section of the query builder.
KEY names the fold-state id; LABEL is the always-visible section
name.  SUMMARY, when non-nil, is the active filter rendered into the
header so a folded section still shows what it contributes.  WIDGET
is the section's control."
  (jetpacs-collapsible
   (concat "search-sec-" key)
   (if summary
       (jetpacs-rich-text (list (jetpacs-span (concat label ": ") :bold t)
                             (jetpacs-span summary))
                       :style 'body)
     (jetpacs-text label 'body))
   (list widget)
   :collapsed t))

(defun glasspane-ui--search-builder ()
  "The query-builder card for the Search view.
Every filter change reruns the search and writes the equivalent
org-ql query into the search field, so the builder doubles as a
worked example of the query language.  Each filter lives in its own
collapsible section whose header names the active value, so the
folded builder reads as a filter summary.  The whole card starts
folded once a search has results, to keep them above the fold."
  (let* ((todo-val (or (car (glasspane-ui--filter-values "search-filter-todo")) "Any"))
         (tags-list (glasspane-ui--filter-values "search-filter-tags"))
         (text-val (or (jetpacs-ui-state "search-filter-text") ""))
         (prio-val (or (car (glasspane-ui--filter-values "search-filter-priority")) "Any"))
         (due-val (or (car (glasspane-ui--filter-values "search-filter-due")) "Any")))
    (jetpacs-card
     (list
      (jetpacs-collapsible
       "search-builder"
       (jetpacs-text "Query builder" 'headline)
       (list
        (glasspane-ui--search-builder-section
         "todo" "Status" (unless (equal todo-val "Any") todo-val)
         (jetpacs-enum-list "search-filter-todo"
                         (append '("Any") (glasspane-ui--global-todo-keywords)
                                 '("Done (any)"))
                         :value todo-val
                         :on-change (jetpacs-action "search.update-filter"
                                                 :args '((field . "todo")))))
        (glasspane-ui--search-builder-section
         "tags" "Tags (all must match)"
         (when tags-list (string-join tags-list ", "))
         (jetpacs-enum-list "search-filter-tags" (glasspane-org--all-tags)
                         :value (vconcat tags-list)
                         :multi-select t
                         :allow-add t
                         :on-change (jetpacs-action "search.update-filter"
                                                 :args '((field . "tags")))))
        (glasspane-ui--search-builder-section
         "priority" "Priority" (unless (equal prio-val "Any") prio-val)
         (jetpacs-enum-list "search-filter-priority" '("Any" "A" "B" "C")
                         :value prio-val
                         :on-change (jetpacs-action "search.update-filter"
                                                 :args '((field . "priority")))))
        (glasspane-ui--search-builder-section
         "due" "Due" (unless (equal due-val "Any") due-val)
         (jetpacs-enum-list "search-filter-due" '("Any" "Overdue" "Today" "This week")
                         :value due-val
                         :on-change (jetpacs-action "search.update-filter"
                                                 :args '((field . "due")))))
        (glasspane-ui--search-builder-section
         "text" "Text contains"
         (unless (string-empty-p text-val) text-val)
         (jetpacs-text-input "search-filter-text"
                          :value text-val
                          :hint "e.g. meeting notes"
                          :single-line t
                          :on-submit (jetpacs-action "search.update-filter"
                                                  :args '((field . "text")))))
        (jetpacs-row
         (jetpacs-box (list (jetpacs-text "Filters search as you pick them and write the org-ql query below — edit it there to go further."
                                    'caption))
                   :weight 1)
         (jetpacs-button "Clear" (jetpacs-action "search.clear-filters"))))
       :collapsed (and glasspane-ui--search-results t)))
     :padding 16)))

(defun glasspane-ui--search-body ()
  (let* ((q (or glasspane-ui--search-query ""))
         (results glasspane-ui--search-results)
         (input (jetpacs-text-input "search-query"
                                 :value q
                                 :hint "Text, todo:NEXT tags:work, or (org-ql query)"
                                 :single-line t
                                 :on-submit (jetpacs-action "org.search.run")))
         (cards (mapcar #'glasspane-ui--result-card results)))
    ;; One lazy column for the whole view: the builder card can grow
    ;; taller than the screen (a big tag vocabulary), so everything —
    ;; builder, search row, results — must share a single scroll.  A
    ;; plain column gives overflowing children zero height instead.
    (apply
     #'jetpacs-lazy-column
     (glasspane-ui--search-builder)
     (jetpacs-spacer :height 8)
     (jetpacs-row
      (jetpacs-box (list input) :weight 1)
      (jetpacs-button "Search" (jetpacs-action "org.search.run" :args `((value . ,q))))
      (jetpacs-button "Save" (jetpacs-action "agenda.save-custom" :args `((query . ,q)))))
     (jetpacs-spacer :height 8)
     (cond
      (glasspane-ui--search-error
       (list (jetpacs-empty-state :icon "error"
                               :title "Query error"
                               :caption glasspane-ui--search-error)))
      (cards
       (cons (jetpacs-section-header (format "%d match%s" (length cards)
                                          (if (= (length cards) 1) "" "es")))
             cards))
      ((and (stringp q) (not (string-empty-p q)))
       (list (jetpacs-empty-state :icon "manage_search"
                               :title "No matches"
                               :caption (format "Nothing matched \"%s\"." q))))
      (t
       (list (jetpacs-empty-state :icon "search"
                               :title "Search your notes"
                               :caption "Type a query, or open the query builder above.")))))))

(defun glasspane-ui--global-todo-keywords ()
  "Extract a flat list of all global TODO keywords from `org-todo-keywords'."
  (let ((kws nil))
    (dolist (seq (default-value 'org-todo-keywords))
      (dolist (w (cdr seq))
        (unless (string-equal w "|")
          ;; Strip fast-access keys, e.g. "TODO(t)" -> "TODO"
          (push (if (string-match "^\\([a-zA-Z0-9_-]+\\)" w)
                    (match-string 1 w)
                  w)
                kws))))
    (nreverse kws)))

(defun glasspane-ui--split-todo-sequence (seq)
  "Split `org-todo-keywords' entry SEQ into (ACTIVE . FINISHED) keyword lists.
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

(defun glasspane-ui--settings-body ()
  (let* ((available-tags (mapcar (lambda (x) (if (consp x) (car x) x)) org-tag-alist))
         (enum-list (jetpacs-enum-list "settings-tags" available-tags
                                    :value available-tags
                                    :multi-select t
                                    :allow-add t
                                    :on-change (jetpacs-action "settings.tags")))
         (linenum-value (pcase jetpacs-line-numbers
                          ('absolute "Absolute")
                          ('relative "Relative")
                          (_ "Off")))
         (agenda-cards
          (cl-loop for (name . query) in glasspane-org-custom-agendas
                   collect
                   (jetpacs-card
                    (list
                     (jetpacs-row
                      (jetpacs-box
                       (list
                        (jetpacs-column
                         (jetpacs-text name 'label)
                         (jetpacs-text query 'body)))
                       :weight 1)
                      (jetpacs-icon-button "edit"
                                        (jetpacs-action "settings.agenda.edit"
                                                     :args `((name . ,name))
                                                     :when-offline "drop")
                                        :content-description "Edit search")
                      (jetpacs-icon-button "delete"
                                        (jetpacs-action "settings.agenda.delete"
                                                     :args `((name . ,name))
                                                     :when-offline "drop")
                                        :content-description "Delete search"))))))
         (seq-cards
          (condition-case err
              (cl-loop for seq in (or (default-value 'org-todo-keywords) '((sequence "TODO" "DONE")))
                       for i from 0
                       collect
                       (let* ((split (glasspane-ui--split-todo-sequence seq))
                              (bare (lambda (w)
                                      (if (string-match "^\\([a-zA-Z0-9_-]+\\)" w)
                                          (match-string 1 w)
                                        w)))
                              (active (mapcar bare (car split)))
                              (finished (mapcar bare (cdr split))))
                         (jetpacs-card
                          (list
                           (jetpacs-row
                            ;; The text column must carry the flex weight
                            ;; itself: the client renders columns fillMaxWidth,
                            ;; so an unweighted one swallows the whole row and
                            ;; pushes the buttons off-screen.
                            (jetpacs-box
                             (list
                              (jetpacs-column
                               (jetpacs-text (format "Sequence %d" (1+ i)) 'label)
                               (jetpacs-text (concat (mapconcat #'identity active ", ") " | " (mapconcat #'identity finished ", ")) 'body)))
                             :weight 1)
                            (jetpacs-icon-button "edit"
                                              (jetpacs-action "settings.todo.edit"
                                                           :args `((index . ,i))
                                                           :when-offline "drop")
                                              :content-description "Edit sequence")
                            (jetpacs-icon-button "delete"
                                              (jetpacs-action "settings.todo.delete"
                                                           :args `((index . ,i))
                                                           :when-offline "drop")
                                              :content-description "Delete sequence"))))))
            (error (list (jetpacs-text (format "Error loading sequences: %s" (error-message-string err)) 'caption))))))
    ;; lazy_column, not column: the scaffold body has no scroll container
    ;; on the client, so a plain column taller than the screen is simply
    ;; unreachable below the fold.
    (apply #'jetpacs-lazy-column
           (append
            (list (jetpacs-section-header "Display")
                  (jetpacs-text "Line numbers in the buffer view and editor." 'caption)
                  (jetpacs-enum-list "settings-linenum" '("Off" "Absolute" "Relative")
                                  :value (list linenum-value)
                                  :on-change (jetpacs-action "settings.line-numbers"))
                  (jetpacs-divider)
                  (jetpacs-section-header "Saved Searches")
                  (jetpacs-text "Manage your custom agenda queries." 'caption))
            agenda-cards
            (list (jetpacs-button "New Saved Search"
                               (jetpacs-action "settings.agenda.edit")
                               :variant "outlined")
                  (jetpacs-divider)
                  (jetpacs-section-header "Global TODO Sequences")
                  (jetpacs-text "Manage your global TODO states and workflows." 'caption))
            seq-cards
            (list (jetpacs-button "Add Sequence"
                               (jetpacs-action "settings.todo.edit"
                                            :args '((index . -1))
                                            :when-offline "drop")
                               :variant "outlined")
                  (jetpacs-divider)
                  (jetpacs-section-header "Global Org Tags")
                  (jetpacs-text "Manage the global tag list (org-tag-alist)." 'caption)
                  enum-list)
            ;; Schema-driven sections: every allowlisted defcustom in
            ;; `jetpacs-settings-registry', rendered from its custom-type.
            (jetpacs-settings-sections)))))

(defun glasspane-ui--todo-chips (current keywords ref)
  "A single-line chip rail for KEYWORDS with CURRENT selected.
Tapping an active chip removes the state.  Long sequences pan
sideways rather than wrapping into a stack."
  (apply #'jetpacs-scroll-row
         (mapcar (lambda (kw)
                   (jetpacs-chip kw
                              :selected (equal kw current)
                              :on-tap (jetpacs-action
                                       "heading.todo-set"
                                       :args (cons (cons 'state (if (equal kw current) "" kw)) ref))))
                 keywords)))

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

(defun glasspane-ui--priority-chips (current ref)
  "A row of priority chips (A..C) with CURRENT selected; tapping an active chip removes it."
  (let* ((hi (or (bound-and-true-p org-priority-highest) ?A))
         (lo (or (bound-and-true-p org-priority-lowest) ?C))
         (levels (mapcar #'char-to-string (number-sequence hi lo))))
    (apply #'jetpacs-flow-row
           (mapcar (lambda (p)
                     (jetpacs-chip p
                                :selected (equal p current)
                                :on-tap (jetpacs-action
                                         "heading.priority"
                                         :args (cons (cons 'value (if (equal p current) "" p)) ref))))
                   levels))))

(defun glasspane-ui--property-row (key value ref pos)
  "A two-column KEY → editable VALUE row for the detail Properties editor.
KEY renders without org's colons.  ID is shown read-only (editing it
breaks links); every other value is an inline input whose submit runs
`heading.prop-set' — submitting an empty value removes the property."
  (let* ((marker (ignore-errors (glasspane-org--resolve-ref ref)))
         (buf (and marker (marker-buffer marker)))
         (allowed (and buf
                       (with-current-buffer buf
                         (org-with-wide-buffer (goto-char pos)
                           (ignore-errors
                             (org-property-get-allowed-values pos key))))))
         (is-boolean (or (equal allowed '("t" "nil")) (equal allowed '("true" "false"))
                         (string-match-p "\\?" key)))
         (is-date (or (string-match-p "_DATE\\|_TIME\\'" key)
                      (member key '("CREATED" "SCHEDULED" "DEADLINE"))))
         (action (jetpacs-action "heading.prop-set" :args (cons `(name . ,key) ref))))
    (jetpacs-row
     (jetpacs-box (list (jetpacs-text key 'label)) :weight 2)
     (jetpacs-box
      (list (cond
             ((equal key "ID")
              (jetpacs-text value 'caption nil nil t))
             (is-boolean
              (jetpacs-switch (format "prop-%s/%s" pos key)
                           :value (member value '("t" "true" "1"))
                           :on-toggle action))
             ((and allowed (listp allowed))
              (jetpacs-enum-list (format "prop-%s/%s" pos key) allowed
                              :value (list value)
                              :on-select action))
             (is-date
              (jetpacs-date-button value action :value value))
             (t
              (jetpacs-text-input (format "prop-%s/%s" pos key)
                               :value value
                               :single-line t
                               :on-submit action))))
      :weight 3))))

(defun glasspane-org--format-clock-time (start end)
  (condition-case nil
      (let ((s-date (substring start 0 10))
            (s-time (substring start -5))
            (e-date (substring end 0 10))
            (e-time (substring end -5)))
        (if (equal s-date e-date)
            (format "%s, %s to %s" s-date s-time e-time)
          (format "%s %s to %s %s" s-date s-time e-date e-time)))
    (error (format "%s to %s" start end))))

(defun glasspane-org--parse-logbook (text)
  ;; Keywords may be written lowercase in org files ("clock:" is as valid
  ;; as "CLOCK:"), so match case-insensitively — explicitly, like
  ;; org-element does, never relying on the ambient `case-fold-search'.
  (let ((case-fold-search t)
        (lines (split-string text "\n" t "[ \t]+"))
        entries current-entry)
    (dolist (line lines)
      (cond
       ((string-match "^CLOCK: \\[\\(.*?\\)\\]--\\[\\(.*?\\)\\] =>[ \t]+\\(.*\\)$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'clock :start (match-string 1 line)
                                  :end (match-string 2 line)
                                  :duration (match-string 3 line))))
       ((string-match "^CLOCK: \\[\\(.*?\\)\\]$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'clock :start (match-string 1 line) :active t)))
       ((string-match "^- Note taken on \\(\\[.*?\\]\\) \\\\\\\\$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'note :timestamp (match-string 1 line) :content "")))
       ((string-match "^- State \"\\(.*?\\)\"[ \t]+from \"\\(.*?\\)\"[ \t]+\\(\\[.*?\\]\\)\\(\\(?: \\\\\\\\\\)?\\)$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'state :to (match-string 1 line) :from (match-string 2 line)
                                  :timestamp (match-string 3 line)
                                  :has-note (not (string-empty-p (match-string 4 line)))
                                  :content "")))
       ((string-match "^- State \"\\(.*?\\)\"[ \t]+\\(\\[.*?\\]\\)\\(\\(?: \\\\\\\\\\)?\\)$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'state :to (match-string 1 line)
                                  :timestamp (match-string 2 line)
                                  :has-note (not (string-empty-p (match-string 3 line)))
                                  :content "")))
       (t
        ;; Continuation line
        (when current-entry
          (let ((content (plist-get current-entry :content)))
            (setq current-entry (plist-put current-entry :content
                                           (if (string-empty-p content)
                                               line
                                             (concat content "\n" line)))))))))
    (when current-entry (push current-entry entries))
    (nreverse entries)))

(defun glasspane-ui--render-logbook-entry (entry)
  (let ((type (plist-get entry :type)))
    (cl-case type
      (clock
       (jetpacs-box
        (list
         (jetpacs-row
          (jetpacs-icon "timer" :color "primary" :padding [0 12 0 0])
          (jetpacs-column
           (jetpacs-text (if (plist-get entry :active)
                          (format "Started %s" (plist-get entry :start))
                        (glasspane-org--format-clock-time (plist-get entry :start) (plist-get entry :end)))
                      'body t nil nil nil [0 0 4 0])
           (jetpacs-text (plist-get entry :duration) 'caption))))
        :padding [8 16 8 16]))
      (note
       (jetpacs-box
        (list
         (jetpacs-row
          (jetpacs-icon "chat" :color "primary" :padding [0 12 0 0])
          (jetpacs-column
           (jetpacs-text (format "Note • %s" (plist-get entry :timestamp)) 'caption nil nil nil nil [0 0 4 0])
           (jetpacs-text (plist-get entry :content) 'body))))
        :padding [8 16 8 16]))
      (state
       (jetpacs-box
        (list
         (jetpacs-row
          (jetpacs-icon "change_history" :color "primary" :padding [0 12 0 0])
          (jetpacs-column
           (jetpacs-text (if (plist-get entry :from)
                          (format "%s → %s" (plist-get entry :from) (plist-get entry :to))
                        (format "Set to %s" (plist-get entry :to)))
                      'body t nil nil nil [0 0 4 0])
           (jetpacs-text (if (not (string-empty-p (plist-get entry :content)))
                          (format "%s\n%s" (plist-get entry :timestamp) (plist-get entry :content))
                        (plist-get entry :timestamp))
                      'caption))))
        :padding [8 16 8 16])))))

(defun glasspane-ui--logbook-entries (pos)
  "Return structured logbook entries for heading at POS, or nil.
Drawer delimiters are matched case-insensitively (\":logbook:\" is
valid org), explicitly rather than via ambient `case-fold-search'."
  (save-excursion
    (goto-char pos)
    (let ((case-fold-search t)
          (end (save-excursion (org-end-of-meta-data t) (point))))
      (goto-char pos)
      (when (re-search-forward "^[ \t]*:LOGBOOK:[ \t]*$" end t)
        (let ((start (match-end 0)))
          (when (re-search-forward "^[ \t]*:END:[ \t]*$" end t)
            (glasspane-org--parse-logbook (buffer-substring-no-properties start (match-beginning 0)))))))))

(defun glasspane-ui--properties-section (props ref pos)
  "The Properties collapsible: KEY → VALUE rows plus an + Add button.
Always present (even with no properties yet) so + Add is reachable."
  (jetpacs-collapsible
   (format "detail-props/%s" pos)
   (jetpacs-text (if props (format "Properties (%d)" (length props)) "Properties")
              'label)
   (delq nil
         (append
          (mapcar (lambda (kv)
                    (glasspane-ui--property-row (car kv) (or (cdr kv) "") ref pos))
                  props)
          (list
           (when props
             (jetpacs-text "Submit an empty value to remove a property." 'caption))
           (jetpacs-row
            (jetpacs-spacer :weight 1)
            (jetpacs-button "+ Add property"
                         (jetpacs-action "heading.prop-add" :args ref)
                         :variant "outlined")))))
   :collapsed t))

(defvar glasspane-ui-detail-nodes-functions nil
  "Abnormal hook: functions from a detail REF to extra section nodes.
App layers (notes backlinks, SRS flashcards) contribute detail-view
sections here; each returns a node list or nil.  An erroring function
costs its own section, never the body.")

(defun glasspane-ui--detail-body-with-notes (ref)
  "The detail body plus every registered app layer's sections.
The sections splice INTO a lazy_column body (nesting another scroll
container would break Compose) and wrap otherwise."
  (let ((body (glasspane-ui--detail-body ref))
        (extras (and ref
                     (cl-loop for fn in glasspane-ui-detail-nodes-functions
                              append (condition-case nil (funcall fn ref)
                                       (error nil))))))
    (cond
     ((null extras) body)
     ((equal (alist-get 't body) "lazy_column")
      (mapcar (lambda (kv)
                (if (eq (car kv) 'children)
                    (cons 'children (vconcat (cdr kv) extras))
                  kv))
              body))
     (t (apply #'jetpacs-column body extras)))))

(defun glasspane-ui--detail-body (ref)
  (condition-case err
      (let* ((marker (glasspane-org--resolve-ref ref))
             (buf (marker-buffer marker))
             (file (buffer-file-name buf))
             (pos (marker-position marker))
             (meta (with-current-buffer buf
                     (org-with-wide-buffer
                      (goto-char pos)
                      (let ((comps (org-heading-components)))
                        (list :headline (or (nth 4 comps) "")
                              :todo (nth 2 comps)
                              :priority (and (nth 3 comps)
                                             (char-to-string (nth 3 comps)))
                              :tags (org-get-tags)
                              :local-tags (ignore-errors (org-get-tags pos t))
                              :scheduled (org-entry-get pos "SCHEDULED")
                              :deadline (org-entry-get pos "DEADLINE")
                              :keywords (or org-todo-keywords-1 '("TODO" "DONE"))
                              ;; Ancestor (TITLE . POS) pairs, outermost
                              ;; first, for the breadcrumb trail.
                              :ancestors
                              (save-excursion
                                (let (path)
                                  (ignore-errors
                                    (org-back-to-heading t)
                                    (while (org-up-heading-safe)
                                      (push (cons (substring-no-properties
                                                   (org-get-heading t t t t))
                                                  (point))
                                            path)))
                                  path)))))))
             (headline (plist-get meta :headline))
             (todo (plist-get meta :todo))
             (priority (plist-get meta :priority))
             (tags (plist-get meta :tags))
             (local-tags (plist-get meta :local-tags))
             (scheduled (plist-get meta :scheduled))
             (deadline (plist-get meta :deadline))
             (keywords (plist-get meta :keywords))
             (is-clocked-in (and (bound-and-true-p org-clock-hd-marker)
                                 (marker-buffer org-clock-hd-marker)
                                 (equal buf (marker-buffer org-clock-hd-marker))
                                 (with-current-buffer buf
                                   (= (line-number-at-pos marker)
                                      (line-number-at-pos org-clock-hd-marker)))))
             (sched-button
              (lambda (label when)
                (jetpacs-button label
                             (jetpacs-action "heading.schedule"
                                          :args (cons (cons 'when when) ref))
                             :variant "text"))))
        (if (not glasspane-ui--detail-read-mode)
            (let ((content (with-current-buffer buf
                             (org-with-wide-buffer
                              (goto-char pos)
                              (org-mark-subtree)
                              (buffer-substring-no-properties (region-beginning) (region-end))))))
              (jetpacs-column
               (jetpacs-editor (format "detail-%s" pos) content
                            :syntax "org"
                            :toolbar "org"
                            :line-numbers (and jetpacs-line-numbers
                                               (symbol-name jetpacs-line-numbers))
                            :on-save (jetpacs-action "detail.save"
                                                  :args `((ref . ,ref))
                                                  :when-offline "queue"
                                                  :dedupe (format "save-detail/%s" pos)))))
          (let ((sdate (glasspane-ui--ts-date scheduled))
                (ddate (glasspane-ui--ts-date deadline))
                (entry-props (ignore-errors
                               (with-current-buffer buf
                                 (org-with-wide-buffer
                                  (goto-char pos)
                                  (org-entry-properties pos 'standard)))))
                (logbook-entries (ignore-errors
                                   (with-current-buffer buf
                                     (org-with-wide-buffer
                                      (glasspane-ui--logbook-entries pos))))))
            (apply #'jetpacs-lazy-column
                   (delq nil
                         (append
                          (list
                           ;; Breadcrumb trail — the file, then each
                           ;; ancestor heading.  Every chip taps up to that
                           ;; level, so climbing out of a deep subtree never
                           ;; detours through the file picker.
                           (apply #'jetpacs-scroll-row
                                  (cons
                                   (if file
                                       (jetpacs-assist-chip
                                        (file-name-nondirectory file)
                                        :icon "description"
                                        :on-tap (jetpacs-action
                                                 "files.open"
                                                 :args `((file . ,file))))
                                     (jetpacs-text "?" 'caption))
                                   (mapcan
                                    (lambda (anc)
                                      (list (jetpacs-icon "chevron_right" :size 16)
                                            (jetpacs-assist-chip
                                             (car anc)
                                             :on-tap (jetpacs-action
                                                      "heading.tap"
                                                      :args `((file . ,file)
                                                              (pos . ,(cdr anc))
                                                              (headline . ""))))))
                                    (plist-get meta :ancestors))))
                           ;; Headline
                           (jetpacs-text headline 'title)
                           ;; State (always visible)
                           (glasspane-ui--todo-chips todo keywords ref)
                           ;; Priority (always visible)
                           (glasspane-ui--priority-chips priority ref)
                           (jetpacs-divider)
                           ;; ▸ Scheduling (collapsible — expanded when any date is set)
                           ;; The date-stamp chip IS the display (date + time);
                           ;; the raw "<2026-07-02 Thu>" caption is gone. Only a
                           ;; repeater cookie — which the chip can't show —
                           ;; surfaces as a caption.
                           (jetpacs-collapsible
                            (format "detail-sched/%s" pos)
                            (jetpacs-text "Scheduling" 'label)
                            (list
                             (jetpacs-row
                              (if sdate
                                  (jetpacs-date-stamp :date sdate
                                                   :time (glasspane-ui--ts-time scheduled))
                                (jetpacs-spacer :width 0))
                              (jetpacs-box
                               (list
                                (apply #'jetpacs-column
                                       (delq nil
                                             (list
                                              (jetpacs-text "Scheduled" 'label)
                                              (unless sdate
                                                (jetpacs-text "Not scheduled" 'caption))
                                              (when-let ((rep (glasspane-ui--ts-repeater scheduled)))
                                                (jetpacs-text (concat "Repeats " rep) 'caption))
                                              (jetpacs-flow-row
                                               (jetpacs-date-button "Set date"
                                                                 (jetpacs-action "heading.schedule" :args ref)
                                                                 :value sdate)
                                               (jetpacs-time-button "Set time"
                                                                 (jetpacs-action "heading.schedule-time" :args ref)
                                                                 :value (glasspane-ui--ts-time scheduled))
                                               (funcall sched-button "Today" "+0d")
                                               (funcall sched-button "+1d" "+1d")
                                               (funcall sched-button "+1w" "+1w")
                                               (jetpacs-button "Clear"
                                                            (jetpacs-action "heading.schedule"
                                                                         :args (cons '(clear . t) ref))
                                                            :variant "text"))))))
                               :weight 1))
                             (jetpacs-divider)
                             (jetpacs-row
                              (if ddate
                                  (jetpacs-date-stamp :date ddate
                                                   :time (glasspane-ui--ts-time deadline))
                                (jetpacs-spacer :width 0))
                              (jetpacs-box
                               (list
                                (apply #'jetpacs-column
                                       (delq nil
                                             (list
                                              (jetpacs-text "Deadline" 'label)
                                              (unless ddate
                                                (jetpacs-text "No deadline" 'caption))
                                              (when-let ((rep (glasspane-ui--ts-repeater deadline)))
                                                (jetpacs-text (concat "Repeats " rep) 'caption))
                                              (jetpacs-flow-row
                                               (jetpacs-date-button "Set date"
                                                                 (jetpacs-action "heading.deadline" :args ref)
                                                                 :value ddate)
                                               (jetpacs-button "Clear"
                                                            (jetpacs-action "heading.deadline"
                                                                         :args (cons '(clear . t) ref))
                                                            :variant "text"))))))
                               :weight 1)))
                            :collapsed (not (or sdate ddate)))
                           ;; ▸ Tags (collapsible)
                           (let* ((local-tags (or local-tags tags))
                                  (inherited-tags (seq-difference tags local-tags))
                                  (available (seq-uniq (append local-tags (mapcar (lambda (x) (if (consp x) (car x) x)) org-tag-alist))))
                                  (tags-content
                                   (apply #'jetpacs-column
                                          (delq nil
                                                (list
                                                 (jetpacs-enum-list (format "detail-tags/%s" pos) available
                                                                 :value local-tags :multi-select t :allow-add t
                                                                 :on-change (jetpacs-action "heading.tags" :args ref))
                                                 (when inherited-tags
                                                   (jetpacs-column
                                                    (jetpacs-text "Inherited" 'caption nil nil nil nil 8)
                                                    (apply #'jetpacs-flow-row
                                                           (mapcar (lambda (tg)
                                                                     (jetpacs-assist-chip tg))
                                                                   inherited-tags)))))))))
                             (jetpacs-collapsible
                              (format "detail-tags-fold/%s" pos)
                              (jetpacs-text (if tags (format "Tags (%d)" (length tags)) "Tags") 'label)
                              (list tags-content)
                              :collapsed (null tags)))
                           ;; ▸ Logbook (collapsible)
                           (when logbook-entries
                             (jetpacs-collapsible
                              (format "detail-logbook/%s" pos)
                              (jetpacs-text (format "Logbook (%d)" (length logbook-entries)) 'label)
                              (let ((notes (seq-filter (lambda (e) (eq (plist-get e :type) 'note)) logbook-entries))
                                    (states (seq-filter (lambda (e) (eq (plist-get e :type) 'state)) logbook-entries))
                                    (clocks (seq-filter (lambda (e) (eq (plist-get e :type) 'clock)) logbook-entries)))
                                (delq nil
                                      (list
                                       (when notes
                                         (jetpacs-collapsible
                                          (format "detail-logbook-notes/%s" pos)
                                          (jetpacs-text (format "Notes (%d)" (length notes)) 'label)
                                          (delq nil (cl-loop for entry in notes
                                                             for i from 0
                                                             append (list (glasspane-ui--render-logbook-entry entry)
                                                                          (when (< i (1- (length notes))) (jetpacs-divider)))))
                                          :collapsed nil))
                                       (when states
                                         (jetpacs-collapsible
                                          (format "detail-logbook-states/%s" pos)
                                          (jetpacs-text (format "State Changes (%d)" (length states)) 'label)
                                          (delq nil (cl-loop for entry in states
                                                             for i from 0
                                                             append (list (glasspane-ui--render-logbook-entry entry)
                                                                          (when (< i (1- (length states))) (jetpacs-divider)))))
                                          :collapsed t))
                                       (when clocks
                                         (jetpacs-collapsible
                                          (format "detail-logbook-clocks/%s" pos)
                                          (jetpacs-text (format "Clocks (%d)" (length clocks)) 'label)
                                          (delq nil (cl-loop for entry in clocks
                                                             for i from 0
                                                             append (list (glasspane-ui--render-logbook-entry entry)
                                                                          (when (< i (1- (length clocks))) (jetpacs-divider)))))
                                          :collapsed t)))))
                              :collapsed t))
                           ;; ▸ Properties (collapsible — collapsed by default)
                           (glasspane-ui--properties-section entry-props ref pos)
                           (jetpacs-divider))
                          ;; Reader: body (highlighted) and child headings (foldable).
                          ;; Properties are shown above, so skip them here.
                          (glasspane-org-reader-subtree file pos t)))))))
    (error
     (jetpacs-column
      (jetpacs-text "Error loading heading" 'title)
      (jetpacs-text (error-message-string err) 'body)))))

;; ─── Capture Dialog ──────────────────────────────────────────────────────────

(defvar glasspane-ui--shared-text nil
  "Body text shared from another app, pending the next capture submit.")
(defvar glasspane-ui--shared-subject nil
  "Subject shared from another app; seeds the capture Headline field.")

(defun glasspane-ui-show-capture-dialog ()
  (condition-case err
      (let* ((templates (glasspane-org--capture-templates))
             (template-buttons
              (mapcar (lambda (t-info)
                        (jetpacs-button
                         (alist-get 'description t-info)
                         (jetpacs-action "org.capture.select"
                                      :args `((key . ,(alist-get 'key t-info))))
                         :variant "outlined"))
                      templates))
             (dialog-body
              (apply #'jetpacs-column
                     (jetpacs-text "Quick Capture" 'title)
                     (jetpacs-text "Select a template:" 'caption)
                     (append
                      ;; Shared-in content shows a preview so the user knows
                      ;; what this capture will carry.
                      (when glasspane-ui--shared-text
                        (list (jetpacs-card
                               (list (jetpacs-text
                                      (truncate-string-to-width
                                       glasspane-ui--shared-text 200 nil nil "…")
                                      'caption)))))
                      template-buttons
                      (list (jetpacs-button "Cancel"
                                         (jetpacs-action "org.capture.cancel")
                                         :variant "text"))))))
        (jetpacs-send-dialog dialog-body))
    (error
     (message "Jetpacs capture dialog error: %s" (error-message-string err)))))

(defun glasspane-ui-show-capture-form (template-key)
  ;; Forget values from any previous capture so they can't leak into
  ;; this submit (`jetpacs--ui-state' is global and persistent).
  (jetpacs-ui-state-clear "cap-")
  ;; A shared-in subject pre-fills the Headline field; it must also land
  ;; in UI state, since state.changed only fires for edits the user makes.
  (when glasspane-ui--shared-subject
    (jetpacs-ui-state-put "cap-Headline" glasspane-ui--shared-subject))
  (condition-case err
      (let* ((templates (glasspane-org--capture-templates))
             (tmpl (cl-find-if
                    (lambda (t-info) (equal (alist-get 'key t-info) template-key))
                    templates))
             (prompts (append (alist-get 'prompts tmpl) nil)) ;; coerce vector to list
             (inputs (mapcar (lambda (p)
                               (jetpacs-text-input
                                (format "cap-%s" p) :label p
                                :value (and (equal p "Headline")
                                            glasspane-ui--shared-subject)))
                             prompts))
             (dialog-body
              (apply #'jetpacs-column
                     (jetpacs-text (format "Capture: %s" (alist-get 'description tmpl)) 'title)
                     (append inputs
                             (list
                              (jetpacs-row
                               (jetpacs-button "Cancel"
                                            (jetpacs-action "org.capture.cancel")
                                            :variant "text")
                               (jetpacs-button "Capture"
                                            (jetpacs-action "org.capture.submit"
                                                         :args `((key . ,template-key))))))))))
        (jetpacs-send-dialog dialog-body))
    (error
     (message "Jetpacs capture form error: %s" (error-message-string err)))))

;; ─── Action Handlers ─────────────────────────────────────────────────────────

(jetpacs-defaction "heading.tap"
  (lambda (args _)
    ;; ARGS is the ref alist (id/file/pos/headline) the card embedded.
    ;; This push IS the navigation, so it forces the detail view.
    (setq glasspane-ui--detail-ref args)
    (setq glasspane-ui--detail-read-mode t)
    (jetpacs-shell-push nil :switch-to "detail")))

(jetpacs-defaction "detail.toggle-read"
  (lambda (_ _)
    (setq glasspane-ui--detail-read-mode (not glasspane-ui--detail-read-mode))
    (jetpacs-shell-push nil :switch-to "detail")))

(jetpacs-defaction "detail.save"
  (lambda (args _)
    (let ((ref (alist-get 'ref args))
          (value (alist-get 'value args)))
      (when (and ref value)
        (condition-case err
            (let* ((marker (glasspane-org--resolve-ref ref))
                   (buf (marker-buffer marker))
                   (pos (marker-position marker)))
              (with-current-buffer buf
                (org-with-wide-buffer
                 (goto-char pos)
                 (org-mark-subtree)
                 (delete-region (region-beginning) (region-end))
                 (insert value)
                 (goto-char pos)
                 (setq glasspane-ui--detail-ref (glasspane-org--heading-ref))
                 (let ((glasspane-org--inhibit-save-refresh t)
                       (save-silently t))
                   (save-buffer))))
              (when (fboundp 'glasspane-org-cache-invalidate)
                (glasspane-org-cache-invalidate))
              (setq glasspane-ui--detail-read-mode t)
              (jetpacs-shell-notify "Saved heading"))
          (error
           (jetpacs-shell-notify (format "Save failed: %s" (error-message-string err))))))
      (jetpacs-shell-push))))

(jetpacs-defaction "heading.back"
  ;; Legacy: detail's back button is now a companion-local view.switch.
  ;; Kept for stale cached UIs.
  (lambda (_ _)
    (setq glasspane-ui--detail-ref nil)
    (jetpacs-shell-push nil :switch-to (jetpacs-shell-current-tab))))

(jetpacs-defaction "tasks.filter"
  (lambda (args _)
    (setq glasspane-ui--tasks-filter (alist-get 'filter args))
    (jetpacs-shell-push)))

(defun glasspane-ui--run-search (q)
  "Run search query Q, refreshing the cached results and error state.
A failed query lands in `glasspane-ui--search-error' for the view to
show — the search body renders it instead of a bogus \"no matches\"."
  (setq glasspane-ui--search-query q
        glasspane-ui--search-error nil
        glasspane-ui--search-results
        (condition-case err
            (glasspane-org--search q)
          (error
           (setq glasspane-ui--search-error (error-message-string err))
           nil)))
  ;; Mirror the query into the client-side field state so the search
  ;; box shows what actually ran (builder edits included).
  (jetpacs-ui-state-put "search-query" q))

(defun glasspane-ui--search-filter-query ()
  "Build an org-ql query string from the query-builder filter state.
Returns \"\" when every filter is at its resting value."
  (let ((todo (car (glasspane-ui--filter-values "search-filter-todo")))
        (tags (glasspane-ui--filter-values "search-filter-tags"))
        (text (jetpacs-ui-state "search-filter-text"))
        (prio (car (glasspane-ui--filter-values "search-filter-priority")))
        (due (car (glasspane-ui--filter-values "search-filter-due")))
        (clauses nil))
    (cond
     ((or (null todo) (equal todo "Any")))
     ((equal todo "Done (any)") (push '(done) clauses))
     (t (push `(todo ,todo) clauses)))
    (dolist (tg tags)
      (push `(tags ,tg) clauses))
    (when (and (stringp prio) (not (member prio '("Any" ""))))
      (push `(priority ,prio) clauses))
    (pcase due
      ("Overdue" (push '(deadline :to -1) clauses))
      ("Today" (push '(deadline :on today) clauses))
      ("This week" (push '(deadline :from today :to 7) clauses)))
    (when (and (stringp text) (not (string-empty-p (string-trim text))))
      (push `(regexp ,(regexp-quote (string-trim text))) clauses))
    (setq clauses (nreverse clauses))
    (cond ((null clauses) "")
          ((null (cdr clauses)) (format "%S" (car clauses)))
          (t (format "%S" `(and ,@clauses))))))

(jetpacs-defaction "org.search.run"
  ;; The query arrives as the search field's submitted `value'. Run it,
  ;; cache the results, and land the user on the search view.
  (lambda (args _)
    (glasspane-ui--run-search (or (alist-get 'value args) ""))
    (jetpacs-shell-push nil :switch-to "search")))

(jetpacs-defaction "org.capture.show"
  (lambda (_ _)
    (glasspane-ui-show-capture-dialog)))

(jetpacs-defaction "org.capture.select"
  (lambda (args _)
    (glasspane-ui-show-capture-form (alist-get 'key args))))

(jetpacs-defaction "org.capture.cancel"
  (lambda (_ _)
    (setq glasspane-ui--shared-text nil
          glasspane-ui--shared-subject nil)
    (jetpacs-dismiss-dialog)))

(defun glasspane-ui--on-share (args _payload)
  "Android share sheet → capture: stash the text/subject, open the picker.
Queued offline, so sharing works with Emacs dead — the capture dialog
appears on the next replay."
  (let ((text (alist-get 'text args))
        (subject (alist-get 'subject args)))
    (setq glasspane-ui--shared-text
          (and (stringp text) (not (string-empty-p (string-trim text)))
               (string-trim text))
          glasspane-ui--shared-subject
          (and (stringp subject) (not (string-empty-p (string-trim subject)))
               (string-trim subject)))
    ;; A share with only a subject still captures: use it as the text too.
    (unless glasspane-ui--shared-text
      (setq glasspane-ui--shared-text glasspane-ui--shared-subject))
    (glasspane-ui-show-capture-dialog)))

;; The companion's share sheet emits the app-agnostic `share.text'; this
;; app answers it with org capture.  The old app-specific id stays
;; registered so shares queued by a pre-rename companion still replay.
(jetpacs-defaction "share.text" #'glasspane-ui--on-share)
(jetpacs-defaction "org.capture.share" #'glasspane-ui--on-share)

(jetpacs-defaction "org.capture.submit"
  (lambda (args _)
    (let ((key (alist-get 'key args)))
      (condition-case err
          (let* ((templates (glasspane-org--capture-templates))
                 (tmpl (cl-find-if
                        (lambda (t-info) (equal (alist-get 'key t-info) key))
                        templates))
                 (prompts (append (alist-get 'prompts tmpl) nil))
                 ;; Field values arrived earlier as state.changed events and
                 ;; were recorded into `jetpacs--ui-state' by jetpacs-surfaces.
                 (values (mapcar
                          (lambda (p)
                            (let ((v (jetpacs-ui-state (format "cap-%s" p))))
                              (cons p (if (stringp v) v ""))))
                          prompts)))
            (glasspane-org--do-capture key values glasspane-ui--shared-text)
            (setq glasspane-ui--shared-text nil
                  glasspane-ui--shared-subject nil)
            (glasspane-org-cache-invalidate)
            (jetpacs-ui-state-clear "cap-")
            (jetpacs-shell-notify "Captured ✓")
            (jetpacs-dismiss-dialog)
            (jetpacs-shell-push))
        (error
         (message "Jetpacs capture submit error: %s" (error-message-string err))
         (setq glasspane-ui--shared-text nil
               glasspane-ui--shared-subject nil)
         (jetpacs-ui-state-clear "cap-")
         (jetpacs-dismiss-dialog))))))

(defun glasspane-ui--at-ref (args fn &optional save)
  "Resolve ARGS to its heading and call FN with point there.
With SAVE non-nil, save the buffer afterwards (guarded against
triggering our own after-save refresh on top of the explicit push).
Returns non-nil on success; messages and returns nil on failure."
  (condition-case err
      (let ((marker (glasspane-org--resolve-ref args)))
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (funcall fn))
          (when save
            (let ((glasspane-org--inhibit-save-refresh t)
                  (save-silently t))
              (save-buffer))))
        (glasspane-org-cache-invalidate)
        t)
    (error
     (message "Jetpacs: heading action failed: %s" (error-message-string err))
     (jetpacs-shell-notify "Couldn't find that heading — refreshing")
     (jetpacs-shell-push)
     nil)))

(jetpacs-defaction "heading.todo-set"
  (lambda (args _)
    (let* ((state (alist-get 'state args))
           (clear (equal state "")))
      (when (and state
                 (glasspane-ui--at-ref args (lambda () (org-todo (if clear 'none state))) t))
        (jetpacs-shell-notify (if clear "State cleared" (format "State → %s" state)))
        (jetpacs-shell-push)))))

(jetpacs-defaction "heading.todo-cycle"
  (lambda (args _)
    (when (glasspane-ui--at-ref args
                                (lambda ()
                                  (org-todo)
                                  (unless (org-get-todo-state)
                                    (org-todo)))
                                t)
      (let* ((marker (glasspane-org--resolve-ref args))
             (state (with-current-buffer (marker-buffer marker)
                      (org-with-wide-buffer
                       (goto-char marker)
                       (org-get-todo-state)))))
        (jetpacs-shell-notify (if state (format "State → %s" state) "State cleared"))
        (jetpacs-shell-push)))))

(jetpacs-defaction "heading.schedule"
  (lambda (args _)
    ;; CLEAR removes the timestamp; otherwise WHEN (relative, e.g. "+1d") or
    ;; VALUE (concrete "YYYY-MM-DD", from the date picker) sets it.
    (let* ((clear (alist-get 'clear args))
           (date (or (alist-get 'when args) (alist-get 'value args)))
           (ok (cond
                (clear (glasspane-ui--at-ref args (lambda () (org-schedule '(4))) t))
                ((and (stringp date) (not (string-empty-p date)))
                 (glasspane-ui--at-ref args (lambda () (org-schedule nil date)) t)))))
      (when ok
        (jetpacs-shell-notify (if clear "Schedule cleared" (format "Scheduled %s" date)))
        (jetpacs-shell-push)))))

(jetpacs-defaction "heading.schedule-time"
  ;; Adds/updates the clock time on the existing SCHEDULED date (today if
  ;; none yet). VALUE is the "HH:MM" the time picker injected.
  (lambda (args _)
    (let ((time (alist-get 'value args)))
      (when (and (stringp time) (not (string-empty-p time))
                 (glasspane-ui--at-ref
                  args
                  (lambda ()
                    (let* ((sched (org-entry-get nil "SCHEDULED"))
                           (date (or (glasspane-ui--ts-date sched)
                                     (format-time-string "%Y-%m-%d"))))
                      (org-schedule nil (format "%s %s" date time))))
                  t))
        (jetpacs-shell-notify (format "Scheduled %s" time))
        (jetpacs-shell-push)))))

(jetpacs-defaction "org.footnote.show"
  ;; A tapped footnote marker in rich text: surface its inline definition
  ;; (when the reference carried one) or just its label.
  (lambda (args _)
    (let ((def (alist-get 'def args))
          (label (alist-get 'label args)))
      (jetpacs-shell-notify
       (if (and (stringp def) (not (string-empty-p def)))
           (format "Footnote: %s" def)
         (format "Footnote %s" (or label ""))))
      (jetpacs-shell-push))))

(jetpacs-defaction "heading.deadline"
  (lambda (args _)
    (let* ((clear (alist-get 'clear args))
           (date (or (alist-get 'when args) (alist-get 'value args)))
           (ok (cond
                (clear (glasspane-ui--at-ref args (lambda () (org-deadline '(4))) t))
                ((and (stringp date) (not (string-empty-p date)))
                 (glasspane-ui--at-ref args (lambda () (org-deadline nil date)) t)))))
      (when ok
        (jetpacs-shell-notify (if clear "Deadline cleared" (format "Deadline %s" date)))
        (jetpacs-shell-push)))))

(jetpacs-defaction "heading.priority"
  (lambda (args _)
    ;; Empty VALUE means None (remove); otherwise the first char is the priority.
    (let* ((val (alist-get 'value args))
           (remove (or (null val) (string-empty-p val)))
           (ok (glasspane-ui--at-ref
                args
                (lambda ()
                  (if remove (org-priority 'remove)
                    (org-priority (string-to-char val))))
                t)))
      (when ok
        (jetpacs-shell-notify (if remove "Priority cleared"
                                (format "Priority %s" val)))
        (jetpacs-shell-push)))))

(jetpacs-defaction "heading.refile"
  ;; Bridged picker over org-refile targets; refiles the whole subtree.
  (lambda (args _)
    (condition-case err
        (let ((marker (glasspane-org--resolve-ref args)))
          (with-current-buffer (marker-buffer marker)
            (org-with-wide-buffer
             (goto-char marker)
             (let* ((org-refile-targets (or org-refile-targets
                                            '((org-agenda-files :maxlevel . 3))))
                    (targets (org-refile-get-targets))
                    (choice (condition-case nil
                                (completing-read "Refile to: "
                                                 (mapcar #'car targets) nil t)
                              (quit nil)))
                    (target (and choice (assoc choice targets))))
               (if (not target)
                   (jetpacs-shell-notify "Refile cancelled")
                 (org-refile nil nil target)
                 (let ((glasspane-org--inhibit-save-refresh t)
                       (save-silently t))
                   (org-save-all-org-buffers))
                 (glasspane-org-cache-invalidate)
                 (setq glasspane-ui--detail-ref nil)
                 (jetpacs-shell-notify (format "Refiled to %s" choice))))))
          (jetpacs-shell-push nil :switch-to (jetpacs-shell-current-tab)))
      (error
       (jetpacs-shell-notify (format "Refile failed: %s"
                                     (error-message-string err)))
       (jetpacs-shell-push)))))

(jetpacs-defaction "heading.archive"
  ;; Bridged y/n confirm, then org-archive-subtree; saves source + archive.
  (lambda (args _)
    (let ((headline (or (alist-get 'headline args) "this heading")))
      (if (not (yes-or-no-p (format "Archive \"%s\"? " headline)))
          (jetpacs-shell-notify "Archive cancelled")
        (when (glasspane-ui--at-ref
               args
               (lambda ()
                 (org-archive-subtree)
                 (let ((glasspane-org--inhibit-save-refresh t)
                       (save-silently t))
                   (org-save-all-org-buffers))))
          (setq glasspane-ui--detail-ref nil)
          (jetpacs-shell-notify "Archived")))
      (jetpacs-shell-push nil :switch-to (jetpacs-shell-current-tab)))))

(jetpacs-defaction "heading.add-note"
  ;; Quick logbook note: bridged prompt, written where org-log-into-drawer
  ;; says notes belong, in org's own note format.
  (lambda (args _)
    (let ((note (string-trim (condition-case nil
                                 (read-string "Note: ")
                               (quit "")))))
      (if (string-empty-p note)
          (jetpacs-shell-notify "Note cancelled")
        (when (glasspane-ui--at-ref
               args
               (lambda ()
                 (let ((org-log-into-drawer t))
                   (goto-char (org-log-beginning t))
                   (insert (format "- Note taken on %s \\\\\n  %s\n"
                                   (format-time-string
                                    (org-time-stamp-format t t))
                                   (replace-regexp-in-string "\n" "\n  " note)))))
               t)
          (jetpacs-shell-notify "Note added")))
      (jetpacs-shell-push))))

(jetpacs-defaction "heading.prop-set"
  ;; VALUE arrives injected by the row input's on-submit; NAME rides in
  ;; args. An empty value deletes the property.
  (lambda (args _)
    (let* ((name (alist-get 'name args))
           (raw-val (alist-get 'value args))
           (value (cond
                   ((eq raw-val t) "t")
                   ((memq raw-val '(nil :json-false)) "nil")
                   ((vectorp raw-val) (if (> (length raw-val) 0) (aref raw-val 0) ""))
                   ((listp raw-val) (if raw-val (car raw-val) ""))
                   ((stringp raw-val) (string-trim raw-val))
                   (t (format "%s" raw-val))))
           (ok (and (stringp name) (not (string-empty-p name))
                    (glasspane-ui--at-ref
                     args
                     (lambda ()
                       (if (string-empty-p value)
                           (org-delete-property name)
                         (org-set-property name value)))
                     t))))
      (when ok
        (jetpacs-shell-notify (if (string-empty-p value)
                                  (format "Removed %s" name)
                                (format "%s → %s" name value)))
        (jetpacs-shell-push)))))

(jetpacs-defaction "heading.prop-add"
  ;; The bridged read-string asks for the key; the new (empty) property
  ;; then appears as a row whose value column is ready to fill in.
  (lambda (args _)
    (let ((name (string-trim (condition-case nil
                                 (read-string "New property name: ")
                               (quit "")))))
      (cond
       ((string-empty-p name) nil)
       ((string-match-p "[: \t]" name)
        (jetpacs-shell-notify "Property names can't contain colons or spaces"))
       ((glasspane-ui--at-ref args
                             (lambda () (org-set-property (upcase name) ""))
                             t)
        (jetpacs-shell-notify (format "Added %s — fill in its value" (upcase name)))))
      (jetpacs-shell-push))))

(jetpacs-defaction "heading.tags"
  (lambda (args _)
    (let* ((val (alist-get 'value args))
           (tags (cond
                  ((vectorp val) (append val nil))
                  ((listp val) val)
                  ((stringp val) (split-string val "[ \t:,]+" t))
                  (t nil)))
           (ok (glasspane-ui--at-ref args (lambda () (org-set-tags tags)) t)))
      (when ok
        (jetpacs-shell-notify (if tags (format "Tags: %s" (string-join tags " "))
                                "Tags cleared"))
        (jetpacs-shell-push)))))

(jetpacs-defaction "settings.line-numbers"
  ;; Single-select enum: value arrives as a JSON array with (at most) one
  ;; entry.  Deselecting everything counts as Off.
  (lambda (args _)
    (let* ((val (alist-get 'value args))
           (choice (car (append val nil)))
           (sym (pcase choice
                  ("Absolute" 'absolute)
                  ("Relative" 'relative)
                  (_ nil))))
      (setq jetpacs-line-numbers sym)
      (ignore-errors (customize-save-variable 'jetpacs-line-numbers sym))
      (jetpacs-shell-notify (format "Line numbers: %s" (or choice "Off")))
      (jetpacs-shell-push))))

(jetpacs-defaction "settings.tags"
  (lambda (args _)
    (let* ((val (alist-get 'value args))
           (tags-list (cond
                       ((vectorp val) (append val nil))
                       ((listp val) val)
                       (t nil))))
      (when tags-list
        ;; Keep existing keys/chars if possible, else just use the string
        (let ((new-alist (mapcar (lambda (tg)
                                   (let ((existing (assoc tg org-tag-alist)))
                                     (if existing existing tg)))
                                 tags-list)))
          (setq org-tag-alist new-alist)
          (glasspane-ui--customize-save 'org-tag-alist org-tag-alist)))
      (jetpacs-shell-notify "Settings saved")
      (jetpacs-shell-push))))

;; The org settings exposed to the companion, through the generic
;; schema-driven machinery (the registry is the security boundary:
;; only symbols listed here can be modified from the wire).
(jetpacs-settings-register-section
 "Org Workflow"
 '((org-directory :label "Org directory")
   (org-log-done :label "Log task completion")
   (org-log-into-drawer :label "Log into drawer")
   (org-archive-location :label "Archive location")))
(jetpacs-settings-register-section
 "Org Agenda"
 '((org-agenda-span :label "Agenda span")
   (org-deadline-warning-days :label "Deadline warning days")
   (org-extend-today-until :label "Extend today until (hour)")))
(jetpacs-settings-register-section
 "Org Editing & Display"
 '((org-startup-folded :label "Initial folding")
   (org-startup-indented :label "Indent to outline level")
   (org-hide-emphasis-markers :label "Hide emphasis markers")
   (org-return-follows-link :label "Enter follows links")
   (glasspane-babel-timeout :label "Babel run timeout (s)")))
(jetpacs-settings-register-section
 "User Defaults"
 '((user-full-name :label "Author (Name)")
   (user-mail-address :label "Email")))
(jetpacs-settings-register-section
 "Calendar & Location"
 '((calendar-week-start-day :label "Week start day (0=Sun, 1=Mon)")
   (calendar-latitude :label "Latitude (e.g. 40.7)")
   (calendar-longitude :label "Longitude (e.g. -74.0)")))

;; Org-derived views are memoised; per the cache contract every mutation
;; must drop the memo or the phone keeps rendering stale data.
(add-hook 'jetpacs-settings-after-set-hook
          (lambda (sym _value)
            (when (or (string-prefix-p "org-" (symbol-name sym))
                      (string-prefix-p "calendar-" (symbol-name sym)))
              (glasspane-org-cache-invalidate))))

(defalias 'glasspane-ui--customize-save #'jetpacs-settings-save-variable
  "Persist a variable through Customize, surfacing failures.
Kept as an alias for the todo/tag actions that predate the generic
settings module (`jetpacs-settings-save-variable').")

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

(jetpacs-defaction "settings.todo.edit"
  (lambda (args _)
    (condition-case err
        (let* ((idx (alist-get 'index args))
               (seqs (or (default-value 'org-todo-keywords) '((sequence "TODO" "DONE"))))
               (seq (if (>= idx 0) (nth idx seqs) '(sequence "TODO" "|" "DONE"))))
          (if (null seq)
              ;; Stale index: the list changed since the card was rendered.
              (progn (jetpacs-shell-notify "That sequence no longer exists")
                     (jetpacs-shell-push))
            (let* ((type (car seq))
                   ;; Keep the raw keyword strings, fast-access keys and all
                   ;; ("TODO(t!)"), so an untouched save round-trips losslessly.
                   (split (glasspane-ui--split-todo-sequence seq))
                   (active (mapconcat #'identity (car split) ", "))
                   (finished (mapconcat #'identity (cdr split) ", ")))
              ;; Pre-filled `:value's must be seeded by hand: state.changed
              ;; only fires for edits the user makes, and these ids may still
              ;; hold text from the previously edited sequence.
              (jetpacs-ui-state-clear "todo-")
              (jetpacs-ui-state-put "todo-active" active)
              (jetpacs-ui-state-put "todo-finished" finished)
              (jetpacs-send-dialog
               (jetpacs-column
                (jetpacs-text (if (>= idx 0) "Edit Sequence" "New Sequence") 'title)
                (jetpacs-text "Comma-separated states; fast keys like TODO(t) are kept." 'caption)
                (jetpacs-text-input "todo-active" :label "Active States" :value active :single-line t)
                (jetpacs-text-input "todo-finished" :label "Finished States" :value finished :single-line t)
                (jetpacs-row
                 (jetpacs-spacer :weight 1)
                 (when (>= idx 0)
                   (jetpacs-button "Delete" (jetpacs-action "settings.todo.delete" :args `((index . ,idx))) :variant "text"))
                 (jetpacs-button "Cancel" (jetpacs-action "dialog.dismiss") :variant "text")
                 (jetpacs-spacer :width 8)
                 (jetpacs-button "Save" (jetpacs-action "settings.todo.save" :args `((index . ,idx) (type . ,(symbol-name type)))))))))))
      (error
       (jetpacs-shell-notify (format "Edit failed: %s" (error-message-string err)))))))

(jetpacs-defaction "settings.agenda.edit"
  (lambda (args _)
    (let* ((name (alist-get 'name args))
           (query (if name (cdr (assoc name glasspane-org-custom-agendas)) "")))
      (jetpacs-ui-state-clear "agenda-")
      (jetpacs-ui-state-put "agenda-name" (or name ""))
      (jetpacs-ui-state-put "agenda-query" query)
      (jetpacs-send-dialog
       (jetpacs-column
        (jetpacs-text (if name "Edit Saved Search" "New Saved Search") 'title)
        (jetpacs-text "Enter the display name and the org-ql query string." 'caption)
        (jetpacs-text-input "agenda-name" :label "Name" :value (or name "") :single-line t)
        (jetpacs-text-input "agenda-query" :label "Query String" :value query)
        (jetpacs-row
         (jetpacs-spacer :weight 1)
         (when name
           (jetpacs-button "Delete" (jetpacs-action "settings.agenda.delete" :args `((name . ,name))) :variant "text"))
         (jetpacs-button "Cancel" (jetpacs-action "dialog.dismiss") :variant "text")
         (jetpacs-spacer :width 8)
         (jetpacs-button "Save" (jetpacs-action "settings.agenda.save" :args `((old-name . ,name))))))))))

(jetpacs-defaction "settings.agenda.delete"
  (lambda (args _)
    (let ((name (alist-get 'name args)))
      (setq glasspane-org-custom-agendas (assoc-delete-all name glasspane-org-custom-agendas))
      (glasspane-ui--customize-save 'glasspane-org-custom-agendas glasspane-org-custom-agendas)
      (jetpacs-dismiss-dialog)
      (jetpacs-shell-notify (format "Deleted saved search: %s" name))
      (jetpacs-shell-push))))

(jetpacs-defaction "settings.agenda.save"
  (lambda (args _)
    (let ((old-name (alist-get 'old-name args))
          (new-name (jetpacs-ui-state "agenda-name"))
          (query (jetpacs-ui-state "agenda-query")))
      (if (or (not (stringp new-name)) (string-empty-p new-name))
          (jetpacs-shell-notify "Name cannot be empty")
        (when (and old-name (not (equal old-name new-name)))
          (setq glasspane-org-custom-agendas (assoc-delete-all old-name glasspane-org-custom-agendas)))
        (setq glasspane-org-custom-agendas (assoc-delete-all new-name glasspane-org-custom-agendas))
        (setq glasspane-org-custom-agendas (append glasspane-org-custom-agendas (list (cons new-name query))))
        (glasspane-ui--customize-save 'glasspane-org-custom-agendas glasspane-org-custom-agendas)
        (jetpacs-dismiss-dialog)
        (jetpacs-shell-notify "Saved custom agenda")
        (jetpacs-shell-push)))))

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

(jetpacs-defaction "search.update-filter"
  ;; A builder filter changed: rebuild the org-ql query from the whole
  ;; filter state and run it immediately — the results and the query
  ;; text update together, no extra Search tap needed.
  (lambda (args _)
    (jetpacs-ui-state-put (concat "search-filter-" (alist-get 'field args))
                       (alist-get 'value args))
    (glasspane-ui--run-search (glasspane-ui--search-filter-query))
    (jetpacs-shell-push)))

(jetpacs-defaction "search.clear-filters"
  (lambda (_ _)
    (jetpacs-ui-state-clear "search-filter-")
    (glasspane-ui--run-search "")
    (jetpacs-shell-push)))

(jetpacs-defaction "agenda.save-custom"
  (lambda (args _)
    (let* ((query (alist-get 'query args))
           (name (read-string "Agenda Name: ")))
      (when (and (stringp name) (not (string-empty-p name)))
        ;; Remove existing if overriding
        (setq glasspane-org-custom-agendas (assoc-delete-all name glasspane-org-custom-agendas))
        (add-to-list 'glasspane-org-custom-agendas (cons name query) t)
        (customize-save-variable 'glasspane-org-custom-agendas glasspane-org-custom-agendas)
        (jetpacs-shell-notify (format "Saved custom agenda: %s" name))
        (jetpacs-shell-push)))))

(jetpacs-defaction "agenda.set-mode"
  (lambda (args _)
    (let ((mode (alist-get 'mode args)))
      (jetpacs-ui-state-put "agenda-mode" mode)
      (jetpacs-shell-push))))

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

(jetpacs-defaction "agenda.today"
  ;; Reset the anchor (and any month-grid selection) back to today.
  (lambda (_ _)
    (jetpacs-ui-state-put "agenda-anchor" nil)
    (jetpacs-ui-state-put "agenda-selected-date" nil)
    (jetpacs-shell-push)))

(jetpacs-defaction "agenda.select-date"
  (lambda (args _)
    (let ((date (alist-get 'date args)))
      (jetpacs-ui-state-put "agenda-selected-date" date)
      (jetpacs-shell-push))))

(jetpacs-defaction "heading.clock-in"
  (lambda (args _)
    (when (glasspane-ui--at-ref args #'org-clock-in)
      (jetpacs-shell-notify "Clocked in")
      (jetpacs-shell-push "clock"))))

(jetpacs-defaction "search.by-tag"
  ;; A tag chip tap: reset the builder to just that tag, then run the
  ;; same query the builder would generate, so the search field shows a
  ;; query the user can retype or edit.
  (lambda (args _)
    (jetpacs-ui-state-clear "search-filter-")
    (jetpacs-ui-state-put "search-filter-tags" (vector (alist-get 'tag args)))
    (glasspane-ui--run-search (glasspane-ui--search-filter-query))
    (jetpacs-shell-push nil :switch-to "search")))

(jetpacs-defaction "org.link.open"
  ;; A tappable link inside rich org text. Emacs resolves it (id:, file:,
  ;; http(s):, attachment:, …) via the org link machinery; we report the
  ;; outcome back as a snackbar since the action itself happens Emacs-side.
  (lambda (args _)
    (let ((link (alist-get 'link args)))
      (when (and (stringp link) (not (string-empty-p link)))
        (let ((navigated nil))
          (condition-case err
              (progn
                (org-link-open-from-string link)
                (jetpacs-shell-notify (format "Opened %s" link))
                (when (derived-mode-p 'org-mode)
                  (setq glasspane-ui--detail-ref (glasspane-org--heading-ref))
                  (setq glasspane-ui--detail-read-mode t)
                  (setq navigated t)))
            (error
             (jetpacs-shell-notify
              (format "Couldn't open %s: %s" link (error-message-string err)))))
          (if navigated
              (jetpacs-shell-push nil :switch-to "detail")
            (jetpacs-shell-push)))))))

(jetpacs-defaction "checkbox.toggle"
  ;; Toggle a checkbox in an org file from the reader view.  The companion
  ;; sends FILE and POS (the real-buffer position of the list item line).
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (progn
              (with-current-buffer (find-file-noselect file)
                (org-with-wide-buffer
                 (goto-char pos)
                 (org-toggle-checkbox))
                (let ((glasspane-org--inhibit-save-refresh t)
                      (save-silently t))
                  (save-buffer)))
              (glasspane-org-cache-invalidate)
              (jetpacs-shell-push))
          (error
           (jetpacs-shell-notify
            (format "Toggle failed: %s" (error-message-string err)))))))))

(jetpacs-defaction "heading.reorder"
  (lambda (args _)
    (let* ((file      (alist-get 'file args))
           (from-pos  (alist-get 'from_pos args))
           (after-pos (alist-get 'after_pos args))  ;; 0 or nil = move to top
           (new-level (alist-get 'new_level args)))
      (when (and file from-pos (file-readable-p file))
        (with-current-buffer (find-file-noselect file)
          (org-with-wide-buffer
           (goto-char from-pos)
           (org-back-to-heading t)
           (let* ((from-level (org-outline-level))
                  (subtree-beg (point))
                  (subtree-end (save-excursion (org-end-of-subtree t t) (point)))
                  (subtree-size (- subtree-end subtree-beg)))
             ;; Cut the subtree
             (org-cut-subtree)
             ;; Navigate to the insertion point
             (if (and after-pos (> after-pos 0))
                 (let ((target (if (> after-pos from-pos)
                                   (- after-pos subtree-size)
                                 after-pos)))
                   (goto-char (min target (point-max)))
                   (org-back-to-heading t)
                   (org-end-of-subtree t t))
               ;; Move to top of file (before first heading)
               (goto-char (point-min))
               (when (re-search-forward org-heading-regexp nil t)
                 (goto-char (line-beginning-position))))
             ;; Paste at the new level (or original level if nil)
             (org-paste-subtree (or new-level from-level)))))
        (let ((glasspane-org--inhibit-save-refresh t)
              (save-silently t))
          (with-current-buffer (find-file-noselect file)
            (save-buffer)))
        (glasspane-org-cache-invalidate)
        (jetpacs-shell-push nil :switch-to "edit")))))

;; ─── Table actions ───────────────────────────────────────────────────────────
;; The rich renderer emits native `table' nodes whose cells and "+"
;; affordances carry these actions with real-file positions baked in.

(defun glasspane-ui--table-mutate (file pos fn)
  "Run FN with point at POS inside FILE's table, then align, save, repush.
FN performs one table mutation.  Afterwards the table is realigned,
recalculated when a #+TBLFM line follows it (formulas live Emacs-side —
the phone never computes), saved, and every view repushed.  A mutation
that moves point off the table (killing a row) realigns from the
table's start; one that consumes the table entirely (killing its only
row) skips the realign instead of erroring."
  (with-current-buffer (find-file-noselect file)
    (org-with-wide-buffer
     (goto-char pos)
     (unless (org-at-table-p) (error "No table at position %s" pos))
     (let ((table-beg (org-table-begin)))
       (funcall fn)
       (unless (org-at-table-p)
         (goto-char (min table-beg (point-max))))
       (when (org-at-table-p)
         (org-table-align)
         (when (save-excursion
                 (goto-char (org-table-end))
                 ;; "#+tblfm:" is valid org — match case-insensitively.
                 (let ((case-fold-search t))
                   (looking-at-p "[ \t]*#\\+TBLFM:")))
           (org-table-recalculate t)))))
    (let ((glasspane-org--inhibit-save-refresh t)
          (save-silently t))
      (save-buffer)))
  (glasspane-org-cache-invalidate)
  (jetpacs-shell-push))

(defun glasspane-ui--table-field-formula ()
  "The #+TBLFM entry (LHS . RHS) computing the field at point, or nil.
Field formulas (@R$C, with @< / @> resolved to concrete rows) win over
column formulas ($C), mirroring org's own recalculation.  Point must be
inside a table.  The LHS comes back exactly as written in the #+TBLFM
line, so callers can `assoc' it in `org-table-get-stored-formulas'
output to update the formula in place.  Formulas keyed by field name
are not resolved — those cells stay value-editable."
  (org-table-analyze)
  (let* ((line (count-lines org-table-current-begin-pos
                            (line-beginning-position)))
         (dline (org-table-line-to-dline line))
         (col (org-table-current-column))
         (stored (org-table-get-stored-formulas t))
         (norm (lambda (kv)
                 (or (ignore-errors
                       (org-table-formula-handle-first/last-rc (car kv)))
                     (car kv)))))
    (when (and dline col (> col 0))
      (or (cl-find (format "@%d$%d" dline col) stored :key norm :test #'equal)
          (cl-find (format "$%d" col) stored :key norm :test #'equal)))))

(jetpacs-defaction "org.table.edit"
  ;; Tap a table cell in the reader: a native dialog (bridged
  ;; `read-string') prefilled with the current field, written back
  ;; through the org table machinery so formulas recalculate.  A field
  ;; that #+TBLFM computes opens its formula instead — recalculation
  ;; would immediately overwrite any value typed into it.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (let (current formula)
              (with-current-buffer (find-file-noselect file)
                (org-with-wide-buffer
                 (goto-char pos)
                 (unless (org-at-table-p) (error "No table cell here"))
                 (setq formula (glasspane-ui--table-field-formula))
                 (unless formula
                   (setq current (string-trim (org-table-get-field))))))
              (if formula
                  (let ((input (string-trim
                                (read-string (format "Formula %s= " (car formula))
                                             (cdr formula)))))
                    (when (string-empty-p input)
                      (error "Empty formula — edit the #+TBLFM line to remove one"))
                    (glasspane-ui--table-mutate file pos
                      (lambda ()
                        (let* ((stored (org-table-get-stored-formulas t))
                               (entry (or (assoc (car formula) stored)
                                          (error "Formula %s not found"
                                                 (car formula)))))
                          (setcdr entry input)
                          (save-excursion
                            (org-table-store-formulas stored))))))
                (let* ((input (read-string "Cell: " current))
                       ;; A field is one line between pipes — keep it that way.
                       (new (string-replace
                             "|" "\\vert{}"
                             (string-replace "\n" " " input))))
                  (glasspane-ui--table-mutate file pos
                    (lambda () (org-table-get-field nil new))))))
          (error
           (jetpacs-shell-notify
            (format "Edit failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

(jetpacs-defaction "org.table.cell-menu"
  ;; Long-press a table cell in the reader: row/column structure edits
  ;; picked from a bridged `completing-read'.  Org's own commands fix up
  ;; #+TBLFM references (or mark them INVALID) on the way through.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (let ((choice (completing-read
                           "Row/column: "
                           '("Insert row above" "Insert column left"
                             "Delete row" "Delete column")
                           nil t)))
              (glasspane-ui--table-mutate file pos
                (lambda ()
                  (pcase choice
                    ("Insert row above"   (org-table-insert-row))
                    ("Insert column left" (org-table-insert-column))
                    ("Delete row"         (org-table-kill-row))
                    ("Delete column"      (org-table-delete-column))))))
          (error
           (jetpacs-shell-notify
            (format "Table edit failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

(jetpacs-defaction "org.table.add-row"
  ;; The "+" strip under the table: append an empty row at the bottom,
  ;; then tap-to-edit fills it in.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (glasspane-ui--table-mutate file pos
              (lambda ()
                (goto-char (org-table-end))
                (forward-line -1)       ; last table line
                (org-table-insert-row t)))
          (error
           (jetpacs-shell-notify
            (format "Add row failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

(jetpacs-defaction "org.table.add-col"
  ;; The "+" gutter at the right edge: append an empty column.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (glasspane-ui--table-mutate file pos
              (lambda ()
                ;; Force-create a field one past the last column on the
                ;; first data line (pipe count is authoritative — \vert
                ;; never appears raw); the helper's realign squares every
                ;; other row off to match.  `org-table-insert-column'
                ;; inserts to the LEFT of point's column, so it can't
                ;; append at the right edge directly.
                (goto-char (org-table-begin))
                (while (and (org-at-table-hline-p)
                            (< (point) (org-table-end)))
                  (forward-line 1))
                (let ((ncols (1- (cl-count ?| (buffer-substring-no-properties
                                               (line-beginning-position)
                                               (line-end-position))))))
                  (org-table-goto-column (1+ (max 1 ncols)) nil 'force))))
          (error
           (jetpacs-shell-notify
            (format "Add column failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

;; ─── Babel ───────────────────────────────────────────────────────────────────

(defcustom glasspane-babel-timeout 30
  "Seconds before a phone-triggered babel execution is abandoned.
Best-effort: the timer can't interrupt a synchronous subprocess mid-call,
but it fires between process reads and stops a runaway block from
wedging the bridge forever."
  :type 'integer :group 'jetpacs)

(jetpacs-defaction "org.babel.execute"
  ;; The play button on a src-block header.  The wire names only a
  ;; location — the code that runs lives in the user's own file, so the
  ;; semantic-action boundary holds.  `org-confirm-babel-evaluate' is
  ;; honored: the yes/no prompt bridges to a native dialog, and it runs
  ;; BEFORE the timeout starts so a slow answer never counts against the
  ;; execution budget.
  (lambda (args _)
    (let ((file (alist-get 'file args))
          (pos  (alist-get 'pos args)))
      (when (and file pos (file-readable-p file))
        (condition-case err
            (progn
              (with-current-buffer (find-file-noselect file)
                (org-with-wide-buffer
                 (goto-char pos)
                 (let ((info (org-babel-get-src-block-info)))
                   (unless info (error "No source block here"))
                   ;; `org-babel-confirm-evaluate' RETURNS nil on decline (it
                   ;; does not signal) — gate on that, or a declined prompt
                   ;; would fall through and evaluate anyway.
                   (unless (org-babel-confirm-evaluate info)
                     (user-error "Evaluation declined"))
                   (let ((org-confirm-babel-evaluate nil))
                     (with-timeout ((max 1 glasspane-babel-timeout)
                                    (error "Timed out after %ss"
                                           glasspane-babel-timeout))
                       (org-babel-execute-src-block nil info)))))
                (let ((glasspane-org--inhibit-save-refresh t)
                      (save-silently t))
                  (save-buffer)))
              (glasspane-org-cache-invalidate)
              (jetpacs-shell-notify "Block executed")
              (jetpacs-shell-push))
          (error
           (jetpacs-shell-notify
            (format "Run failed: %s" (error-message-string err)))
           (jetpacs-shell-push)))))))

(jetpacs-defaction "file.view"
  ;; Legacy (old cached UIs): now routes into the jetpacs-files editor.
  (lambda (args _)
    (let ((file (alist-get 'file args)))
      (when (and (stringp file) (file-readable-p file))
        (setq jetpacs-files--file (expand-file-name file))
        (jetpacs-shell-push nil :switch-to "edit")))))

;; ─── Files integration: org files open reader-first ─────────────────────────
;; Registered on the core files module's app seams; the editor itself stays
;; org-agnostic.

(defvar glasspane-ui--files-read-mode nil
  "When non-nil, org files open in the foldable reader instead of the editor.")

(defvar glasspane-ui--files-refile-mode nil
  "When non-nil, org reader shows a flat drag-to-reorder heading list.")

(defun glasspane-ui--org-file-p (file)
  "Non-nil when FILE is an org file."
  (and file (string-match-p "\\.org\\'" file)))

(defvar glasspane-ui--files-filter ""
  "Sparse-filter query for the org read-mode body; empty = everything.
Reset when a different file opens.")

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

(jetpacs-defaction "files.filter"
  ;; The sparse filter for the open org file: VALUE is the submitted
  ;; query ("" clears). State only — matching happens at render.
  (lambda (args _)
    (let ((value (alist-get 'value args)))
      (when (stringp value)
        (setq glasspane-ui--files-filter value)
        (jetpacs-shell-push nil :switch-to "edit")))))

(defun glasspane-ui--org-editor-actions (file)
  "Reader/refile toggles and the properties dialog for org FILE."
  (when (glasspane-ui--org-file-p file)
    (delq nil
          (list
           (when glasspane-ui--files-read-mode
             (jetpacs-icon-button
              (if glasspane-ui--files-refile-mode "visibility" "swap_vert")
              (jetpacs-action "files.toggle-refile")
              :content-description
              (if glasspane-ui--files-refile-mode "Reader" "Refile")))
           (jetpacs-icon-button
            (if glasspane-ui--files-read-mode "edit" "visibility")
            (jetpacs-action "files.toggle-read")
            :content-description
            (if glasspane-ui--files-read-mode "Edit" "Read"))
           (jetpacs-icon-button
            "tune"
            (jetpacs-action "files.properties.show" :args `((file . ,file)))
            :content-description "Properties")))))

(add-hook 'jetpacs-files-editor-body-functions #'glasspane-ui--org-editor-body)
(add-hook 'jetpacs-files-editor-actions-functions #'glasspane-ui--org-editor-actions)

;; Org files get the org formatting toolbar above the keyboard — declared
;; in the editor spec, so the renderer stays app-agnostic.
(setq jetpacs-files-editor-toolbar-function
      (lambda (file) (when (glasspane-ui--org-file-p file) "org")))

;; Org files open reader-first; everything else lands in the editor.
;; A fresh file starts unfiltered.
(add-hook 'jetpacs-files-open-hook
          (lambda (file)
            (setq glasspane-ui--files-read-mode (glasspane-ui--org-file-p file)
                  glasspane-ui--files-filter "")))

;; A phone-side save may have changed org data the views memoise.
(add-hook 'jetpacs-files-after-save-hook
          (lambda (_file) (glasspane-org-cache-invalidate)))

(jetpacs-defaction "files.toggle-read"
  (lambda (_ _)
    (setq glasspane-ui--files-read-mode (not glasspane-ui--files-read-mode))
    (jetpacs-shell-push nil :switch-to "edit")))

(jetpacs-defaction "files.toggle-refile"
  (lambda (_ _)
    (setq glasspane-ui--files-refile-mode (not glasspane-ui--files-refile-mode))
    (jetpacs-shell-push nil :switch-to "edit")))

(jetpacs-defaction "files.properties.show"
  (lambda (args _)
    (let ((file (alist-get 'file args)))
      (if (not (and file (stringp file) (file-readable-p file)))
          (jetpacs-shell-notify (format "Cannot open properties: %s" (or file "no file")))
        (condition-case err
            (let* ((buf (or (get-file-buffer file) (find-file-noselect file)))
                   (kwds (with-current-buffer buf (org-collect-keywords '("TITLE" "CATEGORY" "FILETAGS" "TODO" "SEQ_TODO" "TYP_TODO" "STARTUP" "AUTHOR" "EMAIL" "DATE" "ARCHIVE"))))
                   (title (car (alist-get "TITLE" kwds nil nil #'equal)))
                   (category (car (alist-get "CATEGORY" kwds nil nil #'equal)))
                   (filetags-str (car (alist-get "FILETAGS" kwds nil nil #'equal)))
                   (filetags (when filetags-str (split-string filetags-str ":" t "[ \t\n\r]+")))
                   (available-tags (seq-uniq (append filetags (mapcar (lambda (x) (if (consp x) (car x) x)) org-tag-alist))))
                   (todo-str (or (car (alist-get "TODO" kwds nil nil #'equal))
                                 (car (alist-get "SEQ_TODO" kwds nil nil #'equal))
                                 (car (alist-get "TYP_TODO" kwds nil nil #'equal))))
                   (todo-parts (if todo-str (split-string todo-str "|") nil))
                   (todo-active (if todo-str (mapconcat #'identity (split-string (car todo-parts) "[ \t]+" t) ", ") ""))
                   (todo-finished (if (and todo-parts (cadr todo-parts))
                                      (mapconcat #'identity (split-string (cadr todo-parts) "[ \t]+" t) ", ")
                                    ""))
                   (startup (car (alist-get "STARTUP" kwds nil nil #'equal)))
                   (author (car (alist-get "AUTHOR" kwds nil nil #'equal)))
                   (email (car (alist-get "EMAIL" kwds nil nil #'equal)))
                   (date (car (alist-get "DATE" kwds nil nil #'equal)))
                   (archive (car (alist-get "ARCHIVE" kwds nil nil #'equal))))
              (jetpacs-send-dialog
               (jetpacs-scroll-column
                (jetpacs-text "File Properties" 'title)
                (jetpacs-text (file-name-nondirectory file) 'caption)
                (jetpacs-text-input "file-prop-title" :label "Title" :value title :single-line t)
                (jetpacs-text-input "file-prop-category" :label "Category" :value category :single-line t)
                (jetpacs-text "File Tags" 'caption nil nil nil nil 8)
                (jetpacs-enum-list "file-prop-tags" available-tags
                                :value filetags :multi-select t :allow-add t)
                (jetpacs-text "TODO Sequence" 'caption nil nil nil nil 8)
                (jetpacs-text-input "file-prop-todo-active" :label "Active States" :value todo-active :single-line t)
                (jetpacs-text-input "file-prop-todo-finished" :label "Finished States" :value todo-finished :single-line t)
                (jetpacs-text "Metadata" 'caption nil nil nil nil 8)
                (jetpacs-text-input "file-prop-author" :label "Author" :value author :single-line t)
                (jetpacs-text-input "file-prop-email" :label "Email" :value email :single-line t)
                (jetpacs-text-input "file-prop-date" :label "Date" :value date :single-line t)
                (jetpacs-text "Options" 'caption nil nil nil nil 8)
                (jetpacs-text-input "file-prop-startup" :label "Startup" :value startup :single-line t)
                (jetpacs-text-input "file-prop-archive" :label "Archive" :value archive :single-line t)
                (jetpacs-row
                 (jetpacs-spacer :weight 1)
                 (jetpacs-button "Cancel" (jetpacs-action "dialog.dismiss") :variant "text")
                 (jetpacs-spacer :width 8)
                 (jetpacs-button "Save" (jetpacs-action "files.properties.save" :args `((file . ,file))))))))
          (error
           (jetpacs-shell-notify (format "Properties error: %s" (error-message-string err)))))))))

(jetpacs-defaction "files.properties.save"
  (lambda (args _)
    (let* ((file (alist-get 'file args))
           (buf (or (get-file-buffer file) (find-file-noselect file)))
           (title (jetpacs-ui-state "file-prop-title"))
           (category (jetpacs-ui-state "file-prop-category"))
           (tags-val (jetpacs-ui-state "file-prop-tags"))
           (tags (cond
                  ((vectorp tags-val) (append tags-val nil))
                  ((listp tags-val) tags-val)
                  (t nil)))
           (todo-active (jetpacs-ui-state "file-prop-todo-active"))
           (todo-finished (jetpacs-ui-state "file-prop-todo-finished"))
           (todo-str (let ((a (when (stringp todo-active) (string-join (split-string todo-active "[ \t]*,[ \t]*" t) " ")))
                           (f (when (stringp todo-finished) (string-join (split-string todo-finished "[ \t]*,[ \t]*" t) " "))))
                       (if (and a f (not (string-empty-p a)) (not (string-empty-p f)))
                           (concat a " | " f)
                         (or a f))))
           (startup (jetpacs-ui-state "file-prop-startup"))
           (author (jetpacs-ui-state "file-prop-author"))
           (email (jetpacs-ui-state "file-prop-email"))
           (date (jetpacs-ui-state "file-prop-date"))
           (archive (jetpacs-ui-state "file-prop-archive")))
      (with-current-buffer buf
        (save-excursion
          (save-restriction
            (widen)
            (let ((update-kwd (lambda (kwd val)
                                (goto-char (point-min))
                                (if (re-search-forward (format "^[ \t]*#\\+%s:[ \t]*\\(.*\\)$" kwd) nil t)
                                    (if (and val (not (string-empty-p val)))
                                        (replace-match val t t nil 1)
                                      (delete-region (line-beginning-position) (min (1+ (line-end-position)) (point-max))))
                                  (when (and val (not (string-empty-p val)))
                                    (goto-char (point-min))
                                    ;; If inserting something else than TITLE and a TITLE exists, insert after it.
                                    (when (not (equal kwd "TITLE"))
                                      (when (re-search-forward "^[ \t]*#\\+TITLE:.*$" nil t)
                                        (forward-line 1)))
                                    (insert (format "#+%s: %s\n" kwd val)))))))
              (funcall update-kwd "TITLE" title)
              (funcall update-kwd "FILETAGS" (when tags (concat ":" (string-join tags ":") ":")))
              (funcall update-kwd "CATEGORY" category)
              (funcall update-kwd "TODO" todo-str)
              (funcall update-kwd "STARTUP" startup)
              (funcall update-kwd "AUTHOR" author)
              (funcall update-kwd "EMAIL" email)
              (funcall update-kwd "DATE" date)
              (funcall update-kwd "ARCHIVE" archive))
            (let ((glasspane-org--inhibit-save-refresh t)
                  (save-silently t))
              (save-buffer)))))
      (jetpacs-dismiss-dialog)
      (glasspane-org-cache-invalidate)
      (jetpacs-shell-push))))

;; ─── Auto-refresh ────────────────────────────────────────────────────────────

(defvar glasspane-ui--save-refresh-timer nil)

(defcustom glasspane-ui-save-refresh-delay 2
  "Idle seconds after saving an agenda file before re-pushing the dashboard.
Debounces bursts of saves (e.g. `org-save-all-org-buffers') into one push."
  :type 'integer :group 'jetpacs)

(defun glasspane-ui--after-save-refresh ()
  "Schedule a dashboard refresh if an org agenda file was just saved.
No-op for saves Jetpacs itself performs — anything inside an action
handler (`jetpacs--in-action-handler') pushes explicitly, and other
programmatic saves bind `glasspane-org--inhibit-save-refresh' — which would
otherwise refresh twice or loop."
  (when (and (jetpacs-connected-p)
             (not (bound-and-true-p glasspane-org--inhibit-save-refresh))
             (not (bound-and-true-p jetpacs--in-action-handler))
             buffer-file-name
             (derived-mode-p 'org-mode)
             (ignore-errors
               (member (expand-file-name buffer-file-name)
                       (mapcar #'expand-file-name (org-agenda-files)))))
    (glasspane-org-cache-invalidate)
    (when (timerp glasspane-ui--save-refresh-timer)
      (cancel-timer glasspane-ui--save-refresh-timer))
    (setq glasspane-ui--save-refresh-timer
          (run-with-idle-timer glasspane-ui-save-refresh-delay nil
                               #'jetpacs-shell-push))))

(add-hook 'after-save-hook #'glasspane-ui--after-save-refresh)

(defun glasspane-ui--refresh-if-connected (&rest _)
  "Re-push the dashboard when there's a live session.
Safe to put on any hook: a no-op while disconnected.  Invalidates the
extraction cache first — this runs on clock in/out, which mutate the
org buffer without necessarily saving it."
  (when (jetpacs-connected-p)
    (glasspane-org-cache-invalidate)
    (jetpacs-shell-push)))

;; The connect and queue-drained pushes are owned by the shell; this app
;; only contributes its cache invalidation via `jetpacs-shell-refresh-hook'.

;; Clock state shows on the Clock tab and the dashboard generally —
;; keep it live. Depth 90: after jetpacs-surfaces' notification hooks.
(add-hook 'org-clock-in-hook  #'glasspane-ui--refresh-if-connected 90)
(add-hook 'org-clock-out-hook #'glasspane-ui--refresh-if-connected 90)

(provide 'glasspane-ui)
;;; glasspane-ui.el ends here