# M3 Expressive Catalog — verification ledger (2026-07-28)

**CLOSED (stamped 2026-08-14, the D-17 ledger row): the sprint this
file was resume state for finished at 265/279 recreated with 14 real
`:unsupported` — counted from the REGISTRY, not grep (20 raw hits
include 6 infrastructure markers in jetpacs-m3-core.el).  The resume
commands below cd into the ARCHIVED llm-poc-2 checkout and must not be
run; llm-poc-3 is the live line.  Everything below is HISTORY.**

The catalog is **authored and gated**; what was outstanding was the
**verification pass**, cut short by usage. This file WAS the
resume state.

## What exists

`emacs/jetpacs-m3-catalog.el` + `emacs/apps/m3-catalog/` (42 files) +
`test/jetpacs-m3-catalog-test.el` + `tools/m3-check.{el,sh}`.

* **41 components / 279 examples**, upstream `Components.kt` order,
  upstream names, descriptions, source urls and `isExpressive` flags.
* **67 examples recreated** (23 of them by claiming the Example
  screen's own scaffold slots via `:slots` / `:top-bar`),
  **212 marked `:unsupported`** with a reason.
* Local gates all green: `tools/m3-check.sh <every slug>` OK,
  `test/jetpacs-m3-catalog-test.el` 14/14, icon lint 2/2, byte-compile
  clean with warnings-as-errors.

## Why the verification still matters

**213 / 279 unsupported is suspicious on its face**, and the four
verifier reports that did land before the cut already show the failure
mode is real:

* `split-button` **P1, false unsupported** —
  `SplitButtonWithUnCheckableTrailingButtonSample` is the one sample in
  that module with no `checked` state, so its whole subject is the
  fused geometry, and **both** things its reason called missing are on
  the wire: per-corner `:corner` (`jetpacs--corner-keys`,
  `Attributes.kt` builds the `RoundedCornerShape`) and `:spacing 2`.
  `jetpacs-m3-lists.el` already composes exactly this geometry for
  `ListItemDefaults.segmentedShapes`. **FIXED** — recreated as
  `jetpacs-m3-split-button--uncheckable`; the module Commentary now
  says the fusion composes and only the checked state is missing.
* `split-button` P2 — the shared `--layout-note` claimed "no
  per-corner shape". **FIXED**: it now rests on the missing `checked`
  state alone.
* `togglebuttons` P2 — "no node has a shape member" is false
  (`surface` has `:shape`). **FIXED** in `togglebuttons`,
  `segmented-button` (two copies) and `button-groups`, each now naming
  what is really missing (a checked/selected state, and the
  press-animated connected shapes).
* `sliders` P2 — `--track-note` described `SliderDefaults.Thumb`/
  `.Track` mechanics for `SliderWithCustomThumbSample`, which uses
  neither (its thumb is a `Label`+`Icon`). **FIXED**: split into
  `--thumb-note` and `--track-note`.

These reason strings are **product text** — they are what a user reads
on the "Not supported" screen — so a false claim there is a defect, not
a comment nit.

## Verified so far (12 of 41)

| verdict | components |
|---|---|
| clean | adaptive, carousel, checkboxes, icon-buttons, progress-indicators, tabs, tooltips |
| problems (all fixed except the split-button P1) | badge, bottom-app-bar, sliders, split-button, togglebuttons |

Fixed already: `badge` P1 (an `icon_button` `:badge ""` renders NO dot —
`InputNodes.kt` guards on `badge.isNotEmpty()`; the bare dot is the
`badge` NODE, so it now rides inside a tappable `box`), `bottom-app-bar`
P2 ×2 (`arrange` silently discards `spacing` in `horizontalArrange`, so
the Fixed samples now cluster between weighted spacers; the dead
`--source` defconst is now used by all nine examples). The same
`:badge ""` bug was in `jetpacs-m3-core.el`'s pin affordance and is
fixed there too.

## Unverified (29 of 41)

badge is verified but re-check after the fix. Outstanding:

bottom-sheet, button-groups, buttons, card, chips, date-pickers,
dialogs, extended-fab, fab-menu, floating-action-buttons,
floating-toolbar, lists, loading-indicators, material-shapes, menus,
navigation-bar, navigation-drawer, navigation-rail,
navigation-suite-scaffold, pull-to-refresh-indicator, radio-buttons,
search-bars, segmented-button, snackbars, swipe-to-dismiss, switches,
text-fields, time-picker, top-app-bar.

**Prioritise the components with ZERO recreations** — that is where a
lazy "unsupported" hides: togglebuttons (0/10), tooltips (0/13),
split-button (0/12, one already confirmed false), navigation-rail
(0/8), adaptive (0/7), carousel (0/6), loading-indicators (0/5),
button-groups (0/4), bottom-sheet (0/3), dialogs (0/3), search-bars
(0/3), radio-buttons (0/2), segmented-button (0/2),
navigation-suite-scaffold (0/2), fab-menu (0/1), material-shapes (0/1).
(adaptive, carousel, tooltips and togglebuttons have already been
checked and stand.)

## Systemic checks to run across ALL modules

1. **`:corner` per-corner** — any reason claiming "no shape member" or
   "no per-corner shape" is wrong. `grep -rn "per-corner\|shape member"
   emacs/apps/m3-catalog/`.
2. **Renderer reality, not JSON validity** — the `badge ""` bug proves
   the gate cannot catch a member the renderer ignores. For each
   recreation, read the Kotlin renderer
   (`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/`)
   and confirm the member is actually consumed. Known traps:
   `arrange` beats `spacing` (`LayoutNodes.kt`), `badge` needs a
   non-empty label on `icon_button`/`icon` (`InputNodes.kt`,
   `ContentNodes.kt`).
3. **Composition from wrapped nodes** — an unwrapped M3 component does
   NOT automatically mean unsupported (see `jetpacs-m3-lists.el`
   composing segmented shapes). Ask whether the sample's *point*
   survives composition.
4. **Reason strings** must describe *that* sample, name a real missing
   member, and be true.

## How to resume

Per component: re-run the verify prompt from the workflow script
`.../workflows/scripts/m3-catalog-main-wf_637cff5e-40e.js` (the
`verify:` stage), or drive it manually. The local gate for any subset:

```sh
cd llm-poc-2 && tools/m3-check.sh <slug>...
```

The whole-app gate:

```sh
cd llm-poc-2 && emacs -Q --batch -L emacs -L emacs/apps/m3-catalog \
  -l test/jetpacs-m3-catalog-test.el -f ert-run-tests-batch-and-exit
```

Still never done: a **device smoke** (nothing here has been rendered on
hardware — see the device-smoke practice: force-stop first, screenshot
before tapping).
