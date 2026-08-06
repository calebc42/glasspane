;;; jetpacs-org.el --- The org extraction and mutation engine -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; JA-4 of docs/PLAN-jetpacs-apps.md: the org API the entire app tier
;; stands on — cache, heading refs and their wire tokens, the org-ql-
;; subset query grammar, mutations, and the shared primitives (capture,
;; LOGBOOK, planning cookies, TBLFM).  UI-FREE by construction: this
;; module requires no widgets and builds no nodes; JA-5's skin and any
;; Tier-1 (the D-1 block editor, glasspane at its port rung) consume it.
;;
;; THE ENGINE IS MOVING OUT (docs/PLAN-ebp-org-split.md).  By the rule
;; ratified 2026-08-06 — `jetpacs-' names what cannot exist without
;; Kotlin, Android, and Compose; `ebp-' names what only ever touches the
;; wire and Emacs — none of this is jetpacs work, and it now lives in
;; `ebp-org.el'.  G6 has taken the grammar and the primitives; what is
;; left below is the half that still reads through the root allowlist,
;; the cache, or a mutation, and it follows at G7, where this file
;; becomes a ~40-line registration shim carrying the teardown hook and
;; nothing callable.  Names here re-point to `ebp-org-' as their code
;; crosses; there are no aliases, by house rule.
;;
;; Ported from poc-v1's jetpacs-org.el engine ranges, NOT transliterated.
;; Twelve poc defects are fixed here rather than restored — the audit
;; map lives in the JA-4 plan; the load-bearing ones are named at their
;; fix sites.  (The query reader's obarray poisoning and the bare-symbol
;; error discipline moved to `ebp-org.el' with the code that fixes
;; them.)  Do not "restore" either of the following from the source:
;;
;;   - `org-id-find' in ref resolution: its miss path runs a FULL org-id
;;     rescan and falls back to the ambient current buffer — inside the
;;     socket filter.  Resolution never calls it.
;;   - the raw `save-buffer' idle timer: supersession and file locks both
;;     PROMPT, and a prompt in a timer wedges a daemon.  The save path
;;     refuses loudly instead.
;;
;; THE WIRE CONTRACT (D-4, ratified + amended 2026-07-27): refs are
;; Emacs-side plists and NEVER cross the wire; the wire carries opaque
;; per-owner tokens minted against a replace-set table (the
;; `results.visit' :index contract generalized).  Status mapping for
;; handlers (`ebp-org-refusal-disposition' computes it): token miss
;; -> `stale'; `ebp-org-unresolved' -> `stale';
;; `ebp-org-refused' -> `rejected'; `ebp-org-unavailable' ->
;; `jetpacs-retry-later' (1500 event-retry — the durable record
;; survives redelivery).  The glasspane alist->plist
;; migration deliberately did NOT ride this rung — glasspane cannot load
;; against the rewrite yet, and migrates once, at its own port rung.

;;; Code:

(require 'ebp-org)                      ; the engine itself
(require 'jetpacs-surfaces)             ; owner floor: teardown only now

(defgroup jetpacs-org nil
  "The Jetpacs org extraction and mutation engine."
  :group 'jetpacs)

;;;; The root allowlist

(defcustom jetpacs-org-roots nil
  "Directories `jetpacs-org-resolve-ref' may touch.
nil derives the set from `org-directory' and the directories of
`org-agenda-files'.  Matching is by true-name path components, never
by string prefix — /org-evil does not sit under /org."
  :type '(repeat directory))

(defun jetpacs-org-agenda-files ()
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

(defun jetpacs-org--roots ()
  "The effective allowlist, raw — `ebp-check-path' truenames it.
Explicit `jetpacs-org-roots' entries anchor to `org-directory'
\(Batch-3 P2: a relative entry previously resolved against the AMBIENT
`default-directory' — whatever buffer the socket filter had current);
nil derives the set from `org-directory' and the directories of the
LOCAL agenda files, already absolute after the same anchoring."
  (if jetpacs-org-roots
      (mapcar (lambda (d)
                (if (and (stringp d) (not (string-empty-p d)))
                    (expand-file-name d org-directory)
                  d))
              jetpacs-org-roots)
    (delete-dups
     (cons (expand-file-name org-directory)
           (mapcar #'file-name-directory (jetpacs-org-agenda-files))))))

(defun jetpacs-org--check-file (file)
  "FILE validated against `jetpacs-org-roots', as a truename, or signal.
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
      (ebp-check-path file (jetpacs-org--roots))
    (ebp-path-refused
     (pcase (cadr err)
       ('no-roots (signal 'ebp-org-unavailable (cdr err)))
       ('unreadable
        (if (file-exists-p file)
            (signal 'ebp-org-unavailable (cdr err))
          (signal 'ebp-org-unresolved (list 'file-missing))))
       (_ (signal 'ebp-org-refused (cdr err)))))))

(defun jetpacs-org-file-allowed-p (file)
  "FILE's truename when it is inside the org roots and readable, else nil.
The TOTAL form of `jetpacs-org--check-file'.  Every condition that
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
      (jetpacs-org--check-file file)
    ((ebp-org-refused ebp-org-unresolved ebp-org-unavailable)
     nil)))

;;;; Cache layer

(defvar jetpacs-org--cache (make-hash-table :test #'equal)
  "Memoised org extraction results.")

(defconst jetpacs-org-cache-max 64
  "Entries one key generation may hold before the table is dropped.
The key embeds wire-supplied query text, so without a ceiling N
distinct hostile queries retain N entries for the process lifetime
\(JA-4 audit P2).  Every entry is cheap to recompute and the eviction
is wholesale, so this is a plain bound rather than an LRU carrying its
own per-entry bookkeeping: overflow costs one re-run, never a wrong
answer.")

(defcustom jetpacs-org-stat-ttl 1.0
  "Seconds the agenda-file mtime stamp is trusted between stats.
The poc statted every agenda file on EVERY cache lookup, hits included
— N truename+stat syscalls per lookup.  Within this window the DISK
half of the stamp is reused; `jetpacs-org-cache-invalidate' clears it,
so a mutation is never masked by the memo.  The BUFFER half
\(`jetpacs-org--stamp-buffers') is never memoised — it costs no
syscalls, and memoising it would blind the cache to an unsaved edit
for exactly this window."
  :type 'number)

(defvar jetpacs-org--stamp-memo nil
  "(EXPIRY-FLOAT NAMES . DISK) — the memoised DISK half, or nil.")

(defun jetpacs-org--stamp-disk ()
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
    (if (and jetpacs-org--stamp-memo
             (< now (car jetpacs-org--stamp-memo)))
        (cdr jetpacs-org--stamp-memo)
      (let* ((names
              (mapcar (lambda (file) (cons file (file-truename file)))
                      ;; Remote entries are dropped BEFORE these stats: this
                      ;; runs on every cache-key computation, i.e. inside
                      ;; every query, which made it the hottest TRAMP dialler
                      ;; in the module (JA-4 audit P1-7).
                      (jetpacs-org-agenda-files)))
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
        (setq jetpacs-org--stamp-memo (cons (+ now jetpacs-org-stat-ttl) value))
        value))))

(defun jetpacs-org--stamp-buffers (names)
  "The buffer half of the freshness stamp: (TRUENAME . CHARS-TICK) list.
JA-4 audit P1-11: the stamp was derived entirely from `file-attributes'
while EVERY cached value is produced by `org-map-entries' /
`jetpacs-org-ref-at-point' reading the BUFFER.  An org buffer edited in
Emacs and not yet written — the normal state of a working buffer, and
precisely the state `jetpacs-org-with-mutation' deliberately leaves for
the debounce window — moved nothing at all, so a repeated query served
positions that no longer exist and (with the P1-9 scan) a tap mutated
the wrong heading.

`buffer-chars-modified-tick' is monotonic per buffer and free to read,
which is why this half is recomputed on every lookup rather than
memoised.  Both spellings in NAMES are probed: a buffer visits the name
it was opened with, which need not be the truename, and `get-file-buffer'
is a string comparison — `find-buffer-visiting' would stat every file
again inside the very window `jetpacs-org-stat-ttl' exists to avoid."
  (delq nil
        (mapcar (lambda (name)
                  (when-let* ((buf (or (get-file-buffer (car name))
                                       (get-file-buffer (cdr name)))))
                    (cons (cdr name) (buffer-chars-modified-tick buf))))
                names)))

(defun jetpacs-org--files-stamp ()
  "A full-resolution freshness stamp for the agenda file set.
\(DISK . BUFFERS): what the files say and what their live buffers say.
Neither half alone is the truth the cache serves — see the two
functions above."
  (let ((memo (jetpacs-org--stamp-disk)))
    (cons (cdr memo) (jetpacs-org--stamp-buffers (car memo)))))

(defun jetpacs-org--cache-key (namespace &rest parts)
  "Build a cache key from NAMESPACE and PARTS.
Scoped to today's date and the agenda files' stamp, so external edits,
membership changes, and date roll-over all bust the cache.  NAMESPACE
stays at `nth 2' — `jetpacs-org-cache-invalidate' reads it there."
  (cons (format-time-string "%Y-%m-%d")
        (cons (jetpacs-org--files-stamp)
              (cons namespace parts))))

(defvar jetpacs-org--cache-generation nil
  "The (DATE . STAMP) head every live entry in the cache is keyed under.")

(defun jetpacs-org--cache-admit (key value)
  "Store VALUE under KEY, evicting so the table stays bounded.  Returns VALUE.
Both evictions are wholesale (JA-4 audit P2 — the poc's table only ever
grew).  A key carries (DATE STAMP) at its head, so the moment either
moves every older entry is unreachable FOREVER: the buffer tick is
monotonic and the date rolls forward, so a superseded generation is
dead weight, not a cache.  Within the live generation
`jetpacs-org-cache-max' bounds the table, because the rest of the key
is wire-supplied query text."
  (let ((generation (cons (nth 0 key) (nth 1 key))))
    (unless (equal generation jetpacs-org--cache-generation)
      (clrhash jetpacs-org--cache)
      (setq jetpacs-org--cache-generation generation))
    (when (>= (hash-table-count jetpacs-org--cache) jetpacs-org-cache-max)
      (clrhash jetpacs-org--cache))
    (puthash key value jetpacs-org--cache)))

(defmacro jetpacs-org-with-cache (namespace key &rest body)
  "Memoise BODY's result in `jetpacs-org--cache' under NAMESPACE and KEY.
KEY must distinguish everything the BODY's VALUE depends on that the
stamp does not — including which function produced it (P1-12)."
  (declare (indent 2))
  (let ((k (gensym "key")) (hit (gensym "hit")))
    `(let* ((,k (jetpacs-org--cache-key ,namespace ,key))
            (,hit (gethash ,k jetpacs-org--cache 'jetpacs-org--miss)))
       (if (eq ,hit 'jetpacs-org--miss)
           (jetpacs-org--cache-admit ,k (progn ,@body))
         ,hit))))

(defun jetpacs-org-cache-invalidate (&optional namespace)
  "Drop memoised org extractions (and the stat memo).
With NAMESPACE, only entries under it — the live generation stands, so
every other namespace keeps its entries.  Keys are collected before
removal — never `remhash' inside the `maphash' walk."
  (setq jetpacs-org--stamp-memo nil)
  (if namespace
      (let (dead)
        (maphash (lambda (k _v)
                   (when (equal (nth 2 k) namespace) (push k dead)))
                 jetpacs-org--cache)
        (dolist (k dead) (remhash k jetpacs-org--cache)))
    (clrhash jetpacs-org--cache)
    (setq jetpacs-org--cache-generation nil)))

;;;; Heading references — Emacs-side plists, never on the wire

(defun jetpacs-org-ref-at-point ()
  "Ref plist for the org heading at point:
\(:id ID-or-nil :file TRUENAME :pos INT :headline STRING).
Emacs-internal; a ref NEVER crosses the wire (D-4) — mint a token with
`jetpacs-org-ref-tokens'.  :file is a truename so the resolve-time root
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

(defun jetpacs-org--find-in-file-by-id (id file)
  "Marker for ID in validated FILE, or nil.  Never `org-id-find':
its miss path runs `org-id-update-id-locations' — a full rescan of the
org-id file set — and falls back to the CURRENT buffer's file, which
inside the socket filter is whatever happened to be current."
  (ignore-errors (org-id-find-id-in-file id file 'marker)))

(defun jetpacs-org-resolve-ref (ref)
  "Resolve REF (a plist from `jetpacs-org-ref-at-point') to a marker.
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
                        (jetpacs-org--check-file file)))
             (marker
              (or
               ;; 1. The stable id, in the ref's own (validated) file.
               (and true (stringp id) (not (string-empty-p id))
                    (jetpacs-org--find-in-file-by-id id true))
               ;; 2. The id, wherever org-id last recorded it — with the
               ;;    mapped file put through the SAME policy guards.
               (and (stringp id) (not (string-empty-p id))
                    (hash-table-p org-id-locations)
                    (when-let* ((mapped (gethash id org-id-locations))
                                (mapped-true
                                 (condition-case nil
                                     (jetpacs-org--check-file mapped)
                                   (ebp-org-refused nil))))
                      (jetpacs-org--find-in-file-by-id id mapped-true)))
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

(defconst jetpacs-org-token-set-max 512
  "Refs per (owner,set); minting beyond signals (a build-time error).")

(defconst jetpacs-org-token-sets-max 32
  "Sets per owner; minting a new set beyond signals.")

(defvar jetpacs-org--tokens (make-hash-table :test #'equal)
  "TOKEN-STRING -> (:owner O :set S :ref REF-PLIST).")

(defvar jetpacs-org--token-sets (make-hash-table :test #'equal)
  "(OWNER . SET) -> list of live token strings, for the replace sweep.")

(defvar jetpacs-org--token-nonce
  (format "%08x" (random #x100000000))
  "Per-session opacity salt; re-minted by `jetpacs-org-reset'.")

(defvar jetpacs-org--token-counter 0)

(cl-defun jetpacs-org-ref-tokens (refs &key (set "default") owner)
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
    (error "jetpacs-org-ref-tokens: no owner (pass :owner)"))
  (when (> (length refs) jetpacs-org-token-set-max)
    (error "jetpacs-org-ref-tokens: %d refs exceeds the %d per-set cap"
           (length refs) jetpacs-org-token-set-max))
  (let ((key (cons owner set)))
    (unless (gethash key jetpacs-org--token-sets)
      (let ((sets 0))
        (maphash (lambda (k _v) (when (equal (car k) owner)
                                  (setq sets (1+ sets))))
                 jetpacs-org--token-sets)
        (when (>= sets jetpacs-org-token-sets-max)
          (error "jetpacs-org-ref-tokens: owner %s exceeds %d sets"
                 owner jetpacs-org-token-sets-max))))
    ;; Pass 1 — validate EVERY ref while both tables stay untouched.
    (dolist (ref refs)
      ;; SHAPE first (JA-4 audit P1-12): `(plist-get "Alpha" :file)'
      ;; returns nil rather than signalling, so a list of display
      ;; STRINGS — exactly what a mis-keyed query used to hand back —
      ;; sailed past the policy check below and became live tokens.
      ;; The offending value is not echoed (23.3): it may be user text
      ;; or a path.
      (unless (and (plistp ref) (plist-member ref :file))
        (error "jetpacs-org-ref-tokens: not a ref plist (%s)" (type-of ref)))
      (let ((file (plist-get ref :file)))
        (when (and (stringp file) (not (string-empty-p file)))
          (jetpacs-org--check-file file))))
    ;; Pass 2 — mint locally; still no table writes.
    (let ((entries
           (mapcar (lambda (ref)
                     (cons (format "o%s-%x" jetpacs-org--token-nonce
                                   (cl-incf jetpacs-org--token-counter))
                           ref))
                   refs)))
      ;; Pass 3 — the replace sweep + BOTH installs, signal-free.
      (dolist (old (gethash key jetpacs-org--token-sets))
        (remhash old jetpacs-org--tokens))
      (dolist (entry entries)
        (puthash (car entry)
                 (list :owner owner :set set :ref (cdr entry))
                 jetpacs-org--tokens))
      (puthash key (mapcar #'car entries) jetpacs-org--token-sets)
      (mapcar #'car entries))))

(cl-defun jetpacs-org-token-ref (token &key owner)
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
      (error "jetpacs-org-token-ref: no owner (pass :owner)"))
    (let ((entry (gethash token jetpacs-org--tokens)))
      (when (and entry (equal (plist-get entry :owner) owner))
        (plist-get entry :ref)))))

(defun jetpacs-org-teardown-owner (owner)
  "Sweep OWNER's token sets with its registration (live-reload hygiene).
PUBLIC, and named for what it does rather than for when it happens: any
scope owner may drop its own tokens by calling this, and the sweep is
the token table's business alone — it reads no floor state and answers
to the same opaque scope key the mint took.
WHO CALLS IT is the caller's business, not this function's.  today the
only caller is the `jetpacs-teardown-functions' registration below, in
this same file; that add-hook and its remove-hook in the unload
function are one pair and move together to the shim at G7, leaving the
sweep behind with the engine."
  (let (dead)
    (maphash (lambda (key _tokens)
               (when (equal (car key) owner) (push key dead)))
             jetpacs-org--token-sets)
    (dolist (key dead)
      (dolist (token (gethash key jetpacs-org--token-sets))
        (remhash token jetpacs-org--tokens))
      (remhash key jetpacs-org--token-sets))))

(add-hook 'jetpacs-teardown-functions #'jetpacs-org-teardown-owner)

;;;; Mutations

(defvar-local jetpacs-org--save-timer nil
  "This buffer's pending deferred save, or nil.  ONE per buffer: the
poc armed a fresh timer per mutation — ten taps, ten timers, nine
no-op wakeups all holding the buffer.")

(defun jetpacs-org--save-now (buf)
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
      (setq jetpacs-org--save-timer nil)
      (when (buffer-modified-p)
        (cond
         ((not (verify-visited-file-modtime buf))
          (message "jetpacs-org: NOT saving %s — file changed on disk \
(resolve in Emacs, then save)" (buffer-name buf)))
         ((let ((lock (file-locked-p buffer-file-name)))
            (and lock (not (eq lock t))))
          (message "jetpacs-org: NOT saving %s — locked by another \
process" (buffer-name buf)))
         (t (condition-case nil
                (ebp-org--with-clamped-io (save-buffer))
              (ebp-org-refused
               (message "jetpacs-org: NOT saving %s — needs interactive \
input" (buffer-name buf))))))))))

(defun jetpacs-org-defer-save ()
  "Schedule ONE idle save for the current buffer."
  (unless (timerp jetpacs-org--save-timer)
    (setq jetpacs-org--save-timer
          (run-with-idle-timer 0.5 nil #'jetpacs-org--save-now
                               (current-buffer)))))

(defmacro jetpacs-org-with-mutation (ref namespace &rest body)
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
     (let ((marker (jetpacs-org-resolve-ref ,ref)))
       (unwind-protect
           (with-current-buffer (marker-buffer marker)
             (org-with-wide-buffer
              (goto-char marker)
              (prog1 (progn ,@body)
                (jetpacs-org-cache-invalidate ,namespace)
                (jetpacs-org-defer-save))))
         (set-marker marker nil)))))

(defun jetpacs-org-set-property (ref namespace prop value)
  "Set PROP to VALUE on the heading at REF."
  (jetpacs-org-with-mutation ref namespace
    (org-entry-put (point) prop value)))

(defvar jetpacs-org-toggle-todo-cancelled-note nil
  "The `org-log-note-how' kind the last toggle CANCELLED, or nil.
`jetpacs-org-toggle-todo' clears it on entry and sets it when it must
cancel a pending free-text note (any kind outside time/state — those
need interactive input this extent cannot host).  JA-5's dialog layer
reads it to follow up with a `capture_fields' note dialog, closing the
loop the cancel would otherwise silently drop.")

(defun jetpacs-org-toggle-todo (ref namespace &optional state)
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
`jetpacs-org-toggle-todo-cancelled-note' so JA-5's `capture_fields'
note dialog can pick it up.  The note is only ONE of the interactive
hazards on this path: `jetpacs-org-with-mutation' runs the whole
toggle under `ebp-org--with-clamped-io', so the rest — the `++'
repeater catch-up question, supersession, changed-on-disk — surface
as `ebp-org-refused'."
  (setq jetpacs-org-toggle-todo-cancelled-note nil)
  (jetpacs-org-with-mutation ref namespace
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
        (setq jetpacs-org-toggle-todo-cancelled-note
              (and (boundp 'org-log-note-how) org-log-note-how))
        (message "jetpacs-org: log note skipped — %S needs interactive \
input (the JA-5 note dialog follows up)"
                 jetpacs-org-toggle-todo-cancelled-note)))))

(defun jetpacs-org-set-planning (ref namespace which date-str)
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
    (jetpacs-org-with-mutation ref namespace
      (if (or (null date-str) (string-empty-p date-str))
          (org-add-planning-info nil nil type)
        (org-add-planning-info type date-str)))))

;;;; High-level query

(defun jetpacs-org--query-files ()
  "The explicit query scope: local agenda files that EXIST, or signal.
Routes through `jetpacs-org-agenda-files' — the SAME P1-7 floor filter
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
  (or (cl-remove-if-not #'file-exists-p (jetpacs-org-agenda-files))
      (signal 'ebp-org-unavailable (list 'no-agenda-files))))

(defun jetpacs-org--run-query (tree action)
  "Run vetted query TREE over the agenda files, calling ACTION at matches.
The scope is the EXPLICIT existence-filtered file list, never the
`agenda' symbol — that re-reads configuration through the
`org-agenda-files' FUNCTION (remote dialling, P1-7) and marches every
raw entry through `org-check-agenda-file' (the missing-file prompt,
P1-5)."
  (let ((files (jetpacs-org--query-files))
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

(defun jetpacs-org-query (namespace key tree action)
  "Run query sexp TREE over the agenda files, calling ACTION at matches.
Results are cached under NAMESPACE and KEY.  KEY is MANDATORY and must
identify the ACTION, not merely the caller (JA-4 audit P1-12): the
cached value is `(mapcar ACTION matches)', and a closure has no stable
printed identity, so keying on (namespace, tree) alone handed the
SECOND caller of a tree the FIRST caller's payload.  That is a D-4
breach, not merely a cache bug — one screen asks a tree for display
titles and for refs, and whichever ran second got the other list: ref
plists (absolute paths) to a text consumer, and bare strings to
`jetpacs-org-ref-tokens', whose per-ref policy check then silently did
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
    (error "jetpacs-org-query: KEY must be a non-nil string or symbol"))
  (when tree
    (let ((printed (let ((print-length nil)
                         (print-level nil)
                         (print-circle t))
                     (format "%S" tree))))
      (jetpacs-org-with-cache namespace (cons key printed)
        (jetpacs-org--run-query tree action)))))

;;;; The file-save seam

(defun jetpacs-org--default-file-save (_buffer)
  "Invalidate the org memo and schedule a save for the current buffer.
The default `jetpacs-org-file-save-function'."
  (jetpacs-org-cache-invalidate)
  (jetpacs-org-defer-save))

(defvar jetpacs-org-file-save-function #'jetpacs-org--default-file-save
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

(defcustom jetpacs-org-outline-max-headings 400
  "Cap on heading records returned by one collection pass.
Bounds very large files; `jetpacs-org-outline-cap' applies it."
  :type 'integer)

(defcustom jetpacs-org-outline-show-deadline t
  "Include each heading's DEADLINE string in its outline record."
  :type 'boolean)

(defcustom jetpacs-org-outline-show-clocked nil
  "Include each heading's clocked-minutes total in its outline record.
Off by default: the totals only exist after an `org-clock-sum' pass,
which a consumer must run itself — this switch just carries the value."
  :type 'boolean)

(defun jetpacs-org--outline-record (pos next)
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
           (deadline (and jetpacs-org-outline-show-deadline
                          (ignore-errors (org-entry-get pos "DEADLINE"))))
           (clocked (and jetpacs-org-outline-show-clocked
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

(defun jetpacs-org-outline-collect (beg end include-first)
  "Collect heading records between BEG and END of the current org buffer.
INCLUDE-FIRST non-nil includes a heading sitting exactly at BEG (the
subtree case).  Uncapped — apply `jetpacs-org-outline-cap' at the edge
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
             do (push (jetpacs-org--outline-record pos next) records))
    (nreverse records)))

(defun jetpacs-org-outline-tree (records)
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

(defun jetpacs-org-outline-cap (records)
  "RECORDS truncated to `jetpacs-org-outline-max-headings'."
  (seq-take records jetpacs-org-outline-max-headings))

(defun jetpacs-org-file-toplevel-records (file)
  "Capped level-1 heading records for org FILE, tagged :file and :buffer.
FILE goes through the root allowlist first — signals
`ebp-org-refused' outside `jetpacs-org-roots', exactly like every
other engine entry point (the poc read any path handed to it).  The
extra :file/:buffer members let a consumer mint a heading ref or a tap
target from a record."
  (let ((file (jetpacs-org--check-file file)))
    (with-current-buffer (find-file-noselect file t)
      (unless (derived-mode-p 'org-mode) (org-mode))
      (org-with-wide-buffer
       (let* ((buf (buffer-name))
              (all (jetpacs-org-outline-collect (point-min) (point-max) nil))
              (tops (cl-remove-if-not
                     (lambda (r) (= (plist-get r :level) 1)) all)))
         (mapcar (lambda (r)
                   (setq r (plist-put (copy-sequence r) :file file))
                   (plist-put r :buffer buf))
                 (jetpacs-org-outline-cap tops)))))))

;;;; Reset (the test seam; wired into `jetpacs-test-reset-state')

(defun jetpacs-org-reset ()
  "Reset engine state: cache, stat memo, tokens (fresh nonce), timers."
  (clrhash jetpacs-org--cache)
  (setq jetpacs-org--cache-generation nil
        jetpacs-org--stamp-memo nil)
  (clrhash jetpacs-org--tokens)
  (clrhash jetpacs-org--token-sets)
  (setq jetpacs-org--token-nonce (format "%08x" (random #x100000000))
        jetpacs-org--token-counter 0)
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (timerp jetpacs-org--save-timer)
        (cancel-timer jetpacs-org--save-timer)
        (setq jetpacs-org--save-timer nil)))))

(defun jetpacs-org-unload-function ()
  "Unload hygiene."
  (remove-hook 'jetpacs-teardown-functions #'jetpacs-org-teardown-owner)
  (jetpacs-org-reset)
  nil)

(provide 'jetpacs-org)
;;; jetpacs-org.el ends here
