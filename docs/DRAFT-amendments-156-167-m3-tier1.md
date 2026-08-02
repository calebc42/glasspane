# DRAFT amendments #156–#167 — the m3-catalog Tier 1 package

Drafted 2026-08-02 against `ebp/SPEC.md` @ `83d6e08` (amendments through **#141**
applied on this branch; SPEC-CHANGES rows run to **#152**). Source audit:
[AUDIT-m3-blockers-2026-08-02.md](AUDIT-m3-blockers-2026-08-02.md), gaps
G-01..G-42. Tree: `llm-poc-2` @ `16e8dd1`, branch `m3-fidelity`; `ebp/` on its
own `m3-fidelity` branch.

**These are drafts for ratification, not applied edits.** Each gives (a) the
`SPEC-CHANGES.md` row ready to paste, (b) the exact normative `SPEC.md` edits,
(c) the `contract.json` / goldens artifact delta, (d) the Companion
implementation site, and (e) the catalog examples it unblocks. The `Ratified`
column is the maintainer's.

## Numbering

`#149` is held at Caleb's direction. `#153` (extension conformance) and
`#154`/`#155` (the `ebp.data` module, ratified and applied at `ebp` `37fb456`)
are pre-authored on the **rf-4a** line and unpushed. This package therefore
opens at **#156**. If the rf-4a stack lands first, no renumbering is needed —
the ranges are disjoint by construction.

## What this package is for

The m3-catalog is a faithful re-creation of
`Compose-Material-3-Expressive-Catalog`: 41 components, 279 examples. 212 of
those examples are `:unsupported` — the wire cannot express what the sample
exists to demonstrate. The audit triaged all of them and ranked the gaps by
examples-unblocked per unit of cost.

**This package is Tier 1: the SMALL gaps — members and enum values the
renderer already almost does. Ratifying all twelve clears 52 of the 212.**
Tier 2 (MEDIUM members, ~97 more) and Tier 3 (the ~15 new node types, ~57
more) follow as separate packages. Three examples are unreachable by any
declarative member and are documented as such.

## Prerequisite already landed

`ed86191` raised the Companion's material3 from **1.4.0** (BOM-managed,
unpinned) to **1.5.0-alpha16**, the version the catalog's upstream pins. 1.4.0
shipped the design *tokens* for SplitButton, ButtonGroup, LoadingIndicator,
FloatingToolbar and ToggleButton without their composables, and lacked
`MaterialShapes` and `FloatingActionButtonMenu` outright. The bump compiles on
the existing Kotlin 2.1.10 / AGP 9.1.1 with zero renderer changes; 699 Kotlin
tests green. Several amendments below name APIs that exist only because of it.

The five adaptive artifacts Tier 3 will need
(`material3.adaptive:{adaptive,adaptive-layout,adaptive-navigation}`,
`material3-adaptive-navigation-suite`, `material3-window-size-class`) were
separately probed: they resolve and compile clean. They are deliberately NOT
added yet — nothing consumes them until their amendments are drafted.

## Two conditions the ratifier should weigh before signing

**1. Every enum in this package is unenforced by every gate in the repo.**
`contract.json`'s `enums` block is read by *nothing*: `validate.py` never
mentions it, neither generator projects it, and `Vocabulary.kt` records
`"keyboard" to "enum"` — the string "enum" as a type name — never the value
set. A golden carrying `{"t":"button","variant":"bogus"}` validates clean
today. These twelve amendments add roughly twenty enums, and on landing all of
them are prose. The value sets are load-bearing for §12 rule 6's
unknown-value fallback, which cannot be conformance-checked while nothing
knows the known values. The fix is ~15 lines in `validate.py` (look up
`enums["<t>.<member>"]` for each present member of each golden node) and would
retroactively cover the 19 entries already there.

**2. No new member can be render-asserted.** The Companion has no Compose UI
test infrastructure — no `ui-test-junit4`, no `androidTest` source set, and the
four `render/` unit tests assert on data, never on a composition. This is the
direct cause of the defect class the audit found: `text_input.hint`,
`align_self`, `badge ""` and half of `surface.elevation` each passed every gate
while rendering nothing. Two are fixed in `1917fff`; the pattern is not.
Per the agreed ordering, implementation lands before tests — so this is
recorded as a known condition of the package, not a precondition of it.

## Design decisions requiring a maintainer call

Collected from the individual drafts; each is also stated in place with its
A/B table. The drafts are written as option A throughout.

## Status of this revision

> ⚠ **Revision 1, RECHECK INCOMPLETE.** These twelve were drafted, adversarially
> reviewed (16 P1 defects found, every one cited), and revised against those
> findings — **149 findings applied, 23 rejected with evidence**. The
> confirmation pass that would prove each P1 is *gone from the text* rather than
> merely acknowledged **did not run**: all twelve recheck agents died on a usage
> limit. Treat the verbatim `SPEC.md` quotes and the artifact deltas as
> **unconfirmed** until that pass completes.

## What ratifying all twelve actually clears

| # | title | clears | decisions | findings applied | findings rejected |
|---|---|---|---|---|---|
| #156 | button expressive geometry | **12** | 4 | 15 | 1 |
| #157 | icon_button expressive geometry | **6** | 6 | 12 | 1 |
| #158 | toggle state on button and icon_button | **3** | 5 | 13 | 0 |
| #159 | the wavy and loading progress variants | **8** | 6 | 12 | 2 |
| #160 | card variants and the surface-container theme roles | **4** | 3 | 11 | 2 |
| #161 | the chip family | **8** | 5 | 10 | 2 |
| #162 | tab presentation | **3** | 6 | 11 | 2 |
| #163 | the text field family | **5** | 4 | 17 | 2 |
| #164 | scaffold chrome refinements | **1** | 5 | 16 | 4 |
| #165 | picker display modes | **2** | 9 | 14 | 3 |
| #166 | slider presentation | **2** | 5 | 9 | 1 |
| #167 | assorted input and layout members | **3** | 9 | 17 | 3 |
The raw sum is 57, but examples shared between amendments are double-counted;
the honest distinct total is lower and is stated per amendment below. These
counts are **already corrected downward** by the review: #158 fell from a
claimed 19 to 3, #164 from 4 to 1, #167 from 7 to 3, once the reviewers proved
the claimed examples were blocked by something else as well.

The audit's Tier 1 estimate of 52 was optimistic for exactly that reason. A
smaller true number is the deliverable; a larger false one is the defect.

## Design decisions requiring a maintainer call

Sixty-seven, collected from the twelve drafts. Each is also stated in place
with its A/B table, and every draft is written as option A throughout.

- **#156** — D1 — does button.variant gain a stated safe fallback to `filled` alongside its fifth value `elevated`? A (recommended, drafted): unrecognized variant falls back to filled, matching InputNodes.kt:93's `else -> Button(...)`, so `elevated` degrades on a pre-#156 Companion. B: keep §16.1's implied whole-surface 1201 rejection, making `elevated` unemittable until every deployed Companion carries #156, with no enum-value discovery channel in the welcome to gate on. A is strictly a loosening — a third-party Companion that DID reject becomes non-conforming on ratification day.
- **#156** — D2 — the wire name `size` collides with field_types.size = "dp", which SpecValidator.checkScalarFieldType (SpecValidator.kt:467-497) keys on the bare member name, so {"t":"button","size":"medium"} throws `size must be a finite number` today. A (recommended, drafted): keep `size`, demote field_types.size to varies-per-node, restate icon.size's dp check as a dedicated validator arm — pays the cost once for G-08's icon_button.size too. B: rename the member `size_class`, leave the type table alone, no §17.1 carve-out and no Kotlin arm, at the price of diverging from M3's vocabulary forever. Note the Companion has no Compose UI test infrastructure, so nothing in the repo can assert what the demoted-and-restored check renders.
- **#156** — D3 — scope of button.size: A (recommended, drafted) ButtonDefaults tokens in every position, including inside scaffold.fab, which Renderer.kt:728-730 hands straight to RenderNode as a plain Button; or B, the same member additionally selecting FloatingActionButtonDefaults when the node occupies the fab slot, which would claim the ledger's six extended-fab unblocks now at the cost of one member meaning two token families depending on where its node sits. Under A those six belong to G-68 and G-01's honest score is ~8.0/16, not the ledger's 11.0/22.
- **#156** — Whether to bump the amendment number. SPEC-CHANGES.md's highest row on this branch is 152; #153-#155 are unratified and live on the rf-4a line. The draft keeps 156 and states the dependency, but the ratifier may prefer to reassign at merge.
- **#157** — D1 — the member name `size`. Keep `size` (qualify §17.1, project `varies-per-node`, accept that `icon.size` loses its SpecValidator finite-number check until the Companion arm lands) or rename to `size_step` (no §17.1 edit, no §24.4 loosening, but diverges from upstream, from the ledger, and from the `button.size` G-01 will ask for). This is now a disclosed §24.4 loosening, which raises the stakes on A.
- **#157** — D2 — five steps (`xsmall`…`xlarge`, matching the alpha16 classpath and G-01's button scale) or the ledger's literal four (`xsmall`…`large`).
- **#157** — D3 — whether `variant` spells its own default as a fourth value `standard` (parallel to `button.variant` naming `filled`) or stays at G-02's three with the default unnamed and unauthorable.
- **#157** — D4 — whether the generic `validate.py` `check_enum_values` arm lands with this amendment (verified green on the corpus and verified to bite) or is deferred, leaving four vocabularies with zero in-repo enforcement.
- **#157** — D5 (new, surfaced by review finding 6) — whether `width_mode` may ride this amendment at all. It is beyond G-08 as ledgered. Dropping it drops `MediumRoundWideIconButtonSample` and the honest unblocks count goes 6 → 5.
- **#157** — Unresolved risk the maintainer should weigh, not a menu choice: `extraSmallContainerSize`, `IconButtonWidthOption`, and the ten shape getters are `@ExperimentalMaterial3ExpressiveApi` on a 1.5.0-alpha library and have already churned once since 1.4.0. A SPEC vocabulary minted from alpha words can be stranded without a deprecation cycle. And the Companion has no Compose UI test infrastructure, so nothing in the repo can assert that `size:"large"` renders a 96 dp container — every geometry claim here rests on reading InputNodes.kt, IconButton.kt, and javap output.
- **#158** — #158-D1 — what a toggle tap dispatches. A (drafted): exactly one action per tap, `on_change` when present else the required `on_tap`. B: `on_tap` always, `on_change` additionally. A is recommended; its only real cost, now stated in the amendment, is that `on_tap` becomes the first REQUIRED member in the vocabulary that is unreachable in a legal configuration, mitigated by §17.1's hidden-action rule.
- **#158** — #158-D2 (implicit in A, ratify together) — `checked` without a universal `id` is LEGAL and non-stateful (authored presentation, the chip.selected model) rather than 1201 content-invalid. Requiring `id` would invalidate a previously valid CORE message and trip §25's first classification bullet (protocol major). Golden line 76 pins this arm.
- **#158** — Scope asymmetry a ratifier may want to close: `checked_icon` lands on `icon_button` (G-09) but not on `button` (G-65). It is one more optional identifier and one more branch in the existing `content` lambda at InputNodes.kt:81-88. Folding it in would not clear any further example on its own, because G-65's real blocker is that no wire string can select a filled vector (IconMap.kt:89-105 resolves outlined -> automirrored -> filled for every name).
- **#158** — Batch-wide sweep still owed: `checked` is today an ignored unknown field on button/icon_button (§16.3, §12 rule 1), so any sender already emitting it starts rendering a toggle after ratification. A grep of emacs/ found no such sender, but the risk class applies to every additive-member amendment in this batch.
- **#158** — material3 1.5.0-alpha16 is an ALPHA and every toggle entry point used here is @ExperimentalMaterial3ExpressiveApi. The wire members are toolkit-independent; the two InputNodes.kt renderers are pinned to signatures that may move before 1.5.0 stable (androidx tip-of-tree already renames TonalToggleButton -> FilledTonalToggleButton and ToggleButtonDefaults.shapes() -> shapesFor()).
- **#159** — DD-1 — four `progress.variant` enum values (drafted, A) vs. a new `loading_indicator` node type (B). Ratifying A overrules jetpacs-m3-loading-indicators.el:12-13's own commentary ('a new component, not a new option on an old one') in the same change; B costs node_types + core_node_set + node_schema + a coverage golden + NodeSupport + regeneration of both vocabulary mirrors, and turns an unadvertised node into a whole-surface 1201 under §16.2 where A degrades to a spinner.
- **#159** — DD-2 — leave the four expressive values ungated (drafted, A, per §22.4's 'over-accept' definition) vs. register a `progress.expressive` constraining feature and widen §22.4 to admit fidelity-only advertisements (B). Without B, Emacs has no positive way to learn the wave/morph was actually drawn, and all eight examples ship `:build` on any pre-1.5 Companion drawing a plain spinner — the false-`:build` class the audit headlines. Mitigated only out-of-band: one Companion, on 1.5.0-alpha16 since ed86191.
- **#159** — Whether to accept an unasserted landing. The Companion has no Compose UI test infrastructure; four new `when` arms land with zero test that anything draws, and a typo in a variant string would pass every gate in the repo and silently render a circular spinner. Recorded as a standing caveat in the draft, not resolved by it.
- **#159** — Whether `ebp/validate.py` should grow a generic `<t>.<member>` enum arm. contract.json's `enums` block is read by nothing today, and growing this one 2 → 6 makes an unpinned artifact more load-bearing; the only mechanical guard on the six values anywhere is the hand-kept list at emacs/jetpacs-widgets.el:695, outside `ebp/`. That arm is its own amendment, not this one.
- **#159** — Ordering: #159 must be ratified before G-27's draft (`scaffold.refresh_indicator`), whose `"loading"` value is defined by this enum (audit :222).
- **#159** — Alpha-API exposure: all four composables are @ExperimentalMaterial3ExpressiveApi in 1.5.0-alpha16. The wire enum will outlive the alpha; the four `progress = { … }` call sites are the only breakage surface if the signatures move before 1.5.0 stable.
- **#160** — D1 — where the derived container ramp tops out: surface_container_highest = the pushed surface_variant (endpoint of the existing 0.25/0.5/0.75 series, drafted) vs a sub-endpoint stop ~0.85. Verified numerically: baseline light SurfaceContainerHighest #E6E0E9 vs SurfaceVariant #E7E0EC (near-identical); baseline dark #36343B vs #49454F (clearly distinct), so A collapses that distinction in dark polarity.
- **#160** — D2 — how much of the container ramp the wire names: the four roles the ledger scoped (drafted, leaves surfaceContainerHigh derived-but-unnameable) vs the complete five-stop ramp.
- **#160** — D3 (NEW, from the P1 findings) — whether the derivation gate applies to the three ALREADY-SHIPPING stops as well as the two new ones. A (drafted) gives one rule the SPEC can state literally and protects the switch track, at the price of changing the reorderable drag chrome and the bottom_bar surface under a colors map that pushes neither surface role (frames.golden index 20 is the corpus example: dark #3B3740 -> #2B2930 and #2D2A32 -> #211F26). B leaves the three alone and gates only the new two, at the price of two rules in one function and a 18.4 sentence too loose to state either.
- **#161** — D1 — `input` as a third `chip.variant` value (A, drafted) vs. a new `input_chip` node type (B). Unresolved and NOT severable from the unblocks count: route B strikes `InputChipSample` and `InputChipWithAvatarSample`, dropping this amendment from 8 to 6, and it sets a per-Material-variant node-type precedent that repeats at G-01, G-02, G-05, G-10, G-14 and G-21.
- **#161** — D2 — `chip.avatar` typed as an identifier through `IconMap` (A, drafted) vs. the §17.2 image form (B). A is recommended; the member is named `avatar` rather than `avatar_icon` so B stays available later as a widening, not a rename.
- **#161** — D3 — a member whose selected variant has no slot: reject `1201` (A, drafted) vs. ignore (B). Now governs THREE combinations, not two, after the icon/avatar precedence finding.
- **#161** — D4 (NEW, forced by the P1 `field_types` finding) — `trailing_icon` is typed `identifier` GLOBALLY by this amendment, because `field_types` is a flat bare-name map and cannot express node scoping. G-40 wants MenuItem `trailing_icon` to carry the shipped MenuSample's "F11" shortcut, i.e. string-or-identifier. Either G-40 renames its member, or it widens this entry and every chip loses the free `IDENTIFIER` + `MAX_IDENTIFIER_OCTETS` check. The ratifier should settle the NAME in this batch rather than at G-40.
- **#161** — D5 (NEW, forced by the P2 non-negativity finding) — `content_spacing` projects as `non-negative-dp` while the six members that share its §17.1 sentence (`size`, `spacing`, `run_spacing`, `content_padding`, `elevation`, `thickness`) still project as `dp` and are still unchecked for sign. Retyping those six is a separate amendment: it changes rejection behaviour for members outside this node family. The ratifier should confirm the asymmetry is acceptable as an interim state rather than have this amendment widen it silently.
- **#162** — G-19 shape A vs B (relax `label` to optional + `content_description`, versus keep `label` a MUST and add `icon_only: boolean`). The A/B table is retained verbatim; the draft is written as A. The P1 fix strengthens A's case — under B the accessible name falls out of `label` for free, whereas A now has to carry an explicit §17.3 MUST — but B still institutionalizes a declared-then-discarded member. Still Caleb's call.
- **#162** — `content_description` on `TabItem` is beyond G-19's literal ledger shape (AUDIT:190-193). After the P1 finding it is no longer merely nice-to-have: without it an icon-only tab's only accessible name is the icon identifier, which §16.4 calls "a fallback of last resort, not a substitute". A ratifier may still want it split into its own row.
- **#162** — Whether the `secondary` branch should migrate from `TabRow`/`ScrollableTabRow` to `SecondaryTabRow`/`SecondaryScrollableTabRow`. Deferred here (no Compose render-test harness can prove the swap is a no-op), leaving two spellings of one picture in one function.
- **#162** — The two shipped badge readers (`ContentNodes.kt:258-260`, `InputNodes.kt:100,110-112`) drop a numeric badge entirely and fold `badge: ""` into absence, both contrary to `field_types.badge` = `string-or-number`. Per the P2 finding this is now explicitly OUT of #162 and needs its own numbered amendment carrying a §25 classification, because fixing it changes what two currently-valid documents render.
- **#162** — Golden line index 75 is only correct against today's 00-74 corpus (`wc -l ebp/goldens/widgets.golden` = 75). Sibling amendments in this batch append to the same file; whoever lands second renumbers their own new line and its `chk` string, never an existing one.
- **#162** — Pre-existing and untouched: `CompanionEngine.kt:854-855` comments that `tabs.items` is "deliberately absent" from `NODE_ARRAY_MEMBERS` while `"items"` is in fact in the set (:856). The walk is still correct — it gates on `stringOrNull("t") != null` (:928) and TabItems carry no `t` — but anyone auditing the new TabItem members against that walker will trip on the stale comment.
- **#163** — #163-D1 keyboard dismissal shape: A (drafted) `text_input.hide_keyboard_on_submit: boolean`, now also raising the platform submit action so it works with no `on_submit`, vs B a new §14.2 builtin `companion.keyboard.hide` usable from any ActionDescriptor. The review's objection to A — that the one caller wants the purely local form — is answered by the new clause, not by argument; A now recreates TextFieldSamples.kt:326-334 exactly. B remains more general and addable later without retracting A.
- **#163** — #163-D2 does an enforcement member ship now: A (drafted) `max_length` announces only, enforcement deferred to the G-52 amendment where upstream chains it with the digits filter, vs B add `enforce_max_length` (default false) now with revert-in-full semantics mirroring MaxLengthFilter.transformInput. A is recommended; under A the TextFieldWithTransformations :unsupported string stays true, under B it must be rewritten.
- **#163** — #163-D3 (new) do `is_error` and `max_length` ship at all: after the correction they clear zero catalog examples, since TextFieldWithErrorState needs a further, unfiled gap. A ship all eleven (they are two of the three pieces that gap will need, and `is_error` is half of supporting_text's colour contract), vs B ship nine and defer them to the amendment that files the counter gap. A is recommended, with the zero-caller status stated in the commit message so it is a recorded choice — this codebase was just burned by `hint`, which shipped declared, validated and read by nobody under a green gate.
- **#163** — A new gap must be filed for TextFieldWithErrorState before it can clear: a supporting-text slot that takes a Node (upstream's is a Row with a Spacer and a live counter) plus locally-derived per-keystroke error state. The ledger runs to G-98 and has no id for it, and AUDIT-m3-blockers-2026-08-02.md:209 and :212 must be corrected — they claim G-22 and G-23 clear it.
- **#164** — Decision 1 (unchanged, still open): does `snackbar_duration: indefinite` IMPLY the dismiss affordance (A, drafted — the standing 'MUST be dismissible by the user' then holds at every duration, at the cost of an authored `snackbar_dismiss: false` being overridden), or is the affordance authored-only with `indefinite` alone rejected 1201 (B)?
- **#164** — Decision 2 (unchanged, still open): are `refresh_indicator` / `fab_position` INERT without `on_refresh` / `fab` (A, drafted — matches `snackbar_action` without `snackbar`), or co-requisite like `empty_state`'s action_label/on_tap, rejecting the surface 1201 (B)? The ledger's G-27 line asserts B ('Requires `on_refresh` present'), and under B a surface that drops `on_refresh` in one snapshot while leaving `refresh_indicator` in place becomes a whole-surface 1201 — a rejection class no other scaffold member has, and one the m3-catalog would hit while switching examples.
- **#164** — NEW, raised by this revision: is the Emacs harness work (jetpacs-scaffold, jetpacs-chrome-screen, jetpacs-m3-slot-keys, the jetpacs-m3--example-slots `:on-refresh` exemption) in scope for THIS amendment, or split into a companion harness change? The single cleared example depends on it; if it splits out, this amendment's honest unblocks count is 0 and everything it clears moves behind that split.
- **#164** — NEW: the `enums` block is decorative — nothing in the tree reads it. Ratifier should decide whether to keep projecting closed vocabularies into a block no tool consumes, or to make `validate.py` / `gen-vocabulary.py` actually read it (a separate, larger amendment). This amendment only declines to CLAIM enforcement.
- **#164** — NEW: amendment number 164 is unverifiable against this tree (SPEC-CHANGES.md max is 152; only #153/#154/#155 are otherwise accounted for). Confirm the m3 batch's allocation or renumber at merge.
- **#165** — Keep `date_button.mode` at all? Its honest catalog yield is now ZERO examples (DateInputSample is inline, so it needs a month_grid-shaped member #165 does not open). It still closes a real wire gap — Emacs cannot choose which display the dialog opens on — for one argument. Keep (drafted) or defer to whenever the inline gap is filed. Decision table 1.
- **#165** — Member naming: asymmetric `date_button.mode` / `time_button.display_mode` (drafted, matches ledger G-30/G-31) vs. one `display_mode` name on both with disjoint per-node ranges. Moot if decision 1 defers the date member. Decision table 2.
- **#165** — `switchable` as a third value of `time_button.display_mode` (drafted) vs. a two-value `display_mode` plus a boolean `time_button.mode_toggle`. Decision table 3.
- **#165** — THE ONE THAT MOVES PIXELS: whether RenderTimeButton may move off the bare AlertDialog onto M3's TimePickerDialog for ALL three values. `switchable` needs the modeToggleButton slot, which only TimePickerDialog has; doing it unconditionally gives every EXISTING default time_button an M3 dialog headline (TimePickerDialog's `title` parameter has no default), shape and container colour. Legal under §16.4, visible to any user. The alternative forks the renderer: AlertDialog for `picker`, TimePickerDialog for `input`/`switchable`, at the cost of two dialog shapes for one node. Decision table 4.
- **#165** — The height fallback is now a MAY, not a MUST, so the shipped build stays conforming — but that means a Companion may silently substitute the text form and nothing on the wire or in any gate can observe it. If the ratifier wants it binding, it has to land WITH the Companion change and the reference implementation has to be the proof, because there is no render assertion in this repo.
- **#165** — Whether `mode` and `display_mode` should be projected into `field_types` at all. I dropped them (dead in both validators, and `mode` is a very generic global name — the #66/#82 trap). If the ratifier reads §17.1's 'These definitions … MUST be projected together into contract.json' as covering enum-valued members, then the projection convention is wrong for eight other members too and that is a separate, larger amendment.
- **#165** — The unfiled gap: DateInputSample needs typed date entry on the INLINE node. The ledger has no G-id for it (G-61 is selectable-dates, G-62 is ranges). Someone has to assign one before the date-pickers module can reach 5/5.
- **#165** — Pre-existing and adjacent: `var show by remember` at InputNodes.kt:435 and :464 is not rememberSaveable, so both picker dialogs close on rotation. Ratifying #165 puts a mode toggle inside a dialog that still cannot survive a configuration change. Separate fix, but the ratifier should decide whether it rides along.
- **#165** — Amendment number 165 was assigned by the orchestrator. SPEC-CHANGES.md on this branch ends at #152 (line 112) and #154/#155 are pre-authored on rf-4a; 153 and 156-164 are assumed reserved by sibling drafts in this batch and were NOT verified from any file.
- **#166** — Colour granularity (Design Decision 1): A = one `slider.color` tinting thumb + active track together plus `color_end` for the second thumb (2 members, matches the house 'a node's color is its accent' pattern and the exact `SliderDefaults.colors(thumbColor = X, activeTrackColor = X)` call the catalog makes) vs B = `color` (thumb) + `track_color` (active track) + `color_end`, which reproduces `RangeSliderWithCustomComponents`' blue/red/green and `SliderWithCustomThumbSample`'s red-icon-on-default-track exactly, at the cost of a third member and a per-part colour vocabulary no other node type has. Drafted as A; B remains a clean later addition.
- **#166** — Land `color_end` now as legal-but-inert (A, drafted) or defer it to G-57's amendment (B). Under A nothing in any suite can catch a Companion that mis-implements it until G-57 lands, and G-57 must route it through `RangeSlider`'s `endThumb` slot with a second `SliderColors` object.
- **#166** — Neither `track`, `color`, `color_end` nor `thumb_icon` has any observable wire effect, and the Companion has no Compose UI test infrastructure: every MUST in the new SPEC text ('MUST NOT defeat the disabled affordance', 'MUST still present a grabbable thumb', 'MUST NOT become the accessible label') is unenforced by CI on ratification day. Ratify knowing that.
- **#166** — `thumb_icon "favorite"` resolves to `Icons.Outlined.Favorite` because `IconMap.get` tries Outlined before Filled (IconMap.kt:93-98); upstream `SliderWithCustomThumbSample` draws `Icons.Filled.Favorite`. No wire string can select a Filled vector. Not fixable inside this amendment.
- **#166** — `@OptIn(ExperimentalMaterial3ExpressiveApi::class)` on `RenderSlider` would be the first expressive opt-in in the Companion, pinning it to an alpha API (`CenteredTrack-7LSsfP0`) that a later alpha may rename or re-signature.
- **#167** — The MenuItem trailing slot: two typed members (`trailing_icon` + `trailing_text`, mutually exclusive) versus one string-or-identifier member. Drafted as A; B is unimplementable without a new IconMap.getOrNull, since IconMap.kt:89-106 returns Icons.Outlined.HelpOutline for any unresolved name. A/B table retained in the amendment.
- **#167** — NEW, forced by the P1 finding: authoring `supporting_text` on any item opts the WHOLE menu into the M3 expressive item layout (different content padding, a required per-position Shape, an animated container). A = per-menu branch with MenuDefaults.leadingItemShape/middleItemShape/trailingItemShape/standaloneItemShape and one geometry throughout a popup (drafted); B = per-item branch, which renders one popup in two geometries; C = defer `supporting_text` to G-79, which needs the expressive path anyway, and land only `trailing_icon`/`trailing_text` here at zero rendering risk. C is the conservative option and would leave this amendment's unblocks count unchanged at three. A/B/C table is in the amendment; Caleb picks.
- **#167** — `reverse_scroll` is scoped to `column` only, not `row`, though horizontalScroll takes the same reverseScrolling parameter and the extension is free. Say if you want `row.reverse_scroll` in this landing rather than a later one-line amendment.
- **#167** — `switch.thumb_icon` is drawn only while the live `checked` is true, matching upstream's lambda, so an always-on thumb icon is inexpressible. A later `thumb_icon_unchecked` would be purely additive; confirm the narrow form.
- **#167** — `checkbox.stroke` is NOT mirrored onto `switch` despite the ledger's 'SHOULD be accepted on switch for symmetry' — SwitchKt has no stroke parameters in alpha16, so the member would be inert and unfalsifiable. Confirm the omission.
- **#167** — G-43's design is now constrained by G-36: EnterAlwaysTopAppBarWithReverseScrolling needs ONE ScrollState shared between the scrolling body and enterAlwaysScrollBehavior(scrollableState = ...). Either G-43 hoists the body's scroll state Companion-side, or that example is not cleared by G-36 + G-43 and needs a third member. Decide when G-43 is drafted, not here.
- **#167** — field_types.thumb_icon collides by name with the G-34 slider.thumb_icon amendment in the same batch. Values are byte-identical, but a naive sequential paste produces a duplicate JSON key, which json.load silently collapses. Whichever lands first satisfies both; the second must not re-add it.
- **#167** — menu.initial_scroll: "end" inherits an upstream race — scrollState.maxValue is 0 until the popup is measured, so scrollTo(maxValue) inside LaunchedEffect(open) can land at the top on first open. Upstream MenuWithScrollStateSample has the identical exposure. The spec text has been softened to a SHOULD-shaped 'opens scrolled to the end once the popup has been measured'; confirm you want that rather than a flat MUST.
- **#167** — No render-assertion harness exists (no ui-test-junit4, no androidTest source set). switch.thumb_icon's checked-only rendering, checkbox.stroke's cap/join-on-checkmark-only asymmetry, and the new menu overload branch are the three things here whose defects no test this repo can run would catch.
## Review findings the revisers rejected, with evidence

Twenty-three. Recorded because a rejected finding is a claim about the tree
that the ratifier may want to check independently.

- **#156** — None. All eight findings (1 P1, 3 P2, 4 P3) were checked against the cited files and all eight were correct. The nearest thing to a defensible draft claim was the P1 sub-point that the draft 'misattributes FIELD_TYPES to SpecValidator.kt' — the draft's words were 'field types are enforced by SpecValidator.kt', and SpecValidator does enforce them. But the finding's substance stands: the declaration is Vocabulary.kt:81, the artifact list omitted the file entirely, and the SurfaceStoreTest drift assertions — not the icon.size arm — are what make the regeneration same-commit mandatory. Applied in full.
- **#157** — None. Every finding in 157.review.txt was checked at the cited file:line and every one held. Two pieces of supporting evidence were slightly off without affecting the finding: the `check_enum_values` planted-value transcript prints `widgets:75`, not `widgets:77`, when the bad value is planted on the first appended golden line (the backtick-vs-single-quote defect the finding is actually about is real, and is fixed); and SPEC-CHANGES.md carries 118 numbered rows, not 52 (`grep -c '^| 1'` misses the two-digit rows), though the finding's real claim — that the file tops out at #152 and #153-#155 are absent — is correct.
- **#159** — [P2, partial] The finding claims BOTH new MUSTs in edit 2 'apply to `circular` and `linear` — the only two variants that exist'. That is right for the a11y MUST and wrong for the sender MUST: 'a sender MUST NOT make the wave, the morph, or the container the sole carrier of load-bearing meaning' names three things that exist only in the four NEW forms, so it is vacuous for `circular` and `linear` and binds no traffic that is legal today. I applied the fix in full anyway (it is the right fix), but the revised row classifies the two halves separately and states the vacuity rather than repeating the reviewer's framing. The a11y half is additionally not new at all — §16.4 (SPEC.md:2151-2152) already requires a render to preserve 'accessibility meaning' — so I demoted it to a restatement, which is the finding's own stated alternative.
- **#159** — [P3, line cites] The `--determinate` finding's line numbers are off by one: the hardcoded label `(jetpacs-text "Set progress:")` is at jetpacs-m3-progress-indicators.el:48 and the demo verb at :50, not :47/:49. The substance of the finding is correct and applied; the revised amendment cites :48/:50.
- **#160** — [P2, partial] The outlineVariant consumer list is real but slightly over-broad as given: InputChipTokens and OutlinedIconButtonTokens do reference ColorSchemeKeyTokens.OutlineVariant, but neither InputChip nor OutlinedIconButton appears anywhere in the Companion (grep over companion/app/src/main/kotlin finds no usage), so `icon_button` does NOT change colour. The revised enumeration names only sites that actually render today, plus date_button/time_button/diagnostic-action OutlinedButtons that the reviewer missed. OutlinedTextField is also NOT affected — OutlinedTextFieldTokens resolves to ColorSchemeKeyTokens.Outline, not OutlineVariant (javap).
- **#160** — [P2, partial] 'the drafted MUST says derivation fires when a map pushes surface, surface_variant, or outline' — the fix was taken, but not by narrowing the SPEC sentence as the reviewer's second option suggested; narrowing would have left the sentence describing outline_variant as sitting 'between outline and surface' while never deriving from surface. The code was widened instead.
- **#161** — P1's EVIDENCE and its RECOMMENDED fix are wrong. The reviewer wrote: "the body forwards three distinct `Function2` slots into `SelectableChip-9rhh4-4(…)`, so both draw", and recommended "drop the MUST NOT (they genuinely ARE distinct slots in 1.5.0-alpha16) and instead state that `chip.icon` and `chip.avatar` MAY both appear on an `input` chip, avatar first at `InputChipDefaults.AvatarSize` and `icon` at `FilterChipDefaults.IconSize`, plus a fifth golden covering the pair." They are forwarded but they do not both draw. `ChipContent`/`AnimatingChipContent` collapse the two slots through `leadingContent(avatar, leadingIcon, leadingIconColor)`, which returns ONE lambda. Source (/home/calebc42/pkb/resources/android/androidx/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Chip.kt:3516-3532): `when { avatar != null -> avatar // An avatar takes precedence; leadingIcon != null -> {…}; else -> null }`, under a KDoc that reads "Returns the actual leading content lambda based on priority (avatar > leadingIcon)". The `InputChip` KDoc itself (Chip.kt:1253-1254) says "An Input Chip can have a leading icon or an avatar at its start. In case both are provided, the avatar will take precedence and will be displayed." Confirmed in the SHIPPED alpha16 bytecode, `javap -c androidx/compose/material3/ChipKt.class`, method `leadingContent-XO-JAsU`: `29: aload_0` (avatar) `30: ifnull 54` … `50: aload_0; 51: goto 129` — when avatar is non-null the method returns avatar immediately and never touches `aload_1` (leadingIcon). Adopting the recommended fix would have written a normative sentence and a golden asserting a rendering Material cannot produce, and would have left the authored `icon` silently dropped — the exact genre D3 exists to end. I therefore took the finding's ALTERNATIVE branch (a third combination rule) instead, and the fifth golden covers `variant: "suggestion"` rather than the icon+avatar pair, which is now illegal.
- **#161** — P1's collateral claim that the `MUST NOT` sentence is "either vacuous or violated" is half right and I want the record straight: as written against alpha16 it is neither — it is SATISFIED by the library (only one leading graphic ever draws), and the real defect is that the draft's renderer and validator let a sender author a member that then draws nothing. The finding's severity is correct; its diagnosis is not.
- **#162** — The P3 fix's replacement citation `TabSamples.kt:224-249` is wrong for the androidx checkout at /home/calebc42/pkb/resources/android/androidx. In compose/material3/material3/samples/src/main/java/androidx/compose/material3/samples/TabSamples.kt, `fun TextAndIconTabs()` is at line **257** (with `@Preview`/`@Composable`/`@OptIn` at 254-256) and its closing brace is at **282**; line 224 falls inside `SecondaryIconTabs` (line 210). The finding's premise — that the draft's `224-253` is wrong — is correct, so I applied a correction, but to the verified range `257-282`. Same for the neighbouring sample: `LeadingIconTabs` is 287-316.
- **#162** — The P3 validate.py fix's specific remedy — guard the dispatch with `if t == "tabs" and "items" in value` AND make the early return bare — is over-broad in its second half. `check_slider_values` returns silently only when `values` is *absent* (validate.py:241-243); it still calls `problem()` for a present-but-malformed value (:244-246). A bare return for a present-but-non-array `items` would silently drop the only place the arm checks it, since the generic schema walk (validate.py:284-287) checks member *names*, not member types. I kept the finding's substance (one defect, one line) by returning silently only on `items is None`, and left the dispatch unguarded.
- **#163** — Nothing was rejected. All seven findings were verified against the cited files and all held: TextFieldSamples.kt:209-243 and :326-334 confirm the P1 and the hide-keyboard P2; Renderer.kt:160 and CompanionEngine.kt:430 confirm the JsonNull P2; TextFieldSamples.kt :93/:104/:142/:194/:249/:328 confirm the filled-vs-outlined P2; Kotlin String.length being UTF-16 confirms the unit P2; Attributes.kt:159 vs :160-161 and Renderer.kt:463 confirm the two P3 citations; SPEC.md:2462-2464 confirms the clearable/password P3.
- **#163** — One P1 sub-recommendation was declined on the merits rather than rejected as wrong: the reviewer offered 'give the clamp its own member (`enforce_max_length`, default false)'. It is not added, because it would have zero callers — its only catalog user, TextFieldWithTransformations, still needs G-52's mask/filter, and upstream fuses the two in one inputTransformation chain (TextFieldSamples.kt:121-126). The reviewer's alternative ('or state design decision 2 as option C') is what was taken: decision 2 is now scope, A = announce-only now with enforcement deferred to G-52, B = enforce_max_length shipped now. If B is ever taken the amendment records that it must be revert-the-edit, matching MaxLengthFilter.transformInput (InputTransformation.kt:240-244), not the first draft's clamp.
- **#164** — The draft's Companion line citations were all challenged implicitly by the review's framing but are CORRECT and were kept: Renderer.kt:693 (duration = SnackbarDuration.Short), :700 (snackbarHost = { SnackbarHost(hostState) }), :777 (PullToRefreshBox), :699 (Scaffold(), :728-730 (floatingActionButton), :688 (LaunchedEffect(snackbar)), :678 (@OptIn), NodeAccess.kt:63 (intByValue), IconMap.kt:28 (close), SpecValidator.kt:471/487-488/546. All confirmed by grep -n.
- **#164** — The review implied the draft's `VocabularyDriftTest` name might be wrong (it is not listed as its own file). It is correct: `class VocabularyDriftTest` is at companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire/SurfaceStoreTest.kt:727 with `generatedVocabularyMatchesContract` at :732. Kept, with the file path spelled out.
- **#164** — The draft's cross-reference of the badge accessibility split to Section 17.2 is CORRECT and was kept — SPEC.md:2252 is the §17.2 `badge` node row ('A decimal-integer string MAY be visually capped, but its exact accessible value MUST remain available'). §17.6:2602 has a second, weaker badge sentence, but §17.2 is the right citation for the MUST.
- **#164** — The reviewer's P1 #2 concluded 'the Cleared outright (4) count then becomes 0'. That is one of the two options it offered, and I took the other: the `:on-refresh` exemption is a five-line change in a file this amendment already has to touch (jetpacs-m3-slot-keys is a closed list that SIGNALS on the new keywords), so folding it in is in scope rather than a new amendment. With it, PullToRefreshWithLoadingIndicatorSample is genuinely clear — upstream (PullToRefreshSamples.kt:114-159) is exactly PullToRefreshBox(indicator = { PullToRefreshDefaults.LoadingIndicator(...) }), which `refresh_indicator: loading` reproduces one-for-one. The only conceded fidelity is the hoisted isRefreshing (G-73), and that is the identical concession the already-shipping sibling PullToRefreshSample makes on the same screen. Honest count is therefore 1, not 0.
- **#165** — [P3, the opt-in half] 'the opt-in requirement for TimePickerDialog is recorded in Kotlin @Metadata and is not readable from the bytecode, so I could not confirm from the AAR whether ExperimentalMaterial3ExpressiveApi is also required.' This is wrong about where opt-in markers live, and the question is answerable from the unpacked AAR. Kotlin emits an opt-in marker as an ordinary JVM annotation on the declaration (BINARY retention), so it appears in the class file. Evidence: `strings androidx/compose/material3/TimePickerKt.class | grep Experimental` yields `Landroidx/compose/material3/ExperimentalMaterial3Api;` — the technique detects markers — while the same grep over TimePickerDialogKt.class and TimePickerDialogDefaults.class in the 1.5.0-alpha16 classes yields NOTHING, and `javap -v` shows no RuntimeInvisibleAnnotations naming any experimental marker on TimePickerDialog-FItCLgY. TimePickerDialog, TimePickerDialogDefaults.Title, .DisplayModeToggle and .MinHeightForTimePicker are unmarked in this artifact. The existing @OptIn(ExperimentalMaterial3Api::class) at InputNodes.kt:460 suffices; no ExperimentalMaterial3ExpressiveApi is needed and the ratifier does not need a compile check for it. I kept the import list from this finding (correct) and replaced the deferral with the verified answer.
- **#165** — [P2, first branch, partially] The finding's parenthetical that removing the field_types entries 'also shrinks the Vocabulary.kt regeneration to node_schema alone' is right, but its framing that this makes the Vocabulary.kt regeneration optional is not — I want to be explicit that it does NOT: VocabularyDriftTest asserts NODE_SCHEMA row-by-row against contract.json (SurfaceStoreTest.kt:740-744), so the node_schema edit alone still requires the regeneration. Not a rejection of the fix, a correction to the reasoning; the amendment states it.
- **#165** — [P2, second finding, line citation] The reviewer cites jetpacs-m3-time-picker.el:41-49 for the --picker docstring. Line 41 is blank; the defun opens at 42 and the docstring runs 43-48. The finding's substance is confirmed and applied; only the anchor is off by one, and the amendment cites :42-49.
- **#166** — [P2] 'the sketched implementation silently swaps the THUMB composable; the default thumb lambda invokes Thumb-HwbPF3A (the SliderState-aware expressive thumb)' — WRONG. The reviewer found the `Thumb-HwbPF3A` invocation and attributed it to `Slider`, but it is inside `VerticalSlider$lambda$1`. Disassembling the alpha16 `SliderKt` and mapping every `Thumb-*` call site to its enclosing synthetic lambda: `Slider$lambda$1` (default thumb of the value/onValueChange simple overload the Companion uses TODAY), `Slider$lambda$5` (default thumb of the value/onValueChange SLOTTED overload this amendment moves to), and `Slider$lambda$10` (default thumb of the SliderState overload) ALL invoke `SliderDefaults."Thumb-9LiSoMs"` — the stateless form the draft sketches. Only `VerticalSlider$lambda$1` (javap line 7496, call at 7524) invokes `Thumb-HwbPF3A`. Corroborated upstream: androidx `Slider.kt` writes `thumb: @Composable (SliderState) -> Unit = { _ -> SliderDefaults.Thumb(interactionSource = interactionSource, colors = colors, enabled = enabled) }` for the horizontal overloads, and `CenteredSliderSample` itself passes `SliderDefaults.Thumb(interactionSource = interactionSource)` — the same stateless call. Taking the reviewer's fix would have been the actual divergence: it would swap in a DIFFERENT thumb from every other slider on the surface, and `Thumb-HwbPF3A` carries `@ExperimentalMaterial3ExpressiveApi` (annotation at javap line 2703, inside 2302-2736) where `Thumb-9LiSoMs` (1915-2301) carries none, so it would also widen the alpha exposure for no gain. `track` really is track-only as drafted; a note recording this verification has been added to the Companion section so a later reader does not re-open it.
- **#167** — [P3, partially] The review's evidence says the sample 'passes reverseScrolling = true to enterAlwaysScrollBehavior as well'. It does not, in this checkout: AppBarSamples.kt:958-960 is TopAppBarDefaults.enterAlwaysScrollBehavior(scrollableState = scrollState) with the comment 'Pass this state to ensure the top app bar color updates correctly when content has reverse scrolling' — one argument, the state, no reverseScrolling parameter. The reverseScrolling = true appears only at :999 on the body's verticalScroll. The substantive point (a shared hoisted ScrollState the drafted RenderColumn cannot provide) is right and is applied; the parameter detail is not, and I did not write it into the amendment.
- **#167** — [P1, the FIX only] The review prescribes branching 'when supporting_text, trailing_icon and trailing_text are all absent'. Two of those three do not force the migration: the overload the Companion binds today, AndroidMenu_androidKt.DropdownMenuItem(text, onClick, modifier, leadingIcon, trailingIcon, enabled, colors, contentPadding, interactionSource), ALREADY has a trailingIcon slot — it is the slot upstream's own MenuSample fills with Text("F11", textAlign = TextAlign.Center) (MenuSamples.kt:148). Branching on all three would push every trailing-only item, including the F11 repair this amendment exists partly to make, onto the expressive path for no reason. Applied the narrower branch: supporting_text alone selects the overload, and it selects it for the whole menu (per-item branching would render one popup in two geometries). The finding's defect is confirmed; its remedy was wider than the defect.
- **#167** — [P2, the renumber option] Declined to renumber 167 -> 153. The finding offers 'either renumber ... or state explicitly which sibling batch reserves 156-166'; the second is correct here, since 153-166 are the other m3-fidelity drafts of this same batch and renumbering one of them in isolation would collide. Stated the reservation explicitly instead.
---

## #156 — button expressive geometry: `size`, `shape`, `animate_shape`, and the `elevated` variant

Drafted 2026-08-02 against `ebp/SPEC.md` @ **`83d6e08`** (ebp submodule HEAD, "spec: amendments
#140–#141"); superproject `16e8dd1`. Every verbatim quote below was re-checked against that tree.

**Numbering.** `ebp/SPEC-CHANGES.md`'s highest row on this branch is **152**. Rows 153–155 are
unratified and live on the `rf-4a` line. This amendment assumes #153–#155 ratify first and takes
**156**; if they do not, renumber to the next free row before merge. Nothing in the amendment
depends on their content.

Source audit: `docs/AUDIT-m3-blockers-2026-08-02.md`, gaps **G-01**, **G-05**, **G-06**, **G-07**.
Every renderer and Compose claim below was verified against the file and against
`material3-android-1.5.0-alpha16` (`javap` on the AAR classes, plus the androidx source at
`compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Button.kt`), not
taken from the ledger.

**Design decisions required: three (D1, D2, D3, at the end).** The draft is written as
option A everywhere.

### SPEC-CHANGES row (ready to paste)

> | 156 | 2026-08-02 | §17.1, §17.4 (cross-ref §12 rule 6, §16.1, §16.3, §16.5, §22.4; contract) | **Button expressive geometry — the container scale, the shape, and the elevated variant reach the wire.** `button` has carried `{label, on_tap, icon, variant, enabled}` since format 6, and `RenderButton` (`InputNodes.kt:75-95`) hardcodes every remaining dimension of the component: `PaddingValues(horizontal = 12.dp, vertical = 8.dp)` at :80, a `Modifier.size(18.dp)` leading icon at :83, a `Spacer(Modifier.size(6.dp))` at :84, and an unstyled `Text` at :86. Emacs can therefore ask for a button's *role* and for nothing about its *proportion*, and the universal attributes do not close the gap: `min_height` (`Attributes.kt:146-149`) really does reach the Button's own modifier — the shared catalog size-note claiming otherwise is wrong — but it carries one of the five tokens a Material 3 size step consists of, and `corner`/`bg`/`clip` (`Attributes.kt:155-167`) decorate the node's modifier *outside* `Surface.minimumInteractiveComponentSize()`, i.e. the 48dp touch box rather than the 40dp container, leaving the Button's own pill clip, ripple and border intact underneath. Three optional members and one enum value close it. **`size`** is an OPTIONAL string enum `xsmall｜small｜medium｜large｜xlarge`; **omitted it means exactly today's rendering**, and an unrecognized value MUST fall back to that same omitted behavior under Section 12 rule 6, so no existing traffic changes meaning. A present `size` is a coordinated token set, never a height alone: the Companion derives the container height, the content padding, the leading-icon size, the icon-to-label spacing and the label typography from the one step (`ButtonDefaults.contentPaddingFor/iconSizeFor/iconSpacingFor/textStyleFor` and the `ExtraSmall/Medium/Large/ExtraLargeContainerHeight` constants, with `small` = `ButtonDefaults.MinHeight`, whose `contentPaddingFor` resolves to `SmallContentPadding`), and MUST NOT apply the step partially — a container stretched around unscaled content is a different component, not a larger one, which is precisely the false picture the catalog's `:unsupported` screens exist to prevent. **`shape`** is an OPTIONAL string enum `round｜square` defaulting to `round`, which is the shape `Button` already draws, so the default is today's rendering; it selects the container's own shape (`ButtonDefaults.shape` / `ButtonDefaults.squareShape`), the thing `corner` provably cannot reach. **`animate_shape`** is an OPTIONAL boolean defaulting to `false` — today's rendering, since no `shapes=` argument is passed now — and `true` asks for the platform press-state morph while changing neither resting geometry, hit area, nor dispatch; when `size` is also present the morph target comes from the selected step, because a step-sized container morphing to an unsized target is the partial application the paragraph above forbids. **`variant`** gains a fifth value `elevated` (`ElevatedButton`), and — because the welcome advertises node types but has no enum-value discovery channel, so a grown enum would otherwise take an older Companion's whole surface to `1201 content-invalid` under §16.1 — `variant` also gains the safe fallback to `filled` that Section 12 rule 6 requires of a growable enum; that fallback is what `InputNodes.kt:93`'s `else -> Button(…)` has always done, so the amendment aligns the text with the shipped receiver rather than changing it. All four members are presentation-only and MUST NOT be relied on to disable, hide, authorize or limit an action; on a receiver that predates them the three new member names are exactly the unknown optional fields §16.3 already tells it to ignore. None constrains a construct an ignoring receiver would over-accept, so §22.4 registers nothing. One consequence is paid in §17.1: `size` was globally typed as non-negative `dp` (for `icon.size`), and `button.size` is an enumerated string, so §17.1's two `size` sentences are qualified to *numeric* `size` — the `boolean-valued selected` / `boolean-valued fill` idiom the section already uses — and `field_types.size` is demoted to `varies-per-node` alongside `value`, `selected`, `fill` and `items`, with `icon.size`'s finite-number check restored as a dedicated `SpecValidator` arm so nothing it rejected today becomes acceptable. Additive per §12: three new optional cosmetic members with defaults that preserve today's rendering, one enum value, and one enum fallback; no existing message, golden, or fixture is modified, and `validate.py` is unchanged because it checks key membership, not field types. This clears every one of the twelve `:unsupported` entries in the catalog's `buttons` component, taking it from 5/17 to 17/17. | contract `node_schema.button.optional` += `size`, `shape`, `animate_shape`; `enums."button.variant"` += `elevated`; `enums."button.size"`, `enums."button.shape"` (new); `field_types.size` `dp` → `varies-per-node`, `field_types.animate_shape` = `boolean`; **both generated mirrors regenerated in the same commit** — `tools/gen-vocabulary.py` → `companion/wire/…/Vocabulary.kt` (`NODE_SCHEMA` :49, `FIELD_TYPES` :81) and `tools/gen-jetpacs-vocabulary.py` → `emacs/jetpacs-vocabulary.el` (:56); goldens/widgets.golden += 1 appended line (none modified); validate.py unchanged — the Kotlin `SpecValidator` gains an `icon.size` finite-number arm preserving the demoted check | |

### SPEC.md edits

**1. §17.1, second paragraph** — replace (SPEC.md:2226, one line):

> `width`, `height`, `size`, `radius`, and coordinate fields are finite numbers;

with:

> `width`, `height`, `radius`, numeric `size`, and coordinate fields are finite numbers;

**2. §17.1, third paragraph** — replace (SPEC.md:2235 through the first sentence of :2236;
the `An action-valued field MUST contain a valid descriptor…` sentence that continues line
2236 is untouched):

> `size`, `spacing`, `run_spacing`, `content_padding`, `elevation`, and
> `thickness` are non-negative `dp`.

with:

> Numeric `size`, `spacing`, `run_spacing`, `content_padding`, `elevation`, and
> `thickness` are non-negative `dp`. A `size` member whose row in Section 17.2 or
> 17.4 gives it an enumerated domain is that enumerated string rather than a `dp`
> value, and that row supplies both the domain and the unrecognized-value
> fallback.

*(The generic phrasing is deliberate. D2(A) exists precisely so that G-08's
`icon_button.size` rides the same demotion; a sentence naming `button.size` as
"the one `size` that is not a `dp` value" would be false the day G-08 lands and
would need a second amendment to unsay.)*

**3. §17.4 node table, the `button` row** — replace (SPEC.md:2412, one line):

> | `button` | `label: string`, `on_tap: ActionDescriptor` | `icon`, `variant`, `enabled`. `variant`: `filled` (default), `tonal`, `outlined`, or `text`. |

with:

> | `button` | `label: string`, `on_tap: ActionDescriptor` | `icon`, `variant`, `size`, `shape`, `animate_shape`, `enabled`. `variant`: `filled` (default), `tonal`, `elevated`, `outlined`, or `text`; unknown values fall back to `filled`. `size`: `xsmall`, `small`, `medium`, `large`, or `xlarge`; omitted or unrecognized means the Companion's unscaled default button. `shape`: `round` (default) or `square`; unknown values fall back to `round`. `animate_shape` is a boolean defaulting to `false`. |

**4. §17.4 prose** — after (SPEC.md:2426-2429):

> A `MenuItem` MUST contain `label` and `on_tap` and MAY contain `icon` and
> `enabled`; `enabled` defaults to `true`. An `EnumOption` MUST contain `label`
> and `value`; `value` MUST be a
> string, number, or boolean. Option values MUST be distinct under Section 4.3.

insert three new paragraphs (before `For input nodes, every listed `on_*` member is an
ActionDescriptor.` at :2431):

> `button.size` selects one step of the Material 3 container scale. It is a string
> enum, not the `dp` value Section 17.1 gives every other `size` member. Omitting it
> means the Companion's unscaled default button — exactly the rendering produced
> before this member existed — and an unrecognized value MUST fall back to that same
> omitted behavior under Section 12 rule 6. Omission is not equivalent to
> `size: "small"`: omission preserves whatever the Companion already renders, while
> `small` selects the scale's small step and applies every one of its tokens. A
> present `size` is a coordinated token set, not a height: the Companion MUST derive
> the container height, the content padding, the leading-icon size, the
> icon-to-label spacing, and the label typography from the one selected step, and
> MUST NOT apply the step partially. A container stretched around unscaled content
> is a different component, not a larger one. A universal `height`, `min_height`, or
> `max_height` (Section 16.5) constrains the sized container; it does not cancel the
> remaining tokens.
>
> `button.shape` selects the button's own container shape. `round` is the default and
> is the shape a Companion draws for a button today; `square` requests the platform's
> square-cornered container. Unknown values fall back to `round`. The universal
> `corner`, `bg`, and `clip` attributes are not a substitute: they decorate the node's
> modifier, outside the button's minimum-touch-target box, and leave the button's own
> shape, state layer, and border in place beneath them. `button.animate_shape` is a
> boolean defaulting to `false`; `true` requests the platform's press-state shape
> morph and MUST NOT change the button's resting geometry, its hit area, its enabled
> semantics, or its dispatch. When `size` and `animate_shape` are both present, the
> morph target MUST come from the step `size` selects; morphing a step-sized
> container to an unsized target is a partial application of the step.
>
> `size`, `shape`, and `animate_shape` are presentation-only. Section 16.3 applies:
> Emacs MUST NOT depend on any of them to disable, hide, authorize, or limit an
> action, and a Companion that does not honor one MUST still render an operable
> button.

### Artifact changes

**contract.json — `node_schema.button` (contract.json:295-305).** Replace:

```json
      "optional": [
        "icon",
        "variant",
        "enabled"
      ]
```

with:

```json
      "optional": [
        "icon",
        "variant",
        "size",
        "shape",
        "animate_shape",
        "enabled"
      ]
```

**contract.json — `field_types` (contract.json:570-571).** Replace:

```json
    "scroll_here": "boolean",
    "size": "dp",
```

with:

```json
    "scroll_here": "boolean",
    "animate_shape": "boolean",
    "size": "varies-per-node",
```

`shape` gets no `field_types` entry, matching `surface.shape` and `variant`: the
table keeps enum-valued members out of the scalar type map because §12 rule 6
gives them fallback semantics rather than a coercion check.

**contract.json — `enums` (contract.json:626-631).** Replace:

```json
    "button.variant": [
      "filled",
      "tonal",
      "outlined",
      "text"
    ],
```

with:

```json
    "button.variant": [
      "filled",
      "tonal",
      "elevated",
      "outlined",
      "text"
    ],
    "button.size": [
      "xsmall",
      "small",
      "medium",
      "large",
      "xlarge"
    ],
    "button.shape": [
      "round",
      "square"
    ],
```

*No claim is made that these entries are enforced anywhere.* `grep -n 'enums'
ebp/validate.py` returns zero hits, neither generator reads the block
(`tools/gen-vocabulary.py:43` reads `field_types` only; `tools/gen-jetpacs-vocabulary.py`
reads `node_schema` only), and `Vocabulary.kt` stores only the type *name* `"enum"`.
The `enums` block is documentation projected from the SPEC; the ratified text in
§17.4 is what binds.

**Both generated mirrors, regenerated in the same commit.** This is not optional and
it is the reason the contract edit cannot land alone: `VocabularyDriftTest`
(`companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire/SurfaceStoreTest.kt:727`)
asserts exact equality against `contract.json` — `assertEquals("$name optional",
set("optional"), NODE_SCHEMA.getValue(name).optional)` at :744 and
`assertEquals(fieldTypes.keys, FIELD_TYPES.keys)` at :753 with the per-key value
compare at :755 — and `jetpacs-widgets/catalog-node-schema`
(`test/jetpacs-widgets-test.el:889-905`) asserts the same for the elisp mirror.
Three assertions go red the moment `contract.json` moves without them.

```
python3 tools/gen-vocabulary.py          # -> companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/Vocabulary.kt
python3 tools/gen-jetpacs-vocabulary.py  # -> emacs/jetpacs-vocabulary.el
```

Resulting lines (both files carry a `GENERATED … DO NOT EDIT` banner; regenerate,
do not hand-edit):

`Vocabulary.kt:49` — contract member order is preserved by `kt_set`:

```kotlin
    "button" to NodeRow(setOf("label", "on_tap"), setOf("icon", "variant", "size", "shape", "animate_shape", "enabled")),
```

`Vocabulary.kt:81` block — `FIELD_TYPES` is emitted `sorted()`
(`tools/gen-vocabulary.py:41-44`), so `"animate_shape" to "boolean",` lands between
`"allow_add"` (:84) and `"annotation"` (:85), and the existing `"size" to "dp",`
at :153 becomes `"size" to "varies-per-node",`.

`emacs/jetpacs-vocabulary.el:56` — the elisp mirror sorts both sets
(`tools/gen-jetpacs-vocabulary.py:33-34`) and carries no `field_types` projection at
all, so this one line is its whole delta:

```elisp
    ("button" ("label" "on_tap") ("animate_shape" "enabled" "icon" "shape" "size" "variant"))
```

**goldens/widgets.golden.** Append one line; lines `35` and `36` (the existing minimal
and maximal `button`) are untouched, so the coverage floor and every replay keep their
present meaning. The corpus carries a zero-based `NN ` index prefix that
`validate.py:377-379` strips, so the new line is index `75`:

```
75 {"animate_shape":true,"icon":"edit","label":"Label","on_tap":{"action":"demo.tap"},"shape":"square","size":"medium","t":"button","variant":"elevated"}
```

The JSON is canonical (`json.dumps(..., sort_keys=True, separators=(',', ':'))`) and
exercises all four new spellings at once. Two other gates consume it:
`WidgetsGoldenReplayTest.kt:52-60` drives every line through `SpecValidator` (which is
why the `Vocabulary.kt` regeneration above must be in the same commit), and
`test/smoke-parity.el` drives every `t`-bearing line through a live Emacs↔Companion
pair as an `app:main` surface root.

**validate.py — no arm needed, and none added.** `check_node` (validate.py:253-300)
enforces required members, key membership against `required ∪ optional ∪ UNIVERSAL`,
and the per-type arms for `text_input`, `enum_list`, and `slider`. It never reads
`field_types` or `enums`: `grep -n 'field_types\|enums' ebp/validate.py` returns zero
hits. The structural argument stands on its own; the run below is the actual
post-change transcript, with the contract and golden deltas applied to a scratch copy
of `ebp/` and `validate.py` itself untouched (`75 widget lines` before, `76` after):

```
OK: 40 frames, 76 widget lines, 7 hypertext nodes, 17 wire fixtures x3 chunkings validate (spec 2.0.0-draft, format 6); SPEC §8/§11 in sync; 9.3 KAT reproduced
```

**The compensating check is Kotlin, and it must land in the same commit.**
`FIELD_TYPES` is *declared* at `Vocabulary.kt:81` (generated) and *consumed* by
`SpecValidator.checkScalarFieldType` (`SpecValidator.kt:467-497`), which keys the map
on the **bare member name** at :470 and is called for every schema-listed member
present on the node (:545-546). That is why `button.size` cannot ship against
`field_types.size = "dp"` — `{"t":"button","size":"medium"}` throws
`size must be a finite number` today — and it is why demoting the entry needs a
replacement arm in `validateNode`'s `when (t)` block (:547 onward), reproducing the
`"dp", "number"` case at :481-483 verbatim so nothing changes for `icon`. `icon` is the
only node type in the contract that lists `size` at all, and `size` is not a universal
attribute, so one arm covers the whole demotion:

```kotlin
// #156: field_types.size is varies-per-node now, so the dp check that covered
// icon.size through checkScalarFieldType is restated here — same predicate,
// same reason string, same non-enforcement of non-negativity.
"icon" -> node["size"]?.let { v ->
    val d = v.asDoubleOrNull()
    if (d == null || d.isInfinite() || d.isNaN())
        throw ContentInvalid("$path.size", "size must be a finite number")
}
```

`button.size` and `button.shape` correctly get **no** validator arm: §16.1 exempts a
member with a defined safe fallback from whole-object rejection, and the existing enums
(`text.style`, `surface.shape`, `progress.variant`, `box.alignment`) are likewise
unchecked there. A companion test belongs beside
`SpecValidatorCompletenessTest.scalarMembersAreTypeCheckedNotCoerced` (:67-91): `icon`
with `size: "big"` still rejects, `button` with `size: "medium"` now accepts. Nothing
currently pins `icon.size` — `grep '"size"' companion/wire/src/jvmTest/**/*.kt` returns
nothing — so without that test a forgotten arm is invisible to every gate in the repo.

### Companion implementation

**File:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/InputNodes.kt`
**Function:** `RenderButton`, lines **75-95** — currently the `pad` literal at :80, the icon
`Modifier.size(18.dp)` at :83, the `Spacer(Modifier.size(6.dp))` at :84, the unstyled
`Text` at :86, and the `when (node.stringOr("variant"))` at :89-94.
The dispatcher hands `m = modifier.universal(node)` to it at `Renderer.kt:275` (the
assignment) via the `"button" -> RenderButton(node, ctx, m)` arm at `Renderer.kt:306`.

The file needs `@OptIn(ExperimentalMaterial3ExpressiveApi::class)` on the function — the
house pattern already used at `InputNodes.kt:243` (`ExperimentalLayoutApi`) and `:431`,
`:460` (`ExperimentalMaterial3Api`). Every API below was confirmed present in the
disassembled `material3-android-1.5.0-alpha16` `classes.jar` (`ed86191` raised the
dependency); only `ElevatedButton` is stable, the rest are `@ExperimentalMaterial3ExpressiveApi`.

**Step resolution** (`ButtonDefaults`, all verified by `javap` on the AAR and against
`Button.kt:1055-1110`, `:1578-1650`):

| `size` | container height | tokens |
|---|---|---|
| absent | — (today's `m`) | `PaddingValues(12.dp, 8.dp)`, `18.dp` icon, `6.dp` spacer, unstyled label — unchanged |
| `xsmall` | `ButtonDefaults.ExtraSmallContainerHeight` (`ButtonXSmallTokens.ContainerHeight`) | `contentPaddingFor(h, hasStartIcon)`, `iconSizeFor(h)`, `iconSpacingFor(h)`, `textStyleFor(h)` |
| `small` | `ButtonDefaults.MinHeight` (`ButtonSmallTokens.ContainerHeight` = 40dp) | same four; `contentPaddingFor(MinHeight)` resolves to `SmallContentPadding` — there is deliberately no `SmallContainerHeight` constant, and `shapesFor`'s own step ladder (`Button.kt:1547-1563`) uses `MinHeight` for this rung |
| `medium` | `ButtonDefaults.MediumContainerHeight` | same four |
| `large` | `ButtonDefaults.LargeContainerHeight` | same four |
| `xlarge` | `ButtonDefaults.ExtraLargeContainerHeight` | same four |

Height goes on the Button's own modifier as `m.heightIn(min = h)`, exactly upstream's
`Modifier.heightIn(size)` in `ButtonSamples.kt:155`, `:176`, `:197`, `:218`.

`contentPaddingFor` takes `hasStartIcon`/`hasEndIcon` flags
(`contentPaddingFor-8Feqmps(float, boolean, boolean)` in the AAR; `Button.kt:1578-1594`),
and every upstream sized-with-icon sample passes `hasStartIcon = true`
(`ButtonSamples.kt:156`, `:177`, `:198`, `:219`; the unsized `ButtonWithIconSample` does
the same at `:134-135`). The Companion MUST pass
`hasStartIcon = iconName.isNotEmpty()`; a leading icon with the no-icon padding is a
partial application of the step in the same sense the §17.4 prose forbids, and it is the
difference between recreating `MediumButtonWithIconSample` and approximating it.

**Shape resolution** — `shape` × `animate_shape` × (`size` present). The pressed shape
is part of the step: `ButtonDefaults` exposes `pressedShape`, `extraSmallPressedShape`,
`mediumPressedShape`, `largePressedShape`, `extraLargePressedShape` (`Button.kt:1126-1143`),
and `shapesFor(h)` picks among them on the height ladder. Define one helper reproducing
that ladder for the five discrete steps:

```kotlin
val pressed: Shape = when (node.stringOr("size")) {   // absent/unrecognized and "small" -> pressedShape
    "xsmall" -> ButtonDefaults.extraSmallPressedShape
    "medium" -> ButtonDefaults.mediumPressedShape
    "large"  -> ButtonDefaults.largePressedShape
    "xlarge" -> ButtonDefaults.extraLargePressedShape
    else     -> ButtonDefaults.pressedShape
}
```

| `animate_shape` | `shape` | Compose argument |
|---|---|---|
| `false` | `round` | *(none — `ButtonDefaults.shape` is already the default; today's call, byte-for-byte)* |
| `false` | `square` | `shape = ButtonDefaults.squareShape` |
| `true` | `round`, no `size` | `shapes = ButtonDefaults.shapes()` |
| `true` | `round`, with `size` | `shapes = ButtonDefaults.shapesFor(h)` |
| `true` | `square` | `shapes = ButtonDefaults.shapes(shape = ButtonDefaults.squareShape, pressedShape = pressed)` |

The square/animated row carries `pressed` rather than the one-argument
`shapes(shape = squareShape)`. Without it a `{"size":"xlarge","shape":"square",
"animate_shape":true}` button is a 136dp container morphing to the 40dp-step pressed
shape — the step applied to the resting geometry but not to the morph, which the §17.4
prose forbids in as many words. With `size` absent or `small`, `pressed` is
`ButtonDefaults.pressedShape`, which is exactly what the one-argument overload would
have defaulted to, so nothing changes for the unsized case.

`ButtonDefaults.squareShape` resolves `ButtonSmallTokens.ContainerShapeSquare` =
`ShapeKeyTokens.CornerMedium` (`Button.kt:1122-1123`, `tokens/ButtonSmallTokens.kt:26`)
and is **size-invariant** — 1.5.0-alpha16 ships no per-size *resting* square token, so
the resting shape matches upstream `SquareButtonSample` exactly at every step. That is a
faithful reproduction of an upstream limitation, not a partial step; the pressed shape,
which *does* have per-size tokens, is handled above.

Every variant composable has both a `shape:` and a `shapes: ButtonShapes` overload
(`Button.kt:139`/`:236` for `Button`, `:336`/`:413` `ElevatedButton`, `:486`/`:564`
`FilledTonalButton`, `:636`/`:713` `OutlinedButton`, `:786`/`:864` `TextButton`), with
`shapes` as the **second positional** parameter and no `shape` parameter alongside it, so
the `when (variant)` block becomes two parallel five-arm blocks selected on
`shapes == null`:

```kotlin
val h: Dp? = when (node.stringOr("size")) {          // absent OR unrecognized -> null
    "xsmall" -> ButtonDefaults.ExtraSmallContainerHeight
    "small"  -> ButtonDefaults.MinHeight
    "medium" -> ButtonDefaults.MediumContainerHeight
    "large"  -> ButtonDefaults.LargeContainerHeight
    "xlarge" -> ButtonDefaults.ExtraLargeContainerHeight
    else     -> null
}
val pad = if (h == null) PaddingValues(horizontal = 12.dp, vertical = 8.dp)
          else ButtonDefaults.contentPaddingFor(h, hasStartIcon = iconName.isNotEmpty())
val mm  = if (h == null) m else m.heightIn(min = h)
// …icon Modifier.size(h?.let { ButtonDefaults.iconSizeFor(it) } ?: 18.dp),
//   Spacer Modifier.size(h?.let { ButtonDefaults.iconSpacingFor(it) } ?: 6.dp),
//   Text(…, style = h?.let { ButtonDefaults.textStyleFor(it) } ?: LocalTextStyle.current)
val square = node.stringOr("shape") == "square"
val shapes: ButtonShapes? = when {
    !node.boolOr("animate_shape") -> null
    square -> ButtonDefaults.shapes(shape = ButtonDefaults.squareShape, pressedShape = pressed)
    h != null                     -> ButtonDefaults.shapesFor(h)
    else                          -> ButtonDefaults.shapes()
}
// variant dispatch, unchanged except for the new arm and the two overloads:
//   "elevated" -> ElevatedButton(onClick, mm, enabled, contentPadding = pad) { content() }
//   "elevated" -> ElevatedButton(onClick, shapes, mm, enabled, contentPadding = pad) { content() }
```

`pad` is passed explicitly on both paths. That matters for the `shapes` overloads, whose
own `contentPadding` default is `contentPaddingFor(MinHeight)` rather than
`ButtonDefaults.ContentPadding` (`Button.kt:244`) — relying on the default would silently
change the padding of an unsized `animate_shape` button.

Both `else` branches keep the existing filled `Button`, so an unrecognized `variant`
renders `filled` — which is what `:93` already does and what D1(A) writes into the SPEC.

**Emacs side** (`emacs/jetpacs-widgets.el`): `jetpacs--button-variants` at :985 grows the
fifth value; `jetpacs-button` at :988-998 gains `&key size shape animate-shape` with two
`jetpacs--check-enum` calls in the shape of `jetpacs-progress`'s at :695 and one
`jetpacs--check-bool` for `animate-shape` in the shape of the existing `:enabled` check
at :996.

### Unblocks

**All twelve `:unsupported` entries in `emacs/apps/m3-catalog/jetpacs-m3-buttons.el` —
the whole `buttons` component goes from 5/17 buildable to 17/17.** Both shared reason
constants (`jetpacs-m3-buttons--shape-note` :28-30 and `--size-note` :32-34) are retired
with them, along with the three per-example reason strings at :85-86, :97-98 and
:104-105; all five are among the audit's 79 factually inaccurate reason strings.

| # | Example | Gap(s) cleared |
|---|---|---|
| 1 | `SmallButtonSample` | G-01 (sole) |
| 2 | `XSmallButtonWithIconSample` | G-01 (sole) |
| 3 | `MediumButtonWithIconSample` | G-01 (sole) |
| 4 | `LargeButtonWithIconSample` | G-01 (sole) |
| 5 | `XLargeButtonWithIconSample` | G-01 (sole) |
| 6 | `ElevatedButtonSample` | G-05 (sole) |
| 7 | `FilledTonalButtonWithAnimatedShapeSample` | G-06 (sole) |
| 8 | `OutlinedButtonWithAnimatedShapeSample` | G-06 (sole) |
| 9 | `TextButtonWithAnimatedShapeSample` | G-06 (sole) |
| 10 | `ButtonWithAnimatedShapeSample` | G-06 (sole) — **ledger correction**, see below |
| 11 | `SquareButtonSample` | G-07 (sole) |
| 12 | `ElevatedButtonWithAnimatedShapeSample` | G-05 + G-06, both in this amendment |

`SmallButtonSample` deserves a note because it is the one row where "same step" is
load-bearing: upstream is `Button(onClick, contentPadding = ButtonDefaults.SmallContentPadding)`
(`ButtonSamples.kt:63-67`) with no `heightIn` and no `style`. `size: "small"` produces
`heightIn(min = MinHeight)` — which `Button`'s own `defaultMinSize(minHeight = MinHeight)`
(`Button.kt:172-175`) already imposed — plus `contentPaddingFor(MinHeight)` =
`SmallContentPadding` and `textStyleFor(MinHeight)` = `labelLarge`, which is the style
`Button` already provides via `ProvideContentColorTextStyle` (`Button.kt:167-169`). Net
rendering is identical to the sample.

**Two ledger corrections this table makes.** (a) `docs/AUDIT-m3-blockers-2026-08-02.md:121`
credits `ButtonWithAnimatedShapeSample` to G-06 **and** G-07. Upstream is
`Button(onClick = {}, shapes = ButtonDefaults.shapes())` (`ButtonSamples.kt:49-51`) with no
`shape` argument at all — G-06 alone. G-07's real sole-gap case is `SquareButtonSample`
(`ButtonSamples.kt:56-58`). The cleared count is unaffected; G-07's appearance count drops
from 3 to 2. (b) The audit's G-01 row at :89 says the four sized toggle samples come "with
G-03". G-03 is `progress.variant` wavy; the intended gap is G-04 (`button.checked`), whose
own row at :108 claims "togglebuttons/all 10". Read as G-04 below.

**Deliberately not claimed, against the ledger.** G-01's entry credits six
`extended-fab` examples (`Small`/`Medium`/`LargeExtendedFloatingActionButtonSample` and
their `…TextSample` siblings) as `button.size`-only. They are not cleared here.
`Renderer.kt:728-730` hands `scaffold.fab` straight to `RenderNode`, so a `button` in
that slot is a `Button`; the audit's own finding for `SmallExtendedFloatingActionButtonSample`
asks for the *extended-FAB* token family — container height, extended-FAB corner,
`FloatingActionButtonDefaults` icon size — and names a dedicated `fab` node as the
alternative shape of the fix. That is G-68, and see **D3**. Against this amendment G-01's
honest score is ~8.0/16, not the ledger's 11.0/22.

**Partially advanced, still blocked** (listed so the ledger's arithmetic reconciles).
**Twelve** examples lose a prerequisite without becoming buildable:

| Count | Examples | Still needs |
|---|---|---|
| 1 | `split-button/ElevatedSplitButtonSample` | G-02 |
| 3 | `togglebuttons/ElevatedToggleButtonSample`, `ToggleButtonWithIconSample`, `RoundToggleButtonSample` | G-04 |
| 4 | `togglebuttons/XSmall`, `Medium`, `Large`, `XLargeToggleButtonWithIconSample` | G-04 (ledger says G-03; typo, see above) |
| 4 | `split-button/XSmall`, `Medium`, `Large`, `ExtraLargeFilledSplitButtonSample` | G-08 |

**Design decision required**

**D1 — does `button.variant` gain a safe fallback along with its fifth value?**

| | A (recommended, drafted) | B |
|---|---|---|
| Rule | An unrecognized `variant` MUST fall back to `filled` | `variant` keeps today's implied whole-surface `1201` rejection under §16.1 |
| Effect of `elevated` on a pre-#156 Companion | renders as a filled button | rejects the entire surface update |
| Discovery available to Emacs | none — the welcome advertises `node_types`, `builtins`, `features`; there is no enum-value channel and no `spec_version` member anywhere in §10.2 | same, so Emacs must gate on out-of-band knowledge of the receiver's build |
| Relation to the shipped receiver | matches `InputNodes.kt:93` `else -> Button(…)`, which has always rendered unknown variants as filled | leaves the spec requiring a rejection no reference code performs |
| Cost | a loosening for content that was already invalid; a third-party Companion that *did* reject becomes non-conforming | every future enum growth on `variant` is a flag day |

**Recommendation: A.** Growing a closed enum with no discovery channel and no fallback is
the flag-day shape #152 spent a whole amendment avoiding elsewhere, and here the
fallback is not a new behavior — it is the behavior. Note the asymmetry that makes this
the *only* growth hazard in the amendment: `size`, `shape`, and `animate_shape` are new
member *names*, which §16.3 already tells an older Companion to ignore; `elevated` is a
new *value* on an existing member, which §16.1's "outside its declared type or domain"
clause takes to `1201` unless the fallback is stated.

**D2 — the `size` member name collides with `field_types.size = "dp"`.**

`SpecValidator.checkScalarFieldType` (`SpecValidator.kt:467-497`) keys the type table on
the bare member name at :470 and runs for every schema-listed member (:545-546), so
`{"t":"button","size":"medium"}` throws `size must be a finite number` today. Verified by
reading the file, not inferred.

| | A (recommended, drafted) | B |
|---|---|---|
| Wire name | `size`, matching Material 3, the ledger, and `jetpacs-button :size` | `size_class` (or `scale`) |
| `field_types` | `size` → `varies-per-node`, the `value`/`selected`/`fill`/`items` precedent | untouched; `size_class` gets no entry, like `variant` and `shape` |
| §17.1 | needs the two `numeric size` carve-outs above | no edit |
| Kotlin | needs the `icon.size` finite-number arm, or the check silently vanishes | no arm |
| Knock-on | G-08 (`icon_button.size`) rides free on the same demotion | G-08 must also be `icon_button.size_class`, and `icon.size` (dp) vs `icon_button.size_class` (enum) reads as an inconsistency forever |
| Hazard | `icon.size: 24` and `button.size: "medium"` sit one row apart in §17.4/§17.2 with different types | a vocabulary word nobody outside this spec uses |

**Recommendation: A.** `varies-per-node` exists for exactly this, four members already
use it, and the type-table cost is paid once for both G-01 and G-08. B is the safer
mechanical choice and stays on the table if the missing render-assertion harness makes
the demotion feel too quiet — the Companion has no Compose UI test infrastructure, so
nothing in the repo can assert what a demoted-and-restored check actually renders.

**D3 — does `button.size` mean the FAB scale inside `scaffold.fab`?**

| | A (recommended, drafted) | B |
|---|---|---|
| Meaning | `ButtonDefaults` tokens, in every position | `ButtonDefaults` normally; `FloatingActionButtonDefaults` when the node is the `scaffold.fab` slot |
| Unblocks now | 12 | 18 (the six `extended-fab` samples the ledger credits to G-01) |
| Cost | the six wait for G-68 (a `fab` node, or a fab-slot size member) | one member names two token families depending on where its node sits, and `Renderer.kt:728-730` must stop being a plain `RenderNode` call — which is G-68's work regardless |

**Recommendation: A.** A member whose meaning depends on its parent slot is the kind of
positional magic §16.1's document model has otherwise avoided, and the extended-FAB
samples need a real `ExtendedFloatingActionButton` at the slot before any size member
matters.

**Ratification caveats, recorded rather than resolved.**

- Every API here except `ElevatedButton` is `@ExperimentalMaterial3ExpressiveApi`:
  `shapes()`, `shapesFor()`, `contentPaddingFor()`, `iconSizeFor()`, `iconSpacingFor()`,
  `textStyleFor()`, `squareShape`, the five `*PressedShape` getters, and all four
  `*ContainerHeight` constants. A material3 alpha bump can rename or drop any of them
  with nothing in the repo to catch it.
- The dp values behind the step names are input-mode dependent: `ButtonDefaults.MinHeight`
  is 36dp rather than `ButtonSmallTokens.ContainerHeight`'s 40dp when
  `shouldUsePrecisionPointerComponentSizing` is set (`Button.kt:1059-1065`), and the
  small vertical padding likewise (`Button.kt:1652-1653`). The SPEC edits therefore name
  the scale by its steps and never by dp — correct, but it means the amendment cannot be
  conformance-tested by measuring pixels.
- `size` is the first member in the vocabulary that is a five-token coordinated set, and
  the Companion has no Compose UI test infrastructure. A half-applied `size` would pass
  every gate in the repo and would ship as false product text under an upstream sample's
  own name. The `MUST NOT apply the step partially` sentence in the §17.4 edit, and the
  `hasStartIcon` and pressed-shape requirements above, are the only things holding it.
---

## #157 — `icon_button` expressive geometry: `variant`, `size`, `shape`, `width_mode`

Drafted 2026-08-02 against the `ebp` tree pinned by llm-poc-2 (`ebp` HEAD `83d6e08`,
branch `m3-fidelity`), whose `SPEC-CHANGES.md` ends at **#152**. #153–#156 are
unratified drafts absent from this checkout; #157 assumes they ratify ahead of it
and touches no section they do. Every verbatim quote below was re-checked
character-for-character against this file and applies to it as it stands.

Source: `docs/AUDIT-m3-blockers-2026-08-02.md` gaps **G-02** (`icon_button.variant`,
score 9.0, `:93-96`) and **G-08** (`icon_button.size` + `icon_button.shape`, score 3.5,
`:131-135`).

**Scope note — one member is beyond the ledger.** G-08 as ledgered is `size` + `shape`;
`width_mode` appears nowhere in the audit as a gap. It is a fourth member this draft
ADDS, and it is not optional to the claim: three of the six samples cleared below pass
an explicit `IconButtonWidthOption`, and `MediumRoundWideIconButtonSample`
(`IconButtonSamples.kt:141-144`, `IconButtonDefaults.mediumContainerSize(IconButtonDefaults.IconButtonWidthOption.Wide)`)
is otherwise **not** cleared — without `width_mode` the honest unblocks count is 5, not 6.
A ratifier who wants #157 held to the ledger's literal shape should strike `width_mode`
and that sample together (decision D5).

Every renderer and Compose claim below was re-verified against the file and against the
`material3 1.5.0-alpha16` classes on the Companion's classpath
(`companion/gradle/libs.versions.toml:14`), not taken from the ledger.

### SPEC-CHANGES row (ready to paste)

> | 157 | 2026-08-02 | §17.1, §17.4 (cross-ref §12 rule 6, §16.1, §16.5, §24.4, §25; precedent #65, #66; contract) | **`icon_button` gains the container the M3 expressive family is made of.** §17.4's `icon_button` row carried `icon`, `on_tap`, `content_description`, `badge`, `enabled` — nothing that names a container — so `RenderIconButton` (`InputNodes.kt:99-114`) calls the bare `IconButton` unconditionally and builds its inner `Icon` (`:105-109`) with **no size modifier at all**. The whole expressive icon-button family is therefore unreachable from Emacs: the filled, tonal and outlined containers; the 32/40/56/96/136 dp container-height scale with its paired 20/24/24/32/40 dp icon steps; the round-versus-square container shape; and the Narrow/Uniform/Wide width option. Four OPTIONAL members close it. `variant` is `standard` (default), `filled`, `tonal`, or `outlined`, selecting `IconButton` / `FilledIconButton` / `FilledTonalIconButton` / `OutlinedIconButton` — the same four words map 1:1 onto the four `*IconToggleButton` composables that exist on the same classpath, so a later `checked` member reuses this vocabulary rather than minting a second. `size` is `xsmall`, `small`, `medium`, `large`, or `xlarge` and selects ONE step that sets both the container and the icon drawn inside it: one member, not two, because a container step alone would strand a 24 dp icon in a 96 dp button, which is precisely the defect the current renderer has by omission. `shape` is `round` or `square`. `width_mode` is `narrow`, `uniform`, or `wide` and stretches the container horizontally without changing its height; `uniform` is Compose's own default — verified in the 1.5.0-alpha16 bytecode, where `largeContainerSize-N-wlBFI$default` loads `IconButtonWidthOption.Uniform` — which is why upstream's `LargeRoundUniformOutlinedIconButtonSample` calls `largeContainerSize()` bare. All four are omissible and **every default is today's rendering**: a node omitting all four MUST produce exactly the call the Companion makes now, and the size scale is consulted only when at least one of `size`, `shape`, `width_mode` is present, so no existing traffic changes meaning. Each is a closed vocabulary whose §12 rule 6 fallback is to treat an unrecognized value as if the member were omitted — never guessed, never a whole-node rejection. The universal §16.5 attributes genuinely cannot substitute, though not for the reason a reader might assume: `width` and `height` DO constrain the rendered container (`Attributes.kt:140-141` imposes fixed constraints on the modifier the component receives as its own `modifier`, and the component's inner `.size(...)` is coerced into them), but nothing on the wire sizes the `Icon` inside an `icon_button`, so they yield a stretched box around an unchanged icon rather than the token-correct container-and-icon pairing, and they cannot express Narrow/Uniform/Wide, which are token widths and not author-chosen lengths; `corner` is consumed only by the universal `clip`/`bg`/`border` operations (`Attributes.kt:155`, `cornerShape` at `:93-108`) and is never passed to the component's own `shape` parameter, so it cannot produce the expressive round and square containers at all. One edit falls outside §17.4, forced by the member's name: §17.1 binds every field named `size` to a finite, non-negative `dp` and the contract projects `field_types.size: "dp"` — which the Companion's own `SpecValidator.checkScalarFieldType` enforces (`SpecValidator.kt:467-497`, the `"dp", "number"` arm at `:482`, scoped to the node's schema row at `:514`/`:545`), so `size: "medium"` on an `icon_button` would have drawn `1201 content-invalid` before ever reaching the renderer and the amendment would be dead on arrival. §17.1's two `size` sentences are accordingly qualified — the "boolean-valued `fill`" idiom already in that paragraph — and the projection is corrected to `varies-per-node`. **§24.4 disclosure:** this is a LOOSENING of the projection, stated rather than buried. `icon.size` loses its only structured type statement in `contract.json` and, with it, its runtime finite-number check at `SpecValidator.kt:482` (the member falls to the unchecked `else` at `:495`); the reference implementation re-adds the check as a node-specific `t == "icon" && member == "size"` arm, which moves a contract-expressed type into implementation code — the direction §24.4 argues against. This is **#66's mechanism applied for the opposite reason**: #66 corrected a projection that contradicted §17.5 text already in the spec, whereas #157 degrades a correct projection to make room for a new member, and accepts the debt because the alternative (a per-node `field_types` override map) changes the contract format and both generators and belongs in its own amendment. **§25 classification: additive within the major** — `icon_button.size`, `variant`, `shape`, and `width_mode` were unknown keys before this amendment, so no previously valid message changes meaning, and every one of the four has a named safe fallback. No existing golden, fixture, or message changes meaning. Enforcement named per #150/#151: `validate.py` enforces member MEMBERSHIP (an unknown key on `icon_button` fails, `validate.py:253-299`) and, with the severable `check_enum_values` arm below, the four vocabularies across the golden corpus; the §12 rule 6 fallback and the geometry itself are Companion behaviour, deferred to the reference implementation's rung and recorded here so the deferral is explicit, not silent. | contract `node_schema.icon_button.optional` += `variant`, `size`, `shape`, `width_mode`; `enums` += `icon_button.variant`, `icon_button.size`, `icon_button.shape`, `icon_button.width_mode`; `field_types.size` `dp` → `varies-per-node`, `field_types` += `width_mode: "enum"` and (projection completeness) `variant`/`shape`: `varies-per-node`; goldens/widgets.golden += 2 lines (75-76); the two GENERATED contract mirrors (`companion/wire/.../Vocabulary.kt`, `emacs/jetpacs-vocabulary.el`) regenerated by their tools, never hand-edited; validate.py `check_enum_values` arm (severable) | |

### SPEC.md edits

**1. §17.1, second paragraph** (line 2226) — the global "size is a number" rule is
qualified with the paragraph's own existing idiom. Replace:

> `width`, `height`, `size`, `radius`, and coordinate fields are finite numbers;

with:

> `width`, `height`, numeric-valued `size`, `radius`, and coordinate fields are finite numbers;

**2. §17.1, third paragraph** (lines 2235-2236) — the dp rule gains its one
exception. Replace:

> `size`, `spacing`, `run_spacing`, `content_padding`, `elevation`, and
> `thickness` are non-negative `dp`.

with:

> `size` on `icon_button` is a closed size-step vocabulary (Section 17.4) — the
> one member named `size` that is not a number, and the reason `contract.json`
> projects `size` as `varies-per-node`. Elsewhere `size`, `spacing`,
> `run_spacing`, `content_padding`, `elevation`, and `thickness` are
> non-negative `dp`.

*(The remainder of line 2236 — "An action-valued field MUST contain a valid" and the
sentence it begins — is untouched and still follows on the same line.)*

**3. §17.4, the input-node table** (line 2413). Replace:

> | `icon_button` | `icon: identifier`, `on_tap: ActionDescriptor` | `content_description`, `badge`, `enabled` |

with:

> | `icon_button` | `icon: identifier`, `on_tap: ActionDescriptor` | `content_description`, `badge`, `variant`, `size`, `shape`, `width_mode`, `enabled`. `variant`: `standard` (default), `filled`, `tonal`, or `outlined`. |

`variant`'s vocabulary is stated **here and nowhere else**, matching the `button` row
directly above it (line 2412), which likewise carries its vocabulary inline only. The
paragraph added by edit 4 does not restate it.

**4. §17.4, new paragraph** inserted immediately after the paragraph ending
(line 2440):

> `enabled` is boolean and defaults to `true` for every
> input node.

and immediately before (line 2442):

> `text_input.value` and `editor.value` default to the empty string.

Insert:

> `icon_button.size`, `icon_button.shape`, and `icon_button.width_mode` are the
> geometry members the table lists without an inline type. `size` selects one
> step of the icon-button size scale — `xsmall`, `small`, `medium`, `large`, or
> `xlarge` — and a step sets BOTH the container and the icon drawn inside it;
> they are one member because a container without its matching icon step is not
> the presented size. `shape` is `round` or `square`. `width_mode` is `narrow`,
> `uniform`, or `wide` and widens or narrows the container without changing its
> height. All three, and `variant`, are optional.
>
> A node that omits `size`, `shape`, and `width_mode` MUST render at the
> Companion's standard icon-button geometry — exactly what it rendered before
> these members existed. The size scale is consulted only when at least one of
> the three is present; where `shape` or `width_mode` is present without `size`,
> the `small` step supplies the geometry. An omitted `variant` is `standard`,
> which is likewise the prior rendering. Each of the four is a closed
> vocabulary: under Section 12 rule 6 an unrecognized value MUST be treated as
> if the member were omitted, and MUST NOT reject the node or be guessed at.
>
> These four members address the component's own container and the icon inside
> it, which the Section 16.5 universal attributes cannot reach. `corner` is
> consumed only by the universal `clip`, `bg`, and `border` operations and is
> never applied to the component's own shape, so it cannot produce the round and
> square containers. `width` and `height` do constrain the rendered container,
> but no universal attribute sizes the icon within an `icon_button`, so they
> produce a resized box around an unchanged icon rather than the paired
> container-and-icon step, and they cannot express the narrow, uniform, and wide
> width options, which are token values and not author-chosen lengths. Where
> both are authored the universal attributes take precedence over the selected
> step. A Companion MUST NOT let a selected step reduce the node's interactive
> target below the platform minimum.

*(Placement, since §17.1:2229-2230 routes an un-typed table member to "the
member-specific prose immediately after the table": the new paragraph is not
adjacent to the table — the MenuItem/EnumOption paragraph at 2426-2429 and the
input-node types paragraph at 2431-2440 intervene — but it sits immediately after the
paragraph that supplies types for every other un-typed input-node member, which is the
same block §17.1's rule is pointing at. Putting it anywhere else would separate these
three members' types from `single_line`'s and `document`'s.)*

### Artifact changes

**`ebp/contract.json`.** Four edits plus one correction; all verified to leave
`ebp/validate.py` green (run below).

1. `node_schema.icon_button.optional` (`contract.json:306`) — replace

```json
      "optional": [
        "content_description",
        "badge",
        "enabled"
      ]
```

with

```json
      "optional": [
        "content_description",
        "badge",
        "variant",
        "size",
        "shape",
        "width_mode",
        "enabled"
      ]
```

2. `enums` — insert immediately after the `button.variant` block (`contract.json:626`):

```json
    "icon_button.variant": [
      "standard",
      "filled",
      "tonal",
      "outlined"
    ],
    "icon_button.size": [
      "xsmall",
      "small",
      "medium",
      "large",
      "xlarge"
    ],
    "icon_button.shape": [
      "round",
      "square"
    ],
    "icon_button.width_mode": [
      "narrow",
      "uniform",
      "wide"
    ],
```

3. `field_types` (`contract.json:571`) — **the load-bearing correction.** Replace
   `"size": "dp",` with `"size": "varies-per-node",`. This is #66's *mechanism* — a
   global by-name map cannot hold a name that means two things, and
   `varies-per-node` is the contract's existing escape hatch (`value`, `items`,
   `fill`, `selected`) — applied for the opposite reason: #66 corrected a projection
   that contradicted the spec, this one degrades a correct projection. The §24.4 cost
   is disclosed in the row and again under *Companion implementation*. Without this
   change the Companion's `SpecValidator` rejects every authored `size` step with
   `1201`.

4. `field_types` — insert after `"keyboard": "enum",` (`contract.json:527`):

```json
    "width_mode": "enum",
    "variant": "varies-per-node",
    "shape": "varies-per-node",
```

   `width_mode` occurs on one node type, so `enum` matches the `keyboard`
   precedent. **`variant` and `shape` are a severable projection-completeness
   rider**: neither has a `field_types` entry today although `button.variant`,
   `progress.variant`, and `surface.shape` already appear in `enums`, and this
   amendment adds a third `variant` vocabulary and a second `shape` vocabulary.
   Recording them as `varies-per-node` is the #66 fix applied before the same
   defect recurs; dropping the two lines changes no behaviour (an absent key and
   `varies-per-node` both fall to `SpecValidator`'s unchecked `else` at
   `SpecValidator.kt:495`).

**`ebp/goldens/widgets.golden`** — two appended lines, ordinals 75 and 76 (the file
holds 75 lines, ordinals 00-74), key-sorted compact per the file's convention. The
per-node-type coverage floor was already met by line 37; these exercise the new
members at both ends of the scale and are the corpus the `check_enum_values` arm bites
on. Both were regenerated with
`json.dumps(obj, sort_keys=True, separators=(",", ":"))` and are byte-identical to it:

```
75 {"badge":"2","content_description":"Lock","icon":"lock","on_tap":{"action":"demo.tap"},"shape":"square","size":"xsmall","t":"icon_button","variant":"filled","width_mode":"narrow"}
76 {"content_description":"Lock","icon":"lock","on_tap":{"action":"demo.tap"},"shape":"round","size":"large","t":"icon_button","variant":"outlined","width_mode":"uniform"}
```

**Generated mirrors — regenerate, never hand-edit.** Both are drift-tested against
`contract.json` and MUST be regenerated in the same commit:

- `companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/Vocabulary.kt` via
  `python3 tools/gen-vocabulary.py` (`NODE_SCHEMA["icon_button"]` at
  `Vocabulary.kt:50`, `FIELD_TYPES["size"]` at `:153`).
  `SurfaceStoreTest.kt:734-752` asserts exact equality of both maps against
  `contract.json`, so a stale mirror fails the build.
- `emacs/jetpacs-vocabulary.el` via `python3 tools/gen-jetpacs-vocabulary.py` (the
  `icon_button` row at `:57`). The elisp mirror sorts the optional list, so the
  regenerated row reads
  `("icon_button" ("icon" "on_tap") ("badge" "content_description" "enabled" "shape" "size" "variant" "width_mode"))`.

**`ebp/validate.py` — no arm is REQUIRED.** `check_node` (`validate.py:253-299`)
derives the accepted key set from `node_schema` + `UNIVERSAL`, so the contract delta
alone admits the two new golden lines. **Dry run on a scratch copy of `ebp/`, contract
delta and both golden lines applied verbatim:**

```
OK: 40 frames, 77 widget lines, 7 hypertext nodes, 17 wire fixtures x3 chunkings validate (spec 2.0.0-draft, format 6); SPEC §8/§11 in sync; 9.3 KAT reproduced
```

**`ebp/validate.py` — optional `check_enum_values` arm (severable; see decision D4).**
`contract["enums"]` is read by nothing in `validate.py` today — and, per the same
audit, by nothing else in the tree either: neither generator projects it and
`Vocabulary.kt` stores only the type NAME `"enum"`. Without this arm the four new
vocabularies ship with zero in-repo enforcement, the #150/#151 defect class. The arm
is generic (it also retro-covers `text.style`, `button.variant`, `box.alignment`,
`arrange`, `align_self`, `dialog.style`, …).

Add beside the other module-level bindings, after
`NODE_SCHEMA = contract["node_schema"]` (`validate.py:40`):

```python
ENUMS = contract["enums"]
```

Add above `def check_node(...)` (`validate.py:253`):

```python
def check_enum_values(t: str, node: dict, path: str):
    """SPEC 12 rule 6 / 16.1: a closed-vocabulary member present with a value
    outside its vocabulary is malformed. Keyed `<type>.<member>` first, then
    the node-agnostic bare member name (`arrange`, `align_self`)."""
    for member, v in node.items():
        if not isinstance(v, str):
            continue
        vocab = ENUMS.get(f"{t}.{member}", ENUMS.get(member))
        if vocab is not None and v not in vocab:
            problem(f"{path}.{member}: `{v}` is not one of {vocab}")
```

and hook it as the first per-type check inside `check_node`'s `else` branch,
immediately before the `if t == "text_input" and value.get("single_line")` line:

```python
            check_enum_values(t, value, path)
```

*(The arm is deliberately value-typed: it skips non-string values, so `icon.size: 24`
and `chip.selected: true` are untouched.)*

**Verified, not asserted.** With the contract delta, both golden lines and the arm
applied to a scratch copy of `ebp/`, the clean run is unchanged
(`OK: 40 frames, 77 widget lines, …`, as above). Planting `"size":"gigantic"` in place
of `"size":"xsmall"` on golden ordinal 75 produces exactly:

```
widgets:75.size: `gigantic` is not one of ['xsmall', 'small', 'medium', 'large', 'xlarge']

FAIL: 1 problem(s)
```

Note the backticks — that is `problem()`'s f-string, not a transcription in quotes —
and the ordinal is the line the bad value was planted on.

### Companion implementation

**Two files. The renderer, and the reason the contract correction is not cosmetic.**

**(a) `SpecValidator` is why `field_types.size` must change, and what that costs.**
`companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/SpecValidator.kt:514`
takes the node's `NODE_SCHEMA` row and at `:545` loops
`for (member in row.required + row.optional)` into `checkScalarFieldType`
(`:467-497`), which switches on the **global** `FIELD_TYPES[member]`; the
`"dp", "number"` arm at `:482` throws `ContentInvalid` unless the member reads as a
finite number. Adding `size` to `icon_button.optional` while `field_types.size` stays
`"dp"` therefore makes `{"t":"icon_button","size":"medium",…}` a whole-surface `1201`
— the members would never reach `RenderIconButton`. With `varies-per-node` the member
falls to the unchecked `else` at `:495`, alongside every other enum-valued member.

**Cost, disclosed as a §24.4 loosening:** `icon.size` loses both its projected type and
its finite-number back-stop. The mitigation is one arm at the same site, no contract
change — but it is Companion-side and does **not** land with the `ebp` commit, so
between ratification and the implementation rung `icon.size: "big"` is accepted on the
wire and folded into a default by the renderer's defaulting read:

```kotlin
// #157: `size` is dp on `icon`, a step vocabulary on `icon_button`; the
// global FIELD_TYPES map cannot say both (contract: varies-per-node).
if (t == "icon" && member == "size")
    node[member]?.asDoubleOrNull()
        ?.takeIf { it.isFinite() } ?: throw ContentInvalid(p, "size must be a finite number")
```

**(b) `InputNodes.kt:97-114`, `RenderIconButton` — the whole amendment.**
Today the function calls one composable and sizes nothing:

```kotlin
    IconButton(
        onClick = { onButton(node.objOrNull("on_tap"), ctx) },
        enabled = node.boolOr("enabled", true),
        modifier = m) {
        val icon: @Composable () -> Unit = {
            Icon(IconMap.get(node.stringOr("icon")),
                contentDescription = node.stringOr("content_description")
                    .takeIf { it.isNotEmpty() })
        }
```

The replacement keeps that exact call as the no-members path and adds the step
derivation around it. Every API named is present in `material3 1.5.0-alpha16`,
verified by `javap` on the unpacked classes:

```kotlin
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderIconButton(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val badge = node.stringOr("badge")
    val onClick = { onButton(node.objOrNull("on_tap"), ctx) }
    val enabled = node.boolOr("enabled", true)
    // §12 rule 6: an unrecognized value is treated as if the member were omitted.
    val step = node.stringOr("size").takeIf { it in ICON_BUTTON_STEPS }
    val shapeWord = node.stringOr("shape").takeIf { it == "round" || it == "square" }
    val widthWord = node.stringOr("width_mode")
        .takeIf { it == "narrow" || it == "uniform" || it == "wide" }
    val geometry = step != null || shapeWord != null || widthWord != null
    val s = step ?: "small"                       // §17.4: the step for shape-only nodes
    val w = when (widthWord) {
        "narrow" -> IconButtonDefaults.IconButtonWidthOption.Narrow
        "wide"   -> IconButtonDefaults.IconButtonWidthOption.Wide
        else     -> IconButtonDefaults.IconButtonWidthOption.Uniform
    }
    val container: DpSize? = if (!geometry) null else when (s) {
        "xsmall" -> IconButtonDefaults.extraSmallContainerSize(w)
        "medium" -> IconButtonDefaults.mediumContainerSize(w)
        "large"  -> IconButtonDefaults.largeContainerSize(w)
        "xlarge" -> IconButtonDefaults.extraLargeContainerSize(w)
        else     -> IconButtonDefaults.smallContainerSize(w)
    }
    val square = shapeWord == "square"
    val shape: Shape? = if (!geometry) null else when (s) {
        "xsmall" -> if (square) IconButtonDefaults.extraSmallSquareShape
                    else IconButtonDefaults.extraSmallRoundShape
        "medium" -> if (square) IconButtonDefaults.mediumSquareShape
                    else IconButtonDefaults.mediumRoundShape
        "large"  -> if (square) IconButtonDefaults.largeSquareShape
                    else IconButtonDefaults.largeRoundShape
        "xlarge" -> if (square) IconButtonDefaults.extraLargeSquareShape
                    else IconButtonDefaults.extraLargeRoundShape
        else     -> if (square) IconButtonDefaults.smallSquareShape
                    else IconButtonDefaults.smallRoundShape
    }
    val iconSize: Dp? = when (step) {          // the step the Icon has never had
        "xsmall" -> IconButtonDefaults.extraSmallIconSize
        "small"  -> IconButtonDefaults.smallIconSize
        "medium" -> IconButtonDefaults.mediumIconSize
        "large"  -> IconButtonDefaults.largeIconSize
        "xlarge" -> IconButtonDefaults.extraLargeIconSize
        else     -> null
    }
    // §17.4: `m` stays OUTERMOST so an authored §16.5 width/height still binds.
    // The chain is upstream's own, from ExtraSmallNarrowSquareIconButtonsSample
    // (IconButtonSamples.kt:105-112): minimumInteractiveComponentSize() reports
    // max(child, 48.dp) WITHOUT shrinking the child, so a 32 dp xsmall container
    // keeps its 48 dp touch target — the §17.4 platform-minimum MUST.
    val mm = if (container == null) m
             else m.minimumInteractiveComponentSize().size(container)
    val content: @Composable () -> Unit = {
        val icon: @Composable () -> Unit = {
            Icon(IconMap.get(node.stringOr("icon")),
                contentDescription = node.stringOr("content_description")
                    .takeIf { it.isNotEmpty() },
                modifier = if (iconSize != null) Modifier.size(iconSize) else Modifier)
        }
        if (badge.isNotEmpty())
            BadgedBox(badge = { Badge { Text(badge) } }) { icon() }
        else icon()
    }
    when (node.stringOr("variant")) {
        "filled"   -> if (shape == null) FilledIconButton(onClick, mm, enabled) { content() }
                      else FilledIconButton(onClick, mm, enabled, shape) { content() }
        "tonal"    -> if (shape == null) FilledTonalIconButton(onClick, mm, enabled) { content() }
                      else FilledTonalIconButton(onClick, mm, enabled, shape) { content() }
        "outlined" -> if (shape == null) OutlinedIconButton(onClick, mm, enabled) { content() }
                      else OutlinedIconButton(onClick, mm, enabled, shape) { content() }
        else       -> if (shape == null) IconButton(onClick, mm, enabled) { content() }
                      else IconButton(onClick, mm, enabled, shape = shape) { content() }
    }
}

private val ICON_BUTTON_STEPS =
    setOf("xsmall", "small", "medium", "large", "xlarge")
```

**Why the arms differ, precisely.** `javap IconButtonKt` on the alpha16 aar gives
`FilledIconButton(Function0, Modifier, boolean, Shape, IconButtonColors,
MutableInteractionSource, content)` and `OutlinedIconButton(Function0, Modifier,
boolean, Shape, IconButtonColors, BorderStroke, MutableInteractionSource, content)` —
`shape` is a **defaulted fourth parameter**, so the positional four-argument call binds
it and the three-argument call takes `IconButtonDefaults`' default. The standard
`IconButton` orders its parameters `(onClick, modifier, enabled, colors,
interactionSource, shape, content)`, which is why that arm alone needs a named
argument. These are not shapeless/shape-bearing overload *pairs*: the second overload
each of the four carries takes `IconButtonShapes` (the animated-shape API), not
`Shape`, and is not used here. The shapeless standard `IconButton` in the source is
`@Deprecated(level = HIDDEN)` (`IconButton.kt:85-91`) and resolves to the shape form
with `IconButtonDefaults.standardShape` — which is exactly today's rendering.

`IconButtonDefaults` supplies `extraSmall|small|medium|large|extraLargeContainerSize(IconButtonWidthOption)`,
the ten `…RoundShape`/`…SquareShape` getters, the five `…IconSize` values, and the
`IconButtonWidthOption` companion (`Narrow=0`, `Uniform=1`, `Wide=2`). Token geometry,
read out of `tokens/*IconButtonTokens.kt`: container heights 32 / 40 / 56 / 96 / 136 dp,
icons 20 / 24 / 24 / 32 / 40 dp. (The container *width* varies with the width option;
the height is the fixed token.)

New imports: `FilledIconButton`, `FilledTonalIconButton`, `OutlinedIconButton`,
`IconButtonDefaults`, `ExperimentalMaterial3ExpressiveApi`,
`minimumInteractiveComponentSize`, `androidx.compose.ui.graphics.Shape`,
`androidx.compose.ui.unit.Dp`, `androidx.compose.ui.unit.DpSize`. This is the tree's
**first** `ExperimentalMaterial3ExpressiveApi` opt-in (only `ExperimentalMaterial3Api`
appears today, `InputNodes.kt:39`).

**Emacs-side co-requisite** (llm-poc-2, not `ebp`), stated at its real cost:

- The regenerated `emacs/jetpacs-vocabulary.el` row keeps the generator's drift test
  green and is what a `&rest`-children *container* constructor would need. It does
  **nothing** for this node: `jetpacs--check-options` (`emacs/jetpacs-widgets.el:370-393`)
  is reached only through `jetpacs--children-and-opts`, and its own docstring says the
  `cl-defun &key` constructors "have always refused an unknown keyword".
- `jetpacs-icon-button` (`emacs/jetpacs-widgets.el:1000-1009`) accepts the four new
  keywords only because its `cl-defun … &key` list gains `:variant`, `:size`, `:shape`,
  `:width-mode` — a hand edit, not a regeneration.
- Value checking is a **second, unmirrored copy of every vocabulary this amendment
  mints**. `jetpacs-vocabulary.el` projects `jetpacs-node-schema` only — it has no
  `enums` at all — so the four value sets cannot be generated. They must be four
  hand-maintained constants in the `jetpacs--button-variants` style
  (`emacs/jetpacs-widgets.el:985`), each fed to `jetpacs--check-enum` (`:253`) the way
  `jetpacs-button` does at `:995`. That duplication is a real maintenance cost and is
  the direct consequence of `enums` being read by nothing.
- Each member is emitted only when non-nil, so the wire form of an unadorned icon
  button is byte-identical to today's.

### Unblocks

**Cleared outright by #157 — 6, all in `icon-buttons`** (module goes 1/12 → 7/12
buildable; the file holds 12 `jetpacs-m3-example` forms, 11 of them `:unsupported`).
Each upstream body was read in full and needs nothing beyond these four members plus
`content_description`:

| slug (repo) | members it needs | ledger | upstream body |
|---|---|---|---|
| `FilledIconButtonSample` | `variant:"filled"` | G-02, sole gap | `IconButtonSamples.kt:263` |
| `FilledTonalIconButtonSample` | `variant:"tonal"` | G-02, sole gap | `:353` |
| `OutlinedIconButtonSample` | `variant:"outlined"` | G-02, sole gap | `:446` |
| `MediumRoundWideIconButtonSample` | `size:"medium"`, `shape:"round"`, `width_mode:"wide"` (plain `IconButton`) | G-08 + the beyond-ledger `width_mode` | `:129` |
| `XSmallNarrowSquareIconButtonsSample` | `variant:"filled"`, `size:"xsmall"`, `shape:"square"`, `width_mode:"narrow"` | G-02 + G-08 | `:95` |
| `LargeRoundUniformOutlinedIconButtonSample` | `variant:"outlined"`, `size:"large"`, `shape:"round"`, `width_mode:"uniform"` | G-02 + G-08 | `:161` |

Two naming notes, so the divergence is on the record rather than silent. The table uses
the **repo slug** `XSmallNarrowSquareIconButtonsSample`, which is what
`emacs/apps/m3-catalog/jetpacs-m3-icon-buttons.el:119` and
`docs/AUDIT-m3-blockers-2026-08-02.md:96` both key on; upstream names the same function
`ExtraSmallNarrowSquareIconButtonsSample` (`IconButtonSamples.kt:95`). And the
`MediumRoundWideIconButtonSample` row is the one that depends on `width_mode`: strike
that member and this row goes with it (5 cleared, not 6). The tooltip wrapper every
sample carries is `content_description`, which the node already has (#145).

**Advanced but NOT cleared — 8**, each still short exactly one other gap:

- `FilledIconToggleButtonSample`, `FilledTonalIconToggleButtonSample`,
  `OutlinedIconToggleButtonSample` — need **G-09** (`checked` / `on_change` /
  `checked_icon`). #157's `variant` vocabulary is written to serve them unchanged;
  `FilledIconToggleButton`, `FilledTonalIconToggleButton` and `OutlinedIconToggleButton`
  are all on the same alpha16 classpath.
- split-button/`ElevatedSplitButtonSample` — needs **G-05** (`button.variant` +=
  `elevated`).
- split-button/`XSmall`, `Medium`, `Large`, `ExtraLargeFilledSplitButtonSample`
  — need **G-01** (`button.size`) for the leading half.

Union of G-02 (9) and G-08 (7), less the 2 they share: **14 examples in which #157 is a
required ingredient**, 6 of them completed by it. The four split-button samples are
reachable only via the fused row-plus-per-corner recreation (G-84's note), which this
draft did not independently re-verify as faithful.

**Reason-string co-requisite (catalog side, llm-poc-2, not an `ebp` artifact).**
Ratification makes five product strings in
`emacs/apps/m3-catalog/jetpacs-m3-icon-buttons.el` false: `--variant-note` (`:39-41`),
`--variant-toggle-note` (`:47-49`), `--size-note` (`:51-53`), and the per-example
strings at `:124` and `:137`. Six examples become `:build`; the three toggle strings
must be narrowed to name `checked` alone (`--toggle-note` at `:43-45` is correct as it
stands and is left untouched). `--size-note` is stale **twice over** — it says
"The icon_button node has no size or shape member" (now false) *and* enumerates the
scale as "extraSmall through large", which is wrong independently of the members'
existence under decision D2's five steps. It is deleted outright with its two consumers
becoming `:build`; if any variant of its wording survives elsewhere it must also stop
saying "extraSmall through large". Per `PLAN-m3-catalog-verification.md` a stale reason
string is a defect, not a comment nit.

### Design decisions required

A is recommended and the draft above is written as A throughout.

| # | Decision | A (recommended) | B |
|---|---|---|---|
| D1 | The member name `size`, which collides with §17.1's global "fields named `size` are non-negative dp" rule and with `field_types.size: "dp"`, which `SpecValidator.kt:482` actually enforces | Keep `size`. Qualify §17.1 with its own "boolean-valued `fill`" idiom and correct the projection to `varies-per-node`. Matches upstream's word, the ledger, and the `button.size` G-01 will ask for next. **Cost, now disclosed as a §24.4 loosening in the row:** `icon.size` loses its projected type and its `SpecValidator` finite-number check; the check returns only as a hardcoded node-specific arm in the reference implementation, which lands on a later rung | Name it `size_step`. No §17.1 edit, no §24.4 loosening, `icon.size` keeps its projected type and its check — but it diverges from upstream and from the ledger, and G-01 must then adopt `button.size_step` or the two nodes disagree |
| D2 | How many steps `icon_button.size` names | Five — `xsmall`…`xlarge`. `extraLargeContainerSize`, `extraLargeIconSize`, and `extraLargeRoundShape`/`SquareShape` are all on the 1.5.0-alpha16 classpath (136 dp container / 40 dp icon), and five matches the `button.size` scale G-01 specifies, so the two members share one vocabulary | Four — `xsmall`…`large`, the ledger's literal G-08 shape. Covers every catalog example today but guarantees a second amendment the moment an xlarge icon button is authored |
| D3 | Whether the `variant` enum spells its own default | Four values, `standard` (default), `filled`, `tonal`, `outlined`. Exactly parallel to `button.variant`, which names `filled` as both a value and the default, and it gives §12 rule 6 a named value to describe the fallback with | Three values (G-02's literal shape), leaving the default unnamed and unauthorable — an author cannot say "explicitly standard" |
| D4 | Whether the generic `validate.py` `check_enum_values` arm lands with this amendment | Land it. Without it the four vocabularies have **zero** in-repo enforcement — `contract["enums"]` is read by `validate.py`, by both generators, and by `Vocabulary.kt` not at all — which is precisely the stated-versus-actual enforcement gap #150/#151 institutionalized against. Verified green on the full corpus and verified to bite on a planted bad value | Defer it. Smaller diff, but the amendment then ships four closed vocabularies nothing checks, and the row's enforcement sentence must say so plainly |
| D5 | Whether `width_mode` — a member the ledger does not list under G-08 — may ride this amendment | Include it. Three of the six cleared samples pass an explicit `IconButtonWidthOption`, and `MediumRoundWideIconButtonSample` is not buildable without it. The scope drift is declared in the header rather than folded into a G-id | Strike it. #157 then matches G-08 exactly, `field_types` gains no `width_mode` key, and the honest unblocks count drops from 6 to 5 |

*(A third shape for D1, recorded and not drafted: give `contract.json` a per-node
`field_types` override map so `size` can be `dp` on `icon` and `enum` on `icon_button`
without either losing its check. Structurally the right fix — `varies-per-node` is a
wart, not a design, and §24.4 is on its side — but it changes the contract format,
`tools/gen-vocabulary.py`, `tools/gen-jetpacs-vocabulary.py`, `Vocabulary.kt`'s shape,
`SpecValidator`, and `validate.py`. It belongs in its own amendment, not riding a widget
row.)*

*(Two risks that are not decisions and have no A/B: the names this vocabulary is minted
from — `extraSmallContainerSize`, `IconButtonWidthOption`, the ten shape getters — are
`@ExperimentalMaterial3ExpressiveApi` on a 1.5.0-alpha library and have already churned
once since 1.4.0; a later alpha can rename them with no deprecation cycle and strand the
SPEC vocabulary on words the platform no longer uses. And the Companion has no Compose
UI test infrastructure, so nothing in the repo can assert that a `size:"large"` node
renders a 96 dp container. These four members' only failure mode is silent — the class
in which `hint`, `align_self` and half of `surface.elevation` rotted while every gate
stayed green.)*
---

## #158 — toggle state on `button` and `icon_button`

Covers ledger gaps **G-04** (`button.checked` + `button.on_change`, score 6.5 / 13 appearances) and
**G-09** (`icon_button.checked` + `on_change` + `checked_icon`, score 3.0 / 6 appearances) from
`docs/AUDIT-m3-blockers-2026-08-02.md:105-115` and `:137-142`.

**⚠ Design decision required: what a toggle tap dispatches.** Two candidates; A is drafted. Table at
the end.

### SPEC-CHANGES row (ready to paste)

> | 158 | 2026-08-02 | §17.4, §14.6, §13.5, §13.6 (cross-ref §16.1, §16.4, §17.1, §17.2, §18.1, §12 rule 1, §25; contract) | **`button` and `icon_button` gain a toggle form.** Material 3's expressive vocabulary makes the toggle button and the icon toggle button first-class controls and EBP could express neither: `contract.json:295-305`/`:306-316` gave `button` only `icon`/`variant`/`enabled` and `icon_button` only `content_description`/`badge`/`enabled`, so `InputNodes.kt:89-94` always built a stateless `Button`/`TextButton`/`OutlinedButton`/`FilledTonalButton` and `InputNodes.kt:101-104` always built a plain `IconButton` — nineteen catalog examples, including every one of the ten `togglebuttons` samples, had no wire to sit on. Both node types gain OPTIONAL `checked` (boolean; `field_types.checked` is already `boolean`; **default `false`**) and OPTIONAL `on_change` (an ActionDescriptor by §17.1's `on_` rule, already in `actions.hook_keys`); `icon_button` additionally gains OPTIONAL `checked_icon` (an identifier — stated inline because §17.1 types only the member literally named `icon`), drawn in place of `icon` while checked and falling back to `icon` when absent. **Omitting all three preserves today's rendering exactly**, so no existing traffic changes meaning: a node with no `checked` is the same stateless button it is now, down to the `PaddingValues(horizontal = 12.dp, vertical = 8.dp)` at `InputNodes.kt:80`. The state machine is `checkbox`'s, not a new one: when `checked` is accompanied by the universal `id`, the node becomes a stateful node under §14.6 — the Companion holds the flipped boolean on the device keyed by `(surface, id)`, seeds it from the store and then from the authored member exactly as `RenderCheckbox` does at `InputNodes.kt:185-210`, and every flip publishes `state.changed` with the boolean **before** any action, the §14.6 state-before-action ordering the single dispatch executor already enforces by FIFO. Each tap dispatches exactly one action — `on_change` with the boolean in `args.value` when present, otherwise the required `on_tap` unchanged — so a message that could legally exist before this amendment behaves identically after it; because `on_change` suppresses `on_tap`, §17.1's hidden-action rule governs that unreached `on_tap`. `checked` **without** an `id` is not an error: the node has no wire address to publish on, so `checked` is authored presentation only, the Companion MUST NOT flip it locally, and the tap dispatches as it does today — the `chip.selected` model already in the same table. Requiring `id` was rejected because `button` is a Core Node Set type and the requirement would invalidate a previously valid core message, which §25's first classification bullet makes a protocol major. Statefulness is therefore **conditional**, mirroring §14.6's existing "an `editor` whose `publish_state` is `true`" clause; that is what keeps ordinary buttons legal inside `stale_spec` (§13.5 now says so explicitly, because a set-membership strip rather than a predicate would silently delete every button from every stale presentation) and what gives §13.6 an exact compatibility rule (boolean value; a snapshot that drops `checked` leaves a non-stateful node and erases the draft). §16.1's duplicate-stateful-ID rejection and §18.1's dialog-local state rule then apply to toggles with no further text. No monotonically consumed resource is created (§25): the device-held booleans enter the same `(surface, id)` input-state map as `checkbox`, bounded by `max_input_state_bytes` and reclaimed by §13.6's four erasure conditions and by surface tombstoning. Enforcement (§25): `ebp/validate.py`'s `check_node` (:279-287) gates the new members against `node_schema` across `goldens/widgets.golden`; `SpecValidator.kt:707-721` performs the device-side stateful registration and the §13.5 `stale_spec` rejection at `:190-191`; `SurfaceStore.kt:467-496` (`compatible`) and `:509-517` (`authoredValueOf`) enforce §13.6's new bullet and supply the toggle's authored value to `welcome.input_state` and to `capture_fields`; `VocabularyDriftTest` (`SurfaceStoreTest.kt:727-745`) and `jetpacs-widgets/catalog-node-schema` re-read the contract so the generated `Vocabulary.kt` and `jetpacs-vocabulary.el` cannot drift. **No repo test can assert that a toggle renders checked** — the Companion has no Compose UI test infrastructure (`AUDIT-m3-blockers-2026-08-02.md:56-64`); the enforcement above is wire- and data-level only. Additive under §25's second bullet: three new OPTIONAL non-constraining members whose omission is today's behaviour. | contract `node_schema.button.optional` += `checked`, `on_change`; `node_schema.icon_button.optional` += `checked`, `on_change`, `checked_icon`; `field_types` += `checked_icon: identifier`; goldens/widgets.golden += 4 lines (75–78); validate.py needs no new arm; `tools/gen-vocabulary.py:63-64`'s hardcoded `STATEFUL_NODE_TYPES` literal += `button`, `icon_button` and `Vocabulary.kt` + `jetpacs-vocabulary.el` regenerated; `SpecValidator.kt` `isStateful` becomes a per-type predicate; `SurfaceStore.kt` `compatible`/`authoredValueOf` gain toggle arms; `emacs/jetpacs-shell.el`'s `jetpacs-shell--stateful-types` flat list becomes a predicate; `emacs/jetpacs-widgets.el` `jetpacs-button`/`jetpacs-icon-button` gain the new `&key`s; `test/jetpacs-widgets-test.el` `jetpacs-widgets/input-goldens` += 4 arms | |

### SPEC.md edits

**1. §17.4 — the vocabulary table rows.** Replace (SPEC.md:2412-2413):

> ```
> | `button` | `label: string`, `on_tap: ActionDescriptor` | `icon`, `variant`, `enabled`. `variant`: `filled` (default), `tonal`, `outlined`, or `text`. |
> | `icon_button` | `icon: identifier`, `on_tap: ActionDescriptor` | `content_description`, `badge`, `enabled` |
> ```

with:

> ```
> | `button` | `label: string`, `on_tap: ActionDescriptor` | `icon`, `variant`, `enabled`, `checked`, `on_change`. `variant`: `filled` (default), `tonal`, `outlined`, or `text`. |
> | `icon_button` | `icon: identifier`, `on_tap: ActionDescriptor` | `content_description`, `badge`, `enabled`, `checked`, `on_change`, `checked_icon: identifier` |
> ```

**2. §17.4 — the toggle semantics.** After the paragraph at SPEC.md:2496-2498:

> ```
> `checkbox.checked` and `switch.checked` default to `false`. Every flip MUST
> produce `state.changed`; when `on_change` is present it MUST also produce an
> action with the boolean in `args.value`, after the state notification.
> ```

insert:

> A `button` or `icon_button` carrying `checked` is a toggle. `checked` is a
> boolean and defaults to `false`; omitting it leaves the node exactly as
> specified above, with no toggle behavior of any kind. A Companion rendering a
> toggle MUST make the checked state visibly distinct from the unchecked state
> and MUST carry that distinction into the node's accessibility meaning under
> Section 16.4. For a `button`, the toggle affordance MUST preserve the node's
> `variant`: where a `variant` has no distinct toggle container in the
> platform's design system, the Companion MUST still render that variant's
> container and carry the checked state through its own color treatment; it
> MUST NOT substitute a different variant's container.
>
> When `checked` is accompanied by a universal `id`, the node is a stateful node
> under Section 14.6: the Companion holds the flipped value on the device keyed
> by surface and `id`, reconciles it under Section 13.6, and every flip MUST
> produce `state.changed` carrying the new boolean before any action from that
> flip. Without an `id` the node has no wire address, so `checked` is authored
> presentation only: the Companion MUST NOT hold or flip a local value, the
> rendered state follows the authored `checked` until a later snapshot changes
> it, and the tap dispatches exactly as it does for a non-toggle node. Emacs
> SHOULD supply an `id` for any toggle whose state the user is meant to change.
>
> A tap on a toggle dispatches exactly one action: `on_change`, with the new
> boolean in `args.value`, when `on_change` is present; otherwise `on_tap`,
> unchanged. It MUST NOT dispatch both. `on_change` is an ActionDescriptor and
> has no effect on a node that omits `checked`. Because a toggle carrying
> `on_change` never dispatches its REQUIRED `on_tap`, that `on_tap` MUST still
> be a valid descriptor and Emacs MUST NOT make it the only path to
> load-bearing behavior, under Section 17.1's hidden-action rule.
>
> `icon_button.checked_icon` is an icon identifier drawn in place of `icon`
> while `checked` is true. When it is absent, `icon` is drawn in both states. An
> unresolvable `checked_icon` degrades exactly as any other unresolvable icon
> identifier under Section 17.2, and a Companion MUST NOT reject the node for
> it. `content_description` describes the control, not the current state, and
> applies to both icons.

**3. §14.6 — the stateful-node roster.** Replace (SPEC.md:1853-1855):

> ```
> `surface`, `revision_seen`, `id`, and `value` are REQUIRED. Stateful nodes are
> `text_input`, `checkbox`, `switch`, `enum_list`, and `slider`, plus an `editor`
> whose `publish_state` is `true`. Widget IDs MUST be unique among stateful nodes
> ```

with:

> ```
> `surface`, `revision_seen`, `id`, and `value` are REQUIRED. Stateful nodes are
> `text_input`, `checkbox`, `switch`, `enum_list`, and `slider`, plus an `editor`
> whose `publish_state` is `true` and a `button` or `icon_button` carrying both
> `checked` and an `id`. Widget IDs MUST be unique among stateful nodes
> ```

**4. §14.6 — the publication duty.** Replace (SPEC.md:1861-1862):

> ```
> A checkbox or switch MUST publish after each flip; an `enum_list` after each
> settled selection; and a slider after the user commits a gesture. An editor
> ```

with:

> ```
> A checkbox, a switch, or a toggling `button` or `icon_button` MUST publish
> after each flip; an `enum_list` after each
> settled selection; and a slider after the user commits a gesture. An editor
> ```

**5. §13.5 — the `stale_spec` carve-out.** Replace (SPEC.md:1502-1503):

> ```
> `stale_spec` MUST NOT contain a stateful node or any `editor`, regardless of
> `publish_state` or `document`. The accepted primary `spec`
> ```

with:

> ```
> `stale_spec` MUST NOT contain a stateful node or any `editor`, regardless of
> `publish_state` or `document`. A `button` or `icon_button` is excluded only
> when it carries both `checked` and an `id`; every other one is not a stateful
> node and remains permitted. The accepted primary `spec`
> ```

**6. §13.6 — value-schema compatibility.** Replace (SPEC.md:1536-1537):

> ```
> - `checkbox` and `switch` remain compatible with the same node type because
>   their value is boolean;
> ```

with:

> ```
> - `checkbox` and `switch` remain compatible with the same node type because
>   their value is boolean;
> - a toggling `button` or `icon_button` requires `checked` present in both
>   snapshots, because its value is boolean; a snapshot that omits `checked`
>   leaves a node that is not stateful and MUST erase the draft;
> ```

### Artifact changes

**`ebp/contract.json`** — `node_schema.button` (:295-305) becomes:

> ```json
>     "button": {
>       "required": [
>         "label",
>         "on_tap"
>       ],
>       "optional": [
>         "icon",
>         "variant",
>         "enabled",
>         "checked",
>         "on_change"
>       ]
>     },
> ```

`node_schema.icon_button` (:306-316) becomes:

> ```json
>     "icon_button": {
>       "required": [
>         "icon",
>         "on_tap"
>       ],
>       "optional": [
>         "content_description",
>         "badge",
>         "enabled",
>         "checked",
>         "on_change",
>         "checked_icon"
>       ]
>     },
> ```

`field_types` — insert one entry immediately after `"icon": "identifier"` (:522):

> ```json
>     "icon": "identifier",
>     "checked_icon": "identifier",
> ```

`field_types.checked` is already `"boolean"` (:562) and needs no edit. `actions.hook_keys` already
contains `on_change` and needs no edit. **No `enums` entry, no `theme_roles` entry, no
`universal_node_attributes` entry, no `limits` or `capabilities` change** — this amendment adds no
closed vocabulary, so §12 rule 6 has nothing to fall back from. (`field_types` is a flat bare-name
map, so `checked_icon: identifier` types that name globally; no other node type uses it, and the
member is only reachable where `node_schema` lists it.)

**`ebp/goldens/widgets.golden`** — append four lines (the last existing line is `74`; keys in
canonical sorted order, matching the corpus):

> ```
> 75 {"checked":true,"id":"fmt_bold","label":"Bold","on_change":{"action":"fmt.bold"},"on_tap":{"action":"fmt.bold"},"t":"button","variant":"tonal"}
> 76 {"checked":true,"label":"Bold","on_tap":{"action":"fmt.bold"},"t":"button"}
> 77 {"checked":true,"checked_icon":"favorite","content_description":"Favorite","icon":"favorite_border","id":"fav","on_change":{"action":"fav.set"},"on_tap":{"action":"fav.toggle"},"t":"icon_button"}
> 78 {"checked":false,"icon":"lock","id":"lock_ib","on_tap":{"action":"lock.toggle"},"t":"icon_button"}
> ```

`75` is the maximal stateful toggle button; `76` is the id-less authored-presentation arm the draft
deliberately keeps legal; `77` is the maximal icon toggle including `checked_icon`; `78` is an icon
toggle with no `on_change`, exercising the `on_tap`-fallback dispatch. Lines `35`–`37` (the existing
`button`/`icon_button` rows) are untouched, so the corpus still pins today's meaning.

**`ebp/validate.py`** — **no new arm required.** `check_node` (:279-287) derives required/optional
keys from `node_schema`, so the four new lines validate the moment the contract delta lands, and the
coverage floor (:757-762) is already satisfied for both types. There is deliberately no
`checked`-implies-`id` arm to write: that combination stays valid by design (see the design-decision
note).

**`emacs/jetpacs-widgets.el` — the sender-side builders (REQUIRED; not generated).**
`jetpacs-button` (:988) and `jetpacs-icon-button` (:1000) are hand-written `cl-defun`s whose `&key`
lists mirror `node_schema` one-for-one. Without this edit no Emacs program can author the new
members and none of the examples below can be written at all:

> ```elisp
> (cl-defun jetpacs-button (label on-tap &key icon variant enabled checked on-change)
>   ...
>   (when checked (jetpacs--check-bool checked ":checked"))
>   (when on-change (jetpacs--check-descriptor on-change ":on-change"))
>   (jetpacs--node "button" :label label :on_tap on-tap
>                  :icon icon :variant variant :enabled enabled
>                  :checked checked :on_change on-change))
>
> (cl-defun jetpacs-icon-button (icon on-tap &key content-description badge enabled
>                                            checked on-change checked-icon)
>   ...
>   (when checked (jetpacs--check-bool checked ":checked"))
>   (when on-change (jetpacs--check-descriptor on-change ":on-change"))
>   (when checked-icon (jetpacs--check-identifier checked-icon ":checked_icon"))
>   (jetpacs--node "icon_button" :icon icon :on_tap on-tap
>                  :content_description content-description :badge badge :enabled enabled
>                  :checked checked :on_change on-change :checked_icon checked-icon))
> ```
>
> `jetpacs--node` (:332-345) drops nil-valued pairs and preserves `:json-false`, so `:checked
> :json-false` emits `"checked":false` and an omitted `:checked` emits nothing — the same mechanism
> `jetpacs-checkbox` (:1093) already relies on. The universal `id` still rides in through
> `jetpacs-with-attrs` (:427), exactly as it does for every other node.

**`test/jetpacs-widgets-test.el`** — `jetpacs-widgets/input-goldens` (:257-270) asserts byte
identity between each builder and its golden line; the four new lines need four new arms:

> ```elisp
> (chk "75" (jetpacs-with-attrs
>            (jetpacs-button "Bold" (jetpacs-action "fmt.bold")
>                            :variant 'tonal :checked t
>                            :on-change (jetpacs-action "fmt.bold"))
>            :id "fmt_bold"))
> (chk "76" (jetpacs-button "Bold" (jetpacs-action "fmt.bold") :checked t))
> (chk "77" (jetpacs-with-attrs
>            (jetpacs-icon-button "favorite_border" (jetpacs-action "fav.toggle")
>                                 :content-description "Favorite" :checked t
>                                 :checked-icon "favorite"
>                                 :on-change (jetpacs-action "fav.set"))
>            :id "fav"))
> (chk "78" (jetpacs-with-attrs
>            (jetpacs-icon-button "lock" (jetpacs-action "lock.toggle")
>                                 :checked :json-false)
>            :id "lock_ib"))
> ```
>
> `jetpacs-widgets/catalog-node-schema` (:889) compares only the GENERATED schema to the contract, so
> it will not catch a missing builder `&key`; this test is the only thing that does.

**Regenerated repo artifacts** (downstream of `contract.json`, outside `ebp/`):
`companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/Vocabulary.kt:49-50` and
`emacs/jetpacs-vocabulary.el:56-57` are generated and must be re-emitted by
`tools/gen-vocabulary.py` / `tools/gen-jetpacs-vocabulary.py` **in the same commit**;
`VocabularyDriftTest` and `jetpacs-widgets/catalog-node-schema` fail until they are.
`STATEFUL_NODE_TYPES` is **not** projected from `contract.json` — it is a hardcoded literal inside
the generator template (`tools/gen-vocabulary.py:63-64`), so item 3 below edits the template and
then regenerates.

### Companion implementation

Every Compose API named below was confirmed present in `material3-android:1.5.0-alpha16` (the floor
raised in `ed86191`) by `javap` over the AAR's `classes.jar`:
`androidx.compose.material3.ToggleButtonKt` exports `ToggleButton`, `ElevatedToggleButton`,
`TonalToggleButton`, `OutlinedToggleButton` (alpha16's name for upstream `FilledTonalToggleButton`);
`IconButtonKt` exports `IconToggleButton`, `FilledIconToggleButton`, `FilledTonalIconToggleButton`,
`OutlinedIconToggleButton`, each with an `IconToggleButtonShapes` overload;
`IconButtonDefaults.toggleableShapes()` and `ToggleButtonDefaults.shapes()` both exist;
`ToggleButtonDefaults.toggleButtonColors(containerColor, contentColor, disabledContainerColor,
disabledContentColor, checkedContainerColor, checkedContentColor)` takes all six independently.
There is no `TextToggleButton` — hence the `text` arm below.

**Opt-in.** Every one of those toggle entry points carries
`androidx.compose.material3.ExperimentalMaterial3ExpressiveApi` in the alpha16 class file's
`RuntimeVisibleAnnotations` (verified by `javap -v` on `ToggleButtonKt` and `IconButtonKt`), so both
`RenderButton` and `RenderIconButton` MUST be annotated
`@OptIn(ExperimentalMaterial3ExpressiveApi::class)`. The wire members are toolkit-independent; these
Kotlin arms are pinned to an alpha whose signatures may move before 1.5.0 stable.

**1. `render/InputNodes.kt:75-95` `RenderButton`.** The `when (node.stringOr("variant"))` at :89-94
gains a toggle sibling. Seeding and ordering are copied from `RenderCheckbox` (:185-210), including
the C6 comment's explicit primitive read — `as? Boolean` on a `JsonElement` compiles and is always
null:

> ```kotlin
> val id = node.stringOr("id")
> val isToggle = "checked" in node
> val stateful = isToggle && id.isNotEmpty()
> // Only a node with an id gets a rememberSaveable slot: the slot key IS the
> // wire address, and an empty id would alias every id-less button in the
> // surface into one shared cell.
> var checked by if (stateful) rememberSaveable(ctx.surface, id, ctx.epochOf(id),
>         key = "in:${ctx.surface}:$id:${ctx.epochOf(id)}") {
>     mutableStateOf((ctx.storeValue(id) as? JsonPrimitive)
>         ?.takeIf { !it.isString }?.content?.toBooleanStrictOrNull()
>         ?: node.boolOr("checked"))
> } else remember(node) { mutableStateOf(node.boolOr("checked")) }
> val onChange = node.objOrNull("on_change")
> val onCheck: (Boolean) -> Unit = {
>     if (stateful) {
>         checked = it
>         ctx.state(id, JsonPrimitive(it))          // §14.6: state FIRST
>     }
>     if (onChange != null) ctx.action(onChange, JsonPrimitive(it))
>     else onButton(onTap, ctx)                     // exactly one action
> }
> ```
>
> and, in place of the :89-94 dispatch when `isToggle`:
>
> ```kotlin
> when (node.stringOr("variant")) {
>     "outlined" -> OutlinedToggleButton(checked, onCheck, m, enabled, contentPadding = pad) { content() }
>     "tonal"    -> TonalToggleButton(checked, onCheck, m, enabled, contentPadding = pad) { content() }
>     "text"     -> ToggleButton(checked, onCheck, m, enabled,
>                       colors = ToggleButtonDefaults.toggleButtonColors(
>                           containerColor = Color.Transparent,
>                           contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
>                           checkedContainerColor = Color.Transparent,
>                           checkedContentColor = MaterialTheme.colorScheme.primary),
>                       contentPadding = pad) { content() }
>     else       -> ToggleButton(checked, onCheck, m, enabled, contentPadding = pad) { content() }
> }
> ```
>
> The `text` arm is §17.4's "no distinct toggle container" case: Material 3 ships no
> `TextToggleButton`, so the flat container is kept in **both** states — `checkedContainerColor` must
> be supplied explicitly, because `toggleButtonColors` defaults every unsupplied color to the filled
> toggle's, which would have made a checked `text` toggle grow the filled container the same
> paragraph forbids. The checked distinction is therefore content-color only, which is exactly what
> "carry the checked state through its own color treatment" licenses.
> `ElevatedToggleButton` becomes reachable only once G-05 adds `"elevated"` to
> `enums."button.variant"` (out of scope here). The `content` lambda at :81-88 is unchanged, so the
> 18dp icon and 6dp spacer are identical in both forms.

**2. `render/InputNodes.kt:99-114` `RenderIconButton`.** The unconditional `IconButton(` at :101
becomes a two-arm dispatch on the same `isToggle`/`stateful`/`onCheck` trio, and the inner `Icon` at
:106 takes the checked vector. `RenderIconButton` has no `enabled` local today (it inlines
`node.boolOr("enabled", true)` at :103), so hoist one:

> ```kotlin
> val enabled = node.boolOr("enabled", true)
> val iconName = if (checked) node.stringOr("checked_icon").ifEmpty { node.stringOr("icon") }
>                else node.stringOr("icon")
> // IconMap.get returns a non-null ImageVector, substituting
> // Icons.Outlined.HelpOutline for a name it cannot resolve (IconMap.kt:104).
> // That satisfies §17.4's "MUST NOT reject" and §17.2's placeholder rule; it
> // does NOT fall back to `icon`, which is why §17.4 above routes an
> // unresolvable `checked_icon` to §17.2 rather than promising the `icon`
> // vector. Changing that would need a nullable IconMap.getOrNull beside
> // IconMap.get (IconMap.kt:89) — deliberately out of scope.
> ```
>
> wrapping the existing badge/`icon()` body verbatim as `body()`:
>
> ```kotlin
> if (isToggle)
>     IconToggleButton(checked, onCheck, IconButtonDefaults.toggleableShapes(),
>         modifier = m, enabled = enabled) { body() }
> else
>     IconButton(onClick = { onButton(node.objOrNull("on_tap"), ctx) },
>         enabled = enabled, modifier = m) { body() }
> ```
>
> `IconButtonDefaults.toggleableShapes()` supplies the M3 expressive checked shape morph for free
> (the `IconToggleButton(Boolean, Function1, IconToggleButtonShapes, Modifier, Boolean, …)` overload,
> confirmed in `IconButtonKt`). The `Filled`/`FilledTonal`/`Outlined` toggle constructors become
> reachable once G-02 adds `icon_button.variant`; the same `when` then selects toggle-or-plain off
> `isToggle`, exactly as the ledger describes at `AUDIT-m3-blockers-2026-08-02.md:95`.

**3. `tools/gen-vocabulary.py:63-64` — `STATEFUL_NODE_TYPES` membership.** This is the edit that
makes items 4 and 5 reachable at all. `SpecValidator.kt:707` is `if (t in STATEFUL_NODE_TYPES) {`,
and that set is a hardcoded template literal in the generator (**not** projected from
`contract.json`, so `VocabularyDriftTest` will not force it):

> ```python
> val STATEFUL_NODE_TYPES: Set<String> = setOf(
>     "text_input", "checkbox", "switch", "enum_list", "slider", "editor",
>     "button", "icon_button")
> ```
>
> Regenerating emits `Vocabulary.kt:18-19`. `SpecValidator.kt:707` is the set's only Kotlin consumer
> (grep), so it can stay a **set**: the per-node predicate lives in item 4. This is the opposite of
> the Emacs side (item 6), whose consumer strips by membership and therefore genuinely needs a
> predicate.

**4. `wire/SpecValidator.kt:714-715` — stateful registration.** Inside the `t in
STATEFUL_NODE_TYPES` gate the `isStateful` expression already has the conditional shape this
amendment needs (it was written for `editor`). Replace:

> ```kotlin
> val isStateful = t != "editor" ||
>     (node.boolOr("publish_state") && "document" !in node)
> ```
>
> with:
>
> ```kotlin
> val isStateful = when (t) {
>     "editor" -> node.boolOr("publish_state") && "document" !in node
>     // §17.4: a toggle without an id has no wire address and is not stateful.
>     // It is NOT invalid — requiring id here would invalidate a previously
>     // valid CORE message (§25's first classification bullet).
>     "button", "icon_button" -> "checked" in node && "id" in node
>     else -> true
> }
> ```
>
> The `?: throw ContentInvalid(path, "$t requires an id")` at :718 is then unreachable for an
> id-less button, which is the intent. Together with item 3 this also makes `validateStaleSpec`
> (`SpecValidator.kt:178-196`) correct: it rejects only when `statefuls.isNotEmpty()` (:190-191), so
> an ordinary button never enters `ctx.statefuls` and stays legal in a stale spec, while a
> `checked`+`id` toggle is refused — matching SPEC edit 5 exactly.

**5. `wire/SurfaceStore.kt` — draft reconciliation and the authored value.** Both dispatch on node
type with a closed `when` whose `else` is a hard denial, so without these two arms every accepted
snapshot would wipe a toggle's held boolean (`reconcileDrafts`, :446-463, erases when
`!compatible(node, value)`) and every welcome `input_state` and `capture_fields` capture would carry
JSON null instead of the boolean (`CompanionEngine.kt:2120` writes
`authoredValueOf(node) ?: JsonNull`, which `Renderer.kt:100-112` `captureValue` reads back as "no
default"; `currentValue` at :189-192 falls through to the same helper).

> In `compatible` (:467-496), beside the `"checkbox", "switch"` arm:
>
> ```kotlin
> // §13.6: a toggle's value is boolean, and a snapshot that drops `checked`
> // leaves a node that is not stateful — erase rather than retain.
> "button", "icon_button" -> "checked" in node && isJsonBoolean(value)
> ```
>
> In `authoredValueOf` (:509-517), beside the `"checkbox", "switch"` arm:
>
> ```kotlin
> // Bare subscript, NOT `?: JsonPrimitive(false)`: a non-toggle button has no
> // logical value and MUST keep returning null so it never gains a default.
> "button", "icon_button" -> node["checked"]
> ```

**6. `emacs/jetpacs-shell.el:124-127` — `jetpacs-shell--stateful-types`.** This flat list is consumed
by membership: `jetpacs-shell--strip-stateful` (:478-500) tests
`(member (plist-get value :t) jetpacs-shell--stateful-types)` and returns nil for a match. Appending
`"button"` and `"icon_button"` as plain set members would **delete every button from every
`stale_spec`** — a shipped regression. This one must become the predicate "`button`/`icon_button`
only when `checked` and `id` are both present", i.e. the type test at :494 becomes a per-node
function.

**7. Dialogs.** No edit needed. `RenderCtx.state` (`Renderer.kt:228-231`) already routes to
`dialog.fields[id]` when inside a dialog, so a toggle inside a `dialog` becomes a capturable field
and never persists — §18.1 (SPEC.md:2724-2725) is satisfied by the existing plumbing, now that item
5 gives `captureValue`'s defaults layer a real boolean to fall back to.

### Unblocks

**19 catalog examples** carry G-04 or G-09 (13 + 6, disjoint sets; verified against
`docs/AUDIT-m3-blockers-2026-08-02.data.json`). #158 alone clears **3** of them; the other 16 need a
named co-requisite that this amendment does not supply.

*Cleared outright by #158 alone (3):*

| slug | example |
|---|---|
| togglebuttons | `ToggleButtonSample` |
| togglebuttons | `TonalToggleButtonSample` |
| togglebuttons | `OutlinedToggleButtonSample` |

Each of the three lists exactly `button.checked` + `button.on_change` in the audit data and nothing
else, and each maps onto a variant EBP already has (`filled` default / `tonal` / `outlined`).

*Cleared once the named co-requisite lands (16):*

| slug | example | also needs |
|---|---|---|
| icon-buttons | `IconToggleButtonSample` | G-65's icon-style selector (see correction) |
| icon-buttons | `FilledIconToggleButtonSample` | G-02 `icon_button.variant`, G-65 |
| icon-buttons | `FilledTonalIconToggleButtonSample` | G-02, G-65 |
| icon-buttons | `OutlinedIconToggleButtonSample` | G-02, G-65 |
| togglebuttons | `RoundToggleButtonSample` | G-07 `button.shape` |
| togglebuttons | `ElevatedToggleButtonSample` | G-05 `button.variant "elevated"` |
| togglebuttons | `ToggleButtonWithIconSample` | G-05, G-65 `button.checked_icon` + icon style |
| togglebuttons | `XSmallToggleButtonWithIconSample` | G-01 `button.size`, G-65 |
| togglebuttons | `MediumToggleButtonWithIconSample` | G-01, G-65 |
| togglebuttons | `LargeToggleButtonWithIconSample` | G-01, G-65 |
| togglebuttons | `XLargeToggleButtonWithIconSample` | G-01, G-65 |
| button-groups | `SingleSelectConnectedButtonGroupWithFlowLayoutSample` | G-63 `button.shape_role`, G-65 |
| button-groups | `MultiSelectConnectedButtonGroupWithFlowLayoutSample` | G-63, G-65 |
| button-groups | `VerticalButtonGroupSample` | G-63, G-64 signed `column.spacing` |
| split-button | `FilledSplitButtonSample` | the `split_button` node |
| split-button | `SplitButtonWithTextSample` | the `split_button` node |

**Two corrections to the ledger.**

*(a) icon-buttons/`IconToggleButtonSample` is not a sole gap for G-09*
(`AUDIT-m3-blockers-2026-08-02.md:141`). The upstream sample swaps `Icons.Filled.Lock` for
`Icons.Outlined.Lock`
(`Compose-Material-3-Expressive-Catalog/app/src/main/java/com/emertozd/compose/catalog/samples/IconButtonSamples.kt:221-227`),
and `IconMap.get` resolves outlined → automirrored → filled for every name
(`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/IconMap.kt:89-105`), so
`checked_icon: "lock"` and `icon: "lock"` resolve to the **same** vector and the sample would render
identically in both states — a false `:build`. `checked_icon` delivers a real swap only between
distinct names (`favorite_border`/`favorite`, `lock_open`/`lock`), which is what golden line `77`
pins. #158 clears the sample's state machine; **G-65's second half — the icon-style selector —**
clears its icon. The ledger concedes this at `:356` ("Also the icon half of G-09's four toggle
samples"); the G-09 entry's "sole gap" line is the one that is wrong. (G-09's own deps line at
`:142` says "G-24 for the icon swap"; G-24 is `text_input.leading_icon`/`trailing_icon`/`clearable`
at `:211-213` and has nothing to do with this. The icon-style selector is G-65 alone, `:355-357`.)

*(b) The four sized `ToggleButtonWithIcon` samples need G-65 too.* The audit data lists only
`button.size` beside `checked`/`on_change` for `XSmall`/`Medium`/`Large`/`XLargeToggleButtonWithIconSample`,
but all four use `if (checked) Icons.Filled.Edit else Icons.Outlined.Edit`
(`androidx/compose/material3/material3/samples/.../ToggleButtonSamples.kt:118-136` and following),
the same filled/outlined pair G-65 identifies as unreachable — the ledger even notes that IconMap
pre-caches `"edit"` to `Icons.Outlined.Edit` (`:355`). Applying correction (a) consistently means
these four carry G-65 as well as G-01. It does not change the outright-cleared count.

### **Design decision required** — what a toggle tap dispatches

`on_tap` is a REQUIRED member of both node types, so a toggle always carries one. The question is
whether the new `on_change` replaces it or joins it.

| | A — one action per tap (**recommended; drafted**) | B — `on_tap` always, `on_change` additionally |
|---|---|---|
| Dispatch | `state.changed`, then `on_change` when present, else `on_tap` | `state.changed`, then `on_change`, then `on_tap` |
| Events per tap | 1 | 2 |
| Existing traffic | Byte-for-byte identical: a message that can legally exist today carries no `on_change` (an ignored unknown member under §12 rule 1), so it still fires `on_tap` | Also identical, for the same reason |
| Author burden | `on_tap` is required anyway; it becomes the no-`on_change` fallback and keeps a real job | `on_tap` must be authored as a no-op handler whenever `on_change` is used |
| Offline cost | 1 durable event per flip | 2 durable events per flip against the same `max_queue_events`, and §15.2 dedupe or §15.2 expiry can split the pair |
| Against | A sender cannot express "a tap event *and* a change event"; no catalog example needs it. It also makes `on_tap` the first REQUIRED member in the vocabulary that is unreachable in a legal configuration — §17.1's hidden-action rule is the mitigation, cross-referenced in SPEC edit 2 | Doubles event volume for the intended authoring form |

**Recommendation: A.** It matches `checkbox`/`switch`, where the flip is the whole interaction and
`on_change` is the only hook; it keeps the offline queue arithmetic honest; and it leaves the
required `on_tap` meaningful rather than demoting it to ceremony.

**Second decision, implicit in A (ratify together) — #158-D2.** `checked` without a universal `id`
is legal and non-stateful (authored presentation, the `chip.selected` model) rather than
`1201 content-invalid`. Requiring `id` would invalidate a previously valid CORE message and trip
§25's first classification bullet (protocol major), so the draft does not require it. Golden line
`76` pins that arm.

**Standing caveat the ratifier should price in.** Nothing in the repo can assert that a toggle
*renders* checked, that the flip publishes `state.changed` before `on_change`, or that an id-less
`checked` does not flip locally: the Companion has no Compose UI test infrastructure
(`AUDIT-m3-blockers-2026-08-02.md:56-64`). The wire, validator, store and builder edits above are
all covered by data-level tests; the two `InputNodes.kt` renderers are not.
---

## #159 — the wavy and loading progress variants

Drafted 2026-08-02 against `ebp/SPEC.md` @ `83d6e08` (amendments through **#152** in
`SPEC-CHANGES.md`). Ledger gap: **G-03** (`docs/AUDIT-m3-blockers-2026-08-02.md:99-103`,
score 8.0, "best effort-to-yield ratio in the ledger").

Numbering: `SPEC-CHANGES.md` tops out at #152. #153 is pending on its own line; #154/#155
are pre-authored on the `rf-4a` line and await ratification; **#156–#167 are the siblings
of this m3-catalog batch**, of which this is #159. Nothing in 153–158 conflicts with the
sections touched here.

**This is a draft for ratification, not an applied edit.**

### SPEC-CHANGES row (ready to paste)

> | 159 | 2026-08-02 | §17.2 (cross-ref §12 rule 6, §16.4, §22.4, §25; precedent #41, #145; contract, goldens) | **`progress.variant` grows to the four expressive forms; determinacy stays on `value`.** §17.2's `progress` row admitted exactly two variants — `circular` (default) and `linear` — which name Compose's `CircularProgressIndicator` and `LinearProgressIndicator` and nothing else, so the eight m3-catalog examples whose entire subject is the *shape* of the indicator had no vocabulary at all: the four `WavyProgressIndicator` samples (an undulating active track with its own amplitude, wavelength and wave speed) and the four `LoadingIndicator` samples (a rotating sequence of morphing MaterialShapes polygons, optionally seated on a filled shaped container). `variant` now enumerates `circular`, `linear`, `linear_wavy`, `circular_wavy`, `loading`, and `contained_loading`. **No member is added and no default changes**: `variant` is already in `progress.optional` (`contract.json:149-155`), its absence still means `circular`, and determinacy is still carried by `value` alone for every variant — present ⇒ determinate `0..1`, absent ⇒ indeterminate — which is precisely the axis each of the four upstream sample pairs varies, so the wire needs no determinacy member either and no existing `progress` node changes meaning. The row also pins the unknown-value fallback that §12 rule 6 has always required and that §17.2 never stated for this member: an unrecognized `variant` MUST fall back to `circular`, MUST NOT cause rejection of the node or of the containing surface, and MUST NOT render nothing — the same shape #41 pinned for `dialog.style` and the same wording §17.2 already uses for `text.style` ("unknown values fall back to `body`", `SPEC.md:2244`). That is already what the reference Companion does — `ContentNodes.kt:348` tests `stringOr("variant") == "linear"` and takes the circular branch for every other string — so the fallback clause imposes no new receiver obligation, and no conforming sender's traffic is reinterpreted, the four new strings having been illegal to send before this amendment. Accessibility is preserved by construction and §17.2 now says so, as a restatement of §16.4's standing duty to preserve "accessibility meaning" rather than as a new receiver obligation: every variant exposes `ProgressBarRangeInfo` in material3 1.5.0-alpha16 — `ProgressIndicatorKt` and `WavyProgressIndicatorKt` via `Modifier.progressSemantics` (two call sites each), and `LoadingIndicatorKt` via `progressSemantics` on the indeterminate impl (`LoadingIndicatorImpl-eopBjH0`) and a hand-built `ProgressBarRangeInfo(progress, 0f..1f)` semantics block on the determinate impl (`LoadingIndicatorImpl-t6yy7ic`, lambda `…$lambda$6$0`), which is semantically equivalent — so every variant announces the same determinate range or indeterminate state. §25 classification: the enum grows, nothing previously valid becomes invalid, no existing frame changes meaning, and a Companion MUST NOT reject a `progress` node on accessibility grounds — no protocol-major, discharged in the shape #145 used. The one genuinely new duty is **sender-side and restricting only for the four new forms**: a sender MUST NOT make the wave, the morph, or the container the sole carrier of load-bearing meaning, mirroring the `icon` row's existing clause; it is vacuous for `circular` and `linear`, which have none of the three. Per #151, the enforcement, named and scoped: `validate.py` checks only required/optional member membership — it has **no `enums` arm at all** (`grep -n enums ebp/validate.py` is empty), so it enforces neither the value set, the fallback, nor the semantics; the ERT suite adds builder-parity and canonical round-trip on the four new golden lines and nothing more; the Companion has no render-assertion harness, so the fallback and the a11y clause are conformance duties checkable only by inspection. The only mechanical guard on the six values anywhere is the hand-kept `jetpacs--check-enum` list at `emacs/jetpacs-widgets.el:695`, outside `ebp/`. The Companion side is four `when` arms in `RenderProgress` (`ContentNodes.kt:345-357`) over `LinearWavyProgressIndicator` / `CircularWavyProgressIndicator` / `LoadingIndicator` / `ContainedLoadingIndicator`, each with both the determinate `progress: () -> Float` overload and the indeterminate one, under `@OptIn(ExperimentalMaterial3ExpressiveApi::class)`; the library floor was met by `ed86191` (material3 1.4.0 → 1.5.0-alpha16). `variant` is deliberately NOT registered as a constraining feature: §22.4 defines one as gating "a construct an ignoring receiver would over-accept", and a circular fallback under-delivers rather than over-accepts, so §22.4's registry is untouched — the cost, recorded rather than papered over, is that a sender cannot positively learn whether the expressive form was drawn. Additive on the wire and in the artifacts: the enum grows; the schema row, `field_types`, `node_types`, `features`, both generated vocabulary mirrors and every existing golden are byte-unchanged (verified by regenerating both). | contract `enums."progress.variant"` 2 → 6 values; `goldens/widgets.golden` += 4 lines (75–78); no `validate.py` arm (it has none for enums — see draft); both generated mirrors regenerate byte-identical (verified) | |

### SPEC.md edits

**1. §17.2, the `progress` table row (`SPEC.md:2251`).** Replace, verbatim:

> | `progress` | — | `variant`, `value`. `variant` is `circular` (default) or `linear`. Omitted `value` is indeterminate; supplied `value` MUST be `0..1`. |

with:

> | `progress` | — | `variant`, `value`. `variant` is `circular` (default), `linear`, `linear_wavy`, `circular_wavy`, `loading`, or `contained_loading`; unknown values fall back to `circular`. Omitted `value` is indeterminate; supplied `value` MUST be `0..1`, for every variant. |

(The em dash in the "Required members" cell is U+2014, as in the current line. "unknown
values fall back to" is the phrasing the `text` row at `SPEC.md:2244` already uses.)

**2. §17.2, new prose paragraph.** Insert after the paragraph ending (`SPEC.md:2258-2262`):

> For `date_stamp`, `day` is an integer `1..31`, `month` is a display string,
> `month_index` is an integer `1..12`, `year` is a non-negative integer, and
> `time` is a display string. `section_header.trailing` is a Node. In an
> `empty_state`, `action_label` and `on_tap` MUST appear together or both be
> absent. `badge.children`, when present, is a Node array.

and before the paragraph beginning (`SPEC.md:2264`):

> For an `image`, no URI form is implicit. A Companion advertising `image` in a

the new paragraph:

> A `progress` node's `variant` selects the indicator's form only. Determinacy is
> carried by `value` alone and identically for every variant: an omitted `value`
> is indeterminate, a supplied one is determinate. `circular` and `linear` are the
> plain circular and linear tracks; `linear_wavy` and `circular_wavy` draw those
> same tracks with an undulating active indicator; `loading` draws a shape-morphing
> indicator; and `contained_loading` draws that indicator seated on a filled,
> shaped container. A Companion that cannot draw a requested form MUST fall back to
> `circular` and MUST NOT reject the node, reject the containing surface, or render
> nothing — the fallback is a legible indicator of the same determinacy, which is
> why `variant` is not a constraining member under Section 12 and takes no feature
> advertisement under Section 22.4. Every variant preserves the same accessibility
> meaning, which Section 16.4 already requires a render to preserve: a determinate
> node exposes `value` as its accessible progress value, and an indeterminate node
> announces indeterminate progress. This restates Section 16.4 for this node and
> creates no new invalidity; a Companion MUST NOT reject a `progress` node for an
> accessibility reason. A form is presentation: a sender MUST NOT make the wave, the
> morph, or the container the sole carrier of load-bearing meaning.

No other section changes. §12 rule 6 is satisfied by edit 1's fallback clause and
needs no edit of its own; §16.4 is restated, not amended; §22.4's registry is untouched.

### Artifact changes

**1. `ebp/contract.json` — `enums."progress.variant"` (lines 622-625).** Replace,
verbatim:

```json
    "progress.variant": [
      "circular",
      "linear"
    ],
```

with:

```json
    "progress.variant": [
      "circular",
      "linear",
      "linear_wavy",
      "circular_wavy",
      "loading",
      "contained_loading"
    ],
```

Nothing else in `contract.json` moves. `node_schema.progress` already carries
`variant` in `optional` (`contract.json:149-155`), so there is **no `node_schema`
delta**. `variant` has no `field_types` row — verified: `field_types` is a flat
bare-name map and contains `value` (`"varies-per-node"`) but not `variant` — so there is
**no `field_types` delta**, which matters because `field_types` is global and could not
express node scoping anyway. No `node_types`, `core_node_set`, `theme_roles`,
`features`, or `surface_spec_variants` delta.

**2. `ebp/goldens/widgets.golden` — append four lines.** The file currently holds 75
lines, `00`–`74`, and ends with a newline; `golden_lines()` strips the numeric prefix
(`validate.py:376-379`), so appending `75`–`78` is the only *placement* needed within
`ebp/` (the out-of-tree builder-parity duty is item 5). Keys are in the file's
alphabetical order, matching existing line `14`:

```
75 {"t":"progress","variant":"linear_wavy"}
76 {"t":"progress","value":0.25,"variant":"circular_wavy"}
77 {"t":"progress","variant":"loading"}
78 {"t":"progress","value":0.75,"variant":"contained_loading"}
```

Two determinate and two indeterminate, so both arms of every new value's Companion
branch have a corpus line. Existing lines `13` (`{"t":"progress"}`) and `14`
(`{"t":"progress","value":0.5,"variant":"linear"}`) are untouched. All four were run
through `jetpacs-node->canonical-json` and returned byte-identical, so
`jetpacs-widgets/canonical-round-trips-corpus` (`test/jetpacs-widgets-test.el:686-701`)
covers them the moment they land, with no test edit.

**3. `ebp/validate.py` — no arm required.** `check_node` (`validate.py:253-300`)
validates required/optional membership and the two hand-written node rules
(`text_input.single_line`, `enum_list`, `slider`); **there is no enum arm anywhere in
the file** — `grep -n enums validate.py` returns nothing — so the four golden lines
pass unchanged because `variant` is already `progress.optional`. The §17.2 coverage
floor (`validate.py:757-762`) is per node *type* and is already met by line `13`. This
is the enforcement scope #151 requires be named: `validate.py` gates membership, not
values.

**4. Generated mirrors — no delta, verified rather than assumed.** The standing rule is
that a `node_schema`/`field_types` change must regenerate both mirrors in the same
commit. This amendment touches neither, and neither generator projects `enums`. Verified
by running both against the modified contract:

```
python3 tools/gen-vocabulary.py          -> companion/wire/.../Vocabulary.kt   byte-identical
python3 tools/gen-jetpacs-vocabulary.py  -> emacs/jetpacs-vocabulary.el        byte-identical
```

so `SurfaceStoreTest`'s exact-equality assertion and the elisp drift test both stay green
with no regeneration commit. `emacs/jetpacs-vocabulary.el:41` —
`("progress" () ("value" "variant"))` — is member-level and correctly unchanged.

**5. Out-of-tree co-requisites (NOT `ebp/` artifacts, but the amendment is inert or
untested without them).**

*(a) `emacs/jetpacs-widgets.el:695` hand-keeps the enum* — this is the single mechanical
guard on the six values anywhere in the repo:

```elisp
  (when variant (setq variant (jetpacs--check-enum variant '("circular" "linear") ":variant")))
```

It must grow to `'("circular" "linear" "linear_wavy" "circular_wavy" "loading"
"contained_loading")`, and the docstring at `:693-694` ("VARIANT is circular
(default) or linear") with it. Until it does, the amendment is **inert on the Emacs
side**: `(jetpacs-progress :variant "loading")` signals today with
`jetpacs: :variant must be one of ("circular" "linear"), got "loading"` — verified by
running it.

*(b) `test/jetpacs-widgets-test.el` needs four builder-parity `chk` lines.*
`jetpacs-widgets/content-goldens` (`:79-118`) is index-keyed and its docstring pins
"widgets.golden 00-16"; `grep -oE '\(chk "[0-9]+"'` over the file yields 00 through 71
and nothing above. Appending content-family `progress` vectors at 75-78 therefore lands
them *outside* the checked block: without this item they would be the only
widgets.golden vectors besides the three post-hoc equality lines 72-74 with no builder
check at all. Add a new deftest so the "00-16" docstring stays true:

```elisp
(ert-deftest jetpacs-widgets/progress-variant-goldens ()
  "The four expressive progress variants build byte-identically to widgets.golden 75-78."
  (let ((g (jetpacs-test--golden-map "widgets")))
    (cl-flet ((chk (idx form)
                (ert-info ((format "widgets.golden line %s" idx))
                  (should (equal (jetpacs-node->canonical-json form)
                                 (gethash idx g))))))
      (chk "75" (jetpacs-progress :variant "linear_wavy"))
      (chk "76" (jetpacs-progress :variant "circular_wavy" :value 0.25))
      (chk "77" (jetpacs-progress :variant "loading"))
      (chk "78" (jetpacs-progress :variant "contained_loading" :value 0.75)))))
```

This deftest depends on (a): it fails with an enum signal until `jetpacs-widgets.el:695`
grows. `canonical-round-trips-corpus` already covers the same four lines independently of
the builders and needs no edit.

Verified end to end: with edits 1 and 2 applied to a copy of `ebp/`, `python3
validate.py` reports `OK: 40 frames, 79 widget lines, 7 hypertext nodes, 17 wire
fixtures x3 chunkings validate` (baseline, unmodified: `40 frames, 75 widget lines`).

### Companion implementation

**File:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/ContentNodes.kt`,
`RenderProgress`, lines **345-357** (dispatched from `Renderer.kt:284`, which already
hands it the universal-attribute modifier `m`).

Current body — `ContentNodes.kt:348` is the whole variant decision, and it is why the
new fallback clause costs nothing:

```kotlin
    val linear = node.stringOr("variant") == "linear"
```

Replacement:

```kotlin
/** §17.2 progress: six variants; `circular` is both the default and the
 * fallback for an unrecognized value (§12 rule 6). No `value` = indeterminate,
 * for every variant — determinacy is not a variant. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderProgress(node: JsonObject, m: Modifier) {
    val v = if ("value" in node)
        node.doubleOr("value", 0.0).toFloat().coerceIn(0f, 1f) else null
    val p: (() -> Float)? = v?.let { f -> { f } }
    when (node.stringOr("variant")) {
        "linear" ->
            if (p != null) LinearProgressIndicator(progress = p, modifier = m)
            else LinearProgressIndicator(modifier = m)
        "linear_wavy" ->
            if (p != null) LinearWavyProgressIndicator(progress = p, modifier = m)
            else LinearWavyProgressIndicator(modifier = m)
        "circular_wavy" ->
            if (p != null) CircularWavyProgressIndicator(progress = p, modifier = m)
            else CircularWavyProgressIndicator(modifier = m)
        "loading" ->
            if (p != null) LoadingIndicator(progress = p, modifier = m)
            else LoadingIndicator(modifier = m)
        "contained_loading" ->
            if (p != null) ContainedLoadingIndicator(progress = p, modifier = m)
            else ContainedLoadingIndicator(modifier = m)
        else ->  // "circular", absent, and every unrecognized value
            if (p != null) CircularProgressIndicator(progress = p, modifier = m)
            else CircularProgressIndicator(modifier = m)
    }
}
```

**Imports.** The sample above uses the *imported* annotation form, matching
`InputNodes.kt:431/460`; do not also fully-qualify it at the site, or the import is
unused. Five additions to the file's alphabetical `androidx.compose.material3.*` block
(currently `:23-33` — `Badge`, `BadgedBox`, `CircularProgressIndicator`, `ElevatedCard`,
`Icon`, `LinearProgressIndicator`, `LocalContentColor`, `MaterialTheme`,
`OutlinedButton`, `Surface`, `Text`), in sorted position:

| Import | Sorted position |
|---|---|
| `CircularWavyProgressIndicator` | after `CircularProgressIndicator` (`:25`) |
| `ContainedLoadingIndicator` | after `CircularWavyProgressIndicator`, **before** `ElevatedCard` (`:26`) — `Ci` < `Co` < `El` |
| `ExperimentalMaterial3ExpressiveApi` | after `ElevatedCard`, before `Icon` |
| `LinearWavyProgressIndicator` | after `LinearProgressIndicator` (`:28`) |
| `LoadingIndicator` | before `LocalContentColor` (`:29`) — `Loa` < `Loc` |

**API existence, verified by `javap` on the unpacked material3 1.5.0-alpha16
`classes.jar`** — every one has both a determinate `Function0<Float>`-first overload and
an indeterminate `Modifier`-first overload:

| Composable | JVM symbols (determinate / indeterminate) |
|---|---|
| `LinearWavyProgressIndicator` | `WavyProgressIndicatorKt.LinearWavyProgressIndicator-1YwxWKA` / `-hvuEXSk` |
| `CircularWavyProgressIndicator` | `WavyProgressIndicatorKt.CircularWavyProgressIndicator-L8eD4gc` / `-hvuEXSk` |
| `LoadingIndicator` | `LoadingIndicatorKt.LoadingIndicator-cf5BqRc` / `-3IgeMak` |
| `ContainedLoadingIndicator` | `LoadingIndicatorKt.ContainedLoadingIndicator-Y0xEhic` / `-DTcfvLk` |

All four carry `androidx.compose.material3.ExperimentalMaterial3ExpressiveApi`, hence the
site `@OptIn`. Site-level `@OptIn` is this render package's existing pattern
(`InputNodes.kt:431`, `:460` and `Renderer.kt:678`, all `ExperimentalMaterial3Api`; the
latter fully-qualified, the former imported — the package uses both conventions).
**This is the Companion's first `ExperimentalMaterial3ExpressiveApi` opt-in**:
`grep -rn ExperimentalMaterial3ExpressiveApi companion/app/src/` returns nothing, so it is
a new annotation for the codebase, not a precedent already set. (`LayoutNodes.kt:164` and
`:328`, cited in an earlier revision of this draft, are `ExperimentalLayoutApi` and
`ExperimentalFoundationApi` — not material3 opt-ins at all.)

**Accessibility, by call site rather than constant pool.** All three sources expose
`ProgressBarRangeInfo`, but not all by the same mechanism, and the difference falls on
exactly the determinate loading path that two of the four new golden lines and two of the
eight unblocked examples exercise:

| Source | Mechanism |
|---|---|
| `ProgressIndicatorKt` | `Modifier.progressSemantics` — 2 `invokestatic ProgressSemanticsKt.progressSemantics` call sites |
| `WavyProgressIndicatorKt` | `Modifier.progressSemantics` — 2 call sites |
| `LoadingIndicatorKt`, indeterminate | `Modifier.progressSemantics` in `LoadingIndicatorImpl-eopBjH0` — the file's **only** `progressSemantics` call |
| `LoadingIndicatorKt`, determinate | hand-built: `LoadingIndicatorImpl-t6yy7ic` → `…$lambda$6$0(Function0, SemanticsPropertyReceiver)` does `new ProgressBarRangeInfo(progress, RangesKt.rangeTo(0f,1f), 0)` then `SemanticsPropertiesKt.setProgressBarRangeInfo` |

The last row is semantically equivalent to `progressSemantics` and satisfies the §17.2
a11y restatement in edit 2 with no extra `Modifier.semantics` on the Companion side — but
the mechanism is not `progressSemantics`, so a claim phrased "all three apply
`progressSemantics`" would be false, and the row above states it by call site instead.

**No `NodeSupport.kt` change.** `progress` is already in `CONTENT_NODE_TYPES`
(`NodeSupport.kt:20-22`), hence in both `APP_NODE_TYPES` and `DIALOG_NODE_TYPES`; no
node type and no feature is added, so `surfaceProfiles()` is byte-identical and
`NodeSupportPinTest` is unaffected.

**Standing caveat, stated because nothing catches it.** The Companion has no Compose UI
test infrastructure; `companion/app/src/test/.../render/` holds four tests
(`DialogCaptureTest`, `NodeSupportPinTest`, `SyntaxHighlightTest`, `ThemeModelTest`) and
none touches `progress`. A typo in a variant string in the `when` would pass every gate in
the repo and silently render a circular spinner. The four arms land unasserted; that is
the audit's own bounding caveat, not something this amendment resolves.

### Unblocks

**8 catalog examples, every one of them sole-gap** (audit `:102`), across two modules.
The count is unchanged from the audit and was re-verified against both modules: all eight
carry `:unsupported` today and none of them names a second missing construct.

*`progress-indicators` (4)* — `emacs/apps/m3-catalog/jetpacs-m3-progress-indicators.el`.
All four currently carry `jetpacs-m3-progress-indicators--wavy-note` (`:34-36`), which
becomes factually false on ratification and must be replaced by builds:

| Example | Build |
|---|---|
| `LinearWavyProgressIndicatorSample` (`:99-104`) | `(jetpacs-m3-progress-indicators--determinate "linear_wavy" …)` — the existing helper at `:38-52` already takes `variant` as a parameter |
| `IndeterminateLinearWavyProgressIndicatorSample` (`:110-115`) | `(jetpacs-column (jetpacs-progress :variant "linear_wavy") :align "center")` |
| `CircularWavyProgressIndicatorSample` (`:121-126`) | same helper, `"circular_wavy"` |
| `IndeterminateCircularWavyProgressIndicatorSample` (`:132-137`) | same column, `"circular_wavy"` |

*`loading-indicators` (4)* — `emacs/apps/m3-catalog/jetpacs-m3-loading-indicators.el`.
The module's `--indicator-note` (`:42-44`), `--contained-note` (`:46-48`) and the two
inline notes (`:77`, `:84`) all rest on "there is no loading_indicator node" and become
false; the module's commentary (`:12-24`) argues the opposite of this amendment and is
addressed in DD-1 below.

| Example | Upstream | Build |
|---|---|---|
| `LoadingIndicatorSample` | `LoadingIndicatorSamples.kt:67-68` — `Column { LoadingIndicator() }` | `(jetpacs-column (jetpacs-progress :variant "loading") :align "center")` |
| `ContainedLoadingIndicatorSample` | `:75-76` | same, `"contained_loading"` |
| `DeterminateLoadingIndicatorSample` | `:83-107` — `LoadingIndicator(progress = { animatedProgress })` over the same Column/Spacer/`Text("Set loading progress:")`/300dp-Slider the progress module already builds | the `--determinate` helper with `"loading"` and a label argument — see the reuse note |
| `DeterminateContainedLoadingIndicatorSample` | `:113-137` | same, `"contained_loading"` |

**Helper reuse is not a drop-in, and the catalog work is not zero.**
`jetpacs-m3-progress-indicators--determinate` is `(variant id)` at `:38-52` with the label
hardcoded twice — `(jetpacs-text "Set progress:")` at `:48` and the same string as the
demo verb at `:50` — and it has four callers at `:54-83`. Upstream's loading samples say
`Text("Set loading progress:")` (`LoadingIndicatorSamples.kt:98`, `:128`). So reuse
requires *either* (i) making the label an `&optional`/keyword argument defaulting to
`"Set progress:"` so the four existing callers are unchanged, **plus** adding
`(require 'jetpacs-m3-progress-indicators)` to the loading module, which today requires
only `jetpacs-widgets` and `jetpacs-m3-core` (`:35-36`) — *or* (ii) duplicating the helper
locally, which is what the other catalog modules do and which avoids a new cross-module
dependency. Either way this is catalog-side work that ratification enables, not work this
amendment performs.

**Not unblocked, and named to keep the count honest:**
`loading-indicators/LoadingIndicatorPullToRefreshSample` (`:85-91`) needs **G-27**
(`scaffold.refresh_indicator`), whose `"loading"` value is *defined by* this amendment
(audit `:222`, "Deps: G-03 for the `loading` value") — so #159 must be ratified before
G-27's draft, but #159 claims none of G-27's example. That is the fifth example in the
`loading-indicators` module; this amendment clears four of its five.

**Also worth stating:** the two determinate loading samples are `LoadingIndicator`'s own
demonstration that a determinate indicator steps through its morph sequence rather than
filling a track. That is entirely a Companion-side consequence of `value` reaching the
determinate overload; no morph fraction, phase, or shape crosses the wire.

### Design decisions required

**DD-1 — four enum values, or a new `loading_indicator` node type?** The catalog module
argues for a node type in its own prose — `jetpacs-m3-loading-indicators.el:12-13`: "All
five samples are the M3 Expressive `LoadingIndicator' -- a new component, not a new
option on an old one", with the argument running through `:24` — so the choice must be
made explicitly rather than inherited from the ledger, and ratifying A means overruling
that commentary in the same change.

| | Option | Consequence |
|---|---|---|
| **A** *(recommended, drafted)* | `loading` / `contained_loading` are `progress.variant` values | One enum edit. The node already carries the exact two axes a `LoadingIndicator` varies — determinate-vs-indeterminate (`value`) and contained-vs-not (`variant`) — and both forms announce identical progress semantics, so on the wire they *are* the same node. Costs nothing to send: no profile advertisement, no §16.2 degradation path, no coverage line, no `NodeSupport` widening. An older Companion draws a plain spinner: less faithful, never wrong. |
| B | a `loading_indicator` node type with `value` and `contained` | Emacs gets positive discovery via `surface_profiles.<target>.node_types` and can refuse to author a lookalike. But it costs a `node_types` + `core_node_set` decision, a `node_schema` row, a golden coverage line, `NodeSupport.CONTENT_NODE_TYPES`, an `APP`/`DIALOG` profile change, regeneration of both vocabulary mirrors, and a duplicate of the determinacy rule; and it makes an unadvertised node a whole-surface `1201` (§16.2) where A degrades to a spinner. Upstream's file boundary is a Compose-source fact, not a wire fact. |

**DD-2 — should the four expressive values carry a `progress.expressive` profile
feature?** The eight examples above will ship `:build`, and on a Companion whose
material3 predates 1.5 they would draw a plain indicator with no way for Emacs to
detect it — the false-`:build` class the audit's headline names.

| | Option | Consequence |
|---|---|---|
| **A** *(recommended, drafted)* | no feature; §12 rule 6 fallback only | §22.4 defines a constraining feature as gating "a construct an ignoring receiver would **over-accept**". A circular fallback under-delivers, so `progress.expressive` is not a constraining feature and does not belong in that registry as written. Registering it anyway requires widening §22.4's definition to admit fidelity-only advertisements — a §22.4 amendment strictly larger than this one, and one that invites a feature per enum value across the whole m3 batch (G-01, G-02, G-05, G-10, G-13, G-14, G-18, G-21…). |
| B | register `progress.expressive` in §22.4 and `contract.json.features`, gated in `NodeSupport.APP_FEATURES`/`DIALOG_FEATURES` | Emacs learns positively, exactly as `jetpacs-org-render.el:202-203` already gates on `image.data`. Costs one string per artifact plus the §22.4 definition change, and sets the precedent that a renderer-fidelity difference is advertisable. Defensible as its own amendment later; out of scope here. |

Under A the mitigation is out-of-band and worth stating in the ratification note: this
repo has one Companion, and it has been on material3 1.5.0-alpha16 since `ed86191`.

**Two costs recorded, not decisions.** (i) Uniform `circular` fallback means a linear
wavy *bar* degrades to a small circular *spinner* — a visible layout change — on any
receiver that does not implement the value; a shape-preserving fallback (`linear_wavy` →
`linear`) was considered and rejected because uniform fallback matches every precedent in
the document (`text.style` → `body`, `dialog.style` → `dialog` per #41,
`image.content_scale` → `fit`) and is already exactly what `ContentNodes.kt:348` does.
(ii) `contained_loading` exposes no container colour or shape member;
`LoadingIndicatorDefaults.containerShape` / `containedContainerColor` /
`containedIndicatorColor` are taken as-is. Upstream's four samples use the defaults, so
nothing in the unblock count depends on this, but a `progress.container_color` request
later is a separate amendment.
---

## #160 — card variants, and the surface-container roles the theme mirror never derived

Covers ledger gaps **G-10** (`card.variant`) and **G-11** (four theme roles). They are one
amendment because they are one defect: the filled and outlined card containers are named by
tokens (`surface_container_highest`, `outline_variant`) that the wire vocabulary does not
carry and that `ThemeModel` leaves frozen at the Material baseline — so `card.variant` alone
would select containers whose colour ignores the running Emacs theme, and the four roles
alone would clear nothing.

Drafted against `ebp` @ `83d6e08` (amendments through **#152**) and
`companion` @ `9b57b35` (material3 **1.5.0-alpha16**, raised in `ed86191`).

### SPEC-CHANGES row (ready to paste)

> | 160 | 2026-08-02 | §17.3, §18.4 (cross-ref §12 rule 6, §16.6; precedent #56; contract) | **`card.variant`, and the surface-container roles the theme mirror never derived.** The §17.3 `card` row carried `children`, the two tap actions and the two swipe sides, and nothing selecting the container — so the Companion rendered every `card` node as an M3 `ElevatedCard` (`LayoutNodes.kt:334`, hardcoded), leaving two of Material's three card containers unreachable from Emacs and four catalog examples whose entire subject is the container style with nothing to ask for. `card` gains OPTIONAL `variant`: `elevated` (default), `filled`, `outlined`; an omitted or unrecognized value is `elevated` under §12 rule 6, so every `card` on the wire today renders byte-for-byte as it does now. The `variant` half is a strict no-op on existing traffic; **the theme half is not, and is priced below.** The member is inert without it. Material names the three containers by token — filled is `surface_container_highest`, elevated `surface_container_low`, outlined `surface` bounded by a one-`dp` `outline_variant` stroke (`FilledCardTokens`/`ElevatedCardTokens`/`OutlinedCardTokens` in material3 1.5.0-alpha16) — and §18.4's standard-role enumeration named none of the container tones and no `outline_variant`, so a filled card's container could not be spelled, and the role the Companion resolves anyway was wrong: `ColorModel.kt:76` resolves `outline_variant` to `scheme.outlineVariant`, which `buildColorScheme` never re-derives (`ThemeModel.kt:96-99` derives `surfaceContainerLow`/`Container`/`High` from the surface/`surface_variant` pair and stops), so it stays at the base Material tone under any pushed palette. `theme_roles` gains `surface_container_low`, `surface_container`, `surface_container_highest` and `outline_variant`, and §18.4 states the rule the older three were implemented under but no sentence required: these four are DERIVED roles — when a `colors` map pushes at least one of the roles a derived role derives from and omits the derived role, the Companion MUST compute it from the pushed values rather than retain its base scheme's; a pushed value wins; a derived role MUST NOT be tonally outside the two roles it derives from; and when NONE of its source roles is pushed the Companion keeps its own scheme's value, as for any other omitted role. This is amendment #56's on-color derivation extended from the on-colors to the container ramp, and for the same reason: a base-scheme container tone under a foreign pushed surface is not a different colour, it is a container that ignores the theme it was told to mirror. **Two disclosed behaviour changes to already-shipping traffic.** (1) Deriving `outline_variant` moves every node that wears it under a `theme.set` that pushes `outline` or the surface pair: the `divider` node (`Renderer.kt:303`), `table` rules (`LayoutNodes.kt:533`), the menu divider (`:744`), `chip` and `assist_chip` (`InputNodes.kt:122`, `:137`), `enum_list`'s chips (`:313`, `:328`, `:339`), `button` with `variant: "outlined"` (`:91`), `date_button` (`:436`), `time_button` (`:465`), and the diagnostic action button (`ContentNodes.kt:341`) — a palette-wide repair, not two hairlines. (2) The derivation gate is new: today's three stops interpolate whenever a `colors` map is present at all, even one that pushes nothing surface-related, so the drag chrome (`LayoutNodes.kt:671`) and the `bottom_bar` surface (`Renderer.kt:752`) currently wear a fresh interpolation of the base scheme's own pair and will fall back to the base scheme's container tones (dark: `#3B3740` → `#2B2930`, `#2D2A32` → `#211F26`; `goldens/frames.golden` index 20 is the corpus case) — see **D3**. The gate is also what keeps `surfaceContainerHighest` from moving every `Switch`'s OFF track (`SwitchTokens.UnselectedTrackColor` = `SurfaceContainerHighest`, `InputNodes.kt:228` taking the defaults) under that same frame. Additive on the wire: `variant` is a new optional member with a today-preserving default, and the four roles were previously unnameable (§16.6 gave an unknown role the legible fallback), so no previously valid message is invalidated. The §18.4 complete-role-set golden is extended to the new set — the frame's stated purpose, and the reason it exists — and `validate.py` gains the arm that enforces that completeness MUST, which nothing checked before and which is mechanically how four roles the renderer already resolves stayed out of the vocabulary. | contract `node_schema.card.optional += "variant"`; `enums."card.variant"`; `theme_roles += 4`; goldens/widgets.golden += 3 card lines; goldens/frames.golden frame 37 extended to the complete role set (§18.4's own requirement); validate.py theme-role completeness arm | |

### SPEC.md edits

**1. §17.3, the layout-node table (SPEC.md:2342).** Replace:

> ``| `card` | `children: Node[]` | `on_tap`, `on_long_tap`, `swipe_start`, `swipe_end`. |``

with:

> ``| `card` | `children: Node[]` | `variant`, `on_tap`, `on_long_tap`, `swipe_start`, `swipe_end`. `variant` is `elevated` (default), `filled`, or `outlined`; unknown values fall back to `elevated`. |``

**2. §17.3, after the `box.alignment`/`surface.shape` paragraph (SPEC.md:2357–2361).** Leave
this paragraph unchanged:

> `box.alignment` is one of `top_start`, `top_center`, `top_end`, `center_start`,
> `center`, `center_end`, `bottom_start`, `bottom_center`, or `bottom_end`; the
> default is `top_start`. `surface.shape` is `rounded`, `rounded_small`, or
> `circle`; omission is rectangular. A numeric universal `corner` overrides
> `shape` except that `circle` remains circular.

and insert immediately after it, as a new paragraph:

> `card.variant` selects the container treatment and nothing else: `elevated`
> (the default) is a shadowed container on the `surface_container_low` role,
> `filled` a flat container on `surface_container_highest`, and `outlined` a
> flat container on `surface` bounded by a one-`dp` `outline_variant` stroke.
> The node's content padding, its `on_tap` and `on_long_tap` handling, and its
> swipe chrome are identical across the three. The universal `bg`, `border`,
> and `corner` attributes compose with the variant rather than replacing it: a
> universal `border` on an `outlined` card draws a second stroke, at the node's
> own `corner` shape, and does not suppress the card's own — exactly as it
> already does over a card today. An unrecognized `variant` falls back to
> `elevated` under Section 12 rule 6, so a `card` is never rejected for its
> `variant` alone, and an omitted `variant` renders exactly as every `card`
> rendered before this member existed.

**3. §18.4, the standard-role enumeration (SPEC.md:2849–2853).** Replace:

> Standard roles include `primary`, `on_primary`, `primary_container`,
> `on_primary_container`, parallel `secondary`, `tertiary`, and `error` roles,
> plus `background`, `on_background`, `surface`, `on_surface`,
> `surface_variant`, `on_surface_variant`, `outline`, `success`, and `warning`.
> Unknown roles MUST be ignored.

with:

> Standard roles include `primary`, `on_primary`, `primary_container`,
> `on_primary_container`, parallel `secondary`, `tertiary`, and `error` roles,
> plus `background`, `on_background`, `surface`, `on_surface`,
> `surface_variant`, `on_surface_variant`, `surface_container_low`,
> `surface_container`, `surface_container_highest`, `outline`,
> `outline_variant`, `success`, and `warning`. Unknown roles MUST be ignored.
>
> The three `surface_container*` roles name tonal steps a container sits on
> between `surface` and `surface_variant`, and `outline_variant` names the
> lower-emphasis stroke between `outline` and `surface`. These four are
> DERIVED roles: each names a tone the Companion can compute from other roles.
> When a `colors` map pushes at least one of the roles a derived role is
> derived from and omits the derived role itself, the Companion MUST compute
> that role from the pushed values and MUST NOT retain its base scheme's value
> for it — the rule this section already imposes on a missing on-color, for
> the same reason: a base-scheme container tone under a foreign pushed surface
> is not merely a different color, it is a container that ignores the theme it
> was asked to mirror. A value pushed for a derived role wins over the
> derivation, and a derived role MUST NOT be tonally outside the two roles it
> is derived from. When a `colors` map pushes none of the roles a derived role
> is derived from, the Companion keeps its own scheme's value for it, as for
> any other omitted role.

*(Three clauses of that paragraph were rewritten from the first draft so that the
normative text and the shipped implementation state the same rule; see D3.)*

### Artifact changes

**contract.json — `node_schema.card`.** Replace:

```json
    "card": {
      "required": [
        "children"
      ],
      "optional": [
        "on_tap",
```

with:

```json
    "card": {
      "required": [
        "children"
      ],
      "optional": [
        "variant",
        "on_tap",
```

(`variant` leads the optional list, as it does on `progress`; on `button` it sits second.
The position is cosmetic either way — `node_schema` optional sets are compared as SETS by
both drift tests, `SurfaceStoreTest.kt:744` and a sorting `jetpacs-widgets-test.el`.)

**contract.json — `enums`.** Insert a new entry immediately after `"surface.shape"` (the
§17.3 declaration order the `enums` block already follows), before `"chart.kind"`:

```json
    "card.variant": [
      "elevated",
      "filled",
      "outlined"
    ],
```

`enums` is read by nothing — `validate.py` never mentions the block, neither generator
projects it, and `Vocabulary.kt` stores only the type NAME. It is documentation of the
closed set, not a validated one; the §12 rule 6 fallback in the renderer is the only
enforcement, exactly as for `button.variant`.

**contract.json — `theme_roles`.** Replace the tail:

```json
    "surface_variant",
    "on_surface_variant",
    "outline",
    "success",
    "warning"
  ],
```

with:

```json
    "surface_variant",
    "on_surface_variant",
    "surface_container_low",
    "surface_container",
    "surface_container_highest",
    "outline",
    "outline_variant",
    "success",
    "warning"
  ],
```

This order is load-bearing downstream: `jetpacs-widgets-test.el:875-877` compares
`jetpacs-theme-roles` to `theme_roles` with `equal` on the ORDERED list, so the elisp
mirror must take the same order (below).

**goldens/widgets.golden** — three lines appended, exercising the closed vocabulary
exhaustively (`elevated` explicitly as well as by omission, which line 29 already covers).
At the next free index — 75 on `ebp` @ `83d6e08`, where the file has 75 lines, indices
0–74; renumber if a sibling amendment in this batch lands first:

```
75 {"children":[{"t":"text","text":"a"}],"t":"card","variant":"filled"}
76 {"children":[{"t":"text","text":"a"}],"on_tap":{"action":"demo.tap"},"t":"card","variant":"outlined"}
77 {"children":[{"t":"text","text":"a"}],"t":"card","variant":"elevated"}
```

**goldens/frames.golden — line 38 (index `37`), the §18.4 complete-role-set frame.** This
is the one existing golden the package touches, and §18.4 requires it: the frame's sole
purpose is "at least one `theme.set` frame exercising the complete `theme_roles` set", so
leaving it at 25 roles is the only way to break it. The 25 existing values are kept
byte-for-byte; the four new roles take values interpolated between their neighbours on the
fixture's existing ramp, and no two values collide. Replace the line with:

```
37 {"jsonrpc":"2.0","method":"theme.set","params":{"colors":{"background":"#a86668","error":"#886680","error_container":"#986674","on_background":"#b06662","on_error":"#90667a","on_error_container":"#a0666e","on_primary":"#3066c2","on_primary_container":"#4066b6","on_secondary":"#5066aa","on_secondary_container":"#60669e","on_surface":"#c06656","on_surface_variant":"#d0664a","on_tertiary":"#706692","on_tertiary_container":"#806686","outline":"#d86644","outline_variant":"#d46647","primary":"#2866c8","primary_container":"#3866bc","secondary":"#4866b0","secondary_container":"#5866a4","success":"#e0663e","surface":"#b8665c","surface_container":"#c26655","surface_container_highest":"#c66651","surface_container_low":"#bc6659","surface_variant":"#c86650","tertiary":"#686698","tertiary_container":"#78668c","warning":"#e86638"},"dark":true,"syntax":{"comment":{"fg":"#616e88","underline":false},"keyword":{"fg":"#cc0000","font_weight":"bold"},"preprocessor":{"fg":"#ff7f9f","italic":true},"tag":{"fg":"#caa6df"}}}}
```

Because this frame pushes every derived role explicitly, no derivation fires on it and the
gate below is invisible to it — the gate's corpus witness is index 20, not this line.

No `goldens/wire/` fixture changes; no `manifest.json` change.

**ebp/validate.py — one new arm.** `check_params` already validates every `theme.set`
`colors` key against `theme_roles` (amendment #127, `validate.py:325`), but nothing enforced
§18.4's *completeness* MUST. In `main()`, immediately before the `seen_methods` coverage
floor (`:763`), insert:

```python
    # SPEC 18.4: "The golden corpus MUST contain at least one `theme.set`
    # frame exercising the complete `theme_roles` set." Nothing enforced that
    # MUST, so a role added to the contract could leave the corpus silently
    # incomplete -- the drift class amendment #127 found in this same payload.
    all_roles = set(contract["theme_roles"])
    if not any(set(msg.get("params", {}).get("colors") or {}) == all_roles
               for msg in (json.loads(line)
                           for line in golden_lines("frames.golden"))
               if msg.get("method") == "theme.set"):
        problem("coverage: no theme.set frame exercises the complete "
                "theme_roles set (SPEC 18.4)")
```

**Dry run of the complete package** (contract + both goldens + the arm, applied to a copy
of `ebp` @ `83d6e08` and re-run for this revision): `OK: 40 frames, 78 widget lines,
7 hypertext nodes, 17 wire fixtures x3 chunkings validate (spec 2.0.0-draft, format 6);
SPEC §8/§11 in sync; 9.3 KAT reproduced`. The arm was then negative-tested by reverting
only the four added keys on frame 37: `coverage: no theme.set frame exercises the complete
theme_roles set (SPEC 18.4)` — `FAIL: 1 problem(s)`, exit status 1.

**Downstream mirrors (llm-poc-2, not `ebp` — regenerate, do not hand-edit):**

- `python3 tools/gen-vocabulary.py` → `companion/wire/.../Vocabulary.kt` `NODE_SCHEMA` card
  row (pinned by `SurfaceStoreTest.kt:731-745`, which asserts exact equality against
  `contract.json`).
- `python3 tools/gen-jetpacs-vocabulary.py` → `emacs/jetpacs-vocabulary.el:51`, today
  `("card" ("children") ("on_long_tap" "on_tap" "swipe_end" "swipe_start"))`, becoming
  `("card" ("children") ("on_long_tap" "on_tap" "swipe_end" "swipe_start" "variant"))`
  (pinned by `jetpacs-widgets-test.el/catalog-node-schema`). This is also what teaches the
  container trailing-option checker to accept `:variant`.
- Both mirrors are drift-tested and MUST be regenerated in the same commit as this
  `node_schema` change. `field_types` is unchanged.
- `emacs/jetpacs-widgets.el:67-74` is hand-written and ORDER-pinned by
  `jetpacs-widgets-test.el/catalog-theme-roles`. Replace with:

  ```elisp
  (defconst jetpacs-theme-roles
    '("primary" "on_primary" "primary_container" "on_primary_container"
      "secondary" "on_secondary" "secondary_container" "on_secondary_container"
      "tertiary" "on_tertiary" "tertiary_container" "on_tertiary_container"
      "error" "on_error" "error_container" "on_error_container"
      "background" "on_background" "surface" "on_surface"
      "surface_variant" "on_surface_variant"
      "surface_container_low" "surface_container" "surface_container_highest"
      "outline" "outline_variant" "success" "warning")
    "The theme-role color tokens (contract.json `theme_roles'; §18.4).")
  ```

  This is also what makes `jetpacs-color-valid-p` (`:444-452`) stop calling the four new
  roles unknown.
- `jetpacs-card` (`emacs/jetpacs-widgets.el:853-872`) reads its trailing options by name,
  so it needs a `:variant` arm in the `let*` and a docstring line, and `:variant variant`
  threaded into the `jetpacs--node "card"` emit at **`:867`**.
- `test/jetpacs-widgets-test.el` — `jetpacs-widgets/layout-goldens` (`:153-180`) hand-lists
  the golden indices it checks (`chk "29"`, `chk "30"` are the card vectors). Nothing forces
  a new index to be covered, so without new arms the builder could ship a broken `:variant`
  with the goldens still green. Add, next to `chk "30"`:

  ```elisp
  (chk "75" (jetpacs-card (jetpacs-text "a") :variant "filled"))
  (chk "76" (jetpacs-card (jetpacs-text "a") :variant "outlined"
                          :on-tap (jetpacs-action "demo.tap")))
  (chk "77" (jetpacs-card (jetpacs-text "a") :variant "elevated"))
  ```
- `docs/lookup-tables/WIDGET-REFERENCE.org:70` and `M3-COMPONENT-LOOKUP.org:75` both say
  "ElevatedCard" and stop being true.

`variant` is absent from contract `field_types` today (as it is for `button` and
`progress`), so `SpecValidator.checkScalarFieldType` takes its `else -> Unit` arm
(`SpecValidator.kt:495`) and the §12 rule 6 fallback lives in the renderer, exactly as for
`button.variant`. Adding it to `field_types` is not an option here: that map is a FLAT
bare-name → type map, so a `variant` entry would type the name globally for every node type.

### Companion implementation

**1. `render/LayoutNodes.kt:328-352`, `RenderCard`.** Two imports first —
`LayoutNodes.kt:51` imports `ElevatedCard` only, so the block below does not compile
without them:

```kotlin
import androidx.compose.material3.Card
import androidx.compose.material3.OutlinedCard
```

Today the container is a literal:

```kotlin
    val content: @Composable () -> Unit = {
        ElevatedCard(                                    // :334
            modifier = m.fillMaxWidth().then(
```

Hoist the modifier and the body, then dispatch. The click keeps riding the modifier
(`:335-341`), so the no-`onClick` overloads are the right ones and tap/long-tap/swipe
behaviour is untouched; `m` is passed through unchanged in all three arms, which is what
the new §17.3 sentence means by a universal `border` composing with the variant:

```kotlin
    val cardModifier = m.fillMaxWidth().then(
        if (onLongTap != null) Modifier.combinedClickable(
            onClick = { if (onTap != null) ctx.action(onTap) },
            onLongClick = { ctx.action(onLongTap) })
        else Modifier.clickable(enabled = onTap != null) {
            if (onTap != null) ctx.action(onTap)
        })
    val body: @Composable ColumnScope.() -> Unit = {
        Box(Modifier.padding(16.dp)) {
            RenderChildren(node.arrOrNull("children"), ctx)
        }
    }
    val content: @Composable () -> Unit = {
        when (node.stringOr("variant")) {
            "filled" -> Card(modifier = cardModifier, content = body)
            "outlined" -> OutlinedCard(modifier = cardModifier, content = body)
            else -> ElevatedCard(modifier = cardModifier, content = body)  // §12 r6
        }
    }
```

All three signatures exist in material3 1.5.0-alpha16 and all three take the same
`Function3<ColumnScope, Composer, Integer, Unit>` content slot (`javap` on
`androidx.compose.material3.CardKt`): `Card(Modifier, Shape, CardColors, CardElevation,
BorderStroke, content)`, `ElevatedCard(Modifier, Shape, CardColors, CardElevation,
content)`, `OutlinedCard(Modifier, Shape, CardColors, CardElevation, BorderStroke,
content)`. None is experimental, so no `@OptIn` is added. `NodeAccess.stringOr` returns
`""` for an absent member, so absent and unknown take the same `else` arm — one expression
discharging both the default and the §12 rule 6 fallback.

**Why this is G-11-dependent, from the artifact rather than from the docs.** Disassembling
the token classes gives the container colours the three defaults resolve to:

| composable | `CardDefaults` colors | container token |
|---|---|---|
| `Card` | `cardColors()` | `FilledCardTokens.ContainerColor` = `ColorSchemeKeyTokens.SurfaceContainerHighest` |
| `ElevatedCard` | `elevatedCardColors()` | `ElevatedCardTokens.ContainerColor` = `SurfaceContainerLow` |
| `OutlinedCard` | `outlinedCardColors()` + `outlinedCardBorder()` | `OutlinedCardTokens.ContainerColor` = `Surface`, `OutlineColor` = `OutlineVariant` |

So the elevated default already lands on a role `buildColorScheme` derives, and the two new
variants land on the two roles it does not.

**2. `render/ThemeModel.kt:59-101`, `buildColorScheme`.** Add two flags after the effective
surface pair is computed (`:61-62`):

```kotlin
    val surfacePushed = c.role("surface") != null || c.role("surface_variant") != null
    val outlinePushed = c.role("outline") != null
```

`role()` returns null for an absent OR unparseable value, so a malformed hex is not a push.
Lines 96-99 today read:

```kotlin
        outline = c.role("outline") ?: base.outline,
        surfaceContainerLow = lerp(surface, surfaceVariant, 0.25f),
        surfaceContainer = lerp(surface, surfaceVariant, 0.5f),
        surfaceContainerHigh = lerp(surface, surfaceVariant, 0.75f),
```

Replace with:

```kotlin
        outline = c.role("outline") ?: base.outline,
        // §18.4 (amendment #160): the four DERIVED roles, plus the gate the
        // three shipped stops never had. A pushed value wins; otherwise the
        // role is derived ONLY when at least one of the roles it derives from
        // was pushed, and keeps the base scheme's own tone when none was.
        // Without the gate, `surfaceContainerHighest = surfaceVariant` would
        // fire for ANY colors map — including one pushing only `primary` —
        // and move every Switch's OFF track (SwitchTokens.UnselectedTrackColor
        // = SurfaceContainerHighest). See D3.
        outlineVariant = c.role("outline_variant")
            ?: if (outlinePushed || surfacePushed)
                   lerp(c.role("outline") ?: base.outline, surface, 0.5f)
               else base.outlineVariant,
        surfaceContainerLow = c.role("surface_container_low")
            ?: if (surfacePushed) lerp(surface, surfaceVariant, 0.25f)
               else base.surfaceContainerLow,
        surfaceContainer = c.role("surface_container")
            ?: if (surfacePushed) lerp(surface, surfaceVariant, 0.5f)
               else base.surfaceContainer,
        surfaceContainerHigh = if (surfacePushed) lerp(surface, surfaceVariant, 0.75f)
            else base.surfaceContainerHigh,
        surfaceContainerHighest = c.role("surface_container_highest")
            ?: if (surfacePushed) surfaceVariant else base.surfaceContainerHighest,
```

`lerp` (`androidx.compose.ui.graphics.lerp`) is already imported at `ThemeModel.kt:20` and
interpolates in Oklab (`Color.kt:546-551`), i.e. perceptually. `ColorScheme.copy` carries
`outlineVariant` and all five `surfaceContainer*` parameters in 1.5.0-alpha16 (`javap` on
`androidx.compose.material3.ColorScheme`: `getOutlineVariant`,
`getSurfaceContainer{,Low,Lowest,High,Highest}`). `surfaceContainerHigh` keeps no push arm
because `surface_container_high` is not a wire role under D2-A.

*Sanity of the `outline_variant` formula against the baseline it replaces* (Oklab midpoint
of the effective `outline` and the effective `surface`, computed from
`PaletteTokens`/`ColorLightTokens`/`ColorDarkTokens`):

| polarity | `outline` | `surface` | derived | baseline `OutlineVariant` |
|---|---|---|---|---|
| light | `#79747E` | `#FEF7FF` | `#B9B3BC` | `#CAC4D0` |
| dark | `#938F99` | `#141218` | `#4F4C54` | `#49454F` |

Close in dark, one step darker in light — the same family, and the point is that it now
tracks a pushed palette instead of a frozen one.

**3. `render/ColorModel.kt:54-83`, `resolveColorIn`.** Three arms, next to the existing
`on_surface_variant` at `:68`:

```kotlin
        "surface_container_low" -> scheme.surfaceContainerLow
        "surface_container" -> scheme.surfaceContainer
        "surface_container_highest" -> scheme.surfaceContainerHighest
```

`outline_variant` needs no arm — it is already resolved at `:76`; edit 2 is what makes that
line return the pushed theme's tone instead of the baseline's. Without the new arms the
three container roles fall to `else -> scheme.onSurface` (`:82`), i.e. a near-black
"background".

**4. `app/src/test/.../ThemeModelTest.kt`.** The existing
`overlaysPushedRolesAndKeepsBaseForTheRest` case pushes `surface`/`surface_variant`, so the
gate is open on it and its two container assertions (`:37-38`) still pass unchanged. Add,
on that same monotone-grey fixture (`surface` `#101010`, `surface_variant` `#303030`, whose
ramp is monotonic per channel — which is the only reason the existing
`scheme.surfaceContainer.red < scheme.surfaceVariant.red` assertion works, and the form any
new ordering assertion has to take):

```kotlin
        assertNotEquals(base.surfaceContainerHighest, scheme.surfaceContainerHighest)
        assertEquals(scheme.surfaceVariant, scheme.surfaceContainerHighest)   // D1-A
        assertTrue(scheme.surface.red < scheme.surfaceContainerLow.red)
        assertTrue(scheme.surfaceContainerLow.red < scheme.surfaceContainer.red)
        assertNotEquals(base.outlineVariant, scheme.outlineVariant)           // surface-only arm
```

plus two new cases:

- `pushedDerivedRoleWinsOverTheDerivation` — a `colors` map with `surface`,
  `surface_variant` AND `surface_container_highest: "#abcdef"` yields exactly `#abcdef`.
- `derivedRolesKeepTheBaseWhenNoSourceRoleIsPushed` — the P1 regression guard, and the
  corpus case (`frames.golden` index 20): a `colors` map of `primary` + `on_primary` only
  leaves `surfaceContainerLow`, `surfaceContainer`, `surfaceContainerHigh`,
  `surfaceContainerHighest` and `outlineVariant` all equal to the base scheme's. Without
  the gate this case fails on all five.

The caveat that bounds the whole ledger: these are data assertions on `buildColorScheme`.
The Companion has no Compose UI test infrastructure, so nothing in the gates will witness
that a `filled` card actually draws a filled container, or that a pushed
`surface_container_highest` reaches it.

### Unblocks

**4 examples, all in `emacs/apps/m3-catalog/jetpacs-m3-card.el`, all currently
`:unsupported`.** All four are cleared by this amendment alone — `variant` makes them
buildable, and the theme half is what makes the container they select honour a pushed
palette:

| slug | today | after |
|---|---|---|
| `CardSample` | `:unsupported jetpacs-m3-card--filled-note` (`:95`) | `:build`, `:variant "filled"` |
| `ClickableCardSample` | `:unsupported`, "only half of this one is on the wire" (`:100-101`) | `:build`, `:variant "filled"` + `:on-tap` |
| `OutlinedCardSample` | `:unsupported jetpacs-m3-card--outlined-note` (`:116`) | `:build`, `:variant "outlined"` |
| `ClickableOutlinedCardSample` | `:unsupported` (`:121-122`) | `:build`, `:variant "outlined"` + `:on-tap` |

Upstream `CardSamples.kt` confirms the pairing: `CardSample`/`ClickableCardSample` use
`Card`, `OutlinedCardSample`/`ClickableOutlinedCardSample` use `OutlinedCard`, all four at
`Modifier.size(width = 180.dp, height = 100.dp)` — which `jetpacs-m3-card--sized` already
reproduces for the elevated pair.

The card module's six examples are one 3×2 matrix (three containers × plain/clickable);
this completes it. Both shared reason constants (`--filled-note` at `:37-39`,
`--outlined-note` at `:41-43`) and both per-example strings become factually false on
ratification and must be deleted with the same change — they are product text on the
"Not supported" screen, which is why the audit counts a stale one as a defect. The module
commentary at `:11-26` says the same thing in prose and goes with them.

**Not cleared by this amendment, but named because G-11 is its stated blocker:**

- `navigation-rail/WideNavigationRailCollapsedSample` — G-11 supplies the rail's container
  colour; still gated on **G-86** (the `navigation_rail` node type,
  `AUDIT-m3-blockers-2026-08-02.md:451`). The ledger's own G-11 row (`:152`) says "with
  G-58", which is the `slider.orientation` gap (`:330`); that line needs the same
  correction.
- **G-21** (`text_input.variant = "filled"`) is not in this amendment's scope, but its
  fidelity depends on it: M3's filled text field container is `surfaceContainerHighest`,
  the role edit 2 unfreezes. Landing G-21 before #160 would ship a filled field whose
  container ignores the pushed palette.

**Design decisions required**

Three real choices; the draft above is written as A in all three.

**D1 — where the derived container ramp tops out.**

| | Option | Consequence |
|---|---|---|
| **A** *(recommended, drafted)* | `surfaceContainerHighest` = the pushed `surface_variant` (the ramp's endpoint, i.e. stop `1.0` of the existing `0.25/0.5/0.75` series) | Invents no number the palette does not supply, and matches the Material baseline's own light-polarity relationship almost exactly (`#E6E0E9` vs `#E7E0EC`). Cost: in dark polarity the baseline puts them further apart (`#36343B` vs `#49454F`), so a filled card and a `surface_variant` background become indistinguishable under a pushed dark palette. Satisfies the softened ordering clause (endpoint-equality is not "outside" the two roles) but sits exactly on the boundary. The escape hatch is first-class — `surface_container_highest` is now a pushable role, so an Emacs theme that wants them distinct says so. |
| B | a sub-endpoint stop, e.g. `lerp(surface, surfaceVariant, 0.85f)` | Keeps filled cards distinguishable from a `surface_variant` background in both polarities, and puts the role strictly inside its two endpoints, at the price of a magic constant with no palette justification, chosen to make one comparison come out. |

Re-spacing the ramp to fit four stops (`0.2/0.4/0.6/0.8`) is **not** an option: it moves
`surfaceContainerLow`, which is the elevated card's container, so every `card` on the wire
today would change colour under a pushed palette — the one thing the `variant` half of this
amendment promises not to do.

**D2 — how much of the container ramp the wire vocabulary names.**

| | Option | Consequence |
|---|---|---|
| **A** *(recommended, drafted)* | the four roles the ledger scoped: `surface_container_low`, `surface_container`, `surface_container_highest`, `outline_variant` | Every added role is justified by a named consumer (the three card containers, the rail, the filled text field), matching the positive-knowledge posture the vocabulary is built on. Leaves one visible asymmetry: `surfaceContainerHigh` is derived internally and used by the drag chrome (`LayoutNodes.kt:671`) but cannot be named from Emacs. |
| B | the complete five-stop ramp: also `surface_container_lowest` and `surface_container_high` | Closes the asymmetry and makes the vocabulary self-evidently complete, for two more strings in `theme_roles`, the elisp mirror, and the golden. Costs an unjustified widening now against §25's later-addition path, which is cheap for theme roles precisely because §16.6 already gives an unknown role a legible fallback. |

**D3 — whether the derivation gate applies to the three already-shipping stops.**

Today `surfaceContainerLow`/`Container`/`High` interpolate unconditionally whenever a
`colors` map is present at all, even one that pushes neither surface role: with neither
endpoint pushed they become a fresh Oklab interpolation of the BASE scheme's own pair, never
the base's actual container tones. That is the arm the drafted §18.4 sentence "keeps its own
scheme's value" describes, and the code does not currently implement it.

| | Option | Consequence |
|---|---|---|
| **A** *(recommended, drafted)* | gate all four container stops uniformly: derive only when `surface` or `surface_variant` is pushed, else keep the base scheme's tone | §18.4 states one rule and the code obeys it literally. Protects the `Switch` OFF track from the new `surfaceContainerHighest` derivation (`SwitchTokens.UnselectedTrackColor` = `SurfaceContainerHighest`, `InputNodes.kt:228` taking the defaults) under `frames.golden` index 20, which pushes only `primary`/`on_primary`. Cost, disclosed: under such a `colors` map, the reorderable drag chrome (`LayoutNodes.kt:671`, `surfaceContainerHigh`) and the `bottom_bar` surface (`Renderer.kt:752`, `surfaceContainer`) move to the base scheme's tones — in dark polarity `#3B3740` → `#2B2930` and `#2D2A32` → `#211F26`. Both moves are toward Material's real container ramp and away from a synthetic interpolation, i.e. a repair, but they are a visible change to already-shipping rendering. |
| B | leave the three shipped stops unconditional; gate only `outlineVariant` and `surfaceContainerHighest` | Zero change to today's drag chrome and `bottom_bar`. Cost: two rules in one function, and §18.4 can no longer state either — the sentence would have to say a derived role is computed from the "effective" surface pair (true of the old three) while separately exempting the two new ones, which is the kind of wording that produces the next G-11. |

Not an option: dropping the gate entirely. That is what the first draft did, and it moves
every `Switch`'s OFF track under any `theme.set` carrying a `colors` map — a regression on
existing traffic the row would have had to disclose rather than a repair.
---

## #161 — the chip family (§17.4): `chip`/`assist_chip` wrap one Material component each, and no member can select a sibling

Drafted 2026-08-02 against `ebp/SPEC.md` @ `83d6e08` (this line carries amendments
through **#152**; #153–#155 live on the rf-4a line, #149 is held). Ledger source:
`docs/AUDIT-m3-blockers-2026-08-02.md` **G-13, G-14, G-15, G-16, G-17**. Every
renderer and Compose claim below was re-verified against the file and against the
`material3-android-1.5.0-alpha16` `classes.jar` (`javap -c`), not taken from the
ledger and not inferred from the newer `androidx-main` checkout, which already
carries a two-boolean `FilterChipDefaults.horizontalArrangement` overload that
alpha16 does not.

Revision 2 (post-review). Four substantive corrections against revision 1, each
listed here so a ratifier who read the first draft knows what moved: a **third**
rejection rule (`chip.icon` and `chip.avatar` are mutually exclusive, because
Compose gives the avatar strict precedence and DROPS the leading icon); two new
**§17.1** edits, because `field_types` is a flat bare-name map and this
amendment therefore types three names globally whether or not it admits it;
`content_spacing` extended to `assist_chip`, which has the identical Compose
capability; and a **`non-negative-dp`** field type, because the shared `"dp"`
arm checks finiteness only.

### SPEC-CHANGES row (ready to paste)

> | 161 | 2026-08-02 | §17.1, §17.4 (cross-ref §12 rule 6, §16.1, §16.3, §16.4; contract) | **The chip family, completed — five optional members take `chip` and `assist_chip` from two Material components to seven.** §17.4's `chip` row wrapped exactly one component (`FilterChip`) and `assist_chip` exactly one (`AssistChip`), and neither row carried any member that could select a sibling in the same family — so `ElevatedFilterChip`, `InputChip`, `ElevatedAssistChip`, `SuggestionChip` and `ElevatedSuggestionChip` were unreachable from the wire, and the reference catalog reported them with three shared reason strings, two of which ("there is no input_chip node type", "there is no suggestion_chip node type") announce a missing NODE TYPE when what is missing is one enum value on a node whose member set the target component already matches verbatim: `InputChip` takes `selected`/`onClick`/`label`/`enabled` exactly as `FilterChip` does, and `SuggestionChip` takes `onClick`/`label`/`enabled` exactly as `AssistChip` does. Five members close it. `chip.variant` (`flat` default, `elevated`, `input`) and `assist_chip.variant` (`flat` default, `elevated`, `suggestion`, `elevated_suggestion`) select the container, and an unrecognized value in either falls back to `flat` under Section 12 rule 6 and Section 16.1's fallback-instead-of-rejection carve-out, exactly as `text.style` falls back to `body` and `dialog.style` to `dialog`. `chip.trailing_icon` and `assist_chip.trailing_icon` are identifiers filling a slot that was not merely unauthored but unreachable: each node has one `icon` member and `RenderChip`/`RenderAssistChip` spend it on `leadingIcon` (`InputNodes.kt:127`, `:141`), passing no `trailingIcon` argument at all — this member also repairs a shipped `:build`, `ChipGroupSingleLineSample`, whose nine assist chips silently drop upstream's per-chip ArrowDropDown. `chip.avatar` is an identifier in `InputChip`'s circular 24 dp `InputChipDefaults.AvatarSize` slot, which is distinct from and larger than the 18 dp leading icon and exists on no other chip in the family. `content_spacing` is a non-negative `dp` for the gap between a chip's own leading slot, label and trailing slot — interior geometry that no universal attribute reaches, because `padding` lands on the modifier the widget is composed with, i.e. as margin (`Attributes.kt:130-133`), outside the chip container entirely; it is carried by BOTH nodes, because `AssistChipDefaults.horizontalArrangement-0680j_4(float)` and `SuggestionChipDefaults.horizontalArrangement-0680j_4(float)` exist in alpha16 exactly as their filter/input twins do, so a chip-only member would be a vocabulary asymmetry with no capability behind it. **Every one of the five is OPTIONAL and every default is today's rendering**, so no existing frame, golden, fixture or authored surface changes meaning: an absent `variant` is the flat filter/assist chip the renderer builds now; an absent `trailing_icon` or `avatar` passes `null` on exactly the absent-`icon` path the renderer already takes; and an absent `content_spacing` leaves Compose's own `ChipArrangement(8.dp)` in place, which is precisely what a `FilterChip` constructed without a `horizontalArrangement` argument gets today. THREE combinations are invalid content rather than ignored, because in each the authored member draws nothing and the sender has no way to learn it: `chip.avatar` requires `variant: "input"`; `chip.avatar` and `chip.icon` are mutually exclusive, because `InputChip` forwards both slots but `leadingContent()` returns the avatar and DISCARDS the leading icon (verified in the alpha16 bytecode, not inferred — `leadingContent-XO-JAsU` branches `ifnull` on `avatar` and returns it without reading `leadingIcon`, under an `InputChip` KDoc that says "In case both are provided, the avatar will take precedence"); and `assist_chip.trailing_icon` is invalid under `suggestion`/`elevated_suggestion`, because `SuggestionChip` and `ElevatedSuggestionChip` take a single `icon` parameter and NO `trailingIcon` parameter, verified in the alpha16 `C(SuggestionChip)N(onClick,label,modifier,enabled,icon,…)` composer trace. Each rule names the variants that LACK the slot rather than the ones that have it, so an unrecognized `variant` — which falls back to `flat`, a container that HAS a trailing slot and has NO avatar slot — is accepted for `trailing_icon` and rejected for `avatar` without either implementation having to reason about the Section 12 substitution, and the Python and Kotlin arms agree for every JSON kind including a non-string `variant`. Enforcement, per the #150/#151 duties, stated with its exact scope and no more: `validate.py`'s `check_node` unknown-key check (`:284-287`) covers the member NAMES against `node_schema`, and two new arms cover the three combination rules; the Companion's `SpecValidator.checkScalarFieldType` (`:467-497`) covers `trailing_icon`/`avatar` as identifiers (regex + `MAX_IDENTIFIER_OCTETS`) and, through a new `non-negative-dp` arm added by this amendment, `content_spacing` as a finite number `>= 0` — the pre-existing `"dp"` arm at `:482-484` checks finiteness ONLY, so reusing it would have left the SPEC saying MUST and nothing checking it; `VocabularyDriftTest` (`SurfaceStoreTest.kt:727-756`) covers `Vocabulary.kt` against `node_schema` and `field_types`, and `jetpacs-widgets/catalog-node-schema` (`test/jetpacs-widgets-test.el:889-905`) covers `jetpacs-vocabulary.el` against `node_schema`; the two enum domains are enforced by NOTHING, which is both deliberate — Section 16.3 and Section 12 rule 6 give both a safe fallback rather than a rejection — and unavoidable, since `contract.json`'s `enums` block is read by no tool in the tree and the block is added here as documentation only; and nothing asserts on a composition, because the Companion has no Compose UI test infrastructure. This amendment introduces no monotonically consumed resource, so the Section 25 exhaustion duty is discharged as not-applicable. Additive under Section 25: five optional members, two new closed vocabularies, three new `field_types` entries and one new `field_types` VALUE; no existing member, enum, type, golden or fixture is modified, and a Companion that ignores all five renders precisely what it renders today. | §17.1 identifier sentence += `trailing_icon`, `avatar`; §17.1 non-negative-dp sentence += `content_spacing`; contract `node_schema.chip.optional` += `trailing_icon`, `avatar`, `variant`, `content_spacing`; `node_schema.assist_chip.optional` += `trailing_icon`, `variant`, `content_spacing`; `field_types` += `trailing_icon`/`avatar` (identifier), `content_spacing` (non-negative-dp); `enums` += `chip.variant`, `assist_chip.variant` (documentation only — no tool reads `enums`); goldens/widgets.golden += 5 lines; validate.py chip/assist_chip combination arms; SpecValidator `non-negative-dp` arm + two per-type arms; regenerate `companion/wire/.../Vocabulary.kt` and `emacs/jetpacs-vocabulary.el` from the contract | |

### SPEC.md edits

**1. §17.1, the common-name paragraph (SPEC.md:2216-2223).** Replace, verbatim:

> ```
> Unless a row states a narrower rule, fields named `text`, `label`, `title`,
> `caption`, `hint`, `content_description`, `annotation`, and `summary` are plain
> JSON strings; fields named `icon` and `syntax` are identifiers; fields named
> `children` are arrays of Nodes; and fields beginning `on_` are
> ActionDescriptors. Optional booleans default to `false` unless stated
> otherwise. Numeric values MUST be finite; layout numbers MUST also be
> non-negative. Arrays and strings MUST fit Section 4.5 and the advertised module
> limits.
> ```

with:

> ```
> Unless a row states a narrower rule, fields named `text`, `label`, `title`,
> `caption`, `hint`, `content_description`, `annotation`, and `summary` are plain
> JSON strings; fields named `icon`, `trailing_icon`, `avatar`, and `syntax` are
> identifiers; fields named `children` are arrays of Nodes; and fields beginning
> `on_` are ActionDescriptors. Optional booleans default to `false` unless
> stated otherwise. Numeric values MUST be finite; layout numbers MUST also be
> non-negative. Arrays and strings MUST fit Section 4.5 and the advertised module
> limits.
> ```

**2. §17.1, the dp paragraph (SPEC.md:2233-2238).** Replace, verbatim:

> ```
> `font_weight` is `normal`, `bold`, or an integer multiple of 100 from 100
> through 900. `selectable`, `italic`, `underline`, and `mono` are booleans.
> `size`, `spacing`, `run_spacing`, `content_padding`, `elevation`, and
> `thickness` are non-negative `dp`. An action-valued field MUST contain a valid
> descriptor even when the platform cannot expose that interaction; a sender
> MUST NOT rely on a hidden action as the only path to load-bearing behavior.
> ```

with:

> ```
> `font_weight` is `normal`, `bold`, or an integer multiple of 100 from 100
> through 900. `selectable`, `italic`, `underline`, and `mono` are booleans.
> `size`, `spacing`, `run_spacing`, `content_padding`, `content_spacing`,
> `elevation`, and `thickness` are non-negative `dp`; a negative
> `content_spacing` MUST be rejected under Section 16.1 rather than clamped.
> An action-valued field MUST contain a valid
> descriptor even when the platform cannot expose that interaction; a sender
> MUST NOT rely on a hidden action as the only path to load-bearing behavior.
> ```

Both §17.1 edits are load-bearing and were absent from revision 1. `field_types`
in `contract.json` is a FLAT bare-name → type map (`"icon": "identifier"` at
`:522`, `"content_padding": "dp"` at `:574` — never `<node>.<member>`, in
contrast to `enums`, which IS keyed `button.variant` at `:626`), and
`SpecValidator.checkScalarFieldType(t, member, node, path)` looks the member up
as `FIELD_TYPES[member]` with the node type `t` never consulted. Adding these
three names to `field_types` therefore types them GLOBALLY whatever §17.4 says,
and §17.1:2230-2231 requires the projection to run the other way ("These
definitions are cumulative and MUST be projected together into `contract.json`").
These edits make the SPEC state the rule the artifact actually carries. The
consequence for G-24 and G-40 is in **Concerns**.

**3. §17.4, the `chip` table row (SPEC.md:2414).** Replace, verbatim:

> ```
> | `chip` | `label: string` | `on_tap`, `selected`, `icon`, `enabled` |
> ```

with:

> ```
> | `chip` | `label: string` | `on_tap`, `selected`, `icon`, `trailing_icon`, `avatar`, `variant`, `content_spacing`, `enabled`. `variant`: `flat` (default), `elevated`, or `input`; unknown values fall back to `flat`. |
> ```

**4. §17.4, the `assist_chip` table row (SPEC.md:2415).** Replace, verbatim:

> ```
> | `assist_chip` | `label: string` | `on_tap`, `icon`, `enabled` |
> ```

with:

> ```
> | `assist_chip` | `label: string` | `on_tap`, `icon`, `trailing_icon`, `variant`, `content_spacing`, `enabled`. `variant`: `flat` (default), `elevated`, `suggestion`, or `elevated_suggestion`; unknown values fall back to `flat`. |
> ```

**5. §17.4, new prose.** The member-type paragraph after the table ends
(SPEC.md:2439-2440) with:

> ```
> formats stated below. `enabled` is boolean and defaults to `true` for every
> input node.
> ```

Insert the following three paragraphs AFTER that paragraph and BEFORE the
paragraph beginning "`text_input.value` and `editor.value` default to the empty
string." (SPEC.md:2442):

> `chip.trailing_icon`, `assist_chip.trailing_icon`, and `chip.avatar` are
> identifiers drawn from the same icon vocabulary as `icon`. A chip's `icon`
> occupies the leading slot and `trailing_icon` the trailing slot; `avatar`
> occupies a leading slot distinct from, and larger than, `icon`, and the two
> compete for the same position, so they MUST NOT both be present on one node.
> Omitting `variant` MUST render exactly what this document required before
> these members existed: the flat filter chip and the flat assist chip. An
> unrecognized `variant` on either node falls back to `flat` under Section 12
> rule 6, and a Companion MUST NOT reject a chip for an unrecognized `variant`
> alone. A `variant` that is not a JSON string is an unrecognized value for
> every purpose in this section.
>
> Three member-and-`variant` combinations are invalid content and MUST be
> rejected with `1201 content-invalid` rather than ignored, because in each the
> selected presentation has no slot the member can reach and a sender that
> authored one would otherwise have no way to learn that it drew nothing:
> `chip.avatar` is valid only when `variant` is exactly `input`; `chip.avatar`
> and `chip.icon` MUST NOT both be present; and `assist_chip.trailing_icon` is
> invalid when `variant` is exactly `suggestion` or `elevated_suggestion`. Each
> rule names the variants that LACK the slot, so the fallback of the preceding
> paragraph needs no special treatment: an unrecognized `variant` renders the
> flat container, which has a trailing slot and has no avatar slot, and is
> therefore accepted for `trailing_icon` and rejected for `avatar` on exactly
> the same reading. These are the only rejections these members introduce.
>
> `content_spacing` is the horizontal gap between a chip's own leading slot,
> label, and trailing slot, measured inside the chip container. It is interior
> to the chip and is independent of the universal `padding` of Section 16.5. It
> defaults to the platform's own chip content spacing, and omitting it MUST
> render exactly as this document required before the member existed.

### Artifact changes

**`ebp/contract.json` — `node_schema` (contract.json:317-336).** Replace:

```json
    "chip": {
      "required": [
        "label"
      ],
      "optional": [
        "on_tap",
        "selected",
        "icon",
        "enabled"
      ]
    },
    "assist_chip": {
      "required": [
        "label"
      ],
      "optional": [
        "on_tap",
        "icon",
        "enabled"
      ]
    },
```

with:

```json
    "chip": {
      "required": [
        "label"
      ],
      "optional": [
        "on_tap",
        "selected",
        "icon",
        "trailing_icon",
        "avatar",
        "variant",
        "content_spacing",
        "enabled"
      ]
    },
    "assist_chip": {
      "required": [
        "label"
      ],
      "optional": [
        "on_tap",
        "icon",
        "trailing_icon",
        "variant",
        "content_spacing",
        "enabled"
      ]
    },
```

**`ebp/contract.json` — `field_types`.** After `"icon": "identifier",`
(contract.json:522) insert:

```json
    "trailing_icon": "identifier",
    "avatar": "identifier",
```

After `"content_padding": "dp",` (contract.json:574) insert:

```json
    "content_spacing": "non-negative-dp",
```

`non-negative-dp` is a new `field_types` VALUE, following the existing
`non-negative-integer` naming. Nothing constrains the value vocabulary:
`tools/gen-vocabulary.py:43` copies the map verbatim, `gen-jetpacs-vocabulary.py`
never reads `field_types`, and `validate.py` contains no occurrence of
`field_types` at all. The only consumer is `checkScalarFieldType`'s `when`, which
gains a matching arm below.

`variant` deliberately gets NO `field_types` entry — `button.variant` has none
either, and `SpecValidator.checkScalarFieldType`'s `else -> Unit` arm
(SpecValidator.kt:495) is the correct treatment for a member whose §16.3 /
§12-rule-6 semantics are fallback, not rejection. A non-string `variant` is
consequently caught by neither validator; the two combination arms below are
written so it is nonetheless handled identically on both sides.

**`ebp/contract.json` — `enums`.** After the `"button.variant"` block
(contract.json:626-631) insert:

```json
    "chip.variant": [
      "flat",
      "elevated",
      "input"
    ],
    "assist_chip.variant": [
      "flat",
      "elevated",
      "suggestion",
      "elevated_suggestion"
    ],
```

**This block is documentation, not enforcement.** No tool in the tree reads
`contract.json`'s `enums`: `validate.py` never mentions it, neither generator
projects it, `Vocabulary.kt` stores only the type NAME `"enum"`, and
`VocabularyDriftTest` asserts on `node_schema`, `universal_node_attributes`,
`actions.schema` and `field_types` only. It is added for symmetry with the
nineteen existing entries and so a reader has one place to find the domain.

No `theme_roles`, `node_types`, `core_node_set`, `methods`, `error_codes`,
`limits` or `capabilities` change, and no `contract_format` / `spec_version`
change (still `6` / `2.0.0-draft`).

**`ebp/goldens/widgets.golden` — append five lines.** The file currently ends at
index `74` (75 lines). `chip` and `assist_chip` already satisfy the
per-node-type coverage floor (`validate.py:757-762`), so these are member
coverage, not a floor requirement:

```
75 {"content_spacing":4,"icon":"done","label":"Filter chip","on_tap":{"action":"demo.tap"},"selected":true,"t":"chip","trailing_icon":"arrow_drop_down","variant":"elevated"}
76 {"avatar":"person","label":"Input Chip","on_tap":{"action":"demo.tap"},"selected":true,"t":"chip","trailing_icon":"close","variant":"input"}
77 {"content_spacing":4,"icon":"settings","label":"Assist Chip","on_tap":{"action":"demo.tap"},"t":"assist_chip","trailing_icon":"arrow_drop_down","variant":"elevated"}
78 {"icon":"info","label":"Suggestion Chip","on_tap":{"action":"demo.tap"},"t":"assist_chip","variant":"suggestion"}
79 {"icon":"settings","label":"Suggestion Chip","on_tap":{"action":"demo.tap"},"t":"assist_chip","variant":"elevated_suggestion"}
```

Keys are alphabetically ordered, matching every existing line. Between them
these cover all five new members and **five of the seven enum values by
presence**; the two remaining values are both `flat`, covered by omission on
existing lines `38`/`39`/`40`, which is exactly the
default-preserves-today's-rendering claim. Line `76` also pins the legal shape of
an input chip with an avatar — `avatar` present, `icon` ABSENT, per the new
exclusivity rule — and lines `78`/`79` pin the legal shape of a suggestion chip:
`icon` present, `trailing_icon` absent. `done` and `close` are pre-seeded in
`IconMap`; `person`, `arrow_drop_down`, `settings` and `info` resolve through its
reflective snake_case → PascalCase path over material-icons-extended, and an
unresolved name renders `HelpOutline` rather than erroring (`IconMap.kt:1-6`), so
no golden line can fail on an icon name.

These five lines are driven end to end by `test/smoke-parity.el`, which sends
every `t`-bearing golden vector through a live session as an `app:main` surface
root and asserts `applied`, and replayed by
`companion/wire/.../WidgetsGoldenReplayTest.kt:52-60`. They fall outside every
index range claimed by the byte-parity tests in `test/jetpacs-widgets-test.el`
(input family is `35-44, 48-55`), so no existing test changes; adding matching
`chk` entries there is optional hygiene, not a gate.

**`ebp/validate.py` — two arms.** In `check_node` (validate.py:288-292), replace:

```python
            if t == "text_input" and value.get("single_line") \
                    and "\n" in value.get("value", ""):
                problem(f"{path}: single_line value contains U+000A (SPEC 17.4)")
            if t == "enum_list":
```

with:

```python
            if t == "text_input" and value.get("single_line") \
                    and "\n" in value.get("value", ""):
                problem(f"{path}: single_line value contains U+000A (SPEC 17.4)")
            # SPEC 17.4: a slot the selected variant does not have, and a
            # leading slot two members compete for. Each rule names the
            # variants that LACK the slot, so an unrecognized `variant`
            # (which falls back to `flat`) needs no special case, and a
            # non-string `variant` behaves identically here and in Kotlin.
            if t == "chip" and "avatar" in value:
                if value.get("variant") != "input":
                    problem(f"{path}: chip.avatar requires variant \"input\" "
                            f"(SPEC 17.4)")
                if "icon" in value:
                    problem(f"{path}: chip.avatar and chip.icon are mutually "
                            f"exclusive (SPEC 17.4)")
            if t == "assist_chip" and "trailing_icon" in value \
                    and value.get("variant") in ("suggestion",
                                                 "elevated_suggestion"):
                problem(f"{path}: assist_chip.trailing_icon is invalid with "
                        f"variant `{value.get('variant')}` (SPEC 17.4)")
            if t == "enum_list":
```

No other `validate.py` change: `check_contract` needs nothing (no new node type,
method, or error code), `check_spec_sync` reads only §8 and §11, and the enum
registries are not walked.

**Generated mirrors — regenerate, never hand-edit:**

```
python3 tools/gen-vocabulary.py          # companion/wire/.../Vocabulary.kt
python3 tools/gen-jetpacs-vocabulary.py  # emacs/jetpacs-vocabulary.el
```

Expected diffs, for review:

- `Vocabulary.kt:51-52` →
  `"chip" to NodeRow(setOf("label"), setOf("on_tap", "selected", "icon", "trailing_icon", "avatar", "variant", "content_spacing", "enabled")),`
  and `"assist_chip" to NodeRow(setOf("label"), setOf("on_tap", "icon", "trailing_icon", "variant", "content_spacing", "enabled")),`
  plus three new `FIELD_TYPES` entries. `VocabularyDriftTest`
  (`SurfaceStoreTest.kt:731-756`) fails on both `node_schema` and `field_types`
  until this is regenerated.
- `jetpacs-vocabulary.el:58-59` →
  `("chip" ("label") ("avatar" "content_spacing" "enabled" "icon" "on_tap" "selected" "trailing_icon" "variant"))`
  and `("assist_chip" ("label") ("content_spacing" "enabled" "icon" "on_tap" "trailing_icon" "variant"))`
  (the generator sorts). `jetpacs-widgets/catalog-node-schema`
  (`test/jetpacs-widgets-test.el:889-905`) fails until this is regenerated. Note
  this mirror carries `node_schema` only — `gen-jetpacs-vocabulary.py` never
  reads `field_types`.

### Companion implementation

**File:** `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/InputNodes.kt`.
The whole amendment lands in `RenderChip` (`:116-131`) and `RenderAssistChip`
(`:133-145`); `Renderer.kt:308-309` and `NodeSupport.kt:30` are unchanged — both
node types are already dispatched and already advertised in the app profile.

**Library floor — checked against the shipped AAR, not the source checkout.**
Every name below is present in
`androidx.compose.material3:material3-android:1.5.0-alpha16` (raised in
`ed86191`), read out of `classes.jar` with `javap -c`:

| Compose API | evidence |
|---|---|
| `ElevatedFilterChip`, `InputChip`, `ElevatedAssistChip`, `SuggestionChip`, `ElevatedSuggestionChip` | `ChipKt` public methods |
| `FilterChip`/`ElevatedFilterChip` param order `selected, onClick, label, modifier, enabled, leadingIcon, trailingIcon, …, horizontalArrangement, contentPadding, interactionSource` | `C(FilterChip)N(…)` / `C(ElevatedFilterChip)N(…)` composer traces |
| `AssistChip`/`ElevatedAssistChip` param order `onClick, label, modifier, enabled, leadingIcon, trailingIcon, …, horizontalArrangement, contentPadding, interactionSource` | `C(AssistChip)N(…)` / `C(ElevatedAssistChip)N(…)` |
| `InputChip` param order `selected, onClick, label, modifier, enabled, leadingIcon, avatar, trailingIcon, …, horizontalArrangement, …` | `C(InputChip)N(…)` — three composable slots, `avatar` in the middle |
| **`SuggestionChip`/`ElevatedSuggestionChip` take `icon` and have NO `trailingIcon`** | `C(SuggestionChip)N(onClick,label,modifier,enabled,icon,shape,colors,elevation,border,horizontalArrangement,contentPadding,interactionSource)` |
| **`avatar` STRICTLY PRE-EMPTS `leadingIcon` — they never both draw** | `ChipKt.leadingContent-XO-JAsU`: `29: aload_0` (avatar) `30: ifnull 54` … `50: aload_0; 51: goto 129` — returns the avatar without ever reading `aload_1` (leadingIcon). Source twin, `Chip.kt:3521`: `avatar != null -> avatar // An avatar takes precedence`, KDoc "priority (avatar > leadingIcon)" |
| `horizontalArrangement-0680j_4(float)` on all four `*ChipDefaults` | `FilterChipDefaults`, `InputChipDefaults`, `AssistChipDefaults`, `SuggestionChipDefaults` each expose `horizontalArrangement()` and `horizontalArrangement-0680j_4(float)` |
| `InputChipDefaults.AvatarSize` = **24 dp**, `*ChipTokens.IconSize`/`LeadingIconSize` = **18 dp** | `InputChipTokens.<clinit>`: `204: ldc2_w double 24.0d` → `AvatarSize`; `FilterChipTokens`/`AssistChipTokens`/`SuggestionChipTokens`/`InputChipTokens` all `ldc2_w double 18.0d` → the icon-size field |
| default chip content spacing = **8 dp** on all four | each `*ChipDefaults.<clinit>`: `bipush 8` → `HorizontalSpacing` |
| **none of these carries `@ExperimentalMaterial3ExpressiveApi`** | zero `Experimental` annotations anywhere in `Chip.kt` / `ChipKt` |

Five rows are load-bearing. 8 dp is why an absent `content_spacing` is
byte-for-byte today's rendering (the renderer passes no `horizontalArrangement`
at all, so Compose applies the same default, and `horizontalArrangement(8.dp)`
even returns the same shared instance). The missing `trailingIcon` on the
suggestion pair is why D3's third rejection exists. The `leadingContent`
precedence is why D3's second rejection exists — and it is the correction that
revision 1 got backwards. The four `horizontalArrangement` overloads are why
`content_spacing` is on both nodes. The absence of an opt-in annotation is why no
`@OptIn` is needed and no gate moves.

**Shared helper** (new, private, in `InputNodes.kt`; needs
`androidx.compose.ui.unit.Dp`):

```kotlin
/** null when NAME is empty — the absent-slot path RenderChip already takes. */
private fun chipIcon(name: String, size: Dp): (@Composable () -> Unit)? =
    if (name.isEmpty()) null
    else { { Icon(IconMap.get(name), null, Modifier.size(size)) } }
```

**`RenderChip`** (replaces `InputNodes.kt:119-131`):

```kotlin
internal fun RenderChip(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.objOrNull("on_tap")
    val click = { if (onTap != null) onButton(onTap, ctx) }
    val selected = node.boolOr("selected")
    val enabled = node.boolOr("enabled", true)
    val label: @Composable () -> Unit = { Text(node.stringOr("label")) }
    val gap = node["content_spacing"]?.numOrNull()?.let { safeDp(it) }
    val lead = chipIcon(node.stringOr("icon"), FilterChipDefaults.IconSize)
    val trail = chipIcon(node.stringOr("trailing_icon"), FilterChipDefaults.IconSize)
    when (node.stringOr("variant", "flat")) {
        "elevated" -> ElevatedFilterChip(
            selected, click, label, m, enabled,
            leadingIcon = lead, trailingIcon = trail,
            horizontalArrangement = gap
                ?.let { FilterChipDefaults.horizontalArrangement(it.dp) }
                ?: FilterChipDefaults.horizontalArrangement())
        "input" -> {
            // SPEC 17.4: `icon` and `avatar` are mutually exclusive, because
            // Compose's leadingContent() gives the avatar strict precedence
            // and DROPS the leading icon. SpecValidator rejects the pair
            // before a frame lands; this keeps the invariant local so the
            // renderer can never be the thing that silently drops a member.
            val avatar = chipIcon(node.stringOr("avatar"), InputChipDefaults.AvatarSize)
            InputChip(
                selected, click, label, m, enabled,
                leadingIcon = if (avatar == null) lead else null,
                avatar = avatar,
                trailingIcon = trail,
                horizontalArrangement = gap
                    ?.let { InputChipDefaults.horizontalArrangement(it.dp) }
                    ?: InputChipDefaults.horizontalArrangement())
        }
        else -> FilterChip(                       // `flat` and the SPEC 12 fallback
            selected, click, label, m, enabled,
            leadingIcon = lead, trailingIcon = trail,
            horizontalArrangement = gap
                ?.let { FilterChipDefaults.horizontalArrangement(it.dp) }
                ?: FilterChipDefaults.horizontalArrangement())
    }
}
```

**`RenderAssistChip`** (replaces `InputNodes.kt:134-145`):

```kotlin
internal fun RenderAssistChip(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.objOrNull("on_tap")
    val click = { if (onTap != null) onButton(onTap, ctx) }
    val enabled = node.boolOr("enabled", true)
    val label: @Composable () -> Unit = { Text(node.stringOr("label")) }
    val lead = node.stringOr("icon")
    val trail = node.stringOr("trailing_icon")
    val gap = node["content_spacing"]?.numOrNull()?.let { safeDp(it) }
    when (node.stringOr("variant", "flat")) {
        "elevated" -> ElevatedAssistChip(
            click, label, m, enabled,
            leadingIcon = chipIcon(lead, AssistChipDefaults.IconSize),
            trailingIcon = chipIcon(trail, AssistChipDefaults.IconSize),
            horizontalArrangement = gap
                ?.let { AssistChipDefaults.horizontalArrangement(it.dp) }
                ?: AssistChipDefaults.horizontalArrangement())
        // NOTE: SuggestionChip's leading slot is named `icon`, NOT
        // `leadingIcon`, and it has no trailing slot at all — which is
        // exactly why assist_chip.trailing_icon is invalid under these two.
        "suggestion" -> SuggestionChip(
            click, label, m, enabled,
            icon = chipIcon(lead, SuggestionChipDefaults.IconSize),
            horizontalArrangement = gap
                ?.let { SuggestionChipDefaults.horizontalArrangement(it.dp) }
                ?: SuggestionChipDefaults.horizontalArrangement())
        "elevated_suggestion" -> ElevatedSuggestionChip(
            click, label, m, enabled,
            icon = chipIcon(lead, SuggestionChipDefaults.IconSize),
            horizontalArrangement = gap
                ?.let { SuggestionChipDefaults.horizontalArrangement(it.dp) }
                ?: SuggestionChipDefaults.horizontalArrangement())
        else -> AssistChip(                       // `flat` and the SPEC 12 fallback
            click, label, m, enabled,
            leadingIcon = chipIcon(lead, AssistChipDefaults.IconSize),
            trailingIcon = chipIcon(trail, AssistChipDefaults.IconSize),
            horizontalArrangement = gap
                ?.let { AssistChipDefaults.horizontalArrangement(it.dp) }
                ?: AssistChipDefaults.horizontalArrangement())
    }
}
```

Naming `horizontalArrangement` also disambiguates every call from the
`@Deprecated(level = HIDDEN)` binary-compatibility overload that omits it.

**Behaviour-preservation check.** Today's leading icons are drawn at a hardcoded
`Modifier.size(18.dp)` (`InputNodes.kt:128`, `:142`).
`FilterChipTokens.IconSize`, `AssistChipTokens.IconSize`,
`SuggestionChipTokens.LeadingIconSize` and `InputChipTokens.LeadingIconSize` all
resolve to `18.0` at 1.5.0-alpha16, so the swap is value-identical today and
stays correct if a token moves; a ratifier who wants literally zero risk may keep
the `18.dp` literal without changing anything else in this amendment. The
`input` branch reuses `lead`, built at `FilterChipDefaults.IconSize`, rather than
`InputChipDefaults.IconSize` — also 18 dp, so also value-identical.

**Wire-side rejection** — `companion/wire/.../SpecValidator.kt`, the per-type
`when (t)` at `:547`. Two new arms carrying the three rules:

```kotlin
            "chip" -> if ("avatar" in node) {
                if (node.stringOrNull("variant") != "input")
                    throw ContentInvalid("$path.avatar", "avatar requires variant \"input\"")
                if ("icon" in node)
                    throw ContentInvalid("$path.avatar", "avatar and icon are mutually exclusive")
            }
            "assist_chip" -> if ("trailing_icon" in node &&
                node.stringOrNull("variant") in listOf("suggestion", "elevated_suggestion"))
                throw ContentInvalid("$path.trailing_icon",
                    "trailing_icon is invalid with this variant")
```

**These agree with `validate.py` for every JSON kind, which revision 1 did not.**
`stringOrNull` returns null for a JSON number (`JsonAccess.kt:38-39`:
`(this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content`), so revision 1's
`!in listOf(null, "flat", "elevated")` ACCEPTED `{"variant": 3}` while the Python
rejected it. Writing each rule as membership in the set of variants that lack the
slot removes the asymmetry structurally rather than by adding a presence test:
`null in listOf("suggestion", "elevated_suggestion")` is false and
`3 in ("suggestion", "elevated_suggestion")` is false, so both sides accept; and
`null != "input"` and `3 != "input"` are both true, so both sides reject. Case
table, Python arm ‖ Kotlin arm:

| authored `variant` | `avatar` present | `assist_chip.trailing_icon` present |
|---|---|---|
| absent | reject ‖ reject | accept ‖ accept |
| `"flat"` / `"elevated"` | reject ‖ reject | accept ‖ accept |
| `"input"` | accept ‖ accept | n/a |
| `"suggestion"` / `"elevated_suggestion"` | reject ‖ reject | **reject ‖ reject** |
| `"elevted"` (unrecognized) | reject ‖ reject | accept ‖ accept |
| `3` (non-string) | reject ‖ reject | accept ‖ accept |

**New `checkScalarFieldType` arm** (`SpecValidator.kt:467-497`), beside the
existing `"dp", "number"` arm at `:482-484`:

```kotlin
            "non-negative-dp" -> node[member]?.asDoubleOrNull().let {
                if (it == null || !it.isFinite() || it < 0.0) bad("a non-negative number")
            }
```

Without this, §17.1's "non-negative" would be words with nothing behind them:
the shared `"dp"` arm tests finiteness only, `validate.py` type-checks nothing
(it never reads `field_types`), and `safeDp` (`Attributes.kt:41-42`,
`v.toFloat().takeIf { it.isFinite() && it >= 0f }`) would turn a negative into
`null` and thus into the 8 dp default — a silent drop that SPEC.md:2111-2112
forbids in as many words. The identifier and finite-number checks for
`trailing_icon`, `avatar` and `content_spacing` otherwise need no code: once
`field_types` carries them, `checkScalarFieldType` runs from the
`for (member in row.required + row.optional)` loop at `:546`.

**Accessibility.** All icon slots pass `contentDescription = null`, exactly as
the current leading-icon path does: they are decorative, and §16.4's derivation
floor (SPEC.md:2157-2159, amendment #145) takes the chip's `label` as the
accessible name. No chip in this family can ever be icon-only, because `label`
is REQUIRED.

**Elisp builders** (`emacs/jetpacs-widgets.el:1011-1028`). `jetpacs-chip` gains
`&key trailing-icon avatar variant content-spacing` and `jetpacs-assist-chip`
gains `&key trailing-icon variant content-spacing`, each guarded with the
existing `jetpacs--check-identifier` (`:91`) and `jetpacs--check-number` (`:140`,
with `min` 0) helpers, and each mirroring all three combination rules so an
authoring mistake signals in Emacs rather than arriving as a `1201` on device.

### Unblocks

**8 catalog examples — the entire remaining `:unsupported` set of the `chips`
module** (`emacs/apps/m3-catalog/jetpacs-m3-chips.el:145-215`). After this
amendment the module is 13 of 13 `:build`: the largest component group to reach
zero unsupported, joining `badge` (1 of 1), `swipe-to-dismiss` (1 of 1) and
`navigation-bar` (3 of 3), which are already there.

| slug | gap(s) | retires reason string |
|---|---|---|
| `ElevatedFilterChipSample` | G-13 | `jetpacs-m3-chips--elevated-note` (`:44-46`) |
| `ElevatedAssistChipSample` | G-14 | `jetpacs-m3-chips--elevated-note` |
| `SuggestionChipSample` | G-14 | `jetpacs-m3-chips--suggestion-note` (`:52-54`) |
| `ElevatedSuggestionChipSample` | G-14 | inline `:204` ("no suggestion_chip node type … no variant or elevation member") |
| `InputChipSample` | G-13 | `jetpacs-m3-chips--input-note` (`:48-50`) |
| `InputChipWithAvatarSample` | G-13 + G-16 | inline `:193` ("no input_chip node type … no avatar slot") |
| `FilterChipWithTrailingIconSample` | G-15 | inline `:176` ("one icon member and the renderer spends it on leadingIcon") |
| `FilterChipWithCustomSpacingSample` | G-17 | inline `:182` ("no horizontal_arrangement member") |

All three shared reason constants (`--elevated-note`, `--input-note`,
`--suggestion-note`, at `jetpacs-m3-chips.el:44-54`) are fully retired — the
first has two uses (`:155`, `:165`), the other two one each (`:187`, `:198`).
Each was factually wrong in the way the audit's headline counts: they announce a
missing node type where a member was missing.

**The new exclusivity rule costs nothing here.** `InputChipWithAvatarSample`
authors `avatar` and no `leadingIcon` upstream (`ChipSamples.kt:250-264`), so it
builds as `:avatar "person"` with no `:icon`. The count stands at 8.

**This count is not severable from D1.** Route B (a real `input_chip` node type)
moves `InputChipSample` and `InputChipWithAvatarSample` to a separate
NEEDS_NODE amendment and drops this one from 8 to 6.

**Plus one already-shipped `:build` repaired, not unblocked.**
`ChipGroupSingleLineSample` currently drops upstream's per-chip
`Icons.Filled.ArrowDropDown` on all nine chips — its own docstring says so
(`jetpacs-m3-chips.el:93-94`, "the per-chip trailing ArrowDropDown is dropped
rather than moved to the leading slot"). Verified upstream at
`ChipSamples.kt:318-323`: that trailing icon sits on **AssistChip**, on `:322`,
which is why `assist_chip.trailing_icon` — and not only `chip.trailing_icon` —
is in scope for this amendment.

**Authoring caveat carried from G-17**, for whoever writes
`FilterChipWithCustomSpacingSample`: upstream's `leadingIcon` is `null` while
unselected (`ChipSamples.kt:214-234`, the `if (selected) … else null` at
`:220-231`), so a faithful build must also author `:selected t :icon "done"` or
the 4 dp gap at `:232` has nothing to space and the new member renders invisibly.

### Design decisions required

**D1 — `input` as a `chip.variant` value, or a new `input_chip` node type?**

| | A (recommended; the draft is written as A) | B |
|---|---|---|
| shape | `chip.variant` gains `input`; `InputChip` renders from the existing `chip` node | a new `input_chip` node type |
| cost | one enum value; zero new node types | `node_types` + `core_node_set` review, `NodeSupport.kt` profile lists, a `Renderer.kt` dispatch arm, a `node_schema` row, a coverage-floor golden line, an elisp builder, and both generated mirrors |
| grounds | `InputChip`'s parameter list is `selected, onClick, label, enabled` — the `chip` node's exact member set. A node type buys nothing the enum does not, and §12 reserves node-type growth for genuinely new vocabulary, which this is not | the catalog's own reason string calls InputChip "neither of them", and a ratifier may want wire node types to track Material components 1:1 |

**Recommendation: A.** B sets a precedent that costs one node type per Material
variant across the whole ledger — G-01, G-02, G-05, G-10, G-14 and G-21 all have
this exact shape. A D1 hold also moves `InputChipSample` and
`InputChipWithAvatarSample` out of this amendment, dropping its unblocks from 8
to 6.

**D2 — how is `chip.avatar` typed?**

| | A (recommended; drafted) | B |
|---|---|---|
| shape | an identifier, resolved through `IconMap` like every other icon field | the §17.2 image form (a `url`, or the §17.2 image-data encoding) |
| grounds | upstream's own sample draws `Icon(Icons.Filled.Person, …, Modifier.size(InputChipDefaults.AvatarSize))` (`ChipSamples.kt:256-262`) — an icon, not a photograph. `IconMap.get()` is the only path by which a drawable reaches the device without a network fetch, so a NAME is the right shape and needs no new plumbing | a real avatar is usually a picture, which an identifier can never express; a later widening from identifier to "identifier or image" is additive for the contract but forces a second elisp parameter |

**Recommendation: A**, with the note that B stays available as a later widening —
the member is named `avatar` rather than `avatar_icon` precisely so a future
amendment can widen the type without renaming the member.

**D3 — a member whose selected variant has no slot: reject, or ignore?**

| | A (recommended; drafted) | B |
|---|---|---|
| behaviour | `1201 content-invalid` for `avatar` without `variant:"input"`, for `avatar` alongside `icon`, and for `assist_chip.trailing_icon` under a suggestion variant | ignore the member and render the chip |
| grounds | §16.1:2105-2112 already rejects "an optional member present with a value outside its declared type or domain" and forbids silently dropping it, and §17.4 already rejects an analogous combination (`clear_on_submit: true` is invalid when `on_submit` is a builtin). Silence here is the exact failure genre the source audit exists to end: a member on the wire that renders nothing and reports nothing — and for `icon`+`avatar` the drop is not hypothetical, it is what `leadingContent()` does | a whole surface revision rejected over a cosmetic authoring mistake is a heavy penalty, and §16.3's "MUST ignore an unknown optional node field" reads to some as the governing posture |

**Recommendation: A.** §16.3 governs fields the receiver does not *know*; these
are fields it knows and cannot honour, which is §16.1's territory. The blast
radius is bounded and mechanically checkable: these three conditions are the only
new rejections in the amendment, and all three are caught by `validate.py` and
`SpecValidator` before a frame is ever sent.

**D4 — `trailing_icon` is typed GLOBALLY. Settle the name now or at G-40?**

| | A (recommended; drafted) | B |
|---|---|---|
| shape | `field_types.trailing_icon = "identifier"`, and §17.1 says so | rename this amendment's member (e.g. `trail_icon`) to leave `trailing_icon` free |
| grounds | `field_types` is a flat bare-name map with no node scoping; a rule that is global in the artifact should be global in the SPEC. `trailing_icon` is the Compose parameter name on `FilterChip`, `InputChip` and `AssistChip` alike, and G-24 (`text_input.trailing_icon`) wants an identifier too | G-40 wants MenuItem `trailing_icon` to carry the shipped MenuSample's `"F11"` shortcut, i.e. string-or-identifier. If G-40 ratifies as the ledger drafts it, this entry must widen to `string-or-number`/`string-or-identifier`, and every chip loses the free `IDENTIFIER` + `MAX_IDENTIFIER_OCTETS` check |

**Recommendation: A**, but this is a genuine fork and it belongs in this batch,
not at G-40. §17.1's "Unless a row states a narrower rule" leaves the SPEC room
for a per-node override; `field_types` does not, so whichever way this goes, one
of the two amendments has to bend.

### Concerns

- **No render assertions exist to protect any of this.** The audit's bounding
  caveat applies at full force: the Companion has no `ui-test-junit4`, no
  `androidTest` source set, and the four `render/` unit tests assert on data.
  Five new members land with the same exposure that let `hint`, `align_self` and
  `badge ""` render nothing while every gate passed. The two enum domains are
  deliberately unenforced (SPEC 12 rule 6 gives both a fallback, not a
  rejection), so `variant: "elevted"` silently renders a flat chip and no tool
  anywhere will say so. `contract.json`'s `enums` block does not change this: it
  is read by nothing.
- **`field_types` cannot express node scoping, so this amendment claims three
  names globally and says so.** That is why edits 1 and 2 touch §17.1. The
  consequence: G-40's MenuItem `trailing_icon` and G-24's
  `text_input.leading_icon`/`trailing_icon` inherit `identifier` unless one of
  them renames or widens — see D4. There is no version of this amendment that
  leaves those gaps untouched; revision 1's claim that it "keeps the blast radius
  on this node family" was simply false.
- **The `non-negative-dp` projection is deliberately asymmetric.**
  `content_spacing` shares its §17.1 sentence with `size`, `spacing`,
  `run_spacing`, `content_padding`, `elevation` and `thickness`, all of which
  still project as `"dp"` and are still checked for finiteness only. Retyping
  those six would change rejection behaviour for members outside this node
  family and is a separate amendment's business; leaving `content_spacing` as
  `"dp"` would have made §17.1's new "MUST be rejected" sentence unenforced on
  arrival. The asymmetry is the lesser defect, but it IS a defect, and §17.1's
  own "MUST be projected together" is what makes it one.
- **Fidelity is member-faithful, not pixel-faithful.** `IconMap.get` resolves
  Outlined → AutoMirrored → Filled (`IconMap.kt:1-6`), so upstream's
  `Icons.Filled.ArrowDropDown` and `Icons.Filled.Person` render as the Outlined
  vectors on device. The unblocked samples will look slightly different from the
  catalog screenshots for a reason that has nothing to do with this amendment and
  is not fixable by any wire string.
- **`chip.variant: "input"` renders `InputChip`, whose Material idiom is a
  trailing DISMISS affordance that removes the chip.** The wire has no dismiss
  semantics: `trailing_icon` + `on_tap` is the closest expression, and the actual
  removal is Emacs's to implement in the next snapshot. A reader of the §17.4 row
  could reasonably expect `input` to bring dismissal with it; the drafted prose
  does not promise it, but does not disclaim it either.
- **The icon/avatar exclusivity rule is a wire rule, not a Material rule.**
  Compose accepts both and resolves the conflict by precedence. Rejecting is a
  choice under D3 — a Companion that instead followed Compose would render the
  avatar and drop the icon with no diagnostic, which is the outcome this
  amendment exists to prevent, but a ratifier who takes D3-B should note that
  this third rule falls with the other two.
- **`InputChipWithAvatarSample` and `InputChipSample` both depend on
  `chip.variant` accepting `input`**, so a D1 hold strikes 2 of the 8 unblocks
  from this amendment and moves them to a separate NEEDS_NODE amendment. The
  unblocks count is not severable from D1.

---

## #162 — tab presentation: the primary indicator, the icon-only tab, and the leading-icon tab

Covers ledger gaps **G-18** (`tabs.style`, score 3.0), **G-19** (`tab_item.label` relaxed
to optional, 2), **G-20** (`tab_item.icon_position` + `tab_item.badge`, 1) from
`docs/AUDIT-m3-blockers-2026-08-02.md:184-197`.

Drafted against `ebp/SPEC.md` §17.3/§17.6 and `ebp/contract.json` as of branch
`m3-fidelity`. Every contract/golden/validate.py line below was applied to a private
copy of `ebp/` and run: `OK: 40 frames, 76 widget lines, 7 hypertext nodes, 17 wire
fixtures x3 chunkings` — plus a negative run confirming the new validate.py arm
rejects a TabItem with neither `label` nor `icon` and one with an unknown key.
**Nothing in `ebp/` was edited.**

### SPEC-CHANGES row (ready to paste)

> | 162 | 2026-08-02 | §17.3, §17.6 (cross-ref §12 rule 6, §16.4, §17.1, §17.2; precedent #41; contract) | **Tab presentation: the primary indicator, the icon-only tab, and the leading-icon tab.** §17.3's `tabs` had one presentation and its `TabItem` had two members, so three of Material 3's stock tab pictures could not be asked for at all and a fourth was being drawn wrong under a green gate. (1) `tabs.style` — `secondary` (default) or `primary` — selects the indicator family. Today `scrollable` alone picks the row composable and every combination draws the full-width secondary indicator, so the content-width rounded primary indicator, the single thing that distinguishes a primary tab row from a secondary one, was unreachable from Emacs. The default is `secondary`, which is exactly what every existing snapshot renders today, so no traffic changes meaning; an unknown value falls back to `secondary` under §12 rule 6, following amendment #41's `dialog.style` precedent, and `style` is inert under `pager_only` because no strip is drawn. (2) `TabItem.label` becomes optional when `icon` is present, and an item with neither is invalid. Authoring `label: ""` was never a workaround and the amendment now says so normatively, because the defect is a schema fact rather than a value: an empty string still *occupies* the tab's text slot, and a tab with both slots occupied takes the two-line tab metrics with a blank second line instead of the single-row icon-only metrics — the member has to be absent, and no value can express absence. Because an icon-only tab carries no visible name, `TabItem` also gains `content_description` (a §17.1 string; absent by default, which is precisely the `null` the Companion passes into every tab icon today), and §17.3 states the receiver duty directly: where `content_description` is present it MUST be the tab's accessible name, and where it is absent the Companion MUST still derive one per §16.4. That duty has to be written here rather than inherited, because §16.4's MUST is on *nodes* and §17.2's icon rule is on the `icon` *node type*, and a TabItem is neither — so relaxing `label` without this sentence would have created the one shape in §17 that legitimately carries no accessible name. (3) `TabItem.icon_position` — `above` (default) or `leading` — selects the leading-icon tab, whose icon sits beside the label rather than over it; it has no effect unless the item carries both `label` and `icon`, and an unknown value falls back to `above`. (4) `TabItem.badge` is the §17.6 badge member, already string-or-number and already spelled on `icon` and `icon_button`, decorating the tab's `label` or, when there is no label, its `icon`. §17.6 additionally records that, **on a `TabItem`**, presence with an empty string is a *presence*: an omitted `badge` means no badge, while `badge: ""` asks for a badge with no content and MAY render as a bare attention dot, exactly as an empty `badge` node label does in §17.2. That sentence is scoped to `TabItem` on purpose — `badge` on an `icon` or a navigation control keeps its existing meaning, and repairing those two readers is a separate amendment, because it would change what a currently-valid document renders. **§25 classification:** `tabs.style`, `tab_item.content_description`, `tab_item.icon_position`, and `tab_item.badge` are new OPTIONAL non-constraining fields with declared safe fallbacks, and each default reproduces today's rendering byte for byte — §25's second bullet, no protocol-major increment. The `label` change is a relaxation, and relaxing a MUST-present member cannot invalidate a previously valid core message. No existing field is reinterpreted, no required observable behavior changes, and no security boundary moves. This also repairs a shipped `:build`: `m3-catalog` `tabs/TextAndIconTabs` recreates an upstream sample built on the primary tab row, and with no `style` member the Companion has been drawing it with the secondary indicator — green in the gate, wrong on the glass. | contract `node_schema.tabs.optional` += `style`; `enums` += `tabs.style`, `tab_item.icon_position` (documentation-grade — nothing in the toolchain reads `enums`; no `field_types` change, since `label`/`icon`/`content_description`/`badge` already carry the right global types and enum members are conventionally absent); goldens/widgets.golden += 1 appended line (append only: the byte-parity ERTs index golden lines by number); validate.py `check_tab_items` arm (TabItem is not a node, so the generic walk applies no schema to it) | |

### SPEC.md edits

**1. §17.3, layout-node table — replace the `tabs` row (SPEC.md:2345).**

Current text, verbatim:

> | `tabs` | `items: TabItem[]`, `children: Node[]` | `initial`, `scrollable`, `pager_only`, `on_change`, `id`. Arrays MUST have equal non-zero length. |

Replacement:

> | `tabs` | `items: TabItem[]`, `children: Node[]` | `initial`, `scrollable`, `pager_only`, `on_change`, `id`, `style`. `style` is `secondary` (default) or `primary`; unknown values fall back to `secondary`. `style` has no effect when `pager_only` is true, because no strip is drawn. Arrays MUST have equal non-zero length. |

**2. §17.3, the TabItem paragraph — replace SPEC.md:2370-2376 in full.**

Current text, verbatim:

> A `TabItem` MUST contain `label: string` and MAY contain `icon`. `initial` is a
> zero-based index and defaults to `0`. The Companion MUST preserve the selected
> index across snapshots with the same Section 16.1 presentation identity; a new
> identity resets to `initial`. If a later same-identity snapshot has fewer items
> and the retained index is no longer valid, the Companion MUST select that
> snapshot's valid `initial` without emitting `on_change`.
> `on_change` receives the settled zero-based index as `args.value`.

Replacement (two paragraphs where there was one; the `initial` sentences are
unchanged and merely start a new paragraph):

> A `TabItem` MUST contain at least one of `label` and `icon` and MAY contain
> both; an item with neither is invalid. It MAY also contain
> `content_description`, `icon_position`, and `badge`. An item with no `label` is
> an icon-only tab, and the Companion MUST leave that tab's text slot empty
> rather than render an empty string: an empty string occupies the slot, so a
> Companion that substitutes one lays the tab out as a two-line tab with a blank
> line instead of the single-row icon-only tab. Authoring `label: ""` is
> therefore not a way to request an icon-only tab. An icon-only tab has no
> visible name, so `content_description` SHOULD be present on it, and where
> present it MUST be the tab's accessible name. When it is absent the Companion
> MUST still expose an accessible name for the tab, derived per Section 16.4.
> `icon_position` is `above` (default) or `leading`; unknown values fall back to
> `above`, and the member has no effect on an item that does not carry both
> `label` and `icon`. `badge` follows Section 17.6 and decorates the item's
> `label`, or its `icon` when the item has no `label`.
>
> `initial` is a zero-based index and defaults to `0`. The Companion MUST
> preserve the selected index across snapshots with the same Section 16.1
> presentation identity; a new identity resets to `initial`. If a later
> same-identity snapshot has fewer items and the retained index is no longer
> valid, the Companion MUST select that snapshot's valid `initial` without
> emitting `on_change`.
> `on_change` receives the settled zero-based index as `args.value`.

The accessible-name sentence is not redundant with §16.4. §16.4 (SPEC.md:2157-2159)
puts the derivation MUST on **nodes**, and §17.2's "an icon MUST NOT be the sole
carrier of load-bearing meaning without `content_description`" (SPEC.md:2246) is a
rule of the **`icon` node type**. A TabItem is neither — it carries no `t`, which is
also why `SpecValidator.walkNode` never reaches it (SpecValidator.kt:454) and why
`CompanionEngine`'s node walk skips it (CompanionEngine.kt:925-929). Without this
sentence, relaxing `label` would create the one shape in §17 that legitimately
carries no accessible name.

*(SPEC.md:2378-2381 — "For `tabs`, `id` is an identifier; `scrollable` and
`pager_only` are booleans; and `initial` MUST be less than the common non-zero
item count…" — is deliberately left untouched: `style`'s vocabulary and fallback
are stated in the table row, and §17.1 already types `label`, `icon`, and
`content_description`.)*

**3. §17.6 — replace the `badge` paragraph (SPEC.md:2602-2604).**

Current text, verbatim:

> The `badge` member MAY appear on an icon or navigation control as either a
> string or number. A number above the platform's visual limit MAY display as
> `99+`, but accessibility output SHOULD retain the exact authored value.

Replacement:

> The `badge` member MAY appear on an icon, on a navigation control, or on a
> `TabItem` (Section 17.3), as either a string or number. A number above the
> platform's visual limit MAY display as `99+`, but accessibility output SHOULD
> retain the exact authored value. On a `TabItem`, presence with an empty string
> is a presence and not an absence: an omitted `badge` means no badge, while
> `badge: ""` requests a badge with no content and MAY render as a bare
> attention dot, exactly as an empty `badge` node label does in Section 17.2.
> This distinction is stated for `TabItem` only; `badge` on an `icon` or a
> navigation control keeps its existing meaning.

The scoping is load-bearing, not stylistic. `ContentNodes.kt:258-259` and
`InputNodes.kt:100,110` both read the member as `stringOr("badge")` and test
`isNotEmpty()`, so today `{"t":"icon","name":"x","badge":""}` renders nothing and
`{"t":"icon","name":"x","badge":3}` renders nothing — both are valid, accepted
documents. An unscoped sentence would reinterpret an existing field on two shipped
node types, which §25 (SPEC.md:4430-4432) makes a protocol-major change. Repairing
those two readers is worth doing and is **not** done here; see "Deliberately not
migrated" below.

### Artifact changes

**contract.json — `node_schema.tabs`** (contract.json:272-284). Append `"style"`
**last** in `optional`; `tools/gen-vocabulary.py` emits this array in order into
`Vocabulary.kt:47`, while `tools/gen-jetpacs-vocabulary.py` sorts it, and `style`
sorts last either way:

```json
    "tabs": {
      "required": [
        "items",
        "children"
      ],
      "optional": [
        "initial",
        "scrollable",
        "pager_only",
        "on_change",
        "id",
        "style"
      ]
    },
```

**contract.json — `enums`.** Insert both keys immediately after `"surface.shape"`
(contract.json:672-676), which is where §17.3's other enums live. Default value
first, matching `text.style` (`body`), `dialog.style` (`dialog`), and
`button.variant` (`filled`):

```json
    "tabs.style": [
      "secondary",
      "primary"
    ],
    "tab_item.icon_position": [
      "above",
      "leading"
    ],
```

`tab_item.*` as an `enums` key with no `node_schema` row is the existing
`dialog.style` shape (§18.1 dialogs are not node types either). Nothing in the
toolchain reads `enums` — `grep -n enums tools/gen-vocabulary.py
tools/gen-jetpacs-vocabulary.py ebp/validate.py` returns nothing, and `Vocabulary.kt`
stores only the type *name* `"enum"` — so these two keys are documentation for a human
reader and nothing else. **No validator enforces either value set**; both fallbacks
below are structural.

**contract.json — `field_types`: no change.** `label` → `string` (contract.json:511),
`content_description` → `string` (:515), `icon` → `identifier` (:522), and `badge` →
`string-or-number` (:599) already exist as global member names with exactly the
required types. Note `field_types` is a **flat bare-name map**: an entry types a name
for *every* node type, so it cannot express node scoping. `style` and `icon_position`
are enum-valued and enum members are conventionally absent from it (`text.style`,
`button.variant`, `image.content_scale`, `box.alignment`, `surface.shape` all have no
entry — confirmed, `field_types["style"]` and `field_types["icon_position"]` are both
absent today; `keyboard` is the lone exception). Adding them would also buy nothing:
`SpecValidator.checkScalarFieldType` (SpecValidator.kt:461-496) runs only for members
listed in a **node's own** schema row, and `icon_position` lives on a TabItem, which
is not a node.

**goldens/widgets.golden — append one line.** Today's corpus is 00–74
(`wc -l` = 75), so this is line **75**; if a sibling amendment lands first, renumber
only this new line — never an existing one, because `test/jetpacs-widgets-test.el`
indexes golden lines by string (`(chk "33" …)`) and `test/smoke-parity.el` replays
them all through a live session. Keys are sorted, as everywhere else in the file; the
line exercises `style` plus all four TabItem members, including an icon-only item, a
leading-icon item with a string badge, and a numeric badge:

```
75 {"children":[{"t":"text","text":"1"},{"t":"text","text":"2"},{"t":"text","text":"3"}],"id":"tabs2","items":[{"content_description":"Favorite","icon":"favorite"},{"badge":"999+","icon":"favorite","icon_position":"leading","label":"Tab 2"},{"badge":9,"label":"Tab 3"}],"style":"primary","t":"tabs"}
```

Existing line 33 is untouched and still exercises the pre-amendment shape, so the
default path keeps a golden of its own. No `frames.golden`, `hypertext.golden`, or
`goldens/wire/` change: no method, no error code, no framing.

**validate.py — one arm, RECOMMENDED (the delta is green without it).** `check_node`
walks `items` generically; TabItem objects carry no `t`, so **no per-item rule runs
today at all** and the new golden passes either way. That is exactly the hole worth
closing while the shape is being widened. Add above `def check_node(...)`:

```python
# SPEC 17.3: a TabItem is not a node (it carries no `t`), so the generic walk
# applies no schema to it. These are its members and its one presence rule;
# `icon_position` and `tabs.style` are deliberately not value-checked here —
# SPEC 12 rule 6 gives each a fallback, so an unknown value is legal traffic,
# not a defect, and contract.json's `enums` block is read by nothing.
TAB_ITEM_MEMBERS = {"label", "icon", "content_description",
                    "icon_position", "badge"}


def check_tab_items(node, path: str):
    items = node.get("items")
    if items is None:
        return  # the schema arm already reported the missing member
    if not isinstance(items, list):
        problem(f"{path}.items: tabs items must be an array")
        return
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            problem(f"{path}.items[{i}]: TabItem must be an object")
            continue
        for key in item:
            if key not in TAB_ITEM_MEMBERS:
                problem(f"{path}.items[{i}]: unknown key `{key}` on TabItem")
        if "label" not in item and "icon" not in item:
            problem(f"{path}.items[{i}]: TabItem needs `label` or `icon`")
```

and dispatch it beside the existing per-type arms (validate.py:291-294, the
`enum_list` and `slider` pair):

```python
            if t == "tabs":
                check_tab_items(value, path)
```

The `items is None` early return is not cosmetic: validate.py:281-283 already emits
`{path}: tabs missing required `items`` from the generic schema arm, so reporting it
again here would make one defect produce two lines. The shape mirrors
`check_slider_values` (validate.py:238-250), which returns silently on an absent
`values` but still calls `problem()` for a present-but-malformed one — which is why
the present-but-not-a-list branch is kept rather than collapsed into the return.

Verified: green with the arm and without it; and with a probe line
`{"items":[{"tooltip":"x"}],…}` it reports both
`unknown key \`tooltip\` on TabItem` and `TabItem needs \`label\` or \`icon\``.

**Generated mirrors (llm-poc-2, same change, not `ebp/`).** Re-run both generators in
the same commit — neither file is hand-edited and both are drift-tested:
- `tools/gen-vocabulary.py` → `companion/wire/.../Vocabulary.kt:47` becomes
  `"tabs" to NodeRow(setOf("items", "children"), setOf("initial", "scrollable", "pager_only", "on_change", "id", "style")),`
- `tools/gen-jetpacs-vocabulary.py` → `emacs/jetpacs-vocabulary.el:54` becomes
  `("tabs" ("children" "items") ("id" "initial" "on_change" "pager_only" "scrollable" "style"))`

`VocabularyDriftTest`, `SurfaceStoreTest` (which asserts exact equality between
`Vocabulary.kt` and `contract.json`), and `jetpacs-widgets/catalog-node-schema` all
re-read `contract.json` and fail on any disagreement, so a missed regeneration is
caught — but it is caught as a red build, not as a warning.

### Companion implementation

All line numbers verified against the files on `m3-fidelity`; `material3` is
`1.5.0-alpha16` (`companion/gradle/libs.versions.toml:14`, raised in `ed86191`) and
every API named below was confirmed present by `javap` on
`androidx.compose.material3/material3-android/1.5.0-alpha16/material3.aar`.

**API existence, confirmed (not assumed):**
- `TabRowKt`: `PrimaryTabRow`, `SecondaryTabRow`, `PrimaryScrollableTabRow`,
  `SecondaryScrollableTabRow`, and the legacy `TabRow`/`ScrollableTabRow` all exist.
  In `PrimaryTabRow(selectedTabIndex, modifier, containerColor, contentColor,
  indicator, divider, tabs)` and `PrimaryScrollableTabRow(…, minTabWidth, tabs)` the
  `tabs` content slot is **last**, so today's trailing-lambda call site shape is
  preserved verbatim. `PrimaryScrollableTabRow` has a second, older overload in the
  aar, but it is `@Deprecated(level = DeprecationLevel.HIDDEN)`, i.e. invisible at
  source level — the bare `PrimaryScrollableTabRow(selectedTabIndex = selected) { … }`
  call is unambiguous.
- Neither `PrimaryTabRow` nor `PrimaryScrollableTabRow` nor `LeadingIconTab` is
  annotated `@ExperimentalMaterial3ExpressiveApi` or `@ExperimentalMaterial3Api`, so
  **no `@OptIn` is required** by this amendment. (The upstream samples carry
  `@OptIn(ExperimentalMaterial3Api::class)` for `TooltipBox`, which is G-83's problem,
  not this one.)
- `TabKt`: `Tab(selected, onClick, modifier, enabled, text, icon, …)` — `text` and
  `icon` are both `@Composable (() -> Unit)? = null` slots (the current code already
  leaves the icon slot null at `LayoutNodes.kt:449`); and
  `LeadingIconTab(selected, onClick, text, icon, modifier, enabled, …)`, whose `text`
  and `icon` are **required non-null**, which is why `icon_position: "leading"` is
  defined to have no effect without both members.
- `BadgeKt`: `BadgedBox(badge, modifier, content)` and
  `Badge(modifier, containerColor, contentColor, content)`, where
  `content: @Composable (RowScope.() -> Unit)? = null` — the same pair `RenderIcon`
  already uses at `ContentNodes.kt:260`. `Badge()` with a null content selects
  `BadgeTokens.Size` rather than `LargeSize`, which is literally the bare attention
  dot §17.6 now names.

**Why `label: ""` is not a workaround (the G-19 defect, verified in the file).**
`NodeAccess.kt:30-31` is `stringOr(k, d = "") = stringOrNull(k) ?: d`, so an *absent*
label reads as `""`. `LayoutNodes.kt:446` then passes
`text = { Text(item.stringOr("label")) }` — a **non-null** slot in every case. Both
slots are therefore occupied for any item with an icon, and the two-line tab metrics
are selected with a blank line where the label should be. This is no longer an
inference: `Tab.kt`'s `TabBaselineLayout` reads

```kotlin
        val specHeight =
            if (textPlaceable != null && iconPlaceable != null) {
                    LargeTabHeight
                } else {
                    SmallTabHeight
                }
```

with `LargeTabHeight = 72.dp` and `SmallTabHeight = PrimaryNavigationTabTokens
.ContainerHeight` — selection is by **slot presence**, and nothing an author can put
in `label` changes it. Only absence does, which is why the fix is a schema relaxation
and why the renderer must switch from `stringOr` to `stringOrNull`.

**`LayoutNodes.kt:439-454` — the whole edit.** Everything above line 436 (the
`key(ctx.path)` presentation identity, `rememberPagerState`, the `initial` coercion at
line 405, the two `LaunchedEffect`s, the `on_change` settle reporting) and everything
below 455 (`HorizontalPager`) is untouched, including the `!node.boolOr("pager_only")`
gate at line 437 that makes `style` inert under `pager_only`:

```kotlin
                val tabs: @Composable () -> Unit = {
                    for (i in 0 until minOf(items.size, pageCount)) {
                        val item = items[i] as? JsonObject ?: continue
                        val icon = item.stringOr("icon")
                        // §17.3: an ABSENT label leaves the text slot empty.
                        // stringOr() folds absent to "" and Text("") still
                        // OCCUPIES the slot — hence stringOrNull here.
                        val label = item.stringOrNull("label")
                        val cd = item.stringOr("content_description")
                            .takeIf { it.isNotEmpty() }
                        // §16.4's chain, which §17.3 now imposes on a TabItem:
                        // content_description, then the textual label, then the
                        // icon identifier's name. With a label present the slot
                        // stays null and the label carries the name, so every
                        // labelled tab is byte-identical to LayoutNodes.kt:448.
                        val iconCd =
                            if (label != null) cd
                            else cd ?: icon.takeIf { it.isNotEmpty() }
                        val badge = item.badgeOrNull()
                        val iconSlot: (@Composable () -> Unit)? =
                            if (icon.isNotEmpty()) {
                                { Icon(IconMap.get(icon), contentDescription = iconCd) }
                            } else null
                        // §17.3: the badge decorates the label, or the icon
                        // when there is no label. §17.6: "" is a bare dot.
                        val decorate: @Composable (@Composable () -> Unit) -> Unit =
                            { inner ->
                                if (badge == null) inner()
                                else BadgedBox(badge = {
                                    if (badge.isEmpty()) Badge() else Badge { Text(badge) }
                                }) { inner() }
                            }
                        val textSlot: (@Composable () -> Unit)? =
                            label?.let { l -> { decorate { Text(l) } } }
                        val leading = item.stringOr("icon_position") == "leading" &&
                            textSlot != null && iconSlot != null
                        val onClick = { scope.launch { pagerState.animateScrollToPage(i) }; Unit }
                        if (leading)
                            LeadingIconTab(
                                selected = selected == i,
                                onClick = onClick,
                                text = textSlot!!,
                                icon = iconSlot!!)
                        else
                            Tab(
                                selected = selected == i,
                                onClick = onClick,
                                text = textSlot,
                                icon = if (textSlot == null) iconSlot?.let { s -> { decorate(s) } }
                                       else iconSlot)
                    }
                }
                val primary = node.stringOr("style") == "primary"
                if (node.boolOr("scrollable")) {
                    if (primary) PrimaryScrollableTabRow(selectedTabIndex = selected) { tabs() }
                    else ScrollableTabRow(selectedTabIndex = selected) { tabs() }
                } else {
                    if (primary) PrimaryTabRow(selectedTabIndex = selected) { tabs() }
                    else TabRow(selectedTabIndex = selected) { tabs() }
                }
```

Both fallbacks are structural, not lookups: anything other than the exact string
`"primary"` — an unknown enum value, a non-string, an absent member — yields
`primary == false` and the existing `TabRow`/`ScrollableTabRow` path, and anything
other than `"leading"` yields `leading == false`. That is §12 rule 6's required safe
fallback, it is why no `field_types` entry is needed, and it is the only enforcement
either enum gets — `contract.json`'s `enums` block is read by nothing.

The one shape neither slot can name is `{"icon": ""}`: `icon` is a string, so the
item satisfies the presence rule, but `icon.isNotEmpty()` is false and both slots go
null, producing an empty-but-tappable tab. That is the same degenerate outcome
`{"label": ""}` produces today and is not made worse here; `""` is not a §4.4
identifier, so authoring it is already a client defect.

**Deliberately not migrated (two things, for the same reason).**
1. The `secondary` branch keeps calling today's `TabRow`/`ScrollableTabRow` rather
   than `SecondaryTabRow`/`SecondaryScrollableTabRow`. They draw the same picture and
   the modern spelling is the better long-term one, but the amendment's hard guarantee
   is that the default renders exactly as it does today, and this repo has no Compose
   render-test harness to prove a swap is a no-op.
2. The two shipped badge readers stay exactly as they are. `ContentNodes.kt:258-259`
   and `InputNodes.kt:100,110` read `badge` with `stringOr` and test `isNotEmpty()`,
   which drops a **numeric** badge entirely (`strOrNull`, NodeAccess.kt:23-24, returns
   null for a non-string primitive, so `badge: 3` renders nothing even though
   `field_types.badge` has been `string-or-number` all along) and folds `badge: ""`
   into "no badge". Both are wrong. Fixing them changes what a currently-valid,
   currently-accepted document renders — `{"t":"icon","name":"x","badge":""}` would
   gain a dot and `{"t":"icon","name":"x","badge":3}` would gain a "3" — which §25
   classifies as reinterpreting an existing field. That needs its own numbered
   amendment with its own classification, and #162 must not smuggle it in. The
   in-repo blast radius is nil today (the only badge values in the corpus are `"3"` at
   widgets.golden:05 and `"2"` at :38, and `jetpacs-m3-core.el:266` authors
   `(and pinned "•")`, which is nil-dropped), which is exactly why it is cheap to do
   properly and separately.

Both are recorded as follow-ups, not as riders.

**New reader — `NodeAccess.kt`, beside `stringOr` (NodeAccess.kt:28-31):**

```kotlin
/** §17.6 badge on a TabItem: a string OR a number, and PRESENCE (even "") is
 * distinct from absence — `badge: ""` is a bare attention dot, not "no badge".
 * A number's JSON lexeme is the display text, so `999` renders "999", not
 * "999.0". Deliberately NOT wired into the `icon`/`icon_button` readers: doing
 * so reinterprets an existing field (SPEC 25) and needs its own amendment. */
internal fun JsonObject.badgeOrNull(): String? =
    (this["badge"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
```

No key parameter, by design: a general-purpose helper invites the migration this
amendment has just declined to make.

**Imports to add at `LayoutNodes.kt:51-63`** (the material3 block is alphabetized):
`androidx.compose.material3.Badge` and `BadgedBox` before `ElevatedCard`,
`LeadingIconTab` after `IconButton`, `PrimaryScrollableTabRow` and `PrimaryTabRow`
after `MaterialTheme`.

**Wire validator — `SpecValidator.kt:780-800`, `validateTabs`.** Replace the label
MUST at lines 792-793 with:

```kotlin
            val hasLabel = item.stringOrNull("label") != null
            val hasIcon = item.stringOrNull("icon") != null
            if ("label" in item && !hasLabel)
                throw ContentInvalid("$path.items[$i].label", "TabItem label must be a string")
            if (!hasLabel && !hasIcon)
                throw ContentInvalid("$path.items[$i]",
                    "TabItem needs a label or an icon")
```

and update the KDoc at `SpecValidator.kt:780-781`, which still asserts the removed
rule — current text `/** SPEC 17.3: tabs arrays pair 1:1 and are non-empty; TabItem
needs a label; initial indexes the common count. */` becomes `… TabItem needs a label
or an icon; …`.

**This block is a strict loosening, and that is checked rather than asserted.** Today
`validateTabs` (SpecValidator.kt:789-793) rejects exactly two things per item: a
non-object, and `stringOrNull("label") == null`. After the change: the non-object arm
is untouched; an item with a present-but-non-string `label` is still rejected by the
first arm; an item with an absent `label` is rejected only if `icon` is also not a
string. Every rejection after is a rejection before, so no previously accepted
document is now refused.

`icon_position`, `content_description`, `badge`, and `style` are **not** value-checked
on the wire. That is deliberate. `icon_position` and `style` have §12 rule 6
fallbacks, so an unknown value is legal traffic. `icon` and `content_description` and
`badge` are unchecked today — `{"t":"tabs","items":[{"label":"a","icon":5}],…}` passes
`validateTabs` and renders fine, because `LayoutNodes.kt:442`'s `stringOr("icon")`
folds the number to `""` and the icon slot goes null at :449, and because TabItems get
`walkValue` rather than `walkNode` (SpecValidator.kt:454) so `checkScalarFieldType`
never runs on them. Adding those checks here would make the Companion start refusing
snapshots it accepts today, which §25's first bullet makes a protocol-major change.
Tightening TabItem member types is a legitimate future amendment; it is not this one.
`WidgetsGoldenReplayTest` (`companion/wire/src/jvmTest/.../WidgetsGoldenReplayTest.kt:52-60`)
replays the whole corpus including the new line 75, which is the coverage that proves
the loosening did not break the accepted set.

**Emacs authoring — `emacs/jetpacs-widgets.el`:** `jetpacs-tab-item` (line 916) keeps
its positional `label` but must accept `nil` for it and gain the three new keys;
`jetpacs-tabs` (line 922) gains `:style`. Both helpers already exist:
`jetpacs--check-badge` (line 312, "a string or a number") and `jetpacs--check-enum`
(line 253).

```elisp
(cl-defun jetpacs-tab-item (label &key icon content-description icon-position badge)
  "A TabItem for `jetpacs-tabs' (SPEC §17.3).
LABEL may be nil when ICON is given -- an icon-only tab.  Passing \"\"
is NOT the same thing: an empty string still fills the tab's text slot."
  (when label (jetpacs--require-string label ":label"))
  (when icon (jetpacs--check-identifier icon ":icon"))
  (unless (or label icon)
    (error "jetpacs-tab-item: needs a label or an icon (SPEC 17.3)"))
  (when content-description
    (jetpacs--require-string content-description ":content-description"))
  (when icon-position
    (setq icon-position
          (jetpacs--check-enum icon-position '("above" "leading") ":icon-position")))
  (when badge (jetpacs--check-badge badge))
  (jetpacs--node nil :label label :icon icon
                 :content_description content-description
                 :icon_position icon-position :badge badge))
```

`jetpacs--node` (jetpacs-widgets.el:332-344) drops **only** nil values, so `:label
nil` disappears from the wire while `:badge ""` and `:badge 0` survive — which is
precisely the presence/absence mechanism §17.3 and §17.6 now depend on. `jetpacs-tabs`
takes `:style`, checked with `(jetpacs--check-enum style '("secondary" "primary")
":style")` and passed as `:style`.

Existing call sites — including the byte-parity vector at
`test/jetpacs-widgets-test.el:196-197` for golden line 33 — keep working unchanged.
The new golden line needs its own vector in the same `layout-goldens` deftest (the
file carries one `chk` per golden line):

```elisp
      (chk "75" (jetpacs-tabs
                 (list (jetpacs-tab-item nil :icon "favorite"
                                         :content-description "Favorite")
                       (jetpacs-tab-item "Tab 2" :icon "favorite"
                                         :icon-position "leading" :badge "999+")
                       (jetpacs-tab-item "Tab 3" :badge 9))
                 (list (jetpacs-text "1") (jetpacs-text "2") (jetpacs-text "3"))
                 :id "tabs2" :style "primary"))
```

### Unblocks

**Cleared outright (3)** — every remaining gap resolved by this amendment alone:

| example | gaps closed here |
|---|---|
| `tabs/PrimaryTextTabs` | G-18 (sole gap) — upstream is `PrimaryTabRow` wrapping text-only `Tab`s, `TabSamples.kt:89-107` |
| `tabs/ScrollingPrimaryTextTabs` | G-18 (sole gap) — `PrimaryScrollableTabRow` wrapping text-only `Tab`s, `TabSamples.kt:321-347` |
| `tabs/LeadingIconTabs` | G-18 + G-20 — upstream (`TabSamples.kt:287-316`) builds it as `LeadingIconTab` inside a `PrimaryTabRow` with `BadgedBox(badge = { Badge(modifier = Modifier) { Text("999+") } }) { Text(title) }` in the `text` slot, which is `style:"primary"` + `icon_position:"leading"` + `badge:"999+"` exactly, including the badge decorating the *label* rather than the icon |

**Also repairs a shipped `:build` (1).** `tabs/TextAndIconTabs` is green today and
renders the wrong picture: upstream's `TextAndIconTabs` uses `PrimaryTabRow`
(`TabSamples.kt:257-282`), while `jetpacs-m3-tabs--text-and-icon`
(`emacs/apps/m3-catalog/jetpacs-m3-tabs.el:86-95`) authors no `style` and the
Companion draws the secondary indicator. Adding `:style "primary"` to that builder
makes the recreation faithful. This is the same defect class as G-00's
`TextFieldWithPlaceholder`.

**Advanced but still blocked (2).** `tabs/PrimaryIconTabs` and `tabs/SecondaryIconTabs`
lose both of their current blockers here (icon-only tabs via G-19, and the primary
indicator via G-18 for the former), leaving exactly one: G-83's `tab_item.tooltip`
rider — upstream wraps each icon-only `Tab` in a `TooltipBox` with a `PlainTooltip`,
and its own source comment at `TabSamples.kt:118` says so outright: *"Icon-only tab
should have a tooltip associated with it."* (Ledger correction owed: the G-18 and G-19
unblocks lines at `AUDIT-m3-blockers-2026-08-02.md:188` and `:192` cite **G-32** as the
co-requisite, but G-32 is `slider.track` (AUDIT:234-235) and has nothing to do with
tabs. The intended reference is the `tab_item.tooltip` rider stated correctly under
G-83 at AUDIT:433. The ledger typo should be corrected so a ratifier diffing this
amendment against it does not see an unexplained mismatch.)

Worth noting for the eventual G-83 amendment: upstream's icon-only `Tab` passes
`contentDescription = "Favorite"` on the Icon *and* names the tab in the tooltip, which
is exactly the `content_description` member this amendment adds — so G-83's rider will
sit on top of #162's shape rather than duplicate it.

**Component arithmetic.** `tabs` goes from **3/12** built (`SecondaryTextTabs`,
`TextAndIconTabs`, `ScrollingSecondaryTextTabs`) to **6/12**. The 6 that remain are
the two icon-only samples (G-83 tooltip rider) and the four custom-indicator /
custom-content ones (`FancyTabs` → G-82 `tab_item.content`; `FancyIndicatorTabs`,
`FancyIndicatorContainerTabs`, `ScrollingFancyIndicatorContainerTabs` → G-81
`tabs.indicator`).

**Reason-string corrections owed** (product text a user reads, so each is a defect in
the audit's terms, not a comment nit) — all in
`emacs/apps/m3-catalog/jetpacs-m3-tabs.el`:

- `jetpacs-m3-tabs--primary-note` (lines 44-46, used at :121 by `PrimaryTextTabs` and
  at :153 by `ScrollingPrimaryTextTabs`) — becomes wholly false; delete with the
  constant, as both examples become `:build`.
- `PrimaryIconTabs`'s inline note (line 127): *"Neither half is on the wire: a
  tab_item always renders its label, so there is no icon-only tab, and no member
  selects PrimaryTabRow's indicator."* — **both** clauses become false; rewrite to
  name only the missing tooltip.
- `jetpacs-m3-tabs--icon-only-note` (lines 48-50, used at :137 by `SecondaryIconTabs`)
  — its first clause becomes false; keep only the `TooltipBox`/`PlainTooltip` half.
- `LeadingIconTabs`'s inline note (line 148) — becomes wholly false; the example
  becomes `:build`.
- The module commentary at line 29 (*"that pairing IS a tab_item"*) should note that
  a TabItem is now label-or-icon, and that `TextAndIconTabs` is no longer the only
  primary-row sample that recreates.

**Pre-existing, untouched, flagged for whoever reviews this:**
`CompanionEngine.kt:854-855` comments that `tabs.items` is *"deliberately absent"*
from `NODE_ARRAY_MEMBERS` while `"items"` is in fact in that set (:856). The walk is
still correct — it gates on `it.stringOrNull("t") != null` (:928) and TabItems carry
none — but anyone auditing the four new TabItem members against that walker will trip
on the stale comment.

### **Design decision required** — the shape of the icon-only tab

The ledger names two shapes for G-19 (`AUDIT-m3-blockers-2026-08-02.md:190-193`:
*"Either relax it when `icon` is present, or add `icon_only: boolean`"*). Both work;
they differ in where the accessible name lives and in how much of the stack moves.
**A is recommended and the draft above is written as A.**

| | **A — relax `label` to optional (recommended, drafted)** | **B — keep `label` a MUST, add `icon_only: boolean`** |
|---|---|---|
| Wire shape | `label` optional when `icon` present; item with neither is invalid; new `content_description` carries the accessible name | `label` stays REQUIRED; new `icon_only` (boolean, default `false`) suppresses the text slot; `label` is promoted to the tab's accessible name |
| New members | 3 (`content_description`, `icon_position`, `badge`) | 3 (`icon_only`, `icon_position`, `badge`) — same count, but no new string member |
| Default preserves today | yes (absent members) | yes (`false` is §17.1's default for an optional boolean) |
| Validator | `validateTabs` loosens (a loosening can invalidate nothing) | `validateTabs` unchanged; one boolean read added |
| Elisp constructor | `jetpacs-tab-item`'s positional `label` must accept `nil` | signature unchanged; one new key |
| Accessible name | needs an explicit §17.3 MUST (added above), because §16.4's duty is on nodes and a TabItem is not one | falls out of `label` with no new normative sentence |
| Honesty of the document | the schema says what is true: an icon-only tab has no label | an authored `label` is never displayed — a member whose value the renderer deliberately discards, which is the `align_self`/`hint` shape this repo has twice been burned by |

**Why A.** B's ergonomics are genuinely nicer — one boolean, no relaxation, and the
accessible name comes for free without the extra §17.3 sentence — but it
institutionalizes a declared-and-then-discarded member, which is precisely the defect
class the audit's own caveat is about (`hint` and `align_self` were declared,
validated, and read nowhere for months). A makes absence mean absence, which is the
only thing that produces the correct tab metrics given
`TabBaselineLayout`'s slot-presence height selection, and it introduces
`content_description` on the one node family that could previously not carry one.
If B is preferred, the §17.3 replacement paragraph becomes: `label` stays a MUST;
`icon_only` is a boolean defaulting to `false`, valid only with `icon`, which
suppresses the text slot and makes `label` the tab's accessible name — the explicit
§16.4 derivation sentence can then be dropped, `contract.json` gains no `enums` key
for it (booleans are not enums), and `field_types` is still untouched.
---

## #163 — the text field family (§17.4)

Drafted 2026-08-02 against `ebp/SPEC.md` @ `9b57b35` (amendments through **#152**).
Source: `docs/AUDIT-m3-blockers-2026-08-02.md` gaps **G-21 … G-26**. Anchors and
renderer claims re-verified against the files; the ledger's `Renderer.kt` line
numbers predate `1917fff` and run ~21 lines low, so the citations below are the
current ones.

**Revision note (r2).** The first draft defined `max_length` as a hard clamp on
committed text and claimed it cleared `TextFieldWithErrorState`. Both are wrong,
and the correction is load-bearing: upstream's error sample sets
`Modifier.semantics { maxTextLength = charLimit }` (`TextFieldSamples.kt:238`)
as an **announcement only** — the field permits typing past ten, which is how
the error it exists to show ever occurs. A clamp makes that sample unreachable
by construction. `max_length` is now the accessibility bound and nothing more,
the §13.6 edit that rode on the clamp is withdrawn, and the honest clear-count
is **five**, not six. `TextFieldWithErrorState` is **not** cleared by #163.

**⚠ Three design decisions required** (tables at the end): the shape of the
keyboard dismissal, whether an enforcement member ships with `max_length`, and
whether `is_error`/`max_length` ship at all given they clear nothing today.

### SPEC-CHANGES row (ready to paste)

> | 163 | 2026-08-02 | §17.4 (cross-ref §12 rule 6, §14.6, §16.4, §16.3, §17.2; contract) | **The text field family — eleven members that turn one hardcoded `OutlinedTextField` into Material 3's actual text field.** §17.4's `text_input` carried fifteen optional members and not one of them reached a single slot M3 hangs off a text field: `RenderTextInput` passes exactly ten arguments to `OutlinedTextField` — value, enabled, visualTransformation, onValueChange, label, placeholder, singleLine, keyboardOptions, keyboardActions, and the node's universal modifier (`Renderer.kt:431-463`) — so nothing an author writes can select the container, put an icon or an affix inside it, attach the helper line, colour the error state, announce a length bound, or lower the keyboard; `min_lines`/`max_lines` are validated at `SpecValidator.kt:561` and then never passed to `minLines`/`maxLines` at all. Eleven optional members close the slot gap, each defaulting to today's rendering so no existing traffic changes meaning. `variant` (enum `outlined` \| `filled`, default `outlined`, an unrecognized value falling back to `outlined` under §12 rule 6) selects the container: `outlined` is the only rendering that has ever shipped, `filled` is `androidx.compose.material3.TextField` — tonal container, no outline, a focus-thickening bottom indicator, the label riding inside rather than notching the border — which is a different widget and not reachable by painting the universal `bg` behind the existing one, since `Attributes.kt:160-161` paints *behind* the widget while the outline and the notched label cut-out stay. `supporting_text` (string) is the helper line M3 measures to the **field's own** width (`TextFieldImpl.kt:781` filled, `:1449` outlined) and tints with `colors.supportingTextColor(enabled, isError, isFocused)`, which is exactly why a sibling `text` node under the field is a different drawing rather than a workaround: a sibling wraps to the parent, and on a 411dp phone the field is ~280dp inside a 379dp body, so the helper prose overhangs the field it is helping. `is_error` (boolean, default `false`) puts the field in M3's error presentation — container, label, indicator, cursor — and, when `supporting_text` is present, the Companion MUST publish that string as the node's accessibility error description, because §16.4 makes accessible meaning part of rendering and a recolour with no announced reason is not an error state. `max_length` (positive integer, absent = no bound announced) is the field's advertised length bound in Unicode code points, exposed to the accessibility layer and **nothing else**: it does not truncate, revert or reject an edit, and it does not bar a longer authored `value` — Material's own error sample depends on the user being able to type past it — so §12 rule 2's constraining-member bar is not engaged and Emacs re-checks any length it actually relies on when the value arrives. `leading_icon` and `trailing_icon` (identifiers) fill M3's two decoration slots **inside** the container, where a `row` of sibling icons cannot go; `trailing_on_tap` — an ActionDescriptor typed by prose like `header_action` rather than by §17.1's `on_*` rule, because it belongs to the trailing icon and reads that way beside it, and added to the contract's `hook_keys` so both validators walk it as a descriptor instead of as a child node — makes that icon an activatable control, inert while `enabled: false`. `clearable` (boolean, default `false`) is the wire form of `state.clearText()`: a Companion-local affordance that empties the field and then behaves exactly as if the user had erased the text, which no ActionDescriptor can express because the draft lives in a `rememberSaveable` keyed `"ti:<surface>:<id>:<epoch>"` (`Renderer.kt:398-399`) that only an input-reset epoch bump moves; it is permitted on a `password` node, unlike `clear_on_submit`. Because `clearable` and `trailing_icon` both claim the trailing slot, authoring both is `1201 content-invalid`, as is `trailing_on_tap` without `trailing_icon`. `prefix` and `suffix` (strings) are the affixes M3 draws inside the container around the editable text; they are presentation only and MUST NOT appear in `value`, in a `state.changed` value, in a captured field, or in a welcome `input_state` entry. `hide_keyboard_on_submit` (boolean, default `false`) raises the platform's submit action — whether or not `on_submit` is present — and dismisses the software input method once it fires: today `KeyboardActions(onDone = { submit() })` (`Renderer.kt:461-462`) installs a handler that never calls `defaultKeyboardAction()`, which *suppresses* Compose's own hide-on-Done, so the keyboard stays up after every submit, and `imeAction` is `Done` only when `on_submit` is present (`:459`), so a field whose whole purpose is a Done key that lowers the keyboard cannot have one; the member restores both on request rather than changing either for everyone, and unlike `clear_on_submit` the dismissal does not wait on §14.4 admission, because the IME is a local affordance and an offline `queue` submission must still lower it. Additive throughout: eleven optional members, one enum, one hook key, nine `field_types` entries; every default is the pre-existing rendering, no existing golden, fixture or message changes meaning, and a receiver that does not know a member ignores it under §16.3 and renders exactly what it renders today. | contract: `node_schema.text_input.optional` += 11 members, `enums."text_input.variant"`, `field_types` += 9 entries, `actions.hook_keys` += `trailing_on_tap`; goldens/widgets.golden += 2 lines; validate.py gains `check_text_input_slots`; `Vocabulary.kt` and `jetpacs-vocabulary.el` regenerated from the contract | |

### SPEC.md edits

**1. §17.4, the `text_input` table row (SPEC.md:2417).** Replace:

> | `text_input` | `id: identifier` | `value`, `hint`, `label`, `on_change`, `on_submit`, `single_line`, `min_lines`, `max_lines`, `monospace`, `syntax`, `password`, `keyboard`, `autofocus`, `clear_on_submit`, `enabled` |

with:

> | `text_input` | `id: identifier` | `value`, `hint`, `label`, `on_change`, `on_submit`, `single_line`, `min_lines`, `max_lines`, `monospace`, `syntax`, `password`, `keyboard`, `autofocus`, `clear_on_submit`, `variant`, `is_error`, `supporting_text`, `max_length`, `leading_icon`, `trailing_icon`, `trailing_on_tap`, `clearable`, `prefix`, `suffix`, `hide_keyboard_on_submit`, `enabled` |

**2. §17.4, the member-type paragraph (SPEC.md:2431-2435).** Replace:

> For input nodes, every listed `on_*` member is an ActionDescriptor. `value`,
> `hint`, and `label` on `text_input` and `editor.value` are strings;
> `single_line`, `monospace`, `password`, `autofocus`, `clear_on_submit`,
> `read_only`, `line_numbers`, `complete`, `chromeless`, and `publish_state` are
> booleans. `document` is an identifier.

with:

> For input nodes, every listed `on_*` member is an ActionDescriptor. `value`,
> `hint`, `label`, `supporting_text`, `prefix`, and `suffix` on `text_input` and
> `editor.value` are strings; `single_line`, `monospace`, `password`,
> `autofocus`, `clear_on_submit`, `is_error`, `clearable`,
> `hide_keyboard_on_submit`, `read_only`, `line_numbers`, `complete`,
> `chromeless`, and `publish_state` are booleans. `document`, `leading_icon`,
> and `trailing_icon` are identifiers, and an icon identifier names an icon
> exactly as `icon.name` does. `trailing_on_tap`, when present, is an
> ActionDescriptor. `max_length` MUST be a positive integer.

(The replaced span ends mid-sentence at "`document` is an identifier."; the rest
of that paragraph — "Checkbox and switch `checked` values are booleans. …" —
is untouched and follows the replacement unchanged.)

**3. §17.4, the defaults paragraph (SPEC.md:2442-2448).** Replace:

> `text_input.value` and `editor.value` default to the empty string.
> `single_line`, `monospace`, `password`, `autofocus`, `clear_on_submit`,
> `line_numbers`, `complete`, `chromeless`, `publish_state`, and `read_only`
> default to `false`. `min_lines` and `max_lines` MUST be positive integers, and
> `min_lines` MUST NOT exceed `max_lines`. `min_lines` defaults to `1`;
> `max_lines` defaults to `1` when `single_line` is true and otherwise defaults to
> `min_lines`. `single_line: true` requires both line counts to equal `1`.

with:

> `text_input.value` and `editor.value` default to the empty string.
> `single_line`, `monospace`, `password`, `autofocus`, `clear_on_submit`,
> `is_error`, `clearable`, `hide_keyboard_on_submit`, `line_numbers`,
> `complete`, `chromeless`, `publish_state`, and `read_only`
> default to `false`. `min_lines` and `max_lines` MUST be positive integers, and
> `min_lines` MUST NOT exceed `max_lines`. `min_lines` defaults to `1`;
> `max_lines` defaults to `1` when `single_line` is true and otherwise defaults to
> `min_lines`. `single_line: true` requires both line counts to equal `1`.
> `variant` defaults to `outlined`; an omitted `supporting_text`, `prefix`,
> `suffix`, `leading_icon`, `trailing_icon`, or `trailing_on_tap` renders
> nothing in the corresponding slot, and an omitted `max_length` announces no
> bound. Each of these defaults is the rendering this section described before
> the member existed, so a `text_input` that omits them all renders exactly as
> it did.

**4. §17.4, new prose after the password paragraph.** After:

> Password
> handling MUST obey Section 14.6, and `max_field_bytes` applies while the value
> is held in volatile memory.

insert (before the paragraph beginning "`autofocus: true` MAY acquire focus"):

> `variant` is `outlined` (default) or `filled`; an unrecognized value falls
> back to `outlined`. `outlined` is the container every previous revision of
> this section described. `filled` selects the platform's filled container: a
> tonal fill with no outline, a bottom indicator line that thickens and
> recolours on focus, and the label carried inside the container rather than
> notching its border. The two differ only in presentation; every other member
> of the node means the same thing under both.
>
> `supporting_text` is a helper line the Companion draws as part of the field,
> not beside it: it MUST be measured to the field's own width and MUST take its
> colour from the field's enabled, focused, and error state. A sender MUST NOT
> expect an equivalent drawing from a separate sibling node. `is_error: true`
> puts the field in the platform's error presentation — container, label,
> indicator, and cursor — and, when `supporting_text` is also present, the
> Companion MUST expose that string as the node's accessibility error
> description. Because Section 16.4 makes accessible meaning part of rendering,
> and an error presentation with no announced reason carries none, a sender
> SHOULD supply `supporting_text` whenever it sets `is_error`.
>
> `max_length` is the field's advertised length bound, counted in Unicode code
> points. The Companion MUST expose it to the platform's accessibility layer as
> the field's maximum text length. It is an announcement and not an
> enforcement: the Companion MUST NOT truncate, revert, or refuse an edit that
> carries the value past the bound, MUST NOT reject an authored `value` longer
> than it, and MUST NOT treat a retained draft longer than it as incompatible
> under Section 13.6. A field that announces a bound and then permits the value
> to exceed it is the intended arrangement — it is what lets a sender colour an
> over-long value as an error. `max_length` is correspondingly not a validation
> boundary: Emacs MUST NOT treat it as one and MUST re-check any length
> constraint it relies on when the value arrives.
>
> `leading_icon` and `trailing_icon` name icons the Companion draws inside the
> field's container, at its leading and trailing edges, tinted with the field's
> own content colour and following its enabled and error state; an unresolved
> name behaves as Section 17.2 requires of `icon`. `trailing_on_tap` makes
> `trailing_icon` an activatable control; it MUST NOT be dispatched while the
> node is not `enabled`, and a `trailing_on_tap` without `trailing_icon` is
> invalid content and MUST be rejected with `1201 content-invalid`. `prefix`
> and `suffix` are drawn inside the container immediately before and after the
> editable text. They are presentation only: the user cannot edit them, and
> they MUST NOT appear in `value`, in a `state.changed` value, in a captured
> field, or in a welcome `input_state` entry.
>
> `clearable: true` places the platform's clear affordance in the field's
> trailing slot. Activating it empties the node's value locally, and the
> Companion MUST then behave exactly as if the user had erased the text —
> including Section 14.6's rules when the node is a `password` — and MUST NOT
> dispatch a remote action of its own. `clearable` is permitted on a `password`
> node: erasure by the user is exactly what Section 14.6 already contemplates,
> unlike `clear_on_submit`, which that section's unconditional erasure makes
> redundant. Because it occupies the trailing slot, `clearable: true` together
> with `trailing_icon` is invalid content and MUST be rejected with `1201
> content-invalid`.
>
> `hide_keyboard_on_submit: true` dismisses the software input method once the
> platform's submit action fires, without moving focus. The Companion MUST
> raise the platform's submit action for a node that sets it, whether or not
> `on_submit` is present; where `on_submit` is present it is dispatched first
> and the dismissal follows. Unlike `clear_on_submit`, the dismissal does not
> wait on Section 14.4 admission: the input method is a local affordance, and
> an offline `queue` submission MUST still lower it.

**No §13.6 edit.** The first draft amended §13.6's `text_input`
draft-compatibility bullet so a retained draft longer than a new node's
`max_length` became incompatible. That rode entirely on the withdrawn clamp;
with `max_length` announcement-only, a longer draft is legal and the bullet
stays exactly as it is. §13.6 is not touched by this amendment.

### Artifact changes

All four sub-changes below were applied to a scratch copy of `ebp/` and
`python3 validate.py` passes: `OK: 40 frames, 77 widget lines, 7 hypertext
nodes, 17 wire fixtures x3 chunkings validate (spec 2.0.0-draft, format 6);
SPEC §8/§11 in sync; 9.3 KAT reproduced`.

**contract.json** — four surgical insertions, no reformatting (line-level
insertion, verified by re-parsing the result):

1. `node_schema.text_input.optional` (contract.json:376) — insert **before**
   `"enabled"`: `"variant", "is_error", "supporting_text", "max_length",
   "leading_icon", "trailing_icon", "trailing_on_tap", "clearable", "prefix",
   "suffix", "hide_keyboard_on_submit"`.
2. `enums` (after the `"text_input.keyboard"` array, contract.json:701-708):
   `"text_input.variant": ["outlined", "filled"]`.
3. `field_types` — nine entries, placed in their existing type groups:
   after `"snackbar"` (:530): `"supporting_text": "string"`, `"prefix":
   "string"`, `"suffix": "string"`; after `"document"` (:537):
   `"leading_icon": "identifier"`, `"trailing_icon": "identifier"`; after
   `"clear_on_submit"` (:567): `"is_error": "boolean"`, `"clearable":
   "boolean"`, `"hide_keyboard_on_submit": "boolean"`; after `"max_lines"`
   (:590): `"max_length": "positive-integer"`.
   `variant` is deliberately **not** added: `field_types` is a flat bare-name
   map — adding a name types it globally for every node type — and `variant`
   already means different enums on `button` and `progress`, which is why it is
   absent today. `checkScalarFieldType` (`SpecValidator.kt:467-496`) falls
   through `"enum"` to `else -> Unit` anyway.
4. `actions.hook_keys` (contract.json:760) — append `"trailing_on_tap"`.
   Without this, `validate.py:296` and `SpecValidator.kt:394/429` would walk the
   descriptor as a child node and silently skip every action check on it.

**A caution about the `enums` entry.** Nothing reads `contract.json`'s `enums`
block: `validate.py` never mentions it, neither generator projects it, and
`Vocabulary.kt` stores only the type *name* `"enum"` for a field. The entry is
documentation. The only actual enforcement of `outlined|filled` is (a) the
Companion's §12 rule 6 fallback to `outlined` on an unrecognized value and (b)
the build-time `jetpacs--check-enum` in elisp added below. Do not read the
contract entry as a validated value set.

**goldens/widgets.golden** — two appended lines (nothing existing is touched;
the prefix-`43` maximal `text_input` at file line 44 stays exactly as it is).
The file is 0-indexed with a two-digit prefix and currently runs `00`…`74`:

```
75 {"hint":"google","id":"site","is_error":true,"label":"Site","leading_icon":"favorite","max_length":10,"prefix":"www.","single_line":true,"suffix":".com","supporting_text":"Text input too long","t":"text_input","trailing_icon":"clear","trailing_on_tap":{"action":"site.clear"},"value":"example.com","variant":"filled"}
76 {"clearable":true,"hide_keyboard_on_submit":true,"id":"query","label":"Search","single_line":true,"t":"text_input","variant":"outlined"}
```

Line 75 is the filled container with every non-exclusive slot occupied, and its
11-code-point `"value"` deliberately **exceeds** its own `max_length: 10`
beside `"is_error": true` — that is the announcement-only reading made
executable, and the shape upstream's error sample actually produces. Line 76 is
the clearable/keyboard pair, which cannot share a line with 75 because
`clearable` and `trailing_icon` are mutually exclusive; it carries no
`on_submit`, exercising `hide_keyboard_on_submit` standing alone.

**validate.py** — yes, an arm is needed: the trailing-slot rules are not
expressible in `node_schema`, and `validate.py` does not read `field_types` at
all (grep: zero occurrences), so the positive-integer check for `max_length`
has to live here too. Insert `check_text_input_slots` immediately before
`check_node`, and route `text_input` through it:

```python
def check_text_input_slots(node, path: str):
    """SPEC 17.4 (#163): one occupant of the trailing slot, a trailing action
    only where there is a trailing icon, and a positive-integer max_length
    (validate.py does not read contract field_types, so the type is checked
    here; SpecValidator gets it free from FIELD_TYPES)."""
    if node.get("clearable") and "trailing_icon" in node:
        problem(f"{path}: clearable and trailing_icon both claim the trailing "
                f"slot (SPEC 17.4)")
    if "trailing_on_tap" in node and "trailing_icon" not in node:
        problem(f"{path}: trailing_on_tap without trailing_icon (SPEC 17.4)")
    n = node.get("max_length")
    if n is None:
        return
    if isinstance(n, bool) or not isinstance(n, int) or n < 1:
        problem(f"{path}.max_length: must be a positive integer (SPEC 17.4)")
```

and in `check_node`, replace (validate.py:288-290)

```python
            if t == "text_input" and value.get("single_line") \
                    and "\n" in value.get("value", ""):
                problem(f"{path}: single_line value contains U+000A (SPEC 17.4)")
```

with

```python
            if t == "text_input":
                if value.get("single_line") \
                        and "\n" in value.get("value", ""):
                    problem(f"{path}: single_line value contains U+000A "
                            f"(SPEC 17.4)")
                check_text_input_slots(value, path)
```

There is **no** authored-value length check, in either validator: an authored
`value` longer than `max_length` is legal content under the announcement-only
reading. That is also what removes the code-point/UTF-16 hazard the first draft
carried — Python `len(str)` counts code points and Kotlin `String.length`
counts UTF-16 units, so a six-emoji value under `max_length: 8` would have
passed `validate.py` and been rejected `1201` by the Companion on a MUST-reject
rule. With the rule gone there is nothing to disagree about; the surviving
scalar check is integral-by-value in both.

Verified negatively against the scratch copy: four deliberately malformed
golden lines each raise exactly one problem and the run fails —

```
widgets:77: clearable and trailing_icon both claim the trailing slot (SPEC 17.4)
widgets:77: trailing_on_tap without trailing_icon (SPEC 17.4)
widgets:77.max_length: must be a positive integer (SPEC 17.4)   # max_length: 0
widgets:77.max_length: must be a positive integer (SPEC 17.4)   # max_length: true
```

**Generated mirrors** — re-run `python3 tools/gen-vocabulary.py` and
`python3 tools/gen-jetpacs-vocabulary.py` **in the same commit**; both mirrors
are drift-tested. The eleven members (`trailing_on_tap` among them, since it is
an `optional` entry) land in `Vocabulary.kt`'s `NODE_SCHEMA` and in
`jetpacs-vocabulary.el`'s `jetpacs-node-schema`; the nine `field_types` entries
land in `Vocabulary.kt`'s `FIELD_TYPES`; `trailing_on_tap` also lands in
`Vocabulary.kt`'s `ACTION_HOOK_KEYS`. `VocabularyDriftTest`
(`SurfaceStoreTest.kt:727-755`) fails until `Vocabulary.kt` is regenerated —
note that it asserts `node_schema`, `universal_node_attributes`,
`actions.schema` keys and `field_types`, but **not** `hook_keys`, so the
`ACTION_HOOK_KEYS` half is not gate-caught on its own. `jetpacs-widgets/
catalog-node-schema` (`test/jetpacs-widgets-test.el:889-905`) fails until
`jetpacs-vocabulary.el` is regenerated; that file carries `node_schema` only.

Two hand-maintained Emacs spots are **not** generated and must be edited
alongside: `jetpacs-text-input` (`emacs/jetpacs-widgets.el:1044-1091`) is a
`cl-defun &key` constructor that never consults the generated schema, so it
needs the eleven keywords added to its lambda list, to its `jetpacs--node`
call, and to its guards — `jetpacs--require-string` for `supporting-text`/
`prefix`/`suffix`, `jetpacs--check-bool` for `is-error`/`clearable`/
`hide-keyboard-on-submit`, `jetpacs--check-identifier` for the two icons,
`jetpacs--check-integer` (min 1) for `max-length`, `jetpacs--check-descriptor`
for `trailing-on-tap`, plus the two exclusivity errors — and a
`(defconst jetpacs--text-input-variants '("outlined" "filled"))` beside
`jetpacs--keyboards` (`:986`) for the `jetpacs--check-enum` call.

### Companion implementation

All in `RenderTextInput`,
`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt:383-464`.
API existence checked against the resolved artifacts, not from memory:
`material3-android/1.5.0-alpha16/…/material3.aar` and
`ui-android/1.11.0-beta02/…/ui.aar` (compose-bom `2026.02.01`,
`companion/gradle/libs.versions.toml:4,14`). None of the eleven is
@ExperimentalMaterial3ExpressiveApi — no `@OptIn` is required.

- **`variant`** — `Renderer.kt:431` is the single unconditional
  `OutlinedTextField(`. Hoist the seven slot lambdas and the shared arguments
  into locals and branch:
  `if (variant == "filled") TextField(...) else OutlinedTextField(...)`.
  Both `String`-overloads exist on the classpath with identical parameter lists
  — `androidx/compose/material3/TextFieldKt.class` and
  `OutlinedTextFieldKt.class` each expose
  `(String, Function1, Modifier, boolean enabled, boolean readOnly, TextStyle,
  label, placeholder, leadingIcon, trailingIcon, prefix, suffix, supportingText,
  boolean isError, VisualTransformation, KeyboardOptions, KeyboardActions,
  boolean singleLine, int maxLines, int minLines, MutableInteractionSource,
  Shape, TextFieldColors)`, i.e. the seven `Function2` slots this amendment
  needs plus `isError`. New import: `androidx.compose.material3.TextField`
  (`Icon` and `IconButton` are already imported at `Renderer.kt:30-31`).
- **`leading_icon` / `trailing_icon` / `trailing_on_tap`** — `leadingIcon = {
  Icon(IconMap.get(node.stringOr("leading_icon")), contentDescription = null) }`,
  guarded on non-empty; the trailing slot is the same wrapped in
  `IconButton(onClick = { ctx.action(desc) })` when `trailing_on_tap` is
  present and `enabled`. **`ctx.action(desc)` bare, not `ctx.action(desc,
  JsonNull)`** — `RenderCtx.action`'s `value` parameter already defaults to
  `null` (`Renderer.kt:160`), and a non-null `JsonNull` would flow through
  `DeviceBridge.action` to `CompanionEngine.kt:430`'s
  `if (hookValue != null) put("value", hookValue)` and emit an `args.value =
  null` that §14.3 does not authorize; `trailing_on_tap` is not in the
  contract's `actions.injections`. Every existing non-injecting hook site calls
  it bare (`Renderer.kt:695`, `:781`, `:809`, `LayoutNodes.kt:200`, `:337`,
  `ContentNodes.kt:238`). `IconMap.get` (`IconMap.kt:89-105`) resolves
  `"clear"` reflectively to `Icons.Outlined.Clear` and falls back to
  `Icons.Outlined.HelpOutline`, which is §17.2's harmless placeholder.
- **`prefix` / `suffix`** — `prefix = { Text(node.stringOr("prefix")) }`,
  `suffix = { Text(...) }`, both guarded on non-empty. They sit outside
  `value`, so nothing in the `onValueChange` path at `Renderer.kt:435-448`
  changes and no `state.changed` payload moves.
- **`supporting_text` / `is_error` / `max_length`** — `supportingText = {
  Text(s) }` and `isError = node.boolOr("is_error")`; both a11y halves fold
  into one `semantics` block on the node's universal modifier, which is passed
  at `Renderer.kt:463`:

  ```kotlin
  val ml = node.intByValue("max_length", 0)   // 0 == absent
  val sup = node.stringOr("supporting_text")
  val isError = node.boolOr("is_error")
  val mm = if (ml > 0 || (isError && sup.isNotEmpty()))
      m.semantics {
          if (ml > 0) maxTextLength = ml
          if (isError && sup.isNotEmpty()) error(sup)
      } else m
  ```

  and `modifier = mm`. `intByValue` (`NodeAccess.kt:59-66`) is the existing
  integral-by-value reader used for `max_lines`, so `"max_length": 10.0` is
  accepted traffic as elsewhere.
  `androidx.compose.ui.semantics.error(SemanticsPropertyReceiver, String)`
  (`SemanticsProperties.kt:1386`) and
  `SemanticsPropertyReceiver.maxTextLength` (`:1402`, backed by
  `SemanticsProperties.MaxTextLength` at `:301`) both exist.
  **There is no clamp.** `onValueChange` (`Renderer.kt:435-448`) is untouched
  by `max_length`; the only transform there remains the §17.4 newline strip at
  `:437`. This is the whole of the r2 correction: the drafted
  `codePointCount`/`offsetByCodePoints` truncation is deleted.
- **`clearable`** — factor the body of `onValueChange` (`Renderer.kt:435-448`)
  into a local `fun commit(raw: String)` and render the trailing slot as
  `IconButton(onClick = { commit("") }) { Icon(IconMap.get("clear"), "Clear
  text") }`. Routing through `commit` is what makes it "as if the user had
  erased the text": the §14.6 password branch at `:442-447` is reused verbatim,
  and the draft in `rememberSaveable("ti:${ctx.surface}:$id:${ctx.epochOf(id)}")`
  (`Renderer.kt:398-399`) is updated in place, which is the one thing no
  descriptor can reach.
- **`hide_keyboard_on_submit`** — two edits, not one. (a) `Renderer.kt:459`
  becomes `imeAction = if (onSubmit != null || hideOnSubmit) ImeAction.Done
  else ImeAction.Default`, so the member raises the Done key by itself; without
  this the sample it exists for — a field with no remote handler at all — is
  unreachable. (b) read `val ime = LocalSoftwareKeyboardController.current` at
  the top of the composable (it is a CompositionLocal read and cannot live
  inside the plain `fun submit()`), then append `if (hideOnSubmit) ime?.hide()`
  to `submit()` at `Renderer.kt:429`, which is what `KeyboardActions(onDone = {
  submit() })` at `:461-462` invokes. `submit()`'s existing `onSubmit == null
  -> {}` arm already makes the no-handler path a no-op, so the dismissal is the
  only effect. `androidx.compose.ui.platform.LocalSoftwareKeyboardController`
  is present in `CompositionLocalsKt.class`.
- **Wire-side validation** — `SpecValidator.kt:548-561`'s `"text_input" -> {`
  arm gains exactly **two** rules, mirroring `check_text_input_slots`:
  `clearable` with `trailing_icon` → `ContentInvalid`, and `trailing_on_tap`
  without `trailing_icon` → `ContentInvalid`. There is no length rule to
  mirror. `max_length`'s positive-integer check comes free from
  `checkScalarFieldType` (`:467-496`, driven from the contract at `:545-546`)
  once `field_types` carries the entry, as do the other eight scalars, and
  `trailing_on_tap` is walked as an action by `:429` once `hook_keys` carries
  it.

**Bounding caveat, restated because it applies to all eleven.** The Companion
has no Compose UI test infrastructure — no `ui-test-junit4`, no `androidTest`
source set, and the four `render/` unit tests assert on data, never on a
composition. Every renderer claim above is source-verified only; none of it can
be gate-verified on a rendered frame. `hint` shipped declared-validated-and-read-
by-nobody for months under a fully green gate (`1917fff`), and the same class of
silent no-op is available to each of these eleven.

### Unblocks

**Five** catalog examples clear, all in `text-fields`
(`emacs/apps/m3-catalog/jetpacs-m3-text-fields.el`). Every one of them is a
**filled** `TextField` upstream — only `SimpleOutlinedTextFieldSample`
(`TextFieldSamples.kt:104`) is outlined — so `variant: "filled"` is a
co-requisite of all five, and no row below is "G-2x sole gap":

| example | upstream call | gap(s) | cleared by | divergence |
|---|---|---|---|---|
| `SimpleTextFieldSample` | `TextField(` `:93` | G-21 | `variant: "filled"` | none |
| `TextFieldWithSupportingText` | `TextField(` `:249` | G-21 + G-22 | `variant` + `supporting_text` | none |
| `TextFieldWithIcons` | `TextField(` `:142` | G-21 + G-24 | `variant` + `leading_icon` + `clearable` | two, below |
| `TextFieldWithPrefixAndSuffix` | `TextField(` `:194` | G-21 + G-25 + G-00 | `variant` + `prefix` + `suffix` (G-00's `placeholder=` landed in `1917fff`) | the `alwaysMinimizeLabel` checkbox knob is omitted |
| `TextFieldWithHideKeyboardOnImeAction` | `TextField(` `:328` | G-21 + G-26 | `variant` + `hide_keyboard_on_submit` | none, *given* the "raises Done itself" clause |

`TextFieldWithIcons` recreates but is not pixel-exact, and this is worth
ratifying with open eyes: upstream's leading icon is `Icons.Filled.Favorite`
while `IconMap.get` resolves Outlined → AutoMirrored → Filled
(`IconMap.kt:89-105`), so no wire string can select the Filled vector; and
upstream wraps the trailing clear button in `TooltipBox`/`PlainTooltip`
("Clear text"), which needs the separate `tooltip` node from the tooltips
group. `TextFieldWithPrefixAndSuffix`'s omitted checkbox follows the precedent
already set by the shipping `TextFieldWithPlaceholder` recreation, which drops
the same knob and says so in its docstring.

`TextFieldWithHideKeyboardOnImeAction` clears **only** because
`hide_keyboard_on_submit` raises the submit action itself. Upstream
(`TextFieldSamples.kt:326-334`) has no submit handler at all —
`onKeyboardAction = { keyboardController?.hide() }` and nothing else — and the
first draft's rule that the member "has no effect when `on_submit` is absent",
combined with `Renderer.kt:459` raising `ImeAction.Done` only when `on_submit`
is present, would have forced the recreation to invent a remote `on_submit`
and dispatch a spurious action to Emacs on every Done press. That is a real
fidelity divergence and the module's own docstring policy ("No recreated field
authors `on_change'") is against exactly that kind of noise. The clause in
edit 4 removes the need.

**Not cleared: `TextFieldWithErrorState`.** It stays `:unsupported` after
#163, and the ledger is wrong to attribute it to G-22 + G-23. Upstream
(`TextFieldSamples.kt:209-243`) needs three things this amendment does not
supply:

- `isError` is **derived per keystroke** (`:215-217`, driven by
  `snapshotFlow { state.text }` at `:219-222`); the wire's `is_error` is a
  static authored boolean, and flipping it needs an `on_change` round trip to
  Emacs and back.
- `supportingText` is a **`Row`**, not a string: `Text(if (isError)
  errorMessage else "")`, a `Spacer(Modifier.weight(1f))`, and a live counter
  `Text("Limit: ${state.text.length}/$charLimit")` (`:227-233`). A single
  `supporting_text` string cannot produce that layout or that counter.
- `label` swaps `"Username"` / `"Username*"` on error (`:226`).

`max_length` supplies the a11y announcement at `:238` and nothing else — which
is precisely why it must not clamp: the sample's error state is *reached* by
typing past ten. There is no existing G-id for the missing piece (the ledger
runs to G-98); it needs a **new gap** — a supporting-text *slot* that takes a
Node plus locally-derived error state, or a dedicated counter member. Whoever
files it should also correct `docs/AUDIT-m3-blockers-2026-08-02.md:209` and
`:212`, which claim G-22 and G-23 clear it.

Two further ledger cross-references are wrong and both samples stay
`:unsupported` after #163:

- `TextFieldWithInitialValueAndSelection` — G-21 supplies the filled container;
  the remaining half is `text_input.selection` (**G-50**, not G-25 as
  `AUDIT:203` says). Its outlined sibling
  `OutlinedTextFieldWithInitialValueAndSelection` is G-50 alone and is
  untouched here.
- `TextFieldWithTransformations` — the remaining halves are `mask`/`filter`
  (**G-52**, not G-31 as `AUDIT:212` says) *and* a hard length limit. Note that
  upstream fuses both in one expression:
  `InputTransformation.maxLength(10).then { if (!isDigitsOnly()) revertAllChanges() }`
  (`TextFieldSamples.kt:121-126`). `MaxLengthFilter.transformInput` is
  `if (length > maxLength) revertAllChanges()`
  (`InputTransformation.kt:240-244`) — revert-the-whole-edit, not clamp — and
  it *also* sets `maxTextLength` semantics (`:236-238`). So the enforcement
  half belongs with G-52, in the same `inputTransformation` chain, which is why
  it is not in #163. See decision 2.

`DenseTextFieldContentPadding` (`content_padding`, G-53) is out of scope.
Four examples in the module already build and are unaffected:
`SimpleOutlinedTextFieldSample`, `TextFieldWithPlaceholder`,
`PasswordTextField`, `TextArea`.

**Product text that must change in the same commit.** §16.4 makes
`:unsupported` reason strings product text, not comments, so a string that
becomes false is a defect and not a stale note. Eight pieces are affected, and
they split three ways —

*Five deleted with their examples* (each becomes a `:build`):
`jetpacs-m3-text-fields--filled-note` (`:43-45`, used only by
`SimpleTextFieldSample`) and the four inline strings for icons
(`:147`), prefix/suffix (`:158`), supporting text (`:170`) and the keyboard
(`:187`).

*Two rewritten while the example stays `:unsupported`*:
`TextFieldWithInitialValueAndSelection`'s string (`:125`) claims "text_input
always renders an OutlinedTextField, so the filled container is not
requestable" — half of it becomes false, and it must be reduced to the
selection reason alone; `TextFieldWithErrorState`'s string (`:164`) claims "no
is_error or supporting_text member" — both land, and it must be rewritten to
the live-counter / per-keystroke-derivation reason above.

*One docstring clause*: `PasswordTextField`'s "has no `trailing_icon` member to
ride on" (`:88`, in the `--password` docstring) is no longer true — with
`trailing_icon` + `trailing_on_tap` the reveal button becomes authorable, though
flipping obfuscation would still need a `password` visibility member this
amendment does not add.

Two strings are **unchanged and stay true**, contrary to the first draft:
`jetpacs-m3-text-fields--selection-note` (`:47-49` — there is still no
`selection` member) and `TextFieldWithTransformations`' string (`:141` — there
is still no input/output transformation member, and under decision 2A no
enforcement member either). `DenseTextFieldContentPadding`'s string is likewise
untouched.

**Design decision required (1 of 3): the shape of the keyboard dismissal.**

| | shape | for | against |
|---|---|---|---|
| **A** (drafted) | `text_input.hide_keyboard_on_submit: boolean`, which also raises the platform submit action so it works with no `on_submit` | Scoped to the node that raised the IME; no new action surface; two lines inside `RenderTextInput`. With the "raises Done itself" clause it recreates the one caller **exactly** — no invented remote handler, no spurious dispatch. | Only a `text_input` can lower the keyboard; a "Done" `button` beside the field cannot. The member's name says "on_submit" while its no-`on_submit` case is the one the catalog uses. |
| **B** | a §14.2 builtin `companion.keyboard.hide`, usable as any ActionDescriptor including `text_input.on_submit` | More general (any control can dismiss the IME); composes with the `dialog.dismiss`-style local builtins; `on_submit: {builtin: "companion.keyboard.hide"}` also recreates the caller exactly and locally. | Adds a builtin to the contract `actions` surface and to every builtin-aware validator; §17.4 currently forbids `clear_on_submit` beside a builtin `on_submit`, so authoring both together needs a new rule. |

The audit records both (G-26). **A** is recommended — but note that the first
draft's argument for A ("the general form has no second caller today") was
weak, because under the drafted rules the one caller wanted B's shape. That is
fixed by the clause, not by the argument: A now serves the caller exactly, and
B can still be added later without retracting A.

**Design decision required (2 of 3): does an enforcement member ship now?**

| | scope | for | against |
|---|---|---|---|
| **A** (drafted) | `max_length` announces only; the enforcement lands later, with G-52 | Matches the only two upstream uses precisely: the error sample announces without enforcing, and the transformations sample enforces via `InputTransformation`, where the limit is chained with the digits filter G-52 must add anyway. No caller in the catalog needs enforcement without G-52. Keeps §12 rules 2/3 clearly disengaged — an announcement constrains nothing, so no feature advertisement is owed. | `max_length` reads like a limit and is not one. A sender that assumes it clamps ships an over-long value and only finds out from the `state.changed` payload. |
| **B** | add `enforce_max_length: boolean` (default `false`) now; when true, an edit that would carry the value past `max_length` is **reverted in full** | Names the ambiguity away. Mirrors `MaxLengthFilter.transformInput`'s `revertAllChanges()` exactly, so the Companion could one day delegate. | A member with zero callers until G-52 lands, and its revert semantics are surprising in isolation: a 40-character paste into a 10-limit field yields *nothing*. `field_types` is flat, so the name is typed globally for every future node type. |

**A** is recommended. Note for the record that if B is ever taken, the
enforcement must be *revert-the-edit*, not the first draft's clamp — upstream's
implementation is `if (length > maxLength) revertAllChanges()`
(`InputTransformation.kt:240-244`), and clamping would silently truncate a
paste where Material discards it.

**Design decision required (3 of 3): do `is_error` and `max_length` ship at all
in #163?**

After the r2 correction they clear **nothing**: `TextFieldWithErrorState` is
their only catalog caller and it needs a further, unfiled gap.

| | scope | for | against |
|---|---|---|---|
| **A** (drafted) | ship all eleven; `is_error` + `max_length` land with zero callers | They are two of the three pieces the error sample needs, and the third is a *slot* change that will want them already present. `is_error` is also half of `supporting_text`'s colour contract (`supportingTextColor(enabled, isError, isFocused)`), so `supporting_text` without it can never show the error tint. Closes G-22 and G-23 as filed, which is what the ratifier reading the ledger expects. | Two members with no demonstrated caller, in a codebase that has just been burned by `hint` — declared, validated and read by nobody for months under a green gate. Nothing here can be gate-verified on a composition. |
| **B** | ship nine; defer `is_error` + `max_length` to the amendment that files and closes the counter gap | Every member in #163 then has a working caller on the day it lands. | `supporting_text` ships without its error tint; G-22 and G-23 stay open with an amendment that touched the same node and skipped them. |

**A** is recommended, with the zero-caller status stated plainly in the commit
message so it is a recorded choice and not an oversight.
---

## #164 — scaffold chrome refinements: snackbar duration/dismiss/clamp, the refresh indicator, and the FAB slot (§17.6)

Covers ledger gaps **G-27** (`scaffold.refresh_indicator`), **G-28**
(`snackbar_duration` + `snackbar_dismiss`), **G-29** (`snackbar_max_lines`), and
**G-42** (`fab_position`). Drafted 2026-08-02 against `ebp/SPEC.md` §17.6 and
`ebp/contract.json` as committed on `m3-fidelity`; every renderer and Compose
claim below was checked against the Kotlin and against
`material3-android-1.5.0-alpha16` (`ed86191`), not taken from the ledger.

**Numbering.** `ebp/SPEC-CHANGES.md`'s highest ratified row is **152**, and the
only pending numbers this tree accounts for are #153 and the rf-4a pair
#154/#155. `164` presumes eight sibling drafts in the same m3 batch; confirm the
batch's allocation before ratification, or renumber to the next free integer at
merge time.

**⚠ Two design decisions required** — see the tables at the end. A is drafted in
both cases.

**⚠ The unblocks claim was corrected in revision.** This amendment clears **one**
catalog example, not four, and only if the Emacs harness changes in the
"Emacs authoring" section land in the same commit. Three of the four examples
the draft claimed are demoted (two to G-76, one to G-73 + G-74); each demotion
and its blocking G-id is itemised under Unblocks.

### SPEC-CHANGES row (ready to paste)

> | 164 | 2026-08-02 | §17.6 (cross-ref §12 rule 6, §16.1, §16.4, §17.2; contract) | **Scaffold chrome gets its five presentation choices; the Companion stops hardcoding them.** §17.6's scaffold carries the chrome *slots* but none of the presentation members M3 puts on them, so five distinct renderings were unreachable from Emacs and the Companion silently picked one of each: `Renderer.kt:693` passes `duration = SnackbarDuration.Short` unconditionally and never passes `withDismissAction`; `Renderer.kt:700` wires `snackbarHost = { SnackbarHost(hostState) }` with no content lambda, so the message can never be clamped; `Renderer.kt:777` constructs `PullToRefreshBox` with no `indicator` argument; and the `Scaffold` opened at `Renderer.kt:699` passes no `floatingActionButtonPosition`. Five optional members close it, each defaulting to exactly what ships today. `snackbar_duration` is `short` (default), `long`, or `indefinite` and selects `SnackbarDuration`; `indefinite` never self-dismisses on a timer. `snackbar_dismiss` is a boolean, default `false`, and adds M3's trailing dismiss affordance (`withDismissAction`) — distinct from `snackbar_action`, and it dispatches nothing. The two are coupled by an existing MUST rather than by taste: the same paragraph already requires that a presented snackbar be dismissible by the user, and a snackbar with no timer and no dismiss affordance satisfies it only by accident, so `indefinite` IMPLIES the affordance whether or not `snackbar_dismiss` is present. `snackbar_max_lines` is a positive integer, absent meaning unclamped, and clamps the presented *message* to that many lines with a visible overflow indication while the complete `snackbar` string remains the accessible value — the same split §17.2's `badge` row already draws for a visually capped badge, and the reason a two-line clamp is a presentation member rather than a sender-side truncation. The three snackbar members are not equally live and the prose now says so: `snackbar_duration` and `snackbar_dismiss` are fixed at presentation time, while a snapshot that changes only `snackbar_max_lines` MAY re-clamp a snackbar already on screen — re-clamping is not re-presenting. `refresh_indicator` is `default` (default), `loading`, or `none`, filling `PullToRefreshBox`'s existing `indicator` slot with `PullToRefreshDefaults.Indicator` — which is literally that argument's own default, so `default` is today's pixels — or `PullToRefreshDefaults.LoadingIndicator`, or nothing. `fab_position` is `end` (default), `end_overlay`, or `center`, i.e. three of Compose's four `FabPosition` values; `Start` exists in 1.5.0-alpha16 and is deliberately not mapped, because no catalog example needs it and adding it later is a §25 optional non-constraining addition with the §12 rule 6 fallback already in place. The prose pins what each member does NOT do, because §17.6's standing rule is that chrome acquires no hidden behavior: none of the five adds an interaction; `none` neither removes the refresh gesture nor changes when `on_refresh` dispatches, and does not excuse §16.4's accessible-reachability duty; `refresh_indicator` and `fab_position` are inert when `on_refresh` or `fab` is absent rather than rejecting the surface; and a change to a snackbar presentation member ALONE MUST NOT re-present an unchanged `snackbar`, which keeps §17.6's §4.3-equality presentation rule keyed on the message exactly as it is today. Unknown enum values fall back to `short` / `default` / `end` under §12 rule 6 and never reject; nothing validates those value sets — `contract.json`'s `enums` block is read by no tool in this tree (neither `validate.py`, `tools/gen-vocabulary.py` nor `tools/gen-jetpacs-vocabulary.py` mentions it), so the closed vocabularies are documentation plus the renderer's `when` fallbacks, exactly the arrangement `text.style` has today. A `snackbar_max_lines` outside its domain is an ordinary §16.1 `1201`, enforced with no new validator arm, because `SpecValidator.kt:546` type-checks every schema-listed member through the projected `field_types`. Additive: all five members are optional and each default reproduces the current hardcoded rendering, so no previously valid snapshot changes meaning. Unblocks **one** catalog example — pull-to-refresh-indicator/`PullToRefreshWithLoadingIndicatorSample` — and only together with the `:on-refresh` slot exemption in `emacs/apps/m3-catalog/jetpacs-m3-core.el` named below; it advances but does not clear five others, still blocked on G-76, G-73, G-74, G-70, and the Node-valued indicator form. | contract `node_schema.scaffold.optional` += 5 members, `field_types` += `snackbar_dismiss`/`snackbar_max_lines`, `enums` += `scaffold.snackbar_duration`/`.refresh_indicator`/`.fab_position` (documentation only — no tool reads `enums`); goldens/widgets.golden line 75; generated mirrors `Vocabulary.kt` and `jetpacs-vocabulary.el` regenerated from the contract in the same commit (`VocabularyDriftTest`, `jetpacs-widgets/catalog-node-schema`); `jetpacs-widgets/scaffold-goldens` gains a line-75 arm; validate.py green with no new arm | |

### SPEC.md edits

**1. §17.6, the member list.** Replace:

> A `scaffold` node has no required members and MAY contain `top_bar`, `body`,
> `bottom_bar`, `fab`, `floating_toolbar`, and `drawer` as Nodes;
> `snackbar: string`; `snackbar_action: {label, on_tap}`; and
> `on_refresh: ActionDescriptor`.

with:

> A `scaffold` node has no required members and MAY contain `top_bar`, `body`,
> `bottom_bar`, `fab`, `floating_toolbar`, and `drawer` as Nodes;
> `snackbar: string`; `snackbar_action: {label, on_tap}`; `snackbar_duration`;
> `snackbar_dismiss`; `snackbar_max_lines`; `refresh_indicator`;
> `fab_position`; and `on_refresh: ActionDescriptor`.

(Types beyond §17.1's common rules: `snackbar_duration`, `refresh_indicator`,
and `fab_position` are the closed vocabularies fixed below; `snackbar_dismiss`
is an ordinary optional boolean under §17.1 and so defaults to `false`;
`snackbar_max_lines` is narrower than §17.1's finite-number rule and is stated
inline below.)

**2. §17.6, the snackbar paragraph.** Replace (the quote extends through the
presentation-identity sentence so the paragraph still reads
message-lifecycle → identity → presentation members):

> A presented snackbar SHOULD remain visible for at least 4 seconds and
> MUST be dismissible by the user. `snackbar` carries no Section 16.1 presentation
> identity: it is not a node and retains no local state.

with:

> A presented snackbar SHOULD remain visible for at least 4 seconds and
> MUST be dismissible by the user. `snackbar` carries no Section 16.1 presentation
> identity: it is not a node and retains no local state.
> `snackbar_duration` is `short` (default), `long`, or `indefinite` and
> governs how long a presented snackbar remains before it self-dismisses;
> `indefinite` MUST NOT self-dismiss on a timer, and remains until the user
> dismisses it, until the user taps `snackbar_action`, or until a later
> snapshot's absent or empty `snackbar` clears it as above.
> `snackbar_dismiss` is a boolean, default `false`; when true the presented
> snackbar carries an explicit dismiss affordance, which is distinct from
> `snackbar_action` and MUST NOT dispatch it. Because a snackbar that never
> times out would otherwise have no exit of its own, a `snackbar_duration`
> of `indefinite` MUST be presented with that affordance whether or not
> `snackbar_dismiss` is present — it is implied — so the requirement above
> that a presented snackbar be dismissible by the user holds at every
> duration. `snackbar_max_lines` MUST be a positive integer; it clamps the
> presented message to that many lines with a visible overflow indication,
> while the complete `snackbar` string MUST remain the accessible value,
> exactly as Section 17.2 requires of a visually capped `badge`. Omitting it
> leaves the message unclamped. An unrecognized `snackbar_duration` falls
> back to `short` (Section 12 rule 6). These three members are presentation
> of the `snackbar` value: they have no effect while no snackbar is
> presented, and a change to one of them alone MUST NOT re-present an
> unchanged `snackbar`. `snackbar_duration` and `snackbar_dismiss` are fixed
> when the snackbar is presented and a later change to either MUST NOT alter
> the snackbar already on screen; a change to `snackbar_max_lines` alone MAY
> be applied to a snackbar currently presented, since re-clamping the
> message is not re-presenting it.

**3. §17.6, the refresh and structural-content sentences.** Replace:

> It MUST dispatch `on_refresh` only after a user refresh gesture. A
> drawer or bar is structural content and MUST NOT acquire hidden navigation
> behavior not declared by its nodes.

with:

> It MUST dispatch `on_refresh` only after a user refresh gesture.
> `refresh_indicator` selects which indicator that gesture draws: `default`
> (the default), `loading`, or `none`. It is presentation of the refresh
> gesture and has no effect when `on_refresh` is absent, there being no
> gesture to indicate. `none` draws no indicator; it MUST NOT remove the
> gesture or change when `on_refresh` dispatches, and a scaffold that
> suppresses the indicator remains subject to Section 16.4 — the refresh
> MUST still be reachable and labelled, whether through the platform's own
> refresh affordance or through a control the scaffold's nodes declare. An
> unrecognized value falls back to `default` (Section 12 rule 6).
> `fab_position` places the `fab` slot: `end` (the default), `end_overlay`,
> or `center`. `end_overlay` overlays the fab on the `bottom_bar` rather
> than resting it above; `center` centers it on the horizontal axis. It has
> no effect when `fab` is absent, and an unrecognized value falls back to
> `end` (Section 12 rule 6). Neither member adds an interaction:
> `fab_position` MUST NOT alter what `fab`'s own nodes dispatch, and
> `refresh_indicator` MUST NOT alter what `on_refresh` dispatches. A
> drawer or bar is structural content and MUST NOT acquire hidden navigation
> behavior not declared by its nodes.

### Artifact changes

**`ebp/contract.json`** — four hunks, exactly as diffed below (the file is
`indent=2`, so this is byte-faithful; anchors verified against lines 570-571,
579-580 and 698-704 of the committed file):

```diff
@@ node_schema.scaffold.optional @@
         "drawer",
         "snackbar",
         "snackbar_action",
-        "on_refresh"
+        "on_refresh",
+        "snackbar_duration",
+        "snackbar_dismiss",
+        "snackbar_max_lines",
+        "refresh_indicator",
+        "fab_position"
       ]
@@ field_types @@
     "clip": "boolean",
     "scroll_here": "boolean",
+    "snackbar_dismiss": "boolean",
     "size": "dp",
@@ field_types @@
     "min_lines": "positive-integer",
     "max_lines": "positive-integer",
+    "snackbar_max_lines": "positive-integer",
     "initial": "non-negative-integer",
@@ enums (after "align_self", before "dialog.style") @@
       "end",
       "stretch"
     ],
+    "scaffold.snackbar_duration": [
+      "short",
+      "long",
+      "indefinite"
+    ],
+    "scaffold.refresh_indicator": [
+      "default",
+      "loading",
+      "none"
+    ],
+    "scaffold.fab_position": [
+      "end",
+      "end_overlay",
+      "center"
+    ],
     "dialog.style": [
```

Note on `field_types`: the three enum members are deliberately NOT added.
`field_types` is a FLAT bare-name → type map — adding a name types it globally
for every node type, so it cannot express node scoping — and it omits every
other enum-valued member (`style`, `variant`, `align`, `alignment`, `shape`,
`kind`, `op`, `placement`), with `keyboard: "enum"` the single outlier.
`snackbar_dismiss` and `snackbar_max_lines` ARE added, because every boolean and
integer member is listed there and `SpecValidator` drives its scalar type check
off exactly that map; both names are new to the whole vocabulary, so the global
typing has no collateral effect on another node type.

Note on `enums`: the block is **read by nothing** in this tree. `grep -n enums
ebp/validate.py tools/gen-vocabulary.py tools/gen-jetpacs-vocabulary.py` returns
no hits, and `Vocabulary.kt` stores only the type NAME `"enum"` for
`field_types` entries. The three entries are added for documentation parity with
every other closed vocabulary; the actual enforcement is the renderer's `when`
fallbacks, which is why §12 rule 6 fallbacks (not rejection) are the right
choice here and why this amendment claims no validator coverage for them.

**`ebp/goldens/widgets.golden`** — append one line. The file's last index today
is `74`, so the new index is `75`; indices `59` and `60` (the bare and full
scaffold) are untouched, so no existing fixture changes meaning:

```
75 {"fab":{"icon":"add","on_tap":{"action":"demo.tap"},"t":"icon_button"},"fab_position":"end_overlay","on_refresh":{"action":"app.refresh"},"refresh_indicator":"loading","snackbar":"Saved","snackbar_dismiss":true,"snackbar_duration":"indefinite","snackbar_max_lines":2,"t":"scaffold"}
```

(Keys are `json.dumps(..., sort_keys=True, separators=(',',':'))`-canonical, matching the corpus.)

**`test/jetpacs-widgets-test.el`** — `jetpacs-widgets/scaffold-goldens`
(`:512-528`) currently pins only indices `59` and `60`; the house pattern is that
every golden vector has a byte-parity arm, so it gains a third:

```elisp
      (chk "75" (jetpacs-scaffold
                 :fab (jetpacs-icon-button "add" (jetpacs-action "demo.tap"))
                 :fab-position "end_overlay"
                 :on-refresh (jetpacs-action "app.refresh")
                 :refresh-indicator "loading"
                 :snackbar "Saved"
                 :snackbar-dismiss t
                 :snackbar-duration "indefinite"
                 :snackbar-max-lines 2))
```

Its docstring ("Scaffold builds byte-identically to widgets.golden 59-60")
updates to 59-60 and 75. This arm cannot be written until `jetpacs-scaffold`
gains the keywords, which is why the Emacs work below is an artifact of this
amendment and not a follow-on.

**`ebp/validate.py`** — no arm. `check_node` (`:253`) validates a scaffold
against `node_schema` alone; `validate.py` reads neither `enums` nor
`field_types`, and the `positive-integer` domain is not enforced by the
reference validator for any member today (`max_lines` included), so nothing new
is owed. Applying the four contract hunks and the golden line to a scratch copy
of `ebp/` and running it produces, verbatim:

```
OK: 40 frames, 76 widget lines, 7 hypertext nodes, 17 wire fixtures x3 chunkings validate (spec 2.0.0-draft, format 6); SPEC §8/§11 in sync; 9.3 KAT reproduced
```

**Generated mirrors** (never hand-edited; both are drift-tested and MUST be
regenerated in the same commit as the contract change):
`python3 tools/gen-vocabulary.py` → `companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/Vocabulary.kt:65` (`NODE_SCHEMA["scaffold"]`) and its `FIELD_TYPES` map — asserted equal to `contract.json` by `VocabularyDriftTest.generatedVocabularyMatchesContract` (`companion/wire/src/jvmTest/.../SurfaceStoreTest.kt:727-751`);
`python3 tools/gen-jetpacs-vocabulary.py` → `emacs/jetpacs-vocabulary.el:72` — asserted by `jetpacs-widgets/catalog-node-schema` (`test/jetpacs-widgets-test.el:889`). The elisp mirror sorts members, so the regenerated row is alphabetical.

**Validator, for free.** `SpecValidator.kt:546` runs `checkScalarFieldType` over
`row.required + row.optional` for every present member, and `:487-488`
implements `"positive-integer"` as `(integralLongOrNull(...) ?: 0) < 1 →
ContentInvalid`. Once `snackbar_max_lines` is in the scaffold's schema row and
in `field_types`, `snackbar_max_lines: 0`, `-2`, `1.5`, or `"2"` is a §16.1
`1201` with no code change; `snackbar_dismiss: 0` likewise fails the `"boolean"`
arm at `:471`. Nothing checks the three enum values at any layer — that is the
§12 rule 6 fallback, by design, not an omission.

### Companion implementation

All four sites are inside `RenderScaffold`,
`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt:680`.
Every Compose symbol named below was confirmed present in
`material3-android-1.5.0-alpha16` (`javap` over the AAR's `classes.jar`).

**0. The opt-in.** `RenderScaffold` is annotated
`@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)` at
`Renderer.kt:678`. `PullToRefreshDefaults.LoadingIndicator` is
`@ExperimentalMaterial3ExpressiveApi` (`PullToRefresh.kt:633`), so that
annotation becomes
`@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class,
androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)`.
`PullToRefreshDefaults.Indicator` (`:582`), `FabPosition.EndOverlay`
(`Scaffold.kt:345`), `SnackbarHost`'s content overload and the content-slot
`Snackbar` are all stable and need no opt-in.

**1. `snackbar_duration` + `snackbar_dismiss` — Renderer.kt:688-697.** Today
`hostState.showSnackbar(message =, actionLabel =, duration = SnackbarDuration.Short)`:

```kotlin
val dur = when (node.stringOr("snackbar_duration", "short")) {
    "long"       -> SnackbarDuration.Long
    "indefinite" -> SnackbarDuration.Indefinite
    else         -> SnackbarDuration.Short        // §12 rule 6 fallback
}
// §17.6: `indefinite` implies the dismiss affordance.
val dismiss = node.boolOr("snackbar_dismiss") || dur == SnackbarDuration.Indefinite
...
val result = hostState.showSnackbar(
    message = snackbar,
    actionLabel = action?.stringOr("label")?.takeIf { it.isNotEmpty() },
    withDismissAction = dismiss,
    duration = dur)
```

`SnackbarHostState.showSnackbar(String, String, boolean, SnackbarDuration, Continuation)`
and `SnackbarDuration.{Short,Long,Indefinite}` are confirmed in the jar. The
`LaunchedEffect(snackbar)` key at :688 stays keyed on the message alone, which
is what makes both the "a change to one of them alone MUST NOT re-present"
sentence and the new "fixed when the snackbar is presented" sentence true by
construction rather than by promise.

**2. `snackbar_max_lines` — Renderer.kt:700**, replacing
`snackbarHost = { SnackbarHost(hostState) }`:

```kotlin
snackbarHost = {
    val cap = node.intByValue("snackbar_max_lines", Int.MAX_VALUE)
    if (cap == Int.MAX_VALUE) SnackbarHost(hostState)   // today's rendering, untouched
    else SnackbarHost(hostState) { data ->
        androidx.compose.material3.Snackbar(
            action = data.visuals.actionLabel?.let { lbl -> {
                androidx.compose.material3.TextButton(onClick = { data.performAction() }) {
                    Text(lbl) } } },
            dismissAction = if (data.visuals.withDismissAction) { {
                androidx.compose.material3.IconButton(onClick = { data.dismiss() }) {
                    androidx.compose.material3.Icon(IconMap.get("close"), "Dismiss") } } }
                else null) {
            Text(data.visuals.message, maxLines = cap,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                modifier = Modifier.semantics { contentDescription = data.visuals.message })
        }
    }
}
```

`SnackbarHost(SnackbarHostState, Modifier, (SnackbarData) -> Unit)`
(`SnackbarHostKt`, confirmed) and the content-slot `Snackbar(modifier, action,
dismissAction, actionOnNewLine, shape, …, content)` are both in the jar;
`SnackbarData` exposes `visuals`, `performAction()`, `dismiss()`, and
`SnackbarVisuals` exposes `message`, `actionLabel`, `withDismissAction`.
`IconMap.kt:28` already resolves `close`. The `semantics` modifier is what
discharges "the complete `snackbar` string MUST remain the accessible value".
This mirrors upstream `ScaffoldSamples.kt`'s `ScaffoldWithMultilineSnackbar`,
which is exactly `Snackbar { Text(message, maxLines = 2, overflow =
TextOverflow.Ellipsis) }` — with the action and dismiss buttons re-derived here
because our host, unlike the sample's, may carry them.
`intByValue` (`NodeAccess.kt:63`) is the by-value integer read `max_lines`
already uses, so `snackbar_max_lines: 2.0` is honored as validated.

The `cap == Int.MAX_VALUE` branch is load-bearing, not defensive: it is the only
thing that keeps the absent case on the bare `SnackbarHost(hostState)` path.
Without it the amendment silently restyles every existing snackbar, and the
"each default reproduces the current hardcoded rendering" claim would be false.

Note the asymmetry the new SPEC sentence now names: this read happens inside the
host's content lambda, so a snapshot changing only `snackbar_max_lines`
re-clamps a snackbar already on screen, whereas `snackbar_duration` and
`snackbar_dismiss` are captured when `LaunchedEffect(snackbar)` fires and cannot
change mid-presentation. That behavioural split is normative as of this
amendment rather than incidental.

**3. `refresh_indicator` — Renderer.kt:770-785.** Hoist the state (today the
`PullToRefreshBox` at :777 passes none, so it makes its own internally) and fill
the `indicator` slot:

```kotlin
val ptr = androidx.compose.material3.pulltorefresh.rememberPullToRefreshState()
...
androidx.compose.material3.pulltorefresh.PullToRefreshBox(
    isRefreshing = refreshing,
    onRefresh = { refreshing = true; ctx.action(onRefresh) },
    state = ptr,
    indicator = {
        when (node.stringOr("refresh_indicator", "default")) {
            "loading" -> PullToRefreshDefaults.LoadingIndicator(
                state = ptr, isRefreshing = refreshing,
                modifier = Modifier.align(Alignment.TopCenter))
            "none" -> Unit
            else -> PullToRefreshDefaults.Indicator(     // §12 rule 6 fallback
                state = ptr, isRefreshing = refreshing,
                modifier = Modifier.align(Alignment.TopCenter))
        }
    },
    modifier = bodyModifier) { body?.let { RenderNode(it, ctx.child(it, 1)) } }
```

`rememberPullToRefreshState()`, `PullToRefreshDefaults.Indicator-2poqoh4(state,
isRefreshing, modifier, containerColor, color, maxDistance)` and
`PullToRefreshDefaults.LoadingIndicator-4eDdRP8(...)` are all confirmed in the
jar. The `else` arm is provably today's pixels, not merely a close match:
`PullToRefreshBox`'s own default `indicator` argument is literally
`{ Indicator(modifier = Modifier.align(Alignment.TopCenter), isRefreshing =
isRefreshing, state = state) }` (`PullToRefresh.kt`, the `PullToRefreshBox`
signature), and the compiled default lambda
`PullToRefreshKt.PullToRefreshBox$lambda$0` calls
`PullToRefreshDefaults."Indicator-2poqoh4"`.

The naming precedent for the value `loading` is G-03's
`progress.variant += "loading"` — the ledger records that as G-27's dependency
("**Deps:** G-03 for the `loading` value", AUDIT:222). It is a **naming**
dependency only and does not block: `PullToRefreshDefaults.LoadingIndicator` is
its own composable on `PullToRefreshDefaults` (`LoadingIndicator-4eDdRP8`,
verified in the jar) with no relation to `progress.variant` or its renderer. If
G-03 lands first the two spellings agree; if this lands first, G-03 inherits the
spelling.

**4. `fab_position` — the `Scaffold(` call opened at Renderer.kt:699** (its
`floatingActionButton` slot is at :728-730; the ledger's G-42 citation of
`Renderer.kt:702-704` is wrong — that is the topBar lambda's `if (topBar != null
|| drawer != null)`):

```kotlin
floatingActionButtonPosition = when (node.stringOr("fab_position", "end")) {
    "end_overlay" -> androidx.compose.material3.FabPosition.EndOverlay
    "center"      -> androidx.compose.material3.FabPosition.Center
    else          -> androidx.compose.material3.FabPosition.End   // §12 rule 6 fallback
},
```

`FabPosition$Companion` exposes `getStart-ERTFSPs()`, `getCenter-`, `getEnd-`
and `getEndOverlay-` in 1.5.0-alpha16 (verified by `javap`); upstream
`AppBarSamples.kt:1777` (inside `ExitAlwaysBottomAppBar`, `:1685`) passes
`floatingActionButtonPosition = FabPosition.EndOverlay` and `Scaffold`'s own
default is `FabPosition.End`, so the `else` arm is today's rendering. `Start` is
the fourth value and is deliberately not mapped — no catalog example needs it
(upstream names it only in a comment, `FloatingToolbarSamples.kt:1477-1478`,
and passes `FabPosition.End` at `:1480`). Adding it later is a §25 "new
OPTIONAL … non-constraining field" addition with the §12 rule 6 fallback
already in place, so it costs one `enums` entry and one `when` arm and
invalidates nothing.

### Emacs authoring

Not a follow-on: without these, none of the five members can be authored at all,
the golden's byte-parity arm cannot be written, and the Unblocks claim below is
false. Four sites, three of which signal rather than degrade.

**1. `emacs/jetpacs-widgets.el:1516` `cl-defun jetpacs-scaffold`** gains five
keywords, guarded with the house helpers already used a few lines above
(`jetpacs--check-enum` at `:253`, `jetpacs--check-integer` as `jetpacs-text`
uses it at `:596`):

```elisp
(cl-defun jetpacs-scaffold (&key top-bar body bottom-bar fab floating-toolbar
                                 drawer snackbar snackbar-action on-refresh
                                 snackbar-duration snackbar-dismiss
                                 snackbar-max-lines refresh-indicator
                                 fab-position)
  ...
  (when snackbar-duration
    (setq snackbar-duration
          (jetpacs--check-enum snackbar-duration
                               '("short" "long" "indefinite") ":snackbar_duration")))
  (when snackbar-max-lines
    (jetpacs--check-integer snackbar-max-lines ":snackbar_max_lines" 1 nil))
  (when refresh-indicator
    (setq refresh-indicator
          (jetpacs--check-enum refresh-indicator
                               '("default" "loading" "none") ":refresh_indicator")))
  (when fab-position
    (setq fab-position
          (jetpacs--check-enum fab-position
                               '("end" "end_overlay" "center") ":fab_position")))
```

`snackbar-dismiss` needs no guard (`jetpacs--node` drops nil and emits `t` as
JSON `true`, the same treatment `:selectable` gets).

**2. `emacs/jetpacs-chrome.el:79-80` `cl-defun jetpacs-chrome-screen`** is
`&key back actions fab drawer bottom-bar on-refresh` — it has no `:snackbar` and
no `:floating-toolbar` today, so `jetpacs-m3-core.el:466-468`, which applies it
with the raw slot plist, would signal on any new keyword. Its `&key` list gains
the five (and, in passing, the two it was already missing), each forwarded to
`jetpacs-scaffold`.

**3. `emacs/apps/m3-catalog/jetpacs-m3-core.el:96-97 jetpacs-m3-slot-keys`** is
the closed list `(:fab :bottom-bar :drawer :floating-toolbar :on-refresh
:snackbar)`, and `jetpacs-m3-example` **errors** on an unknown slot at
`:135-136`. It gains the five. The per-slot type check at `:139` currently reads
`(if (eq key :snackbar) (stringp value) (functionp value))`; it becomes a
three-way check — node slots are nullary functions, `:snackbar` /
`:snackbar-duration` / `:refresh-indicator` / `:fab-position` are strings,
`:snackbar-dismiss` is a boolean, `:snackbar-max-lines` a positive integer.

**4. `emacs/apps/m3-catalog/jetpacs-m3-core.el:439-450
jetpacs-m3--example-slots`** — the `:on-refresh` exemption, and the reason
anything is cleared. Today the loop at `:443-449` pushes `(jetpacs-m3--guard
label value)` for every key but `:snackbar`, and `jetpacs-m3--guard` (`:401`) demands
`jetpacs--root-node-p`; `jetpacs-scaffold` demands an action **descriptor** for
`:on-refresh`, so the slot degrades to an `empty_state` node and then signals.
`jetpacs-m3-pull-to-refresh-indicator.el:26-35` records exactly this as a
HARNESS NOTE and is why the shipping `PullToRefreshSample` is built from
`:top-bar` + `:build` with no pull gesture on the screen at all. The loop must
pass the non-node slots through unguarded (`:on-refresh` funcalled without the
root-node check; the scalar members passed as authored):

```elisp
(push (cond ((memq key '(:snackbar :snackbar-duration :snackbar-dismiss
                         :snackbar-max-lines :refresh-indicator :fab-position))
             value)
            ((eq key :on-refresh) (funcall value))   ; a descriptor, not a node
            (t (jetpacs-m3--guard label value)))
      out)
```

Only after this does `refresh_indicator` reach a scaffold that has an
`on_refresh` — and `Renderer.kt:772` builds a `PullToRefreshBox` only inside
`if (onRefresh != null)`, so without it `refresh_indicator: loading` would
render nothing.

### Unblocks

**Cleared outright (1):**

| Slug / example | Gap it was blocked on | Its `:unsupported` string today |
|---|---|---|
| pull-to-refresh-indicator/`PullToRefreshWithLoadingIndicatorSample` | G-27 (sole wire gap) + the `:on-refresh` slot exemption above | the shared `--indicator-note`, `jetpacs-m3-pull-to-refresh-indicator.el:46-48` |

Upstream (`androidx .../samples/PullToRefreshSamples.kt:114-159`) is a `Scaffold`
whose body is a `PullToRefreshBox(state, isRefreshing, onRefresh, indicator = {
PullToRefreshDefaults.LoadingIndicator(state, isRefreshing,
Modifier.align(Alignment.TopCenter)) })` over a fifteen-row `LazyColumn`, with a
top bar carrying an accessible "Trigger Refresh" `IconButton`. Every piece is
now expressible: the top bar and list already build
(`jetpacs-m3-pull-to-refresh-indicator.el:89-95`), the gesture arrives via
`:on-refresh`, and `refresh_indicator: "loading"` is precisely the sample's
`indicator` argument. **Conceded fidelity, stated:** upstream hoists
`isRefreshing` and holds it for a 5 s fetch; the Companion substitutes its
hardcoded 1200 ms self-clear at `Renderer.kt:773-775` (G-73 `scaffold.is_refreshing`
is the member that would close this). That is the identical concession the
already-shipping sibling `PullToRefreshSample` makes on the same screen, so it is
not a new one.

**Advanced but not cleared (5):**

- snackbars/`ScaffoldWithIndefiniteSnackbar` — **with G-76.** The draft's earlier
  claim that this raises through a FAB tap on `:build` traffic was wrong. The
  m3-catalog root is a MULTI_VIEW, not a scaffold
  (`jetpacs-chrome.el:275` returns `(jetpacs-multi-view (nreverse views) (caar
  stack))`), and `jetpacs-shell.el:864` injects a queued snackbar only `(when
  (and snack (equal (plist-get spec :t) "scaffold")))`, degrading everything
  else to a toast at `:920-921`. So `m3catalog.demo` →
  `jetpacs-m3--on-demo` (`jetpacs-m3-core.el:644`) → `jetpacs-shell-notify`
  produces a TOAST here, which carries no duration, no dismiss affordance and no
  line clamp. `jetpacs-m3-snackbars.el`'s own commentary (`:22-30`) already says
  so, and AUDIT:395-398 records it as G-76 — including the ⚠ that the *shipping*
  `ScaffoldWithSimpleSnackbar` commentary is subtly wrong for the same reason.
  Beyond G-76, `jetpacs-shell-notify` (`jetpacs-shell.el:950-957`, the `puthash`
  at `:956-957`) stores a BARE
  STRING keyed by surface with no slot for the new members, so the raise payload
  must widen too.
- snackbars/`ScaffoldWithMultilineSnackbar` — **with G-76**, identically, and for
  the same payload reason.
- loading-indicators/`LoadingIndicatorPullToRefreshSample` — **with G-73
  (`is_refreshing`) and G-74 (`distance_fraction` + universal `scale`).** This
  sample does not use `PullToRefreshBox` at all: it applies
  `Modifier.pullToRefresh(state, isRefreshing, onRefresh)` to the `Scaffold`,
  draws `PullToRefreshDefaults.LoadingIndicator` inside a `Box` scaled by
  `LinearOutSlowInEasing.transform(state.distanceFraction)` through
  `graphicsLayer`, and hides the list entirely while `isRefreshing`
  (androidx `.../samples/LoadingIndicatorSamples.kt:143-198` — esp. `:158-160`
  the `scaleFraction` lambda, `:165-169` `Modifier.pullToRefresh`, `:184` `if
  (!isRefreshing)`, `:188-192` the `graphicsLayer`
  `Box`). `refresh_indicator: loading` reproduces the indicator identity and
  nothing else — not the pull-proportional scale, not the `isRefreshing` gating.
  The sample's own reason string names `distanceFraction`, and this amendment
  does not answer it.
- bottom-app-bar/`ExitAlwaysBottomAppBar` — **with G-70**
  (`scaffold.bottom_bar_behavior`, AUDIT:376-377). `fab_position: end_overlay`
  supplies the FAB-overlap half, which is exactly what the ledger's G-42 entry
  claims and no more; the sample still needs
  `BottomAppBarDefaults.exitAlwaysScrollBehavior()` (MEDIUM, its own amendment).
- pull-to-refresh-indicator/`PullToRefreshCustomIndicatorWithDefaultTransform` —
  needs the Node-valued indicator form, a separate NEEDS_PROTOCOL gap. (The
  ledger's G-27 line says "with G-28"; G-28 is the snackbar duration, so that
  cross-reference is an erratum — the real co-requisite is the Node-valued
  form.) `refresh_indicator: none` is the seam it will build on: an authored
  indicator subtree presupposes the ability to suppress the canned one.

Also repaired in passing: `jetpacs-m3-pull-to-refresh-indicator.el:46-48`'s
`--indicator-note` becomes false for the cleared sample the moment this lands,
and per the verification plan a stale reason string is a product defect, not a
comment nit. It is **shared** — `:100` and `:123` both use it — so it cannot
simply be deleted: `PullToRefreshWithLoadingIndicatorSample` (`:100`) drops
`:unsupported` entirely and gains its `:top-bar` / `:build` / `:slots`, while
`PullToRefreshCustomIndicatorWithDefaultTransform` (`:123`) needs a narrowed
note naming only the Node-valued indicator form. The five still-blocked examples
keep their reason strings, but each SHOULD be re-pointed at its actual remaining
gap (G-76, G-73/G-74, G-70) rather than at the members this amendment adds — the
HARNESS NOTE at `:26-35` is likewise discharged by the `:on-refresh` exemption
and must go.

**Bounding caveat.** The Companion has no Compose UI test infrastructure — the
`render/` unit tests assert on data, never on a composition — so nothing in this
tree can assert that `snackbar_max_lines` reaches a `Text(maxLines =)` or that
`refresh_indicator: loading` draws the loading indicator. All five members can
pass `SpecValidator`, be projected into the contract, be mirrored into both
vocabularies, and still render nothing, exactly as `hint`, `align_self` and half
of `surface.elevation` did. The only enforcement this amendment claims is the
contract/mirror drift tests, `validate.py`'s structural pass, and
`SpecValidator`'s scalar type check on `snackbar_dismiss` and
`snackbar_max_lines`. Verification of the rendering is manual, on device.

### Design decision required — 1 of 2: does `indefinite` imply the dismiss affordance?

| | Option A (recommended, drafted) | Option B |
|---|---|---|
| Rule | `snackbar_duration: indefinite` MUST be presented with the dismiss affordance whether or not `snackbar_dismiss` is present | `snackbar_dismiss` is authored-only; `indefinite` without it is content-invalid (`1201`) |
| Upside | The standing MUST that a presented snackbar be dismissible by the user holds at every duration, with no new rejection class. One-member authoring for the common case. Matches upstream `ScaffoldWithIndefiniteSnackbar`, which passes both together. | The wire says exactly what the user sees; no member is ever silently promoted. |
| Downside | An authored `snackbar_dismiss: false` alongside `indefinite` is honored as `true` — a member whose authored value is overridden, which no other §17 member does. | A new whole-surface rejection for a legal-looking combination, and Emacs must know the coupling to author a valid snapshot at all. |
| Note | `snackbar_action` is NOT an acceptable substitute for the affordance: §17.6 already forbids dispatching it on anything but a user tap, and an author may want an indefinite snackbar with no action. | |

### Design decision required — 2 of 2: inert, or co-requisite?

| | Option A (recommended, drafted) | Option B |
|---|---|---|
| Rule | `refresh_indicator` without `on_refresh`, and `fab_position` without `fab`, have no effect | Each is a co-requisite: present without its slot ⇒ `1201`, on the `empty_state` `action_label`/`on_tap` model |
| Upside | Matches how §17.6 already treats `snackbar_action` with no `snackbar`. A surface that toggles `on_refresh` between snapshots keeps rendering. | Catches an authoring mistake at the wire instead of rendering nothing; the ledger's G-27 entry assumes this ("Requires `on_refresh` present"). |
| Downside | A typo'd `on_refresh` leaves `refresh_indicator` silently inert. | Turns a benign leftover member into a whole-surface rejection — the m3-catalog apps, which switch examples inside one surface, would hit it. |
| Note | The two decisions interact: under B, a surface that drops `on_refresh` in one snapshot while leaving `refresh_indicator` in place becomes a whole-surface `1201`, a rejection class no other scaffold member has. | |
---

## #165 — picker display modes: `date_button.mode`, `time_button.display_mode`

**⚠ Four design decisions required.** Tables at the end; the draft below is
option A in each. Decision 4 is the one that changes pixels for existing
traffic — read it before ratifying.

**Revised against review.** Three corrections the reviewer was right about and
this draft now carries: the contract delta regenerates two drift-tested
mirrors (they are now in the artifact cell); `DateInputSample` is **not**
unblocked, so the honest count is **2, not 3**; and the `time_button` half is
additive on the wire but **not** on screen, so the "reproduces today's
rendering exactly" claim is gone and the height rule is a MAY, not a MUST.

### SPEC-CHANGES row (ready to paste)

> | 165 | 2026-08-02 | §17.4 (cross-ref §12 rules 2/6, §16.3, §16.4; contract) | **The date and time buttons can only ask for a dial, never a keypad.** `date_button` and `time_button` each carry exactly `label`, `on_pick`, `value`, `enabled` — the Companion builds the entire picker dialog behind the button, and both of the toolkit's entry affordances live inside it where no authored member reaches. `RenderDateButton` calls `rememberDatePickerState(initialSelectedDateMillis = …)` with no `initialDisplayMode` (`InputNodes.kt:442`), so every date picker *opens* on the month grid; `RenderTimeButton` fills a bare `AlertDialog` with `text = { TimePicker(state) }` (`InputNodes.kt:472-485`), so every time picker opens on the clock dial and there is no mode control anywhere in the composition. Two optional presentational members close it. `date_button.mode` is an enum, `calendar` (default) or `input`, passed as the picker state's **initial** display; the member buys the initial display and nothing more, because M3's `DatePicker` already ships `showModeToggle = true` (`DatePicker.kt:206`) and the Companion does not override it at `InputNodes.kt:455` — typed date entry is already reachable on device by tapping the pencil, and what Emacs cannot do today is choose which display the dialog opens on. The spec says so, so no author mistakes `mode` for a lock. `time_button.display_mode` is an enum, `picker` (default), `input`, or `switchable`, selecting `TimePicker` vs `TimeInput` inside the dialog; `switchable` additionally requires a mode control, which is why it is a third value rather than a second member — M3 supplies that control only through `TimePickerDialog`'s `modeToggleButton` slot (`TimePickerDialogDefaults.DisplayModeToggle`), so `switchable` is the one value that changes the dialog's *construction* rather than just its contents. The two members are named apart deliberately: their ranges are disjoint, `switchable` is meaningless on a date button whose toggle is unconditional, and a shared name would invite `display_mode: "calendar"` on a time button and `mode: "switchable"` on a date button — both of which would then take Section 12 rule 6's silent fallback. Neither member is constraining under Section 12 rule 2 (omitting it yields a picker that enters exactly the same values), so neither needs a feature advertisement; an older Companion ignores an unknown optional field under Section 16.3 and renders today's dial, which is what the new defaults mean. **On the wire this is purely additive; on screen the time side is not.** Because `switchable` needs a toggle slot the bare `AlertDialog` does not have, `RenderTimeButton` moves onto M3's `TimePickerDialog` for all three values, and every existing default `time_button` therefore gains M3's dialog headline (`TimePickerDialogDefaults.Title` — `TimePickerDialog`'s `title` parameter has no default), shape and container colour. That is a Section 16.4 fidelity change, not a wire change: "Render" does not require pixel identity, `on_pick` still receives `HH:MM` and `YYYY-MM-DD`, and no existing golden, fixture, or message changes meaning. The section also records a Section 16.4 allowance the toolkit does not exercise today: where the available height cannot accommodate a clock dial, a Companion MAY render the text-entry form under any value, and one that does MUST NOT offer a control it cannot honor. It is stated as a permission and not a requirement precisely so that the shipped build — which has no height test anywhere in `RenderTimeButton` — does not become non-conforming on ratification. No screen geometry crosses the wire. | contract `node_schema.date_button.optional` += `mode`, `node_schema.time_button.optional` += `display_mode`; `enums` += `date_button.mode`, `time_button.display_mode` (range registry — nothing reads it); regenerate `companion/wire/…/Vocabulary.kt` and `emacs/jetpacs-vocabulary.el` in the same commit (both drift-tested); goldens/widgets.golden += 2 lines; `field_types` and validate.py unchanged | Caleb Christensen |

### SPEC.md edits

1. **§17.4, the input-node table.** Replace (SPEC.md:2422-2423):

   > ```
   > | `date_button` | `label: string`, `on_pick: ActionDescriptor` | `value`, `enabled` |
   > | `time_button` | `label: string`, `on_pick: ActionDescriptor` | `value`, `enabled` |
   > ```

   with:

   > ```
   > | `date_button` | `label: string`, `on_pick: ActionDescriptor` | `value`, `mode`, `enabled`. `mode`: `calendar` (default) or `input`. |
   > | `time_button` | `label: string`, `on_pick: ActionDescriptor` | `value`, `display_mode`, `enabled`. `display_mode`: `picker` (default), `input`, or `switchable`. |
   > ```

2. **§17.4, the member-semantics prose after the table.** Replace (SPEC.md:2509-2510):

   > `date_button.value` is `YYYY-MM-DD`; `time_button.value`
   > is `HH:MM` in local civil time.

   with:

   > `date_button.value` is `YYYY-MM-DD`; `time_button.value`
   > is `HH:MM` in local civil time.
   >
   > `date_button.mode` selects the date picker's initial display: `calendar`
   > (default) a month grid, `input` a typed-date field with the toolkit's own
   > formatting and validation. It selects the initial display only; a Companion
   > MAY continue to offer its own control for switching between the two, and
   > Emacs MUST NOT use `mode` to restrict how a date may be entered.
   > `time_button.display_mode` is `picker` (default), a clock dial; `input`, hour
   > and minute text fields; or `switchable`, the clock dial together with a
   > control that switches to and from the text fields. Under `picker` and `input`
   > the Companion MUST NOT offer a mode control; under `switchable` it MUST,
   > except where the following allowance applies. Where the available height
   > cannot accommodate a clock dial, a Companion MAY render the text-entry form
   > under any value, and one that does MUST NOT offer a control it cannot honor.
   > Both members are presentational: they change how a value is entered, never
   > which values are legal, and neither changes what `on_pick` receives. An
   > unknown `mode` falls back to `calendar` and an unknown `display_mode` to
   > `picker`, the Section 12 rule 6 safe fallbacks.

*(No §17.1 change: `mode` and `display_mode` are not covered by 17.1's common
types, and the prose above supplies both, which is exactly what 17.1's "the
member-specific prose immediately after the table supplies its type"
(SPEC.md:2228-2229) directs.)*

### Artifact changes

**`contract.json` — `node_schema`** (contract.json:424-443). Replace:

> ```json
>     "date_button": {
>       "required": [
>         "label",
>         "on_pick"
>       ],
>       "optional": [
>         "value",
>         "enabled"
>       ]
>     },
>     "time_button": {
>       "required": [
>         "label",
>         "on_pick"
>       ],
>       "optional": [
>         "value",
>         "enabled"
>       ]
>     },
> ```

with:

> ```json
>     "date_button": {
>       "required": [
>         "label",
>         "on_pick"
>       ],
>       "optional": [
>         "value",
>         "mode",
>         "enabled"
>       ]
>     },
>     "time_button": {
>       "required": [
>         "label",
>         "on_pick"
>       ],
>       "optional": [
>         "value",
>         "display_mode",
>         "enabled"
>       ]
>     },
> ```

**`contract.json` — `field_types`: NO CHANGE.** The previous draft added
`"mode": "enum"` and `"display_mode": "enum"`. Both are dropped, for two
reasons that were checked rather than assumed:

- *They would be dead entries.* `validate.py` never reads `field_types` at
  all (`grep -n field_types validate.py` returns nothing), and the Companion's
  `SpecValidator.checkScalarFieldType` routes `"enum"` to `else -> Unit`
  (`SpecValidator.kt:470-495`, "enum, font-weight, varies-per-node, and
  complex types"). An `"enum"` entry buys zero enforcement anywhere.
- *The convention is the other way, 8-to-1.* `keyboard` (contract.json:527) is
  the **only** `"enum"` entry in `field_types`; `variant`, `style`, `align`,
  `alignment`, `arrange`, `content_scale`, `kind`, `shape`, `op`, `placement`,
  `priority` and `severity` — every other enum-valued member in `node_schema` —
  are absent from it and live only in `enums`. Claiming the very generic global
  name `mode` walks straight into the trap amendments **#66** (`fill`) and
  **#82** (`selected`) had to correct: `field_types` is name-keyed, so a future
  `mode` on any other node type would degrade the entry to `varies-per-node`.

**`contract.json` — `enums`** (contract.json:698). Insert immediately before
`"align_self": [`:

> ```json
>     "date_button.mode": [
>       "calendar",
>       "input"
>     ],
>     "time_button.display_mode": [
>       "picker",
>       "input",
>       "switchable"
>     ],
> ```

Placement rationale, stated honestly: this is *adjacency to
`text_input.keyboard`*, the only other §17.4 input-node enum — not a file-wide
ordering rule. The `enums` key order is `text.style, rich_text.style,
progress.variant, button.variant, image.content_scale, row.align, column.align,
flow_row.align, arrange, box.alignment, surface.shape, chart.kind, canvas.op,
text_input.keyboard, align_self, dialog.style, notification.priority,
diagnostic.severity, toolbar.placement` — four node-scoped enums sit *after* the
cross-cutting `align_self`, so "node-scoped enums together, ahead of the
cross-cutting ones" is not what the file does. JSON object order is not
semantic; any position validates.

**And state plainly what `enums` is worth:** nothing reads it. `validate.py`
never mentions it, neither generator projects it, and `Vocabulary.kt` stores
only the type *name*. It is the contract's documentation-grade range registry.
The enforced half of this delta is `node_schema` alone — which is exactly the
half that makes the two new golden lines legal.

**Generated mirrors — REQUIRED, same commit.** Both are generated from
`contract.json.node_schema` and both carry a drift test that re-reads the
contract and fails on disagreement. Run from the `llm-poc-2` root:

```
python3 tools/gen-vocabulary.py          # -> companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/Vocabulary.kt
python3 tools/gen-jetpacs-vocabulary.py  # -> emacs/jetpacs-vocabulary.el
```

- `Vocabulary.kt:59-60` (contract order preserved) becomes:

  ```kotlin
  "date_button" to NodeRow(setOf("label", "on_pick"), setOf("value", "mode", "enabled")),
  "time_button" to NodeRow(setOf("label", "on_pick"), setOf("value", "display_mode", "enabled")),
  ```

  Drift test: `VocabularyDriftTest.generatedVocabularyMatchesContract`
  (`SurfaceStoreTest.kt:727-756`) asserts `required`/`optional` row-by-row. Its
  `FIELD_TYPES` assertion (`:752-755`) is untouched because `field_types` is
  unchanged — the `FIELD_TYPES` map near `Vocabulary.kt:121` does not move.

- `jetpacs-vocabulary.el:66-67` (the generator **sorts** each member set —
  `gen-jetpacs-vocabulary.py:32-37`) becomes:

  ```elisp
  ("date_button" ("label" "on_pick") ("enabled" "mode" "value"))
  ("time_button" ("label" "on_pick") ("display_mode" "enabled" "value"))
  ```

  Drift test: `jetpacs-widgets/catalog-node-schema`
  (`test/jetpacs-widgets-test.el:889-905`) — "when this fails the contract
  moved, so REGENERATE rather than editing emacs/jetpacs-vocabulary.el by
  hand."

**`goldens/widgets.golden`** — append two lines. The file is 75 lines numbered
`00`–`74`, so these are `75` and `76`; the `NN ` index prefix is load-bearing
(`validate.py:379` splits each line on the first space and raises without it).
The existing date_button/time_button coverage lines **52** and **53** are *not*
touched, so the default rendering stays pinned:

> ```
> 75 {"label":"Due","mode":"input","on_pick":{"action":"due.pick"},"t":"date_button","value":"2026-07-22"}
> 76 {"display_mode":"switchable","label":"At","on_pick":{"action":"at.pick"},"t":"time_button","value":"09:30"}
> ```

(Keys in the corpus's sorted-key canonical form.) These lines are also replayed
through `SpecValidator` by `WidgetsGoldenReplayTest` (`:52-60`), which is why
the `Vocabulary.kt` regeneration above is not optional.

**`validate.py`** — **no arm needed.** `check_node` (validate.py:253-296) admits
a member iff it is in the node's `required`/`optional` or in
`universal_node_attributes`, so the `node_schema` edit is exactly what makes the
new golden lines legal. Verified end to end: with the `node_schema`, `enums` and
golden delta above applied to a scratch copy of `ebp/`, `python3 validate.py`
prints

```
OK: 40 frames, 77 widget lines, 7 hypertext nodes, 17 wire fixtures x3 chunkings validate (spec 2.0.0-draft, format 6); SPEC §8/§11 in sync; 9.3 KAT reproduced
```

and exits 0.

**Named-tool enforcement, per §24.4/#151.** What actually gates these two
members: `validate.py check_node` and `SpecValidator.validateNode` gate the
member *names* against `node_schema`; `VocabularyDriftTest` and
`jetpacs-widgets/catalog-node-schema` gate the two mirrors against the contract;
`jetpacs--check-enum` gates the *values* on the Emacs side only. Nothing
anywhere gates the value set on the wire (the `enums` registry is read by no
tool), and nothing asserts that the renderer honours either member — the
Companion has **no Compose UI test infrastructure**. Enforcement of the
rendering is a human reading `InputNodes.kt`. That is the amendment's weak
point and it is the same shape that let `hint`, `align_self` and `badge ""`
rot.

**Emacs-side (consumer, not an `ebp/` artifact).** `jetpacs-date-button`
(`emacs/jetpacs-widgets.el:1153-1160`) gains `:mode` and `jetpacs-time-button`
(`:1162-1169`) gains `:display-mode`, each gated by the existing
`jetpacs--check-enum` (`:253`) in the shape `jetpacs-progress`'s `:variant` uses
at `:695`:

```elisp
(cl-defun jetpacs-date-button (label on-pick &key value mode enabled)
  ;; …
  (when mode (setq mode (jetpacs--check-enum mode '("calendar" "input") ":mode")))
  (jetpacs--node "date_button" :label label :on_pick on-pick :value value
                 :mode mode :enabled enabled))

(cl-defun jetpacs-time-button (label on-pick &key value display-mode enabled)
  ;; …
  (when display-mode
    (setq display-mode (jetpacs--check-enum display-mode
                                            '("picker" "input" "switchable")
                                            ":display-mode")))
  (jetpacs--node "time_button" :label label :on_pick on-pick :value value
                 :display_mode display-mode :enabled enabled))
```

Add the two matching byte-parity cases to `jetpacs-widgets/input-goldens`
(`test/jetpacs-widgets-test.el:257`, beside the existing `chk "52"`/`chk "53"`):

```elisp
(chk "75" (jetpacs-date-button "Due" (jetpacs-action "due.pick")
                               :mode "input" :value "2026-07-22"))
(chk "76" (jetpacs-time-button "At" (jetpacs-action "at.pick")
                               :display-mode "switchable" :value "09:30"))
```

This is the only automated check anywhere that the constructors emit the new
members at all.

### Companion implementation

All in
`companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/InputNodes.kt`.
material3 is `1.5.0-alpha16` since `ed86191`.

**Opt-in: nothing new is required.** `InputNodes.kt:460` already carries
`@OptIn(ExperimentalMaterial3Api::class)`, and that is sufficient. Verified from
the unpacked `classes.jar` rather than assumed: Kotlin emits an opt-in marker as
an ordinary JVM annotation on the declaration, so it is visible in bytecode —
`TimePickerKt.class` does contain `Landroidx/compose/material3/ExperimentalMaterial3Api;`,
which proves the check works, while `TimePickerDialogKt.class` and
`TimePickerDialogDefaults.class` contain **no** experimental-marker reference at
all and `javap -v` shows no such `RuntimeInvisibleAnnotations` on
`TimePickerDialog-FItCLgY`. `TimePickerDialog`, `TimePickerDialogDefaults.Title`,
`.DisplayModeToggle` and `.MinHeightForTimePicker` are unmarked in this
artifact; no `ExperimentalMaterial3ExpressiveApi` is involved.

**`RenderDateButton` (:433-457) — one argument and one import.** At **:442**,
replace

```kotlin
val state = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
```

with

```kotlin
val state = rememberDatePickerState(
    initialSelectedDateMillis = initialMillis,
    initialDisplayMode = if (node.stringOr("mode") == "input")
        DisplayMode.Input else DisplayMode.Picker)
```

New import: `androidx.compose.material3.DisplayMode`.
`rememberDatePickerState(Long?, Long?, IntRange, DisplayMode, SelectableDates)`
and `DisplayMode.Picker`/`.Input` are present
(`DatePickerKt.rememberDatePickerState-EU0dCGE`,
`DisplayMode$Companion.getPicker-jFl-4v0`/`getInput-jFl-4v0`). The `else` arm is
the §12 rule 6 fallback and is the same `when`/`else` idiom `RenderButton` uses
for `variant` at **:89-94**. Nothing else in the function changes: the
`DatePickerDialog` at **:443** and the `DatePicker(state)` at **:455** stay, and
because :455 passes no `showModeToggle` M3's default of `true`
(`DatePicker.kt:206`) leaves the pencil toggle on screen — which is what makes
the SPEC's "initial display only" sentence true of the reference implementation,
and also why this member's honest value is narrower than it looks (see Unblocks).

**`RenderTimeButton` (:462-487) — the dialog moves.** `switchable` needs a mode
control and M3 exposes one only through `TimePickerDialog`'s `modeToggleButton`
slot, so the bare `AlertDialog` at **:472** becomes `TimePickerDialog`. The
confirm/dismiss bodies at **:474-484** carry over verbatim; `state` stays hoisted
above the mode branch so toggling never loses the hour/minute already dialed.
Replace the `if (show) { … }` body at **:469-486** with:

```kotlin
val (h, min) = remember { parseHm(node.stringOr("value")) }
val state = rememberTimePickerState(initialHour = h, initialMinute = min)
val authored = node.stringOr("display_mode")
var input by rememberSaveable(authored) { mutableStateOf(authored == "input") }
val switchable = authored == "switchable"
val tall = LocalConfiguration.current.screenHeightDp.dp >
    TimePickerDialogDefaults.MinHeightForTimePicker
val mode = if (input || !tall) TimePickerDisplayMode.Input
           else TimePickerDisplayMode.Picker
TimePickerDialog(
    onDismissRequest = { show = false },
    confirmButton = {                          // :474-481 verbatim
        TextButton(onClick = {
            show = false
            if (onPick != null)
                ctx.action(onPick, JsonPrimitive(
                    String.format("%02d:%02d", state.hour, state.minute)))
        }) { Text("OK") }
    },
    title = { TimePickerDialogDefaults.Title(displayMode = mode) },
    modeToggleButton = if (switchable && tall) {
        {
            TimePickerDialogDefaults.DisplayModeToggle(
                onDisplayModeChange = { input = !input },
                displayMode = mode)
        }
    } else null,
    dismissButton = {                          // :482-484 verbatim
        TextButton(onClick = { show = false }) { Text("Cancel") }
    }) {
    if (mode == TimePickerDisplayMode.Picker) TimePicker(state = state)
    else TimeInput(state = state)
}
```

New imports: `androidx.compose.material3.TimeInput`,
`androidx.compose.material3.TimePickerDialog`,
`androidx.compose.material3.TimePickerDialogDefaults`,
`androidx.compose.material3.TimePickerDisplayMode`, and
`androidx.compose.ui.platform.LocalConfiguration`. `rememberSaveable` (:60),
`dp` (:65) and `AlertDialog` (:29, still used at :357) need no change.

Notes on the shape:

- `TimePickerDialog`'s parameter list is
  `(onDismissRequest, confirmButton, title, modifier, properties,
  modeToggleButton, dismissButton, shape, containerColor, content)`; `title` has
  **no default**, `modeToggleButton` is `@Composable (() -> Unit)?` defaulting to
  `null`. Passing `null` (rather than upstream's `{}`) is why `picker` and
  `input` satisfy the SPEC's "MUST NOT offer a mode control".
- `rememberSaveable(authored)` re-seeds when Emacs re-pushes a different
  `display_mode` and survives configuration change; a bare `rememberSaveable`
  would pin the first authored value forever.
- The `!tall` term is the SPEC's height allowance. It reads `LocalConfiguration`
  device-locally, so nothing crosses the wire — and because the SPEC states it as
  a MAY, this arm is a Companion choice, not a conformance obligation.
- This is upstream `TimePickerSwitchableSample`
  (`androidx …/samples/TimePickerSamples.kt:154-218`) with `displayMode` driven
  by the wire member instead of a bare `remember`; `TimeInputSample` (`:107-148`)
  is the same call with `modeToggleButton = {}`. `TimeInput(TimePickerState,
  Modifier, TimePickerColors)` is present in `TimePickerKt.class`.

**What this costs existing traffic.** Every `time_button` on the wire today
renders through the new path. The dialog container changes from `AlertDialog`
(no headline, `AlertDialog` shape/colors) to `TimePickerDialog` (a required
`Title`, `TimePickerDialogDefaults.shape`, `TimePickerDialogDefaults.containerColor`).
Semantics, content, enabled state, hooks and accessibility meaning are
unchanged, so this is inside §16.4 (SPEC.md:2149-2156, "It does not require
pixel identity among toolkits or platforms") — but it is visible, and it is
Decision 4.

**Adjacent, pre-existing, not introduced here:** `var show by remember { … }` at
**:435** and **:464** is a bare `remember`, so an open picker dialog closes on
rotation. Worth a separate fix; the new `input` flag above is `rememberSaveable`
so this amendment does not add a second instance of the bug.

### Catalog product text that must be rewritten in the same change

These are what a user reads on the "Not supported" screen, and
`docs/PLAN-m3-catalog-verification.md:50-52` is explicit: "a false claim there is
a defect, not a comment nit."

| file:line | what is there now | why it must change |
|---|---|---|
| `jetpacs-m3-time-picker.el:34-36` (`--input-note`) | "…no display-mode member…" | false on ratification; the example becomes `:build` |
| `jetpacs-m3-time-picker.el:38-40` (`--toggle-note`) | "…no display-mode member and its dialog is built entirely by the Companion…" | false on ratification; the example becomes `:build` |
| `jetpacs-m3-time-picker.el:16-23` (Commentary) | "…there is no display-mode member and no slot in that Companion-built dialog…" | false on ratification |
| `jetpacs-m3-time-picker.el:42-49` (`--picker` docstring) | "the Companion opens an **AlertDialog** holding an M3 TimePicker with OK and Cancel" | false once `RenderTimeButton` moves to `TimePickerDialog` — this one is on a **supported** example, so it drifts silently |
| `jetpacs-m3-date-pickers.el:20-22` (Commentary) | "The other three exist to demonstrate something **neither node has a member for**: a per-day SelectableDates predicate, **DisplayMode.Input**, and a two-ended range" | half-false: `date_button` gains the member; the surviving gap is typed entry on the **inline** node |
| `jetpacs-m3-date-pickers.el:92` (`DateInputSample` reason) | "The date_button node has no display-mode member: … and month_grid draws a calendar only." | first clause becomes false; **rewrite to rest on `month_grid` alone — do not delete it** |

New builders for the two examples that do get unblocked:

```elisp
(defun jetpacs-m3-time-picker--input ()
  "Upstream TimeInputSample: the same \"Set Time\" button, text-field dialog."
  (jetpacs-time-button "Set Time" (jetpacs-m3-demo "Entered time")
                       :display-mode "input"))

(defun jetpacs-m3-time-picker--switchable ()
  "Upstream TimePickerSwitchableSample: the clock dial plus the mode toggle."
  (jetpacs-time-button "Set Time" (jetpacs-m3-demo "Entered time")
                       :display-mode "switchable"))
```

### Unblocks

**2 examples, both sole-gap, both currently `:unsupported` — corrected down from
the draft's claim of 3, and from the ledger's.**

| module | example | current reason string | with #165 |
|---|---|---|---|
| `time-picker` | `TimeInputSample` | `jetpacs-m3-time-picker.el:34-36` (`--input-note`) | `(jetpacs-time-button "Set Time" … :display-mode "input")` |
| `time-picker` | `TimePickerSwitchableSample` | `jetpacs-m3-time-picker.el:38-40` (`--toggle-note`) | `(jetpacs-time-button "Set Time" … :display-mode "switchable")` |

Both are **G-31**. `time-picker` reaches 3/3.

**Still blocked — `date-pickers/DateInputSample`. G-30 unblocks ZERO examples.**

The draft, and `docs/AUDIT-m3-blockers-2026-08-02.md:230`, both claim G-30
unblocks `DateInputSample`. It does not. Upstream is an **inline** picker, not a
dialog:

```kotlin
// androidx …/samples/DatePickerSamples.kt:238-248
fun DateInputSample() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val state = rememberDatePickerState(initialDisplayMode = DisplayMode.Input)
        DatePicker(state = state, modifier = Modifier.padding(16.dp))
        Text("Entered date timestamp: ${state.selectedDateMillis ?: "no input"}", …)
    }
}
```

The house shape for an inline date picker is `month_grid`, not `date_button` —
`jetpacs-m3-date-pickers.el:11-18` draws the line itself ("`date_button' IS M3's
DatePickerDialog … `month_grid' is the inline calendar"), and the sibling
`DatePickerSample` is recreated at `:33-49` with `jetpacs-month-grid` inside a
`jetpacs-column`, which is exactly the shape `DateInputSample` needs.
`date_button :mode "input"` would put the same M3 field behind a button that
opens a dialog: the right widget on the wrong screen. And `RenderMonthGrid`
(`VisualizationNodes.kt:282+`) is a hand-rolled header/weekday/day grid, not M3's
`DatePicker`, so the typed field is not reachable from it either.

The reason string at `:92` therefore does **not** become false — only its first
clause does. Its operative half, "and month_grid draws a calendar only", still
holds. Rewrite it to rest on the inline node alone; do not delete it.

**Additionally needed, by G-id: none exists.** The ledger has no gap for typed
date entry on the inline node. `G-61` is `month_grid.min_date`/`max_date`/
`disabled_weekdays`, `G-62` is `range_start`/`range_end` — neither is this. A
`month_grid` text-entry member (or a decision to render `month_grid` through M3's
`DatePicker` so `DisplayMode` becomes reachable) has to be **filed as a new gap**
before `date-pickers` can pass 5/5. Correct the ledger at
`AUDIT-m3-blockers-2026-08-02.md:230` in the same pass.

So: G-31 = 2 examples. G-30 = 0 examples, and closes a real wire gap anyway
(Emacs cannot choose the dialog's opening display) — which is Decision 1.

---

**Design decision 1 of 4: keep `date_button.mode`, or defer it.**

| | shape | for | against |
|---|---|---|---|
| **A (recommended, drafted)** | ship `date_button.mode` now | One argument, one import, zero risk; closes a genuine expressive gap the ledger already numbered (G-30); lets the date and time halves land as one coherent §17.4 edit. | Clears **no** catalog example. `DisplayMode.Input` is already reachable on device via M3's own pencil toggle, so the member buys only *which display the dialog opens on*. |
| **B** | ship the `time_button` half only; defer G-30 until the inline gap is filed | The amendment's payload is then exactly its yield; the date side gets designed together with the `month_grid` member `DateInputSample` actually needs, which may want a shared vocabulary. | Leaves a one-line capability unshipped for an unknown interval, and Emacs still cannot open a date dialog on typed entry. |

**Design decision 2 of 4: one member name or two.** *(Moot if 1B.)*

| | shape | for | against |
|---|---|---|---|
| **A (recommended, drafted)** | `date_button.mode` ∈ `calendar\|input`; `time_button.display_mode` ∈ `picker\|input\|switchable` | The ranges are disjoint and the semantics differ (date = initial display under an unconditional toggle; time = the dialog's construction). Distinct names make `:display-mode "calendar"` and `:mode "switchable"` *constructor errors* under `jetpacs--check-enum` instead of §12 rule 6 silent fallbacks. Matches the ledger (G-30/G-31). | Two registry names for one idea. |
| **B** | `display_mode` on both, ∈ `calendar\|input` and `picker\|input\|switchable` | One name, one `:display-mode` keyword across both constructors. | Same member name with disjoint ranges, and it advertises an interchangeability that does not exist. (Note this is *not* a `field_types` argument either way — neither option touches `field_types`.) |

**Design decision 3 of 4: how `switchable` is expressed.**

| | shape | for | against |
|---|---|---|---|
| **A (recommended, drafted)** | `switchable` is a third value of `time_button.display_mode` | One member. `switchable` genuinely selects a different *dialog construction*, not a different initial mode, so it belongs on the same axis. | Cannot express "start on input, with a toggle" — no catalog example wants it. |
| **B** | `display_mode` ∈ `picker\|input` plus a boolean `time_button.mode_toggle` (default `false`) | Orthogonal; expresses all four combinations. | A second member for one example; and `date_button`'s toggle is unconditional, so the symmetry it buys is only apparent. |

**Design decision 4 of 4 — the one that moves pixels: the dialog container.**

| | shape | for | against |
|---|---|---|---|
| **A (recommended, drafted)** | `RenderTimeButton` uses `TimePickerDialog` for **all three** values | One code path. Matches upstream exactly (all three samples use `TimePickerDialog`), so `TimePickerSample` gets *closer* to fidelity, not further. `TimePickerDialogDefaults` shape/colour are the M3-correct container for a time picker, which `AlertDialog` never was. | Every existing default `time_button` visibly changes: it gains a headline (`title` has no default) plus M3 dialog shape and container colour. Legal under §16.4, but no author asked for it and no gate will catch a regression. |
| **B** | keep `AlertDialog` for `picker`; use `TimePickerDialog` only for `input`/`switchable` | Zero visible change for existing traffic; the new container appears only where a new member asked for it. | Forks the renderer into two dialog shapes for one node type, so the same app shows two different time dialogs depending on a presentational member — and leaves `TimePickerSample` recreated in the *wrong* container forever. |

---

## #166 — slider presentation: `track`, `color` / `color_end`, `thumb_icon`

Covers ledger gaps **G-32**, **G-33**, **G-34** (`docs/AUDIT-m3-blockers-2026-08-02.md:234-238`).
Drafted against `ebp/SPEC.md` §17.4 and `ebp/contract.json` on branch `m3-fidelity`.

**⚠ Two design decisions required** — see the tables at the end. The draft below is written as **A** for both.

---

### SPEC-CHANGES row (ready to paste)

> | 166 | 2026-08-02 | §17.4 (cross-ref §12 rule 6, §16.4, §16.6, §17.2; contract) | **Slider presentation: `track`, `color`/`color_end`, `thumb_icon`.** The `slider` row has carried the same seven members since the vocabulary was written — `id`, `on_change`, `value`, `min`, `max`, `values`, `enabled` — every one of which describes the node's *domain* and none of which describes how it is drawn. `InputNodes.kt:396-407` and `:416-425` accordingly call the plain `Slider(value, onValueChange, …)` overload with no `colors`, no `track` and no `thumb` argument, so nine of the eleven upstream M3 slider samples are `:unsupported` and five of them are blocked wholly or partly on presentation the wire cannot ask for — the shipped reason strings say exactly that ("The slider node has no track member…", "…no thumb, track or colors member…", `emacs/apps/m3-catalog/jetpacs-m3-sliders.el:38-46,116`). Four OPTIONAL members close the presentational half of that hole. `slider.track` is an enum, `default` (the default) or `centered`; `centered` grows the active track out from the midpoint of the drawn track in both directions instead of from its start — `SliderDefaults.CenteredTrack`, an expressive API that reached the classpath only with the material3 1.5.0-alpha16 bump in `ed86191`. It is the entire subject of `CenteredSliderSample` and it is **not** derivable from the numbers: a `-50..50` slider draws its active track from `-50` today no matter what those numbers mean, because the growth origin is a track property and not a value property. An unrecognized `track` is a safe fallback under Section 12 rule 6 — rendered as `default`, never a whole-surface `1201` — exactly as `text.style` falls back to `body` and `dialog.style` to `dialog` under §16.1's carve-out. `slider.color` is a §16.6 Color tinting the node's accent, meaning its thumb and its active track together, which is literally `SliderDefaults.colors(thumbColor = it, activeTrackColor = it)` — the call `SliderWithCustomTrackAndThumbSample` makes. `slider.color_end` is a Color tinting the second thumb of a two-thumb slider and MUST be ignored by a slider presenting one thumb, so it is legal and inert on every slider that exists today and becomes authorable-with-effect the moment the two-thumb form lands, with no second edit to this row. `slider.thumb_icon` is an identifier drawn in the thumb slot tinted with `color`; it is a **name and not a drawing** because `IconMap.get` is the only path by which a vector reaches the device, and the wire has no vector type. Every default is today's rendering exactly: with all four omitted the Companion keeps the same `Slider` overload with the same arguments it passes now, so no existing surface, golden, fixture or `state.changed` value changes meaning, and no `on_change` payload is affected — these members are presentation only and are never reported back. Two guards are stated rather than left to the implementer. First, an authored colour MUST NOT defeat the `enabled: false` disabled affordance §17.4 already requires, and that guard covers the `thumb_icon` tint as well as the thumb and track; M3 keeps the `disabled*` slots of `SliderColors` separate from the enabled ones, so overriding `thumbColor`/`activeTrackColor` leaves the disabled presentation untouched and only the icon tint needs the explicit `enabled`-first branch. Second, a `thumb_icon` is decorative — it MUST NOT become the node's §16.4 accessible label, MUST NOT alter the reported value or range, and an unresolved identifier MUST still leave a **grabbable** thumb: §17.2's "or nothing" option is unavailable here because the thumb is the node's only drag target, and a slider whose thumb rendered as nothing would be a control with no affordance. Additive throughout; a Companion that ignores all four members renders every conforming slider as it does today. | contract `node_schema.slider.optional += ["track","color","color_end","thumb_icon"]`; `enums."slider.track" = ["default","centered"]`; `field_types += {"color_end":"color","thumb_icon":"identifier"}`; regenerate `companion/wire/…/Vocabulary.kt` (`tools/gen-vocabulary.py`) and `emacs/jetpacs-vocabulary.el` (`tools/gen-jetpacs-vocabulary.py`); `emacs/jetpacs-widgets.el` `jetpacs-slider` gains four keywords and a `jetpacs--slider-tracks` defconst; `goldens/widgets.golden` += lines 75, 76; no new `validate.py` arm and no new `SpecValidator.kt` arm | |

---

### SPEC.md edits

**1. §17.4, the input-node table — the `slider` row.**

Current text (`ebp/SPEC.md:2424`), verbatim:

> ```
> | `slider` | `id: identifier`, `on_change: ActionDescriptor` | `value`, `min`, `max`, `values`, `enabled` |
> ```

Replacement:

> ```
> | `slider` | `id: identifier`, `on_change: ActionDescriptor` | `value`, `min`, `max`, `values`, `track`, `color`, `color_end`, `thumb_icon`, `enabled`. `track` is `default` (default) or `centered`; unknown values fall back to `default`. |
> ```

**2. §17.4, the member-type paragraph — `color_end` and `thumb_icon` are typed inline because §17.1's name rules cover `color` and `icon`, not `color_end` and `thumb_icon`.**

Current text (`ebp/SPEC.md:2437-2438`), verbatim:

> ```
> distinct option values when `multi_select` is true. Slider `value`, `min`, and
> `max` are finite numbers and `values` is an array of finite numbers. Date and time values use the
> ```

Replacement:

> ```
> distinct option values when `multi_select` is true. Slider `value`, `min`, and
> `max` are finite numbers and `values` is an array of finite numbers;
> `slider.color_end` is a Color and `slider.thumb_icon` is an identifier. Date and time values use the
> ```

(`slider.color` needs no inline type — §17.1 at `:2225` already types every field named `color` as a Color. `track` needs none either: the table row states its domain, as `button.variant` and `text.style` do.)

**3. §17.4 — three new paragraphs, inserted immediately after the slider paragraph and before the `### 17.5 Visualization nodes` heading.**

Current text (`ebp/SPEC.md:2512-2520`), verbatim — this paragraph is **not modified**, it is the anchor:

> ```
> For a continuous `slider`, `min` defaults to `0`, `max` to `1`, and `value` to
> `min`; `min` MUST be less than `max` and `value` MUST be in the closed range. A
> discrete slider supplies `values` as two or more strictly increasing, distinct
> JSON numbers; it MUST omit `min` and `max`, and `value` MUST equal one listed
> number under Section 4.3 or defaults to the first. The Companion MUST return the
> exact selected authored number, avoiding toolkit-specific step arithmetic. It
> SHOULD dispatch
> `on_change` once when the user commits a gesture, not for every intermediate
> pixel.
> ```

**How to apply:** insert a **new blank line after line 2520**, then the three paragraphs below. The file's existing blank line 2521 stays where it is and remains the separator before `### 17.5 Visualization nodes` at 2522. (Without the added blank line the first new paragraph merges into the anchor paragraph, which this edit promises not to modify.)

> ```
> `slider.track` selects where the active track grows from. `default` grows it
> from the start of the track; `centered` grows it out from the midpoint of the
> drawn track in both directions, so a position below the midpoint fills toward
> the start and a position above it fills toward the end. The midpoint is a point
> on the track: on a discrete slider it need not coincide with a listed number,
> which is harmless because `track` changes nothing that can be selected.
> `track` is presentation only: it changes no value, no domain, no dispatch, and
> nothing reported in `state.changed`. It defaults to `default`, which is the
> rendering of a slider that omits it. An unrecognized value is a member with a
> safe fallback under Section 12 rule 6: the Companion MUST render it as
> `default` and MUST NOT reject the surface.
>
> `slider.color` tints the node's accent — its thumb and its active track — and
> when absent the Companion keeps its own slider accent, so an omitted `color`
> renders exactly as before this member existed. `slider.color_end` tints the
> second thumb of a slider that presents two; a slider presenting a single thumb
> MUST ignore it. Neither member may defeat the disabled affordance: when
> `enabled` is `false` the Companion MUST present its disabled presentation as
> required above — including the tint of any `thumb_icon` — in preference to an
> authored colour.
>
> `slider.thumb_icon` names an icon drawn in place of the thumb, tinted with
> `slider.color` where present and with the thumb colour otherwise, subject to
> the disabled rule above. It is decorative: it MUST NOT be used as the node's
> accessible label under Section 16.4, and it MUST NOT change the slider's
> value, range, step behavior, or accessible value. Section 17.2's
> unresolved-icon rule applies with one narrowing — a slider MUST still present
> a grabbable thumb, so an unresolved `thumb_icon` MUST render either the
> placeholder or the Companion's default thumb, never nothing.
> ```

---

### Artifact changes

**`ebp/contract.json`** — three edits, all additive.

1. `node_schema.slider.optional` (`ebp/contract.json:444-456`). Current:

   ```json
       "slider": {
         "required": [
           "id",
           "on_change"
         ],
         "optional": [
           "value",
           "min",
           "max",
           "values",
           "enabled"
         ]
       },
   ```

   Replacement:

   ```json
       "slider": {
         "required": [
           "id",
           "on_change"
         ],
         "optional": [
           "value",
           "min",
           "max",
           "values",
           "track",
           "color",
           "color_end",
           "thumb_icon",
           "enabled"
         ]
       },
   ```

2. `field_types` — two entries. After `"bg": "color",` (`ebp/contract.json:544`) insert:

   ```json
       "color_end": "color",
   ```

   and after `"icon": "identifier",` (`ebp/contract.json:522`) insert:

   ```json
       "thumb_icon": "identifier",
   ```

   `field_types` is a **flat bare-name → type map**: these two rows type the names `color_end` and `thumb_icon` *globally*, for every node type that ever adopts them. It cannot express node scoping and this amendment does not pretend otherwise. What limits the blast radius today is the consumer, not the map: `SpecValidator.validateNode` runs its `checkScalarFieldType` loop over `row.required + row.optional` only (`SpecValidator.kt:545`), so the check fires on `slider` and nowhere else until another schema row lists the same name. That is a real, wanted gain — see the `validate.py` bullet below.

   `track` gets **no** `field_types` entry, following the `variant` / `style` / `align` precedent: enum-valued fields are typed by their `enums` key, and `field_types` carries only `keyboard` as a legacy `"enum"` row (`:527`).

3. `enums` — one entry, inserted after the `"text_input.keyboard"` block (`ebp/contract.json:690-697`) and before `"align_self"`, keeping node-scoped enums in §17.4 table order:

   ```json
       "slider.track": [
         "default",
         "centered"
       ],
   ```

   **What this entry does and does not do.** It is documentation carried in the contract. Nothing reads it: `validate.py` never mentions `enums`, neither generator projects it, and `gen-vocabulary.py` stores only the type *name* `"enum"` for a `field_types` row. No suite anywhere checks that a `track` string is one of these two. That is deliberate and consistent with §12 rule 6 — an out-of-domain `track` is a fallback, not a rejection — but this amendment must not be read as adding validation it does not add.

**`ebp/goldens/widgets.golden`** — append two lines (the file currently ends at index `74`; keys are canonically sorted, matching the corpus):

```
75 {"color":"#ff0000","id":"pan","max":50,"min":-50,"on_change":{"action":"pan.set"},"t":"slider","thumb_icon":"favorite","track":"centered","value":0}
76 {"color":"primary","color_end":"tertiary","id":"trim","on_change":{"action":"trim.set"},"t":"slider","track":"centered","value":0,"values":[-50,-25,0,25,50]}
```

Line 75 is the continuous arm (hex Color, `centered`, `thumb_icon`); line 76 is the discrete arm (theme-role Color, `centered` over `values`, and `color_end` legal-while-inert). Both pass `check_slider_values` unchanged: 76 has five strictly increasing values, omits `min`/`max`, and its `value` `0` is a listed number under §4.3.

`track: "centered"` on line 76 is kept deliberately. No upstream sample pairs `centered` with a discrete range, but the combination is legal under the §17.4 text above — the midpoint is a point on the drawn track and is defined independently of what is selectable — and the golden corpus exists to lock *legality*, which is precisely the pair a later implementer is most likely to reject by accident.

**`ebp/validate.py`** — **no new arm required**, but the reason is narrower than "nothing validates these".

- `check_node` derives the legal key set from `NODE_SCHEMA` at `validate.py:279-287`, so the four new members become legal the moment the contract lands. `check_slider_values` (`:238-250`) is untouched and still governs `values`/`min`/`max`/`value`; the per-type dispatch that calls it is `:288-294`.
- `validate.py` itself reads neither `enums` nor `field_types` — `grep FIELD_TYPES ebp/validate.py` is empty — so on the Python side nothing type-checks `color_end` or `thumb_icon` and nothing checks the `track` domain.
- The **JVM** validator is different and the draft previously got this wrong. `SpecValidator.checkScalarFieldType` (`SpecValidator.kt:467-497`) *does* enforce `FIELD_TYPES`, dispatched at `:545` over the node's own schema row. So the two `field_types` rows are not decoration: after the regeneration below, `{"t":"slider","thumb_icon":42,…}` raises `1201 content-invalid` at `path.thumb_icon` via the `"identifier"` arm (`:473-477`, which also enforces `IDENTIFIER` and `MAX_IDENTIFIER_OCTETS`), and a non-string `color_end` raises via the `"color"` arm (`:478`). `track` has no row and therefore falls to `else -> Unit` (`:495`) — a non-string `track` reads as `""` and takes the §12 rule 6 fallback, which is the intended behaviour.
- The `widgets.golden` node-type coverage floor (`validate.py:757-762`) is already satisfied by lines 54/55.

**Generated mirrors — REQUIRED, or the JVM and elisp suites go red.** `companion/wire/…/Vocabulary.kt:61` and `emacs/jetpacs-vocabulary.el:68` are generated from `contract.json` and pinned by `VocabularyDriftTest.generatedVocabularyMatchesContract` (`companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire/SurfaceStoreTest.kt:732-756`, which asserts `node_schema` key-for-key at `:738-745` **and** `field_types` key-for-key at `:752-755`) and by `jetpacs-widgets/catalog-node-schema` (`test/jetpacs-widgets-test.el:889-905`). Regenerate, do not hand-edit:

```
python3 tools/gen-vocabulary.py
python3 tools/gen-jetpacs-vocabulary.py
```

Resulting rows:

```kotlin
"slider" to NodeRow(setOf("id", "on_change"),
    setOf("value", "min", "max", "values", "track", "color", "color_end", "thumb_icon", "enabled")),
```

```elisp
("slider" ("id" "on_change")
 ("color" "color_end" "enabled" "max" "min" "thumb_icon" "track" "value" "values"))
```

(The elisp mirror sorts both lists with `string<`; the order above is that sort.)

**`emacs/jetpacs-widgets.el`** — `jetpacs-slider` (`:1171-1201`) is hand-written and will silently drop any keyword it does not name, so regenerating `jetpacs-vocabulary.el` makes the members legal but **not authorable**. That is exactly the failure mode that left `text_input.hint` a dead member. Two edits:

1. Beside the other input defconsts at `:985`:

   ```elisp
   (defconst jetpacs--slider-tracks '("default" "centered"))
   ```

2. In `jetpacs-slider`, extend the lambda list, add the checks in the house form, and pass the wire names through `jetpacs--node`:

   ```elisp
   (cl-defun jetpacs-slider (id on-change &key value min max values
                                 track color color-end thumb-icon enabled)
     ...
     (when track
       (setq track (jetpacs--check-enum track jetpacs--slider-tracks ":track")))
     (when color (jetpacs--check-color color))
     (when color-end (jetpacs--check-color color-end))
     (when thumb-icon (jetpacs--check-identifier thumb-icon ":thumb-icon"))
     ...
     (jetpacs--node "slider"
                    :id id :on_change on-change :value value
                    :min min :max max :values (and values (vconcat values))
                    :track track :color color :color_end color-end
                    :thumb_icon thumb-icon :enabled enabled))
   ```

   The `setq` re-assignment is not optional: `jetpacs--check-enum` (`:253`) *returns* the normalized string, and the established call form is `(setq variant (jetpacs--check-enum variant jetpacs--button-variants ":variant"))` at `:995`. Dropping the `setq` would put the raw symbol `centered` on the wire instead of the string, making `:track 'centered` silently unauthorable while `:track "centered"` worked.

`WidgetsGoldenReplayTest.everyWidgetsGoldenLineValidates` (`companion/wire/src/jvmTest/…/WidgetsGoldenReplayTest.kt:50-63`) replays the two new golden lines through `SpecValidator` and passes on the regenerated `Vocabulary.kt` with no change to `SpecValidator.kt`'s `"slider" ->` arm (`:562-603`), which validates only the numeric domain.

---

### Companion implementation

All in `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/InputNodes.kt`, `RenderSlider` (`:377-427`). Verified by `javap` against the unpacked `androidx.compose.material3:material3-android:1.5.0-alpha16` classes:

- `SliderDefaults.CenteredTrack(sliderState, modifier, enabled, colors, drawStopIndicator, drawTick, thumbTrackGapSize, trackInsideCornerSize, trackCornerSize)` — **present**, `SliderDefaults.CenteredTrack-7LSsfP0`. It is the **only** call this amendment adds that carries `@ExperimentalMaterial3ExpressiveApi`, so `RenderSlider` needs `@OptIn(ExperimentalMaterial3ExpressiveApi::class)`. The file already uses per-function `@OptIn` (`:243`, `:431`, `:460`); there is no module-wide opt-in. Note this would be the **first** expressive opt-in anywhere in the Companion — `grep -rn ExperimentalMaterial3ExpressiveApi companion/ --include=*.kt` is currently empty. Internally `CenteredTrack` is `TrackImpl(… isCentered = true)`, whose draw path takes `centerAxis = center.x` from the `DrawScope`, which is why the §17.4 text above states the rule geometrically rather than in terms of `min`/`max` or of indices.
- `SliderDefaults.Track(sliderState, modifier, enabled, colors, …)` — present (`Track-4EFweAY`), **not** expressive.
- `SliderDefaults.Thumb(interactionSource, modifier, colors, enabled, thumbSize)` — present (`Thumb-9LiSoMs`), **not** expressive.
- `SliderDefaults.colors(thumbColor, activeTrackColor, activeTickColor, inactiveTrackColor, inactiveTickColor, disabledThumbColor, disabledActiveTrackColor, disabledActiveTickColor, disabledInactiveTrackColor, disabledInactiveTickColor)` — present (`colors-q0g_0yA`, ten `long`s). The five `disabled*` slots are **separate parameters with their own defaults**, which is why overriding `thumbColor`/`activeTrackColor` cannot defeat the disabled affordance for the thumb or the track. `SliderColors.thumbColor` and `.disabledThumbColor` are public getters (`getThumbColor-0d7_KjU`, `getDisabledThumbColor-0d7_KjU`), so the thumb-icon tint can and MUST follow `enabled` explicitly — that is the one place the disabled rule needs code rather than a default.
- The slotted overload exists on the `value`/`onValueChange` form the Companion already uses: `Slider(value: Float, onValueChange: (Float) -> Unit, modifier, enabled, onValueChangeFinished, colors, interactionSource, steps, thumb: @Composable (SliderState) -> Unit, track: @Composable (SliderState) -> Unit, valueRange)` — confirmed from the alpha16 composable source-info string `C(Slider)N(value,onValueChange,modifier,enabled,onValueChangeFinished,colors,interactionSource,steps,thumb,track,valueRange)`. It carries no `Deprecated` attribute and no expressive marker in alpha16. **No move to `rememberSliderState` is needed**, so the seed/epoch machinery at `:395` and `:411-415` and the exact-authored-number dispatch at `:400-402` are untouched. (Pass every argument by name: androidx-main has since reordered `steps` and `valueRange` on this overload and retained the alpha16 ordering as a `DeprecationLevel.HIDDEN` binary-compat shim, so positional calls would not survive the next bump.)

**Verified: `track` really is track-only.** The concern that switching to the slotted overload silently downgrades the thumb does not hold. Disassembling alpha16's `SliderKt` and mapping each `Thumb-*` call site to its enclosing synthetic lambda: `Slider$lambda$1` (default thumb of the simple `value`/`onValueChange` overload the Companion calls **today**), `Slider$lambda$5` (default thumb of the **slotted** overload this amendment moves to) and `Slider$lambda$10` (default thumb of the `SliderState` overload) all invoke `SliderDefaults."Thumb-9LiSoMs"` — the stateless form. The `SliderState`-aware `Thumb-HwbPF3A` appears exactly once in the file, inside `VerticalSlider$lambda$1`, i.e. it is `VerticalSlider`'s default and belongs to G-58, not here. Upstream's own `CenteredSliderSample` likewise passes `SliderDefaults.Thumb(interactionSource = interactionSource)`. So the sketch below reproduces the Companion's current thumb byte-for-byte, and authoring `track: "centered"` changes the track and only the track.

Shape of the change:

1. `RenderSlider` reads three members beside the existing ones (`:379-382`):
   `val track = node.stringOr("track")`, `val thumbIcon = node.stringOr("thumb_icon")`,
   `val accent = resolveColor(node.stringOr("color").takeIf { it.isNotEmpty() })` — `resolveColor` is `ColorModel.kt:37`, the same helper `RenderIcon` uses at `ContentNodes.kt:245`, and it already implements §16.6 including the legible fallback for an unknown role.
2. `val colors = accent?.let { SliderDefaults.colors(thumbColor = it, activeTrackColor = it) } ?: SliderDefaults.colors()`.
3. When `track != "centered"` **and** `thumbIcon` is empty, call the **existing** overload exactly as today, adding only `colors = colors`. With `color` absent this is `SliderDefaults.colors()`, i.e. the argument's own default — byte-identical rendering to `06fd9cd` traffic.
4. Otherwise call the slotted overload with the same `value` / `onValueChange` / `onValueChangeFinished` / `valueRange` / `steps` / `enabled` / `modifier` arguments plus a hoisted `val interactionSource = remember { MutableInteractionSource() }` and:

   ```kotlin
   track = {
       if (trackCentered) SliderDefaults.CenteredTrack(sliderState = it, colors = colors, enabled = enabled)
       else               SliderDefaults.Track(sliderState = it, colors = colors, enabled = enabled)
   },
   thumb = {
       if (thumbIcon.isEmpty())
           SliderDefaults.Thumb(interactionSource = interactionSource, colors = colors, enabled = enabled)
       else
           Icon(IconMap.get(thumbIcon), contentDescription = null,
                modifier = Modifier.size(ButtonDefaults.IconSize),
                tint = if (enabled) (accent ?: colors.thumbColor) else colors.disabledThumbColor)
   }
   ```

   `trackCentered` is `track == "centered"`; every other string, including an unknown one and the empty string a non-string `track` reads as, takes the `else` arm — the §12 rule 6 fallback, implemented by construction rather than by a guard that can be forgotten.

   The `tint` expression is **`enabled`-first on purpose**. Written the other way round (`accent ?: if (enabled) … else …`) the elvis short-circuits on a non-null `accent`, so a slider with `enabled: false` **and** `color` **and** `thumb_icon` would draw the icon at full authored strength and never reach `disabledThumbColor` — precisely the case the §17.4 paragraph above forbids. The thumb and the track need no such branch because `SliderDefaults.colors(thumbColor = …, activeTrackColor = …)` leaves the five `disabled*` slots at their own defaults; the icon is the one hole, and this is where it is closed.
5. `IconMap.get` (`IconMap.kt:89-105`) never fails: it resolves Outlined → AutoMirrored → Filled and otherwise returns `Icons.Outlined.HelpOutline` (`:104`, already annotated "SPEC 17.2: harmless placeholder"). The "grabbable thumb" rule is therefore already satisfied with no new code, and no `getOrNull` variant is needed.
6. `contentDescription = null` on the icon keeps §16.4's accessible label derivation on the slider itself — `Slider` supplies its own `progressSemantics`, and the icon must not enter it.
7. **`color_end` is read by no code in this amendment.** Steps 1-6 read `track`, `thumb_icon` and `color` only. `color_end` lands as a legal, type-checked, inert member; the Companion parses it and ignores it, which is what "a slider presenting a single thumb MUST ignore it" requires of every slider that can exist before G-57. See Design Decision 2.

Both `Slider` call sites (`:396-407` discrete, `:416-425` continuous) take the same treatment; the two arms differ only in `valueRange`/`steps` and in what `onValueChangeFinished` dispatches, neither of which this amendment touches.

**No Compose UI test can see any of this.** The Companion has no Compose UI test infrastructure, and all four members are pure rendering with no observable wire effect. `SpecValidator` will type-check `thumb_icon` and `color_end` and the goldens will lock their legality, but nothing in the repo can distinguish a Companion that honours `track`/`color`/`thumb_icon` from one that parses and drops them. Every MUST in the new §17.4 prose — the disabled tint, the grabbable thumb, the non-label — is unenforced by CI on ratification day. `align_self`, `text_input.hint` and half of `surface.elevation` all shipped green through the same hole.

**Collision note for whoever lands G-58 (`slider.orientation`).** That gap requires dropping the unconditional `.fillMaxWidth()` at `:407` and `:425` (AUDIT:332). This amendment leaves both in place. Landing #166 first is free; in either order the G-58 edit touches the same two lines. G-58 also moves to `VerticalSlider`, whose default thumb *is* the expressive `Thumb-HwbPF3A` — a difference to handle there, not here.

---

### Unblocks

**Cleared outright (2)** — this amendment is the sole remaining gap:

| slug | component | gap | note |
|---|---|---|---|
| `CenteredSliderSample` | sliders | G-32 | `:min -50 :max 50 :value 0 :track "centered"`. Upstream is `rememberSliderState(valueRange = -50f..50f)` with `thumb = { SliderDefaults.Thumb(interactionSource = interactionSource) }` and `track = { SliderDefaults.CenteredTrack(sliderState = sliderState) }` — the default thumb and the centered track, which is exactly what step 4 produces. Upstream's live `"%.2f".format` readout is authored at the start value, the convention the two shipped `:build` recreations already use (`jetpacs-m3-sliders.el:50-56`). |
| `SliderWithCustomTrackAndThumbSample` | sliders | G-33 | `:min 0 :max 100 :color "#ff0000"`. Upstream's custom `thumb`/`track` slots are `SliderDefaults.Thumb`/`.Track` **with the same `colors = SliderDefaults.colors(thumbColor = Color.Red, activeTrackColor = Color.Red)`** — i.e. the default composables, so `color` reproduces the sample exactly and step 3's existing-overload path suffices. Same readout convention. |

**Advanced but still blocked (3)** — the presentational half lands here, the rest is another gap:

| slug | still needs | what #166 supplies |
|---|---|---|
| `VerticalCenteredSliderSample` | **G-58** `slider.orientation` | the `centered` track; `:values '(-50 -40 … 50)` is upstream's `steps = 9` over `-50f..50f`, and the 11-element list centres on the listed `0` |
| `SliderWithCustomThumbSample` | **G-59** `slider.value_label` | the `Icon` thumb (`thumb_icon "favorite"`, `color "#ff0000"`); the `Label`/`PlainTooltip` live readout cannot be authored because `:419` dispatches only at `onValueChangeFinished` |
| `RangeSliderWithCustomComponents` | **G-57** `value_end`, **G-59** | `color` (start thumb + active track) and `color_end` (end thumb) — the `SliderDefaults.colors` pair upstream builds, modulo the blue/red split Design Decision 1 gives up |

Two ledger corrections to make when the ledger is next touched, so ratifying #166 does not leave it self-contradictory:

- **Reason strings.** `jetpacs-m3-sliders--track-note` ("no thumb, track or colors member") and the `CenteredSliderSample` string both become false on ratification; the `RangeSliderWithCustomComponents` string's "nor the labelled blue and green thumbs or the red active track" becomes half false.
- **Wrong dependency IDs.** `AUDIT:235` says `VerticalCenteredSliderSample` needs G-32 "(with G-44)" and `:237` says `SliderWithCustomThumbSample` needs G-34 "(with G-43)". G-43 and G-44 are the **scaffold top-bar** gaps — `scaffold.scroll_behavior` (`:268`) and `scaffold.top_bar_style` (`:275`) — nothing to do with sliders. The real co-requisites are **G-58** and **G-59**, confirmed by those gaps' own entries at `:332-333`, which list exactly these two slugs. The table above uses the correct IDs; the ledger should be fixed to match rather than left as a wrong ordering for someone to mine.

---

### Design decision 1 — the granularity of slider colour

`RangeSliderWithCustomComponents` uses **three** distinct colours (`startThumbAndTrackColors = SliderDefaults.colors(thumbColor = Color.Blue, activeTrackColor = Color.Red)` and `endThumbColors = SliderDefaults.colors(thumbColor = Color.Green)`). One `color` member cannot express Blue-thumb-on-Red-track.

| | shape | reproduces | cost |
|---|---|---|---|
| **A (recommended, drafted)** | `color` = thumb **and** active track together; `color_end` = second thumb | `SliderWithCustomTrackAndThumbSample` exactly (Red/Red). `RangeSliderWithCustomComponents` renders red/red/green rather than blue/red/green. `SliderWithCustomThumbSample`'s red icon also reddens the active track, which upstream leaves default. | 2 members; matches the house pattern where a node's `color` is its single accent (`text`, `icon`, `badge`, ChartSeries), and matches the one `SliderDefaults.colors(thumbColor = X, activeTrackColor = X)` call the catalog actually makes |
| **B** | `color` = thumb only; new `track_color` = active track; `color_end` = second thumb | all three samples pixel-for-pixel | 3 members and a per-part colour vocabulary no other node type has; `track_color` needs its own inline type and its own `field_types` row |

**Recommendation: A.** The blue/red split in that one sample is demo noise, not an M3 idiom, and B buys exact fidelity on one example at the price of a colour vocabulary that would then want copying to `switch`, `checkbox`, and `progress`. B remains a clean later addition — adding `track_color` afterwards would not change A's meaning.

Named so ratification is not later read as a fidelity promise: under A, neither `RangeSliderWithCustomComponents` nor `SliderWithCustomThumbSample` is pixel-exact. Separately and not fixable here, `thumb_icon "favorite"` resolves to `Icons.Outlined.Favorite` because `IconMap.get` tries Outlined before Filled (`IconMap.kt:93-98`), where upstream draws `Icons.Filled.Favorite`; no wire string can select a Filled vector.

### Design decision 2 — land `color_end` now, or with G-57

`color_end` is inert until a two-thumb slider exists (G-57 `slider.value_end`, a separate amendment).

| | | consequence |
|---|---|---|
| **A (recommended, drafted)** | land `color_end` now, defined as "the second thumb of a slider that presents two; a single-thumb slider MUST ignore it" | Self-consistent today (every slider has one thumb, so it is always ignored) and live the day G-57 lands, with no second edit to the §17.4 row or the schema. Costs one legal-but-inert member and one golden field. |
| **B** | defer `color_end` to G-57's amendment | Nothing on the wire is inert. Costs a second edit to the same row and schema, and splits one coherent colour story across two ratifications. |

**Recommendation: A.** The rule is stated in terms of *thumbs presented*, not in terms of an unratified member, so the SPEC text needs no forward reference and is complete as written.

Two things A does **not** hide. First, golden line 76 locks `color_end`'s *legality* and its scalar type, not its behaviour: nothing in any suite can catch a Companion that mis-implements it until G-57 lands. Second, `color_end` will cost G-57 more than one argument. `SliderColors` carries exactly **one** thumb colour — `javap` shows a single `getThumbColor-0d7_KjU()` — so G-57 cannot honour `color_end` by passing a second value into `SliderDefaults.colors(…)`. It must build a **second** `SliderColors` (`SliderDefaults.colors(thumbColor = <color_end>)`) and inject it through `RangeSlider`'s `endThumb` slot, which is exactly what upstream's `RangeSliderWithCustomComponents` does with `endThumbColors`. That is a real constraint on G-57 and it is recorded here rather than discovered there.

---

## #167 — assorted input and layout members (`box.on_long_tap`, `column.reverse_scroll`, `checkbox.stroke`, `switch.thumb_icon`, `menu.initial_scroll`, MenuItem `supporting_text`/`trailing_icon`/`trailing_text`)

Covers ledger gaps **G-35, G-36, G-37, G-38, G-39, G-40**
(`docs/AUDIT-m3-blockers-2026-08-02.md:240-254`). Drafted against
`ebp/SPEC.md` @ **`83d6e08`** — the `ebp/` submodule HEAD on `m3-fidelity`,
whose `SPEC-CHANGES.md` tops out at **#152**. Companion @ `9b57b35`,
material3 `1.5.0-alpha16` (raised in `ed86191`).

> **Numbering.** The next free slot in this tree is 153. This amendment keeps
> **167** because 153–166 are the sibling drafts of the same m3-fidelity
> batch, and renumbering one of them in isolation collides with the rest;
> #153/#154/#155 additionally exist on the unmerged `rf-4a` line and are not
> in this worktree. Ratify the batch in one pass, or renumber the whole batch
> together. An earlier revision of this draft cited `37fb456`, which is not an
> object in either the superproject or the submodule; that citation was wrong.

**Every renderer and API claim below was re-verified against the file and the
artifact.** The contract delta, the five appended golden lines, and the two
`validate.py` arms were applied to a scratch copy of `ebp/` and run:
`OK: 40 frames, 80 widget lines, 7 hypertext nodes, 17 wire fixtures x3
chunkings validate`. No file in `ebp/` was edited.

### SPEC-CHANGES row (ready to paste)

> | 167 | 2026-08-02 | §17.3, §17.4 (cross-ref §12 rule 6, §16.1, §16.4; contract) | **Six members for the interactions the renderer's own shape already implied.** Each closes a gap where the Compose call the Companion already makes has a parameter the wire cannot name. (1) `box.on_long_tap`, an optional ActionDescriptor: today the ONLY nodes that can carry a long press draw their own chrome — `card`'s `ElevatedCard` plus a 16 dp inset (`LayoutNodes.kt:330-345`) and `collapsible`'s forced chevron header (`:356-391`) — so a flat, container-less row cannot be long-pressed at all, while `RenderBox` (`LayoutNodes.kt:186-204`) reaches for `Modifier.clickable` at `:200` exactly where `RenderCard` reaches for `Modifier.combinedClickable` at `:336-338`; the member is a keyword away and adds no chrome, which is the whole point. (2) `column.reverse_scroll`, boolean, default `false`, effective only alongside `scroll: true`: `RenderColumn` calls `it.verticalScroll(rememberScrollState())` at `LayoutNodes.kt:150`, and the fourth parameter of `Modifier.verticalScroll(state, enabled, flingBehavior, reverseScrolling)` was never reachable, so a column that should open at its end and grow upward cannot be authored; reversal moves the scroll anchor and the gesture direction only — children still lay out in array order and `arrange`/`align`/`spacing` are untouched. (3) `checkbox.stroke`, an optional object `{width?, cap?, join?}` with `width` defaulting to the platform's own checkbox stroke width, `cap` to `butt` and `join` to `miter`: `RenderCheckbox` calls the plain `Checkbox` overload at `InputNodes.kt:201-205`, and 1.5.0-alpha16 carries a second, NON-experimental overload taking `checkmarkStroke`/`outlineStroke` (`CheckboxKt`, verified on the classpath) that nothing on the wire can select; `cap` and `join` shape the CHECKMARK only and the outline takes `width` alone, an asymmetry that is upstream's and is the visible subject of the sample, so a Companion that rounded both would render the wrong picture. (4) `switch.thumb_icon`, an identifier from the same vocabulary as `icon.name`: `RenderSwitch` passes no `thumbContent` at `InputNodes.kt:228-232`; the icon is drawn at `SwitchDefaults.IconSize` and ONLY while the live `checked` state is true, matching upstream's lambda, and it is decoration over a control that already has an accessible label, so §16.4 forbids it carrying the switch's meaning alone. (5) `menu.initial_scroll`, `start` (default) or `end`, unknown values falling back to `start` under §12 rule 6: `InputNodes.kt:160` passes no `scrollState`, so a thirty-item popup always opens at the top and the wire cannot say otherwise; the popup's scroll position stays Companion-local presentation state — nothing about it crosses the wire in either direction, and nothing about it is retained between openings, so §25's monotonic-resource duty is satisfied vacuously here and for the other five members. (6) The `MenuItem` record has been `{label, on_tap, icon, enabled}` since format 6 and `InputNodes.kt:167-176` passes exactly those four, so `DropdownMenuItem`'s `supportingText` slot has no wire member and its `trailingIcon` slot — which the Companion's current overload already has — is never filled; `supporting_text` (string) and the trailing pair `trailing_icon` (identifier) / `trailing_text` (string) fill them, the pair mutually exclusive because the item has ONE trailing slot. That pair also repairs an already-shipped `:build`: `menus/MenuSample` renders today with its "F11" shortcut silently dropped, a loss its own module docstring records (`emacs/apps/m3-catalog/jetpacs-m3-menus.el:41-46`) — the same genre of false `:build` as the `hint` defect fixed in `1917fff`. Two members rather than one string-or-identifier because `IconMap.get` cannot report a miss: `IconMap.kt:89-106` returns `HelpOutline` for any unresolved name, so a single overloaded member would render `"F11"` as a help glyph with no diagnostic anywhere. Additive on the wire throughout: every member is OPTIONAL, every default is the behaviour the Companion has today, and a document omitting all six is rendered by exactly the calls the Companion makes today — no existing golden, fixture, or message changes meaning. One rendering consequence is stated rather than hidden: `supporting_text` is reachable only through material3's expressive `DropdownMenuItem` overload, whose item geometry differs from the one the Companion binds today, so authoring `supporting_text` anywhere in a menu changes that whole menu's item layout; §17.4 now requires one item layout throughout a single menu and permits the change, and a menu with no `supporting_text` keeps today's exact call. Enforcement, named per #150/#151: `validate.py` gains a `check_stroke` arm (object shape and non-negative finite `width`; it deliberately does NOT reject an unknown `cap`/`join`, which §12 rule 6 makes a fallback, not an error) and a `check_menu_items` arm (the trailing exclusivity); both scoped to those two checks and nothing else. The three `enums` entries are projection documentation, not enforcement: no tool in this repository reads that block. | contract `node_schema`: `box.optional` += `on_long_tap`, `column.optional` += `reverse_scroll`, `checkbox.optional` += `stroke`, `switch.optional` += `thumb_icon`, `menu.optional` += `initial_scroll`; `field_types` += `supporting_text`, `trailing_text`, `thumb_icon`, `trailing_icon`, `initial_scroll`, `reverse_scroll`, `stroke`; `enums` += `menu.initial_scroll`, `stroke.cap`, `stroke.join`; BOTH generated mirrors regenerated (`Vocabulary.kt`, `jetpacs-vocabulary.el`); goldens/widgets.golden += 5 appended lines (indices 75–79), none modified; validate.py `check_stroke` + `check_menu_items` arms | |

### SPEC.md edits

**1. §17.3, widget table — the `column` row** (`SPEC.md:2335`). Replace:

> ```
> | `column` | `children: Node[]` | `spacing`, `align`, `arrange`, `scroll`, `fill`. `align`: `start`, `center`, `end`; default `start`. |
> ```

with:

> ```
> | `column` | `children: Node[]` | `spacing`, `align`, `arrange`, `scroll`, `reverse_scroll`, `fill`. `align`: `start`, `center`, `end`; default `start`. |
> ```

**2. §17.3, widget table — the `box` row** (`SPEC.md:2337`). Replace:

> ```
> | `box` | `children: Node[]` | `alignment`, `on_tap`. Children stack in array order from back to front. |
> ```

with:

> ```
> | `box` | `children: Node[]` | `alignment`, `on_tap`, `on_long_tap`. Children stack in array order from back to front. |
> ```

**3. §17.3, prose — the booleans sentence** (`SPEC.md:2354-2355`). Replace:

> `scroll` and layout `fill` are booleans. `flow_row.align` is `top`, `center`, or
> `bottom`, default `top`. `content_padding` is a non-negative `dp` value.

with:

> `scroll`, `column.reverse_scroll`, and layout `fill` are booleans.
> `flow_row.align` is `top`, `center`, or `bottom`, default `top`.
> `content_padding` is a non-negative `dp` value.
>
> `column.reverse_scroll` defaults to `false` and has effect only when `scroll`
> is `true`; it is not an error otherwise, and a `column` that does not scroll
> renders identically whether the member is present or absent. When both are
> `true` the column's scroll axis is reversed: the column is first presented
> scrolled to its END, and a scroll gesture proceeds toward its start.
> Reversal changes the scroll anchor and the gesture direction only — children
> still lay out in array order, and `arrange`, `align`, and `spacing` are
> unaffected.

**4. §17.3, prose — the `box.alignment` / `surface.shape` paragraph**
(`SPEC.md:2357-2361`). Replace:

> `box.alignment` is one of `top_start`, `top_center`, `top_end`, `center_start`,
> `center`, `center_end`, `bottom_start`, `bottom_center`, or `bottom_end`; the
> default is `top_start`. `surface.shape` is `rounded`, `rounded_small`, or
> `circle`; omission is rectangular. A numeric universal `corner` overrides
> `shape` except that `circle` remains circular.

with:

> `box.alignment` is one of `top_start`, `top_center`, `top_end`, `center_start`,
> `center`, `center_end`, `bottom_start`, `bottom_center`, or `bottom_end`; the
> default is `top_start`. `surface.shape` is `rounded`, `rounded_small`, or
> `circle`; omission is rectangular. A numeric universal `corner` overrides
> `shape` except that `circle` remains circular.
>
> `box.on_long_tap` makes an otherwise plain container a long-press target. A
> Companion MUST dispatch it at most once per completed press and MUST NOT also
> dispatch `on_tap` for that same press. The two members are independent:
> either MAY appear without the other, a `box` carrying only `on_long_tap` MUST
> still register the long press while a short tap dispatches nothing, and a
> `box` carrying neither remains non-interactive. Adding either member MUST NOT
> change the node's layout, padding, background, or shape — unlike `card` and
> `collapsible`, a `box` supplies no chrome of its own, and an omitted
> `on_long_tap` renders exactly as before this member existed. Emacs SHOULD
> provide a non-long-press path to the same action, for accessibility and for
> Companions without long-press support, exactly as it SHOULD for a swipe side.

**5. §17.4, widget table — the `menu` row** (`SPEC.md:2416`). Replace:

> ```
> | `menu` | `items: MenuItem[]` | `icon`, `enabled` |
> ```

with:

> ```
> | `menu` | `items: MenuItem[]` | `icon`, `initial_scroll`, `enabled`. `initial_scroll` is `start` (default) or `end`; unknown values fall back to `start`. |
> ```

**6. §17.4, widget table — the `checkbox` row** (`SPEC.md:2419`). Replace:

> ```
> | `checkbox` | `id: identifier` | `checked`, `label`, `on_change`, `enabled` |
> ```

with:

> ```
> | `checkbox` | `id: identifier` | `checked`, `label`, `on_change`, `stroke`, `enabled` |
> ```

**7. §17.4, widget table — the `switch` row** (`SPEC.md:2420`). Replace:

> ```
> | `switch` | `id: identifier` | `checked`, `label`, `on_change`, `enabled` |
> ```

with:

> ```
> | `switch` | `id: identifier` | `checked`, `label`, `on_change`, `thumb_icon`, `enabled` |
> ```

**8. §17.4, prose — the `MenuItem` / `EnumOption` paragraph**
(`SPEC.md:2426-2429`). Replace:

> A `MenuItem` MUST contain `label` and `on_tap` and MAY contain `icon` and
> `enabled`; `enabled` defaults to `true`. An `EnumOption` MUST contain `label`
> and `value`; `value` MUST be a
> string, number, or boolean. Option values MUST be distinct under Section 4.3.

with:

> A `MenuItem` MUST contain `label` and `on_tap` and MAY contain `icon`,
> `supporting_text`, `trailing_icon`, `trailing_text`, and `enabled`; `enabled`
> defaults to `true`. `supporting_text` and `trailing_text` are plain strings
> and `trailing_icon` is an identifier; all three are absent by default.
> `supporting_text` is a secondary line rendered beneath `label`.
> `trailing_icon` and `trailing_text` occupy the item's single trailing slot,
> so a `MenuItem` carrying both is invalid and MUST be rejected with
> `1201 content-invalid`. `trailing_text` is for a short trailing hint such as
> a keyboard shortcut; a Companion MAY truncate it to fit the item and MUST NOT
> let it displace `label`. An item omitting all three MUST NOT gain content it
> did not carry. A Companion MAY render a menu whose items carry
> `supporting_text` with a different item layout — a different interior
> padding, container shape, or container colour — than a menu whose items do
> not, but it MUST apply one item layout to every item of a single menu, and a
> menu in which no item carries `supporting_text` MUST render as it did before
> these members existed. None of the three is load-bearing on its own: the
> item's accessible label derives from `label` under Section 16.4, and a
> Companion MUST NOT make a trailing affordance the item's only dispatch
> target — `on_tap` belongs to the whole item. An `EnumOption` MUST contain
> `label`
> and `value`; `value` MUST be a
> string, number, or boolean. Option values MUST be distinct under Section 4.3.
>
> `menu.initial_scroll` names where the menu's popup is positioned each time it
> opens: `start`, the default, leaves it at the beginning of the item list, and
> `end` opens it scrolled to the end. A Companion MUST apply `end` once the
> popup's scrollable extent is known; it MAY briefly present the popup at its
> start before that extent is measured, and MUST NOT report the intermediate
> position anywhere. An unrecognized value falls back to `start` under
> Section 12 rule 6 and MUST NOT reject the node. The popup's scroll position
> is Companion-local presentation state: it is never reported to Emacs, it is
> not retained between openings, and `initial_scroll` MUST NOT change which
> items exist, their order, their enabled state, or what they dispatch.

**9. §17.4, prose — the checkbox/switch flip paragraph** (`SPEC.md:2496-2498`).
Replace:

> `checkbox.checked` and `switch.checked` default to `false`. Every flip MUST
> produce `state.changed`; when `on_change` is present it MUST also produce an
> action with the boolean in `args.value`, after the state notification.

with:

> `checkbox.checked` and `switch.checked` default to `false`. Every flip MUST
> produce `state.changed`; when `on_change` is present it MUST also produce an
> action with the boolean in `args.value`, after the state notification.
>
> `checkbox.stroke` is an object `{width?, cap?, join?}` describing the stroke
> geometry of the checkbox drawing. `width` is a non-negative `dp` value and
> defaults to the platform's own checkbox stroke width — NOT to zero, which
> would draw nothing. `cap` is `butt` (default), `round`, or `square`, and
> `join` is `miter` (default), `round`, or `bevel`; an unrecognized `cap` or
> `join` falls back to its default under Section 12 rule 6 and MUST NOT reject
> the node, while a `stroke` that is not an object, or a `width` outside its
> type or domain, is content-invalid under Section 16.1. `cap` and `join`
> shape the CHECKMARK only; the box outline takes `width` alone. `stroke`
> describes the node's checkbox drawing and applies to whichever checkbox form
> the Companion renders for the node. An omitted `stroke` MUST render exactly
> as before this member existed.
>
> `switch.thumb_icon` is an identifier drawn inside the switch's thumb, from
> the same icon vocabulary as `icon.name`. It MUST be rendered only while the
> switch's live checked state is `true` and MUST NOT be rendered while the
> switch is off; an omitted `thumb_icon` leaves the thumb plain, which is the
> rendering of every switch authored before this member existed. The icon is
> decoration over a control that already carries an accessible label: it MUST
> NOT be the sole carrier of the switch's meaning (Section 16.4), a Companion
> MUST NOT expose it as a separately focusable or separately actionable
> element, and an unresolved identifier follows Section 17.2's placeholder rule
> rather than invalidating the node.

### Artifact changes

#### `contract.json` — `node_schema`

Five `optional` arrays gain one member each. New members are placed beside
their nearest relative and before `enabled`, matching the file's existing
ordering habit.

```json
    "box": {
      "required": [
        "children"
      ],
      "optional": [
        "alignment",
        "on_tap",
        "on_long_tap"
      ]
    },
```

```json
    "column": {
      "required": [
        "children"
      ],
      "optional": [
        "spacing",
        "align",
        "arrange",
        "scroll",
        "reverse_scroll",
        "fill"
      ]
    },
```

```json
    "checkbox": {
      "required": [
        "id"
      ],
      "optional": [
        "checked",
        "label",
        "on_change",
        "stroke",
        "enabled"
      ]
    },
```

```json
    "switch": {
      "required": [
        "id"
      ],
      "optional": [
        "checked",
        "label",
        "on_change",
        "thumb_icon",
        "enabled"
      ]
    },
```

```json
    "menu": {
      "required": [
        "items"
      ],
      "optional": [
        "icon",
        "initial_scroll",
        "enabled"
      ]
    },
```

`on_long_tap` needs no `field_types` row: it is already in
`actions.hook_keys` and `field_types` registers no `on_*` member at all.

#### `contract.json` — `field_types`

Appended at the end of the map, following the precedent of `time` and `fg`
(both appended by later amendments rather than re-grouped), which also keeps
this delta free of textual conflict with sibling amendments in the same batch.
Replace the map's last line `    "fg": "color"` with:

```json
    "fg": "color",
    "supporting_text": "string",
    "trailing_text": "string",
    "thumb_icon": "identifier",
    "trailing_icon": "identifier",
    "initial_scroll": "enum",
    "reverse_scroll": "boolean",
    "stroke": "stroke-object"
```

Two properties of this map the ratifier should have in view. First, it is a
FLAT bare-name → type map with no node scoping: adding `stroke` types the name
`stroke` for every node type that ever carries it, which is intended (the
object shape is meant to be reusable) but is not a `checkbox`-local statement.
Second, `stroke-object` is a complex category, so
`SpecValidator.checkScalarFieldType` (`SpecValidator.kt:467-497`) falls through
its `else -> Unit` arm at `:495` and the dedicated validator below carries the
check — the same arrangement `swipe-object` and `date-marks-object` already
use.

> **Ratification note.** `"thumb_icon": "identifier"` is also required by the
> `slider.thumb_icon` amendment (G-34). The two entries are byte-identical, so
> whichever lands first satisfies both; the second must not add a duplicate
> key — `json.load` silently collapses duplicates rather than rejecting them,
> so that failure would be invisible.

#### `contract.json` — `enums`

Appended after `toolbar.placement`, the current last entry. `stroke.cap` and
`stroke.join` are keyed on the object shape rather than on `checkbox.` because
the shape is reusable — the same bare-key convention `arrange` and
`align_self` already use.

```json
    "toolbar.placement": [
      "cursor",
      "line-start",
      "block"
    ],
    "menu.initial_scroll": [
      "start",
      "end"
    ],
    "stroke.cap": [
      "butt",
      "round",
      "square"
    ],
    "stroke.join": [
      "miter",
      "round",
      "bevel"
    ]
```

**Enforcement scope of this block, per #150/#151: none.** `validate.py` never
reads `enums`; neither generator projects it; `Vocabulary.kt` stores only the
type NAME `"enum"` from `field_types`, not any value set. These entries are
projection documentation so §24.4's completeness duty is met. The only
enforcement this amendment claims is the two `validate.py` arms below.

#### Regenerate both mirrors — same commit

`node_schema` and `field_types` have two GENERATED projections, both
drift-tested:

```sh
python3 tools/gen-vocabulary.py          # -> companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/Vocabulary.kt
python3 tools/gen-jetpacs-vocabulary.py  # -> emacs/jetpacs-vocabulary.el
```

`SurfaceStoreTest` asserts exact equality between `Vocabulary.kt` and
`contract.json`, and `jetpacs--check-options` (`jetpacs-widgets.el:370-382`)
validates every constructor keyword against the generated
`jetpacs-node-schema` — so without the regeneration the Kotlin test fails and
the elisp constructors reject `:reverse-scroll`, `:on-long-tap`, `:stroke`,
`:thumb-icon`, and `:initial-scroll` outright.

#### `goldens/widgets.golden`

Five lines APPENDED at indices 75–79; no existing line is modified. **The
two-digit index prefix is mandatory** — `golden_lines` splits on the first
space and parses the remainder (`validate.py:376-379`), so a line without it
does not load. The corpus already covers every node type, so the coverage
floor is unaffected — these exist to exercise the new members. Appending
rather than widening the existing `box`/`column`/`checkbox`/`switch`/`menu`
lines follows the precedent of the appended equality lines 72–74 and keeps the
additive-only rule literally true. All five are sorted-key compact JSON,
verified canonical.

```
75 {"alignment":"center","children":[{"t":"text","text":"Item 1"}],"on_long_tap":{"action":"demo.mode"},"on_tap":{"action":"demo.count"},"t":"box"}
76 {"arrange":"end","children":[{"t":"text","text":"a"}],"reverse_scroll":true,"scroll":true,"t":"column"}
77 {"checked":true,"id":"rounded","label":"Rounded","stroke":{"cap":"round","join":"round","width":2},"t":"checkbox"}
78 {"checked":true,"id":"wifi","label":"Wi-Fi","t":"switch","thumb_icon":"check"}
79 {"icon":"more_vert","initial_scroll":"end","items":[{"icon":"edit","label":"Edit mode","on_tap":{"action":"demo.edit"},"supporting_text":"Opens menu","trailing_icon":"chevron_right"},{"icon":"email","label":"Send Feedback","on_tap":{"action":"demo.feedback"},"trailing_text":"F11"}],"t":"menu"}
```

Line 76 pairs `reverse_scroll` with `arrange: "end"` deliberately: that is the
upstream sample's `Arrangement.Bottom`, which `verticalArrange`
(`LayoutNodes.kt:110-119`) already maps from `"end"`, so the golden witnesses
the authored form of `EnterAlwaysTopAppBarWithReverseScrolling`'s **body**
(see Unblocks — the bar half is not this amendment's). Line 79 is deliberately
the mixed case: one item with `supporting_text` and a `trailing_icon`, one
with `trailing_text`, so the exclusivity rule is exercised on the legal side
and the whole-menu layout branch has a witness.

#### `validate.py` — two arms

Both are new module-level functions inserted immediately before
`def check_node(...)` (currently `validate.py:253`), plus two dispatch lines
in `check_node`'s per-type block.

```python
def check_stroke(node, path: str):
    """SPEC 17.4: `checkbox.stroke` is an object and its `width`, when
    present, is a non-negative finite dp. `cap` and `join` are closed
    vocabularies WITH a fallback (SPEC 12 rule 6), so an unrecognized
    spelling is applied as the default and MUST NOT be reported here.
    """
    stroke = node.get("stroke")
    if stroke is None:
        return
    if not isinstance(stroke, dict):
        problem(f"{path}.stroke: must be an object")
        return
    if "width" not in stroke:
        return
    w = stroke["width"]
    if isinstance(w, bool) or not isinstance(w, (int, float)) \
            or w != w or w in (float("inf"), float("-inf")) or w < 0:
        problem(f"{path}.stroke.width: must be a non-negative finite number")


def check_menu_items(node, path: str):
    """SPEC 17.4: a MenuItem has ONE trailing slot, so `trailing_icon` and
    `trailing_text` are mutually exclusive. An ABSENT `items` belongs to the
    required-member check above, not here — reporting it twice was a defect
    of this arm's first draft."""
    items = node.get("items")
    if items is None:
        return
    if not isinstance(items, list):
        problem(f"{path}.items: must be an array")
        return
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            problem(f"{path}.items[{i}]: must be an object")
            continue
        if "trailing_icon" in item and "trailing_text" in item:
            problem(f"{path}.items[{i}]: trailing_icon and trailing_text "
                    f"are mutually exclusive")
```

and in `check_node` (`validate.py:293-294`), replace:

```python
            if t == "slider":
                check_slider_values(value, path)
```

with:

```python
            if t == "slider":
                check_slider_values(value, path)
            if t == "checkbox":
                check_stroke(value, path)
            if t == "menu":
                check_menu_items(value, path)
```

**Enforcement scope, stated per #150/#151:** `validate.py` checks the
`stroke` object shape, `stroke.width`'s domain, and the trailing exclusivity —
nothing else about these six members. `reverse_scroll`, `thumb_icon`,
`initial_scroll`, `supporting_text`, and `on_long_tap` are covered only by the
existing `node_schema` key check and (for `on_long_tap`) the existing
`HOOK_KEYS` action validator. The `enums` block enforces nothing. Verified on
the scratch copy:

```
unknown cap/join                 -> clean   (SPEC 12 rule 6 — must NOT reject)
stroke.width: -1                 -> x.stroke.width: must be a non-negative finite number
stroke: 2                        -> x.stroke: must be an object
item with both trailing members  -> x.items[0]: trailing_icon and trailing_text are mutually exclusive
item with one trailing member    -> clean
item with supporting_text        -> clean
menu with no items at all        -> x: menu missing required `items`      (ONE report, not two)
box with on_long_tap only        -> clean
column reverse_scroll + scroll   -> clean
switch thumb_icon                -> clean
full corpus                      -> OK: 40 frames, 80 widget lines, 7 hypertext nodes, 17 wire fixtures x3 chunkings
```

No `goldens/wire/` fixture and no `frames.golden` line is needed: no method,
error code, or framing behaviour changes.

### Companion implementation

Every Compose API named below was confirmed present in
`material3-android:1.5.0-alpha16` by disassembling the unpacked artifact —
including each one's experimental annotations, which are the part a class
listing does not show. Note that the local `androidx` checkout is NEWER than
the pinned artifact (it has `DropdownMenuItemLegacy` and a renamed
`trailingContent` parameter that alpha16 does not); where the two disagree,
the artifact governs and is what is cited.

**G-35 · `box.on_long_tap` — `LayoutNodes.kt`, `RenderBox`, lines 186-204.**
Line 200 is today

```kotlin
    val mod = if (onTap != null) m.clickable { ctx.action(onTap) } else m
```

Read `val onLongTap = node.objOrNull("on_long_tap")` beside the existing
`onTap` read at `:187` and swap line 200 for the identical construction
`RenderCard` already carries at `:336-338`:

```kotlin
    val mod = when {
        onLongTap != null -> m.combinedClickable(
            onClick = { if (onTap != null) ctx.action(onTap) },
            onLongClick = { ctx.action(onLongTap) })
        onTap != null -> m.clickable { ctx.action(onTap) }
        else -> m
    }
```

`combinedClickable` and `ExperimentalFoundationApi` are already imported in
this file (`LayoutNodes.kt:25`, `:22`); `RenderBox` gains
`@OptIn(ExperimentalFoundationApi::class)`, exactly as `RenderCard` carries at
`:328`. Note the deliberate difference from `RenderCard`: a `box` with neither
member stays outside `clickable` entirely, so it does not begin swallowing
taps.

**G-36 · `column.reverse_scroll` — `LayoutNodes.kt`, `RenderColumn`, lines
146-162.** Line 150 is today

```kotlin
        if (scroll) it.verticalScroll(rememberScrollState()) else it
```

becomes

```kotlin
        if (scroll) it.verticalScroll(
            rememberScrollState(),
            reverseScrolling = node.boolOr("reverse_scroll")) else it
```

`ScrollKt.verticalScroll(Modifier, ScrollState, boolean, FlingBehavior,
boolean)` — the trailing boolean is `reverseScrolling` — is on the classpath.
`boolOr` defaults to `false` (`NodeAccess.kt:37`), so an absent member is
today's call.

**G-37 · `checkbox.stroke` — `InputNodes.kt`, `RenderCheckbox`, lines
185-210.** The call at `:201-205` stays as-is when `stroke` is absent; when
present, select the stroke overload verified in `CheckboxKt` and confirmed
NON-experimental (its only method annotation is `@Composable`):
`Checkbox(boolean, Function1, Stroke checkmarkStroke, Stroke outlineStroke,
Modifier, boolean, CheckboxColors, MutableInteractionSource)`. Width must
reach Compose in pixels, so convert through `LocalDensity` and floor exactly
as upstream does (`CheckboxSamples.kt`:
`floor(CheckboxDefaults.StrokeWidth.toPx())`):

```kotlin
    val strokeObj = node.objOrNull("stroke")
    val strokes = strokeObj?.let { s ->
        val wDp = safeDp(s.doubleOr("width", Double.NaN))
            ?.dp ?: CheckboxDefaults.StrokeWidth
        val px = with(LocalDensity.current) { floor(wDp.toPx()) }
        Pair(
            Stroke(width = px,
                cap = when (s.stringOr("cap")) {
                    "round" -> StrokeCap.Round
                    "square" -> StrokeCap.Square
                    else -> StrokeCap.Butt          // §12 r6 fallback
                },
                join = when (s.stringOr("join")) {
                    "round" -> StrokeJoin.Round
                    "bevel" -> StrokeJoin.Bevel
                    else -> StrokeJoin.Miter        // §12 r6 fallback
                }),
            Stroke(width = px))                     // outline: width ONLY
    }
```

`StrokeCap.{Butt,Round,Square}` and `StrokeJoin.{Miter,Round,Bevel}` are the
complete companion sets in `ui-graphics` (verified); `Stroke`'s own defaults
are `Butt`/`Miter`, so the fallbacks agree with the toolkit. `safeDp`
(`Attributes.kt:41-42`) already rejects negative and non-finite values.
`CheckboxDefaults.StrokeWidth` is present (`getStrokeWidth-D9Ej5fM`). New
imports: `androidx.compose.material3.CheckboxDefaults`,
`androidx.compose.ui.platform.LocalDensity`,
`androidx.compose.ui.graphics.drawscope.Stroke`,
`androidx.compose.ui.graphics.StrokeCap`,
`androidx.compose.ui.graphics.StrokeJoin`, `kotlin.math.floor`.

A matching arm belongs in `SpecValidator.validateNode`'s `when (t)`
(`SpecValidator.kt:547`) — `"checkbox" -> validateStroke(node, path)` —
rejecting a non-object `stroke` and an out-of-domain `width` with
`ContentInvalid`, and deliberately NOT rejecting an unknown `cap`/`join`.
Because `field_types["stroke"]` is a complex category,
`checkScalarFieldType` leaves it alone (`SpecValidator.kt:495`), so without
this arm `stroke: 2` would reach the renderer.

**G-38 · `switch.thumb_icon` — `InputNodes.kt`, `RenderSwitch`, lines
213-234.** The `Switch(...)` call at `:228-232` gains one argument;
`SwitchKt.Switch(boolean, Function1, Modifier, Function2 thumbContent,
boolean, SwitchColors, MutableInteractionSource)` is verified on the classpath
and non-experimental, as is `SwitchDefaults.IconSize` (`getIconSize-D9Ej5fM`):

```kotlin
        val thumbIcon = node.stringOr("thumb_icon").takeIf { it.isNotEmpty() }
        Switch(checked = checked, enabled = enabled,
            thumbContent = if (thumbIcon != null) {
                { if (checked) Icon(IconMap.get(thumbIcon), null,
                    Modifier.size(SwitchDefaults.IconSize)) }
            } else null,
            onCheckedChange = { … })
```

The `if (checked)` sits INSIDE the lambda, reading the live state, which is
both what upstream does and what the spec text now requires. `Modifier.size`
is already imported (`InputNodes.kt:28`); `SwitchDefaults` is not.

**G-39 · `menu.initial_scroll` — `InputNodes.kt`, `RenderMenu`, lines
150-180.** `DropdownMenu` at `:160` passes no `scrollState`. The source-visible
overload in alpha16 is `AndroidMenu_androidKt.DropdownMenu-IlH_yew(boolean,
Function0, Modifier, long, ScrollState, PopupProperties, Shape, long, float,
float, BorderStroke, Function3)` — not experimental, not deprecated; the two
other arities in that class are `DeprecationLevel.HIDDEN` binary-compat shims
and are not source-visible. Hoist the state and run the literal upstream
effect (`MenuSamples.kt:391`, `:426-432`):

```kotlin
    val scrollState = rememberScrollState()
    val toEnd = node.stringOr("initial_scroll") == "end"   // §12 r6: else start
    …
        DropdownMenu(expanded = open, onDismissRequest = { open = false },
            scrollState = scrollState) { … }
        LaunchedEffect(open) {
            if (open && toEnd) scrollState.scrollTo(scrollState.maxValue)
        }
```

`maxValue` is `0` until the popup is measured, so first-open may land at the
start — which is why SPEC edit 8 says "once the popup's scrollable extent is
known" rather than stating a flat requirement. Upstream's sample has the
identical exposure.

**G-40 · `MenuItem.supporting_text` / `trailing_icon` / `trailing_text` —
`InputNodes.kt`, `RenderMenu`, lines 167-176.** This one is an overload
migration, not an added argument, and the amendment is written around that.

*What the current call binds.* All-named-argument
`DropdownMenuItem(text =, enabled =, onClick =, leadingIcon =)` resolves to
`AndroidMenu_androidKt.DropdownMenuItem(Function2 text, Function0 onClick,
Modifier, Function2 leadingIcon, Function2 trailingIcon, boolean enabled,
MenuItemColors, PaddingValues, MutableInteractionSource)` — the `actual` of
the `expect fun` in `Menu.kt`. Its `contentPadding` default is
`MenuDefaults.DropdownMenuItemContentPadding`, it has no shape parameter, and
its content is a plain `Row`. **It already has a `trailingIcon` slot**, which
is where upstream's own `MenuSample` puts `Text("F11", textAlign =
TextAlign.Center)` (`MenuSamples.kt:148`). So `trailing_icon` and
`trailing_text` cost no migration at all.

*What `supportingText` costs.* There is no `supportingText` on that overload.
Naming it moves resolution into `MenuKt`, where the match for a
`(onClick, text, …)` call is
`DropdownMenuItem(Function0 onClick, Function2 text, Shape shape, Modifier,
Function2 leadingIcon, Function2 trailingIcon, boolean enabled,
MenuItemColors, PaddingValues, MutableInteractionSource, Function2
supportingText)`. Three consequences, each verified in the alpha16 bytecode:

1. It is `@ExperimentalMaterial3ExpressiveApi` — every `MenuKt.DropdownMenuItem`
   overload is. `InputNodes.kt` imports `ExperimentalMaterial3Api` only
   (`:39`); there is no project-wide opt-in in `companion/app/build.gradle.kts`
   or `gradle/libs.versions.toml`. **This is the first expressive opt-in in
   the file.**
2. `shape: Shape` has **no default** — the bytecode's default-argument block
   fills only `Modifier`, `MenuDefaults.itemColors()`,
   `MenuDefaults.DropdownMenuSelectableItemContentPadding`, and a null
   interaction source. A caller must supply a shape.
3. Its `contentPadding` default is a **different constant** from the current
   overload's (`getDropdownMenuSelectableItemContentPadding` vs
   `getDropdownMenuItemContentPadding`), and it delegates to a different
   internal `DropdownMenuItemContent` that takes `MenuItemShapes` and an
   animated container colour.

So an unconditional `supportingText =` would change the geometry of every
item in every menu, including items carrying none of the three new members.
That is why the branch is at MENU granularity, keyed on `supporting_text`
alone — a menu with no supporting text keeps today's exact call, and a menu
with any supporting text renders all of its items in one expressive layout,
which is what SPEC edit 8 now permits and bounds. The neighbouring parameter
in alpha16 is spelled `trailingIcon` on both overloads (the newer androidx
snapshot renames it `trailingContent`; do not use that name against this
artifact).

```kotlin
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderMenu(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    …
    val n = items?.size ?: 0
    val expressive = (0 until n).any {
        (items!![it] as? JsonObject)?.stringOr("supporting_text")?.isNotEmpty() == true
    }
    …
        val trailing: (@Composable () -> Unit)? = when {
            item.stringOr("trailing_icon").isNotEmpty() -> {
                { Icon(IconMap.get(item.stringOr("trailing_icon")), null,
                    Modifier.size(MenuDefaults.TrailingIconSize)) }
            }
            item.stringOr("trailing_text").isNotEmpty() -> {
                { Text(item.stringOr("trailing_text"), textAlign = TextAlign.Center) }
            }
            else -> null
        }
        if (!expressive) {
            // byte-for-byte today's call, plus the slot that already existed
            DropdownMenuItem(
                text = { Text(item.stringOr("label")) },
                enabled = itemEnabled,
                onClick = { … },
                leadingIcon = …,
                trailingIcon = trailing)
        } else {
            DropdownMenuItem(
                onClick = { … },
                text = { Text(item.stringOr("label")) },
                shape = when {
                    n == 1 -> MenuDefaults.standaloneItemShape
                    i == 0 -> MenuDefaults.leadingItemShape
                    i == n - 1 -> MenuDefaults.trailingItemShape
                    else -> MenuDefaults.middleItemShape
                },
                enabled = itemEnabled,
                leadingIcon = …,
                trailingIcon = trailing,
                supportingText = item.stringOr("supporting_text")
                    .takeIf { it.isNotEmpty() }?.let { { Text(it) } })
        }
```

`MenuDefaults.TrailingIconSize` (`getTrailingIconSize-D9Ej5fM`) and the four
shape accessors (`getStandaloneItemShape`, `getLeadingItemShape`,
`getMiddleItemShape`, `getTrailingItemShape`) are verified present in alpha16.
New imports: `androidx.compose.material3.ExperimentalMaterial3ExpressiveApi`,
`androidx.compose.material3.MenuDefaults`,
`androidx.compose.ui.text.style.TextAlign` (`DropdownMenuItem` is already
imported, at `:38`).

A `SpecValidator` arm for the trailing exclusivity belongs in `walkValue`'s
non-node object branch (`SpecValidator.kt:384-402`) or in a `"menu" ->` arm of
`validateNode`'s `when (t)`; note that MenuItem members are **not** covered by
`checkScalarFieldType`, because it is scoped to a node's own `node_schema` row
(`SpecValidator.kt:545-546`) and `MenuItem` has no row — the same situation
`label`, `icon`, and `enabled` are already in. The `field_types` rows added
above type the three new names for tooling; they enforce nothing on a
MenuItem.

**Elisp sender side.** Two different shapes, not one:

- `jetpacs-checkbox` (`jetpacs-widgets.el:1093`), `jetpacs-switch` (`:1104`),
  `jetpacs-menu` (`:1038`), and `jetpacs-menu-item` (`:1030`) are
  `cl-defun … &key` and each gains one keyword.
- `jetpacs-column` (`:749`) and `jetpacs-box` (`:789`) are `(&rest args)` +
  `jetpacs--children-and-opts` + `plist-get`; each gains a `plist-get` read
  and a check (`jetpacs--check-bool` for `:reverse-scroll`,
  `jetpacs--check-descriptor` for `:on-long-tap`), not a `&key`.

All six then depend on the regenerated `jetpacs-node-schema`, since
`jetpacs--check-options` (`:370-382`) refuses any keyword not in it. All
additive; no existing call site changes.

### Unblocks

**Three catalog examples cleared outright, one cleared at the wire but still
blocked by the m3-catalog app's own house rule, three cleared jointly with a
sibling amendment, and one partial fidelity repair to an already-shipped
`:build`.** The claim of seven in the first revision counted joint clears as
clears.

Cleared outright — this amendment is the example's sole remaining gap and the
result builds inside the catalog app:

| slug | example | gap | reason string it replaces |
|---|---|---|---|
| `checkboxes` | `CheckboxRoundedStrokesSample` | G-37 | `jetpacs-m3-checkboxes--stroke-note` |
| `switches` | `SwitchWithThumbIconSample` | G-38 | `jetpacs-m3-switches.el:55` |
| `menus` | `MenuWithScrollStateSample` | G-39 | `jetpacs-m3-menus.el:82` |

Cleared at the wire, still blocked in the app:

| slug | example | gap | what still blocks it |
|---|---|---|---|
| `lists` | `ListItemWithModeChangeOnLongClickSample` | G-35 | not a wire gap — `README.md:76-77` permits only `(jetpacs-m3-demo "…")` handlers and forbids registering new actions from a component module, and this sample's whole subject is a long press that rewrites its siblings via `event.action` → `surface.update` with `reset_input_ids` |

Cleared jointly with a sibling amendment:

| slug | example | this amendment supplies | still needs |
|---|---|---|---|
| `checkboxes` | `TriStateCheckboxRoundedStrokesSample` | G-37 `checkbox.stroke` | **G-56** `checkbox.state` (AUDIT:324-327) |
| `top-app-bar` | `EnterAlwaysTopAppBarWithReverseScrolling` | G-36 `column.reverse_scroll`, which is the sample's **body** | **G-43** `scaffold.scroll_behavior`, *and* a design constraint stated below |
| `menus` | `GroupedMenuSample` | G-40 item members | **G-79** `menu.groups`, `menu.footer`, `menu.items[].checked` (AUDIT:408-409) |

> The first revision of this table wrote G-46 and G-52, copied from the
> audit's own stale cross-refs. G-46 is `scaffold.floating_toolbar_*`
> (AUDIT:283-287) and G-52 is `text_input.mask`/`filter` (AUDIT:314-315).
> Whoever lands this should fix the audit at `:247` and `:252`/`:254` in the
> same change, since the stale refs originate there.

**Design constraint this amendment hands to G-43.** Upstream's
`EnterAlwaysTopAppBarWithReverseScrolling` (`AppBarSamples.kt:955-1004`)
hoists ONE `rememberScrollState()`, passes it to
`TopAppBarDefaults.enterAlwaysScrollBehavior(scrollableState = scrollState)`
with the in-source comment "Pass this state to ensure the top app bar color
updates correctly when content has reverse scrolling", and reuses the same
state at `:999` in `verticalScroll(state = scrollState, reverseScrolling =
true)`. The `RenderColumn` change above creates a column-private state that
nothing outside the composable can reach. So G-36 clears the body's authored
form — which golden line 76 witnesses — and G-43 must additionally hoist the
scrolling body's state into the bar's scroll behaviour, or that example needs
a third member. That belongs to G-43's design and is deliberately out of scope
here; it is recorded so it is not discovered later.

**Partial fidelity repair, no new example.** `menus/MenuSample` is `:build`
today and its module docstring (`jetpacs-m3-menus.el:41-46`) records **two**
losses: the "F11" trailing shortcut and the `HorizontalDivider` above "Send
Feedback". `trailing_text` restores the first. The divider is still not
expressible inside a `menu`'s item list and remains a documented loss — the
docstring should be trimmed to that one remaining item, not deleted.

**Caveat the ratifier should see rather than discover.** The catalog's
`:unsupported` reason for `ListItemWithModeChangeOnLongClickSample`
(`jetpacs-m3-lists.el:356`) is one of the 79 factually inaccurate reasons the
audit found: it blames the sibling rewrite after a gesture, which is ordinary
EBP. Whoever lands G-35 must rewrite that string in the same change — to the
house-rule reason above — or it ships a false explanation of a now-fixed wire
gap.

### Design decision required — 1 of 2

**The trailing slot on a `MenuItem`: one overloaded member or two typed
members?** Upstream's own sample puts `Text("F11")` in `trailingIcon`, so the
slot genuinely carries either an icon or a short string. The draft is **A**.

| | A — two members (recommended) | B — one `trailing_icon`, typed string-or-identifier |
|---|---|---|
| Wire | `trailing_icon` (identifier) and `trailing_text` (string), mutually exclusive; both present ⇒ `1201` | one member; the Companion tries icon resolution, falls back to rendering the literal string as text |
| Members added | 2 | 1 |
| Failure mode | An unresolved `trailing_icon` follows §17.2's placeholder rule, an explicit, documented outcome | **Unimplementable as specified.** `IconMap.get` has no miss signal — `IconMap.kt:89-106` returns `Icons.Outlined.HelpOutline` at `:105` for any unresolved name and deliberately does not cache it. `"F11"` pascal-cases to a class that does not exist, so B renders a help glyph with no diagnostic on either side of the wire |
| To make B work | — | a new `IconMap.getOrNull`, and then a typo'd icon name silently becomes rendered body text — a silent semantic switch, exactly the guessing §12 rule 6 and §16.3 forbid |
| Author clarity | The author states which kind of trailing content they mean | The author cannot express "render this literally" for a string that happens to be an icon name |

**Recommendation: A.** Two narrow members cost one extra `field_types` row and
one exclusivity check that `validate.py` enforces in the arm above; B costs a
renderer change whose failure mode is invisible. The audit's own phrasing
("if it is typed as string-or-identifier", G-40) floats B without having
checked `IconMap`; the check has now been made.

### Design decision required — 2 of 2

**`supporting_text` forces an overload migration. Which cut?** Established
above: the only path to `supportingText` in 1.5.0-alpha16 is an
`@ExperimentalMaterial3ExpressiveApi` overload with a required `shape` and a
different `contentPadding` default. The draft is **A**.

| | A — per-menu branch (drafted) | B — per-item branch | C — defer `supporting_text` to G-79 |
|---|---|---|---|
| Wire this amendment lands | all three MenuItem members | all three | `trailing_icon` + `trailing_text` only |
| Menu with no `supporting_text` | today's exact call, unchanged | today's exact call, unchanged | today's exact call, unchanged |
| Menu with some `supporting_text` | every item in the expressive layout, one geometry per popup | supporting items expressive, siblings not — **two geometries in one popup**, different padding and container | n/a |
| Expressive opt-in in `InputNodes.kt` | yes, first one | yes | no — nothing here leaves the stable API |
| SPEC text needed | the "one item layout per menu" rule in edit 8 | a rule permitting mixed layout, which is not defensible | edit 8 loses its `supporting_text` clauses |
| Unblocks changed | none | none | none — `GroupedMenuSample` needs G-79 either way, and G-79 must adopt the expressive path for `DropdownMenuGroup`/`MenuDefaults.itemShape` regardless |
| Risk under no render-assertion harness | one branch, exercised by golden 79, unobserved visually | two branches, the mixed case unobserved and visibly wrong | none added |

**Recommendation: A**, with **C** as the honest fallback. C is worth real
consideration: `supporting_text` unblocks nothing on its own that G-79 does
not also require, G-79 has to take the expressive path anyway, and the
Companion has no composition test that could catch a layout regression here
(no `ui-test-junit4`, no `androidTest` source set — the four `render/` unit
tests assert on data). If the batch's appetite for unobserved rendering change
is low, land C and let G-79 carry `supporting_text` together with the
expressive machinery it already needs.
---

