# Plan: typed properties + the vault doctor

**Status: plan (2026-07-16).** This document *executes* PKM Task 10
(typed property forms, `PLAN-pkm-conversion.md` Phase C5) at full
depth and adds its natural sibling, the **vault doctor** — a
scan/report/fix surface for schema violations, missing metadata, and
missing IDs. It exists because a 2026-07-16 survey of the owner's
pre-jetpacs elisp found the same two features designed **three
separate times** (coppermind-lib, metadata-linting, org-pkms) — the
strongest possible signal of a real personal need, and a worked design
corpus this plan mines instead of re-deriving. Sources and warnings in
§1.

Engine decisions already made elsewhere are honored, not reopened:
the schema registry is **`vulpea-schema-define`** (PKM Task 1 note,
`PLAN-vulpea-ecosystem-exploration.md` A.1/A.2 — schema as a
combinable authoring-hygiene facility, pack-shippable as a dep).

---

## 0. Thesis

Notion's differentiator is *typed, validated databases*; Obsidian's
power users obsess over frontmatter consistency. Glasspane already has
the query grammar, saved views (Task 11 ✅), and property drawers as
data — what's missing is the **form UX** (drawers never rendered as
drawer syntax) and the **hygiene loop** (impose a schema on a
pre-existing pile of notes without hand-editing hundreds of files).
Together they are the convert-onboarding moment: import a vault
(Task 12/13), run the doctor, watch it become a database.

## 1. Prior art (mined 2026-07-16 — read before implementing)

| Source | Take | Avoid |
|---|---|---|
| `org-pkms` — `\\wsl.localhost\Debian\home\calebc42\org-pkms\` | Field model (9 types: enum string date datetime number percent price boolean **ref**), per-field validator/normalizer, schema *defined in an org file*, discovery-linter UX (README.org:182-199): group violations, offer accept-as-alias / rename-all / add-to-schema / review-individually; ~60 ERT tests (temp-vault sandbox pattern) | The split modules in `elisp/` are **broken mid-refactor** (schema.el has unbalanced parens; sync.el calls an unported fn). Port ideas from the monolith `pkms.el.backup` + docs only. Skip the KB_* materialization entirely (§2 D4) |
| `coppermind-lib.el` — `\\wsl.localhost\Debian-Sandbox\home\calebc42\.emacs.d\lisp\lib\` | The typed property setter's dispatch (lines 62-144): enum → completing-read, date → timestamp, `link:TYPE` → filtered node picker; the vault linter loop (231-337): missing/empty/extra props + missing-ID batch fix | Filesystem-as-schema (a directory per property) — superseded by `vulpea-schema-define`. Several fns are runtime-broken (`generate-roam-template` let* bug); duplicated blocks |
| Schema *data* — `\\wsl.localhost\Debian-Sandbox\home\calebc42\coppermind\system\schemas\` | The owner's real vocabulary, use as seed schemas: project STATUS enum backlog/pending/in-progress/review/blocked/done, PRIORITY high/medium/low, event subtype (date, location); resource format text/diagram/video/url/code, ARCHIVED yes/no, CONFIDENCE, PARENT `ref:resource` | Mixed-case property names (`format` vs `STATUS`) — normalize per org case conventions |
| `metadata-linting.el` — `\\wsl.localhost\ro-debian\home\calebc42\.emacs.d\el\` | The guided-fill loop: query nodes by pattern, walk required properties, prompt for each missing one, write back | Minibuffer-only UX; org-roam-db-query (use the core grammar) |
| `relationships.org` — coppermind `system/lib/` | Named relations as properties (`REL-IMPLEMENTS: [[id:…]]`) + reverse query ("projects implementing X") — the extension shape beyond plain refs | Deferred (§7); plain `:target-tags` refs first |
| `templates/default.org` (same dir) | The default new-note drawer the owner settled on: ID / type / tags / archived / modified | — |

## 2. Design decisions

- **D1 — registry:** `vulpea-schema-define` is the engine. Glasspane
  adds a thin layer: schemas registered under the app owner,
  persisted/edited via the Customize seam (settings-controls pattern,
  proven by `jetpacs-settings`), shippable in a pack as a dep
  (vulpea-plan A.2 row: "pack dep + a form-fill action").
- **D2 — storage convention (the Task 10 open call):** property
  **drawers are canonical** for Glasspane. The whole stack — the core
  grammar's `property` term, saved views' columns, `glasspane-detail`
  — reads drawers; vulpea *meta* (description lists) stays a
  read-layer the schema can validate but Glasspane forms don't write.
  Revisit only if the vulpea spike (PKM Task 1) contradicts.
- **D3 — advisory, never a gate:** unknown keys render as free text;
  validation *reports*, it never blocks a save. Org files are wild;
  every feature keeps its escape hatch (org-pkms's founding
  principle).
- **D4 — no native-field materialization:** org-pkms mirrored TODO /
  CLOSED / clock sums into `KB_*` properties because org-roam couldn't
  query natives. Our grammar queries `todo/scheduled/deadline/tags`
  first-class — materializing copies would create dual truth. Explicit
  non-goal.
- **D5 — typed relations:** field type `ref` = an ID-valued property
  constrained by `:target-tags` (vulpea-schema's own shape). The
  editor widget is the wikilink-capf node picker filtered to the
  target tag (exists — `glasspane-notes.el`).
- **D6 — case:** all property-name matching case-insensitive; enum
  *values* compared case-sensitively; every new regex lands with a
  case test (repo rule).
- **D7 — battery:** doctor scans run on demand (or as an explicit
  automation), memoised per the cache contract, never on save hooks.
  The owner's own `org-roam-reflink` (full DB rescan per save) is the
  documented anti-pattern here.

## 3. Task S1 — schema registry + seed schemas

**Goal:** `glasspane-schema.el`: register/lookup note schemas (tag
predicate → typed fields) over `vulpea-schema-define`, degrade
gracefully when vulpea is absent (probe, like
`glasspane-notes-available-p`). Ship two seed schemas from §1 data
(project, resource) as pack-mergeable templates via
`glasspane-config`'s merge-by-key.

**Files:** `emacs/apps/glasspane/glasspane-schema.el` (new),
`glasspane-config.el` (seed templates), tests ported from the
org-pkms ERT sandbox pattern (temp vault, round-trip pinning).

**Acceptance:** schema for tag `:project:` resolves fields + enum
values; unknown tag → nil; loads clean without vulpea.

## 4. Task S2 — typed property form (PKM Task 10 proper)

**Goal:** the detail view's property section renders each known key as
its typed control — enum → picker, date/datetime → native date picker
(exact org timestamp round-trip), number/percent/price → numeric
field, boolean → checkbox, ref → filtered node picker, everything
else → text. Writes go through the existing mutation funnel via
`property.set`.

**Files:** `glasspane-detail.el` (property section),
`glasspane-schema.el` (field→widget mapping; reuse the
settings-controls schema→control code path), action allowlist check.

**Pitfalls:** the Task 10 list verbatim (advisory schema, timestamp
round-trip, case) + rotate field ids to clear inputs (journal capture
trick).

**Acceptance:** Task 10's acceptance, plus: a `ref` field opens the
node picker filtered to `:target-tags`, and the resulting drawer diff
is one clean line.

## 5. Task S3 — typed capture ("new Project" as a form)

**Goal:** creating a note whose schema is known pre-seeds the drawer
(owner's default drawer + schema fields with `:DEFAULT:`s) and offers
the typed form immediately — the capture-side of S2. Include the
guided "define a schema" flow (org-pkms wizard's prompt chain:
type → fields → field types → enum values) as a settings screen —
this is the "create your first database" onboarding beat.

**Files:** capture path (`glasspane-capture.el` / journal capture
row), `glasspane-schema.el` (wizard), drawer seeding in the mutation
funnel.

**Acceptance:** new note tagged `:project:` opens with STATUS/PRIORITY
pickers pre-rendered; wizard produces a schema that S1 loads.

## 6. Task S4 — the vault doctor

**Goal:** a doctor surface: scan the vault against registered schemas
and report, grouped by violation kind — missing required property,
value not in enum, missing ID, missing CREATED — with per-group bulk
actions (org-pkms's UX): **accept as alias** (map value→canonical),
**rename all**, **add to schema**, **fix individually** (jump into the
S2 form), **add IDs** (batch, the org-pkms-auto-id behavior, run here
rather than on find-file).

**Files:** `emacs/apps/glasspane/glasspane-doctor.el` (new; render on
magit-section or tablist substrate — report rows are exactly that
shape), scan over `jetpacs-org` query + extraction (errors become
report rows, not signals — org-pkms-extract's condition-case
pattern), actions behind the mutation funnel.

**Pitfalls:** D7 (on-demand only, memoised); big-vault scan cost is
the battery risk — chunk by directory and show progress; bulk rename
must be previewable (count + first N) before it touches files.

**Acceptance:** imported messy vault → doctor lists "12 notes have
STATUS=ongoing (not in schema)" → *rename all* → files change, report
lane empties, second scan is clean. Errors in one file surface as a
row, never abort the scan.

## 7. Task S5 (cross-repo) — property value comparisons in the grammar

**Goal:** the built-in grammar's `property` term is equality-only;
dashboard lanes like `REVIEW_DUE < today` and doctor rules like
"deadline in the past" need date/number comparisons. Per the ROADMAP
convention this is **filed against jetpacs first** (core grammar +
fallback interpreter + case test), consumed here on the next submodule
pin.

**Acceptance (jetpacs side):** `(property "REVIEW_DUE" :< "<today>")`
(exact operator syntax = org-ql compatibility decision) evaluates in
both the org-ql path and the fallback interpreter.

## 8. Non-goals (decided now)

- No `KB_*` / native-field materialization (D4).
- No named relation types (`REL-IMPLEMENTS`) yet — plain typed refs
  first; named relations + reverse-relation lanes are a follow-up once
  refs earn use.
- No schema versioning/migration machinery (org-pkms README sketches
  it; build when a shipped seed schema actually changes).
- No blocking validation anywhere (D3).
- Doctor does not rewrite content beyond properties/IDs (no body
  surgery).

## 9. Sequencing

S1 → S2 → (S3 ∥ S4) — S5 rides any jetpacs release before S4 needs
date rules, else the doctor ships with equality rules only. S2 is the
Task 10 deliverable; S4 is the demo-video moment (import → doctor →
database).
