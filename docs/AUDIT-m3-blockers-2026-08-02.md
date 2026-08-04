# AUDIT — every m3-catalog blocker, triaged (2026-08-02)

> **Ledger state as of 2026-08-04 (ninth pass) — 265/279 built, 14
> remain. G-51 IS CLOSED, ON HARDWARE.** state.changed grew an opt-in
> caret (SPEC 14.6.1): a text-valued stateful node authored with
> report_caret reports value + caret and caret-only moves; on the
> editable dropdown the member also hands the completion arithmetic to
> the author (local filter stands down, a pick dispatches without
> touching the field). menus is complete 7/7: MultiAutocomplete filters
> its popup through a real Emacs round trip and splices picks via
> reset_input_ids — the device found both remaining bugs (the catalog
> client hooks never attached on a device boot, latent for
> window.changed too; and §13.6 draft protection correctly blocking the
> splice until the push carried the reset). The fn verb contract is now
> complete: nullary or unary (injected value), return plist = re-push
> arguments.
>
> **Ledger state as of 2026-08-04 (eighth pass, the DX audit) —
> 264/279 built, 15 remain. THE SPRINT IS CLOSED.** The DX pass named
> the idioms the sprint kept writing by hand (jetpacs-bool, spacer
> sizing keywords, jetpacs-m3-defselection), brought the catalog README
> and the widget-reference disclaimer back to the current state, and
> audited every remaining :unsupported reason for truth — which itself
> flipped the two floating-toolbar WithFab samples (the fused FAB is an
> authored node; its tap flips a flag and the next snapshot re-authors
> floating_toolbar_expanded — the reasons predated the flag verb;
> floating-toolbar complete 8/8) and rewrote adaptive's levitated-sheet
> reason around its true remaining gap. The 15 that remain, all with
> audited-true reasons: adaptive ×5 (pane strategies/navigators),
> pull-to-refresh ×3 (G-74 + the indicator slot), tabs two-stiffness
> pair ×2, top-app-bar behavior-argument pair ×2, menus
> MultiAutocomplete (G-51), carousel Fading alpha, floating-toolbar
> scroll-driven collapse. (The lists radio rows this note first
> claimed were already live on the enum_list radio variant — the
> registry, not the note, is the count.) Every gate green: 40 slugs
> m3-check, widgets 68/68, catalog 14/14, theme 22/22, gradle compile +
> :wire:jvmTest, ebp validate (43 frames, 100 widget lines).
>
> **Ledger state as of 2026-08-04 (seventh pass) — 262/279 built, 17
> remain. THE PROTOCOL TIER IS SUBSTANTIALLY DONE.** This pass landed:
> G-80's content_padding half (carousel multi-aspect on a composed
> scrolling row; the snap half was deliberately dropped — its only
> sample landed on the carousel node's uncontained strategy), G-81/82
> (tabs.indicator outline vocabulary + TabItem content/selected_content
> swapped by the device on its live selection — fancy tabs pair live),
> G-75 (scaffold.snackbar_content + button.color — the custom snackbar
> live on the fn verb), G-96..98 (theme.set dynamic/font_scale/
> layout_direction + the three theme-screen rows live), G-77/78
> (window.changed + the welcome window mirror + the scaffold rail slot
> — navigation-suite-scaffold complete 2/2, the swap a real re-push on
> every geometry change), and G-76 (snackbar.show, a REQUEST answered
> with action|dismissed when the snackbar leaves — snackbars complete
> 5/5). Remaining 17: G-51 caret read (menus MultiAutocomplete), G-92
> floating-toolbar-with-FAB (3), G-74 pull-to-refresh progress (2, the
> honest answer stays a canned indicator variant), the top-app-bar
> behavior-ARGUMENT pair (2), lists SingleSelection radio rows (2),
> tabs two-stiffness Container pair (2), carousel Fading alpha (1), and
> the documented-impossible set. Next: the DX/refactor pass, final
> gates and docs.
>
> **Ledger state as of 2026-08-04 (sixth pass) — 255/279 built, 24
> remain. THE SMALL/MEDIUM MEMBER LANE IS CLOSED.** This pass landed,
> in order: G-42/70 (bottom_bar_behavior exit_always + fab_position
> end_overlay — bottom-app-bar 9/9), the toggle checked_shape
> (togglebuttons 10/10), G-66 (surface.shape grew the 34-name
> MaterialShapes vocabulary — material-shapes 1/1), G-39/79/40 (menu
> groups/footer/MenuItem riders + the initial_scroll renderer fix that
> the member had silently lacked — menus 6/6 but MultiAutocomplete),
> G-35 (box.on_long_tap + the m3catalog.fn COMPOUND-mutation verb —
> lists mode-change live), G-44/45 (top_bar_style medium_flexible/
> large_flexible/two_rows + top_bar_centered + the height pair +
> top_bar_expanded node slot — top-app-bar 13/15), and G-63/64/65
> (button shape_role incl. vertical top/bottom caps, checked_icon with
> the IconMap _filled suffix, row/column overlap — button-groups 4/4).
> Still open: the protocol tier (G-51 caret read, G-74, G-76 snackbar
> result, G-77/78 window.changed + rail slot, G-92 toolbar-with-FAB,
> G-96..98 theme.set), the behavior-ARGUMENT pair in top-app-bar
> (PreScrolledLazyColumn, ReverseScrolling pairing), the two
> SingleSelection radio-row lists samples, tabs G-81/82, carousel
> G-80-adjacent, and the documented-impossible set.
>
> **Ledger state as of 2026-08-04 (fifth pass) — 244/279 built, 35
> remain.** G-71/G-72 landed: scaffold.drawer_variant (modal|
> dismissible|permanent, the permanent hamburger suppressed) and the
> rail's closed state loop — expanded is SYNCED authored state,
> on_expand_change reports settles the author did not write, variant
> modal + hide_on_collapse are the two ModalWideNavigationRail forms.
> navigation-drawer complete at 3/3, navigation-rail at 8/8, all three
> rail recreations LIVE on the flag verb. Still open: G-35, G-39/79,
> G-42/70, G-44/45, G-63/65, G-66, G-68, togglebuttons Round, the
> protocol tier, 3 impossible.
>
> Earlier (fourth pass) — 240/279: G-12 and G-69 landed on one shared seam: BodyScrollSignal, a
> CompositionLocal the scaffold provides around its BODY, published by
> the body's scrolling containers (at-start, reverseLayout included,
> always derived on the device) and read by `button.expanded "auto"`
> and `scaffold.fab_hide_on_scroll` — extended-fab complete at 12/12,
> floating-action-buttons at 5/5. The fab-menu hide-on-scroll seam is
> deliberately left open there (the wrap cannot see the menu's local
> expanded state, and hiding an open menu would be worse than not
> hiding). Still open: G-35, G-39/79, G-42/70, G-44/45, G-63/65, G-66,
> G-68, G-71/72, togglebuttons Round, the protocol tier, 3 impossible.
>
> Earlier (third pass) — 235/279: G-61/G-62 landed too: date_button carries the
> SelectableDates predicate declaratively (min_date/max_date/
> disabled_weekdays, 0 = Sunday) and month_grid takes the same
> day-level bounds plus range_start/range_end, shading the span with
> rounded caps — date-pickers complete at 5/5. Still open: G-12+G-69
> (the body-scroll signal seam), G-35, G-39/79, G-42/70, G-44/45,
> G-63/65, G-66, G-68, G-71/72, togglebuttons Round, the protocol tier,
> 3 impossible.
>
> Earlier (second pass) — 233/279: The member lane advanced: G-48 (the sheet slot, both forms —
> bottom-sheet 3/3), G-49 route b + G-41 (the confirm OBJECT and surface
> in the dialog profile — dialogs 3/3, no lookalikes), G-54/G-55
> (enum_list radio + children — radio-buttons 2/2, lists 11/12),
> G-16/G-17 (chips complete at 13/13). The catalog harness also grew
> LIVE sample state: m3catalog.flag flips a named boolean and re-pushes,
> :scaffold may be a function read at build time, and m3catalog.dialog
> raises a registered §18.1 spec — the modal sheet is the first
> recreation whose flow is the real Emacs-owns-the-model round trip.
> Still open in the member lane: G-12 (expanded FABs ×4, wants the
> body-scroll signal seam shared with G-69), G-35 pairing, G-39/79 menu
> groups, G-42/70 (ExitAlways bottom bar), G-44/45 (two_rows ×3),
> G-61/62 (month_grid dates ×2), G-63/65 (connected toggles ×3), G-66
> (MaterialShapes), G-68, G-71/72 (drawer/rails ×3), togglebuttons
> Round ×1; then the protocol tier (G-51/74/76/77/78/92/96..98) and 3
> truly impossible.
>
> Earlier that day — 221/279, 52 node types: The Tier-3 node lane is CLOSED: G-93 `fab_menu` (50th), G-94
> `button_group` (51st) and G-95 `lazy_grid` (52nd) landed, consumed by
> fab-menu 1/1, button-groups 1/4 (the three connected-toggle samples
> still need G-04+G-63/G-65's shared selection and morphing shapes) and
> top-app-bar 10/15 (the reversed grid, with its behavior-state seam
> stated). What remains is the member lane (G-12 expanded FABs, G-16/17
> chips, G-35 pairing, G-39/79 menu groups, G-41/42, G-44/45 two_rows,
> G-48 sheet, G-49 dialogs, G-54/55 radio lists, G-61/62 dates,
> G-63/64/65, G-66 shapes, G-68..G-72) and the protocol tier
> (G-51, G-74/76/77/78, G-92, G-96..98) plus 3 truly impossible.
>
> Earlier, 2026-08-03 (second pass) — 218/279: G-89 `dropdown` (45th), G-91
> `segmented_button` (46th — the node owns the fused seam, so G-64
> negative spacing is no longer needed for it), G-88 `app_bar_row` +
> `app_bar_column` (47th/48th), and G-87 `carousel` (49th, keyline
> strategies multi_browse/uncontained/centered_hero; the Fading and
> MultiAspect samples stay out with corrected reasons). Consumed by
> menus, segmented-button, bottom-app-bar, floating-toolbar,
> top-app-bar (adaptive actions) and carousel recreations. Still open
> among the node types: G-93 fab_menu, G-94 button_group, G-95
> lazy_grid, plus everything in the note below.
>
> Earlier the same day — 206/279: Landed
> since this audit was written, beyond the Tier-1 package it triggered:
> G-26/G-27/G-28/G-29 (scaffold snackbar + refresh members), G-30/G-31
> (both picker display modes incl. `switchable`), G-37/G-56 (checkbox
> stroke + tri-state), G-50/G-52/G-53 (text_input selection, mask+filter,
> content_padding), G-57/G-58/G-59/G-60 (range/vertical/labelled/
> track-icon sliders), G-73 (`is_refreshing`), icon_button `color`
> (Tinted), split_button label→optional (the icon-only leading half),
> tooltip `caret_width`/`caret_height`, `tab_item.tooltip`, and the
> search-bars/tabs/icon-buttons catalog recreations their earlier wire
> work was waiting on. Still open: G-12, G-16/17, G-35 pairing, G-39
> riders, G-41/42, G-44/45 (two_rows), G-48 (sheet), G-49 (dialogs),
> G-51, G-54/55, G-61/62, G-63/64/65, G-66, G-68..G-72, G-74..G-82, and
> the Tier-3 node types G-87/G-88/G-89/G-91..G-95 plus the Tier-4
> protocol members.

The resume of `PLAN-m3-catalog-verification.md`, carried to completion. That
plan verified 12 of 41 components by hand and stopped; this pass triaged
**all 217** `:unsupported` examples at once and rolled the result into a
capability-gap ledger.

## Method

One agent per component group read (a) the module's `:unsupported` entries and
their reason strings, (b) the upstream `@Composable` body of every sample, and
(c) `contract.json` + SPEC §16/§17 + the Kotlin renderer — the renderer being
the ground truth for whether a member is actually *consumed*. Every
"buildable today" verdict then faced an adversarial refuter instructed to
default to refuted. 59 agents, 1194 tool calls.

## Headline

| verdict | count |
|---|---|
| NEEDS_MEMBER — new member(s) on existing node types | 147 |
| NEEDS_NODE — a new node type | 52 |
| NEEDS_PROTOCOL — a new wire message or state channel | 10 |
| FALSE_BLOCKER — buildable on today's 39-node wire | 5 |
| TRULY_IMPOSSIBLE | 3 |

**79 of the 212 reason strings are factually inaccurate.** These are product
text — what a user reads on the "Not supported" screen — so each is a defect,
not a comment nit, exactly as the verification plan held.

## Corrections applied to the triage after review

- The two FAB survivors (`LargeFloatingActionButtonSample`,
  `MediumFloatingActionButtonSample`) are **not** buildable today. Both
  sketches rest on `surface :elevation`, and `LayoutNodes.kt:220-224` passes
  that to `tonalElevation` only, which is a no-op for every background except
  `colorScheme.surface`. A FAB that does not float is not a FAB. Re-marked
  NEEDS_MEMBER against G-67/G-68.
- Independently re-verified before publishing: `text_input.hint` never
  reaches `placeholder=` (G-00), `align_self` is applied nowhere,
  `RenderSurfaceNode` is `tonalElevation`-only, `RenderCard` hardcodes
  `ElevatedCard`, and `IconMap.get` resolves Outlined → AutoMirrored →
  Filled so **no wire string can select a Filled vector**.
- G-00 and `align_self` are **already fixed** (`1917fff`); they needed no
  amendment, being renderer bugs rather than vocabulary gaps.

## Prerequisite already landed

`ed86191` raised material3 1.4.0 → 1.5.0-alpha16. 1.4.0 shipped the design
*tokens* for SplitButton/ButtonGroup/LoadingIndicator/FloatingToolbar/
ToggleButton without their composables, and lacked MaterialShapes and
FloatingActionButtonMenu outright — so ~41 blockers were gated on a
dependency, not on the wire. Tier 3 is only implementable because of it.

## Caveat that bounds this whole document

The Companion has **no Compose UI test infrastructure** — no `ui-test-junit4`,
no `androidTest` source set, and the four `render/` unit tests assert on data,
never on a composition. Every gate in the repo passed while `hint`,
`align_self`, `badge ""` and half of `surface.elevation` rendered nothing.
The ledger below therefore rests on *reading* the renderer. Landing ~98 new
members without a render-assertion harness invites the same rot at scale.

---

# CAPABILITY GAP LEDGER — m3-catalog

**Ranking rule.** Score = (examples in which the gap appears) ÷ cost weight (SMALL=1, MEDIUM=2, LARGE=4). Riders — members that are inert until their parent node type exists — are listed immediately under their parent and carry the parent's dependency, not their own standalone score.

**Verified against ground truth** (not taken from the triage): `Attributes.kt:116-170` (universal set; `align_self` read nowhere), `Renderer.kt:273/337-358` (dispatcher applies `universal`, children get `weight` only), `Renderer.kt:654-775` (scaffold slots, no `nestedScroll`, `PullToRefreshBox` with no `indicator`, `ModalNavigationDrawer` hardcoded at `fillMaxWidth(0.75f)`), `Renderer.kt:410-437` (`OutlinedTextField` unconditional; **no `placeholder=` — `hint` is a dead member**), `InputNodes.kt:75-95/99-114` (`RenderButton` hardcodes 12/8dp pad, 18dp icon, 6dp spacer; `RenderIconButton` always plain `IconButton`), `ContentNodes.kt:345-357` (`progress` = Linear/Circular only), `LayoutNodes.kt:207-226` (`surface.elevation` → `tonalElevation` **only**, never `shadowElevation`), `NodeSupport.kt:34-57` (`surface` in `LAYOUT_NODE_TYPES`, absent from `DIALOG_NODE_TYPES`), `contract.json:16-56/57-78/79-507`.

---

## TIER 0 — no wire change (Companion-only)

### G-00 · `text_input.hint` → `placeholder=` — **RENDERER BUG, NOT A GAP**
- **Shape:** none. `hint` is already in `contract.json:347` `text_input.optional` and `field_types.hint: "string"`.
- **File / API:** `Renderer.kt:410-437` — add `placeholder = { Text(hint) }` to the `OutlinedTextField` call. Zero wire, zero schema.
- **Unblocks:** `text-fields/TextFieldWithPrefixAndSuffix` (co-requisite). **Also repairs an already-shipped example**: `text-fields/TextFieldWithPlaceholder` is `:build` today and renders **no placeholder at all on device** — the one thing it exists to show.
- **Cost:** SMALL. **Deps:** none. **Priority: fix first regardless of ledger order — it is currently shipping a false `:build`.**

---

## TIER 1 — SMALL (a member/enum the renderer already almost does)

### G-01 · `button.size` — score 11.0 (22 appearances) · **widest single win in the ledger**
- **Shape:** `node_schema.button.optional += "size"`; `enums."button.size" = ["xsmall","small","medium","large","xlarge"]`; absent = today's rendering. Unknown-value fallback per SPEC §12 rule 6.
- **File / API:** `InputNodes.kt:75-95` `RenderButton`. Replaces four hardcoded literals with one derived token set: `contentPadding = ButtonDefaults.contentPaddingFor(h)` (today `PaddingValues(12.dp, 8.dp)` at :80), `Modifier.size(ButtonDefaults.iconSizeFor(h))` (today `18.dp` at :83), `ButtonDefaults.iconSpacingFor(h)` (today `6.dp` at :84), `Text(style = ButtonDefaults.textStyleFor(h))` (today unstyled at :86), `Modifier.heightIn(ButtonDefaults.<H>ContainerHeight)`.
- **Unblocks (22):** buttons/`SmallButtonSample`, `XSmallButtonWithIconSample`, `MediumButtonWithIconSample`, `LargeButtonWithIconSample`, `XLargeButtonWithIconSample` (5, sole gap) · split-button/`XSmall`,`Medium`,`Large`,`ExtraLargeFilledSplitButtonSample` (4, with G-08) · togglebuttons/`XSmall`,`Medium`,`Large`,`XLargeToggleButtonWithIconSample` (4, with G-03) · extended-fab/`Small`,`Medium`,`LargeExtendedFloatingActionButtonSample` + `…TextSample` ×3 (6) · extended-fab/`Small`,`Medium`,`LargeAnimatedExtendedFloatingActionButtonSample` (3, with G-12).
- **Cost:** MEDIUM (five stock `ButtonDefaults.*For` calls, no new state). **Deps:** none.
- **Note:** `min_height` is NOT a substitute and the shared size-notes that say "the container height cannot be expressed" are wrong — `Attributes.kt:145-148` really does reach the Button's own modifier. The height is 1 of the 5 tokens; the other 4 are unreachable.

### G-02 · `icon_button.variant` — score 9.0 (9)
- **Shape:** `node_schema.icon_button.optional += "variant"`; `enums."icon_button.variant" = ["filled","tonal","outlined"]`; absent = plain `IconButton`.
- **File / API:** `InputNodes.kt:99-114` — a `when(variant)` block exactly mirroring `RenderButton`'s at :89-94, dispatching to `FilledIconButton` / `FilledTonalIconButton` / `OutlinedIconButton`. With G-09's `checked` present, the same enum selects `Filled/FilledTonal/OutlinedIconToggleButton`.
- **Unblocks (9):** icon-buttons/`FilledIconButtonSample`, `FilledTonalIconButtonSample`, `OutlinedIconButtonSample` (3, sole gap) · `XSmallNarrowSquareIconButtonsSample`, `LargeRoundUniformOutlinedIconButtonSample` (2, with G-08) · `FilledIconToggleButtonSample`, `FilledTonalIconToggleButtonSample`, `OutlinedIconToggleButtonSample` (3, with G-09) · split-button/`ElevatedSplitButtonSample` (1, with G-05).
- **Cost:** SMALL. **Deps:** none.

### G-03 · `progress.variant` += `"linear_wavy" | "circular_wavy" | "loading" | "contained_loading"` — score 8.0 (8)
- **Shape:** `enums."progress.variant"` grows from `["circular","linear"]` to 6 values. No new member: the existing `value` (present ⇒ determinate) already carries both arms.
- **File / API:** `ContentNodes.kt:346-357` `RenderProgress`, one branch each: `LinearWavyProgressIndicator` / `CircularWavyProgressIndicator` / `LoadingIndicator` / `ContainedLoadingIndicator`, `progress = { v }` when `value` present. All ship in material3 under the Companion's compose-bom.
- **Unblocks (8, all sole-gap):** progress-indicators/`LinearWavyProgressIndicatorSample`, `IndeterminateLinearWavyProgressIndicatorSample`, `CircularWavyProgressIndicatorSample`, `IndeterminateCircularWavyProgressIndicatorSample` · loading-indicators/`LoadingIndicatorSample`, `ContainedLoadingIndicatorSample`, `DeterminateLoadingIndicatorSample`, `DeterminateContainedLoadingIndicatorSample`.
- **Cost:** SMALL (four `when` arms). **Deps:** none. **Best effort-to-yield ratio in the ledger.**

### G-04 · `button.checked` + `button.on_change` — score 6.5 (13)
- **Shape:** `button.optional += ["checked","on_change"]`; `field_types.checked: "boolean"` (exists); `on_change` is an ActionDescriptor. Device-held state keyed on the universal `id`.
- **File / API:** `InputNodes.kt:75-95`. Copy `RenderCheckbox`'s state machine verbatim (`InputNodes.kt:185-210`): `rememberSaveable(ctx.surface, id, ctx.epochOf(id))` seeded from `ctx.storeValue(id)` then the authored member; on flip publish `ctx.state(id, JsonPrimitive(it))` **first**, then `ctx.action(onChange, …)`. `variant` then selects `ToggleButton` / `TonalToggleButton` / `OutlinedToggleButton` / `ElevatedToggleButton`.
- **Unblocks (13):** togglebuttons/all 10 · button-groups/`SingleSelectConnectedButtonGroupWithFlowLayoutSample`, `MultiSelectConnected…`, `VerticalButtonGroupSample` (3, with G-06/G-07/G-19).
- **Sole gap for 3:** `ToggleButtonSample`, `TonalToggleButtonSample`, `OutlinedToggleButtonSample`.
- **Cost:** MEDIUM (new device state on a node that has none). **Deps:** none.

### G-05 · `button.variant` += `"elevated"` — score 5.0 (5)
- **Shape:** `enums."button.variant"` gains a fifth value.
- **File / API:** `InputNodes.kt:89-94` — one arm: `"elevated" -> ElevatedButton(onClick, m, enabled, contentPadding = pad) { content() }`; with G-04 present, `ElevatedToggleButton`.
- **Unblocks (5):** buttons/`ElevatedButtonSample` (sole gap), `ElevatedButtonWithAnimatedShapeSample` (with G-06) · togglebuttons/`ElevatedToggleButtonSample`, `ToggleButtonWithIconSample` (with G-04) · split-button/`ElevatedSplitButtonSample` (with G-02).
- **Cost:** SMALL. **Deps:** none.

### G-06 · `button.animate_shape` — score 5.0 (5)
- **Shape:** `button.optional += "animate_shape"`, boolean, default false.
- **File / API:** `InputNodes.kt:89-94` — pass `shapes = ButtonDefaults.shapes()` to whichever variant constructor is chosen, so the container morphs between `shape` and `pressedShape` on press.
- **Unblocks (5):** buttons/`FilledTonalButtonWithAnimatedShapeSample`, `OutlinedButtonWithAnimatedShapeSample`, `TextButtonWithAnimatedShapeSample` (3, sole gap) · `ButtonWithAnimatedShapeSample` (with G-07) · `ElevatedButtonWithAnimatedShapeSample` (with G-05).
- **Cost:** SMALL. **Deps:** none.

### G-07 · `button.shape` — score 3.0 (3)
- **Shape:** `button.optional += "shape"`; `enums."button.shape" = ["round","square"]`, default `round`.
- **File / API:** `InputNodes.kt:89-94` — the Compose `shape` argument (`ButtonDefaults.shape` / `ButtonDefaults.squareShape` = `CornerMedium`/12dp at the 40dp `ButtonSmallTokens.ContainerHeight`). With G-04, `ToggleButtonDefaults.shapesFor(size)`.
- **Unblocks (3):** buttons/`SquareButtonSample` (sole gap), `ButtonWithAnimatedShapeSample` · togglebuttons/`RoundToggleButtonSample` (with G-04).
- **Cost:** SMALL. **Deps:** none.
- **Note:** universal `corner`/`bg`/`clip` genuinely cannot substitute — they decorate the modifier outside `Surface.minimumInteractiveComponentSize()`, i.e. the 48dp touch box, not the 40dp container, and leave the Button's own pill clip/ripple/border intact.

### G-08 · `icon_button.size` + `icon_button.shape` — score 3.5 (7)
- **Shape:** `icon_button.optional += ["size","shape","width_mode"]`; `enums."icon_button.size" = ["xsmall","small","medium","large"]`, `"icon_button.shape" = ["round","square"]`, `"icon_button.width_mode" = ["narrow","uniform","wide"]`.
- **File / API:** `InputNodes.kt:99-114` — `IconButtonDefaults.<size>ContainerSize(width_mode)`, `<size>RoundShape`/`<size>SquareShape`, **and an explicit `Modifier.size(IconButtonDefaults.<size>IconSize)` on the inner `Icon`**, which today is constructed with no size modifier at all (:105-109), so a container-size member alone would not deliver the icon step.
- **Unblocks (7):** icon-buttons/`MediumRoundWideIconButtonSample` (sole gap), `XSmallNarrowSquareIconButtonsSample`, `LargeRoundUniformOutlinedIconButtonSample` (with G-02) · split-button/`XSmall`,`Medium`,`Large`,`ExtraLargeFilledSplitButtonSample` (with G-01).
- **Cost:** MEDIUM. **Deps:** G-02 for two of them.

### G-09 · `icon_button.checked` + `on_change` + `checked_icon` — score 3.0 (6)
- **Shape:** `icon_button.optional += ["checked","on_change","checked_icon"]`; `checked` boolean device-held on the universal `id`; `checked_icon` an identifier.
- **File / API:** `InputNodes.kt:99-114` → `IconToggleButton(checked, onCheckedChange)` (or the Filled/Tonal/Outlined toggle under G-02), same `rememberSaveable` + `state`-before-`action` ordering as `RenderCheckbox`. Gets the M3 expressive checked shape morph free from `IconButtonDefaults.toggleableShapes`.
- **Unblocks (6):** icon-buttons/`IconToggleButtonSample` (sole gap), `FilledIconToggleButtonSample`, `FilledTonalIconToggleButtonSample`, `OutlinedIconToggleButtonSample` (with G-02) · split-button/`FilledSplitButtonSample`, `SplitButtonWithTextSample`.
- **Cost:** MEDIUM. **Deps:** G-02 (3 of them); G-24 for the icon swap.

### G-10 · `card.variant` — score 4.0 (4)
- **Shape:** `node_schema.card.optional += "variant"`; `enums."card.variant" = ["filled","elevated","outlined"]`, default `elevated` (today's behaviour, so no old traffic changes).
- **File / API:** `LayoutNodes.kt:330-345` `RenderCard`, which hardcodes `ElevatedCard(…)` at :334 → `Card` / `ElevatedCard` / `OutlinedCard`.
- **Unblocks (4):** card/`CardSample`, `ClickableCardSample`, `OutlinedCardSample`, `ClickableOutlinedCardSample`.
- **Cost:** SMALL. **Deps:** G-11 (the filled container's token is unnameable without it).

### G-11 · theme roles `surface_container_highest`, `surface_container`, `surface_container_low`, `outline_variant` — score 5.0 (5)
- **Shape:** add to `contract.json` `theme_roles` (and `jetpacs-theme-roles`).
- **File / API:** `ColorModel.kt:54-83` `resolveColorIn` — new arms; `ThemeModel.kt:97-99` must **derive** them from the pushed §18.4 palette (today `surfaceContainerHighest` and `outlineVariant` are never re-derived and stay frozen at the Material baseline, so naming them today either falls through to the `else -> scheme.onSurface` legible fallback or renders a colour that ignores the running Emacs theme).
- **Unblocks:** card ×4 (with G-10) · navigation-rail/`WideNavigationRailCollapsedSample` (with G-58).
- **Cost:** SMALL. **Deps:** none.

### G-12 · `button.expanded` — score 2.0 (4)
- **Shape:** `button.optional += "expanded"`; value `true | false | "auto"`, default `true` when absent.
- **File / API:** `InputNodes.kt:75-95` — `false` drops the label (icon-only FAB); `"auto"` has the Companion derive it from the scaffold body's own scroll state (`LayoutNodes.kt:241` already owns the `LazyListState`), matching upstream's `derivedStateOf` **device-locally so no per-scroll wire traffic is needed**.
- **Unblocks (4):** extended-fab/`AnimatedExtendedFloatingActionButtonSample`, `Small…`, `Medium…`, `LargeAnimatedExtendedFloatingActionButtonSample`.
- **Cost:** MEDIUM. **Deps:** G-01 for three of them.

### G-13 · `chip.variant` — score 3.0 (3)
- **Shape:** `chip.optional += "variant"`; `enums."chip.variant" = ["flat","elevated","input"]`, default `flat`.
- **File / API:** `InputNodes.kt:119-131` — `FilterChip` / `ElevatedFilterChip` / `InputChip` (whose `selected/onClick/label/enabled` shape the node already carries verbatim).
- **Unblocks (3):** chips/`ElevatedFilterChipSample`, `InputChipSample`, `InputChipWithAvatarSample` (with G-16).
- **Cost:** SMALL. **Deps:** none.

### G-14 · `assist_chip.variant` — score 3.0 (3)
- **Shape:** `assist_chip.optional += "variant"`; `enums."assist_chip.variant" = ["flat","elevated","suggestion","elevated_suggestion"]`.
- **File / API:** `InputNodes.kt:133-145` — `AssistChip` / `ElevatedAssistChip` / `SuggestionChip` / `ElevatedSuggestionChip`.
- **Unblocks (3):** chips/`ElevatedAssistChipSample`, `SuggestionChipSample`, `ElevatedSuggestionChipSample`.
- **Cost:** SMALL. **Deps:** none.

### G-15 · `chip.trailing_icon` (+ `assist_chip.trailing_icon`) — score 1.0 (1)
- **Shape:** identifier. Today `icon` is spent on `leadingIcon` (`InputNodes.kt:127`) and no `trailingIcon` argument is passed at all.
- **File / API:** `InputNodes.kt:122-130` — `FilterChip(trailingIcon = { Icon(IconMap.get(name), null, Modifier.size(18.dp)) })`.
- **Unblocks:** chips/`FilterChipWithTrailingIconSample`. **Also repairs a shipped `:build`**: `ChipGroupSingleLineSample` currently drops upstream's per-chip ArrowDropDown.
- **Cost:** SMALL. **Deps:** none.

### G-16 · `chip.avatar` — 1 · **G-17 · `chip.content_spacing`** — 1
- **G-16 shape:** identifier (or §17.2 image form), valid only with `variant:"input"` → `InputChip(avatar = { Icon(…, Modifier.size(InputChipDefaults.AvatarSize)) })` (24dp circular, a distinct slot from the 18dp `leadingIcon`). Unblocks chips/`InputChipWithAvatarSample`. **Deps:** G-13.
- **G-17 shape:** non-negative dp → `FilterChip(horizontalArrangement = FilterChipDefaults.horizontalArrangement(dp))`. Unblocks chips/`FilterChipWithCustomSpacingSample`. **Authoring caveat:** upstream's leadingIcon is null while unselected, so a faithful build must also author `:selected t :icon "done"` or the new member renders invisibly.
- Both `InputNodes.kt:119-131`. **Cost:** SMALL each.

### G-18 · `tabs.style` — score 3.0 (3)
- **Shape:** `tabs.optional += "style"`; `enums."tabs.style" = ["primary","secondary"]`, default `secondary` (preserves today's rendering).
- **File / API:** `LayoutNodes.kt:452-454` — `PrimaryTabRow` / `PrimaryScrollableTabRow` instead of the legacy `TabRow` / `ScrollableTabRow`, keeping the same items/children/`HorizontalPager` wiring; `primary` draws the content-width 3dp rounded indicator.
- **Unblocks (3):** tabs/`PrimaryTextTabs`, `ScrollingPrimaryTextTabs` (sole gap) · `PrimaryIconTabs` (with G-19/G-32).
- **Cost:** SMALL. **Deps:** none.

### G-19 · `tab_item.label` relaxed to optional (or `tab_item.icon_only`) — 2
- **Shape:** SPEC.md:2370 currently makes `label` a MUST on TabItem. Either relax it when `icon` is present, or add `icon_only: boolean`.
- **File / API:** `LayoutNodes.kt:443-449` — pass `text = null` so Material3's `Tab` uses the 48dp icon-only layout. **Authoring `label ""` is not a workaround**: `NodeAccess.kt:30` makes an absent label read as `""`, and `Text("")` still fills the slot and forces the 72dp two-line tab with a blank line.
- **Unblocks:** tabs/`PrimaryIconTabs`, `SecondaryIconTabs` (both also need G-32). **Cost:** SMALL.

### G-20 · `tab_item.icon_position` + `tab_item.badge` — 1
- **Shape:** `enums."tab_item.icon_position" = ["above","leading"]`, default `above`; `badge` string-or-number (same grammar as `icon.badge`), empty string = bare dot.
- **File / API:** `LayoutNodes.kt:443-449` — `LeadingIconTab(text, icon)` instead of `Tab`, and wrap the text in `BadgedBox { Badge { Text(badge) } }`.
- **Unblocks:** tabs/`LeadingIconTabs`. **Cost:** SMALL.

### G-21 · `text_input.variant` — score 3.0 (3)
- **Shape:** `text_input.optional += "variant"`; `enums."text_input.variant" = ["outlined","filled"]`, default `outlined` (the shipped rendering).
- **File / API:** `Renderer.kt:410` — `filled` renders `androidx.compose.material3.TextField`: surfaceContainerHighest container, no outline, focus-thickening bottom indicator, label riding inside rather than notching a border.
- **Unblocks (3):** text-fields/`SimpleTextFieldSample` (sole gap), `TextFieldWithInitialValueAndSelection` (with G-25), `TextFieldWithSupportingText` (with G-22).
- **Cost:** SMALL. **Deps:** none.

### G-22 · `text_input.is_error` + `text_input.supporting_text` — 2
- **Shape:** boolean (default false) + string.
- **File / API:** `Renderer.kt:410-437` — the `isError` and `supportingText` arguments, which are passed today. M3 measures the helper line to the **field's own** measured width (`TextFieldImpl.kt:781/1449`) and tints it with `colors.supportingTextColor(enabled, isError, isFocused)` — which is exactly why a sibling `text` node under the field is not a substitute. `is_error` MUST also set the a11y error semantics from `supporting_text`.
- **Unblocks:** text-fields/`TextFieldWithErrorStateSample` (with G-23), `TextFieldWithSupportingText`. **Cost:** SMALL.

### G-23 · `text_input.max_length` — 2 · **G-24 · `text_input.leading_icon` / `trailing_icon` (+ `trailing_on_tap`) / `clearable`** — 1 · **G-25 · `text_input.prefix` / `suffix`** — 1 · **G-26 · `text_input.hide_keyboard_on_submit`** — 1
- **G-23:** positive integer; refuse committed text past N (paste/IME included, like the `single_line` newline rule) + a11y `maxTextLength`. `Renderer.kt:414-427`. Unblocks `TextFieldWithTransformations` (with G-31), `TextFieldWithErrorState`.
- **G-24:** identifiers in the `leadingIcon`/`trailingIcon` slots; `clearable` renders M3's clear affordance that empties the field **locally** and publishes the resulting `state.changed` — the wire form of `state.clearText()`, which no descriptor can express (the draft lives in `rememberSaveable "ti:surface:id:epoch"`, `Renderer.kt:377-378`, and only an input-reset epoch bump moves it). Unblocks `TextFieldWithIcons`.
- **G-25:** strings in the M3 `prefix`/`suffix` slots, inside the container, never part of `value`/`state.changed`. Unblocks `TextFieldWithPrefixAndSuffix` (with **G-00**).
- **G-26:** boolean; call `LocalSoftwareKeyboardController.hide()` after dispatching `on_submit` inside the `onDone` handler at `Renderer.kt:436`. Today `KeyboardActions(onDone = { submit() })` **suppresses Compose's default hide-on-Done**, so the IME stays up. Unblocks `TextFieldWithHideKeyboardOnImeAction`.
- All `Renderer.kt` `RenderTextInput`. **Cost:** SMALL each.

### G-27 · `scaffold.refresh_indicator` — score 3.0 (3)
- **Shape:** `scaffold.optional += "refresh_indicator"`; `enums."scaffold.refresh_indicator" = ["default","loading","none"]`, default `default`. Requires `on_refresh` present.
- **File / API:** `Renderer.kt:744-759` — the `indicator` slot of the `PullToRefreshBox` already being constructed: `PullToRefreshDefaults.Indicator` vs `.LoadingIndicator`.
- **Unblocks (3):** pull-to-refresh/`PullToRefreshWithLoadingIndicatorSample` · loading-indicators/`LoadingIndicatorPullToRefreshSample` · pull-to-refresh/`PullToRefreshCustomIndicatorWithDefaultTransform` (with G-28 and a Node-valued form).
- **Cost:** SMALL. **Deps:** G-03 for the `loading` value.

### G-28 · `scaffold.snackbar_duration` + `snackbar_dismiss` — 1 · **G-29 · `scaffold.snackbar_max_lines`** — 1
- **G-28 shape:** `enums."scaffold.snackbar_duration" = ["short","long","indefinite"]` + boolean `snackbar_dismiss`. `Renderer.kt:662-670` hardcodes `duration = SnackbarDuration.Short` and never passes `withDismissAction`. `snackbar_dismiss` SHOULD be implied by `indefinite` so such a snackbar always has a user exit. Unblocks snackbars/`ScaffoldWithIndefiniteSnackbar`.
- **G-29 shape:** positive integer → the host's message `Text(maxLines = N, overflow = Ellipsis)`, full string kept as the accessible value. Unblocks snackbars/`ScaffoldWithMultilineSnackbar`. Subsumed by G-53 if that lands instead.
- **Cost:** SMALL each.

### G-30 · `date_button.mode` — 1 · **G-31 · `time_button.display_mode`** — 2
- **G-30:** `enums."date_button.mode" = ["calendar","input"]` → `rememberDatePickerState(initialDisplayMode = DisplayMode.Input)` at `InputNodes.kt:442`. One member, one argument; M3 then supplies its own mask, validation and mode toggle inside the existing dialog and `on_pick` still returns YYYY-MM-DD. Unblocks date-pickers/`DateInputSample`.
- **G-31:** `enums."time_button.display_mode" = ["picker","input","switchable"]` → `TimePicker` vs `TimeInput` inside the dialog `InputNodes.kt:472-486`. `switchable` wants the move from the bare `AlertDialog` to M3's `TimePickerDialog`, which brings `Title(displayMode)` and `modeToggleButton`. The screen-height fallback needs **no** wire member. Unblocks time-picker/`TimeInputSample`, `TimePickerSwitchableSample`.
- **Cost:** SMALL each.

### G-32 · `slider.track` (`default|centered`) — 2 · **G-33 · `slider.color` (+ `color_end`)** — 2 · **G-34 · `slider.thumb_icon`** — 1
- **G-32:** `enums."slider.track" = ["default","centered"]` → `SliderDefaults.CenteredTrack`. `InputNodes.kt:396-425` passes no `track`. Unblocks sliders/`CenteredSliderSample`, `VerticalCenteredSliderSample` (with G-44).
- **G-33:** §16.6 Color → `SliderDefaults.colors(thumbColor = it, activeTrackColor = it)`; `color_end` tints the second thumb only (ignored unless `value_end` present). Unblocks sliders/`SliderWithCustomTrackAndThumbSample`, `RangeSliderWithCustomComponents`.
- **G-34:** identifier → `thumb = { Icon(IconMap.get(name), tint = <slider.color>) }`. `IconMap.get()` is the only path a drawable reaches the device, so a **name**, not a drawing, is the right shape. Unblocks sliders/`SliderWithCustomThumbSample` (with G-43).
- All `InputNodes.kt:378-427`. **Cost:** SMALL each.

### G-35 · `box.on_long_tap` — 1
- **Shape:** ActionDescriptor, optional, on `box`.
- **File / API:** `LayoutNodes.kt:186-204` — swap `Modifier.clickable` for `Modifier.combinedClickable(onClick, onLongClick)`, the identical construction `RenderCard` already uses at :336-338. Today the only nodes carrying a long press draw their own chrome (`ElevatedCard` + 16dp box; `collapsible`'s forced chevron header).
- **Unblocks:** lists/`ListItemWithModeChangeOnLongClickSample`. **Cost:** SMALL. **Note:** the sibling rewrite this sample needs is ordinary EBP (`event.action` → `surface.update` with `reset_input_ids`), not a gap.

### G-36 · `column.reverse_scroll` — 1 · **G-37 · `checkbox.stroke`** — 2 · **G-38 · `switch.thumb_icon`** — 1 · **G-39 · `menu.initial_scroll`** — 1
- **G-36:** boolean; with `scroll:true` pass `reverseScrolling = true` to `verticalScroll` (`LayoutNodes.kt:146-162`, which reads `scroll` as a bare boolean). Unblocks top-app-bar/`EnterAlwaysTopAppBarWithReverseScrolling` (with G-40).
- **G-37:** `{width?: dp, cap?: "butt"|"round"|"square", join?: "miter"|"round"|"bevel"}` → `Checkbox(checkmarkStroke = Stroke(w, cap, join), outlineStroke = Stroke(w))` at `InputNodes.kt:200-209`. Unblocks checkboxes/`CheckboxRoundedStrokesSample`, `TriStateCheckboxRoundedStrokesSample` (with G-46).
- **G-38:** identifier → `Switch(thumbContent = { Icon(…, Modifier.size(SwitchDefaults.IconSize)) })`, drawn only while the **live** `checked` is true (matching upstream's lambda). `InputNodes.kt:228` passes no `thumbContent`. Unblocks switches/`SwitchWithThumbIconSample`.
- **G-39:** `enums."menu.initial_scroll" = ["start","end"]`; `RenderMenu` hoists a `rememberScrollState()`, passes it as `DropdownMenu(scrollState =)` and runs the literal upstream `LaunchedEffect(open) { state.scrollTo(state.maxValue) }`. `InputNodes.kt:160` passes no `scrollState`, so the popup always opens at the top. Unblocks menus/`MenuWithScrollStateSample`.
- **Cost:** SMALL each.

### G-40 · `menu.items[].supporting_text` / `trailing_icon` — 1 (rider on G-52)
- **Shape:** strings/identifiers on the MenuItem record → `DropdownMenuItem(supportingText =, trailingIcon = { Icon(…, Modifier.size(MenuDefaults.TrailingIconSize)) })`. `InputNodes.kt:160-177` passes only text/enabled/onClick/leadingIcon. `trailing_icon` typed string-or-identifier **also recovers the "F11" shortcut the shipped `MenuSample` build drops.**
- **Cost:** SMALL. **Deps:** part of G-52.

### G-41 · advertise `surface` in the dialog profile — 1 (rider on G-49)
- **Shape:** `NodeSupport.kt` — add `surface` to `DIALOG_NODE_TYPES` (today it sits in `LAYOUT_NODE_TYPES`, app-profile only), mirrored in `jetpacs-dialog-node-types`.
- **Why:** `shape` and `elevation` exist on exactly one node, and SPEC §18.1 makes an unadvertised type in a dialog `spec` a whole-dialog 1201 (`Renderer.kt:266-272` degrades it to a bare Column, discarding both). `BasicAlertDialogSample`'s entire subject is the **caller-supplied** `Surface(shape = shapes.large, tonalElevation = AlertDialogDefaults.TonalElevation)`.
- **Unblocks:** dialogs/`BasicAlertDialogSample` (with G-49). **Cost:** SMALL.

### G-42 · `scaffold.fab_position` — 1 (secondary)
- `enums."scaffold.fab_position" = ["end","end_overlay","center"]` → Compose `FabPosition`, `Renderer.kt:702-704`. Unblocks the FAB-overlap half of bottom-app-bar/`ExitAlwaysBottomAppBar`. **Cost:** SMALL.

---

## TIER 2 — MEDIUM (a member needing new Compose plumbing)

### G-43 · `scaffold.scroll_behavior` (top bar) — score 5.5 (11)
- **Shape:** `scaffold.optional += "scroll_behavior"`; `enums."scaffold.scroll_behavior" = ["none","pinned","enter_always","exit_until_collapsed"]`, default `none`.
- **File / API:** `Renderer.kt:675-701` currently draws `top_bar` as a **plain `Row` with `statusBarsPadding`, not an M3 `TopAppBar`, with no `nestedScroll` connection anywhere in the file** — so the bar must first move into a real `TopAppBar`, then `Modifier.nestedScroll(TopAppBarDefaults.<behavior>ScrollBehavior().nestedScrollConnection)` on the `Scaffold`. Entirely Companion-side: **no scroll feedback crosses the wire.** SPEC §17.6's "a bar MUST NOT acquire hidden navigation behavior not declared by its nodes" is exactly why this must be an explicit member and not a default.
- **Unblocks (11):** top-app-bar/`PinnedTopAppBar`, `PinnedTopAppBarWithPreScrolledLazyColumn`, `EnterAlwaysTopAppBar` (3, sole gap) · `EnterAlwaysTopAppBarWithReverseScrolling` (G-36) · `ExitUntilCollapsedMediumTopAppBar`, `…CenterAlignedMediumFlexible…`, `ExitUntilCollapsedLargeTopAppBar`, `…CenterAlignedLargeFlexible…`, `CustomTwoRowsTopAppBar` (5, with G-44) · `PinnedTopAppBarWithReversedLazyGrid` (with G-63) · search-bars/`FullScreenSearchBarScaffoldSample`, `DockedSearchBarScaffoldSample` (with G-59).
- **Cost:** MEDIUM. **Deps:** none.
- **Note:** the pre-scroll half of `PinnedTopAppBarWithPreScrolledLazyColumn` is **already on the wire** — `scroll_here` on child 30 of a `lazy_column` IS `initialFirstVisibleItemIndex = 30` (`LayoutNodes.kt:231-244`).

### G-44 · `scaffold.top_bar_style` + `top_bar_collapsed_height` / `top_bar_expanded_height` — score 2.5 (5)
- **Shape:** `enums."scaffold.top_bar_style" = ["small","medium","large","two_rows"]`, default `small`; heights non-negative dp (64/156 for `CustomTwoRowsTopAppBar`). The style enum carries the M3 defaults; the explicit heights are the escape hatch.
- **File / API:** `Renderer.kt:675-701` — select `TopAppBar` / `MediumTopAppBar` / `LargeTopAppBar` / `TwoRowsTopAppBar` and place the authored `top_bar` node in its title slot, so the Companion owns the collapsed/expanded geometry. Today the bar is drawn in a fixed content-height `Row` — there is no expanded height to collapse *from*.
- **Unblocks (5):** the four ExitUntilCollapsed samples + `CustomTwoRowsTopAppBar`. **Deps:** G-43.

### G-45 · `scaffold.top_bar_expanded` (Node) — 1 (rider on G-44)
- A second Node rendered in the expanded row of a two-rows bar; the Companion cross-fades to the plain `top_bar` node as it collapses. **This carries `CustomTwoRowsTopAppBar`'s "Expanded TopAppBar"→"Collapsed TopAppBar" string swap with no collapse fraction ever crossing the wire** — cheaper than the reporting channel the current reason string implies. `field_types.top_bar_expanded: "node"`. **Cost:** MEDIUM.

### G-46 · `scaffold.floating_toolbar_orientation` + `floating_toolbar_placement` — score 2.5 (5)
- **Shape:** `enums."scaffold.floating_toolbar_orientation" = ["horizontal","vertical"]`, default `horizontal`; `floating_toolbar_placement` over the `box.alignment` vocabulary, default `bottom_center`, plus a `ScreenOffset` inset.
- **File / API:** `Renderer.kt:706-716` — today an unconditional `Surface(tonalElevation = 3.dp, shadowElevation = 4.dp, Modifier.fillMaxWidth())` inside the bottomBar `Column`. Needs to become a placed, wrap-content pill (`VerticalFloatingToolbar` where oriented).
- **Unblocks (5):** floating-toolbar/`ScrollableVertical…`, `CenteredVerticalWithFab`, `ExpandableVertical…`, `OverflowingVertical…`, `VerticalWithFab` (the last three also need G-57/G-64).
- **Cost:** MEDIUM. **Dependency floor:** the Companion's material3 (1.4.0) ships `FloatingToolbarTokens` only — the composable itself arrives in 1.5+, so this gap carries a **library bump**.

### G-47 · `scaffold.floating_toolbar_scroll` (+ `floating_toolbar_exit_direction`) — score 2.0 (4)
- **Shape:** `enums = ["none","exit_always"]`, default `none`; `exit_direction` ∈ `["bottom","top","start","end"]`, default `bottom`.
- **File / API:** `Renderer.kt:705-736` — `FloatingToolbarDefaults.exitAlwaysScrollBehavior(exitDirection)` hung on the Scaffold's `nestedScroll` and offsetting the slot. Companion-local; no device→Emacs signal.
- **Unblocks (4):** floating-toolbar/`ScrollableHorizontal…`, `CenteredHorizontalWithFab` (2, sole gap) · `ScrollableVertical…`, `CenteredVerticalWithFab` (with G-46).
- **Cost:** MEDIUM. **Deps:** G-46 for the vertical pair; same 1.5 library floor.

### G-48 · `scaffold.sheet` + `sheet_peek_height` + `sheet_state` (+ `sheet_skip_partial`, `on_sheet_change`) — score 1.5 (3)
- **Shape:** `scaffold.optional += ["sheet","sheet_peek_height","sheet_state","sheet_skip_partial","on_sheet_change"]`; `field_types.sheet: "node"`; `enums."scaffold.sheet_state" = ["hidden","partial","expanded"]`, default `hidden`.
- **File / API:** `Renderer.kt:654-775` — `BottomSheetScaffold(sheetContent, sheetPeekHeight)` for the persistent form, `ModalBottomSheet` for the modal. **A node slot, not `dialog.show`** — a slot is reachable from an example `:build`; a protocol request is not. Nested scroll from a `lazy_column` inside the sheet to the sheet's own drag comes free with `BottomSheetScaffold`.
- **Unblocks (3):** bottom-sheet/`ModalBottomSheetSample`, `SimpleBottomSheetScaffoldSample`, `BottomSheetScaffoldNestedScrollSample`.
- **Cost:** MEDIUM. **Deps:** none.
- **Also note:** `dialog.style` already enumerates `sheet | sheet_full` (`contract.json:704-708`) and `ebp-client-dialog-show` already sends it — but `MainActivity.kt:127-140` **ignores `style` entirely** and renders every dialog through `androidx.compose.ui.window.Dialog`. That is a Companion gap, not a wire gap, and reason strings claiming a sheet "cannot be requested from Emacs" are wrong.

### G-49 · `dialog` node type (or `confirm` grown to an object) + catalog `:dialog` slot — 3
- **Shape (route a, NEEDS_NODE):** a `dialog` node with addressable `icon` / `title` / `text` / `confirm{label,on_tap}` / `dismiss{label,on_tap}` slots, returnable from a builder. **(route b, NEEDS_MEMBER):** grow the §14.1 `confirm` descriptor field from a bare string (`SPEC.md:1598`) into `{text, title, icon, confirm_label, dismiss_label}` — `ConfirmHost` (`MainActivity.kt:100-115`) already draws a real `AlertDialog` with hardcoded OK/Cancel.
- **Why a node and not `dialog.show`:** `dialog.show` is genuinely implemented and advertised (`surfaces.dialog`), but it is an Emacs→Companion **request**; a sample `:build` is a nullary function returning ONE root node and cannot make one. `dialog.submit`/`dialog.dismiss` are also **no-ops outside a DialogContext** (`CompanionEngine.kt:391-393`) and absent from `APP_BUILTINS`, so a hand-drawn in-body lookalike ships two visibly-enabled dead buttons.
- **Catalog-side co-requisite (not a wire gap):** a `:dialog` entry in `jetpacs-m3-slot-keys` (`jetpacs-m3-core.el:94-101`) + a core verb dispatched through `jetpacs-flow-continue` (the dialog must be raised OUTSIDE the dispatch extent).
- **Unblocks (3):** dialogs/`AlertDialogSample`, `AlertDialogWithIconSample`, `BasicAlertDialogSample` (the last also needs G-41).
- **Cost:** MEDIUM (route b) / LARGE (route a). **Deps:** G-41.

### G-50 · `text_input.selection` (write) — 2 · **G-51 · text_input selection READ channel** — 1
- **G-50 shape:** `[start, end]` non-negative integer character offsets into `value`, `start ≤ end ≤ len`. Seeds the initial `TextRange` only (re-seeded on an input-reset epoch, like `value`). **Requires `RenderTextInput` to hold `TextFieldValue` instead of the bare `String` it holds today** (`Renderer.kt:374-386` → `mutableStateOf(String)` → the `value: String` overload at :410) — the plumbing already exists in `RenderEditor` at `Renderer.kt:467-476`. Unblocks text-fields/`TextFieldWithInitialValueAndSelection` (with G-21), `OutlinedTextFieldWithInitialValueAndSelection` (sole gap).
- **G-51 shape (PROTOCOL):** report the caret with the value — either `selection: {start,end}` added to `state.changed` params (`contract.json:1130-1146`) and to `actions.injections.on_change` (:830-833), or a per-node opt-in `publish_selection: boolean` to keep the bytes off ordinary fields. The wire already owns caret machinery (`edit.caret`, `edit.apply` carry cursor/sel_start/sel_end, `contract.json:1315-1335/1413-1451`) but **only for an `editor` under `editor.sync`**. Unblocks menus/`MultiAutocompleteExposedDropdownMenuSample` (with G-60).
- **Cost:** MEDIUM each.

### G-52 · `text_input.mask` + `filter` — 1 · **G-53 · `text_input.content_padding` (or `dense`)** — 1
- **G-52:** `mask` a display template over the stored value (`"(###) ###-####"`: `#` consumes one stored char, everything else is literal filler that displays but never enters `value`/`state.changed`) rendered as a `VisualTransformation` + `OffsetMapping` — the same seam `Renderer.kt:391` already uses for password/syntax; `filter` an enum `digits|alnum` for the revert. `onValueChange` today applies exactly one transform (the §17.4 newline strip). A round trip is **not** this sample: upstream's point is that filtering and formatting happen locally, per keystroke. Unblocks `TextFieldWithTransformations` (with G-23).
- **G-53:** non-negative dp or the §16.5 `pad` object, passed as the field's **interior** `contentPadding`. Universal `padding` lands on the modifier the widget is composed with, i.e. as margin (`Attributes.kt:129-133`). Implementing it means moving `RenderTextInput` to the `OutlinedTextFieldDefaults.decorator`/`DecorationBox` overload, which is where `contentPadding` lives. `min_height` alone cannot shrink anything — the interior padding still measures ~56dp. Unblocks `DenseTextFieldContentPadding`.
- **Cost:** MEDIUM each.

### G-54 · `enum_list.variant` = `"radio"` — 2 · **G-55 · `enum_list.children`** — 2
- **G-54 shape:** `enum_list.optional += "variant"`; `enums = ["chips","radio"]`, default `chips`. Under `radio` the Companion renders M3 `RadioButton` targets inside `Modifier.selectableGroup()` with `role = Role.RadioButton`, replacing the `FlowRow(FilterChip)` at `InputNodes.kt:306-326` — keeping the identical id/options/value/on_change state path. Unblocks radio-buttons/`RadioButtonSample`, `RadioGroupSample`.
- **G-55 shape:** a Node array parallel to `options`; when present the Companion renders one selectable **row** per option (RadioButton for single-select, Checkbox for multi), the child node as the row body, instead of the chip flow. Each child keeps its own universal attributes, so the segmented `:bg`/per-corner `:corner` the lists module already authors rides straight through. Unblocks lists/`SingleSelectionListItemSample`, `SingleSelectionSegmentedListItemSample`.
- **File:** `InputNodes.kt:245-343`. **Cost:** MEDIUM each. `radio_group` as a separate node type is strictly more surface for the same result and would duplicate `enum_list`'s selection machinery.

### G-56 · `checkbox.state` (tri-state) — 2
- **Shape:** `enums."checkbox.state" = ["off","on","indeterminate"]`, **mutually exclusive with `checked`** (a node carrying both is content-invalid). It changes what `state.changed` carries for that id from a boolean to the enum string, which is why it must be a distinct member and not a widened `checked` — §13.6 draft compatibility keys on the value schema, so a retained boolean draft is incompatible and is erased.
- **File / API:** `InputNodes.kt:184-210` → `TriStateCheckbox(state = ToggleableState.…)`; a click cycles Indeterminate/Off→On→Off, publishes the enum string, then dispatches `on_change` with it in `args.value`.
- **Unblocks (2):** checkboxes/`TriStateCheckboxSample`, `TriStateCheckboxRoundedStrokesSample` (the second with G-37).
- **Cost:** MEDIUM.

### G-57 · `slider.value_end` — 3 · **G-58 · `slider.orientation`** — 2 · **G-59 · `slider.value_label`** — 2 · **G-60 · `slider.track_icon_start` / `track_icon_end`** — 1
- **G-57:** optional number; its **presence** switches `Slider` → `RangeSlider(activeRangeStart = value, activeRangeEnd = value_end)`, and `state.changed`/`on_change` carry a two-number array — already legal traffic (`field_types.value: "varies-per-node"`, and `enum_list` multi-select already publishes a `JsonArray`). Must be legal alongside `values` (`value_end` is a position, not a bound). Unblocks sliders/`RangeSliderSample`, `StepRangeSliderSample`, `RangeSliderWithCustomComponents`.
- **G-58:** `enums = ["horizontal","vertical"]` → M3 `VerticalSlider(reverseDirection = true)`. **Must also stop forcing `.fillMaxWidth()`** — `InputNodes.kt:407/425` applies it unconditionally on both arms and would silently flatten a vertical slider — and honour the universal `height` instead. Unblocks sliders/`VerticalSliderSample`, `VerticalCenteredSliderSample`.
- **G-59:** boolean; while the gesture is in flight the Companion wraps the thumb in M3 `Label`/`PlainTooltip` showing the current position. **Cannot be authored from Emacs**: `InputNodes.kt:399/419` dispatch only at `onValueChangeFinished`, so the intermediate value never leaves the device. Unblocks sliders/`SliderWithCustomThumbSample`, `RangeSliderWithCustomComponents`.
- **G-60:** two identifiers drawn at the leading/trailing edge of each track segment (active tinted `activeTickColor`, inactive `inactiveTickColor`), suppressed when the segment is narrower than the icon — reproduces the sample's `drawWithContent` without the wire ever carrying a `DrawScope`. Unblocks sliders/`SliderWithTrackIconsSample`.
- All `InputNodes.kt:378-427`. **Cost:** MEDIUM each.
- **Correction to the shipped reason on `SliderWithTrackIcons`:** "the wire has no way to hand the Companion a drawing" is false — `canvas` is exactly that. What defeats it is narrower: the canvas op set has no **icon** op and a canvas is not draggable.

### G-61 · `month_grid.min_date` / `max_date` / `disabled_weekdays` (+ the same on `date_button`) — 1
- **Shape:** `min_date`/`max_date` YYYY-MM-DD (min not after max); `disabled_weekdays` an array of 0..6 integers (0 = Sunday), default `[]`. Listed weekdays and out-of-range days render disabled and MUST NOT dispatch `on_day_tap`.
- **File / API:** `VisualizationNodes.kt:298-406` — today `min_month`/`max_month` gate only the prev/next **arrows** (:298, 323, 330) and every in-month cell is clickable whenever `on_day_tap` is present (:363-367); `marks` carry dots 0..3 + colour only (:384-406) so they cannot grey a day. On `date_button`, straight into `rememberDatePickerState(selectableDates = …)` at `InputNodes.kt:442`. A **declarative predicate is the only form the wire can carry** — `SelectableDates` is a Kotlin lambda — and it covers the weekend rule for every navigable month, which a per-date list cannot.
- **Unblocks:** date-pickers/`DatePickerWithDateSelectableDatesSample`. **Cost:** MEDIUM.

### G-62 · `month_grid.range_start` / `range_end` — 1
- **Shape:** YYYY-MM-DD, both-or-neither, start ≤ end, mutually exclusive with `selected`. The Companion shades the inclusive span (including leading/trailing partial weeks) and rounds the two end cells.
- **File / API:** `VisualizationNodes.kt:364/391-392`, which today compares one string per cell. **No new node and no new hook**: `on_day_tap` already dispatches each tapped day, so Emacs builds the range and re-pushes. (`date_range_button` returning `{start,end}` is the alternative — only one is needed.)
- **Unblocks:** date-pickers/`DateRangePickerSample`. **Cost:** MEDIUM.

### G-63 · `button.shape_role` — 3 (rider on G-04)
- `enums."button.shape_role" = ["single","leading","middle","trailing"]` → `ButtonGroupDefaults.connected{Leading,Middle,Trailing}ButtonShapes`, which also supplies the pressed/checked shape morph that the static universal `corner` cannot. Unblocks button-groups/`SingleSelect…`, `MultiSelect…`, `VerticalButtonGroupSample`. **Cost:** MEDIUM. **Deps:** G-04.
- **Note:** the *static* connected radii genuinely do compose today (per-corner `corner` → `RoundedCornerShape`, `Attributes.kt:92-109`, as `jetpacs-m3-split-button--half` already ships). It is the state and the morph that are missing.

### G-64 · `column.spacing` signed, or `column.overlap` — 1
- Either relax SPEC §16.5's non-negative rule for `spacing` (refused on **both** sides today: `jetpacs-widgets.el:760` validates min 0, and `safeDp` at `Attributes.kt:40-41` discards `< 0` before `LayoutNodes.kt:117-118` uses it), or add `overlap: dp` meaning `Arrangement.spacedBy(-overlap)`. Unblocks button-groups/`VerticalButtonGroupSample` (the −6dp interlock). **The same gap blocks the segmented-button track's `Arrangement.spacedBy(-BorderWidth)` seam** (G-71). **Cost:** MEDIUM.

### G-65 · `button.checked_icon` + IconMap filled-variant resolution — 3 (rider on G-04)
- **Shape:** an icon identifier drawn while checked (`icon` stays the unchecked one). **Blocked by a deeper problem than the member:** `IconMap.kt:89-105` resolves `Icons.Outlined` → `automirrored.outlined` → `filled` for **every** name, pre-caches `"edit"` to `Icons.Outlined.Edit` (:30), and all 2075 rows of `M3-ICON-REFERENCE.org` are Outlined — **no wire string can select a filled vector today.** So this gap is really two: the member, plus either a naming convention (`<name>_filled` tried against `androidx.compose.material.icons.filled` first) or an explicit `icon_style: "outlined"|"filled"` selector.
- **Unblocks:** togglebuttons/`ToggleButtonWithIconSample` · button-groups/`SingleSelect…`, `MultiSelect…`. Also the icon half of G-09's four toggle samples. **Cost:** MEDIUM.

### G-66 · universal `shape` attribute (MaterialShapes vocabulary) — 1
- **Shape:** a new entry in `universal_node_attributes`: an identifier from a fixed vocabulary including the 35 `MaterialShapes` (`circle`, `square`, `slanted`, `arch`, `fan`, `arrow`, `semi_circle`, `oval`, `pill`, `triangle`, `diamond`, `clam_shell`, `pentagon`, `gem`, `sunny`, `very_sunny`, `cookie_4_sided`…`pixel_triangle`, `bun`, `heart`). The same names SHOULD be accepted as extra values of `enums."surface.shape"`.
- **File / API:** `Attributes.kt:92-109` — resolve at the point `cornerShape()` is computed, so the existing `clip`/`bg`/`border` all honour it (upstream clips a bare `Spacer`). `MaterialShapes.<Name>.toShape()`; unknown name falls back to the current corner/rectangle behaviour.
- **Unblocks:** material-shapes/`ShapesSample`. **Cost:** MEDIUM. **Note:** `canvas` is a real escape hatch but only a lookalike — `VisualizationNodes.kt:250-261` draws `path` as a straight-segment polyline with no curves, and the vertex data lives in `androidx.graphics.shapes`, not on the wire.

### G-67 · `surface.shadow_elevation` — 2..4
- **Shape:** `surface.optional += "shadow_elevation"`, dp. **`surface.elevation` is a partially-dead member today**: `LayoutNodes.kt:223` binds it to `tonalElevation` only, and M3's `applyTonalElevation` returns the background colour **unchanged** unless it `== colorScheme.surface` — so `:elevation 6` on `:color "primary_container"` changes not one pixel. The only two `shadowElevation` uses in the whole Companion are hardcoded (`Renderer.kt:712`, `EditorToolbar.kt:102`).
- **Unblocks:** floating-action-buttons/`SmallFloatingActionButtonSample` (with G-68) · floating-toolbar/`ExpandableVerticalFloatingToolbarSample` (with G-46). **⚠ It is also the load-bearing hole under two entries the triage marked FALSE_BLOCKER — see the caveat in the totals.**
- **Cost:** SMALL–MEDIUM.

### G-68 · fab container size (`scaffold.fab` size member, or a `fab` node) — 1
- The `fab` slot takes any node (`Renderer.kt:702-704`), but nothing on the wire asks for a FAB **at a size step**. Minimal fix: a `size` enum (`small|default|medium|large`) on whatever occupies the slot. Unblocks floating-action-buttons/`SmallFloatingActionButtonSample`. **Cost:** MEDIUM. **Deps:** G-67.

### G-69 · `scaffold.fab_hide_on_scroll` — 1
- Boolean, default false → wrap the `fab` node in `Modifier.animateFloatingActionButton(visible = <body's first visible index == 0>, alignment = BottomEnd)`, deriving the flag from the body scrollable's own state (`LayoutNodes.kt:231-260`). Entirely device-local, like `on_refresh`'s spinner. Unblocks floating-action-buttons/`AnimatedFloatingActionButtonSample`. **Cost:** MEDIUM.
- **Correction:** "nothing reports firstVisibleItemIndex back to Emacs" is a red herring — upstream derives it locally too. An author-driven `fab_visible` boolean **alone** would NOT recreate the sample (nothing tells Emacs when to flip it) and would be NEEDS_PROTOCOL; the `hide_on_scroll`/`auto` form avoids that.

### G-70 · `scaffold.bottom_bar_behavior` — 1
- `enums = ["pinned","exit_always"]`, default `pinned` → `BottomAppBarDefaults.exitAlwaysScrollBehavior()`'s `nestedScrollConnection` on the Scaffold, offsetting the `bottom_bar` slot by its `heightOffset`. `Renderer.kt:705-736` pins the bar in a plain Surface with no `nestedScroll`. Unblocks bottom-app-bar/`ExitAlwaysBottomAppBar` (with G-42). **Cost:** MEDIUM.

### G-71 · `scaffold.drawer_variant` — 1 · **G-72 · `scaffold.drawer_open` (+ `drawer_width`)** — 2
- **G-71:** `enums = ["modal","dismissible","permanent"]`, default `modal`, meaningful only with `drawer` present. Selects the host around the SAME drawer node at `Renderer.kt:765-774` (today unconditionally `ModalNavigationDrawer` + `ModalDrawerSheet(fillMaxWidth(0.75f))`); `permanent` must additionally suppress the synthesized hamburger at :686-697. Unblocks navigation-drawer/`DismissibleNavigationDrawerSample`.
- **G-72:** boolean, default false — Emacs-authored open state synced to `DrawerState` (open on true, close on false) while still allowing scrim dismissal; `drawer_width` (dp) overrides the hardcoded 75% so a modal **rail** (~220dp) is distinguishable from a modal drawer. Unblocks navigation-rail/`ModalWideNavigationRailSample`, `DismissibleModalWideNavigationRailSample`.
- **Cost:** MEDIUM each.

### G-73 · `scaffold.is_refreshing` — 1
- Boolean, default false, passed to `PullToRefreshBox(isRefreshing =)` at `Renderer.kt:751`, replacing the local flag that **self-clears after a hardcoded 1200ms delay** (:746-750). Keep the local flag as the optimistic default when the member is absent so existing senders are unaffected. Unblocks pull-to-refresh/`PullToRefreshViewModelSample` — Emacs *is* the ViewModel; the other two consumers of `isRefreshing` (`icon_button.enabled`, the list contents) already reach the wire. **Cost:** MEDIUM.

### G-74 · `pull_to_refresh.distance_fraction` (state) + universal `scale` — 2
- **Shape:** a rate-limited continuous gesture-progress channel (0.0..1.0) reported while dragging (SPEC §17.6 currently declares `on_refresh` the ONLY pull-to-refresh signal), plus a universal `scale` (number > 0 or `{x,y}`) applied as `Modifier.graphicsLayer` in `Attributes.kt` — there is no transform attribute at all today.
- **Unblocks (2):** pull-to-refresh/`PullToRefreshScalingSample`, `PullToRefreshCustomIndicatorWithDefaultTransform` (with G-27 in its Node-valued form).
- **Cost:** MEDIUM (protocol). **Honest caveat:** a per-frame round trip over jsonrpc is not a realistic driver; the practical answer for both samples is the canned Companion-side indicator variant under G-27.

### G-75 · `scaffold.snackbar_content` (Node) + `button.color` — 1
- A Node rendered **inside** `SnackbarHost`'s content lambda instead of the default `Snackbar` — the authored subtree draws the container and action while the host keeps M3's animation, timing and dismissal; the plain `snackbar` string stays the message and the accessible text. Rejected as content-invalid if it contains a `scaffold`. `Renderer.kt:674` hardwires `snackbarHost = { SnackbarHost(hostState) }` with no content lambda seam. `button.color` (a §16.6 Color) then carries the sample's error-vs-normal `textButtonColors`. Unblocks snackbars/`ScaffoldWithCustomSnackbar`. **Cost:** MEDIUM. **Deps:** G-28.

### G-76 · event-driven snackbar raise + `SnackbarResult` report — 1
- **Shape (PROTOCOL):** an out-of-band raise carrying message **plus** action label, triggerable against the *current view* of a multi-view surface, and a `SnackbarResult` (`Dismissed`/`ActionPerformed`) reported back. Today `scaffold.snackbar`/`snackbar_action` are static tree members fired by `LaunchedEffect(snackbar)` on compose and keyed on the message string (`Renderer.kt:662`), while the only tap-to-snackbar path (`jetpacs-shell-notify`) carries a bare string and injects only into a scaffold **root** spec — on the catalog's multi_view stack it degrades to `toast.show`.
- **Unblocks:** snackbars/`ScaffoldWithCoroutinesSnackbar`.
- **⚠ Separate finding for the maintainer:** by the same H10 reasoning the **already-supported** `ScaffoldWithSimpleSnackbar` is subtly wrong — its commentary claims the tap returns as `scaffold.snackbar`, but on this multi_view surface it returns as a toast. **Cost:** MEDIUM.

### G-77 · `window.changed` message + welcome mirror — 3
- **Shape (PROTOCOL):** Companion→Emacs notification (states SYNCING/READY, capability `core`), params `{surface, width_dp, height_dp, width_class, height_class}` with `enums."window.size_class" = ["compact","medium","expanded"]`; re-sent on rotation/fold/resize and **mirrored once in the `auth.response` welcome** so the FIRST snapshot can already be authored for the right class. Nothing reports geometry today: the welcome members (`SPEC.md:1079-1096`), the §20.1 device report (`SPEC.md:3320-3363`) and the whole Companion→Emacs method set (`session.superseded`, `state.changed`, the `edit.*` family) carry no display metric.
- **Unblocks (3):** top-app-bar/`SimpleTopAppBarWithAdaptiveActions` · navigation-suite-scaffold/`NavigationSuiteScaffoldSample`, `NavigationSuiteScaffoldCustomConfigSample` (the latter needs **both** axes — it tests `windowHeightSizeClass == COMPACT` too).
- **Cost:** MEDIUM. **Deps:** G-78 for the nav-suite pair.

### G-78 · `scaffold.rail` slot (+ `rail_type`) — 2
- Node slot, sibling of `bottom_bar`, laid on the start edge as a vertical navigation rail beside `body`; `enums."scaffold.rail_type" = ["collapsed","expanded"]` (with the bar side covered by the existing `bottom_bar`, optionally widened by a `medium` value) for `WideNavigationRailCollapsed` vs `Expanded` vs `ShortNavigationBarMedium`. Once the width class is known, Emacs fills either `bottom_bar` or `rail` from the same items — which is precisely the swap `NavigationSuiteScaffold` performs. **The rail's item arrangement needs nothing new**: `column.arrange "center"` already maps to `Arrangement.Center` (`LayoutNodes.kt:110-119`). Unblocks navigation-suite-scaffold ×2. **Cost:** MEDIUM. **Deps:** G-77.

### G-79 · `menu.groups` + `menu.items[].checked` / `checked_icon` + `menu.footer` — 1
- `groups`: array of `{label, items: MenuItem[]}`, mutually exclusive with the flat `items` → `DropdownMenuGroup(shapes = MenuDefaults.groupShape(i, n))` with `MenuDefaults.Label` + `HorizontalDivider`, spaced by `MenuDefaults.GroupSpacing`. `checked` is **authored** presentation state exactly like `chip.selected` (Emacs flips it on the next snapshot) → `DropdownMenuItem(checked =, onCheckedChange =)` — **no new state channel**. `footer`: a Node rendered inside the popup below the groups (the conditional ButtonGroup). Unblocks menus/`GroupedMenuSample`. **File:** `InputNodes.kt:150-180`. **Cost:** MEDIUM. **Deps:** G-40.

### G-80 · `row.snap` + `row.content_padding` — 1
- `enums."row.snap" = ["none","start","center"]`, default `none`, meaningful only with `scroll:true` → `rememberSnapFlingBehavior` over the row's scroll state; position stays Companion-local presentation state like tabs' page. `content_padding` (dp) applies **inside** the scroll viewport as `PaddingValues` so it scrolls with the content — unlike the universal `padding`, which `RenderRow` applies before appending `horizontalScroll` (`LayoutNodes.kt:122-143`).
- **Unblocks:** carousel/`HorizontalUncontainedCarouselSample` — **the only carousel sample that is a member away rather than a node away**, because the 186dp fixed item size and the static extraLarge maskClip are already universal `width`/`height`/`corner`/`clip`. **Cost:** MEDIUM.

### G-81 · `tabs.indicator` — 1 · **G-82 · `tab_item.content` (Node)** — 1
- **G-81:** `{kind: "underline"|"outline", color?: Color, inset?: dp}` → an indicator that strokes a `RoundedCornerShape(5.dp)` border inset from the selected tab's bounds, still animated by the standard `tabIndicatorOffset`. `LayoutNodes.kt:452-454` calls TabRow with only `selectedTabIndex`. **A bounded vocabulary, not an arbitrary composable** — it reproduces the picture, not the API. Unblocks tabs/`FancyIndicatorTabs`.
- **G-82:** a Node rendered in Material3 `Tab`'s trailing content slot in place of text/icon (`Tab(selected, onClick) { RenderNode(content) }`), `label` staying required as the accessibility name. `LayoutNodes.kt:440-450` reads an item as two strings and nothing else. Unblocks tabs/`FancyTabs`. **Note:** `pager_only` is not an escape hatch — with it the strip isn't drawn, and the Tab's own `onClick` is the ONLY path that changes the pager page, so a hand-built row of tappable boxes could never drive it.
- **Cost:** MEDIUM each.

---

## TIER 3 — LARGE (a whole node type, usually with device-held state)

### G-83 · `tooltip` node type — score 3.25 (13) · **largest single-component win**
- **Shape:** `node_types += "tooltip"`; `node_schema.tooltip = {required: ["children"], optional: ["text","title","action","persistent","position","caret","caret_width","caret_height","shown"]}`. `children` is the **anchor**, wrapped exactly as `badge` wraps its children in a `BadgedBox` (`ContentNodes.kt:268-281`).
- **File / API:** a new `RenderTooltip` (ContentNodes.kt or a new file) + a dispatcher arm at `Renderer.kt:275-322` + `APP_NODE_TYPES` in `NodeSupport.kt`. `TooltipBox(tooltip = { PlainTooltip { Text(text) } }, state = rememberTooltipState()) { children }` — long-press/hover raises it, it times out, **and the anchor's own `on_tap` is untouched.**
- **Riders (all SMALL once the node lands):**
  - `position`: `enums = ["above","below","left","right","start","end"]`, default `above` → `TooltipDefaults.rememberTooltipPositionProvider(TooltipAnchorPosition.*)`. **`left`/`right` are ABSOLUTE sides and must stay distinct from `start`/`end`** — the existing `align_self`/`box.alignment` enums are direction-relative only and model no such thing. (7 examples)
  - `caret`: boolean → `PlainTooltip(caretShape = TooltipDefaults.caretShape())`. (9 examples)
  - `caret_width`/`caret_height`: non-negative dp, both-or-neither, valid only with `caret:true` → `caretShape(DpSize(w,h))`. (2)
  - `title` + `action {label, on_tap}` + `persistent`: presence of title-or-action switches to `RichTooltip` and passes `hasAction`; `action` reuses the **exact `label-on-tap-object` field type already in `field_types` for `scaffold.snackbar_action`** (`contract.json:596`); `persistent` → `rememberTooltipState(isPersistent = true)`. (4)
  - `shown`: boolean, default false. Authored presentation state exactly like `collapsible.collapsed` — false→true on an accepted snapshot calls `TooltipState.show()`, true→false calls `dismiss()`. **No new action descriptor is needed for programmatic show**: an ordinary `surface.update` carries it. (2)
- **Unblocks (13):** tooltips/all 13. **Plus 2 more via `tab_item.tooltip`** (`PlainTooltip` in a `TooltipBox` around a Tab): tabs/`PrimaryIconTabs`, `SecondaryIconTabs` (with G-18/G-19).
- **Cost:** LARGE (node) + SMALL riders. **Deps:** none.
- **Reason-string corrections owed:** "the wire's only transient surface is the scaffold snackbar slot" is false (`dialog.show`, `toast.show`, `pie_menu.show` are all Emacs-raised transient presentation), and "[the snackbar] has no action button" is flatly false (`snackbar_action` is rendered and dispatched at `Renderer.kt:666-669`). `dialog.dismiss` also *is* a builtin that dismisses a popup; only the **show** half is descriptor-less.

### G-84 · `split_button` node type — score 1.5 (6)
- **Shape:** `{leading: {label?, icon?, on_tap}, trailing: {icon, checked, on_change}, variant, size}` → `SplitButtonLayout`.
- **Why a node and not just `icon_button.checked`:** the two visuals the family exists to show — `SplitButtonDefaults.TrailingButton`'s checked shape morph and the 180° `animateFloatAsState` `rotationZ` on the KeyboardArrowDown — are **renderer behaviour**, not attributes. Eleven of twelve upstream samples carry `checked`; the one that doesn't is the one already built.
- **Unblocks (6):** split-button/`SplitButtonWithDropdownMenuSample`, `TonalSplitButtonSample`, `OutlinedSplitButtonSample`, `SplitButtonWithIconSample` (4, sole gap) + `FilledSplitButtonSample`, `SplitButtonWithTextSample` (also satisfiable by G-09). Cheaper alternative for all 11: G-09 + G-01/G-08 + G-05/G-02.
- **Cost:** LARGE. **Note:** the **fused geometry composes today** (`jetpacs-m3-split-button--half` + per-corner `corner`), so every reason string claiming "no split_button node to fuse the two halves" is wrong and should be reworded to name the checked state.

### G-85 · `pane_scaffold` node type — score 1.75 (7)
- **Shape:** named pane children — `list` + `detail` (+ `extra`) for the list-detail form, `main` + `supporting` (+ `extra`) for the supporting form, each a Node; optional `id` so the pane navigator is Companion-local presentation state under §16.1; optional `on_pane_change` (the newly active role injected as `args.value`).
- **File / API:** new render file + `Renderer.kt` dispatcher + `NodeSupport.kt`. `NavigableListDetailPaneScaffold` / `SupportingPaneScaffold`; the Companion computes `calculatePaneScaffoldDirective` from **its own** window.
- **Key finding:** **`window.changed` (G-77) is NOT a prerequisite.** The adaptation is Companion-side inside the node — Emacs authors every pane once and never learns the width, exactly as `tabs` owns its page and `collapsible` its expansion. That is a strictly smaller ask than the shipped reason strings imply.
- **Riders:** `pane_expansion {anchors:[{proportion}|{offset_start}|{offset_end}], initial_index, drag_handle}` → `PaneExpansionAnchors` + `VerticalDragHandle`, settled anchor kept device-local (1 example); `adapt_strategy {role: "hide"|"reflow"|"levitate"{alignment, scrim, only_if_single_pane, docked_edge, drag_to_resize}}` (2); `back_behavior` enum of the four `BackNavigationBehavior` values, the node consuming back **while its own pane history is non-empty** and only then letting it fall through to the surface's view stack (1); `on_pane_change` (1..2).
- **Unblocks (7):** adaptive/all 7.
- **Cost:** LARGE. **Deps:** none.

### G-86 · `navigation_rail` node type (or a leading-edge scaffold slot) — score 1.5 (6)
- **Shape:** `{items: [{icon, label, selected?, badge?, on_tap}], expanded?, header?: Node, arrangement?: "top"|"center"|"bottom", modal?, hide_on_collapse?, on_expand_change?}` → `WideNavigationRail` / `ModalWideNavigationRail`, the Companion owning the expand/collapse animation so a header tap toggles locally.
- **Minimal alternative:** a leading-edge, full-height scaffold slot alongside `bottom_bar`, which the Companion wraps in the rail container colour and window insets — **exactly how `bottom_bar` already works** (`Renderer.kt:717-733` supplies `Surface(color = surfaceContainer, fillMaxWidth)` inside `Box(navigationBarsPadding())`). That is why the navigation-**bar** module ships from composed items and the rail cannot.
- **Two supporting wire gaps that block even a hand-composed stand-in:**
  - **no height-filling member anywhere**: `fill` on row/column and `fill_fraction` are `fillMaxWidth`-**only** (`LayoutNodes.kt:125-151`, `Attributes.kt:149-150`), despite the neutral name;
  - **`align_self` is a dead member**: declared in `universal_node_attributes` and validated in elisp (`jetpacs-widgets.el:213-215`), but read **nowhere** in the Kotlin — `Attributes.kt:6`'s comment claims the containers apply it and `RenderRow/ColumnChildren` (`Renderer.kt:337-358`) apply `weight` alone. **This is a `badge ""`-class latent bug worth filing on its own.**
- **Unblocks (6):** navigation-rail/`WideNavigationRailResponsiveSample`, `WideNavigationRailCollapsedSample`, `WideNavigationRailExpandedSample`, `WideNavigationRailArrangementsSample`, `NavigationRailSample`, `NavigationRailBottomAlignSample`. **Deps:** G-11 (rail container colour).
- **Cost:** LARGE.
- **Reason-string correction:** "no node carries a WideNavigationRailItem's selected state or the active indicator" is false — the indicator is `:bg` + `:corner`, as `jetpacs-m3-navigation-bar.el:98-131` already ships, and `chip.selected` exists. Replace with the rail-node / full-height / leading-edge / container-colour argument.

### G-87 · `carousel` node type — score 1.25 (5)
- **Shape:** `{children: Node[], strategy: "multi_browse"|"uncontained"|"centered_hero"|"multi_aspect", preferred_item_width?, item_width?, item_spacing?, content_padding?, id?, on_item_tap?}`. The Companion runs all keyline math and the per-frame mask; **Emacs supplies content only and never learns the width.**
- **Riders:** `item_mask {corner: number|Corner, border?}` applied to the item's **live** mask rect (the wire form of `maskClip`/`maskBorder`), overridable per child (2 examples); `item_overlay` (a Node pinned to the mask rect, fading with mask coverage — declarative intent for the `graphicsLayer{alpha=lerp(...)}` the fading sample is named for; **Emacs can declare it but can never compute it**, since no message reports per-frame geometry) (1).
- **Unblocks (5):** carousel/`HorizontalMultiBrowseCarouselSample`, `HorizontalCenteredHeroCarouselSample`, `FadingHorizontalMultiBrowseCarouselSample`, `CarouselWithShowAllButtonSample`, `MultiAspectCarouselLazyRowSample`.
- **Cost:** LARGE. **Note:** everything in `CarouselWithShowAllButtonSample` **except** the carousel already composes (text button, two-column grid via lazy_column-of-weighted-rows, back nav) — the node is the only missing piece.

### G-88 · `app_bar_row` / `app_bar_column` (measuring overflow container) — score 1.0 (4)
- **Shape:** `{children: Node[], max_item_count?: integer, overflow?: MenuItem[]}` — or equivalently an `overflow` member on `row`/`column` naming an icon (`"more_vert"`).
- **File / API:** `LayoutNodes.kt` — the Companion measures children in order at layout time, renders those that fit inline, and moves the remainder into a `DropdownMenu` opened by a trailing overflow IconButton, each item's `content_description` supplying the label (AppBarRow's `clickableItem` shape). **`AppBarColumnKt`/`AppBarRowKt` already ship in the Companion's material3 1.4.0** — this is a node amendment, not a dependency bump.
- **Unblocks (4):** top-app-bar/`SimpleTopAppBarWithAdaptiveActions` (alternative to G-77, and the one that needs no new message) · bottom-app-bar/`BottomAppBarWithOverflow` · floating-toolbar/`OverflowingHorizontal…`, `OverflowingVertical…` (the latter also G-46).
- **Cost:** LARGE. **Deps:** none.
- **Why a static split is not it:** four icon_buttons plus a `menu` reproduces one width's screenshot and never reflows — and on a full-width band under zero width pressure it reads as a plain "more" menu, i.e. the opposite of the condition that causes overflow.

### G-89 · `dropdown` node type (ExposedDropdownMenu) — score 0.75 (3)
- **Shape:** `{id, options: [{label, value}], value?, label?, hint?, editable?, on_change?, enabled?}` → `ExposedDropdownMenuBox { TextField(modifier = menuAnchor(PrimaryEditable|PrimaryNotEditable), readOnly = !editable, trailingIcon = ExposedDropdownMenuDefaults.TrailingIcon(expanded)); ExposedDropdownMenu { options.map { DropdownMenuItem } } }`, publishing `state.changed` + `on_change` with the picked value.
- **Why:** `RenderMenu` (`InputNodes.kt:150-160`) is `Box { IconButton; DropdownMenu }` — the popup can only hang off **its own** anchor icon; `RenderTextInput` has no `menuAnchor` and no `read_only` (`enabled:false` greys the field, which is not readOnly). `M3-COMPONENT-LOOKUP.org:83,142-146` already proposes exactly this type.
- **Rider:** `dropdown.options[].spans` — a `RichSpan[]` alternative to the plain label (the §17.2 span record is already on the wire), so the underlined subsequence match is expressible; MenuItem labels are plain strings (`SPEC.md:2426`) and only rich_text/table cells take spans.
- **Unblocks (3):** menus/`ExposedDropdownMenuSample`, `EditableExposedDropdownMenuSample`, `MultiAutocompleteExposedDropdownMenuSample` (the last also G-51).
- **Cost:** LARGE. **Correction:** the per-keystroke filter rebuild is **not** a wire gap — `Renderer.kt:414-427` already fires `state.changed` + `on_change` on every keystroke, so Emacs can legitimately re-push a filtered menu per character.

### G-90 · `search_bar` node type — score 0.75 (3)
- **Shape:** `{id, value?, hint?, leading_icon?, trailing_icon?, presentation?: "full_screen"|"docked", on_query_change?, on_search?, children}` where `children` are the result rows shown only while expanded. The Companion holds `SearchBarValue` Collapsed/Expanded device-locally (like `collapsible`), renders `SearchBarDefaults.InputField` collapsed and `ExpandedFullScreenSearchBar` / `ExpandedDockedSearchBar` open (the docked arm owning the measure-to-field-width layout), and swaps the leading icon to a back affordance while expanded. Publishes `state.changed` for the query so Emacs can push filtered children.
- **Unblocks (3):** search-bars ×3 (two also need G-43).
- **Cost:** LARGE. **Correction to the module commentary:** the full-screen and docked samples' InputFields differ materially (the full-screen one carries a Search↔ArrowBack leading icon and a Mic trailing IconButton; the docked one passes only a placeholder), so the "they'd be the same row of icon buttons twice" argument does not hold — the verdict survives on the expansion, not the comparison.

### G-91 · `segmented_button` node type — 2
- **Shape:** a single-choice/multi-choice connected track: per-segment `checked` + `on_change` device state with an `id`, `selectableGroup()` + `Role.RadioButton` semantics, `SegmentedButtonDefaults.itemShape(index,count)`, the `Icon(active)` check crossfade, and the fused seam.
- **Three distinct missing pieces, only one of which is geometry:** (a) live single-choice selection on a track (no container node has `selected`; `enum_list` renders FlowRow(FilterChip)); (b) **the fused seam** — `Arrangement.spacedBy(-BorderWidth)` + `interactionZIndex`, unaskable because `row.spacing` is validated ≥ 0 in elisp **and** `safeDp` rejects negatives, so adjacent 1dp borders double to 2dp (see G-64); (c) the `Role.RadioButton` selection semantics.
- **What is NOT missing, contrary to the shipped reason:** the start/middle/end shape math — per-corner `corner` expresses it exactly (`Attributes.kt:92-109`). **The reason string asserting "the only shape member on the wire is surface's rounded/rounded_small/circle enum" is false and must be rewritten.**
- **Unblocks (2):** segmented-button/`SegmentedButtonSingleSelectSample`, `SegmentedButtonMultiSelectSample`. **Cost:** LARGE. **Deps:** G-64.

### G-92 · floating-toolbar rail node w/ attached FAB — 3
- **Shape:** a toolbar node that collapses **horizontally toward a retained trailing FAB**, carrying `expanded` plus the FAB as one unit, at a free placement over the body.
- **Two independent holes:** (a) no node collapses along the horizontal axis toward a retained element — `collapsible` is hard-coded vertical, always `fillMaxWidth()`, and always prepends a rotating `keyboard_arrow_down` chevron (`LayoutNodes.kt:367-390`), with no member to suppress it or reverse direction; (b) **no tap on a child can drive a sibling's or ancestor's Companion-local presentation state** — every interactive node dispatches to Emacs, and an `icon_button` inside a collapsible's header **swallows the tap** before the header row's `clickable` sees it, so "the FAB toggles the toolbar" has nothing to ride on. The sample's second driver, `floatingToolbarVerticalNestedScroll`, is the same missing scroll signal.
- **Unblocks (3):** floating-toolbar/`HorizontalFloatingToolbarWithFabSample`, `VerticalFloatingToolbarWithFabSample`, `ExpandableVerticalFloatingToolbarSample`. **Cost:** LARGE. **Deps:** G-46, G-67; material3 1.5 floor.

### G-93 · `fab_menu` / toggle-FAB node type — 1
- A checkable FAB carrying `expanded`/`checked` with an Add→Close icon morph, whose menu items unfold **above** it at BottomEnd. `collapsible` is the only device-local expander and it hard-codes the chevron, stacks children below, and offers no spacing/alignment for the items. Unblocks fab-menu/`FloatingActionButtonMenuSample`. **Cost:** LARGE. **Deps:** G-69 for the hide-on-scroll half.

### G-94 · `button_group` node type — 1
- `{children: Node[], overflow?: MenuItem[], spacing?: dp}` → M3 `ButtonGroup` so the press animation couples neighbours, moving what does not fit into an overflow menu at measure time. **Emacs must never be asked to compute the split.** Unblocks button-groups/`ButtonGroupSample`. **Cost:** LARGE. **Deps:** overlaps G-88.

### G-95 · `lazy_grid` node type — 1
- `{children: Node[], columns?: integer, min_item_width?: dp (GridCells.Adaptive), reverse?: boolean, spacing?, content_padding?}` → `LazyVerticalGrid`, preserving array order and honouring `scroll_here` like `lazy_column` (`LayoutNodes.kt` has only `RenderLazyColumn`). Unblocks top-app-bar/`PinnedTopAppBarWithReversedLazyGrid`. **Cost:** LARGE. **Deps:** G-43 (and the Companion must derive `isScrollingContentAtStart` including the reverseLayout case device-side — never ask Emacs).

---

## TIER 4 — protocol members outside the 212 (core ThemePicker rows)

### G-96 · `theme.set.dynamic` — boolean on the existing `theme.set` notification → `dynamicLight/DarkColorScheme()` at `ThemeModel.kt:134`, falling back to baseline where unavailable. **Emacs cannot supply this as `colors` — the palette derives from the device wallpaper, which never reaches Emacs.** Clears core/ColorMode's Dynamic third. **Cost:** SMALL.
### G-97 · `theme.set.font_scale` — number 0.4..2.0, absent = follow device → `CompositionLocalProvider(LocalDensity provides Density(density, fontScale))` in `EbpTheme` (`ThemeModel.kt:124-146`), so every text node scales together. A per-node member would be the wrong shape. Clears core/Font scale. **Cost:** SMALL.
### G-98 · `theme.set.layout_direction` — `["ltr","rtl"]`, **absent = follow system**, deliberately mirroring the tri-state `dark` established by amendment #36 rather than inventing a third convention → `CompositionLocalProvider(LocalLayoutDirection)`. Every existing `pad.start/end`, row `arrange start/end`, column `align start/end` then mirrors for free. Clears core/Text direction. **Cost:** SMALL.
- core/**Theme (System/Light/Dark)** is a **FALSE BLOCKER**: `theme.set`'s `dark` is sent **by Emacs** (`ThemeModel.kt:129-132` — a real boolean forces polarity, only its *absence* falls through to `isSystemInDarkTheme()`), and `jetpacs-theme-mode` already spells the three-way choice. The row's reason inverts the direction of control. Buildable today with one `pcase` arm on the existing `m3catalog.pref` verb.

---

## TOTALS

| Tier | Contents | Blockers cleared | Cumulative |
|---|---|---|---|
| **Today** | no wire change at all | **3** | 3 |
| **Tier 0** | G-00, a pure Companion bug fix | 0 new (**repairs 1 shipped `:build`**) | 3 |
| **Tier 1** | every SMALL member/enum (G-02..G-42 + the SMALL riders) | **52** | 55 |
| **Tier 2** | + every MEDIUM member/protocol (G-01, G-43..G-82) | **+97** | 152 |
| **Tier 3** | + every LARGE node type (G-83..G-95) | **+57** | 209 |
| **Never** | TRULY_IMPOSSIBLE | 3 | 212 |

**Buildable TODAY with no wire change: 3 of 212** — and only **one is uncontested**:
- ✅ navigation-drawer/`PermanentNavigationDrawerSample` — M3's `PermanentNavigationDrawer` *is* a Row of (sheet, content) with no DrawerState; `row` + universal `width 240` + `weight 1` + a `surface` with omitted `shape` (= RectangleShape, exactly `PermanentDrawerSheet`'s) covers it, and the module already owns the item builder. Two traps: the sheet column must **not** carry `:scroll t` (the Example screen already wraps the body in a scrolling column and nested `verticalScroll` throws), and `--item`'s hardcoded `:key` should take a prefix argument.
- ⚠️ floating-action-buttons/`LargeFloatingActionButtonSample`, `MediumFloatingActionButtonSample` — **these two FALSE_BLOCKER verdicts are unsound.** Both sketches rest on `(jetpacs-surface … :color "primary_container" :elevation 6)`, and the refutation of their own sibling `SmallFloatingActionButtonSample` proves that member dead: `LayoutNodes.kt:223` passes it to `tonalElevation` only, and `applyTonalElevation` returns the colour unchanged for every background except `colorScheme.surface`. A FAB that does not float is not a FAB. **Recommend: re-mark both NEEDS_MEMBER against G-67 + G-68, giving 1 buildable today and 205 needing wire work.**

**Truly impossible (3):** tabs/`FancyIndicatorContainerTabs`, tabs/`ScrollingFancyIndicatorContainerTabs` (a `tabIndicatorLayout` measure lambda driving two per-edge `Animatable`s at differential spring stiffnesses — no declarative member can name a spring spec or a measure policy), pull-to-refresh/`PullToRefreshSampleCustomState` (implementing the `PullToRefreshState` *interface* in Kotlin — code-level extensibility).

### Recommended build order (effort-weighted)
1. **G-00** (free, and stops a shipping false `:build`), then **G-03** (8 examples, four `when` arms) and **G-02** (9 examples, one `when` block).
2. **G-01** (22 appearances) and **G-04** (13) — the two members that dominate the whole catalog.
3. **G-43** (11) — but note it requires first moving `top_bar` from a plain `Row` into a real M3 `TopAppBar`, which is prerequisite work for G-44/G-45 too.
4. Sweep the remaining SMALL enums (G-05..G-42): ~30 more examples for roughly a week of one-liners.
5. Only then the node types, cheapest-first: **G-83** (tooltip, 15 examples incl. two tabs) → **G-85** (pane_scaffold, 7) → **G-86** (navigation_rail, 6) → **G-84** (split_button, 6) → **G-87** (carousel, 5) → **G-88** (app_bar_row, 4).

### Cross-cutting defects surfaced by this pass (file separately)
- **`align_self` is a declared, elisp-validated, never-read member.** `contract.json:57-78` + `jetpacs-widgets.el:213-215` accept it; `Attributes.kt:6` claims the containers apply it; `Renderer.kt:337-358` applies `weight` and nothing else. Same class as `badge ""`. Blocks any leading-edge placement.
- **`surface.elevation` is half-dead** (tonal only; discarded for every colour but `surface`) — G-67.
- **`text_input.hint` is fully dead** — G-00.
- **`IconMap` resolves Outlined before Filled for all 2075 names** (`IconMap.kt:89-105`, `"edit"` pre-cached to Outlined at :30) — **no wire string can select a filled vector**, which silently blocks every Outlined→Filled checked-icon swap — G-65.
- **`ScaffoldWithSimpleSnackbar` (shipped `:build`) is subtly wrong** on this multi_view surface: `jetpacs-shell-notify` injects only into a scaffold **root** spec, so the tap degrades to a toast, not the `scaffold.snackbar` its docstring claims — G-76.
- **`dialog.show`'s `style` (`dialog|sheet|sheet_full`) is sent by Emacs and ignored by the Companion** (`MainActivity.kt:127-140` always uses `androidx.compose.ui.window.Dialog`). Several reason strings claim the sheet "cannot be requested from Emacs"; it can — it just isn't honoured.