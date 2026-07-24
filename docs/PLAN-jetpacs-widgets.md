# PLAN — `jetpacs-widgets.el`, the Emacs-side node-vocabulary builders

The Emacs counterpart to the W9 Kotlin renderer: the application-layer builders
that **construct** the 39-node widget vocabulary (SPEC §16 attributes + §16.6
colors + §17 families) and hand it to `ebp.el` for push. An **independent
implementation of the same `ebp/` spec** as the Kotlin companion — guided by
`ebp/SPEC.md` + `ebp/contract.json` + `ebp/goldens/`, not ported from Kotlin.

Status of the two sides:

- **Kotlin (companion/app):** W9 done 2026-07-23 — all 39 node types render;
  parity gate `test/smoke-parity.el` 61/61 applied.
- **Emacs (this plan):** greenfield. The endpoint (`ebp.el`) is finished through
  the surface-push seam; **no `jetpacs-*.el` exists yet.**

---

## 0. Decisions locked (2026-07-23)

1. **Home:** a new `jetpacs-widgets.el` in the **`jetpacs-` application layer**,
   which `(require 'ebp)` and calls `ebp-client-surface-update`. Per REWRITE-PLAN
   §"The ebp.el boundary": ebp.el is the endpoint (jsonrpc.el analogue), builders
   are the application. **`ebp.el` needs no changes** — its push seam is complete.
   The delineation guard keeps ebp.el jetpacs-free; the dependency arrow
   `jetpacs → ebp` is intended and allowed.
2. **Conformance gate:** byte-parity ERT (offline, deterministic) **plus** a live
   "applied" smoke. See §7.

---

## 1. Why this is lower-risk than it looks

- **The `ebp.el` seam is done — zero endpoint work.** `ebp-client-surface-update`
  (`emacs/ebp.el:1115`, public `cl-defun`) already claims/owns revisions, absorbs
  floors, carries `stale-after-s` / `stale-spec` / `current-view` /
  `reset-input-ids` / `callback (status error)`. Removal: `ebp-client-surface-remove`
  (`:1135`). Dialog push, toasts, themes, reminders, triggers, capabilities, pie,
  editor-sync, action registry, input reads — all already have public
  `ebp-client-*` entry points. ebp.el treats the node tree as **opaque**; the
  device returns `"applied"`/`"stale"` and that is the only push-path check.
- **poc-v1 already has full 39-type coverage to port.** `llm-poc/emacs/core/jetpacs-widgets.el`
  (1432 lines) has exactly one primary constructor per type. The work is **shape
  drift + serialization**, not missing types.
- **Two genuinely new problems** (neither existed in poc-v1): a **key-sorting
  canonical serializer** and a **generic universal-attribute rider**. §4.

---

## 2. Data model & the two serialization contexts

**Node = a plist** keyed by `:t` (type string) plus keyword members; **children
are vectors of plists**; nested descriptors (`:on_tap`, spans, options, ops) are
plists / vectors of plists. This is the exact shape `ebp-client-surface-update`
expects (verified against `test/smoke-widgets.el` / `smoke-inputs.el`):

```elisp
(:t "column" :padding 16
 :children
 [(:t "text" :text "Input nodes" :style "headline")
  (:t "checkbox" :id "cb" :label "Flip me" :on_change (:action "demo.cb"))
  (:t "slider" :id "sl" :values [1 5 9] :on_change (:action "demo.sl"))
  (:t "button" :label "Never" :enabled :json-false :on_tap (:action "demo.never"))
  (:t "enum_list" :id "en" :multi_select t
   :options [(:label "Alpha" :value "a") (:label "Gamma" :value 3)])])
```

**Booleans / absence (one representation, two sinks):**

| meaning | builder emits |
|---|---|
| JSON `true` | `t` |
| JSON `false` | `:json-false` |
| absent | **omit the key** (never `nil`, never JSON `null`) |

**The two serialization contexts — do not conflate them:**

| context | serializer | key order | `false` | gate |
|---|---|---|---|---|
| **Live push** | jsonrpc.el (`jsonrpc--json-encode`: `:false-object :json-false :null-object nil`) | insertion order (device doesn't care) | `:json-false` | device returns `"applied"` |
| **Golden byte-parity test** | our canonicalizer | **sorted, recursively** | bareword `false` | `string=` golden line |

The goldens are literally `json.dumps(obj, sort_keys=True, separators=(",",":"),
ensure_ascii=False)` (`ebp/validate.py:417`). Emacs `json-serialize` is compact
and emits raw UTF-8 (both match) but **does NOT sort keys** — the only real gap.
So one plist representation feeds both paths; the canonicalizer is a test-time
concern, the live path just hands plists to `ebp.el`.

---

## 3. Module layout

Start single-file (mirrors poc-v1), split by family later only if it grows unwieldy.

| File | Contents |
|---|---|
| `jetpacs-widgets.el` | the `jetpacs--node` funnel; `jetpacs--children-and-opts`; the **generic universal-attribute rider**; the **color helper**; **ActionDescriptor + builtin** constructors; **surface-shape wrappers** (§13.4); all 39 node constructors + sub-spec constructors |
| `jetpacs-widgets-canonical.el` *(or a section)* | `jetpacs-node->canonical-json` — recursive key-sort serializer, test-only |
| `test/jetpacs-widgets-test.el` | byte-parity ERT over `widgets.golden` + `hypertext.golden` + the 39-type/action coverage floor |
| `test/smoke-widgets-builders.el` | live "applied" smoke: build trees via the DSL, push, assert `applied` |

Namespace `jetpacs-`; `Package-Requires: ((emacs "30.1"))`; `lexical-binding: t`;
`setopt` for any `defcustom`. May `(require 'ebp)` + cl-lib + core libs only.

---

## 4. The two new problems

### 4.1 The canonical serializer (`jetpacs-node->canonical-json`)

Recursive descent that, for **every object at every depth**, emits members in
`string<` key order, compactly, with:

- ints bare (`5`, `700`, `86400`); floats shortest round-trip (`0.5`, `1.5`) —
  **preserve the caller's elisp numeric type** (`value` is polymorphic: int for
  slider, float for progress, string for enum, array for multi-select).
- `t → true`, `:json-false → false` (explicit, **never omitted** —
  `scroll:false`, `enabled:false`, `pager_only:false` all appear literally).
- nil-valued keys **dropped**; no `null` anywhere in the corpus.
- empty array `[]` preserved (`{"children":[],"t":"row"}`); raw UTF-8, no `\uXXXX`.

Simplest correct implementation: walk the plist, collect `(json-key . value)`
pairs, `sort` by key string, recurse into plist/vector values, then join. Reuse
`json-serialize` only for leaf string/number escaping; impose the sort yourself.

### 4.2 Generic universal-attribute rider (§16.5)

poc-v1 wired universals ad-hoc per constructor (text couldn't emit `key`/`bg`/
`corner`; icon couldn't emit `key`). Format-6's `node_schema."*"` makes all 20
legal on **every** node: `key id scroll_here padding pad width height min_width
max_width min_height max_height fill_fraction aspect_ratio weight bg corner
border alpha clip align_self`. Attach them **generically** — a trailing `&rest
attrs` merged by `jetpacs--node`, or a post-construction `jetpacs-with-attrs`
rider — rather than re-listing per constructor. Value grammars: `fill_fraction`
∈(0,1], `aspect_ratio`>0, `weight`>0, `alpha`∈[0,1]; `corner` = number or
`{top_start,top_end,bottom_start,bottom_end}`; `border` = `{width,color}`; `pad`
= `{start,top,end,bottom,horizontal,vertical}` (side wins over axis).

### 4.3 Color helper (§16.6)

A `Color` is a **theme-role id** OR hex `#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`
(case-insensitive; alpha is the last byte on the wire). 25 roles + `success`/
`warning` extension. The builder just passes the string through; a validation
helper may check role-membership/hex-shape. Unknown role is legal (device uses a
legible fallback) — don't reject it.

---

## 5. The rung ladder

PR-sized units, each landing with its exit gate green. Mirrors the W9 atom
decomposition so the two implementations stay legible against each other. Golden
line indices are into `ebp/goldens/widgets.golden` (00–60 nodes, 61–71 actions).

| Rung | Deliverable | Golden | Exit gate |
|---|---|---|---|
| **JW-0 Foundation** | `jetpacs--node` funnel (plist, nil-drop, `:t` tag) + `--children-and-opts` + generic universal rider (§4.2) + color helper (§4.3) + canonical serializer (§4.1) + `ebp-action`/`ebp-builtin`-style **ActionDescriptor & builtin** constructors honoring offline rules + the byte-parity test harness (golden reader, per-line `string=` + semantic-equal fallback) | 61–71 | canonicalizer round-trips a fixture set; all 11 action/builtin lines byte-match; offline-policy invariants enforced (dot in name; `queue`/`wake` ⇒ `ttl_s`; `drop` ⇒ no `ttl_s`/`dedupe`) |
| **JW-1 Content** | text, rich_text (+span), icon, image, date_stamp, section_header, empty_state, progress, badge. **Drift:** text gains `font_weight`/`syntax`/`key`; span drops `strike`/`tag`/`baseline`, `code`→`mono`, `bold`→numeric `font_weight`; date_stamp `day`/`year` **int**; image self-restricts to advertised `image.https`/`image.data` | 00–16 | lines byte-match; applied for each |
| **JW-2 Layout** | row, column, flow_row, box, surface, lazy_column, spacer, divider, card, collapsible, reorderable_list, tabs, table (+ TabItem/TableRow/Cell/Swipe). **Drift:** drop legacy `on_swipe` (card/collapsible) — only `swipe_start`/`swipe_end`. **Invariants:** reorderable items each need unique `key`\|`id`; tabs `items`≡`children` len, `initial`<count; table `kind`∈{data,header,rule}, `rule` has no cells; note `align` (row) vs `alignment` (box) vs `aligns` (table) | 17–34 | byte-match + applied |
| **JW-3 Input** | button, icon_button, chip, assist_chip, menu, text_input, checkbox, switch, enum_list, date_button, time_button, slider. **Drift:** add `enabled` to **every** input; enum_list options → `{label,value}` objects, no implicit selection, `value` scalar-vs-array by `multi_select`; slider `steps`→discrete `values` (≥2 strictly increasing, omit `min`/`max`, returns exact number). **Invariants:** `single_line` prohibits `\n`; `password:true` ⇒ no `value`/`on_change`; `clear_on_submit` invalid with builtin `on_submit` | 35–44, 48–55 | byte-match + applied |
| **JW-4 Editor + toolbar** | `editor` **local tier** (no `document`, `publish_state:true`, drafts + `on_save`/`capture_fields` — the orgseq standing decision) + ToolbarItem builders. **Rules:** ToolbarItem needs `label`\|`icon` + **exactly one** primary op ∈ {`snippet`,`on_tap`,`menu`,`command`,`line`}; `command`/`complete` require `document`; snippet ≤1 `${input:…}`, `$${`→literal `${`; `line`∈{promote,demote,move-up,move-down} | 45–47 | byte-match + applied; a doc-tier `command`/`complete` builder errors without `document` |
| **JW-5 Visualization** | chart (+series/point, optional `meta`; `x` required though ordinal), month_grid (marks map date→`{dots 0..3,color?}`), **canvas — clean rebuild** (ops `width`/`height`/`radius`/`stroke_width`, path points `{x,y}`, `fill` is a **Color**). Respect welcome `max_chart_points` (aggregate across series) / `max_canvas_ops` | 56–58 | byte-match + applied; unknown canvas op tolerated |
| **JW-6 Scaffold + surface shapes** | scaffold (named slots top_bar/body/bottom_bar/fab/floating_toolbar/drawer + snackbar/snackbar_action/on_refresh) + §13.4 SurfaceSpec wrappers: `app:*` (root Node \| multi-view `{views,initial_view}`), `notification:*` `{body,meta?}`, `widget:*` `{title,body,empty?,header_action?}`; `stale_spec` must match variant and carry no stateful/`editor` node | 59–60 | byte-match + applied; multi-view push + `current_view` update round-trips |
| **JW-7 Profile gating + hypertext + composites** | a **target-profile guard** so a builder refuses to place an unadvertised type in a dialog(26)/notification(6) tree (§16.2 self-restriction — Emacs MUST NOT emit an unadvertised type, even as fallback children) + `hypertext.golden` array builders + the pure-elisp composites (`jetpacs-list-item`/`-stat`/`-kv`/…) | hypertext 00–03 | hypertext lines byte-match; guard rejects `chart`-in-notification, `editor`-in-dialog |

**Follow-on (explicitly out of this plan, the broader "elisp application layer"):**
the downstream consumers `jetpacs-sections.el` / `-hypertext.el` / `-buffer.el` /
`-results.el` (generic Emacs-buffer→node renderers that *call* these builders),
`build-contract.el` re-pointed at format-6, and minibuffer/completion. Port after
the vocabulary API settles.

---

## 6. Format-6 drift checklist (the 15 deltas from poc-v1)

Apply during the port; each is a spot where a poc-v1 mental model emits wrong JSON:

1. slider `steps` → discrete `values` (exact authored number).
2. enum_list bare-string options → `{label,value}` objects; no implicit first selection.
3. rich span: drop `strike`/`tag`/`baseline`; `code`→`mono`.
4. date_stamp `day`/`year` → integers.
5. drop legacy single-action `on_swipe`; only `swipe_start`/`swipe_end`.
6. canvas ops: `w`/`h`→`width`/`height`, `r`→`radius`, `stroke`→`stroke_width`, `[x,y]`→`{x,y}`, `fill` bool→Color.
7. chart `on_point_tap` returns the complete authored point (companion-side; builder just must emit `x` on every point).
8. toolbar `$${` → literal `${` (snippet passes through; no builder change).
9. theme `syntax` roles are SyntaxStyle objects (theme mirror, **not** this layer).
10. `enabled` honored on **every** input (poc-v1 had it on none).
11. text node gains `font_weight` (distinct from layout `weight`).
12. text may carry `syntax` and `key` directly.
13. span `bold` (bool) → `font_weight` (number/string).
14. chart points gain optional `meta`.
15. universal attributes attach generically to every node (§16.5), not per-constructor.

---

## 7. Test strategy

**A. Byte-parity ERT — `test/jetpacs-widgets-test.el` (offline, deterministic).**
For each golden line `NN P`: build the node via the DSL, `jetpacs-node->canonical-json`
→ `G`; `(should (string= G P))`; on failure, secondary
`(should (equal (json-parse-string G) (json-parse-string P)))` to localize
float/key-order breaks. Route 00–60 through node builders, 61–71 through
action/builtin builders (on presence of `action`/`builtin`, mirroring
`validate.py:457`); cover `hypertext.golden` (each line is an **array**).
Add a **coverage-floor** test (mirror `validate.py:472`): assert the suite
exercises all 39 `contract.node_types` and every `actions.schema` form.

**Traps to encode as explicit cases:** key-sort at every depth (spans, cells,
canvas ops, `marks` object, scaffold slots, action `args`); `value` polymorphism;
`aspect_ratio` float; explicit `false` not omitted; absent-vs-null; `month` vs
`month_index`, `align`/`alignment`/`aligns`, `spacing`/`run_spacing`/
`content_padding`; `rule` rows have no `cells`; item identity via `key` OR `id`.

**B. Live "applied" smoke — `test/smoke-widgets-builders.el`.** Structural twin
of `smoke-parity.el`, but the tree comes from **builder calls**, not golden
literals: `ebp-connect` to `127.0.0.1:8765` (KAT pairing), push via
`ebp-client-surface-update … :callback`, assert `status "applied"`, `kill-emacs`
on the count. Catches renderer rejection the byte test can't see.

**Harness wiring.** `test/run-tests.sh` is the whole harness (no Makefile): gate 1
delineation (`ebp` alone, no `jetpacs-` symbols — unaffected, it never loads our
file), gate 2 byte-compile ebp.el warnings-as-errors, gate 3 ERT
`ebp-wire-test.el`. Add the builder ERT as a new `-l test/jetpacs-widgets-test.el`
line (may `(require 'jetpacs-widgets)`; stays out of gate 1). Byte-compile the
builder file warnings-as-errors too. Smokes run manually / via the adb harness,
not `run-tests.sh`.

---

## 8. Build target — the 39 types

Full field lists (required/optional/enums/defaults/limits) live in `ebp/SPEC.md`
§16–17 and `ebp/contract.json` `node_schema`; the golden gives the exact wire
shape per type. Families and counts (= 39): **content** 9 (text·, rich_text, icon,
image, date_stamp, section_header, empty_state, progress, badge) — §17.2;
**layout** 13 (row·, column·, flow_row, box·, surface, lazy_column, spacer·,
divider·, card, collapsible, reorderable_list, tabs, table) — §17.3; **input** 13
(button·, icon_button, chip, assist_chip, menu, text_input·, editor, checkbox,
switch, enum_list, date_button, time_button, slider) — §17.4; **visualization** 3
(chart, canvas, month_grid) — §17.5; **scaffold** 1 — §17.6. (· = Core Node Set,
mandatory.) Per-target advertised sets (respect in JW-7): **app** all 39;
**dialog** 26 (core-8 + content + input, no editor/scaffold/layout/viz);
**notification** 6 (text/row/column/box/spacer/divider).

---

## 9. Open decisions (flagged, not blocking)

- **Spec-driven vs hand-written constructors.** Recommend hand-written ergonomic
  `cl-defun &key` / `&rest` constructors (as poc-v1) with a **contract.json-driven
  coverage test**, rather than fully generating constructors from `node_schema`.
- **Canonicalizer location.** Test-only helper vs a shipped `jetpacs-widgets.el`
  function. Recommend shipping it (useful for a future non-jsonrpc transport and
  for golden regeneration), but it is not on the live push path.
- **File split threshold.** Single `jetpacs-widgets.el` to start; split into
  `-content`/`-layout`/`-input`/`-viz` only if it passes ~1.5k lines.

---

## 10. Concrete references

- Push seam: `emacs/ebp.el:1115` `ebp-client-surface-update` (revisions at `:1097`);
  removal `:1135`; struct `:490`; `ebp-connect` `:1266`.
- Corpus: `ebp/goldens/widgets.golden` (00–60 nodes / 61–71 actions),
  `ebp/goldens/hypertext.golden` (arrays). Canonical formula: `ebp/validate.py:417`;
  schema/offline/coverage: `ebp/validate.py:137–201, 472–483`.
- Contract: `ebp/contract.json` `node_schema` / `universal_node_attributes` /
  `theme_roles` / `actions.schema` / `offline_policies`.
- Spec: `ebp/SPEC.md` §16 (1655–1771), §17 (1772–2190), §13.4 (1089–1155).
- Port source: `llm-poc/emacs/core/jetpacs-widgets.el` (funnel `:15`,
  children-split `:31/:47`); drift list `docs/W9-feature-parity.md`.
- Boundary/harness: `docs/REWRITE-PLAN.md` §"ebp.el boundary" (L61–84);
  `test/run-tests.sh`; templates `test/smoke-parity.el` / `smoke-widgets.el` /
  `smoke-inputs.el`.
- Kotlin parity refs (independent impl, cross-check only): `companion/app/.../render/`
  {Renderer, ContentNodes, InputNodes, LayoutNodes, VisualizationNodes,
  Attributes, ColorModel, NodeSupport}.kt; advertised sets `AppCapabilities.kt`.
