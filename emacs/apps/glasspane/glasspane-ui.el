;;; glasspane-ui.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:


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

(require 'glasspane-org-toolbar)

(require 'glasspane-org-reader)

(require 'jetpacs-files)

(require 'jetpacs-keymap)

(require 'jetpacs-magit)

(require 'jetpacs-settings)

;; Not used directly — pulled in so (require 'glasspane-ui) still assembles
;; the complete reference app for init-file users.
(require 'jetpacs-emacs-ui)

(require 'cl-lib)

(defcustom glasspane-org-custom-agendas nil
  "Alist of custom agenda views (Name . Query) for Jetpacs."
  :type '(alist :key-type string :value-type string)
  :group 'jetpacs)

(defvar glasspane-ui--last-widget 'unset
  "Widget views from the previous push, to suppress identical pushes.")

(add-hook 'jetpacs-shell-after-push-hook #'glasspane-ui--push-capture-tile)

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

(defun glasspane-ui--review-view (snackbar)
  (jetpacs-shell-tab-view "glasspane.review" (glasspane-ui--review-body)
                       :snackbar snackbar))

(defun glasspane-ui--settings-view (snackbar)
  (jetpacs-shell-nav-view "Settings" (glasspane-ui--settings-body)
                       :snackbar snackbar))

(jetpacs-shell-define-view "glasspane.review" :builder #'glasspane-ui--review-view
                        :tab '(:icon "rate_review" :label "Review") :order 25)

(jetpacs-shell-define-view "glasspane.settings" :builder #'glasspane-ui--settings-view
                        :order 80)

;; Glasspane is the first `jetpacs-defapp'. Zero visible change while it is
;; the only app; load a second app (jetpacs-hello.el) and the launcher home
;; appears with these views grouped as Glasspane's own.  Every view name
;; carries the "glasspane." namespace so a coexisting app (orgzly's
;; "orgzly.agenda", say) can never replace one of these in the registry.
(jetpacs-defapp "glasspane" :label "Glasspane" :icon "event"
             :views '("glasspane.agenda" "glasspane.journal" "glasspane.tasks"
                      "glasspane.clock" "glasspane.search" "glasspane.views"
                      "glasspane.srs" "glasspane.settings" "glasspane.detail"
                      "glasspane.gallery")
             :order 10)

;; Landing on any non-overlay view closes the detail drill-in.
(add-hook 'jetpacs-shell-view-switched-hook
          (lambda (_view) (setq glasspane-ui--detail-ref nil)))

;; Search from every tab's top bar.  (There used to be a second
;; filter_list icon here doing the same switch — one affordance per
;; destination.)  Owned by the app, so it rides only Glasspane's own
;; tabs.  Settings needs no registration either way: the stock drawer
;; entry resolves to "glasspane.settings" while this app is current
;; (`jetpacs-shell-resolve-view').
(with-jetpacs-owner "glasspane"
  (jetpacs-shell-add-top-action
   10 (lambda () (jetpacs-icon-button "search" (jetpacs-shell-switch-view "glasspane.search")
                                   :content-description "Search"))))

;; The org extractions are memoised; an explicit refresh (pull-to-refresh,
;; the drawer item, a queue drain) must drop them.
;; A pull-to-refresh recomputes everything: drop the whole org memo table
;; (no namespace arg — a refresh is an explicit "give me fresh state").
(add-hook 'jetpacs-shell-refresh-hook #'jetpacs-org-cache-invalidate)

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

(defvar glasspane-ui-detail-nodes-functions nil
  "Abnormal hook: functions from a detail REF to extra section nodes.
App layers (notes backlinks, SRS flashcards) contribute detail-view
sections here; each returns a node list or nil.  An erroring function
costs its own section, never the body.")

(defun glasspane-ui--at-ref (args fn &optional save)
  "Resolve ARGS to its heading and call FN with point there.
With SAVE non-nil, save the buffer afterwards (guarded against
triggering our own after-save refresh on top of the explicit push).
Returns non-nil on success; messages and returns nil on failure.

This is the app's ONE mutation funnel, deliberately NOT built on
`jetpacs-org-with-mutation': the core mutators defer saves to an idle
timer, which fires outside `glasspane-org--inhibit-save-refresh's
dynamic extent (double-firing the after-save refresh) and leaves the
file not-yet-on-disk for flows that read it back immediately
(share-sheet capture finalize, offline-queue replay).  The canonical
pieces it DOES stand on: `jetpacs-org-resolve-ref' and
`jetpacs-org-cache-invalidate'.  Save timing and the notify+repush
error UX are app policy and stay here."
  (condition-case err
      (let ((marker (jetpacs-org-resolve-ref args)))
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (funcall fn))
          (when save
            (let ((glasspane-org--inhibit-save-refresh t)
                  (save-silently t))
              (save-buffer))))
        (jetpacs-org-cache-invalidate 'glasspane)
        t)
    (error
     (message "Jetpacs: heading action failed: %s" (error-message-string err))
     (jetpacs-shell-notify "Couldn't find that heading — refreshing")
     (jetpacs-shell-push)
     nil)))

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
          (jetpacs-settings-save-variable 'org-tag-alist org-tag-alist)))
      (jetpacs-shell-notify "Settings saved")
      (jetpacs-shell-push))))

;; Org-derived views are memoised; per the cache contract every mutation
;; must drop the memo or the phone keeps rendering stale data.
(add-hook 'jetpacs-settings-after-set-hook
          (lambda (sym _value)
            (when (or (string-prefix-p "org-" (symbol-name sym))
                      (string-prefix-p "calendar-" (symbol-name sym)))
              (jetpacs-org-cache-invalidate 'glasspane))))

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
      (jetpacs-settings-save-variable 'glasspane-org-custom-agendas glasspane-org-custom-agendas)
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
        (jetpacs-settings-save-variable 'glasspane-org-custom-agendas glasspane-org-custom-agendas)
        (jetpacs-dismiss-dialog)
        (jetpacs-shell-notify "Saved custom agenda")
        (jetpacs-shell-push)))))

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
        (jetpacs-settings-save-variable 'glasspane-org-custom-agendas glasspane-org-custom-agendas)
        (jetpacs-shell-notify (format "Saved custom agenda: %s" name))
        (jetpacs-shell-push)))))

(jetpacs-defaction "agenda.today"
  ;; Reset the anchor (and any month-grid selection) back to today.
  (lambda (_ _)
    (jetpacs-ui-state-put "agenda-anchor" nil)
    (jetpacs-ui-state-put "agenda-selected-date" nil)
    (jetpacs-shell-push)))

(jetpacs-defaction "agenda.select-date"
  ;; `date' comes from the composed grid's per-cell args; `value' is what
  ;; the curated month_grid's on_day_tap injects. Same date either way.
  (lambda (args _)
    (let ((date (or (alist-get 'date args) (alist-get 'value args))))
      (when (and (stringp date)
                 (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date))
        (jetpacs-ui-state-put "agenda-selected-date" date)
        (jetpacs-shell-push)))))

(jetpacs-defaction "agenda.set-month"
  ;; The curated month grid navigates companion-locally (chevrons, swipe)
  ;; and reports the newly shown month via on_month_change; anchoring on
  ;; its 1st re-extracts that month and pushes fresh marks for it.
  (lambda (args _)
    (let ((month (alist-get 'value args)))
      (when (and (stringp month)
                 (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}\\'" month))
        (jetpacs-ui-state-put "agenda-anchor" (concat month "-01"))
        (jetpacs-shell-push)))))

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
                (glasspane-org--save-and-invalidate))
              (jetpacs-shell-push))
          (error
           (jetpacs-shell-notify
            (format "Toggle failed: %s" (error-message-string err)))))))))

;; ─── Babel ───────────────────────────────────────────────────────────────────

(defcustom glasspane-babel-timeout 30
  "Seconds before a phone-triggered babel execution is abandoned.
Best-effort: the timer can't interrupt a synchronous subprocess mid-call,
but it fires between process reads and stops a runaway block from
wedging the bridge forever."
  :type 'integer :group 'jetpacs)

(jetpacs-defaction "file.view"
  ;; Legacy (old cached UIs): now routes into the jetpacs-files editor.
  (lambda (args _)
    ;; `jetpacs-files-open' guards stringp + readability + within-root,
    ;; runs the open hook, and does the :switch-to "edit" push itself.
    (jetpacs-files-open (alist-get 'file args))))

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

(jetpacs-defaction "files.filter"
  ;; The sparse filter for the open org file: VALUE is the submitted
  ;; query ("" clears). State only — matching happens at render.
  (lambda (args _)
    (let ((value (alist-get 'value args)))
      (when (stringp value)
        (setq glasspane-ui--files-filter value)
        (jetpacs-shell-push nil :switch-to "edit")))))

(add-hook 'jetpacs-files-editor-body-functions #'glasspane-ui--org-editor-body)

(add-hook 'jetpacs-files-editor-actions-functions #'glasspane-ui--org-editor-actions)

;; Org files get the org formatting toolbar above the keyboard — composed
;; as data in the editor spec (glasspane-org-toolbar.el), so the renderer
;; stays app-agnostic and the companion ships no org Kotlin.
(setq jetpacs-files-editor-toolbar-function
      (lambda (file) (when (glasspane-ui--org-file-p file) (glasspane-org-toolbar))))

;; Org files open reader-first; everything else lands in the editor.
;; A fresh file starts unfiltered.
(add-hook 'jetpacs-files-open-hook
          (lambda (file)
            (setq glasspane-ui--files-read-mode (glasspane-ui--org-file-p file)
                  glasspane-ui--files-filter "")))

;; A phone-side save may have changed org data the views memoise.
(add-hook 'jetpacs-files-after-save-hook
          (lambda (_file) (jetpacs-org-cache-invalidate 'glasspane)))

(jetpacs-defaction "files.toggle-read"
  (lambda (_ _)
    (setq glasspane-ui--files-read-mode (not glasspane-ui--files-read-mode))
    (jetpacs-shell-push nil :switch-to "edit")))

(jetpacs-defaction "files.toggle-refile"
  (lambda (_ _)
    (setq glasspane-ui--files-refile-mode (not glasspane-ui--files-refile-mode))
    (jetpacs-shell-push nil :switch-to "edit")))

;; ─── Auto-refresh ────────────────────────────────────────────────────────────

(defvar glasspane-ui--save-refresh-timer nil)

(defcustom glasspane-ui-save-refresh-delay 2
  "Idle seconds after saving an agenda file before re-pushing the dashboard.
Debounces bursts of saves (e.g. `org-save-all-org-buffers') into one push."
  :type 'integer :group 'jetpacs)

(defun glasspane-ui--after-save-refresh ()
  "Schedule a dashboard refresh if an org agenda file was just saved.
No-op for saves Jetpacs itself performs — anything inside an action
handler (see `jetpacs-in-action-p') pushes explicitly, and other
programmatic saves bind `glasspane-org--inhibit-save-refresh' — which would
otherwise refresh twice or loop."
  (when (and (jetpacs-connected-p)
             (not (bound-and-true-p glasspane-org--inhibit-save-refresh))
             (not (jetpacs-in-action-p))
             buffer-file-name
             (derived-mode-p 'org-mode)
             (ignore-errors
               (member (expand-file-name buffer-file-name)
                       (mapcar #'expand-file-name (org-agenda-files)))))
    (jetpacs-org-cache-invalidate 'glasspane)
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
    (jetpacs-org-cache-invalidate 'glasspane)
    (jetpacs-shell-push)))

;; The connect and queue-drained pushes are owned by the shell; this app
;; only contributes its cache invalidation via `jetpacs-shell-refresh-hook'.

;; Clock state shows on the Clock tab and the dashboard generally —
;; keep it live. Depth 90: after jetpacs-surfaces' notification hooks.
(add-hook 'org-clock-in-hook  #'glasspane-ui--refresh-if-connected 90)

(add-hook 'org-clock-out-hook #'glasspane-ui--refresh-if-connected 90)

(provide 'glasspane-ui)

(provide 'glasspane-ui)
