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

### Rung ladder

| Rung | What | Status |
|---|---|---|
| RF-0 | Land the outstanding debt: pushes + open P1s | OPEN |
| RF-1 | CI — enforce what is currently demonstrated-once | OPEN |
| RF-2 | KMP flip (JVM-only target) + org.json → kotlinx.serialization | IN PROGRESS — RF-2a done; RF-2b at checkpoint B1. Runs ahead of RF-1 on local gates (ratified 2026-07-28); see [PLAN-rf2-kmp-migration.md](PLAN-rf2-kmp-migration.md) §0 |
| RF-3 | Extension-dispatch seam + trivial tenant | OPEN — blocked on RF-2 |
| RF-4 | `ebp.data` module spec + `ebp-data.el` + `ebp-room3` | OPEN — blocked on RF-3 |
| RF-5 | Ecosystem swaps: track-changes / WorkManager / Keystore / Coil | OPEN — each independent, unblocked after RF-1 |
| RF-6 | Graduation: publish the wire core, exit `llm-poc-N` naming | OPEN — after RF-2..RF-4 |

Strict order only where "blocked on" says so. RF-5's four items are
parallelizable with RF-2..RF-4 and with each other.

---

## §1 Decisions locked (2026-07-28)

1. **Evolve in place; no llm-poc-3.** Rationale in §0.
2. **Room 3 over SQLDelight.** Room 3 closed SQLDelight's KMP advantage while
   staying the AndroidX-native artifact; both are compile-time codegen, so the
   choice only touches typed consumers (`jetpacs-vroom3`-style) — `ebp-room3`'s
   generic layer is `androidx.sqlite` driver-level either way.
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

---

## §2 Invariants — hold across every rung

- **I1 — Goldens are byte-identical through RF-2.** The KMP flip and the JSON
  swap are *representation* changes; `ebp/goldens/` + `validate.py` (37 frames,
  17 wire fixtures, three chunkings) must pass unmodified. Any golden edit
  during RF-2 is a defect, not an update.
- **I2 — The dependency arrow points one way: Jetpacs → EBP.** No `jetpacs.*`
  symbol, method name, or schema in `:wire`, `ebp.el`, `ebp-data.el`, or
  `ebp-room3`. (Upstream candidacy dies the day this breaks.)
- **I3 — Names beginning `ebp.` are the spec's** (SPEC §12). Extension tenants
  use their own namespace (`jetpacs.*`) until ratified into the registry per
  §25.
- **I4 — Nothing Room-shaped, Kotlin-shaped, or Android-shaped in a module's
  wire vocabulary.** Room/Nav3/Glance are materializers, one per platform.
- **I5 — Core dispatch behavior is frozen.** RF-3 adds a route for negotiated
  non-`ebp.` methods; §7.3 unknown/unnegotiated behavior for everything else
  is bit-for-bit unchanged, and the existing test corpus proves it.
- **I6 — No rung lands without its gate green in CI** (once RF-1 exists).

---

## RF-0 — Land the outstanding debt

A re-founding does not start on unpushed, known-defective ground.

1. Push `ebp` (submodule first — jetpacs pins it), then the jetpacs repo, per
   the standing order in the JC-0 ledger.
2. Close the open P1s: JA-4 P1-6 (blocks the JA-5 H1 hardware case) and JA-6's
   five open P1s.
3. APK smoke on device after the pushes (force-stop first; screenshot before
   tapping — per device-smoke practice).

**Gate:** clean `git status` on both repos, remotes current, P1 ledger empty,
device smoke green.

---

## RF-1 — CI

The sharpest v1-vs-v2 review finding: *every green number is demonstrated-once,
not enforced* — this repo has no workflow (only the `ebp` submodule's
`validate.yml`). CI precedes the migration so every later rung is enforced.

**Workflow (GitHub Actions, on push + PR):**

| Job | Runs |
|---|---|
| wire | `:wire` JVM test suite (Gradle) |
| app | `:app` unit tests (no device) |
| spec | `ebp/validate.py` — goldens, contract, `check_spec_sync` |
| elisp | ERT suites batch-mode on GNU Emacs 30.1 (container/nix pin), incl. the live-loopback suite |

Device/instrumented tests stay manual (documented exclusion in the workflow
file — no silent caps).

**Gate:** intentionally break one wire test, one golden, one elisp test →
three red runs → revert → green. Red-on-regression *demonstrated*, not assumed.

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
*Gate:* **I1** — goldens byte-identical; the 17 `.bin` fixtures at all three
chunkings; elisp cross-implementation loopback green.

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
proof; (2) tenant round-trips elisp↔Kotlin over live loopback; (3) tenant
method *without* negotiation gets the §7.3 response, golden-pinned; (4) SPEC
conformance note (if §24 needs an "extensions present" clause, that is a spec
amendment through the normal §25 process, not a silent reinterpretation).

---

## RF-4 — `ebp.data` + `ebp-data.el` + `ebp-room3`

The seam's first real tenant, and the strategic module: read-mostly mirror
now, CRDT-ready vocabulary later.

**RF-4a — module spec** (drafted as spec text in `ebp/`, negotiated like §19):

- Negotiation entry carries **schema identity + version/hash** — typed
  consumers (vroom3-class) must detect drift *before* changesets flow; the
  spec defines mismatch behavior (refuse vs degrade-to-dynamic).
- **Changeset-shaped from day one:** monotonic revisions, snapshots,
  tombstones — the surface-model discipline applied to rows. v1 semantics =
  single-writer (Emacs authoritative); CRDT arrives later as a negotiated
  merge-discipline capability (cr-sqlite's column-clock scheme is the design
  document), not a rewrite.
- Changesets are **canonical JSON** over the §4 data model + JCS — never the
  SQLite session extension's binary format (unreachable from Emacs anyway:
  the built-in binding has no session API, and `sqlite-load-extension`'s
  hardcoded allowlist in `src/sqlite.c` bars third-party extensions forever).
- Write-back rides the **existing §15 durable queue** (Replicache/PowerSync
  upload-queue shape: Emacs = server authority, Companion mutations queue,
  ack, rebase). No second sync machinery.

**RF-4b — `ebp-data.el`:** built-in `sqlite.c` only (30.1 API: `sqlite-execute-batch`,
transactions, pragmas, statement cursors) — no emacsql/closql in the core
candidate, same rule as jsonrpc.el. Change capture = triggers → changelog
table (~30 lines of SQL; the one legitimately hand-rolled piece, since the
canonical primitives are C-API-only).

**RF-4c — `ebp-room3`:** schema-**generic**, `androidx.sqlite` driver-level —
receives the declared schema, creates tables, applies changesets in one
transaction, tracks revisions, verifies schema identity. Zero `@Entity`;
compile-time typed DAOs are the downstream consumer's job (post-plan,
`jetpacs-vroom3`). Depends on the RF-3 seam + Room 3
(`androidx.room3:room3-runtime` line).

**Gate:** contract entries + goldens for every `ebp.data` method
(`check_spec_sync` binds prose↔contract both directions); elisp↔Kotlin
loopback: declare schema → push changesets → kill Companion process → restart
→ verify materialized state + revision resume; write-back event survives
offline queue + replay; schema-drift case golden-pinned.

---

## RF-5 — Ecosystem swaps (independent rungs)

| Item | Today (audited 2026-07-28) | Target | Gate |
|---|---|---|---|
| **RF-5a track-changes** | No change hooks at all; 1s `buffer-chars-modified-tick` poll (`emacs/jetpacs-emacs-ui.el:571`) | Emacs 30 built-in `track-changes.el` (written for eglot's sync problem) wherever Emacs must observe local edits; feeds §19 | elisp editor suites green; poll timer deleted; latency case in live-loopback suite |
| **RF-5b WorkManager** | Queue survives as JSON file but the pump dies with the process — raw threads (`DeviceBridge.kt:166,191`), `AlarmManager` for exact triggers only (`TriggerAlarms.kt:33`) | `androidx.work` for deferrable guaranteed §15 delivery under Doze; AlarmManager stays for exact-time triggers | device smoke: queue → force-stop → constraint met → delivery without app open |
| **RF-5c Keystore** | Hard-coded W4 token constant in source both sides (`DeviceBridge.kt:108-110`, `device/init.el:184`); stores are plain JSON in `filesDir` | Android Keystore-held pairing token (SPEC §23.3 **mandates** keystore-backed when the platform provides it — this is a conformance gap, not an option) + real pairing persistence | pairing survives process death + reboot; token absent from any file/backup; conformance case added |
| **RF-5d Coil 3** | Hand-rolled fetch/decode/LRU (`render/ImageLoader.kt`, `ImageCache.kt`) | Coil 3 for fetch/decode/cache; **keep** the SPEC policy layer (`wire/ImageGuards.kt`) in front — the guards are the product, the plumbing is not | image goldens/smokes green; SSRF/redirect/deadline guard tests still pass against the Coil path |

Priority: 5c (conformance) > 5a (spec-module quality) > 5b > 5d.

---

## RF-6 — Graduation

When RF-2..RF-4 are green: the `commonMain` wire core is published as the
reusable EBP Kotlin library (it is already named `com.calebc42.ebp.wire` — the
artifact graduates into its name, the Kotlin analog of `ebp.el`), Jetpacs
becomes its first consumer by import rather than by co-location, and the repo
exits the `llm-poc-N` scheme. Rewrites are retired as the unit of change;
"add a negotiated module" replaces them.

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
- **CRDT merge capability** — vocabulary is CRDT-ready (RF-4a); the
  capability itself waits for a multi-writer use case.
- **Compose Multiplatform renderer / non-JVM targets** — enabled by RF-2, not
  scheduled by it.
