;;; glasspane-views.el --- Saved queries as views -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The query-surfaces rung, views third (docs/PLAN-glasspane-app.md,
;; G6): a named query rendered three ways over one result set — list
;; (table with property columns), board (kanban by TODO state), and
;; calendar (grouped by scheduled date).  Definitions persist through
;; Customize; the rendering choice persists per view.
;;
;; Retired against v1 (the plan's retirement list + G6 section):
;;
;; - The two-screens-one-shell-view trick, `views.back', and the
;;   drawer item (S1): each open view is a real Tier-1 chrome peer now —
;;   `views.open' pushes `jetpacs-wire-id "view" NAME', back is the
;;   screen's own arrow, and chrome truncates the stack on view.switched.
;;   Agenda's Saved page is the active entry; this module retains the
;;   historical `views.hub' screen/verb only for rollback and PA-3d's alias
;;   cutover.
;; - The `jetpacs-form' registry and its id-rotation reset (S2/S3):
;;   the new-view form is three literal stateful ids, `views.save'
;;   reads them back through `jetpacs-ui-state', and the device-side
;;   clear is `:reset-input-ids' on the deferred repush.
;; - The `jetpacs-ui-state' writes under "views-cal-" (S2): calendar
;;   anchor/selection are app defvars whose single writer is the
;;   views.cal.* handler pair; the widgets re-seed each render.
;; - Raw file/pos riding the reorder items (D-4): the drag list
;;   registers its resolution in the reader's per-list table and the
;;   G4 `heading.reorder' handler recovers file and positions there —
;;   the v1 `(view . "glasspane.views")' repush routing dies with the
;;   view fabric.
;; - `jetpacs-node-or' (T2): `jetpacs-node-advertised-p' conditionals.
;; - `:strike'/`:tag' span members (T3, FOUNDATION-GAPS #7): done rows
;;   degrade to on_surface_variant color; tag spans style with
;;   `:color' + `:on-tap'.
;; - Explicit `:when-offline "drop"' (T4, the default); the four queue
;;   sites carry `:ttl-s' now — build-time errors replaced silent drops.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'jetpacs-settings)
(require 'glasspane-org)
(require 'glasspane-ui)                 ; shared tokenization helper
(require 'glasspane-org-reader)         ; the reorder resolution table (D-4)
(require 'glasspane-agenda)             ; card date row + month fallback grid

(defcustom glasspane-saved-views nil
  "Saved query views: a list of alists with `name', `query', `rendering'.
`query' is a STRING in the ebp-org search grammar (`ebp-org-parse-query':
a printed query sexp, filter tokens, or free text); `rendering' is
\"list\" | \"board\" | \"calendar\".  Managed from the phone; persisted
through Customize."
  :type '(repeat sexp) :group 'jetpacs)

(defconst glasspane-views--renderings '("list" "board" "calendar"))

(defconst glasspane-views--ttl-s 86400
  "Offline retention for queued view mutations (one day, SPEC 14.1).
A todo-set/schedule/delete older than that replays against a vault
that has long moved on.")

(defconst glasspane-views--hub-screen-id "glasspane-views"
  "The hub's chrome screen id; per-view screens mint their own.")

(defconst glasspane-views--form-ids
  '("views-new-name" "views-new-query" "views-new-rendering")
  "The new-view form's stateful ids, authored literally in the hub body.
Each appears exactly once per document, so the first claimant keeps
the stable name (`jetpacs-claimed-node-id') and these literals ARE the
emitted ids `:reset-input-ids' must name.")

;;;; State (S2 — the handlers below are the only writers)

(defvar glasspane-views--reorder nil
  "Non-nil while the open view's list rendering shows the drag list.
Reset when a view opens.")

(defvar glasspane-views--cal-anchor nil
  "The calendar rendering's anchor date (\"YYYY-MM-DD\"), or nil for today.
Written only by the views.cal.* handlers; reset when a view opens.")

(defvar glasspane-views--cal-selected nil
  "The calendar rendering's selected day (\"YYYY-MM-DD\"), or nil.
Written only by the views.cal.* handlers; reset when a view opens.")

(defvar glasspane-views--reorder-lists nil
  "List ids this module registered in the reader's resolution table.
Tracked so unregister can sweep exactly what this module wrote there.")

;;;; The saved-view registry

(defun glasspane-views--get (name)
  (cl-find name glasspane-saved-views
           :key (lambda (v) (alist-get 'name v)) :test #'equal))

(defun glasspane-views--persist ()
  (jetpacs-settings-save-variable 'glasspane-saved-views
                                  glasspane-saved-views))

(defun glasspane-views--rendering (view)
  "VIEW's rendering, coerced back to one we offer.
A hand-authored Customize entry may carry junk or nothing."
  (let ((r (alist-get 'rendering view)))
    (if (member r glasspane-views--renderings) r "list")))

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
  "Run VIEW's query; heading items, or signal `user-error'.
`ebp-org-parse-query' reads strings only, so a hand-authored sexp
entry is printed first — with truncation off, or two entries could
render each other's results (the core's own %S rule)."
  (let ((q (alist-get 'query view)))
    (glasspane-org-search
     (if (stringp q) q
       (let ((print-length nil) (print-level nil) (print-circle t))
         (format "%S" q))))))

;;;; Renderings

(defun glasspane-views--tap (item)
  "The drill-in action for ITEM's heading, or nil when it never minted."
  (when-let* ((token (alist-get 'token item)))
    (jetpacs-action "heading.tap" :args (list :token token))))

(defun glasspane-views--done-p (item)
  "Non-nil when ITEM's todo keyword is a done state."
  (let ((todo (alist-get 'todo item)))
    (and todo (member todo (or (default-value 'org-done-keywords)
                               '("DONE" "CANCELLED")))
         t)))

(defconst glasspane-views--priority-colors
  '(("A" . "#E53935") ("B" . "#F57C00") ("C" . "#1976D2"))
  "Badge color per priority; anything else renders neutral gray.")

(defun glasspane-views--priority-span (priority)
  "The bold colored [P] badge span, or nil without PRIORITY."
  (when priority
    (jetpacs-span (format "[%s] " priority)
                  :font-weight "bold"
                  :color (or (cdr (assoc priority
                                         glasspane-views--priority-colors))
                             "#9E9E9E"))))

(defun glasspane-views--headline-spans (item)
  "Priority badge + headline spans; done titles degrade to color
\(no strike span on the wire — FOUNDATION-GAPS #7).  One span list
feeds both table cells and `jetpacs-rich-text' cards."
  (let ((headline (or (alist-get 'headline item) "")))
    (delq nil
          (list (glasspane-views--priority-span (alist-get 'priority item))
                (jetpacs-span headline
                              :color (and (glasspane-views--done-p item)
                                          "on_surface_variant"))))))

(defun glasspane-views--tag-action (tag)
  "The tap action shared by tag spans and chips: search by TAG."
  (jetpacs-action "search.by-tag" :args (list :tag tag)))

(defun glasspane-views--tag-spans (item)
  "Tappable #tag spans for the list rendering's Tags cell."
  (let (spans)
    (dolist (tg (append (alist-get 'tags item) nil))
      (when spans (push (jetpacs-span " ") spans))
      (push (jetpacs-span (concat "#" tg)
                          :color "#1976D2"
                          :on-tap (glasspane-views--tag-action tg))
            spans))
    (nreverse spans)))

(defun glasspane-views--tag-chips (item)
  "The tappable tag chip row for card renderings, or nil without tags."
  (when-let* ((tags (append (alist-get 'tags item) nil)))
    (apply #'jetpacs-flow-row
           (mapcar (lambda (tg)
                     (jetpacs-assist-chip
                      tg :on-tap (glasspane-views--tag-action tg)))
                   tags))))

(defun glasspane-views--caption (item)
  "The todo · file caption line, or nil when neither is known."
  (let ((caption (string-join
                  (delq nil (list (alist-get 'todo item)
                                  (when-let* ((file (alist-get 'file item)))
                                    (file-name-nondirectory file))))
                  "  ·  ")))
    (unless (string-empty-p caption) caption)))

(defun glasspane-views--done-keyword ()
  "The keyword a swipe-to-complete lands on."
  (or (car (default-value 'org-done-keywords)) "DONE"))

(defun glasspane-views--card (item &optional trailing)
  "The shared rich card for ITEM; TRAILING sits at the row's end.
Priority-badged headline, todo · file caption, compact
scheduled/deadline row, tappable tag chips.  Swipe from the start
completes an open todo; swipe from the end schedules it today — both
remain reachable by tap → detail.  Every wired affordance needs the
minted token, so an unmintable item renders inert rather than
carrying a ref on the wire (D-4)."
  (let* ((token (alist-get 'token item))
         (middle
          (apply #'jetpacs-column
                 (delq nil
                       (list
                        (jetpacs-rich-text
                         (glasspane-views--headline-spans item))
                        (when-let* ((caption (glasspane-views--caption item)))
                          (jetpacs-text caption :style "caption"))
                        (glasspane-agenda-card-date-row item)
                        (glasspane-views--tag-chips item))))))
    (jetpacs-card
     (list (apply #'jetpacs-row
                  (delq nil
                        (list (jetpacs-with-attrs (jetpacs-box middle)
                                                  :weight 1)
                              trailing))))
     :on-tap (glasspane-views--tap item)
     :swipe-start
     (when (and token (not (glasspane-views--done-p item)))
       (jetpacs-swipe "Done" :icon "check" :color "#2E7D32"
                      :on-trigger
                      (jetpacs-action "heading.todo-set"
                                      :args (list :token token
                                                  :state (glasspane-views--done-keyword))
                                      :when-offline "queue"
                                      :ttl-s glasspane-views--ttl-s)))
     :swipe-end
     (when token
       (jetpacs-swipe "Today" :icon "today"
                      :on-trigger
                      (jetpacs-action "heading.schedule"
                                      :args (list :token token :when "+0d")
                                      :when-offline "queue"
                                      :ttl-s glasspane-views--ttl-s))))))

;;;; The drag-reorder list

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
Resolution registers in the reader's per-list table — the G4
`heading.reorder' handler is the only code that resolves the verb, and
file/positions live Emacs-side (D-4); the wire carries the minted list
id and item keys alone.  The stars stay in the label so the level is
visible without a widget-side indent (the reader's rule)."
  (let* ((true (file-truename file))
         (list-id (jetpacs-wire-id "views-reorder" true))
         (keys nil)
         (rows (mapcar
                (lambda (it)
                  (let* ((pos (alist-get 'pos it))
                         (key (jetpacs-wire-id
                               "vr" (format "%s@%d" true pos))))
                    (push (cons key pos) keys)
                    (jetpacs-with-attrs
                     (jetpacs-text
                      (concat (make-string (alist-get 'level it) ?*) " "
                              (or (alist-get 'headline it) ""))
                      :style "body" :max-lines 2)
                     :key key)))
                items)))
    (glasspane-org-reader-refile-store
     list-id (list :file true :keys (nreverse keys)))
    (cl-pushnew list-id glasspane-views--reorder-lists :test #'equal)
    (jetpacs-reorderable-list
     rows
     :on-reorder (jetpacs-action "heading.reorder"
                                 :args (list :list list-id)))))

;;;; The list rendering

(defun glasspane-views--table-node (items)
  "The list rendering: one table row per item, tappable cells."
  (jetpacs-table
   (cons
    (jetpacs-table-row
     "header"
     (jetpacs-table-cell (list (jetpacs-span "Heading" :font-weight "bold")))
     (jetpacs-table-cell (list (jetpacs-span "State" :font-weight "bold")))
     (jetpacs-table-cell (list (jetpacs-span "Scheduled" :font-weight "bold")))
     (jetpacs-table-cell (list (jetpacs-span "Tags" :font-weight "bold"))))
    (mapcar
     (lambda (item)
       (let ((tap (glasspane-views--tap item)))
         (jetpacs-table-row
          "data"
          (jetpacs-table-cell (glasspane-views--headline-spans item)
                              :on-tap tap)
          (jetpacs-table-cell
           (list (jetpacs-span (or (alist-get 'todo item) "")
                               :color (and (glasspane-views--done-p item)
                                           "on_surface_variant"))))
          (jetpacs-table-cell
           (list (jetpacs-span (or (ebp-org-ts-date
                                    (alist-get 'scheduled item))
                                   ""))))
          (jetpacs-table-cell (glasspane-views--tag-spans item)))))
     items))
   :aligns '("start" "start" "start" "start")))

;;;; The board rendering

(defun glasspane-views--board-columns (items)
  "Distinct TODO states across ITEMS, keyword order preserved.
Global keywords come first in `org-todo-keywords-1' order; states the
global list doesn't know (file-local #+TODO: lines) follow in encounter
order — every present state gets a column, or its cards would silently
vanish from the board."
  (let ((globals (default-value 'org-todo-keywords-1))
        (present (delete-dups (mapcar (lambda (i)
                                        (or (alist-get 'todo i) ""))
                                      items))))
    (append (cl-remove-if-not (lambda (kw) (member kw present)) globals)
            (cl-remove-if (lambda (kw)
                            (or (string-empty-p kw) (member kw globals)))
                          present)
            (and (member "" present) '("")))))

(defun glasspane-views--board-card (item columns)
  "A board card: tap opens the heading; the menu moves it to a column.
Board columns still don't drag — no drag-between-columns wire node
exists — so the move is a menu of the OTHER columns."
  (let ((token (alist-get 'token item))
        (state (or (alist-get 'todo item) "")))
    (glasspane-views--card
     item
     (when token
       (jetpacs-menu
        (mapcar (lambda (target)
                  (jetpacs-menu-item
                   (if (string-empty-p target) "No state" target)
                   (jetpacs-action "heading.todo-set"
                                   :args (list :token token :state target)
                                   :when-offline "queue"
                                   :ttl-s glasspane-views--ttl-s)))
                (remove state columns))
        :icon "more_vert")))))

(defun glasspane-views--board-node (items)
  "The kanban rendering: one column per TODO state, panning sideways.
Columns pin a width: the client renders columns fillMaxWidth (the G3
flex-trap lesson, horizontal edition), so an unbounded one would
swallow the scroll row and hide its siblings past the fold."
  (let ((columns (glasspane-views--board-columns items)))
    (apply #'jetpacs-row
           (append
            (mapcar
             (lambda (col)
               (let ((in-col (cl-remove-if-not
                              (lambda (i) (equal (or (alist-get 'todo i) "")
                                                 col))
                              items)))
                 (jetpacs-with-attrs
                  (jetpacs-box
                   (apply #'jetpacs-column
                          (cons (jetpacs-section-header
                                 (format "%s (%d)"
                                         (if (string-empty-p col)
                                             "No state" col)
                                         (length in-col)))
                                (mapcar (lambda (i)
                                          (glasspane-views--board-card
                                           i columns))
                                        in-col))))
                  :width 260 :padding 4)))
             columns)
            (list :scroll t)))))

;;;; The calendar rendering

(defun glasspane-views--cal-anchor-date ()
  "The calendar's anchor date as \"YYYY-MM-DD\"; today when unset."
  (let ((a glasspane-views--cal-anchor))
    (if (and (stringp a)
             (string-match-p
              "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" a))
        a
      (format-time-string "%Y-%m-%d"))))

(defun glasspane-views--calendar-node (items)
  "The calendar rendering: a month grid over ITEMS' scheduled dates.
The curated `month_grid' when the device advertises it (marks = item
count per day, month swipe), the composed fallback grid otherwise;
below it the selected day's cards and the Unscheduled section."
  (let* ((today (format-time-string "%Y-%m-%d"))
         (anchor (glasspane-views--cal-anchor-date))
         (month-prefix (substring anchor 0 7))
         (sel glasspane-views--cal-selected)
         ;; A remembered selection only counts inside the shown month;
         ;; otherwise select today (when visible) or the anchor day.
         (selected-date (cond
                         ((and (stringp sel)
                               (string-prefix-p month-prefix sel))
                          sel)
                         ((string-prefix-p month-prefix today) today)
                         (t anchor)))
         (items-by-date (seq-group-by
                         (lambda (it)
                           (ebp-org-ts-date (alist-get 'scheduled it)))
                         items))
         (unscheduled (cdr (assoc nil items-by-date)))
         (selected-items (cdr (assoc selected-date items-by-date))))
    (apply #'jetpacs-column
           (delq nil
                 (list
                  (if (jetpacs-node-advertised-p "month_grid")
                      (jetpacs-month-grid
                       month-prefix
                       ;; One mark per date, dots = item count capped
                       ;; at the node's 0..3 grammar.
                       :marks (delq nil
                                    (mapcar
                                     (lambda (g)
                                       (and (stringp (car g))
                                            (cons (car g)
                                                  (jetpacs-month-mark
                                                   (min 3 (length (cdr g)))))))
                                     items-by-date))
                       :selected selected-date
                       ;; Taps arrive with the ISO date as args :value.
                       :on-day-tap (jetpacs-action "views.cal.select-date")
                       ;; Device-local swipe/chevrons report the shown
                       ;; month; the handler re-anchors and pushes
                       ;; fresh marks for it.
                       :on-month-change (jetpacs-action "views.cal.set-month"))
                    (glasspane-agenda-month-fallback
                     items-by-date anchor selected-date
                     "views.cal.select-date"))
                  (jetpacs-divider)
                  (jetpacs-section-header (format "Events for %s"
                                                  selected-date))
                  (if selected-items
                      (apply #'jetpacs-column
                             (mapcar #'glasspane-views--card
                                     selected-items))
                    (jetpacs-text "No events" :style "caption"))
                  (when unscheduled (jetpacs-divider))
                  (when unscheduled
                    (jetpacs-section-header
                     (format "Unscheduled (%d)" (length unscheduled))))
                  (when unscheduled
                    (apply #'jetpacs-column
                           (mapcar #'glasspane-views--card
                                   unscheduled))))))))

;;;; The per-view screen

(defun glasspane-views--rendering-chips (view)
  "The List | Board | Calendar switcher for devices predating `tabs'."
  (apply #'jetpacs-row
         (mapcar (lambda (r)
                   (jetpacs-chip
                    (capitalize r)
                    :selected (jetpacs-bool
                               (equal r (glasspane-views--rendering view)))
                    :on-tap (jetpacs-action
                             "views.rendering"
                             :args (list :name (alist-get 'name view)
                                         :rendering r))))
                 glasspane-views--renderings)))

(defun glasspane-views--rendering-tabs (view items file)
  "The list | board | calendar pager for VIEW over ITEMS.
Every page ships in the push, so switching is device-local and works
offline; on_change persists the settled page as the view's rendering.
`:id' is keyed by the view name — deliberately, unlike the agenda's
no-id tabs: opening a DIFFERENT view must reset the pager to that
view's persisted rendering, while re-pushes of the same view keep the
user's page.  FILE is the single-file guard result gating the list
page's drag-reorder body."
  (let* ((name (alist-get 'name view))
         (rendering (glasspane-views--rendering view))
         (initial (or (seq-position glasspane-views--renderings rendering)
                      0)))
    (jetpacs-tabs
     (mapcar (lambda (r) (jetpacs-tab-item (capitalize r)))
             glasspane-views--renderings)
     (list (if (and glasspane-views--reorder file)
               (glasspane-views--reorder-node items file)
             (glasspane-views--table-node items))
           (glasspane-views--board-node items)
           (glasspane-views--calendar-node items))
     :initial initial
     :id (jetpacs-wire-id "views-tabs" name)
     :on-change (jetpacs-action "views.rendering"
                                :args (list :name name)))))

(defun glasspane-views--view-body (view)
  "The body for one saved VIEW."
  (let* ((items (condition-case err
                    (glasspane-views--items view)
                  ;; The grammar's own feedback ("Query too long",
                  ;; an unknown term) rendered back at its author is
                  ;; the feature; this is a screen, not a log, and
                  ;; the datum is the user's own saved query (23.3
                  ;; governs labels/logs, not renders).
                  (user-error (list 'error (error-message-string err)))))
         (broken (eq (car-safe items) 'error))
         ;; Set "views", minted even when broken/empty: only one view
         ;; screen renders at a time, so one set serves them all, and
         ;; its replace sweep is what retires the previous render's
         ;; tokens — what makes a sheet left open on view A answer
         ;; `stale' once view B has drawn (S5).
         (items (if broken
                    (progn (ebp-org-ref-tokens nil :set "views"
                                               :owner "glasspane")
                           items)
                  (glasspane-ui-tokenize-tap items "views")))
         (file (and (not broken) (glasspane-views--single-file items))))
    (apply #'jetpacs-lazy-column
           (append
            ;; Drag reorder only makes sense on one file's list — see
            ;; `glasspane-views--single-file'.
            (when file
              (list (jetpacs-row
                     (jetpacs-spacer :weight 1)
                     (jetpacs-icon-button
                      "swap_vert"
                      (jetpacs-action "views.reorder")
                      :content-description "Toggle drag reorder"))))
            (cond
             (broken
              (list (jetpacs-text (cadr items) :style "body")))
             ((null items)
              ;; %s: a hand-authored query may be a sexp, not a string.
              (list (jetpacs-empty-state
                     :icon "manage_search"
                     :title "No matches"
                     :caption (format "%s" (alist-get 'query view)))))
             (t
              (list
               (if (jetpacs-node-advertised-p "tabs")
                   (glasspane-views--rendering-tabs view items file)
                 ;; Pre-`tabs' devices keep the chip switcher over the
                 ;; one persisted rendering.
                 (jetpacs-column
                  (glasspane-views--rendering-chips view)
                  (jetpacs-spacer :height 4)
                  (pcase (glasspane-views--rendering view)
                    ("board" (glasspane-views--board-node items))
                    ("calendar" (glasspane-views--calendar-node items))
                    (_ (if (and glasspane-views--reorder file)
                           (glasspane-views--reorder-node items file)
                         (glasspane-views--table-node items)))))))))))))

(defun glasspane-views--screen (name back)
  "The pushed screen for saved view NAME.
Re-looks the view up each render: the stacked builder outlives edits
and deletion, so a vanished view renders its tombstone rather than
taking the whole push down."
  (let ((view (glasspane-views--get name)))
    (jetpacs-chrome-screen
     name
     (if view
         (glasspane-views--view-body view)
       (jetpacs-empty-state :icon "manage_search"
                            :title "View deleted"
                            :caption "This saved view no longer exists."))
     :back back)))

;;;; The hub screen

(defun glasspane-views--new-form ()
  "The collapsed new-view form at the hub's foot.
Literal stateful ids: the device reconciles drafts against them
(SPEC 14.6), views.save reads them back through `jetpacs-ui-state',
and the post-save repush resets them (S2)."
  (jetpacs-collapsible
   "views-new"
   (jetpacs-section-header "New view")
   (list
    (jetpacs-text-input "views-new-name" :label "Name" :single-line t)
    (jetpacs-text-input "views-new-query"
                        :label "Query"
                        :hint "todo:TODO tags:work — or a query sexp"
                        :single-line t)
    (jetpacs-enum-list "views-new-rendering"
                       (mapcar (lambda (r)
                                 (jetpacs-enum-option (capitalize r) r))
                               glasspane-views--renderings)
                       :value "list")
    (jetpacs-button "Save view" (jetpacs-action "views.save") :icon "add"))
   :collapsed t))

(defun glasspane-views--hub-body ()
  "The hub: every saved view as a card, plus the new-view form."
  (apply #'jetpacs-lazy-column
         (append
          (if glasspane-saved-views
              (mapcar
               (lambda (view)
                 (let ((name (alist-get 'name view)))
                   (jetpacs-card
                    (list
                     (jetpacs-row
                      (jetpacs-with-attrs
                       (jetpacs-column
                        (jetpacs-text name :style "label")
                        (jetpacs-text (format "%s · %s"
                                              (glasspane-views--rendering view)
                                              (alist-get 'query view))
                                      :style "caption"))
                       :weight 1)
                      (jetpacs-icon-button
                       "delete"
                       (jetpacs-action "views.delete"
                                       :args (list :name name)
                                       :when-offline "queue"
                                       :ttl-s glasspane-views--ttl-s)
                       :content-description "Delete view")))
                    :on-tap (jetpacs-action "views.open"
                                            :args (list :name name)))))
               glasspane-saved-views)
            (list (jetpacs-empty-state
                   :icon "manage_search" :title "No saved views"
                   :caption "Name a query below and it becomes a view")))
          (list (jetpacs-divider) (glasspane-views--new-form)))))

(defun glasspane-views--hub-screen (back)
  "The pushed Saved views hub screen."
  (jetpacs-chrome-screen "Saved views" (glasspane-views--hub-body)
                         :back back))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-views--push-screen (params id builder)
  "Defer-push screen ID via BUILDER onto PARAMS' surface (D2); `accepted'.
A deferred `jetpacs-chrome-push-screen' must catch its own re-signal
or a refused gate dies in a timer."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       (condition-case err
           (jetpacs-chrome-push-screen surface id builder)
         (error (message "glasspane: %s push failed: %s"
                         id (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-views--on-hub (_args params)
  "Push the Saved views hub onto the tapped surface."
  (glasspane-views--push-screen params glasspane-views--hub-screen-id
                                #'glasspane-views--hub-screen))

(defun glasspane-views--on-open (args params)
  "Open saved view `:name' as a pushed screen; reset its per-view state."
  (let ((name (plist-get args :name)))
    (cond
     ((not (stringp name)) 'rejected)
     ((not (glasspane-views--get name))
      ;; The card outlived the list it was rendered from.
      (jetpacs-toast "That view no longer exists")
      (jetpacs-app-defer-refresh params)
      'stale)
     (t
      (setq glasspane-views--reorder nil
            glasspane-views--cal-anchor nil
            glasspane-views--cal-selected nil)
      (glasspane-ui-open-destination
       "agenda" (jetpacs-wire-id "view" name)
       (lambda (back) (glasspane-views--screen name back))
       params)))))

(defun glasspane-views--on-reorder (_args params)
  "Toggle the single-file list rendering's drag list."
  (setq glasspane-views--reorder (not glasspane-views--reorder))
  (jetpacs-app-defer-refresh params)
  'accepted)

(defun glasspane-views--on-cal-select-date (args params)
  "Select a calendar day.  `:date' comes from the composed fallback
grid's per-cell args; `:value' is what the curated month grid's
on_day_tap injects."
  (let ((date (or (plist-get args :date) (plist-get args :value))))
    (if (and (stringp date)
             (string-match-p
              "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date))
        (progn
          (setq glasspane-views--cal-selected date)
          (jetpacs-app-defer-refresh params)
          'accepted)
      'rejected)))

(defun glasspane-views--on-cal-set-month (args params)
  "Anchor on the 1st of the month on_month_change reported (`:value')."
  (let ((month (plist-get args :value)))
    (if (and (stringp month)
             (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}\\'" month))
        (progn
          (setq glasspane-views--cal-anchor (concat month "-01"))
          (jetpacs-app-defer-refresh params)
          'accepted)
      'rejected)))

(defun glasspane-views--on-rendering (args params)
  "Switch a saved view's rendering.  `:rendering' names come from the
fallback chips; `:value' (a page index) from the tabs pager's
on_change.  Either way the result must name a rendering we offer."
  (let* ((name (plist-get args :name))
         (idx (plist-get args :value))
         ;; A whole-valued integer can arrive as a float after the
         ;; JSON round trip (org.json emits the trailing .0).
         (idx (if (numberp idx) (truncate idx) idx))
         (rendering (or (plist-get args :rendering)
                        (and (integerp idx)
                             (nth idx glasspane-views--renderings)))))
    (cond
     ((not (stringp name)) 'rejected)
     ((not (glasspane-views--get name))
      ;; The pager outlived the view it was rendered for.
      (jetpacs-app-defer-refresh params)
      'stale)
     ((not (member rendering glasspane-views--renderings)) 'rejected)
     (t
      (glasspane-views--set-rendering name rendering)
      (glasspane-views--persist)
      (jetpacs-app-defer-refresh params)
      'accepted))))

(defun glasspane-views--field (id)
  "The trimmed reconciled string for stateful ID; \"\" when unset."
  (let ((v (jetpacs-ui-state id)))
    (if (stringp v) (string-trim v) "")))

(defun glasspane-views--on-save (_args params)
  "Create or replace a saved view from the hub form's reconciled fields.
The reads need the live session's draft store, so no client refuses
outright; `accepted' only after the definition is persisted (durable),
with the deferred repush clearing the device drafts."
  (if (null (jetpacs-client))
      'rejected
    (let* ((name (glasspane-views--field "views-new-name"))
           (query (glasspane-views--field "views-new-query"))
           (rendering (let ((r (jetpacs-ui-state "views-new-rendering")))
                        ;; Single-select: ONE option value — but be
                        ;; liberal in case an old draft stored a list.
                        (cond ((and (vectorp r) (> (length r) 0))
                               (aref r 0))
                              ((and (consp r) (not (keywordp (car r))))
                               (car r))
                              (t r)))))
      (cond
       ((string-empty-p name)
        (jetpacs-shell-notify "The view needs a name")
        'rejected)
       ((string-empty-p query)
        (jetpacs-shell-notify "The view needs a query")
        'rejected)
       (t
        (condition-case nil
            (progn
              ;; Parse now so a broken query fails at save, not render.
              (ebp-org-parse-query query)
              (setq glasspane-saved-views
                    (append (cl-remove name glasspane-saved-views
                                       :key (lambda (v) (alist-get 'name v))
                                       :test #'equal)
                            (list (list (cons 'name name)
                                        (cons 'query query)
                                        (cons 'rendering
                                              (if (member rendering
                                                          glasspane-views--renderings)
                                                  rendering "list"))))))
              (glasspane-views--persist)
              (jetpacs-shell-notify (format "Saved view %s" name))
              (let ((surface (or (plist-get params :surface)
                                 (jetpacs-shell-surface-for "glasspane"))))
                (jetpacs-flow-continue
                 (lambda ()
                   (ignore-errors
                     (jetpacs-shell-push
                      surface
                      :reset-input-ids glasspane-views--form-ids)))))
              'accepted)
          ;; The grammar's message would be feedback, but a NOTIFY is
          ;; a label path (SPEC 23.3/T2) — the authored line has to do;
          ;; opening the view would render the detail.
          (user-error
           (jetpacs-shell-notify "That query does not parse")
           'rejected)))))))

(defun glasspane-views--on-delete (args params)
  "Delete saved view `:name'; pop its screen when it is on top."
  (let ((name (plist-get args :name)))
    (cond
     ((not (stringp name)) 'rejected)
     ((not (glasspane-views--get name))
      (jetpacs-app-defer-refresh params)
      'stale)
     (t
      (setq glasspane-saved-views
            (cl-remove name glasspane-saved-views
                       :key (lambda (v) (alist-get 'name v)) :test #'equal))
      (glasspane-views--persist)
      (jetpacs-shell-notify (format "Deleted view %s" name))
      (let ((surface (or (plist-get params :surface)
                         (jetpacs-shell-surface-for "glasspane")))
            (screen-id (jetpacs-wire-id "view" name)))
        (jetpacs-flow-continue
         (lambda ()
           ;; Deleted from its own screen: leave for the hub below.
           (if (equal (car (jetpacs-chrome-stack surface)) screen-id)
               (jetpacs-chrome-pop-screen surface)
             (ignore-errors (jetpacs-shell-push surface))))))
      'accepted))))

;;;; Registration

(defconst glasspane-views--verbs
  '("views.hub"
    "views.open"
    "views.reorder"
    "views.cal.select-date"
    "views.cal.set-month"
    "views.rendering"
    "views.save"
    "views.delete")
  "The verbs this module owns, for the register/unregister sweep.
heading.todo-set/schedule/tap and heading.reorder are other modules'
verbs the boards/cards re-emit by wire string; search.by-tag is the
search sibling's.")

(defun glasspane-views-register ()
  "Register the saved-views verbs.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent: re-registration replaces the handlers in
place."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "views.hub" #'glasspane-views--on-hub
                       :doc "Open the saved-views hub screen")
    (jetpacs-defaction "views.open" #'glasspane-views--on-open
                       :doc "Open a saved view by name")
    (jetpacs-defaction "views.reorder" #'glasspane-views--on-reorder)
    (jetpacs-defaction "views.cal.select-date"
                       #'glasspane-views--on-cal-select-date)
    (jetpacs-defaction "views.cal.set-month"
                       #'glasspane-views--on-cal-set-month)
    (jetpacs-defaction "views.rendering" #'glasspane-views--on-rendering
                       :doc "Switch a saved view's rendering (list/board/calendar)")
    (jetpacs-defaction "views.save" #'glasspane-views--on-save)
    (jetpacs-defaction "views.delete" #'glasspane-views--on-delete
                       :doc "Delete a saved view by name")))

(defun glasspane-views-unregister ()
  "Drop the saved-views verbs and the reorder resolution records."
  (dolist (name glasspane-views--verbs)
    (jetpacs-undefaction name))
  (dolist (id glasspane-views--reorder-lists)
    (glasspane-org-reader-refile-store id nil))
  (setq glasspane-views--reorder-lists nil))

(provide 'glasspane-views)
;;; glasspane-views.el ends here
