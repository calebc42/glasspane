# Glasspane app rebuild ladder (v1 → v3 port)

Status: G0–G8 ALL LANDED 2026-08-13/14 (G1 c36be82, G2 479dc06, G3
4719ca8, G4 78612e7, G5 68ad844, G6 369d75f, G7 2add74e, G8 f2c6e2b;
final gate 984 tests / 41 suites, 0 unexpected, independently re-run).
Pre-G9 punch list SWEPT 2026-08-14: all 40 advisories dispositioned
(24 fixed, 11 test strengthenings, 4 wontfix, 1 deferred), gate 989
tests / 41 suites, 0 unexpected. Remaining: G9 (device gate), preceded
by the hub-wiring rung that punch-list #26 escalates to the ladder;
two device-only residuals (#2, #20) ride the G9 checklist.
G1 LANDED 2026-08-13 (data layer: glasspane-org.el + glasspane-vulpea.el;
gate 11/11, full suite 934/41). G2 LANDED 2026-08-13 (services:
glasspane-clock.el + glasspane-config.el + glasspane-packages.el;
gate 21/21, full suite 944/41). G3 LANDED 2026-08-13 (keystone:
glasspane-ui.el — settings surface, shared view defvars, at-ref
funnel; gate 25/25, full suite 948/41). G4 LANDED 2026-08-13 (reader +
detail: glasspane-org-reader.el + glasspane-detail.el — foldable
reader claims the files body seam, detail is a pushed screen, prompt
arms delegated to the foundation dialogs; gate 31/31, full suite
954/41). G5 LANDED 2026-08-14 (daily surfaces: glasspane-agenda.el +
glasspane-journal.el + glasspane-capture.el + glasspane-dates.el —
agenda/tasks/journal as pushed chrome screens, capture's one-dialog
S3 sheet chain, the gap-#10 date helpers; gate 39/39, full suite
962/41). G6 LANDED 2026-08-14 (query surfaces: glasspane-views.el +
glasspane-search.el + glasspane-table.el — views as a real pushed
stack with app-owned kanban board, search's S2 offline screen with
the sexp query builder, table's app-authored mutable nodes over the
--table-mutate funnel; gate 47/47, full suite 970/41). G7 LANDED
2026-08-14 (knowledge arms: glasspane-notes.el + glasspane-srs.el —
wikilink capf on the ebp-complete shadow bridge, mentions dissolved
into the jetpacs-async keyed loader, SRS review as a pushed chrome
screen with the in-screen due count, engine wrapper reworked so a
failed call never answers 'accepted; vulpea/org-srs guarded, live
paths banked for G9; gate 53/53, full suite 976/41). G8 LANDED
2026-08-14 (satellites + fixtures: glasspane-ef.el +
glasspane-theme-picker.el + glasspane-demo.el + glasspane-gallery.el —
ef-themes screen on the app-local picker scaffold (gap #8), demo
seeder kept with roots-derived targets, gallery gauge rebuilt on
canvas; gate 61/61, full suite 984/41). Next: G9 (DEVICE GATE — the
one device/vulpea smoke session that closes the ladder). The completion ladder
(PLAN-glasspane-completion.md, R0–R5) is closed on the foundation side;
this plan is the app itself. Source: the 22-file v1 app at
`llm-poc/jetpacs-v1-examples/glasspane/emacs/apps/glasspane/` (8,522
lines). Destination: `llm-poc-3/emacs/apps/glasspane/` — CANONICAL, ratified
by Caleb 2026-08-13: Tier-1 apps live inside jetpacs, which they
depend on; no repo split is planned (the bundle-producer gap therefore
gates nothing here — it matters only for distributing apps OUTSIDE
this tree). Measured baseline
(2026-08-12 verification workflow): 11/18 v1 requires resolve in v3
and all 7 missing are dead/retired/renamed; 30/45 most-used v1
functions exist keyword-compatible; the four
`jetpacs-files-editor-*` seams survive under v1 names; ~60–70% of the
mass is mechanical (rename map + alist→plist + ttl audit), ~30% is
five semantic rewrites concentrated in five files.

House rules that bind every rung: Emacs 30.1 floor, `setopt` for user
options, no compat shims. `jetpacs-` prefix is fine — this is an app
and may require anything; only `ebp-*` files are guard-constrained.
Every SPEC 14 handler returns `'accepted`/`'stale`/`'rejected`.
vulpea and org-ql are NOT installed locally: vulpea-dependent paths
hide behind feature guards, their local bar is byte-compile + guard,
functional ERT only for org-free logic, device/vulpea session owns the
rest. Dialog style `"sheet"` is plain presentation (K1a scaffold slots
are irrelevant here).

Test home: ONE suite file, `test/glasspane-test.el`, named after the
entry feature (the M3 pattern: entry `jetpacs-m3-catalog.el` →
`test/jetpacs-m3-catalog-test.el`, invoked at run-tests.sh:276-278).
The byte-compile guard already globs `emacs/apps/*/*.el`
(run-tests.sh:67) but its loop passes `-L emacs -L emacs/apps/m3-catalog`
only (run-tests.sh:68) — G0 adds `-L emacs/apps/glasspane` and the
suite stanza, or the first sibling `require` goes red.

## Banked traps (read before every rung)

- **Handlers never block, never push inline (D2).** The
  `jetpacs-defaction` contract (jetpacs-surfaces.el:907-918) forbids
  blocking the dispatch extent; every trailing `jetpacs-shell-push`
  moves into `jetpacs-flow-continue` (jetpacs-surfaces.el:586) or
  `jetpacs-buffer-defer-refresh` (jetpacs-buffer.el:1138). `read-string`
  / `completing-read` / `yes-or-no-p` inside a handler is the same
  violation — bridge via the jetpacs-dialog advice behind
  `jetpacs-dialog-can-bridge-p` (jetpacs-dialog.el:852) inside a
  continuation, headless refusal path mandatory (the JA-6 P2 lesson,
  jetpacs-org-dialogs.el:74-80).
- **Refs never cross the wire (D-4).** ebp-org refs are Emacs-side
  plists (ebp-org.el:429-433); anything the device can tap carries a
  minted token (SPEC 23.1) instead.
- **`'accepted` means durable.** Return it only after the effect is on
  disk/in the engine (jetpacs-surfaces.el:918); a swallowed error that
  still answers `'accepted` is a defect (see G7's srs engine wrapper).
- **Build-time errors replaced silent drops.** `:when-offline "queue"`
  / `"wake"` without `:ttl-s` signals (jetpacs-widgets.el:528-536);
  universal attrs (`:weight` `:padding` `:width` `:height` `:border`
  `:fill-fraction`) inline on a container signal
  (`jetpacs--check-options`, jetpacs-widgets.el:373) — wrap
  `jetpacs-with-attrs` (jetpacs-widgets.el:440); enum-list options must
  be `jetpacs-enum-option` nodes (jetpacs-widgets.el:2038,2051);
  reorderable-list items must carry `:key`/`:id`
  (jetpacs-widgets.el:1035-1049). Nothing in v1 byte-compiles into a
  working view by rename alone.
- **Plain nil is not false on the wire.** `:collapsed` and friends take
  t/`:json-false` via `jetpacs-bool` (jetpacs-widgets.el:430-439).
- **Ids are SPEC 4.4 identifiers.** Anything embedding a file path
  mints through `jetpacs-wire-id` (jetpacs-widgets.el:101).
- **Surface pushes are grant-gated and SIGNAL.** `jetpacs-shell-push`
  errors on an ungranted gate (jetpacs-shell.el:720-726); notification/
  widget pushes guard on `jetpacs-granted-p` (jetpacs-surfaces.el:214)
  or the surface degrades whole.
- **vulpea declare-functions use the `ext:` pseudo-file idiom**
  (jetpacs-org-vulpea.el:46-58) so `byte-compile-error-on-warn`
  (run-tests.sh:54,69) stays honest with vulpea absent. Note
  `jetpacs-org-vulpea-available-p` (jetpacs-org-vulpea.el:118) PROBES
  `(require 'vulpea nil t)` — it loads vulpea when present; v1's
  softer featurep-only probe remains valid app policy where load cost
  matters.

## The five semantic rewrites (strategy, stated once)

Every rung below applies these by reference; the counts are the
measured sites (~31 / ~51 / ~21 / ~105 / 7-per-group).

### S1 — nav fabric → chrome

v1 had `jetpacs-shell-define-view`/`-nav-view`/`-tab-view`, drawer
items, overlays with `:when`/`:overlay`/`:order`, and `:switch-to`
pushes. None exist. The v3 shape: the app claims ONE owner
(`"glasspane"`, valid per `jetpacs-valid-owner-p`
jetpacs-surfaces.el:81; never the reserved `jetpacs.` prefix, :72),
defines ONE chrome root (`jetpacs-chrome-define-root`,
jetpacs-chrome.el:414), and every other v1 "view" becomes either a
dock destination (`jetpacs-defapp` `:surfaces`/`:dock`,
jetpacs-apps.el:54; item shape `:label :icon :on-tap [:selected]`,
jetpacs-chrome.el:77-89) or a pushed screen
(`jetpacs-chrome-push-screen` :496 / `-pop-screen` :521 /
`-reset-screens` :531; screen slots `:back :actions :fab :drawer
:bottom-bar :floating-toolbar` on `jetpacs-chrome-screen`,
jetpacs-chrome.el:93). Overlay lifecycle machinery (open flags,
view-switched close hooks) is DELETED — chrome truncates the stack on
`view.switched` (jetpacs-chrome.el:555-567) and stacked builders only
run while stacked. The in-tree precedent is the m3-catalog
registration tail, apps/m3-catalog/jetpacs-m3-core.el:1212-1248 (dock
item shape :1195-1210; cross-surface taps use the global
`jetpacs.launcher.open` verb). Drawer rows are `jetpacs-chrome-row`
nodes in the root screen's `:drawer` slot (jetpacs-chrome.el:134;
precedent jetpacs-settings.el:356-397). Satellite screens live in
Settings links (`jetpacs-settings-add-link`, jetpacs-settings.el:284),
not the drawer — unchanged from v1 (docs/CHROME-VOCABULARY.md).

### S2 — ui-state writes → app defvars + reconciled input

`jetpacs-ui-state` is READ-THROUGH ONLY in v3 ("no jetpacs writer
exists by design", jetpacs-surfaces.el:1203); `jetpacs-ui-state-put`
/`-clear` have no port target. Three replacement moves: (a) server
mode/anchor/selection state (agenda mode, calendar anchor, views
rendering, search filters) becomes app `defvar`s whose SINGLE writer
is the action handler, with widgets re-seeded via `:value` each
render; (b) dialog field seeding becomes the field's `:value` in the
dialog spec plus `:capture-fields` on the submit button — the
conclusion echoes the fields, no state round-trip; (c) device-side
clearing is `jetpacs-shell-push :reset-input-ids`
(jetpacs-shell.el:800-812) or `:clear-on-submit` on the text input
(jetpacs-widgets.el:1885). `jetpacs-on-state-change`
(jetpacs-surfaces.el:1156) exists for live-edit mirroring where
wanted. The v1 comment at glasspane-search.el:39-48 documents that
filter persistence IS the feature — preserve it in the defvar, not by
fighting the reconciled model.

### S3 — dialogs → ebp-client-dialog-show

`jetpacs-send-dialog`/`jetpacs-dismiss-dialog`/`jetpacs-form-*` are
gone. One shape everywhere: `ebp-client-dialog-show` (ebp.el:2252) on
`(jetpacs-client)` (jetpacs-surfaces.el:184) with a `(status result
error)` callback; submit buttons are `jetpacs-dialog-submit
:capture-fields` (jetpacs-widgets.el:604), Cancel is the
`jetpacs-dialog-dismiss` builtin (:613), values are read from the
conclusion's `:fields` (`jetpacs-dialog--submitted-field`,
jetpacs-dialog.el:279). In-tree precedent:
jetpacs-org-dialogs--show-set-todo, jetpacs-org-dialogs.el:385-424;
sheet-dispatch revalidation shape :296-300. Dismissal itself IS
covered: `ebp-client-abandon` (ebp.el:1148-1159) sends `rpc.cancel` for
the outstanding `dialog.show` request id and the Companion concludes it
with error 1301 (ebp.el:63-66, SPEC 18.1) — the in-tree precedent is
`jetpacs-org-dialogs--archive`, which retires its live sheet with
`(ebp-client-abandon client (plist-get sheet :request-id))` after a
successful archive (jetpacs-org-dialogs.el:1142-1148). Every v1
handler-side `jetpacs-dismiss-dialog` site (5) maps the same way: keep
the `dialog.show` request id, `ebp-client-abandon` it, make the
callback a no-op on the 1301. Only a dialog-UPDATE verb is absent —
there is no way to mutate a live dialog's contents from Emacs, only end
it. `:style "sheet"` is per-dialog (no global
`jetpacs-dialog-style` variable — wrap in an app helper). Live-update
resend loops (the detail planning dialog) either re-show a fresh
dialog from the callback or delegate to the foundation timestamp
dialog (jetpacs-org-dialogs.el:558-745,1166-1168). Watch the dialog
size gates (`jetpacs-dialog--gate-spec`/enum threshold,
jetpacs-dialog.el:60,105) on the big property dialogs.

### S4 — handler returns (SPEC 14.4)

~105 v1 handler bodies return nothing; every v3 handler returns
`'accepted`/`'stale`/`'rejected` (contract jetpacs-surfaces.el:907-918,
dispatch :725-736; m3 precedent
apps/m3-catalog/jetpacs-m3-core.el:977-1011). The classifier idiom is
established once, in G3's `glasspane-ui--at-ref` successor:
`ebp-org-token-ref` nil → `'stale`; `ebp-org-resolve-ref`
(ebp-org.el:452) signaling `ebp-org-refused` → `'rejected`,
`ebp-org-unresolved` → `'stale`; mutation succeeds under
`ebp-org-with-mutation` (ebp-org.el:705) → `'accepted`. Gate order
inside a handler: shape → stale → exposure → grant
(jetpacs-org-dialogs--dialog-tap, jetpacs-org-dialogs.el:1049-1063:
cond malformed buffer/pos → `'rejected`; `jetpacs-event-stale-p` →
`'stale`; `jetpacs-buffer-exposed-p` miss → `'rejected`; ungranted
`surfaces.dialog` → `'rejected`; then the run-at-time continuation +
`'accepted`). Malformed args → `'rejected`; moved/renamed subject → `'stale`; an
error RENDER (e.g. a failed search landing in the error card) is still
`'accepted` — the render is the effect. Deferred work returns
`'accepted` immediately and continues in `jetpacs-flow-continue`
(re-entrancy guards survive the move).

### S5 — refs → minted tokens (SPEC 23.1)

Every v1 site that baked a ref alist into on-wire `:args` mints
instead: `ebp-org-ref-tokens` at render (`:owner "glasspane"`, one
`:set` per rendered screen/list — replace-set semantics make stale
sheets answer `'stale` for free; ebp-org.el:563), `:args (:token TOK)`
on the wire, `ebp-org-token-ref` (ebp-org.el:625) at dispatch, then
resolve/mutate per S4. Refs themselves become plists from
`ebp-org-ref-at-point` (ebp-org.el:429). Buffer-backed alternates may
use the exposure route (`:buffer NAME :pos POS` +
`jetpacs-buffer-expose`, jetpacs-buffer.el:272,310) — the render-skin
precedent is jetpacs-org-render.el:47-56. Coordinate mint sets across
files: detail owns the per-screen set the srs/notes toolbar chips join.

## Consolidated transform table (mechanical porter rules)

Apply file-by-file, in this order, before any semantic work.

### T1 — rename map: jetpacs-org-* → ebp-org-* (~50 sites)

| v1 | v3 | authority |
|---|---|---|
| jetpacs-org-cache-invalidate | ebp-org-cache-invalidate | ebp-org.el:412 |
| jetpacs-org-with-cache | ebp-org-with-cache (same NAMESPACE KEY shape) | ebp-org.el:400 |
| jetpacs-org-resolve-ref | ebp-org-resolve-ref (plist ref; signals refused/unresolved) | ebp-org.el:452 |
| jetpacs-org-heading-ref | ebp-org-ref-at-point (returns PLIST) | ebp-org.el:429 |
| jetpacs-org-defer-save | ebp-org-defer-save | ebp-org.el:698 |
| — (new) | ebp-org-with-mutation (resolve+widen+invalidate+defer) | ebp-org.el:705 |
| jetpacs-org-parse-query | ebp-org-parse-query (wire-vetted; regexp off the wire allowlist, ebp-org.el:828-831) | ebp-org.el:1022 |
| jetpacs-org-entry-matches-p | ebp-org-entry-matches-p | ebp-org.el:1206 |
| jetpacs-org-query | ebp-org-query — **ARITY (NAMESPACE KEY TREE ACTION)**, KEY mandatory and must identify the ACTION (P1-12 cache-poisoning rule, ebp-org.el:1262-1270); always the built-in interpreter, org-ql dispatch removed (ebp-org.el:1277-1282) | ebp-org.el:1260 |
| jetpacs-org-note-matches-p / -note-query-supported-p | ebp-org-note-matches-p / ebp-org-note-query-supported-p | jetpacs-org-vulpea.el:96/105 |
| jetpacs-org-note-query-terms | ebp-org-note-query-terms | ebp-org.el:820 |
| jetpacs-org-ts-date / -ts-time / -ts-repeater | ebp-org-ts-date / -ts-time / -ts-repeater | ebp-org.el:1300/1306/1312 |
| jetpacs-org-set-repeater | ebp-org-set-repeater | ebp-org.el:1593 |
| jetpacs-org-logbook-entries | ebp-org-logbook-entries | ebp-org.el:1575 |
| jetpacs-org-format-clock-time | ebp-org-format-clock-time | ebp-org.el:1646 |
| jetpacs-org-table-field-formula | ebp-org-table-field-formula | ebp-org.el:1622 |
| jetpacs-org-capture-templates | ebp-org-capture-templates (returns PLISTS :key :description :prompts) | ebp-org.el:1357 |
| jetpacs-org-capture-run (+fill/prompts) | ebp-org-capture-run / -fill / -prompts | ebp-org.el:1461/1408/1337 |
| jetpacs-org-clocked-in-p | ebp-org-clocked-in-p | ebp-org.el:1319 |
| jetpacs-org-outline-cap/-collect/-tree/-show-clocked/-show-deadline | ebp-org-outline-* (collect gained optional LEVEL/MAX; outline-body `:header` is now a SINGLE node, records are plists) | ebp-org.el:1811/1752/1795/1691/1687; jetpacs-org-outline.el:66 |
| jetpacs-org-file-save-function | ebp-org-file-save-function | ebp-org.el:1666 |
| (require 'jetpacs-org) | (require 'ebp-org) — jetpacs-org.el survives as a floor-registration shim only, no aliases | jetpacs-org.el:1-54 |

### T2 — rename map: everything else

| v1 | v3 | authority |
|---|---|---|
| (require 'jetpacs) | dead — require jetpacs-surfaces/-widgets/-shell/-chrome/-apps explicitly | no jetpacs.el in tree |
| jetpacs-send "toast.show" alist | jetpacs-toast TEXT &key :duration-s | jetpacs-surfaces.el:275 |
| jetpacs-connected-hook | jetpacs-ready-functions, arity (CLIENT); pre-replay state → jetpacs-before-replay-functions | jetpacs-surfaces.el:1261/1245 |
| jetpacs-shell-view-switched-hook | jetpacs-shell-view-change-functions, arity (SURFACE VIEW) | jetpacs-shell.el:1094 |
| jetpacs-settings-after-set-hook | per-entry :after-set in the registry | jetpacs-settings.el:44-62 |
| jetpacs-installed-bundles | jetpacs-app-store-installed | jetpacs-app-store.el:74 |
| jetpacs-node-or / jetpacs-node-supported-p | (if (jetpacs-node-advertised-p TYPE) A B) | jetpacs-surfaces.el:1050 |
| jetpacs-swipe-action (ICON LABEL ACTION :color) | jetpacs-swipe (LABEL &key icon color on-trigger) | jetpacs-widgets.el:945 |
| jetpacs-scroll-row / -column | jetpacs-row/-column … :scroll t | jetpacs-widgets.el:781/820; vocabulary:43-44 |
| jetpacs-clipboard-action / jetpacs-share-action | jetpacs-clipboard-copy / jetpacs-share | jetpacs-widgets.el:583/588 |
| jetpacs-markup | jetpacs-text TEXT :syntax "org" | jetpacs-widgets.el:622 |
| jetpacs-reminders-owner-set | jetpacs-reminders-set (:owner :callback) — ASYNC, signals on ungranted "reminders.owner"; adopt caches in the callback under jetpacs-granted-p | jetpacs-device.el:109,148 |
| jetpacs-theme-mode 'emacs | 'mirror | jetpacs-theme.el:67,88-92 |
| jetpacs-send-dialog / jetpacs-dismiss-dialog / (jetpacs-action "dialog.dismiss") | S3 | ebp.el:2252; jetpacs-widgets.el:604/613 |
| jetpacs-shell-nav-view / -define-view / -tab-view / -add-drawer-item / -switch-view / -add-top-action / push :switch-to | S1 | jetpacs-chrome.el:93/414/496/521; jetpacs-apps.el:54; jetpacs-widgets.el:577 |
| jetpacs-form / -reset / -seed / -field-id / -value | S2/S3 (:capture-fields, ui-state reads, :reset-input-ids, :clear-on-submit) | jetpacs-shell.el:800; jetpacs-widgets.el:604,1885 |
| jetpacs-surface-push / -remove | jetpacs-shell-define-root / -remove-root (grant-gated) | jetpacs-shell.el:187/213,720-726 |
| jetpacs-notification-spec | jetpacs-notification-surface (body + :meta; SPEC 18.5 meta vocabulary, buttons live in meta :actions — the notification node set has NO button) | jetpacs-widgets.el:2833,2915; ebp/SPEC.md:2910-2944 |
| jetpacs-widget-item / -widget-divider / jetpacs-tile | no port target (FOUNDATION-GAPS #1) | jetpacs-vocabulary.el (52 nodes, none widget/tile) |
| jetpacs-fab / jetpacs-apps-set-default-fab | per-screen :fab node (any node; icon-button precedent jetpacs-org-render.el:795-800) | jetpacs-chrome.el:93; jetpacs-widgets.el:2583 |
| jetpacs-nav-item / jetpacs-bottom-bar / jetpacs-filter-section / jetpacs-drawer-item | app-local compositions (dock-tab precedent jetpacs-chrome.el:177-204; jetpacs-collapsible widgets:1010; jetpacs-chrome-row chrome:134) | — |
| jetpacs-defsource | RETIRED — see retirement list | docs/PLAN-jetpacs-apps.md:844-848 |
| jetpacs-gauge / jetpacs-arc-points / jetpacs-border | app-local canvas rebuild; :border is a universal-attr plist (:width N :color C) | jetpacs-widgets.el:2394-2452,211 |
| jetpacs-sync-shadow-setup-hook | ebp-complete-shadow-setup-hook | ebp-complete.el:176 |
| :jetpacs-insert-function (capf prop) | :ebp-insert-function | ebp-complete.el:285 |
| (error-message-string err) in user-facing notify | jetpacs-error-label (SPEC 23.3) | jetpacs-surfaces.el:539 |
| jetpacs-files-open | route through the jetpacs.files.open verb or drop | jetpacs-files.el:11,295 |
| jetpacs-app-dir / jetpacs-app-config-{load,sync,ensure} | app-local helper (FOUNDATION-GAPS #4) | — |

### T3 — argument-shape rules (~92 shapes)

- **Action `:args` are member PLISTS** (jetpacs-widgets.el:565-567):
  `((kind . k))` → `(:kind k)`. Handler reads: `(alist-get 'x args)` →
  `(plist-get args :x)` — jsonrpc decodes nested objects as keyword
  plists too.
- **Refs are plists** (`:id :file :pos :headline`) and never appear in
  `:args` at all (S5).
- **Widget signature churn:** `jetpacs-table-row` is kind-first
  (`("header"|"data" CELL…)`, jetpacs-widgets.el:1156);
  `jetpacs-month-grid :marks` values are `jetpacs-month-mark` plists,
  dots capped 0..3 (jetpacs-widgets.el:2493,2500);
  `jetpacs-chart-series` takes `jetpacs-chart-point` nodes and `:label`
  → `:name` (jetpacs-widgets.el:2356,2365); `jetpacs-slider` on-change
  is positional arg 2, `:steps` → `:values` (jetpacs-widgets.el:2149);
  `jetpacs-switch :value/:on-toggle` → `:checked/:on-change`
  (jetpacs-widgets.el:2025); `jetpacs-date-stamp` takes decomposed
  `:day :month :year :time` (jetpacs-widgets.el:695); `jetpacs-editor`
  content → `:value`, `:line-numbers` is bool
  (jetpacs-widgets.el:2313); `jetpacs-card` has no `:on-swipe` —
  `:swipe-start/:swipe-end` take jetpacs-swipe objects
  (jetpacs-widgets.el:983,998); `jetpacs-span :bold` → `:font-weight
  "bold"`, `:tag` gone (style with :color/:bg/:on-tap), `:strike` has
  NO member (jetpacs-widgets.el:643 — FOUNDATION-GAPS #7);
  `jetpacs-enum-list` single-select `:value` is ONE option value, not
  a list (jetpacs-widgets.el:2051-2056).

### T4 — ttl/policy audit (the 161-site rule)

`"drop"` is the default and forbids `:ttl-s`/`:dedupe`; `"queue"` and
`"wake"` REQUIRE integer `:ttl-s` 1..604800; `"wake"` additionally
needs the session offline.wake grant (jetpacs-widgets.el:526-536;
gates jetpacs-shell.el:731-738; jetpacs-gate-descriptor-policy
jetpacs-surfaces.el:1109). Queue/wake sites needing `:ttl-s`, by file:
notes:174; views:170,177,269,486; clock:31,33 (wake),79,84;
journal:137,165,169; capture:32,50; reader:89; detail:607-609
(detail.save, also carries :dedupe),826-829. Every other audited site
is `"drop"` and ports as-is (explicit "drop" may be deleted — it is
the default).

### T5 — text styles and guards

- `jetpacs-text` positional style symbols → `:style "label|body|
  caption|title|headline|mono"` (~120 sites; enum at
  jetpacs-widgets.el:252,622).
- Drop `fboundp` guards on `jetpacs-shell-notify`/`-push`/`-refresh` —
  hard deps in v3 (jetpacs-shell.el:1014/799/1009).
- vulpea/org-srs declare-functions use `ext:` pseudo-files
  (jetpacs-org-vulpea.el:46-58); require-probes stay.
- defcustoms may keep `:group 'jetpacs` (defgroup at
  jetpacs-surfaces.el:41; the app-store defcustoms do the same);
  `setopt` binds users, not definitions.

## Rung ladder

Every rung's LOCAL GATE is: `test/run-tests.sh` fully green — the
byte-compile guard (error-on-warn) over the rung's files via the
apps glob, plus the NAMED ERT assertions added to
`test/glasspane-test.el`. Rungs land in order; a rung may stub a
later sibling with declare-function but never requires forward.

### G0 — skeleton, registration, harness wiring

Files: `emacs/apps/glasspane/glasspane.el` (entry);
`test/run-tests.sh` (two edits); `test/glasspane-test.el` (new).

The entry is the M3 thin-entry template (jetpacs-m3-catalog.el:27-105)
including the `eval-and-compile` load-path shim
(jetpacs-m3-catalog.el:31-36 — the flat on-device layout needs it
regardless of final location), an `M-x glasspane` autoload command, a
`glasspane-unload-function`, and a `glasspane-register` /
`-unregister` pair per jetpacs-m3-core.el:1212-1258: claim owner
`"glasspane"` (jetpacs-valid-owner-p jetpacs-surfaces.el:81), define
the chrome root (`jetpacs-chrome-define-root` jetpacs-chrome.el:414 —
a placeholder home screen at this rung), end with `jetpacs-defapp`
(:surfaces/:dock, jetpacs-apps.el:54). Wire `jetpacs-ready-functions`
(jetpacs-surfaces.el:1261) + `jetpacs-connected-p`
(jetpacs-surfaces.el:210). The require list grows one rung at a time.
Harness: add `-L emacs/apps/glasspane` to the run-tests.sh:68 loop and
a suite stanza after the M3 one (run-tests.sh:276-278) — same commit
as the entry, or the guard breaks the moment two files exist.

LOCAL GATE: byte-compile; ERT `glasspane-test-registers` (load +
register populates `jetpacs-apps--registry` and
`jetpacs-action-handlers`, owner claim visible in `jetpacs--claim`
records), `glasspane-test-home-serializes` (root screen builds and
round-trips `jetpacs-node->canonical-json`),
`glasspane-test-unload-clean` (unregister leaves no claims/handlers).

### G1 — data layer: glasspane-org.el, glasspane-vulpea.el

The port's foundation stone: memoised extraction, query routing,
reminder specs, clock status, save funnel, CREATED/MODIFIED hooks.
Apply T1 (15 rename sites), S5 groundwork (all 6 ref-building sites
switch to `ebp-org-ref-at-point` plists; tokens are minted by the UI
layer, not here). `ebp-org-query` gains its mandatory KEY. Delete the
org-ql routing commentary (glasspane-org.el:274-281) — v3 never forks
to org-ql. Port `glasspane-org--vulpea-query`/`glasspane-org--query`
(glasspane-org.el:282-308, the whole-vault-via-note-index scope rule
guarded by `glasspane-org--vulpea-p` :182 and
`jetpacs-org-note-query-supported-p` :303) behind that same feature
guard — `glasspane-org--search` (v1:310-317) calls `--query` at :317,
and T1's `ebp-org-note-matches-p`/`-note-query-supported-p`
(jetpacs-org-vulpea.el:96/105) plus `ebp-org-note-query-terms`
(ebp-org.el:820) are the vulpea arm this keeps alive.
`find-file-noselect` sites (v1:247,333,367) validate through the
ebp-org file policy (`ebp-org--check-file` ebp-org.el:189,
`ebp-org-file-allowed-p` :214, `ebp-org-roots` :137) and open under
`ebp-org--with-clamped-io` (ebp-org.el:239-248), applied around
resolution/opening at ebp-org.el:475 with the find-file-noselect calls
themselves at :501 and :517. Load-time global org hooks
(v1:484-502) move behind app enable with `jetpacs-teardown-functions`
removal hygiene. glasspane-vulpea.el ports verbatim modulo the `ext:`
declare-function idiom; its `glasspane-vulpea-register` callers
(glasspane-org load tail, packages light-up) re-find homes in G1/G2.

LOCAL GATE: byte-compile with vulpea ABSENT; ERT
`glasspane-test-org-extraction` (agenda/todo/level-1 items over temp
org files), `glasspane-test-org-query-routing` (built-in interpreter,
keyed cache), `glasspane-test-org-filter-items`,
`glasspane-test-org-reminder-horizon`,
`glasspane-test-org-timestamp-hooks`,
`glasspane-test-org-roots-refusal` (file outside ebp-org-roots
refuses), `glasspane-test-vulpea-register-noop` (silent no-op,
`--registered` stays nil, with vulpea-db-register-extractor unbound).
Vulpea arms: guard-only, functional bar DEFERRED to the device/vulpea
session.

### G2 — services: glasspane-clock.el, glasspane-config.el, glasspane-packages.el

Clock first (zero glasspane deps — the pattern-proving port):
notification surface restructures per SPEC 18.5 (buttons out of the
body into meta `:actions`; chronometer alist → `:chronometer
(:base_ms N)` plist; SPEC.md:2910-2944), pushes through
`jetpacs-shell-define-root`/`-push`/`-remove-root` guarded on
`jetpacs-granted-p "surfaces.notification"` (jetpacs-shell.el:720-726).
The widget:custom1 slot is FOUNDATION-GAPS #1 — dropped. Handler
statuses: clock.out `'accepted`/no-clock `'stale`; clock.switch
`'rejected` until a real picker exists; in-last condition-case →
`'rejected`.

Config: the per-app config seam is app-local (~40 lines over
`(expand-file-name "jetpacs/apps/glasspane/" user-emacs-directory)` —
FOUNDATION-GAPS #4 decided DEFER). Managed payloads (v1:44-96) port
verbatim. Consent test → `jetpacs-app-store-installed`; config.sync
writes synchronously (fast, local, durable), notifies, defers the
push, returns `'accepted`.

Packages: the packages.install handler is the D2 showcase —
`package-refresh-contents` pumps the event loop, so the v3 shape is
jetpacs-package-browser's deferred pattern verbatim
(`jetpacs-pkg--deferred`, jetpacs-package-browser.el:176-187): toast
progress, `jetpacs-flow-continue` the install + outcome toast, return
`'accepted` immediately; keep the `--installing` re-entrancy guard.
Closed set stays app-owned, never wire-named (the package-browser lock,
jetpacs-package-browser.el:189-192); fold glasspane-pack's min-version
data (org 9.6+, org-ql 0.7+, vulpea 2.0+) into `--set` here. Settings
section via `jetpacs-settings-register-section`
(jetpacs-settings.el:51).

LOCAL GATE: ERT `glasspane-test-clock-notification-shape` (meta
:chronometer :base_ms integerp, :actions vector, via canonical-json),
`glasspane-test-clock-handler-matrix` (faked org-clock state),
`glasspane-test-clock-grant-degrade` (jetpacs-granted-p stubbed nil →
no signal, no push), `glasspane-test-config-sync-ensure-load` (temp
user-emacs-directory; sync writes 2 files, ensure is create-once, load
in name order), `glasspane-test-config-sync-accepted`,
`glasspane-test-packages-wanted-drops-vulpea` (sqlite-available-p nil),
`glasspane-test-packages-batch-noop` (noninteractive),
`glasspane-test-packages-install-defers` ('accepted with ensure
stubbed; no synchronous ensure inside dispatch),
`glasspane-test-packages-settings-registered`.

### G3 — keystone: glasspane-ui.el

The largest decision surface and the idiom template. Part of the v1
file is now foundation-owned and is DELETED, not ported (see
retirement list): the bimodal rendered↔plain mode-toggle machinery,
checkbox.toggle, org toolbar/FAB wiring, after-save invalidation — all
live in jetpacs-org-render.el:740-851
(`jetpacs-org-render--files-mode` hash :757, `jetpacs.org.view-mode`
verb :809-827, seams :832-851). The v1 block was actually TRIMODAL,
though: it also housed the app's own foldable reader (filter row +
outline card list) and the refile drag-list mode, which have no
foundation home and PORT instead — see G4 for
`glasspane-ui--org-editor-body`/`-actions`, `glasspane-org-reader-file`,
and `glasspane-org-reader-refile-list`, and the replacement surfacing
G4 assigns them. What ports: the settings screen (chrome
screen + `jetpacs-settings-register-section`; per-entry `:after-set`
carries the `ebp-org-cache-invalidate` that replaced the after-set
hook), the 17 handlers under S4, the dialog pair under S3, the
ui-state writes under S2 (agenda anchor/selected-date become shared
defvars agenda reads in G5), and above all `glasspane-ui--at-ref`
(v1 ui:281-316) → the token→resolve→classify funnel of S4/S5 that
every later rung copies. The `agenda.save-custom` handler's inline
`read-string` (ui:454) becomes a captured dialog field — the v3
no-prompt regime forbids it in the dispatch extent
(jetpacs-dialog.el:86-103). `glasspane-magit` (v1 require, lives
outside the app dir) goes soft: declare-function + optional require;
its port is out of this plan's scope. Enum-list string options →
enum-option nodes (2 sites); duplicate `(provide 'glasspane-ui)`
deleted.

LOCAL GATE: ERT `glasspane-test-ui-todo-sequences`
(--split-todo-sequence/--global-todo-keywords, pure),
`glasspane-test-ui-settings-nodes` (body shapes over stubbed org
vars), `glasspane-test-ui-at-ref-classifier` (the triple: stubbed
token table → 'stale on nil token, 'rejected on ebp-org-refused,
'stale on ebp-org-unresolved, 'accepted on success),
`glasspane-test-ui-handler-statuses` (every registered handler funcall
via `(gethash NAME jetpacs-action-handlers)` with plist args returns a
status symbol; no client needed).

### G4 — reader + detail: glasspane-org-reader.el, glasspane-detail.el

The semantic epicenter (28 + 1 handlers, ~30 token-mint sites, 3
dialog conversions, the nav conversion). Detail becomes a PUSHED
screen: heading.tap calls `jetpacs-chrome-push-screen` with a builder
closure capturing the detail ref; the 8 `:switch-to`/current-tab sites
become push/pop. Dialog dedup decision (made here, engineering):
todo-set, schedule, priority, and tags are NOT dialog launches at the
handler level — they are direct arg-carrying mutations that later
rungs emit with computed args (views board swipe "Done" / column menu
→ heading.todo-set `(state . KW)`, glasspane-views.el:167-170,267-269
— G6; journal's Today/Pick buttons → heading.schedule
`(when . "+0d")` / a date value, glasspane-journal.el:163-170 — G5;
detail's own chip rows → todo-set/priority with explicit values,
glasspane-detail.el:386-388,400-402; the tag enum-list → heading.tags
`:value`, detail:732). KEEP these four handlers app-owned with their
direct arms intact: todo-set takes `:state` (detail:945-955), schedule
takes `:when`/`:value`/`:clear` (detail:975-1004), tags takes `:value`
(detail:1322-1357) — v3 registers no direct-set verb of its own (base
only has jetpacs.org.footnote/heading/archive/timestamp/ts-pick/
add-heading, jetpacs-org-dialogs.el:1161-1169). DELEGATE only the
PROMPT arms — todo-set/schedule's `(ask . t)` picker path and the
empty-date path bridged through `org-read-date` — plus
deadline/*-time/repeater/planning.show/archive/add-heading wholesale,
to the shipped foundation dialogs
(jetpacs-org-dialogs.el:385/425/474/558-745/1165/1169; the base
functions are user-picker flows, e.g.
`jetpacs-org-dialogs--show-set-todo` :385). KEEP an app-owned
long-press sheet for the delta the base sheet cannot carry (Clock
In/Out, Properties, Open/drill-in — the base candidate list is
hardcoded, jetpacs-org-dialogs.el:217-234, FOUNDATION-GAPS #12), with
dialog.submit values revalidated against fresh candidates (SPEC 23.2
shape at jetpacs-org-dialogs.el:296-300). The planning dialog's resend
loop (v1:861-866) delegates to the foundation timestamp dialog rather
than re-showing. Bridged prompts (10 read-string/completing-read/
org-read-date sites) move into flow continuations behind
`jetpacs-dialog-can-bridge-p`. files.properties.save's 9 ui-state
reads become one `:capture-fields` submit. The foldable reader and
refile-list mode inherited from glasspane-ui's trimodal block
(`glasspane-ui--org-editor-body` → glasspane-agenda.el:552-601,
`glasspane-ui--org-editor-actions` → glasspane-detail.el:1425-1442,
both reading `glasspane-org-reader-file`/`-refile-list`) need
replacement surfacing here, since jetpacs-org-render.el:740-851 only
claims the bimodal rendered/plain toggle: either claim
`jetpacs-files-editor-body-functions` ahead of jetpacs-org-render's own
hook entry (hooks chain — legal), or push a dedicated reader/refile
chrome screen instead — `glasspane-test-reader-trees`'s file/refile
tree assertions (LOCAL GATE, below) depend on this surfacing existing.
Reader bodies: with jetpacs-org-rich dead, bodies degrade to
`(jetpacs-text BODY :syntax "org")` this rung (FOUNDATION-GAPS #6 /
open question 2); done-title strikethrough degrades to color
(FOUNDATION-GAPS #7). Collapsible ids and refile-list `:key`s mint via
`jetpacs-wire-id`; refile items carry pos + per-list resolution, never
raw paths (D-4). v1's clocked-in duplicate (detail:236-251) deletes in
favor of `ebp-org-clocked-in-p`.

LOCAL GATE: ERT `glasspane-test-reader-trees` (file/subtree/refile
trees from temp org fixtures, canonical serialization, §16.2 profile,
§16.1 id uniqueness — the m3 gate pattern),
`glasspane-test-reader-token-mint` (offline mint/resolve round trip,
:owner "glasspane"; test/ebp-org-test.el precedent),
`glasspane-test-detail-builders` (card/row/logbook/property-row golden
node trees from fixture plists),
`glasspane-test-detail-handler-triples` ('accepted/'stale/'rejected
over temp org files, org core only),
`glasspane-test-detail-vulpea-noop` (refile/archive vulpea touchpoints
no-op with vulpea absent).

### G5 — daily surfaces: glasspane-agenda.el, glasspane-journal.el, glasspane-capture.el

Plus the app-local date-helper module (`glasspane-dates.el` or inline
in ui): jetpacs-date-format/-shift/month-abbrev do not exist anywhere
in v3 (grep-verified; FOUNDATION-GAPS #10). Agenda: tab-view/badge
block → dock items (the badge itself is FOUNDATION-GAPS #5 — until
the dock-item `:badge` thread-through lands, surface the count
in-screen); the clock tombstone view dies; day/week/month stays
in-body `jetpacs-tabs`; reminders adopt in the
`jetpacs-reminders-set` callback under `jetpacs-granted-p
"reminders.owner"` with the suppress-identical cache moving there;
month-grid marks via `jetpacs-month-mark`; outline-body `:header`
wraps in a single column node. Journal: the datetree engine
(--append/--day-pos) ports verbatim; capture input uses
`:clear-on-submit` (the form id-rotation trick dies); the landing
block's raw-var apology is obsolete (jetpacs-shell.el:1105
unasserted-view); carried-over cards mint tokens (set
"journal-carried"). Capture: the select→form→submit chain collapses
into ONE dialog — template picker buttons carry the next dialog from
the callback, Capture carries `jetpacs-dialog-submit :capture-fields`,
values read from result `:fields`; the whole jetpacs-form block dies;
capture-run `'accepted` only after `ebp-org-capture-run` returns
(durable). The widget/tile/default-FAB preamble (capture v1:6-67) is
dropped per FOUNDATION-GAPS #1/#2 (FAB reimplemented per-screen via
chrome `:fab`); share.text/org.capture.share stay REGISTERED (cheap,
offline-replay entry points) with Companion emission unverified
(FOUNDATION-GAPS #3).

LOCAL GATE: ERT `glasspane-test-agenda-formatters` (widget-item-meta,
type-icon/label, card-date-label, month fallback grid, modes — pure,
fixture plists), `glasspane-test-agenda-handler-matrix` (incl.
settings.todo.save stale-index → 'stale, agenda.set-mode unknown →
'rejected), `glasspane-test-journal-datetree` (--day-pos/--append
against a real temp datetree), `glasspane-test-journal-carried-query`
(tree passes ebp-org--vet-query), `glasspane-test-journal-handlers`
(nav non-integer → 'rejected; capture empty → 'rejected, durable →
'accepted), `glasspane-test-capture-flow` (templates/fill/run against
temp org + org-capture-templates fixture; dialog spec builders golden
node trees), `glasspane-test-dates-helpers` (pure).

### G6 — query surfaces: glasspane-views.el, glasspane-search.el, glasspane-table.el

Views: the two-screens-one-view trick becomes a real stack (hub screen
+ `views.open` pushes `jetpacs-wire-id "view" NAME`); calendar
anchor/selected → defvars; the new-view form drops the registry
(literal stateful ids, views.save reads `jetpacs-ui-state`, reset via
`:reset-input-ids`); 4 token-mint sites; 4 queue sites gain `:ttl-s`;
done-row strikethrough degrades (gap #7). Search: the S2 flagship —
filter state Emacs-side, the whole view then builds OFFLINE; the
query builder's sexp output points at the ebp-org grammar. GATE-ENTRY
CHECK: confirm the deadline/scheduled range forms — the journal card
verified `:on/:from/:to` integer offsets in the interpreter
(ebp-org.el:987-1007), so the builder's `(deadline :to -1)` family is
expected to map 1:1; if any spelling diverges, fix the BUILDER, not
the grammar. `glasspane-org--search` has no org-ql arm to guard — it
is parse + `--query` only (v1 glasspane-org.el:310-317); org-ql appears
nowhere as a function call across the 22 v1 app files (docstring/
comment mentions only: glasspane-org.el:297,312; glasspane-views.el:
32,452; glasspane-search.el hint text). The real G6 dependency is that
`--query`'s vulpea arm (ported in G1) survives; org-ql's only remaining
role in the app is the glasspane-packages install set (G2). Table:
footnote handler
deletes (base jetpacs.org.footnote, jetpacs-org-dialogs.el:1161);
`--table-mutate` survives as the app funnel; prompting arms re-enter
via `jetpacs-flow-begin` (jetpacs-surfaces.el:699) behind can-bridge;
notify targets the event surface (params `:surface`); cell descriptors
use exposure or tokens — glasspane authors its OWN table nodes with
`:on-tap/:on-long-tap/:on-add-row/:on-add-col`
(jetpacs-widgets.el:1149,1168) because the base render's table upgrade
is read-only (jetpacs-org-render.el:148-186, gap #11). The
`jetpacs-dialog-style` settings row is dropped.

LOCAL GATE: ERT `glasspane-test-views-board` (--board-columns,
--single-file, --done-p/--priority-span over fixture alists),
`glasspane-test-views-rendering-roundtrip` (set/persist),
`glasspane-test-views-handler-statuses` (unknown name → 'stale,
malformed → 'rejected, stubbed token table),
`glasspane-test-search-sexp-matrix` (--search-filter-query across
every filter combination, incl. the three deadline range forms
asserted against the interpreter),
`glasspane-test-search-screen-offline` (full screen build + canonical
serialize, no client), `glasspane-test-table-mutate-edges`
(align/recalc/kill-only-row; formula-vs-value routing via
ebp-org-table-field-formula), `glasspane-test-table-headless-refusal`
(can-bridge nil → notify + status, no wedge; babel timeout +
declined-confirm with a stub language).

### G7 — knowledge arms: glasspane-notes.el, glasspane-srs.el (vulpea/org-srs guarded)

Notes touches 4 of the 5 rewrites in one file. The wikilink capf
ports onto ebp-complete (shadow hook + `:ebp-insert-function`;
candidates KEEP the leading `[[` — the strip validates prefix by
position). The mentions hash + pending/error sentinels + manual
re-push dissolve into `jetpacs-async` (jetpacs-async.el:164 — keyed
loader, coalesced re-push; the refresh-hook clrhash dies). The
"glasspane.notes" defsource registration DROPS (retired seam); its
query helpers become plain functions feeding the builder. Graph
queries beyond the vetted grammar (by-links/by-ids/search-by-title/
stale-notes) stay raw guarded `vulpea-db-*` calls (gap #9 decided
DEFER — apps may require anything). link.materialize failure arms →
'rejected, file-changed arm → 'stale. SRS: review becomes a chrome
screen; the due-count drawer badge surfaces in-screen (gap #5);
`glasspane-srs--engine`'s swallow-and-notify is REWORKED so a failed
engine call never answers 'accepted; srs.item.create validates,
returns 'accepted, and runs org-srs's prompting create inside
`jetpacs-flow-continue` where prompts bridge to Companion dialogs
(jetpacs-dialog.el:332,690); both token sites join detail's mint
discipline; srs.answer.page's read-only pager mirror is already
v3-legal and keeps.

LOCAL GATE: byte-compile with vulpea AND org-srs absent; ERT
`glasspane-test-notes-orgfree` (--find-unlinked over local org,
--age-caption, --materialize-terms matched arm),
`glasspane-test-notes-guard-contract` (every entry point nil /
'rejected with vulpea absent — the jetpacs-org-vulpea-test.el
precedent), `glasspane-test-srs-layout` (card-parts/child-body/
part-nodes/card-content/cloze-content over fixture buffers, cloze
collect stubbed; canonical-json shapes),
`glasspane-test-srs-rating-row` (stubbed intervals),
`glasspane-test-srs-handler-statuses` (stubbed engine: write ok →
'accepted, no item → 'stale, bad rating → 'rejected). Vulpea-live
paths (capf candidates, backlinks, stale query, extractor) and
org-srs engine paths: DEVICE/DOGFOOD ONLY — banked for the device
gate. MEMORY caveat rides that session, not this rung: the local
vulpea checkout is outdated; develop against installed MELPA vulpea.

### G8 — satellites + fixtures: glasspane-ef.el (+ glasspane-theme-picker.el), glasspane-demo.el, glasspane-gallery.el

Ef: port the 4 missing theme-picker builders app-locally
(`glasspane-theme-picker.el`, ~150 v1 lines — gap #8 decided
app-local); overlay machinery collapses into one push-screen;
theme-mode `'emacs` → `'mirror`; the Settings satellite link picks its
`:order` against v3's registered links (the v1 anchor at 25 does not
exist). Demo: KEEP as the fixture seeder (the only way to place files
in the app-private Android home; the corpus doubles as the
device-smoke fixture set) — two handler signatures + one rename; NEW
v3 constraint: the seeded corpus must land INSIDE `ebp-org-roots`
(ebp-org.el:137,189,214) or every query/mutation/mint over it refuses,
and `glasspane-demo-directory` must sit under `jetpacs-files-roots`
(jetpacs-files.el:65) — derive targets from the defcustoms, don't
hardcode. Gallery: the only new code is the ~30-line gauge rebuild on
jetpacs-canvas (v1 math at v1 core jetpacs-widgets.el:913-935
transliterates; canvas-text has no :align — offset manually); the
slider mirror re-pushes `:value` from the mirror so the spec never
fights the device draft. Load/port order within this rung: DEMO BEFORE
GALLERY — glasspane-gallery.el calls `glasspane-demo-setup` and
`glasspane-demo-gallery` with no `require` of its own (v1 relied on the
app entry loading everything), so gallery needs demo already in the
image, or gallery must gain its own declare-functions for those two
calls.

LOCAL GATE (ef-themes/org-srs absent is the DEFAULT path — real guard
coverage): ERT `glasspane-test-ef-absent-paths` (--available-p nil,
not-installed body keyed on the packages.install handler-table entry,
ef.load unknown theme → 'rejected),
`glasspane-test-ef-option-nodes` (style section shapes),
`glasspane-test-gallery-trees` (every gallery screen through
canonical-json; chart/canvas shapes; handler good/bad args),
`glasspane-test-gallery-gauge-math` (pure geometry),
`glasspane-test-demo-shift` (zero-shift identity, day-name recompute
in C locale, fixed-width stamps), `glasspane-test-demo-seed`
(tempdir seeding, re-read + org-parse + unique-ID lint; targets
derived from roots), `glasspane-test-demo-handlers` (write failure →
'rejected after notify).

### G9 — DEVICE GATE (exit)

Owed after G8, one device/vulpea session: install the closed engine
set on hardware, then smoke — vulpea capf/backlinks/stale
(glasspane-notes), the extractor registration (glasspane-vulpea +
MELPA 2.6 slot probe), org-srs review/rate/undo/create, reminders
owner-set adopt, notification chronometer + meta actions, capture
dialog flow end-to-end, demo seeding inside roots, and the ~20-notify
snackbar behavior — both arms, the granted immediate raise and the
ungranted next-push injection into the current view's scaffold — under
the app's actual grant profile (gap #13). Device-smoke practice
applies: force-stop first, screenshot before tapping, generated
fixture bytes only.

## FOUNDATION-GAPS (stop/go per gap)

1. **Home-screen widget surface + QS tile** — the surface class and
   push seam actually EXIST: `jetpacs-widget-surface` builds the
   `widget:*` SurfaceSpec (jetpacs-widgets.el:2840-2850);
   jetpacs-shell classifies `widget:`/`tile:` namespaces and accepts
   any `widget:NAME` surface id (`jetpacs-shell--surface-target`,
   jetpacs-shell.el:167-178), gates pushes on `surfaces.widget`/
   `surfaces.tile` (`jetpacs-shell--gate-capability`,
   jetpacs-shell.el:720-729), and its own error degrade already emits
   a widget SurfaceSpec (jetpacs-shell.el:391); the Companion wire
   engine accepts granted `widget:` pushes
   (companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt:796-803).
   What's actually missing: widget_item/widget_divider/tile node types
   (the 52-type list, jetpacs-vocabulary.el) and any Android
   AppWidgetProvider/Glance/TileService renderer (none in companion/).
   **STOP — the renderer absence alone is enough to drop the feature
   from this port (open question 1); a future widget track needs only
   nodes + a Companion renderer, the Emacs-side seam is done.** (v1
   sites: capture:6-53, detail:25,48, clock:65-84, agenda widget rows.)
2. **Plain-FAB builder / app-default FAB registry** — only
   jetpacs-fab-menu (widgets:1485) + per-screen `:fab` slots exist.
   **GO — per-screen :fab on every glasspane chrome screen; no base
   work.**
3. **Companion share-sheet intake (share.text)** — no foundation
   reference to share.text emission. **GO for the Emacs side (handler
   registers; it is an offline-replay entry point); Companion
   emission verified/built before the flow is claimed working — G9
   checklist item.**
4. **Per-app managed-config seam** (jetpacs-app-dir /
   jetpacs-app-config-*) — nearest code is PRIVATE
   `jetpacs-app-store--adopt-dir` (jetpacs-app-store.el:86, used at
   :100,:194); jetpacs-settings.el:26 records POC 3 dropped it
   deliberately.
   **GO with app-local helper (~40 lines) in G2; promote to
   jetpacs-app-store only if a second app wants it.** Corollary
   decision (install consent): in-tree/dev loads are never in
   `jetpacs-app-store-installed`, so dev first-boot seeding is MANUAL
   (`M-x glasspane-config-ensure` / `glasspane-packages-ensure`);
   store-adopted installs keep the automatic path. No base work.
5. **Dock-item badge** — the dock item shape carries no `:badge`
   (jetpacs-chrome.el:77-89,177-204) though jetpacs-icon supports one
   (jetpacs-widgets.el:669). Two v1 consumers (Agenda tab count,
   SRS due count). **PREREQUISITE-LITE: a one-key `:badge`
   thread-through in jetpacs-chrome--dock-tab/rail is the right base
   change, scheduled any time before G5; the accepted fallback
   (in-screen counts) means it never blocks a rung.**
6. **Org body-fragment → widget renderer** (jetpacs-org-rich) — v3's
   only org renderers are the whole-buffer Tier-0 skin
   (jetpacs-org-render.el:1-35,632) and the outline card list
   (jetpacs-org-outline.el:66). **GO with the degrade** —
   `(jetpacs-text BODY :syntax "org")` at G4 — **losing inline
   tappable checkboxes, native tables, emphasis spans in the app
   reader; open question 2 decides whether the v1 rich renderer gets
   an app-side port rung (G4b).**
7. **RichSpan strikethrough** — no `:strike` member
   (jetpacs-widgets.el:643-661). Three v1 consumers (views done rows,
   reader done titles, detail done headline). **GO with the color
   degrade now (done-green keyword + on_surface_variant title); a
   one-member SPEC 17.2 amendment is PARKED — open question 3.**
8. **Shared theme-picker kit** — v1 jetpacs-theme-picker.el absent;
   jetpacs-modus.el is queries only. **GO app-local
   (glasspane-theme-picker.el in G8); promote to foundation only when
   modus wants the same composition.**
9. **Note-graph vulpea queries outside the vetted grammar** —
   jetpacs-org-vulpea.el covers the query-sexp protocol only
   (:96,:147); backlinks/by-ids/search-by-title/stale-notes have no
   staging wrapper. **GO with raw guarded vulpea-db-* calls in
   glasspane-notes (legal for an app); a link/graph arm in
   jetpacs-org-vulpea is a later foundation candidate.**
10. **Date arithmetic/formatting helpers** — zero definitions in v3
    (grep-verified). **GO app-local module in G5.**
11. **Base org-render table cells are read-only**
    (jetpacs-org-render.el:148-186 emits no cell/table actions though
    widgets support them, jetpacs-widgets.el:1149,1168). **GO —
    glasspane authors its own table nodes in G6; a cell-action seam in
    the base skin is deferred until the buffer-skin path needs
    editing.**
12. **Base heading-sheet candidates hardcoded**
    (jetpacs-org-dialogs.el:217-234, no extension hook). **GO —
    decided at G4: delegate the org editors to base dialogs, keep an
    app sheet for the Clock/Properties/Open delta. A candidates hook
    is a foundation candidate only if a third consumer appears.**
13. **Snackbar on chrome stacks** — WORKS, not a gap. Ungranted
    `presentation.snackbar` queues via `jetpacs-shell--inject-snackbar`
    (jetpacs-shell.el:983-1007), which injects into the scaffold of
    whichever view the next push lands on — the multi-view case is
    handled, not degraded; toast is only the fallback when neither
    shape offers a scaffold. With the grant, `jetpacs-shell-notify`
    raises immediately in whatever scaffold is on screen, no injection
    at all (jetpacs-shell.el:1014-1032); the jetpacs-chrome.el:28-33
    comment describing injection as out of scope is stale. **GO — no
    base work; verify both arms (granted raise, ungranted next-push
    injection) against the app's actual grant profile at G9.**
14. **Save-refresh seam** — v1's core-owned
    jetpacs-shell-save-refresh-predicate/-hook has no public v3
    equivalent (privates: jetpacs-shell--schedule-repush
    jetpacs-shell.el:322; surface-scoped jetpacs-buffer-defer-refresh
    jetpacs-buffer.el:1138). **GO with an app-local ~15-line debounce
    (after-save → idle timer → jetpacs-shell-push, guarded by
    jetpacs-connected-p); promote to jetpacs-shell when a second
    Tier-1 reimplements it.**
15. **Pack/manifest seam** — no bundle producer (task-acknowledged).
    **STOP — glasspane-pack.el retired below; revisit at repo-split
    time. The v1 owner-filtered manifest concept maps onto
    jetpacs--claim ownership records (jetpacs-surfaces.el:103) when a
    producer is built.**
16. **Server-initiated dialog UPDATE** — no dialog.hide/update verb in
    ebp.el; dismissal itself is already covered by `ebp-client-abandon`
    (ebp.el:1148-1159, `rpc.cancel` → Companion error 1301, SPEC 18.1),
    already used by `jetpacs-org-dialogs--archive`
    (jetpacs-org-dialogs.el:1142-1148). **GO — v1's 5 handler-side
    `jetpacs-dismiss-dialog` sites map onto `ebp-client-abandon` +
    no-op-on-1301 callback (S3); a new ebp verb only if a future flow
    needs to mutate a LIVE dialog's contents from Emacs, not merely end
    it.**
17. **run-tests.sh wiring** — not a foundation gap, a G0 deliverable
    (the `-L` addition + suite stanza); recorded here because three
    verification passes flagged it independently.

## Retirement list (ports to NOTHING)

| v1 code | reason |
|---|---|
| glasspane-pack.el (whole file) | no pack/manifest seam, no bundle producer (gap #15); its depends data folds into glasspane-packages--set |
| glasspane-source.el (whole file) | the binding/source layer is ratified dead with D-3 (docs/PLAN-jetpacs-apps.md:844-848,1007): drop, never re-seam; all views are :builder; --iso-date duplicates ebp-org-ts-date, --priority/--string fold into views if needed |
| jetpacs-defsource "glasspane.notes" (notes:239-249) | same ruling; query helpers become plain functions |
| glasspane-ui bimodal-toggle machinery only — rendered/plain mode vars (ui:531-543, excluding the reader/refile vars `glasspane-org-reader-file`/`-refile-list` and the files.filter write-target `glasspane-ui--files-filter`, all of which survive), the mode-toggle seam hooks (ui:555-557), checkbox.toggle (ui:491-508), org toolbar/FAB wiring (ui:562-574), after-save invalidation (ui:589-590), files-open-hook (ui:583-586) | foundation-owned: jetpacs-org-render.el:740-851 claims only the bimodal rendered↔plain toggle (`jetpacs-org-render--files-mode` hash :757, `jetpacs.org.view-mode` verb :809-827, seams :832-851); the v1 block was actually TRIMODAL — the foldable reader (`glasspane-ui--org-editor-body`) and refile drag-list (`glasspane-ui--org-editor-actions`) have no foundation home and PORT in G4 with replacement surfacing |
| glasspane-ui vanilla-app block (ui:107-108) | single-app contract is automatic (jetpacs-apps.el:13-16,105-120) |
| glasspane-org-reader's jetpacs-org-rich dependency | no v3 rich body renderer; degrade per gap #6 |
| glasspane-table org.footnote.show (table:7-17) | base jetpacs.org.footnote handles it (jetpacs-org-dialogs.el:1161) |
| jetpacs-dialog-style settings row (table:54) | no such defcustom; style is per-dialog |
| glasspane-detail clocked-in duplicate (detail:236-251) | ebp-org-clocked-in-p owns it (ebp-org.el:1319) |
| detail handlers' PROMPT arms only — heading.todo-set/schedule's `(ask . t)` picker path, the empty-date path bridged through org-read-date, plus deadline/*-time/repeater/planning.show/archive/add-heading wholesale | shipped foundation dialogs (jetpacs-org-dialogs.el:385-745,1163-1169) — user-picker flows only; the todo-set/schedule/priority/tags DIRECT arg arms (:state/:when/:value/:clear) are KEPT app-owned, emitted by G5/G6 with computed args — see G4 |
| org-ql routing commentary only (glasspane-org.el:274-281) | v3 never forks to org-ql (ebp-org.el:1277-1282); the org-ql dispatch itself lived in v1 core jetpacs-org-query, already removed — the rest of the range (282-308, --vulpea-query/--query) PORTS in G1 behind its existing feature guard |
| widget/tile/default-FAB preamble (capture:6-67), widget rows (detail:25,48; clock:65-84), agenda widget dividers | gap #1 (STOP) + gap #2 (per-screen :fab) |
| overlay/open-flag/view-switched-close machinery (ef:50,262-266,285-286; gallery:21,100-108; views two-screen trick) | chrome stack lifecycle (jetpacs-chrome.el:496,555-567) |
| agenda clock tombstone view (agenda:105-113) | dies with the tab fabric |
| jetpacs-form registry usage everywhere | S2/S3 replacements |
| fboundp guards on shell notify/push/refresh | hard deps in v3 |
| glasspane.el's require of glasspane-pack + glasspane-org-reader wiring in ui (ui:32 usage superseded portions) | per rows above; glasspane-org-reader itself PORTS (G4) — only ui's read-mode wiring dies |

## Open questions for Caleb (product choices only)

1. **Home-screen widget + Quick Settings capture tile.** The
   Emacs-side surface class and push seam already exist
   (`jetpacs-widget-surface`, `widget:`/`tile:` gating); what's
   missing is the node vocabulary and any Companion renderer (gap #1).
   Ship Glasspane 1.0 without the feature, or schedule the node types +
   Companion widget/tile renderer as its own post-port track?
   Recommendation: ship without; the capture FAB and share-sheet path
   cover the affordance on-device.
2. **App-reader body fidelity.** With jetpacs-org-rich dead, the
   reader's inline bodies land as plain `:syntax "org"` text — no
   tappable checkboxes, native tables, or emphasis spans inside the
   app's collapsible reader (the Tier-0 buffer skin still renders org
   files fully). Accept the degrade for 1.0, or fund an app-side port
   of the v1 rich body renderer as a G4b rung? Recommendation: accept
   for 1.0; revisit on dogfood feedback.
3. **Strikethrough SPEC amendment.** Done-state text currently
   degrades to color styling (gap #7). Park a one-member SPEC 17.2
   `strike` span amendment for the next amendment batch, or ratify
   the color degrade as the permanent convention? Recommendation:
   park the amendment (small, additive, three consumers already).

## Pre-G9 punch list (ladder review advisories) — SWEPT 2026-08-14

All forty advisories are dispositioned: 24 [FIXED], 11 [TEST
STRENGTHENED], 4 [WONTFIX], 1 [DEFER-G9]. Two fixed items bank a
device-only residual on the G9 checklist (#2, #20). Each entry below is
compressed to the advisory's first sentence plus its stamp; the full
advisory text, the triage reasoning, and the diffs live in git (see
`chore(glasspane): pre-G9 punch list swept`).

- #1 [G1] **[TEST STRENGTHENED]** Partially vacuous test: glasspane-test-org-timestamp-hooks claims "a bare require never mutates the user's global org hooks" but never asserts it. Landed: the test re-loads glasspane-org after glasspane-org-remove-hooks and asserts all four org hooks stay clean — the mutant gate for a v1-style top-level add-hook.

- #2 [G1] **[FIXED]** P1-12-adjacent cache-key gap: glasspane-org--todo-items (glasspane-org.el:237) and glasspane-org--all-tags (:417) memoise arm-dependent payloads under keys that don't encode which arm ran. Landed: both keys now carry the arm flag, mirroring each function's own branch condition verbatim; the query-routing test gained a cross-arm probe. Residual (a real mid-session vulpea light-up) banked for G9.

- #3 [G1] **[WONTFIX: not an advisory — names no change]** Everything else verified clean (no defaction handlers in the data layer, the ext: idiom throughout, the mandatory query KEY present, all find-file-noselect sites clamped, hooks behind install-hooks). The G1 reviewer's clean-bill inventory; spot-checked and still true after G2–G8.

- #4 [G2] **[FIXED]** glasspane-clock.el:146-152 — glasspane-clock--on-ready re-asserts only when a clock RUNS; after a restart with no running clock the phone's cached ongoing chronometer notification is never retired and sits in the shade forever. Real defect. Landed: the no-clock arm sends jetpacs-shell-remove-root (ungated, not routed through --soon — READY is not a dispatch extent), so the hook settles BOTH directions of the cache.

- #5 [G2] **[FIXED]** glasspane-packages.el:99-102 + :173-181 — the folded min-version floors are decorative: an installed-but-old package never reaches the install loop, and (package-install SYMBOL) no-ops when any version is installed. Real defect. Landed: a sibling glasspane-packages--outdated (package.el-installed and below its floor) joins --missing in the loop and installs the archive DESC, not the symbol; --missing stays loadability-based so a loadable non-package.el checkout is never force-installed; the ensure early-exit consults both sets.

- #6 [G2] **[FIXED]** glasspane-config.el:133-134 and glasspane-packages.el:194-196 use (error-message-string err) in *Messages* logs while glasspane-clock.el deliberately uses jetpacs-error-label citing SPEC 23.3. Landed: both sites adopt the clock's jetpacs-error-label posture; the config message keeps the FILE name as its diagnostic anchor.

- #7 [G2] **[TEST STRENGTHENED]** glasspane-test-packages-wanted-drops-vulpea's first assertion restates the --set constant verbatim (a tautology that passes under any edit made in both places). Landed: derived-property assertions (the floors parse under version-to-list, the entry count matches --set); the biting sqlite arms untouched.

- #8 [G2] **[FIXED]** glasspane-config.el:204 — glasspane-config-startup at the load tail executes any EXISTING managed subtree under the real user-emacs-directory during batch byte-compile/suite runs. Hermeticity hazard. Landed: the load tail is now `(unless noninteractive (glasspane-config-startup))`; the function itself is untouched, so M-x and the direct-call tests keep working.

- #9 [G2] **[TEST STRENGTHENED]** test/glasspane-test.el:443-445 — the in-last 'accepted arm uses (make-marker) with no buffer, so the deferred-save path of glasspane-clock--on-in-last is never exercised in the accepted case. Landed: the arm runs in a temp buffer with a live org-clock-marker and asserts the save was deferred in that buffer.

- #10 [G3] **[FIXED]** Dialog slot clobber race — glasspane-ui.el:385-404: --show-dialog overwrites glasspane-ui--settings-dialog without abandoning a still-live prior dialog, and every show's callback unconditionally nils the slot. Landed: the show abandons any live prior dialog first, and the callback clears the slot only while it still holds its own request-id (carried in a one-cell box); the on-submit call stays outside the identity guard.

- #11 [G3] **[WONTFIX: stale]** Mid-ladder dead verbs — glasspane-ui.el:444/455 and :306-313 wire settings.todo.save / settings.todo.delete, which register only in G5. G5 landed: both register at glasspane-agenda.el:800-801. No dead verbs, no interim stubs owed. (They are dialog-fired, so the D1 gate is inert and they correctly stay owner-scoped — see #37.)

- #12 [G3] **[TEST STRENGTHENED]** Mutant survivability — glasspane-test-ui-handler-statuses asserts a deferred continuation only for glasspane.settings.open; a mutant that makes glasspane-ui--defer-refresh push directly still passes. Landed: a counting jetpacs-shell-push stub wraps the whole handler matrix and the count is asserted zero.

- #13 [G3] **[TEST STRENGTHENED]** Test hygiene — glasspane-test-ui-handler-statuses calls glasspane-ui-register twice and leaves org-clock-in/out hooks and the teardown hook attached in the batch process. Landed: unwind-protect with glasspane-ui-unregister in the cleanup, which also exercises the unregister sweep.

- #14 [G4] **[TEST STRENGTHENED]** test/glasspane-test.el:1415-1422 — the `pushes` counter in glasspane-test-detail-handler-triples is stubbed, incremented, and then `(ignore pushes)`d, never asserted. Landed: `(should (zerop pushes))` after the at-ref dispatch block, where the only legitimate push sites are inside never-run continuations.

- #15 [G4] **[FIXED]** glasspane-org-reader.el:686 — (error-message-string err) is rendered into a device-facing caption, while plan T2 maps user-facing error text to jetpacs-error-label (SPEC 23.3). Landed by the advisory's own second option (comment, no code change): the vetting is recorded at the site — this arm catches only ebp-org-parse-query user-errors (fixed strings plus the user's own query keyword, no org payload), and jetpacs-error-label would degrade the caption to the useless "user-error". The T2 grep has a vetted exception here, not a slip.

- #16 [G4] **[FIXED]** glasspane-detail.el:1146-1171 — detail.save with a :value whose leading stars the user deleted answers 'rejected only after delete-region+insert, leaving an unsaved buffer mutation that the next unrelated save flushes to disk. Silent-mutation defect. Landed: a leading-stars shape gate answers 'rejected BEFORE the region is touched; the test asserts the subtree text is unchanged.

- #17 [G4] **[FIXED]** glasspane-detail.el:80-81 — the declare-function for glasspane-org-reader-subtree omits the real function's 4th optional SET arg, and glasspane-detail--reader-nodes relies on the default "reader-subtree" set. Landed: the declaration carries the real 4-arg signature and the call passes "detail-subtree", removing the replace-sweep hazard; glasspane-org-reader.el is not edited.

- #18 [G4] **[WONTFIX: the cure is a foundation change, not an app edit]** glasspane-org-reader.el:723,744 — the body/actions seams key off jetpacs-org-render--files-rendered-p, a foundation double-hyphen private. A public rendered-p accessor widens a base API that every Tier-1 app and the whole 984-test gate ride, for a purity gain only, and would still not close the test half (which needs the private files-mode hash). Correct home: a foundation-side advisory in the base repo's own review, verified against Glasspane per the cross-repo procedure.

- #19 [G4] **[TEST STRENGTHENED]** glasspane-detail.el:1602-1608 — heading.clock-in is registered and emitted from four surfaces but never exercised by the gate suite. Landed: a clock-in round trip in detail-handler-triples — 'accepted with org-clock-in called on a live token, 'stale on a swept or absent one.

- #20 [G5] **[FIXED]** share.text/org.capture.share are registered under with-jetpacs-owner "glasspane" without :any-surface, and the D1 gate rejects any event whose wire surface is a string not owned by glasspane. Landed: both declared :any-surface on the launcher precedent (a share is attributed by the Companion, not by the app's surface); org.capture.show stays owner-scoped. Residual (the surface string a real Android share actually carries) banked for G9.

- #21 [G5] **[FIXED]** journal.capture inserts wire text raw into the datetree: the device input is single-line, but a crafted wire event can carry newlines, promoting payload to org structure. SPEC 23.2. Landed: glasspane-journal--on-capture collapses whitespace before the append, so an embedded newline cannot become a heading, keyword line, or local-variables block; --append (the M-x path) is unchanged.

- #22 [G5] **[FIXED]** Token-set growth is unenforced: each agenda page mints two sets, so ~25+ saved custom agendas exhausts ebp-org-token-sets-max and the mint SIGNALS, killing the whole body build. Landed: glasspane-agenda--custom-max (8) caps the mode list via seq-take, and the comment's unbounded "well under the cap" assertion is replaced by the real bound (3 spans + the cap). glasspane-ui's saved-search list still shows every saved agenda.

- #23 [G5] **[FIXED]** glasspane-journal--on-view-change matches only the owner's primary surface via jetpacs-shell-surface-for, so a journal screen pushed onto a different tapped surface never resets its day on leave. Landed: the test is now jetpacs-owned-surface-p (primary or claimed) — chrome-push-screen accepts any surface, so the journal can live on a claimed secondary.

- #24 [G5] **[TEST STRENGTHENED]** glasspane-agenda--tokenize's disallowed-file filter and the token/archive-token attachment onto agenda/tasks cards are untested. Landed: a mixed allowed/disallowed batch asserts the refused card carries neither cell yet still appears, the allowed card carries both, and the archive tokens resolve under jetpacs-org-dialogs-owner.

- #25 [G5] **[FIXED]** The float coercion in agenda.set-mode/nav and journal.nav accepts non-whole floats (0.7 -> 0) as valid, looser than the "whole-valued integer arrives as float" rationale in the comments. Landed: all three sites coerce only whole-valued floats, so a fractional wire value now falls through to the integerp check and answers 'rejected — a malformed event, not a rounding job.

- #26 [G6] **[DEFER-G9: the cure is a rung, not a bounded punch-list edit]** Reachability: nothing on any surface emits the new verbs — no drawer row, hub card, dock item, or FAB points at views.hub/search.open, and glasspane-table-node has no caller. Confirmed still true (glasspane.el:88-120 is the G0 placeholder home). Escalated to the ladder: the hub-wiring rung must land BEFORE the G9 device session, because only that session can prove the new surfaces are reachable on hardware rather than dead code.

- #27 [G6] **[FIXED]** glasspane-search.el:431 — glasspane-search--on-clear-filters uses (plist-get params :surface) with no jetpacs-shell-surface-for fallback, unlike every sibling handler. Landed: the sibling fallback added; the ignore-errors stays.

- #28 [G6] **[FIXED]** glasspane-table.el:244-245 — the babel user-error arm notifies "Evaluation declined" for every user-error, including org-babel-confirm-evaluate's `:eval no` refusal, mislabeling a block-level policy as a user decline. Cosmetic. Landed: a new glasspane-table--disabled error is signalled when org-babel-check-confirm-evaluate shows the POLICY (not the user) refused, with its own fixed-string notification; the generic arm keeps its wording.

- #29 [G6] **[FIXED]** Duplication: glasspane-views--tokenize and glasspane-search--tokenize are the same ~20-line mint-filter-attach helper differing only in the :set name. Landed: a shared glasspane-ui--tokenize-tap (ITEMS SET) carries the S5 policy in one docstring; both copies deleted and their callers repointed. glasspane-agenda--tokenize (a second set under a different owner) is deliberately out of reach.

- #30 [G7] **[FIXED]** Gate-order inconsistency across the two files: glasspane-notes.el checks vulpea availability BEFORE the token lookup (a swept token answers 'rejected) while glasspane-srs.el checks the token first. Landed: both notes handlers adopt the plan's S4 order (shape → stale → exposure → grant), so a swept token answers 'stale; the guard-contract test asserts it. glasspane-srs.el is the reference convention and is not edited.

- #31 [G7] **[TEST STRENGTHENED]** The mention-card render path (glasspane-notes.el:291-315 and the tap/edit token pairing at :330-341,375-377) is never constructed in any local test. Landed: a glasspane-notes-detail-nodes test over a stubbed ready state pins heading.tap to the TAP token, link.materialize to the EDIT-site token (a swapped destructure fails), and the Link-it action's :ttl-s.

- #32 [G7] **[FIXED]** glasspane-notes--mint is all-or-nothing: ebp-org-ref-tokens validates atomically, so ONE mention path outside the org roots nils the WHOLE batch and, aborting before the replace sweep, leaves the PREVIOUS render's token set live. Landed: refs are pre-filtered with ebp-org-file-allowed-p, minted in one atomic call, and nils spliced back into the rejects' parallel positions, so the sweep still runs and only the offending card degrades.

- #33 [G7] **[FIXED]** glasspane-srs.el:910 installs a top-level (with-eval-after-load 'org-srs ...) that survives M-x unload-feature, so a later (require 'org-srs) signals a void-function inside org-srs's own load. Landed: the form is fboundp-guarded and stays top-level, so the late-install path the docstring relies on survives.

- #34 [G7] **[FIXED]** glasspane-notes-unregister's docstring claims "the async cache sweeps its own entries by owner" — jetpacs-async-clear-owner runs only from jetpacs-teardown-owner, which glasspane-unregister never calls. Docstring drift only. Landed: the clause now says the entries die by per-push generation eviction.

- #35 [G7] **[FIXED]** glasspane-srs-unregister leaves the session defvars (--active/--current/--revealed/--undo) populated, unlike the notes sibling, so an unregister/re-register cycle resumes a phantom session. Landed: one setq clears all four beside the hook removals, the docstring says the session dies with the registration, and the handler-status test asserts it.

- #36 [G8] **[TEST STRENGTHENED]** Test blind spot that hid the must-fix: all G8 handler tests invoke handlers via (gethash NAME jetpacs-action-handlers) and never cross jetpacs--dispatch, so the SPEC 14.4/D1 surface-scope gate is untested. Landed: dispatch-level assertions for ef.show and for the #37 verbs on a foreign surface, plus a negative control on a verb that stays owner-scoped.

- #37 [G8] **[FIXED]** Pre-existing, same family, OUT of that diff: glasspane-ui.el:811 registers "glasspane.settings.open" owner-scoped, and its only button is the order-80 Settings link — the landed G3 rung has the identical dead-link defect. Landed: :any-surface on exactly the six verbs whose only emission site is the Settings root (glasspane.settings.open, settings.line-numbers, settings.tags, settings.todo.edit, settings.agenda.edit, settings.agenda.delete), headed by the ef precedent. Dialog-fired verbs (the gate is inert on a conclusion, which carries no :surface) and own-surface screens stay owner-scoped.

- #38 [G8] **[TEST STRENGTHENED]** glasspane-test-ef-absent-paths never asserts the ef Settings link registers exactly once across re-register nor that glasspane-ef-unregister removes it. Landed: the gallery-trees symmetry — count 1 after a re-register, absent after unregister.

- #39 [G8] **[WONTFIX: hypothetical, no defect]** glasspane-demo's demo.setup/demo.setup-org are owner-scoped with no on-wire button in the port; if a device button ever lands on the Settings screen they will need the same :any-surface treatment. No emitter exists (M-x and offline replay only, as the file's commentary states), so the D1 gate is never reached and declaring :any-surface now would widen the gate for a caller that does not exist. #37 records the rule that settles it if that button ever lands.

- #40 [G8] **[FIXED]** glasspane-demo--org-target honors only (car ebp-org-roots) — correct against ebp-org--roots anchoring, but a multi-root vault seeds only the first root; the docstring could say so explicitly. Docstring only. Landed: the single-root behaviour and its rationale (one self-contained tour directory) are stated.

Banked on the G9 device checklist (residuals of fixed items — observable only on hardware):

- #20 residual — share text from another app into Glasspane; confirm the intake answers accepted and the capture picker opens. What surface string the Companion stamps on an Android share (absent, the launcher's, or a foreign one) cannot be observed from a batch run.

- #2 residual — with vulpea actually installed (absent locally by house rule), load it after a first Agenda render and confirm the next render switches to the vault-index arm without a mutation.

- #26 — the hub-wiring rung must land before the session; see the DEFER-G9 entry above.
