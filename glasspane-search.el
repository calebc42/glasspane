;;; glasspane-search.el --- Glasspane search screen + query builder -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The query-surfaces rung, search third (docs/PLAN-glasspane-app.md,
;; G6): the S2 flagship.  The last query, its results, and every
;; builder filter live in app defvars whose single writers are the
;; handlers below, so the whole screen builds OFFLINE; results render
;; through the shared result card (glasspane-detail) over SPEC 23.1
;; tokens minted one set per render (S5); every handler answers a
;; SPEC 14.4 status (S4).
;;
;; Retired against v1 (the plan's retirement list + G6 section):
;;
;; - The nav fabric (`jetpacs-shell-define-view'/`-nav-view' at order
;;   70, the `:switch-to' pushes): S1 — the view is a chrome screen
;;   behind search.open, and run/by-tag land on it through
;;   `jetpacs-chrome-push-screen' (an id already on the stack
;;   truncates and replaces, so re-running from the screen itself
;;   never stacks a duplicate).
;; - The `jetpacs-ui-state' reads/writes and the "search-query"
;;   mirror (S2): filter persistence IS the feature (the v1 lesson at
;;   v1 glasspane-search.el:39-48), so it moves INTO the defvars —
;;   every widget re-seeds an explicit `:value' each render, and
;;   device-side drafts clear via `:reset-input-ids' on
;;   search.clear-filters (the only flow that must beat a draft).
;; - `jetpacs-filter-section' (T2): app-local collapsible composition
;;   (`glasspane-search--section', the v1 core shape transliterated).
;; - The builder's `(regexp ...)' text clause: `regexp' is off the
;;   SPEC 23.2 wire allowlist (ebp-org.el:828-836), and the builder's
;;   output must survive `ebp-org-parse-query' — so the text filter
;;   emits `(heading ...)', which regexp-quotes in the interpreter
;;   and matches the TITLE (the G6 gate-entry ruling: fix the
;;   builder, not the grammar; the section label says "Title
;;   contains" to match).  The deadline range forms
;;   (:on/:from/:to, `today') map 1:1 (ebp-org.el:983-1007) and port
;;   verbatim.
;; - The org-ql wording in the hint/caption strings: v3 never forks
;;   to org-ql (ebp-org.el:1276-1281); the strings name the query
;;   grammar generically.

;;; Code:

(require 'cl-lib)
(require 'ebp-org)
(require 'jetpacs-surfaces)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-chrome)
(require 'jetpacs-apps)
(require 'glasspane-org)
(require 'glasspane-ui)                 ; shared tokenization helper
(require 'glasspane-detail)             ; the shared result card (G4)
(require 'jetpacs-org-settings)      ; the global-TODO-keywords helper

;;;; State (S2 — the handlers below are the only writers)
;;
;; The search-filter-* widget ids are stable identities whose values
;; must persist across pushes and screen re-renders (that persistence
;; IS the feature — the section summaries and search.clear-filters
;; depend on it), so they live here rather than in any device-side
;; form state; every render re-seeds the widgets with an explicit
;; :value, which is what makes the reconciled input model safe.

(defvar glasspane-search--query ""
  "Last submitted query for the Search screen.
The search field re-seeds from it, so after a builder-driven run the
box shows the query that actually ran — the builder doubles as a
worked example of the query language.")

(defvar glasspane-search--results nil
  "Cached heading items from the last search (alists carrying a `ref').")

(defvar glasspane-search--error nil
  "Human-readable message when the last search query failed, else nil.")

(defvar glasspane-search--filter-todo nil
  "Builder status filter: a TODO keyword, \"Done (any)\", or nil for Any.")

(defvar glasspane-search--filter-tags nil
  "Builder tag filter: a list of tag strings, all of which must match.")

(defvar glasspane-search--filter-text ""
  "Builder title-contains filter; empty means unset.")

(defvar glasspane-search--filter-priority nil
  "Builder priority filter: \"A\"/\"B\"/\"C\", or nil for Any.")

(defvar glasspane-search--filter-due nil
  "Builder due filter: \"Overdue\"/\"Today\"/\"This week\", or nil for Any.")

;;;; The builder's query sexp (points at the ebp-org wire grammar)

(defun glasspane-search--filter-query ()
  "Build a query string from the builder filter state.
Returns \"\" when every filter is at its resting value.  The output
round-trips `ebp-org-parse-query' — the sexp arm's SPEC 23.2 vetter —
which is why the text filter emits `heading' (title match,
regexp-quoted by the interpreter) and never `regexp' (off the wire
allowlist, ebp-org.el:828-836).  A pathological filter set can exceed
the wire query length cap; the parse refusal then lands in the error
card like any other bad query."
  (let ((todo glasspane-search--filter-todo)
        (text glasspane-search--filter-text)
        (prio glasspane-search--filter-priority)
        (clauses nil))
    (cond
     ((or (null todo) (equal todo "Any")))
     ((equal todo "Done (any)") (push '(done) clauses))
     (t (push `(todo ,todo) clauses)))
    ;; One clause per tag under the (and ...): the grammar's (tags A B)
    ;; is ANY-of, the builder's contract is ALL-of.
    (dolist (tg glasspane-search--filter-tags)
      (push `(tags ,tg) clauses))
    (when (and (stringp prio) (not (member prio '("Any" ""))))
      (push `(priority ,prio) clauses))
    (pcase glasspane-search--filter-due
      ("Overdue" (push '(deadline :to -1) clauses))
      ("Today" (push '(deadline :on today) clauses))
      ("This week" (push '(deadline :from today :to 7) clauses)))
    (when (and (stringp text) (not (string-empty-p (string-trim text))))
      (push `(heading ,(string-trim text)) clauses))
    (setq clauses (nreverse clauses))
    ;; Truncation OFF: `format' honours print-length/print-level, and a
    ;; caller with either bound would emit an elided, unparseable query
    ;; (the engine's own rule, ebp-org.el:1271-1274).
    (let ((print-length nil) (print-level nil))
      (cond ((null clauses) "")
            ((null (cdr clauses)) (format "%S" (car clauses)))
            (t (format "%S" `(and ,@clauses)))))))

;;;; Running a search

(defun glasspane-search--run (q)
  "Run search query Q, refreshing the cached results and error state.
A failed query lands in `glasspane-search--error' for the screen to
show — the body renders it instead of a bogus \"no matches\".  The
grammar's `user-error's are curated to never echo query material
\(ebp-org.el:884,906-907), so their message is safe to surface; any
other signal shows only its symbol (SPEC 23.3 — the datum may embed
paths or payload)."
  (setq glasspane-search--query q
        glasspane-search--error nil
        glasspane-search--results
        (condition-case err
            (glasspane-org-search q)
          (ebp-org-unavailable
           (setq glasspane-search--error
                 "No org files available to search")
           nil)
          (user-error
           (setq glasspane-search--error (error-message-string err))
           nil)
          (error
           (setq glasspane-search--error
                 (format "Search failed (%s)" (jetpacs-error-label err)))
           nil))))

;;;; The query builder card

(defun glasspane-search--section (key label summary widget)
  "One collapsible filter section, folded by default.
KEY names the fold-state id under the search prefix; LABEL is the
always-visible section name.  SUMMARY, when non-nil, is the active
value rendered into the header so a folded section still shows what
it contributes.  WIDGET is the section's control.  (v1 core's
`jetpacs-filter-section', app-local per T2.)"
  (jetpacs-collapsible
   (concat "search-sec-" key)
   (if summary
       (jetpacs-rich-text
        (list (jetpacs-span (concat label ": ") :font-weight "bold")
              (jetpacs-span summary))
        :style "body")
     (jetpacs-text label :style "body"))
   widget
   :collapsed t))

(defun glasspane-search--enum-options (values)
  "VALUES (strings) as the enum-option nodes `jetpacs-enum-list' requires."
  (mapcar (lambda (v) (jetpacs-enum-option v v)) values))

(defun glasspane-search--builder ()
  "The query-builder card for the Search screen.
Every filter change reruns the search and writes the equivalent query
into the search field, so the builder doubles as a worked example of
the query language.  Each filter lives in its own collapsible section
whose header names the active value, so the folded builder reads as a
filter summary.  The whole card starts folded once a search has
results, to keep them above the fold."
  ;; A stored value can outlive its option list (a TODO keyword removed
  ;; from `org-todo-keywords'); the enum-list build SIGNALS on a value
  ;; not among its options, so stale values re-seed as the resting one.
  (let* ((todo-opts (delete-dups
                     (append '("Any")
                             (jetpacs-org-settings-global-todo-keywords)
                             '("Done (any)"))))
         (todo-val (if (member glasspane-search--filter-todo todo-opts)
                       glasspane-search--filter-todo
                     "Any"))
         (tags-list glasspane-search--filter-tags)
         (text-val (or glasspane-search--filter-text ""))
         (prio-opts '("Any" "A" "B" "C"))
         (prio-val (if (member glasspane-search--filter-priority prio-opts)
                       glasspane-search--filter-priority
                     "Any"))
         (due-opts '("Any" "Overdue" "Today" "This week"))
         (due-val (if (member glasspane-search--filter-due due-opts)
                      glasspane-search--filter-due
                    "Any")))
    (jetpacs-with-attrs
     (jetpacs-card
      (list
       (jetpacs-collapsible
        "search-builder"
        (jetpacs-text "Query builder" :style "headline")
        (glasspane-search--section
         "todo" "Status" (unless (equal todo-val "Any") todo-val)
         (jetpacs-enum-list "search-filter-todo"
                            (glasspane-search--enum-options todo-opts)
                            :value todo-val
                            :on-change (jetpacs-action
                                        "search.update-filter"
                                        :args '(:field "todo"))))
        (glasspane-search--section
         "tags" "Tags (all must match)"
         (when tags-list (string-join tags-list ", "))
         (jetpacs-enum-list "search-filter-tags"
                            (glasspane-search--enum-options
                             (glasspane-org-all-tags))
                            :value (vconcat tags-list)
                            :multi-select t
                            :allow-add t
                            :on-change (jetpacs-action
                                        "search.update-filter"
                                        :args '(:field "tags"))))
        (glasspane-search--section
         "priority" "Priority" (unless (equal prio-val "Any") prio-val)
         (jetpacs-enum-list "search-filter-priority"
                            (glasspane-search--enum-options prio-opts)
                            :value prio-val
                            :on-change (jetpacs-action
                                        "search.update-filter"
                                        :args '(:field "priority"))))
        (glasspane-search--section
         "due" "Due" (unless (equal due-val "Any") due-val)
         (jetpacs-enum-list "search-filter-due"
                            (glasspane-search--enum-options due-opts)
                            :value due-val
                            :on-change (jetpacs-action
                                        "search.update-filter"
                                        :args '(:field "due"))))
        (glasspane-search--section
         "text" "Title contains"
         (unless (string-empty-p text-val) text-val)
         (jetpacs-text-input "search-filter-text"
                             :value text-val
                             :hint "e.g. meeting notes"
                             :single-line t
                             :on-submit (jetpacs-action
                                         "search.update-filter"
                                         :args '(:field "text"))))
        (jetpacs-row
         (jetpacs-with-attrs
          (jetpacs-box
           (jetpacs-text "Filters search as you pick them and write the query below — edit it there to go further."
                         :style "caption"))
          :weight 1)
         (jetpacs-button "Clear" (jetpacs-action "search.clear-filters")))
        :collapsed (and glasspane-search--results t))))
     :padding 16)))

;;;; The screen

(defun glasspane-search--body ()
  "The Search screen body: builder card, search row, results."
  (let* ((q (or glasspane-search--query ""))
         ;; Set "search-results": this screen's own, one render at a
         ;; time — the replace sweep retires the last result list.
         (items (glasspane-ui-tokenize-tap glasspane-search--results
                                            "search-results"))
         (cards (mapcar #'glasspane-detail-result-card items))
         (input (jetpacs-text-input
                 "search-query"
                 :value q
                 :hint "Text, todo:NEXT tags:work, or a (query sexp)"
                 :single-line t
                 :on-submit (jetpacs-action "org.search.run"))))
    ;; One lazy column for the whole screen: the builder card can grow
    ;; taller than the display (a big tag vocabulary), so everything —
    ;; builder, search row, results — must share a single scroll.  A
    ;; plain column gives overflowing children zero height instead.
    (apply
     #'jetpacs-lazy-column
     (glasspane-search--builder)
     (jetpacs-spacer :height 8)
     (jetpacs-row
      (jetpacs-with-attrs (jetpacs-box input) :weight 1)
      (jetpacs-button "Search" (jetpacs-action "org.search.run"
                                               :args (list :value q)))
      (jetpacs-button "Save" (jetpacs-action "agenda.save-custom"
                                             :args (list :query q))))
     (jetpacs-spacer :height 8)
     (cond
      (glasspane-search--error
       (list (jetpacs-empty-state :icon "error"
                                  :title "Query error"
                                  :caption glasspane-search--error)))
      (cards
       (cons (jetpacs-section-header
              (format "%d match%s" (length cards)
                      (if (= (length cards) 1) "" "es")))
             cards))
      ((not (string-empty-p q))
       (list (jetpacs-empty-state
              :icon "manage_search"
              :title "No matches"
              :caption (format "Nothing matched \"%s\"." q))))
      (t
       (list (jetpacs-empty-state
              :icon "search"
              :title "Search your notes"
              :caption "Type a query, or open the query builder above.")))))))

(defun glasspane-search-screen (back)
  "The pushed Search screen."
  (jetpacs-chrome-screen "Search" (glasspane-search--body) :back back))

;;;; Handlers (S4 — every one answers accepted/stale/rejected)

(defun glasspane-search--push-screen (params)
  "Defer-push the Search screen onto PARAMS' surface (D2); `accepted'.
A deferred `jetpacs-chrome-push-screen' must catch its own re-signal
or a refused gate dies in a timer.  Fired FROM the Search screen, the
push replaces in place (stack-insert truncates on a duplicate id)."
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       (condition-case err
           (jetpacs-chrome-push-screen surface "glasspane-search"
                                       #'glasspane-search-screen)
         (error (message "glasspane: search push failed: %s"
                         (jetpacs-error-label err))))))
    'accepted))

(defun glasspane-search--on-open (_args params)
  "Push the Search screen onto the tapped surface."
  (glasspane-search--push-screen params))

(defun glasspane-search--on-run (args params)
  "Run `:value' (the field's on-submit injection, or the Search
button's echo of the last query) and land on the Search screen.
A query the grammar refuses still answers `accepted': the error card
IS the render, and the effect is durable in the error state (S4)."
  (let ((q (plist-get args :value)))
    (if (and q (not (stringp q)))
        'rejected
      (glasspane-search--run (or q ""))
      (glasspane-search--push-screen params))))

(defun glasspane-search--on-update-filter (args params)
  "One builder filter changed: store it, rebuild the query, rerun.
The results and the query text update together — no extra Search tap
needed.  `:value' rides the control's on-change/on-submit injection:
one option value (or nil on deselect) for the single-select enums, a
vector for tags, a string for text."
  (let ((value (plist-get args :value)))
    (cl-block nil
      (pcase (plist-get args :field)
        ("todo"
         (unless (or (null value) (stringp value)) (cl-return 'rejected))
         (setq glasspane-search--filter-todo value))
        ("priority"
         (unless (or (null value) (stringp value)) (cl-return 'rejected))
         (setq glasspane-search--filter-priority value))
        ("due"
         (unless (or (null value) (stringp value)) (cl-return 'rejected))
         (setq glasspane-search--filter-due value))
        ("tags"
         (let ((tags (cond ((vectorp value) (append value nil))
                           ((proper-list-p value) (copy-sequence value))
                           (t (cl-return 'rejected)))))
           (unless (cl-every #'stringp tags) (cl-return 'rejected))
           (setq glasspane-search--filter-tags (delete-dups tags))))
        ("text"
         (unless (stringp value) (cl-return 'rejected))
         (setq glasspane-search--filter-text value))
        (_ (cl-return 'rejected)))
      (glasspane-search--run (glasspane-search--filter-query))
      (jetpacs-app-defer-refresh params)
      'accepted)))

(defun glasspane-search--on-clear-filters (_args params)
  "Reset every builder filter and the query, then clear device drafts.
The re-seeded \"\" values alone would not evict a device-side draft
in either text field — `:reset-input-ids' is the S2 door for that
(jetpacs-shell.el:288)."
  (setq glasspane-search--filter-todo nil
        glasspane-search--filter-tags nil
        glasspane-search--filter-text ""
        glasspane-search--filter-priority nil
        glasspane-search--filter-due nil)
  (glasspane-search--run "")
  (let ((surface (or (plist-get params :surface)
                     (jetpacs-shell-surface-for "glasspane"))))
    (jetpacs-flow-continue
     (lambda ()
       (ignore-errors
         (jetpacs-shell-push surface
                             :reset-input-ids '("search-query"
                                                "search-filter-text"))))))
  'accepted)

(defun glasspane-search--on-by-tag (args params)
  "A tag chip tap: reset the builder to just `:tag', then run the same
query the builder would generate, so the search field shows a query
the user can retype or edit.  Emitted by the detail/reader/views tag
chips, which live on this owner's surface."
  (let ((tag (plist-get args :tag)))
    (if (not (and (stringp tag) (not (string-empty-p tag))))
        'rejected
      (setq glasspane-search--filter-todo nil
            glasspane-search--filter-tags (list tag)
            glasspane-search--filter-text ""
            glasspane-search--filter-priority nil
            glasspane-search--filter-due nil)
      (glasspane-search--run (glasspane-search--filter-query))
      (glasspane-search--push-screen params))))

;;;; Registration

(defconst glasspane-search--verbs
  '("search.open"
    "org.search.run"
    "search.update-filter"
    "search.clear-filters"
    "search.by-tag")
  "The verbs this file owns, for the register/unregister sweep.")

(defun glasspane-search-register ()
  "Register the search verbs.
Called from `glasspane-register', not at this file's load (the G0
gate contract).  Idempotent: re-registration replaces in place."
  (with-jetpacs-owner "glasspane"
    (jetpacs-defaction "search.open" #'glasspane-search--on-open
                       :doc "Open the search screen")
    (jetpacs-defaction "org.search.run" #'glasspane-search--on-run
                       :doc "Run a search query"
                       :args '((:name value :type "text")))
    (jetpacs-defaction "search.update-filter"
                       #'glasspane-search--on-update-filter)
    (jetpacs-defaction "search.clear-filters"
                       #'glasspane-search--on-clear-filters)
    (jetpacs-defaction "search.by-tag" #'glasspane-search--on-by-tag
                       :doc "Filter search to a single tag"
                       :args '((:name tag :type "text" :required t)))))

(defun glasspane-search-unregister ()
  "Drop the search verbs.
The filter/query defvars deliberately survive: persistence across
lifecycles is the feature, and the next register serves them as-is."
  (dolist (name glasspane-search--verbs)
    (jetpacs-undefaction name)))

(provide 'glasspane-search)
;;; glasspane-search.el ends here
