# Plan: Emacs packages as jetpacs engines — vulpea first, then the ecosystem

**Status: plan (2026-07-13).** A roadmap for making `jetpacs-composer` able to
build real apps by leaning on stable, library-first Emacs packages — **vulpea**
foremost — as engines, exposed to the no-code layer through jetpacs sources /
actions and installed via the pack dependency model. This is the constructive
follow-through on the "rich server, thin client" pivot
(`docs/DECISION-no-binding-template-dsl.md`): the SDUI keeps the client thin, so
the server can be as powerful as Emacs + MELPA/ELPA allow.

> Cross-repo note: the *execution* of this belongs partly in `jetpacs-composer`
> (Stage 4) and `jetpacs` core; it is authored here because that is where the
> Glasspane adoption work lives. Move/mirror to the composer repo when it opens.

---

## 0. Thesis

Every ecosystem app built on vulpea (vulpea-ui, -journal, -para, vino) is a
**pack shape** we can replicate:

> a **pack** = one or more **sources** (a package's query API, normalized to the
> domain-neutral field contract) + **actions** (its create/select/mutate
> primitives) + **read-only data actions** rendered by a widget host + optional
> **schema / extractor deps** the composer installs — with zero coupling to the
> engine's internals.

The composer's job is to let a user assemble those into screens. The engine does
the work. We do not reimplement notes/tasks/agenda/search — we bind to packages
that already do them well.

Vulpea's own docs make the alignment explicit: its API is deliberately
**"LLM-friendly — an AI can help write queries, transformations, and entire
applications because the API expresses intent clearly."** That is exactly the
agent-composed-pack context we are in.

---

## Part A — Vulpea as the reference engine

### A.1 What we already established (deep-dive done 2026-07-13)

A five-reader map of the vulpea repo (`~/.cache/vulpea-maps/`, from the
`map-vulpea-app-surface` workflow) produced a grounded picture. The load-bearing
facts:

- **Headless foundation.** Every interactive command wraps a primitive that
  returns data or a `vulpea-note`; every decision point is a `defvar`/`defcustom`
  hook. This is the exact shape a jetpacs source/action catalog wants.
- **Reads are synchronous and fast** — direct blocking `emacsql` over built-in
  SQLite, no async/threads. `get-by-id` <5ms; indexed `by-tags/links/meta/property`
  <50–100ms/10k; `vulpea-db-query` + Elisp predicate <500ms/10k. **Safe inside a
  jetpacs `:query` at push time**, no concurrency hazard (single-thread; the async
  *write* pipeline can't interleave). Prefer the indexed `-by-*` fns over a full
  scan on hot paths.
- **Hybrid schema:** a materialized `notes` table (JSON blobs) fetches a whole
  note in one query (no JOINs); normalized `tags/links/meta/properties` side
  tables exist only to push filters into SQL. Backlinks/outgoing are a first-class
  edge list (`links-to`/`links-from`/`backlink-counts` — the last computes *all*
  counts in one grouped query, killing N+1).
- **No DB-change hook / revision counter.** A source `:cache-key` must synthesize
  a token: `(cons (vulpea-db-count-notes) <MAX(files.mtime) over the relevant
  scope>)`. Staleness window after a save is ~0.01–0.5s (batch/idle timer); for
  read-after-write correctness, drive the write through `vulpea-db-update-file` /
  `vulpea-utils-with-note-sync`.
- **The extractor plugin system is the domain-table primitive.**
  `vulpea-db-register-extractor` + a `make-vulpea-extractor` (`:name :version
  :schema :priority :extract-fn`) fills a first-class SQLite table during the
  parse-once sync; FK `:on-delete :cascade` to `notes(id)` gives correct
  incremental behaviour for free; a source then queries it with `emacsql` joined
  to `notes`. **A jetpacs pack can ship an extractor to power a domain source
  (tasks, citations, …).** Caveats to design around: (1) `ctx.ast` is file-wide
  but `extract-fn` runs per-note — scope AST reads to the note's subtree or you
  double-count; (2) register **before** the first sync and on every session (the
  registry isn't persisted); (3) `:create-table :if-not-exists` means a version
  bump won't `ALTER` — own additive migrations; (4) runs inside the write
  transaction — keep it fast; (5) namespace the table/name.
- **Headless creation:** `vulpea-create` (file or heading via `:parent`/`:after`)
  writes without a capture buffer, returns the created note, refuses to overwrite,
  and expands `%(...)`/`%<...>` template directives **before** `${var}`/context
  substitution — so a user-typed title can't inject elisp. A jetpacs create action
  inherits that safety if it doesn't re-order substitution.
- **Selection/find/insert seams** (`vulpea-select*`, `vulpea-find`, `vulpea-insert`)
  expose `candidates-fn` / `filter-fn` / `create-fn` as keyword args **and** global
  default vars, so a pack sets policy without wrapping commands. The picker reports
  a `(category . vulpea-note)` completion contract with the id on a text property —
  the same contract that lets `consult-vulpea`/`embark-vulpea` compose, and that a
  jetpacs SDUI picker should mimic. The **dyncontext + backlink-counts** technique
  (one grouped query per finder-open, read per candidate) is the efficiency
  pattern for rich pickers.
- **Async shell-outs** follow a promise-style `(resolve reject)` contract
  (`vulpea-note-unlinked-mentions-async`, ripgrep) — the template for *any*
  jetpacs action that shells out (rg, git, fd) feeding an SDUI async widget.
- **Schema/validation** (`vulpea-schema-define` + validation + flymake) is a
  separate, combinable facility for authoring hygiene (require a `deadline` on
  task notes, etc.) — a pack can ship a schema as a dep.

### A.2 The vulpea → jetpacs mapping (the reusable blueprint)

| Vulpea capability | jetpacs seam | Example |
|---|---|---|
| `vulpea-db-query-by-{tags,links,meta,property,level,directory,created-date}` | `jetpacs-defsource` `:query` (sync, fast) | tag collection, backlinks, "under projects/" |
| `vulpea-db-query-backlink-counts` | badge data in a source / dyncontext | backlink-count badges without N+1 |
| custom extractor + table | `jetpacs-defsource` over `emacsql … :inner :join notes` | a `tasks`/`citations` domain source |
| `vulpea-create` | `jetpacs-defaction` (headless, safe) | `notes.create` (file or heading) |
| `vulpea-select*` / `-find` / `-insert` | `jetpacs-defaction` + the candidates/create default vars | `notes.select`, `notes.insert-link` |
| `vulpea-buffer-{tags,meta}-*` (batch) | mutate actions | `notes.set-meta`, `notes.add-tag` |
| `vulpea-note-unlinked-mentions-async` | async action → SDUI widget | the existing mentions flow (generalize) |
| `vulpea-schema-define` + `-insert-fields` | pack dep + a form-fill action | domain authoring hygiene |
| `vulpea-db-count-notes` + `files.mtime` | source `:cache-key` token | freshness without a hook |

### A.3 Ecosystem apps as pack blueprints (source code still to read)

Each is a *pack recipe* — deep-read their source next to steal the patterns:

- **vulpea-ui** — a widget host with a small async-loader contract over headless
  primitives (backlinks w/ context, mentions, forward links, stats, schema
  health + one-key fix, a collection schema dashboard). Blueprint for the jetpacs
  "note sidebar" pack and the "surface violations + offer a fix action" pattern.
- **vulpea-journal** — date-addressed creation (`vulpea-create` `:parent`/`:after`,
  added for it) + calendar/nav widgets over `by-created-date`. Blueprint for a
  "journal/dailies" pack; all window management delegated to the host.
- **vulpea-para** — a whole methodology as *pure policy* over
  `by-tags`/`create`/`tags` primitives, no new storage. Blueprint for
  "workflow app = tag/query/create actions + saved view defs".
- **vino** — a domain model on **typed metadata + `note`-typed links**, escalating
  to a custom **extractor** only when a persisted queryable table is needed.
  Blueprint for domain packs (schema + typed-meta actions + optional extractor).

### A.4 Concrete near-term vulpea work (Glasspane / jetpacs)

Small, independently-shippable, each validates a slice of the blueprint:

1. **Add a vulpea `:cache-key` to `glasspane.notes`** — `(cons
   (vulpea-db-count-notes) <MAX files.mtime>)`; today the source is uncached.
   (Proves the freshness-token pattern.)
2. **Broaden the notes surface into more sources** — a `glasspane.tags` (tag
   facet + `by-tags-some/every/none`), backlink-count badges via
   `backlink-counts`, a `by-directory`/`by-created-date` source. Each is a few
   lines and expands what the composer can bind.
3. **Wrap creation/selection as headless actions** — `notes.create` (over
   `vulpea-create`), `notes.select`/`notes.insert-link` (over `vulpea-select`/
   `-insert` with the pack's `candidates-fn`). Composer-bindable, no capture buffer.
4. **Prototype one domain extractor** — e.g. a `glasspane.tasks` extractor + table
   (scoped per-note!) + a source over it, as the reference for "pack ships an
   extractor." Get the per-note scoping + registration-timing + migration story
   right once, document it.
5. **Ship a vulpea schema** for a Glasspane note class (authoring hygiene), as the
   reference "pack ships a schema dep."
6. **Deep-read vulpea-ui / -journal / -para / vino source** (a follow-on workflow)
   to extract exact widget/loader/create patterns before building the composer's
   widget-host contract.

---

## Part B — The wider Emacs package survey (candidate engines)

Beyond vulpea, survey MELPA/ELPA for **library-first, stable, clean-API,
server-runnable, data-rich** packages, each a potential jetpacs engine. Selection
criteria (score each candidate):

- **Library-first** — a usable non-interactive API, not just commands.
- **Stable / maintained** — long track record, on MELPA/ELPA, low churn.
- **Data-rich** — exposes queryable/structured data (→ sources) and mutators (→ actions).
- **Headless-capable** — core logic runnable without a visible buffer/window.
- **Dependency-sane** — installable + loadable in a background/server Emacs.

### B.1 Candidate map by domain (initial, to be verified + scored)

| Domain | Candidate engines | Powers a jetpacs app for… | API note |
|---|---|---|---|
| Notes / Zettelkasten | **vulpea** (primary), denote, org-node, org-roam | note graph, backlinks, PKM | vulpea library-first; org-roam is app-first; denote is filename-based (lighter API) |
| Query / agenda | **org-ql**, org-super-agenda, org-sidebar | saved searches, grouped agendas, task boards | org-ql has a real sexp/keyword query API (→ sources); super-agenda = grouping DSL |
| Task deps / scheduling | org-edna, org-gtd | dependency chains, GTD workflows | org-edna is action/condition based |
| Spaced repetition | **org-srs** (already used), org-drill, org-fc, anki-editor | review/study app | org-srs already wired in Glasspane |
| Reading / annotation | nov.el (EPUB), pdf-tools, org-noter, doc-view | a reader/annotator app | pdf-tools/nov expose position + text; org-noter binds notes↔location |
| Transclusion / compose | org-transclusion | live document composition | headless transclude API |
| Feeds / read-later | elfeed, elfeed-org | an RSS reader app | elfeed has a DB + query API (→ sources) |
| Mail | notmuch, mu4e | a mail triage app | notmuch has a strong query/DB API; heavier deps |
| Git / forge | magit, forge (already: jetpacs-magit) | repo/PR dashboards | magit is command-first but has porcelain data fns |
| Time / clocking | org-clock, activity-watch-mode | a time-tracking app | org-clock data is queryable |
| Contacts | org-contacts, BBDB | a contacts app | structured records |
| Tabular / data | org-table, ses, ledger/hledger, csv-mode | budgets, ledgers, sheets | ledger has a reporting API |
| Calendar | org-caldav, calfw | a calendar app | calfw is a rendering lib; caldav is sync |
| Bibliography | citar, org-cite, ebib | a references app | citar exposes a bib DB |

> Some of these (magit, mu4e, pdf-tools) are command/UI-first and would need a
> thin data-extraction layer; flag those as "needs an adapter" vs vulpea/org-ql/
> elfeed which are already query-shaped.

### B.2 Survey method

For the shortlist (start: **org-ql, denote, org-node, org-srs, elfeed,
org-transclusion, citar**), run a per-package fan-out (same shape as the vulpea
workflow): read the public API + docs, and produce a **capability → source/action
mapping** + an API-quality/stability score + a "which jetpacs app it unlocks"
line. Cross-check current MELPA/ELPA status and maintenance.

---

## Part C — Methodology & the engine-pack model

1. **Explore** each engine with a fan-out workflow → a capability map (like
   `~/.cache/vulpea-maps/`).
2. **Map** capabilities to `jetpacs-defsource` (reads) + `jetpacs-defaction`
   (creates/mutates/shell-outs), normalizing to the domain-neutral field/arg
   contract; rich rendering stays `:builder`.
3. **Declare** the engine as a pack dependency (`<pack>.json` `depends`, as
   `glasspane-pack.json` now does for vulpea/org-ql/…); the composer installs from
   MELPA/ELPA. Define the composer's install/version/capability-negotiation story
   (Stage 4).
4. **Prototype** one pack per engine to validate the blueprint end-to-end (source
   + actions + a composer-authored view), and to surface engine-specific caveats
   (extractor scoping, staleness, ripgrep/rg deps, cross-Emacs DB sharing).
5. **Generalize** the widget-host + async-loader contract (from vulpea-ui) so any
   engine's async data (mentions, feeds, PR lists) drops into an SDUI widget.

---

## Part D — Deliverables & sequencing

1. **This plan** (done) + **memory alignment** (done: `emacs-ecosystem-as-jetpacs-engines`,
   `sdui-rich-server-not-wire-dsl`).
2. **Vulpea near-term work** A.4 items 1–3 (cache-key, extra sources, headless
   create/select actions) — small, ship into Glasspane.
3. **Vulpea extractor prototype** (A.4.4) + doc — the domain-source reference.
4. **Ecosystem source-read workflow** (A.3) — vulpea-ui/journal/para/vino patterns.
5. **Package survey workflow** (B.2) — shortlist capability maps + scores.
6. **Composer engine-pack model** (Part C.3) — the install/negotiation design
   (opens with Stage 4 / the composer repo).

## Risks / open questions

- **Registration timing & migrations** for extractor-shipping packs (register
  before sync; own `ALTER`).
- **Staleness window** vs read-after-write; when to force a synchronous sync.
- **Hard external deps** — vulpea mentions needs `rg`; some engines need
  subprocesses (fd/fswatch) or heavy trees (mu4e). The pack `depends`/capability
  model must express non-elisp deps too.
- **Cross-Emacs / multi-surface** (desktop + Termux sharing a DB) — vulpea is
  designed for it; verify per engine.
- **Command-first packages** (magit, pdf-tools) need an adapter layer; budget for it.
- **Security** — headless creation/eval paths (vulpea's template ordering is safe;
  audit each engine's equivalent before exposing user input).

## See also

- `docs/DECISION-no-binding-template-dsl.md` · `emacs/apps/glasspane/glasspane-pack.el`
  (the `depends` model) · `emacs/apps/glasspane/glasspane-notes.el` (the seed
  vulpea source) · vulpea docs `api-reference.org` / `plugin-guide.org` /
  `architecture.org` (in the vulpea repo).
