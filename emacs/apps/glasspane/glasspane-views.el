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
;; menu on the card — plain columns don't drag; a drag wire node is a
;; later decision, noted in the plan).

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
          (list (jetpacs-table-cell
                 (list (jetpacs-span (or (alist-get 'headline item) "")))
                 :on-tap tap)
                (jetpacs-table-cell
                 (list (jetpacs-span (or (alist-get 'todo item) ""))))
                (jetpacs-table-cell
                 (list (jetpacs-span (or (glasspane-ui--ts-date
                                       (alist-get 'scheduled item))
                                      ""))))
                (jetpacs-table-cell
                 (list (jetpacs-span (mapconcat #'identity
                                             (append (alist-get 'tags item) nil)
                                             " "))))))))
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
    (jetpacs-card
     (list
      (jetpacs-row
       (jetpacs-box (list (jetpacs-text (or (alist-get 'headline item) "") 'body))
                 :weight 1)
       (jetpacs-menu
        (mapcar (lambda (target)
                  (jetpacs-menu-item
                   (if (string-empty-p target) "No state" target)
                   (jetpacs-action "heading.todo-set"
                                :args (append ref `((state . ,target)))
                                :when-offline "queue")))
                (remove state columns))
        :icon "more_vert")))
     :on-tap (glasspane-views--tap item))))

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

(defun glasspane-views--calendar-nodes (items)
  "The agenda rendering: items grouped by scheduled date, ascending."
  (let ((buckets (make-hash-table :test 'equal)))
    (dolist (item items)
      (let ((date (or (glasspane-ui--ts-date (alist-get 'scheduled item))
                     "")))
        (puthash date (cons item (gethash date buckets)) buckets)))
    (let ((dates (sort (hash-table-keys buckets)
                       (lambda (a b)
                         ;; Unscheduled ("" sorts first) goes last.
                         (cond ((string-empty-p a) nil)
                               ((string-empty-p b) t)
                               (t (string< a b)))))))
      (cl-loop for date in dates
               append
               (cons (jetpacs-section-header
                      (if (string-empty-p date) "Unscheduled"
                        (glasspane-ui--format-date date "%a, %b %e")))
                     (mapcar (lambda (item)
                               (jetpacs-card
                                (list (jetpacs-text
                                       (format "%s%s"
                                               (if-let ((todo (alist-get 'todo item)))
                                                   (concat todo " ") "")
                                               (or (alist-get 'headline item) ""))
                                       'body))
                                :on-tap (glasspane-views--tap item)))
                             (nreverse (gethash date buckets))))))))

;; ─── The two screens (one shell view) ────────────────────────────────────────

(defun glasspane-views--rendering-chips (view)
  "The List | Board | Calendar switcher for VIEW."
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

(defun glasspane-views--open-view (view snackbar)
  "The screen for one saved VIEW."
  (let* ((items (condition-case err
                    (glasspane-views--items view)
                  (user-error (list 'error (error-message-string err)))))
         (broken (eq (car-safe items) 'error)))
    (jetpacs-shell-nav-view
     (alist-get 'name view)
     (apply #'jetpacs-lazy-column
            (append
             (list (glasspane-views--rendering-chips view)
                   (jetpacs-spacer :height 4))
             (cond
              (broken
               (list (jetpacs-text (cadr items) 'body)))
              ((null items)
               ;; %s: a hand-authored query may be a sexp, not a string.
               (list (jetpacs-empty-state :icon "manage_search"
                                       :title "No matches"
                                       :caption (format "%s"
                                                        (alist-get 'query view)))))
              (t (pcase (alist-get 'rendering view)
                   ("board" (list (glasspane-views--board-node items)))
                   ("calendar" (glasspane-views--calendar-nodes items))
                   (_ (list (glasspane-views--table-node items))))))))
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

(jetpacs-shell-define-view "glasspane.views" :builder #'glasspane-views--view :order 75)

;; Everyday nav: saved views are a daily destination, so they ride the
;; drawer (the contract: drawer = everyday nav, satellites = settings).
(with-jetpacs-owner "glasspane"
  (jetpacs-shell-add-drawer-item
   40 (lambda ()
        (jetpacs-drawer-item "manage_search" "Saved views"
                          (jetpacs-shell-switch-view "glasspane.views")))))

;; ─── Actions ─────────────────────────────────────────────────────────────────

(jetpacs-defaction "views.open"
  (lambda (args _)
    (let ((name (alist-get 'name args)))
      (when (glasspane-views--get name)
        (setq glasspane-views--current name)
        (jetpacs-shell-push nil :switch-to "glasspane.views"))))
  :doc "Open a saved view by name."
  :args '((:name name :type "text" :required t)))

(jetpacs-defaction "views.back"
  (lambda (_args _)
    (setq glasspane-views--current nil)
    (jetpacs-shell-push nil :switch-to "glasspane.views")))

(jetpacs-defaction "views.rendering"
  (lambda (args _)
    (let ((view (glasspane-views--get (alist-get 'name args)))
          (rendering (alist-get 'rendering args)))
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
  :args '((:name name :type "text" :required t)))

(provide 'glasspane-views)
;;; glasspane-views.el ends here
