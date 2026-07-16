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

(defun glasspane-org--save-and-invalidate (&optional buffer)
  "Synchronously save BUFFER (default: current buffer); drop the org memo.
The shared tail of every mutation outside `glasspane-ui--at-ref' —
keep-the-funnel: the save happens NOW, never on an idle timer
\(`jetpacs-org-defer-save'), with the after-save dashboard refresh
suppressed so the caller's explicit repush isn't doubled."
  (with-current-buffer (or buffer (current-buffer))
    (let ((glasspane-org--inhibit-save-refresh t)
          (save-silently t))
      (save-buffer)))
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

(defun glasspane-org--vulpea-note-to-item (note)
  "Convert a `vulpea-note' to a Glasspane item alist."
  (let ((id (vulpea-note-id note))
        (path (vulpea-note-path note))
        (title (vulpea-note-title note))
        (pos (vulpea-note-pos note)))
    `((headline . ,title)
      (todo . ,(vulpea-note-todo note))
      (priority . ,(vulpea-note-priority note))
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
