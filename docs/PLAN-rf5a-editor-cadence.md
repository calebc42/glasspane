# PLAN-rf5a-editor-cadence — RF-5a: track-changes.el and the editor cadence, both sides

Status: **SUPERSEDED (stamped 2026-08-14, the D-16 ledger row) — do NOT
execute as written.** The ebp-sync.el §19 route (df8910c) and the
completion ladder (R0–R6, PLAN-glasspane-completion.md) delivered this
plan's territory by another path, and its two S1 amendment numbers
(#156/#157) were since REUSED by the m3-tier1 draft — running the
checkpoints now would collide with ratified spec text.  Two live
remainders survive it, pointed at the ledger rather than lost:
deliverable 3's poll replacement (jetpacs-emacs-ui.el still runs the
1 s chars-modified-tick `run-at-time` poll) and the Companion :app
profile hardening — both belong to future editor-cadence work, not to
this document.  Everything below is HISTORY.
Branch (on execution): `rf-5a`, stacked on `rf-4a` @ `93bb798`. One commit per
checkpoint; rollback = `git reset --hard` to the prior checkpoint SHA.

## §0 STATE

| Checkpoint | SHA | Status |
|---|---|---|
| R0 runbook | — | pending |
| E1 ebp.el cadence fixes | — | pending |
| E2 ebp-editor.el (observer + driver) | — | pending |
| E3 poll replacement | — | pending |
| K1 :wire cadence pins | — | pending |
| K2 :app hardening | — | pending |
| H1 host --editor flag | — | pending |
| S1 amendments #156/#157 routed | — | pending |
| L1 live suite | — | pending |
| R1 adversarial review | — | pending |
| EXIT battery | — | pending |

## 1. What this rung is

Caleb's governing request (2026-08-02): *"the editor.sync SHOULD have used
track-changes to begin with … as one of the main interaction methods and
loops, it deserves the utmost care and attention. Please put together a
comprehensive plan for implementing track-changes.el AND how it will change
our already existing codebase."* This rung is therefore NOT elisp-only
(correcting the refound plan's original framing at
`docs/PLAN-refound-2026-07-28.md:894`): it is the first-ever production
author of `edit.apply` on the Emacs side, plus the Companion-side hardening
that a live edit cadence makes load-bearing.

Deliverables:

1. `emacs/ebp-editor.el` — a consumer-generic track-changes observer core
   plus the §19 buffer↔document sync driver (the G4 core the apps plan
   deferred), with the RF-4b extraction seam pre-cut.
2. Three minimal `ebp.el` fixes (one required, two recommended) and one
   optional conformance closure (`ebp-client-edit-move`).
3. The `jetpacs-emacs-ui.el` 1 s poll replaced by the observer (the original
   RF-5a gate), preserving the `*Messages*` self-append discipline.
4. Companion `:app` hardening — the pure `adoptMirror` rule, the C4 reseed
   fix, `CaretThrottle` + the device→Emacs caret channel
   (`localEditorCaret`'s first callers), completion-offer hygiene.
5. Host `--editor` flag (forced by premise correction P5 below).
6. A live loopback suite (`test/ebp-editor-live-test.el`) with a
   falsifiable, non-flaking cadence gate.
7. Amendments **#156** (reconciliation precedence — ratified direction) and
   **#157** (informative apply-cadence note) drafted and ROUTED at S1;
   ratification is Caleb's and is NOT an exit condition (RF-3 #153
   precedent).

## 2. Premise corrections (line-verified by the design pass; read first)

Earlier exploration and the refound plan carried claims that did not survive
contact with the tree. Recorded here so they are not rediscovered.

- **P1 — the stale "silent drop" is narrower than previously reported.** In
  `emacs/ebp.el`, the `(when callback …)` at :1917 is a *sibling* of the
  applied-only arm at :1897, so a caller passing `:callback` DOES receive
  `("stale" nil)`. What is missing: any library-side reconcile, any
  docstring statement of the SPEC 19.2:3076-3078 caller duty, and — the
  only true silent drop — the callback-less caller.
- **P2 — the defect that actually breaks a single-in-flight pump:**
  `ebp-client-edit-apply` (ebp.el:1864) wraps its body in `(when ed …)`;
  with no live mirror entry it returns having invoked **nothing** — no
  request, no callback. A pump that sets `pending` before the call wedges
  permanently the first time a session closes mid-flight. Fix E1/8.1 is the
  one required library change.
- **P3 — two further conclusion paths:** `ebp-client--request` can conclude
  by *signal* (`ebp-ungranted`; serialization re-signal after rollback,
  ebp.el:1253-1266) and by error results (local 1401 ceiling, `-32000`
  timeout, 1204 off-READY). The pump must `condition-case` its send and
  clear `pending` on every conclusion.
- **P4 — ebp.el cannot express §19.4's move-only apply at all** (no
  `sel_start`/`sel_end` anywhere; `:cursor` hardcoded to
  `(+ start (length text))` at ebp.el:1895). A real conformance gap; §4.8
  item 8.4 closes it optionally.
- **P5 — `--caps editor.sync` cannot produce a live editor session.**
  `CompanionEngine.kt:956-957` filters editor scanning by the advertised
  node types, and `Host.kt:35-36`'s `HOST_NODE_TYPES` has no `editor`. With
  only the caps flag, no `edit.open` is ever emitted and every apply draws
  `editor-stale`. H1 (a host `--editor` flag doing BOTH halves) is forced.
- **P6 — the guaranteed adoption churn is the move-only apply, not the
  echo.** `CompanionEngine.kt:1854` publishes a mirror on the move-only
  arm, and `Renderer.kt:499-508` rebuilds the entire `TextFieldValue`
  (text, selection, composition) for it. Structural today; continuous under
  RF-5a cadence. Separately, there is **no Companion self-echo**
  (`localEditorEdit` never calls `editorListener`) — so the Compose
  smoothing must NOT be designed as an echo-suppressor; the echo loop is
  gated on the elisp side (test `inbound-delta-authors-no-apply`).
- **P7 — the display-epoch reseed trap (previously unnamed).**
  `Renderer.kt:480-483` keys the field's `rememberSaveable` on the display
  epoch; `SurfaceStore.kt:300-303` bumps it when a stateful node's
  displayed value changes. A synchronized editor has no draft, so a surface
  re-push carrying new `value` text reseeds the device field to it — and no
  mirror publication follows to correct it (`reconcileEditors` preserves
  the session, so the new `value` never reaches the shadow). Fixed both
  sides: Compose seeds from the mirror when one exists (K2), and the driver
  never re-pushes a changed `value` on a live editor (driver rule §11.3).
- **P8 — §19.4's fourth apply gate (text-composition transactions,
  SPEC.md:3266) has no implementation anywhere.** The engine never learns
  about IME composition. In-rung we stop destroying composition
  *needlessly* (the pure adoption rule); refusing an apply mid-composition
  needs an engine↔Compose signal and is deferred to RF-5e.

Confirmed environment facts: Emacs 30.1 ships track-changes **v1.2**
(`/usr/share/emacs/30.1/lisp/emacs-lisp/track-changes.el.gz`);
`track-changes-inconsistent-state-p` is available; v1.2 *errors* on
`:nobefore` + `:disjoint` together; none of its buffer-locals are
permanent-local (the §4.6 revert hazard). The tree has zero
change-function consumers and zero `with-silent-modifications` /
`inhibit-modification-hooks` occurrences — and must keep the latter at zero
(grep-pinned, case 21).

## 3. Ratified decisions of record

1. **CRDT is hard-walled out of the POC** (ratified at RF-4a). Reservations
   and seams only; no merge machinery of any kind in this line.
2. **Reconciliation precedence (ratified 2026-08-02):** a negotiated
   merge-discipline capability, when granted, GOVERNS reconciliation of
   concurrent edits; the normative fallback is **Emacs-first rebase**.
   Drafted as amendment #156 (§6.1) — prose-only, reserves the CRDT seam
   without defining merge semantics, consistent with the hard wall.
3. **Driver conflict policy = Emacs-wins rebase** (the #156 fallback,
   implemented). OT-lite positional transform is REJECTED outright — it is
   merge machinery, exactly what the wall excludes, and it silently
   produces text neither user authored. Resync is the bounded escape hatch
   (fetch `error` sentinel; `stale-count` > limit; inexpressible
   divergence), exposed as `ebp-editor-conflict-policy` so the decision is
   legible in code and a future multi-user rung has a named place to argue
   with.
4. **Scope is both sides** (Caleb's correction of the elisp-only framing).

## 4. Design — the elisp half

### 4.1 Placement

New file `emacs/ebp-editor.el`, sibling of `ebp.el` (`Package-Requires:
((emacs "30.1"))`, requires `ebp` + `track-changes` + `cl-lib`, prefix
`ebp-editor-`). Grounds: ebp.el is the spec surface ("every function cites
the section it implements"); the driver is a policy layer that cites none;
RF-4b needs the observer *without* §19; the sibling `ebp-*.el` shape is
already the plan of record for `ebp-data.el`. One file, two hard-separated
sections — the observer core (consumer-generic, zero `ebp-client-`
references, grep-pinned) and the §19 driver — so RF-4b's extraction is a
mechanical `git mv` along a pre-cut seam.

`test/run-tests.sh`'s delineation guard loads ONLY `ebp` today, so the new
file would be unguarded. E2 extends the guard to require every
`emacs/ebp*.el` feature (derived from the glob, not a hand-kept list — the
same lesson the byte-compile guard already records), so RF-4b's
`ebp-data.el` is covered by construction.
[correction 2026-08-06, PLAN-ebp-org-split G9: this E2 item is DISCHARGED —
another plan reached the guard first. G1 (69bb5ee) rewrote run-tests.sh:6-21
as a POSIX loop over the `emacs/ebp*.el` glob, one `emacs -Q --batch` process
per file, with the count asserted and the offender predicate widened past
`fboundp` to variables, faces, error conditions, group documentation,
`custom-group` parent links and loaded features. `ebp-editor.el` and
`ebp-data.el` are guarded the day they land, exactly as this paragraph asks.
Nothing else in RF-5a's E2 is affected.]

### 4.2 Observer core (consumer-generic)

`ebp-editor-observe BUFFER FN &key debounce name` → handle (registers a
`:nobefore` tracker; FN gets `(HANDLE SPAN)`, SPAN = `(BEG END LEN)` or the
symbol `error`); `ebp-editor-unobserve`; `ebp-editor-discard` (=
`track-changes-fetch id #'ignore`, the echo-suppression primitive);
`ebp-editor-flush`; `ebp-editor-observing-p`; pure `ebp-editor-splice OLD
NEW` → `(START DEL INS)`|nil (written character-for-character against
`EditorSession.kt`'s `diff` so the two agree by construction);
`ebp-editor-buffer-text` (widened, no properties).

Registration is `:nobefore t`, no `:disjoint` (v1.2 errors on the combo; we
want combining anyway — one splice per apply is the protocol's unit), no
`:immediate` (the signal must be able to reach the wire). **The invariant
that makes everything safe: the tracker is a trigger, not a source of
truth.** The splice is always recomputed from `base` (mirror text at last
look) vs the full buffer text, so discarding a fetch never loses
information and fetch/write races are harmless.

`:debounce` = leading-edge schedule, trailing fire, no restart: bounds
latency at DEBOUNCE and rate at 1/DEBOUNCE; a restart-on-signal debounce or
an idle timer would starve forever under continuous typing.

### 4.3 The §19 driver: sessions and the apply pump

Session record: `client document editor-id buffer handle base pending dirty
status stale-count fail-count timer seed-policy conflict-function`; status ∈
`awaiting-open | live | closed | parked`. Sessions in a global hash keyed
`(CLIENT DOCUMENT . EDITOR-ID)`; the buffer holds a **permanent-local**
`ebp-editor--buffer-sessions` (survives `kill-all-local-variables`).

The pump (`ebp-editor--pump`), guarded by: buffer live; status `live`;
client `ready` (1204 off-READY); **`pending` → return (SINGLE APPLY IN
FLIGHT)**; `track-changes-inconsistent-state-p` → reschedule 0.05 s. Then:
widened fetch (`error` sentinel → resync); if mirror ≠ base an inbound
change landed and the conflict path owns it; else splice = diff(base,
buffer); send `ebp-client-edit-apply … :cursor point-scalar :callback
#'ebp-editor--settle` inside `condition-case` (`ebp-ungranted` → park;
serialization error → clear pending, count failure).

Settlement (`ebp-editor--settle`): clear `pending` UNCONDITIONALLY first.
`applied` → reset counters, advance `base`, and if `dirty` re-pump via
0-timer (**the coalescing step**: everything typed during flight becomes
one splice). `stale` → `stale-count++`; over `ebp-editor-stale-limit` (4)
→ resync; else mark dirty and re-pump — the next pump reads *whatever the
mirror is now* and diffs against the buffer, which is self-correcting under
both orderings of (stale response, winning delta) and is exactly SPEC
19.4's "treat the incoming delta as authoritative" discharged by the
caller. Errors: 1401 `:ebp-local` → retry at 0.25 s; 1201 too-large → park
with ONE message, no retry (retrying spins); 1201 editor-stale → closed,
await reopen; other/-32000 → `fail-count`, park at max (3, mirroring the
poll's discipline). Every re-pump is a 0-timer, never an inline call —
keeps every send outside the `ebp--with-dispatch` inbound extent (the
Phase-A hang class).

**The pump owns reconciliation** (SPEC 19.2 assigns the duty to the
caller); the library gains only the minimal fixes in §4.8.

### 4.4 Inbound: delta application, echo suppression, the write

Inbound routing (one dispatcher on `ebp-client-edit-change-functions`,
coexisting by construction with the JC-4b picker's push/`delq`): text nil →
closed; text = pending's text → our own adoption (settle owns it); text =
base → nothing; `dirty`/`pending` → **conflict**: base ← text, notify
`'interleave`, mark dirty, pump (Emacs-wins — the buffer is never written
while dirty; phone keystrokes in the overlap are *visibly* overwritten, one
message + `ebp-editor-conflict-function` so the app layer can toast);
otherwise `ebp-editor--apply-remote`.

`--apply-remote`: race-check fetch first (a keystroke between signal and
write → mark dirty, pump, refuse); read-only/write-protected → refuse +
restore apply (SPEC 19.4:3155-3157; never `inhibit-read-only`,
grep-pinned); else write the splice, advance base, then **echo suppression
= `(track-changes-fetch id #'ignore)`** — NEVER `with-silent-modifications`
(it makes `track-changes-inconsistent-state-p` return t and leaves the
library's buffer-size bookkeeping stale, so the *next* real fetch returns
`error` and triggers a spurious resync). `unwind-protect` so a mid-write
error still leaves bookkeeping consistent.

The write: `undo-boundary` pair around `atomic-change-group` +
`delete-region`/`insert` — the boundary pair produces the single native
undo step (§19.4:3280), the change group provides rollback; they are needed
for different reasons. Ordinary-marker point adjustment with an explicit
clamp for point-inside-splice, applied to `point` and every
`window-point`. Do NOT move point to the remote caret (`edit.delta`
carries no cursor; yanking the Emacs user's point because someone tapped a
phone is hostile — remote-caret overlay is a later rung). Every fetch,
read, and position computation runs under `(save-restriction (widen) …)` —
required, not defensive: `track-changes-fetch` hard-asserts its bounds
against the current restriction.

### 4.5 Lifecycle

**Attach** (`ebp-editor-attach CLIENT DOC EID BUFFER &key seed-policy
conflict-function`) is callable *before* the surface push that causes
`edit.open`: the tracker registers at attach, gap edits accumulate as
dirty, and the full-text diff at open picks them up — no ordering
subtlety. Attach guards: buffer live; multibyte (scalar↔position
equivalence is the whole positional contract); `editor.sync` granted.

**Seed reconciliation** (#71, §19.3:3114-3119) on the open hook: seed =
buffer → clean; **empty buffer + non-empty seed → ESCALATE, never
auto-wipe** (the reconnect-after-buffer-recreated shape; buffer-wins there
destroys the user's phone text); else per `ebp-editor-seed-policy`
(`buffer-wins` default → minimal reconciling splice — pinned minimal, the
clause's actual teeth; `seed-wins`; `ask`). The mirror carries the seed at
fresh session before the hook runs (already pinned by
`ebp-test-edit-open-reconcile-seam`), so the reconciling apply is correctly
sequenced.

**Close/park:** `edit.close` → park, do NOT detach — reconnects reopen
sessions from the SurfaceStore and re-seed. Emacs cannot send a close
(§19.3 makes it Companion→Emacs only); the only lever is re-pushing the
surface without the editor node, which is the app layer's, via
`ebp-editor-detach-functions`. `kill-buffer-hook` → detach-buffer; client
teardown → detach-all.

**The revert/major-mode hazard (highest-probability field bug):**
`kill-all-local-variables` destroys every track-changes buffer-local (none
permanent-local in v1.2) — the tracker dies silently and the buffer stops
reporting forever. Mitigation: permanent-local driver record; a global
`after-change-major-mode-hook` re-registering dead trackers (generation
counter, no private API); `after-revert-hook` doing the same plus a forced
pump (a revert is one giant splice; over-limit routes to the too-large
park, correct and legible). Gated by its own test (case 14).

**Resync** (`ebp-client-edit-resync`) replaces the mirror at a fresh
session/`seq: 0`; the change hook then sees mirror ≠ base → conflict path →
Emacs-wins → the §19.4-mandated post-resync restore apply falls out of the
ordinary policy rather than a special case.

### 4.6 The poll replacement (E3)

`jetpacs-emacs-ui.el:526-576`: delete `--live-timer`/`--live-tick`/
`jetpacs-emacs-ui-live-interval`/`--live-poll`; the reconcile-watch keeps
its exact structure and top-buffer keying, with the timer arm becoming
`ebp-editor-observe :debounce jetpacs-emacs-ui-live-debounce` (0.3 s
trailing — 3× better latency than the poll, bounded 3.3 Hz worst case, and
non-idle so it still fires under continuous typing). This consumer is a
full surface re-push, NOT §19 — it uses the observer core only.

**The `*Messages*` self-append trap is preserved structurally:** the old
code re-read the tick *after* the push; the replacement calls
`ebp-editor-discard` *after* the push, swallowing what the push itself
wrote. The failure counter STAYS (obsolete-alias the interval defcustom):
`surface.update` concludes asynchronously, so a failure logged from its
callback lands after the discard — the consecutive-failure bound is the
guard that does not need to see the future. Carry that reasoning forward
verbatim in the docstring.

### 4.7 What the driver never does (summarized as rules in §11)

Never writes the buffer while dirty/pending; never re-pushes a changed
`value` on a live editor node (P7); binds only editors it registered (the
JC-4b picker is a synchronized editor that must stay unbound); never
suppresses modification hooks or read-only.

### 4.8 Minimal `ebp.el` changes (E1; each independently testable)

- **8.1 REQUIRED** — no-live-mirror-entry concludes the callback with a
  synthetic `editor-stale` (mirroring the #84 too-large local-conclude
  shape). Kills the P2 wedge.
- **8.2 recommended** — docstring states the §19.2 caller duty on `stale`;
  `display-warning` once when a stale concludes with no `:callback`
  (closing P1's only true silent drop). No behavior change for
  callback-passing callers.
- **8.3 recommended** — `&key cursor sel-start sel-end` on
  `ebp-client-edit-apply`, defaulting to today's hardcoded caret. Additive;
  lets the driver dictate Emacs's point (and lets a future transform of the
  device caret — maintained by `--handle-edit-caret` — ride the same keys).
- **8.4 OPTIONAL, drop first if the rung needs narrowing** —
  `ebp-client-edit-move` (§19.4's move-only form, P4). Driver use behind
  `ebp-editor-report-point`, 0.25 s idle, suppressed while pending
  (throttled at the source, symmetric with §19.3's caret guidance). The
  Companion side is already gate-complete.

## 5. Design — the Kotlin/app half

### 5.1 Triage

| # | Candidate | Verdict | Grounds (compressed) |
|---|---|---|---|
| a | Compose adoption smoothing | **IN-RUNG** | P6: move-only applies rebuild text+selection+composition today, continuous under RF-5a. SPEC duty preserved: caret always adopted; only text/composition stop being rebuilt when unchanged. |
| b | Drop completion offer on remote text change | **IN-RUNG** | Offer describes text that no longer exists; tap is a silent no-op. Bridge-side in `publishMirror`. |
| c | Wire `localEditorCaret` (device→Emacs caret) | **IN-RUNG, load-bearing** | `EditorSession.kt`'s own docstring assigns caret choice to ebp.el's side; ebp.el hardcodes it because `localEditorCaret` has ZERO callers — every Emacs apply steals the device caret and no Companion change can legally undo it. Without (c), RF-5a ships a two-way editor unusable two-way. |
| d | Companion `edit.delta` coalescing (§19.3 SHOULD) | **DEFER → RF-5e** | Coalescing *widens* the stale window RF-5a measures; needs an in-flight-aware flush rule; the pressure is unmeasured until RF-5a's live suite produces the first numbers. |
| e | RF-0.5b mirror-wipe CAS (`DeviceBridge.kt:613`) | **STAYS RF-0.5b** (fenced) | The carried finding names presentation flows + editor mirrors as ONE class; fixing one line lets it read as discharged. RF-5a adds a sentence to the RF-0.5b row noting raised reachability. |
| f | Robolectric/Compose adoption tests | **IN-RUNG** | RF-1b infra live (`PresentationIdentityTest` pattern); nothing covers `RenderEditor` at all; #151 forbids claiming unenforced properties. |
| g | Completion-debounce re-arm gate (`Renderer.kt:553`) | **IN-RUNG, rides (b)** | Every remote adoption currently buys an unwanted completion round trip. |
| h | §19.4 gate 4: refuse apply mid-IME-composition | **DEFER → RF-5e** | P8; needs new engine↔Compose machinery. |

### 5.2 The adoption rule (a) — pure, three cases

`internal fun adoptMirror(current: TextFieldValue, m: EditorMirror):
TextFieldValue?` extracted from the `LaunchedEffect` (Renderer.kt:499-508)
into `:app` (the `DialogCaptureTest` pure-function pattern): text+caret
equal → `null` (no state write — kills the redundant publication); text
equal, caret differs → `current.copy(selection=…)` — **composition and
text object preserved** (the P6 move-only case); text differs → fresh
`TextFieldValue` (composition necessarily dropped; the genuine remote
edit). Plus the P7 fix in the same composable: when `document.isNotEmpty()`
and a mirror exists, the `rememberSaveable` seed comes from the mirror, and
the epoch-keyed reseed re-runs adoption.

### 5.3 The caret channel (c) + CaretThrottle

`commit` (Renderer.kt:520-543) gains a selection-only branch →
`ctx.bridge.editorCaret(document, id, …)` (UTF-16, engine converts via
`scalarCaret`); new `DeviceBridge.editorCaret` mirrors `editorCommand` —
one `dispatchExecutor.execute { engine?.localEditorCaret(…) }`. The design
lives in a pure `internal class CaretThrottle`, two rules: (1) at most one
emission per interval per `(document, editorId)`, trailing-edge so the
resting position always ships (§19.3 "throttle at the source"); (2)
**suppress a caret equal to one the adoption itself just installed** — the
infinite-caret-loop breaker, named test, would otherwise be discovered
painfully on device.

### 5.4 Offer hygiene (b)+(g)

In `publishMirror`: published text differs from previously published text
for that key → drop the offer (~6 LOC). In `RenderEditor`: skip the 180 ms
completion request when the current text arrived by adoption (~3 LOC).
Offer publication extracted to `internal fun publishCompletionOffer` (a
behavior-preserving extraction making (b) drivable in tests).

### 5.5 H1 — the host `--editor` flag (forced by P5)

One flag, default off, doing BOTH halves: `editor.sync` into
`supportedCapabilities` AND `"editor"` into the app profile's
`node_types`. RF-3 decision 5 is the precedent and the constraint: the
no-flag host stays behavior-identical. **The loopback CI job's
`EBP_HOST_LAUNCH` line deliberately does NOT change** — widening the
shared host's caps would be additive-safe for existing suites but
insufficient (P5) and would silently change what the RF-2.6/RF-3 suites'
host advertises, the opposite of RF-3's "gate (1) untouched" discipline.
Own flag, own host process, own suite (the `--echo` pattern,
`test/ebp-seam-test.el:33-47`).

### 5.6 Test seams

Two `private` → `internal` in `DeviceBridge.kt`, each commented with its
test: `publishMirror` (drive adoption with no engine/socket) and the
extracted `publishCompletionOffer`.

## 6. Amendments (S1 — drafted + routed; ratification Caleb's, NOT an exit condition)

Draft doc: `docs/DRAFT-amendments-156-157-editor-cadence.md`, per-row
ratifiable. Both prose-only ⇒ I1 exemption class (a); no golden, contract,
fixture, or limit moves; validate.py counts unchanged. #153 remains
separately pending; #154/#155 ratified (`ebp` @ `37fb456`).

### 6.1 #156 — reconciliation precedence (ratified direction; normative)

Appended in §19.4 after the stale/authoritative-delta rule, to the effect
of:

> When a negotiated capability whose definition declares a merge
> discipline for concurrent editor operations has been granted for a
> session, that discipline GOVERNS reconciliation of concurrent edits for
> synchronized editors, taking precedence over the default in this
> section. This specification defines no such capability; the class is
> reserved. In the absence of such a grant, the normative discipline is
> Emacs-first rebase: the Emacs endpoint treats the winning operation as
> authoritative for its shadow of the Companion state and re-expresses its
> local text as a subsequent, properly sequenced `edit.apply` — it MUST
> NOT merge the two texts implicitly.

This reserves the CRDT seam without defining any merge semantics
(consistent with the hard wall), and makes the driver's Emacs-wins policy
the spec's named fallback rather than an implementation accident. Exact
wording drafted at S1 for Caleb's per-row ratification.

### 6.2 #157 — apply-cadence note (informative, NOT a SHOULD)

The considered Emacs-side coalescing SHOULD is rejected on inspection:
§19.3's Companion-side coalescing SHOULD is legal only because the
Companion *assigns* `seq` (§22.2 item 2 carves out pre-`seq` coalescing
explicitly); Emacs does not assign `seq` — it requests `seq + 1` — so
"Emacs coalesces between acks" is unconstrained authorship already outside
the protocol, not the mirror image of §19.3. And single-in-flight is a
*consequence* of the existing §19.4 MUST (a second apply before the ack
carries the same `seq` and is guaranteed stale). A fresh SHOULD would land
as a recorded wish with no tool behind it — #151's enforcement-naming duty
and #150's over-claim discipline both cut against it. Instead, one
informative paragraph in §19.4:

> *Informative: because `seq` is assigned by the Companion and a
> text-changing `edit.apply` is conditional on `seq + 1`, at most one such
> apply per editor can usefully be outstanding — every apply pipelined
> behind an unacknowledged one carries a superseded `seq` and draws
> `stale`. Emacs implementations therefore keep one apply in flight per
> editor and fold intervening local changes into the next one; this is
> authorship, not conflation under Section 22.2.*

## 7. The ladder

```
R0 ──┬── E1 ── E2 ──┬── E3
     │              │
     ├── K1 ── K2 ──┤
     │              │
     ├── H1 ────────┤
     │              │
     └── S1 ────────┴── L1 ── R1 ── EXIT
```

Two independent lanes off R0 (elisp E1→E2→E3; Kotlin K1→K2, H1
independent), joining at L1 (needs E2 AND H1). S1 floats. Serial order:
R0, H1, K1, K2, E1, E2, E3, L1, S1, R1, EXIT — H1 early because it is
small and unblocks L1.

- **R0 — this runbook**, `docs(plan)` commit ahead of any code, carrying
  P1-P8, the triage with both deferrals fenced, and the declined-test
  record. Gate: commit exists, no code in it.
- **E1 — ebp.el cadence fixes** (8.1-8.3; 8.4 optional). Gate: full wire
  suite green, every pre-existing test diff-empty; new
  `ebp-test-edit-apply-*` cases green.
- **E2 — `ebp-editor.el`** + `test/ebp-editor-test.el` + the run-tests.sh
  guard extension (ebp*-glob-derived). Gate: cases 1-21 green; guard
  extension in place; byte-compile glob green.
- **E3 — poll replacement.** Gate: ui suite green with the two new cases
  (one push per edit burst; a push whose own render appends to the watched
  buffer produces no further pushes) + the structural pin (no
  `run-at-time`, no `buffer-chars-modified-tick` in the file).
- **K1 — :wire cadence pins** (expected pins only; a defect surfacing
  lands here). Gate: `:wire:jvmTest` green incl. `EditorCadenceTest`.
- **K2 — :app hardening** (a,b,c,f,g + seams). Gate:
  `:app:testDebugUnitTest :app:assembleDebug` green incl. the three new
  suites; `RobolectricEnvironmentTest` still green (SDK-36 canary).
- **H1 — host `--editor`.** Gate: `:host:jvmTest :host:fatJar` green; two
  new `HostConformanceTest` pins (the `--editor` config advertises BOTH
  halves; the default config advertises neither, profile unchanged);
  existing caps-grant pin untouched.
- **S1 — the draft doc**, routed. Not on the critical path; not an exit
  condition.
- **L1 — live suite** `test/ebp-editor-live-test.el` (selector
  `^ebp-editor-live-`), own `--editor` host via
  `ebp-host-test--start-host` (the `--echo` pattern). Gate: with
  `EBP_HOST_LAUNCH` set, RF-2.6 + seam + editor-live all green; unset, all
  three skip loudly; run-tests.sh gains one stanza; CI elisp job name
  31 → 33 suites, verified against the `Ran N tests` count.
- **R1 — adversarial review**, 4 dimensions × 2-refuter verification over
  the rung diff (house checkpoint; RF-3 R1 / RF-4a S1 precedent). The
  dimension that most needs a refuter: **does the Compose smoothing mask
  an elisp echo loop** — would the rung still go red if E2's suppression
  were deleted? If not, the gate is wrong, not the code.
- **EXIT** — the five-suite battery (§12) from clean + the dual-recorded
  corrections (§10).

## 8. Test inventory

### 8.1 Elisp stub tier — `test/ebp-editor-test.el` (cases 1-21)

Stubbed `ebp-client--request` (`cl-letf`, the too-large-test pattern) for
reply-ordering control: single-apply-in-flight; coalesces-after-ack;
stale-rebase under BOTH orderings of (stale reply, winning delta) — buffer
never written, no resync; stale-storm resyncs at limit+1 then restores;
echo-suppressed (inbound delta → zero applies, point preserved
before/inside/after, single undo); fetch-error resyncs;
seed-reconcile-is-minimal (pins §19.3's teeth); seed-empty-buffer
escalates; read-only refuses + restores (grep-pin: no
`inhibit-read-only`); no-session-concludes (the 8.1 fix — no wedge);
1401 retries; too-large parks without spinning; narrowing-safe;
major-mode-change re-registers; detach-leaves-no-residue
(`edit-change-functions` restored `equal`); ungranted parks; not-ready
holds then sends. Observer tier: observer-coalesces;
splice-astral-parity (U+1D11E fixtures shared verbatim with
`EditorSession.diff`'s Kotlin fixtures); observer-section-is-client-free
(the RF-4b seam pin); no-modification-hook-suppression (grep pin). Plus
the picker-coexistence case (attachment on doc A; the JC-4b picker's
watch on doc B still works and its `delq` teardown restores the list) —
in the editor suite, dialog suite untouched. **The echo-loop pin
`inbound-delta-authors-no-apply` lives here and must not depend on any
Compose behavior** (P6).

### 8.2 `:wire` — `EditorCadenceTest.kt`

Sequence discipline under volume (the engine is single-threaded via
`feed()`): 32-apply burst all applied in order, listener fired exactly 32×
with increasing epoch; stale burst answers stale with zero listener
firings and no state damage (the clause Compose depends on); local edit
wins the race, in-flight apply goes stale, delta carries the right seq;
16 move-only applies never advance seq; an out-of-domain stale between
valid applies doesn't poison them; the #100 base-gate regression under
cadence. **Declined: an "overlapping apply pressure" test** — `feed()` is
single-threaded; it would assert the absence of an architecturally
excluded hazard and stay green with any fix deleted. Recorded here so it
is not later filed as missing coverage.

### 8.3 `:app` — pure + Robolectric

Pure (`EditorAdoptionRulesTest`, `CaretThrottleTest`): identical
publication is a no-op; caret-only preserves composition AND the text
object (the falsifiable form of (a) — composition is invisible to the
semantics tree, which is exactly why the rule is a pure function);
text-changing adopts both; selection adoption (range + collapsed);
throttle trailing-edge; **a caret installed by adoption is not echoed
back** (the loop breaker). Robolectric (`EditorAdoptionTest`, the
`PresentationIdentityTest` harness, mirrors via internal `publishMirror`):
remote apply shows text + peer caret; move-only moves selection only
(`TextSelectionRange`); remote text change drops the offer / caret-only
leaves it standing (the pair keeps (b) from becoming
clear-on-every-publication); **resurfaced editor seeds from the mirror,
not the authored value** (P7's gate — goes red today); read-only adopts
but never dispatches (§17.4 control).

### 8.4 Live suite — `test/ebp-editor-live-test.el` (L1)

Bound work and liveness, never milliseconds. (1) `burst-converges`: 200
rapid modifications then quiesce (15 s deadline): applies ≤ 200 AND
recorded max-in-flight EXACTLY 1 (dies the moment the single-in-flight
guard is deleted); convergence proven via `edit.resync` returning the
Companion's authoritative text = buffer string (deterministic, no clock).
Deliberately NOT asserted: that coalescing occurred — on fast loopback the
round trip may beat the burst; the ≤ bound + max-in-flight is the honest
pin. (2) `last-change-is-acknowledged`: final `applied` within 10 s — the
wedge catcher, cannot flake on a loaded runner. (3)
`stale-apply-reconciles`: hand-author a superseded apply, assert
`"stale"`, assert convergence via resync — pins the §19.4 arm ebp.el does
not implement today. The measured keystroke→applied latency is `message`d
as a diagnostic: an honest latency *claim* and a stable latency
*assertion* are different artifacts.

**Named residue:** the live suite cannot provoke a phone-originated
`edit.delta` (the host has no editor affordance/stdin driver). That
direction stays with the stub tier (echo, rebase orderings, fetch-error)
and the device smoke `test/smoke-a8-editor.el`. A host stdin driver
(`EDIT <doc> <eid> …` → `localEditorEdit`) is the cheap enabler if both
directions live are ever wanted — flagged, not assumed.

## 9. Risks, ranked

1. **The track-changes echo loop** (driver re-authors its own inbound
   write). The specific danger: (a)'s smoothing makes the symptom
   invisible while the loop burns the wire. Two-part mitigation, recorded
   as such: fetch-and-discard (E2) + the Compose-independent elisp pin.
   R1's refuter question targets exactly this.
2. **The caret feedback loop** — broken by CaretThrottle rule 2, pinned by
   its named test.
3. **Single-in-flight without a drain = silent wedge** — every conclusion
   path (1201/1401/-32603/timeout/close/ungranted/serialization) must
   clear `pending`; L1 test 2 + one E1/E2 unit case per path.
4. **P7's reseed trap from the driver's side** — belt and braces: Compose
   seeds from the mirror AND driver rule §11.3, because the SPEC does not
   forbid the push.
5. **`max_editor_bytes` asymmetry** (host 262144, device 65536): a
   whole-buffer restore passes on the host, draws 1201 on device; the
   driver consults `ebp-client-limits`, but the live suite tests the
   generous host — the strict path's only home is the device smoke.
   Residue, named.
6. **JC-4b picker regression** — the driver binds only editors it
   registered; picker coexistence case in the editor suite.
7. **RF-1b's `@Ignore`d rememberSaveable-recreation P1 is adjacent** —
   E3's event-driven pushes raise its reachability for editors. Not
   RF-5a's to fix; fenced, noted on RF-1b's row.
8. **RF-4b coupling** — the observer seam is a documented API (§4.1's
   pre-cut section + grep pin), not something RF-4b discovers.
9. **Non-multibyte/raw-byte buffers** break scalar equivalence and can
   signal out of `json-serialize` — guarded at attach, `condition-case` at
   send.
10. **Large files** park immediately at too-large — correct per SPEC, but
    the app layer should refuse to offer the editor node above the limit
    (`jetpacs-shell.el`'s GATE 4 already sizes the document; lean on it).

## 10. Dual-recorded corrections at exit (same commit as the ledger)

| Anchor | Correction |
|---|---|
| `docs/PLAN-jetpacs-apps.md:818` (B16) | G4's CORE landed generically at RF-5a as `ebp-editor.el` (bind, apply sender, #71 seed reconciler, cadence discipline, device-caret channel). Still OUT and unowned: §19.5 annotation function; Tier-1 product editor UI; org render integration; D-1's block editors. |
| `docs/PLAN-jetpacs-apps.md:827-833` (D-1) | The defer-G4-until-JA-7 recommendation splits: generic half no longer deferred; product half still is, JA-7 still decides it. |
| `docs/PLAN-jetpacs-apps.md:598-599`, `:1033`, `:1060-1065` | G4's core exists; `jetpacs-files.el`'s synchronized path is the first intended consumer, still unscheduled; block editors are a Tier-1 consumer, status unchanged. |
| `docs/PLAN-refound-2026-07-28.md:52` + `:894` | RF-5a row DONE + SHAs + runbook link; RF-5 gate marked met with the named tests. |
| `docs/PLAN-refound-2026-07-28.md` ladder | **New row RF-5e**: Companion-side §19.3 coalescing + §19.4 gate-4 IME refusal; blocked on RF-5a (needs its measurement); carries triage items (d) and (h). |
| `docs/PLAN-refound-2026-07-28.md:296-299` (RF-0.5b) | One sentence: the editor mirror is now long-lived under real two-way traffic, raising the wipe race's reachability; fix stays with RF-0.5b, unsplit. |
| RF-1b row | The rememberSaveable-recreation P1's reachability rises with E3; fence only. |

## 11. Driver rules (the cross-side contract, binding on E2)

1. The driver dictates the caret through 8.3's keys (Emacs point, or a
   transformed device caret from `--handle-edit-caret`'s state); ebp.el's
   hardcoded fallback remains for other callers.
2. On `stale`, the pump discharges the §19.2 caller duty (rebase +
   re-express); the library only concludes.
3. **Never re-push a changed `value` on a live editor node** (P7).
4. **Bind only editors the driver registered** — the JC-4b picker stays
   unbound; an unregistered `edit.open` is ignored (tested).
5. Echo suppression is the elisp side's; its pin is Compose-independent
   (P6).

## 12. EXIT battery (from clean)

```
cd companion && ./gradlew clean :wire:jvmTest :host:jvmTest \
                                :app:testDebugUnitTest :app:assembleDebug :host:fatJar
python3 ebp/validate.py && git status --short ebp/     # empty; pointer 37fb456
test/run-tests.sh                                       # 33 suites; live suites skip loudly
EBP_HOST_LAUNCH="java -jar companion/host/build/libs/host-all.jar --port 0 --kat" \
  test/run-tests.sh                                     # RF-2.6 + seam + editor-live green
```

Parent-gate mapping: "elisp editor suites green" → wire + editor + ui
suites; "poll timer deleted" → E3's structural pin; "latency case in
live-loopback suite" → the three L1 tests, running in the RF-1c loopback
job on every PR.
