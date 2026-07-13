;;; glasspane-search.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

(require 'glasspane-ui)

(defvar glasspane-ui--search-query ""
  "Last submitted query for the Search view.")

(defvar glasspane-ui--search-results nil
  "Cached heading items from the last search.")

(defvar glasspane-ui--search-error nil
  "Human-readable message when the last search query failed, else nil.")

(defun glasspane-ui--search-view (snackbar)
  (jetpacs-shell-nav-view "Search" (glasspane-ui--search-body)
                       :snackbar snackbar))

(jetpacs-shell-define-view "glasspane.search" :builder #'glasspane-ui--search-view
                        :order 70)

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
  (let* ((todo-val (or (car (jetpacs-ui-state-list "search-filter-todo")) "Any"))
         (tags-list (jetpacs-ui-state-list "search-filter-tags"))
         (text-val (or (jetpacs-ui-state "search-filter-text") ""))
         (prio-val (or (car (jetpacs-ui-state-list "search-filter-priority")) "Any"))
         (due-val (or (car (jetpacs-ui-state-list "search-filter-due")) "Any")))
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
  (let ((todo (car (jetpacs-ui-state-list "search-filter-todo")))
        (tags (jetpacs-ui-state-list "search-filter-tags"))
        (text (jetpacs-ui-state "search-filter-text"))
        (prio (car (jetpacs-ui-state-list "search-filter-priority")))
        (due (car (jetpacs-ui-state-list "search-filter-due")))
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
    (jetpacs-shell-push nil :switch-to "glasspane.search")))

(jetpacs-defaction "search.update-filter"
  ;; A builder filter changed: rebuild the org-ql query from the whole
  ;; filter state and run it immediately — the results and the query
  ;; text update together, no extra Search tap needed.
  (lambda (args _)
    (jetpacs-ui-state-put (concat "search-filter-" (alist-get 'field args))
                       (alist-get 'value args))
    (glasspane-ui--run-search (glasspane-ui--search-filter-query))
    (jetpacs-shell-push)))

(jetpacs-defaction "search.by-tag"
  ;; A tag chip tap: reset the builder to just that tag, then run the
  ;; same query the builder would generate, so the search field shows a
  ;; query the user can retype or edit.
  (lambda (args _)
    (jetpacs-ui-state-clear "search-filter-")
    (jetpacs-ui-state-put "search-filter-tags" (vector (alist-get 'tag args)))
    (glasspane-ui--run-search (glasspane-ui--search-filter-query))
    (jetpacs-shell-push nil :switch-to "glasspane.search")))

(provide 'glasspane-search)
