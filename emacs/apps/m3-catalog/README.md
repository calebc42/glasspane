# The Material 3 Expressive Catalog, in Elisp

A faithful re-creation of
`resources/android/Compose-Material-3-Expressive-Catalog` as a Jetpacs
Tier-1 app: **41 components, 279 examples**, three screens deep, all
authored in Elisp and rendered by the Companion.

```
emacs/jetpacs-m3-catalog.el          entry point: requires everything, registers the app
emacs/apps/m3-catalog/
  jetpacs-m3-core.el                 model + the three screens + the verbs
  jetpacs-m3-<slug>.el   x41         one module per upstream component
test/jetpacs-m3-catalog-test.el      the exit gate (builds every screen)
tools/m3-check.el                    per-component gate, for authoring one module
```

Navigation mirrors upstream `NavGraph.kt`: **Home** (a grid of
components) → **Component** (icon, description, its examples) →
**Example** (one sample, centered).  That is exactly
`jetpacs-chrome-max-screens` (3), so the stack never evicts.

## The fidelity rule

Every upstream component and every upstream example is listed, **in
upstream order, with the upstream name, description, source url and
`isExpressive` flag**.  An example is one of:

* `:build FN` — the sample re-created with EBP nodes, or
* `:unsupported REASON` — drills into a **"Not supported"** screen
  showing REASON.

Never drop, rename, reorder or merge an example.  The catalog's job is
to be a complete index of M3; the gaps are part of the map.

### When is an example `:unsupported`?

Ask: **what does this sample exist to demonstrate?**  If the wire
cannot carry *that*, it is unsupported — even when something vaguely
similar could be drawn.

* `FancyIndicatorContainerTabs` demonstrates an indicator whose two
  EDGES spring to the selected tab at different stiffnesses.  The
  `indicator` member carries a bounded picture vocabulary, not a custom
  Animatable pair → **unsupported**, even though ordinary tabs would
  render.
* `FilledTonalButtonSample` demonstrates the tonal variant, and
  `button` has `:variant "tonal"` → **supported**.
* `ButtonWithAnimatedShapeSample` was this section's unsupported
  example for weeks — until `button` grew `:animate-shape`.  A reason
  string that names the exact missing member is what makes that flip a
  one-line diff later.

The reason string is shown to the user.  Make it a sentence that names
the missing wire member or node type, and keep it TRUE — when a member
lands, every reason that mentioned its absence must be rewritten or
retired in the same change.

`docs/lookup-tables/M3-COMPONENT-LOOKUP.org` is the historical
authority on which M3 components Jetpacs wraps; the sprint outgrew its
counts.  The vocabulary now stands at **52 node types** — Carousel,
SearchBar, SegmentedButton, NavigationRail, ModalBottomSheet (the
scaffold `sheet` slot), Tooltip, ExposedDropdownMenu (`dropdown`),
FabMenu, ButtonGroup, LazyGrid and the app-bar strips all became
nodes during the catalog work.  Still deliberately absent: ListItem
(compose it from rows), RadioButton (`enum_list` is the one
single-selection stateful node), NavigationBar (compose a bottom bar),
DateRangePicker.  A sample over an absent component is unsupported
**unless** its point survives composition from real nodes.

## Authoring a module

1. Read the upstream sample file
   (`app/src/main/java/com/emertozd/compose/catalog/samples/<X>Samples.kt`)
   for every example in your module.
2. Keep the generated `jetpacs-m3-example` entries exactly as they are
   — only replace `:unsupported "TODO: not yet triaged"` with a real
   `:build` or a real `:unsupported`.
3. Put each sample in its own `defun jetpacs-m3-<slug>--<name>` above
   the `jetpacs-m3-defcomponent` form, with a docstring naming the
   upstream sample.  A builder takes no arguments and returns ONE root
   node.
4. Re-use the upstream sample's own strings ("Like", "Elevated
   Button", "Localized description") — that is most of the fidelity.
5. Tap handlers climb a ladder — use the LOWEST rung that carries the
   sample's point.  `(jetpacs-m3-demo "…")` pops a real
   `scaffold.snackbar` and mutates nothing: right for a sample whose
   upstream handler only proves the tap landed.  A sample whose
   upstream REMEMBERS one boolean uses `(jetpacs-m3-flag-action KEY)`
   + `(jetpacs-m3-flag KEY)` — the verb flips it in Emacs and
   re-pushes.  One gesture mutating SEVERAL remembered values registers
   a nullary mutation in `jetpacs-m3-fn-registry` and authors
   `(jetpacs-m3-fn-action KEY)`; upstream's `selectedIndex` pattern is
   `jetpacs-m3-defselection` + `jetpacs-m3-selection-action`.  A modal
   dialog registers its §18.1 spec in `jetpacs-m3-dialog-registry`.
   Never `jetpacs-defaction` from a component module — the registries
   are the door.
6. Stateful nodes (`checkbox`, `switch`, `slider`, `text_input`,
   `enum_list`, `collapsible`, `tabs`) need an `id` that is **unique
   across the whole app**: prefix it with the slug, e.g.
   `"checkboxes-tristate"`.
7. Icons must exist in `docs/lookup-tables/M3-ICON-REFERENCE.org`
   (2075 names, snake_case: `favorite`, `more_vert`, `keyboard_arrow_right`).
   A misspelled icon silently renders a placeholder on device, so
   `tools/m3-check.el` fails on one instead.

### Gate (must pass before you are done)

```sh
cd llm-poc-2 && tools/m3-check.sh <slug>
```

It byte-compiles the module with warnings as errors (into a temp
directory, so concurrent checks cannot shadow each other with a stale
`.elc`) and then builds every screen the component contributes,
checking the §16.2 profile, §16.1 id uniqueness, canonical
serialization, icon names, and that nothing still carries the triage
sentinel.  The whole-app gate is
`test/jetpacs-m3-catalog-test.el`.

## Node vocabulary cheat-sheet

Full reference: `docs/lookup-tables/WIDGET-REFERENCE.org`; the
constructors and their validation live in `emacs/jetpacs-widgets.el`.
Enum values are **strings**.  Booleans are `t` (true) or `:json-false`
(explicit false); omit for the default.  Universal attributes
(`:key :id :padding :width :height :weight :fill_fraction :alpha :bg
:corner :pad :border :align_self :clip :aspect_ratio :min_width
:max_width :min_height :max_height :scroll_here`) attach with
`jetpacs-with-attrs`, never as constructor arguments.

```elisp
;; content
(jetpacs-text TEXT :style "body|title|headline|caption|label|mono"
              :font-weight "bold"|100..900 :color ROLE :selectable t
              :max-lines N :syntax "elisp")
(jetpacs-rich-text (list (jetpacs-span TEXT :font-weight "bold" :italic t
                                       :underline t :color R :bg R :mono t
                                       :on-tap D)) :style "body")
(jetpacs-icon NAME :size DP :color ROLE :badge "3" :content-description S)
(jetpacs-badge LABEL :icon NAME :color ROLE :children (list …))
(jetpacs-image URL :content-scale "fit|crop|fill_width|fill_height|inside"
               :content-description S)   ; https:// or data:image/ only
(jetpacs-section-header TITLE :trailing NODE)
(jetpacs-empty-state :icon N :title S :caption S :action-label S :on-tap D)
(jetpacs-progress :variant "linear|circular" :value 0.0..1.0)  ; omit value = indeterminate
(jetpacs-date-stamp :day N :month S :month-index N :year N :time S)

;; layout  (children as &rest or one list, then trailing options)
(jetpacs-row    CHILD… :spacing DP :align "top|center|bottom|baseline"
                :arrange "start|center|end|space_between|space_around|space_evenly"
                :scroll t :fill t :overlap DP :content-padding DP) ; padding INSIDE the scroll viewport
(jetpacs-column CHILD… :spacing DP :align "start|center|end" :arrange … :scroll t
                :reverse-scroll t :fill t :overlap DP)  ; overlap = spacedBy(-DP), excludes :spacing
(jetpacs-flow-row CHILD… :spacing DP :run-spacing DP :align "top|center|bottom" :arrange …)
(jetpacs-box    CHILD… :alignment "top_start|top_center|top_end|center_start|center|
                                   center_end|bottom_start|bottom_center|bottom_end"
                :on-tap D)
(jetpacs-surface CHILD… :color ROLE :elevation DP :shadow-elevation DP
                 :shape "rounded|rounded_small|circle" ; or any MaterialShapes name:
                 )                                     ; arch, sunny, ghostish, heart, … (34)
(jetpacs-lazy-column CHILD… :spacing DP :content-padding DP)
(jetpacs-card CHILD… :on-tap D :on-long-tap D :swipe-start SWIPE :swipe-end SWIPE)
(jetpacs-swipe LABEL :icon N :color ROLE :on-trigger D)          ; on-trigger REQUIRED
(jetpacs-collapsible ID HEADER-NODE CHILD… :collapsed t :on-long-tap D)
(jetpacs-reorderable-list ITEMS :on-reorder D)                   ; every item needs :key/:id
(jetpacs-tabs (list (jetpacs-tab-item LABEL :icon N :badge S :tooltip S
                                      :content NODE :selected-content NODE) …)
              (list NODE …) :initial N :scrollable t :pager-only t :on-change D
              :id ID :style "primary|secondary" :indicator (list :kind "outline"))
(jetpacs-table (list (jetpacs-table-row "head|body" CELL…) (jetpacs-table-rule) …)
               :aligns '("start" "end") :on-add-row D :on-add-col D)
(jetpacs-table-cell (list (jetpacs-span "x")) :on-tap D :on-long-tap D)
(jetpacs-spacer :width DP :height DP :weight N) (jetpacs-divider :color ROLE :thickness DP)

;; input
(jetpacs-button LABEL ON-TAP :icon N :variant "filled|tonal|elevated|outlined|text"
                :size S :shape "round|square" :animate-shape t :expanded t|:json-false|"auto"
                :checked B :on-change D :checked-shape S :checked-icon N :shape-role S
                :color ROLE :enabled :json-false)  ; :checked makes a ToggleButton (needs :id)
(jetpacs-icon-button ICON ON-TAP :content-description S :badge "3" :enabled …)
(jetpacs-chip LABEL :on-tap D :selected t :icon N :enabled …)         ; FilterChip
(jetpacs-assist-chip LABEL :on-tap D :icon N :enabled …)              ; AssistChip
(jetpacs-menu ITEMS :icon N :initial-scroll "end" :footer NODE
              :groups (list (jetpacs-menu-group LABEL ITEMS) …))  ; exactly one of ITEMS/:groups
(jetpacs-menu-item LABEL ON-TAP :icon N :supporting-text S :trailing-icon N
                   :checked B :checked-icon N :enabled …)  ; checked = authored state
(jetpacs-checkbox ID :checked t :label S :on-change D :enabled …)
(jetpacs-switch   ID :checked t :label S :on-change D :enabled …)
(jetpacs-enum-list ID (list (jetpacs-enum-option LABEL VALUE) …)
                   :value V :multi-select t :allow-add t :on-change D :enabled …)
(jetpacs-slider ID ON-CHANGE :value N :min N :max N :values (list 0 1 2) :enabled …)
(jetpacs-date-button LABEL ON-PICK :value "2026-07-28" :enabled …)
(jetpacs-time-button LABEL ON-PICK :value "09:30" :enabled …)
(jetpacs-text-input ID :value S :hint S :label S :on-change D :on-submit D
                    :single-line t :min-lines N :max-lines N :monospace t
                    :syntax S :password t :keyboard "text|number|decimal|email|phone|uri"
                    :autofocus t :clear-on-submit t :enabled …)

;; visualization
(jetpacs-chart (list (jetpacs-chart-series (list (jetpacs-chart-point X Y) …) …)) …)
(jetpacs-canvas W H (list (jetpacs-canvas-rect X Y W H :fill ROLE) …))
(jetpacs-month-grid "2026-07" :marks HASH :on-day D)

;; added during the catalog sprint (docstrings are the reference)
(jetpacs-bool X)                          ; nil -> :json-false, else t — authored live state
(jetpacs-search-bar ID :hint S :on-change D :on-submit D …)
(jetpacs-dropdown ID OPTIONS :value V :label S :editable t :on-change D)
(jetpacs-segmented-button ID OPTIONS :value V :multi-select t :on-change D)
(jetpacs-navigation-rail (list (jetpacs-rail-item LABEL ICON ON-TAP :selected B) …)
                         :variant "standard|wide|modal" :expanded B :arrangement S
                         :header NODE :on-expand-change D :hide-on-collapse t)
(jetpacs-app-bar-row (list (jetpacs-app-bar-item ICON ON-TAP :label S) …))  ; measure-time overflow
(jetpacs-carousel CHILD… :strategy "multi_browse|uncontained|centered_hero"
                  :item-width DP :item-spacing DP :content-padding DP :item-corner DP)
(jetpacs-fab-menu (list (jetpacs-fab-menu-item LABEL ICON ON-TAP) …) :icon N …)
(jetpacs-button-group (list (jetpacs-button-group-item LABEL ON-TAP :icon N) …))
(jetpacs-lazy-grid CHILD… :columns N :min-item-width DP :spacing DP)
(jetpacs-tooltip CHILD… :text S :rich t :title S :action-label S :on-action D :shown B)
(jetpacs-slider ID ON-CHANGE :value-end N :track S :orientation "vertical"
                :value-label S :track-icon-start N :track-icon-end N …)  ; range/vertical forms
(jetpacs-checkbox ID :state "off|on|indeterminate" :stroke (list :width DP :cap S :join S) …)
(jetpacs-scaffold :top-bar N :body N :bottom-bar N :fab N :drawer N :rail N :sheet N
                  :snackbar S :snackbar-content N :top-bar-style S :scroll-behavior S
                  :top-bar-expanded N :drawer-variant S :bottom-bar-behavior S
                  :fab-position S :fab-hide-on-scroll t …)  ; see its docstring — §17.6 is large
```

Color roles (`docs/lookup-tables/COLORS-REFERENCE.org`): `primary`,
`on_primary`, `primary_container`, `on_primary_container`, `secondary`,
`on_secondary`, `secondary_container`, `on_secondary_container`,
`tertiary`, `on_tertiary`, `tertiary_container`,
`on_tertiary_container`, `error`, `on_error`, `error_container`,
`on_error_container`, `background`, `on_background`, `surface`,
`on_surface`, `surface_variant`, `on_surface_variant`, `outline`,
`success`, `on_success`, `warning`, `on_warning` — or `#RRGGBB`.

**Not node types** (do not reach for them): NavigationBar (compose a
bottom bar), ListItem (compose rows), RadioButton (`enum_list`),
DateRangePicker (`month_grid` carries `range_start`/`range_end`).
Everything else that once sat on this list — NavigationRail, SearchBar,
SegmentedButton, Carousel, ModalBottomSheet, Tooltip,
ExposedDropdownMenu — became a node or a scaffold member during the
catalog sprint; reach for the constructor.

## Samples that ARE screen chrome

A Node tree cannot nest a `scaffold` inside a `scaffold`, and the
Example screen already is one.  So a sample whose subject is a scaffold
slot claims **this screen's** slot instead — which is exactly what it
was demonstrating upstream:

```elisp
(jetpacs-m3-example
 "SimpleBottomAppBar" "App bar examples"
 :source jetpacs-m3-bottom-app-bar--source
 :slots (list :bottom-bar #'jetpacs-m3-bottom-app-bar--simple))
```

* `:slots` — a plist over `:fab`, `:bottom-bar`, `:drawer`,
  `:floating-toolbar`, `:on-refresh` (an action descriptor) and
  `:snackbar` (a string).  Every value is a **nullary function**
  returning the node, except `:snackbar`, which is the string itself.
  Covers FloatingActionButton, Bottom App Bar, Navigation bar (as a
  bottom bar of icon buttons), Navigation drawer, Snackbars,
  Pull-to-Refresh and Floating Toolbar samples.
* `:top-bar` — a function of one argument BACK returning the screen's
  whole `top_bar` node, for Top app bar samples.  It **must** offer a
  way back: start the row with `(jetpacs-m3-back-button back)`.
* `:build` is still the body, and may be combined with either.  With
  slots and no `:build`, the body becomes a caption naming the slots.

Give the sample its upstream shape: `SimpleBottomAppBar` really is a
row of icon buttons with the M3 actions upstream picked (check, edit,
mic, image), so author those, with `(jetpacs-m3-demo "…")` handlers.
