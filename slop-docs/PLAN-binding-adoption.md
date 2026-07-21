# Plan: Stage 3 — Glasspane binding-layer adoption

**STATUS (2026-07-13): EXECUTED, in re-scoped form.** What landed on `main`
(commits `07cd2d4`…`e45c160`): the `glasspane.org` defsource with a
canonicalizer (S3.1), the four internal-poke drops onto the promoted 1.5.0
seams (S3.3), the vulpea-backed `glasspane.notes` source, the annotated
action catalog + `glasspane-pack.el` + dependency-aware `glasspane-pack.json`
(S3.7), and agenda capability fallbacks via `jetpacs-node-or`. The planned
`:spec` migrations of the rich card surfaces (S3.2/S3.4/S3.5/S3.6) were
**dropped by design** — see
[DECISION-no-binding-template-dsl.md](../jetpacs/docs/DECISION-no-binding-template-dsl.md):
rich rendering stays in elisp `:builder`s; `:spec` is the composer-facing
grammar, not a Tier-1 replication target. Task 21 and the submodule bump
landed too (`edf5eb7`, `edeba78`; the pin has since moved to api 1.11.0).
**org-adoption remains pending** —
[PLAN-glasspane-org-adoption.md](PLAN-glasspane-org-adoption.md) is the
executable plan. Everything below is the original handoff, kept as the
design record; its "current state" snapshot is historical.

The master plan (in the jetpacs repo) is `jetpacs/docs/PLAN-binding-layer.md`
(Stage 3 section). The binding **grammar** reference is `jetpacs/docs/BINDING.md`
(inside the submodule once bumped). Read both before starting.

---

## Current state of THIS repo (HISTORICAL — the snapshot this plan started from)

The working tree is **not clean** and org-adoption has **not** run yet:

- **jetpacs submodule is at `f4cb47a`** (old `main`, before Stages 0–2). It has
  `jetpacs-org` and `jetpacs-config.el`, but **not** `jetpacs-source.el`,
  `jetpacs-spec.el`, the promoted seams, or api 1.5.0. **Stage 3 needs the
  submodule bumped to the new `main`.**
- **Uncommitted, mixed:** `glasspane-config.el` + `test/glasspane-config-test.el`
  (Phase G **Task 21** — config rebase onto `jetpacs-app-config-*`, source done),
  a modified `glasspane-agenda.el`, the `jetpacs` submodule pointer, and several
  docs (`README.md`, `docs/ROADMAP.md`, …). Untracked: `docs/PLAN-glasspane-org-adoption.md`,
  `emacs/apps/glasspane-ghostel.el`.
- **org-adoption is PENDING:** `glasspane-org--parse-query` still exists
  (`glasspane-org.el:366`) and `glasspane-org--query` still calls it (`:583`); no
  `jetpacs-org-query`/`jetpacs-org-parse-query` delegation yet.
- **`glasspane-ui.el` was modularized** (`ad7ab32` "modularize glasspane-ui.el
  into semantic domain files"). **Every line number from earlier surveys is
  stale — re-grep for the pokes and query calls before editing.**

**First action in the new chat: `git status`, `git log --oneline -6`,
`git submodule status`, and re-grep the symbols below. Reconcile the uncommitted
work (commit Task 21 and the agenda change, or stash) so you start from a known,
green baseline.**

---

## Prerequisites (in order)

1. **jetpacs `main` is pushed** (the owner does this). Stage 3 depends on the new
   core being fetchable by the submodule.
2. **Baseline the tree:** decide what to do with the uncommitted Task 21 / agenda
   / docs work. Task 21 (`glasspane-config.el`) is *file-disjoint* from Stage 3's
   view files, so it can land as its own commit first. Get to a green
   `test/run-tests.sh`.
3. **Bump the jetpacs submodule to the new `main`** (api 1.5.0), then regenerate
   the bundle and run the suite:
   ```
   cd jetpacs && git fetch && git checkout origin/main && cd ..
   emacs --batch -l emacs/build-bundle.el          # regen root glasspane.el
   wsl … bash test/run-tests.sh                     # baseline: all pass (78 + …)
   git add jetpacs glasspane.el && git commit       # "chore: bump jetpacs to 1.5.0 (binding layer)"
   ```
   This one bump unblocks org-adoption, Task 21, *and* Stage 3 (the new main is a
   superset).

**org-adoption relationship.** `PLAN-glasspane-org-adoption.md` (untracked here)
is still unexecuted. Stage 3's source binds to `glasspane-org--query` **by name**,
which survives org-adoption unchanged, so Stage 3 does **not** hard-depend on it.
But both edit the same view files, so **one plan owns a file at a time.** Doing
Stage 3 first actually *helps* org-adoption: Stage 3 centralizes the query call
into a single `defsource` thunk, leaving org-adoption fewer call sites to repoint.
Recommended: **land Stage 3, then org-adoption**, unless the owner wants
org-adoption first. Flag the choice; do not run them concurrently.

---

## What the new core gives you (from Stages 1–2, api 1.5.0)

Read `jetpacs/docs/BINDING.md` for the full grammar. Public surface you'll use:

- **`jetpacs-defsource`** — a named data source: `:params` / `:fields` metadata
  (domain-neutral types `text number boolean date string-list enum ref`) + a
  server-side `:query` thunk + optional `:cache-key`. Owned; `jetpacs-source-query`,
  `-fields`, `-catalog`, `-invalidate`.
- **`:spec` on `jetpacs-shell-define-view`** — a declarative view (exactly one of
  `:builder`/`:spec`): `:source :params :layout :template :header :group-by
  :empty-state :chrome`. Template is **raw wire-node data** with placeholders
  `((bind . "field") (as . "transform"))`; layouts `list` / `board` / `calendar`.
- **`jetpacs-lint-view-spec`** — validates a spec against a source's fields
  (call it in tests).
- **`jetpacs-form*`** — `jetpacs-form` / `-field-id` / `-value` / `-seed` /
  `-reset` / `-dispose`: replaces the hand-rolled `%d`-suffixed-id gen-counter.
- **`jetpacs-defaction … :args :doc`** + **`jetpacs-action-catalog`** — action
  metadata for the pack manifest.
- **`jetpacs-node-or`** — the capability-gated fallback macro (replaces the
  hand-coded `month_grid`/`tabs` fallback pairs in `glasspane-agenda.el`).
- **Promoted seams (drop the pokes):** `jetpacs-shell-set-current-tab`,
  `jetpacs-files-open` / `jetpacs-files-current-file`, `jetpacs-month-abbrev`,
  `jetpacs-in-action-p`, `jetpacs-ui-state-list`.

---

## The load-bearing design nuance: sources must NORMALIZE

The `:spec` transforms are **domain-neutral** — `date`/`date-label` expect an ISO
`YYYY-MM-DD` string, `tags-list` expects a list/vector of strings. Glasspane's
current item alists carry **raw org timestamps** for `scheduled`/`deadline` and a
**vector** for `tags`. So the Glasspane `defsource` must **map each result item to
canonical field types before returning it** — this is the "a source normalizes
engine data before core sees it" contract:

```elisp
(defun glasspane-source--canonicalize (item)
  (list (cons 'headline  (alist-get 'headline item))
        (cons 'todo      (or (alist-get 'todo item) ""))       ; string
        (cons 'scheduled (glasspane-ui--ts-date (alist-get 'scheduled item)))  ; -> ISO or nil
        (cons 'deadline  (glasspane-ui--ts-date (alist-get 'deadline item)))
        (cons 'tags      (append (alist-get 'tags item) nil))  ; vector -> list
        (cons 'priority  (alist-get 'priority item))
        (cons 'ref       (alist-get 'ref item))))              ; opaque locator, passed intact
```

Declare `:fields` to match (`scheduled`/`deadline` → `"date"`, `tags` →
`"string-list"`, `ref` → `"ref"`, `todo` → `"text"` or `"enum"`). The template's
placeholders then bind these canonical fields.

---

## Stage 3 tasks

Every task: re-grep for current locations first (post-modularization), make the
change, regenerate `glasspane.el`, run `test/run-tests.sh` to all-green, **one
commit**. Keep a **migration matrix** (a table in this doc or a comment) recording
each surface's disposition.

### S3.1 — Register the Glasspane engine source(s)
- New `glasspane-source.el` (add to `emacs/build-bundle.el` in dep order, and to
  the load/require chain).
- `(jetpacs-defsource "glasspane.org" :params '((:name query :type "text" :required t))
  :fields <canonical> :query (lambda (p) (mapcar #'glasspane-source--canonicalize
  (glasspane-org--query (glasspane-org--parse-query (alist-get 'query p)))))
  :cache-key (lambda (_p) (glasspane-org--agenda-mtime)))` — wrap under
  `with-jetpacs-owner "glasspane"`. Keeps the vulpea/org-ql/fallback engine + memo
  app-side; the canonicalizer adapts to the domain-neutral field contract.
- The **agenda** items carry extra fields (`time date type ts-date`) — either a
  second source or extra canonical fields.
- **Acceptance:** the source resolves a fixture query to canonical items in
  `emacs --batch`; `jetpacs-lint-view-spec` accepts a spec bound to it.

### S3.2 — Reference migration: a STATIC single-layout surface FIRST
> **Deviation from the master plan, with reason.** The master plan named "saved
> views" as the reference case, but the saved-views screen switches rendering
> (list/board/calendar) **at runtime** per the selected view, plus a hub and a
> form — a single `:spec` (one static layout) can't express a runtime rendering
> switch, and its **board** rendering carries the per-card move-menu (a v1
> `:builder` limitation). So **do not start with saved-views.**
>
> Start with a genuinely static, single-layout, read-only collection to validate
> the source → `:spec` → template → layout pipeline end to end: **search results**
> (`glasspane-search.el`, a query → list) or **notes backlinks**
> (`glasspane-notes.el`). Prove one, then fan out.

- Migrate the chosen surface to a `:spec` view: `:source "glasspane.org"`,
  `:layout "list"`, a `:template` = the raw card the current code emits (author
  it as raw node data — ordinary constructors don't preserve placeholders), with
  `on_tap` → `heading.tap` and `args ((bind . "ref"))`.
- **Acceptance:** the migrated view renders byte-comparably to the old one for a
  fixture; suite green.

### S3.3 — Drop the four internal pokes
Re-grep (locations moved after the ui.el modularization):
`grep -rn "jetpacs--month-abbrevs\|jetpacs-shell--current-tab\|jetpacs-files--file\|jetpacs--in-action-handler\|glasspane-ui--filter-values" emacs/apps/glasspane/`
- `jetpacs--month-abbrevs` → `jetpacs-month-abbrev` (or the `date-label` transform).
- `jetpacs-shell--current-tab` read+setq (journal) → `jetpacs-shell-current-tab` +
  `jetpacs-shell-set-current-tab`.
- `jetpacs-files--file` setq (ui) → `jetpacs-files-open`.
- `jetpacs--in-action-handler` read (ui) → `jetpacs-in-action-p`.
- `glasspane-ui--filter-values` internals → `jetpacs-ui-state-list`.
- **Acceptance:** grep for the four raw internal symbols returns 0; suite green.

### S3.4 — Journal history → `:spec`; capture form → `jetpacs-form*`
- Journal *history* list → node-stream `:spec`. Capture *form* stays `:builder`
  but adopts `jetpacs-form*` (replaces the `--capture-gen` id rotation). Landing
  via `jetpacs-shell-set-current-tab`. Multi-select values arrive as vectors —
  the form primitive centralizes coercion.

### S3.5 — Notes/backlinks → `:spec`
- Linked / Outgoing / Unlinked sections → node-stream `:spec` (section header +
  cards). `note-card` ref has no `pos`. Async mentions populate a hash then
  repush — keep that outside the source cache.

### S3.6 — Search + agenda → `:spec`
- Search results → `:spec` over `"glasspane.org"`. Agenda *collections* → `:spec`;
  keep the `month_grid`/`tabs` fallbacks but via **`jetpacs-node-or`** instead of
  hand-coded `jetpacs-node-supported-p` branches.

### S3.7 — Action-catalog metadata + `glasspane-pack.json`
- Annotate the `jetpacs-defaction` sites (`heading.tap`, `heading.todo-set`,
  `heading.schedule`, `views.save`, `journal.capture`, `notes.*`) with `:args`/`:doc`.
- New `glasspane-pack.el` + a `--batch` generator emitting `glasspane-pack.json`:
  `{pack_id, pack_version, min_jetpacs_api, feature, layouts,
  sources: jetpacs-source-catalog, actions: jetpacs-action-catalog}` — **from live
  registrations**, plus a committed snapshot + a regen-and-assert test.

---

## Migration matrix (fill in as you go)

| Surface | Disposition | Why |
|---|---|---|
| search results | `:spec` (list) | static, single-layout — reference case |
| notes backlinks | `:spec` (node-stream) | static read-only collections |
| journal history | `:spec` | static list |
| journal capture form | `:builder` + `jetpacs-form*` | interactive form |
| agenda collections | `:spec` (+ `jetpacs-node-or`) | static, with capability fallbacks |
| saved-views hub | `:builder` | hub + new-view form |
| saved-views list/calendar rendering | `:spec` *if feasible* | needs a source that reads the current view's query from app state; runtime rendering-switch stays `:builder` dispatch |
| saved-views board rendering | `:builder` | per-card move-menu + curated todo order (v1 limits) |
| detail sheets, SRS review, dialogs | `:builder` | specialized/interactive |

> **Board reproduction limits (v1):** the `:spec` board uses source-enum /
> explicit / encounter column order and has no per-card cross-column move-menu.
> Glasspane's board (curated `org-todo-keywords-1` order + move-menu) exceeds
> that, so any board rendering that needs them stays `:builder`.

---

## Test gate & verification

- Every task: `emacs --batch -l emacs/build-bundle.el` then
  `wsl -d Debian -- bash -lc 'cd ~/pkb/projects/Glasspane && bash test/run-tests.sh'`
  — **all tests pass; the pre-change baseline is 78, plus new
  source/spec-equivalence, manifest, teardown, and mutation tests.**
- New tests to add: source canonicalization; a `:spec`-equivalence test (compiled
  tree vs the old renderer output for a fixture); `glasspane-pack.json`
  regen-and-assert; poke-removal grep-for-zero.
- Windows Emacs cannot run this suite (needs vulpea/org-ql/magit) — run under WSL.

## Pitfalls / risks

- **Stale line numbers** — the ui.el modularization moved things; re-grep everything.
- **Source normalization** is mandatory (raw org timestamps / vector tags won't
  satisfy the domain-neutral transforms).
- **Layout arity:** list/board return one root, calendar a node stream — the `:spec`
  compiler handles this, but a hand-authored template must match the layout.
- **Query engine differences:** the vulpea path may return items without `pos`;
  the canonicalizer must tolerate that.
- **One plan owns a file at a time** vs the pending org-adoption; monotonic
  submodule bumps.
- **Bundles upgrade together** — after the submodule bump, regen `glasspane.el`.

## Reference

- `jetpacs/docs/PLAN-binding-layer.md` (master, Stage 3 section) ·
  `jetpacs/docs/BINDING.md` (grammar) · `jetpacs/docs/contract.json` (`binding`
  block) · `jetpacs/docs/API-STABILITY.md` (the 1.5.0 surface).
- `docs/PLAN-glasspane-org-adoption.md` (the still-pending org refactor) ·
  `PLAN-platform-hardening.md` Task 21 (config rebase, in the jetpacs plan).
- Reference surface to model the migration on: `glasspane-views.el`
  (`--table-node` / `--board-node` / `--calendar-nodes`) and the item field
  contract (`headline todo scheduled deadline tags priority ref file pos`).
