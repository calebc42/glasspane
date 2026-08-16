;;; glasspane-org.el --- Glasspane org-mode data extraction -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The app's data layer: memoised extraction, query routing, reminder
;; specs, clock status, the save funnel, CREATED/MODIFIED stamping.
;; Pure Elisp downstream of Jetpacs and the ebp-org core — Glasspane
;; adds no Kotlin layer.  The floor's teardown hook is named by symbol
;; only, so this file loads and compiles without the live bridge.
;;
;; Retired against v1 (docs/PLAN-glasspane-app.md, retirement list +
;; G1): the org-ql routing commentary and its fork — `ebp-org-query'
;; is ALWAYS the built-in interpreter (ebp-org.el:1277-1282); and the
;; load-time installation of the global CREATED/MODIFIED org hooks — a
;; bare `require' must not mutate `before-save-hook', so the app
;; enables them via `glasspane-org-install-hooks' with
;; `jetpacs-teardown-functions' removal hygiene.  Reminder specs are
;; now SPEC 18.6 reminder plists — the shape `jetpacs-reminders-set'
;; consumes — not the v1 frame alists.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-agenda)
(require 'org-clock)
(require 'ebp-org)
(require 'jetpacs-files)
(require 'jetpacs-editor-org)           ; native save policy
(require 'jetpacs-org-reminders)         ; canonical agenda extraction
(require 'jetpacs-org-vulpea)           ; note-index arm of the ONE grammar

;;;; Refresh coordination

(defvar glasspane-org--inhibit-save-refresh nil
  "When non-nil, the `after-save-hook' dashboard refresh is suppressed.
Bound around our own programmatic saves (heading edits, file saves) so an
explicit dashboard push isn't doubled by the save-hook firing on top.")

(declare-function vulpea-db-update-file "ext:vulpea-db-extract" (file))

(define-error 'glasspane-org-splice-refused
  "Glasspane refused a stale or unsafe subtree splice" 'user-error)

(defun glasspane-org--mtime-stamp (path)
  "Return PATH's opaque microsecond modification stamp, or nil.
The value is compared only with another value from this function; it is
never parsed or exposed as a path-bearing identity."
  (when-let* ((mtime (file-attribute-modification-time
                      (file-attributes path))))
    (format-time-string "%s.%6N" mtime)))

(defun glasspane-org--splice-refuse (message)
  "Refuse a subtree splice with user-facing MESSAGE."
  (signal 'glasspane-org-splice-refused (list message)))

(defun glasspane-org--synced-edit-p (path)
  "Whether PATH is the live document in Files' synchronized editor."
  (let ((current (jetpacs-files-current-edit-path))
        (context (jetpacs-files-current-edit-context)))
    (and current
         (equal (file-truename current) (file-truename path))
         (plist-get context :document)
         (plist-get context :editor-id)
         (buffer-live-p (plist-get context :buffer)))))

(defun glasspane-org--vulpea-refresh-file (&optional buffer-or-path)
  "Synchronously re-index BUFFER-OR-PATH in vulpea's db, when it is up.
BUFFER-OR-PATH may be a visiting buffer or the durable path supplied by
an editor adapter's after-save callback; nil means the current buffer.
Vulpea's autosync applies saves on a short batch/idle timer, so a
mutation that immediately re-renders (todo swipe → push) would read
the stale row back out of the index.  No-op without vulpea."
  (when (fboundp 'vulpea-db-update-file)
    (when-let* ((f (cond
                    ((bufferp buffer-or-path)
                     (buffer-file-name buffer-or-path))
                    ((stringp buffer-or-path) buffer-or-path)
                    (t (buffer-file-name (current-buffer))))))
      (ignore-errors (vulpea-db-update-file f)))))

(defun glasspane-org--save-and-invalidate (&optional buffer)
  "Delegate BUFFER's synchronous save to Jetpacs' native Org policy.
The app keeps only its refresh-suppression opinion; encryption,
durability, optional indexing, and whole-cache invalidation belong to
`jetpacs-editor-org-save-policy'."
  (let ((glasspane-org--inhibit-save-refresh t))
    (jetpacs-editor-org-save-policy (or buffer (current-buffer)))))

(defun glasspane-org--fresh-splice (ref value stamp beg end tick)
  "Replace REF's subtree with VALUE after validating open-time facts.
STAMP, BEG, END, and TICK are the scalar snapshot minted with the detail
editor.  The target is re-resolved from REF, including its Org ID, but the
write proceeds only when disk mtime, subtree bounds, and buffer tick still
match that snapshot.  Any failure before durability restores the visiting
buffer's full text and modified state.  Return a freshly anchored ref."
  (unless (and (stringp value)
               (string-match-p "\\`\\*+\\(?:[ \t]\\|$\\)" value))
    (glasspane-org--splice-refuse "Heading must start with Org stars"))
  (when (> (string-bytes value) jetpacs-files-max-bytes)
    (glasspane-org--splice-refuse "Heading is too large to save"))
  ;; Check disk identity before resolving the ref.  Resolution may visit or
  ;; consult the already-visiting buffer; doing it first would let Emacs ask
  ;; whether to edit a buffer whose file changed externally, violating D2.
  (let ((true (ebp-org--check-file (plist-get ref :file))))
    (when (glasspane-org--synced-edit-p true)
      (glasspane-org--splice-refuse "file is open in the synced editor"))
    (unless (equal stamp (glasspane-org--mtime-stamp true))
      (glasspane-org--splice-refuse "File changed on disk — not saved"))
    (unless (file-writable-p true)
      (glasspane-org--splice-refuse "File is not writable"))
    (let ((marker (ebp-org-resolve-ref ref)))
      (unwind-protect
          (with-current-buffer (marker-buffer marker)
            (org-with-wide-buffer
             (goto-char marker)
             (org-back-to-heading t)
             (let ((current-beg (point))
                   (current-end (save-excursion
                                  (org-end-of-subtree t t)
                                  (point))))
               (unless (and (integerp beg) (integerp end) (integerp tick)
                            (= current-beg beg) (= current-end end)
                            (= (buffer-chars-modified-tick) tick))
                 (glasspane-org--splice-refuse
                  "Heading changed in Emacs — not saved"))
               (let* ((original-beg (point-min))
                      (original-end (point-max))
                      (original-point (point))
                      (original-modified (buffer-modified-p))
                      (original-full
                       (buffer-substring-no-properties
                        (point-min) (point-max)))
                      (changed nil)
                      (durable nil)
                      new-ref)
                 (unwind-protect
                     (progn
                       (setq changed t)
                       (delete-region current-beg current-end)
                       (goto-char current-beg)
                       (insert value)
                       ;; Do not glue the following heading to a value
                       ;; whose final newline was omitted by the client.
                       (unless (or (bolp) (eobp)) (insert "\n"))
                       (goto-char current-beg)
                       (setq new-ref (ebp-org-ref-at-point))
                       (when (> (string-bytes
                                 (buffer-substring-no-properties
                                  (point-min) (point-max)))
                                jetpacs-files-max-bytes)
                         (glasspane-org--splice-refuse
                          "Edited file exceeds the save limit"))
                       (glasspane-org--save-and-invalidate (current-buffer))
                       (setq durable t)
                       new-ref)
                   (when (and changed (not durable))
                     (let ((inhibit-read-only t))
                       (widen)
                       (delete-region (point-min) (point-max))
                       (insert original-full)
                       (narrow-to-region original-beg original-end)
                       (goto-char
                        (min (max original-point (point-min)) (point-max)))
                       (set-buffer-modified-p original-modified))))))))
        (set-marker marker nil)))))

;; The dashboard pushes every view on every action (so navigation stays
;; instant and offline-capable), which means the expensive extractions
;; here — a full `org-agenda' run, an `org-map-entries' sweep — would
;; execute on every chip tap and snackbar.  They are memoised in the
;; core's table (`ebp-org-with-cache' under the `glasspane' namespace;
;; keys carry today's date + the agenda files' disk/buffer stamp, so
;; date roll-over, external edits and unsaved buffer edits bust
;; automatically).  Every mutation path (heading actions, saves,
;; capture, queue replay) drops the namespace via
;; `ebp-org-cache-invalidate'.

;;;; Heading references
;;
;; Every heading the UI lists carries a `ref' — an Emacs-side plist
;; from `ebp-org-ref-at-point' (:id :file :pos :headline) that lets a
;; later action (drill-in, todo-set, schedule, clock-in) find the same
;; heading again via `ebp-org-resolve-ref'.  A ref NEVER crosses the
;; wire (D-4): the UI layer mints SPEC 23.1 tokens for anything the
;; device can tap.

(defalias 'glasspane-org--agenda-scope
  #'jetpacs-org-mode--agenda-scope
  "Delegate to Org Mode's canonical local agenda scope.")

(defalias 'glasspane-org--agenda-items
  #'jetpacs-org-mode--agenda-items
  "Delegate to Org Mode's rich, memoised agenda extraction.")

(defalias 'glasspane-org--agenda-items-1
  #'jetpacs-org-mode--agenda-items-1
  "Delegate to Org Mode's uncached agenda extraction worker.")

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

(declare-function vulpea-note-id "ext:vulpea-note" (note))
(declare-function vulpea-note-path "ext:vulpea-note" (note))
(declare-function vulpea-note-title "ext:vulpea-note" (note))
(declare-function vulpea-note-pos "ext:vulpea-note" (note))
(declare-function vulpea-note-todo "ext:vulpea-note" (note))
(declare-function vulpea-note-priority "ext:vulpea-note" (note))
(declare-function vulpea-note-tags "ext:vulpea-note" (note))
(declare-function vulpea-note-scheduled "ext:vulpea-note" (note))
(declare-function vulpea-note-deadline "ext:vulpea-note" (note))
(declare-function vulpea-note-level "ext:vulpea-note" (note))
(declare-function vulpea-db-query "ext:vulpea-db" (&optional pred))
(declare-function vulpea-db-query-tags "ext:vulpea-db" ())

(defun glasspane-org--vulpea-note-to-item (note)
  "Convert a `vulpea-note' to a Glasspane item alist.
The ref mirrors `ebp-org-ref-at-point' shape exactly — resolution
re-validates and truenames the path, so the index's own spelling
rides as-is."
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
      (ref . ,(list :id (and (stringp id) (not (string-empty-p id)) id)
                    :file (or path "")
                    :pos pos
                    :headline (or title ""))))))

(defun glasspane-org--vulpea-p ()
  "Non-nil when the user has already loaded vulpea.
App policy: never force-load — `jetpacs-org-vulpea-available-p' would
`require' vulpea; Glasspane only rides an index the user's own config
brought up."
  (and (featurep 'vulpea) (fboundp 'vulpea-db-query)))

(defun glasspane-org--todo-items (&optional files)
  "Extract TODO items from FILES (or agenda files).
Memoised; see `ebp-org-cache-invalidate'."
  ;; The key names the ARM as well as the action: the same scope answers
  ;; differently once the vault index exists.
  (ebp-org-with-cache 'glasspane
      (list 'todos files (and (glasspane-org--vulpea-p) (null files) t))
    (if (and (glasspane-org--vulpea-p) (null files))
        (mapcar #'glasspane-org--vulpea-note-to-item
                (vulpea-db-query (lambda (note) (vulpea-note-todo note))))
      (glasspane-org--todo-items-1 files))))

(defun glasspane-org--todo-items-1 (files)
  "Uncached worker for `glasspane-org--todo-items'."
  (let ((scope (or files (glasspane-org--agenda-scope)))
        items)
    (when scope
      (ebp-org--with-clamped-io
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
                       (ref . ,(ebp-org-ref-at-point)))
                     items))))
         "TODO<>\"\"" scope)))
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
      (ref . ,(ebp-org-ref-at-point)))))

(defun glasspane-org--file-heading-items (file)
  "Extract level-1 headings from FILE as item alists.
Same shape as `glasspane-org--todo-items' entries (plus scheduled/deadline).
FILE validates against the org roots FIRST: `ebp-org--check-file'
signals `ebp-org-refused' outside them (the UI layer answers
\\='rejected), `ebp-org-unresolved' when it is gone (\\='stale) — and
the visit runs clamped so a drifted file becomes a STATUS, never a
prompt in the dispatch extent (D2)."
  (when file
    (let ((true (ebp-org--check-file file)))
      (ebp-org--with-clamped-io
        (with-current-buffer (find-file-noselect true t)
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
                            (ref . ,(ebp-org-ref-at-point)))
                          items))))
              nil nil)
             (nreverse items))))))))

;; Search queries pass through the canonical parser (`ebp-org-parse-query')
;; into a vetted query sexp, whichever of the three input shapes the user
;; typed.  Matching is the core's ONE grammar — `ebp-org-entry-matches-p'
;; at a buffer point, `ebp-org-note-matches-p' over a `vulpea-note'.
;; Malformed queries signal `user-error' so the UI can show the problem —
;; an empty result must mean "nothing matched", never "the query didn't
;; parse".

(defun glasspane-org--vulpea-query (tree)
  "Run parsed query sexp TREE over the whole Vulpea database.
Matching runs entirely off the index via the canonical
`ebp-org-note-matches-p'.  Callers route TREE here only when
`ebp-org-note-query-supported-p' approves it; an unsupported term
slipping through signals `user-error'."
  (let ((notes (vulpea-db-query (lambda (note) (ebp-org-note-matches-p tree note)))))
    (mapcar #'glasspane-org--vulpea-note-to-item notes)))

(defun glasspane-org--query (tree)
  "Run parsed query sexp TREE over the org data; heading items.
The engine behind search and every saved/derived view.  Scope rule:
when the user has vulpea loaded and TREE stays inside
`ebp-org-note-query-terms', the note index answers from the WHOLE
vault (no file visit); anything else routes to `ebp-org-query' —
always the built-in interpreter — over the agenda files only.
Signals `user-error' on terms neither engine knows.  Memoised; see
`ebp-org-cache-invalidate'."
  (when tree
    (if (and (glasspane-org--vulpea-p)
             (ebp-org-note-query-supported-p tree))
        ;; `ebp-org-query' caches internally; only the vulpea arm needs
        ;; its own memo.  TREE prints with truncation OFF — `format'
        ;; honours `print-length'/`print-level', so a caller with either
        ;; bound would collide two trees onto one entry (the core's own
        ;; rule, ebp-org.el:1285-1288).
        (ebp-org-with-cache 'glasspane
            (list 'vulpea-query
                  (let ((print-length nil) (print-level nil) (print-circle t))
                    (format "%S" tree)))
          (glasspane-org--vulpea-query tree))
      ;; KEY names the ACTION, not the caller: the cached value is the
      ;; action's own payload (the P1-12 rule, ebp-org.el:1260-1270).
      (ebp-org-query 'glasspane 'glasspane-org--heading-item-at
                     tree #'glasspane-org--heading-item-at))))

(defun glasspane-org--search (query)
  "Search the org data for QUERY; return a list of heading items.
QUERY may be a query sexp, filter tokens, or free text — see
`ebp-org-parse-query'.  Scope follows `glasspane-org--query':
whole vault off the note index when vulpea has it, agenda files
otherwise.  Signals `user-error' on queries that don't parse or use
terms no engine supports, so callers can surface the problem."
  (glasspane-org--query (ebp-org-parse-query query)))

(defun glasspane-org--filter-items (items query)
  "ITEMS whose headings match QUERY — the sparse filter.
QUERY takes the standard search syntax; matching runs the built-in
matcher at each item's own heading, so it works on any file, agenda
or not.  Signals `user-error' on queries that don't parse or use
unsupported terms.  An item whose file has left the org roots (or is
gone) simply doesn't match — a filter is a predicate, not an answer
to a request, so the TOTAL policy check applies (ebp-org.el:214)."
  (let ((tree (ebp-org-parse-query query)))
    (if (null tree)
        items
      (cl-remove-if-not
       (lambda (item)
         (let* ((file (alist-get 'file item))
                (pos (alist-get 'pos item))
                (true (and file pos (ebp-org-file-allowed-p file))))
           (and true
                (ebp-org--with-clamped-io
                  (with-current-buffer (find-file-noselect true t)
                    (org-with-wide-buffer
                     (goto-char (min pos (point-max)))
                     (unless (org-at-heading-p)
                       (ignore-errors (org-back-to-heading t)))
                     (ebp-org-entry-matches-p tree)))))))
       items))))

(defun glasspane-org--all-tags ()
  "Sorted tags for the query builder.
Combines `org-tag-alist' (the configured vocabulary) with every tag
actually used in the agenda files.  Memoised; see
`ebp-org-cache-invalidate'."
  ;; The key names the ARM as well as the action: the same scope answers
  ;; differently once the vault index exists.
  (ebp-org-with-cache 'glasspane
      (list 'all-tags (and (featurep 'vulpea) (fboundp 'vulpea-db-query-tags) t))
    (let ((tags nil))
      (dolist (entry org-tag-alist)
        (let ((tg (if (consp entry) (car entry) entry)))
          (when (stringp tg) (push tg tags))))
      (if (and (featurep 'vulpea) (fboundp 'vulpea-db-query-tags))
          (dolist (tg (vulpea-db-query-tags))
            (push tg tags))
        ;; Explicit scope: passed nil, the table falls back to the
        ;; `org-agenda-files' FUNCTION (P1-5/P1-7); the sweep visits
        ;; every file, so it runs clamped.
        (let ((files (glasspane-org--agenda-scope)))
          (when files
            (ebp-org--with-clamped-io
              (dolist (entry (org-global-tags-completion-table files))
                (when (stringp (car entry)) (push (car entry) tags)))))))
      (sort (delete-dups tags) #'string-lessp))))

(defun glasspane-org--file-list ()
  "List of agenda files and basic stats."
  (mapcar (lambda (f)
            `((file . ,f)
              (name . ,(file-name-nondirectory f))))
          (ebp-org-agenda-files)))

(defun glasspane-org--heading-at (pos file)
  "Get full heading detail at POS in FILE.
FILE validates against the org roots (`ebp-org--check-file' — signals
per its STATUS split); the visit runs clamped (D2)."
  (let ((true (ebp-org--check-file file)))
    (ebp-org--with-clamped-io
      (with-current-buffer (find-file-noselect true t)
        (org-with-wide-buffer
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
             (body . ,body))))))))

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

(defun glasspane-org--reminder-id (name)
  "A stable SPEC 4.4 identifier \"glasspane.rem-STEM-HASH\" for NAME.
`jetpacs-wire-id's minting idiom, duplicated because that minter lives
in jetpacs-widgets, which requires the bridge — and this layer is
bridge-free.  Headlines and file paths are routinely OUT of the 4.4
charset (spaces above all), and `jetpacs-reminders-set' rejects the
whole set on one bad :id; sanitizing alone is lossy (\"a b\" and
\"a-b\" must not collide), so the sha1 of the ORIGINAL name rides
along.  The readable stem keeps the id debuggable; the result stays
under the 128-char ceiling."
  (let* ((safe (replace-regexp-in-string "[^A-Za-z0-9._:/-]" "-" name))
         (stem (substring safe 0 (min (length safe) 80))))
    (format "glasspane.rem-%s-%s" stem (substring (sha1 name) 0 8))))

(defun glasspane-org--upcoming-reminders (&optional horizon-hours)
  "Timed agenda items within HORIZON-HOURS (default 24) as reminder specs.
Only items with a clock time qualify (a date alone isn't an alarm).
Each spec is a SPEC 18.6 reminder plist (:id :at_ms :title :body) —
the shape `jetpacs-reminders-set' consumes; :id is minted over
file/pos/instant, never the raw headline."
  (let* ((horizon (* (or horizon-hours 24) 3600))
         (now (float-time))
         (items (append (glasspane-org--agenda-items 'day nil)
                        (glasspane-org--agenda-items
                         'day (format-time-string "%Y-%m-%d"
                                                  (time-add nil 86400)))))
         reminders seen)
    (dolist (it items)
      (let ((date (alist-get 'date it))
            (hm (glasspane-org--item-hm (alist-get 'time it)))
            (headline (alist-get 'headline it))
            (type (alist-get 'type it))
            (file (alist-get 'file it))
            (pos (alist-get 'pos it)))
        (when (and (stringp date) hm)
          (let ((at (float-time (org-time-string-to-time
                                 (concat date " " hm)))))
            (when (and (> at now) (< (- at now) horizon))
              (let ((id (glasspane-org--reminder-id
                         (format "%sT%s %s:%s" date hm
                                 (or file "") (or pos 0)))))
                ;; Same entry, same instant → ONE alarm: a heading
                ;; scheduled AND deadlined at one time surfaces as two
                ;; agenda lines sharing file/pos/at, and
                ;; `jetpacs-reminders-set' errors on duplicate :id
                ;; within a set (SPEC 18.6).
                (unless (member id seen)
                  (push id seen)
                  (push (list :id id
                              :at_ms (truncate (* at 1000))
                              :title (or headline "Org reminder")
                              :body (concat hm (when (stringp type)
                                                 (concat " · " type))))
                        reminders))))))))
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
                      (ref . ,(ebp-org-ref-at-point)))
                    items))))))
    (cl-subseq (nreverse items) 0 (min n (length items)))))

;;;; Automated timestamps
;;
;; Global org hooks — they touch every org buffer the user edits, not
;; just Glasspane's extractions, so they attach at app ENABLE
;; (`glasspane-org-install-hooks'), never at load, and teardown of the
;; app's owner detaches them.

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

(defun glasspane-org--heading-created-property ()
  "Add a :CREATED: property to new headings."
  (org-set-property "CREATED" (glasspane-org--timestamp-string)))

(defun glasspane-org--heading-modified-property (property &rest _)
  "Update :MODIFIED: property when any other PROPERTY changes."
  (when (and (stringp property)
             (not (equal property "MODIFIED"))
             (not (equal property "CREATED")))
    (let ((org-property-changed-functions nil))
      (org-set-property "MODIFIED" (glasspane-org--timestamp-string)))))

(defun glasspane-org--todo-modified-property ()
  "Stamp :MODIFIED: on the entry whose TODO state just changed.
v1's anonymous `org-after-todo-state-change-hook' member, named so
removal can find it."
  (let ((org-property-changed-functions nil))
    (org-set-property "MODIFIED" (glasspane-org--timestamp-string))))

(defun glasspane-org-remove-hooks ()
  "Detach everything `glasspane-org-install-hooks' attached."
  (remove-hook 'before-save-hook #'glasspane-org--before-save-timestamps)
  (remove-hook 'org-insert-heading-hook #'glasspane-org--heading-created-property)
  (remove-hook 'org-property-changed-functions #'glasspane-org--heading-modified-property)
  (remove-hook 'org-after-todo-state-change-hook #'glasspane-org--todo-modified-property)
  (remove-hook 'jetpacs-teardown-functions #'glasspane-org--on-teardown))

(defun glasspane-org--on-teardown (owner)
  "Drop the global org hooks when OWNER is the Glasspane app.
`glasspane-owner' is read late and defensively: the entry file defines
it and `require's this one, so a back-`require' would cycle — and by
the time any teardown runs, the entry has long finished loading."
  (when (equal owner (bound-and-true-p glasspane-owner))
    (glasspane-org-remove-hooks)))

(defun glasspane-org-install-hooks ()
  "Attach the CREATED/MODIFIED stamping hooks, with teardown hygiene.
Idempotent.  Called at app enable — v1 attached these at load, which
made a bare `require' mutate the user's global org hooks.  Teardown of
the app's owner detaches them (`jetpacs-teardown-functions', arity
\(OWNER); the hook symbol is the floor's, named without a require so
this layer stays bridge-free)."
  (add-hook 'before-save-hook #'glasspane-org--before-save-timestamps)
  (add-hook 'org-insert-heading-hook #'glasspane-org--heading-created-property)
  (add-hook 'org-property-changed-functions #'glasspane-org--heading-modified-property)
  (add-hook 'org-after-todo-state-change-hook #'glasspane-org--todo-modified-property)
  (add-hook 'jetpacs-teardown-functions #'glasspane-org--on-teardown))

;;;; Vulpea light-up (the extractor sibling registers only when the
;;;; user's own config already brought vulpea up)

(declare-function glasspane-vulpea-register "glasspane-vulpea" ())

(when (featurep 'vulpea)
  (when (require 'glasspane-vulpea nil t)
    (glasspane-vulpea-register)))

(provide 'glasspane-org)
;;; glasspane-org.el ends here
