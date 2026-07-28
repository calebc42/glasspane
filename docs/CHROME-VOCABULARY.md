# Chrome vocabulary and functional contracts — DRAFT (proposed 2026-07-28, awaiting ratification)

*Scope: the Jetpacs base layer — docstrings, user-facing docs, commit messages,
and the conventions base apps follow. The EBP wire names (SPEC §17.6:
`top_bar`, `bottom_bar`, `fab`, `floating_toolbar`, `drawer`) are frozen and
are not renamed by this document. Tier-1 apps may deviate; the base does not.*

## The three name layers

| Layer | Names | Owned by |
|---|---|---|
| Wire | `top_bar` `bottom_bar` `fab` `floating_toolbar` `drawer` (scaffold slots) | SPEC §17.6 — frozen |
| Elisp API | `jetpacs-chrome-screen` keywords `:actions` `:fab` `:drawer` etc. | base — stable |
| Vocabulary | the names below | this document |

A convention here is a *naming and placement* rule, never a capability rule:
per SPEC §17.6 chrome is structural content with no hidden behavior, and per
the M-x parity discipline (JA-3) every chrome affordance maps to a command
reachable without it. Chrome is a projection of commands, not a container of
exclusive features.

## The vocabulary

| Element | Name | Never called |
|---|---|---|
| slide-in panel behind the hamburger icon | **Drawer** | App Menu, hamburger menu |
| bar across the top | **Top bar** | Menu bar, Contextual Actions Bar |
| `bottom_bar` used for sibling views | **View switcher** (the pattern; the slot stays "bottom bar") | Bottom nav bar |
| floating cluster of contextual actions | **Floating toolbar** | Contextual Actions Bar |
| round primary-action button | **FAB** | — |
| any `more_vert`-triggered menu | **Action menu** | overflow menu, kebab menu |

## Per-element contract

**Drawer** — app-level *destinations* (screens, roots, the launcher), never
actions that mutate the document. Everything in it is reachable elsewhere
(M-x parity). A screen with fewer than three destinations ships no drawer.

**Top bar** — identity and globals: title, the back affordance or drawer
button on the left, at most two or three screen-scope action icons on the
right, plus at most one Action menu for the rest. It never changes contents
in response to a selection (that job belongs to the floating toolbar).

**View switcher** — the `bottom_bar` slot holding three to five *sibling
views of the same surface* (the `multi_view`/`view.switched` machinery).
Items are views, never actions; the current view is always indicated. When a
screen needs bottom-anchored actions instead, that is a floating toolbar, not
a bottom bar.

**Floating toolbar** — the tool-bar analog: *contextual* actions keyed to the
buffer's major mode or the current selection/edit state (the org toolbar is
the archetype). It appears only when it earns its space and never duplicates
the top bar's globals.

**FAB** — exactly one, verb-shaped, the screen's single primary *creation*
action (add heading, new file). Never a menu, never a toggle; a screen with
no natural creation act has no FAB.

**Action menu** — the `more_vert` menu, scoped to whatever it is anchored to:
on the top bar it holds screen-scope actions that did not earn an icon; on a
row or card it holds that item's actions. Destructive entries sit last and
carry `:confirm`.

## Rationale for the rejected names

- **"Menu bar"** imports an Emacs term for something that is not the Emacs
  menu bar; if a real menu-bar projection ever ships, the name must be free.
- **"Contextual Actions Bar"** collides with Android's contextual action bar
  (the selection-mode bar that *replaces* the top bar) — a specific,
  different widget.
- **"App Menu"** collides with both "menu bar" and "Action menu".
- **"Bottom nav bar"** names the widget, not the contract; "view switcher"
  names what the base actually promises (sibling views, `view.switched`).
