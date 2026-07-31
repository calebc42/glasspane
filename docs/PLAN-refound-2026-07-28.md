# PLAN — Re-founding llm-poc-2: KMP wire core, module seam, `ebp.data` (2026-07-28)

**Purpose.** Execution plan for evolving llm-poc-2 in place — no llm-poc-3 clean
sheet — into: a compiler-enforced multiplatform wire core, an extension-dispatch
seam for negotiated SPEC modules, and `ebp.data` as that seam's first tenant.
A fresh session should read §0, then start at the first non-DONE rung.

**Provenance:**

| Source | What it holds |
|---|---|
| Conversation audit 2026-07-28 | Hand-rolled-vs-ecosystem sweep of llm-poc-2 (9 findings, file:line cited inline below) |
| `docs/REVIEW-poc-v1-vs-rewrite-2026-07-27.md` | Why the `:wire` seam is the asset this plan ports rather than rewrites; the no-CI indictment |
| SPEC §7.3 / §12 / §15 / §19 / §23 / §25 | Unknown-method behavior, namespace reservation, durable queue, editor module (the module-shape template), keystore mandate, registry evolution |
| [AUDIT-plan-spec-adversarial-2026-07-31.md](AUDIT-plan-spec-adversarial-2026-07-31.md) | The adversarial audit of this plan (7 P1 / 7 P2 / 3 P3); its amendments were applied in place 2026-07-31. The repo has no docs index — this citation *is* the registration |

**Method note.** Emacs claims are judged at the `emacs-30.1` tag
(`git -C ~/pkb/resources/emacs/emacs show emacs-30.1:src/sqlite.c`), never
master. Kotlin ecosystem claims (Room 3 = `androidx.room3:room3-runtime`, KMP
incl. JS/WASM, driver-API-backed; Room 2.x in maintenance) verified against the
AndroidX release notes 2026-03.

---

## §0 STATE

**The decision (Caleb, 2026-07-28): evolve llm-poc-2 in place.** The rewrite
criterion — *a rewrite pays only when a load-bearing seam is wrong* — is not
met: every gap below is additive or layer-local behind an existing interface.
A clean sheet would forfeit continuous golden verification and mint a third
set of demonstrated-once properties (see the v1→v2 regression ledger in
`REVIEW-poc-v1-vs-rewrite`). The `llm-poc-N` naming itch is satisfied at RF-6
by **graduating the name**, not the tree.

### Rung ladder (replaced 2026-07-31 per [AUDIT-plan-spec-adversarial-2026-07-31.md](AUDIT-plan-spec-adversarial-2026-07-31.md))

| Rung | What | Blocked on | Why (where non-obvious) |
|---|---|---|---|
| RF-0 | Push `ebp` **+ set upstream**, then parent; JA-4 P1-6; JA-6's five P1s; **`granted` gating**; device smoke | — | The push is a *technical* prerequisite of CI (audit P1-5) |
| RF-1a | CI: elisp + spec + wire + app; three-red demo. No new deps | RF-0 | Elisp suite is self-contained; the wire job needs the submodule |
| RF-0.5a | Process-scope the listener in `EbpApplication`; absorb the rotation defect | RF-1a | Structural, not JSON — land before C2 so it does not enlarge C6 and every later smoke is trustworthy |
| P0 | The owed pre-swap pin tests, string-literal fixtures | RF-1a | Enforced from birth, not demonstrated once |
| C2–C6 | The conversion, on branch `rf-2b` (RF-2a/B0/B1 done — [PLAN-rf2-kmp-migration.md](PLAN-rf2-kmp-migration.md) §0) | P0, RF-1a | Nothing under `ebp/` may change |
| spike-elisp | vulpea → flat rows | — (parallel now) | Zero Kotlin, zero `ebp/` |
| RF-2c | Hoist to `commonMain` | RF-2b exit | |
| spike-kotlin | table + apply-rows, `:app` only, via `surface.update` + `table` | RF-2b exit | Produces the measurement that decides RF-4a's carrier |
| RF-1b | Robolectric + renderer tests | RF-2b exit | New dependency stack + SDK-36 shadow-jar risk |
| RF-2.6 | Headless JVM loopback host | RF-2c | Nearly free once commonMain exists; four things depend on it |
| RF-1c | Cross-implementation CI job | RF-2.6 | First time elisp↔Kotlin is enforced rather than assumed |
| RF-0.5b | Foreground service + reconnection policy + supersession rules | RF-2b exit, RF-0.5a | New Kotlin — would be converted twice if earlier |
| RF-5a | track-changes.el — **now a prerequisite of RF-4b** | RF-1a | Promoted in the priority line |
| RF-5c | Keystore | RF-1a | Note the reconnect interaction |
| RF-3 | Extension seam + `jetpacs.echo` | RF-2c, RF-2.6 | Gate (2) is unrunnable without the host |
| RF-4a | `ebp.data` spec — inline changesets only | RF-3; informed by spike-kotlin; after I1 closes | Editing `ebp/` is forbidden while RF-2 is in flight |
| RF-4b | `ebp-data.el` | RF-4a, RF-5a | |
| RF-4c | `ebp-sqlite` (renamed from `ebp-room3`) | RF-4a, RF-2.6 | Under the producer decision, Room's constraints stop applying to a Companion-owned DB |
| RF-5b | WorkManager, **rewritten gate** | RF-1a | |
| RF-5d | Coil 3 | RF-1a | |
| RF-6 | Graduation + CMP desktop companion UI | RF-2..RF-4 | JVM target — RF-2's flip already suffices |

Strict order only where "Blocked on" says so; rungs sharing a cleared
dependency are parallelizable with each other. A ratified deviation is recorded
on **both** sides: the child runbook's ledger and this ladder's row.

---

## §1 Decisions locked (2026-07-28)

1. **Evolve in place; no llm-poc-3.** Rationale in §0.
2. **Room 3 as typed consumer only; the generic layer is `androidx.sqlite` +
   `sqlite-bundled` (rewritten 2026-07-31).** Room 3 cannot serve a
   schema-generic, wire-declared layer, for four verified reasons (audit P1-6):
   `createOpenDelegate` is implemented only by generated code, so opening
   without KSP codegen is impossible (`RoomDatabase.android.kt:302-306`); the
   connection manager *writes* a schema identity hash into any database it
   opens (`RoomConnectionManager.kt:113-155`); it opens with no flags under an
   `ExclusiveMutex` file lock (`:81`, `:70-73`); and its migration ladder is
   compile-time. The generic module is therefore renamed **`ebp-sqlite`**. Room
   3 remains the right materializer for a *Companion-owned* typed database
   (`jetpacs-vroom3`), where those same properties are harmless. Room 3 over
   SQLDelight stands for that consumer: SQLDelight still lacks a wasmJs target;
   Room 3 declares JS/WasmJS in-source (verified against the local clone,
   2026-07-31).
3. **kotlinx.serialization over org.json.** Forced by RF-2 (org.json is
   JVM-only and cannot exist in `commonMain`); independently justified by typed
   decode + strictness + JetBrains maintenance.
4. **The JSON-RPC envelope stays hand-rolled.** No canonical Kotlin JSON-RPC
   library exists (there is no jsonrpc.el analog), and SPEC §7/§8 constrain
   dispatch past what a generic library provides. Decision rule, stated once:
   *lean on the ecosystem when a canonical standard exists for the category;
   hand-roll when the logic is the spec.*
5. **KMP adopted JVM-first.** `kotlin("multiplatform")` with the JVM target
   only — behaviorally identical to today, zero risk. JS/WASM/native targets
   arrive when a non-Android companion becomes real, and inherit `commonTest`
   (the goldens) on day one.
6. **The three-level module stack**: platform-agnostic negotiated SPEC module →
   generic endpoint library → opinionated typed consumer. `ebp.data` →
   `ebp-data.el`/`ebp-room3` → `jetpacs-vroom3`. Same relationship at every
   level; everything below the SPEC is a negotiated optional with graceful
   fallback.
7. **Stable wire schemas, projected into.** A module's wire schema is a
   contract; upstream churn (e.g. a vulpea upgrade) becomes a maintenance item
   in the projection code, never a wire break.
8. **The library-adoption standing rule (added 2026-07-31).** A library is
   adopted only with: a **dated verification citation** (what was checked,
   where, when), a **tier** per I4 (materializer / capability /
   infrastructure), and the **seam** it sits behind — all named *before* the
   gate of the rung that adopts it, and recorded in
   [LIBRARY-LEDGER.md](LIBRARY-LEDGER.md). No ledger entry, no adoption. The
   Room 3 misfit above went undetected because the adoption was argued from
   release notes rather than source; the ledger is the enforcement point this
   rule otherwise lacks.
9. **Do not specify an optimization before measuring the need (added
   2026-07-31).** Sibling of rule 8, learned from the bulk carrier: the
   generation-swap mechanism was fully specified before any measurement showed
   inline changesets insufficient — and it did not survive contact with its
   own producer (audit P1-1/P1-2). The data spike's measurement decides
   whether a bulk carrier is ever needed; until then the floor is the spec.

---

## §2 Invariants — hold across every rung

- **I1 — `ebp/` is frozen through RF-2; wire-byte drift is expected (restated
  2026-07-31).** No file under `ebp/` is modified during RF-2 and goldens are
  never regenerated; `ebp/goldens/` + `validate.py` (37 frames, 17 wire
  fixtures, three chunkings) must pass unmodified, and the CI assertion is
  `git status --short ebp/` **empty**. Wire-byte drift is expected and
  SPEC-legal: §24 mandates *semantic* body comparison and forbids requiring
  member order or escaping choices (`SPEC.md:4287-4290`). The previous wording
  ("goldens byte-identical") named an enforcement that neither exists — no
  Kotlin test compares serialized bytes — nor would be legal to add without a
  canonical-JSON amendment (audit P2-5). Generalised into the
  **enforcement-naming rule**: a stated invariant names the tool and scope
  that enforce it; an invariant nothing enforces is recorded as a wish, not an
  invariant.
- **I2 — The dependency arrow points one way: Jetpacs → EBP.** No `jetpacs.*`
  symbol, method name, or schema in `:wire`, `ebp.el`, `ebp-data.el`, or
  `ebp-room3`. (Upstream candidacy dies the day this breaks.)
- **I3 — Names beginning `ebp.` are the spec's** (SPEC §12). Extension tenants
  use their own namespace (`jetpacs.*`) until ratified into the registry per
  §25.
- **I4 — Nothing Room-shaped, Kotlin-shaped, or Android-shaped in a module's
  wire vocabulary.** Three tiers (defined 2026-07-31 — the invariant was asked
  to carry all three while defining only the first): a **materializer**
  renders a projection into a platform artifact, one per platform (Room 3 is
  the materializer of `jetpacs-vroom3`; Glance of widgets; Nav3 of chrome); a
  **capability** is a negotiated, wire-visible optional (`ebp.data`,
  `editor.sync`); **infrastructure** is a library inside an endpoint that
  never surfaces anywhere (`androidx.sqlite` + `sqlite-bundled` inside
  `ebp-sqlite`; kotlinx.serialization inside `:wire`). Neither materializers
  nor infrastructure appear in wire vocabulary — only capabilities do.
- **I5 — Core dispatch behavior is frozen.** RF-3 adds a route for negotiated
  non-`ebp.` methods; §7.3 unknown/unnegotiated behavior for everything else
  is bit-for-bit unchanged, and the existing test corpus proves it.
- **I6 — No rung lands without its gate green in CI.** Start point and
  retroactivity (added 2026-07-31): binds from **RF-1a**. RF-2a/B0/B1 are
  grandfathered under their local gates (deviation ratified 2026-07-28,
  [PLAN-rf2-kmp-migration.md](PLAN-rf2-kmp-migration.md) §0); **C2 onward
  requires CI green.** The throwaway data spike carries no permanent gate but
  must never be able to redden another rung's.
- **I7 — Emacs is the sole interpreter of source formats.** Consumers read
  only projections Emacs produced and never author back into the source. A
  companion parsing `.org` (or any authored format) directly is permanently
  out of scope, not deferred: it would re-implement tag inheritance,
  `#+FILETAGS`, ARCHIVE/COMMENT skipping, per-file TODO keyword sets,
  repeaters, logbook semantics, priority normalization, `org-id` resolution —
  and the user's own config on top. Evidence this is a bug farm, not a
  theoretical risk: `AUDIT-ja4-2026-07-27.md`'s P2 org-semantics cluster found
  exactly these divergences *inside Emacs, in elisp, with org loaded*. Writes
  have a second edge — direct authoring collides with Emacs's live buffers
  (the supersession/changed-on-disk machinery clamped in JA-4 batch 3 and the
  mtime guard hardened in JA-6 exist because two writers with no protocol lose
  data), so every mutation rides the §15 queue. Corollary: **a projection
  stale by an hour is honest and correct; a live re-parse is fresher and
  wrong.** Consumers surface the generation, never re-derive.
- **I8 — A projection inherits its source's exposure and never widens it.** A
  derived artifact (index DB, cache, bulk snapshot) is placed in storage no
  more accessible than the source it summarizes. A vault in shared storage may
  have its index beside it; a vault in app-private storage may not. Where the
  vault lives is a user-facing onboarding choice (the Obsidian pattern: shared
  storage is app-agnostic and survives uninstall); the index follows it
  automatically, never independently. Addendum (2026-07-31): a copy under a
  *different application's* private storage — the Companion-owned projection
  the producer decision creates — is a **new exposure surface**, not the same
  exposure, and requires explicit onboarding consent of its own.

---

## RF-0 — Land the outstanding debt

A re-founding does not start on unpushed, known-defective ground.

1. Push `ebp` (submodule first — jetpacs pins it) **and set upstream**, then
   the jetpacs repo, per the standing order in the JC-0 ledger. State it
   plainly: **CI (RF-1a) technically depends on this step** — with no
   upstream, Actions has nothing to check out, and `actions/checkout` cannot
   fetch an unpushed submodule SHA (audit P1-5; verified: `git rev-parse @{u}`
   fails on both repos).
2. Close the open P1s: JA-4 P1-6 (blocks the JA-5 H1 hardware case) and JA-6's
   five open P1s.
3. **`granted` gating in `ebp.el`** (added 2026-07-31 — the v2 review's open
   P1, previously on no rung). The fix is bigger than the two known call
   sites: `ebp.el` has **no method→capability table** (verified, zero
   matches), so one must be built (`theme.set`→`theme`,
   `dialog.show`→`surfaces.dialog`, …) — **pinned against
   `ebp/contract.json`** rather than hand-written, since hand-written mirrors
   are a named v1→v2 regression; but it may read only fields that already
   exist in the contract, or the pin collides with I1. Specify the gate's
   failure mode (signal vs message vs silent drop), and its interaction with
   callers that already gate above it: `jetpacs-theme.el:471` has an explicit
   ungranted branch whose user-visible taxonomy must not change.
4. APK smoke on device after the pushes (force-stop first; screenshot before
   tapping — per device-smoke practice).

**Gate:** clean `git status` on both repos, remotes current **with upstreams
set**, P1 ledger empty (including `granted` gating), device smoke green.

---

## RF-0.5 — Process-scope the listener, then make it survive (added 2026-07-31)

The audit's framing correction (P1-4): the listener is a daemon thread on the
*application process*, merely *started* from `MainActivity.onCreate` — so there
are two separable defects, and the structural one needs no service machinery.
`EbpApplication.onCreate` already does process-lifetime bootstrap — firing
recovery, trigger-source start, baseline arming, reminder + alarm re-arm — and
omits exactly one thing: the socket. Today, a cold start from an alarm revives
triggers; the listener stays dead until the user opens the Activity.

**RF-0.5a — process-owned bridge (before C2).** Hoist the bridge bootstrap
into `EbpApplication`, beside the re-arm calls that already live there. No
`<service>`, no `FOREGROUND_SERVICE_SPECIAL_USE`, no Play surface. This also
absorbs the Activity-recreation defect (audit P2-1): the bridge becomes
process-owned and the Activity a pure observer of its flows — rotation stops
constructing a second bridge that loses the bind race while the first pushes
into a destroyed Activity's callbacks.
**Gate:** rotation + theme/surface round-trip smoke green; a cold start from
an alarm leaves the listener reachable; no bridge callback closes over an
Activity.

**RF-0.5b — foreground service + the reconnection-policy decision (after the
RF-2b exit; new Kotlin written earlier would be converted twice).** The FGS
restores v1's availability posture (`<service>` +
`FOREGROUND_SERVICE_SPECIAL_USE` + the Play justification). It lands together
with the decision it forces: **FGS vs `offline.wake` (§5.3) vs client
backoff** — three overlapping "get Emacs back" mechanisms exist and the plan
previously named only two (audit P2-3; `offline.wake` is validated in `:wire`
and advertised nowhere, `DeviceBridge.kt:111-113`). Whatever the choice, the
**supersession-livelock rules** apply (audit P2-2 — newest-wins plus
auto-reconnect on both endpoints and two Emacsen, a documented configuration,
oscillate forever):

- backoff with jitter and a cap on any close the endpoint did not initiate —
  §5.2 defines no supersession signal, so a bare close must be treated as
  possibly-superseded, never as certainly-crashed;
- drop the superseded session's pending callbacks on reconnect — a stale
  response must not conclude a new session's pending id;
- never shortcut the §10.3 barrier;
- a reconnect that fails at auth/welcome leaves the staleness timer running.

**Warning, recorded:** admitting `offline.wake` roughly doubles the rung —
§5.3's inertness requirements (coalesce, ≤1/60 s, stop waiting after 10 s,
"not background-execution privileges") are a security-conformance burden, not
a checkbox.

**Gate:** 0.5a's smoke stays green under the FGS; a two-Emacsen supersession
flap converges under the backoff rules instead of oscillating.

---

## RF-1 — CI (split 2026-07-31: 1a / 1b / 1c)

The sharpest v1-vs-v2 review finding: *every green number is demonstrated-once,
not enforced* — this repo has no workflow (only the `ebp` submodule's
`validate.yml`). CI precedes the conversion (C2) so every later rung is
enforced. RF-0 is a technical prerequisite, not hygiene (see RF-0 item 1).

**RF-1a — the four jobs, no new dependencies (GitHub Actions, on push + PR):**

| Job | Runs |
|---|---|
| wire | `:wire:jvmTest` (Gradle) |
| app | `:app` unit tests (no device) |
| spec | `ebp/validate.py` — goldens, contract, `check_spec_sync` |
| elisp | ERT suites batch-mode on GNU Emacs 30.1 (container/nix pin) |

Plus the I1 assertion: `git status --short ebp/` empty. Two non-obvious facts,
written down so the workflow author does not rediscover them (verified
2026-07-31):

- **the wire job needs the submodule** — five `:wire` jvmTest suites resolve
  fixtures through the `ebp.dir` system property and `error()` when unset; the
  wire job, not the spec job, is the real cross-repo binding;
- `local.properties` is gitignored, so `:app` needs `ANDROID_HOME` supplied by
  the workflow environment.

Device/instrumented tests stay manual (documented exclusion in the workflow
file — no silent caps).

**Gate:** intentionally break one wire test, one golden, one elisp test →
three red runs → revert → green. Red-on-regression *demonstrated*, not assumed.

**RF-1b — Robolectric + Compose renderer tests (deferred past C6).** Why it
defers, recorded: the renderer's protection during C6 is the APK smoke plus
the string-literal fixture rule (PLAN-rf2 Ground rules), not a framework
introduced the week before the conversion churns every call site — and the
new dependency stack carries its own risk (SDK-36 shadow-jar). Its reference
images are called **render snapshots**, never "goldens" — I1's noun is
already overloaded.

**RF-1c — the cross-implementation job (after RF-2.6).** The first time
elisp↔Kotlin is *enforced* rather than assumed: the ERT live-loopback suite
dials the RF-2.6 headless host instead of the elisp-scripted fake
(`test/ebp-wire-test.el:331`; audit P1-7 — no such harness exists today).

---

## RF-2 — KMP flip + kotlinx.serialization

Three sub-steps, each independently green. `:wire` today:
`kotlin("jvm")` (`companion/wire/build.gradle.kts:2`), org.json as
`compileOnly` (`:11`, Android framework supplies it at runtime), purity by
convention only.

**RF-2a — plugin flip, everything in `jvmMain`.** Swap to
`kotlin("multiplatform")`, declare the JVM target, `git mv`
`src/main/kotlin` → `src/jvmMain/kotlin`, `src/test/kotlin` →
`src/jvmTest/kotlin`. Purely mechanical; history preserved.
*Gate:* full suite + validate.py green, zero source-file content changes.

**RF-2b — org.json → kotlinx.serialization.** Retarget `EbpJson.kt` from
`JSONObject` to `JsonElement`; port the strictness layer (some checks vanish —
kotlinx is strict where org.json is lax — but the ±(2^53−1) bound, duplicate-key
policy, and top-level form checks survive as explicit code). The envelope
(`CompanionEngine` dispatch) sits on the new tree API unchanged in behavior.
Delete the org.json dependency.
*Gate:* **I1** (as restated: `ebp/` untouched, drift SPEC-legal); the 17
`.bin` fixtures at all three chunkings; elisp suite green. (The former "elisp
cross-implementation loopback" clause is retired — no such harness exists
until RF-2.6/RF-1c; audit P1-7.)

**RF-2c — hoist to `commonMain`.** Move everything pure: engine, `FrameCodec`,
stores + validation, `DurableQueue`, `EbpJson`. Leaves that touch the JVM stay
behind `expect`/`actual` or existing interfaces in `jvmMain`: HMAC
(`Auth.kt`'s `javax.crypto` becomes the JVM `actual`), `File`-backed stores
(already behind `QueueStore`/`SurfaceBacking`/`ReminderBacking`/
`TriggerBacking`). Tests move to `commonTest`.
*Gate:* `commonMain` compiles (which **is** the purity proof — `java.*` is
unresolvable there); `jvmMain` contains only the crypto `actual` + `File`
store impls; suite green. The by-convention seam is now compiler-enforced.

**Noted hazard for the future JS/WASM target:** Kotlin/JS numbers are IEEE
doubles — the ±(2^53−1) bound in `EbpJson` is exactly the check most likely to
diverge per-target. `commonTest` goldens exist to catch this class; do not
hand-wave it when the target lands.

---

## Data spike — vulpea → flat rows (added 2026-07-31, split)

A throwaway measurement rung, split so each half sits where it is legal.

**spike-elisp — now, parallel with C2–C6.** Touches only `emacs/` + `test/`,
and **must not modify anything under `ebp/`** (the I1 window). Project a real
vault through vulpea into flat rows; measure.

**spike-kotlin — after the RF-2b exit gate, in `:app` only — never `:wire`**
(or RF-2c's six-file `jvmMain` inventory gate breaks). **The carrier, stated
explicitly:** an ordinary `surface.update` carrying a `table` node — verified
advertised at `NodeSupport.kt:34`. A `jetpacs.*` *method* is impossible
pre-RF-3 (§7.3 unknown-method behavior is frozen, I5), and a `jetpacs.*`
*capability* is impossible (`CapabilityCatalog.VALIDATED` is a closed set and
a capability outside it throws, `CapabilityCatalog.kt:50,:58`) — the spike
rides existing vocabulary or it does not ride.

**Discipline** (this tree already carries two "staging, never required by
base" arms that survived their welcome): written questions, kill criteria, a
named removal commit, and a dedicated directory — all recorded before the
first line.

**The load-bearing question:** *what fraction of a real vault's projection
exceeds `max_frame_bytes` (`SPEC.md:247` — exactly `4194304`), and what does
elisp-side JSON encoding actually cost?* That number decides whether RF-4a's
reserved bulk carrier is ever specified (Decision 9).

**Two constraints orgseq's model header already states**, recorded so the
spike measures the real shape: DB titles are display-formatted, so the
projection must declare DB-vs-file provenance; and every mutation runs
`save-buffer` plus a synchronous `vulpea-db-update-file` — the write path any
change capture must coexist with.

---

## RF-2.6 — Headless JVM loopback host (added 2026-07-31)

`CompanionEngine` + the Memory stores + a `ServerSocket`, in a `:host` module
or a `jvmTest` fixture — after RF-2c, where `commonMain` plus the JVM actuals
make it nearly free. Four things depend on it: RF-1c (the cross-implementation
job dials it), RF-3 (gate (2) is unrunnable without it), RF-4 (its loopback
gate), and RF-6's desktop companion (this is its seed).

**Gate:** the ERT live-loopback suite passes against the host, with the
elisp-scripted fake (`test/ebp-wire-test.el:331`) deleted or demoted to a
unit fixture.

---

## RF-3 — Extension-dispatch seam

The structural anti-poc-4 insurance: negotiated non-`ebp.` module traffic
routes to pluggable handlers, so every future bridge (data, nav, widgets,
camera, credentials, …) is an additive library, never a core change.

**Kotlin side (`commonMain`):** a `ModuleHandler` registry on
`CompanionEngine` — a module registers `(namespace, negotiation entry,
method table, handler)`. Dispatch order: `ebp.` methods → existing registry
(frozen, **I5**); non-`ebp.` methods → registered + negotiated handler, else
exact current §7.3 unknown-method behavior. Handlers receive decoded
`JsonElement` params and the same reply/error seam the core uses (§8 error
model applies to tenants too).

**Elisp side (`ebp.el`):** the symmetric registration —
`ebp-client-register-module` (namespace, welcome/negotiation contribution,
method handlers), mirroring how `editor.sync` (§19) already models an optional
negotiated module, but without hardcoding the tenant.

**Trivial tenant to prove it:** `jetpacs.echo` — one request method, one
notification, negotiated on/off. Lives in test code only.

**Gate:** (1) entire pre-RF-3 corpus green untouched — the frozen-dispatch
proof; (2) tenant round-trips elisp↔Kotlin over live loopback **via the
RF-2.6 host**; (3) tenant
method *without* negotiation gets the §7.3 response, golden-pinned; (4) SPEC
conformance note (if §24 needs an "extensions present" clause, that is a spec
amendment through the normal §25 process, not a silent reinterpretation).

---

## RF-4 — `ebp.data` + `ebp-data.el` + `ebp-sqlite`

(`ebp-sqlite` renamed from `ebp-room3`, 2026-07-31 — see Decision 2: the
schema-generic layer cannot use Room, so the module must not be named after
it.)

The seam's first real tenant, and the strategic module: read-mostly mirror
now, CRDT-ready vocabulary later.

**The producer decision (2026-07-31, superseding the bulk-transfer
capability ratified 2026-07-30):** the Companion materializes its own
database from inline changesets. **Inline changesets are the only carrier; no
bulk carrier is specified until the data spike measures the need** (Decision
9). The struck generation-swap mechanism mandated a durable-publish sequence
Emacs cannot perform — `sqlite-open` hardcodes `CREATE|READWRITE`, URI
filenames are unreachable, no directory-fsync primitive exists, and
`write-region-inhibit-fsync` defaults `t` — and mis-stated the reader side
(a read-only open does *not* skip locking; only `immutable=1` does, and a WAL
artifact needs sidecars) — audit P1-1/P1-2. Dropping it **moots the entire
FUSE / immutable / rename / locking analysis**: no cross-process file
handoff, no cross-UID locking, no journal-mode discipline, no generation
retirement, no reader-holds-old-generation rule.

- **Honest cost, stated:** the projection is stored twice on one device.
  I7's logic accepts it — the Companion's copy is a projection, not a second
  interpreter.
- **Reserved shape** if the spike's measurement ever justifies a bulk
  carrier: not a SQLite file but a dumb hash-verified blob (gzipped NDJSON
  changesets) at a negotiated URI, content hash carried inline. The artifact
  need not be *durable*, only *detectable* — a torn or vanished file fails
  the hash and the consumer falls back to inline changesets, which stay the
  complete floor.

**RF-4a — module spec** (drafted as spec text in `ebp/`, negotiated like §19;
**sequenced after the RF-2b exit** — it edits `ebp/`, which I1 freezes while
RF-2 is in flight):

- Negotiation entry carries **schema identity + version/hash** — typed
  consumers (vroom3-class) must detect drift *before* changesets flow; the
  spec defines mismatch behavior (refuse vs degrade-to-dynamic).
- **Changeset-shaped from day one:** monotonic revisions, snapshots,
  tombstones — the surface-model discipline applied to rows. v1 semantics =
  single-writer (Emacs authoritative); CRDT arrives later as a negotiated
  merge-discipline capability, not a rewrite. cr-sqlite's column-clock scheme
  is the design document — **a frozen one** (last push 2024-10, last release
  2024-01, pre-1.0; audit P3-2): a design reference, not a living upstream.
- Changesets are **canonical JSON** over the §4 data model + JCS — never the
  SQLite session extension's binary format (unreachable from Emacs anyway:
  the built-in binding has no session API, and `sqlite-load-extension`'s
  hardcoded allowlist in `src/sqlite.c` bars third-party extensions forever —
  the allowlist is filename-based and the DEFUN itself is conditional on
  `HAVE_LOAD_EXTENSION`, so the conclusion holds *harder* than previously
  argued; audit P3-3).
- **Wide-integer encoding (added 2026-07-31):** §4.2 caps EBP integers at
  ±(2^53−1) with a hard Parse Error (`SPEC.md:141`) while SQLite `INTEGER` is
  64-bit — the module spec MUST define a canonical string encoding for
  integers outside the safe range before the first changeset flows (audit
  P2-7). Spec text plus goldens, so it lands here, after the I1 window
  closes.
- Write-back rides the **existing §15 durable queue** (Replicache/PowerSync
  upload-queue shape: Emacs = server authority, Companion mutations queue,
  ack, rebase). No second sync machinery.
- **Projection authority is normative, per I7.** The module states that the
  projection is authoritative for consumers and that a consumer MUST NOT
  interpret the underlying source format or write to it. Emacs applied every
  rule before the rows existed.

**RF-4b — `ebp-data.el`:** built-in `sqlite.c` only (30.1 API: `sqlite-execute-batch`,
transactions, pragmas, statement cursors) — no emacsql/closql in the core
candidate, same rule as jsonrpc.el. **Change capture (rewritten 2026-07-31):
not triggers → changelog table.** vulpea's update path is
delete-all-rows-per-file + re-INSERT with FK cascades, so row triggers record
churn, not changes — and a schema-epoch bump deletes the DB *file*,
annihilating an in-DB changelog (audit P1-3;
`~/.emacs.d/elpa/vulpea-20260714.543/vulpea-db-extract.el:1465`,
`…/vulpea-db.el:341`). Two tiers instead: **track-changes.el** (RF-5a — now a
prerequisite of this rung) observes the buffers Emacs actually edits, and a
**content-hash sweep** over projected rows catches out-of-band changes; both
feed the changeset builder *above* the storage layer, never inside it.

**RF-4c — `ebp-sqlite`:** schema-**generic**, `androidx.sqlite` driver-level —
receives the declared schema, creates tables, applies changesets in one
transaction, tracks revisions, verifies schema identity. Zero `@Entity`;
compile-time typed DAOs are the downstream consumer's job (post-plan,
`jetpacs-vroom3` — an ordinary Room 3 database with `@Entity`/KSP/migrations
over a **Companion-owned** DB, where Room's identity hash, file lock, and
no-flags open are harmless). Depends on the RF-3 seam + RF-2.6. **Inherited
costs of not using Room in this layer, priced in now:** a
`BEGIN IMMEDIATE`/`END`/`ROLLBACK` helper (template at
`RoomConnectionManager.kt:127-140`); thread confinement or
`SQLITE_OPEN_FULLMUTEX` (`sqlite-bundled` compiles `SQLITE_THREADSAFE=2` and
the single-connection stance is `hasConnectionPool=false`); and no
`InvalidationTracker` — consumers observe revisions, not tables.

**Gate:** contract entries + goldens for every `ebp.data` method — and name
what gates them: `check_spec_sync` covers 2 of 31 contract registries (audit
P3-1), so either extend it to the `ebp.data` entries or state the actual
enforcement; elisp↔Kotlin loopback **via the RF-2.6 host**: declare schema →
push changesets → kill Companion process → restart → verify materialized
state + revision resume; write-back event survives offline queue + replay;
schema-drift case golden-pinned; a changeset carrying a 64-bit integer
outside ±(2^53−1) round-trips through the canonical string encoding,
golden-pinned. (The former bulk-transfer sub-gates die with the mechanism.)

---

## RF-5 — Ecosystem swaps

(No longer "each independent" — 5a is a prerequisite of RF-4b, amended
2026-07-31.)

| Item | Today (audited 2026-07-28) | Target | Gate |
|---|---|---|---|
| **RF-5a track-changes** | No change hooks at all; 1s `buffer-chars-modified-tick` poll (`emacs/jetpacs-emacs-ui.el:571`) | Emacs 30 built-in `track-changes.el` (written for eglot's sync problem) wherever Emacs must observe local edits; feeds §19 — **and RF-4b's change capture (prerequisite, 2026-07-31)** | elisp editor suites green; poll timer deleted; latency case in live-loopback suite |
| **RF-5b WorkManager** | Queue survives as JSON file but the pump dies with the process — raw threads (`DeviceBridge.kt:166,191`), `AlarmManager` for exact triggers only (`TriggerAlarms.kt:33`) | `androidx.work` for deferrable guaranteed §15 delivery under Doze; AlarmManager stays for exact-time triggers | device smoke (**rewritten 2026-07-31**): queue → **process death by the reaper** (`adb shell am kill`, or OOM) → constraint met → delivery without app open. Never force-stop: a force-stopped app's scheduled work does not run until manual relaunch — the old gate red-bars by construction (audit P2-6) |
| **RF-5c Keystore** | Hard-coded W4 token constant in source both sides (`DeviceBridge.kt:108-110`, `device/init.el:184`); stores are plain JSON in `filesDir` | Android Keystore-held pairing token (SPEC §23.3 **mandates** keystore-backed when the platform provides it — this is a conformance gap, not an option) + real pairing persistence. **Note (2026-07-31): auto-reconnect turns every transport flap into a Keystore operation — budget its latency and rate limits when RF-0.5b's policy lands** | pairing survives process death + reboot; token absent from any file/backup; conformance case added |
| **RF-5d Coil 3** | Hand-rolled fetch/decode/LRU (`render/ImageLoader.kt`, `ImageCache.kt`) | Coil 3 for fetch/decode/cache; **keep** the SPEC policy layer (`wire/ImageGuards.kt`) in front — the guards are the product, the plumbing is not | image goldens/smokes green; SSRF/redirect/deadline guard tests still pass against the Coil path |

Priority (amended 2026-07-31): 5c (conformance) > **5a (spec-module quality
and RF-4b prerequisite)** > 5b > 5d.

---

## RF-6 — Graduation

When RF-2..RF-4 are green: the `commonMain` wire core is published as the
reusable EBP Kotlin library (it is already named `com.calebc42.ebp.wire` — the
artifact graduates into its name, the Kotlin analog of `ebp.el`), Jetpacs
becomes its first consumer by import rather than by co-location, and the repo
exits the `llm-poc-N` scheme. Rewrites are retired as the unit of change;
"add a negotiated module" replaces them. The **CMP desktop companion UI**
lands here (added 2026-07-31), seeded by the RF-2.6 headless host — a JVM
target, so RF-2's jvm-only flip already suffices.

**Gate:** a consumer project resolves the published wire artifact and passes
the loopback suite against it; README/BUILDING updated; the roadmap's §0 STATE
points here.

---

## Non-goals (this plan)

- **`ebp.nav` / Navigation 3** — sequenced after `ebp.data`; entirely disjoint
  from Room 3 (no dependency either direction). Gets the RF-4 treatment later:
  `ebp.nav` module → `ebp-navigation3` → Jetpacs chrome.
- **`jetpacs-vroom3`** — the typed vulpea consumer (two-halved: elisp
  projection + compiled Room entities). Post-RF-4; needs the stable wire
  schema RF-4a defines.
- **`surfaces.widget` on device / Glance** — still unadvertised
  (`DeviceBridge.kt:111-113`); its materializer is Glance when scheduled.
- **Live multi-process SQLite over one file, and companion-side `.org`
  parsing** — not deferred, *rejected*. See I7 (interpretation authority);
  and the two-process-one-file shape was rejected again, harder, by the
  2026-07-31 audit (P1-1/P1-2: a read-only open does not skip locking, and
  Emacs cannot durably publish a shared artifact at all). The vault-location
  onboarding choice per I8 is a Jetpacs application question, not a spec or
  plan rung.
- **CRDT merge capability** — vocabulary is CRDT-ready (RF-4a); the
  capability itself waits for a multi-writer use case.
- **Non-JVM targets, and the CMP desktop companion — split (2026-07-31).**
  The headless JVM loopback host is now a *scheduled* rung (RF-2.6); the CMP
  **UI** app is an RF-6 item; desktop CMP is a JVM target, so RF-2's jvm-only
  flip already suffices and no new target is scheduled. For the eventual web
  target, record now: `sqlite-bundled` declares **no** js/wasmJs targets —
  web uses `sqlite-web`, whose `open` is `suspend` — so `ebp-sqlite`'s
  synchronous open seam does not port unchanged.
