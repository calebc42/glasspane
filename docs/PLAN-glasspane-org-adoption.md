# Plan: Adopt `jetpacs-org` core primitives in Glasspane

Execute the Glasspane half of `jetpacs/docs/PLAN-org-extraction.md` §1: rip the
duplicated org logic out of `glasspane-org.el` and stand the app on the
foundation's new `jetpacs-org` primitive layer. This is a **full refactor across
all 11 files** (no compatibility wrappers), and it **keeps Glasspane's vulpea
query path** (vulpea is Glasspane's app-specific indexed-query opinion, correctly
*not* in the unopinionated core).

> Both of those choices (keep vulpea; full 11-file refactor) were decided by the
> user. Do not deviate without asking.

---

## 0. Current state / prerequisites (already done — just verify)

- **jetpacs main = `f4cb47a`** on origin (`git@github.com:calebc42/jetpacs.git`).
  It ships `jetpacs-org.el` — the unopinionated org primitive layer. Its public
  API is stable (see §2). jetpacs suite is green (100/100).
- **Glasspane's `jetpacs/` submodule was bumped to `f4cb47a`** in the working
  tree (it was pinned at `d079b7a`, which lacked `jetpacs-config`/`jetpacs-org`
  and could not even load Glasspane's own suite). Verify:
  ```
  git -C ~/pkb/projects/Glasspane/jetpacs log --oneline -1     # -> f4cb47a
  ls ~/pkb/projects/Glasspane/jetpacs/emacs/core/jetpacs-org.el
  ```
  The bump is **uncommitted** in the superproject — record it (`git add jetpacs`)
  as part of the final commit. `f4cb47a` is on origin, so the pointer is shareable.
  - The submodule fetch over SSH failed inside WSL (no GitHub creds there); it was
    fetched locally from the Windows clone: `git -C jetpacs fetch
    /mnt/c/Users/caleb/AndroidStudioProjects/jetpacs main && git checkout f4cb47a`.
- **Baseline: 78/78 green** against the bumped submodule.

## 1. Test gate (how to run — this is the loop)

The Glasspane suite must run under **WSL Debian** (its default WSL distro is
`Debian-Sandbox`; the real one is `Debian`, which has Emacs 30.1 + vulpea/org-ql):

```
wsl -d Debian -- bash -lc 'cd ~/pkb/projects/Glasspane && bash test/run-tests.sh'
```

`test/run-tests.sh` loads the app from `emacs/apps/glasspane`, core from
`jetpacs/emacs/core`, and runs all `glasspane-*-test.el`. **Baseline 78/78 must
stay green after every phase.** Windows Emacs cannot run this suite (no
vulpea/org-ql/magit/ghostel).

## 2. Target API — `jetpacs-org` (foundation, already landed)

`emacs/core/jetpacs-org.el` provides (add `(require 'jetpacs-org)` where used):

| function | signature | notes |
|---|---|---|
| `jetpacs-org-with-cache` | `(namespace key &rest body)` macro | **takes a namespace** |
| `jetpacs-org-cache-invalidate` | `(&optional namespace)` | pass `'glasspane` to scope |
| `jetpacs-org-heading-ref` | `()` | byte-identical to glasspane's |
| `jetpacs-org-resolve-ref` | `(ref)` | byte-identical |
| `jetpacs-org-parse-query` | `(query)` | byte-identical |
| `jetpacs-org-entry-matches-p` | `(tree)` | the buffer-point matcher |
| `jetpacs-org-query` | `(namespace tree action)` | **caches internally**; dispatches org-ql → built-in |
| `jetpacs-org-set-property` | `(ref namespace prop value)` | defers save + busts cache |
| `jetpacs-org-toggle-todo` | `(ref namespace &optional state)` | " |
| `jetpacs-org-set-planning` | `(ref namespace which date-str)` | `which` = "SCHEDULED"/"DEADLINE"; empty `date-str` removes |
| `jetpacs-org-entry-typed-value` | `(prop type)` | text/checkbox/date/enum/number/list |
| `jetpacs-org-defer-save` / `jetpacs-org-with-mutation` | | used internally by the mutators |

## 3. Symbol mapping (drives Parts A/B)

| Glasspane (retire) | jetpacs-org (adopt) | note |
|---|---|---|
| `glasspane-org-cache-invalidate` | `(jetpacs-org-cache-invalidate 'glasspane)` | **add the namespace arg** |
| `glasspane-org--heading-ref` | `jetpacs-org-heading-ref` | |
| `glasspane-org--resolve-ref` | `jetpacs-org-resolve-ref` | |
| `glasspane-org--parse-query` | `jetpacs-org-parse-query` | |
| `glasspane-org--query-match-p` | `jetpacs-org-entry-matches-p` | |
| `glasspane-org--with-cache` | `jetpacs-org-with-cache 'glasspane` | **add the namespace arg** |
| `glasspane-org--cache-key` | *(removed)* | fold its `parts` into the `with-cache` KEY arg |

**Blast radius (grep counts):** `glasspane-org.el` 36, `glasspane-detail.el` 12,
`glasspane-ui.el` 8, `glasspane-srs.el` 7, `glasspane-views.el` 5,
`glasspane-demo/journal/notes/table.el` 2 each, `glasspane-agenda/capture.el` 1
each — plus the test suite. Get exact live sites with:

```
cd ~/pkb/projects/Glasspane && grep -rnE \
 "glasspane-org-cache-invalidate|glasspane-org--heading-ref|glasspane-org--resolve-ref|glasspane-org--parse-query|glasspane-org--query-match-p|glasspane-org--with-cache|glasspane-org--cache-key" \
 emacs/apps/glasspane test
```

## 4. Recommended execution order (stay green throughout)

Deleting the duplicated defuns breaks every call site at once, so do it in phases:

### Phase A — repoint call sites (no deletions yet)
- Add `(require 'jetpacs-org)` to `glasspane-org.el`.
- Replace every retired symbol (per §3) with its `jetpacs-org` equivalent
  **everywhere** — the 10 other files, the test files, and the internal uses
  inside `glasspane-org.el`. The old `glasspane-org--*` defuns become dead code
  but still exist, so behavior is identical (the jetpacs-org versions are
  byte-for-byte the same logic).
- **Run the suite → expect 78/78.** This isolates "the rename is correct" from
  "the delegation is correct."

### Phase B — delete the now-dead duplicates + delegate in `glasspane-org.el`
Delete (now provided by `jetpacs-org`):
`glasspane-org--cache`, `--files-mtime`, `--cache-key`, `--with-cache`,
`glasspane-org-cache-invalidate`, `--heading-ref`, `--resolve-ref`,
`--ql-literals`, `--normalize-ql`, `--normalize-ql-arg`, `--query-tokens`,
`--parse-query`, `--query-match-p`, `--planning-match-p`, `--search-fallback`.

**KEEP (Glasspane-specific — do NOT delete):**
- vulpea: `--vulpea-note-to-item`, `--vulpea-query-match-p`, `--vulpea-query`
- `glasspane-org--planning-day` — **still referenced by `--vulpea-query-match-p`**
  (jetpacs-org's copy is private). Leave it in place.
- all extractions/capture/clock/reminder/timestamp helpers:
  `--agenda-items(-1)`, `--todo-items(-1)`, `--heading-item-at`,
  `--file-heading-items`, `--all-tags`, `--file-list`, `--heading-at`,
  `--parse-template-prompts`, `--capture-templates`, `--fill-template`,
  `--do-capture`, `--clock-status`, `--recent-clocks`, `--upcoming-reminders`,
  `--item-hm`, and the `before-save`/`org-insert-heading`/property/todo hooks.

Refactor the survivors:
- **`glasspane-org--query`** — keep the vulpea branch, delegate the rest:
  ```elisp
  (defun glasspane-org--query (tree)
    (when tree
      (if (and (featurep 'vulpea) (fboundp 'vulpea-db-query))
          (jetpacs-org-with-cache 'glasspane (list 'query (format "%S" tree))
            (glasspane-org--vulpea-query tree))
        (jetpacs-org-query 'glasspane tree #'glasspane-org--heading-item-at))))
  ```
  ⚠️ `jetpacs-org-query` **already caches** — do NOT wrap the non-vulpea branch in
  another `with-cache` (that's why only the vulpea branch caches explicitly).
- **`--agenda-items` / `--todo-items` / `--all-tags`** — swap
  `(glasspane-org--with-cache (glasspane-org--cache-key 'agenda span start) BODY)`
  → `(jetpacs-org-with-cache 'glasspane (list 'agenda span start) BODY)`. The
  namespace replaces the need for a per-reader cache-key prefix.
- **`--filter-items`** — `jetpacs-org-parse-query` + `jetpacs-org-entry-matches-p`.
- **`--search`** — `(glasspane-org--query (jetpacs-org-parse-query query))`.
- internal `--heading-ref` calls (in `--agenda-items-1`, `--todo-items-1`,
  `--heading-item-at`, `--file-heading-items`, `--recent-clocks`) →
  `jetpacs-org-heading-ref`.

**Run the suite → expect 78/78.**

### Phase C — adopt the mutation primitives (detail + capture)
Read `glasspane-detail.el` and `glasspane-capture.el`; find sites that
`resolve-ref` then mutate by hand (`org-entry-put`/`org-set-property`,
`org-todo`, `org-schedule`/`org-deadline`/`org-add-planning-info`). Replace with:
- `(jetpacs-org-set-property ref 'glasspane prop value)`
- `(jetpacs-org-toggle-todo ref 'glasspane state)`
- `(jetpacs-org-set-planning ref 'glasspane "SCHEDULED"|"DEADLINE" date-or-"")`

These resolve the ref, mutate at its heading, **invalidate the `'glasspane`
cache, and defer the save** — so the call sites can drop their manual
`glasspane-org-cache-invalidate` + save bookkeeping around those mutations.

**Run the suite → expect 78/78.**

## 5. Risks / gotchas (read before starting)

1. **`--inhibit-save-refresh` vs. jetpacs-org's async save (the plan's open
   question).** jetpacs-org batches saves via `run-with-idle-timer` (0.5s). Glasspane
   suppresses its `after-save-hook` dashboard refresh with
   `glasspane-org--inhibit-save-refresh` bound around its *own* synchronous saves.
   The deferred save fires *later*, outside that dynamic binding — so the
   suppression may no longer cover it, and capture/sync flows that expect the file
   on disk *immediately* (share-sheet capture finalize, queue replay) may race.
   **Audit this explicitly** when adopting the mutators in Phase C; if it bites,
   either keep synchronous saves at those call sites or add an explicit
   `(save-buffer)` after the mutator. Do not assume the idle-timer model is a
   drop-in.
2. **Cache key shape.** jetpacs-org's key is `(date mtime namespace . KEY)`; pass
   the old discriminator (`'agenda`/`'todos`/`'query`/`'all-tags` + args) as the
   single `KEY` arg (a list). Same date+mtime busting semantics as before.
3. **Don't delete the vulpea matcher.** `--query-match-p` (buffer) is deleted;
   `--vulpea-query-match-p` (note structs) is kept — they look similar.
4. **`org-entry-get` special properties are case-insensitive** (TAGS/TODO/
   SCHEDULED/…); a drawer property named after one is shadowed. (Bit the
   jetpacs-org tests.)
5. **Tests reference the retired parser.** The `jetpacs-search-*` and
   cache-memoise tests exercise `glasspane-org--parse-query`/`--query-match-p`/
   `glasspane-org-cache-invalidate`; repoint them in Phase A (or they'll fail to
   load once the defuns are deleted).

## 6. Commit

One Glasspane commit containing: the `glasspane-org.el` refactor, the 10 call-site
files, the test updates, **and the submodule pointer bump** (`git add jetpacs` →
records `f4cb47a`). Suite green at 78/78 (or more). Pushing is the user's call.

Out of scope: `jetpacs-crud.el` / the composer (`jetpacs/docs/PLAN-org-extraction.md`
§2) — the user said do not touch it yet, and it isn't in this repo.
