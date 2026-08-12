# Completion excellence ladder (Glasspane rebuild track)

Status: R0 LANDED. Ratified 2026-08-12 alongside the Glasspane rebuild
decision: v1-quality completion/eldoc/eglot support is the focus, and
the architectural rulings are settled — EBP and LSP are different
layers that already coexist (eglot terminates LSP inside Emacs and fans
results into the built-in middleware the ebp-sync riders and
ebp-complete harvest); the Companion is never an LSP client; the SPEC
never requires LSP; the Glasspane app layer treats an eglot-managed
real buffer as the *expected* completion source for programming modes,
degrading silently when no server exists.

No SPEC loosening anywhere below except R4's narrow selection-gate
prose relaxation, which grants receiver behavior, not interpretation.

## R0 — attach-aware completion routing (LANDED)

The headline v3 gap: `edit.complete` was answered client-wide by the
SHADOW harvester, so an eglot-managed buffer's capf never ran even
though jetpacs-files attaches that exact buffer for the riders.

- ebp.el: `edit-complete-overrides` on the client struct — per-document
  completion sources consulted before the client-wide
  `:edit-complete-function`. The single-mutable-slot defect (a dialog
  picker borrowing the slot answered every other document empty) dies
  at the layer that owned it.
- ebp-sync.el: `ebp-sync-attached-buffer` (DOCUMENT EDITOR-ID) — the
  clientless routing lookup, sound under the JC-0 single-client floor.
- ebp-complete.el: the live-buffer arm. When the attached buffer's
  (widened) text equals the mirror TEXT, harvest THERE — eglot and
  every buffer-local capf answer; on divergence (mid-flush), timeout
  (`ebp-complete-live-timeout`, a thinking LSP server), or no attach,
  the shadow answers exactly as before. A live harvest that finds
  nothing IS the answer (the shadow runs a subset of the same sources).
- jetpacs-dialog.el: the picker registers its own document in the
  override table instead of borrowing the client-wide slot.

Hazards bounded, not eliminated (recorded in `ebp-complete--live-harvest`):
`with-timeout` cannot interrupt a capf spinning in C without yielding
(the #137 shape), and the ebp process filter may dispatch an inbound
`edit.delta` under a waiting harvest — costing at worst a garbage offer
the Companion's SPEC 19.3 selection gate discards.

Adversarial review (13 raw findings, 4 confirmed, all fixed same day):

- An empty live harvest FALLS THROUGH to the shadow — nil-as-final
  silenced `ebp-complete-shadow-setup-hook` sources (the module's own
  extension point, which attached buffers never run) for every
  attached document.
- `ebp-complete--live-harvest-active` latch: `with-timeout` mints its
  catch tag at MACROEXPANSION time, so two stacked live harvests share
  one tag and the inner catch steals the outer timer's throw. The
  latch routes a nested `edit.complete` to the shadow, so harvests
  never stack.
- The same flag defers `jetpacs-flow-continue` continuations
  (reschedule at 0.05s) while a harvest is on the stack: a
  continuation may WAIT (a bridged prompt, hub.eval), and the timeout
  throw unwinding through one would abandon the prompt mid-round-trip
  with no rpc.cancel.
- The picker's quit path (dismiss → keyboard-quit) is pinned: the
  override-table remhash is an unwind-protect obligation, and the
  moved-remhash mutant previously survived the whole suite.

Companion-side hardening noted for a later Kotlin pass (NOT blocking):
`requestCompletion`'s reply callback checks only sessionId, not seq
(CompanionEngine.kt:1891), so a slow reply for an old seq can clobber a
fresher offer in DeviceBridge's latest-write-wins map; taps on it are
refused by selectCompletion's seq gate, so it self-heals on the next
keystroke.

## R1 — eglot lifecycle port (the v1 crown jewels) (LANDED)

Ported from poc-v1 `core/jetpacs-sync.el` into ebp-sync.el's new
"language tooling arm" section, with four deliberate deltas from the
reference:

- v1's two-arm buffer strategy (real buffers for eglot modes, shadows
  otherwise) is NOT ported — v3 binds real buffers universally, so
  only the lifecycle logic was missing. `ebp-sync--ensure-eglot` runs
  at every attach: direct async `eglot--connect` (the `eglot-ensure`
  `post-command-hook` deferral never fires headless — verified at
  emacs-30.1 eglot.el:1455-1476), 30s buffer-local throttle that both
  prevents double-connect races and spaces the reopen attempts that
  revive an OS-reaped server. Gated by `ebp-sync-eglot` +
  `ebp-sync-eglot-modes` (elisp/org excluded on purpose).
- The gate got a `file-remote-p`-before-`file-exists-p` guard v1
  lacked — the house remote-before-stat invariant.
- The in-process elisp flymake backend (paren scan + temp-copy
  byte-compile, no `emacs -batch`) is swapped in at attach and
  RESTORED at detach: v1 swapped inside jetpacs-owned shadows, but v3
  binds the USER's buffer, so the swap is session-scoped.
  `ebp-sync-elisp-repl` carries the REPL lexical-binding-cookie
  variant for a future REPL attacher (the hub editor is not attached
  yet).
- The `flymake-start` kick per arm (headless idle timers unreliable)
  is gated on real backends. Test lesson: `flymake-mode`'s own enable
  calls `flymake-start` internally — a kick test must reset its
  counter after attach or it counts stock behavior.

Adversarial review (14 raw findings, 6 distinct confirmed, all fixed
same day):

- **The throttle is PROJECT-keyed** (`ebp-sync--eglot-attempts`), not
  buffer-local: with `eglot-sync-connect` nil the server reaches
  `eglot-current-server` only after the async initialize handshake, so
  a buffer-local stamp let a second file of the same project spawn a
  second server during cold init — leaked process, project silently
  split across two servers. (A faithfully-ported v1 bug.)
- The in-process backend **widens** — the stock backend it replaces
  widens too, and the wire ships whole-document offsets; unwidened, a
  narrowed buffer shipped spurious paren errors and misplaced
  squiggles.
- The `flymake-start` kick moved **off the dispatch path onto the
  settle timer** (`ebp-sync--push-diagnostics`), and the flymake
  enable is start-suppressed — a synchronous whole-buffer compile per
  keystroke inside the jsonrpc callback was the hot-path finding; a
  plain `run-at-time` timer fires fine headless, which was the whole
  rationale.
- The swap is **platform-gated** (`ebp-sync-elisp-inprocess`, default
  Android-only): in-process compilation runs macro expansion in the
  LIVE session and a pathological form can wedge a headless Emacs, so
  stock's subprocess isolation stays wherever spawning works.
- The in-process compile **mirrors stock's 30.1 `trusted-content-p`
  gate** (macro expansion IS evaluation), degrading to paren diags +
  one :note instead of stock's user-error.
- The paren pre-scan **no longer suppresses compile diagnostics** (an
  unescaped `?(` char literal false-positives it); the truly-unbalanced
  case drops the compile's duplicate end-of-file error.

Stated, accepted deltas (in the backend docstring): sibling `require`s
unresolved (no "-L ." equivalent), and compile-time evaluation runs
live on the Android path — both are why the gate defaults off
everywhere else.

After R0+R1: LSP completion + diagnostics + hover on device = v1
parity for programming modes, pending the desktop-uds/device smoke.

## R2 — exit-function + additionalTextEdits

After the Companion's accept returns as `edit.delta`, run the capf
`:exit-function` in the real buffer (snippet-stripped) and ship distant
edits (auto-import) via `ebp-client-edit-apply` (§19.4). Also the
`publishDiagnostics` event hook for push-latency parity. Never teach
the Companion Range/TextEdit — coordinate authority stays withheld.

## R3 — candidate `kind` (SPEC amendment) + icon render

Optional `kind` string on the §19.3 candidate: the LSP
CompletionItemKind 25-name vocabulary as lowercase strings (eglot emits
exactly these via `eglot--kind-names` / `:company-kind`), §22.4
feature-gated because the candidate object is closed. Companion renders
leading icons. Queues behind a device gate + push.

## R4 — survive-typing offers (SPEC amendment) + local narrowing

Relax §19.3's selection MUST-discard: MAY-apply when the only
divergence since the request is a typed prefix-extension matching the
candidate (replaced range = extended prefix). Companion narrows the
list locally instead of clearing on keystroke — v1's perceived-zero-
latency ingredient. Wire shapes unchanged; Emacs sees an ordinary delta.

## R5 — lazy candidate docs (SPEC amendment) + doc panel

New Companion→Emacs request `edit.candidate.doc` for the HIGHLIGHTED
candidate only (mirroring `completionItem/resolve` laziness), plain
text, frame-budget capped. Emacs answers from `:company-doc-buffer` /
eglot resolve.

## R6 — edit.command revival

§17.7's `command` op is fully specified and doubly allowlisted, but
Emacs has no handler (jetpacs-files.el bans toolbar `:command` ops as a
dead letter). Revive v1's DWIM engine (v1 jetpacs-sync.el:717-920):
predicate-gated command execution at the phone's point/region, bridged
`completing-read` M-x, one-splice diff-back via `edit.apply`. The
carrier for LSP code actions, rename, and formatting — zero wire
additions. Independent of R3-R5; can be pulled earlier.

## R7 — deferred

Snippet tabstops (candidate flag reusing §17.7's finite placeholder
grammar), inlay hints (a fourth §19.5 sibling), eldoc active-parameter
runs. All §25 class-2/3 additive with precedent; none blocks the eglot
goal. Take only when a concrete Glasspane workflow demands them.
