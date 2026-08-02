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

* `ButtonWithAnimatedShapeSample` demonstrates shape morphing on press.
  The `button` node has no shape member → **unsupported**, even though
  a plain button would render.
* `FilledTonalButtonSample` demonstrates the tonal variant, and
  `button` has `:variant "tonal"` → **supported**.

The reason string is shown to the user.  Make it a sentence that names
the missing wire member or node type, e.g.

> The button node has no shape member: M3 shape morphing on press
> (ButtonDefaults.shapes) is a Companion-side visual the wire cannot
> ask for.

`docs/lookup-tables/M3-COMPONENT-LOOKUP.org` is the authority on which
M3 components Jetpacs wraps (30 wrapped, 14 available-but-unwrapped).
An unwrapped component (Carousel, SearchBar, SegmentedButton,
NavigationRail, RadioButton, ModalBottomSheet, Tooltip, ListItem,
ExposedDropdownMenu, DateRangePicker …) means its samples are
unsupported **unless** the sample's point survives composition from
wrapped nodes.

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
5. Every tap handler is `(jetpacs-m3-demo "…")`, which pops a **toast**
   — `jetpacs-shell-notify` injects `scaffold.snackbar` only when the
   pushed spec's `:t` is `"scaffold"`, and this app's root is a
   `multi_view`, so every message takes the non-scaffold fallback.
   Never register new actions from a component module.
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
                :scroll t :fill t)
(jetpacs-column CHILD… :spacing DP :align "start|center|end" :arrange … :scroll t :fill t)
(jetpacs-flow-row CHILD… :spacing DP :run-spacing DP :align "top|center|bottom" :arrange …)
(jetpacs-box    CHILD… :alignment "top_start|top_center|top_end|center_start|center|
                                   center_end|bottom_start|bottom_center|bottom_end"
                :on-tap D)
(jetpacs-surface CHILD… :color ROLE :shape "rounded|rounded_small|circle" :elevation DP)
(jetpacs-lazy-column CHILD… :spacing DP :content-padding DP)
(jetpacs-card CHILD… :on-tap D :on-long-tap D :swipe-start SWIPE :swipe-end SWIPE)
(jetpacs-swipe LABEL :icon N :color ROLE :on-trigger D)          ; on-trigger REQUIRED
(jetpacs-collapsible ID HEADER-NODE CHILD… :collapsed t :on-long-tap D)
(jetpacs-reorderable-list ITEMS :on-reorder D)                   ; every item needs :key/:id
(jetpacs-tabs (list (jetpacs-tab-item LABEL :icon N) …) (list NODE …)
              :initial N :scrollable t :pager-only t :on-change D :id ID)
(jetpacs-table (list (jetpacs-table-row "head|body" CELL…) (jetpacs-table-rule) …)
               :aligns '("start" "end") :on-add-row D :on-add-col D)
(jetpacs-table-cell (list (jetpacs-span "x")) :on-tap D :on-long-tap D)
(jetpacs-spacer) (jetpacs-divider :color ROLE :thickness DP)

;; input
(jetpacs-button LABEL ON-TAP :icon N :variant "filled|tonal|outlined|text" :enabled :json-false)
(jetpacs-icon-button ICON ON-TAP :content-description S :badge "3" :enabled …)
(jetpacs-chip LABEL :on-tap D :selected t :icon N :enabled …)         ; FilterChip
(jetpacs-assist-chip LABEL :on-tap D :icon N :enabled …)              ; AssistChip
(jetpacs-menu (list (jetpacs-menu-item LABEL ON-TAP :icon N :enabled …) …) :icon N)
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
```

Color roles (`docs/lookup-tables/COLORS-REFERENCE.org`): `primary`,
`on_primary`, `primary_container`, `on_primary_container`, `secondary`,
`on_secondary`, `secondary_container`, `on_secondary_container`,
`tertiary`, `on_tertiary`, `tertiary_container`,
`on_tertiary_container`, `error`, `on_error`, `error_container`,
`on_error_container`, `background`, `on_background`, `surface`,
`on_surface`, `surface_variant`, `on_surface_variant`, `outline`,
`success`, `on_success`, `warning`, `on_warning` — or `#RRGGBB`.

**Not node types** (do not reach for them): NavigationBar,
NavigationRail, SearchBar, SegmentedButton, Carousel, ModalBottomSheet,
Tooltip, ListItem, RadioButton, DateRangePicker, ExposedDropdownMenu.

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
