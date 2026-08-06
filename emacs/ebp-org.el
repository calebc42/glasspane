;;; ebp-org.el --- The org extraction and mutation engine -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; The org engine, under the prefix that names what it is.  `ebp-' by
;; the rule ratified 2026-08-06 (bed8ef4, `refactor(complete):
;; ebp-complete - the capf bridge is wire and Emacs only'):
;;
;;     `jetpacs-' names what cannot exist without Kotlin, Android, and
;;     Compose; `ebp-' names what only ever touches the wire and Emacs.
;;
;; The engine passes the boundary test with nothing left over.  org is
;; built-in Emacs; a query is a sexp and a heading is a buffer position;
;; the refusal vocabulary below is SPEC 14.4/14.5 wire.  Nothing here
;; builds a node, names a surface, or knows that a phone exists.  The
;; prefix is an ENFORCED claim rather than a spelling convention:
;; test/run-tests.sh loads every `emacs/ebp*.el' file alone, in a
;; process of its own, and fails if a `jetpacs' symbol — function,
;; variable, face, error condition, group, or loaded feature — exists
;; afterwards.
;;
;; The engine arrives in two rungs (docs/PLAN-ebp-org-split.md).  THIS
;; one carries the grammar and the primitives: everything that depends
;; on neither the root allowlist nor the cache and mutation blocks —
;; the three error conditions with their disposition map, the D2 IO
;; clamp, typed extraction, the wire-facing query parser and the one
;; interpreter it feeds, and the shared org primitives (timestamps,
;; headless capture, LOGBOOK, planning repeaters, TBLFM).  The
;; allowlist, the cache, refs, tokens, mutations, the outline model and
;; the reset follow at G7, when `jetpacs-org.el' shrinks to the
;; registration shim it exists to be.
;;
;; Ported from poc-v1's jetpacs-org.el engine ranges, NOT transliterated.
;; Two of the twelve fixed poc defects are load-bearing HERE and are
;; named at their fix sites; do not "restore" either from the source:
;;
;;   - `(read q)' on a wire string (obarray poisoning, measured; and an
;;     RCE hand-off when org-ql is installed).  The sexp arm reads under
;;     a throwaway obarray and vets against an allowlist (O2).
;;   - absolute paths in error messages: a condition raised here is
;;     answered toward the device, so it carries a bare reason symbol
;;     and never a path or a line of the user's own text (D-4, 23.3).
;;     Every condition this file signals carries no payload beyond its
;;     head symbol's own data discipline — there is no label, no
;;     formatting hook, and nothing for one to leak through.
;;
;; THE HANDLER STATUS BOUNDARY (SPEC 14.4/14.5).  The three conditions
;; are the whole of the engine's answer vocabulary and they map, via
;; `ebp-org-refusal-disposition', onto exactly the statuses a handler
;; may conclude with: `ebp-org-refused' -> `rejected';
;; `ebp-org-unresolved' -> `stale'; `ebp-org-unavailable' -> retry, the
;; one that is NOT a handler status but a `jetpacs-retry-later' call in
;; the application layer, so the durable record survives redelivery.
;; The split is load-bearing in one direction: `rejected' makes the
;; Companion DELETE the record, so a transient condition must never
;; land there.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)                       ; org-id-locations / find-id-in-file
(require 'org-capture)                  ; O3: templates, capture-run
(require 'org-table)                    ; O3: org-table-current-begin-pos defvar
;; Batch 3 (P1-6): loaded EAGERLY, never lazily.  `org-timestamp-change'
;; autoloads org-clock (via `org-clock-update-time-maybe') in the middle
;; of the first repeatered toggle, and org-clock.el's load runs the
;; `org-logind-dbus-session-path' defvar D-Bus probe — whose wait loop
;; pumps `read-event', which under `inhibit-interaction' signals a raw
;; `inhibited-interaction' out of the mutation extent (measured on a
;; system bus; the clamp cannot stub `read-event' without breaking that
;; same D-Bus machinery).  Loading here runs the probe at module load,
;; where interaction is legal.
(require 'org-clock)
;; Batch 3 (P1-6): the C modification guard calls the AUTOLOADED
;; `userlock--ask-user-about-supersession-threat' (emacs-30.1
;; src/filelock.c); if userlock.el loads lazily inside the clamp, its
;; defuns CLOBBER the clamp's `ask-user-about-supersession-threat'
;; rebind mid-extent and the stock batch branch errors ("Cannot resolve
;; conflict in batch mode") instead of the D2 status.  With the library
;; already loaded, `cl-letf' rebinds stick — and the wrapper's
;; content-unchanged check still absorbs a same-content mtime drift
;; before any question is asked.  `load', not `require': userlock.el
;; is a no-provide preloadable library, and the fboundp gate skips the
;; load when a dump already carries it (an autoload STUB does not
;; count — it is exactly the hazard).
(unless (and (fboundp 'userlock--ask-user-about-supersession-threat)
             (not (autoloadp (symbol-function
                              'userlock--ask-user-about-supersession-threat))))
  (load "userlock" nil t))
(require 'ebp-path)                     ; the shared sandbox, floor-free

(defgroup ebp-org nil
  "The org extraction and mutation engine."
  :group 'org
  :prefix "ebp-org-")

;;;; Errors — the handler status boundary

(define-error 'ebp-org-refused "ebp-org: ref refused")
(define-error 'ebp-org-unresolved "ebp-org: heading not found")
(define-error 'ebp-org-unavailable "ebp-org: resource unavailable")

(defun ebp-org-refusal-disposition (err)
  "The SPEC 14.4/14.5 disposition for a signalled engine condition ERR.
ERR is the (CONDITION . DATA) cons a `condition-case' binds (JA-4
audit P1-10: `rejected' makes the Companion DELETE the durable record,
so only permanent conditions may map there).  Returns:
- `rejected' for `ebp-org-refused' — the path itself is out of
  policy (`not-absolute', `remote', `outside-roots'), permanently
  invalid;
- `stale' for `ebp-org-unresolved' — content drift (heading gone,
  file gone, ambiguous duplicates); the Companion re-presents (14.5);
- `retry' for `ebp-org-unavailable' — transient environment
  \(`unreadable', `no-roots', `no-agenda-files': an unmounted vault
  comes back).  NOT a handler status: call `jetpacs-retry-later',
  which concludes the action with `1500 event-retry' so the record
  survives redelivery;
- nil for anything else (not an engine condition — let it propagate).
The handler shape this buys:
  (condition-case err (…engine call… \\='accepted)
    ((ebp-org-refused ebp-org-unavailable ebp-org-unresolved)
     (pcase (ebp-org-refusal-disposition err)
       (\\='retry (jetpacs-retry-later))
       (status status))))"
  (pcase (car-safe err)
    ('ebp-org-refused 'rejected)
    ('ebp-org-unresolved 'stale)
    ('ebp-org-unavailable 'retry)))

;;;; The root allowlist

(defcustom ebp-org-roots nil
  "Directories `ebp-org-resolve-ref' may touch.
nil derives the set from `org-directory' and the directories of
`org-agenda-files'.  Matching is by true-name path components, never
by string prefix — /org-evil does not sit under /org."
  :type '(repeat directory))

(defun ebp-org-agenda-files ()
  "`org-agenda-files' entries anchored, with remote entries dropped.
Each entry is expanded against `org-directory' FIRST — matching
`org-agenda-files's own `(expand-file-name f org-directory)' semantics;
reading the raw variable must not change where a relative entry points
\(Batch-3 P2: it previously resolved against the AMBIENT
`default-directory' at every consumer).  The expansion is pure string
work, so a remote name minted by a remote `org-directory' is still
caught by the `ebp-local-paths' filter that runs AFTERWARDS — the
order is load-bearing.

`org-agenda-files' the FUNCTION calls `file-directory-p' on each raw
entry (emacs-30.1 lisp/org/org.el), so this reads the VARIABLE rather
than calling it: by the time the function returns, a remote entry has
already been dialled.  JA-4 audit P1-7 — one /ssh: entry made every
resolve, every mint and every cache-key computation attempt a TRAMP
connection inside the socket filter, with a 60-second timeout."
  (ebp-local-paths
   (mapcar (lambda (entry)
             ;; Guard the shape: `ebp-local-paths' tolerates (and
             ;; drops) garbage entries, and "" must not silently become
             ;; org-directory itself.
             (if (and (stringp entry) (not (string-empty-p entry)))
                 (expand-file-name entry org-directory)
               entry))
           (if (listp org-agenda-files) org-agenda-files
             (ignore-errors (org-agenda-files))))))

(defun ebp-org--roots ()
  "The effective allowlist, raw — `ebp-check-path' truenames it.
Explicit `ebp-org-roots' entries anchor to `org-directory'
\(Batch-3 P2: a relative entry previously resolved against the AMBIENT
`default-directory' — whatever buffer the socket filter had current);
nil derives the set from `org-directory' and the directories of the
LOCAL agenda files, already absolute after the same anchoring."
  (if ebp-org-roots
      (mapcar (lambda (d)
                (if (and (stringp d) (not (string-empty-p d)))
                    (expand-file-name d org-directory)
                  d))
              ebp-org-roots)
    (delete-dups
     (cons (expand-file-name org-directory)
           (mapcar #'file-name-directory (ebp-org-agenda-files))))))

(defun ebp-org--check-file (file)
  "FILE validated against `ebp-org-roots', as a truename, or signal.
The guard itself is `ebp-check-path', shared (JA-6 promoted it out);
this wrapper supplies the org root set and re-signals in the module's
STATUS-SPLIT conditions (JA-4 audit P1-10 — `rejected' deletes the
Companion's durable record, so a transient condition must never land
there):
- `ebp-org-refused' (handler: rejected): `not-absolute', `remote',
  `outside-roots' — the path itself is out of policy;
- `ebp-org-unavailable' (handler: `jetpacs-retry-later'):
  `unreadable' on an EXISTING file (an I/O condition), and `no-roots'
  \(the whole allowlist collapsed — an unmounted vault comes back);
- `ebp-org-unresolved' (handler: stale): the file is GONE —
  content drift, the Companion re-presents (14.5)."
  (condition-case err
      (ebp-check-path file (ebp-org--roots))
    (ebp-path-refused
     (pcase (cadr err)
       ('no-roots (signal 'ebp-org-unavailable (cdr err)))
       ('unreadable
        (if (file-exists-p file)
            (signal 'ebp-org-unavailable (cdr err))
          (signal 'ebp-org-unresolved (list 'file-missing))))
       (_ (signal 'ebp-org-refused (cdr err)))))))

(defun ebp-org-file-allowed-p (file)
  "FILE's truename when it is inside the org roots and readable, else nil.
The TOTAL form of `ebp-org--check-file'.  Every condition that
checker raises — `ebp-org-refused' (the path is out of policy),
`ebp-org-unresolved' (the file is GONE) and
`ebp-org-unavailable' (unreadable, or the whole allowlist
collapsed) — comes back as a plain nil.  This function never signals.

The signalling checker exists for callers that ANSWER a request and
must tell the three apart, because each routes to a different STATUS
\(23.1 rejected / 14.5 stale / retry-later).  Every other caller only
wants to know whether it may read a path, and those callers had all
written the same wrong thing: a `condition-case' catching
`ebp-org-refused' and nothing else, so the other two conditions
escaped.  That is how a link to a missing image file — plain
`ebp-org-unresolved', the most ordinary thing a document can
contain — signalled out through the whole render instead of degrading
to the link's text."
  (condition-case nil
      (ebp-org--check-file file)
    ((ebp-org-refused ebp-org-unresolved ebp-org-unavailable)
     nil)))

;;;; The D2 IO clamp

(defmacro ebp-org--with-clamped-io (&rest body)
  "Run BODY with every interactive file-IO escape clamped (D2).
Drift and every other would-be question become a STATUS — a
`ebp-org-refused' signal carrying a one-symbol data list per the
floor's 23.3 convention (`file-drifted', `needs-interactive') — never
a prompt: these extents run inside the socket filter or a timer, where
a prompt wedges a daemon with nobody to answer it.

The variables silence what variables can: `query-about-changed-file'
nil the changed-on-disk reread question in `find-file-noselect',
`large-file-warning-threshold' nil the size confirmation,
`enable-local-variables' :safe the unsafe-local-variable prompt.  The
rebinds catch what variables cannot: supersession
\(`ask-user-about-supersession-threat', raised by the FIRST buffer
modification against a drifted file), the `y-or-n-p'/`yes-or-no-p'
family (write-protected saves, `require-final-newline', the
`org-auto-repeat-maybe' `++' catch-up question), and
`read-char-exclusive' (`org-check-agenda-file' on a file that vanishes
between the existence filter and the map — the filter/prepare race)."
  (declare (indent 0) (debug t))
  `(let ((query-about-changed-file nil)
         (large-file-warning-threshold nil)
         (enable-local-variables :safe))
     (cl-letf (((symbol-function 'ask-user-about-supersession-threat)
                (lambda (_fn)
                  (signal 'ebp-org-refused (list 'file-drifted))))
               ((symbol-function 'y-or-n-p)
                (lambda (&rest _)
                  (signal 'ebp-org-refused (list 'needs-interactive))))
               ((symbol-function 'yes-or-no-p)
                (lambda (&rest _)
                  (signal 'ebp-org-refused (list 'needs-interactive))))
               ((symbol-function 'read-char-exclusive)
                (lambda (&rest _)
                  (signal 'ebp-org-refused (list 'needs-interactive)))))
       ,@body)))

;;;; Cache layer

(defvar ebp-org--cache (make-hash-table :test #'equal)
  "Memoised org extraction results.")

(defconst ebp-org-cache-max 64
  "Entries one key generation may hold before the table is dropped.
The key embeds wire-supplied query text, so without a ceiling N
distinct hostile queries retain N entries for the process lifetime
\(JA-4 audit P2).  Every entry is cheap to recompute and the eviction
is wholesale, so this is a plain bound rather than an LRU carrying its
own per-entry bookkeeping: overflow costs one re-run, never a wrong
answer.")

(defcustom ebp-org-stat-ttl 1.0
  "Seconds the agenda-file mtime stamp is trusted between stats.
The poc statted every agenda file on EVERY cache lookup, hits included
— N truename+stat syscalls per lookup.  Within this window the DISK
half of the stamp is reused; `ebp-org-cache-invalidate' clears it,
so a mutation is never masked by the memo.  The BUFFER half
\(`ebp-org--stamp-buffers') is never memoised — it costs no
syscalls, and memoising it would blind the cache to an unsaved edit
for exactly this window."
  :type 'number)

(defvar ebp-org--stamp-memo nil
  "(EXPIRY-FLOAT NAMES . DISK) — the memoised DISK half, or nil.")

(defun ebp-org--stamp-disk ()
  "The syscall half of the freshness stamp: (NAMES . DISK), memoised.
NAMES is a list of (ENTRY . TRUENAME) for the local agenda set — the
buffer half below needs both spellings to find a visiting buffer
without a syscall of its own.  DISK is a list of (TRUENAME . MTIME)
for the entries that exist — a LIST, not a max float: the poc's
max-of-float-time collided inside one clock tick (two writes, same
double => stale hit) and was blind to set MEMBERSHIP changes
\(dropping the newest file left the max unchanged).  Time values keep
their native resolution and compare with `equal'."
  (let ((now (float-time)))
    (if (and ebp-org--stamp-memo
             (< now (car ebp-org--stamp-memo)))
        (cdr ebp-org--stamp-memo)
      (let* ((names
              (mapcar (lambda (file) (cons file (file-truename file)))
                      ;; Remote entries are dropped BEFORE these stats: this
                      ;; runs on every cache-key computation, i.e. inside
                      ;; every query, which made it the hottest TRAMP dialler
                      ;; in the module (JA-4 audit P1-7).
                      (ebp-org-agenda-files)))
             (disk
              (delq nil
                    (mapcar
                     (lambda (name)
                       ;; One stat, not an exists-p plus a stat: nil
                       ;; attributes IS the file being gone.
                       (when-let* ((attrs (file-attributes (cdr name))))
                         (cons (cdr name)
                               (file-attribute-modification-time attrs))))
                     names)))
             (value (cons names disk)))
        (setq ebp-org--stamp-memo (cons (+ now ebp-org-stat-ttl) value))
        value))))

(defun ebp-org--stamp-buffers (names)
  "The buffer half of the freshness stamp: (TRUENAME . CHARS-TICK) list.
JA-4 audit P1-11: the stamp was derived entirely from `file-attributes'
while EVERY cached value is produced by `org-map-entries' /
`ebp-org-ref-at-point' reading the BUFFER.  An org buffer edited in
Emacs and not yet written — the normal state of a working buffer, and
precisely the state `ebp-org-with-mutation' deliberately leaves for
the debounce window — moved nothing at all, so a repeated query served
positions that no longer exist and (with the P1-9 scan) a tap mutated
the wrong heading.

`buffer-chars-modified-tick' is monotonic per buffer and free to read,
which is why this half is recomputed on every lookup rather than
memoised.  Both spellings in NAMES are probed: a buffer visits the name
it was opened with, which need not be the truename, and `get-file-buffer'
is a string comparison — `find-buffer-visiting' would stat every file
again inside the very window `ebp-org-stat-ttl' exists to avoid."
  (delq nil
        (mapcar (lambda (name)
                  (when-let* ((buf (or (get-file-buffer (car name))
                                       (get-file-buffer (cdr name)))))
                    (cons (cdr name) (buffer-chars-modified-tick buf))))
                names)))

(defun ebp-org--files-stamp ()
  "A full-resolution freshness stamp for the agenda file set.
\(DISK . BUFFERS): what the files say and what their live buffers say.
Neither half alone is the truth the cache serves — see the two
functions above."
  (let ((memo (ebp-org--stamp-disk)))
    (cons (cdr memo) (ebp-org--stamp-buffers (car memo)))))

(defun ebp-org--cache-key (namespace &rest parts)
  "Build a cache key from NAMESPACE and PARTS.
Scoped to today's date and the agenda files' stamp, so external edits,
membership changes, and date roll-over all bust the cache.  NAMESPACE
stays at `nth 2' — `ebp-org-cache-invalidate' reads it there."
  (cons (format-time-string "%Y-%m-%d")
        (cons (ebp-org--files-stamp)
              (cons namespace parts))))

(defvar ebp-org--cache-generation nil
  "The (DATE . STAMP) head every live entry in the cache is keyed under.")

(defun ebp-org--cache-admit (key value)
  "Store VALUE under KEY, evicting so the table stays bounded.  Returns VALUE.
Both evictions are wholesale (JA-4 audit P2 — the poc's table only ever
grew).  A key carries (DATE STAMP) at its head, so the moment either
moves every older entry is unreachable FOREVER: the buffer tick is
monotonic and the date rolls forward, so a superseded generation is
dead weight, not a cache.  Within the live generation
`ebp-org-cache-max' bounds the table, because the rest of the key
is wire-supplied query text."
  (let ((generation (cons (nth 0 key) (nth 1 key))))
    (unless (equal generation ebp-org--cache-generation)
      (clrhash ebp-org--cache)
      (setq ebp-org--cache-generation generation))
    (when (>= (hash-table-count ebp-org--cache) ebp-org-cache-max)
      (clrhash ebp-org--cache))
    (puthash key value ebp-org--cache)))

(defmacro ebp-org-with-cache (namespace key &rest body)
  "Memoise BODY's result in `ebp-org--cache' under NAMESPACE and KEY.
KEY must distinguish everything the BODY's VALUE depends on that the
stamp does not — including which function produced it (P1-12)."
  (declare (indent 2))
  (let ((k (gensym "key")) (hit (gensym "hit")))
    `(let* ((,k (ebp-org--cache-key ,namespace ,key))
            (,hit (gethash ,k ebp-org--cache 'ebp-org--miss)))
       (if (eq ,hit 'ebp-org--miss)
           (ebp-org--cache-admit ,k (progn ,@body))
         ,hit))))

(defun ebp-org-cache-invalidate (&optional namespace)
  "Drop memoised org extractions (and the stat memo).
With NAMESPACE, only entries under it — the live generation stands, so
every other namespace keeps its entries.  Keys are collected before
removal — never `remhash' inside the `maphash' walk."
  (setq ebp-org--stamp-memo nil)
  (if namespace
      (let (dead)
        (maphash (lambda (k _v)
                   (when (equal (nth 2 k) namespace) (push k dead)))
                 ebp-org--cache)
        (dolist (k dead) (remhash k ebp-org--cache)))
    (clrhash ebp-org--cache)
    (setq ebp-org--cache-generation nil)))

;;;; Heading references — Emacs-side plists, never on the wire

(defun ebp-org-ref-at-point ()
  "Ref plist for the org heading at point:
\(:id ID-or-nil :file TRUENAME :pos INT :headline STRING).
Emacs-internal; a ref NEVER crosses the wire (D-4) — mint a token with
`ebp-org-ref-tokens'.  :file is a truename so the resolve-time root
check compares like with like."
  (save-excursion
    (unless (org-at-heading-p)
      (ignore-errors (org-back-to-heading t)))
    (let ((id (org-entry-get nil "ID"))
          (file (buffer-file-name)))
      (list :id (and (stringp id) (not (string-empty-p id)) id)
            :file (if file (file-truename file) "")
            :pos (point)
            :headline (or (nth 4 (org-heading-components)) "")))))

(defun ebp-org--find-in-file-by-id (id file)
  "Marker for ID in validated FILE, or nil.  Never `org-id-find':
its miss path runs `org-id-update-id-locations' — a full rescan of the
org-id file set — and falls back to the CURRENT buffer's file, which
inside the socket filter is whatever happened to be current."
  (ignore-errors (org-id-find-id-in-file id file 'marker)))

(defun ebp-org-resolve-ref (ref)
  "Resolve REF (a plist from `ebp-org-ref-at-point') to a marker.
Signals `ebp-org-refused' on policy (absolute/remote/roots/
readable — handler answer: `rejected') and `ebp-org-unresolved'
when the heading is genuinely gone OR AMBIGUOUS (content drift —
handler answer: `stale', the Companion re-presents; SPEC 14.5 mandates
stale over a guess).  Resolution: id in the validated file, id via
`org-id-locations' (the mapped file re-validated), trusted pos with a
MANDATORY headline check, then a headline scan that resolves only a
UNIQUE match (JA-4 audit P1-9 — the poc took the first duplicate and
mutated a heading the user never tapped).  Files open QUIETLY
\(NOWARN, under `ebp-org--with-clamped-io'): a changed-on-disk
question cannot reach the dispatch extent — resolution answers from
the buffer it has."
  (let ((id (plist-get ref :id))
        (file (plist-get ref :file))
        (pos (plist-get ref :pos))
        (headline (plist-get ref :headline)))
    ;; A whole-valued pos can arrive as a float after a JSON round trip
    ;; (org.json emits the trailing .0); without the coercion the
    ;; trusted-position path fails and the headline scan may resolve the
    ;; wrong heading among duplicate titles.
    (when (numberp pos) (setq pos (truncate pos)))
    (ebp-org--with-clamped-io
      (let* ((true (and (stringp file) (not (string-empty-p file))
                        (ebp-org--check-file file)))
             (marker
              (or
               ;; 1. The stable id, in the ref's own (validated) file.
               (and true (stringp id) (not (string-empty-p id))
                    (ebp-org--find-in-file-by-id id true))
               ;; 2. The id, wherever org-id last recorded it — with the
               ;;    mapped file put through the SAME policy guards.
               (and (stringp id) (not (string-empty-p id))
                    (hash-table-p org-id-locations)
                    (when-let* ((mapped (gethash id org-id-locations))
                                (mapped-true
                                 (condition-case nil
                                     (ebp-org--check-file mapped)
                                   (ebp-org-refused nil))))
                      (ebp-org--find-in-file-by-id id mapped-true)))
               ;; 3. Trusted position — only while the headline claim
               ;;    still holds.  MANDATORY (JA-4 audit P1-9, defect
               ;;    (b)): an empty :headline is a claim like any other
               ;;    ("this heading has no title" — `ref-at-point'
               ;;    mints \"\" for those), never a gate bypass; the
               ;;    empty short-circuit fell open in exactly the case
               ;;    it existed to catch.
               (and true (stringp headline)
                    (with-current-buffer (find-file-noselect true t)
                      (org-with-wide-buffer
                       (when (and (integerp pos)
                                  (<= (point-min) pos (point-max)))
                         (goto-char pos)
                         (when (ignore-errors (org-back-to-heading t) t)
                           (when (equal (or (nth 4 (org-heading-components))
                                            "")
                                        headline)
                             (copy-marker (point))))))))
               ;; 4. Headline scan — a UNIQUE match resolves; duplicates
               ;;    fall through to `ebp-org-unresolved' (stale,
               ;;    SPEC 14.5).  The poc took the FIRST match among
               ;;    duplicate titles and mutated a heading the user
               ;;    never tapped (P1-9).
               (and true (stringp headline) (not (string-empty-p headline))
                    (with-current-buffer (find-file-noselect true t)
                      (org-with-wide-buffer
                       (goto-char (point-min))
                       (let (matches)
                         (while (re-search-forward org-heading-regexp nil t)
                           (when (equal (nth 4 (org-heading-components))
                                        headline)
                             (push (line-beginning-position) matches)))
                         (when (and matches (null (cdr matches)))
                           (copy-marker (car matches))))))))))
        (or marker
            ;; The SYMBOL path only: no filename, no headline text — the
            ;; poc formatted the absolute path into this error and
            ;; callers pushed it to a device snackbar.
            (signal 'ebp-org-unresolved nil))))))

;;;; Wire tokens — the D-4 opaque per-scope replace-set table
;;
;; OWNER here is an opaque scope KEY.  This table never resolves it,
;; never validates it against the floor and only ever compares it with
;; `equal'; it partitions the mint, gates the lookup and names the
;; teardown sweep, and that is the whole of its meaning.  So every entry
;; point takes it as an ARGUMENT.  Scope is what the CALLER knows — a
;; surface builder knows which surface it is minting for; a timer, a
;; process filter and a batch run know nothing, and reading whatever
;; owner happened to be current would silently file their tokens under
;; someone else's scope, or under nobody's.

(defconst ebp-org-token-set-max 512
  "Refs per (owner,set); minting beyond signals (a build-time error).")

(defconst ebp-org-token-sets-max 32
  "Sets per owner; minting a new set beyond signals.")

(defvar ebp-org--tokens (make-hash-table :test #'equal)
  "TOKEN-STRING -> (:owner O :set S :ref REF-PLIST).")

(defvar ebp-org--token-sets (make-hash-table :test #'equal)
  "(OWNER . SET) -> list of live token strings, for the replace sweep.")

(defvar ebp-org--token-nonce
  (format "%08x" (random #x100000000))
  "Per-session opacity salt; re-minted by `ebp-org-reset'.")

(defvar ebp-org--token-counter 0)

(cl-defun ebp-org-ref-tokens (refs &key (set "default") owner)
  "Mint one opaque token per REF, REPLACING the (OWNER,SET) entry.
OWNER is required and is passed as `:owner', never inherited: it is
the caller's own scope key (see the section comment above), and the
caller minting the refs is the only one that knows it.  Every token
previously minted for this (owner,set) dies at install — a re-render
re-mints, so the table size stays equal to the live sets and a swept
token is a plain miss (the `results.visit' replace-set shape).
ATOMIC (JA-4 audit P1-8): every ref is validated FIRST; the replace
sweep and the install of BOTH tables run together only once nothing
can signal — a failed mint leaves the tables and the live generation
exactly as they were.  (The poc swept, half-installed, then signalled:
orphan tokens unreachable by the replace sweep, by owner teardown and
by the set cap, plus a surface whose live tokens all died at once.)
A ref whose :file fails the resolve policy signals at MINT time:
statically invalid input fails at build, not at tap — as does a REF
that is not a plist carrying :file at all (P1-12).  Returns tokens in
REFS order."
  (unless (stringp owner)
    (error "ebp-org-ref-tokens: no owner (pass :owner)"))
  (when (> (length refs) ebp-org-token-set-max)
    (error "ebp-org-ref-tokens: %d refs exceeds the %d per-set cap"
           (length refs) ebp-org-token-set-max))
  (let ((key (cons owner set)))
    (unless (gethash key ebp-org--token-sets)
      (let ((sets 0))
        (maphash (lambda (k _v) (when (equal (car k) owner)
                                  (setq sets (1+ sets))))
                 ebp-org--token-sets)
        (when (>= sets ebp-org-token-sets-max)
          (error "ebp-org-ref-tokens: owner %s exceeds %d sets"
                 owner ebp-org-token-sets-max))))
    ;; Pass 1 — validate EVERY ref while both tables stay untouched.
    (dolist (ref refs)
      ;; SHAPE first (JA-4 audit P1-12): `(plist-get "Alpha" :file)'
      ;; returns nil rather than signalling, so a list of display
      ;; STRINGS — exactly what a mis-keyed query used to hand back —
      ;; sailed past the policy check below and became live tokens.
      ;; The offending value is not echoed (23.3): it may be user text
      ;; or a path.
      (unless (and (plistp ref) (plist-member ref :file))
        (error "ebp-org-ref-tokens: not a ref plist (%s)" (type-of ref)))
      (let ((file (plist-get ref :file)))
        (when (and (stringp file) (not (string-empty-p file)))
          (ebp-org--check-file file))))
    ;; Pass 2 — mint locally; still no table writes.
    (let ((entries
           (mapcar (lambda (ref)
                     (cons (format "o%s-%x" ebp-org--token-nonce
                                   (cl-incf ebp-org--token-counter))
                           ref))
                   refs)))
      ;; Pass 3 — the replace sweep + BOTH installs, signal-free.
      (dolist (old (gethash key ebp-org--token-sets))
        (remhash old ebp-org--tokens))
      (dolist (entry entries)
        (puthash (car entry)
                 (list :owner owner :set set :ref (cdr entry))
                 ebp-org--tokens))
      (puthash key (mapcar #'car entries) ebp-org--token-sets)
      (mapcar #'car entries))))

(cl-defun ebp-org-token-ref (token &key owner)
  "TOKEN -> its ref plist within OWNER's scope, or nil.
nil for an unknown token, an owner mismatch, a swept set, or a
non-string TOKEN — all of which a handler answers as `stale' (14.5:
the list moved under the user; re-present, never mis-jump).  The
handler distinguishes arg-SHAPE errors (`rejected') itself.
OWNER is required and is passed as `:owner', never inherited, and its
check sits INSIDE the TOKEN gate on purpose.  A junk token is device
input and keeps answering `stale'; a missing owner is a bug in the
CALLER, and it cannot be allowed to look like one.  With no owner
every `equal' below fails, so every lookup misses and every tap on a
live surface answers `stale' — a screen that has quietly stopped
working, with nothing in any log to say so.  So it signals instead."
  (when (stringp token)
    (unless (stringp owner)
      (error "ebp-org-token-ref: no owner (pass :owner)"))
    (let ((entry (gethash token ebp-org--tokens)))
      (when (and entry (equal (plist-get entry :owner) owner))
        (plist-get entry :ref)))))

(defun ebp-org-teardown-owner (owner)
  "Sweep OWNER's token sets with its registration (live-reload hygiene).
PUBLIC, and named for what it does rather than for when it happens: any
scope owner may drop its own tokens by calling this, and the sweep is
the token table's business alone — it reads no floor state and answers
to the same opaque scope key the mint took.
WHO CALLS IT is the caller's business, not this function's.  today the
only caller is the registration in `jetpacs-org.el', which after the
split is the whole of what that file does; the engine neither knows nor
needs to know that a floor lifecycle exists."
  (let (dead)
    (maphash (lambda (key _tokens)
               (when (equal (car key) owner) (push key dead)))
             ebp-org--token-sets)
    (dolist (key dead)
      (dolist (token (gethash key ebp-org--token-sets))
        (remhash token ebp-org--tokens))
      (remhash key ebp-org--token-sets))))
;;;; Mutations

(defvar-local ebp-org--save-timer nil
  "This buffer's pending deferred save, or nil.  ONE per buffer: the
poc armed a fresh timer per mutation — ten taps, ten timers, nine
no-op wakeups all holding the buffer.")

(defun ebp-org--save-now (buf)
  "The deferred save body: save BUF, never prompting, never signalling.
The stock path PROMPTS in four places — `yes-or-no-p' on supersession
and on a WRITE-PROTECTED file, `ask-user-about-lock' on a foreign
lock, and the `require-final-newline' question — and a prompt inside a
timer wedges a daemon with nobody to answer it.  The two cheap cases
are answered by inspection below; the save itself runs under
`ebp-org--with-clamped-io', so anything that would still ask
\(write-protected, final-newline, a drift landing after the modtime
check) becomes a message-refusal — a signal must never escape a timer."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (setq ebp-org--save-timer nil)
      (when (buffer-modified-p)
        (cond
         ((not (verify-visited-file-modtime buf))
          (message "ebp-org: NOT saving %s — file changed on disk \
(resolve in Emacs, then save)" (buffer-name buf)))
         ((let ((lock (file-locked-p buffer-file-name)))
            (and lock (not (eq lock t))))
          (message "ebp-org: NOT saving %s — locked by another \
process" (buffer-name buf)))
         (t (condition-case nil
                (ebp-org--with-clamped-io (save-buffer))
              (ebp-org-refused
               (message "ebp-org: NOT saving %s — needs interactive \
input" (buffer-name buf))))))))))

(defun ebp-org-defer-save ()
  "Schedule ONE idle save for the current buffer."
  (unless (timerp ebp-org--save-timer)
    (setq ebp-org--save-timer
          (run-with-idle-timer 0.5 nil #'ebp-org--save-now
                               (current-buffer)))))

(defmacro ebp-org-with-mutation (ref namespace &rest body)
  "Resolve REF, run BODY at its heading widened, bust NAMESPACE, defer save.
Widening is load-bearing: the poc mutated without it, and a narrowed
buffer whose restriction excluded the marker silently edited the wrong
position.  The marker is released after use.  The WHOLE extent —
resolve, BODY, invalidate, defer — runs under
`ebp-org--with-clamped-io' (D2): supersession against a drifted
file, the `++' repeater catch-up question, a changed-on-disk reread —
every would-be prompt surfaces as `ebp-org-refused', a status the
handler answers."
  (declare (indent 2))
  `(ebp-org--with-clamped-io
     (let ((marker (ebp-org-resolve-ref ,ref)))
       (unwind-protect
           (with-current-buffer (marker-buffer marker)
             (org-with-wide-buffer
              (goto-char marker)
              (prog1 (progn ,@body)
                (ebp-org-cache-invalidate ,namespace)
                (ebp-org-defer-save))))
         (set-marker marker nil)))))

(defun ebp-org-set-property (ref namespace prop value)
  "Set PROP to VALUE on the heading at REF."
  (ebp-org-with-mutation ref namespace
    (org-entry-put (point) prop value)))

(defvar ebp-org-toggle-todo-cancelled-note nil
  "The `org-log-note-how' kind the last toggle CANCELLED, or nil.
`ebp-org-toggle-todo' clears it on entry and sets it when it must
cancel a pending free-text note (any kind outside time/state — those
need interactive input this extent cannot host).  JA-5's dialog layer
reads it to follow up with a `capture_fields' note dialog, closing the
loop the cancel would otherwise silently drop.")

(defun ebp-org-toggle-todo (ref namespace &optional state)
  "Set the TODO state at REF to STATE, or toggle if nil.
Flushes org's state/repeat log note inline — `org-todo' queues it onto
`post-command-hook' (via `org-add-log-setup'), which never fires here:
a phone action runs inside the socket process filter, not the command
loop.  The flush is GATED on `org-log-note-how' being `time' or
`state': only those store immediately (org 9.7 `org-add-log-note'
branches on exactly that set) — every other kind pops a modal
*Org Note* buffer waiting for a C-c C-c the device can never send,
while `save-window-excursion' hides the damage and the LOGBOOK line is
never written.  For those kinds the pending note is CANCELLED instead
and the skip is surfaced — and recorded in
`ebp-org-toggle-todo-cancelled-note' so JA-5's `capture_fields'
note dialog can pick it up.  The note is only ONE of the interactive
hazards on this path: `ebp-org-with-mutation' runs the whole
toggle under `ebp-org--with-clamped-io', so the rest — the `++'
repeater catch-up question, supersession, changed-on-disk — surface
as `ebp-org-refused'."
  (setq ebp-org-toggle-todo-cancelled-note nil)
  (ebp-org-with-mutation ref namespace
    (org-todo state)
    (when (bound-and-true-p org-log-setup)
      (if (and (boundp 'org-log-note-how)
               (memq org-log-note-how '(time state)))
          (save-window-excursion
            (let ((this-command org-log-note-this-command))
              (org-add-log-note)))
        ;; Cancel the deferred note outright: on a shared interactive
        ;; Emacs the hook WOULD later fire and pop *Org Note* into the
        ;; desktop user's face for a device action they never took.
        (remove-hook 'post-command-hook 'org-add-log-note)
        (setq org-log-setup nil)
        (setq ebp-org-toggle-todo-cancelled-note
              (and (boundp 'org-log-note-how) org-log-note-how))
        (message "ebp-org: log note skipped — %S needs interactive \
input (the JA-5 note dialog follows up)"
                 ebp-org-toggle-todo-cancelled-note)))))

(defun ebp-org-set-planning (ref namespace which date-str)
  "Set the WHICH planning stamp at REF to DATE-STR.
WHICH is \"SCHEDULED\" or \"DEADLINE\"; an empty or nil DATE-STR
removes the stamp.  `org-add-planning-info' wants the type as a symbol,
and removal is the trailing remove-arg form — the string form and the
nonexistent `org-remove-planning-info' both signalled (pinned in ERT:
this is undocumented org behavior we depend on)."
  (let ((type (pcase (upcase (or which ""))
                ("SCHEDULED" 'scheduled)
                ("DEADLINE" 'deadline)
                (_ (user-error "Unsupported planning type: %s" which)))))
    (ebp-org-with-mutation ref namespace
      (if (or (null date-str) (string-empty-p date-str))
          (org-add-planning-info nil nil type)
        (org-add-planning-info type date-str)))))

;;;; Typed extraction

(defun ebp-org-entry-typed-value (prop type)
  "Extract the value of PROP at point according to TYPE.
TYPE is one of `text', `checkbox', `date', `enum', `number', `list'."
  (let ((val (org-entry-get (point) prop)))
    (pcase type
      ('checkbox (equal val "[X]"))
      ('date (and val (not (string-empty-p val)) val))
      ('number (and val (string-to-number val)))
      ('enum
       ;; A PROP_ALL constraint, when present, is enforced.
       (let ((allowed (org-entry-get (point) (concat prop "_ALL") t)))
         (if allowed
             (let ((options (split-string allowed "[ \t]+" t)))
               (if (member val options) val nil))
           (and val (not (string-empty-p val)) val))))
      ('list
       (and val (split-string val "[, \t]+" t)))
      (_ (or val "")))))

;;;; Query parser — the wire-facing grammar (O2)

(defconst ebp-org-ql-literals '(today nil t < <= > >= =)
  "Symbols with grammar meaning that vetting must not stringify.")

(defconst ebp-org-note-query-terms
  '(and or not todo done tags priority heading regexp property level
        scheduled deadline habit)
  "The head symbols of the built-in query grammar — the INTERPRETER'S
coverage set (an arm checks its accessor against it).  This is
NOT the wire allowlist: the sexp arm vets against
`ebp-org--wire-query-terms', which drops `regexp'.")

(defconst ebp-org--wire-query-terms
  '(and or not todo done tags priority heading property level
        scheduled deadline habit)
  "The SPEC 23.2 sexp-arm allowlist: a wire query may name these heads
and nothing else.  `regexp' is deliberately absent (JA-4 audit P1-2 /
SPEC #137) — a wire (regexp …) hands the peer a raw regexp engine
\(ReDoS at will); `heading' regexp-quotes and covers the use case, and
the token arm mints its `regexp' clauses from canonical quoted material
without passing through the vetter.")

(defconst ebp-org--query-max-depth 8)
(defconst ebp-org--query-max-nodes 128)
(defconst ebp-org--query-max-chars 200
  "Cap on a wire query string and on any single string leaf inside one.
Matches `jetpacs-files-grep-max-query-chars' (SPEC #138 spirit): the
peer gets a search box, not a buffer upload.")

(defun ebp-org--read-query (q)
  "Read exactly ONE form from wire string Q, obarray-safely.
The read runs under a THROWAWAY obarray (the ebp.el E4b move): a bare
`read' on a wire string interns every distinct symbol in every query
ever sent into the global obarray, permanently — measured, not
theoretical.  `read-circle' is nil so #1=#1# dies as a reader error
instead of looping the interpreter.  Trailing content after the form is
refused: a smuggled second form must never parse as
accepted-and-ignored."
  (let* ((obarray (obarray-make))
         (read-circle nil)
         (parse (condition-case nil
                    (read-from-string q)
                  (error (user-error "Malformed query"))))
         (rest (string-trim (substring q (cdr parse)))))
    (unless (string-empty-p rest)
      (user-error "Malformed query (trailing content)"))
    (car parse)))

(defun ebp-org--vet-query (form)
  "Vet, normalize and RE-HOME sexp query FORM in one schema-checked walk.
Output invariant (enforced, not aspirational): heads are the canonical
interned symbols of `ebp-org--wire-query-terms'; every string is a
FRESH propertyless copy no longer than `ebp-org--query-max-chars'
\(JA-4 audit P1-3 — the reader mints propertized strings from #(…) wire
text, with throwaway symbols riding in the property list); every other
atom is an integer or a canonical grammar literal (the comparators,
`today', the :on/:from/:to keywords); and every clause carries
schema-checked arity — so the throwaway-obarray symbols from
`ebp-org--read-query' die here and the interpreter fallthroughs are
internal invariants.  `quote' wrappers of the exact 2-element (quote X)
shape are unwrapped (the reader minted them from \\='(...) input; the
loose unwrap silently discarded trailing forms); bare symbols in string
position become fresh strings, exactly as the poc normalizer did.
Everything else — floats, vectors, records, byte-code objects (the
reader will happily mint one from #[...]), hash-table forms, stray
keywords, a wire `regexp' head — is refused outright.  Arity and type
violations refuse as \"Malformed HEAD clause\": the head symbol at
most, NEVER the query text (23.3), and cap violations never echo the
query either (it is user data)."
  (let ((nodes 0))
    (cl-labels
        ((visit (depth)
           (when (> depth ebp-org--query-max-depth)
             (user-error "Query too deep"))
           (when (> (cl-incf nodes) ebp-org--query-max-nodes)
             (user-error "Query too large")))
         (unq (x)
           ;; Exact 2-element (quote X) only — the shape the reader
           ;; mints from 'X.
           (while (and (consp x) (symbolp (car x))
                       (equal (symbol-name (car x)) "quote")
                       (consp (cdr x)) (null (cddr x)))
             (setq x (cadr x)))
           x)
         (bounded (s)
           (when (> (length s) ebp-org--query-max-chars)
             (user-error "Query too large"))
           ;; Fresh copy even for `symbol-name' output — that string is
           ;; the symbol's OWN name storage, never to be shared.
           (substring-no-properties s))
         (bad (head)
           (user-error "Malformed %s clause" head))
         (str (x depth)
           ;; A string-position leaf: fresh bounded string out.
           (visit depth)
           (setq x (unq x))
           (cond
            ((stringp x) (bounded x))
            ((and (symbolp x) (string-prefix-p ":" (symbol-name x)))
             (user-error "Unsupported query keyword"))
            ((symbolp x) (bounded (symbol-name x)))
            (t (user-error "Unsupported query value"))))
         (int (x head depth)
           (visit depth)
           (unless (integerp x) (bad head))
           x)
         (clause (x depth)
           (setq x (unq x))
           (visit depth)
           (unless (and (consp x) (symbolp (car x)) (proper-list-p x))
             (user-error "Malformed query clause"))
           (let* ((name (symbol-name (car x)))
                  (head (cl-find name ebp-org--wire-query-terms
                                 :key #'symbol-name :test #'equal))
                  (args (cdr x))
                  (n (length args)))
             (unless head
               (user-error "Unsupported query term"))
             (cons
              head
              (pcase head
                ((or 'and 'or)
                 (unless (>= n 1) (bad head))
                 (mapcar (lambda (a) (clause a (1+ depth))) args))
                ('not
                 (unless (= n 1) (bad head))
                 (list (clause (car args) (1+ depth))))
                ((or 'todo 'tags 'heading)
                 (mapcar (lambda (a) (str a (1+ depth))) args))
                ((or 'done 'habit)
                 (when args (bad head))
                 nil)
                ('priority
                 (let* ((cmps '("<" "<=" ">" ">=" "="))
                        (op (and (= n 2) (symbolp (car args))
                                 (car (member (symbol-name (car args))
                                              cmps)))))
                   (if op
                       ;; (OP VAL): comparator + a string-or-int bound.
                       (let ((val (cadr args)))
                         (visit (1+ depth))
                         (visit (1+ depth))
                         (unless (or (stringp val) (integerp val))
                           (bad head))
                         (list (intern op)
                               (if (stringp val) (bounded val) val)))
                     ;; Member form: string leaves, no comparator names.
                     (mapcar (lambda (a)
                               (when (and (symbolp a)
                                          (member (symbol-name a) cmps))
                                 (bad head))
                               (str a (1+ depth)))
                             args))))
                ('property
                 (unless (<= 1 n 2) (bad head))
                 (let ((pname (str (car args) (1+ depth))))
                   ;; ALLTAGS/FILE/ITEM/… are path or derived data with
                   ;; dedicated heads; refusing them loses nothing and
                   ;; (property "FILE") would leak absolute paths.
                   (when (member (upcase pname) org-special-properties)
                     (user-error "Unsupported property name"))
                   (cons pname
                         (and (cdr args)
                              (list (str (cadr args) (1+ depth)))))))
                ('level
                 (unless (<= 1 n 2) (bad head))
                 (mapcar (lambda (a) (int a head (1+ depth))) args))
                ((or 'scheduled 'deadline)
                 (unless (cl-evenp n) (bad head))
                 (let (out)
                   (while args
                     (let ((k (pop args)) (v (pop args)))
                       (visit (1+ depth))
                       (visit (1+ depth))
                       (unless (and (symbolp k)
                                    (member (symbol-name k)
                                            '(":on" ":from" ":to")))
                         (bad head))
                       (push (intern (symbol-name k)) out)
                       (push (cond
                              ((integerp v) v)
                              ((and (symbolp v)
                                    (equal (symbol-name v) "today"))
                               'today)
                              ((and (stringp v)
                                    (string-match-p
                                     "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}"
                                     v))
                               (bounded v))
                              (t (bad head)))
                             out)))
                   (nreverse out))))))))
      (clause form 0))))

(defun ebp-org--query-tokens (q)
  "Split query Q on whitespace, keeping \"quoted phrases\" whole.
The empty quoted phrase (\"\") is DROPPED, not returned: downstream it
minted a match-everything (regexp \"\") clause (JA-4 audit P1-4).  The
\\\\S-+ arm can never produce an empty match."
  (let ((pos 0) (tokens nil))
    (while (string-match "\"\\([^\"]*\\)\"\\|\\S-+" q pos)
      (let ((tok (or (match-string 1 q) (match-string 0 q))))
        (unless (string-empty-p tok) (push tok tokens)))
      (setq pos (match-end 0)))
    (nreverse tokens)))

(defun ebp-org-parse-query (query)
  "Parse the search QUERY string into a vetted query sexp, or nil if empty.
Accepts three input shapes:
- a query sexp:    (and (todo \"TODO\") (tags \"work\"))
- filter tokens:   todo:TODO,NEXT tags:work priority:A
- free text:       \"exact phrase\" or bare words
The sexp arm is wire-hardened (SPEC 23.2): obarray-safe read, head and
leaf allowlists, arity/type schema, depth/size caps — see
`ebp-org--vet-query'.  The token and free-text arms never touch the
reader.  BOTH arms sit behind the `ebp-org--query-max-chars' length
cap (JA-4 audit P1-4 — the caps previously governed the sexp arm only):
an over-length QUERY refuses as \"Query too long\" before the reader or
the tokenizer sees it.  Signals `user-error' on anything malformed.
A query of nothing but empty phrases parses to nil (empty query), never
to (regexp \"\") and never to a bare (and)."
  (let ((q (string-trim (or query ""))))
    (cond
     ((string-empty-p q) nil)
     ((> (length q) ebp-org--query-max-chars)
      (user-error "Query too long"))
     ((string-match-p "\\`'?(" q)
      (ebp-org--vet-query (ebp-org--read-query q)))
     (t
      (let ((clauses
             (mapcar
              (lambda (tok)
                (cond
                 ((string-prefix-p "todo:" tok)
                  `(todo ,@(split-string (substring tok 5) "," t)))
                 ((string-prefix-p "tags:" tok)
                  `(tags ,@(split-string (substring tok 5) "," t)))
                 ((string-prefix-p "priority:" tok)
                  `(priority ,@(split-string (substring tok 9) "," t)))
                 (t `(regexp ,(regexp-quote tok)))))
              (ebp-org--query-tokens q))))
        ;; Unreachable under the 200-char cap; pins the size invariant
        ;; on this arm if the bound ever moves.
        (when (> (length clauses) ebp-org--query-max-nodes)
          (user-error "Query too large"))
        (cond ((cdr clauses) `(and ,@clauses))
              (t (car clauses))))))))

;;;; The query interpreter

(defun ebp-org--planning-day (spec)
  "Resolve a query date SPEC to an absolute day number."
  (cond
   ((eq spec 'today) (time-to-days (current-time)))
   ((integerp spec) (+ (time-to-days (current-time)) spec))
   ((stringp spec) (time-to-days (org-time-string-to-time spec)))
   ;; Unreachable for vetted input; never echo the spec (user data).
   (t (user-error "Unsupported query date"))))

(defun ebp-org--planning-match-spec (stamp args)
  "Match raw planning STAMP string against ARGS plist (:on / :from / :to).
Empty ARGS means mere presence of the stamp."
  (and (stringp stamp) (not (string-empty-p stamp))
       (let ((day (time-to-days (org-time-string-to-time stamp)))
             (on (plist-get args :on))
             (from (plist-get args :from))
             (to (plist-get args :to)))
         (and (or (not on) (equal day (ebp-org--planning-day on)))
              (or (not from) (>= day (ebp-org--planning-day from)))
              (or (not to) (<= day (ebp-org--planning-day to)))))))

(defun ebp-org--entry-priority ()
  "The priority character of the heading at point, or nil."
  (save-excursion (org-back-to-heading t) (nth 3 (org-heading-components))))

(defun ebp-org-matches-p (tree get)
  "Non-nil when the entry read through accessor GET matches query TREE.
The ONE interpreter of the built-in grammar, and the engine's
extension point: TREE is a vetted query sexp, GET is an accessor that
reads whatever the caller's entries actually live in.  Base plugs in
the org entry at point (`ebp-org-entry-matches-p'); the vulpea
arm plugs in a note-index record; a test plugs in a plain closure over
an alist.  The grammar is shared, the accessor is the seam.

GET is called as (funcall GET WHAT &rest ARGS), with WHAT one of the
ten accessor questions:
  todo             the todo keyword string, or nil;
  done             non-nil when the entry sits in a done state;
  tags             the list of tag strings;
  priority         the priority CHARACTER (?A), or nil;
  title            the heading text, a string;
  level            the outline level, an integer;
  property NAME    the value of property NAME, or nil;
  planning WHICH   the raw stamp string for WHICH, \"SCHEDULED\" or
                   \"DEADLINE\";
  habit            non-nil when the entry is a habit;
  regexp-match RE  non-nil when RE matches the entry's text.
An accessor that answers nil for a question it cannot serve simply
never matches the terms built on it.

An accessor may APPROXIMATE, deliberately.  The vulpea arm's
`regexp-match' searches title + properties and not the body, because
the note index does not carry the body and visiting the file to be
exact would throw away the entire point of an index read.  An arm
advertises the coverage it does support by checking its accessor
against `ebp-org-note-query-terms'; the approximation is
documented AT the arm, never hidden inside it.

CALLERS MUST VET TREE FIRST, with `ebp-org-parse-query'.  This
function interprets; it does not validate.  An unvetted head falls
through to a plain `error' naming ONLY the head symbol — query
material is user data and never rides in an error.  That fallthrough
is deliberately NOT `ebp-org-refused': under SPEC 14.4 a refusal
is a durable answer ABOUT THE REQUEST, so routing a caller's
programming error through it would record a permanent verdict against
the user's query for a bug in the calling code."
  (pcase tree
    (`(and . ,cs) (cl-every (lambda (c) (ebp-org-matches-p c get)) cs))
    (`(or . ,cs) (and (cl-some (lambda (c) (ebp-org-matches-p c get)) cs) t))
    (`(not ,c) (not (ebp-org-matches-p c get)))
    (`(todo . ,kws)
     (let ((st (funcall get 'todo)))
       (and st (if kws (and (member st kws) t)
                 (not (funcall get 'done))))))
    (`(done) (and (funcall get 'done) t))
    (`(tags . ,tags)
     (let ((have (funcall get 'tags)))
       (if tags (and (cl-some (lambda (tg) (member tg have)) tags) t)
         (and have t))))
    (`(priority ,(and op (pred symbolp)) ,val)
     (let ((pr (funcall get 'priority))
           (want (if (stringp val) (string-to-char val) val)))
       ;; org urgency runs A > B > C — the higher priority is the
       ;; smaller character, so the comparator flips against the chars.
       (and pr (pcase op
                 ('< (> pr want)) ('<= (>= pr want))
                 ('> (< pr want)) ('>= (<= pr want))
                 ('= (= pr want))
                 ;; Unreachable for vetted input; no echo.
                 (_ (user-error "Unsupported priority comparator"))))))
    (`(priority . ,ps)
     (let ((pr (funcall get 'priority)))
       (if ps (and pr (member (char-to-string pr) ps) t)
         (and pr t))))
    (`(heading . ,texts)
     (let ((hl (or (funcall get 'title) ""))
           (case-fold-search t))
       (cl-every (lambda (s) (string-match-p (regexp-quote s) hl)) texts)))
    (`(regexp . ,res)
     (cl-every (lambda (re) (funcall get 'regexp-match re)) res))
    (`(property ,name . ,val)
     (let ((v (funcall get 'property name)))
       (if val (equal v (car val)) (and v t))))
    (`(level ,n) (eql (funcall get 'level) n))
    (`(level ,n ,m) (let ((l (funcall get 'level))) (and l (<= n l m))))
    (`(scheduled . ,args)
     (ebp-org--planning-match-spec (funcall get 'planning "SCHEDULED") args))
    (`(deadline . ,args)
     (ebp-org--planning-match-spec (funcall get 'planning "DEADLINE") args))
    (`(habit) (and (funcall get 'habit) t))
    ;; `error', not `user-error': only a hand-built tree that bypassed
    ;; `ebp-org-parse-query' reaches here — an internal-invariant
    ;; breach.  The head symbol (or the tree's type) only, never the
    ;; tree itself: query material is user data.
    (_ (error "ebp-org-matches-p: unsupported clause head %s"
              (if (and (consp tree) (symbolp (car tree)))
                  (car tree)
                (type-of tree))))))

(defun ebp-org--point-get (what &rest args)
  "The grammar accessor over the org entry AT POINT."
  (pcase what
    ('todo (org-get-todo-state))
    ('done (let ((st (org-get-todo-state)))
             (and st (member st org-done-keywords) t)))
    ('tags (org-get-tags nil t))
    ('priority (ebp-org--entry-priority))
    ('title (nth 4 (org-heading-components)))
    ('level (org-current-level))
    ('property (org-entry-get (point) (car args)))
    ('planning (org-entry-get (point) (car args)))
    ;; `org-is-habit-p' tests only the STYLE=habit property; repeater
    ;; validity is enforced later by `org-habit-parse-todo'.
    ('habit (and (fboundp 'org-is-habit-p) (org-is-habit-p)))
    ('regexp-match
     ;; The point haystack is the entry's body up to the next heading.
     (let ((end (save-excursion (outline-next-heading) (point)))
           (case-fold-search t))
       (save-excursion (re-search-forward (car args) end t))))))

(defun ebp-org-entry-matches-p (tree)
  "Non-nil when the org entry at point matches query sexp TREE."
  (ebp-org-matches-p tree #'ebp-org--point-get))

;; The vulpea note-index arm lives in jetpacs-org-vulpea.el (Tier-1
;; staging, NEVER required by base): base is vanilla Emacs, vulpea is
;; not built-in.  Base keeps only the seam it plugs into — the
;; accessor-pluggable `ebp-org-matches-p' above.  The accessor is
;; the extension point; `ebp-org--point-get' stays PRIVATE behind
;; the public `ebp-org-entry-matches-p', because reading the entry
;; at point is base's own arm, not a name anyone plugs into.

;;;; High-level query

(defun ebp-org--query-files ()
  "The explicit query scope: local agenda files that EXIST, or signal.
Routes through `ebp-org-agenda-files' — the SAME P1-7 floor filter
the roots and the cache stamp use — then drops entries whose files are
gone (JA-4 audit P1-5: `org-check-agenda-file' messages the ABSOLUTE
path and blocks on `read-char-exclusive' for a missing file).  An
EMPTY result signals the RETRYABLE `ebp-org-unavailable' (P1-10:
an unmounted vault comes back — never `rejected', which deletes the
durable record) with the distinct data symbol `no-agenda-files' (vs
the floor's `no-roots'): a nil scope handed to `org-map-entries' means
the CURRENT BUFFER — whatever the socket filter happened to have
current (sandbox drift).  Directory entries are NOT expanded to member
files — the stamp already treats raw entries as files, and the query
matches the module's own semantics, not the `org-agenda-files'
function's."
  (or (cl-remove-if-not #'file-exists-p (ebp-org-agenda-files))
      (signal 'ebp-org-unavailable (list 'no-agenda-files))))

(defun ebp-org--run-query (tree action)
  "Run vetted query TREE over the agenda files, calling ACTION at matches.
The scope is the EXPLICIT existence-filtered file list, never the
`agenda' symbol — that re-reads configuration through the
`org-agenda-files' FUNCTION (remote dialling, P1-7) and marches every
raw entry through `org-check-agenda-file' (the missing-file prompt,
P1-5)."
  (let ((files (ebp-org--query-files))
        ;; Belt and braces only: in 30.1 the `org-agenda-files' FUNCTION
        ;; is the sole consumer of this variable — the existence filter
        ;; above and the clamp's read-char-exclusive rebind are what
        ;; actually close P1-5.
        (org-agenda-skip-unavailable-files t)
        items)
    (ebp-org--with-clamped-io
      (org-map-entries
       (lambda ()
         (when (ebp-org-entry-matches-p tree)
           (push (funcall action) items)))
       nil files))
    (nreverse items)))

(defun ebp-org-query (namespace key tree action)
  "Run query sexp TREE over the agenda files, calling ACTION at matches.
Results are cached under NAMESPACE and KEY.  KEY is MANDATORY and must
identify the ACTION, not merely the caller (JA-4 audit P1-12): the
cached value is `(mapcar ACTION matches)', and a closure has no stable
printed identity, so keying on (namespace, tree) alone handed the
SECOND caller of a tree the FIRST caller's payload.  That is a D-4
breach, not merely a cache bug — one screen asks a tree for display
titles and for refs, and whichever ran second got the other list: ref
plists (absolute paths) to a text consumer, and bare strings to
`ebp-org-ref-tokens', whose per-ref policy check then silently did
nothing.  The TREE still enters the key beneath KEY, printed with
truncation switched OFF: `format \"%S\"' honours
`print-length'/`print-level', so a caller with either bound collided
two different trees onto one entry.

ALWAYS the built-in interpreter: the poc dispatched to
`org-ql-select' when installed, which meant (a) a permanently untested
semantic fork whose results silently changed when a package appeared,
and (b) an arbitrary-code hand-off — org-ql COMPILES query sexps.  If
full org-ql is ever wanted, it enters as a new, separately vetted entry
point, never as an fboundp fork here."
  (unless (and key (or (stringp key) (symbolp key)))
    (error "ebp-org-query: KEY must be a non-nil string or symbol"))
  (when tree
    (let ((printed (let ((print-length nil)
                         (print-level nil)
                         (print-circle t))
                     (format "%S" tree))))
      (ebp-org-with-cache namespace (cons key printed)
        (ebp-org--run-query tree action)))))

;;;; Shared org primitives (O3)
;; Timestamp field extractors, headless capture, the LOGBOOK parser,
;; planning-repeater surgery, and the #+TBLFM resolver — opinion-free
;; org machinery any Tier-1 can lean on.  Nothing here knows about
;; agendas or PKM.  (`file.add-heading' is deliberately absent — it
;; lands with JA-5's dialog module.  The outline model landed at JA-5a;
;; its card VIEW is Tier-1 staging.)

(defun ebp-org-ts-date (ts)
  "Return the YYYY-MM-DD date inside org timestamp string TS, or nil."
  (when (and (stringp ts)
             (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" ts))
    (match-string 1 ts)))

(defun ebp-org-ts-time (ts)
  "Return the HH:MM time inside org timestamp string TS, or nil."
  (when (and (stringp ts)
             (string-match "\\([0-9]\\{1,2\\}:[0-9]\\{2\\}\\)" ts))
    (match-string 1 ts)))

(defun ebp-org-ts-repeater (ts)
  "Return the repeater cookie (e.g. \"+1w\", \".+2d\") inside TS, or nil.
Repeaters only — delay cookies (-1d) deliberately do not match."
  (when (and (stringp ts)
             (string-match "\\([.+]?\\+[0-9]+[hdwmy]\\)" ts))
    (match-string 1 ts)))

(defun ebp-org-clocked-in-p (pos)
  "Whether the heading at POS in the current buffer is the clocked task."
  (and (bound-and-true-p org-clock-hd-marker)
       (marker-buffer org-clock-hd-marker)
       (eq (marker-buffer org-clock-hd-marker) (current-buffer))
       (save-excursion
         (goto-char pos)
         (= (line-beginning-position)
            (save-excursion (goto-char org-clock-hd-marker)
                            (line-beginning-position))))))

;;;; Headless capture
;; D-5 (reversed): `ebp-org-capture-run' is the SUBSTRATE the
;; rescheduled template-builder rung will stand on — the API here is a
;; consumer contract, not an implementation detail.  The poc carried a
;; byte-identical second copy of the prompts extractor 1,750 lines away;
;; ONE survives (D-5's dedupe, executed).

(defun ebp-org-capture-prompts (template-string)
  "Return the ordered field names to collect for TEMPLATE-STRING.
Each `%^{NAME}' or `%^{NAME|default}' contributes NAME (the default is
dropped from the label but honoured at fill time).  A `%?' body
position adds a leading \"Headline\" field.  Duplicates are removed."
  (let (prompts (start 0))
    (while (string-match "%\\^{\\([^}]+\\)}" template-string start)
      ;; Capture the match BEFORE `split-string' runs — it calls
      ;; `string-match' internally and would clobber the match data,
      ;; leaving `match-end' wrong and the loop spinning forever.
      (let ((spec (match-string 1 template-string))
            (end (match-end 0)))
        (push (string-trim (car (split-string spec "|"))) prompts)
        (setq start end)))
    (setq prompts (nreverse prompts))
    (delete-dups
     (if (string-match-p "%\\?" template-string)
         (cons "Headline" prompts)
       prompts))))

(defun ebp-org-capture-templates ()
  "The capture templates as plists (:key :description :prompts).
PROMPTS is a vector of field-name strings.  Plist-native — the poc's
alist projection was a poc-wire shape; JA-5 builds its own nodes from
this."
  (mapcar (lambda (tmpl)
            (let ((key (nth 0 tmpl))
                  (desc (nth 1 tmpl))
                  (template-string (nth 4 tmpl)))
              (list :key key
                    :description desc
                    :prompts (vconcat
                              (ebp-org-capture-prompts
                               (if (stringp template-string)
                                   template-string
                                 ""))))))
          org-capture-templates))

;;;; Wire values are DATA, never template source (SPEC 23.2, amendment #139)

(defvar ebp-org--capture-nonce nil
  "Per-run salt for capture sentinels, bound by `ebp-org-capture-run'.")

(defun ebp-org--capture-sentinel (n)
  "An inert placeholder standing in for substituted value N.
Pure alphanumeric ON PURPOSE: it must pass through every `org-capture'
expansion sweep untouched, so it may contain none of % ^ [ ] < > ( ) :
and must not read as a link, a timestamp, or a property."
  (format "JPCAPZ%sX%dZ" (or ebp-org--capture-nonce "0") n))

(defun ebp-org--capture-restore (bindings)
  "Replace each sentinel in BINDINGS with its raw value, in this buffer.
Runs from `org-capture-before-finalize-hook' — AFTER org has finished
every expansion.  That ordering IS the security property: a value can
only be interpreted if it is present while an interpreter runs, so it
is absent until none will.

Two details are load-bearing:
- ONE pass over an alternation, never a loop per binding.  Sequential
  passes rescan already-substituted text, so one value could be re-read
  as another value's sentinel.
- `replace-match' with LITERAL non-nil.  Otherwise the VALUE is read as
  a replacement template and a literal \\=\\1 or & in user text edits the
  buffer — the same defect one layer down."
  (when bindings
    (save-excursion
      (let ((re (regexp-opt (mapcar #'car bindings))))
        (goto-char (point-min))
        (while (re-search-forward re nil t)
          (replace-match (cdr (assoc (match-string 0) bindings)) t t))))))

(defun ebp-org-capture-fill (tmpl values)
  "Fill org capture TMPL from VALUES; return the cons (TEXT . BINDINGS).
VALUES is STRING-keyed (`assoc') — deliberately outside the alist->plist
migration; the keys are the human field names the prompts extractor
produced.  TEXT carries an inert sentinel everywhere a WIRE-supplied
value belongs, and BINDINGS maps each sentinel to its raw value for
`ebp-org--capture-restore' to install once expansion is over.

The values are deliberately NOT substituted here.  `org-capture' expands
whatever template it is handed, so a value pasted in beforehand is
indistinguishable from template the user wrote: `%(sexp)' in a phone
field would reach `org-eval', and `%[PATH]' would read a local file into
the user's org file (JA-4 audit P1-1, both reproduced).  There is no
escaping alternative — org-capture has NO literal-percent escape
\(verified against emacs-30.1 lisp/org/org-capture.el: every %% there is
inside a `format' string), and its expansion is a series of independent
regexp sweeps with no quoting syntax to hide behind.

A template DEFAULT is the user's own configuration, so it is substituted
directly and keeps org's semantics; only peer-supplied text is deferred.
Any interactive escape that survives (`%^t', `%^g', a valueless
`%^{…}') is stripped, so `org-capture' can never block on a minibuffer
prompt the phone cannot answer."
  (let* ((bindings '())
         (n 0)
         (stash (lambda (v)
                  (let ((s (ebp-org--capture-sentinel (cl-incf n))))
                    (push (cons s (or v "")) bindings)
                    s)))
         (headline (or (cdr (assoc "Headline" values)) "")))
    ;; %? — free-form body position, a wire value.
    (setq tmpl (replace-regexp-in-string
                "%\\?" (lambda (_) (funcall stash headline)) tmpl t t))
    ;; %^{NAME|default} — scan the template's own tokens so NAME always
    ;; matches what `ebp-org-capture-prompts' produced.
    (setq tmpl (replace-regexp-in-string
                "%\\^{\\([^}]*\\)}"
                (lambda (m)
                  ;; M is the whole \"%^{…}\" match; parse it directly —
                  ;; match-data is unreliable inside this callback.
                  (let* ((spec (substring m 3 -1))
                         (bar (string-search "|" spec))
                         (name (string-trim
                                (if bar (substring spec 0 bar) spec)))
                         (default (and bar (substring spec (1+ bar))))
                         (val (cdr (assoc name values))))
                    (cond ((and (stringp val) (not (string-empty-p val)))
                           (funcall stash val))
                          ((stringp default) default)
                          (t ""))))
                tmpl t t))
    (cons (replace-regexp-in-string "%\\^.?" "" tmpl t t) bindings)))

(defun ebp-org-capture-run (template-key values &optional extra-body)
  "Run capture for TEMPLATE-KEY with VALUES alist (NAME -> user input).
EXTRA-BODY, when non-empty, is appended below the filled template — the
carrier for text shared from another app.  An unknown TEMPLATE-KEY
SIGNALS: the poc silently no-opped, which read as a capture that
vanished."
  (let ((ebp-org--capture-nonce (format "%08x" (random (expt 2 32))))
        (entry (assoc template-key org-capture-templates))
        (bindings '()))
    ;; A 2-element entry is a legal PREFIX GROUP, not a template
    ;; (\"b\" \"Templates for marking stuff to buy\") — indexing nth 4 on
    ;; one signalled wrong-type-argument.
    (unless (and entry (> (length entry) 4))
      (user-error "No capture template %S" template-key))
    (let* ((tmpl (nth 4 entry))
           (filled (if (stringp tmpl)
                       (let ((pair (ebp-org-capture-fill tmpl values)))
                         (setq bindings (cdr pair))
                         (car pair))
                     tmpl))
           ;; EXTRA-BODY is wire text too — the share-sheet carrier is the
           ;; one field an arbitrary other app controls verbatim — so it
           ;; gets a sentinel rather than being concatenated raw.
           (filled (if (and (stringp filled)
                            (stringp extra-body)
                            (not (string-empty-p (string-trim extra-body))))
                       (let ((s (ebp-org--capture-sentinel
                                 (1+ (length bindings)))))
                         (push (cons s (string-trim extra-body)) bindings)
                         (concat filled "\n" s))
                     filled))
           (new-entry (copy-sequence entry))
           ;; `plist-put' on a COPIED tail, never `append': org reads
           ;; :immediate-finish with `plist-get', which returns the FIRST
           ;; occurrence — the poc APPENDED, so a template carrying its
           ;; own `:immediate-finish nil' won and the capture buffer
           ;; waited forever for a C-c C-c nobody can press.
           (props (plist-put (copy-sequence (nthcdr 5 entry))
                             :immediate-finish t)))
      (setcar (nthcdr 4 new-entry) filled)
      (setcdr (nthcdr 4 new-entry) props)
      ;; `org-capture-entry' short-circuits template selection inside
      ;; `org-capture', so binding it to the FILLED copy is what makes
      ;; the pre-filled template the one that actually runs.  (Binding
      ;; the original re-ran the raw %^{…} prompts and double-asked the
      ;; user through the bridge.)
      (let* ((org-capture-entry new-entry)
             (restore (lambda () (ebp-org--capture-restore bindings)))
             ;; LET-bound, so it unwinds on a signal with no cleanup
             ;; branch.  If a capture somehow does not finish
             ;; synchronously the sentinels stay visible in the file:
             ;; garbage text, never execution — the right way to fail.
             (org-capture-before-finalize-hook
              (cons restore org-capture-before-finalize-hook)))
        ;; Safety net: if any escape slips through, never let
        ;; `org-capture' block forever on a minibuffer the phone can't
        ;; answer — `with-timeout' fires even inside a synchronous read.
        (with-timeout (30 (message "ebp-org: capture timed out (a \
prompt was left unanswered)"))
          (org-capture))))))

;;;; The LOGBOOK parser

(defun ebp-org-parse-logbook (text)
  "Parse LOGBOOK drawer TEXT into a list of entry plists.
Clock lines yield (:type clock :start … [:end :duration | :active]);
notes (:type note :timestamp :content); state changes (:type state :to
[:from] :timestamp :has-note :content).  Keywords match
case-insensitively — explicitly, like org-element, never via the
ambient `case-fold-search'."
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
        (setq current-entry (list :type 'clock :start (match-string 1 line)
                                  :active t)))
       ((string-match "^- Note taken on \\(\\[.*?\\]\\) \\\\\\\\$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'note :timestamp (match-string 1 line)
                                  :content "")))
       ((string-match "^- State \"\\(.*?\\)\"[ \t]+from \"\\(.*?\\)\"[ \t]+\\(\\[.*?\\]\\)\\(\\(?: \\\\\\\\\\)?\\)$" line)
        (when current-entry (push current-entry entries))
        (setq current-entry (list :type 'state :to (match-string 1 line)
                                  :from (match-string 2 line)
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
        ;; Continuation line.  `:content' is ABSENT on both clock shapes
        ;; — the poc read nil and concat'd a spurious leading newline.
        (when current-entry
          (let ((content (or (plist-get current-entry :content) "")))
            (setq current-entry
                  (plist-put current-entry :content
                             (if (string-empty-p content)
                                 line
                               (concat content "\n" line)))))))))
    (when current-entry (push current-entry entries))
    (nreverse entries)))

(defun ebp-org-logbook-entries (pos)
  "Return structured logbook entries for heading at POS, or nil.
Drawer delimiters match case-insensitively (\":logbook:\" is valid
org), explicitly rather than via ambient `case-fold-search'."
  (save-excursion
    (goto-char pos)
    (let ((case-fold-search t)
          (end (save-excursion (org-end-of-meta-data t) (point))))
      (goto-char pos)
      (when (re-search-forward "^[ \t]*:LOGBOOK:[ \t]*$" end t)
        (let ((start (match-end 0)))
          (when (re-search-forward "^[ \t]*:END:[ \t]*$" end t)
            (ebp-org-parse-logbook
             (buffer-substring-no-properties start
                                             (match-beginning 0)))))))))

;;;; Planning-repeater surgery

(defun ebp-org-set-repeater (type repeater)
  "Rewrite the repeater cookie on the TYPE planning timestamp at point.
TYPE is \"SCHEDULED\" or \"DEADLINE\"; REPEATER like \"+1w\" (nil
removes).  A heading without a TYPE timestamp is a no-op — and so is an
UNTERMINATED one: the poc's `search-forward' had no NOERROR arg, so a
timestamp missing its closer signalled `search-failed' out of the
function instead of declining."
  (save-excursion
    (org-back-to-heading t)
    (let ((bound (save-excursion (outline-next-heading) (point))))
      (when (re-search-forward (concat type ":[ \t]*\\([<[]\\)") bound t)
        (let* ((beg (match-beginning 1))
               (close (if (equal (match-string 1) "<") ">" "]"))
               (end (progn (goto-char beg)
                           (search-forward close bound t))))
          (when end
            (let* ((ts (buffer-substring-no-properties beg end))
                   (stripped (replace-regexp-in-string
                              "[ \t]+[.+]?\\+[0-9]+[hdwmy]" "" ts))
                   (new (if repeater
                            (concat (substring stripped 0 -1) " " repeater
                                    (substring stripped -1))
                          stripped)))
              (delete-region beg end)
              (goto-char beg)
              (insert new))))))))

;;;; The #+TBLFM resolver

(defun ebp-org-table-field-formula ()
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

;;;; The clock formatter

(defun ebp-org-format-clock-time (start end)
  "Human line for a clock span: same-day collapses to one date."
  (condition-case nil
      (let ((s-date (substring start 0 10))
            (s-time (substring start -5))
            (e-date (substring end 0 10))
            (e-time (substring end -5)))
        (if (equal s-date e-date)
            (format "%s, %s to %s" s-date s-time e-time)
          (format "%s %s to %s %s" s-date s-time e-date e-time)))
    (error (format "%s to %s" start end))))

;;;; The file-save seam

(defun ebp-org--default-file-save (_buffer)
  "Invalidate the org memo and schedule a save for the current buffer.
The default `ebp-org-file-save-function'."
  (ebp-org-cache-invalidate)
  (ebp-org-defer-save))

(defvar ebp-org-file-save-function #'ebp-org--default-file-save
  "Function called, with the just-mutated org BUFFER current, to persist it.
Apps rebind it to their own mutation tail — e.g. a synchronous save
plus a note-index refresh — so a generic core mutation keeps their
memo/index coherent.  (The poc's `file.add-heading' consumer of this
seam is JA-5's; the seam itself is engine machinery.)")

;;;; The outline model (JA-5a, amendment A3)
;; Heading records as pure org data — no nodes, no verbs, no owner.
;; Extraction is org fact and lives in base; the card list VIEW over
;; these records is opinion and lives in Tier-1 staging
;; (jetpacs-org-outline.el), per the ratified split.  Ported from
;; poc-v1 jetpacs-org.el 2456-2589.

(defcustom ebp-org-outline-max-headings 400
  "Cap on heading records returned by one collection pass.
Bounds very large files; `ebp-org-outline-cap' applies it."
  :type 'integer)

(defcustom ebp-org-outline-show-deadline t
  "Include each heading's DEADLINE string in its outline record."
  :type 'boolean)

(defcustom ebp-org-outline-show-clocked nil
  "Include each heading's clocked-minutes total in its outline record.
Off by default: the totals only exist after an `org-clock-sum' pass,
which a consumer must run itself — this switch just carries the value."
  :type 'boolean)

(defun ebp-org--outline-record (pos next)
  "Build a record plist for the heading at POS, whose extent ends at NEXT.
Members: :level :pos :line :props :todo :priority :title :tags :done
:deadline :clocked :body :body-start.  :body-start maps the body text
back to real buffer positions so a consumer can address interactive
elements (checkboxes) inside it."
  (save-excursion
    (goto-char pos)
    (let* ((comps (org-heading-components))
           (level (or (nth 0 comps) 1))
           (todo (nth 2 comps))
           (priority (nth 3 comps))
           (title (or (nth 4 comps) ""))
           (tags (ignore-errors (org-get-tags pos t)))
           (done (and todo (member todo org-done-keywords) t))
           (deadline (and ebp-org-outline-show-deadline
                          (ignore-errors (org-entry-get pos "DEADLINE"))))
           (clocked (and ebp-org-outline-show-clocked
                         (get-text-property pos :org-clock-minutes)))
           (line (buffer-substring-no-properties
                  (line-beginning-position) (line-end-position)))
           (props (ignore-errors (org-entry-properties pos 'standard)))
           (body-info
            (progn
              (goto-char pos)
              ;; No FULL arg: skip only planning + PROPERTIES (a consumer
              ;; shows those as their own affordances).  LOGBOOK and other
              ;; drawers stay in :body, where a renderer folds them.
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

(defun ebp-org-outline-collect (beg end include-first)
  "Collect heading records between BEG and END of the current org buffer.
INCLUDE-FIRST non-nil includes a heading sitting exactly at BEG (the
subtree case).  Uncapped — apply `ebp-org-outline-cap' at the edge
that renders."
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
             do (push (ebp-org--outline-record pos next) records))
    (nreverse records)))

(defun ebp-org-outline-tree (records)
  "Nest flat RECORDS into a tree by :level; each node gains :children.
Skipped levels nest under the nearest shallower ancestor."
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

(defun ebp-org-outline-cap (records)
  "RECORDS truncated to `ebp-org-outline-max-headings'."
  (seq-take records ebp-org-outline-max-headings))

(defun ebp-org-file-toplevel-records (file)
  "Capped level-1 heading records for org FILE, tagged :file and :buffer.
FILE goes through the root allowlist first — signals
`ebp-org-refused' outside `ebp-org-roots', exactly like every
other engine entry point (the poc read any path handed to it).  The
extra :file/:buffer members let a consumer mint a heading ref or a tap
target from a record."
  (let ((file (ebp-org--check-file file)))
    (with-current-buffer (find-file-noselect file t)
      (unless (derived-mode-p 'org-mode) (org-mode))
      (org-with-wide-buffer
       (let* ((buf (buffer-name))
              (all (ebp-org-outline-collect (point-min) (point-max) nil))
              (tops (cl-remove-if-not
                     (lambda (r) (= (plist-get r :level) 1)) all)))
         (mapcar (lambda (r)
                   (setq r (plist-put (copy-sequence r) :file file))
                   (plist-put r :buffer buf))
                 (ebp-org-outline-cap tops)))))))

;;;; Reset — every table this file owns, dropped

(defun ebp-org-reset ()
  "Reset engine state: cache, stat memo, tokens (fresh nonce), timers.
The application floor reaches this by `fboundp' probe rather than by
require, so that a build without the engine simply skips it.  That
makes the NAME load-bearing in the silent direction: rename it without
editing the probe and resets stop happening, with nothing anywhere to
say so."
  (clrhash ebp-org--cache)
  (setq ebp-org--cache-generation nil
        ebp-org--stamp-memo nil)
  (clrhash ebp-org--tokens)
  (clrhash ebp-org--token-sets)
  (setq ebp-org--token-nonce (format "%08x" (random #x100000000))
        ebp-org--token-counter 0)
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (timerp ebp-org--save-timer)
        (cancel-timer ebp-org--save-timer)
        (setq ebp-org--save-timer nil)))))

(defun ebp-org-unload-function ()
  "Unload hygiene: drop every table this file owns.
The `jetpacs-teardown-functions' registration is NOT removed here — it
is not this file's to remove.  `jetpacs-org.el' adds it and takes it
back in its own unload function; the engine only supplies the sweep."
  (ebp-org-reset)
  nil)

(provide 'ebp-org)
;;; ebp-org.el ends here
