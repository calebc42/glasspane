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

(provide 'ebp-org)
;;; ebp-org.el ends here
