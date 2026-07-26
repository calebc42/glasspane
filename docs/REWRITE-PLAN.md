# REWRITE-PLAN — rung ladder, gates, port manifest

Source of truth for order and doneness. Derived from SPEC §24,
`ebp/BUILDING-COMPANION.md`, and the poc-v1 divergence map
(`../llm-poc/docs/AUDIT-ebp2-divergence-map.md`). One rung per PR-sized
unit; a rung lands only with its exit gate green.

## Ladder

| Rung | Deliverable | Exit gate |
|---|---|---|
| **W0 contract wiring** | Vocabulary generation from `ebp/contract.json` (elisp tables + Kotlin codegen when the companion lands); drift round-trip | Generated vocabulary == contract, byte-stable |
| **W1 elisp wire core** *(started)* | `emacs/ebp.el`: §6 framing codec, §7 envelope, §4.1 duplicate rejection, §9 HMAC + proofs + token/nonce grammar, handshake message builders/verifiers, §10 client state skeleton | ERT green on: §9.3 KAT; every `ebp/goldens/wire/` fixture decoded at 1/7/whole-octet chunkings with manifest-expected outcomes; encoder byte-syntax incl. non-ASCII length |
| **W2 companion wire core** | Kotlin twin of W1 (FrameCodec largely ports; auth/envelope rebuilt) | Same fixture suite from Kotlin; hand-played handshake Emacs↔device completes |
| **W3 session lifecycle** | CONNECTED→CHALLENGED→SYNCING→READY both sides; welcome (profiles, floors, tombstones, limits, `input_state`); §10.3 barrier; `session.ready`; reconnection | Pre-auth fail-closed vectors (§24.6 items 4–5); barrier ordering test; welcome reservation inequality checked |
| **W4 surfaces** | `surface.update`/`remove` as requests; revisions + tombstones; snapshot store; `reset_input_ids`; §13.6 draft reconciliation; Core Node Set rendering (companion) / push path (client) | Applied/stale idempotency tests; update/remove/update race (§24.6 item 7); unknown-node/key degrade (§16.2–16.3); elisp text on phone |
| **W5 actions + events** | ActionDescriptors incl. `capture_fields`; `event.action` request protocol with EventId, 4-status results, Emacs receipt store; `state.changed` with barrier rules (§14.6) | Counter round trip; duplicate-after-restart (§24.6 item 9); state-before-action flush test |
| **W6 durability** | Companion durable queue (`queue_seq`, expiry high-water mark, dedupe transaction); `queue.replay` pump; safe admission | Kill matrix (§24.6 item 8); replay interruption/capacity (item 10); offline draft + sync + replay (item 11) |
| **W7 modules, by need** | dialogs (request + builtins), toasts, pie menus, themes, reminders, editor sync (new method layer over ported splice math), capabilities, triggers (§21.1 state carry-over, §21.2 transaction) | Each module's REQUIRED rules + its §24.6 module cases; password exclusion (item 12) |
| **W8 durable-offline conformance** | Hoist reminders/triggers to durable file backing shared across connections; device-lifetime `TriggerFiringService`; §21.2 durable transaction + pending-local recovery; boot re-arm; reminder tap routing; engine P2 sweep (validateAction delegation, identifier caps, notification state gate). Closes the W7 audit's P1 cluster — see docs/W8-durable-offline-plan.md | JVM: fire-with-no-engine admits durably; throttle/receipts survive restart; device matrix: at-most-once across force-stop, offline fire → replay on connect, reboot re-arm |
| **W9 organ ports** *(done 2026-07-23)* | Port-safe modules from poc-v1 (see manifest) with format-6 vocabulary updates, driven as atoms a–m (wire completeness → renderer skeleton → content/input/layout/viz families → builtins/multi-view → scaffold → theme+syntax → editor toolbar §17.7 → image guard stack → notification meta/actions → parity gate). All 39 node types render; the app profile advertises exactly what the flat `when(type)` dispatch renders (NodeSupportPinTest). See docs/W9-feature-parity.md | **MET**: every node vector in `ebp/goldens/widgets.golden` renders through a live session (`test/smoke-parity.el`: 61/61 applied); the pin test keeps advertisement == dispatch; 233 wire + 18 app + 26 elisp green + per-family device smokes |
| **W10 overload + polish** *(done 2026-07-26)* | §22 traffic classes, bounded processing, `log.error` protocol. Companion half was discharged in Tier-2 (LD-13 hysteresis + #106 pump exemption); W10 proper is the EMACS half — sender ceiling (512/128 twin, local synthetic 1401, `queue.replay` exempt), inbound bound under the A8 §1.5 invariant (pause never inside a send; every send resumes reading first; backlog measured in the timer-hosted parsed queue), exhaustion = one `log.error` 1401 + close (backlog or #124 dispatch-depth trigger), plus the A8 H2 pre-send-claim fix on `edit.apply`. Amendments #124-125. See docs/W10-overload-plan.md | **MET**: §24.6 item 14 per class in the wire suite over the live loopback — intent flood (400 `state.changed`, complete/ordered/exactly-once), ordered-stream flood (200 deltas, no invented resync), sender ceiling refuse/recover/exempt/close-fails-locally, pause/resume + in-send guard against a real stopped process, both exhaustion triggers observed as `log.error 1401` at the peer then close. 45 wire-elisp / 250 elisp total green |

Interleave W2 with W4/W5 client work as device access allows; the ladder
orders gates, not calendar.

## Port manifest (from the divergence map)

**Kotlin port-safe:** all `Sdui*.kt` renderers, `ThemeBridge`,
`SyntaxHighlight`, `IconMap`, `RadialMenu`, `ReorderableList`,
`NotificationRenderer`, widget/tile chrome, `EmacsWaker`,
`DeviceCapabilities` (unwrap results), app module. **Keep-logic:**
`EditorSync` splice/UTF-16 math + `applyExternal` gates, `InboundPipeline`
concept, `TriggerHost` gate/interpolation logic, `StateSampler`,
`CalendarTriggers`.

**elisp port-safe:** every ABOVE-BOUNDARY module (org layer, files, shell,
demo, settings, apps, satellites) and WIRE-ADJACENT builders (widgets,
hypertext, buffer, keymap, sections, results, tablist, spec, source,
async, comint); `jetpacs-lint` re-pointed at format 6; `build-contract` /
`build-bundle` pattern retained.

**Must-rebuild (never port):** poc-v1 `jetpacs.el` transport/auth,
`jetpacs-sync.el` message layer, `jetpacs-minibuffer.el` dialog layer,
`jetpacs-complete.el` direction, Kotlin `JetpacsAuth`,
`JetpacsConnection`, `ActionReceiver`/queue schema, `JetpacsDialogState`,
`EditorSync` message layer.

## Spec-feedback loop

Implementation friction lands in the W-register (divergence map §5) or as
new findings; each resolves as an `ebp/` amendment before the dependent
code lands. Open at start: W3 (toolbar `line_ops` — needed before W8 ports
orgseq toolbars), W1 (`theme.set.base` — before W8 ports the theme
picker), W6 (`tile:*` namespace — before W8 ports tile slots).

Resolved: ebp amendment #33 (2026-07-22) pinned local-editing efficiency —
delta coalescing before `seq` assignment and source-throttled carets are
explicitly conformant; the W7 editor module builds on that reading.

## The ebp.el boundary (the jsonrpc.el model)

**Decided 2026-07-22:** `emacs/ebp.el` is *the Emacs implementation of the
EBP spec* — the analogue of jsonrpc.el to JSON-RPC — and Jetpacs is an
application built on it. Same split the Kotlin side already has with
`companion/wire`. The line is SPEC §24.2: ebp.el owns every duty the spec
assigns to "a conforming EBP 2 Emacs endpoint"; Jetpacs owns everything
above the semantic-action boundary.

| ebp.el (the endpoint) | jetpacs (the application) |
|---|---|
| Framing, envelope, auth, session lifecycle, reconnection | Widget/surface DSL and builders |
| Surface push plumbing: revisions, tombstone absorption, applied/stale results | What the surfaces contain; org layer, apps, shell |
| `event.action` server: allowlist registry, EventId receipt store, 4-status results | The registered handlers' behavior |
| `state.changed` reconciliation, `input_state` merge, draft rules | What to do with the values |
| Module method plumbing (dialogs, editor sync, triggers, capabilities) | Dialog content, editor commands, trigger policy |

The registry *mechanism* is ebp.el; the registered *content* is Jetpacs.

Enforcement, in-tree (physical extraction is a U-phase `git mv`, not now):
`ebp-` namespace only; **zero `jetpacs-` dependencies, ever**; its own
conformance suite pinned to the `ebp/` corpus; and the delineation guard —
`test/run-tests.sh` batch-loads `ebp.el` alone and fails if any
`jetpacs-`-prefixed symbol exists afterward.

## Code conventions

- **elisp floor: Emacs 30.1** (Jetpacs requires Emacs on the device, and
  the on-device build is 30.1). Every library declares
  `Package-Requires: ((emacs "30.1"))`; modern stdlib is assumed —
  no compat shims.
- **`setopt` for user options** (Emacs 29+): any code, example, or doc
  that sets a `defcustom` uses `setopt` so custom setters run. `setq`
  remains correct for internal variables and lexical state — do not
  blanket-replace it.
- `lexical-binding: t` everywhere. **The Emacs endpoint rents core
  `jsonrpc.el` unmodified** for transport, framing, and id bookkeeping
  (decision log #2, ebp amendment #34); the strict reference decoder in
  ebp.el serves conformance suites and future non-jsonrpc transports, not
  the live path. Beyond core libraries, wire modules stay dependency-free.
- **The rental rule** (from the jsonrpc.el correction, applied broadly):
  rent a core built-in wherever its contract matches a spec duty;
  hand-roll only where the spec demands behavior the library lacks; no
  non-core dependencies in the protocol library. Rented so far: native
  JSON, jsonrpc.el, secure-hash, base64, timer.el, **sqlite.el** (the
  receipt store; file fallback when `sqlite-available-p` is nil — VERIFY
  on the on-device Android Emacs), **custom.el** (defgroup `ebp`; user
  options overridable from init.el with `setopt`, per-connection config
  still wins). Earmarked: `auth-source` for pairing tokens (SPEC 9.1) at
  the pairing rung; `tabulated-list`/`hierarchy` for devtools buffers;
  capf (not completion.el) when the editor module serves `edit.complete`.

## Standing product decisions

**orgseq editing tier (decided 2026-07-22):** orgseq block editing uses the
**local-editor tier** — `editor` without `document`, `publish_state: true`,
drafts + `on_save`/`capture_fields` — so editing works offline and rides
§13.6 draft reconciliation and the welcome `input_state`. Synchronized
editors (`document`, SPEC §19) are reserved for live buffer-mirroring
surfaces and are read-only off-`READY` by spec; orgseq MUST NOT depend on
them for block text entry.
