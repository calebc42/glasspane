# Plan: JA-4 audit fix Batches 1 + 3 in jetpacs-org.el

Target: `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2/emacs/jetpacs-org.el`
Tests: `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2/test/jetpacs-org-test.el`
Baseline: 47/47 ERT green (verified). No commits; working tree only.

Key facts verified against source before planning:
- P1-7 already landed: `jetpacs-org-agenda-files` (jetpacs-org.el:69) filters via floor
  `jetpacs-local-paths`; `--roots` and `--files-stamp` route through it. The "shared
  local-agenda-files helper" EXISTS — the query path just doesn't use it yet.
- `jetpacs-check-path` / `jetpacs-path-refused` live in jetpacs-surfaces.el:231-312.
  `jetpacs-with-no-prompts` (surfaces.el:542) is the real dispatch-extent regime —
  binds `inhibit-interaction` t + stubs the 6 escaping readers; D2 tests drive through it.
- Emacs 30.1 org: `org-check-agenda-file` (org.el:15846) messages the ABSOLUTE path and
  calls `read-char-exclusive` unconditionally on a missing file — the
  `org-agenda-skip-unavailable-files` variable is consulted ONLY inside the
  `org-agenda-files` function (org.el:15697), so the existence filter is the load-bearing
  half; the variable binding is genuine belt-and-braces only.
- `org-map-entries` with a LIST scope (org.el:12536): `(eval scope t)` fires only when
  `(symbolp (car scope))` — a list of path strings is safe. A nil scope means CURRENT
  BUFFER — so an empty file list must never be passed through (sandbox drift).
- `org-auto-repeat-maybe` (org.el:10205): the `++` catch-up prompt is
  `y-or-n-p "%d repeater intervals were not enough …"` at nshift == 10.
- `find-file-noselect` (files.el:2499): NOWARN short-circuits the whole changed-on-disk
  branch; otherwise `query-about-changed-file` non-nil ⇒ `yes-or-no-p`. Both halves of
  the P1-6 open clamp are real.
- `jetpacs-org-vulpea.el:96` uses `jetpacs-org-note-query-terms` as the interpreter-
  coverage check and its accessor DOES support `regexp-match` — so the wire allowlist
  must become a SEPARATE constant; `regexp` cannot simply be deleted from
  `jetpacs-org-note-query-terms` (that would break free-text queries on the vulpea arm).
- `org-special-properties` (org.el:12676): ALLTAGS BLOCKED CLOCKSUM CLOCKSUM_T CLOSED
  DEADLINE FILE ITEM PRIORITY SCHEDULED TAGS TIMESTAMP TIMESTAMP_IA TODO — every one has
  a dedicated grammar head or is path/derived data, so refusing all of them loses nothing.

---

## Batch 1 — the vetter (P1-2, P1-3, P1-4, arity hole, property hole, query echo)

One coherent rewrite of `jetpacs-org--vet-query` + `jetpacs-org-parse-query` (+ small
edits to `--query-tokens`, `--matches-p`, `--planning-day`).

### 1a. New constants
- `jetpacs-org--query-max-chars` defconst 200 (matches `jetpacs-files-grep-max-query-chars`,
  SPEC #138 spirit; sibling caps are private defconsts, follow that style).
- `jetpacs-org--wire-query-terms` defconst — `jetpacs-org-note-query-terms` minus `regexp`:
  `(and or not todo done tags priority heading property level scheduled deadline habit)`.
  Docstring: the SPEC 23.2 sexp-arm allowlist; `regexp` deliberately absent (P1-2 / #137 —
  `heading` regexp-quotes and covers the use case; the token arm mints its `regexp`
  clauses from canonical symbols without passing here).
- `jetpacs-org-note-query-terms` KEEPS `regexp`; docstring updated: it names the
  interpreter grammar (vulpea coverage check), no longer "doubles as the allowlist".

### 1b. `jetpacs-org--vet-query` rewrite — arity/type schema per head
`cl-labels` walker, node counter + depth exactly as now (bump on every visit incl.
leaves). Per-head validation after canonical re-home (head looked up by `symbol-name`
in `jetpacs-org--wire-query-terms`; unknown head ⇒ pinned `"Unsupported query term"` —
this is what now refuses a wire `(regexp …)`):

| head | schema |
|---|---|
| and, or | ≥1 args, each a clause |
| not | exactly 1 clause |
| todo, tags, heading | 0+ string leaves |
| done, habit | 0 args |
| priority | `(OP VAL)`: OP symbol named one of `< <= > >= =` (re-homed canonical), VAL string or integer; OR 0+ string leaves none of which is comparator-named |
| property | 1–2 args; NAME a string leaf; `(member (upcase NAME) org-special-properties)` ⇒ pinned `"Unsupported property name"`; optional VAL string leaf |
| level | 1–2 args, all integers |
| scheduled, deadline | even-length plist; keys named `:on`/`:from`/`:to` (re-homed); values: integer, symbol named `today` (re-homed), or string matching `\`[0-9]{4}-[0-9]{2}-[0-9]{2}` |

- String leaves (P1-3): `substring-no-properties` + length ≤ `jetpacs-org--query-max-chars`
  (over ⇒ "Query too large"). Bare non-keyword symbols in string position ⇒
  `(substring-no-properties (symbol-name s))` (fresh copy — symbol-name shares the
  symbol's own string). Keyword-named symbol in string position ⇒ pinned
  `"Unsupported query keyword"`. Anything else ⇒ pinned `"Unsupported query value"`.
- Arity/type violations ⇒ `(user-error "Malformed %s clause" head)` — head symbol at
  most, NEVER the query text (23.3).
- Quote unwrap tightened to exact `(quote X)` 2-element shape (rides along with the
  rewrite; the loose unwrap silently discarded trailing forms — P3, note in report).
- Docstring rewritten so its output-invariant claim is now TRUE (fresh propertyless
  bounded strings, canonical interned symbols, integers, schema-checked arity).

### 1c. `jetpacs-org-parse-query` — caps govern both arms (P1-4)
- FIRST, after trim: `(> (length q) jetpacs-org--query-max-chars)` ⇒ pinned
  `"Query too long"` (before the reader AND before tokenizing).
- Token arm: empty tokens dropped (in `--query-tokens`: don't push an empty match — only
  the `""` quoted-phrase can produce one; `\S-+` can't); clause count checked against
  `jetpacs-org--query-max-nodes` ⇒ "Query too large" (unreachable under the 200-char cap,
  pins the invariant if the bound ever moves). All tokens dropped ⇒ nil (empty query),
  never `(regexp "")` and never a bare `(and)`.

### 1d. Interpreter echo removal
- `--matches-p` fallthrough: `(error "jetpacs-org--matches-p: unsupported clause head %s" …)`
  printing the head symbol only (or its type-of when not a symbol) — `error` not
  `user-error` (it is now an internal-invariant breach: only a hand-built tree reaches it).
- `--planning-day` fallthrough and the priority-comparator fallthrough: drop the `%S`/`%s`
  echo (both unreachable for vetted input).

### Batch-1 regression tests (each FAILS pre-fix)
1. `jetpacs-org-query-vet-refuses-wire-regexp` (pins P1-2): `(regexp "x")` and
   `(regexp "\\(a*\\)*b")` via `jetpacs-org-parse-query` ⇒ user-error; positive control:
   free-text `"foo"` still parses to `(regexp "foo")`.
2. `jetpacs-org-query-vet-strips-text-properties` (pins P1-3): parse
   `(todo #("x" 0 1 (ja4-smug ja4-val)))`; deep-walk the returned tree asserting every
   symbol satisfies `(eq s (intern-soft (symbol-name s)))` and every string has zero text
   properties over its whole length (walk helper local to the test file; drives the
   public entry point). Existing obarray test kept as-is.
3. `jetpacs-org-parse-query-caps-govern-both-arms` (pins P1-4): >200-char token query
   refuses "Query too long"; >200-char sexp query refuses too; `"\"\""` ⇒ nil;
   `"\"\" x"` ⇒ `(regexp "x")`; plus REAL depth coverage: 12-nested `(not (not …))`
   ⇒ "Query too deep" (closes the P3 vacuous-depth gap over my own rewrite).
4. `jetpacs-org-query-vet-checks-arity-and-types` (pins the arity hole + echo):
   `(done "x")`, `(not)`, `(habit 1)`, `(level "3")`, `(and "x")`,
   `(level 3 "SNEAKPAYLOAD")` all refuse at PARSE time; assert the pinned wording
   (e.g. `(equal (cadr err) "Malformed level clause")`) and that the error string does
   NOT contain "SNEAKPAYLOAD".
5. `jetpacs-org-query-vet-refuses-special-properties` (pins the property hole):
   `(property "FILE")`, `(property "file")`, `(property "TODO" "x")` refuse with
   "Unsupported property name"; positive: `(property "MOOD" "good")` and
   `(property "MOOD")` still parse.

Existing-test compatibility, checked arm by arm: `(todo)` 0-arg OK; `(scheduled :on
"2026-08-01")` ISO OK; `(scheduled :evil 1)` now "Malformed scheduled clause" (test only
asserts user-error type); `'(todo TODO)` exact-quote OK; `(priority > "B")` canonical OK;
`#1=(and . #1#)` free-text routing unchanged; hostile family all still refuse.

---

## Batch 3 — D2 + file guards (P1-5, P1-6, relative-roots P2; reuse P1-7's helper)

### 3a. New macro `jetpacs-org--with-clamped-io` (new subsection after the root
allowlist, before first use in resolve-ref)
```elisp
(let ((query-about-changed-file nil)
      (large-file-warning-threshold nil)
      (enable-local-variables :safe))
  (cl-letf (((symbol-function 'ask-user-about-supersession-threat)
             (lambda (_) (signal 'jetpacs-org-refused (list 'file-drifted))))
            ((symbol-function 'y-or-n-p)      → (signal … (list 'needs-interactive))
            ((symbol-function 'yes-or-no-p)   → same
            ((symbol-function 'read-char-exclusive) → same)   ; org-check-agenda-file race
    …body…))
```
Docstring: D2 — drift becomes a status, not a question; one-symbol data lists per the
floor's 23.3 convention.

### 3b. P1-6 — clamp the resolve/mutation spine
- Both `find-file-noselect` sites in `jetpacs-org-resolve-ref` (steps 3 and 4) get
  NOWARN t; the whole marker-resolution `let*` body wraps in `--with-clamped-io`.
- `jetpacs-org-with-mutation` expansion wraps everything (resolve + body + invalidate +
  defer) in `--with-clamped-io` — this is what converts the supersession loop and the
  `org-auto-repeat-maybe` catch-up `y-or-n-p` into `jetpacs-org-refused`.
- `jetpacs-org--save-now`: the final `(save-buffer)` arm becomes
  `(condition-case nil (jetpacs-org--with-clamped-io (save-buffer))
     (jetpacs-org-refused (message "jetpacs-org: NOT saving %s — needs interactive input" …)))`
  — covers basic-save-buffer's write-protected and require-final-newline prompts in the
  timer context (message-refusal, never a signal out of a timer).
- Docstring corrections: `--save-now` (write-protected/final-newline now named, clamped)
  and `jetpacs-org-toggle-todo` (the log note is no longer framed as the only interactive
  hazard — one sentence pointing at the clamp).

### 3c. P1-5 — existence-filtered explicit query scope
- New `jetpacs-org--query-files`:
  `(or (cl-remove-if-not #'file-exists-p (jetpacs-org-agenda-files))
       (signal 'jetpacs-org-refused (list 'no-agenda-files)))`
  — routes the query through the SAME P1-7 helper (verified: roots+stamp already use it);
  the empty set signals a DISTINCT greppable data symbol (`no-agenda-files`, vs the
  floor's `no-roots`) rather than silently scanning… comment in code: nil scope would
  mean "current buffer" (sandbox drift), and a comment referencing P1-10 (becomes
  retryable `jetpacs-org-unavailable` in Batch 4).
- `jetpacs-org--run-query`: scope = `(jetpacs-org--query-files)` instead of `'agenda`;
  let-bind `org-agenda-skip-unavailable-files` t (belt-and-braces, with an honest comment
  that in 30.1 only the `org-agenda-files` function consults it); wrap the
  `org-map-entries` call in `--with-clamped-io` (covers changed-on-disk prompts when org
  opens agenda files, and the filter↔prepare race via the read-char-exclusive rebind).
- Known deviation to note in report: directory entries in `org-agenda-files` are NOT
  expanded to member files (the function-call path did that); the stamp already treats
  raw entries as files, so this matches the module's existing semantics.

### 3d. P2 — relative entries anchor to org-directory (same functions)
- `jetpacs-org-agenda-files`: expand each entry `(expand-file-name f org-directory)`
  BEFORE `jetpacs-local-paths` (expand is pure string work; a remote name minted by a
  remote org-directory still gets filtered afterwards — order is load-bearing, comment it).
  Matches `org-agenda-files`'s own `(expand-file-name f org-directory)` semantics.
- `jetpacs-org--roots`: explicit `jetpacs-org-roots` entries mapped through
  `(expand-file-name d org-directory)`; derived arm gets `(expand-file-name org-directory)`
  + the (now already absolute) agenda-file directories.

### Batch-3 regression tests (each FAILS pre-fix)
6. `jetpacs-org-query-skips-a-vanished-agenda-file` (pins P1-5): agenda = (f, missing);
   drive `jetpacs-org-query` through `jetpacs-with-no-prompts` — pre-fix
   `org-check-agenda-file`'s `read-char-exclusive` signals `inhibited-interaction` (test
   fails); post-fix titles come back (status asserted, not just no-crash). Second arm:
   agenda = (missing) only ⇒ `should-error` `:type 'jetpacs-org-refused` with data
   `no-agenda-files`.
7. `jetpacs-org-resolve-opens-quietly-when-the-file-drifted` (pins P1-6 open sites):
   visit f, drift disk (`set-file-times` +2s after rewriting content), resolve inside
   `jetpacs-with-no-prompts` ⇒ markerp. Pre-fix: files.el `yes-or-no-p` ⇒
   `inhibited-interaction` ⇒ fail.
8. `jetpacs-org-mutation-answers-drift-as-a-status` (pins P1-6 supersession): visit f,
   drift disk, `jetpacs-org-set-property` inside `jetpacs-with-no-prompts` ⇒
   `should-error :type 'jetpacs-org-refused` (pre-fix: `inhibited-interaction`, wrong
   condition ⇒ fail).
9. `jetpacs-org-toggle-todo-refuses-the-catchup-repeater-prompt` (pins P1-6 repeater):
   fixture `* TODO H` + `SCHEDULED: <30-days-ago ++1d>` (computed via
   `format-time-string` so it is always >10 intervals behind); toggle to DONE inside
   `jetpacs-with-no-prompts` ⇒ `jetpacs-org-refused` (pre-fix: `inhibited-interaction`).
10. `jetpacs-org-save-path-never-prompts` (pins P1-6 save): mutate via public
    `jetpacs-org-set-property` (arms the timer), THEN chmod f 0444, fire the armed timer
    by hand via `timer--function`/`timer--args` inside `jetpacs-with-no-prompts`
    (batch never runs idle timers — per conventions); assert NO signal escapes, buffer
    still modified, disk untouched; restore modes in unwind. Pre-fix:
    basic-save-buffer's write-protected `yes-or-no-p` ⇒ `inhibited-interaction` escapes
    the timer body ⇒ fail.
11. `jetpacs-org-relative-root-anchors-to-org-directory` (pins the P2): org-directory =
    fixture dir, `jetpacs-org-roots '(".")`, `default-directory` bound to a DIFFERENT
    temp dir ⇒ `jetpacs-org--check-file f` succeeds (pre-fix: "." resolves against the
    decoy ⇒ refused ⇒ fail); inverse direction asserted too (org-directory = decoy ⇒
    refused), plus `jetpacs-org-agenda-files` expands a relative entry against
    org-directory.

---

## Refusal-wording catalogue (one pinned wording per layer)
- reader: "Malformed query" / "Malformed query (trailing content)" (unchanged)
- vetter shape: "Malformed query clause" (unchanged)
- vetter unknown head: "Unsupported query term" (unchanged; now also wire `regexp`)
- vetter arity/type: **"Malformed %s clause"** (new; head symbol only)
- vetter special property: **"Unsupported property name"** (new)
- vetter leaf: "Unsupported query value" / "Unsupported query keyword" (unchanged)
- caps: "Query too deep" / "Query too large" / **"Query too long"** (new, parse-query)
- clamp: `jetpacs-org-refused` data ∈ {file-drifted, needs-interactive, no-agenda-files}

## Gate
```
cd /home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2
emacs -Q --batch -L emacs -l test/jetpacs-org-test.el -f ert-run-tests-batch-and-exit   # 47 → ~58, all green
emacs -Q --batch -L emacs --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile emacs/jetpacs-org.el && rm emacs/jetpacs-org.elc
```
Also re-run the vulpea + org-render/dialogs/habits/outline test files (they consume
resolve-ref/with-mutation/the grammar) to prove the clamp broke no consumer.
Delineation: no new requires — the clamp uses cl-lib + built-ins only; jetpacs-org still
depends only on org/org-id/org-capture/org-table/jetpacs-surfaces (no ebp layer).

## Deliberate deviations from the audit text (to state in the report)
1. `regexp` is removed from the WIRE allowlist via a new separate constant, not deleted
   from `jetpacs-org-note-query-terms` — the vulpea arm's coverage check and the token
   arm both legitimately need the interpreter head.
2. `org-agenda-skip-unavailable-files` t is bound but documented as non-load-bearing in
   30.1 (only the `org-agenda-files` function consults it); the existence filter + the
   read-char-exclusive clamp rebind are what actually close P1-5.
3. Strict 2-element `(quote X)` unwrap and real depth-cap test coverage ride along
   (both P3s living inside the functions being rewritten).
4. Directory entries in `org-agenda-files` stay unexpanded on the query path (matches
   the module's existing stamp semantics).
