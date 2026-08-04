# Chrome vocabulary and functional contracts — v2 DRAFT (proposed 2026-07-28, awaiting ratification; v1 ratified same day)

*v2 change: element names are now the **Material 3 component names**, 1:1
(m3.material.io; `material3` 1.4.0 per
`lookup-tables/M3-COMPONENT-LOOKUP.org`).  The functional contracts are
unchanged — they are the Emacs-side discipline M3 does not provide.  Scope:
the Jetpacs base layer — docstrings, user-facing docs, commit messages, and
the conventions base apps follow.  The EBP wire names (SPEC §17.6) are frozen
and are not renamed.  Tier-1 apps may deviate; the base does not.*

## The three name layers

| Layer | Names | Owned by |
|---|---|---|
| Wire | `top_bar` `bottom_bar` `fab` `floating_toolbar` `drawer` (scaffold slots) | SPEC §17.6 — frozen |
| Elisp API | `jetpacs-chrome-screen` keywords, `jetpacs-chrome-dock-items-function` (and the raw-node `jetpacs-chrome-dock-function`) | base — stable |
| Vocabulary | the M3 component names below | this document |

1:1 holds at the vocabulary layer ONLY.  The wire layer is deliberately not
1:1 (the lookup table's own note: `scaffold` bundles 8+ composables;
`OutlinedTextField` serves two wire types) and the contracts are Jetpacs',
not Material's.  A convention here is a *naming and placement* rule, never a
capability rule: chrome is structural content with no hidden behavior
(SPEC §17.6), and every chrome affordance maps to a command reachable
without it (M-x parity, JA-3).  Chrome is a projection of commands.

## The vocabulary (1:1 with M3)

| Element | M3 name | Wire slot | Retired names |
|---|---|---|---|
| slide-in panel behind the hamburger | **Navigation drawer** ("drawer" in running text) | `scaffold.drawer` | App Menu, hamburger menu |
| bar across the top | **Top app bar** ("top bar") | `scaffold.top_bar` | Menu bar, Contextual Actions Bar |
| docked bottom bar of destinations | **Navigation bar** | `scaffold.bottom_bar` (via the dock seam) | View switcher, Bottom nav bar |
| start-edge column of destinations on a wide window | **Navigation rail** | `scaffold.rail` (the same dock seam, expanded width) | — |
| floating cluster of contextual actions | **Toolbar — floating** | `scaffold.floating_toolbar` | Contextual Actions Bar |
| bottom-anchored row of actions | **Toolbar — docked** | `scaffold.bottom_bar` holding actions | — |
| round primary-action button | **FAB** | `scaffold.fab` | — |
| any `more_vert`-anchored menu | **Menu** (the pattern: **overflow menu**) | `menu` node | Action menu, kebab menu |

## Per-element contract (unchanged from v1 except as keyed)

**Navigation drawer** — app-level *destinations* (screens, roots, the
launcher rows), never actions that mutate a document.  Everything in it is
reachable elsewhere (M-x parity).  Fewer than three destinations: no drawer.

**Top app bar** — identity and globals: title, back affordance or drawer
button on the left, at most two or three screen-scope action icons on the
right (M-x sits top-right), plus at most one overflow menu.  It never
changes contents in response to a selection (that is the floating toolbar's
job).

**Navigation bar / navigation rail** — three to five *destinations*, the
selected one always indicated; items are places, never actions.  In Jetpacs
the places are the `multi_view`/`view.switched` machinery, and the
destinations persist across every screen via the dock seam — a navigation
bar that vanishes on drill is a defect, not a style.  Author the
destinations as data with `jetpacs-chrome-dock-items-function` and chrome
wears them per SPEC 20.1.1: a bottom navigation bar on compact and medium
widths, a start-edge navigation rail (`scaffold.rail`) on expanded — the
M3 NavigationSuiteScaffold behavior, one authoring.  The raw-node
`jetpacs-chrome-dock-function` remains as an override for a hand-built bar
(always `bottom_bar`, never adaptive), and wins when both are set.

**Toolbar** — *actions*, in two variants exactly as M3 draws them:
**floating** (the `floating_toolbar` slot) for mode- or selection-contextual
actions keyed to the buffer (the org toolbar is the archetype); **docked**
(action nodes in `bottom_bar`) when a screen needs bottom-anchored actions.
A screen shows a navigation bar or a docked toolbar, never both, and a
toolbar never duplicates the top app bar's globals.

**FAB** — exactly one, verb-shaped, the screen's single primary *creation*
action.  Never a menu, never a toggle; no natural creation act, no FAB.

**Menu** — anchored to `more_vert`, scoped to its anchor: on the top app
bar it is the overflow menu (screen-scope actions that did not earn an
icon); on a row or card it holds that item's actions.  Destructive entries
sit last and carry `:confirm`.

## Fidelity gaps the lookup table exposes (future work, not renames)

- **NavigationBar is unwrapped**: today's navigation bar is authored
  `button` nodes in the `bottom_bar` slot — the contract is honored but the
  visuals are approximated.  Wrapping the real composable (a `nav_bar` wire
  type or the lookup's suggestion of a smarter `bottom_bar` renderer) buys
  the authentic icon-above-label items and indicator pill.  SPEC-governed
  expansion: contract.json, constructor, renderer, NodeSupport, goldens.
- **ListItem is unwrapped**: `jetpacs-chrome-row` is the manual
  card/row/column composition of exactly that component.
- **FloatingToolbar (material3 1.5+)**: the `floating_toolbar` slot
  predates the real composable; adopting it when the dependency moves is
  the same kind of upgrade.

## Rationale

M3 names are what the platform documentation, the Compose API, and every
Android reference use — a private synonym ("View switcher", "Action menu")
taxes every future doc lookup.  The v1 rejections stand for the same
reason: "Menu bar" collides with Emacs's menu bar, "Contextual Actions Bar"
with Android's contextual action bar, "App Menu" with both.  What Jetpacs
adds is not names but contracts — the placement rules and the M-x-parity
discipline above — and those survive v2 untouched.
