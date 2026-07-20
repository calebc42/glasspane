;;; glasspane.el --- Glasspane Emacs client (Jetpacs Tier-1 app), single-file bundle -*- lexical-binding: t; -*-
;;
;; GENERATED FILE -- do not edit by hand.
;; Produced by emacs/build-bundle.el from the emacs/apps/ sources.
;; Concatenated in dependency order; each part keeps its own `provide',
;; and the bundle-internal `require' forms are commented out so the
;; file BYTE-COMPILES standalone: the foundation compiles an adopted
;; bundle before loading it, when none of these features exist yet —
;; a surviving hard require is a compile error and a broken .elc.
;;
;; Requires the Jetpacs core (jetpacs-core.el) on `load-path' first.
;;
;;; Code:

(require 'jetpacs-core)

;;; ==================================================================
;;; BEGIN apps/jetpacs-magit.el
;;; ==================================================================

;;; jetpacs-magit.el --- Curated Tier 1 magit pie menu -*- lexical-binding: t; -*-

;; The first curated Tier 1 radial menu: magit-status.  Four categories
;; fan out as a speed dial; each opens a pie of hand-labelled bindings.
;; Entries marked as prefixes (Commit, Push, Branch, …) are magit's
;; transient commands — running one activates the transient, and
;; `jetpacs-keymap--sync-pie' then pushes the live transient's own pie, so
;; the drill-in continues seamlessly into magit's real menus.
;;
;; This is pure data plus key dispatch: nothing here requires magit at
;; load time.  Keys are executed in the magit buffer through the same
;; allowlisted `jetpacs.keymap.run' action as everything else.

;;; Code:

(require 'jetpacs-keymap)

(defconst jetpacs-magit--menu
  '(("Stage" "add"
     ("s"   "Stage")
     ("u"   "Unstage")
     ("S"   "Stage all")
     ("U"   "Unstage all")
     ("k"   "Discard")
     ("g"   "Refresh"))
    ("Share" "sync"
     ("c"   "Commit" t)
     ("P"   "Push" t)
     ("F"   "Pull" t)
     ("f"   "Fetch" t)
     ("!"   "Run" t))
    ("Branch" "call_split"
     ("b"   "Branch" t)
     ("m"   "Merge" t)
     ("r"   "Rebase" t)
     ("z"   "Stash" t)
     ("t"   "Tag" t))
    ("Inspect" "history"
     ("l"   "Log" t)
     ("d"   "Diff" t)
     ("y"   "Refs" t)
     ("$"   "Process")))
  "Curated magit-status pie menu: (CATEGORY ICON (KEY LABEL [PREFIX-P])...).
PREFIX-P marks a transient prefix — the pie shows a ▸ and running it
drills into the live transient's own pie.")

(defun jetpacs-magit--binding-spec (entry buffer-name)
  "Build one pie binding spec from ENTRY (KEY LABEL [PREFIX-P])."
  (pcase-let ((`(,key ,label ,prefix-p) entry))
    (append
     `((key . ,key)
       (label . ,label)
       (action . ,(jetpacs-action "jetpacs.keymap.run"
                               :args `((buffer . ,buffer-name)
                                       (key . ,key))
                               :when-offline "drop")))
     (when prefix-p '((is_prefix . t))))))

(defun jetpacs-magit-pie-spec (buffer)
  "Curated Tier 1 pie-menu spec for magit BUFFER."
  (let ((buffer-name (buffer-name buffer)))
    `((center_label . "Magit")
      (buffer . ,buffer-name)
      (categories
       . ,(vconcat
           (mapcar
            (lambda (cat)
              (pcase-let ((`(,label ,icon . ,entries) cat))
                `((label . ,label)
                  (icon . ,icon)
                  (bindings . ,(vconcat
                                (mapcar (lambda (e)
                                          (jetpacs-magit--binding-spec e buffer-name))
                                        entries))))))
            jetpacs-magit--menu))))))

(jetpacs-keymap-register-tier1 'magit-status-mode #'jetpacs-magit-pie-spec)

(provide 'jetpacs-magit)
;;; jetpacs-magit.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-vulpea.el
;;; ==================================================================

;;; glasspane-vulpea.el --- Mobile-context vulpea extractor -*- lexical-binding: t; -*-

;; Indexes Tasker/Mobile context properties (LOCATION, WIFI_SSID,
;; BATTERY_LEVEL, ACTIVITY, BLUETOOTH_DEVICES) into a `glasspane_mobile'
;; plugin table riding the user's vulpea note index (vulpea 2.6 extractor
;; API).  Rows are keyed to the note id with a cascade foreign key, so
;; vulpea's own delete-then-reinsert file update and file removals clean
;; them — no delete hook.
;;
;; This file is the extractor's `:worker-lib': vulpea's extraction worker
;; `require's it to resolve the extract-fn in its own process, so loading
;; it must have no side effects — definitions only.  Registration (which
;; applies the plugin schema, DDL only the main process may run) happens
;; through `glasspane-vulpea-register', called where Glasspane detects
;; vulpea: the glasspane-org load tail and the packages light-up.

;;; Code:

(declare-function emacsql "emacsql" (connection sql &rest args))
(declare-function vulpea-db "vulpea-db" ())
(declare-function vulpea-db-register-extractor "vulpea-db-extract"
                  (extractor-or-name &optional fn))
(declare-function make-vulpea-extractor "vulpea-db-extract" (&rest slots))

(defun glasspane-vulpea--extract-mobile (_ctx note-data)
  "Index NOTE-DATA's mobile context properties into `glasspane_mobile'.
Runs per note, inside vulpea's file-update transaction, after the note
row is inserted — so the row it writes can hold a foreign key against
the note.  Props-only: never reads the AST, which keeps the extractor
worker-eligible.  Returns NOTE-DATA unchanged (side-effecting
extractor)."
  (let* ((props (plist-get note-data :properties))
         (id (plist-get note-data :id))
         (location (cdr (assoc "LOCATION" props)))
         (wifi (cdr (assoc "WIFI_SSID" props)))
         (battery (cdr (assoc "BATTERY_LEVEL" props)))
         (activity (cdr (assoc "ACTIVITY" props)))
         (bluetooth (cdr (assoc "BLUETOOTH_DEVICES" props))))
    (when (and id (or location wifi battery activity bluetooth))
      (emacsql (vulpea-db)
               [:insert :into glasspane-mobile :values $v1]
               (vector id location wifi
                       (and battery (string-to-number battery))
                       activity bluetooth)))
    note-data))

(defvar glasspane-vulpea--registered nil
  "Non-nil once the mobile extractor has been registered this session.")

(defun glasspane-vulpea-register ()
  "Register the mobile-context extractor with vulpea (idempotent).
Creates the plugin table via the extractor `:schema'; the cascade
foreign key keeps it consistent from then on.  A no-op when vulpea's
extractor registry isn't loaded — Glasspane never force-loads vulpea,
it only rides an index the user's own config (or the packages
light-up) brought up."
  (when (and (not glasspane-vulpea--registered)
             (fboundp 'vulpea-db-register-extractor))
    (vulpea-db-register-extractor
     (apply #'make-vulpea-extractor
            :name 'glasspane-mobile
            :version 1
            :priority 90
            :schema '((glasspane-mobile
                       [(note-id :not-null) location wifi battery activity bluetooth]
                       (:foreign-key [note-id] :references notes [id]
                        :on-delete :cascade)))
            :extract-fn #'glasspane-vulpea--extract-mobile
            ;; The declaration trio shipped together in vulpea 2.6's
            ;; extractor struct: explicit `:requires-ast nil' (default is
            ;; the `unset' sentinel) pins the props-only contract so
            ;; extraction never forces a full object parse, and
            ;; `:worker-safe'/`:worker-lib' keep it eligible for the
            ;; async worker.  Probed because pre-2.6 vulpea has none of
            ;; these slots — a cl-defstruct constructor signals on
            ;; unknown keywords (the exact load-crash this rewrite
            ;; fixes), and pre-2.6 always populates the AST and has no
            ;; worker, so omitting them there is correct, not degraded.
            (when (fboundp 'vulpea-extractor-requires-ast-p)
              '(:requires-ast nil :worker-safe t :worker-lib glasspane-vulpea))))
    (setq glasspane-vulpea--registered t)))

(provide 'glasspane-vulpea)
;;; glasspane-vulpea.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-org.el
;;; ==================================================================

;;; glasspane-org.el --- Jetpacs Org-Mode Data Extraction -*- lexical-binding: t; -*-

;; Provides functions to extract structured data from org-mode buffers.
;; This layer is pure Elisp and has no bridge dependencies.

;;; Code:

(require 'org)
(require 'org-agenda)
(require 'org-clock)
(require 'org-capture)
(require 'org-id)
(require 'cl-lib)
(require 'jetpacs-org)

;; ─── Refresh coordination ──────────────────────────────────────────────────────

(defvar glasspane-org--inhibit-save-refresh nil
  "When non-nil, the `after-save-hook' dashboard refresh is suppressed.
Bound around our own programmatic saves (heading edits, file saves) so an
explicit dashboard push isn't doubled by the save-hook firing on top.")

(declare-function vulpea-db-update-file "vulpea-db-extract")

(defun glasspane-org--vulpea-refresh-file (&optional buffer)
  "Synchronously re-index BUFFER's file in vulpea's db, when vulpea is up.
Vulpea's autosync applies saves on a short batch/idle timer, so a
mutation that immediately re-renders (todo swipe → push) would read
the stale row back out of the index.  No-op without vulpea."
  (when (fboundp 'vulpea-db-update-file)
    (when-let ((f (buffer-file-name (or buffer (current-buffer)))))
      (ignore-errors (vulpea-db-update-file f)))))

(defun glasspane-org--save-and-invalidate (&optional buffer)
  "Synchronously save BUFFER (default: current buffer); drop the org memo.
The shared tail of every mutation outside `glasspane-ui--at-ref' —
keep-the-funnel: the save happens NOW, never on an idle timer
\(`jetpacs-org-defer-save'), with the after-save dashboard refresh
suppressed so the caller's explicit repush isn't doubled."
  (with-current-buffer (or buffer (current-buffer))
    (let ((glasspane-org--inhibit-save-refresh t)
          (save-silently t))
      (save-buffer))
    (glasspane-org--vulpea-refresh-file))
  (jetpacs-org-cache-invalidate 'glasspane))

;; The dashboard pushes every view on every action (so navigation stays
;; instant and offline-capable), which means the expensive extractions here
;; — a full `org-agenda' run, an `org-map-entries' sweep — would execute on
;; every chip tap and snackbar.  They are memoised in the CORE's table
;; (`jetpacs-org-with-cache' under the `glasspane' namespace; keys carry
;; today's date + the agenda files' mtime, so date roll-over and external
;; edits bust automatically).  Every mutation path (heading actions, saves,
;; capture, queue replay) drops the namespace via
;; `jetpacs-org-cache-invalidate'.

;; ─── Heading references ────────────────────────────────────────────────────────
;;
;; Every heading the UI lists carries a `ref' — a small, JSON-safe alist that
;; lets a later action (drill-in, todo-set, schedule, clock-in) find the same
;; heading again.  Both halves are canonical core primitives now: build with
;; `jetpacs-org-heading-ref' while point is on the heading, ship it to the
;; device inside an action's `:args', and resolve it back to a live marker
;; with `jetpacs-org-resolve-ref'.

(defun glasspane-org--agenda-items (&optional span start-day)
  "Extract agenda items for SPAN (\\='day, \\='week, or \\='month).
START-DAY is an optional string (e.g. \"2026-11-01\") to start the agenda on.
Returns a list of alists representing agenda items.  Memoised; see
`jetpacs-org-cache-invalidate'."
  (jetpacs-org-with-cache 'glasspane (list 'agenda (or span 'day) start-day)
    (glasspane-org--agenda-items-1 span start-day)))

(defconst glasspane-org--agenda-buffer "*Jetpacs Agenda*"
  "Private buffer the agenda extraction builds into (and kills after).")

(defun glasspane-org--agenda-items-1 (span start-day)
  "Uncached worker for `glasspane-org--agenda-items'."
  (let ((org-agenda-span (or span 'day))
        (org-agenda-start-day start-day)
        (org-agenda-files (org-agenda-files))
        ;; Build into a private buffer so a user's open *Org Agenda* on the
        ;; desktop is never clobbered (and never killed) by an extraction.
        ;; `org-agenda-buffer-tmp-name' is the supported redirect: `org-agenda'
        ;; REBINDS `org-agenda-buffer-name' in its own let* and recomputes it,
        ;; so binding that variable directly gets shadowed — the build then
        ;; lands in *Org Agenda* while we look for (and fail to find, and fail
        ;; to kill) our own name.
        (org-agenda-buffer-tmp-name glasspane-org--agenda-buffer)
        (org-agenda-sticky nil)
        (inhibit-redisplay t)
        items)
    (unwind-protect
        (save-window-excursion
          (let ((org-agenda-window-setup 'current-window))
            (org-agenda nil "a")
            (with-current-buffer glasspane-org--agenda-buffer
          (goto-char (point-min))
          (while (not (eobp))
            (let* ((marker (get-text-property (point) 'org-marker))
                   (tags (get-text-property (point) 'tags))
                   (time (get-text-property (point) 'time))
                   (type (get-text-property (point) 'type))
                   ;; The agenda's own qualifier ("Sched. 3x: ", "In 3 d.: ")
                   ;; and the item's own date as an absolute day number —
                   ;; ts-date < (org-today) is the overdue test.
                   (extra (get-text-property (point) 'extra))
                   (ts-date (get-text-property (point) 'ts-date))
                   (date-abs (get-text-property (point) 'date))
                   ;; org ≥9.6 stores the gregorian (MONTH DAY YEAR) list
                   ;; directly; older code stored the absolute day number.
                   ;; Feeding the list to calendar-gregorian-from-absolute
                   ;; signals, which emptied the whole agenda.
                   (date-list (cond ((consp date-abs) date-abs)
                                    ((numberp date-abs)
                                     (calendar-gregorian-from-absolute date-abs))))
                   (date-str (when date-list (format "%04d-%02d-%02d" (nth 2 date-list) (nth 0 date-list) (nth 1 date-list)))))
              (when marker
                (with-current-buffer (marker-buffer marker)
                  (save-excursion
                    (goto-char marker)
                    (let* ((components (org-heading-components))
                           (todo (nth 2 components))
                           (priority (nth 3 components))
                           (headline (nth 4 components)))
                      (push `((headline . ,headline)
                              (todo . ,todo)
                              (priority . ,(if priority (char-to-string priority) nil))
                              (tags . ,(vconcat tags))
                              (file . ,(buffer-file-name))
                              (pos . ,(marker-position marker))
                              (time . ,time)
                              (date . ,date-str)
                              (type . ,(when type (format "%s" type)))
                              (extra . ,extra)
                              (ts-date . ,ts-date)
                              (ref . ,(jetpacs-org-heading-ref)))
                            items))))))
            (forward-line 1)))))
      ;; Kill by buffer object, not name, and even when extraction errored.
      (when-let ((buf (get-buffer glasspane-org--agenda-buffer)))
        (kill-buffer buf)))
    (nreverse items)))

(defun glasspane-org--priority-string (p)
  "Normalize priority P to its display letter, or nil.
Vulpea stores org-element's raw :priority — the char code (65 for A) —
and SQLite may hand it back as that integer or its decimal string;
org-map-entries paths already carry the letter."
  (cond ((null p) nil)
        ((integerp p) (char-to-string p))
        ((and (stringp p) (string-match-p "\\`[0-9]+\\'" p))
         (char-to-string (string-to-number p)))
        ((stringp p) p)))

(defun glasspane-org--vulpea-note-to-item (note)
  "Convert a `vulpea-note' to a Glasspane item alist."
  (let ((id (vulpea-note-id note))
        (path (vulpea-note-path note))
        (title (vulpea-note-title note))
        (pos (vulpea-note-pos note)))
    `((headline . ,title)
      (todo . ,(vulpea-note-todo note))
      (priority . ,(glasspane-org--priority-string (vulpea-note-priority note)))
      (tags . ,(vconcat (vulpea-note-tags note)))
      (scheduled . ,(vulpea-note-scheduled note))
      (deadline  . ,(vulpea-note-deadline note))
      (level . ,(vulpea-note-level note))
      (file . ,path)
      (pos . ,pos)
      (ref . ,(delq nil
                    (list (when (and id (stringp id) (not (string-empty-p id))) `(id . ,id))
                          (when path `(file . ,path))
                          (when pos `(pos . ,pos))
                          (when title `(headline . ,title))))))))

(defun glasspane-org--vulpea-p ()
  "Non-nil when the user has already loaded vulpea.
App policy: never force-load — `jetpacs-org-vulpea-available-p' would
`require' vulpea; Glasspane only rides an index the user's own config
brought up."
  (and (featurep 'vulpea) (fboundp 'vulpea-db-query)))

(defun glasspane-org--todo-items (&optional files)
  "Extract TODO items from FILES (or agenda files).
Memoised; see `jetpacs-org-cache-invalidate'."
  (jetpacs-org-with-cache 'glasspane (list 'todos files)
    (if (and (glasspane-org--vulpea-p) (null files))
        (mapcar #'glasspane-org--vulpea-note-to-item
                (vulpea-db-query (lambda (note) (vulpea-note-todo note))))
      (glasspane-org--todo-items-1 files))))

(defun glasspane-org--todo-items-1 (files)
  "Uncached worker for `glasspane-org--todo-items'."
  (let (items)
    (org-map-entries
     (lambda ()
       (let* ((components (org-heading-components))
              (todo (nth 2 components))
              (priority (nth 3 components))
              (headline (nth 4 components))
              (tags (org-get-tags))
              (scheduled (org-entry-get (point) "SCHEDULED"))
              (deadline  (org-entry-get (point) "DEADLINE")))
         (when todo
           (push `((headline . ,headline)
                   (todo . ,todo)
                   (priority . ,(if priority (char-to-string priority) nil))
                   (tags . ,(vconcat tags))
                   (scheduled . ,scheduled)
                   (deadline  . ,deadline)
                   (level . ,(nth 0 components))
                   (file . ,(buffer-file-name))
                   (pos . ,(point))
                   (ref . ,(jetpacs-org-heading-ref)))
                 items))))
     "TODO<>\"\"" (or files 'agenda))
    (nreverse items)))

(defun glasspane-org--heading-item-at ()
  "Build a heading item alist for the org entry at point.
Same shape as `glasspane-org--todo-items' entries (headline/todo/priority/
tags/file/pos/ref); used by the search layer."
  (let* ((components (org-heading-components))
         (todo (nth 2 components))
         (priority (nth 3 components))
         (headline (nth 4 components))
         (tags (org-get-tags))
         (scheduled (org-entry-get (point) "SCHEDULED"))
         (deadline  (org-entry-get (point) "DEADLINE")))
    `((headline . ,headline)
      (todo . ,todo)
      (priority . ,(if priority (char-to-string priority) nil))
      (tags . ,(vconcat tags))
      (scheduled . ,scheduled)
      (deadline  . ,deadline)
      (level . ,(nth 0 components))
      (file . ,(buffer-file-name))
      (pos . ,(point))
      (ref . ,(jetpacs-org-heading-ref)))))

(defun glasspane-org--file-heading-items (file)
  "Extract level-1 headings from FILE as item alists.
Same shape as `glasspane-org--todo-items' entries (plus scheduled/deadline),
suitable for `glasspane-ui--agenda-card'."
  (when (and file (file-readable-p file))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (let (items)
         (org-map-entries
          (lambda ()
            (let* ((components (org-heading-components))
                   (level (nth 0 components))
                   (todo (nth 2 components))
                   (priority (nth 3 components))
                   (headline (nth 4 components))
                   (tags (org-get-tags))
                   (scheduled (org-entry-get (point) "SCHEDULED"))
                   (deadline  (org-entry-get (point) "DEADLINE")))
              (when (= level 1)
                (push `((headline . ,headline)
                        (todo . ,todo)
                        (priority . ,(if priority (char-to-string priority) nil))
                        (tags . ,(vconcat tags))
                        (scheduled . ,scheduled)
                        (deadline  . ,deadline)
                        (file . ,(buffer-file-name))
                        (pos . ,(point))
                        (ref . ,(jetpacs-org-heading-ref)))
                      items))))
          nil nil)
         (nreverse items))))))

;; Search queries pass through the canonical parser (`jetpacs-org-parse-query')
;; into an org-ql-shaped sexp, whichever of the three input shapes the user
;; typed.  Matching is the core's ONE grammar — `jetpacs-org-entry-matches-p'
;; at a buffer point, `jetpacs-org-note-matches-p' over a `vulpea-note' —
;; with org-ql taking over when installed.  Malformed queries signal
;; `user-error' so the UI can show the problem — an empty result must mean
;; "nothing matched", never "the query didn't parse".

(defun glasspane-org--vulpea-query (tree)
  "Run parsed query sexp TREE over the whole Vulpea database.
Matching runs entirely off the index via the canonical
`jetpacs-org-note-matches-p'.  Callers route TREE here only when
`jetpacs-org-note-query-supported-p' approves it; an unsupported term
slipping through signals `user-error'."
  (let ((notes (vulpea-db-query (lambda (note) (jetpacs-org-note-matches-p tree note)))))
    (mapcar #'glasspane-org--vulpea-note-to-item notes)))

(defun glasspane-org--query (tree)
  "Run parsed query sexp TREE over the org data; heading items.
The engine behind search and every saved/derived view.  Scope rule:
when the user has vulpea loaded and TREE stays inside
`jetpacs-org-note-query-terms', the note index answers from the WHOLE
vault (no file visit); terms the index can't evaluate (ts, closed,
clocked, path, ...) route to `jetpacs-org-query' — org-ql or the
built-in interpreter — over `org-agenda-files' only.  Signals
`user-error' on terms neither engine knows.  Memoised; see
`jetpacs-org-cache-invalidate'."
  (when tree
    (if (and (glasspane-org--vulpea-p)
             (jetpacs-org-note-query-supported-p tree))
        ;; `jetpacs-org-query' caches internally; only the vulpea arm
        ;; needs its own memo.
        (jetpacs-org-with-cache 'glasspane (list 'query (format "%S" tree))
          (glasspane-org--vulpea-query tree))
      (jetpacs-org-query 'glasspane tree #'glasspane-org--heading-item-at))))

(defun glasspane-org--search (query)
  "Search the org data for QUERY; return a list of heading items.
QUERY may be an org-ql sexp, filter tokens, or free text — see
`jetpacs-org-parse-query'.  Scope follows `glasspane-org--query':
whole vault off the note index when vulpea has it, agenda files
otherwise.  Signals `user-error' on queries that don't parse or use
terms no engine supports, so callers can surface the problem."
  (glasspane-org--query (jetpacs-org-parse-query query)))

(defun glasspane-org--filter-items (items query)
  "ITEMS whose headings match QUERY — the sparse filter.
QUERY takes the standard search syntax; matching runs the built-in
matcher at each item's own heading, so it works on any file, agenda
or not.  Signals `user-error' on queries that don't parse or use
unsupported terms."
  (let ((tree (jetpacs-org-parse-query query)))
    (if (null tree)
        items
      (cl-remove-if-not
       (lambda (item)
         (let ((file (alist-get 'file item))
               (pos (alist-get 'pos item)))
           (and file pos
                (with-current-buffer (find-file-noselect file)
                  (org-with-wide-buffer
                   (goto-char (min pos (point-max)))
                   (unless (org-at-heading-p)
                     (ignore-errors (org-back-to-heading t)))
                   (jetpacs-org-entry-matches-p tree))))))
       items))))

(defun glasspane-org--all-tags ()
  "Sorted tags for the query builder.
Combines `org-tag-alist' (the configured vocabulary) with every tag
actually used in the agenda files.  Memoised; see
`jetpacs-org-cache-invalidate'."
  (jetpacs-org-with-cache 'glasspane (list 'all-tags)
    (let ((tags nil))
      (dolist (entry org-tag-alist)
        (let ((tg (if (consp entry) (car entry) entry)))
          (when (stringp tg) (push tg tags))))
      (if (and (featurep 'vulpea) (fboundp 'vulpea-db-query-tags))
          (dolist (tg (vulpea-db-query-tags))
            (push tg tags))
        (dolist (entry (org-global-tags-completion-table))
          (when (stringp (car entry)) (push (car entry) tags))))
      (sort (delete-dups tags) #'string-lessp))))

(defun glasspane-org--file-list ()
  "List of agenda files and basic stats."
  (mapcar (lambda (f) 
            `((file . ,f)
              (name . ,(file-name-nondirectory f))))
          (org-agenda-files)))

(defun glasspane-org--heading-at (pos file)
  "Get full heading detail at POS in FILE."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char pos)
      (let* ((components (org-heading-components))
             (todo (nth 2 components))
             (priority (nth 3 components))
             (headline (nth 4 components))
             (tags (org-get-tags))
             (props (org-entry-properties))
             ;; Basic body extraction:
             (end (save-excursion (org-end-of-subtree t t)))
             (body-start (save-excursion (forward-line 1) (point)))
             (body (if (< body-start end)
                       (buffer-substring-no-properties body-start end)
                     "")))
        `((headline . ,headline)
          (todo . ,todo)
          (priority . ,(if priority (char-to-string priority) nil))
          (tags . ,(vconcat tags))
          (properties . ,props)
          (body . ,body))))))

(defun glasspane-org--parse-template-prompts (template-string)
  "Return the ordered field names to collect for TEMPLATE-STRING.
Each `%^{NAME}' or `%^{NAME|default}' contributes NAME (the default is
dropped from the label but honoured at fill time). A `%?' body position
adds a leading \"Headline\" field. Duplicates are removed."
  (let (prompts (start 0))
    (while (string-match "%\\^{\\([^}]+\\)}" template-string start)
      ;; Capture the match BEFORE `split-string' runs — it calls `string-match'
      ;; internally and would clobber the match data, leaving `match-end' wrong
      ;; and the loop spinning forever.
      (let ((spec (match-string 1 template-string))
            (end (match-end 0)))
        (push (string-trim (car (split-string spec "|"))) prompts)
        (setq start end)))
    (setq prompts (nreverse prompts))
    (delete-dups
     (if (string-match-p "%\\?" template-string)
         (cons "Headline" prompts)
       prompts))))

(defun glasspane-org--capture-templates ()
  "Return list of capture templates."
  (mapcar (lambda (tmpl)
            (let ((key (nth 0 tmpl))
                  (desc (nth 1 tmpl))
                  (template-string (nth 4 tmpl)))
              `((key . ,key)
                (description . ,desc)
                (prompts . ,(vconcat (glasspane-org--parse-template-prompts 
                                      (if (stringp template-string) template-string "")))))))
          org-capture-templates))

(defun glasspane-org--fill-template (tmpl values)
  "Fill org capture TMPL string from VALUES (NAME -> user input alist).
`%?' becomes the Headline value; each `%^{NAME|default}' becomes the user
value for NAME, else its default, else empty. Any *other* interactive
escape that survives (`%^{…}' with no value, `%^t', `%^g', …) is then
stripped, so `org-capture' can never block on a minibuffer prompt — which
on the phone would hang behind the bridge."
  (let ((headline (or (cdr (assoc "Headline" values)) "")))
    ;; %? — free-form body position.
    (setq tmpl (replace-regexp-in-string "%\\?" headline tmpl t t))
    ;; %^{NAME|default} — scan the template's own tokens so NAME always
    ;; matches what `glasspane-org--parse-template-prompts' produced.
    (setq tmpl (replace-regexp-in-string
                "%\\^{\\([^}]*\\)}"
                (lambda (m)
                  ;; M is the whole "%^{ … }" match; parse it directly rather
                  ;; than via match-data (unreliable inside this callback).
                  (let* ((spec (substring m 3 -1))
                         (bar (string-search "|" spec))
                         (name (string-trim (if bar (substring spec 0 bar) spec)))
                         (default (and bar (substring spec (1+ bar))))
                         (val (cdr (assoc name values))))
                    (cond ((and (stringp val) (not (string-empty-p val))) val)
                          ((stringp default) default)
                          (t ""))))
                tmpl t t))
    ;; Neutralise any remaining caret (interactive) escapes; leave plain
    ;; ones like %U %t %i %a for org to expand non-interactively.
    (replace-regexp-in-string "%\\^.?" "" tmpl t t)))

(defun glasspane-org--do-capture (template-key values &optional extra-body)
  "Run capture for TEMPLATE-KEY with VALUES alist (NAME -> user input).
EXTRA-BODY, when non-empty, is appended below the filled template —
the carrier for text shared from another app via the share sheet."
  (let ((entry (assoc template-key org-capture-templates)))
    (when entry
      (let* ((tmpl (nth 4 entry))
             (filled (if (stringp tmpl)
                         (glasspane-org--fill-template tmpl values)
                       tmpl))
             (filled (if (and (stringp filled)
                              (stringp extra-body)
                              (not (string-empty-p (string-trim extra-body))))
                         (concat filled "\n" (string-trim extra-body))
                       filled))
             ;; Shallow-copy the entry, swap in the filled template, and force
             ;; :immediate-finish so the capture buffer never waits for the
             ;; C-c C-c a phone user can't press.
             (new-entry (copy-sequence entry)))
        (setcar (nthcdr 4 new-entry) filled)
        (setcdr (nthcdr 4 new-entry)
                (append (nthcdr 5 new-entry) '(:immediate-finish t)))
        ;; `org-capture-entry' short-circuits template selection inside
        ;; `org-capture', so binding it to the FILLED copy is what makes the
        ;; pre-filled template the one that actually runs.  (Binding it to
        ;; the original — as this code once did — re-ran the raw %^{...}
        ;; prompts and double-asked the user through the bridge.)
        (let ((org-capture-entry new-entry))
          ;; Safety net: a fully pre-filled template shouldn't prompt at all,
          ;; but if any escape slips through, never let `org-capture' block
          ;; Emacs forever on a minibuffer the phone can't answer. `with-timeout'
          ;; fires even while a synchronous read is waiting.
          (with-timeout (30 (message "jetpacs: capture timed out (a prompt was left unanswered)"))
            (org-capture)))))))

(defun glasspane-org--item-hm (time)
  "Normalize an agenda item's raw `time' property to \"HH:MM\", or nil.
The property comes straight from the agenda's time grid and looks like
\" 9:15......\" or \"14:00-15:00\" — leading space, no zero padding,
grid filler dots."
  (when (stringp time)
    (let ((s (string-trim time)))
      (when (string-match "\\`\\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)" s)
        (format "%02d:%s"
                (string-to-number (match-string 1 s))
                (match-string 2 s))))))

(defun glasspane-org--upcoming-reminders (&optional horizon-hours)
  "Timed agenda items within HORIZON-HOURS (default 24) as reminder specs.
Only items with a clock time qualify (a date alone isn't an alarm).
Each spec is ((id . STR) (at_ms . MS) (title . STR) (body . STR)),
ready for the companion's `reminders.set' frame."
  (let* ((horizon (* (or horizon-hours 24) 3600))
         (now (float-time))
         (items (append (glasspane-org--agenda-items 'day nil)
                        (glasspane-org--agenda-items
                         'day (format-time-string "%Y-%m-%d"
                                                  (time-add nil 86400)))))
         reminders)
    (dolist (it items)
      (let ((date (alist-get 'date it))
            (hm (glasspane-org--item-hm (alist-get 'time it)))
            (headline (alist-get 'headline it))
            (type (alist-get 'type it)))
        (when (and (stringp date) hm)
          (let ((at (float-time (org-time-string-to-time
                                 (concat date " " hm)))))
            (when (and (> at now) (< (- at now) horizon))
              (push `((id . ,(format "%s/%s" date (or headline "?")))
                      (at_ms . ,(truncate (* at 1000)))
                      (title . ,(or headline "Org reminder"))
                      (body . ,(concat hm (when (stringp type)
                                            (concat " · " type)))))
                    reminders))))))
    (nreverse reminders)))

(defun glasspane-org--clock-status ()
  "Current clock status."
  (when (org-clock-is-active)
    `((task . ,org-clock-current-task)
      (start . ,(float-time org-clock-start-time))
      (file . ,(buffer-file-name (marker-buffer org-clock-marker)))
      (pos . ,(marker-position org-clock-marker)))))

(defun glasspane-org--recent-clocks (n)
  "Last N clocked tasks."
  (let (items)
    (dolist (m org-clock-history)
      (when (and m (marker-buffer m))
        (with-current-buffer (marker-buffer m)
          (save-excursion
            (goto-char m)
            (let* ((components (org-heading-components))
                   (headline (nth 4 components)))
              (push `((headline . ,headline)
                      (file . ,(buffer-file-name))
                      (pos . ,(marker-position m))
                      (ref . ,(jetpacs-org-heading-ref)))
                    items))))))
    (cl-subseq (nreverse items) 0 (min n (length items)))))

;; ─── Automated Timestamps ───────────────────────────────────────────────────

(defun glasspane-org--timestamp-string ()
  "Return the current time formatted as an inactive Org timestamp."
  (format-time-string "[%Y-%m-%d %a %H:%M]"))

(defun glasspane-org--before-save-timestamps ()
  "Update #+MODIFIED and ensure #+CREATED at the file level on save."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        ;; Update #+MODIFIED if present
        (when (re-search-forward "^[ \t]*#\\+MODIFIED:[ \t]*\\(.*\\)$" nil t)
          (replace-match (glasspane-org--timestamp-string) t t nil 1))
        
        (goto-char (point-min))
        ;; Add #+CREATED to titled note files only.  Inserting front
        ;; matter into a plain org buffer (agenda file, table, config)
        ;; grows it at the top and invalidates the buffer positions any
        ;; in-flight position-based action was rendered with, so gate on
        ;; a #+TITLE — the marker of a note document.
        (when (and (not (re-search-forward "^[ \t]*#\\+CREATED:" nil t))
                   (progn (goto-char (point-min))
                          (re-search-forward "^[ \t]*#\\+TITLE:.*$" nil t)))
          (forward-line 1)
          (insert (format "#+CREATED: %s\n" (glasspane-org--timestamp-string))))))))

(add-hook 'before-save-hook #'glasspane-org--before-save-timestamps)

(defun glasspane-org--heading-created-property ()
  "Add a :CREATED: property to new headings."
  (org-set-property "CREATED" (glasspane-org--timestamp-string)))

(add-hook 'org-insert-heading-hook #'glasspane-org--heading-created-property)

(defun glasspane-org--heading-modified-property (property &rest _)
  "Update :MODIFIED: property when any other property changes."
  (when (and (stringp property)
             (not (equal property "MODIFIED"))
             (not (equal property "CREATED")))
    (let ((org-property-changed-functions nil))
      (org-set-property "MODIFIED" (glasspane-org--timestamp-string)))))

(add-hook 'org-property-changed-functions #'glasspane-org--heading-modified-property)

(add-hook 'org-after-todo-state-change-hook
          (lambda ()
            (let ((org-property-changed-functions nil))
              (org-set-property "MODIFIED" (glasspane-org--timestamp-string)))))

(declare-function glasspane-vulpea-register "glasspane-vulpea" ())

(when (featurep 'vulpea)
  (when (require 'glasspane-vulpea nil t)
    (glasspane-vulpea-register)))

(provide 'glasspane-org)
;;; glasspane-org.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-source.el
;;; ==================================================================

;;; glasspane-source.el --- Glasspane org data as a jetpacs binding source -*- lexical-binding: t; -*-

;; The data half of Glasspane's declarative (`:spec') views: a jetpacs
;; `jetpacs-defsource' named "glasspane.org" that wraps the app's org query
;; engine — `glasspane-org--query' over `jetpacs-org-parse-query', i.e.
;; whichever of vulpea / org-ql / the built-in interpreter is live — and
;; NORMALIZES each result item to core's domain-neutral field contract before
;; core sees it.  This is the "a source normalizes engine data" half of the
;; binding layer (see the submodule's docs/BINDING.md): the query engine and
;; its memo stay app-side; the canonicalizer adapts their output.
;;
;; Why a canonicalizer.  A raw Glasspane item alist carries engine-native
;; shapes the `:spec' transforms don't understand:
;;   - `scheduled'/`deadline' are RAW org timestamp strings ("<2026-07-13 Mon
;;     09:00>"); the `date'/`date-label' transforms want an ISO "YYYY-MM-DD".
;;   - `tags' is a VECTOR; the `tags-list'/`count' transforms want a list.
;;   - `priority' is a char in the vulpea path; a "text" field wants a string.
;; `glasspane-source--canonicalize' maps each item to those canonical types,
;; and `:fields' declares them so a `:spec' template can bind them.  `ref' is
;; an opaque locator (an alist as built by `jetpacs-org-heading-ref') and is
;; passed through intact for an action's `:args'.
;;
;; Why UNCACHED.  `glasspane-org--query' is itself memoised, and its memo is
;; the one seam every mutation path already busts via
;; `jetpacs-org-cache-invalidate' — including in-buffer edits that have not
;; yet reached disk.  A source-level `:cache-key' keyed on file mtime (the only
;; freshness signal a nullary token could cheaply read) would serve stale rows
;; after exactly those edits.  Re-canonicalising the already-memoised query
;; result on each push is cheap (a `mapcar' over a bounded item list) and
;; always fresh, so we lean on the engine's own correctly-invalidated cache
;; rather than add a second one that is harder to keep honest.

;;; Code:

(require 'jetpacs-source)
(require 'jetpacs-surfaces)
;; (require 'glasspane-org) — bundle-internal, provided above

(defun glasspane-source--iso-date (ts)
  "The \"YYYY-MM-DD\" date inside org timestamp string TS, or nil.
Mirrors the agenda's presentation helper `glasspane-ui--ts-date'; kept
local so the data layer does not `require' a view module."
  (when (and (stringp ts)
             (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" ts))
    (match-string 1 ts)))

(defun glasspane-source--string (v)
  "Coerce V to a string, or nil when V is nil.
Leaves an absent field nil (so its template placeholder drops cleanly)."
  (and v (if (stringp v) v (format "%s" v))))

(defun glasspane-source--priority (v)
  "Coerce a priority V to its letter string (\"A\"), or nil.
The org path already hands us a string, but the vulpea path passes the
priority verbatim, where it may be a character code (?A); `format' would
turn that into \"65\", so decode a character with `char-to-string'."
  (cond ((null v) nil)
        ((stringp v) v)
        ((characterp v) (char-to-string v))
        (t (format "%s" v))))

(defun glasspane-source--canonicalize (item)
  "Map raw Glasspane org ITEM alist to the \"glasspane.org\" canonical fields.
Returns a fresh symbol-keyed alist; see this file's commentary for the
per-field normalization contract."
  (list (cons 'headline  (glasspane-source--string (alist-get 'headline item)))
        (cons 'todo      (glasspane-source--string (alist-get 'todo item)))
        (cons 'scheduled (glasspane-source--iso-date (alist-get 'scheduled item)))
        (cons 'deadline  (glasspane-source--iso-date (alist-get 'deadline item)))
        (cons 'tags      (append (alist-get 'tags item) nil))   ; vector -> list
        (cons 'priority  (glasspane-source--priority (alist-get 'priority item)))
        (cons 'ref       (alist-get 'ref item))))               ; opaque locator

(defun glasspane-source--org-query (params)
  "The \"glasspane.org\" `:query' thunk: PARAMS -> canonical item list.
PARAMS is the canonical params alist; its `query' is a search string in
any shape `jetpacs-org-parse-query' accepts.  An empty/nil query yields
no items (never an error)."
  (mapcar #'glasspane-source--canonicalize
          (glasspane-org--query
           (jetpacs-org-parse-query (alist-get 'query params)))))

(with-jetpacs-owner "glasspane"
  (jetpacs-defsource "glasspane.org"
    :params '((:name query :type "text" :required t))
    :fields '((:name "headline"  :type "text")
              (:name "todo"      :type "text")
              (:name "scheduled" :type "date")
              (:name "deadline"  :type "date")
              (:name "tags"      :type "string-list")
              (:name "priority"  :type "text")
              (:name "ref"       :type "ref"))
    :query #'glasspane-source--org-query))

(provide 'glasspane-source)
;;; glasspane-source.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-org-rich.el
;;; ==================================================================

;;; glasspane-org-rich.el --- Org → rich-text SDUI emitter -*- lexical-binding: t; -*-

;; Turns org content into Jetpacs `rich_text' nodes (styled span runs) instead of
;; the syntax-highlighted monospace `jetpacs-markup' produces. Emacs does the
;; parsing via `org-element', so the device never re-parses org — it only paints
;; the spans. Inline emphasis (bold/italic/underline/strike/code/verbatim),
;; links (tappable), timestamps, and #hashtags all map to native styling.
;;
;; Block-level content that doesn't fit a single styled paragraph — source
;; blocks, example blocks — falls back to `jetpacs-markup' so code keeps its
;; highlighted, fixed-width look.  Org tables render as native `table' grids
;; (tap-to-edit, long-press row/column menu, and add-row/add-column when
;; file context is supplied); table.el tables keep the markup fallback.
;; Babel #+RESULTS content renders read-only inside a foldable section —
;; execution regenerates it, so hand edits would be silently lost.
;;
;; Entry point: `glasspane-org-rich-body' (an org body string -> a list of nodes).

;;; Code:

(require 'org)
(require 'org-element)
(require 'org-table)
(require 'cl-lib)
(require 'jetpacs-widgets)

;; ─── Dynamic context for interactive elements ───────────────────────────────

(defvar glasspane-org-rich--file nil
  "File path being rendered; enables interactive checkboxes when non-nil.")

(defvar glasspane-org-rich--body-offset nil
  "Offset mapping temp-buffer positions to real-file positions.
real-pos = offset + temp-pos.  Set by `glasspane-org-rich-body' when
FILE and OFFSET are supplied.")

(defvar glasspane-org-rich--skip-drawers nil
  "Drawer names (upcased) the current render should omit.
Bound by callers that present a drawer's content in their own way —
the heading detail view parses LOGBOOK into a structured section, so
rendering the raw drawer too would double it.")

(defvar glasspane-org-rich--read-only nil
  "Non-nil while rendering babel #+RESULTS content.
Suppresses edit affordances (table cell taps, row/column menus,
checkbox toggles) — execution regenerates results, so a hand edit
would be silently overwritten by the next run.")

;; ─── Inline spans ────────────────────────────────────────────────────────────

(defun glasspane-org-rich--flag (style key)
  "Return STYLE (a plist of emphasis flags) with KEY turned on.
Prepended so `plist-get' sees the new value first; STYLE is never mutated."
  (cons key (cons t style)))

(defun glasspane-org-rich--leaf (text style)
  "Build a span for TEXT carrying the emphasis flags set in STYLE."
  (apply #'jetpacs-span (or text "")
         (append (when (plist-get style :bold)      '(:bold t))
                 (when (plist-get style :italic)    '(:italic t))
                 (when (plist-get style :underline) '(:underline t))
                 (when (plist-get style :strike)    '(:strike t))
                 (when (plist-get style :code)      '(:code t))
                 (when (plist-get style :tag)       '(:tag t))
                 (when (plist-get style :baseline)
                   (list :baseline (plist-get style :baseline))))))

(defconst glasspane-org-rich--image-re
  "\\.\\(png\\|jpe?g\\|gif\\|webp\\|bmp\\|svg\\)\\'"
  "Matches link targets that should render as inline images.")

(defun glasspane-org-rich--image-url (type target)
  "Return a renderable URL for a link of TYPE to TARGET if it's an image.
http(s) image URLs pass through; local file/attachment paths become
file:// URIs the companion can try to load. Returns nil for non-images."
  (when (and (stringp target)
             (string-match-p glasspane-org-rich--image-re (downcase target)))
    (let ((ty (and type (downcase type))))
      (cond
       ((member ty '("http" "https")) (concat ty ":" target))
       ((or (null ty) (equal ty "file"))
        (concat "file://" (expand-file-name target)))
       ((equal ty "attachment")
        (let ((dir (ignore-errors (org-attach-dir))))
          (when dir (concat "file://" (expand-file-name target dir)))))))))

(defun glasspane-org-rich--text-spans (text style)
  "Split TEXT into plain runs and #hashtag runs, all under STYLE.
A hashtag must follow start-of-string or a non-word character, so `C#'
and URL fragments aren't mistaken for tags."
  (let ((spans nil) (start 0) (len (length text)))
    (while (string-match "\\(?:^\\|[^[:alnum:]_]\\)\\(#[[:alnum:]_-]+\\)" text start)
      (let ((mb (match-beginning 1)) (me (match-end 1)))
        (when (> mb start)
          (push (glasspane-org-rich--leaf (substring text start mb) style) spans))
        (push (glasspane-org-rich--leaf (substring text mb me)
                                   (glasspane-org-rich--flag style :tag))
              spans)
        (setq start me)))
    (when (< start len)
      (push (glasspane-org-rich--leaf (substring text start) style) spans))
    (nreverse spans)))

(defun glasspane-org-rich--linkify (spans action)
  "Attach ON-TAP ACTION to every span in SPANS that doesn't already have one."
  (mapcar (lambda (sp)
            (if (assq 'on_tap sp) sp (cons (cons 'on_tap action) sp)))
          spans))

(defun glasspane-org-rich--inline (objects style)
  "Convert a list of org inline OBJECTS (strings and elements) to spans.
STYLE carries inherited emphasis flags as recursion descends into
bold/italic/... containers.

Whitespace following an object belongs to the object as `:post-blank'
— it is absent from both the object's contents and the next sibling
string — so every non-string object re-emits it as a plain span, or
words jam together after emphasis, links, and timestamps."
  (let (spans)
    (dolist (obj objects)
      (cond
       ((stringp obj)
        (setq spans (append spans (glasspane-org-rich--text-spans obj style))))
       ((null obj) nil)
       (t
        (pcase (org-element-type obj)
          ('bold (setq spans (append spans
                                     (glasspane-org-rich--inline
                                      (org-element-contents obj)
                                      (glasspane-org-rich--flag style :bold)))))
          ('italic (setq spans (append spans
                                       (glasspane-org-rich--inline
                                        (org-element-contents obj)
                                        (glasspane-org-rich--flag style :italic)))))
          ('underline (setq spans (append spans
                                          (glasspane-org-rich--inline
                                           (org-element-contents obj)
                                           (glasspane-org-rich--flag style :underline)))))
          ('strike-through (setq spans (append spans
                                               (glasspane-org-rich--inline
                                                (org-element-contents obj)
                                                (glasspane-org-rich--flag style :strike)))))
          ('code (setq spans (append spans
                                     (list (glasspane-org-rich--leaf
                                            (org-element-property :value obj)
                                            (glasspane-org-rich--flag style :code))))))
          ('verbatim (setq spans (append spans
                                         (list (glasspane-org-rich--leaf
                                                (org-element-property :value obj)
                                                (glasspane-org-rich--flag style :code))))))
          ('link
           (let* ((raw (org-element-property :raw-link obj))
                  (contents (org-element-contents obj))
                  (child (if contents
                             (glasspane-org-rich--inline contents style)
                           (list (glasspane-org-rich--leaf (or raw "link") style))))
                  (action (jetpacs-action "org.link.open"
                                       :args (list (cons 'link raw)))))
             (setq spans (append spans (glasspane-org-rich--linkify child action)))))
          ('timestamp
           (setq spans (append spans
                               (list (glasspane-org-rich--leaf
                                      (org-element-property :raw-value obj)
                                      (glasspane-org-rich--flag style :code))))))
          ('entity
           ;; Render org entities (\alpha, \rightarrow, …) as their Unicode form.
           (let ((utf8 (or (org-element-property :utf-8 obj)
                           (org-element-property :name obj))))
             (when utf8
               (setq spans (append spans (list (glasspane-org-rich--leaf utf8 style)))))))
          ('subscript
           (setq spans (append spans
                               (glasspane-org-rich--inline
                                (org-element-contents obj)
                                (cons :baseline (cons "sub" style))))))
          ('superscript
           (setq spans (append spans
                               (glasspane-org-rich--inline
                                (org-element-contents obj)
                                (cons :baseline (cons "super" style))))))
          ('footnote-reference
           ;; A superscript, link-colored marker; tapping reports the inline
           ;; definition (when the reference carries one) via snackbar.
           (let* ((label (org-element-property :label obj))
                  (marker (format "[%s]" (if (and (stringp label)
                                                  (string-prefix-p "fn:" label))
                                             (substring label 3)
                                           (or label "*"))))
                  (def (string-trim
                        (or (ignore-errors
                              (org-element-interpret-data
                               (org-element-contents obj)))
                            "")))
                  (action (jetpacs-action "org.footnote.show"
                                       :args (list (cons 'label (or label ""))
                                                   (cons 'def def)))))
             (setq spans
                   (append spans
                           (list (jetpacs-span marker
                                            :baseline "super"
                                            :tag t
                                            :on-tap action))))))
          ('line-break
           (setq spans (append spans (list (jetpacs-span "\n")))))
          (_
           ;; Anything else (latex fragment, export snippet, …): fall back to
           ;; its interpreted source text.
           (let ((txt (ignore-errors (org-element-interpret-data obj))))
             (when (stringp txt)
               (setq spans (append spans
                                   (glasspane-org-rich--text-spans
                                    (string-trim-right txt) style)))))))
        (let ((pb (or (org-element-property :post-blank obj) 0)))
          (when (> pb 0)
            (setq spans (append spans
                                (list (glasspane-org-rich--leaf
                                       (make-string pb ?\s) style)))))))))
    spans))

;; ─── Block elements ──────────────────────────────────────────────────────────

(defun glasspane-org-rich--item (item)
  "Render a plain-list ITEM to a node (bullet/number + content, plus sub-elements).

When `glasspane-org-rich--file' and `glasspane-org-rich--body-offset' are set
(the reader passes them), checkbox items get a tappable icon that
toggles the checkbox via Emacs without entering edit mode."
  (let* ((bullet (or (org-element-property :bullet item) "- "))
         (checkbox (org-element-property :checkbox item))
         (contents (org-element-contents item))
         (para (cl-find-if (lambda (c) (eq (org-element-type c) 'paragraph)) contents))
         (inline (when para (glasspane-org-rich--inline (org-element-contents para) nil)))
         (lead-text (concat (string-trim-right bullet) " "))
         (head
          (if (and checkbox glasspane-org-rich--file glasspane-org-rich--body-offset
                   (not glasspane-org-rich--read-only))
              ;; Interactive checkbox — a tappable icon beside the item text.
              (let* ((checked (eq checkbox 'on))
                     (item-pos (+ glasspane-org-rich--body-offset
                                  (org-element-property :begin item)))
                     (cb-icon (pcase checkbox
                                ('on  "check_box")
                                ('off "check_box_outline_blank")
                                (_    "indeterminate_check_box")))
                     (cb (jetpacs-box
                          (list (jetpacs-icon cb-icon :size 20))
                          :on-tap (jetpacs-action
                                   "checkbox.toggle"
                                   :args `((file . ,glasspane-org-rich--file)
                                           (pos  . ,item-pos))))))
                (jetpacs-row cb
                          (jetpacs-box
                           (list (jetpacs-rich-text
                                  (cons (jetpacs-span lead-text)
                                        (or inline (list (jetpacs-span ""))))))
                           :weight 1)))
            ;; No checkbox, or no file context — plain text as before.
            (let* ((mark (pcase checkbox
                           ('on "☑ ") ('off "☐ ") ('trans "◪ ") (_ "")))
                   (lead (jetpacs-span (concat lead-text mark))))
              (jetpacs-rich-text (cons lead (or inline (list (jetpacs-span ""))))))))
         (rest-contents (delq para (copy-sequence contents)))
         (sub-nodes (delq nil (mapcar #'glasspane-org-rich--element rest-contents))))
    (if sub-nodes
        (jetpacs-column head
                     (jetpacs-row (jetpacs-spacer :width 16)
                               (jetpacs-box (list (apply #'jetpacs-column sub-nodes)) :weight 1)))
      head)))

(defun glasspane-org-rich--list (el)
  "Render a plain-list EL to a column of item nodes."
  (let ((items (delq nil
                     (mapcar (lambda (item)
                               (when (eq (org-element-type item) 'item)
                                 (glasspane-org-rich--item item)))
                             (org-element-contents el)))))
    (when items (apply #'jetpacs-column items))))

;; ─── Source blocks ───────────────────────────────────────────────────────────

(defun glasspane-org-rich--src-block (el)
  "Render src-block EL: highlighted code, plus a run header when executable.
The header (language label + play button dispatching `org.babel.execute')
appears only when file context is present *and* this Emacs has an
`org-babel-execute:LANG' function — the same test execution would make,
so the button never promises more than `org-babel-load-languages'
delivers.  The action carries the block's real-file position; the code
itself never crosses the wire."
  (let* ((lang (org-element-property :language el))
         (code (jetpacs-markup (or (org-element-property :value el) "")
                            :syntax (or lang "text")))
         (pos (and glasspane-org-rich--file glasspane-org-rich--body-offset
                   lang
                   (fboundp (intern (concat "org-babel-execute:" lang)))
                   (+ glasspane-org-rich--body-offset
                      (org-element-property :post-affiliated el)))))
    (if (not pos)
        code
      (jetpacs-column
       (jetpacs-row
        (jetpacs-text lang 'label)
        (jetpacs-spacer :weight 1)
        (jetpacs-icon-button "play_arrow"
                          (jetpacs-action "org.babel.execute"
                                       :args `((file . ,glasspane-org-rich--file)
                                               (pos . ,pos)))
                          :content-description "Run block"))
       code))))

;; ─── Tables ──────────────────────────────────────────────────────────────────

(defconst glasspane-org-rich--cookie-re "\\`<[lcr]?[0-9]*>\\'"
  "Matches alignment/width cookie cells: <l>, <r>, <c>, <10>, <r20>, …")

(defun glasspane-org-rich--cell-text (cell)
  "Trimmed plain text of table CELL (nil-safe: nil CELL gives \"\")."
  (if (null cell) ""
    (string-trim
     (or (ignore-errors
           (org-element-interpret-data (org-element-contents cell)))
         ""))))

(defun glasspane-org-rich--cookie-row-p (cells)
  "Non-nil when CELLS form a cookie row (alignment config, not data).
Every non-empty cell is a cookie and at least one is non-empty."
  (let ((texts (mapcar #'glasspane-org-rich--cell-text cells)))
    (and (cl-some (lambda (s) (not (string-empty-p s))) texts)
         (cl-every (lambda (s)
                     (or (string-empty-p s)
                         (string-match-p glasspane-org-rich--cookie-re s)))
                   texts))))

(defun glasspane-org-rich--table-aligns (cookie-rows data-rows ncols)
  "Alignment strings (start/center/end) for NCOLS columns.
A cookie in COOKIE-ROWS wins; otherwise a column whose DATA-ROWS cells
are mostly numbers right-aligns, mirroring org's own aligner.  Returns
nil when every column would be \"start\" (no wire noise)."
  (let (aligns)
    (dotimes (c ncols)
      (let ((cookie
             (cl-loop for row in cookie-rows
                      for text = (glasspane-org-rich--cell-text (nth c row))
                      when (string-match "\\`<\\([lcr]\\)" text)
                      return (match-string 1 text))))
        (push
         (pcase cookie
           ("l" "start") ("c" "center") ("r" "end")
           (_ (let ((total 0) (numbers 0))
                (dolist (row data-rows)
                  (let ((text (glasspane-org-rich--cell-text (nth c row))))
                    (unless (string-empty-p text)
                      (cl-incf total)
                      (when (string-match-p org-table-number-regexp text)
                        (cl-incf numbers)))))
                (if (and (> total 0)
                         (>= (/ (float numbers) total)
                             org-table-number-fraction))
                    "end" "start"))))
         aligns)))
    (setq aligns (nreverse aligns))
    (and (cl-some (lambda (a) (not (equal a "start"))) aligns)
         aligns)))

(defun glasspane-org-rich--table-cell (cell)
  "Build a cell node for table CELL.
When file context is present (the reader passes it), tapping the cell
edits it through `org.table.edit' and long-pressing opens the
row/column menu (`org.table.cell-menu'), both at its real-file
position.  Read-only renders (babel results) stay inert."
  (let* ((spans (or (glasspane-org-rich--inline (org-element-contents cell) nil)
                    (list (jetpacs-span ""))))
         (pos (and glasspane-org-rich--file glasspane-org-rich--body-offset
                   (not glasspane-org-rich--read-only)
                   (+ glasspane-org-rich--body-offset
                      (or (org-element-property :contents-begin cell)
                          (org-element-property :begin cell)))))
         (args (when pos
                 `((file . ,glasspane-org-rich--file) (pos . ,pos)))))
    (jetpacs-table-cell
     spans
     :on-tap (when pos (jetpacs-action "org.table.edit" :args args))
     :on-long-tap (when pos (jetpacs-action "org.table.cell-menu" :args args)))))

(defun glasspane-org-rich--table (el)
  "Render an org table EL to a native `jetpacs-table' node, or nil when empty.
Cookie-only rows configure column alignment and drop out of display;
alignment otherwise follows org's numeric-majority rule.  Header rows
are the first row group when a rule separates it from more groups
\(decorative border rules don't create one).  With file context, cells
tap-edit and the client offers add-row/add-column affordances."
  (let* ((file glasspane-org-rich--file)
         (offset glasspane-org-rich--body-offset)
         (cookie-rows nil)
         ;; Ordered display shapes: `rule' or a list of cell elements.
         (shapes
          (delq nil
                (mapcar
                 (lambda (row)
                   (when (eq (org-element-type row) 'table-row)
                     (if (eq (org-element-property :type row) 'rule)
                         'rule
                       (let ((cells (org-element-contents row)))
                         (if (glasspane-org-rich--cookie-row-p cells)
                             (progn (push cells cookie-rows) nil)
                           cells)))))
                 (org-element-contents el))))
         (data-rows (cl-remove 'rule shapes))
         (ncols (cl-loop for s in data-rows maximize (length s))))
    (when (and ncols (> ncols 0))
      ;; Header = the first row group, when a rule separates it from
      ;; further groups; leading border rules don't open a group.
      (let ((groups 0) (prev-rule t) header-rows)
        (dolist (shape shapes)
          (if (eq shape 'rule)
              (setq prev-rule t)
            (when prev-rule (cl-incf groups))
            (setq prev-rule nil)
            (when (= groups 1) (push shape header-rows))))
        (unless (> groups 1) (setq header-rows nil))
        (let ((table-pos (and file offset
                              (not glasspane-org-rich--read-only)
                              (+ offset
                                 (org-element-property :post-affiliated el)))))
          (jetpacs-table
           (mapcar (lambda (shape)
                     (if (eq shape 'rule)
                         (jetpacs-table-rule)
                       (jetpacs-table-row
                        (mapcar #'glasspane-org-rich--table-cell shape)
                        :header (and (memq shape header-rows) t))))
                   shapes)
           :aligns (glasspane-org-rich--table-aligns
                    (nreverse cookie-rows) data-rows ncols)
           :on-add-row (when table-pos
                         (jetpacs-action "org.table.add-row"
                                      :args `((file . ,file)
                                              (pos . ,table-pos))))
           :on-add-col (when table-pos
                         (jetpacs-action "org.table.add-col"
                                      :args `((file . ,file)
                                              (pos . ,table-pos))))))))))

(defun glasspane-org-rich--drawer (el)
  "Render drawer EL as a folded section, like desktop org.
Returns nil for drawers named in `glasspane-org-rich--skip-drawers'
and for drawers whose content renders to nothing."
  (let ((name (or (org-element-property :drawer-name el) "DRAWER")))
    (unless (member (upcase name) glasspane-org-rich--skip-drawers)
      (let ((inner (delq nil (mapcar #'glasspane-org-rich--element
                                     (org-element-contents el)))))
        (when inner
          (jetpacs-collapsible
           (format "drawer/%s/%s"
                   (or glasspane-org-rich--file "")
                   (+ (or glasspane-org-rich--body-offset 0)
                      (org-element-property :begin el)))
           (jetpacs-text name 'label)
           inner
           :collapsed t))))))

(defun glasspane-org-rich--paragraph-image (el)
  "If paragraph EL is just a single image link, return an `jetpacs-image' node."
  (let* ((contents (org-element-contents el))
         (non-blank (cl-remove-if (lambda (c) (and (stringp c) (string-blank-p c)))
                                  contents)))
    (when (and (= (length non-blank) 1)
               (consp (car non-blank))
               (eq (org-element-type (car non-blank)) 'link))
      (let* ((lnk (car non-blank))
             (url (glasspane-org-rich--image-url (org-element-property :type lnk)
                                            (org-element-property :path lnk))))
        (when url (jetpacs-image url))))))

(defun glasspane-org-rich--element (el)
  "Render one top-level org element EL to a node, or nil to skip it.
Babel output — any element under a #+RESULTS: affiliated keyword —
renders read-only inside a foldable RESULTS section, like desktop org."
  (if (org-element-property :results el)
      (let* ((glasspane-org-rich--read-only t)
             (node (glasspane-org-rich--element-1 el)))
        (when node
          ;; `:results drawer' output is already a foldable drawer named
          ;; RESULTS — don't nest a second collapsible around it.
          (if (equal (alist-get 't node) "collapsible")
              node
            (jetpacs-collapsible
             (format "results/%s/%s"
                     (or glasspane-org-rich--file "")
                     (+ (or glasspane-org-rich--body-offset 0)
                        (org-element-property :begin el)))
             (jetpacs-text "RESULTS" 'label)
             (list node)))))
    (glasspane-org-rich--element-1 el)))

(defun glasspane-org-rich--element-1 (el)
  "Render element EL to a node ignoring any #+RESULTS: wrapping."
  (pcase (org-element-type el)
    ('paragraph
     (or (glasspane-org-rich--paragraph-image el)
         (let ((spans (glasspane-org-rich--inline (org-element-contents el) nil)))
           (when spans (jetpacs-rich-text spans)))))
    ('plain-list (glasspane-org-rich--list el))
    ('src-block (glasspane-org-rich--src-block el))
    ((or 'example-block 'fixed-width)
     (jetpacs-markup (or (org-element-property :value el) "")))
    ('quote-block
     (let ((inner (delq nil (mapcar #'glasspane-org-rich--element
                                    (org-element-contents el)))))
       (when inner (apply #'jetpacs-column inner))))
    ('table
     ;; table.el tables keep the monospace fallback; org tables go native.
     (if (eq (org-element-property :type el) 'table.el)
         (jetpacs-markup (string-trim (org-element-interpret-data el)) :syntax "org")
       (or (glasspane-org-rich--table el)
           (jetpacs-markup (string-trim (org-element-interpret-data el)) :syntax "org"))))
    ('horizontal-rule (jetpacs-divider))
    ('drawer (glasspane-org-rich--drawer el))
    ;; Structural noise the reader handles elsewhere (properties drawer) or
    ;; that carries no display value on its own.
    ((or 'keyword 'comment 'comment-block 'planning
         'property-drawer 'node-property)
     nil)
    (_
     (let ((txt (ignore-errors (string-trim (org-element-interpret-data el)))))
       (when (and (stringp txt) (not (string-empty-p txt)))
         (jetpacs-markup txt :syntax "org"))))))

(defun glasspane-org-rich--top-elements (tree)
  "Return the top-level elements of parsed TREE, descending through a section."
  (let (out)
    (dolist (el (org-element-contents tree))
      (if (eq (org-element-type el) 'section)
          (setq out (append out (org-element-contents el)))
        (setq out (append out (list el)))))
    out))

;;;###autoload
(defun glasspane-org-rich-body (body &optional base-dir file offset)
  "Parse org BODY string into a list of Jetpacs rich/markup nodes.
Paragraphs and lists become native `rich_text'; code/tables/examples
fall back to highlighted `jetpacs-markup'. BASE-DIR resolves relative image
paths (pass the org file's directory).

FILE and OFFSET enable interactive elements (checkboxes): OFFSET maps
temp-buffer positions to real file positions (real = offset + temp).
Returns nil for empty input."
  (if (or (null body) (string-empty-p (string-trim body)))
      nil
    (let ((glasspane-org-rich--file file)
          (glasspane-org-rich--body-offset offset))
      (with-temp-buffer
        (insert body)
        (when (and base-dir (file-directory-p base-dir))
          (setq default-directory base-dir))
        (let ((org-inhibit-startup t)
              (org-element-use-cache nil))
          (delay-mode-hooks (org-mode))
          (let ((tree (org-element-parse-buffer)))
            (delq nil (mapcar #'glasspane-org-rich--element
                              (glasspane-org-rich--top-elements tree)))))))))

(provide 'glasspane-org-rich)
;;; glasspane-org-rich.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-org-reader.el
;;; ==================================================================

;;; glasspane-org-reader.el --- Foldable org outline renderer for Jetpacs -*- lexical-binding: t; -*-

;; Renders an org buffer (or a single subtree) into a tree of Jetpacs widgets:
;; each heading becomes an `jetpacs-collapsible' whose header is the org-highlighted
;; heading line and whose children are an optional (collapsed) PROPERTIES drawer,
;; the heading's own body as highlighted org text, and its child headings —
;; recursively. Folding is resolved entirely on the device (see the `collapsible'
;; widget), so the whole subtree is shipped once and folds without a round-trip.
;;
;; Two entry points feed the UI layer (glasspane-ui):
;;   `glasspane-org-reader-file'    — whole file, every top-level heading foldable
;;   `glasspane-org-reader-subtree' — one heading's content inline + children foldable

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'jetpacs-widgets)
;; (require 'glasspane-org-rich) — bundle-internal, provided above

(defcustom glasspane-org-reader-max-headings 400
  "Cap on headings rendered in one reader pass, to bound very large files."
  :type 'integer :group 'jetpacs)

(defcustom glasspane-org-reader-show-deadline t
  "Show each heading's DEADLINE date on its reader header (red when overdue)."
  :type 'boolean :group 'jetpacs)

(defcustom glasspane-org-reader-show-clocked nil
  "Show each heading's total clocked time on its reader header.
Off by default: computing the sums adds an `org-clock-sum' pass over
the file on every render."
  :type 'boolean :group 'jetpacs)

;; ─── Parsing ───────────────────────────────────────────────────────────────────

(defun glasspane-org-reader--record (pos next)
  "Build a record for the heading at POS, whose body ends at NEXT.
Returns a plist with :level :pos :line :props :body :body-start.
:body-start is the real-buffer position of the first non-blank char
in the body, used to map temp-buffer positions back for interactive
elements (checkboxes)."
  (save-excursion
    (goto-char pos)
    (let* ((comps (org-heading-components))
           (level (or (nth 0 comps) 1))
           (todo (nth 2 comps))
           (priority (nth 3 comps))
           (title (or (nth 4 comps) ""))
           (tags (ignore-errors (org-get-tags pos t)))
           (done (and todo (member todo org-done-keywords) t))
           (deadline (and glasspane-org-reader-show-deadline
                          (ignore-errors (org-entry-get pos "DEADLINE"))))
           (clocked (and glasspane-org-reader-show-clocked
                         (get-text-property pos :org-clock-minutes)))
           (line (buffer-substring-no-properties
                  (line-beginning-position) (line-end-position)))
           (props (ignore-errors (org-entry-properties pos 'standard)))
           (body-info
            (progn
              (goto-char pos)
              ;; No FULL arg: skip only planning + PROPERTIES (shown as
              ;; their own section).  LOGBOOK and other drawers stay in
              ;; the body, where the rich renderer folds them.
              (ignore-errors (org-end-of-meta-data))
              (let* ((b (min (point) next))
                     (raw (buffer-substring-no-properties b next))
                     (trimmed (string-trim-left raw "\\(?:[ \t]*[\n\r]\\)+"))
                     (trim-count (- (length raw) (length trimmed))))
                (list (string-trim-right trimmed) (+ b trim-count)))))
           (body (car body-info))
           (body-start (cadr body-info)))
      (list :level level :pos pos :line line :props props
            :todo todo :priority (and priority (char-to-string priority))
            :title title :tags tags :done done
            :deadline deadline :clocked clocked
            :body body :body-start body-start))))

(defun glasspane-org-reader--collect (beg end include-first)
  "Collect heading records between BEG and END.
INCLUDE-FIRST non-nil includes the heading at BEG (used for subtrees)."
  (let (positions records)
    (save-excursion
      (goto-char beg)
      (when (and include-first (org-at-heading-p))
        (push (line-beginning-position) positions)
        (end-of-line))                  ; don't re-match this heading below
      (while (re-search-forward org-heading-regexp end t)
        (push (line-beginning-position) positions)))
    (setq positions (nreverse positions))
    (cl-loop for cell on positions
             for pos = (car cell)
             for next = (or (cadr cell) end)
             do (push (glasspane-org-reader--record pos next) records))
    (nreverse records)))

(defun glasspane-org-reader--build-tree (records)
  "Nest flat RECORDS into a tree by :level. Each node gains a :children list."
  (let* ((root (list :level 0 :children nil))
         (stack (list root)))
    (dolist (rec records)
      (let ((node (append rec (list :children nil)))
            (level (plist-get rec :level)))
        (while (>= (plist-get (car stack) :level) level)
          (pop stack))
        (let ((parent (car stack)))
          (plist-put parent :children
                     (append (plist-get parent :children) (list node))))
        (push node stack)))
    (plist-get root :children)))

;; ─── Rendering ──────────────────────────────────────────────────────────────────

(defun glasspane-org-reader--props-node (props file pos)
  "A collapsed PROPERTIES drawer node for PROPS (an alist of KEY . VALUE)."
  (let ((text (mapconcat (lambda (kv) (format ":%s: %s" (car kv) (cdr kv)))
                         props "\n")))
    (jetpacs-collapsible (format "fold-props/%s/%s" file pos)
                      (jetpacs-text "PROPERTIES" 'label)
                      (list (jetpacs-text text 'mono))
                      :collapsed t)))

(defvar glasspane-org-reader-inline-props t
  "When nil, PROPERTIES drawers are not rendered inline under headings.
The detail view binds this off: its per-heading overflow menu offers
the drawer as an editable dialog (heading.props.show) instead.")

(defun glasspane-org-reader--content-nodes (n file &optional skip-props)
  "Inline content nodes for tree node N: PROPERTIES drawer, body, child headings.
When SKIP-PROPS is non-nil, omit the PROPERTIES drawer (used when the
detail view already shows properties in its own section)."
  (let ((pos (plist-get n :pos))
        (props (plist-get n :props))
        (body (plist-get n :body))
        (body-start (plist-get n :body-start))
        (children (plist-get n :children)))
    (delq nil
          (append
           (when (and props (not skip-props) glasspane-org-reader-inline-props)
             (list (glasspane-org-reader--props-node props file pos)))
           (when (and body (not (string-empty-p body)))
             ;; Native rich text (emphasis, links, #tags) instead of the
             ;; monospace org highlighter; code/tables still fall back to it.
             ;; file + offset enable interactive checkboxes.  SKIP-PROPS
             ;; marks the detail view, which shows LOGBOOK as its own
             ;; structured section — suppress the raw drawer there.
             (let ((glasspane-org-rich--skip-drawers
                    (and skip-props '("LOGBOOK"))))
               (glasspane-org-rich-body body (and file (file-name-directory file))
                                        file (when body-start (1- body-start)))))
           (mapcar (lambda (c) (glasspane-org-reader--heading-node c file)) children)))))

(defun glasspane-org-reader--clocked-in-p (pos)
  "Whether the heading at POS in the current buffer is the clocked task."
  (and (bound-and-true-p org-clock-hd-marker)
       (marker-buffer org-clock-hd-marker)
       (eq (marker-buffer org-clock-hd-marker) (current-buffer))
       (save-excursion
         (goto-char pos)
         (= (line-beginning-position)
            (save-excursion (goto-char org-clock-hd-marker)
                            (line-beginning-position))))))

(defun glasspane-org-reader-heading-menu (ref clocked-in)
  "The per-heading overflow menu: quick actions without the detail drill-in.
Schedule/Deadline/Priority/Tags arrive with no value, which the
handlers answer with a bridged prompt dialog."
  (jetpacs-menu
   (list
    (jetpacs-menu-item "Open" (jetpacs-action "heading.tap" :args ref)
                    :icon "open_in_new")
    (if clocked-in
        (jetpacs-menu-item "Clock Out" (jetpacs-action "org.clock.out")
                        :icon "timer_off")
      (jetpacs-menu-item "Clock In"
                      (jetpacs-action "heading.clock-in" :args ref
                                   :when-offline "drop")
                      :icon "timer"))
    (jetpacs-menu-item "Priority…"
                    (jetpacs-action "heading.priority"
                                 :args (cons '(ask . t) ref)
                                 :when-offline "drop")
                    :icon "flag")
    (jetpacs-menu-item "Schedule…"
                    (jetpacs-action "heading.planning.show"
                                 :args (cons '(type . "SCHEDULED") ref)
                                 :when-offline "drop")
                    :icon "event")
    (jetpacs-menu-item "Deadline…"
                    (jetpacs-action "heading.planning.show"
                                 :args (cons '(type . "DEADLINE") ref)
                                 :when-offline "drop")
                    :icon "event_busy")
    (jetpacs-menu-item "Tags…"
                    (jetpacs-action "heading.tags"
                                 :args (cons '(ask . t) ref)
                                 :when-offline "drop")
                    :icon "label")
    (jetpacs-menu-item "Properties"
                    (jetpacs-action "heading.props.show" :args ref
                                 :when-offline "drop")
                    :icon "data_object")
    (jetpacs-menu-item "Duplicate"
                    (jetpacs-action "heading.duplicate" :args ref
                                 :when-offline "queue")
                    :icon "content_copy"))))

(defconst glasspane-org-reader--todo-color "#EF5350"
  "Span color for open TODO keywords in reader headers.")
(defconst glasspane-org-reader--done-color "#66BB6A"
  "Span color for done keywords in reader headers.")
(defconst glasspane-org-reader--priority-color "#F57C00"
  "Span color for priority cookies (matches the agenda cards).")

(defconst glasspane-org-reader--overdue-color "#EF5350"
  "Span color for overdue deadline badges.")

(defun glasspane-org-reader--meta-line (n)
  "The deadline/clocked badge line for tree node N, or nil.
The deadline date shows in the priority orange, switching to red once
overdue; the clocked total renders as h:mm."
  (let* ((deadline (plist-get n :deadline))
         (ddate (and (stringp deadline)
                     (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" deadline)
                     (match-string 0 deadline)))
         (overdue (and ddate (not (plist-get n :done))
                       (string< ddate (format-time-string "%Y-%m-%d"))))
         (mins (plist-get n :clocked))
         (spans (delq nil
                      (list
                       (when ddate
                         (jetpacs-span (concat "Deadline " ddate)
                                    :bold overdue
                                    :color (if overdue
                                               glasspane-org-reader--overdue-color
                                             glasspane-org-reader--priority-color)))
                       (when (and (numberp mins) (> mins 0))
                         (jetpacs-span (format "%s%d:%02d clocked"
                                            (if ddate "  ·  " "")
                                            (/ mins 60) (% mins 60))))))))
    (when spans (jetpacs-rich-text spans))))

(defun glasspane-org-reader--heading-header (n)
  "The structured header for tree node N.
Todo keyword and priority render as colored spans, the title strikes
through when done, tags become tappable chips, and deadline/clocked
badges follow on their own line — instead of the raw org heading
line.  Falls back to org markup when the heading didn't parse (no
title)."
  (let ((todo (plist-get n :todo))
        (priority (plist-get n :priority))
        (title (plist-get n :title))
        (tags (plist-get n :tags))
        (done (plist-get n :done)))
    (if (string-empty-p (or title ""))
        (jetpacs-markup (plist-get n :line) :syntax "org")
      (let* ((line (jetpacs-rich-text
                    (delq nil
                          (list
                           (when todo
                             (jetpacs-span (concat todo " ") :bold t
                                        :color (if done
                                                   glasspane-org-reader--done-color
                                                 glasspane-org-reader--todo-color)))
                           (when priority
                             (jetpacs-span (format "[#%s] " priority) :bold t
                                        :color glasspane-org-reader--priority-color))
                           (if done
                               (jetpacs-span title :strike t)
                             (jetpacs-span title))))))
             (meta (glasspane-org-reader--meta-line n))
             (tag-row (when tags
                        (apply #'jetpacs-flow-row
                               (mapcar (lambda (tg)
                                         (jetpacs-assist-chip
                                          tg :on-tap (jetpacs-action
                                                      "search.by-tag"
                                                      :args `((tag . ,tg)))))
                                       tags)))))
        (if (or meta tag-row)
            (apply #'jetpacs-column (delq nil (list line meta tag-row)))
          line)))))

(defun glasspane-org-reader-swipe-sides (ref)
  "The (START . END) per-side swipe actions for REF's heading.
Rightward reveals the todo cycle (green), leftward Archive (red, its
handler confirms).  Shared with the agenda/tasks cards."
  (cons (jetpacs-swipe-action "check" "Cycle"
                           (jetpacs-action "heading.todo-cycle" :args ref)
                           :color "#4CAF50")
        (jetpacs-swipe-action "archive" "Archive"
                           (jetpacs-action "heading.archive" :args ref
                                        :when-offline "drop")
                           :color "#E53935")))

(defun glasspane-org-reader--heading-node (n file)
  "Render tree node N (and its subtree) to a foldable `jetpacs-collapsible'.
Long-pressing the header opens the heading detail view when FILE is
available; the trailing overflow menu carries the quick actions, and
the header swipes: right = todo cycle, left = archive (legacy
single-action on_swipe kept for older companions)."
  (let* ((pos (plist-get n :pos))
         (ref (when file
                `((file . ,file) (pos . ,pos) (headline . ""))))
         (sides (and ref (glasspane-org-reader-swipe-sides ref)))
         (header (glasspane-org-reader--heading-header n)))
    (jetpacs-collapsible (format "fold/%s/%s" file pos)
                      (if ref
                          (jetpacs-row
                           (jetpacs-box (list header) :weight 1)
                           (glasspane-org-reader-heading-menu
                            ref (glasspane-org-reader--clocked-in-p pos)))
                        header)
                      (glasspane-org-reader--content-nodes n file)
                      :on-long-tap (when ref
                                     (jetpacs-action "heading.tap" :args ref))
                      :on-swipe (when ref
                                  (jetpacs-action "heading.todo-cycle" :args ref))
                      :swipe-start (car sides)
                      :swipe-end (cdr sides))))

;; ─── Entry points ───────────────────────────────────────────────────────────────

(defun glasspane-org-reader--cap (records)
  "Truncate RECORDS to `glasspane-org-reader-max-headings'."
  (if (> (length records) glasspane-org-reader-max-headings)
      (cl-subseq records 0 glasspane-org-reader-max-headings)
    records))

(defun glasspane-org-reader-file (file)
  "Render the whole org FILE to a list of foldable widget nodes.
Content before the first heading is not shown."
  (when (and file (file-readable-p file))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (when glasspane-org-reader-show-clocked
         (ignore-errors (org-clock-sum)))
       (let* ((records (glasspane-org-reader--cap
                        (glasspane-org-reader--collect (point-min) (point-max) nil)))
              (tree (glasspane-org-reader--build-tree records)))
         (mapcar (lambda (n) (glasspane-org-reader--heading-node n file)) tree))))))

(defun glasspane-org-reader-subtree (file pos &optional skip-props)
  "Render the org subtree at POS in FILE.
The drilled-into heading's own PROPERTIES/body render inline (its title is
already in the top bar); its child headings render as foldable sections.
Returns a list of widget nodes (possibly empty).
When SKIP-PROPS is non-nil, the top-level PROPERTIES drawer is omitted."
  (when (and file (file-readable-p file))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (when glasspane-org-reader-show-clocked
         (ignore-errors (org-clock-sum)))
       (goto-char (min pos (point-max)))
       (unless (org-at-heading-p) (ignore-errors (org-back-to-heading t)))
       (let* ((beg (point))
              (end (save-excursion (org-end-of-subtree t t)))
              (records (glasspane-org-reader--cap
                        (glasspane-org-reader--collect beg end t)))
              (tree (glasspane-org-reader--build-tree records))
              (root (car tree)))
         (when root
           (glasspane-org-reader--content-nodes root file skip-props)))))))

(defun glasspane-org-reader-refile-list (file)
  "Render all headings in FILE as a flat reorderable item list.
Returns a single `jetpacs-reorderable-list' node for refile mode."
  (when (and file (file-readable-p file))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (let* ((records (glasspane-org-reader--cap
                        (glasspane-org-reader--collect (point-min) (point-max) nil)))
              (items (mapcar (lambda (r)
                               `((label . ,(plist-get r :line))
                                 (level . ,(plist-get r :level))
                                 (pos   . ,(plist-get r :pos))
                                 (file  . ,file)))
                             records)))
         (jetpacs-reorderable-list
          items
          :on-reorder (jetpacs-action "heading.reorder"
                                   :args `((file . ,file)))))))))

(when (fboundp 'jetpacs-settings-register-section)
  (with-jetpacs-owner "glasspane"
    (jetpacs-settings-register-section
     "Reader"
     '((glasspane-org-reader-show-deadline :label "Deadline on headings")
       (glasspane-org-reader-show-clocked :label "Clocked time on headings")))))

(provide 'glasspane-org-reader)
;;; glasspane-org-reader.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-clock.el
;;; ==================================================================

;;; glasspane-clock.el --- org-clock chronometer notification -*- lexical-binding: t; -*-

;; Tier 1 org integration: mirrors the running org clock to the companion
;; as an ongoing chronometer notification with Clock out / Switch task
;; buttons, and re-asserts it on reconnect so the phone's cache matches
;; reality after an Emacs restart.
;;
;; This is app-layer code — the core (jetpacs-surfaces) knows nothing about
;; org; it only carries the `notification:org-clock' surface this module
;; pushes through the generic senders.

;;; Code:

(require 'jetpacs)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'org-clock)

(defun glasspane-clock-in-notification ()
  "Push the org-clock chronometer notification surface."
  (when (and (boundp 'org-clock-current-task) org-clock-current-task)
    (jetpacs-surface-push
     "notification:org-clock"
     (jetpacs-notification-spec
      :channel "clocking" :ongoing t :category "stopwatch"
      :chronometer `((base_ms . ,(truncate (* (float-time org-clock-start-time) 1000))))
      :body (list
             (jetpacs-text (format "Clocked in: %s" org-clock-current-task) 'title)
             (jetpacs-row
              (jetpacs-button "Clock out"
                           (jetpacs-action "org.clock.out" :when-offline "wake"))
              (jetpacs-button "Switch task"
                           (jetpacs-action "org.clock.switch" :when-offline "wake"))))))))

(defun glasspane-clock-out-notification ()
  "Remove the org-clock notification surface."
  (jetpacs-surface-remove "notification:org-clock"))

;; Closing the loop: a tap on "Clock out" arrives here as an event.action.
(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "org.clock.out"
                  (lambda (&rest _) (when (org-clock-is-active) (org-clock-out))))
  (jetpacs-defaction "org.clock.switch"
                  ;; Placeholder: jump to the running task. Swap for a real
                  ;; task-picker (e.g. org-clock-in to a recent task) when ready.
                  (lambda (&rest _) (org-clock-goto)))
  (jetpacs-defaction "org.clock.in-last"
                  ;; The home-screen widget's "Clock In (Last)" button.
                  (lambda (&rest _)
                    (condition-case err
                        (org-clock-in-last)
                      (error (message "Jetpacs clock-in-last failed: %s"
                                      (error-message-string err)))))))

(add-hook 'org-clock-in-hook  #'glasspane-clock-in-notification)
(add-hook 'org-clock-out-hook #'glasspane-clock-out-notification)

;; ─── Home-screen clock widget (a blank widget:customN slot) ──────────────────

(defvar glasspane-clock--widget-pushed nil
  "Non-nil once the static clock widget spec has been pushed this session.")

(defun glasspane-clock-widget-spec ()
  "The `widget:custom1' spec: clock in (last) / clock out rows.
The foundation's JetpacsClockWidgetProvider is gone (it hardcoded the
two org actions in Kotlin); the same widget is composed here and
rendered by the companion's blank widget slots. Taps are silent
broadcasts — no app open — and queue when Emacs is dead, exactly as
the old static widget did."
  `((title . "Org clock")
    (items . ,(vconcat
               (list
                (jetpacs-widget-item "Clock in (last)"
                                  :meta "Resume the last task"
                                  :icon "scheduled"
                                  :on-tap (jetpacs-action "org.clock.in-last"
                                                       :when-offline "queue"))
                (jetpacs-widget-item "Clock out"
                                  :meta "Stop the running clock"
                                  :icon "event"
                                  :on-tap (jetpacs-action "org.clock.out"
                                                       :when-offline "queue")))))))

(defun glasspane-clock--push-widget ()
  "Push the clock widget once per session (static content; it persists)."
  (unless glasspane-clock--widget-pushed
    (setq glasspane-clock--widget-pushed t)
    (jetpacs-surface-push "widget:custom1" (glasspane-clock-widget-spec))))

(add-hook 'jetpacs-shell-after-push-hook #'glasspane-clock--push-widget)

;; On (re)connect, re-assert current clock state so the companion's cache
;; matches reality after an Emacs restart. (Runs after the revision snapshot
;; has been absorbed — see the -50 depth in jetpacs-surfaces.)
(add-hook 'jetpacs-connected-hook
          (lambda (_welcome)
            (when (and (fboundp 'org-clock-is-active) (org-clock-is-active))
              (glasspane-clock-in-notification))))

(provide 'glasspane-clock)
;;; glasspane-clock.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-org-toolbar.el
;;; ==================================================================

;;; glasspane-org-toolbar.el --- the org keyboard toolbar as data -*- lexical-binding: t; -*-

;; The org formatting toolbar, composed as pure data (SPEC §9 "Editor
;; toolbars" in the jetpacs submodule).  The companion interprets the
;; items locally — every tap is one splice, one undo step, no Emacs
;; round-trip — so this app ships its toolbar with zero Kotlin.  It
;; replaces the reference companion's OrgEditToolbar.kt (deleted from
;; the foundation); this file is now the specification of what the org
;; toolbar contains.

;;; Code:

(require 'jetpacs-widgets)

(defconst glasspane-org-toolbar--src-languages
  '("emacs-lisp" "python" "shell" "kotlin" "java"
    "javascript" "sql" "c" "rust" "go" "org" "text")
  "Preset languages in the src-block menu; a final item prompts free-form.")

(defun glasspane-org-toolbar--src-item (lang)
  "A src-block menu sub-item inserting a LANG block."
  (jetpacs-toolbar-item nil lang
                     :snippet (format "#+begin_src %s\n${cursor}\n#+end_src" lang)
                     :placement "block"))

(defun glasspane-org-toolbar ()
  "The org keyboard toolbar as a list of `jetpacs-toolbar-item's.
Attach it via `jetpacs-editor' :toolbar (the detail-view editor) or
return it from `jetpacs-files-editor-toolbar-function' (.org files).
Anything smarter than a local edit belongs in an :on-tap item — that
round-trips to Emacs through the ordinary action pipeline."
  (list
   ;; Heading (dropdown for levels)
   (jetpacs-toolbar-item "title" "H"
                      :menu (mapcar (lambda (level)
                                      (let ((stars (make-string level ?*)))
                                        (jetpacs-toolbar-item
                                         nil (format "%s Heading %d" stars level)
                                         :snippet (concat stars " ")
                                         :placement "line-start")))
                                    (number-sequence 1 6)))
   ;; TODO heading (dropdown for levels)
   (jetpacs-toolbar-item "task_alt" "TODO"
                      :menu (mapcar (lambda (level)
                                      (let ((stars (make-string level ?*)))
                                        (jetpacs-toolbar-item
                                         nil (format "%s TODO %d" stars level)
                                         :snippet (concat stars " TODO ")
                                         :placement "line-start")))
                                    (number-sequence 1 6)))
   ;; Structure: promote / demote / move up / move down
   (jetpacs-toolbar-item "format_indent_decrease" "←" :line "promote")
   (jetpacs-toolbar-item "format_indent_increase" "→" :line "demote")
   (jetpacs-toolbar-item "arrow_upward" "↑" :line "move-up")
   (jetpacs-toolbar-item "arrow_downward" "↓" :line "move-down")
   ;; Lists
   (jetpacs-toolbar-item "checklist" "☐" :snippet "- [ ] " :placement "line-start")
   ;; Progress cookie: tap = [/], long-press = [%]
   (jetpacs-toolbar-item "data_object" "[/]" :snippet "[/]"
                      :long-press (jetpacs-toolbar-item nil nil :snippet "[%]"))
   (jetpacs-toolbar-item "format_list_bulleted" "•" :snippet "- " :placement "line-start")
   (jetpacs-toolbar-item "format_list_numbered" "1." :snippet "1. " :placement "line-start")
   ;; Source block: preset languages, plus a free-form prompt
   (jetpacs-toolbar-item "code" "Src"
                      :menu (append
                             (mapcar #'glasspane-org-toolbar--src-item
                                     glasspane-org-toolbar--src-languages)
                             (list (jetpacs-toolbar-item
                                    nil "Custom…"
                                    :snippet "#+begin_src ${input:Language}\n${cursor}\n#+end_src"
                                    :placement "block"))))
   ;; Properties drawer
   (jetpacs-toolbar-item "data_object" "Props"
                      :snippet ":PROPERTIES:\n:END:" :placement "block")
   ;; Inline emphasis (selection-aware wraps)
   (jetpacs-toolbar-item "format_bold" "B" :snippet "*${selection}*")
   (jetpacs-toolbar-item "format_italic" "I" :snippet "/${selection}/")
   (jetpacs-toolbar-item "code" "~" :snippet "~${selection}~")
   (jetpacs-toolbar-item "format_strikethrough" "S" :snippet "+${selection}+")
   ;; Link: cursor in the target, selection becomes the description
   (jetpacs-toolbar-item "link" "Link" :snippet "[[${cursor}][${selection}]]")
   ;; Timestamp: tap = inactive [date], long-press = active <date>
   (jetpacs-toolbar-item "schedule" "TS" :snippet "[${date}]"
                      :long-press (jetpacs-toolbar-item nil nil :snippet "<${date}>"))))

(provide 'glasspane-org-toolbar)
;;; glasspane-org-toolbar.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-ui.el
;;; ==================================================================

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

;; (require 'glasspane-org) — bundle-internal, provided above

;; (require 'glasspane-clock) — bundle-internal, provided above

;; (require 'glasspane-org-toolbar) — bundle-internal, provided above

;; (require 'glasspane-org-reader) — bundle-internal, provided above

(require 'jetpacs-files)

(require 'jetpacs-keymap)

;; (require 'jetpacs-magit) — bundle-internal, provided above

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

(defun glasspane-ui--settings-view (snackbar)
  (jetpacs-shell-nav-view "Settings" (glasspane-ui--settings-body)
                       :snackbar snackbar))

(with-jetpacs-owner "glasspane"
  (jetpacs-shell-define-view "glasspane.settings" :builder #'glasspane-ui--settings-view
                          :order 80))

;; Glasspane is the first `jetpacs-defapp'. Zero visible change while it is
;; the only app; load a second app (jetpacs-hello.el) and the launcher home
;; appears with these views grouped as Glasspane's own.  Every view name
;; carries the "glasspane." namespace so a coexisting app (orgzly's
;; "orgzly.agenda", say) can never replace one of these in the registry.
(jetpacs-defapp "glasspane" :label "Glasspane" :icon "event"
             :views '("glasspane.agenda" "glasspane.journal" "glasspane.tasks"
                      "glasspane.clock" "glasspane.search" "glasspane.views"
                      "glasspane.review" "glasspane.settings" "glasspane.detail"
                      "glasspane.gallery")
             :order 10)

;; The core auto-registers a vanilla "Jetpacs" app claiming the stock
;; views (`jetpacs-apps-show-vanilla-app', default t) — with Glasspane
;; loaded that makes two apps, and containment takes Files and Eval
;; (the only stock bottom-bar tabs) out of Glasspane's bar into the
;; launcher's second app.  It also turns the core's unowned drawer
;; entries (Buffers, Messages, Tools) into dead taps here: they render
;; in every app, but switch to views the app filter drops from the
;; push while Glasspane is current.  Glasspane's opinion is the
;; single-app world: flip the option off through its :set (which does
;; the actual unregistration), and every stock view shows here again —
;; Files (order 40) and Eval (order 50) slot in after the org tabs,
;; the drawer entries land.  The user keeps the last word both ways:
;; an already-loaded saved customization is respected (the `get'
;; guard), and the Settings toggle saves to custom.el, which the
;; starter init loads after this bundle — re-enabling re-registers.
(unless (get 'jetpacs-apps-show-vanilla-app 'saved-value)
  (customize-set-variable 'jetpacs-apps-show-vanilla-app nil))

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

(defvar glasspane-ui-detail-toolbar-functions nil
  "Abnormal hook: functions from a detail REF to floating-toolbar items.
App layers contribute `jetpacs-nav-item' chips after the built-in
Refile/Archive pair; each returns an item list or nil.  An erroring
function costs its own chips, never the toolbar.")

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
              (save-buffer))
            ;; Read-after-write: vulpea's autosync lags the save on an
            ;; idle timer, and the push right after this would render
            ;; the stale row (tasks view todo/priority).
            (glasspane-org--vulpea-refresh-file)))
        (jetpacs-org-cache-invalidate 'glasspane)
        t)
    (error
     (message "Jetpacs: heading action failed: %s" (error-message-string err))
     (jetpacs-shell-notify "Couldn't find that heading — refreshing")
     (jetpacs-shell-push)
     nil)))

(with-jetpacs-owner "glasspane"
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
        (jetpacs-shell-push)))))

;; Org-derived views are memoised; per the cache contract every mutation
;; must drop the memo or the phone keeps rendering stale data.
(add-hook 'jetpacs-settings-after-set-hook
          (lambda (sym _value)
            (when (or (string-prefix-p "org-" (symbol-name sym))
                      (string-prefix-p "calendar-" (symbol-name sym)))
              (jetpacs-org-cache-invalidate 'glasspane))))

(with-jetpacs-owner "glasspane"
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
              (format "Toggle failed: %s" (error-message-string err))))))))))

;; ─── Babel ───────────────────────────────────────────────────────────────────

(defcustom glasspane-babel-timeout 30
  "Seconds before a phone-triggered babel execution is abandoned.
Best-effort: the timer can't interrupt a synchronous subprocess mid-call,
but it fires between process reads and stops a runaway block from
wedging the bridge forever."
  :type 'integer :group 'jetpacs)

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "file.view"
    ;; Legacy (old cached UIs): now routes into the jetpacs-files editor.
    (lambda (args _)
      ;; `jetpacs-files-open' guards stringp + readability + within-root,
      ;; runs the open hook, and does the :switch-to "edit" push itself.
      (jetpacs-files-open (alist-get 'file args)))))

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

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "files.filter"
    ;; The sparse filter for the open org file: VALUE is the submitted
    ;; query ("" clears). State only — matching happens at render.
    (lambda (args _)
      (let ((value (alist-get 'value args)))
        (when (stringp value)
          (setq glasspane-ui--files-filter value)
          (jetpacs-shell-push nil :switch-to "edit"))))))

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

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "files.toggle-read"
    (lambda (_ _)
      (setq glasspane-ui--files-read-mode (not glasspane-ui--files-read-mode))
      (jetpacs-shell-push nil :switch-to "edit")))

  (jetpacs-defaction "files.toggle-refile"
    (lambda (_ _)
      (setq glasspane-ui--files-refile-mode (not glasspane-ui--files-refile-mode))
      (jetpacs-shell-push nil :switch-to "edit"))))

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

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-agenda.el
;;; ==================================================================

;;; glasspane-agenda.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

;; (require 'glasspane-ui) — bundle-internal, provided above

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

(with-jetpacs-owner "glasspane"
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
                          :order 30))

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
     (jetpacs-node-or "month_grid"
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

(defun glasspane-ui--agenda-month-fallback (items-by-date anchor selected-date
                                                       &optional select-action)
  "The composed month grid for companions that predate `month_grid'.
SELECT-ACTION (default \"agenda.select-date\") receives the tapped
day as its `date' arg — saved views pass their own handler."
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
                              :on-tap (jetpacs-action (or select-action "agenda.select-date")
                                                   :args `((date . ,date-str))))
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
   ((equal mode "month")
    ;; Grid present: it carries its own header/chevrons/swipe, so only the
    ;; jump-home chip is ours (and only off the current month).  Grid absent:
    ;; fall back to the shared nav row.
    (jetpacs-node-or "month_grid"
      (unless (equal (substring anchor 0 7) (format-time-string "%Y-%m"))
        (jetpacs-row
         (jetpacs-spacer :weight 1)
         (jetpacs-assist-chip "Today" :icon "today"
                           :on-tap (jetpacs-action "agenda.today"))))
      (glasspane-ui--agenda-nav-row mode anchor)))
   ((member mode '("day" "week"))
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
    (jetpacs-node-or "tabs"
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

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "tasks.filter"
    (lambda (args _)
      (setq glasspane-ui--tasks-filter (alist-get 'filter args))
      (jetpacs-shell-push))
    :doc "Filter the tasks collection to a TODO keyword (or \"ALL\")."
    :args '((:name filter :type "text" :required t))))

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
  (jetpacs-org-cache-invalidate 'glasspane)
  (jetpacs-settings-save-variable 'org-todo-keywords seqs))

(with-jetpacs-owner "glasspane"
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
        (jetpacs-shell-push)))))

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

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-capture.el
;;; ==================================================================

;;; glasspane-capture.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

;; (require 'glasspane-ui) — bundle-internal, provided above

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
       ;; header_action: the widget header's "+" is server-driven chrome
       ;; (SPEC §4) — the companion hardcodes nothing; this is where the
       ;; org-capture opinion lives now.
       `((views . ,views)
         (initial_view . "today")
         (header_action . ,(jetpacs-action "org.capture.show"
                                        :when-offline "queue")))))))

(defvar glasspane-ui--capture-tile-pushed nil
  "Non-nil once the static capture tile spec has been pushed this session.")

(defun glasspane-ui--push-capture-tile ()
  "Push the `tile:custom1' Quick Settings tile: one-tap org capture.
The foundation's CaptureTileService is gone (it hardcoded an org
action); the tile is now composed here and rendered by the companion's
blank tile slots. Static content — pushed once per session; the
companion persists it, and the user adds the tile to the shade from
the tile picker."
  (unless glasspane-ui--capture-tile-pushed
    (setq glasspane-ui--capture-tile-pushed t)
    (jetpacs-surface-push
     "tile:custom1"
     (jetpacs-tile "Capture" :icon "add" :state "active"
                :on-tap (jetpacs-action "org.capture.show"
                                     :when-offline "queue")
                ;; Capture needs a keyboard, so the tap opens the app.
                :in-app t))))

;; App opinion: dialogs present as bottom sheets (SPEC §7 `dialog_style') —
;; capture templates, pickers, and the whole minibuffer bridge read native
;; on mobile. Per-user override lives in Settings → Appearance; old
;; companions ignore the style and center the dialog.
(setq jetpacs-dialog-style "sheet")

;; Capture is this app's signature affordance: the default FAB on every
;; Glasspane tab view that doesn't define its own — and, registered
;; per-app, never on a coexisting app's views.
(jetpacs-apps-set-default-fab "glasspane"
                           (lambda (_name)
                             (jetpacs-fab "add" :label "Capture"
                                       :on-tap (jetpacs-action "org.capture.show"))))

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

(defun glasspane-capture--form ()
  "The capture dialog's field registry (`jetpacs-form').
Reset before each dialog and after each submit: rotating the field ids
keeps a previous capture's device-side field state from resurfacing."
  (jetpacs-form "cap" "glasspane"))

(defun glasspane-ui-show-capture-form (template-key)
  ;; Forget values from any previous capture so they can't leak into
  ;; this submit — the reset also rotates the field ids, so stale
  ;; device-side field state can't resurface either.
  (jetpacs-form-reset (glasspane-capture--form))
  ;; A shared-in subject pre-fills the Headline field; it must also land
  ;; in UI state, since state.changed only fires for edits the user makes.
  (when glasspane-ui--shared-subject
    (jetpacs-form-seed (glasspane-capture--form) "Headline"
                       glasspane-ui--shared-subject))
  (condition-case err
      (let* ((form (glasspane-capture--form))
             (templates (glasspane-org--capture-templates))
             (tmpl (cl-find-if
                    (lambda (t-info) (equal (alist-get 'key t-info) template-key))
                    templates))
             (prompts (append (alist-get 'prompts tmpl) nil)) ;; coerce vector to list
             (inputs (mapcar (lambda (p)
                               (jetpacs-text-input
                                (jetpacs-form-field-id form p) :label p
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

(with-jetpacs-owner "glasspane"
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
      (jetpacs-dismiss-dialog))))

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
(with-jetpacs-owner "glasspane"
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
                   (form (glasspane-capture--form))
                   (values (mapcar
                            (lambda (p)
                              (let ((v (jetpacs-form-value form p)))
                                (cons p (if (stringp v) v ""))))
                            prompts)))
              (glasspane-org--do-capture key values glasspane-ui--shared-text)
              (setq glasspane-ui--shared-text nil
                    glasspane-ui--shared-subject nil)
              (jetpacs-org-cache-invalidate 'glasspane)
              (jetpacs-form-reset form)
              (jetpacs-shell-notify "Captured ✓")
              (jetpacs-dismiss-dialog)
              (jetpacs-shell-push))
          (error
           (message "Jetpacs capture submit error: %s" (error-message-string err))
           (setq glasspane-ui--shared-text nil
                 glasspane-ui--shared-subject nil)
           (jetpacs-form-reset (glasspane-capture--form))
           (jetpacs-dismiss-dialog)))))))

(provide 'glasspane-capture)

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-detail.el
;;; ==================================================================

;;; glasspane-detail.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

;; (require 'glasspane-ui) — bundle-internal, provided above

(defvar glasspane-ui--detail-ref nil
  "Reference alist (id/file/pos/headline) of the heading being viewed, or nil.")

(defvar glasspane-ui--detail-read-mode t
  "When non-nil, detail view shows the foldable reader instead of the editor.")

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

(defun glasspane-ui--detail-toolbar-extras (ref)
  "Every registered app layer's floating-toolbar chips for REF.
An erroring contributor costs its own chips, never the toolbar."
  (when ref
    (cl-loop for fn in glasspane-ui-detail-toolbar-functions
             append (condition-case nil (funcall fn ref)
                      (error nil)))))

(defun glasspane-ui--detail-copy-link-item (ref)
  "The Copy Link chip for REF, or nil when the ref can't resolve.
An id link when the heading already has an :ID:, a file::*headline
link otherwise — built at render time so the copy itself is
companion-local (`clipboard.copy') and works offline."
  (condition-case nil
      (let ((marker (jetpacs-org-resolve-ref ref)))
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (let* ((headline (org-get-heading t t t t))
                  (id (org-entry-get nil "ID"))
                  (link (if id
                            (format "[[id:%s][%s]]" id headline)
                          (format "[[file:%s::*%s][%s]]"
                                  (buffer-file-name) headline headline))))
             (jetpacs-nav-item "content_copy" "Copy Link"
                            (jetpacs-clipboard-action link))))))
    (error nil)))

(defun glasspane-ui--detail-subtree-text (ref)
  "REF's whole subtree as a string, or nil when the ref can't resolve."
  (condition-case nil
      (let ((marker (jetpacs-org-resolve-ref ref)))
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (buffer-substring-no-properties
            (point)
            (progn (org-end-of-subtree t t) (point))))))
    (error nil)))

(defun glasspane-ui--detail-copy-text-item (ref)
  "The Copy Text chip for REF: the whole subtree onto the clipboard.
Companion-local (`clipboard.copy'), so it works offline; nil when the
ref can't resolve."
  (when-let ((text (glasspane-ui--detail-subtree-text ref)))
    (jetpacs-nav-item "copy_all" "Copy Text"
                   (jetpacs-clipboard-action text))))

(defun glasspane-ui--detail-share-item (ref)
  "The Share chip for REF: the whole subtree through the system share
sheet (`share.send'), titled with the headline; nil when the ref
can't resolve."
  (when-let ((text (glasspane-ui--detail-subtree-text ref)))
    (jetpacs-nav-item "share" "Share"
                   (jetpacs-share-action
                    text :title (alist-get 'headline ref)))))

(defun glasspane-ui--sibling-ref (ref direction)
  "A `heading.tap' ref for REF's same-level sibling in DIRECTION, or nil.
DIRECTION is `next' or `prev'.  Drives the detail view's Prev/Next
bottom-bar navigation, which only appears when a sibling exists — so
this doubles as the availability check."
  (condition-case nil
      (let ((marker (jetpacs-org-resolve-ref ref)))
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (org-back-to-heading t)
           (when (org-goto-sibling (eq direction 'prev))
             (let ((file (buffer-file-name))
                   (pos (point))
                   (title (nth 4 (org-heading-components))))
               (delq nil
                     (list (when file `(file . ,file))
                           `(pos . ,pos)
                           (when (and title (not (string-empty-p title)))
                             `(headline . ,title)))))))))
    (error nil)))

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
                 ;; Prev/Next flank the bar (leftmost / rightmost) and
                 ;; appear only when a same-level sibling exists; the two
                 ;; add actions sit between them.
                 (let ((prev (and ref (glasspane-ui--sibling-ref ref 'prev)))
                       (next (and ref (glasspane-ui--sibling-ref ref 'next))))
                   (jetpacs-bottom-bar
                    (delq nil
                          (list
                           (when prev
                             (jetpacs-nav-item
                              "chevron_left" "Prev"
                              (jetpacs-action "heading.tap" :args prev)))
                           (jetpacs-nav-item
                            "edit_note" "Log Note"
                            (jetpacs-action "heading.add-note"
                                         :args glasspane-ui--detail-ref
                                         :when-offline "drop"))
                           (jetpacs-nav-item
                            "post_add" "Add Heading"
                            (jetpacs-action "heading.add-heading"
                                         :args glasspane-ui--detail-ref
                                         :when-offline "drop"))
                           (when next
                             (jetpacs-nav-item
                              "chevron_right" "Next"
                              (jetpacs-action "heading.tap" :args next))))))))
   :floating-toolbar (when glasspane-ui--detail-read-mode
                       (vconcat
                        (delq nil
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
                                             :when-offline "drop"))
                               (when ref
                                 (glasspane-ui--detail-copy-link-item ref))
                               (when ref
                                 (glasspane-ui--detail-copy-text-item ref))
                               (when ref
                                 (glasspane-ui--detail-share-item ref))
                               (jetpacs-nav-item
                                "delete" "Delete"
                                (jetpacs-action "heading.delete"
                                             :args glasspane-ui--detail-ref
                                             :when-offline "drop"))))
                        (glasspane-ui--detail-toolbar-extras ref)))
   :snackbar snackbar)))

(with-jetpacs-owner "glasspane"
  (jetpacs-shell-define-view "glasspane.detail" :builder #'glasspane-ui--detail-view
                          :when (lambda () (and glasspane-ui--detail-ref t))
                          :overlay (lambda () (and glasspane-ui--detail-ref t))
                          :order 110))

(defun glasspane-ui--ref-clocked-in-p (ref)
  "Whether REF's heading is the currently clocked task.
A file that isn't even visited can't be the clock source, so this
stays cheap across a list of cards."
  (when-let* ((file (alist-get 'file ref))
              (pos (alist-get 'pos ref))
              (buf (find-buffer-visiting file)))
    (and (bound-and-true-p org-clock-hd-marker)
         (eq (marker-buffer org-clock-hd-marker) buf)
         (integerp pos)
         (with-current-buffer buf
           (org-with-wide-buffer
            (= (progn (goto-char (min pos (point-max)))
                      (line-beginning-position))
               (progn (goto-char org-clock-hd-marker)
                      (line-beginning-position))))))))

(defun glasspane-ui--agenda-card (it)
  "A detail-rich agenda card for item IT.
Leading time (or a type icon), priority-prefixed headline (struck
through when done), a todo/type/file caption, tag chips when present,
a quick complete button for open todos, and the heading overflow menu."
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
    (let ((sides (and ref (glasspane-org-reader-swipe-sides ref))))
      (jetpacs-card
       (list (apply #'jetpacs-row
                    (delq nil (list lead
                                    (jetpacs-box (list middle) :weight 1)
                                    (when ref
                                      (glasspane-org-reader-heading-menu
                                       ref (glasspane-ui--ref-clocked-in-p ref)))))))
       :on-tap (jetpacs-action "heading.tap" :args ref)
       :on-swipe (jetpacs-action "heading.todo-cycle" :args ref)
       :swipe-start (car sides)
       :swipe-end (cdr sides)))))

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
  (let* ((marker (ignore-errors (jetpacs-org-resolve-ref ref)))
         (buf (and marker (marker-buffer marker)))
         (allowed (and buf
                       (with-current-buffer buf
                         (org-with-wide-buffer (goto-char pos)
                           (ignore-errors
                             (org-property-get-allowed-values pos key))))))
         (is-boolean (or (equal allowed '("t" "nil")) (equal allowed '("true" "false"))
                         (string-match-p "\\?" key)))
         (is-date (or (string-match-p "_DATE\\|_TIME\\'" key)
                      (member key '("CREATED" "SCHEDULED" "DEADLINE"))
                      (string-match-p "\\`[[<].*?[\]>]\\'" value)))
         (is-number (and (not is-date) (string-match-p "\\`[0-9]+\\'" value)))
         (is-link (and (not (string-empty-p value)) (string-match org-link-bracket-re value)))
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
              ;; :on-change is the enum-list's real callback key — the
              ;; old :on-select signalled whenever a property carried
              ;; org allowed values (KEY_ALL), killing the whole row.
              (jetpacs-enum-list (format "prop-%s/%s" pos key) allowed
                              :value (list value)
                              :on-change action))
             (is-date
              (jetpacs-date-button (if (string-empty-p value) "Set Date" value) action :value value))
             (is-number
              (let ((num (string-to-number value)))
                (if (<= num 10)
                    (jetpacs-slider (format "prop-%s/%s" pos key) :value num :min 0 :max 10 :steps 10 :on-change action)
                  (jetpacs-slider (format "prop-%s/%s" pos key) :value num :min 0 :max 100 :steps 100 :on-change action))))
             (is-link
              (let ((link (match-string 1 value))
                    (desc (match-string 2 value)))
                (jetpacs-button (or desc link)
                                (jetpacs-action "org.open-at-point" :args `((link . ,link)))
                                :variant "outlined")))
             (t
              (jetpacs-text-input (format "prop-%s/%s" pos key)
                               :value value
                               :single-line t
                               :on-submit action))))
      :weight 3))))

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
      (let* ((marker (jetpacs-org-resolve-ref ref))
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
                            :toolbar (glasspane-org-toolbar)
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
                          ;; Properties are shown above (and for sub-headings
                          ;; through the overflow menu's dialog), so no
                          ;; inline drawers here.
                          (let ((glasspane-org-reader-inline-props nil))
                            (glasspane-org-reader-subtree file pos t))))))))
    (error
     (jetpacs-column
      (jetpacs-text "Error loading heading" 'title)
      (jetpacs-text (error-message-string err) 'body)))))

;; ─── The structured Scheduled/Deadline editor dialog ─────────────────────────

(defun glasspane-ui--set-repeater (type repeater)
  "Rewrite the repeater cookie on the TYPE planning timestamp at point.
TYPE is \"SCHEDULED\" or \"DEADLINE\"; REPEATER like \"+1w\" (nil
removes).  A heading without a TYPE timestamp is a no-op — the dialog
asks for a date first."
  (save-excursion
    (org-back-to-heading t)
    (let ((bound (save-excursion (outline-next-heading) (point))))
      (when (re-search-forward (concat type ":[ \t]*\\([<[]\\)") bound t)
        (let* ((beg (match-beginning 1))
               (close (if (equal (match-string 1) "<") ">" "]"))
               (end (progn (goto-char beg) (search-forward close bound)))
               (ts (buffer-substring-no-properties beg end))
               (stripped (replace-regexp-in-string
                          "[ \t]+[.+]?\\+[0-9]+[hdwmy]" "" ts))
               (new (if repeater
                        (concat (substring stripped 0 -1) " " repeater
                                (substring stripped -1))
                      stripped)))
          (delete-region beg end)
          (goto-char beg)
          (insert new))))))

(defconst glasspane-ui--repeater-choices
  '("none" "+1d" "+1w" "+2w" "+1m" "+3m" "+1y")
  "Repeater cookies offered in the planning dialog.")

(defun glasspane-ui--planning-dialog (ref type)
  "Send the structured TYPE editor dialog for REF.
TYPE is \"SCHEDULED\" or \"DEADLINE\".  Every control dispatches the
ordinary planning actions with a (dialog . TYPE) marker, and those
handlers re-send this dialog after the write so the values on screen
stay live."
  (let* ((marker (jetpacs-org-resolve-ref ref))
         (info (with-current-buffer (marker-buffer marker)
                 (org-with-wide-buffer
                  (goto-char marker)
                  (list (org-get-heading t t t t)
                        (org-entry-get nil type)))))
         (headline (nth 0 info))
         (ts (nth 1 info))
         (date (glasspane-ui--ts-date ts))
         (time (glasspane-ui--ts-time ts))
         (rep (glasspane-ui--ts-repeater ts))
         (scheduled-p (equal type "SCHEDULED"))
         (set-name (if scheduled-p "heading.schedule" "heading.deadline"))
         (mark `(dialog . ,type))
         (when-chip
          (lambda (label when)
            (jetpacs-button label
                         (jetpacs-action set-name
                                      :args (append (list mark `(when . ,when)) ref)
                                      :when-offline "queue")
                         :variant "outlined"))))
    (jetpacs-send-dialog
     (jetpacs-scroll-column
      (jetpacs-text (if scheduled-p "Edit schedule" "Edit deadline") 'title)
      (jetpacs-text headline 'caption)
      (jetpacs-row
       (jetpacs-date-button (or date "Set date")
                         (jetpacs-action set-name :args (cons mark ref))
                         :value date)
       (jetpacs-time-button (or time "Set time")
                         (jetpacs-action (if scheduled-p "heading.schedule-time"
                                        "heading.deadline-time")
                                      :args (cons mark ref))
                         :value time))
      (apply #'jetpacs-flow-row
             (mapcar (lambda (pair) (funcall when-chip (car pair) (cdr pair)))
                     '(("Today" . "+0d") ("+1d" . "+1d")
                       ("+1w" . "+1w") ("+1m" . "+1m"))))
      (jetpacs-text "Repeat" 'label)
      (jetpacs-enum-list (format "planning-rep/%s" type)
                      glasspane-ui--repeater-choices
                      :value (list (or rep "none"))
                      :on-change (jetpacs-action "heading.repeater"
                                              :args (append (list mark `(type . ,type)) ref)))
      (jetpacs-row
       (jetpacs-button "Clear"
                    (jetpacs-action set-name
                                 :args (append (list mark '(clear . t)) ref))
                    :variant "text")
       (jetpacs-spacer :weight 1)
       (jetpacs-button "Done" (jetpacs-action "dialog.dismiss") :variant "text"))))))

(defun glasspane-ui--planning-dialog-resend (args &optional type)
  "Re-send the planning dialog when ARGS carry the (dialog . TYPE) marker."
  (when-let ((marked (alist-get 'dialog args)))
    (ignore-errors
      (glasspane-ui--planning-dialog
       args (or type (and (stringp marked) marked) "SCHEDULED")))))

;; ─── Action Handlers ─────────────────────────────────────────────────────────

(defun glasspane-ui--add-heading (args child)
  "Bridged title prompt, then insert a heading at ARGS's ref.
CHILD non-nil nests one level under the ref heading at the end of its
subtree; otherwise the new heading follows the subtree as a sibling.
On a file-level note (no heading to hang off) both land top-level at
the end of the file."
  (let ((title (string-trim (condition-case nil
                                (read-string "New heading: ")
                              (quit "")))))
    (if (string-empty-p title)
        (jetpacs-shell-notify "Heading cancelled")
      (when (glasspane-ui--at-ref
             args
             (lambda ()
               (if (org-before-first-heading-p)
                   (progn (goto-char (point-max))
                          (unless (bolp) (insert "\n"))
                          (insert "* " title "\n"))
                 (let ((level (org-current-level)))
                   (org-end-of-subtree t t)
                   (unless (bolp) (insert "\n"))
                   (insert (make-string (if child (1+ level) level) ?*)
                           " " title "\n"))))
             t)
        (jetpacs-shell-notify (format "Added \"%s\"" title))))
    (jetpacs-shell-push)))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "heading.tap"
    (lambda (args _)
      ;; ARGS is the ref alist (id/file/pos/headline) the card embedded.
      ;; This push IS the navigation, so it forces the detail view.
      (setq glasspane-ui--detail-ref args)
      (setq glasspane-ui--detail-read-mode t)
      (jetpacs-shell-push nil :switch-to "glasspane.detail"))
    :doc "Open a heading in the detail view."
    :args '((:name ref :type "ref" :required t)))

  (jetpacs-defaction "detail.toggle-read"
    (lambda (_ _)
      (setq glasspane-ui--detail-read-mode (not glasspane-ui--detail-read-mode))
      (jetpacs-shell-push nil :switch-to "glasspane.detail")))

  (jetpacs-defaction "detail.save"
    (lambda (args _)
      (let ((ref (alist-get 'ref args))
            (value (alist-get 'value args)))
        (when (and ref value)
          (condition-case err
              (let* ((marker (jetpacs-org-resolve-ref ref))
                     (buf (marker-buffer marker))
                     (pos (marker-position marker)))
                (with-current-buffer buf
                  (org-with-wide-buffer
                   (goto-char pos)
                   (org-mark-subtree)
                   (delete-region (region-beginning) (region-end))
                   (insert value)
                   (goto-char pos)
                   (setq glasspane-ui--detail-ref (jetpacs-org-heading-ref))
                   (glasspane-org--save-and-invalidate)))
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

  (jetpacs-defaction "heading.todo-set"
    (lambda (args _)
      (let* ((state (alist-get 'state args))
             (clear (equal state "")))
        (when (and state
                   (glasspane-ui--at-ref args (lambda () (org-todo (if clear 'none state))) t))
          (jetpacs-shell-notify (if clear "State cleared" (format "State → %s" state)))
          (jetpacs-shell-push))))
    :doc "Set a heading's TODO state; an empty state clears it."
    :args '((:name ref :type "ref" :required t)
            (:name state :type "text" :required t)))

  (jetpacs-defaction "heading.todo-cycle"
    (lambda (args _)
      (when (glasspane-ui--at-ref args
                                  (lambda ()
                                    (org-todo)
                                    (unless (org-get-todo-state)
                                      (org-todo)))
                                  t)
        (let* ((marker (jetpacs-org-resolve-ref args))
               (state (with-current-buffer (marker-buffer marker)
                        (org-with-wide-buffer
                         (goto-char marker)
                         (org-get-todo-state)))))
          (jetpacs-shell-notify (if state (format "State → %s" state) "State cleared"))
          (jetpacs-shell-push))))
    :doc "Cycle a heading through the TODO keyword sequence."
    :args '((:name ref :type "ref" :required t)))

  (jetpacs-defaction "heading.schedule"
    (lambda (args _)
      ;; CLEAR removes the timestamp; otherwise WHEN (relative, e.g. "+1d") or
      ;; VALUE (concrete "YYYY-MM-DD", from the date picker) sets it.  With
      ;; neither, a bridged `org-read-date' dialog asks — the overflow-menu
      ;; path ("+2d", "fri", a concrete date all work).
      (let* ((clear (alist-get 'clear args))
             (date (or (alist-get 'when args) (alist-get 'value args)))
             (prompted (and (not clear)
                            (or (null date) (string-empty-p date)))))
        (when prompted
          (setq date (condition-case nil (org-read-date)
                       (quit nil))))
        (cond
         ((and prompted (null date))
          (jetpacs-shell-notify "Schedule cancelled")
          (jetpacs-shell-push))
         ((cond
           (clear (glasspane-ui--at-ref args (lambda () (org-schedule '(4))) t))
           ((and (stringp date) (not (string-empty-p date)))
            (glasspane-ui--at-ref args (lambda () (org-schedule nil date)) t)))
          (jetpacs-shell-notify (if clear "Schedule cleared" (format "Scheduled %s" date)))
          (glasspane-ui--planning-dialog-resend args "SCHEDULED")
          (jetpacs-shell-push)))))
    :doc "Schedule a heading (WHEN relative like \"+1d\", VALUE a date, CLEAR, or a bridged prompt with neither)."
    :args '((:name ref :type "ref" :required t)
            (:name when :type "text")
            (:name value :type "date")
            (:name clear :type "bool")))

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
          (glasspane-ui--planning-dialog-resend args "SCHEDULED")
          (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.deadline-time"
    ;; The deadline sibling of heading.schedule-time, for the dialog's
    ;; time picker.
    (lambda (args _)
      (let ((time (alist-get 'value args)))
        (when (and (stringp time) (not (string-empty-p time))
                   (glasspane-ui--at-ref
                    args
                    (lambda ()
                      (let* ((dl (org-entry-get nil "DEADLINE"))
                             (date (or (glasspane-ui--ts-date dl)
                                       (format-time-string "%Y-%m-%d"))))
                        (org-deadline nil (format "%s %s" date time))))
                    t))
          (jetpacs-shell-notify (format "Deadline %s" time))
          (glasspane-ui--planning-dialog-resend args "DEADLINE")
          (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.repeater"
    ;; VALUE from the dialog's enum ("none" removes); rewrites the
    ;; repeater cookie in place, preserving the date and time.
    (lambda (args _)
      (let* ((type (or (alist-get 'type args) "SCHEDULED"))
             (raw (alist-get 'value args))
             (value (cond
                     ((vectorp raw) (if (> (length raw) 0) (aref raw 0) "none"))
                     ((and (listp raw) raw) (car raw))
                     ((stringp raw) raw)
                     (t "none")))
             (value (unless (equal value "none") value)))
        (when (glasspane-ui--at-ref
               args (lambda () (glasspane-ui--set-repeater type value)) t)
          (jetpacs-shell-notify (if value (format "Repeats %s" value)
                                  "Repeat removed"))
          (glasspane-ui--planning-dialog-resend args type)
          (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.planning.show"
    ;; The structured Scheduled/Deadline editor (the overflow-menu path).
    (lambda (args _)
      (condition-case err
          (glasspane-ui--planning-dialog
           args (or (alist-get 'type args) "SCHEDULED"))
        (error
         (jetpacs-shell-notify (format "Planning: %s" (error-message-string err)))
         (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.deadline"
    (lambda (args _)
      ;; Mirrors heading.schedule, including the bridged prompt when no
      ;; date arrives on the wire.
      (let* ((clear (alist-get 'clear args))
             (date (or (alist-get 'when args) (alist-get 'value args)))
             (prompted (and (not clear)
                            (or (null date) (string-empty-p date)))))
        (when prompted
          (setq date (condition-case nil (org-read-date)
                       (quit nil))))
        (cond
         ((and prompted (null date))
          (jetpacs-shell-notify "Deadline cancelled")
          (jetpacs-shell-push))
         ((cond
           (clear (glasspane-ui--at-ref args (lambda () (org-deadline '(4))) t))
           ((and (stringp date) (not (string-empty-p date)))
            (glasspane-ui--at-ref args (lambda () (org-deadline nil date)) t)))
          (jetpacs-shell-notify (if clear "Deadline cleared" (format "Deadline %s" date)))
          (glasspane-ui--planning-dialog-resend args "DEADLINE")
          (jetpacs-shell-push))))))

  (jetpacs-defaction "heading.priority"
    (lambda (args _)
      ;; Empty VALUE means None (remove); otherwise the first char is the
      ;; priority.  ASK (the overflow-menu path) prompts through the bridge
      ;; instead of clearing on the missing value.
      (let* ((val (alist-get 'value args))
             (cancelled nil))
        (when (and (alist-get 'ask args) (null val))
          (setq val (condition-case nil
                        (upcase (string-trim
                                 (read-string "Priority (letter, empty for none): ")))
                      (quit (setq cancelled t) nil))))
        (if cancelled
            (progn (jetpacs-shell-notify "Priority cancelled")
                   (jetpacs-shell-push))
          (let* ((remove (or (null val) (string-empty-p val)))
                 (ok (glasspane-ui--at-ref
                      args
                      (lambda ()
                        (if remove (org-priority 'remove)
                          (org-priority (string-to-char val))))
                      t)))
            (when ok
              (jetpacs-shell-notify (if remove "Priority cleared"
                                      (format "Priority %s" val)))
              (jetpacs-shell-push)))))))

  (jetpacs-defaction "heading.refile"
    ;; Bridged picker over org-refile targets; refiles the whole subtree.
    (lambda (args _)
      (condition-case err
          (let ((marker (jetpacs-org-resolve-ref args)))
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
                   (glasspane-org--vulpea-refresh-file)
                   (jetpacs-org-cache-invalidate 'glasspane)
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
                     (org-save-all-org-buffers))
                   (glasspane-org--vulpea-refresh-file)))
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

  (jetpacs-defaction "heading.delete"
    ;; Bridged y/n confirm, then the subtree is deleted outright —
    ;; Archive is the recoverable path; this one is for genuine junk.
    (lambda (args _)
      (let ((headline (or (alist-get 'headline args) "this heading")))
        (if (not (yes-or-no-p (format "Delete \"%s\" and its subtree? " headline)))
            (jetpacs-shell-notify "Delete cancelled")
          (when (glasspane-ui--at-ref
                 args
                 (lambda ()
                   (delete-region (point)
                                  (progn (org-end-of-subtree t t) (point))))
                 t)
            (setq glasspane-ui--detail-ref nil)
            (jetpacs-shell-notify "Deleted")))
        (jetpacs-shell-push nil :switch-to (jetpacs-shell-current-tab)))))

  (jetpacs-defaction "heading.duplicate"
    ;; Copy the whole subtree and insert it right after itself — the
    ;; recurring-meeting-notes idiom (organice's Duplicate).
    (lambda (args _)
      (when (glasspane-ui--at-ref
             args
             (lambda ()
               (let ((subtree (buffer-substring-no-properties
                               (point)
                               (save-excursion (org-end-of-subtree t t) (point)))))
                 (org-end-of-subtree t t)
                 (unless (bolp) (insert "\n"))
                 (insert subtree)))
             t)
        (jetpacs-shell-notify "Duplicated")
        (jetpacs-shell-push))))

  (jetpacs-defaction "heading.add-heading"
    ;; Bridged prompt for the title; the new heading lands as a child at
    ;; the end of this subtree (or top-level at the end of a file-level
    ;; note, where there is no subtree to nest under).
    (lambda (args _) (glasspane-ui--add-heading args t)))

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

  (jetpacs-defaction "heading.props.show"
    ;; The sub-heading Properties dialog: the detail reader hides the
    ;; inline drawer, and this overflow-menu action surfaces it as
    ;; editable rows through the same heading.prop-set funnel.
    (lambda (args _)
      (condition-case err
          (let* ((marker (jetpacs-org-resolve-ref args))
                 (buf (marker-buffer marker))
                 (pos (marker-position marker))
                 (info (with-current-buffer buf
                         (org-with-wide-buffer
                          (goto-char pos)
                          (list (org-get-heading t t t t)
                                (org-entry-properties nil 'standard)
                                (buffer-file-name)))))
                 (headline (nth 0 info))
                 (props (nth 1 info))
                 (ref `((file . ,(nth 2 info)) (pos . ,pos)
                        (headline . ,headline))))
            (jetpacs-send-dialog
             (apply #'jetpacs-scroll-column
                    (delq nil
                     (append
                     (list (jetpacs-text "Properties" 'title)
                           (jetpacs-text headline 'caption))
                     (or (mapcar (lambda (kv)
                                   (glasspane-ui--property-row
                                    (car kv) (or (cdr kv) "") ref pos))
                                 props)
                         (list (jetpacs-text "No properties yet." 'caption)))
                     (list
                      (when props
                        (jetpacs-text "Submit an empty value to remove a property."
                                   'caption))
                      (jetpacs-row
                       (jetpacs-button "+ Add property"
                                    (jetpacs-action "heading.prop-add" :args ref)
                                    :variant "text")
                       (jetpacs-spacer :weight 1)
                       (jetpacs-button "Close" (jetpacs-action "dialog.dismiss")
                                    :variant "text"))))))))
        (error
         (jetpacs-shell-notify (format "Properties: %s" (error-message-string err)))
         (jetpacs-shell-push)))))

  (jetpacs-defaction "heading.tags"
    (lambda (args _)
      ;; VALUE arrives from the tag enum-list; ASK (the overflow-menu path)
      ;; prompts through the bridged completing-read-multiple, prefilled
      ;; with the heading's current local tags.
      (let* ((val (alist-get 'value args))
             (cancelled nil))
        (when (and (alist-get 'ask args) (null val))
          (let ((current (condition-case nil
                             (let ((m (jetpacs-org-resolve-ref args)))
                               (with-current-buffer (marker-buffer m)
                                 (org-with-wide-buffer
                                  (goto-char m)
                                  (org-get-tags nil t))))
                           (error nil)))
                (candidates (seq-filter #'stringp
                                        (mapcar (lambda (x) (if (consp x) (car x) x))
                                                org-tag-alist))))
            (setq val (condition-case nil
                          (completing-read-multiple
                           "Tags: " candidates nil nil
                           (when current (concat (string-join current ",") ",")))
                        (quit (setq cancelled t) nil)))))
        (if cancelled
            (progn (jetpacs-shell-notify "Tags cancelled")
                   (jetpacs-shell-push))
          (let* ((tags (cond
                        ((vectorp val) (append val nil))
                        ((listp val) val)
                        ((stringp val) (split-string val "[ \t:,]+" t))
                        (t nil)))
                 (ok (glasspane-ui--at-ref args (lambda () (org-set-tags tags)) t)))
            (when ok
              (jetpacs-shell-notify (if tags (format "Tags: %s" (string-join tags " "))
                                      "Tags cleared"))
              (jetpacs-shell-push)))))))

  (jetpacs-defaction "heading.clock-in"
    (lambda (args _)
      (when (glasspane-ui--at-ref args #'org-clock-in)
        (jetpacs-shell-notify "Clocked in")
        (jetpacs-shell-push "clock"))))

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
                    (setq glasspane-ui--detail-ref (jetpacs-org-heading-ref))
                    (setq glasspane-ui--detail-read-mode t)
                    (setq navigated t)))
              (error
               (jetpacs-shell-notify
                (format "Couldn't open %s: %s" link (error-message-string err)))))
            (if navigated
                (jetpacs-shell-push nil :switch-to "glasspane.detail")
              (jetpacs-shell-push)))))))

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
          (glasspane-org--save-and-invalidate (find-file-noselect file))
          ;; Views-originated drags pass `view' to land back where the
          ;; drag happened; legacy templates (no arg) keep the editor.
          (jetpacs-shell-push nil :switch-to (or (alist-get 'view args) "edit")))))))

(defun glasspane-ui--org-editor-actions (file)
  "Reader/refile toggles, add-heading, and the properties dialog for org FILE."
  (when (glasspane-ui--org-file-p file)
    (delq nil
          (list
           (when glasspane-ui--files-read-mode
             (jetpacs-icon-button
              "post_add"
              (jetpacs-action "file.add-heading" :args `((file . ,file))
                           :when-offline "drop")
              :content-description "Add Heading"))
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

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "file.add-heading"
    ;; The file-view sibling of heading.add-heading: bridged title
    ;; prompt, then a top-level heading appended at the end of FILE.
    (lambda (args _)
      (let ((file (alist-get 'file args)))
        (if (not (and (stringp file) (file-writable-p file)))
            (jetpacs-shell-notify "Can't add a heading — file not writable")
          (let ((title (string-trim (condition-case nil
                                        (read-string "New heading: ")
                                      (quit "")))))
            (if (string-empty-p title)
                (jetpacs-shell-notify "Heading cancelled")
              (with-current-buffer (find-file-noselect file)
                (org-with-wide-buffer
                 (goto-char (point-max))
                 (unless (bolp) (insert "\n"))
                 (insert "* " title "\n"))
                (glasspane-org--save-and-invalidate))
              (jetpacs-shell-notify (format "Added \"%s\"" title)))))
        (jetpacs-shell-push))))

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
              (glasspane-org--save-and-invalidate))))
        (jetpacs-dismiss-dialog)
        (jetpacs-shell-push)))))

(provide 'glasspane-detail)

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-search.el
;;; ==================================================================

;;; glasspane-search.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

;; (require 'glasspane-ui) — bundle-internal, provided above

(defvar glasspane-ui--search-query ""
  "Last submitted query for the Search view.")

(defvar glasspane-ui--search-results nil
  "Cached heading items from the last search.")

(defvar glasspane-ui--search-error nil
  "Human-readable message when the last search query failed, else nil.")

(defun glasspane-ui--search-view (snackbar)
  (jetpacs-shell-nav-view "Search" (glasspane-ui--search-body)
                       :snackbar snackbar))

(with-jetpacs-owner "glasspane"
  (jetpacs-shell-define-view "glasspane.search" :builder #'glasspane-ui--search-view
                          :order 70))

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
  ;; Deliberately raw `jetpacs-ui-state', not a `jetpacs-form': the
  ;; search-filter-* ids are stable identities whose values must persist
  ;; across pushes and view switches (that persistence IS the feature —
  ;; the section summaries and search.clear-filters' prefix clear depend
  ;; on it), and every render re-seeds the widgets with an explicit
  ;; :value, so the device-side staleness that form gen-rotation cures
  ;; cannot occur here.
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

(with-jetpacs-owner "glasspane"
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
      (jetpacs-shell-push nil :switch-to "glasspane.search"))
    :doc "Filter search to a single tag."
    :args '((:name tag :type "text" :required t))))

(provide 'glasspane-search)

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-table.el
;;; ==================================================================

;;; glasspane-table.el --- Glasspane UI component -*- lexical-binding: t; -*-
;;; Code:

;; (require 'glasspane-ui) — bundle-internal, provided above

(with-jetpacs-owner "glasspane"
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
        (jetpacs-shell-push)))))

;; The org settings exposed to the companion, through the generic
;; schema-driven machinery (the registry is the security boundary:
;; only symbols listed here can be modified from the wire).  Registered
;; under the app's owner id, so coexisting apps' settings never
;; interleave: these sections render only while Glasspane is current.
(with-jetpacs-owner "glasspane"
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
  (jetpacs-settings-register-section
   "Appearance"
   '((jetpacs-dialog-style :label "Dialog presentation"))))

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
    (glasspane-org--save-and-invalidate))
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

(with-jetpacs-owner "glasspane"
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
                  (glasspane-org--save-and-invalidate))
                (jetpacs-shell-notify "Block executed")
                (jetpacs-shell-push))
            (error
             (jetpacs-shell-notify
              (format "Run failed: %s" (error-message-string err)))
             (jetpacs-shell-push))))))))

(provide 'glasspane-table)

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-journal.el
;;; ==================================================================

;;; glasspane-journal.el --- Daily-note landing surface -*- lexical-binding: t; -*-

;; The Logseq bootstrapping habit, org-native (PKM plan Task 5): open
;; the app → today's page, ready to type.  A `journal' tab renders one
;; datetree day at a time — capture row on top, the day's content
;; through the foldable reader, and (on today) a "Carried over" section
;; of unfinished TODOs scheduled before today with one-tap reschedule.
;;
;; Engine decision: plain `org-datetree' (builtin, standard, importable
;; — the file layout every journal tool understands).  vulpea-journal
;; gets evaluated when the vulpea spike runs on device (PKM Task 1);
;; the seam is `glasspane-journal--append' / `--day-pos', one code path
;; either way.
;;
;; The journal file defaults to journal.org in `org-directory' — no new
;; layout invented, nothing seeded until the first capture creates the
;; datetree.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-datetree)
(require 'jetpacs)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-shell)
(require 'jetpacs-settings)
;; (require 'glasspane-org) — bundle-internal, provided above
;; (require 'glasspane-org-reader) — bundle-internal, provided above
;; (require 'glasspane-ui)                ; date helpers + the glasspane defapp — bundle-internal, provided above

(defcustom glasspane-journal-file nil
  "The journal file holding the datetree.
nil means journal.org inside `org-directory'."
  :type '(choice (const :tag "journal.org in org-directory" nil) file)
  :group 'jetpacs)

(defcustom glasspane-journal-landing nil
  "When non-nil the app opens on the Journal view instead of Agenda."
  :type 'boolean :group 'jetpacs)

(defvar glasspane-journal--date nil
  "The day being viewed (\"YYYY-MM-DD\"), or nil for today.")

(defun glasspane-journal--capture-form ()
  "The capture row's field registry (`jetpacs-form').
Reset after each append: rotating the field id is the server-driven
way to clear the input field."
  (jetpacs-form "journal" "glasspane"))

(defun glasspane-journal--file ()
  "The journal file path."
  (or glasspane-journal-file
      (expand-file-name "journal.org" org-directory)))

(defun glasspane-journal--today ()
  (format-time-string "%Y-%m-%d"))

(defun glasspane-journal--current ()
  "The date the view shows."
  (or glasspane-journal--date (glasspane-journal--today)))

;; ─── The datetree seam ───────────────────────────────────────────────────────

(defun glasspane-journal--day-pos (date)
  "Position of DATE's day heading in the journal file, or nil.
Datetree day headings read \"*** 2026-07-05 Saturday\"; the full
Y-m-d makes the match unambiguous against month/year levels."
  (let ((file (glasspane-journal--file)))
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (goto-char (point-min))
         (when (re-search-forward
                (format "^\\*+[ \t]+%s\\(?:[ \t]\\|$\\)" (regexp-quote date))
                nil t)
           (line-beginning-position)))))))

(defun glasspane-journal--append (text &optional date)
  "Append TEXT as a plain list item under DATE's (default today) day.
Creates the datetree levels (and the file) on first use."
  (let ((date (or date (glasspane-journal--today)))
        (file (glasspane-journal--file)))
    (pcase-let ((`(,y ,m ,d) (mapcar #'string-to-number
                                     (split-string date "-"))))
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-datetree-find-date-create (list m d y))
         (org-back-to-heading t)
         (org-end-of-subtree t t)
         (unless (bolp) (insert "\n"))
         (insert "- " text "\n"))
        (glasspane-org--save-and-invalidate)))))

(defun glasspane-journal--carried-over ()
  "Unfinished TODOs scheduled before today — the carry-over list."
  (glasspane-org--query '(and (todo) (scheduled :to -1))))

;; ─── The view ────────────────────────────────────────────────────────────────

(defun glasspane-journal--nav-row (date today-p)
  "‹ yesterday | the day (a native date picker) | tomorrow › chrome."
  (apply #'jetpacs-row
         (delq nil
               (list
                (jetpacs-icon-button
                 "chevron_left"
                 (jetpacs-action "journal.nav" :args '((delta . -1))
                              :when-offline "drop")
                 :content-description "Previous day")
                (jetpacs-box
                 (list (jetpacs-date-button
                        (glasspane-ui--format-date
                         date (if today-p "Today · %a, %b %e" "%a, %b %e, %Y"))
                        (jetpacs-action "journal.goto" :when-offline "drop")
                        :value date))
                 :weight 1 :alignment "center")
                (unless today-p
                  (jetpacs-chip "Today"
                             :on-tap (jetpacs-action "journal.today"
                                                  :when-offline "drop")))
                (jetpacs-icon-button
                 "chevron_right"
                 (jetpacs-action "journal.nav" :args '((delta . 1))
                              :when-offline "drop")
                 :content-description "Next day")))))

(defun glasspane-journal--capture-row (date)
  "The always-on-top quick-capture input for DATE."
  (jetpacs-text-input
   (jetpacs-form-field-id (glasspane-journal--capture-form) "capture")
   :hint "Add to this day…"
   :single-line t
   :on-submit (jetpacs-action "journal.capture"
                           :args `((date . ,date))
                           :when-offline "queue")))

(defun glasspane-journal--day-nodes (date)
  "DATE's datetree content through the foldable reader, or a placeholder."
  (or (when-let ((pos (glasspane-journal--day-pos date)))
        (glasspane-org-reader-subtree (glasspane-journal--file) pos t))
      (list (jetpacs-text "Nothing here yet — the row above starts the day."
                       'caption))))

(defun glasspane-journal--carried-card (item)
  "One carried-over TODO with one-tap reschedule.
The buttons ride the existing allowlisted `heading.schedule' — the
orgro timestamp-tap-edit item folds in here."
  (let ((ref (alist-get 'ref item)))
    (jetpacs-card
     (list
      (jetpacs-column
       (jetpacs-text (or (alist-get 'headline item) "") 'body)
       (jetpacs-text (format "%s · %s"
                          (or (alist-get 'todo item) "TODO")
                          (or (alist-get 'scheduled item) ""))
                  'caption)
       (jetpacs-row
        (jetpacs-spacer :weight 1)
        (jetpacs-button "Today"
                     (jetpacs-action "heading.schedule"
                                  :args (append ref '((when . "+0d")))
                                  :when-offline "queue")
                     :variant "text")
        (jetpacs-date-button "Pick"
                          (jetpacs-action "heading.schedule"
                                       :args ref
                                       :when-offline "queue"))))))))

(defun glasspane-journal--view (snackbar)
  "The journal screen for the current date."
  (let* ((date (glasspane-journal--current))
         (today-p (equal date (glasspane-journal--today)))
         ;; A broken query must cost the section, not the day.
         (carried (and today-p
                       (condition-case nil
                           (glasspane-journal--carried-over)
                         (error nil)))))
    (jetpacs-shell-tab-view
     "glasspane.journal"
     (apply #'jetpacs-lazy-column
            (append
             (list (glasspane-journal--nav-row date today-p)
                   (glasspane-journal--capture-row date)
                   (jetpacs-spacer :height 4))
             (glasspane-journal--day-nodes date)
             (when carried
               (append
                (list (jetpacs-divider)
                      (jetpacs-section-header
                       (format "Carried over (%d)" (length carried))))
                (mapcar #'glasspane-journal--carried-card carried)))
             ;; The clock rides the journal (its own tab felt barren and
             ;; crowded the bottom bar) — today's time is journal matter.
             (when (and today-p (fboundp 'glasspane-ui--clock-body))
               (list (jetpacs-divider)
                     (jetpacs-section-header "Clock")
                     (glasspane-ui--clock-body)))))
     :snackbar snackbar)))

(with-jetpacs-owner "glasspane"
  (jetpacs-shell-define-view "glasspane.journal"
                          :builder #'glasspane-journal--view
                          :tab '(:icon "today" :label "Journal")
                          :order 15))

;; ─── Landing & state resets ──────────────────────────────────────────────────

(defun glasspane-journal--apply-landing (_welcome)
  "Land on the journal when configured and no tab was chosen this session.
Depth 5: before the shell's on-connect push (10) builds the surface.

This deliberately reads and seeds the internal `jetpacs-shell--current-tab'
rather than the promoted `jetpacs-shell-current-tab' / -set-current-tab
seams: the public getter falls back to the first registered tab (so it can
never report \"no tab chosen\"), and the public setter routes through
`jetpacs-shell-push' — which at connect depth 5 would fire a premature push
and the view-switched hook before the depth-10 push builds the surface.
A public \"is a tab explicitly set / seed without pushing\" accessor does
not exist in jetpacs 1.5.0; until it does, this seam stays on the raw var."
  (when (and glasspane-journal-landing (null jetpacs-shell--current-tab))
    (setq jetpacs-shell--current-tab "glasspane.journal")))

(add-hook 'jetpacs-connected-hook #'glasspane-journal--apply-landing 5)

(defun glasspane-journal--on-view-switched (view)
  "Leaving the journal resets it to today — returning starts fresh."
  (unless (equal view "glasspane.journal")
    (setq glasspane-journal--date nil)))

(add-hook 'jetpacs-shell-view-switched-hook #'glasspane-journal--on-view-switched)

(with-jetpacs-owner "glasspane"
  (jetpacs-settings-register-section
   "Journal"
   '((glasspane-journal-landing :label "Open on the journal"))))

;; ─── Actions ─────────────────────────────────────────────────────────────────

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "journal.nav"
    (lambda (args _)
      (let ((delta (alist-get 'delta args)))
        (when (integerp delta)
          (setq glasspane-journal--date
                (glasspane-ui--shift-date (glasspane-journal--current)
                                          delta 'day))
          (jetpacs-shell-push)))))

  (jetpacs-defaction "journal.goto"
    (lambda (args _)
      (let ((date (alist-get 'value args)))
        (when (and (stringp date)
                   (string-match-p
                    "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" date))
          (setq glasspane-journal--date date)
          (jetpacs-shell-push)))))

  (jetpacs-defaction "journal.today"
    (lambda (_args _)
      (setq glasspane-journal--date nil)
      (jetpacs-shell-push)))

  (jetpacs-defaction "journal.capture"
    (lambda (args _)
      (let ((text (string-trim (or (alist-get 'value args) "")))
            (date (alist-get 'date args)))
        (unless (string-empty-p text)
          (glasspane-journal--append
           text (and (stringp date) (not (string-empty-p date)) date))
          ;; Rotate the input id: the re-render clears the field.
          (jetpacs-form-reset (glasspane-journal--capture-form))
          (jetpacs-shell-notify "Added to journal")
          (jetpacs-shell-push))))
    :doc "Append text to the current journal day."
    :args '((:name value :type "text" :required t)
            (:name date :type "date"))))

(provide 'glasspane-journal)
;;; glasspane-journal.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-views.el
;;; ==================================================================

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
;; (require 'glasspane-org) — bundle-internal, provided above
;; (require 'glasspane-ui) — bundle-internal, provided above
;; (require 'glasspane-agenda)             ; date helpers + the month fallback grid — bundle-internal, provided above

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

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-automations.el
;;; ==================================================================

;;; glasspane-automations.el --- Automations as literate org -*- lexical-binding: t; -*-

;; Automation plan Task 13: rules live in an org file — readable,
;; editable on the phone with the org editor that already exists,
;; version-controllable.  One heading per rule:
;;
;;   * Charge sync
;;   :PROPERTIES:
;;   :TRIGGER: power connected
;;   :POLICY: wake
;;   :THROTTLE: 300
;;   :END:
;;   #+begin_src elisp
;;   (my/org-sync)
;;   #+end_src
;;
;; The drawer holds the wire fields (a shorthand `:TRIGGER:', raw
;; `:PARAMS:'/`:ON_FIRE:' for anything richer); the body's first elisp
;; src block is the handler, evaluated with `data' and `args' in scope.
;; Marking the heading DONE removes the rule from the pushed set — org
;; semantics as the enable switch.
;;
;; TRUST BOUNDARY: the src blocks are user-authored code from the
;; user's own file, the same trust as init.el.  This file must only
;; ever be loaded from the local `org-directory' — never from anything
;; that arrived over the wire or the share sheet.
;;
;; Property drawers are case-insensitive per the org case conventions
;; (org-element normalizes keys; the ERT suite pins a lowercase
;; drawer).  TODO keywords stay case-sensitive.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-element)
(require 'jetpacs)
(require 'jetpacs-triggers)
(require 'jetpacs-shell)
;; (require 'glasspane-org) — bundle-internal, provided above

(defcustom glasspane-automations-file nil
  "The org file holding trigger rules.
nil means automations.org inside `org-directory'."
  :type '(choice (const :tag "automations.org in org-directory" nil) file)
  :group 'jetpacs)

(defvar glasspane-automations--ids nil
  "Trigger ids registered from the org file (replaced on each reload).")

(defun glasspane-automations--file ()
  (or glasspane-automations-file
      (expand-file-name "automations.org" org-directory)))

;; ─── Parsing ─────────────────────────────────────────────────────────────────

(defconst glasspane-automations--types jetpacs-triggers-supported-types
  "Trigger types rules may use — the shipped SPEC §11 catalog.
An unknown type would make the companion reject the whole replace-set
\(and `jetpacs-triggers--specs' skips it as a second line of defense), so
unknown rules are caught at parse time with a message naming the rule.
Notably NOT here yet: wifi.ssid / bluetooth.device — hardware-gated,
see the automation plan.")

(defun glasspane-automations--parse-trigger (str)
  "Parse the `:TRIGGER:' shorthand STR into (TYPE . PARAMS).
Grammar: the first token names the type; the rest is per-type sugar —
\"power connected\", \"screen off\", \"battery.level below 20\",
\"time every 3600\", \"package added com.example\".  Anything richer
goes in `:PARAMS:'.  Returns nil for an empty or unknown-type string."
  (pcase-let* ((tokens (split-string (or str "") "[ \t]+" t))
               (`(,type . ,rest) tokens))
    (when (and type (member type glasspane-automations--types))
      (cons type
            (pcase type
              ((or "power" "screen" "headset" "airplane")
               (when (car rest) `((state . ,(car rest)))))
              ("battery.level"
               (pcase rest
                 (`("below" ,n) `((below . ,(string-to-number n))))
                 (`("above" ,n) `((above . ,(string-to-number n))))))
              ("time"
               (pcase rest
                 (`("every" ,s) `((every_s . ,(string-to-number s))))
                 (`("at" ,ms) `((at_ms . ,(string-to-number ms))))))
              ("package"
               (append (when (car rest) `((event . ,(car rest))))
                       (when (cadr rest) `((package . ,(cadr rest))))))
              (_ nil))))))

(defun glasspane-automations--read (str)
  "Read STR as one elisp datum, or nil when STR is nil/empty.
For `:PARAMS:' / `:ON_FIRE:' — data from the user's own file."
  (when (and (stringp str) (not (string-empty-p (string-trim str))))
    (car (read-from-string str))))

(defun glasspane-automations--handler (src headline)
  "Build the rule handler from SRC, the elisp block body.
The forms run with `data' and `args' bound to the fire payload.  Same
trust as init.el — see the file header."
  (condition-case err
      (eval `(lambda (data args)
               (ignore data args)
               ,(car (read-from-string (format "(progn %s)" src))))
            t)
    (error
     (message "Jetpacs automations: bad handler in %S: %s"
              headline (error-message-string err))
     nil)))

(defun glasspane-automations--rules ()
  "Parse the automations file into registration plists.
A rule = a headline with a `:TRIGGER:' property that is not DONE."
  (let ((file (glasspane-automations--file))
        rules)
    (when (file-readable-p file)
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-element-map (org-element-parse-buffer) 'headline
           (lambda (hl)
             (when-let ((trigger (org-element-property :TRIGGER hl)))
               (let* ((headline (org-element-property :raw-value hl))
                      (done (eq (org-element-property :todo-type hl) 'done))
                      (parsed (glasspane-automations--parse-trigger trigger)))
                 (cond
                  (done nil)            ; org semantics as the enable switch
                  ((null parsed)
                   (message "Jetpacs automations: skipping %S — unknown trigger %S"
                            headline trigger))
                  (t
                   (let* ((src (car (org-element-map hl 'src-block
                                      (lambda (blk)
                                        (when (member (downcase
                                                       (or (org-element-property
                                                            :language blk)
                                                           ""))
                                                      '("elisp" "emacs-lisp"))
                                          (org-element-property :value blk))))))
                          (params (or (glasspane-automations--read
                                       (org-element-property :PARAMS hl))
                                      (cdr parsed))))
                     (push (list :id (format "org/%s" headline)
                                 :type (car parsed)
                                 :params params
                                 :policy (org-element-property :POLICY hl)
                                 :dedupe (org-element-property :DEDUPE hl)
                                 :throttle-s
                                 (when-let ((th (org-element-property
                                                 :THROTTLE hl)))
                                   (string-to-number th))
                                 :on-fire (glasspane-automations--read
                                           (org-element-property :ON_FIRE hl))
                                 :handler (when src
                                            (glasspane-automations--handler
                                             src headline)))
                           rules)))))))))))
    (nreverse rules)))

;; ─── Loading ─────────────────────────────────────────────────────────────────

(defun glasspane-automations-reload ()
  "Re-read the automations file and replace the org-defined triggers.
Previously org-defined ids not in the file anymore are unregistered —
the file is the source of truth for the `org/' id namespace."
  (interactive)
  (let* ((rules (glasspane-automations--rules))
         (ids (mapcar (lambda (r) (plist-get r :id)) rules)))
    ;; Owner-bound HERE, not at load time: reload also fires from the
    ;; files after-save hook and interactively, where no load-time
    ;; owner binding exists — unregister unclaims unconditionally, so
    ;; an unowned re-register would strand the triggers unattributed.
    (with-jetpacs-owner "glasspane"
      ;; Unregister leavers first, then (re)register — each call pushes,
      ;; and replace-set makes the intermediate states harmless.
      (dolist (stale (cl-set-difference glasspane-automations--ids ids
                                        :test #'equal))
        (jetpacs-trigger-unregister stale))
      (dolist (r rules)
        (apply #'jetpacs-trigger-register (plist-get r :id)
               (cl-loop for (k v) on r by #'cddr
                        unless (eq k :id) append (list k v)))))
    (setq glasspane-automations--ids ids)
    (when (called-interactively-p 'interactive)
      (message "Jetpacs automations: %d rule(s) active" (length ids)))
    ids))

(defvar jetpacs-files-after-save-hook)

(defun glasspane-automations--after-save (file)
  "Reload when the phone saves the automations FILE."
  (when (equal (expand-file-name file)
               (expand-file-name (glasspane-automations--file)))
    (glasspane-automations-reload)))

(with-eval-after-load 'jetpacs-files
  (add-hook 'jetpacs-files-after-save-hook #'glasspane-automations--after-save))

;; Load rules when the file exists; a missing file is simply zero rules.
(when (file-readable-p (glasspane-automations--file))
  (glasspane-automations-reload))

(provide 'glasspane-automations)
;;; glasspane-automations.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-notes.el
;;; ==================================================================

;;; glasspane-notes.el --- Vulpea bridge: wikilink completion + backlinks -*- lexical-binding: t; -*-

;; The linking loop over vulpea's note database (the PKM engine
;; decision — vulpea v2, org-roam as fallback never materialized):
;;
;;   PKM 3 — typing "[[" in the phone editor offers note titles from
;;   the vulpea index through the existing capf bridge; accepting one
;;   inserts a full "[[id:…][Title]]" link (the candidate `insert'
;;   attr, SPEC §8).
;;
;;   PKM 4 — the heading detail view grows "Linked references" (notes
;;   linking here, from the db) and on-demand "Unlinked mentions"
;;   (vulpea's async ripgrep pass) with a one-tap link.materialize.
;;
;; Everything degrades to absent when vulpea isn't installed or has no
;; database yet — no errors, no empty chrome.  The starter init
;; installs vulpea and enables `vulpea-db-autosync-mode'.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'jetpacs)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-source)
(require 'jetpacs-shell)
(require 'jetpacs-sync)
;; (require 'glasspane-org) — bundle-internal, provided above

(declare-function vulpea-db-search-by-title "vulpea-db-query")
(declare-function vulpea-db-query-by-links-some "vulpea-db-query")
(declare-function vulpea-db-query-by-ids "vulpea-db-query")
(declare-function vulpea-db-get-by-id "vulpea-db-query")
(declare-function vulpea-db-query-stale-notes "vulpea-db-query")
(declare-function vulpea-note-level "vulpea-note")
(declare-function vulpea-note-unlinked-mentions-async "vulpea-mentions")
(declare-function vulpea-note-id "vulpea-note")
(declare-function vulpea-note-title "vulpea-note")
(declare-function vulpea-note-path "vulpea-note")
(declare-function vulpea-note-tags "vulpea-note")
(declare-function vulpea-note-links "vulpea-note")
(declare-function vulpea-note-aliases "vulpea-note")

(defun glasspane-notes-available-p ()
  "Non-nil when the vulpea note database is usable."
  (and (featurep 'vulpea)
       (fboundp 'vulpea-db-search-by-title)))

;; ─── PKM 3: wikilink completion ──────────────────────────────────────────────

(defcustom glasspane-notes-completion-limit 20
  "Notes offered per wikilink completion request."
  :type 'integer :group 'jetpacs)

(defun glasspane-notes--matches (partial)
  "Vulpea notes whose title (or alias) matches PARTIAL, capped."
  (condition-case nil
      (seq-take (vulpea-db-search-by-title partial)
                glasspane-notes-completion-limit)
    (error nil)))

(defun glasspane-notes--wikilink-capf ()
  "Complete \"[[partial\" with note titles; insert full id links.
Candidates keep the \"[[\" so the phone replaces the whole open
bracket with the link (the strip validates the prefix by position,
so the brackets must be part of it)."
  (when (and (derived-mode-p 'org-mode)
             (glasspane-notes-available-p))
    (save-excursion
      (when (looking-back "\\[\\[\\([^][\n]*\\)"
                          (max (point-min) (- (point) 120)))
        (let* ((beg (match-beginning 0))
               (partial (match-string 1))
               (notes (glasspane-notes--matches partial))
               (table (mapcar (lambda (n)
                                (cons (concat "[[" (vulpea-note-title n)) n))
                              notes)))
          (when table
            (list beg (point)
                  ;; A function table owns its own matching: vulpea
                  ;; already filtered by PARTIAL case-insensitively, so
                  ;; every candidate passes.  try-completion (the
                  ;; :exclusive-no validation probe) must also succeed,
                  ;; or the capf wrapper discards this capf entirely.
                  (lambda (string _pred action)
                    (cond
                     ((eq action t) (mapcar #'car table))
                     ((null action) (and table string))
                     ((eq action 'lambda) (and (assoc string table) t))
                     ((eq action 'metadata)
                      '(metadata (category . glasspane-wikilink)))))
                  :annotation-function
                  (lambda (c)
                    (when-let ((n (cdr (assoc c table))))
                      (file-name-nondirectory (vulpea-note-path n))))
                  :jetpacs-insert-function
                  (lambda (c)
                    (when-let ((n (cdr (assoc c table))))
                      (format "[[id:%s][%s]]"
                              (vulpea-note-id n) (vulpea-note-title n))))
                  :exclusive 'no)))))))

;; The capf bridge builds shadow buffers through this hook; installing
;; the capf there (buffer-locally, front of the list) keeps wikilink
;; completion scoped to the phone editor — desktop org buffers are the
;; user's own capf business.
(defun glasspane-notes--setup-shadow ()
  (when (derived-mode-p 'org-mode)
    (add-hook 'completion-at-point-functions
              #'glasspane-notes--wikilink-capf -10 t)))

(add-hook 'jetpacs-sync-shadow-setup-hook #'glasspane-notes--setup-shadow)

;; ─── PKM 4: backlinks + unlinked mentions ────────────────────────────────────

(defvar glasspane-notes--mentions (make-hash-table :test 'equal)
  "Note id -> computed unlinked-mentions list, `pending', or `error'.
Dropped wholesale by the cache seam.")

(defun glasspane-notes--note-ref (note)
  "The heading.tap REF alist for vulpea NOTE — id/file/headline, no pos.
nil-valued cells are pruned so the ref serialises cleanly to JSON."
  (let ((id (and (fboundp 'vulpea-note-id) (vulpea-note-id note)))
        (path (vulpea-note-path note))
        (title (vulpea-note-title note)))
    (delq nil
          (list (when (and id (stringp id) (not (string-empty-p id))) `(id . ,id))
                (when path `(file . ,path))
                (when title `(headline . ,title))))))

(defun glasspane-notes--note-card (note)
  "A tappable card for NOTE (opens its heading in the detail view)."
  (let ((title (vulpea-note-title note))
        (path (vulpea-note-path note))
        (ref (glasspane-notes--note-ref note)))
    (jetpacs-card
     (list (jetpacs-column
            (jetpacs-text title 'body)
            (jetpacs-text (file-name-nondirectory path) 'caption)))
     :on-tap (when ref
               (jetpacs-action "heading.tap" :args ref :when-offline "drop")))))

(defun glasspane-notes--mention-card (mention note-id)
  "A card for MENTION (a :note :path :line :context plist).
Current vulpea resolve plists don't carry :matched (the exact text the
scan hit) — it is forwarded when present, and link.materialize falls
back to the note's title/aliases otherwise.  The path prefers the
plist's own :path, with the mentioning note's file as backstop."
  (let* ((source (plist-get mention :note))
         (path (or (plist-get mention :path)
                   (and source (vulpea-note-path source))))
         (id (and source (fboundp 'vulpea-note-id) (vulpea-note-id source)))
         (title (if source (vulpea-note-title source)
                  (file-name-nondirectory (or path ""))))
         (ref (delq nil
                    (list (when (and id (stringp id) (not (string-empty-p id))) `(id . ,id))
                          (when path `(file . ,path))
                          (when title `(headline . ,title))))))
    (jetpacs-card
     (list
      (jetpacs-column
       (jetpacs-text title 'body)
       (jetpacs-text (or (plist-get mention :context) "") 'caption)
       (jetpacs-row
        (jetpacs-spacer :weight 1)
        (jetpacs-button "Link it"
                     (jetpacs-action "link.materialize"
                                  :args `((id . ,note-id)
                                          (path . ,path)
                                          (line . ,(plist-get mention :line))
                                          (matched . ,(plist-get mention :matched)))
                                  :when-offline "queue")
                     :variant "text" :icon "link"))))
     :on-tap (when ref
               (jetpacs-action "heading.tap" :args ref :when-offline "drop")))))

(defun glasspane-notes--ref-id (ref)
  "REF's org ID: carried in the ref, or read from the heading itself.
Reader-built drill-in refs carry only file/pos, so a child heading
with an :ID: still gets its backlink section."
  (or (alist-get 'id ref)
      (condition-case nil
          (let ((marker (jetpacs-org-resolve-ref ref)))
            (with-current-buffer (marker-buffer marker)
              (org-with-wide-buffer
               (goto-char marker)
               (org-entry-get nil "ID"))))
        (error nil))))

;; ─── The notes data source (composer-bindable note graph) ────────────────────
;;
;; The synchronous half of the note graph — backlinks and outgoing (forward)
;; links — exposed as a `jetpacs-defsource' over vulpea's db-query, normalized
;; to the domain-neutral field contract.  This is the data a `:spec' view (or
;; the no-code composer) binds; Glasspane's own detail rendering stays a
;; `:builder' that leans on the same helpers.  Unlinked mentions are the async
;; ripgrep pass and don't fit a synchronous source, so they stay builder-side.

(defun glasspane-notes--backlinks (id)
  "Notes that link TO ID (the linked-references set), or nil."
  (condition-case nil (vulpea-db-query-by-links-some (list id)) (error nil)))

(defun glasspane-notes--forward-links (id)
  "Notes that ID links out to via id-type links, resolved to note objects."
  (when-let* ((note (condition-case nil (vulpea-db-get-by-id id) (error nil)))
              (dest-ids (delq nil
                              (mapcar (lambda (l)
                                        (when (equal (plist-get l :type) "id")
                                          (plist-get l :dest)))
                                      (vulpea-note-links note)))))
    (condition-case nil (vulpea-db-query-by-ids dest-ids) (error nil))))

(defun glasspane-notes--note-item (note)
  "Normalize vulpea NOTE to the \"glasspane.notes\" canonical fields."
  (let ((path (vulpea-note-path note)))
    (list (cons 'id        (vulpea-note-id note))
          (cons 'title     (vulpea-note-title note))
          (cons 'path      path)
          (cons 'file_name (and path (file-name-nondirectory path)))
          (cons 'tags      (append (and (fboundp 'vulpea-note-tags)
                                        (vulpea-note-tags note))
                                   nil))
          (cons 'ref       (glasspane-notes--note-ref note)))))

(defun glasspane-notes--source-query (params)
  "The \"glasspane.notes\" :query: a RELATION over a note ID -> canonical items.
RELATION is \"backlinks\" (default) or \"outgoing\".  Yields no items when
vulpea is unavailable or ID is blank — never an error."
  (let ((id (alist-get 'id params))
        (relation (or (alist-get 'relation params) "backlinks")))
    (when (and (stringp id) (not (string-empty-p id)) (glasspane-notes-available-p))
      (mapcar #'glasspane-notes--note-item
              (pcase relation
                ("outgoing" (glasspane-notes--forward-links id))
                (_          (glasspane-notes--backlinks id)))))))

(with-jetpacs-owner "glasspane"
  (jetpacs-defsource "glasspane.notes"
    :params '((:name id       :type "text" :required t)
              (:name relation :type "enum" :values ["backlinks" "outgoing"]))
    :fields '((:name "id"        :type "text")
              (:name "title"     :type "text")
              (:name "path"      :type "text")
              (:name "file_name" :type "text")
              (:name "tags"      :type "string-list")
              (:name "ref"       :type "ref"))
    :query #'glasspane-notes--source-query))

(defun glasspane-notes-detail-nodes (ref)
  "Backlink section nodes for the detail REF (needs an org ID), or nil."
  (when-let* (((glasspane-notes-available-p))
              (id (glasspane-notes--ref-id ref)))
    (let* ((backlinks (glasspane-notes--backlinks id))
           (forward-links (glasspane-notes--forward-links id))
           (mentions (gethash id glasspane-notes--mentions 'unfetched)))
      (append
       (list (jetpacs-divider)
             (jetpacs-collapsible
              (concat "forwardlinks/" id)
              (jetpacs-section-header
               (format "Outgoing links (%d)" (length forward-links)))
              (or (mapcar #'glasspane-notes--note-card forward-links)
                  (list (jetpacs-text "No outgoing links." 'caption)))
              :collapsed (null forward-links)))
       (list (jetpacs-collapsible
              (concat "backlinks/" id)
              (jetpacs-section-header
               (format "Linked references (%d)" (length backlinks)))
              (or (mapcar #'glasspane-notes--note-card backlinks)
                  (list (jetpacs-text "Nothing links here yet." 'caption)))
              :collapsed (null backlinks)))
       ;; The mentions section only exists once a scan has been asked
       ;; for (the toolbar chip) — an unscanned note gets no chrome.
       (unless (eq mentions 'unfetched)
         (list (jetpacs-collapsible
                (concat "mentions/" id)
                (jetpacs-section-header
                 (pcase mentions
                   ('pending "Unlinked mentions (searching…)")
                   ('error "Unlinked mentions (search failed)")
                   (found (format "Unlinked mentions (%d)" (length found)))))
                (pcase mentions
                  ('pending (list (jetpacs-progress :variant "linear")))
                  ('error (list (jetpacs-text "ripgrep unavailable or the search failed."
                                           'caption)))
                  ('nil (list (jetpacs-text "No unlinked mentions." 'caption)))
                  (found (mapcar (lambda (m)
                                   (glasspane-notes--mention-card m id))
                                 found)))
                :collapsed nil)))))))

(defun glasspane-notes-detail-toolbar (ref)
  "The detail floating-toolbar chip for REF: scan for unlinked mentions.
Results land in the Unlinked mentions section of the body; a re-tap
re-runs the scan."
  (when-let* (((glasspane-notes-available-p))
              (id (glasspane-notes--ref-id ref)))
    (list (jetpacs-nav-item
           "manage_search" "Mentions"
           (jetpacs-action "notes.mentions" :args `((id . ,id))
                        :when-offline "drop")))))

;; The mention grep is the battery-risk item: computed only on the
;; explicit chip tap, cached per note, dropped by the standard seam.
(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "notes.mentions"
    (lambda (args _)
      (let ((id (alist-get 'id args)))
        (when (and (stringp id) (glasspane-notes-available-p)
                   (fboundp 'vulpea-note-unlinked-mentions-async))
          (when-let ((note (vulpea-db-get-by-id id)))
            (puthash id 'pending glasspane-notes--mentions)
            (vulpea-note-unlinked-mentions-async
             note
             (lambda (mentions)
               (puthash id mentions glasspane-notes--mentions)
               (jetpacs-shell-push))
             (lambda (_err)
               (puthash id 'error glasspane-notes--mentions)
               (jetpacs-shell-push)))
            (jetpacs-shell-push)))))
    :doc "Scan for unlinked mentions of a note (async ripgrep)."
    :args '((:name id :type "text" :required t))))

(defun glasspane-notes--materialize-terms (id matched)
  "The strings to look for on the mention line, most specific first.
MATCHED when the wire carried it; otherwise the note's title and
aliases — current vulpea mention plists name the note but not the
matched text, so the fallback is what makes \"Link it\" work at all."
  (if (and (stringp matched) (not (string-empty-p matched)))
      (list matched)
    (when-let ((note (and (glasspane-notes-available-p)
                          (fboundp 'vulpea-db-get-by-id)
                          (ignore-errors (vulpea-db-get-by-id id)))))
      (delq nil (cons (vulpea-note-title note)
                      (and (fboundp 'vulpea-note-aliases)
                           (ignore-errors (vulpea-note-aliases note))))))))

(defun glasspane-notes--find-unlinked (terms end)
  "Move point to the first occurrence of a TERMS member before END.
Case-insensitive; leaves the match data on the hit and returns the
term, or nil.  Occurrences already inside an org link are skipped —
the file may have changed since the mention scan, and a stale tap
must not nest a link inside a link."
  (let ((case-fold-search t)
        (start (point)))
    (cl-loop for term in terms
             do (goto-char start)
             thereis (cl-loop while (search-forward term end t)
                              unless (save-match-data
                                       (save-excursion
                                         (goto-char (match-beginning 0))
                                         (org-in-regexp org-link-any-re)))
                              return term))))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "link.materialize"
    ;; Replace the first un-linked occurrence of the mention on LINE in
    ;; PATH with a real id link.  Matching is case-insensitive (search
    ;; UX); the replacement keeps the text exactly as written in the
    ;; file.  Every failure path answers with a snackbar — a tap that
    ;; silently does nothing is a bug class, not an outcome.
    (lambda (args _)
      (let* ((id (alist-get 'id args))
             (path (alist-get 'path args))
             (line (alist-get 'line args))
             (terms (and (stringp id)
                         (glasspane-notes--materialize-terms
                          id (alist-get 'matched args)))))
        (cond
         ((not (and (stringp id) (stringp path) (integerp line) terms))
          (jetpacs-shell-notify "Couldn't link — mention data incomplete"))
         ((not (file-writable-p path))
          (jetpacs-shell-notify (format "Couldn't link — %s not writable"
                                     (file-name-nondirectory path))))
         (t
          (with-current-buffer (find-file-noselect path)
            (org-with-wide-buffer
             (goto-char (point-min))
             (forward-line (1- line))
             (if (not (glasspane-notes--find-unlinked
                       terms (line-end-position)))
                 (jetpacs-shell-notify
                  "Couldn't find the mention — file changed? Refresh and retry")
               (replace-match (format "[[id:%s][%s]]" id (match-string 0))
                              t t)
               (glasspane-org--save-and-invalidate)
               (remhash id glasspane-notes--mentions)
               (jetpacs-shell-notify "Linked"))))))
        (jetpacs-shell-push)))))

(add-hook 'jetpacs-shell-refresh-hook
          (lambda () (clrhash glasspane-notes--mentions)))

;; The detail view splices this module's sections and toolbar chip
;; through the ui seams.
(add-hook 'glasspane-ui-detail-nodes-functions #'glasspane-notes-detail-nodes)
(add-hook 'glasspane-ui-detail-toolbar-functions #'glasspane-notes-detail-toolbar)

;; ─── Stale files: the vulpea half of the Review view ────────────────────────
;; vulpea-db-query-stale-notes joins the files table's real mtime; a file
;; leaves the list only when its content actually changes (a bare touch is
;; skipped by vulpea's hash check at sync).  Tap opens the note — editing
;; it is what marks it reviewed.

(defcustom glasspane-notes-stale-days 90
  "Days without modification before a note file counts as stale.
The Review view lists these for a look-over."
  :type 'integer :group 'jetpacs)

(defconst glasspane-notes--stale-cap 20
  "Stale files shown at once (the oldest); the rest wait their turn.")

(defun glasspane-notes-stale-available-p ()
  "Non-nil when the stale-files query is usable (vulpea new enough)."
  (and (glasspane-notes-available-p)
       (fboundp 'vulpea-db-query-stale-notes)))

(defun glasspane-notes--stale-notes ()
  "The oldest stale note per file, oldest file first, capped.
The query returns every note in a stale file (heading-level notes
share the file's mtime); one card per file is the useful grain, and
the file-level (level 0) note names the file best when present."
  (when (glasspane-notes-stale-available-p)
    (condition-case nil
        (let ((by-path (make-hash-table :test 'equal))
              (order nil))
          (dolist (note (vulpea-db-query-stale-notes glasspane-notes-stale-days))
            (let* ((path (vulpea-note-path note))
                   (seen (gethash path by-path)))
              (unless seen (push path order))
              (when (or (not seen)
                        (eql 0 (ignore-errors (vulpea-note-level note))))
                (puthash path note by-path))))
          (seq-take (mapcar (lambda (p) (gethash p by-path)) (nreverse order))
                    glasspane-notes--stale-cap))
      (error nil))))

(defun glasspane-notes--age-caption (path)
  "\"modified N days/months/years ago\" from PATH's filesystem mtime, or nil."
  (when-let* ((attrs (file-attributes path))
              (days (floor (- (float-time)
                              (float-time (file-attribute-modification-time attrs)))
                           86400)))
    (cond
     ((< days 60) (format "modified %d days ago" days))
     ((< days 730) (format "modified %d months ago" (floor days 30)))
     (t (format "modified %d years ago" (floor days 365))))))

(defun glasspane-notes--stale-card (note)
  "A tappable card for stale NOTE: title, file, and how long untouched."
  (let* ((title (vulpea-note-title note))
         (path (vulpea-note-path note))
         (ref (glasspane-notes--note-ref note))
         (age (glasspane-notes--age-caption path)))
    (jetpacs-card
     (list (jetpacs-column
            (jetpacs-text title 'body)
            (jetpacs-text (concat (file-name-nondirectory path)
                                  (when age (concat " · " age)))
                       'caption)))
     :on-tap (when ref
               (jetpacs-action "heading.tap" :args ref :when-offline "drop")))))

(defun glasspane-notes-stale-section ()
  "Section nodes for the stale-files review, or nil when vulpea is absent."
  (when (glasspane-notes-stale-available-p)
    (let ((notes (glasspane-notes--stale-notes)))
      (if (null notes)
          (list (jetpacs-section-header "Stale files")
                (jetpacs-text (format "Nothing untouched for %d+ days."
                                   glasspane-notes-stale-days)
                           'caption))
        (append
         (list (jetpacs-section-header "Stale files")
               (jetpacs-text (format "Untouched for %d+ days — oldest first."
                                  glasspane-notes-stale-days)
                          'caption))
         (mapcar #'glasspane-notes--stale-card notes))))))

(provide 'glasspane-notes)
;;; glasspane-notes.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-srs.el
;;; ==================================================================

;;; glasspane-srs.el --- Spaced repetition over org-srs -*- lexical-binding: t; -*-

;; The Tier 1 skin for org-srs (PKM plan: SRS = org-srs, decided
;; 2026-07-05): a Review drawer destination plus "Make flashcard" on the
;; heading detail view.
;;
;; Design — org-srs as an ENGINE, not a mirrored session.  An earlier
;; version puppeteered org-srs's live, window-centric review session
;; (`org-srs-review-start' → `switch-to-buffer' + window asserts) and
;; rendered the raw review buffer; on the phone that produced broken
;; cards (per-line ellipsis dots on multi-line answers, raw org stars,
;; cloze cards that looped without revealing) and stray message toasts.
;;
;; Instead we drive org-srs entirely in the background and render our own
;; clean cards:
;;   - The queue is `org-srs-review-pending-items' — the same set org-srs
;;     itself pulls each step; we show its first element and re-fetch
;;     after every rating (so `Again' cards reappear and the queue empties
;;     naturally).  No session, no continue-hook loop.
;;   - Rating is `org-srs-review-rate' with EXPLICIT item args, which
;;     routes through `org-srs-item-with-current' (a `with-current-buffer'
;;     + marker) — no window, no selected-buffer coupling.
;;   - The question/answer are extracted per item type (card regions,
;;     cloze spans) and rendered with our widgets: reveal is a plain UI
;;     flag, so nothing depends on org-srs's confirm state machine.
;;   - Undo keeps its own small stack of log-drawer snapshots (org-srs's
;;     own undo history is only set up by the session we don't run).
;;
;; Native-Emacs review coherence is a non-goal (this skin is for the
;; phone).  Everything degrades to absent when org-srs isn't installed.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'jetpacs)
(require 'jetpacs-widgets)
(require 'jetpacs-surfaces)
(require 'jetpacs-buffer)
(require 'jetpacs-shell)
(require 'jetpacs-settings)
;; (require 'glasspane-org) — bundle-internal, provided above
;; (require 'glasspane-notes) — bundle-internal, provided above

(declare-function org-srs-review-pending-items "org-srs-review")
(declare-function org-srs-review-postpone "org-srs-review")
(declare-function org-srs-review-rate "org-srs-review-rate")
(declare-function org-srs-item-create "org-srs-item")
(declare-function org-srs-item-marker "org-srs-item")
(declare-function org-srs-item-call-with-current "org-srs-item")
(declare-function org-srs-item-cloze-collect "org-srs-item-cloze")
(declare-function org-srs-log-beginning-of-drawer "org-srs-log")
(declare-function org-srs-log-end-of-drawer "org-srs-log")
(declare-function org-srs-log-hide-drawer "org-srs-log")
(declare-function org-srs-table-goto-column "org-srs-table")
(declare-function org-srs-stats-intervals "org-srs-stats-interval")
(declare-function org-srs-time-seconds-desc "org-srs-time")

;; `org-srs-review-rate' reads this dynamic var to decide whether it is
;; mid-session; outside a session it is unbound, so we bind it to nil to
;; take the explicit-item-args path.  The bare defvar marks it special
;; so the `let' below binds dynamically even when byte-compiled without
;; org-srs loaded.
(defvar org-srs-review-item)

(defcustom glasspane-srs-source nil
  "The review scope: a file or directory org-srs reviews over.
nil means `org-directory' — review everything, the phone default."
  :type '(choice (const :tag "org-directory" nil) directory file)
  :group 'jetpacs)

(defvar glasspane-srs--available 'unknown
  "Cached org-srs availability; `unknown' re-probes on next ask.")

(defun glasspane-srs-available-p ()
  "Non-nil when org-srs is installed and loadable.
A failed probe is cached (a missing package must not re-scan the
load-path per render); pull-to-refresh re-probes, so installing
org-srs mid-session only needs a refresh."
  (when (eq glasspane-srs--available 'unknown)
    (setq glasspane-srs--available (and (require 'org-srs nil t) t)))
  glasspane-srs--available)

(add-hook 'jetpacs-shell-refresh-hook
          (lambda () (setq glasspane-srs--available 'unknown)))

(defun glasspane-srs--source ()
  (or glasspane-srs-source org-directory))

;; ─── Session state ───────────────────────────────────────────────────────────

(defvar glasspane-srs--active nil
  "Non-nil while a review is in progress on the phone.")

(defvar glasspane-srs--current nil
  "The item-args `(ITEM ID BUFFER)' under review, or nil.
Nil while a session is active means the queue drained (the done
screen); ITEM is `(card SIDE)' or `(cloze CLOZE-ID)'.")

(defvar glasspane-srs--revealed nil
  "Non-nil once the answer for `glasspane-srs--current' is shown.
A pure UI flag — the reveal never touches org-srs.")

(defvar glasspane-srs--undo nil
  "Stack of (ITEM-ARGS . LOG-STRING) snapshots for `srs.undo'.
Each entry is the item's SRSITEMS log-drawer text captured just
before that item was rated.")

(defmacro glasspane-srs--engine (&rest body)
  "Run BODY (org-srs engine calls) quietly, returning its value or nil.
Messages are suppressed so org-srs's and the user's `message's don't
surface as Glasspane toasts; a signal becomes a snackbar, never a
crash — a review tap that silently dies is a bug class."
  (declare (indent 0) (debug t))
  `(condition-case err
       (let ((inhibit-message t) (message-log-max nil))
         ,@body)
     (error
      (jetpacs-shell-notify (format "Review: %s" (error-message-string err)))
      nil)))

(defmacro glasspane-srs--quietly (&rest body)
  "Run BODY with messages suppressed, returning its value or nil on error.
The render-time counterpart of `glasspane-srs--engine': a failure while
building a view must NOT raise a snackbar (only actions do that)."
  (declare (indent 0) (debug t))
  `(let ((inhibit-message t) (message-log-max nil))
     (ignore-errors ,@body)))

(defun glasspane-srs--next-item ()
  "The first pending item over the source, or nil when none remain."
  (car (org-srs-review-pending-items (glasspane-srs--source))))

(defun glasspane-srs--advance ()
  "Load the next pending item and clear the reveal flag.
`--current' nil afterward means the queue drained."
  (setq glasspane-srs--current (glasspane-srs--quietly (glasspane-srs--next-item))
        glasspane-srs--revealed nil))

;; ─── Due count (idle screen) ─────────────────────────────────────────────────

(defun glasspane-srs--due-count ()
  "Items a session over the configured source would show now, or nil.
Memoised through the org cache seam — every mutating srs.* action
invalidates, so the count follows ratings without a per-render scan."
  (when (glasspane-srs-available-p)
    (glasspane-srs--quietly
      (jetpacs-org-with-cache 'glasspane (list 'srs-due (glasspane-srs--source))
        (length (org-srs-review-pending-items (glasspane-srs--source)))))))

;; ─── Content extraction & clean rendering ────────────────────────────────────

(defconst glasspane-srs--noise-drawers '("PROPERTIES" "SRSITEMS" "LOGBOOK")
  "Drawers hidden from the fallback render: org metadata plus org-srs's
review log (`org-srs-log-drawer-name' is SRSITEMS).")

;; Card layouts are computed with plain org (not org-srs's region
;; helpers): under a subtree narrowing those helpers return *entry*-scoped
;; positions that collapse to empty answers.  This is predictable and
;; testable without org-srs installed.

(defun glasspane-srs--child-body (base title child-re)
  "Body region (BEG . END) of the direct child named TITLE, or nil.
BASE is the entry's outline level (point-min is its heading);
CHILD-RE matches level BASE+1 headings.  The region starts after the
child's own heading and meta-data, so it carries no `*' stars."
  (save-excursion
    (goto-char (point-min))
    (let (region)
      (while (and (not region) (re-search-forward child-re nil t))
        (goto-char (match-beginning 0))
        (when (and (eql (org-current-level) (1+ base))
                   (string-equal-ignore-case
                    (or (org-get-heading t t t t) "") title))
          (setq region
                (cons (save-excursion (org-end-of-meta-data t) (point))
                      (save-excursion (org-end-of-subtree t t) (point)))))
        (goto-char (match-end 0)))
      region)))

(defun glasspane-srs--card-parts (side)
  "Return (QUESTION . ANSWER) parts for the narrowed heading entry.
Each part is (title . STRING), (region BEG . END), or 
(title-and-region STRING BEG . END). SIDE is the reviewed (hidden answer) side.
Handles the common heading-level layouts: heading-as-front + body-as-back, 
explicit `Front`/`Back` children, and Logseq-style nested block children."
  (goto-char (point-min))
  (let* ((base (or (org-current-level) 1))
         (title (or (org-get-heading t t t t) ""))
         (child-re (format "^\\*\\{%d\\}[ \t]" (1+ base)))
         (meta-end (save-excursion (goto-char (point-min))
                                   (org-end-of-meta-data t) (point)))
         (first-child (save-excursion
                        (goto-char meta-end)
                        (if (re-search-forward child-re nil t)
                            (line-beginning-position)
                          (point-max))))
         (front (glasspane-srs--child-body base "Front" child-re))
         (back (glasspane-srs--child-body base "Back" child-re))
         (front-face
          (cond (front (cons 'region front))
                ((< first-child (point-max))
                 ;; Has children: Front is title + body up to first-child
                 (list 'title-and-region title meta-end first-child))
                (t (cons 'title title))))
         (back-face
          (cond (back (cons 'region back))
                ((< first-child (point-max))
                 ;; Has children: Back is the children
                 (list 'region first-child (point-max)))
                (t 
                 ;; No children: Back is the body
                 (list 'region meta-end (point-max))))))
    (if (eq side 'front)
        (cons back-face front-face)
      (cons front-face back-face))))

(defun glasspane-srs--part-nodes (part)
  "Render a card PART: (title . STRING), (region BEG END), or (title-and-region ...)."
  (pcase part
    (`(title . ,s)
     (and (stringp s) (not (string-empty-p s)) (list (jetpacs-text s 'title))))
    (`(title-and-region ,title ,beg . ,rest)
     (let* ((end (if (consp rest) (car rest) rest))
            (title-nodes (and (stringp title) (not (string-empty-p title))
                              (list (jetpacs-text title 'title))))
            (jetpacs-line-numbers nil)
            (jetpacs-buffer-monospace nil)
            (region-nodes (when (and (integerp beg) (integerp end) (< beg end))
                            (jetpacs-buffer-render-region (current-buffer) beg end))))
       (append title-nodes region-nodes)))
    (`(region ,beg . ,rest)
     (let ((end (if (consp rest) (car rest) rest))
           (jetpacs-line-numbers nil)
           (jetpacs-buffer-monospace nil))
       (when (and (integerp beg) (integerp end) (< beg end))
         (jetpacs-buffer-render-region (current-buffer) beg end))))
    (_ nil)))

(defun glasspane-srs--card-content (item revealed)
  "Question and (when REVEALED) answer nodes for a `card' ITEM.
ITEM is `(card SIDE)'; SIDE (default `back') is the hidden answer."
  (condition-case nil
      (let* ((parts (glasspane-srs--card-parts (or (cadr item) 'back)))
             (open (format "^[ \t]*:%s:[ \t]*$"
                           (regexp-opt glasspane-srs--noise-drawers)))
             (overlays nil)
             ;; Save the real buffer-local value so we can restore it.
             ;; We must use setq (not let) because `invisible-p' is a C
             ;; function that reads the buffer struct directly and never
             ;; sees Lisp-level dynamic bindings.
             (orig-invis-spec buffer-invisibility-spec))
        (unwind-protect
            (progn
              ;; Build a clean spec: remove fold-related entries so folded
              ;; body text renders.
              (setq buffer-invisibility-spec
                    (if (listp orig-invis-spec)
                        (cl-remove-if
                         (lambda (x)
                           (memq (if (consp x) (car x) x)
                                 '(outline org-fold-outline
                                   org-fold-drawer org-fold-block)))
                         orig-invis-spec)
                      orig-invis-spec))
              (add-to-invisibility-spec 'glasspane-srs-hide)
              ;; Hide noise drawers (PROPERTIES / SRSITEMS / LOGBOOK)
              ;; with our own overlays.
              (save-excursion
                (goto-char (point-min))
                (while (re-search-forward open nil t)
                  (let ((dbeg (match-beginning 0))
                        (dend (save-excursion
                                (and (re-search-forward
                                      "^[ \t]*:END:[ \t]*$" nil t)
                                     (min (1+ (line-end-position))
                                          (point-max))))))
                    (if (null dend)
                        (goto-char (line-end-position))
                      (let ((ov (make-overlay dbeg dend)))
                        (overlay-put ov 'invisible 'glasspane-srs-hide)
                        (push ov overlays)
                        (goto-char dend))))))
              ;; Hide org link brackets and targets using `display'
              ;; overlays.  The renderer checks (get-char-property pos
              ;; 'display) and when it's an empty string the span is
              ;; skipped entirely.  This is more reliable than the
              ;; `invisible' property which depends on the C-level
              ;; `invisible-p' and can be disrupted by font-lock.
              (save-excursion
                (goto-char (point-min))
                ;; Descriptive links: [[target][description]]
                (while (re-search-forward
                        "\\[\\[\\([^]]*\\)\\]\\[\\([^]]*\\)\\]\\]" nil t)
                  (let ((ov1 (make-overlay (match-beginning 0)
                                           (match-beginning 2)))
                        (ov2 (make-overlay (match-end 2)
                                           (match-end 0))))
                    (overlay-put ov1 'display "")
                    (overlay-put ov2 'display "")
                    (push ov1 overlays)
                    (push ov2 overlays))))
              (save-excursion
                (goto-char (point-min))
                ;; Plain links: [[target]]
                (while (re-search-forward
                        "\\[\\[\\([^]]*\\)\\]\\]" nil t)
                  (let ((ov1 (make-overlay (match-beginning 0)
                                           (match-beginning 1)))
                        (ov2 (make-overlay (match-end 1)
                                           (match-end 0))))
                    (overlay-put ov1 'display "")
                    (overlay-put ov2 'display "")
                    (push ov1 overlays)
                    (push ov2 overlays))))
              ;; Render parts
              (append
               (or (glasspane-srs--part-nodes (car parts))
                   (list (jetpacs-text "(no question)" 'caption)))
               (when revealed
                 (cons (jetpacs-divider)
                       (or (glasspane-srs--part-nodes (cdr parts))
                           (list (jetpacs-text "(no answer)" 'caption)))))))
          ;; Restore original spec and clean up overlays.
          (setq buffer-invisibility-spec orig-invis-spec)
          (mapc #'delete-overlay overlays)))
    (error (list (jetpacs-text "Couldn't lay out this card." 'caption)))))

(defun glasspane-srs--cloze-content (item revealed)
  "Nodes for a `cloze' ITEM: the sentence with the reviewed blank.
ITEM is `(cloze CLOZE-ID)'.  The reviewed cloze shows as `[hint]' /
`[…]' until REVEALED; other clozes show their text as context.  Bounds
come from plain org; only `org-srs-item-cloze-collect' is org-srs."
  (condition-case nil
      (let* ((target (cadr item))
             (beg (save-excursion (goto-char (point-min))
                                  (org-end-of-meta-data t) (point)))
             (end (point-max))
             (clozes (sort (copy-sequence (org-srs-item-cloze-collect beg end))
                           (lambda (a b) (< (cadr a) (cadr b)))))
             (pos beg) (parts nil))
        (dolist (cz clozes)
          (cl-destructuring-bind (id cbeg cend text &optional hint) cz
            (push (buffer-substring-no-properties pos cbeg) parts)
            (push (cond ((not (equal id target)) text)
                        (revealed text)
                        (t (format "[%s]" (or hint "…"))))
                  parts)
            (setq pos cend)))
        (push (buffer-substring-no-properties pos end) parts)
        (list (jetpacs-text (string-trim (apply #'concat (nreverse parts))) 'body)))
    (error (list (jetpacs-text "Couldn't lay out this cloze." 'caption)))))

(defun glasspane-srs--fallback-content ()
  "Render the narrowed entry cleanly for an unknown item type.
Drawers and gutter line numbers stripped; transient overlays only."
  (let ((jetpacs-line-numbers nil) (jetpacs-buffer-monospace nil) (overlays nil)
        (open (format "^[ \t]*:%s:[ \t]*$"
                      (regexp-opt glasspane-srs--noise-drawers))))
    (unwind-protect
        (progn
          (add-to-invisibility-spec 'glasspane-srs-hide)
          (save-excursion
            (goto-char (point-min))
            (while (re-search-forward open nil t)
              (let ((dbeg (match-beginning 0))
                    (dend (save-excursion
                            (and (re-search-forward "^[ \t]*:END:[ \t]*$" nil t)
                                 (min (1+ (line-end-position)) (point-max))))))
                (if (null dend)
                    (goto-char (line-end-position))
                  (let ((ov (make-overlay dbeg dend)))
                    (overlay-put ov 'invisible 'glasspane-srs-hide)
                    (push ov overlays))
                  (goto-char dend)))))
          (jetpacs-buffer-render (current-buffer)))
      (mapc #'delete-overlay overlays)
      (remove-from-invisibility-spec 'glasspane-srs-hide))))

(defun glasspane-srs--item-nodes (item-args revealed)
  "Clean card nodes for ITEM-ARGS (`(ITEM ID BUFFER)'), REVEALED or not.
Resolves the item's marker in the background — no window, no session —
narrows to its entry, and dispatches on the item type."
  (let* ((item (car item-args))
         (type (car item))
         (marker (glasspane-srs--quietly (apply #'org-srs-item-marker item-args))))
    (if (not (and (markerp marker) (marker-buffer marker)))
        (list (jetpacs-text "Couldn't load this card." 'caption))
      (with-current-buffer (marker-buffer marker)
        (save-excursion
          (save-restriction
            (widen)
            (goto-char marker)
            (org-back-to-heading-or-point-min)
            (unless (org-before-first-heading-p) (org-narrow-to-subtree))
            (pcase type
              ('card (glasspane-srs--card-content item revealed))
              ('cloze (glasspane-srs--cloze-content item revealed))
              (_ (glasspane-srs--fallback-content)))))))))

;; ─── Rating chrome ───────────────────────────────────────────────────────────

(defconst glasspane-srs--ratings
  '(("again" :again "Again" "outlined")
    ("hard" :hard "Hard" "tonal")
    ("good" :good "Good" "filled")
    ("easy" :easy "Easy" "tonal"))
  "WIRE-NAME KEYWORD LABEL VARIANT rows for the rating buttons.")

(defun glasspane-srs--intervals ()
  "Predicted next intervals as a (:again SECS …) plist, or nil.
The org-srs-ui-mouse recipe, over the current item args: with point on
its log row and a `rating' column, the simulator runs."
  (when glasspane-srs--current
    (glasspane-srs--quietly
      (apply #'org-srs-item-call-with-current
             (lambda ()
               (when (org-srs-table-goto-column 'rating)
                 (org-srs-stats-intervals)))
             glasspane-srs--current))))

(defun glasspane-srs--format-interval (seconds)
  "SECONDS as a short \"3d 2h\" description (two components max)."
  (cl-loop for (amount unit . rest) on (org-srs-time-seconds-desc seconds)
           by #'cddr
           for i from 1
           concat (format "%d%.1s" amount
                          (string-trim-left (symbol-name unit) ":"))
           while (< i 2)
           when rest concat " "))

(defun glasspane-srs--rating-controls ()
  "The four rating buttons with predicted-interval captions."
  (let ((intervals (glasspane-srs--intervals)))
    (delq nil
          (list
           (when intervals
             (apply #'jetpacs-row
                    (mapcar (lambda (row)
                              (jetpacs-box
                               (list (jetpacs-text
                                      (if-let ((secs (plist-get intervals
                                                                (cadr row))))
                                          (glasspane-srs--format-interval secs)
                                        "")
                                      'caption))
                               :weight 1 :alignment "center"))
                            glasspane-srs--ratings)))
           (apply #'jetpacs-row
                  (mapcar (lambda (row)
                            (cl-destructuring-bind (name _kw label variant) row
                              (jetpacs-button label
                                           (jetpacs-action
                                            "srs.rate"
                                            :args `((rating . ,name))
                                            :when-offline "drop")
                                           :variant variant :weight 1)))
                          glasspane-srs--ratings))))))

;; ─── The view ────────────────────────────────────────────────────────────────

(defun glasspane-srs--session-body ()
  "The active-session screen: the card, then reveal or rating controls."
  (cond
   ((null glasspane-srs--current)
    (jetpacs-empty-state
     :icon "school" :title "All caught up"
     :caption "Review complete."
     :action-label "Done"
     :on-tap (jetpacs-action "srs.quit" :when-offline "drop")))
   ((jetpacs-node-supported-p "tabs")
    (glasspane-srs--session-pager))
   (t
    (apply #'jetpacs-lazy-column
           (append
            (glasspane-srs--item-nodes glasspane-srs--current
                                       glasspane-srs--revealed)
            (list (jetpacs-spacer :height 8) (jetpacs-divider))
            (if glasspane-srs--revealed
                (glasspane-srs--rating-controls)
              (list (jetpacs-button "Show answer"
                                 (jetpacs-action "srs.answer.show"
                                              :when-offline "drop")
                                 :variant "filled" :icon "visibility"))))))))

(defun glasspane-srs--session-pager ()
  "Swipe-through review: the question page ‹ the answer page.
Both pages ship in one push — `glasspane-srs--item-nodes' is a pure
renderer over the item, so the answer costs no extra round-trip — and
the pager is id-keyed per item: rating pushes the next card, whose new
id lands the pager back on its question page; undo restores a card
answer-shown, so INITIAL follows the reveal flag. on_change mirrors the
settled page into `glasspane-srs--revealed' without a re-push."
  (jetpacs-tabs
   (list (jetpacs-tab-item "Question") (jetpacs-tab-item "Answer"))
   (list
    (apply #'jetpacs-lazy-column
           (append
            (glasspane-srs--item-nodes glasspane-srs--current nil)
            (list (jetpacs-spacer :height 8)
                  (jetpacs-box
                   (list (jetpacs-text "Swipe for the answer ›" 'caption))
                   :alignment "center"))))
    (apply #'jetpacs-lazy-column
           (append
            (glasspane-srs--item-nodes glasspane-srs--current t)
            (list (jetpacs-spacer :height 8) (jetpacs-divider))
            (glasspane-srs--rating-controls))))
   :pager-only t
   :initial (if glasspane-srs--revealed 1 0)
   :id (format "srs-%x" (sxhash-equal glasspane-srs--current))
   :on-change (jetpacs-action "srs.answer.page" :when-offline "drop")))

(defun glasspane-srs--idle-body ()
  "The between-sessions screen: due summary and the start button."
  (let ((due (glasspane-srs--due-count)))
    (cond
     ((null due)
      (jetpacs-column
       (jetpacs-text "Couldn't count due items — check *Messages*." 'caption)
       (jetpacs-button "Start review"
                    (jetpacs-action "srs.review.start" :when-offline "drop")
                    :variant "filled" :icon "play_arrow")))
     ((zerop due)
      (jetpacs-empty-state :icon "school" :title "All caught up"
                        :caption "Nothing due right now."))
     (t
      (jetpacs-column
       (jetpacs-text (format "%d item%s due" due (if (= due 1) "" "s")) 'title)
       (jetpacs-spacer :height 8)
       (jetpacs-button "Start review"
                    (jetpacs-action "srs.review.start" :when-offline "drop")
                    :variant "filled" :icon "play_arrow"))))))

(defun glasspane-srs--install-body ()
  (jetpacs-empty-state
   :icon "school" :title "org-srs not installed"
   :caption (concat "Install the org-srs package (MELPA) in the on-device "
                    "Emacs — the starter init does it on first launch — "
                    "then pull to refresh.")))

(defun glasspane-srs--top-actions ()
  "Session top-bar actions — kept to the two that read at a glance:
undo (only after a rating) and close.  Postpone/suspend are niche and
their icons weren't legible; they stay as `srs.*' actions for a future
labelled menu rather than cluttering the bar."
  (delq nil
        (list
         (when glasspane-srs--undo
           (jetpacs-icon-button "undo"
                             (jetpacs-action "srs.undo" :when-offline "drop")
                             :content-description "Undo last rating"))
         (jetpacs-icon-button "close"
                           (jetpacs-action "srs.quit" :when-offline "drop")
                           :content-description "End review"))))

(defun glasspane-srs--review-body ()
  "The between-sessions Review body: flashcards, then vulpea stale files.
Stacked sections in one scroll — the flashcard half is small (a due
count and the start button), so both halves show at once.  Each half
degrades to its install prompt / to absent independently: org-srs
missing must not blank the stale list, nor vice versa."
  (let ((stale (glasspane-notes-stale-section)))
    (apply #'jetpacs-lazy-column
           (append
            (list (jetpacs-section-header "Flashcards")
                  (if (glasspane-srs-available-p)
                      (glasspane-srs--idle-body)
                    (glasspane-srs--install-body)))
            (when stale
              (cons (jetpacs-divider) stale))))))

(defun glasspane-srs--view (snackbar)
  "The Review screen for the current session state."
  (jetpacs-shell-nav-view
   "Review"
   (if glasspane-srs--active
       (glasspane-srs--session-body)
     (glasspane-srs--review-body))
   :actions (when (and glasspane-srs--active glasspane-srs--current)
              (glasspane-srs--top-actions))
   :snackbar snackbar))

(with-jetpacs-owner "glasspane"
  (jetpacs-shell-define-view "glasspane.review" :builder #'glasspane-srs--view :order 78))

;; Everyday nav (the drawer contract); no entry while both halves are
;; absent (org-srs not installed AND no stale-capable vulpea).
;; The due count rides the drawer item's badge (memoised; nil when clear).
(with-jetpacs-owner "glasspane"
  (jetpacs-shell-add-drawer-item
   45 (lambda ()
        (when (or (glasspane-srs-available-p)
                  (glasspane-notes-stale-available-p))
          (jetpacs-drawer-item "school" "Review" (jetpacs-shell-switch-view "glasspane.review")
                            :badge (let ((due (glasspane-srs--due-count)))
                                     (and (numberp due) (> due 0) due)))))))

;; ─── Actions ─────────────────────────────────────────────────────────────────

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "srs.review.start"
    (lambda (_args _)
      (if (not (glasspane-srs-available-p))
          (jetpacs-shell-notify "org-srs is not installed")
        (setq glasspane-srs--active t glasspane-srs--undo nil)
        (glasspane-srs--advance))
      (jetpacs-shell-push nil :switch-to "glasspane.review")))

  (jetpacs-defaction "srs.answer.show"
    (lambda (_args _)
      (when glasspane-srs--current (setq glasspane-srs--revealed t))
      (jetpacs-shell-push)))

  (jetpacs-defaction "srs.answer.page"
    ;; The review pager settled on a page; mirror it into the reveal flag —
    ;; no re-push (both pages already shipped), just state coherence for
    ;; undo and the button-era code path.
    (lambda (args _)
      (let ((idx (alist-get 'value args)))
        (when (and glasspane-srs--current (integerp idx))
          (setq glasspane-srs--revealed (= idx 1)))))))

(defun glasspane-srs--push-undo (item-args)
  "Snapshot ITEM-ARGS's log drawer onto the undo stack (capped).
Best-effort: a snapshot failure must not block the rating."
  (glasspane-srs--quietly
    (let ((marker (apply #'org-srs-item-marker item-args)))
      (with-current-buffer (marker-buffer marker)
        (org-with-wide-buffer
         (goto-char marker)
         (let ((log (buffer-substring-no-properties
                     (progn (org-srs-log-beginning-of-drawer) (point))
                     (progn (org-srs-log-end-of-drawer) (point)))))
           (push (cons item-args log) glasspane-srs--undo)
           (when (nthcdr 20 glasspane-srs--undo)
             (setcdr (nthcdr 19 glasspane-srs--undo) nil))))))))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "srs.rate"
    (lambda (args _)
      (let ((kw (cadr (assoc (alist-get 'rating args) glasspane-srs--ratings))))
        (when (and kw glasspane-srs--current)
          (glasspane-srs--push-undo glasspane-srs--current)
          (glasspane-srs--engine
            ;; `org-srs-review-rate' assumes a session: it reads a
            ;; buffer-local schedule offset from `(current-buffer)', which
            ;; the session normally makes the item's buffer.  Driving it in
            ;; the background we must set that up ourselves — current-buffer
            ;; = the item's buffer, and org-srs-review-item nil so it rates
            ;; the item passed in ARGS.  (Missed, the offset assert fails,
            ;; the rating never persists, and the card loops forever.)
            (let ((buf (marker-buffer
                        (apply #'org-srs-item-marker glasspane-srs--current)))
                  (org-srs-review-item nil))
              (with-current-buffer buf
                (apply #'org-srs-review-rate kw glasspane-srs--current))))
          (jetpacs-org-cache-invalidate 'glasspane)
          (glasspane-srs--advance)))
      (jetpacs-shell-push)))

  (jetpacs-defaction "srs.quit"
    (lambda (_args _)
      (setq glasspane-srs--active nil glasspane-srs--current nil
            glasspane-srs--revealed nil glasspane-srs--undo nil)
      (jetpacs-shell-push)))

  (jetpacs-defaction "srs.postpone"
    (lambda (_args _)
      (when glasspane-srs--current
        (glasspane-srs--engine
          (apply #'org-srs-review-postpone '(1 :day) glasspane-srs--current))
        (jetpacs-org-cache-invalidate 'glasspane)
        (glasspane-srs--advance))
      (jetpacs-shell-push)))

  (jetpacs-defaction "srs.suspend"
    (lambda (_args _)
      (when glasspane-srs--current
        (glasspane-srs--engine
          (let ((marker (apply #'org-srs-item-marker glasspane-srs--current)))
            (with-current-buffer (marker-buffer marker)
              (save-excursion
                (save-restriction
                  (widen)
                  (goto-char marker)
                  (org-back-to-heading t)
                  (unless (org-in-commented-heading-p) (org-toggle-comment))
                  (let ((save-silently t)) (save-buffer)))))))
        (jetpacs-org-cache-invalidate 'glasspane)
        (glasspane-srs--advance))
      (jetpacs-shell-push)))

  (jetpacs-defaction "srs.undo"
    ;; org-srs's own undo history is set up only by the session we don't
    ;; run, so we restore the item's log drawer from our own snapshot and
    ;; re-present the card (answer shown) for a fresh rating.
    (lambda (_args _)
      (if-let ((snap (pop glasspane-srs--undo)))
          (progn
            (glasspane-srs--engine
              (let* ((item-args (car snap))
                     (marker (apply #'org-srs-item-marker item-args)))
                (with-current-buffer (marker-buffer marker)
                  (org-with-wide-buffer
                   (goto-char marker)
                   (delete-region
                    (progn (org-srs-log-beginning-of-drawer) (point))
                    (progn (org-srs-log-end-of-drawer) (point)))
                   (insert (cdr snap))
                   (org-srs-log-hide-drawer)
                   (let ((save-silently t)) (save-buffer))))))
            (jetpacs-org-cache-invalidate 'glasspane)
            (setq glasspane-srs--current (car snap) glasspane-srs--revealed t))
        (jetpacs-shell-notify "Nothing to undo"))
      (jetpacs-shell-push)))

  ;; ─── Authoring: Make flashcard on the heading detail view ───────────────────

  (jetpacs-defaction "srs.item.create"
    ;; The type picker and any follow-up prompts arrive as phone dialogs
    ;; through the minibuffer bridge — write it as if at the keyboard.
    (lambda (args _)
      (if (not (glasspane-srs-available-p))
          (jetpacs-shell-notify "org-srs is not installed")
        (condition-case err
            (let ((marker (jetpacs-org-resolve-ref args)))
              (with-current-buffer (marker-buffer marker)
                (org-with-wide-buffer
                 (goto-char marker)
                 (org-srs-item-create))
                (let ((save-silently t)) (save-buffer)))
              (jetpacs-org-cache-invalidate 'glasspane)
              (jetpacs-shell-notify "Review item created"))
          (quit (jetpacs-shell-notify "Cancelled"))
          (error (jetpacs-shell-notify
                  (format "Flashcard: %s" (error-message-string err))))))
      (jetpacs-shell-push))))

(defun glasspane-srs-detail-toolbar (ref)
  "The detail floating-toolbar chip for REF: make this heading reviewable."
  (when (glasspane-srs-available-p)
    (list (jetpacs-nav-item
           "school" "Flashcard"
           (jetpacs-action "srs.item.create"
                        :args ref
                        :when-offline "drop")))))

(add-hook 'glasspane-ui-detail-toolbar-functions #'glasspane-srs-detail-toolbar)

;; ─── Settings ────────────────────────────────────────────────────────────────

(with-eval-after-load 'org-srs
  (with-jetpacs-owner "glasspane"
    (jetpacs-settings-register-section
     "Review"
     '((org-srs-review-new-items-per-day :label "New cards per day")
       (org-srs-review-max-reviews-per-day :label "Max reviews per day")))))

(provide 'glasspane-srs)
;;; glasspane-srs.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-demo.el
;;; ==================================================================

;;; glasspane-demo.el --- Guided-tour demo files for the mobile IDE -*- lexical-binding: t; -*-

;; Writes a set of small tour files into `glasspane-demo-directory' so the
;; phone editor's IDE features can be demoed on demand: completion,
;; eldoc signatures, and flymake squiggles today; each file also marks
;; what upgrades once the eglot phase lands.  A companion org corpus
;; (`glasspane-demo-setup-org') resets `org-directory' to a de-personalized
;; set of files exercising tables, babel, LaTeX, drawers, and the agenda.
;;
;; The files ship *inside the bundle* rather than as repo files because
;; Emacs's home on Android is app-private storage — adb can't push into
;; it, but Emacs itself can write there.  Run `M-x glasspane-demo-setup' (or
;; the `demo.setup' action from the phone) and the files appear under
;; the Files tab.  Setup always overwrites, so a mangled demo resets to
;; pristine by running it again.

;;; Code:

(require 'org)
(require 'jetpacs-surfaces)
;; (require 'glasspane-srs)               ; SRS registration for the flashcards — bundle-internal, provided above

(defcustom glasspane-demo-directory "~/glasspane-demo/"
  "Directory `glasspane-demo-setup' writes the tour files into.
Must lie within `jetpacs-files-roots' to be reachable from the phone's
Files browser (the default is inside the Home root)."
  :type 'directory :group 'jetpacs)

(defconst glasspane-demo--files
  `(("demo.el" . "\
;;; demo.el --- Glasspane mobile IDE tour -*- lexical-binding: t; -*-

;; Welcome!  This buffer is live-synced to your Emacs while you type.
;; Everything below runs against the real Emacs image on this device.

;; ── 1. Completion ────────────────────────────────────────────────
;; On the blank line below, type   (buffer-sub   and pause.
;; Chips appear above the keyboard; tap one to accept — mobile TAB.


;; ── 2. Signatures (eldoc) ────────────────────────────────────────
;; Tap to place the cursor inside the `concat' call below and pause.
;; Its signature appears in the doc line above the keyboard.

(defun demo-greet (name)
  \"Return a friendly greeting for NAME.\"
  (concat \"Hello, \" name \"!\"))

;; ── 3. Diagnostics (flymake) ─────────────────────────────────────
;; A few seconds after this file opens, the real byte-compiler flags
;; the two functions below with squiggles.  Tap inside one to read
;; its message in the doc line.

(defun demo-unused (thing)
  \"THING is never used, and the byte-compiler notices.\"
  42)

(defun demo-wrong-arity ()
  \"Calls `demo-greet' with one argument too many.\"
  (demo-greet \"world\" 'oops))

;; ── 4. Break something yourself ──────────────────────────────────
;; Delete the closing paren of any defun above and pause: a squiggle
;; appears.  Undo, pause, and it clears.

(provide 'demo)
;;; demo.el ends here
")
    ("demo.py" . "\
\"\"\"Glasspane mobile IDE tour - Python.

With pylsp installed in Termux (pip install python-lsp-server) and
the eglot bridge on, this file gets REAL language-server completion,
hover, and diagnostics.  Without a server it degrades gracefully to
same-buffer word completion.
\"\"\"


def fibonacci(n: int) -> int:
    \"\"\"Return the n-th Fibonacci number (naive on purpose).\"\"\"
    if n < 2:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)


def fibonacci_sequence(count: int) -> list[int]:
    \"\"\"Return the first COUNT Fibonacci numbers.\"\"\"
    return [fibonacci(i) for i in range(count)]


# 1. Completion: on the line below, type   fib   and pause.
#    With pylsp: type   fibonacci_sequence(10).   for list methods.


# 2. Diagnostics (needs pyflakes: pip install pyflakes in Termux).
#    Both lines below earn squiggles from the server:
import os  # <- 'os' imported but unused


def uses_an_undefined_name():
    return undefined_name  # <- undefined name

if __name__ == \"__main__\":
    print(fibonacci_sequence(10))
")
    ("demo.sh" . "\
#!/data/data/com.termux/files/usr/bin/bash
# Glasspane mobile IDE tour - Shell.
#
# The most on-brand language here: sh-mode is built into Emacs, and
# bash-language-server installs straight into Termux
# (npm install -g bash-language-server) for full LSP via eglot.
# Without it: same-buffer word completion still works.

greet_user() {
    local name=\"$1\"
    echo \"Hello, ${name}!\"
}

count_greetings() {
    local total=\"$1\"
    for i in $(seq 1 \"$total\"); do
        greet_user \"friend #$i\"
    done
}

# 1. Completion: on the line below, type   gre   and pause.


count_greetings 3
")
    ("demo.c" . "\
/* Glasspane mobile IDE tour - C.
 *
 * Tree-sitter: with the c grammar installed and c-mode remapped to
 * c-ts-mode in your init, this file's colors come from tree-sitter,
 * pushed by Emacs (fontify.show) in your real theme.
 *
 * LSP: with clangd on the exec-path (Termux), eglot adds completion,
 * hover, and diagnostics. Without it: word completion still works.
 */

#include <stdio.h>

static long fibonacci(int n) {
    return n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2);
}

static void print_sequence(int count) {
    for (int i = 0; i < count; i++) {
        printf(\"%ld\\n\", fibonacci(i));
    }
}

/* 1. Completion: on the line below, type   fib   and pause.
 * 2. With clangd: add an undefined call like  missing();  inside
 *    main and pause for the squiggle. */


int main(void) {
    print_sequence(10);
    return 0;
}
")
    ("demo.org" . "\
#+title: Glasspane mobile IDE tour — Org

This file opens in the foldable reader; toggle to the raw editor
to try the features below.

* What works in org today
- Word completion from this buffer: type =comp= in the scratch
  section and pause.
- The org formatting toolbar sits under the editor.

* TODO Try tag completion                                    :server:
If your init opts =my/org-tag-completion= into shadow buffers via
=jetpacs-sync-shadow-setup-hook=, typing =:ser= at the end of a
headline completes your =:server:= tag from the phone.

* Scratch space
Type here — completion offers words already in this file, like
completion or formatting or headline.
"))
  "Alist of (FILENAME . CONTENT) written by `glasspane-demo-setup'.")

;; ─── Demo org corpus ─────────────────────────────────────────────────────────
;; A small, de-personalized set of org files exercising every rendering
;; feature the phone supports: native tables with #+TBLFM recalculation,
;; babel blocks (run-button gating included), LaTeX fragments (for when
;; preview lands), drawers, statistics cookies, footnotes, id: links,
;; repeaters, and custom TODO keywords.  Written into `org-directory' by
;; `glasspane-demo-setup-org' — same ship-inside-the-bundle rationale as
;; the tour files above.

(defconst glasspane-demo--org-files
  '(("health.org" . "\
#+TITLE: Health & Fitness
#+STARTUP: overview
#+TODO: TODO IN-PROGRESS | DONE CANCELLED

* Training Log
:PROPERTIES:
:ID:       8f5d7c3a-c707-4cf3-bcdb-4d8019d57bc6
:END:
Tap a cell to edit it — the totals row recalculates in Emacs.

| Date             | Push-Ups | Squats | Miles |
|------------------+----------+--------+-------|
| [2026-06-29 Mon] |       40 |     60 |   2.5 |
| [2026-07-01 Wed] |       45 |     65 |   3.1 |
| [2026-07-03 Fri] |       50 |     70 |   2.8 |
|------------------+----------+--------+-------|
| Total            |      135 |    195 |   8.4 |
#+TBLFM: @>$2=vsum(@I..@II)::@>$3=vsum(@I..@II)::@>$4=vsum(@I..@II);%.1f

** Weekly routine [2/4]
- [X] Run 5K
- [X] Yoga session
- [ ] Long hike
- [ ] Strength training

* Goals
:PROPERTIES:
:ID:       6cb4432e-b24a-437d-9278-0421d01155eb
:END:
** IN-PROGRESS [#A] Hike a rim-to-rim canyon route             :fitness:goal:
DEADLINE: <2026-08-15 Sat>
:PROPERTIES:
:Effort:   8h
:ID:       d825ffc9-1160-49cc-b2d0-113c7436deb7
:END:
:LOGBOOK:
CLOCK: [2026-07-01 Wed 06:30]--[2026-07-01 Wed 07:15] =>  0:45
:END:
Need to build up to *20+ mile* days.  Current max: /about 12 miles/.

** IN-PROGRESS Run a sub-25 minute 5K                                 :goal:
SCHEDULED: <2026-07-06 Mon> DEADLINE: <2026-08-01 Sat>
:PROPERTIES:
:ID:       6c4b91a5-b4f6-43ea-8ad9-56d1ac8e8e03
:END:
:LOGBOOK:
CLOCK: [2026-07-02 Thu 18:10]--[2026-07-02 Thu 18:40] =>  0:30
- Note taken on [2026-07-02 Thu 18:45] \\\\
  Negative splits felt easier this week.
:END:
Recent attempts:

| Date             |  Time |
|------------------+-------|
| [2026-06-20 Sat] | 28:11 |
| [2026-06-27 Sat] | 27:42 |

** TODO Weekly long run                                            :fitness:
SCHEDULED: <2026-07-05 Sun +1w>
:PROPERTIES:
:ID:       a91d1e27-afc6-4b24-b5bc-e916730f6043
:END:

** DONE Complete 30-day yoga challenge                        :fitness:goal:
CLOSED: [2026-06-26 Fri 18:00]
:PROPERTIES:
:ID:       a5504036-77b4-42f5-89bd-ffbad8038822
:END:

* Reference
:PROPERTIES:
:ID:       3d83cd97-6188-4074-9c66-6c273c6a89d5
:END:
:NUTRITION:
Protein target: 140 g/day.  Hydration: 3 L minimum.
:END:
Resting heart rate trend: 58 \\rightarrow 54 bpm since March.
")
    ("inbox.org" . "\
#+TITLE: Inbox
#+STARTUP: overview
#+TODO: TODO IDEA | DONE

* TODO Read /Designing Data-Intensive Applications/, chapter 6     :reading:
SCHEDULED: <2026-07-06 Mon>
:PROPERTIES:
:Effort:   1h
:ID:       5359bbea-6de3-4aba-bc86-fb46122005d3
:END:
The partitioning chapter pairs well with the replication notes[fn:1].

** Highlights so far
:PROPERTIES:
:ID:       e372b40c-f1fe-490a-9832-3b517af0309c
:END:
- Rebalancing strategies: fixed partitions vs. dynamic splitting
- Request routing belongs in a /separate/ layer

* TODO Look into Nix flakes for a reproducible dev setup          :computer:
:PROPERTIES:
:Effort:   1h
:ID:       2bfc9a36-831f-4bcc-8431-d7373a47e151
:END:

* TODO Fix the leaky faucet in the guest bathroom                     :home:
SCHEDULED: <2026-07-07 Tue>
:PROPERTIES:
:ID:       eda8dcb1-311e-400a-b713-25b73941bcaf
:END:

* IDEA Kanban board backed by plain org files                      :project:
:PROPERTIES:
:ID:       a0a70496-49c8-475d-bbc6-b507e8c43d82
:END:
Columns map to TODO keywords; drag-and-drop rewrites the keyword.
Could run on the [[id:86b18efc-f950-4c22-b006-5af19d0e1a74][home server]].

* TODO [#B] Renew the domain registration                            :admin:
SCHEDULED: <2026-07-08 Wed> DEADLINE: <2026-07-31 Fri>
:PROPERTIES:
:Effort:   10min
:ID:       cff8c2b4-da5a-46c1-aab4-9661c6e65368
:END:
Registrar dashboard: [[https://example.com/domains][example.com/domains]]

* TODO Order a replacement HEPA filter                          :home:errand:
SCHEDULED: <2026-07-05 Sun>
:PROPERTIES:
:ID:       2bf199b2-ab05-430d-a48c-81550252f6c3
:END:

* TODO [#A] Back up phone photos [0/3]                             :digital:
DEADLINE: <2026-07-09 Thu>
:PROPERTIES:
:Effort:   30min
:ID:       68fbf216-c578-41f1-b570-2b52ed092d13
:END:
- [ ] Mount the network share
- [ ] Sync the camera folder
- [ ] Verify checksums

* Footnotes

[fn:1] Chapter 5, replication — reread the section on quorums.
")
    ("project.org" . "\
#+TITLE: Projects
#+STARTUP: overview
#+TODO: TODO IN-PROGRESS | DONE CANCELLED

* Mobile companion app                                            :software:
:PROPERTIES:
:ID:       f95e563c-62e9-4c8a-bff6-eef9194f9660
:END:
** DONE [#A] Phase 1 — Core features
DEADLINE: <2026-06-15 Mon>
:PROPERTIES:
:Effort:   20h
:ID:       9bfcf1a9-b6bb-48fd-9b21-898804c6036e
:END:
*** DONE Foldable document reader
CLOSED: [2026-06-11 Thu 16:45]
:PROPERTIES:
:ID:       61a44fea-a312-4b53-93a5-3e9147d4c2bf
:END:
*** DONE Agenda with day/week/month views
CLOSED: [2026-06-12 Fri 10:20]
:PROPERTIES:
:ID:       0b6cfc7f-0a29-438a-a25d-2d2d07c97677
:END:
*** DONE Search across files
CLOSED: [2026-06-12 Fri 17:02]
:PROPERTIES:
:ID:       9142df4e-e85a-4cf1-9675-943e16da5e47
:END:

** IN-PROGRESS [#B] Phase 2 — Rich content
SCHEDULED: <2026-07-01 Wed>
:PROPERTIES:
:ID:       933b2dfe-0b63-46ad-a4c4-6bfa8a847b2c
:END:
*** DONE Native tables with formula recalculation
CLOSED: [2026-07-04 Sat 18:30]
:PROPERTIES:
:ID:       abcfe479-27c0-4d86-b336-ad8d56e3c700
:END:
*** TODO Inline LaTeX previews
:PROPERTIES:
:ID:       c8d7b18d-de46-4934-aab4-ef46096a4de5
:END:
Fixtures live in [[id:53e5ad9b-a66d-480b-b91a-050f526515ab][Calculus — the Gaussian integral]].
*** TODO Transcluded sections
:PROPERTIES:
:ID:       71a8da2a-c295-4b30-807b-bb845bf72fd7
:END:

** TODO [#C] Phase 3 — Polish & distribution
SCHEDULED: <2026-08-01 Sat>
:PROPERTIES:
:ID:       7ca33acb-b76d-4e5b-b980-cae51fccb33b
:END:
*** TODO Packaging for app stores
*** TODO Landing page and README
*** TODO Demo video

** Build size tracking
:PROPERTIES:
:ID:       5e097c4d-442a-4376-b691-7b513864a666
:END:
Run the block to regenerate the table below it — the same trick as the
Babel playground over in the study notes.

#+begin_src emacs-lisp :results table
(mapcar (lambda (r) (list (car r) (cdr r)))
        '((\"v0.1\" . 3.9) (\"v0.2\" . 4.6) (\"v0.3\" . 5.2)))
#+end_src

#+RESULTS:
| v0.1 | 3.9 |
| v0.2 | 4.6 |
| v0.3 | 5.2 |

* Home server                                                     :selfhost:
:PROPERTIES:
:ID:       86b18efc-f950-4c22-b006-5af19d0e1a74
:END:
** DONE [#B] Migrate file sync to the new VPS                    :migration:
CLOSED: [2026-06-30 Tue 21:00]
:PROPERTIES:
:Effort:   4h
:ID:       ec0731bb-ff11-4632-b25c-5409ee1325c6
:END:

** TODO Set up a WireGuard tunnel to the phone                  :networking:
SCHEDULED: <2026-07-10 Fri>
:PROPERTIES:
:Effort:   2h
:ID:       b66f76ee-b3d6-414e-a7c9-cf7888ba26c9
:END:

** TODO [#A] Fix the failing backup cron job                        :urgent:
DEADLINE: <2026-07-05 Sun>
:PROPERTIES:
:Effort:   1h
:ID:       17ada464-8c94-4827-afe1-981cc8955492
:END:
The unit fires but the target never mounts.  Current crontab entry:

#+begin_example
0 3 * * * /usr/local/bin/backup.sh --incremental
#+end_example

Check the mount from the phone:

#+begin_src sh :results output
df -h | head -3
#+end_src

* Side projects                                                        :fun:
:PROPERTIES:
:ID:       4fa298a0-5c68-442a-ba4c-b3c71adc00cf
:END:
** TODO CLI pomodoro timer in Rust                                    :rust:
:PROPERTIES:
:Effort:   4h
:ID:       f263c776-dc0c-4998-8c34-72cbc93b77c7
:END:
The run button only appears for languages this Emacs can execute:

#+begin_src rust
fn main() {
    println!(\"25:00 — focus\");
}
#+end_src

** DONE ASCII-art welcome banner for the terminal
CLOSED: [2026-06-20 Sat 12:00]
:PROPERTIES:
:ID:       bbdf1a74-406f-4c12-866a-046462853f63
:END:
")
    ("notes.org" . "\
#+TITLE: Study Notes
#+STARTUP: overview

* Calculus — the Gaussian integral                                    :math:
:PROPERTIES:
:ID:       53e5ad9b-a66d-480b-b91a-050f526515ab
:END:
The definite integral every statistics course leans on:

\\[ \\int_{-\\infty}^{\\infty} e^{-x^2} \\, dx = \\sqrt{\\pi} \\]

Inline fragments work too: the normal density peaks at
\\(1/\\sqrt{2\\pi\\sigma^2}\\).

Related: [[id:94bff2e9-8e82-40d5-9403-b9278cc3a1ec][Physics — mass–energy equivalence]]

* Physics — mass–energy equivalence                                :physics:
:PROPERTIES:
:ID:       94bff2e9-8e82-40d5-9403-b9278cc3a1ec
:END:
Einstein's E = mc^{2} relates rest mass to energy.  Water is H_{2}O;
the decay \\alpha \\rightarrow \\beta + \\gamma conserves both.

* Chemistry reference table                                           :chem:
:PROPERTIES:
:ID:       4ff4f602-382c-4e15-9ce5-faf3d7525daa
:END:
Alignment cookies pin each column: left, center, right.

| Element  | Symbol | Atomic mass |
| <l>      |  <c>   |         <r> |
|----------+--------+-------------|
| Hydrogen |   H    |       1.008 |
| Carbon   |   C    |      12.011 |
| Nitrogen |   N    |      14.007 |
| Oxygen   |   O    |      15.999 |

* Babel playground                                                    :code:
:PROPERTIES:
:ID:       ba4b6d51-efe5-44b7-a702-a302d5c3e27d
:END:
Tap the play button on a block to execute it in Emacs on this device.
Grace Hopper would have insisted on a shell block, so there is one below.

#+begin_src emacs-lisp
(emacs-version)
#+end_src

#+begin_src emacs-lisp :results table
(mapcar (lambda (n) (list n (* n n) (* n n n)))
        (number-sequence 1 5))
#+end_src

#+RESULTS:
| 1 |  1 |   1 |
| 2 |  4 |   8 |
| 3 |  9 |  27 |
| 4 | 16 |  64 |
| 5 | 25 | 125 |

Shell blocks need =(shell . t)= in =org-babel-load-languages=:

#+begin_src sh :results output
uname -o && whoami
#+end_src

* A linked image
:PROPERTIES:
:ID:       c60ffce1-4449-4689-87a0-d8489b262e42
:END:
Remote images render inline when the device is online:

[[https://picsum.photos/seed/orgdemo/600/300.jpg]]
")
    ("quotes.org" . "\
#+TITLE: Quotes
#+STARTUP: overview

* Marcus Aurelius
:PROPERTIES:
:ID:       8249dcbc-7d87-4c0e-a8b2-58fbd1245091
:END:
#+begin_quote
You have power over your mind — not outside events.  Realize this,
and you will find strength.
#+end_quote
Captured: [2026-05-15 Fri 08:30]

* Alan Kay
:PROPERTIES:
:ID:       8fee047a-29e5-4ef0-93df-cc8462ac56b4
:END:
#+begin_quote
The best way to predict the future is to /invent/ it.
#+end_quote
Captured: [2026-05-28 Thu 14:22]
A fitting motto for the [[id:f95e563c-62e9-4c8a-bff6-eef9194f9660][Mobile companion app]].

* Grace Hopper
:PROPERTIES:
:ID:       9142df4e-0000-4cf1-9675-943e16da5e47
:END:
#+begin_quote
The most dangerous phrase in the language is, \\\"We've always done it
this way.\\\"
#+end_quote
Captured: [2026-06-05 Fri 19:45]

* Antoine de Saint-Exupéry
:PROPERTIES:
:ID:       933b2dfe-0000-46ad-a4c4-6bfa8a847b2c
:END:
#+begin_verse
Perfection is achieved, not when there is nothing more to add,
but when there is nothing left to take away.
#+end_verse
Captured: [2026-06-18 Thu 09:12]

* Carver Mead
:PROPERTIES:
:ID:       abcfe479-0000-4d86-b336-ad8d56e3c700
:END:
#+begin_quote
Listen to the technology; find out what it's telling you.
#+end_quote
Captured: [2026-07-01 Wed 16:40]
")
    ("trackers.org" . "\
#+TITLE: Task Tracker
#+STARTUP: overview
#+TODO: TODO IN-PROGRESS | DONE CANCELLED

* IN-PROGRESS [#A] Prepare the quarterly demo                         :work:
DEADLINE: <2026-07-06 Mon>
:PROPERTIES:
:Effort:   45min
:ID:       eda8dcb1-0000-400a-b713-25b73941bcaf
:END:
:LOGBOOK:
CLOCK: [2026-07-03 Fri 08:20]--[2026-07-03 Fri 08:34] =>  0:14
CLOCK: [2026-07-02 Thu 09:00]--[2026-07-02 Thu 10:21] =>  1:21
:END:
Slides: [[https://example.com/slides][deck draft]]

* TODO [#A] Finish the agenda screen                              :software:
SCHEDULED: <2026-07-06 Mon>
:PROPERTIES:
:Effort:   2h
:ID:       a0a70496-0000-475d-bbc6-b507e8c43d82
:END:
:LOGBOOK:
CLOCK: [2026-06-29 Mon 02:39]--[2026-06-29 Mon 04:00] =>  1:21
:END:
** TODO Wire up the date-picker component
DEADLINE: <2026-07-07 Tue>
:PROPERTIES:
:ID:       86b18efc-0000-4c22-b006-5af19d0e1a74
:END:
** DONE Parse the agenda payload on the client
CLOSED: [2026-07-01 Wed 14:32]
:PROPERTIES:
:ID:       cff8c2b4-0000-46c1-aab4-9661c6e65368
:END:
** DONE Add the swipe-to-archive gesture
CLOSED: [2026-06-29 Mon 02:13]
:PROPERTIES:
:ID:       2bf199b2-0000-430d-a48c-81550252f6c3
:END:
:LOGBOOK:
CLOCK: [2026-06-29 Mon 02:08]--[2026-06-29 Mon 02:13] =>  0:05
:END:

* TODO Weekly grocery run                                           :errand:
SCHEDULED: <2026-07-07 Tue +1w>
:PROPERTIES:
:ID:       68fbf216-0000-41f1-b570-2b52ed092d13
:LAST_REPEAT: [2026-06-30 Tue 18:37]
:END:
:LOGBOOK:
- State \"DONE\"       from \"TODO\"       [2026-06-30 Tue 18:37]
:END:

* IN-PROGRESS Call the insurance company about the claim      :phone:errand:
SCHEDULED: <2026-07-06 Mon>
:PROPERTIES:
:ID:       f95e563c-0000-4c8a-bff6-eef9194f9660
:END:

* IN-PROGRESS [#B] Write a blog post about server-driven UI        :writing:
SCHEDULED: <2026-07-08 Wed> DEADLINE: <2026-07-12 Sun>
:PROPERTIES:
:Effort:   2h
:ID:       9bfcf1a9-0000-48fd-9b21-898804c6036e
:END:
:LOGBOOK:
CLOCK: [2026-07-02 Thu 22:20]--[2026-07-02 Thu 22:33] =>  0:13
CLOCK: [2026-07-01 Wed 20:05]--[2026-07-01 Wed 20:35] =>  0:30
:END:
Outline: what /server-driven/ buys you on mobile, and where it hurts.

* DONE [#B] Set up folder sync between phone and laptop              :sync:
CLOSED: [2026-06-27 Sat 11:40]
:PROPERTIES:
:Effort:   1h
:ID:       61a44fea-0000-4b53-93a5-3e9147d4c2bf
:END:

* DONE Clean the kitchen                                              :home:
CLOSED: [2026-07-03 Fri 21:30]
:PROPERTIES:
:ID:       0b6cfc7f-0000-438a-a25d-2d2d07c97677
:END:

* DONE Send the invoice to the client                         :work:finance:
CLOSED: [2026-07-02 Thu 09:15]
:PROPERTIES:
:Effort:   15min
:ID:       9142df4e-1111-4cf1-9675-943e16da5e47
:END:
")
    ("flashcards.org" . "\
#+TITLE: Flashcards
#+STARTUP: overview

Spaced repetition over the study notes (drawer → Review on the phone).
Plain org until org-srs is installed — the demo setup registers these
as review items automatically when it is.

* What does the Gaussian integral evaluate to?
:PROPERTIES:
:ID:       7c2e91d4-5a38-4f61-9b0e-3d84a2c6f105
:END:
√π — [[id:53e5ad9b-a66d-480b-b91a-050f526515ab][Calculus — the Gaussian integral]]
walks through the polar-coordinates trick.
* Mass–energy equivalence
:PROPERTIES:
:ID:       b19f4e73-2c60-4585-8aa1-64f0d3b7e2c9
:END:
State Einstein's relation between rest mass and energy.
** Back
E = mc² — derivation notes live in
[[id:94bff2e9-8e82-40d5-9403-b9278cc3a1ec][Physics — mass–energy equivalence]].
* The first computer bug
:PROPERTIES:
:ID:       e4a8c1f6-97b2-4d3e-8c05-1f6a9d24b380
:END:
The first actual case of bug being found: operators taped a moth into
the Harvard Mark II logbook in 1947.
"))
  "Alist of (FILENAME . CONTENT) written by `glasspane-demo-setup-org'.")

;; ─── SRS registration for the flashcards file ────────────────────────────────

(declare-function org-srs-item-new "org-srs-item")
(declare-function org-srs-item-cloze-default "org-srs-item-cloze")
(declare-function org-srs-item-cloze-update-entry "org-srs-item-cloze")

(defconst glasspane-demo--srs-cards
  '("What does the Gaussian integral evaluate to?"
    "Mass–energy equivalence")
  "flashcards.org headings the demo registers as `card' items.")

(defconst glasspane-demo--srs-clozes
  '(("The first computer bug" "a moth" "1947"))
  "(HEADING TARGET…) rows the demo registers as cloze items.
Each TARGET is clozed in place, then the entry's items are created.")

(defun glasspane-demo--srs-goto-heading (heading)
  "Move point to HEADING's line in the current org buffer."
  (goto-char (point-min))
  (re-search-forward (format org-complex-heading-regexp-format
                             (regexp-quote heading)))
  (beginning-of-line))

(defun glasspane-demo--register-srs-items (dir)
  "Register DIR's flashcards.org entries as org-srs review items.
A no-op without org-srs — the file reads as plain org either way.
Runs right after the corpus overwrote the files, so previously
registered drawers are gone and every item is created fresh.  Errors
cost the registration, never the demo setup."
  (when (glasspane-srs-available-p)
    (condition-case err
        (with-current-buffer
            (find-file-noselect (expand-file-name "flashcards.org" dir))
          ;; The buffer may predate the overwrite; the disk copy rules.
          (revert-buffer :ignore-auto :noconfirm)
          (org-with-wide-buffer
           (dolist (heading glasspane-demo--srs-cards)
             (glasspane-demo--srs-goto-heading heading)
             (org-srs-item-new 'card))
           (pcase-dolist (`(,heading . ,targets) glasspane-demo--srs-clozes)
             (dolist (target targets)
               ;; Re-locate per target: each cloze wrap shifts positions.
               (glasspane-demo--srs-goto-heading heading)
               (search-forward target (org-entry-end-position))
               (org-srs-item-cloze-default (match-beginning 0)
                                           (match-end 0)))
             (glasspane-demo--srs-goto-heading heading)
             (org-srs-item-cloze-update-entry)))
          (let ((save-silently t)) (save-buffer)))
      (error (message "glasspane-demo: SRS registration failed: %s"
                      (error-message-string err))))))

;; ─── Relative dates ──────────────────────────────────────────────────────────

(defconst glasspane-demo--org-anchor "2026-07-06"
  "The \"today\" the org corpus above was authored against.
Setup shifts every timestamp by (today − anchor) days at write time,
so the corpus always lands with its authored spread — overdue items,
a today, a tomorrow, deadlines weeks out — relative to the day the
command runs.  Editing corpus dates means re-anchoring this to the
new authoring day.")

(defun glasspane-demo--noon (date)
  "Encoded noon of DATE (\"YYYY-MM-DD\"); noon dodges DST date flips."
  (encode-time 0 0 12
               (string-to-number (substring date 8 10))
               (string-to-number (substring date 5 7))
               (string-to-number (substring date 0 4))))

(defun glasspane-demo--shift-timestamps (content days)
  "CONTENT with every day-named \"YYYY-MM-DD Day\" date moved DAYS forward.
One rewrite covers every org form in the corpus — active and inactive
stamps, CLOCK ranges, CLOSED/LAST_REPEAT entries, table rows — because
all of them carry the day-named date; whatever follows it (a time, a
repeater cookie) rides along untouched.  Day names are recomputed in
the C locale to match the corpus style, and the fixed-width stamp
keeps table alignment intact."
  (if (zerop days) content
    (let ((system-time-locale "C"))
      (replace-regexp-in-string
       "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} \\(?:Mon\\|Tue\\|Wed\\|Thu\\|Fri\\|Sat\\|Sun\\)"
       (lambda (stamp)
         (format-time-string
          "%Y-%m-%d %a"
          (time-add (glasspane-demo--noon (substring stamp 0 10))
                    (days-to-time days))))
       content t t))))

(defun glasspane-demo--org-shift ()
  "Days from the corpus's authoring anchor to today."
  (- (time-to-days (current-time))
     (time-to-days (glasspane-demo--noon glasspane-demo--org-anchor))))

;;;###autoload
(defun glasspane-demo-setup-org (&optional dir)
  "Write the demo org corpus into DIR (default `org-directory').
Overwrites exactly the files named in `glasspane-demo--org-files' —
other files in the directory are untouched.  Timestamps land relative
to today: the authored dates shift as one block (see
`glasspane-demo--org-anchor'), so the agenda always opens onto the
same mix of overdue, due-today, and upcoming items.  Returns DIR."
  (interactive)
  (let ((dir (file-name-as-directory
              (expand-file-name
               (or dir
                   (and (boundp 'org-directory) org-directory)
                   "~/org/"))))
        (shift (glasspane-demo--org-shift))
        (coding-system-for-write 'utf-8))
    (make-directory dir t)
    (dolist (spec glasspane-demo--org-files)
      (write-region (glasspane-demo--shift-timestamps (cdr spec) shift)
                    nil (expand-file-name (car spec) dir)
                    nil 'silent))
    ;; The flashcards become live review items when org-srs is around.
    (glasspane-demo--register-srs-items dir)
    ;; Agenda/search memos now describe files that no longer exist.
    (jetpacs-org-cache-invalidate 'glasspane)
    (when (called-interactively-p 'interactive)
      (message "Demo org corpus written to %s" dir))
    dir))

;;;###autoload
(defun glasspane-demo-setup (&optional dir)
  "Write the mobile-IDE tour files into DIR (default `glasspane-demo-directory').
Existing copies are overwritten so the tour always starts pristine.
Returns the directory the files were written to."
  (interactive)
  (let ((dir (file-name-as-directory
              (expand-file-name (or dir glasspane-demo-directory))))
        ;; The tour files contain non-ASCII (section rules, em-dashes);
        ;; pin utf-8 so no platform default can make write-region prompt.
        (coding-system-for-write 'utf-8))
    (make-directory dir t)
    (dolist (spec glasspane-demo--files)
      (write-region (cdr spec) nil (expand-file-name (car spec) dir)
                    nil 'silent))
    (when (called-interactively-p 'interactive)
      (message "Jetpacs demo files written to %s" dir))
    dir))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "demo.setup"
    ;; Allowlisted and argument-free: always writes the fixed file set into
    ;; `glasspane-demo-directory' — nothing on the wire chooses paths or content.
    (lambda (_ _)
      (glasspane-demo-setup)
      (when (fboundp 'jetpacs-shell-notify)
        (jetpacs-shell-notify
         (format "Demo files in %s"
                 (abbreviate-file-name
                  (expand-file-name glasspane-demo-directory)))))))

  (jetpacs-defaction "demo.setup-org"
    ;; Same shape as demo.setup: argument-free, fixed file set, fixed target
    ;; (`org-directory').  Overwrites the six corpus files — reset-to-pristine
    ;; is the point — but never touches anything else in the directory.
    (lambda (_ _)
      (let ((dir (glasspane-demo-setup-org)))
        (when (fboundp 'jetpacs-shell-notify)
          (jetpacs-shell-notify
           (format "Demo org corpus in %s" (abbreviate-file-name dir)))))
      (when (fboundp 'jetpacs-shell-push)
        (jetpacs-shell-push)))))

(provide 'glasspane-demo)
;;; glasspane-demo.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-gallery.el
;;; ==================================================================

;;; glasspane-gallery.el --- Interactive widget-primitives gallery -*- lexical-binding: t; -*-

;; A live demo of the platform's rendering primitives — charts, the canvas
;; interpreter, slider, sizing/border/spacing — wired together so the
;; interactive loop is visible: the slider drives a canvas gauge, chips
;; switch the chart kind, tapping a chart point reports its value.  Reached
;; from the drawer ("Widget Gallery"), the `demo.gallery' action, or
;; `M-x glasspane-demo-gallery' — the newest of the demo commands next to
;; `glasspane-demo-setup'.
;;
;; Everything here is composed from core `jetpacs-*' constructors: it is also
;; the worked example that a whole visual surface is Elisp, no Kotlin.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-surfaces)

(defvar glasspane-gallery--open nil
  "Non-nil while the gallery overlay is showing.")
(defvar glasspane-gallery--kind "line"
  "The chart kind the gallery currently renders.")
(defvar glasspane-gallery--level 0.5
  "The gauge value (0.0-1.0) the slider last set.")

;; ─── Canvas gauge (geometry computed here, drawn by the canvas node) ─────────

(defun glasspane-gallery--arc-points (cx cy r a0 a1 n)
  "N+1 points along the arc A0→A1 degrees, centre (CX CY), radius R.
Screen y grows downward, so a top semicircle spans 180°→0°."
  (cl-loop for i from 0 to n
           for a = (+ a0 (* (- a1 a0) (/ (float i) n)))
           for rad = (degrees-to-radians a)
           collect (list (+ cx (* r (cos rad))) (- cy (* r (sin rad))))))

(defun glasspane-gallery--gauge (level)
  "A semicircular canvas gauge filled to LEVEL (0.0-1.0)."
  (let* ((w 240) (h 132) (cx 120) (cy 116) (r 95)
         (end (- 180 (* 180 (max 0.0 (min 1.0 level)))))
         (na (degrees-to-radians end))
         (nx (+ cx (* r 0.9 (cos na))))
         (ny (- cy (* r 0.9 (sin na)))))
    (jetpacs-canvas
     w h
     (list (jetpacs-draw-path (glasspane-gallery--arc-points cx cy r 180 0 44)
                           :color "#8888aa" :stroke 12)
           (jetpacs-draw-path (glasspane-gallery--arc-points cx cy r 180 end 44)
                           :color "#00A676" :stroke 12)
           (jetpacs-draw-line cx cy nx ny :color "#E64980" :stroke 3)
           (jetpacs-draw-circle cx cy 7 :fill t :color "#E64980")
           (jetpacs-draw-text cx 74 (format "%d%%" (round (* 100 level)))
                           :align "center" :size 28 :color "primary")))))

;; ─── Body ────────────────────────────────────────────────────────────────────

(defun glasspane-gallery--kind-chips ()
  "A chip rail selecting `glasspane-gallery--kind'."
  (apply #'jetpacs-flow-row
         (append
          (mapcar (lambda (k)
                    (jetpacs-chip k
                               :selected (equal k glasspane-gallery--kind)
                               :on-tap (jetpacs-action "demo.gallery.kind"
                                                    :args (list (cons 'kind k)))))
                  '("line" "bar" "area" "sparkline"))
          (list :spacing 8))))

(defun glasspane-gallery--body ()
  "The scrollable gallery content (a `lazy_column', so it scrolls)."
  (jetpacs-lazy-column
   (jetpacs-section-header "Chart — tap a point, switch the kind")
   (glasspane-gallery--kind-chips)
   (jetpacs-chart
    (list (jetpacs-chart-series '(3 7 4 9 6 8 5) :label "alpha" :color "#4C6FFF")
          (jetpacs-chart-series '(5 4 6 5 7 5 8) :label "beta"))
    :kind glasspane-gallery--kind :height 150 :summary "two sample series"
    :on-point-tap (jetpacs-action "demo.gallery.point"))
   (jetpacs-divider)
   (jetpacs-section-header "Slider → live canvas gauge")
   (jetpacs-slider "gallery.level" (jetpacs-action "demo.gallery.level")
                :value glasspane-gallery--level :min 0.0 :max 1.0)
   (glasspane-gallery--gauge glasspane-gallery--level)
   (jetpacs-divider)
   (jetpacs-section-header "Sizing · border · spacing · align")
   (jetpacs-row
    (jetpacs-surface (list (jetpacs-text "100×64"))
                  :width 100 :height 64
                  :border (jetpacs-border :width 2 :color "primary"))
    (jetpacs-surface (list (jetpacs-text "rounded, fills rest"))
                  :height 64 :color "surface_container" :shape "rounded"
                  :fill-fraction 1.0)
    :spacing 12 :align "center")
   (jetpacs-spacer :height 12)))

(defun glasspane-gallery--view (snackbar)
  "The gallery as a back-arrow nav view."
  (jetpacs-shell-nav-view "Widget Gallery" (glasspane-gallery--body)
                       :snackbar snackbar))

;; ─── Actions ─────────────────────────────────────────────────────────────────

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "demo.gallery"
    (lambda (_args _payload)
      (setq glasspane-gallery--open t)
      (jetpacs-shell-push nil :switch-to "glasspane.gallery")))

  (jetpacs-defaction "demo.gallery.kind"
    (lambda (args _payload)
      (setq glasspane-gallery--kind (or (alist-get 'kind args) "line"))
      (jetpacs-shell-push)))

  (jetpacs-defaction "demo.gallery.level"
    (lambda (args _payload)
      (setq glasspane-gallery--level (or (alist-get 'value args) 0.5))
      (jetpacs-shell-push)))

  (jetpacs-defaction "demo.gallery.point"
    (lambda (args _payload)
      (let ((v (alist-get 'value args)))
        (when (fboundp 'jetpacs-shell-notify)
          (jetpacs-shell-notify (format "point %s = %s"
                                     (alist-get 'index v) (alist-get 'y v)))))
      (jetpacs-shell-push)))

  ;; ─── Registration ────────────────────────────────────────────────────────────

  (jetpacs-shell-define-view "glasspane.gallery"
    :builder #'glasspane-gallery--view
    :when (lambda () glasspane-gallery--open)
    :overlay (lambda () glasspane-gallery--open)
    :order 120))

;; Landing on any real view closes the overlay (mirrors the detail drill-in).
(add-hook 'jetpacs-shell-view-switched-hook
          (lambda (_view) (setq glasspane-gallery--open nil)))

(with-jetpacs-owner "glasspane"
  (jetpacs-shell-add-drawer-item
   65 (lambda () (jetpacs-drawer-item "insights" "Widget Gallery"
                                   (jetpacs-action "demo.gallery")))))

;;;###autoload
(defun glasspane-demo-gallery ()
  "Open the interactive widget-primitives gallery on the connected phone.
The newest of the demo commands (see also `glasspane-demo-setup')."
  (interactive)
  (setq glasspane-gallery--open t)
  (if (and (fboundp 'jetpacs-connected-p) (jetpacs-connected-p))
      (progn (jetpacs-shell-push nil :switch-to "glasspane.gallery")
             (message "Widget gallery opened on the phone"))
    (message "Jetpacs: not connected — connect a phone, then reopen")))

(provide 'glasspane-gallery)
;;; glasspane-gallery.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-ef.el
;;; ==================================================================

;;; glasspane-ef.el --- Ef-themes control screen -*- lexical-binding: t; -*-

;; A Glasspane screen for Prot's ef-themes — the "colorful" companion to the
;; austere modus themes.  Unlike modus, ef-themes ship as a third-party
;; package rather than inside Emacs, so this lives in the app tier (an
;; opinion Glasspane offers) rather than the core.
;;
;; Reached from Emacs Settings — a link right after the core "Modus Themes"
;; one, so the two theme pickers sit together — or `M-x glasspane-ef-open'.
;; It is a back-arrow overlay that only builds while open (the picker lists
;; ~40 themes, so we don't pay for it on every background push).  It offers:
;;
;;  - a light/dark grouped picker, each row previewing a theme's background
;;    and identity accent as swatches; the active theme is marked, a tap
;;    loads another (`ef-themes-load-theme');
;;  - the current theme's palette strip;
;;  - "Random", "Random dark", "Random light" — ef-themes' surprise-me loaders;
;;  - the everyday style options (bold, italic, mixed fonts, variable-pitch
;;    UI) as switches, each reloading the theme so the change shows at once.
;;
;; ef-themes 2.0+ are built on the modus 5.0 palette API, so an ef theme is a
;; registered modus derivative: the Jetpacs theme mirror
;; (`jetpacs-theme-mode' `emacs') already reflects it faithfully onto the
;; companion, reading its semantic roles.  When mirroring is on, switching a
;; theme here re-pushes it; when it is off, a one-tap "Mirror on phone" flips
;; it (only shown when the running core exposes `jetpacs-theme-mode').
;;
;; Everything reads ef-themes through its public API, so the screen tracks
;; whatever ef-themes version the user has installed and simply hides itself
;; when ef-themes is absent.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-widgets)
(require 'jetpacs-shell)
(require 'jetpacs-surfaces)
(require 'jetpacs-settings)

;; ef-themes is an optional runtime dependency loaded on demand; every use is
;; guarded.  Declared so the byte-compiler stays quiet when it is absent.
(declare-function ef-themes-get-color-value "ef-themes" (color &optional with-overrides theme))
(declare-function ef-themes-load-theme "ef-themes" (theme &optional hook))
(declare-function ef-themes-load-random "ef-themes" (&optional variant))
(declare-function ef-themes-load-random-dark "ef-themes" ())
(declare-function ef-themes-load-random-light "ef-themes" ())
(declare-function require-theme "custom" (feature &optional noerror))
(defvar ef-themes-items)
(defvar glasspane-ef--open nil
  "Non-nil while the Ef Themes overlay is showing.")

;; ─── Availability and loading ────────────────────────────────────────────────

(defun glasspane-ef--available-p ()
  "Non-nil when the ef-themes package is installed in this Emacs."
  (and (seq-some (lambda (theme)
                   (string-prefix-p "ef-" (symbol-name theme)))
                 (custom-available-themes))
       t))

(defun glasspane-ef--ensure ()
  "Load the ef-themes library; non-nil on success.
ef-themes is a package, so a plain `require' finds it once the package
system has initialised; `require-theme' is the fallback for the case where
only its theme directory is on the load path."
  (or (featurep 'ef-themes)
      (require 'ef-themes nil t)
      (and (fboundp 'require-theme)
           (ignore-errors (require-theme 'ef-themes t))
           (featurep 'ef-themes))))

;; ─── Theme queries ───────────────────────────────────────────────────────────

(defun glasspane-ef--themes ()
  "The list of selectable ef themes."
  (and (boundp 'ef-themes-items) ef-themes-items))

(defun glasspane-ef--current ()
  "The active ef theme symbol, or nil."
  (let ((known (glasspane-ef--themes)))
    (seq-find (lambda (theme) (memq theme known)) custom-enabled-themes)))

(defun glasspane-ef--dark-p (theme)
  "Non-nil when THEME is a dark ef theme.
ef derivatives register a `:background-mode' theme property (the modus 5.0
API), so this needs no name-guessing."
  (eq (plist-get (get theme 'theme-properties) :background-mode) 'dark))

(defun glasspane-ef--color (key &optional theme)
  "Hex value of ef palette KEY for THEME (or the current theme), or nil."
  (when (fboundp 'ef-themes-get-color-value)
    (let ((value (ignore-errors
                   (if theme
                       (ef-themes-get-color-value key nil theme)
                     (ef-themes-get-color-value key :with-overrides)))))
      (and (stringp value) value))))

;; ─── Swatches ────────────────────────────────────────────────────────────────

(defun glasspane-ef--swatch (hex &optional size)
  "A round color chip of HEX at SIZE dp (default 22), or nil when HEX is nil."
  (when hex
    (jetpacs-surface nil :color hex :shape "circle"
                     :width (or size 22) :height (or size 22))))

(defconst glasspane-ef--strip-keys
  '(bg-main fg-main accent-0 accent-1 accent-2 accent-3 err info)
  "Palette roles shown in the current theme's swatch strip.")

(defun glasspane-ef--strip ()
  "The CURRENT theme's swatch strip: one chip per `glasspane-ef--strip-keys'.
Reads the live palette (no theme arg), which resolves reliably."
  (delq nil (mapcar (lambda (key)
                      (glasspane-ef--swatch (glasspane-ef--color key)))
                    glasspane-ef--strip-keys)))

(defun glasspane-ef--preview (theme)
  "Per-theme swatches (background / foreground / accent) for THEME's list row.
Reading a NON-current theme's palette needs `modus-themes-activate' — the modus
5.0 machinery ef-themes 2.0+ builds on; when it is unavailable we return nil so
the list shows uniformly clean names."
  (when (fboundp 'modus-themes-activate)
    (delq nil (mapcar (lambda (key)
                        (glasspane-ef--swatch (glasspane-ef--color key theme) 18))
                      '(bg-main fg-main accent-0)))))

(defun glasspane-ef--display-name (theme)
  "A human-friendly label for THEME: drop the `ef-' prefix, then title-case,
so `ef-melissa-dark' reads as \"Melissa Dark\"."
  (capitalize
   (replace-regexp-in-string
    "-" " " (string-remove-prefix "ef-" (symbol-name theme)))))

;; ─── View sections ───────────────────────────────────────────────────────────

(defun glasspane-ef--mirror-note ()
  "Companion-mirror status, when the running core exposes `jetpacs-theme-mode'.
A live badge under mirror mode, or a one-tap switch into it otherwise."
  (when (boundp 'jetpacs-theme-mode)
    (if (eq jetpacs-theme-mode 'emacs)
        (jetpacs-row (jetpacs-icon "smartphone" :size 16)
                     (jetpacs-text "Mirroring to the companion" 'caption))
      (jetpacs-chip "Mirror on phone" :icon "smartphone"
                    :on-tap (jetpacs-action "ef.mirror" :when-offline "drop")))))

(defun glasspane-ef--current-card (current)
  "The header card: the active theme's name, polarity, palette, mirror status."
  (jetpacs-card
   (list (apply #'jetpacs-column
                (delq nil
                      (list (jetpacs-text (if current (symbol-name current)
                                            "No ef theme active")
                                          'title)
                            (when current
                              (jetpacs-text (concat (if (glasspane-ef--dark-p current)
                                                        "Dark" "Light")
                                                    " · " (symbol-name current))
                                            'caption))
                            (when current (apply #'jetpacs-row (glasspane-ef--strip)))
                            (when current (glasspane-ef--mirror-note))))))))

(defun glasspane-ef--actions-row ()
  "The surprise-me loaders ef-themes is known for."
  (jetpacs-row
   (jetpacs-button "Random" (jetpacs-action "ef.random" :when-offline "drop")
                   :icon "shuffle" :variant "tonal")
   (jetpacs-button "Random dark" (jetpacs-action "ef.random-dark" :when-offline "drop")
                   :icon "dark_mode" :variant "tonal")
   (jetpacs-button "Random light" (jetpacs-action "ef.random-light" :when-offline "drop")
                   :icon "light_mode" :variant "tonal")))

(defun glasspane-ef--theme-card (theme current)
  "A single-line row for THEME: name, preview swatches, and a marker; a tap
loads it.  CURRENT (the active theme) is checked and not re-loadable.  The
swatches are spread as direct row children — a nested `row' fills the width
and would starve the weighted name (the companion renders every row
`fillMaxWidth'); polarity is omitted, the cards are grouped under Light/Dark."
  (let ((activep (eq theme current)))
    (jetpacs-card
     (list (apply #'jetpacs-row
                  (append
                   (list (jetpacs-box
                          (list (jetpacs-text (glasspane-ef--display-name theme)
                                              'label))
                          :weight 1))
                   (glasspane-ef--preview theme)
                   (list (if activep
                             (jetpacs-icon "check_circle" :color "primary")
                           (jetpacs-icon "chevron_right"))))))
     :on-tap (unless activep
               (jetpacs-action "ef.load"
                               :args `((theme . ,(symbol-name theme)))
                               :when-offline "drop")))))

(defun glasspane-ef--themes-section (current)
  "The theme picker: cards grouped Light then Dark."
  (let* ((themes (glasspane-ef--themes))
         (light (seq-remove #'glasspane-ef--dark-p themes))
         (dark (seq-filter #'glasspane-ef--dark-p themes))
         (card (lambda (theme) (glasspane-ef--theme-card theme current))))
    (append
     (when light (cons (jetpacs-section-header "Light") (mapcar card light)))
     (when dark (cons (jetpacs-section-header "Dark") (mapcar card dark))))))

(defconst glasspane-ef--options
  '((ef-themes-bold-constructs    . "Bold keywords")
    (ef-themes-italic-constructs  . "Italic comments")
    (ef-themes-mixed-fonts        . "Mixed fonts in code")
    (ef-themes-variable-pitch-ui  . "Variable-pitch UI"))
  "Ef style options exposed as switches, each with a friendly label.")

(defun glasspane-ef--option-symbols ()
  "Just the option symbols from `glasspane-ef--options'."
  (mapcar #'car glasspane-ef--options))

(defun glasspane-ef--style-section ()
  "The style options as switch cards.
ef-themes' options carry no reified `custom-type', so we render the switch
directly rather than through `jetpacs-settings-item' (which classifies by
type); the paired `jetpacs-settings-watch-toggle' still applies each."
  (cons
   (jetpacs-section-header "Style")
   (mapcar (lambda (opt)
             (let ((sym (car opt)) (label (cdr opt)))
               (jetpacs-card
                (list (if (boundp sym)
                          (jetpacs-switch (concat "ef-opt/" (symbol-name sym))
                                          :checked (and (symbol-value sym) t)
                                          :label label)
                        (jetpacs-text (concat label " — not available") 'caption))))))
           glasspane-ef--options)))

(defun glasspane-ef--more-link ()
  "A card cross-linking into the customize browser's ef-themes group."
  (jetpacs-card
   (list (jetpacs-row
          (jetpacs-icon "tune")
          (jetpacs-box (list (jetpacs-text "More options in Customize" 'label))
                       :weight 1)
          (jetpacs-icon "chevron_right")))
   :on-tap (jetpacs-action "customize.show"
                           :args '((group . "ef-themes"))
                           :when-offline "drop")))

(defun glasspane-ef--body ()
  "The screen body, assuming the ef-themes library is loaded."
  (let ((current (glasspane-ef--current)))
    (apply #'jetpacs-lazy-column
           (delq nil
                 (append
                  (list (glasspane-ef--current-card current)
                        (glasspane-ef--actions-row))
                  (glasspane-ef--themes-section current)
                  (glasspane-ef--style-section)
                  (list (glasspane-ef--more-link)))))))

(defun glasspane-ef--not-installed ()
  "Placeholder shown when the ef-themes package is absent.
On a connected device it auto-installs (with the app's other packages);
we also offer a one-tap install when that action is available."
  (apply #'jetpacs-column
         (delq nil
               (list (jetpacs-text "ef-themes isn't installed yet." 'title)
                     (jetpacs-text
                      "It installs automatically on a connected device; you can also install it now (with the app's other packages)."
                      'caption)
                     (when (gethash "packages.install" jetpacs-action-handlers)
                       (jetpacs-button
                        "Install"
                        (jetpacs-action "packages.install" :when-offline "drop")
                        :icon "download" :variant "tonal"))))))

(defun glasspane-ef--view (snackbar)
  "The overlay view: back returns to wherever the user was."
  (jetpacs-shell-nav-view
   "Ef Themes"
   (if (glasspane-ef--ensure)
       (glasspane-ef--body)
     (glasspane-ef--not-installed))
   :snackbar snackbar))

;; ─── Live re-apply ───────────────────────────────────────────────────────────

(defun glasspane-ef--reload (&rest _)
  "Reload the active ef theme so a just-changed option takes effect.
The reload also drives `enable-theme-functions', re-pushing the mirror when
`jetpacs-theme-mode' is `emacs'."
  (when-let ((theme (glasspane-ef--current)))
    (when (fboundp 'ef-themes-load-theme)
      (ignore-errors (ef-themes-load-theme theme)))))

;; ─── Actions and registration ────────────────────────────────────────────────

(with-jetpacs-owner "glasspane"

  (jetpacs-defaction "ef.show"
    (lambda (_ __)
      (setq glasspane-ef--open t)
      (jetpacs-shell-push nil :switch-to "glasspane.ef")))

  (jetpacs-defaction "ef.load"
    (lambda (args _)
      (let* ((name (alist-get 'theme args))
             (sym (and (stringp name) (intern-soft name))))
        (if (and sym (glasspane-ef--ensure) (memq sym (glasspane-ef--themes)))
            (condition-case err
                (ef-themes-load-theme sym)
              (error (jetpacs-shell-notify (error-message-string err))))
          (jetpacs-shell-notify (format "Unknown ef theme: %s" (or name "?"))))
        (jetpacs-shell-push))))

  (jetpacs-defaction "ef.random"
    (lambda (_ __)
      (when (and (glasspane-ef--ensure) (fboundp 'ef-themes-load-random))
        (ignore-errors (ef-themes-load-random)))
      (jetpacs-shell-push)))

  (jetpacs-defaction "ef.random-dark"
    (lambda (_ __)
      (when (and (glasspane-ef--ensure) (fboundp 'ef-themes-load-random-dark))
        (ignore-errors (ef-themes-load-random-dark)))
      (jetpacs-shell-push)))

  (jetpacs-defaction "ef.random-light"
    (lambda (_ __)
      (when (and (glasspane-ef--ensure) (fboundp 'ef-themes-load-random-light))
        (ignore-errors (ef-themes-load-random-light)))
      (jetpacs-shell-push)))

  (jetpacs-defaction "ef.mirror"
    ;; Flip the companion into mirror mode; its `:set' pushes the current theme.
    (lambda (_ __)
      (when (boundp 'jetpacs-theme-mode)
        (jetpacs-settings-apply 'jetpacs-theme-mode 'emacs))
      (jetpacs-shell-push)))

  ;; The style switches publish state.changed under `ef-opt/<name>'; register
  ;; their handlers up front so a toggle queued offline replays even before the
  ;; screen first renders.  The reload after-set re-applies the theme so the
  ;; change is visible; a nil `custom-type' is fine — `jetpacs-settings-apply'
  ;; treats it as unconstrained.
  (dolist (sym (glasspane-ef--option-symbols))
    (jetpacs-settings-watch-toggle
     sym (concat "ef-opt/" (symbol-name sym)) #'glasspane-ef--reload))

  (jetpacs-shell-define-view "glasspane.ef"
    :builder #'glasspane-ef--view
    :when (lambda () glasspane-ef--open)
    :overlay (lambda () glasspane-ef--open)
    :order 122)

  ;; Entry point: a card in the Emacs settings screen, right after the core
  ;; "Modus Themes" link (order 25), so the two theme pickers sit together —
  ;; satellite screens live in Settings, not the drawer (the drawer-UX rule).
  (jetpacs-settings-add-link
   26 (lambda ()
        (jetpacs-card
         (list (jetpacs-row
                (jetpacs-icon "colorize")
                (jetpacs-box (list (jetpacs-column
                                    (jetpacs-text "Ef Themes" 'label)
                                    (jetpacs-text "Pick, preview, and tune the colorful ef-themes"
                                                  'caption)))
                             :weight 1)
                (jetpacs-icon "chevron_right")))
         :on-tap (jetpacs-action "ef.show" :when-offline "drop")))))

;; Landing on any real view closes the overlay (mirrors the gallery).
(add-hook 'jetpacs-shell-view-switched-hook
          (lambda (_view) (setq glasspane-ef--open nil)))

;;;###autoload
(defun glasspane-ef-open ()
  "Open the Ef Themes screen on the connected phone."
  (interactive)
  (setq glasspane-ef--open t)
  (if (and (fboundp 'jetpacs-connected-p) (jetpacs-connected-p))
      (progn (jetpacs-shell-push nil :switch-to "glasspane.ef")
             (message "Ef Themes opened on the phone"))
    (message "Jetpacs: not connected — connect a phone, then reopen")))

(provide 'glasspane-ef)
;;; glasspane-ef.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-config.el
;;; ==================================================================

;;; glasspane-config.el --- App-managed org defaults on disk -*- lexical-binding: t; -*-

;; Glasspane's opinionated defaults — capture templates, agenda wiring,
;; babel languages — live as small elisp files in Glasspane's config
;; subtree, written and refreshed by the app rather than hand-maintained in
;; init.el.  As of the jetpacs foundation-root work the subtree and its
;; sync/ensure/load contract are owned by core: this file is a thin caller
;; of `jetpacs-app-config-*', keyed by the app-id "glasspane", so the files
;; live under `(jetpacs-app-dir "glasspane")' (i.e.
;; ~/.emacs.d/jetpacs/apps/glasspane/) alongside every other app's subtree.
;; The contract is unchanged:
;;
;;   - `glasspane-config-sync' (or the allowlisted `config.sync' action)
;;     rewrites every managed file to the bundle's current defaults, so an
;;     app update can evolve them; edits to the files themselves are
;;     expected to be lost.
;;   - Personal configuration belongs in init.el or ~/.emacs.d/jetpacs/user.el
;;     (both load after these files, so they win) or in Customize.
;;   - The defaults are deliberately soft: capture templates merge by key
;;     and never replace one the user already defined; variables are seeded
;;     only while still at their stock values.
;;
;; Who writes the subtree the first time depends on the install flow:
;; the legacy starter init calls `glasspane-config-ensure' itself, and
;; under the foundation flow (jetpacs-init + apps.el) the bundle's own
;; load does it via `glasspane-config-startup' — being listed in
;; ~/.emacs.d/jetpacs/apps.el IS the install consent.  A bare
;; (require 'glasspane) anywhere else only loads what already exists;
;; nothing is written until asked.

;;; Code:

(require 'jetpacs-config)
(require 'jetpacs-surfaces)

(defconst glasspane-config-app-id "glasspane"
  "App-id keying Glasspane's config subtree and its foundation ownership.
The managed files live under `(jetpacs-app-dir glasspane-config-app-id)'.")

(defconst glasspane-config-version 1
  "Version of the managed defaults; stamped into every written file.")

(defconst glasspane-config--files
  '(("capture-templates.el" . "\
;;; capture-templates.el --- Glasspane-managed capture templates
;; APP-MANAGED (glasspane-config v1): rewritten by `glasspane-config-sync'.
;; Don't edit here — define your own templates in init.el; these merge
;; by key and never replace one you already have.

(require 'org-capture)

(defvar glasspane-config-capture-templates
  '((\"t\" \"Todo\" entry (file+headline org-default-notes-file \"Tasks\")
     \"* TODO %?\\n%U\\n%i\" :empty-lines 1)
    (\"n\" \"Note\" entry (file+headline org-default-notes-file \"Notes\")
     \"* %? :note:\\n%U\\n%i\" :empty-lines 1)
    (\"l\" \"Link\" entry (file+headline org-default-notes-file \"Links\")
     \"* %?\\n%U\\n%a\" :empty-lines 1))
  \"Glasspane's default capture templates (phone capture reads these).\")

(dolist (tpl glasspane-config-capture-templates)
  (unless (assoc (car tpl) org-capture-templates)
    (setq org-capture-templates
          (append org-capture-templates (list tpl)))))
")
    ("org-defaults.el" . "\
;;; org-defaults.el --- Glasspane-managed org wiring
;; APP-MANAGED (glasspane-config v1): rewritten by `glasspane-config-sync'.
;; Personal settings belong in init.el or Customize — they win because
;; init.el runs after this file loads.

(require 'org)

;; Capture lands in the inbox inside `org-directory' (only seeded while
;; still at org's stock ~/.notes default).
(when (equal org-default-notes-file
             (convert-standard-filename \"~/.notes\"))
  (setq org-default-notes-file
        (expand-file-name \"inbox.org\" org-directory)))
(make-directory org-directory t)

;; The phone's agenda tab needs agenda files; default to the whole
;; org directory when nothing is configured yet.
(unless org-agenda-files
  (setq org-agenda-files (list org-directory)))

;; State changes and clocks go into LOGBOOK drawers — the heading
;; detail view shows them as a structured section.
(setq org-log-into-drawer t)

;; Languages the demo corpus executes from the phone; the run button
;; only appears for languages loaded here.
(org-babel-do-load-languages
 'org-babel-load-languages
 '((emacs-lisp . t) (shell . t) (python . t)))
"))
  "Alist of (FILENAME . CONTENT) written by `glasspane-config-sync'.")

;;;###autoload
(defun glasspane-config-sync ()
  "Rewrite Glasspane's app-managed defaults and load them.
Delegates to `jetpacs-app-config-sync' under the app-id
`glasspane-config-app-id'; every file in `glasspane-config--files' is
overwritten — the reset-to-current-bundle semantics are the point.
Returns the subtree directory."
  (interactive)
  (jetpacs-app-config-sync glasspane-config-app-id glasspane-config--files))

(defun glasspane-config-load ()
  "Load every elisp file in Glasspane's config subtree, in name order.
A missing subtree is fine — nothing loads until the user opts in via
`glasspane-config-ensure' or `glasspane-config-sync'."
  (jetpacs-app-config-load glasspane-config-app-id))

;;;###autoload
(defun glasspane-config-ensure ()
  "Create the app-managed defaults on first run; load them afterwards.
Delegates to `jetpacs-app-config-ensure': a missing subtree is populated
via `glasspane-config-sync'; an existing one is only loaded, never
rewritten."
  (jetpacs-app-config-ensure glasspane-config-app-id glasspane-config--files))

(defun glasspane-config-startup ()
  "Load the managed defaults; under the foundation flow, create them first.
Being listed in ~/.emacs.d/jetpacs/apps.el (`jetpacs-installed-bundles')
is the install consent: the bundle's require during
`jetpacs-config-bootstrap' is Glasspane starting up on a device, and a
fresh one must come up with capture templates and agenda wiring or the
phone shows an empty Agenda and an empty capture sheet.  Bootstrap loads
custom.el and user.el after the app bundles, so personal settings still
win.  Anywhere else — a desktop `require', batch loads (tests, the pack
build) — nothing is written until the user opts in explicitly via
`glasspane-config-ensure'."
  (if (member "glasspane.el" (bound-and-true-p jetpacs-installed-bundles))
      (glasspane-config-ensure)
    (glasspane-config-load)))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "config.sync"
    ;; Allowlisted and argument-free: rewrites the fixed file set into
    ;; Glasspane's config subtree — nothing on the wire chooses paths or
    ;; content.
    (lambda (_ _)
      (let ((dir (glasspane-config-sync)))
        (when (fboundp 'jetpacs-shell-notify)
          (jetpacs-shell-notify
           (format "App defaults refreshed in %s"
                   (abbreviate-file-name dir)))))
      (when (fboundp 'jetpacs-shell-push)
        (jetpacs-shell-push)))))

(provide 'glasspane-config)
;;; glasspane-config.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-packages.el
;;; ==================================================================

;;; glasspane-packages.el --- Self-provisioning of the optional org engines -*- lexical-binding: t; -*-

;; org-ql (the full search language), vulpea (backlinks, note
;; completion, the stale-file half of Review), org-srs (the Review
;; screen), ef-themes (the Ef Themes picker — a MELPA package, unlike the
;; built-in modus themes): all optional, all degrading cleanly — and all
;; installed by the LEGACY starter init at boot.  Under the foundation flow
;; (jetpacs-init + apps.el) nothing installed them, so a fresh device
;; dead-ended degraded forever: no Review entry, no backlinks, and
;; nothing on the device ever attempted the install — restarting could
;; never help.  Ported from jetpacs-composer's engine self-provisioning
;; (jetpacs-crud-vulpea.el): the app provisions its OWN engines.  One
;; automatic attempt per interactive session when the app is installed
;; as a device app and something is missing, the allowlisted
;; `packages.install' action as the on-demand path, and
;; `M-x glasspane-packages-ensure' as the desktop path.  Success lights
;; features up live — probes re-ask, vulpea autosync wired, shell
;; refreshed — no restart.
;;
;; Trust boundary (the same lock composer's Stage 4 keeps): only this
;; closed, app-owned set ever auto-installs.  Nothing on the wire and
;; nothing in org data can name a package.

;;; Code:

(require 'cl-lib)
(require 'jetpacs)
(require 'jetpacs-shell)
(require 'jetpacs-settings)
(require 'jetpacs-config)
;; (require 'glasspane-config) — bundle-internal, provided above

(declare-function vulpea-db-autosync-mode "vulpea-db" (&optional arg))
(declare-function vulpea-db-sync-full-scan "vulpea-db" ())
(declare-function glasspane-vulpea-register "glasspane-vulpea" ())
(declare-function org-srs-item-confirm-command "org-srs" ())

;; Forward-declared: `org-directory' lives in org, which this file must not
;; force-load — the references in `--light-up' only run once the optional
;; engines are present.
(defvar org-directory)

(defcustom glasspane-packages-auto-install t
  "When non-nil, a device install with missing engines schedules one
automatic install attempt per session (on an idle timer, so boot is
never blocked).  The `packages.install' action and
`glasspane-packages-ensure' work regardless.  Set to nil (in user.el
or from Settings) to manage packages yourself."
  :type 'boolean :group 'jetpacs)

(defconst glasspane-packages--set '(org-ql vulpea org-srs ef-themes)
  "The closed MELPA set the app's optional features read through.
The starter init's package list, now owned by the bundle, plus ef-themes
for the Ef Themes picker.  Deliberately not extensible from app data or
the wire — see the trust note above.")

(defvar glasspane-packages--attempted nil
  "Non-nil once this session has scheduled its automatic install attempt.")

(defvar glasspane-packages--installing nil
  "Non-nil while an engine install is in flight.
Load-bearing re-entrancy guard: `package-refresh-contents' pumps the
event loop (`accept-process-output'), so a second tap could otherwise
re-enter mid-install.")

(defun glasspane-packages--wanted ()
  "The subset of `glasspane-packages--set' this Emacs build can run.
vulpea's index rides SQLite; on a build without it no package install
can help, so vulpea is simply not wanted — search (org-ql) and review
\(org-srs) still are."
  (if (and (fboundp 'sqlite-available-p) (sqlite-available-p))
      glasspane-packages--set
    (remq 'vulpea glasspane-packages--set)))

(defun glasspane-packages--missing ()
  "The wanted packages not currently loadable, freshly probed."
  (cl-remove-if (lambda (pkg) (require pkg nil t))
                (glasspane-packages--wanted)))

(defun glasspane-packages--light-up ()
  "Wire what is now loadable and refresh the shell.
The wiring the starter init used to carry: vulpea autosync over the
vault (additive — user directories are kept, one index, and the
initial full scan runs once per device via a marker file) and the
command-style org-srs confirm phone-driven review needs.  Then a shell
refresh, which re-asks the memoised probes and rebuilds every pushed
view — the Review drawer entry and the notes sections appear live."
  (when (require 'vulpea nil t)
    (defvar vulpea-db-sync-directories)
    (when (and (stringp org-directory) (file-directory-p org-directory))
      (add-to-list 'vulpea-db-sync-directories org-directory))
    ;; The mobile-context extractor must be in the registry before
    ;; autosync or the once-per-device full scan index anything.
    (when (require 'glasspane-vulpea nil t)
      (glasspane-vulpea-register))
    (when (fboundp 'vulpea-db-autosync-mode)
      (vulpea-db-autosync-mode 1))
    ;; Autosync watches for changes; a vault that predates vulpea still
    ;; needs one full index build.
    (let ((marker (expand-file-name ".vulpea-scanned"
                                    (jetpacs-app-dir glasspane-config-app-id))))
      (unless (file-exists-p marker)
        (when (fboundp 'vulpea-db-sync-full-scan)
          (ignore-errors (vulpea-db-sync-full-scan)))
        (make-directory (file-name-directory marker) t)
        (write-region "" nil marker nil 'silent))))
  (when (require 'org-srs nil t)
    (defvar org-srs-item-confirm)
    ;; Upstream's own recommendation for Emacs on Android: the default
    ;; confirm reads a key, which phone-driven review can never answer.
    (setq org-srs-item-confirm #'org-srs-item-confirm-command))
  (when (fboundp 'jetpacs-shell-refresh)
    (jetpacs-shell-refresh)))

(defun glasspane-packages-ensure ()
  "Install any missing engine from MELPA, then light features up.
Synchronous (package.el is), idempotent, and never signals: returns
non-nil when everything wanted is loadable afterwards, else nil with
the reason in *Messages*.  The retry story is calling this again —
each device boot's automatic attempt and every `packages.install' tap
do exactly that."
  (interactive)
  (cond
   (glasspane-packages--installing
    (message "glasspane-packages: install already in progress")
    nil)
   ((null (glasspane-packages--missing))
    (glasspane-packages--light-up)
    t)
   (t
    (setq glasspane-packages--installing t)
    (unwind-protect
        (condition-case err
            (progn
              (require 'package)
              (defvar package-archives)
              (add-to-list 'package-archives
                           '("melpa" . "https://melpa.org/packages/") t)
              (unless (bound-and-true-p package--initialized)
                (package-initialize))
              (package-refresh-contents)
              (dolist (pkg (glasspane-packages--missing))
                (unless (package-installed-p pkg)
                  (message "glasspane-packages: installing %s…" pkg)
                  (package-install pkg)))
              (let ((still (glasspane-packages--missing)))
                (if still
                    (progn
                      (message "glasspane-packages: %s installed but not loadable — see *Messages*"
                               (mapconcat #'symbol-name still ", "))
                      nil)
                  (glasspane-packages--light-up)
                  (message "glasspane-packages: engines ready — views refreshed")
                  t)))
          (error
           (message "glasspane-packages: install failed: %s"
                    (error-message-string err))
           nil))
      (setq glasspane-packages--installing nil)))))

(defun glasspane-packages-maybe-auto-install ()
  "Schedule this session's one automatic install when a device needs it.
Called from the bundle entry at load; fires on an idle timer so boot
cost is zero.  Only in an interactive session (batch/CI must never
reach for MELPA), only when the app is installed as a device app
\(listed in `jetpacs-installed-bundles' — the same consent that seeds
the managed config), at most once a session, and only when something
wanted is actually missing.  Restart = the natural retry."
  (when (and glasspane-packages-auto-install
             (not noninteractive)
             (not glasspane-packages--attempted)
             (member "glasspane.el" (bound-and-true-p jetpacs-installed-bundles))
             (glasspane-packages--missing))
    (setq glasspane-packages--attempted t)
    (run-with-idle-timer
     3 nil
     (lambda ()
       (message "glasspane-packages: engines missing — attempting install (%s)…"
                (mapconcat #'symbol-name (glasspane-packages--missing) ", "))
       (glasspane-packages-ensure)))))

(with-jetpacs-owner "glasspane"
  (jetpacs-defaction "packages.install"
    ;; Allowlisted and argument-free: installs the closed engine set —
    ;; nothing on the wire chooses packages.  package.el is synchronous,
    ;; so feedback rides toasts around the (possibly long) install.
    (lambda (_ _)
      (jetpacs-send "toast.show" '((text . "Installing packages…")))
      (if (glasspane-packages-ensure)
          (jetpacs-send "toast.show" '((text . "Packages ready — views refreshed")))
        (jetpacs-send "toast.show" '((text . "Install failed — check *Messages* in Emacs"))))))

  (jetpacs-settings-register-section
   "Packages"
   '((glasspane-packages-auto-install
      :label "Auto-install packages (org-ql, vulpea, org-srs, ef-themes)"))))

(provide 'glasspane-packages)
;;; glasspane-packages.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane-pack.el
;;; ==================================================================

;;; glasspane-pack.el --- The Glasspane engine-pack manifest -*- lexical-binding: t; -*-

;; Glasspane ships as a jetpacs *engine pack*: a bundle of elisp (the Tier-1
;; app) plus a machine-readable manifest, `glasspane-pack.json', that tells the
;; no-code composer what it can bind without reading any elisp — the data
;; SOURCES it registers, the composer-facing ACTIONS its cards expose, the
;; layouts available, and — the SDUI dependency model — the Emacs packages the
;; engine relies on so the composer can install them.
;;
;; The manifest is built from LIVE registrations (`jetpacs-source-catalog',
;; `jetpacs-action-catalog'), so it can never drift from what the app actually
;; registers; `emacs/build-pack.el' regenerates the committed JSON and a test
;; asserts the two agree.  Rich rendering stays in `:builder's that lean on the
;; declared engine (vulpea/org-ql/…) — the manifest is the seam, not a wire DSL.

;;; Code:

(require 'cl-lib)
(require 'jetpacs-source)               ; jetpacs-source-catalog
(require 'jetpacs-surfaces)             ; jetpacs-action-catalog
(require 'jetpacs-lint)                 ; jetpacs-lint-spec-layouts

(defconst glasspane-pack-id "glasspane"
  "The pack id the composer keys Glasspane by.")

(defconst glasspane-pack-version "1.0.0"
  "Version of the Glasspane pack (distinct from `jetpacs-api-version').")

(defconst glasspane-pack-min-jetpacs-api "1.5.0"
  "The minimum jetpacs api the Glasspane pack requires (source registry + :spec).")

(defconst glasspane-pack-depends
  '(((name . "org")    (min_version . "9.6"))
    ((name . "org-ql") (min_version . "0.7"))
    ((name . "vulpea") (min_version . "2.0"))
    ((name . "cl-lib") (min_version . "1.0")))
  "Emacs packages the Glasspane engine relies on, for the composer to install.
The whole point of the SDUI split: the server may lean on rich packages
(vulpea's note index, org-ql's query language) and the composer brings them
in automatically — Glasspane never re-implements what these already do.")

(defun glasspane-pack--sort-by (key entries)
  "ENTRIES (a list of alists) sorted by their KEY value, for a stable manifest.
`jetpacs-source-catalog'/`jetpacs-action-catalog' iterate a hash table, so a
deterministic snapshot must impose an order."
  (sort (copy-sequence entries)
        (lambda (a b) (string< (format "%s" (alist-get key a))
                               (format "%s" (alist-get key b))))))

(defun glasspane-pack-manifest ()
  "The Glasspane engine-pack manifest, built from live registrations.
A JSON-serializable alist; sources and actions are name-sorted so the
generated `glasspane-pack.json' is byte-stable."
  (list (cons 'pack_id         glasspane-pack-id)
        (cons 'pack_version    glasspane-pack-version)
        (cons 'min_jetpacs_api glasspane-pack-min-jetpacs-api)
        (cons 'feature         glasspane-pack-id)
        (cons 'depends         (vconcat glasspane-pack-depends))
        (cons 'layouts         (vconcat jetpacs-lint-spec-layouts))
        (cons 'sources         (vconcat (glasspane-pack--sort-by
                                         'name (jetpacs-source-catalog))))
        ;; Owner-filtered: every Glasspane registration is wrapped in
        ;; `with-jetpacs-owner', so the catalog is exact regardless of what
        ;; else the build environment loaded.  (Sources stay unfiltered —
        ;; `jetpacs-source-catalog' has no owner arg at this core pin.)
        (cons 'actions         (vconcat (glasspane-pack--sort-by
                                         'action (jetpacs-action-catalog "glasspane"))))))

(defun glasspane-pack-json ()
  "The manifest as pretty-printed, newline-terminated JSON text."
  (with-temp-buffer
    (insert (json-serialize (glasspane-pack-manifest)
                            :null-object :null :false-object :false))
    (json-pretty-print-buffer)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (buffer-string)))

(defun glasspane-pack-write (file)
  "Write the manifest JSON to FILE.  Returns FILE."
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file file (insert (glasspane-pack-json))))
  file)

(provide 'glasspane-pack)
;;; glasspane-pack.el ends here

;;; ==================================================================
;;; BEGIN apps/glasspane/glasspane.el
;;; ==================================================================

;;; glasspane.el --- Glasspane: the reference org app on Jetpacs -*- lexical-binding: t; -*-

;; The one-require entry point for the full reference app.  Pulls in the
;; Jetpacs core (transport, shell, renderers, editor bridge) plus every
;; Glasspane module (org views, clock notification, magit pie, package
;; browser, demo tour):
;;
;;   (require 'glasspane)
;;
;; The pre-built single-file bundle at the repo root carries the same
;; feature name, so init files work unchanged with either install option.

;;; Code:

;; (require 'glasspane-ui) — bundle-internal, provided above
;; (require 'glasspane-source) — bundle-internal, provided above
;; (require 'glasspane-agenda) — bundle-internal, provided above
;; (require 'glasspane-capture) — bundle-internal, provided above
;; (require 'glasspane-detail) — bundle-internal, provided above
;; (require 'glasspane-search) — bundle-internal, provided above
;; (require 'glasspane-table) — bundle-internal, provided above
;; (require 'glasspane-journal) — bundle-internal, provided above
;; (require 'glasspane-views) — bundle-internal, provided above
;; (require 'glasspane-automations) — bundle-internal, provided above
;; (require 'glasspane-notes) — bundle-internal, provided above
;; (require 'glasspane-srs) — bundle-internal, provided above
;; (require 'glasspane-gallery) — bundle-internal, provided above
;; (require 'glasspane-ef) — bundle-internal, provided above
;; (require 'glasspane-config) — bundle-internal, provided above
;; (require 'glasspane-packages) — bundle-internal, provided above
;; (require 'glasspane-pack) — bundle-internal, provided above

;; The app-managed defaults (capture templates, agenda wiring): under
;; the foundation flow (listed in ~/.emacs.d/jetpacs/apps.el) a missing
;; subtree is created — first boot on a device must yield a working
;; capture sheet and agenda.  Elsewhere this only loads what exists —
;; and either way init.el code after (require 'glasspane) still runs
;; later, so personal settings always win.
(glasspane-config-startup)

;; A device install also provisions the optional engines the starter
;; init used to install (org-ql, vulpea, org-srs): one idle attempt per
;; session, batch and desktop requires never reach for MELPA — see
;; glasspane-packages.el.
(glasspane-packages-maybe-auto-install)

(provide 'glasspane)
;;; glasspane.el ends here

(provide 'glasspane)
;;; glasspane.el ends here
