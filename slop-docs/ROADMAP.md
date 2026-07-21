# Roadmap — the Glasspane app

**STATUS (2026-07-13): current.** This is the *app* roadmap: the
Glasspane org experience and the reference Tier-1 apps bundled with it.
The **foundation roadmap** — the wire, the core elisp, the renderer
library, the companion shell — lives with the
[jetpacs repo](https://github.com/calebc42/jetpacs). The pre-split
unified roadmap that ordered both worlds is preserved in the jetpacs
repo's git history; this document carries its app-level horizons
forward.

**How this repo tracks the foundation:** the `jetpacs` git submodule is
a deliberate pin, not a live edge. Bumping it is a reviewed change:
update the pin, regenerate `glasspane.el`, run the suite, commit —
never ride the core's HEAD blind. An item below that needs *new*
companion capability (a SPEC section + `:jetpacs` Kotlin) is filed
against the jetpacs repo first and consumed here once released.

## Where things stand

Horizons 0–3 of the old unified roadmap are **landed code-side**: the
org dashboard, capture, clock, search; the daily-note journal with
carried-over reschedule (PKM 5); wikilink autocomplete + backlinks over
vulpea (PKM 3–4); saved org-ql queries as table/board/calendar views
(PKM 11); org-defined automations (AUTO 13); the sparse filter; the SRS
review skin over org-srs.

Since then the **binding-layer adoption** landed in re-scoped form
([PLAN-binding-adoption.md](PLAN-binding-adoption.md) has the status;
[DECISION-no-binding-template-dsl.md](../jetpacs/docs/DECISION-no-binding-template-dsl.md)
the why): Glasspane now exposes engine **sources** (`glasspane.org`,
vulpea-backed `glasspane.notes`), an annotated action catalog, and
`glasspane-pack.json` for the composer, while rich cards stay
`:builder`s.

The **org-adoption** landed too: `glasspane-org.el` stands on the
core's `jetpacs-org-*` primitives (one query grammar, canonical
refs/cache, the guarded vulpea note path — adopted at api 1.6.0),
keeping only Glasspane's extractions and its mutation-funnel policy
([PLAN-glasspane-org-adoption.md](PLAN-glasspane-org-adoption.md) has
the record, including the deliberate keep-the-funnel decision).

The **jetpacs pin now rides `6cf8fa9` (api 1.11.0, SPEC-1.0-rc)** — a
purely additive bump (hypertext/sections/hosts substrates, the schema
registry's stricter lint). On that base the **saved views went rich**
(all `:builder`, per the standing no-template-DSL decision): span
styling with priority badges and strike-through, tappable tag chips,
swipe complete/schedule-today, single-file drag reorder, a month-grid
calendar, and a list|board|calendar tabs pager — each with the
composed fallback for companions predating the node.

What that leaves is **debt, not features**:

1. **On-device acceptance.** Most of the automation/trigger/journal
   work has never had its acceptance pass on real hardware. The full
   pending list is [TESTING-ON-DEVICE.md](TESTING-ON-DEVICE.md) — this
   is the top of the queue, because everything else stacks on those
   paths.
2. **The vulpea performance spike** (PKM 1). Backlinks shipped ahead of
   the spike on the strength of the API; the phone still owes the
   numbers: cold-index time, incremental update, memory on a
   realistic-size vault. If they're bad, the fallback decision
   (org-roam) reopens.

## ⛔ The gate

**Battery numbers before heavier device integration.** A normal day's
profile with a real trigger set active (screen + power + a time
trigger); expectation is ≈0 delta over the existing foreground service.
The measurement itself is foundation work (jetpacs roadmap, near-term
#4); this repo's H4 items stay blocked until the numbers exist. This
gate was deliberately deferred once (2026-07-05, away from hardware) —
it does not defer again.

## Quick wins (small, audit-fed, not gate-blocked)

Items the two audits recommended that fell through the horizon lists
when the unified roadmap split. None adds background work, so the ⛔
gate doesn't apply; pull any of these whenever a small win is wanted.
Anchors are in the audits.

- **Undo snackbar** on mutating actions
  ([AUDIT-logseq-plunder.md](AUDIT-logseq-plunder.md) P1) — the
  audit's "cheapest genuinely-daily win"; engine-side undo already
  works, this is the phone affordance.
- **Favorites + recents** in the drawer (P2) — bookmarks + drawer, no
  new machinery.
- **Journal riders** (P3 + P5) — a "due today" foldable on the daily
  note and the quick-add inbox convention (seeded template, inbox
  count badge, one-tap refile).
- **Search scope chips + in-buffer find** (P7) — opportunistic, when
  search is next touched.
- **Subtree delete** from the detail view
  ([AUDIT-orgzly-parity.md](AUDIT-orgzly-parity.md) #2) — one
  allowlisted action + confirm dialog; the most-noticed structure-ops
  hole.
- **Date-only reminder time** (orgzly #3) — small extension of the
  upcoming-reminders pass.
- **Reminder Done/Snooze actions** (orgzly #1) *(foundation:
  `reminder.action` wire)* — the largest true orgzly gap; SPEC +
  Kotlin filed against jetpacs first.
- **Decide: calendar provider sync** (orgzly #5) — want/don't-want;
  if wanted, it's a new device capability (foundation), not app work.

## Horizon 4 — daily-driver maturity

In dependency order; items marked *(foundation)* need jetpacs-side work
first.

- **PKM 19 — org-roam vault interop.** Aliases/refs in autocomplete
  and mentions, roam-dailies journal layout, desktop-coexistence
  check — the cheapest adoption channel (existing Emacs users), added
  2026-07-10; details in
  [PLAN-pkm-conversion.md](PLAN-pkm-conversion.md). Depends only on
  the vulpea spike confirming the engine.
- **PKM 9 — inline images + photo capture.** Settles the cross-app
  storage-boundary question; genuine personal value now,
  convert-critical later.
- **PKM 10 — typed property forms.** Drawer syntax disappears from the
  detail view; reuses the settings-controls pattern.
- **ORGRO: LaTeX.** Make the TeX-vs-KaTeX decision, then implement.
  The decision is the blocker, not the work — stop carrying it
  undecided.
- **Notification-listener automation** *(foundation: AUTO 9)* —
  Tasker's most-loved trigger; isolated because of special access and
  the privacy review.
- **Launcher maturity** *(foundation: AUTO 15–17)* — offline app
  switching, shortcuts/pinning, widget/tile slot picker: the
  "installed app" illusion, in dependency order.
- **Special-access effectors** *(foundation: AUTO 5)* — brightness,
  DND; opportunistic, pull earlier whenever a real automation wants
  one.
- **Voice-note capture** *(foundation: `media.record`)* —
  [AUDIT-logseq-plunder.md](AUDIT-logseq-plunder.md) P4; rides PKM 9's
  storage-boundary decision, optional on-device transcription.
- **Per-file git history** — Logseq audit P6; pure composition of
  landed pieces (magit bridge, diff shading), and makes the future
  PKM 14 autocommit visible and trustable.

## Horizon 5 — convert-facing (parked, not cancelled)

**Unpark trigger (unchanged from the unified roadmap):** a concrete
second user in sight — an F-Droid release push, or a real
Obsidian/Logseq/Notion convert willing to trial. Until then this
horizon accrues design notes only.

- **PKM 2 — the editing-model design**, then PKM 6 → 7 → 8 (conceal,
  structural manipulation, slash menu). The design doc comes first if
  any earlier work touches editor-sync rendering.
- **PKM 12 → 13 — importers** (Obsidian/markdown, then Logseq +
  Notion). The switching lever; Logseq's DB-first turn makes its
  org-era users prime converts
  ([AUDIT-logseq-plunder.md](AUDIT-logseq-plunder.md)).
- **PKM 14 — the FOSS sync floor.** **PKM 15 — zero-Emacs onboarding.**
- **AUTO 18 → 19 — build import with consent; declarative org apps**
  (19 may pull into H4 on personal desire — useful without converts).
- **ORGRO: org-crypt, org-protocol** (org-protocol is mostly a desktop
  concern; the share sheet already covers Android capture).
- **Local-neighborhood graph view** *(foundation: canvas/graph wire
  node)* — reopened 2026-07-10 as a design-notes candidate; the global
  graph stays a non-goal. See the decision note in
  [PLAN-pkm-conversion.md](PLAN-pkm-conversion.md) non-goals; behind
  the vulpea spike and the ⛔ gate.

## Backlog feeds

Two standing audits mine competitor UX for candidates; neither is a
commitment list:

- [AUDIT-logseq-plunder.md](AUDIT-logseq-plunder.md) — suggested
  insertions absorbed 2026-07-10 (→ Quick wins + H4); still mines
  fresh candidates.
- [AUDIT-orgzly-parity.md](AUDIT-orgzly-parity.md) — parity confirmed
  exceeded; the four true gaps slotted 2026-07-10 (→ Quick wins;
  image share stays PKM 9).

## Standing gates (every substantial change)

- **Org case conventions.** Keywords/blocks/drawers case-insensitive
  (bind `case-fold-search` explicitly); TODO keywords and tags
  case-sensitive; display preserves file case. Every new org-syntax
  regex ships with a case test.
- **The cache contract.** Views memoise; every mutation path
  invalidates — directly in the action handler, plus the shell refresh
  hook for pull-to-refresh and queue drains.
- **Bundle freshness.** `glasspane.el` is generated; regenerate and
  commit with every `emacs/` change (CI enforces).
- **Deliberate submodule bumps.** A jetpacs pin bump is its own
  reviewed commit with the suite green against the new core.
- **Battery.** Anything adding background work states its cost; the ⛔
  gate above governs H4.
