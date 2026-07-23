# W9 feature-parity checklist (poc-v1 organs → conformant rewrite)

Date: 2026-07-23. W9 ports poc-v1's port-safe renderer/chrome organs into the
conformant rewrite (`companion/`), with the EBP 2.0.0-draft **format-6**
vocabulary. This is the W9 exit gate: the parity of *what the device can
render*, node-type by node-type, against the promoted contract.

**Automated gate.** `test/smoke-parity.el` drives every NODE vector in
`ebp/goldens/widgets.golden` (the corpus that covers all 39 node types) through
a live session as an `app:main` surface root: **61/61 applied**. The remaining
11 golden vectors are ActionDescriptor/builtin shapes with no `t` — not surface
roots — and are exercised by the wire golden-replay + action tests instead.
`NodeSupportPinTest` pins the renderer's flat `when(type)` dispatch to the
advertised `surface_profiles`, so advertisement and rendering can never drift.

## Node coverage (all 39 contract types render)

| Family | Types | Atom | Renderer |
|---|---|---|---|
| Core (8) + editor/scaffold | text, row, column, box, spacer, divider, button, text_input, editor, scaffold | W9-b/d/g/i | Renderer.kt, InputNodes.kt |
| Content (7) | rich_text, icon, badge, section_header, empty_state, progress, date_stamp | W9-c | ContentNodes.kt |
| Image (1) | image | W9-j | ContentNodes.RenderImage + ImageLoader |
| Input (10) | icon_button, chip, assist_chip, menu, checkbox, switch, enum_list, slider, date_button, time_button | W9-d | InputNodes.kt |
| Layout (8) | flow_row, surface, lazy_column, card, collapsible, reorderable_list, tabs, table | W9-e | LayoutNodes.kt |
| Visualization (3) | chart, canvas, month_grid | W9-k | VisualizationNodes.kt |

## Feature coverage

| Feature | Atom | Status | Verification |
|---|---|---|---|
| §16.5 universal attributes (key/padding/sizes/fill/aspect/weight/bg/corner/border/alpha/clip/align_self) | W9-b | ✅ | NodeSupportPinTest + smoke-attrs.el |
| §16.6 color model (roles + #rgb/#rgba/#rrggbb/#rrggbbaa, legible fallback) | W9-b | ✅ | pin test hex forms |
| §16.1 presentation identity (key > id > tree path) for tabs/collapsible/month_grid | W9-e/k | ✅ | smoke-layout.el (tabs survive re-push) |
| §17.4 `enabled` on every input; state.changed before on_change; discrete slider exact value; no implicit selection | W9-d | ✅ | smoke-inputs.el |
| §14.2 builtins (view.switch + view.switched, clipboard/share/settings, trigger.fire) + multi-view | W9-f | ✅ | BuiltinTest + smoke-views.el |
| §14.3 injection (on_reorder from/to/order, on_add_row/col index, swipe direction) | W9-e | ✅ | wire injection test + smoke-layout.el |
| §17.6 scaffold (top_bar/body/bottom_bar/fab/floating_toolbar/drawer/on_refresh/snackbar) | W9-g | ✅ | smoke-chrome.el |
| §18.4 theme mirror (25 roles + success/warning extension) + persistence | W9-h1 | ✅ | ThemeModelTest + smoke-theme.el |
| §18.4 syntax fontification (SyntaxStyle map → text/text_input/editor) | W9-h2 | ✅ | SyntaxHighlightTest + smoke-syntax.el |
| §17.7 editor toolbar (snippet subst + `$${` escape + placements + 4 line ops + command) | W9-i | ✅ | ToolbarEditsTest + EditorCommandTest + smoke-toolbar.el |
| §17.2 image guard stack (HTTPS-only, no ambient creds, SSRF address checks, redirect budget, byte/pixel/decoded limits, data:image validation) | W9-j | ✅ | ImageGuardsTest + smoke-image.el |
| §17.5 chart on_point_tap (complete point), canvas op program, month_grid day/month taps + max_chart_points/max_canvas_ops | W9-k | ✅ | smoke-viz.el |
| §18.5 notification meta (channel/ongoing/category/priority/chronometer) + actions (inline reply, safe-admission dismiss) | W9-l | ✅ | NotificationActionTest + smoke-notif.el |

## Format-6 vocabulary drift fixed during the port

- slider `steps` → discrete `values` (returns the exact authored number, not a
  toolkit-computed step).
- enum_list string options → `{label, value}` objects; no implicit first
  selection; `allow_add` publishes a local string without mutating the list.
- rich span members: `strike`/`tag`/`baseline`/`code` gone (`code` → `mono`).
- date_stamp `day`/`year` are integers.
- legacy single-action `on_swipe` dropped; only `swipe_start`/`swipe_end`.
- canvas ops: `w`/`h` → `width`/`height`, `r` → `radius`, `stroke` →
  `stroke_width`, `[x,y]` path points → `{x,y}`, `fill` is a Color (not a bool).
- chart `on_point_tap` returns the COMPLETE authored point (was `{index,y}`).
- toolbar `$${` yields a literal `${` (the poc would have substituted it).
- theme `syntax` roles are SyntaxStyle objects `{fg,bg,font_weight,italic,
  underline}`, not bare colors.
- `enabled` honored on every input (the poc ignored it).

## Deferred past W9 (unchanged from the plan)

- Home-screen **widget** + Quick-Settings **tile** chrome (separate
  presentation stacks; the tile also awaits the amendment-#39 register
  question).
- **App shell** (Onboarding/Settings) — the dev flow keeps the §9.3 KAT
  pairing; `companion.settings.open` shows a visible stub.
- The **elisp application layer** + minibuffer/completion rebuild — it consumes
  exactly the advertised `surface_profiles` W9 produced (`NodeSupport` is the
  seam contract).
- **RadialMenu** gesture polish (time-boxed drop; pie menus still render via the
  existing W7 path).
