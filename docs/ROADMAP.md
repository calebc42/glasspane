# Roadmap — the Glasspane app

**STATUS (2026-07-09): current.** This is the *app* roadmap: the
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

## Horizon 4 — daily-driver maturity

In dependency order; items marked *(foundation)* need jetpacs-side work
first.

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

## Backlog feeds

Two standing audits mine competitor UX for candidates; neither is a
commitment list:

- [AUDIT-logseq-plunder.md](AUDIT-logseq-plunder.md) — undo snackbar,
  favorites/recents, voice capture, git file history, tag-keyed
  schemas, …
- [AUDIT-orgzly-parity.md](AUDIT-orgzly-parity.md) — parity confirmed
  exceeded except: reminder actions (Done/Snooze), subtree delete,
  image share (→ PKM 9), calendar sync (unplanned).

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
