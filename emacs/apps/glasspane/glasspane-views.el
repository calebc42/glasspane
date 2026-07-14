;;; glasspane-views.el --- Saved queries as views -*- lexical-binding: t; -*-

;; PKM plan Task 11 — the Dataview / Notion-database story: a named
;; org-ql query rendered three ways over the same result set — list
;; (table with property columns), board (kanban by TODO state), and
;; calendar (grouped by scheduled date).  Definitions persist through
;; Customize; rendering switches per view and persists too.
;;
;; Everything rides existing machinery: `glasspane-org--query' (memoised,
;; org-ql-or-fallback), the §9 table node, `heading.tap' for drill-in,
;; and `heading.todo-set' for moving a board card between columns (a
;; menu on the card — board columns still don't drag; no drag-between-
;; columns wire node exists).  Cards swipe to complete/schedule-today,
;; and a single-file view's list rendering can toggle into a
;; `jetpacs-reorderable-list' riding `heading.reorder'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'jetpacs)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-settings)
(require 'glasspane-org)
(require 'glasspane-ui)
(require 'glasspane-agenda)             ; date helpers + the month fallback grid

(defcustom glasspane-saved-views nil
  "Saved query views: a list of alists with `name', `query', `rendering'.
`query' is anything `jetpacs-org-parse-query' accepts (org-ql sexp,
filter tokens, or free text); `rendering' is \"list\" | \"board\" |
\"calendar\".  Managed from the phone; persisted through Customize."
  :type '(repeat sexp) :group 'jetpacs)

(defvar glasspane-views--current nil
  "Name of the saved view being shown, or nil for the hub.")

(defun glasspane-views--form ()
  "The new-view form's field registry (`jetpacs-form').
Owner passed explicitly so resolution never depends on dynamic context;
resetting it rotates the field ids, the server-driven field clear."
  (jetpacs-form "views-new" "glasspane"))

(defconst glasspane-views--renderings '("list" "board" "calendar"))

(defun glasspane-views--get (name)
  (cl-find name glasspane-saved-views
           :key (lambda (v) (alist-get 'name v)) :test #'equal))

(defun glasspane-views--persist ()
  (jetpacs-settings-save-variable 'glasspane-saved-views glasspane-saved-views))

(defun glasspane-views--set-rendering (name rendering)
  "Set view NAME's rendering to RENDERING, rebuilding the saved list.
Rebuilding (rather than a `setcdr' into the entry) tolerates a
hand-authored Customize entry without a `rendering' key and never
mutates the value Customize handed out."
  (setq glasspane-saved-views
        (mapcar (lambda (v)
                  (if (equal (alist-get 'name v) name)
                      (cons (cons 'rendering rendering)
                            (assq-delete-all 'rendering (copy-alist v)))
                    v))
                glasspane-saved-views)))

(defun glasspane-views--items (view)
  "Run VIEW's query; heading items, or signal `user-error'."
  (glasspane-org--query
   (jetpacs-org-parse-query (alist-get 'query view))))

;; ─── Renderings ──────────────────────────────────────────────────────────────

(defun glasspane-views--tap (item)
  "The drill-in action for ITEM's heading."
  (jetpacs-action "heading.tap" :args (alist-get 'ref item)
               :when-offline "drop"))

(defun glasspane-views--done-p (item)
  "Non-nil when ITEM's todo keyword is a done state."
  (let ((todo (alist-get 'todo item)))
    (and todo (member todo (or (default-value 'org-done-keywords)
                               '("DONE" "CANCELLED"))))))

(defconst glasspane-views--priority-colors
  '(("A" . "#E53935") ("B" . "#F57C00") ("C" . "#1976D2"))
  "Badge color per priority; anything else renders neutral gray.")

(defun glasspane-views--priority-span (priority)
  "The bold colored [P] badge span, or nil without PRIORITY."
  (when priority
    (jetpacs-span (format "[%s] " priority) :bold t
               :color (or (cdr (assoc priority glasspane-views--priority-colors))
                          "#9E9E9E"))))

(defun glasspane-views--headline-spans (item)
  "Priority badge + headline spans; done headings render struck through.
One span list feeds both table cells and `jetpacs-rich-text' cards."
  (let ((headline (or (alist-get 'headline item) "")))
    (delq nil
          (list (glasspane-views--priority-span (alist-get 'priority item))
                (if (glasspane-views--done-p item)
                    (jetpacs-span headline :strike t)
                  (jetpacs-span headline))))))

(defun glasspane-views--tag-action (tag)
  "The tap action shared by tag spans and chips: search by TAG."
  (jetpacs-action "search.by-tag" :args `((tag . ,tag))))

(defun glasspane-views--tag-spans (item)
  "Tappable #tag spans for the list rendering's Tags cell."
  (let (spans)
    (dolist (tg (append (alist-get 'tags item) nil))
      (when spans (push (jetpacs-span " ") spans))
      (push (jetpacs-span (concat "#" tg) :tag t
                       :on-tap (glasspane-views--tag-action tg))
            spans))
    (nreverse spans)))

(defun glasspane-views--tag-chips (item)
  "The tappable tag chip row for card renderings, or nil without tags."
  (when-let ((tags (append (alist-get 'tags item) nil)))
    (apply #'jetpacs-flow-row
           (mapcar (lambda (tg)
                     (jetpacs-assist-chip tg :on-tap (glasspane-views--tag-action tg)))
                   tags))))

(defun glasspane-views--caption (item)
  "The todo · file caption line, or nil when neither is known."
  (let ((caption (string-join
                  (delq nil (list (alist-get 'todo item)
                                  (when-let ((file (alist-get 'file item)))
                                    (file-name-nondirectory file))))
                  "  ·  ")))
    (unless (string-empty-p caption) caption)))

(defun glasspane-views--done-keyword ()
  "The keyword a swipe-to-complete lands on."
  (or (car (default-value 'org-done-keywords)) "DONE"))

(defun glasspane-views--card (item &optional trailing)
  "The shared rich card for ITEM; TRAILING sits at the row's end.
Priority-badged headline (struck through when done), todo · file
caption, compact scheduled/deadline row, tappable tag chips.  Swipe
from the start completes an open todo; swipe from the end schedules
it today — both remain reachable by tap → detail on old companions."
  (let ((ref (alist-get 'ref item))
        (middle
         (apply #'jetpacs-column
                (delq nil
                      (list
                       (jetpacs-rich-text (glasspane-views--headline-spans item))
                       (when-let ((caption (glasspane-views--caption item)))
                         (jetpacs-text caption 'caption))
                       (glasspane-ui--card-date-row item)
                       (glasspane-views--tag-chips item))))))
    (jetpacs-card
     (list (apply #'jetpacs-row
                  (delq nil (list (jetpacs-box (list middle) :weight 1)
                                  trailing))))
     :on-tap (glasspane-views--tap item)
     :swipe-start
     (unless (glasspane-views--done-p item)
       (jetpacs-swipe-action
        "check" "Done"
        (jetpacs-action "heading.todo-set"
                     :args (append ref
                                   `((state . ,(glasspane-views--done-keyword))))
                     :when-offline "queue")
        :color "#2E7D32"))
     :swipe-end
     (jetpacs-swipe-action
      "today" "Today"
      (jetpacs-action "heading.schedule"
                   :args (append ref '((when . "+0d")))
                   :when-offline "queue")))))

(defvar glasspane-views--reorder nil
  "Non-nil while the open view's list rendering shows the drag list.
Reset when a view opens or closes.")

(defun glasspane-views--single-file (items)
  "The one file every item of ITEMS lives in, or nil when they span files.
Drag reorder needs one buffer: `heading.reorder' cuts and pastes a
subtree within a single file, so a query whose results span files (or
include file-level notes, level 0) cannot reorder."
  (let ((file (and items (alist-get 'file (car items)))))
    (when (and (stringp file)
               (cl-every (lambda (it)
                           (and (equal (alist-get 'file it) file)
                                (integerp (alist-get 'pos it))
                                (integerp (alist-get 'level it))
                                (>= (alist-get 'level it) 1)))
                         items))
      file)))

(defun glasspane-views--reorder-node (items file)
  "The drag-reorder list for a single-FILE view's ITEMS.
Rides the existing `heading.reorder' action; `view' routes the repush
back here instead of the file editor."
  (jetpacs-reorderable-list
   (mapcar (lambda (it)
             `((label . ,(or (alist-get 'headline it) ""))
               (level . ,(alist-get 'level it))
               (pos   . ,(alist-get 'pos it))
               (file  . ,file)))
           items)
   :on-reorder (jetpacs-action "heading.reorder"
                            :args `((file . ,file)
                                    (view . "glasspane.views")))))

(defun glasspane-views--table-node (items)
  "The list rendering: one table row per item, tappable cells."
  (jetpacs-table
   (cons
    (jetpacs-table-row
     (list (jetpacs-table-cell (list (jetpacs-span "Heading" :bold t)))
           (jetpacs-table-cell (list (jetpacs-span "State" :bold t)))
           (jetpacs-table-cell (list (jetpacs-span "Scheduled" :bold t)))
           (jetpacs-table-cell (list (jetpacs-span "Tags" :bold t))))
     :header t)
    (mapcar
     (lambda (item)
       (let ((tap (glasspane-views--tap item)))
         (jetpacs-table-row
          (list (jetpacs-table-cell (glasspane-views--headline-spans item)
                                 :on-tap tap)
                (jetpacs-table-cell
                 (list (jetpacs-span (or (alist-get 'todo item) "")
                                  :strike (and (glasspane-views--done-p item) t))))
                (jetpacs-table-cell
                 (list (jetpacs-span (or (glasspane-ui--ts-date
                                       (alist-get 'scheduled item))
                                      ""))))
                (jetpacs-table-cell (glasspane-views--tag-spans item))))))
     items))
   :aligns '("start" "start" "start" "start")))

(defun glasspane-views--board-columns (items)
  "Distinct TODO states across ITEMS, keyword order preserved.
Global keywords come first in `org-todo-keywords-1' order; states the
global list doesn't know (file-local #+TODO: lines) follow in encounter
order — every present state gets a column, or its cards would silently
vanish from the board."
  (let ((present (delete-dups (mapcar (lambda (i)
                                        (or (alist-get 'todo i) ""))
                                      items))))
    (append (cl-remove-if-not (lambda (kw) (member kw present))
                              org-todo-keywords-1)
            (cl-remove-if (lambda (kw)
                            (or (string-empty-p kw)
                                (member kw org-todo-keywords-1)))
                          present)
            (and (member "" present) '("")))))

(defun glasspane-views--board-card (item columns)
  "A board card: tap opens the heading; the menu moves it to a column."
  (let ((ref (alist-get 'ref item))
        (state (or (alist-get 'todo item) "")))
    (glasspane-views--card
     item
     (jetpacs-menu
      (mapcar (lambda (target)
                (jetpacs-menu-item
                 (if (string-empty-p target) "No state" target)
                 (jetpacs-action "heading.todo-set"
                              :args (append ref `((state . ,target)))
                              :when-offline "queue")))
              (remove state columns))
      :icon "more_vert"))))

(defun glasspane-views--board-node (items)
  "The kanban rendering: one column per TODO state, panning sideways."
  (let ((columns (glasspane-views--board-columns items)))
    (apply #'jetpacs-scroll-row
           (mapcar
            (lambda (col)
              (let ((in-col (cl-remove-if-not
                             (lambda (i) (equal (or (alist-get 'todo i) "")
                                                col))
                             items)))
                (jetpacs-box
                 (list (apply #'jetpacs-column
                              (cons (jetpacs-section-header
                                     (format "%s (%d)"
                                             (if (string-empty-p col)
                                                 "No state" col)
                                             (length in-col)))
                                    (mapcar (lambda (i)
                                              (glasspane-views--board-card
                                               i columns))
                                            in-col))))
                 :padding 4)))
            columns))))

(defun glasspane-views--calendar-node (items)
  "The calendar rendering: a month grid over ITEMS' scheduled dates.
The curated `month_grid' when the companion has it (marks = item
count per day, month swipe), the composed fallback grid otherwise;
below it the selected day's cards and the Unscheduled section.
Anchor month and selection live in UI state under \"views-cal-\",
cleared when a view opens or closes."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (anchor (or (jetpacs-ui-state "views-cal-anchor") today))
         (month-prefix (substring anchor 0 7))
         (sel (jetpacs-ui-state "views-cal-selected"))
         ;; A remembered selection only counts inside the shown month;
         ;; otherwise select today (when visible) or the anchor day.
         (selected-date (cond
                         ((and (stringp sel) (string-prefix-p month-prefix sel)) sel)
                         ((string-prefix-p month-prefix today) today)
                         (t anchor)))
         (items-by-date (seq-group-by
                         (lambda (it)
                           (glasspane-ui--ts-date (alist-get 'scheduled it)))
                         items))
         (unscheduled (cdr (assoc nil items-by-date)))
         (selected-items (cdr (assoc selected-date items-by-date))))
    (apply #'jetpacs-column
           (delq nil
                 (list
                  (jetpacs-node-or "month_grid"
                      (jetpacs-month-grid month-prefix
                                       :marks (delq nil
                                                    (mapcar
                                                     (lambda (g)
                                                       (and (stringp (car g))
                                                            (cons (car g)
                                                                  (length (cdr g)))))
                                                     items-by-date))
                                       :selected selected-date
                                       :on-day-tap (jetpacs-action "views.cal.select-date")
                                       :on-month-change (jetpacs-action "views.cal.set-month"))
                    (glasspane-ui--agenda-month-fallback
                     items-by-date anchor selected-date "views.cal.select-date"))
                  (jetpacs-divider)
                  (jetpacs-section-header (format "Events for %s" selected-date))
                  (if selected-items
                      (apply #'jetpacs-column
                             (mapcar #'glasspane-views--card selected-items))
                    (jetpacs-text "No events" 'caption))
                  (when unscheduled (jetpacs-divider))
                  (when unscheduled
                    (jetpacs-section-header
                     (format "Unscheduled (%d)" (length unscheduled))))
                  (when unscheduled
                    (apply #'jetpacs-column
                           (mapcar #'glasspane-views--card unscheduled))))))))

;; ─── The two screens (one shell view) ────────────────────────────────────────

(defun glasspane-views--rendering-chips (view)
  "The List | Board | Calendar switcher for companions predating `tabs'."
  (apply #'jetpacs-row
         (mapcar (lambda (r)
                   (jetpacs-chip (capitalize r)
                              :selected (equal r (alist-get 'rendering view))
                              :on-tap (jetpacs-action
                                       "views.rendering"
                                       :args `((name . ,(alist-get 'name view))
                                               (rendering . ,r))
                                       :when-offline "drop")))
                 glasspane-views--renderings)))

(defun glasspane-views--rendering-tabs (view items file)
  "The list | board | calendar pager for VIEW over ITEMS.
Every page ships in the push, so switching is companion-local and
works offline; on_change persists the settled page as the view's
rendering.  `:id' is keyed by the view name — deliberately, unlike the
agenda's no-id tabs: opening a DIFFERENT view must reset the pager to
that view's persisted rendering, while re-pushes of the same view keep
the user's page.  FILE is the single-file guard result gating the list
page's drag-reorder body."
  (let* ((name (alist-get 'name view))
         (rendering (or (alist-get 'rendering view) "list"))
         (initial (or (seq-position glasspane-views--renderings rendering) 0)))
    (jetpacs-tabs
     (mapcar (lambda (r) (jetpacs-tab-item (capitalize r)))
             glasspane-views--renderings)
     (list (if (and glasspane-views--reorder file)
               (glasspane-views--reorder-node items file)
             (glasspane-views--table-node items))
           (glasspane-views--board-node items)
           (glasspane-views--calendar-node items))
     :initial initial
     :id (concat "views-tabs-" name)
     :on-change (jetpacs-action "views.rendering"
                             :args `((name . ,name))
                             :when-offline "drop"))))

(defun glasspane-views--open-view (view snackbar)
  "The screen for one saved VIEW."
  (let* ((items (condition-case err
                    (glasspane-views--items view)
                  (user-error (list 'error (error-message-string err)))))
         (broken (eq (car-safe items) 'error))
         (rendering (or (alist-get 'rendering view) "list"))
         (file (and (not broken) (glasspane-views--single-file items))))
    (jetpacs-shell-nav-view
     (alist-get 'name view)
     (apply #'jetpacs-lazy-column
            (append
             ;; Drag reorder only makes sense on one file's list —
             ;; see --single-file.
             (when file
               (list (jetpacs-row
                      (jetpacs-spacer :weight 1)
                      (jetpacs-icon-button
                       "swap_vert"
                       (jetpacs-action "views.reorder" :when-offline "drop")
                       :content-description "Toggle drag reorder"))))
             (cond
              (broken
               (list (jetpacs-text (cadr items) 'body)))
              ((null items)
               ;; %s: a hand-authored query may be a sexp, not a string.
               (list (jetpacs-empty-state :icon "manage_search"
                                       :title "No matches"
                                       :caption (format "%s"
                                                        (alist-get 'query view)))))
              (t
               (list
                (jetpacs-node-or "tabs"
                    (glasspane-views--rendering-tabs view items file)
                  ;; Pre-`tabs' companions keep the chip switcher over
                  ;; the one persisted rendering.
                  (jetpacs-column
                   (glasspane-views--rendering-chips view)
                   (jetpacs-spacer :height 4)
                   (pcase rendering
                     ("board" (glasspane-views--board-node items))
                     ("calendar" (glasspane-views--calendar-node items))
                     (_ (if (and glasspane-views--reorder file)
                            (glasspane-views--reorder-node items file)
                          (glasspane-views--table-node items)))))))))))
     :nav-action (jetpacs-action "views.back" :when-offline "drop")
     :snackbar snackbar)))

(defun glasspane-views--new-form ()
  "The collapsed new-view form at the hub's foot.
Field ids come from the `jetpacs-form' registry; views.save reads them."
  (let ((form (glasspane-views--form)))
    (jetpacs-collapsible
     "views-new"
     (jetpacs-section-header "New view")
     (list
      (jetpacs-text-input (jetpacs-form-field-id form "name")
                       :label "Name" :single-line t)
      (jetpacs-text-input (jetpacs-form-field-id form "query")
                       :label "Query"
                       :hint "todo:TODO tags:work — or an org-ql sexp"
                       :single-line t)
      (jetpacs-enum-list (jetpacs-form-field-id form "rendering")
                      glasspane-views--renderings
                      :value '("list"))
      (jetpacs-button "Save view"
                   (jetpacs-action "views.save" :when-offline "drop")
                   :icon "add"))
     :collapsed t)))

(defun glasspane-views--hub (snackbar)
  "The hub: every saved view as a card, plus the new-view form."
  (jetpacs-shell-nav-view
   "Saved views"
   (apply #'jetpacs-lazy-column
          (append
           (if glasspane-saved-views
               (mapcar
                (lambda (view)
                  (let ((name (alist-get 'name view)))
                    (jetpacs-card
                     (list
                      (jetpacs-row
                       (jetpacs-box
                        (list (jetpacs-column
                               (jetpacs-text name 'label)
                               (jetpacs-text (format "%s · %s"
                                                  (alist-get 'rendering view)
                                                  (alist-get 'query view))
                                          'caption)))
                        :weight 1)
                       (jetpacs-icon-button
                        "delete"
                        (jetpacs-action "views.delete" :args `((name . ,name))
                                     :when-offline "queue")
                        :content-description "Delete view")))
                     :on-tap (jetpacs-action "views.open" :args `((name . ,name))
                                          :when-offline "drop"))))
                glasspane-saved-views)
             (list (jetpacs-empty-state
                    :icon "manage_search" :title "No saved views"
                    :caption "Name a query below and it becomes a view")))
           (list (jetpacs-divider) (glasspane-views--new-form))))
   :snackbar snackbar))

(defun glasspane-views--view (snackbar)
  (if-let ((view (and glasspane-views--current
                      (glasspane-views--get glasspane-views--current))))
      (glasspane-views--open-view view snackbar)
    (glasspane-views--hub snackbar)))

(with-jetpacs-owner "glasspane"
  (jetpacs-shell-define-view "glasspane.views" :builder #'glasspane-views--view :order 75))

;; Everyday nav: saved views are a daily destination, so they ride the
;; drawer (the contract: drawer = everyday nav, satellites = settings).
(with-jetpacs-owner "glasspane"
  (jetpacs-shell-add-drawer-item
   40 (lambda ()
        (jetpacs-drawer-item "manage_search" "Saved views"
                          (jetpacs-shell-switch-view "glasspane.views")))))

;; ─── Actions ─────────────────────────────────────────────────────────────────

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "views.open"
    (lambda (args _)
      (let ((name (alist-get 'name args)))
        (when (glasspane-views--get name)
          (setq glasspane-views--current name
                glasspane-views--reorder nil)
          (jetpacs-ui-state-clear "views-cal-")
          (jetpacs-shell-push nil :switch-to "glasspane.views"))))
    :doc "Open a saved view by name."
    :args '((:name name :type "text" :required t)))

  (jetpacs-defaction "views.back"
    (lambda (_args _)
      (setq glasspane-views--current nil
            glasspane-views--reorder nil)
      (jetpacs-ui-state-clear "views-cal-")
      (jetpacs-shell-push nil :switch-to "glasspane.views")))

  (jetpacs-defaction "views.reorder"
    (lambda (_args _)
      (setq glasspane-views--reorder (not glasspane-views--reorder))
      (jetpacs-shell-push)))

  (jetpacs-defaction "views.cal.select-date"
    ;; `date' comes from the composed fallback grid's per-cell args;
    ;; `value' is what the curated month_grid's on_day_tap injects.
    (lambda (args _)
      (let ((date (or (alist-get 'date args) (alist-get 'value args))))
        (when (and (stringp date)
                   (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date))
          (jetpacs-ui-state-put "views-cal-selected" date)
          (jetpacs-shell-push)))))

  (jetpacs-defaction "views.cal.set-month"
    ;; The curated grid navigates companion-locally and reports the
    ;; shown month; re-anchoring pushes fresh marks for it.
    (lambda (args _)
      (let ((month (alist-get 'value args)))
        (when (and (stringp month)
                   (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}\\'" month))
          (jetpacs-ui-state-put "views-cal-anchor" (concat month "-01"))
          (jetpacs-shell-push)))))

  (jetpacs-defaction "views.rendering"
    ;; `rendering' names come from the fallback chips; `value' (a page
    ;; index) from the tabs pager's on_change. Either way the result
    ;; must name a rendering we actually offer.
    (lambda (args _)
      (let* ((view (glasspane-views--get (alist-get 'name args)))
             (idx (alist-get 'value args))
             (rendering (or (alist-get 'rendering args)
                            (and (integerp idx)
                                 (nth idx glasspane-views--renderings)))))
        (when (and view (member rendering glasspane-views--renderings))
          (glasspane-views--set-rendering (alist-get 'name view) rendering)
          (glasspane-views--persist)
          (jetpacs-shell-push))))
    :doc "Switch a saved view's rendering (list/board/calendar)."
    :args '((:name name :type "text" :required t)
            (:name rendering :type "enum" :values ["list" "board" "calendar"] :required t)))

  (jetpacs-defaction "views.save"
    (lambda (_args _)
      (let* ((form (glasspane-views--form))
             (name (string-trim
                    (or (jetpacs-form-value form "name") "")))
             (query (string-trim
                     (or (jetpacs-form-value form "query") "")))
             (rendering (let ((r (jetpacs-form-value form "rendering")))
                          (cond ((stringp r) r)
                                ((consp r) (car r))
                                ((vectorp r) (aref r 0))
                                (t "list")))))
        (cond
         ((string-empty-p name) (jetpacs-shell-notify "The view needs a name"))
         ((string-empty-p query) (jetpacs-shell-notify "The view needs a query"))
         (t
          (condition-case err
              (progn
                ;; Parse now so a broken query fails at save, not render.
                (jetpacs-org-parse-query query)
                (setq glasspane-saved-views
                      (append (cl-remove name glasspane-saved-views
                                         :key (lambda (v) (alist-get 'name v))
                                         :test #'equal)
                              (list `((name . ,name)
                                      (query . ,query)
                                      (rendering . ,(if (member rendering
                                                                glasspane-views--renderings)
                                                        rendering "list"))))))
                (glasspane-views--persist)
                (jetpacs-form-reset form)
                (jetpacs-shell-notify (format "Saved view %s" name)))
            (user-error (jetpacs-shell-notify (error-message-string err))))))
        (jetpacs-shell-push))))

  (jetpacs-defaction "views.delete"
    (lambda (args _)
      (let ((name (alist-get 'name args)))
        (when (glasspane-views--get name)
          (setq glasspane-saved-views
                (cl-remove name glasspane-saved-views
                           :key (lambda (v) (alist-get 'name v)) :test #'equal))
          (glasspane-views--persist)
          (when (equal glasspane-views--current name)
            (setq glasspane-views--current nil))
          (jetpacs-shell-notify (format "Deleted view %s" name))
          (jetpacs-shell-push))))
    :doc "Delete a saved view by name."
    :args '((:name name :type "text" :required t))))

(provide 'glasspane-views)
;;; glasspane-views.el ends here
