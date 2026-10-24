;;; glasspane-org.el --- Glasspane org-mode data extraction -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The app's data layer: query routing, clock status, the save funnel,
;; CREATED/MODIFIED stamping, and the PARA opinions over the foundation's
;; built-in Org extractions.  The extractions themselves — agenda items,
;; the TODO sweep, the heading item shape, tag vocabulary, tag-group
;; indexing, workflow keywords, the freshness-checked subtree splice —
;; are Jetpacs primitives (jetpacs-org-reminders.el, jetpacs-org-settings.el,
;; jetpacs-editor-org.el); this file keeps only the arms that need the
;; optional vulpea note index and the PARA inheritance rule, and aliases
;; the rest under the names its sibling modules call.  Pure Elisp
;; downstream of Jetpacs and the ebp-org core — Glasspane adds no Kotlin
;; layer.  The floor's teardown hook is named by symbol only, so this
;; file loads and compiles without the live bridge.
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
(require 'jetpacs-org-settings)          ; public workflow vocabulary
(require 'glasspane-vulpea)             ; note-index arm + mobile extractor

(declare-function vulpea-db-update-file "ext:vulpea-db-extract" (file))

(defun glasspane-org-vulpea-refresh-file (&optional buffer-or-path)
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

(defun glasspane-org-save-and-invalidate (&optional buffer)
  "Delegate BUFFER's synchronous save to Jetpacs' native Org policy.
The app keeps its optional Vulpea index refresh opinion; encryption,
durability, and whole-cache invalidation belong to
`jetpacs-org-save-policy'."
  (let ((target (or buffer (current-buffer))))
    (prog1 (jetpacs-org-save-policy target)
      (glasspane-org-vulpea-refresh-file target))))

(defun glasspane-org-fresh-splice (ref value stamp beg end tick)
  "Replace REF's subtree with VALUE through the foundation's fresh splice.
STAMP, BEG, END, and TICK are the scalar snapshot minted with the detail
editor; `jetpacs-editor-org-fresh-splice' re-validates every one of them
and saves through the native policy.  Glasspane adds only its optional
vulpea row refresh.  Signals `jetpacs-editor-org-splice-refused' with a
user-facing message; return a freshly anchored ref."
  (prog1 (jetpacs-editor-org-fresh-splice ref value stamp beg end tick)
    (glasspane-org-vulpea-refresh-file (plist-get ref :file))))

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
(declare-function vulpea-note-properties "ext:vulpea-note" (note))
(declare-function vulpea-db-query-by-property-key "ext:vulpea-db-query" (key))
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
App policy: never force-load — `glasspane-vulpea-available-p' would
`require' vulpea; Glasspane only rides an index the user's own config
brought up."
  (and (featurep 'vulpea) (fboundp 'vulpea-db-query)))

(defun glasspane-org-todo-items (&optional files)
  "Extract TODO items from FILES (or agenda files).
The whole-vault case answers off the vulpea note index when the user's
config brought it up; every other case is the foundation's built-in
sweep (`jetpacs-org-mode-todo-items', memoised under `org-mode').
Memoised; see `ebp-org-cache-invalidate'."
  (if (and (glasspane-org--vulpea-p) (null files))
      ;; The key names the ARM as well as the action: the same scope
      ;; answers differently once the vault index exists.
      (ebp-org-with-cache 'glasspane (list 'todos files t)
        (mapcar #'glasspane-org--vulpea-note-to-item
                (vulpea-db-query (lambda (note) (vulpea-note-todo note)))))
    (jetpacs-org-mode-todo-items files)))

(defun glasspane-org-tag-groups-at (pos)
  "Return foundation tag-group membership at POS with PARA inheritance.
POS is a heading position in the current Org buffer.  Glasspane considers
file tags and parent tags even when `org-use-tag-inheritance' narrows
agenda display.  `org-tags-exclude-from-inheritance' still applies.
The foundation returns propertyless strings and does not cache this query."
  (let ((org-use-tag-inheritance t))
    (ebp-org-tag-groups-at pos)))

(defun glasspane-org-file-tag-group-index (file group)
  "Return FILE's effective tag GROUP members and heading memberships.
Public: the per-file memo every Area consumer (cards, Resources archives)
shares.  The walk, the memo and its settings-aware cache identity are
the foundation's (`jetpacs-org-mode-file-tag-group-index'); Glasspane
contributes the PARA inheritance rule — file tags and parent tags count
even when `org-use-tag-inheritance' narrows agenda display — the same
rule `glasspane-org-tag-groups-at' applies to a single heading."
  (jetpacs-org-mode-file-tag-group-index file group t))

(defun glasspane-org-open-todo-p (item)
  "Return non-nil when ITEM carries a TODO keyword that is not done.
Done-ness is `ebp-org-done-keyword-p': the current buffer's keywords
when the caller is inside the source buffer (file-local `#+TODO' lines
are honored), else the global configuration."
  (let ((todo (alist-get 'todo item)))
    (and (stringp todo)
         (not (string-empty-p todo))
         (not (ebp-org-done-keyword-p todo)))))

(defun glasspane-org-indexed-area-declarations ()
  "Return Area declarations known to the vault index, or nil without one.
An Area note declares itself with an `AREA' property whose value is the
Area tag.  Each result is a plist (:name VALUE :file PATH :pos POS
:headline TITLE :level LEVEL).  This is the only place the Areas model
reads the vulpea index; membership itself is always resolved from the
files (see `glasspane-org-file-tag-group-index').  Memoised; see
`ebp-org-cache-invalidate'."
  (when (and (glasspane-org--vulpea-p)
             (fboundp 'vulpea-db-query-by-property-key))
    (ebp-org-with-cache 'glasspane (list 'area-declarations-indexed t)
      (condition-case nil
          (delq nil
                (mapcar
                 (lambda (note)
                   (let ((value (cdr (assoc-string
                                      "AREA" (vulpea-note-properties note)
                                      t))))
                     (when (and (stringp value)
                                (not (string-empty-p (string-trim value))))
                       (list :name (string-trim value)
                             :file (vulpea-note-path note)
                             :pos (or (vulpea-note-pos note) 1)
                             :headline (or (vulpea-note-title note) "")
                             :level (or (vulpea-note-level note) 0)))))
                 (vulpea-db-query-by-property-key "AREA")))
        (error nil)))))

(defun glasspane-org-item-tag-group-members (item group)
  "Return ITEM's effective memberships in native Org tag GROUP.
Membership is resolved at ITEM's source position so file tags and inherited
heading tags are honored.  If a stale index item has no matching position,
its own `tags' field is intersected with the source file's effective group.
The result follows the group's declaration order."
  (when-let* ((file (alist-get 'file item))
              (index (glasspane-org-file-tag-group-index file group)))
    (let* ((pos (alist-get 'pos item))
           (at-pos (and (integerp pos)
                        (assoc pos (plist-get index :positions))))
           (tags (jetpacs-org-mode-tag-strings
                  (alist-get 'tags item))))
      (copy-sequence
       (if at-pos
           (cdr at-pos)
         (cl-remove-if-not
          (lambda (member) (member member tags))
          (plist-get index :members)))))))

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

(defun glasspane-org-query (tree)
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
      (ebp-org-query 'glasspane 'jetpacs-org-mode-heading-item-at
                     tree #'jetpacs-org-mode-heading-item-at))))

(defun glasspane-org-search (query)
  "Search the org data for QUERY; return a list of heading items.
QUERY may be a query sexp, filter tokens, or free text — see
`ebp-org-parse-query'.  Scope follows `glasspane-org-query':
whole vault off the note index when vulpea has it, agenda files
otherwise.  Signals `user-error' on queries that don't parse or use
terms no engine supports, so callers can surface the problem."
  (glasspane-org-query (ebp-org-parse-query query)))

(defun glasspane-org-all-tags ()
  "Sorted tags for the query builder.
With the vulpea index up, the configured vocabulary (`org-tag-alist')
joins every tag the whole vault's index knows; otherwise the answer is
the foundation's built-in sweep over the agenda scope
\(`jetpacs-org-mode-all-tags').  Memoised; see `ebp-org-cache-invalidate'."
  (if (and (featurep 'vulpea) (fboundp 'vulpea-db-query-tags))
      ;; The key names the ARM as well as the action: the same scope
      ;; answers differently once the vault index exists.
      (ebp-org-with-cache 'glasspane (list 'all-tags t)
        (let ((tags nil))
          (dolist (entry org-tag-alist)
            (let ((tg (if (consp entry) (car entry) entry)))
              (when (stringp tg) (push tg tags))))
          (dolist (tg (vulpea-db-query-tags))
            (push tg tags))
          (sort (delete-dups tags) #'string-lessp)))
    (jetpacs-org-mode-all-tags)))

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

(defconst glasspane-org--stamping-hooks
  '((before-save-hook . glasspane-org--before-save-timestamps)
    (org-insert-heading-hook . glasspane-org--heading-created-property)
    (org-property-changed-functions . glasspane-org--heading-modified-property)
    (org-after-todo-state-change-hook . glasspane-org--todo-modified-property))
  "The global CREATED/MODIFIED stampers as (HOOK . FUNCTION) pairs.")

(defun glasspane-org-remove-hooks ()
  "Detach everything `glasspane-org-install-hooks' attached."
  (pcase-dolist (`(,hook . ,fn) glasspane-org--stamping-hooks)
    (jetpacs-remove-hook hook fn)))

(defun glasspane-org-install-hooks ()
  "Attach the CREATED/MODIFIED stamping hooks under the app's owner.
Idempotent.  Called at app enable — v1 attached these at load, which
made a bare `require' mutate the user's global org hooks.  Each is
ledgered (`jetpacs-add-hook'), so the app's teardown detaches them."
  (with-jetpacs-owner "glasspane"
    (pcase-dolist (`(,hook . ,fn) glasspane-org--stamping-hooks)
      (jetpacs-add-hook hook fn))))

;;;; Vulpea light-up (the extractor sibling registers only when the
;;;; user's own config already brought vulpea up)

(declare-function glasspane-vulpea-register "glasspane-vulpea" ())

(when (featurep 'vulpea)
  (when (require 'glasspane-vulpea nil t)
    (glasspane-vulpea-register)))

(provide 'glasspane-org)
;;; glasspane-org.el ends here
