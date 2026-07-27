# The app tier — per-module verdicts and build ladder

*Source: 31 poc-v1 modules, 14,021 lines, assessed across eight clusters and
adversarially challenged (workflow `wf_c9bb90be-626`, 18 agents, 2026-07-26).
Where a challenge corrected a verdict, the correction is used below.*

This is the successor plan to `PLAN-jetpacs-consumers.md` (the JC ladder,
JC-0..JC-5 complete + W10). Rungs here are named **JA-n**.

---

## 1. The verdict table

### port — mechanical translation, logic survives intact

| module | lines | effort | value | reason |
|---|---|---|---|---|
| `jetpacs-org-toolbar.el` | 87 | trivial | high | Pure §17.7 ToolbarItem data; the spec survived format 6 unchanged and `smoke-toolbar.el` already proves the mechanism. Two mechanical fixes (positional→keyword args; `:long-press` is an op plist, not a nested item). |
| `jetpacs-commands.el` | 78 | trivial | high (upgraded) | 78 lines with zero wire contact. Only change is `(require 'jetpacs)` → `jetpacs-surfaces`. Upgraded from "medium/derivative": the rewrite already carries **two** hand-rolled command denylists (`jetpacs-sections-menu-denylist`, and keymap's), so this is the consolidation point, and `jetpacs-unsupported` is the definition-site channel neither has. |

### rebuild-lite — logic survives, transport/prompt/surface seams get rewired

| module | lines | effort | value | reason |
|---|---|---|---|---|
| `jetpacs-theme.el` | 454 | medium | high | ~200 lines of Emacs-side extraction (modus semantic palette, tty-safe hex parse, face resolution) has no Companion equivalent and ports untouched; the whole wire half is new — SPEC 18.4 deleted `base`, so the tri-mode enum is unexpressible, and syntax roles became objects. |
| `jetpacs-triggers.el` | 296 | medium | high | The Companion already ships durable device-lifetime firing, 17 types and `on_fire` substitution, all unreachable from Emacs. Registry + `deftrigger` + replace-set assembly are the missing glue (G2). `when`-gate filter retires (ebp does it); `trigger.fired` is a **rebuild** (§14.4 durable admission). |
| `jetpacs-project.el` | 357 | medium | high | Root selection, name resolution and widen-roots are ~60 portable lines; everything else is chrome + a buffer-view seam that does not exist. Three D2 violators, not two — `project.buffers` prompts via `(project-current t)`. |
| `jetpacs-hosts.el` | 279 | **large** (corrected) | high | ssh-config parsing, the label allowlist, connection-state-by-reading and the timeout clamp all survive; the module's design comment banks on prompting *inside* the handler, which D2 inverted. Effort raised: three of four actions produce a buffer, and nothing in the rewrite can put a buffer on a surface. |
| `jetpacs-package-browser.el` | 247 | medium | medium | The three tablist skin hooks port with call-site drift only — and this is the rewrite's *only* worked example of an API it advertises with no in-tree consumer. Four actions do minutes of network I/O inside handlers. |
| `jetpacs-devtools.el` | 187 | small | medium | ~60 lines survive (report renderer, storm predicate, last-spec retention). The stated blocker is void: a `:before` method on `jsonrpc-connection-send` composes with ebp's `:around`. But push is a *request* now, so the data model (count notifications) is superseded by observable outcomes. |

### rebuild — the contract underneath inverted; most of it is new code

| module | lines | effort | value | reason |
|---|---|---|---|---|
| `jetpacs-files.el` | 1064 | large | **essential** | ~300 lines genuinely port (sandbox guard, /sdcard probe, grep scanner, seams); the five ops, both dialogs and the whole view layer are new. `files.save`'s real bound is `max_event_bytes`, which nothing in ebp reads. |
| `jetpacs-org-rich.el` | 563 | large | medium | The document model is good; format 6 deleted four of its inline span features (`strike`, `tag`, sub/superscript) and **all seven** of the actions it emits were never registered anywhere. No caps, no budget — it will blow `max_rich_spans` on any real subtree. |
| `jetpacs-transient.el` | 315 | medium+ | high | The version-compat layout reader (~135 lines) is the crown jewel and ports verbatim. Everything above it dies: SPEC 18.1 gives 1201 to a second request with the same `dialog_id`, so the show→toggle→re-show loop has no wire representation. |
| `jetpacs-witheditor.el` | 197 | small | high | ~60 lines survive (message-region arithmetic, live-session validation, one-shot guard). The push-model dialog, the two custom actions and the ui-state seed-and-read-back are all gone. Fails **closed** today: every tablet-initiated commit stalls forever. |
| `jetpacs-spec.el` | 253 | large | speculative | Corrected from the plan's "port". Alist-native against plist nodes, chrome half calls three shell functions that do not exist, and its binding vocabulary was deleted with contract format 5. **NO-GO — not scheduled.** |

### split — sub-capabilities diverge; a single verdict would hide the work

| module | lines | effort | value | reason |
|---|---|---|---|---|
| `jetpacs-org.el` | 2797 | very large | **essential** | ~730 lines **port** (extraction engine + shared primitives), ~750 **rebuild-lite** (render skin, habits, outline), ~510 **rebuild** (header sheet, footnote, timestamp editor, add-heading), ~710 **defer** (capture builder, detail overlay). "Port jetpacs-org" was never an actionable unit. |
| `jetpacs-lint.el` | 924 | medium (corrected) | low overall | ~280 **retire** (contract tables, payload validator, sanitize-on-push — the last contradicts a ratified gate design), ~110 **defer** (trigger linter → triggers cluster), ~200 **rebuild** (opaque-member walk — real subject, see §4), ~40 **rebuild-lite** (test helpers, take now). |
| `jetpacs-emacs-ui.el` | 646 | large | **essential** | Buffer list + drill-in + M-x + eval REPL is what makes the tablet a general client, and it is the load-bearing host for `jetpacs-tablist-view-buffer-function` (still a `message` stub). ~80 lines are chrome; the rest splits rebuild / rebuild-lite. |
| `jetpacs-keymap.el` | 719 | **small–medium** (corrected) | high (palette) / retire (pie) | Keymap extraction + **menu-bar mining** (~195 lines) port verbatim and are the best idea in the cluster — human-written labels for any mode. The pie menu (~217 lines) retires, which also deletes the SPEC 23.2 exposure blocker entirely. |
| `jetpacs-settings.el` | 555 | medium | high | The defcustom apply engine has no equivalent anywhere and five poc modules build on it. Engine corrected `port`→**rebuild-lite** (the blanket `condition-case` swallows `inhibited-interaction`, destroying the diagnosis it exists for). Switch watcher corrected → **rebuild**. Owner filter/hub retires — D1 replaced it. |
| `jetpacs-device.el` | 401 | large | medium | Reminders wrapper **promoted** to the module's highest-value shippable piece (`reminders.owner` is granted and `handleRemindersSet` is implemented — it works today, with a tappable `on_tap`). Invoke funnel + `vibrate`/`clipboard.read` rebuild-lite. 16 wrappers defer on Kotlin. Permissions screen corrected → **defer**. |
| `jetpacs-apps.el` | 378 | medium | high | `jetpacs-app-unregister` is verbatim gap G5 and D1 makes it *more* urgent (a leaked owner leaves a visible surface). The launcher corrected `defer`→**rebuild-lite**: `jetpacs-shell-push` is owner-unchecked and `--build` rebinds the owner, so cross-surface push works today, no Kotlin. Filters/FAB seam/vanilla-app retire. |
| `jetpacs-modus.el` | 298 | small | medium (corrected) | Style options = one `register-section` call on a ported settings engine. `modus.toggle` corrected → **port, ships today**: no device-side M-x exists, and #36's follow-the-device polarity makes an Emacs-side light/dark flip *more* necessary, not less. Picker screen defers. |
| `jetpacs-tools.el` | 195 | small | medium | Kill-ring→clipboard is the best value/effort item in the cluster (corrected: effort `small` not trivial — needs a byte cap and a builtin-advertisement check). The four buffer actions corrected `defer`→**rebuild-lite**: the buffer host is ~15 lines, not app-shell work. Hub/drawer defer. |
| `jetpacs-demo.el` | 1160 | large | low | ~940 lines of prose describing screens that no longer exist. hello-app corrected `rebuild`→**retire**: `smoke-floor.el` already demonstrates D1 + the 14.4 status contract, and `smoke-dialog-prompts.el`/`smoke-picker.el` demonstrate D2 on hardware. **Nothing here is scheduled.** |

### defer — worth having eventually, not on the critical path

| module | lines | effort | value | reason / what unblocks it |
|---|---|---|---|---|
| `jetpacs-customize.el` | 359 | medium | medium | ~60% navigation. Unblocked by JA-3's M-x (which makes `customize-set-variable` reachable) plus JA-10's settings engine — at which point only the "Modified" filter and prefix search remain worth building. |
| `jetpacs-app-store.el` | 286 | large | low | Its entire substrate (`jetpacs-config.el`'s deployment half) was deleted at JC-3b and deferred to a U-phase. Unblocked by a second user existing. |
| `jetpacs-automations-org.el` | 205 | small | medium | 100% blocked on the triggers layer. Two set-wide defects kill the whole replace-set: the wire id is built from raw headline text (spaces → invalid §4.4), and there is no `:TTL:` drawer key though its own example uses `wake`. |
| `jetpacs-sql.el` | 199 | small | **speculative** (corrected) | Corrected from "low": there is no `sql-connection-alist` anywhere in Caleb's config, so the landing view is the empty state. Both handlers additionally block on `sql-get-login`'s `read-passwd`. |
| `jetpacs-source.el` | 170 | small | speculative | Healthiest code in its cluster and has no reader. `depends_on` corrected to **none** — the lint coupling is a 7-string defconst, not a governance act. Unblocked by the composer decision (D-3). |
| `jetpacs-automations.el` | 142 | small | medium | Pure rendering over the trigger registry; dead code until a first trigger exists. Topology corrected: a second `app:*` surface **hijacks** the display on this Companion — build it as a multi-view view inside the owning surface. |

### retire — do not bring forward

| module | lines | reason |
|---|---|---|
| `jetpacs-theme-picker.el` | 139 | One consumer (modus), and it hardcodes modus palette keys and gates on `modus-themes-activate` — the "generic scaffold" claim was false at authorship. `jetpacs-swatch` does not exist in the rewrite at all. |
| `jetpacs-pack.el` | 71 | All three data sources absent or optional; `jetpacs-defaction` records no per-action metadata to serialize; the composer repo exists but is empty (README + a TODO). Zero consumers, zero blocked work. |

**Where the adversarial pass overturned the assessment.** Six corrections change
scheduling, not just wording: (1) the view/nav framework is **not** a base
blocker — `multi_view` + `scaffold` + `view.switched` are all present and
smoke-verified, so screen swapping is an app-owned `defvar` plus a `pcase`;
(2) `on_change` value injection is mandatory Companion behaviour, so the two
`(alist-get 'value args)` sites are a rename, not a hazard — which is why the
capture builder moved from retire to defer; (3) the Emacs-side launcher works
today with zero Kotlin; (4) the buffer-view host is ~15 lines, freeing four
`jetpacs-tools` actions and much of project/hosts; (5) `editor` **is**
advertised for the dialog profile (the elisp constant was stale — fixed
2026-07-26, see B14) — voiding witheditor's fallback requirement; (6)
`trigger.fired` arrives through `jetpacs--dispatch`, so triggers can bridge
prompts today — the flow-entry gap is witheditor's alone.

---

## 2. What the numbers say

Of the poc's **23,337 lines across 45 core modules**:

- **9,316 are already resolved.** 7,193 lines became the rewrite's 9,943-line
  base (async, buffer, comint, hypertext, results, sections, shell, surfaces,
  tablist, widgets, complete, and minibuffer→dialog). 2,123 were retired
  outright — `jetpacs.el` (867) and `jetpacs-sync.el` (923) both replaced by
  `ebp.el`, and `jetpacs-config.el` (333) deleted at JC-3b for minting
  `file://` URIs.
- **14,021 lines remain**, in the 31 modules above.

Inside that 14,021:

| disposition | lines | share |
|---|---|---|
| retired outright | ~1,600 | 11% |
| deferred (nothing scheduled) | ~3,300 | 24% |
| **scheduled work** | **~9,100** | **65%** |

And inside the scheduled 9,100, roughly **1,700 lines port mechanically** — the
org extraction engine and shared primitives (730), keymap extraction plus
menu-bar mining (195), transient's layout reader (135), files'
guard/probe/scanner/seams (150), theme's color plumbing (95), modus's
version-adaptive queries (85), org-toolbar (87), commands (78), and the smaller
registries. Everything else is rewiring at best. Being honest about the rest: of
the ~7,400 remaining scheduled lines, maybe 40% survives as logic through a
rebuild-lite, so expect **~3,000 lines of surviving logic and ~4,400 lines of
genuinely new app code** — plus **1,200–1,800 lines of new base** that has no
port source at all.

**The largest single lumps:**

1. **`jetpacs-org.el` (2,797)** is the biggest file and the most decomposable.
   Its actionable shape is 730 port + 750 rebuild-lite + 510 rebuild + 710
   defer. The 646-line capture-template builder is the single largest
   deferrable unit in the whole tier.
2. **The shared app-tier floor (~500–700 new lines, no port source).** Named as
   the dominant cost by three separate clusters and costed by none of them:
   teardown, a flow-entry seam, a thunk-shaped buffer-view host, an identifier
   minter, chrome composition, a toast wrapper, a 1401 helper. Files, project,
   sql, tools, hosts, package-browser, emacs-ui, customize, modus and
   automations all block on some part of it.
3. **`jetpacs-files.el` (1,064)** — rebuild, essential, and the only path from a
   file on disk to a surface.
4. **`jetpacs-emacs-ui.el` + `jetpacs-keymap.el` (1,365)** — of which ~420 lines
   port cleanly and the rest is chrome and D2 inversions.
5. **`jetpacs-demo.el` (1,160)** and **~880 of `jetpacs-lint.el`** — the two
   largest lumps that come forward as *nothing*. Together that is 2,040 lines,
   15% of the remaining tier, deleted.

The shape of the work: this is not a port. It is roughly one-eighth mechanical
translation, one-third surviving logic on new seams, and half new code —
against a floor that has to be built first.

---

## 3. The ladder

Rungs are strictly dependency-ordered. Each exit gate follows the rewrite's
existing convention: an ERT suite that runs offline, plus a device smoke script
in `test/`.

### JA-1 — Device coherence *(no dependencies; ships standalone)*
**DONE + DEVICE-VERIFIED 2026-07-26** (c08dec1 theme+granted-p, 2f8d6eb
reminders+clip, 421399e device gate: theme mirror 7/7 — ready-hook push,
visible vivendi chrome, device toggle round trip with zero manual sends,
#36 native return; reminder tap 9/9 — real alarm at at_ms, Companion-injected
owner/reminder_id, the SPEC 14.4 omit rule witnessed live; clip 6/6 — offline
copy with NO session on the wire, 4096-byte cap proven in-band via
clipboard.read).  `modus.toggle` ships; heading-monochrome-under-operandi is
flagged for Caleb's eye (theme open-choice 2).  Two runner lessons recorded in
the gate commit: adb `forward --remove` does not sever established TCP, and
MainActivity does not restore the persisted surface on cold start (B18,
now witnessed).

**Lands:** `jetpacs-granted-p` (G1). `jetpacs-theme.el` rebuild-lite —
extraction ports verbatim, wire half rewritten onto `ebp-client-theme-set` with
`success`/`warning` added, `meta`→`preprocessor`, syntax values as SyntaxStyle
objects, and #36 follow-the-device as the default polarity. `jetpacs-modus.el`'s
version-adaptive queries (port) and `modus.toggle` (port). A
`jetpacs-reminders-set` wrapper with D1 owner default and owner→set
bookkeeping. The kill-ring→clipboard view from `jetpacs-tools.el`, with a
per-entry byte cap and a hand-rolled `clipboard.copy` advertisement check.

**Why here:** every piece works against the base as it stands today. No
navigation, no buffer host, no view system, no Kotlin. And it fixes the most
visible unfinished-ness on the device — `jetpacs-buffer` already emits per-span
hexes from live faces, so without a mirrored palette you get Nord buffer text
inside Material-You purple chrome. Light/dark and tappable reminders are the two
daily-use capabilities in the whole cluster set that have no substitute.

**Size:** ~450 lines (~150 port, ~300 new).

**Exit gate:** ERT — palette extraction against a fixture theme, role names
checked against `jetpacs-theme-roles`, the tty-hex path exercised in batch.
Smoke — `theme.set` accepted and the chrome visibly changes; a reminder fires
and its `on_tap` dispatches back into Emacs; `clipboard.copy` lands in another
Android app while the socket is down.

### JA-2 — The app-tier floor *(forced by every rung below)*
**CODE COMPLETE 2026-07-26** (11c0af8 utilities+flow, 7a7dfdc teardown,
42febe4 buffer host+chrome; 345 elisp / 16 suites).  Landed exactly as
briefed with the integration corrections: `jetpacs-flow-begin` (the name),
`jetpacs-refused-p`, `jetpacs-buffer-funcall-shimmed`; B9 ratified as the
floor commentary block (synchronous-when-cheap / durable-home / else
`jetpacs-retry-later` → 1500 with the load-bearing forced queue.replay);
teardown's local-first sweep order + the `jetpacs-shell--send-remove` W10
loss-proofing (the refused-tombstone test drives ebp's real held branch);
chrome representation A (one multi_view; back = the view.switch builtin;
13.4 background-refresh omission pinned by the suite); the C7 drill adapter
(minted id, deferred push, repeat-drill replace-top for free).
**DEVICE GATE DONE 2026-07-26** (c2e5fdb, one consolidated `smoke-ja2.el`, 16/16):
toast, stack drill + companion-local back (revision unmoved), navigate drill,
flow-begin bridging with no dispatch in the trace, teardown with the tombstone
applied and the survivor untouched, and the B9 retry-durable loop — same
event_id across three deliveries, record deleted on accepted.  **JA-2
COMPLETE.  Still open: the adversarial review over the JA-1+JA-2 diff
(deferred for usage, Caleb 2026-07-26).**
The §22.2/15.3 `retry_after_s` ratification amendment is flagged for Caleb
(the wire carries it as a SPEC-8 advisory extra meanwhile).

**Lands:** `jetpacs-teardown-owner` (G5), body taken from
`jetpacs-app-unregister` but clearing state **per surface**, not by id prefix.
`jetpacs-flow-enter` / `with-jetpacs-flow SURFACE` (G14) — the seam that
*establishes* a device flow rather than inheriting one. A thunk-shaped buffer
navigator (`call-shimmed` takes a command, not a lambda) that also shims
`display-buffer`, plus a real `jetpacs-tablist-view-buffer-function`. A
path/buffer-name → §4.4 identifier minter promoted out of
`jetpacs-comint--input-id`. A chrome kit: `top_bar`/`fab`/`drawer`/list-row
composed from row/column/card/icon-button over `scaffold`, plus a per-surface
screen stack with a back affordance. `jetpacs-toast` with the
`presentation.toast` gate (G7). A 1401-refused helper (G10). A ratified §14.4
durable-admission convention and `jetpacs-retry-later` (G12).

**Why here:** nine of the remaining modules cite some part of this. Teardown
alone is a daily-friction fix — Caleb live-reloads elisp constantly and under D1
every redefinition leaves a *visible* orphaned surface on the tablet.

**Size:** ~500–700 new lines. No port source.

**Exit gate:** ERT — teardown sweeps surfaces, actions, async generations and
state subscriptions for a synthetic owner; the identifier minter round-trips
`*shell /ssh:host:*`-class names; flow-entry marks `jetpacs-device-flow-p` from
a bare timer. Smoke — define two owners, tear one down, assert its surface is
tombstoned and the other is untouched; navigate to an arbitrary buffer and back.

### JA-3 — The general Emacs client
**CODE COMPLETE + GATED 2026-07-27** (447 elisp / 19 suites green; every
new guard mutation-verified).  Landed: `jetpacs-commands.el` (port; its
defaults absorbed the keymap-noise halves of both hand-rolled denylists —
sections keeps its destructive-magit SAFETY residue, consulted via
`jetpacs-command-visible-p` at BOTH sites incl. the 23.2 replay);
`jetpacs-keymap.el` (pure library — extraction + menu-bar mining +
palette candidates; poc bug FIXED: `current-minor-mode-maps` returns
plain keymaps, the poc destructured (VAR . MAP) and silently extracted
ZERO minor-mode bindings — regression-pinned); `jetpacs-emacs-ui.el`
(owner `jetpacs.emacs`, chrome hub + drilled screens with imenu/palette
affordances, *Messages* tail over `jetpacs-buffer-render-tail`, imenu
extends `jetpacs-results-show-region` via new public
`jetpacs-results-region-buffer`/`-clear-region`, M-x over the bridged
obarray picker); `jetpacs-echo.el` (JA-3d: OFF by default, explicit
install, device-flow-gated, throttled latest-wins, re-entrancy-proof).
Prereq fixed: `jetpacs-dialog--static-candidates` obarrayp guard (no
more whole-obarray enumerate+sort per bridged completing-read).
run-tests.sh byte-compile guard is now a GLOB over emacs/*.el.

**PORT LESSON (device-caught, then ERT-pinned): `execute-kbd-macro` runs
the command loop against the SELECTED WINDOW's buffer.**  On the device
the viewed buffer is never in a window, so the poc's palette self-inserted
the key into *scratch* and clobbered current-buffer; it only ever worked
on a desktop because the viewed buffer was also the selected window.  The
palette now resolves the binding in the buffer and runs the COMMAND under
`jetpacs-buffer-call-shimmed`.

**Device smoke (`test/smoke-ja3.el`, runner-driven)**: list ✓ drill ✓
palette-on-unskinned-mode ✓ (enum dialog → selection → execution
witnessed on hardware).  M-x: the icon opens the bridged picker dialog on
the device ✓, but the full type-and-submit round trip is
DRIVER-LIMITED, not witnessed — adb text injection raced the Compose
dialog's render/focus across three attempts.  Every link is proven
elsewhere (the same bridge carried the palette; the JC-4a text dialog is
device-verified by smoke-dialog-prompts; execution is `call-shimmed`,
ERT-pinned), so this is recorded as a runner gap, not a code gap: re-run
P3 by hand — tap M-x, type emacs-version, OK, expect "GNU Emacs" in
*Messages*.  **Adversarial review of the JA-3 diff: OPEN (the JA-1/JA-2
precedent — reviewed as its own audit pass).**


**Lands:** `jetpacs-emacs-ui.el`'s buffer list + drill-in (rebuild),
live-refresh watch (rebuild-lite), *Messages* tail (rebuild-lite, over
`jetpacs-buffer-render-tail`), imenu navigation extending
`jetpacs-results-show-region` rather than paralleling it, and the M-x runner.
`jetpacs-keymap.el`'s binding extraction and menu-bar mining (both port) plus
the command palette. `jetpacs-commands.el` (port). The `message`→toast bridge
lands as its own module, gated on `jetpacs-device-flow-p` and **off by default**.

**Why here:** it is the first consumer of JA-2's buffer host, and it is what
turns the tablet from "a viewer for whatever a skin pushed" into a general Emacs
client. Menu-bar mining is the highest-leverage idea in the whole assessment: it
produces human-written labels for an arbitrary mode's commands, making any
package touch-usable without writing a skin. It also unblocks two deferred
modules by making `M-x customize-set-variable` and `M-x load-theme` reachable.

**Size:** ~900 lines from 1,443 poc lines (~420 port).

**Exit gate:** ERT — imenu flatten over both `(NAME . POS)` and `(NAME POS FN)`
forms; menu-bar mining over a fixture keymap with `:filter`/`:enable`/`:visible`;
`jetpacs-command-visible-p` proves a suppressed command is *unreachable* from
the picker, not merely unsuggested. Smoke — list buffers, drill into one, run
M-x, invoke a palette entry from a mode with no registered skin.

**Note:** fix `jetpacs-dialog--static-candidates` first — it runs
`all-completions` + sort over the whole obarray on *every* bridged
`completing-read`.

### JA-4 — Org engine *(port)*

**Lands:** the extraction engine (cache, heading refs, the org-ql-subset
interpreter over a pluggable accessor, the vulpea note arm, mutations) and the
shared primitives (headless capture-run, LOGBOOK parser, planning-cookie
surgery, TBLFM resolver). New alongside: a root allowlist and remote-file-name
rejection on `resolve-ref`, a SPEC 23.2 allowlist on the `(read q)` sexp arm of
`parse-query`, and a lock guard on the idle `save-buffer`. The heading-ref
alist→plist migration lands **in the same commit as glasspane**, which nests the
ref under `(ref . …)` at five sites and reads it as an alist at four more.

**Why here:** it is the org API the entire app tier stands on, it is UI-free,
and it ports nearly verbatim. Nothing else in the rewrite can read or mutate org.

**Size:** ~730 port + ~120 new; plus a glasspane migration commit.

**Exit gate:** ERT — the query grammar against fixture org files (sexp,
`todo:`/`tags:` tokens, free text), the mtime+date cache key, `capture-run`'s
filled-copy binding and `:immediate-finish`. Smoke — run a query from the
device, toggle a TODO and confirm the log note flushed, capture into a template.

### JA-5 — Org on screen

**Lands:** the render skin (rebuild-lite): data: URIs replacing `file://`, LaTeX
compile moved onto `jetpacs-async`, SPEC 23.1 exposure records **and checks**
for the three skin-minted verbs plus the buffer-addressed ones, and the whole
render inside one `jetpacs-buffer-with-budget`. `jetpacs-org-toolbar.el` (port)
— which finally gets a host. The footnote dialog and the header action sheet
rebuilt as single 18.1 dialogs on the `jetpacs-sections--show-menu` template.
The outline model (rebuild-lite). The timestamp editor as a one-shot
`dialog.show` with `capture_fields` rather than a live view. `file.add-heading`
rebuilt onto `jetpacs-flow-continue`.

**Why here:** needs JA-4's engine and JA-2's flow entry; delivers the actual org
reading and editing experience on the tablet.

**Size:** ~900 lines.

**Exit gate:** ERT — golden spec for the skin over a fixture org file with
tables, rules, images and LaTeX; span-budget accounting under a synthetic
`max_rich_spans`. Smoke — tap a footnote, tap a heading → sheet → schedule with
a repeater, use the toolbar to insert a src block.

### JA-6 — Files

**Lands:** the sandbox guard (with `file-remote-p` rejected **before** any
stat), the /sdcard probe, the grep scanner behind a `text_input` `:on-submit`
(no dialog, no D2 exposure) running through `jetpacs-async`, the dired card skin
**with a row cap**, the five ops (`delete` uses descriptor `:confirm`,
`duplicate` needs no prompt, the other three go through flow-continued dialogs),
the plain `value`+`on_save` editor with its cap derived from `max_event_bytes`,
and the four app seams. Org affordances move out of core and into the app layer
through those seams. The launcher surface lands here too, once there are three
owners to switch between.

**Size:** ~600 lines.

**Exit gate:** ERT — the guard against symlink-inside-root,
path-prefix-not-component, and remote-filename cases; grep bounds (hit cap, file
cap, size cap, NUL binary guard). Smoke — browse `/sdcard`, edit init.el, save,
restart Emacs, confirm the edit took.

### JA-7 — git from the tablet

**Lands:** `jetpacs-transient.el` — layout reader (port) plus a **single**
dialog whose infixes are stateful nodes and whose suffix buttons are
`(jetpacs-dialog-submit :value SUFFIX :capture-fields …)`, concluding once;
`transient.toggle` disappears. The advice gate moves from
`jetpacs--in-action-handler` to `jetpacs-device-flow-p`. `jetpacs-witheditor.el`
rebuilt on a **local** editor (`:publish-state t`, no `:document` — a
synchronized editor is never capturable), the id minted through JA-2's minter,
and `with-editor-finish` run from JA-2's flow entry so a GPG prompt can bridge.

**Why here:** transient prefixes are keyboard-only by construction, and
with-editor currently **fails closed** — every tablet-initiated commit stalls
forever with no recoverable path. One module makes every transient package
touch-usable.

**Size:** ~350 lines.

**Exit gate:** ERT — the layout reader against both `transient--layout` shapes
(0.7.x 4-slot group vectors and newer 3-slot roots). Smoke — `magit-commit` end
to end from the tablet, including one prefix with an infix argument set.

### JA-8 — Project and hosts

**Lands:** the project dashboard on JA-2's buffer host — grep, compile, shell,
buffers, magit, each landing on a substrate the rewrite already finished.
`project.find-file` is **dropped** in favour of JC-5's live picker over
`project-files` (deletes ~50 lines and is a better phone affordance).
`project-files` moves onto `jetpacs-async`. Hosts: ssh-config discovery, the
label allowlist, connection-state-by-reading, the timeout clamp, all four
actions moved into continuations, plus a connect-in-flight guard (the dialog
pump runs the socket filter inside TRAMP's connection extent).

**Size:** ~500 lines.

**Exit gate:** Smoke — grep a repo from the tablet and step the results,
compile, open magit-status and fold a section, ssh to a box and get a working
shell.

### JA-9 — Triggers

**Lands:** the registry and `jetpacs-deftrigger` (port), `:ttl-s` added and
validated 1..604800, replace-set assembly emitting keyword plists, the
per-trigger `:type`-vs-`device.trigger_types` skip (ebp filters only `when`),
the `when`-gate filter deleted as superseded, a **non-destructive** connect push
(explicit `jetpacs-triggers-commit`, never an implicit empty set), 1401 retry on
the arming push, and `trigger.fired` built against §14.4 durable admission — a
durable work item, not a scheduled timer. Then the automations screen as a
**view inside the owning surface**.

**Why here:** it unlocks the largest already-paid-for Companion capability in
the system, and it is the one thing on this ladder that works while nobody is
looking at the screen.

**Size:** ~350 lines.

**Exit gate:** ERT — replace-set assembly and `ttl_s` validation; the omission
report from `ebp-client-triggers-set`; the durable work item survives a
simulated crash between commit and effect. Smoke — arm a `time` trigger, kill
Emacs, confirm it fires offline and replays on reconnect exactly once.

### JA-10 — Settings and packages

**Lands:** the settings engine (rebuild-lite — the `condition-case` must
re-signal `inhibited-interaction`, which is a child of `error`), the
schema→widget renderer (rebuild-lite), `settings.set`/`.reset` with a
flow-continued disk write, and the switch watcher (rebuild — the state.changed
extent has neither the no-prompts regime nor a device-flow marker, and welcome
`input_state` is never fanned out). Modus style options as one
`register-section`. The package browser's three skin hooks plus an async install
pipeline — the browse/search/describe half unconditionally, the four mutating
actions only under D-11.

**Size:** ~600 lines.

**Exit gate:** ERT — type classification across all five widget kinds,
`:json-false` decode, the standard-value reset, and a save-failure that is
*loud*. Smoke — flip a boolean, pick an enum, confirm both persist across a
restart; search MELPA and install one package.

### JA-11 — Instrumentation and leftovers *(optional)*

`jetpacs-devtools.el` rebuild-lite (a `:before` method plus per-build timing via
advice on `jetpacs-shell--build`), the tools hub as a multi-view view, and the
opaque-member linter — the ~200-line walk over `:args`/`:meta`/`:value` and the
§13.4 SurfaceSpec variants, which are the three members the shell gates are
deliberately blind to. Take `jetpacs-test-visible-text` / `jetpacs-test-view-ok`
/ a 3-line `jetpacs-render-to-json` into `test/` **at any time** — they have
consumers today and cost ~40 lines.

---

## 4. Base work this exposes

| # | capability | forced by | notes |
|---|---|---|---|
| B1 | **`jetpacs-granted-p`** (G1) | theme, device, package-browser, triggers | `ebp-client-granted` returns a *vector*; shell, dialog and sections each hand-roll `seq-contains-p` separately today. |
| B2 | **`jetpacs-teardown-owner`** (G5) | every owner; body from `jetpacs-app-unregister` | Must clear state per **surface** — the poc's id-prefix convention is dead under D1 and a literal port silently tears down nothing. |
| B3 | **Flow entry — `jetpacs-flow-begin` / `with-jetpacs-flow SURFACE`** (new gap; call it G14) | witheditor; transient's dialog-callback path | `jetpacs-flow-continue` only *inherits* a flow. A with-editor buffer appears from a process callback with no dispatch on the stack, so its prompts hit the real minibuffer and hang Emacs. `jetpacs-sections--show-menu` currently escapes this only because `execute-kbd-macro` does not prompt. **Triggers do not need this** — `trigger.fired` arrives as an `event.action`. |
| B4 | **Buffer-view host + thunk-shaped `call-shimmed` sibling** | tools, project, sql, hosts, emacs-ui, package-browser | `jetpacs-buffer-call-shimmed` does `call-interactively`, so a plain lambda signals `wrong-type-argument commandp`; the poc helper took a thunk. It must additionally shim `display-buffer` (`project-list-buffers` reaches it directly and escapes the current cl-letf list). |
| B5 | **Path/buffer-name → §4.4 identifier minter** | files (editor id), witheditor (state id), hosts (shell buffer name) | Promote `jetpacs-comint--input-id`'s sanitize+sha1. A raw name signals and takes the *whole* render down — already learned once on device. |
| B6 | **Chrome kit + per-surface screen stack** (G6, reduced) | files, project, hosts, tools, customize, modus, automations | Not a protocol gap — `multi_view`, `scaffold` slots and `view.switched` are all present and smoke-verified. What is missing is composition helpers and drill-in/back, ~50–80 lines. |
| B7 | **`jetpacs-toast` with the `presentation.toast` gate** (G7) | package-browser, device, emacs-ui | The current fallback calls `ebp-client-toast` inside `ignore-errors` with no grant check. |
| B8 | **1401-refused helper** (G10) | triggers (the *arming* push), device, package-browser | `ebp-client--request` returns nil under the sender ceiling. For triggers this is silent divergence on the durable path: Emacs believes the device is armed with the current registry when it is still running the last accepted set. |
| B9 | **§14.4 durable-admission convention + `jetpacs-retry-later`** (G12) | triggers | `accepted` deletes the Companion's durable record. Scheduling the effect on a `run-at-time 0` timer and answering `accepted` is explicitly non-conforming and loses work on any crash. This needs a design decision (durable work item / synchronous effect / `1500 event-retry`), not a rewiring. |
| B10 | **Welcome `input_state` fan-out + a regime for the state.changed extent** (new gap) | settings switches, and every future switch/slider/enum consumer | `ebp.el` merges welcome `input_state` into the store without calling `ebp-client-state-changed-functions`, and `jetpacs--on-state-changed` runs subscribers with neither `jetpacs-with-no-prompts` nor a device-flow marker — so a `yes-or-no-p` there goes to a real minibuffer from inside a process filter. |
| B11 | **Expose `max_event_bytes`** | files.save | Unread anywhere in `ebp.el`. `jetpacs-buffer-budgets` returns the *push* bound, not the save bound. On a minimum-conforming Companion (`max_event_bytes` ≥ 262144) a 256 KB file cannot round-trip at all, and the Companion drops it with only a local diagnostic — Emacs never learns. |
| B12 | ~~**Outbound frame guard + an ebp defect fix**~~ **— defect FIXED 2026-07-26** | any raw `:args`/`:meta` payload | The W10 ceiling incremented `outstanding` immediately before `jsonrpc-connection-send` with no `condition-case`, so a non-serializable scalar signalled out of `jetpacs-shell-push` **and permanently burned an outstanding slot**, walking the session toward `ebp-overload-exhaust`. Fixed with a rollback-and-re-raise + regression test. The `max_frame_bytes` pre-check on `ebp-client-surface-update` remains open. |
| B13 | **A builtin-advertisement predicate** | kill-ring (`clipboard.copy`) | The app layer has node and feature predicates only; GATE 1b *signals* on an unadvertised builtin, taking down the whole push. |
| B14 | ~~**Fix the stale `jetpacs-dialog-node-types` constant**~~ **— FIXED 2026-07-26** | witheditor, transient, any dialog author | The Companion advertises `editor` for dialogs (JC-4b added it to `NodeSupport.DIALOG_NODE_TYPES`); the elisp reference set and its pin test still asserted the opposite, so `jetpacs-check-profile TREE 'dialog` wrongly rejected conforming dialogs. The picker worked on device only because the runtime gate reads the live welcome. Constant + pin test corrected (26→27). |
| B15 | **Short-circuit `jetpacs-dialog--static-candidates`** | M-x, the command palette | It runs `all-completions ""` + sort over the entire collection *before* choosing between the enum fast path and the picker. An obarray M-x pays a full-image sweep on every invocation. |
| B16 | **G4 — editor↔buffer binding** | files (synchronized path), org rebase-todo | Explicitly **not** on this ladder. No `jetpacs-editor-bind`, no delta sender, no #71 seed reconciler, no §19.5 annotation function. Bigger than `jetpacs-files.el` itself. |
| B17 | **G3 — tile SurfaceSpec builder + `:tile` error-spec branch** | nothing on this ladder | Recorded so it is not rediscovered: a builder crash on a tile surface currently emits a bare Node and is content-invalid. |
| B18 | **Kotlin (not elisp)** | device's 16 wrappers; launcher polish | `AppCapabilities.kt` implements 2 of 18 catalog entries and reports empty `permissions`; `settings.open` is absent entirely, so `device.settings_panels` is unadvertised; MainActivity is a single-slot last-accepted-wins display with no `BackHandler`. Recommended order if any Kotlin is done: `intent.start` > `app.launch`/`apps.list` > `settings.open` > `state.get`. |

---

## 5. Decisions for Caleb

**D-1 — Is tablet editing *real* editing?** *Recommendation: ship the plain
`value`+`on_save` editor at JA-6 and defer G4 until JA-7 tells you whether
git-from-tablet is real.* Plain works now but caps in the **tens of KB** (see
B11) and loses completion, undo/redo, fill, comment-dwim and the bridged M-x. G4
is a base build larger than `jetpacs-files.el` itself. If JA-7 lands and you
find yourself editing rebase todos and long org subtrees on the tablet, G4
becomes the next base rung; if you find yourself only reading and tapping, it
never does.

**D-2 — Does Jetpacs ship to humans other than Caleb?** *Recommendation: no.*
That retires `jetpacs-demo.el` (1,160), `jetpacs-app-store.el` (286),
`jetpacs-pack.el` (71) and the device permissions screen, and it means the
walkthrough is never re-authored. Saying yes costs you not a port but a
re-authoring: ~500 sentences of walkthrough asserting behaviour of screens that
no longer exist, plus a deployment layer (`jetpacs-config.el`'s
staging/adopt/byte-compile half) that JC-3b deleted. A wrong tour is worse than
no tour.

**D-3 — Does the no-code composer survive?** *Recommendation: no — NO-GO on
JC-6.* The composer repo is a README and a TODO; the real app wrote eleven
`:builder` views and zero `:spec` views *having built the source layer to feed
them*; and contract format 6 deleted the entire `binding` vocabulary, so
re-establishing it is a governance act. Killing it retires `jetpacs-source.el`
(170), `jetpacs-spec.el` (253) and ~880 of `jetpacs-lint.el`. Keep two carve-outs
regardless: the ~40-line test helpers, and the ~200-line opaque-member linter,
which is the only validator that can see `:args`/`:meta`/`:value` — and that
subject **already shipped** (`smoke-notif.el` hand-authors an 18.5 meta today,
and G3 guarantees hand-written tile specs).

**D-4 — May a heading ref carry an absolute local path over the wire?**
*Recommendation: no — mint an opaque per-owner token, the `results.visit
:index` contract.* Paths cost you a permanent SPEC 23.1 surface you must
re-validate at every entry point forever, and `jetpacs-results` deliberately
avoids exactly this. The token costs a per-owner ref table plus migrating
glasspane's nine heading-ref sites — which you are touching anyway for the
alist→plist change, so do both in one commit.

**D-5 — Do you want to *manage* `org-capture-templates` from the tablet?**
*Recommendation: no.* 646 lines of screen for a config edited a few times a
year, from a tablet that can already edit init.el through a file editor.
Capturing *into* templates is separate and lands at JA-4. Keep exactly one
function from that region: the capture-form schema extractor, which is
byte-identical to a second copy 1,750 lines away and should be deduped on the
way past.

**D-6 — Does a phone-editable file define code Emacs evaluates?**
*Recommendation: keep `eval`, but refuse reload on a device-originated save;
treat a desktop-originated save as init.el-equivalent trust and document it.*
Note that dropping `#+begin_src elisp` handlers **does not** close the hole —
`:ON_FIRE:` and `:PARAMS:` are `read` from the same phone-writable file and
drive `intent.start`/`app.launch`/`tts.speak`/`clipboard.read` bounded only by
`device.trigger_caps`. The poc asserts local-only in a comment and then wires
the phone's own save hook to the eval; that combination is the one option you
should not ship.

**D-7 — Is Emacs the sole source of truth for the device's trigger set?**
*Recommendation: never push until an explicit `jetpacs-triggers-commit` at the
end of init; keep the identical re-push on every connect.* SPEC 21.1 guarantees
an unchanged id carries forward its throttle floor, one-shot marker, schedule
anchor and boot receipt, so re-pushing is genuinely free. The hazard is narrower
than it looks and worse: an **empty or partial** registry at connect — fresh
Emacs, `-Q`, a load-order slip — atomically clears device-lifetime registrations
that outlive Emacs. The cost of the recommendation is that you can no longer
clear triggers by deleting code; you clear them with an explicit empty commit.

**D-8 — One org renderer or two?** *Recommendation: one — the faithful
line-render skin.* `jetpacs-org-rich.el` is a second, lossier document model:
format 6 has no encoding for strike-through, sub/superscript or hashtag spans,
all seven of the actions it emits were never registered anywhere in the poc, and
it has no cap or budget of any kind. Keeping both means maintaining two span
emitters and two tap-routing schemes forever. Revisit only if you decide you
want a *re-flowed reader* distinct from the faithful buffer view — that is a
product need, not a rendering detail.

**D-9 — Does the radial pie menu survive?** *Recommendation: retire it.* The
module's own commentary concedes the palette wins for keymaps; transients are
better served by JA-7's dialog; the Tier-1 curated-pie registry has zero
registrants across all 46 modules; and its nesting feature provably never worked
(a by-value `push` onto a parameter). Retiring deletes the whole SPEC 18.3
reshape, the grouping machinery, the `presentation.pie-menu` grant plumbing —
and the SPEC 23.2 `execute-kbd-macro (kbd KEY)` exposure, since
`jetpacs.keymap.run` exists only to serve pie items.

**D-10 — Is git-from-tablet real, and do you sign commits?**
*Recommendation: build JA-7's message-only path; if you sign, accept the
flow-entry plus `read-passwd` bridge as in scope, otherwise disable signing for
tablet-initiated commits.* pinentry runs during `with-editor-finish` and will
raise a passphrase prompt nobody can see. Message-only is ~150 lines once B3
exists; rebase-todo editing implies G4 and is a much larger bet.

**D-11 — Three small scope calls, batched.** *SQL: retire* — there is no
`sql-connection-alist` in your config, so the landing view is an empty state,
and both handlers block on `read-passwd` inside the dispatch extent.
*org-habit: build only if you actually keep habits* — the 200-line
consistency-graph view is worth exactly zero otherwise. *Package browser: build
the browse/search/describe half; drop the four mutating actions unless the
tablet installs its own packages from MELPA* rather than running a `.emacs.d`
synced from the desktop.

**D-12 — Does the tablet need real app switching?** *Recommendation: no, not
yet.* Last-push-wins plus an in-app back affordance is fine for one developer,
and the Emacs-side launcher works today with zero Kotlin (`jetpacs-shell-push`
is owner-unchecked and `--build` rebinds the owner from the root's
registration). What Kotlin would buy is simultaneous display, scroll/state
preservation across switches, and OS-back — none of which the launcher needs to
function. Schedule it when you have three owners you switch between *mid-task*,
not before.

---

## 6. What I would not build

Recorded so these are decisions rather than omissions.

**Retired outright (~1,600 lines).**

`jetpacs-demo.el` (1,160) — 82% embedded prose describing Project, Databases,
the Apps launcher, Automations, Customize, Modus Themes, Packages, Remote hosts,
the drawer and the tab bar, none of which exists. `org-basics.org` is a generic
org tutorial that should not be a defconst in a foundation module. And the one
carve-out the assessment argued for — a rebuilt hello app as `smoke-hello.el` —
is redundant: `smoke-floor.el` already registers inside `with-jetpacs-owner`,
returns `'accepted`, and asserts the push landed on `app:smoke`;
`smoke-counter.el` covers tap→mutate→re-push; `smoke-dialog-prompts.el` and
`smoke-picker.el` cover `jetpacs-flow-continue` on hardware.

`jetpacs-pack.el` (71) and `jetpacs-theme-picker.el` (139) — generality with no
consumer. Pack serves a composer that does not exist and would require widening
`jetpacs-defaction` to record per-action metadata. Theme-picker has one caller
and hardcodes modus palette keys, so the "generic scaffold" it claims to be was
never generic.

`jetpacs-apps.el`'s isolation machinery (~114) — the four seam vars, the
view/chrome/settings filters, the per-app FAB seam and the vanilla-app
auto-registration all exist to slice one global surface among apps. D1 deleted
the premise; per-owner surfaces make cross-app leakage structurally impossible.

`jetpacs-settings.el`'s owner filter and hub splitters (~130) plus the
custom-file-in-sync-tree warning (~32) — same reason for the first; the second
depends on `jetpacs-root` from the retired `jetpacs-sync.el`.

`jetpacs-lint.el`'s contract tables, `jetpacs-lint-payload` and
`jetpacs-lint-sanitize-spec` (~280) — ebp.el owns every SPEC 24.2 endpoint duty
over rented jsonrpc.el, the handshake params are already pinned against
`contract.json` by ERT, `lint-payload` had zero callers outside its own tests,
and sanitize-on-push directly contradicts a ratified design (the shell's gates
*signal*; they never sanitize).

`jetpacs-keymap.el`'s pie menu and Tier-1 registry (~217) — see D-9.

`jetpacs-device.el`'s reminders negotiation (~53) — SPEC 18.6 makes `owner` a
REQUIRED member *and* gates `reminders.set` on the `reminders.owner` capability,
so the "no capability → send a global set" fallback has no method to call. The
three-way cond and its warn-once table guard against an impossibility. Keep the
wrapper; delete the negotiation.

`jetpacs-files.el`'s `config.reload` tombstone, the never-wired swipe seam, and
the org affordances the module's own header says it does not contain — retire
the Outline button **and** its orphaned `files.open-outline` handler together,
both moving to the app layer through the seams the module already publishes.

**Deferred, nothing scheduled (~3,300 lines).**

The org capture-template builder (646) and heading-detail overlay (65) — D-5,
and the overlay needs a route/overlay model the ladder does not build.

`jetpacs-org-rich.el` (563) — D-8. Recommend retire; deferred only because a
re-flowed reader is a legitimate thing to want and this is the only
implementation of one.

`jetpacs-customize.el` (359) — JA-3's M-x makes `customize-set-variable`
reachable and JA-10's engine gives typed controls; what remains uniquely useful
is the "Modified" filter and prefix search, which is a search-first screen at
half the size. Note honestly that until JA-3 lands there is **no** path to set a
non-registry defcustom from the tablet at all — there is no device-side
`execute-extended-command` in the rewrite today.

`jetpacs-app-store.el` (286) — D-2.

`jetpacs-spec.el` (253) and `jetpacs-source.el` (170) — D-3.

`jetpacs-automations-org.el` (205) — blocked on JA-9, and it has two set-wide
defects that must be fixed before any port: the wire trigger id is `(format
"org/%s" headline)`, so the header's own example `* Charge sync` produces an
invalid §4.4 identifier, and there is no `:TTL:` drawer key though the same
example sets `:POLICY: wake`. §21.1 requires validating the complete set before
changing registrations, so one bad heading silently kills *every* automation.

`jetpacs-sql.el` (199) — D-11. Flip to retire if a generic command palette
lands, which JA-3 delivers.

`jetpacs-automations.el` (142) — dead code until a first trigger exists; build
it at JA-9 as a view inside the owning surface, never as a second `app:*`
surface (that hijacks the display on this Companion with no way back).

`jetpacs-device.el`'s 16 unimplemented wrappers (~200) plus the permissions
screen — the cost is Kotlin, not elisp. `AppCapabilities.kt` advertises
`vibrate` and `clipboard.read` and reports `permissions: {}`; `settings.open` is
absent, so `device.settings_panels` is unadvertised and every grant link in that
screen has no transport, not merely a wrong panel name.

`jetpacs-lint.el`'s trigger linter (~110) — belongs with JA-9 if anywhere. Its
residual value over `ebp-client-triggers-set` is the `${…}` placeholder grammar
and the `on_fire` exactly-one-of check.

`jetpacs-files.el`'s synchronized-editor path and `jetpacs-tools.el`'s
hub/drawer — D-1 and B6 respectively.

**One thing to stop doing, not to build.** `jetpacs-emacs-ui.el` marks
`*`/`**`/`***` globally special with `(defvar * nil "doc")`; Emacs 30.1's own
ielm deliberately uses the scope-local `(defvar *)` form. And its
`message`→toast advice is installed unconditionally at load, gated only on
`jetpacs-connected-p` rather than `jetpacs-device-flow-p`, with a self-echo
filter that is now stale — so the bridge's own warnings toast themselves to the
device. Both are direct violations of "desktop Emacs must remain untouched
unless in a device flow"; fix them on the way through JA-3 rather than carrying
them.

---

## 7. Decision outcomes — RATIFIED (Caleb, 2026-07-26)

**The organizing principle Caleb articulated across D-1/D-8/D-9/D-10/D-11,
now standing policy for this plan:** base Jetpacs is a MOBILE EMACS, not an
approximation — any built-in Emacs feature is in base scope (support may be
deferred for thoughtfulness, never retired) — while OPINIONATED experiences
live as Tier-1 apps ("installing Jetpacs is installing vanilla Emacs; a
Tier-1 app is a config on top").

- **D-1 — REAL editing: YES**, scoped as *authoring and drafting* (indentation
  maintenance, auto-bullets on RET, WYSIWYG-leaning), with deep editing left
  to desktop.  The property-drawer abstraction model is the exemplar.  NEW
  DIRECTION beyond the poc: a **block-based editor** — metadata/properties/
  elements stay plain-text org underneath, abstracted by the renderer.  Per
  D-8's extension, this lands as a **Tier-1 app**, not base (it aligns with
  the existing jetpacs-orgseq architecture: blocks = ID'd headlines).  Ladder
  impact: JA-6 still ships the plain editor; G4 stays deferred but its
  successor shape may be per-block editors rather than one whole-buffer sync.
- **D-2 — the llm-poc does not ship to others; the hand-rewrite WILL.**
  demo/app-store/pack stay unported here but are PRESERVED on slop-fork/
  poc-v1 for the rewrite to draw on.  Nothing deleted from history.
- **D-3 — composer: wanted, revisit much later.**  JC-6 stays NO-GO for this
  poc; source/spec/lint-remainder reclassified retire→**defer-long**.
  Audience ordering ratified: (1) Caleb, (2) Emacs users wanting quick
  capture + org-agenda on the phone, (3/4) other-PKM converts before
  mobile-IDE power users.  NOTE: this ordering argues for the org rungs
  (JA-4/JA-5 + capture) ahead of JA-3's general-client work — proposed
  reorder, **DECLINED (Caleb, 2026-07-27): JA-3 first, ladder order
  stands.**  The org rungs follow it.
- **D-4 — RATIFIED as recommended:** opaque per-owner heading-ref tokens;
  never absolute paths on the wire; one commit with glasspane's alist→plist.
- **D-5 — REVERSED: capture-template management from the tablet is IN.**
  Caleb rates it a core use-case for PKM converts.  The 646-line builder
  reschedules after JA-4 (capture-run substrate) + JA-10 (settings engine).
- **D-6 — RATIFIED as recommended:** keep eval; refuse reload on
  device-originated saves; desktop saves are init.el-equivalent trust.
- **D-7 — RATIFIED as recommended:** explicit `jetpacs-triggers-commit`;
  never implicit pushes; clearing happens via an explicit empty commit.
- **D-8 — one FAITHFUL renderer at base; re-flowed/block experiences are
  Tier-1.**  org-rich stays deferred as Tier-1 raw material.
- **D-9 — PARTIALLY REVERSED: the pie menu's PLUMBING is retained.**
  Caleb judges radial menus the best phone interaction model but neither of
  us the right builder — the wire/Companion SPEC 18.3 machinery (already
  built in W7) and the `presentation.pie-menu` grant stay; the poc's
  Emacs-side keymap-pie registry stays unported; implementation belongs to a
  future Tier-1.
- **D-10 — git is NOT base.**  Emacs ships no git binary and base Jetpacs
  will not open the door to bundling arbitrary binaries; a git workflow is a
  Tier-1 (own APK signing + Termux) story.  Ladder impact: JA-7 RESCOPES —
  the transient→dialog layer STAYS base (transient is built-in Emacs), while
  magit/with-editor/git specifics move to the Tier-1 exemplar; base keeps
  only a fail-open guard so a with-editor buffer can never hang Emacs.
- **D-11 — REVERSED on both:** SQL stays (built-in; exploring the app's own
  SQLite — including ebp's receipts store — is a real use); org-habit is
  absolutely in scope with the org rungs.  Package-browser's mutating
  actions are likewise legitimate base scope (package.el is built-in);
  deferral is about sequencing, not scope.
- **D-12 — app switching stays as-is** (Emacs-side launcher, no Kotlin).
  The frame is corrected: "apps" are CONFIGS; the launcher exists to show
  package authors that a Tier-1 skin is cheap, not to serve daily
  multi-app use.

---

## 8. Audit ratifications (Caleb, 2026-07-26) — R1, R2, R3

The `docs/AUDIT-ja1-ja2-2026-07-26.md` fix order was gated on three calls.

**R1 — naming/reservation: `jetpacs.*` APPROVED.**  Base reserves the
`jetpacs.` prefix; `clip`/`theme` become `jetpacs.clip`/`jetpacs.theme` and
their actions `jetpacs-clip.refresh`/`jetpacs-theme.modus-toggle`.  Amendment
#134 carries the wire-level policy.  `jetpacs--claim` must additionally warn on
a same-owner claim from a DIFFERENT defining file (today it is silent, so two
packages picking one owner overwrite each other by load order).

**R2 — clip and theme BOTH STAY IN BASE.**  Caleb's reasoning, which REFINES
the §7 framing and is now the governing statement of it:

> Base Jetpacs is vanilla Emacs **optimized for mobile use**.  The kill ring is
> built-in; a mobile-shaped way to reach it is base.  Modus is built-in, is what
> a fresh Emacs install now themes with, and 5.0 exposes a PUBLIC theme-building
> API — so the theme surface inherits all of that work and will only grow.
> Aesthetics are a first-class concern (the ricing audience is real).

Consequences: no MOVE, no SPLIT.  The audit's clip privacy defects and theme
defects are mandatory ANYWAY and are unaffected.  The seams the audit wanted for
a split (`jetpacs-theme-mode` `off`, `jetpacs-theme-payload-function`, a
hook-free home for `jetpacs-modus-*`) still land — reframed from *enabling a
split* to **enabling a Tier-1 to build on modus 5.0's public API without
fighting base for the palette**, which is the stronger reason.

**R3 — amendment #126: OPTION B (delete the Kotlin reads).**  Decided on the
merits rather than deferred:
- `meta` is not a concept, it is a synonym collision.  The poc mapped it to
  `preprocessor` (a registered role); the Companion reads it for ORG TAGS
  (`tag`, also registered).  One unregistered name serving two purposes both
  already covered is drift, not vocabulary — registering it would bless the
  confusion permanently and still leave `SyntaxHighlight.kt:385` non-conforming
  until it read `tag`.
- `paren` should NOT map to `operator` (the audit's suggestion): parens are
  delimiters, not operators.  Delete the read and keep the Companion's STATIC
  rainbow — which is what JA-1's theme module already argued for when it
  deliberately omitted the role ("one color destroys the depth cue"), and which
  is the better aesthetic outcome under R2's ricing concern.
- Option B is a pure Kotlin change: no protocol growth, no contract edit, no
  golden regeneration, and it makes two already-registered-but-dead roles
  (`tag`, `preprocessor`) live.  `jetpacs-theme.el`'s `:meta` duplicate dies
  either way — it is deleted in the same commit as the Kotlin change.
- **Amendment #127 lands regardless and is the real cure**: `validate.py`
  ignores `theme_roles` and `syntax_roles` entirely, which is the mechanical
  reason this drift survived three rungs.  Pin the vocabulary in the validator
  and the golden corpus, and this class cannot recur.
