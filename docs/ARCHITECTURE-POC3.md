# POC 3 target architecture

The canonical implementation sequence is
[`PLAN-room3-rebuild.md`](PLAN-room3-rebuild.md). It supersedes the original
fork-forward surface-cache adapter: POC 3 now rebuilds the durable POC 2
semantics on Room 3 rather than projecting file-backed state into a second
database.

## Non-negotiable boundaries

EBP is Jetpacs-agnostic. Its Emacs implementation uses built-in Emacs
facilities, and its Kotlin implementation is being incubated in `:wire` for
eventual extraction as a standalone `kotlin-ebp` library. Neither library may
depend on Jetpacs packages, Room, Navigation, Compose, Android, or Jetpacs cache
policy.

Jetpacs is one implementation of EBP. The long-term product target is the
Compose Catalog authored in Emacs/Elisp and transferred as EBP documents. The
Android app is a dumb renderer: it selects a document from Jetpacs' durable Room
implementation of accepted EBP state, renders it, and returns typed EBP
actions. It must not compile a second Kotlin copy of the catalog.

Room 3 and Navigation 3 are Jetpacs choices, not EBP requirements. The EBP spec
must permit their use without naming or requiring them.

## Module map

| Module | Responsibility | May depend on |
|---|---|---|
| `:wire` | Incubator for transport, framing, contract, reducers, transaction SPI, and protocol state; future `kotlin-ebp` | Kotlin, serialization, coroutines, platform transport abstractions only |
| `:core:model` | Jetpacs read models and identifiers | Kotlin |
| `:core:database` | Complete Room 3 schema, DAOs, builders, migrations, and exported schemas | Room 3, SQLite |
| `:core:ebp-store` | Jetpacs Room implementation of the storage-independent EBP transaction SPI | `:wire`, `:core:database` |
| `:core:data` | Read-only Room `Flow` projections for Jetpacs UI state | `:core:model`, `:core:database` |
| `:core:navigation` | Serializable Nav 3 destination keys | Nav 3 |
| `:core:testing` | Shared fakes that obey production revision rules | `:core:data`, `:core:model` |
| `:feature:pairing`, `:feature:surface`, `:feature:settings` | ViewModels, entry providers, and Jetpacs feature UI | Jetpacs `:core:*` modules |
| `:app` | Single Android composition root, transport/platform adapters, and dumb renderer shell | `:wire`, Jetpacs core/feature modules |

The present module names intentionally keep `:wire` outside `:core`.
Extraction should be a source-compatible dependency substitution: publish
`kotlin-ebp`, replace `implementation(projects.wire)`, and delete the
incubator only after the standalone library passes the same goldens.

## Room 3 durable-state contract

Room is Jetpacs' sole durable implementation of information accepted from
Emacs, not an authority beside Emacs and not a second projection beside POC 2
files. Protocol acceptance rules remain generic `kotlin-ebp` behavior; the Room
adapter supplies their atomic persistence.

- Every durable record derived from Emacs is partitioned by pairing identity.
- Room stores surfaces/tombstones/stale metadata/current views, input drafts,
  queue counters/events/clock state, reminders/receipts, trigger
  registrations/runtime, themes, import state, and revocation cleanup state.
- Surface acceptance, draft reconciliation, queue dedupe/counter admission,
  reminder receipt handling, trigger runtime plus event admission, and pairing
  revocation use explicit Room transactions.
- No result is reported as accepted and no platform effect runs before commit.
- DAO `Flow` values feed read-only repositories and ViewModels; composables do
  not query the protocol engine or write accepted state.
- Whole-database delete-and-replace refreshes and live Room/file dual-write are
  forbidden.
- Section 19 editor sessions, deltas, sequence counters, caret positions, and
  completion results are session-scoped and non-durable. They must not enter
  Room or the offline action queue.

POC 1 used Room for queued events and triggers only. POC 2 introduced richer
file-backed queue, surface/tombstone/draft, reminder, and trigger state. POC 3
ports that richer behavior into one normalized Room 3 store and fixes the
pairing, stale-state, commit-reporting, and cross-store transaction gaps rather
than returning to POC 1's smaller schema.

## Navigation 3 contract

Navigation keys are Jetpacs presentation state. They identify pairing,
catalog/surface, and settings destinations; they do not become EBP methods or
document fields. The initial keys are serializable so `rememberNavBackStack`
can own saved navigation state when the current activity is migrated.

The first app migration should follow the local `basicsaveable` recipe for one
back stack. Multiple stacks and adaptive scene strategies are later additions,
after the single-stack dumb renderer is correct.

## Local reference review

All references below are local checkouts; GitHub is not an authority for this
work.

| Local checkout/ref | Commit reviewed | Pattern adopted |
|---|---|---|
| Jetpacs `slop-fork/main` | `9241bdd7c3881fbbdce3e4d871208c793cd0d99c` | Current KMP-shaped `:wire`/app baseline and later rebase target |
| EBP superproject gitlink | `4f8c7ba2bf5a38bcbe41246f1fc0b0c8f63e8776` | Current protocol, durability, and Section 19 authority |
| `architecture-templates` `origin/multimodule` | `9babdc9ca9b9559194bef3238503656b9a1e163e` | Data/database/testing/navigation module boundaries |
| `architecture-samples` TODO app | `ee66e1526b84c026615df032c705842b7d2a521f` | Repository as the data entry point, Room `Flow` as local source, screen state holders, shared fakes |
| `nav3-recipes` | `6564c15b4d1e8be318bffdf980504757d2d70645` | Saveable back stack, serializable `NavKey`, later multiple-stack/scene patterns |
| `kotlin-multiplatform-samples` Fruitties | `7844c73335eebc83f0162cfc4b22eb025a2f5458` | KMP Android library DSL, per-target KSP, generated Room constructor, bundled SQLite driver |
| AndroidX | `d69c96e6bc402016899904d66646816a62ebff4d` | Room 3 packages/plugin, write transaction, builder, current local release `3.0.0-rc01` |
| Emacs | `ba331c27f14adb429ef21fdf3d5c62febb7564d3` | Built-in `track-changes.el` version 1.5 API |

The TODO app's full fake-network refresh is deliberately not adopted. EBP
already supplies ordered, revisioned mutations, so deleting all local rows and
repopulating them would waste bandwidth, erase revision floors, and weaken
ordering guarantees. Its Hilt setup is also not copied into this first
scaffold; the repository boundary permits adding the selected DI mechanism
after the pending rebase without changing cache semantics.

## Implementation sequence

### Historical Step 1 — preparatory scaffold and device proof

The original five-module scaffold, revision/tombstone prototype, rebase, Android
16 floor, Room KMP/device proof, CI gates, and toolchain verification are useful
preparatory evidence. They are not the final persistence architecture.

Run bundled-SQLite DAO and repository integration tests on the KMP JVM target.
Do not treat Android host tests as device coverage: the Android variant of the
bundled driver loads JNI from an Android package, and local Room 3 itself
disables `testAndroidHostTest` for its multiplatform suite. Prove the Android
boundary by compiling the Android KMP variants and assembling the app. The
device follow-up reused the same `commonTest` suite on connected Android
hardware and was verified on a Pixel Tablet running Android 17/API 37.

### Step 2 — clean Room-integrated rebuild

Recreate the Companion from the local architecture template, preserve POC 2
behavior as backend contracts, add the generic suspending transaction SPI and
serialized runtime actor, implement the complete normalized Room schema, and
port one durable vertical slice at a time. The final data path is:

```
kotlin-ebp / :wire reducer
        -> generic EBP transaction SPI
        -> :core:ebp-store Room transaction
        -> committed Room 3 state
        -> read-only repository Flow
        -> screen ViewModel StateFlow
        -> dumb Compose EBP renderer
```

The former typed post-accept cache callback is not a persistence seam. A
post-commit domain change may notify platform-effect adapters, but Room is
already committed before it exists. Move destination ownership to a saveable
Nav 3 back stack only after the Room store cutover. A catalog destination
selects a cached EBP surface; it does not define the catalog.

The complete work packages, schema, transaction matrix, import policy, and
cutover gates live in `PLAN-room3-rebuild.md`.

Before adapter work, run a local-source best-practices audit and make its
findings an explicit gate:

- Gradle wrapper, AGP, Kotlin, KSP, and Compose compiler compatibility,
  including a verified distribution checksum for the selected wrapper.
- Android 16/API 36 and 36.1 behavior changes, lifecycle, background work,
  permissions, edge-to-edge, security, accessibility, and adaptive layouts.
- Current Android Jetpack guidance for repository/state-holder boundaries,
  lifecycle-aware collection, testing, and dependency injection.
- Compose Multiplatform source-set ownership, immutable/stable UI state,
  saveable state, semantics, performance, and platform adapters.
- Room 3 schema export and migrations, constructor/driver configuration,
  transaction boundaries, coroutine contexts, DAO Flow behavior, and tests.
- Nav 3 saveable back stacks, entry decorators, modular entry providers,
  predictive back, deep links, scenes, and adaptive layouts.
- Emacs 30+ built-ins, especially `jsonrpc.el` and `track-changes.el`, with
  ERT coverage on the minimum supported 30.1 release and current Emacs.
- EBP conformance against local EBP `slop-fork/main`, keeping both
  `kotlin-ebp` and `ebp.el` independent of Jetpacs.

Treat every compiler deprecation warning as an audit input. The first green
Android build already identifies inherited renderer/wire cleanup candidates:
AutoMirrored icons, positional `rememberSaveable`, dynamic swipe anchors,
primary/secondary tab rows, and Kotlin 2.4 exhaustiveness.

### Step 2.5 — harden the workspace before the synchronization engine

Pause feature work after the Room cutover and renderer connection. Refine the
evidence-backed hardening backlog before changing `ebp-sync.el` or its
`track-changes.el` engine:

- Inventory Kotlin and Elisp code smells, duplicated behavior, oversized
  files, leaky boundaries, and missing characterization tests. Classify each
  extraction as Jetpacs app code, reusable `kotlin-ebp`, upstreamable `ebp.el`,
  or workspace-only tooling; do not move product policy into EBP.
- Inventory existing utilities, reference material, generators, and lookup
  assets, especially `docs/lookup-tables`, vocabulary generators, goldens,
  validation scripts, and device helpers. Prefer extending one authoritative
  utility over introducing parallel helpers or hand-maintained tables.
- Diff the rebased m3-fidelity implementation and its tests against the DSL
  core. Identify missing or inconsistent primitives for structure, modifiers,
  state, actions, theming, adaptive behavior, accessibility, and expressive
  components; distinguish EBP vocabulary gaps from renderer-only defects.
- Build a POC 1 versus POC 2 regression and pattern matrix covering behavior,
  performance, persistence, synchronization, tests, and developer workflows.
  Mark each item restore, improve, replace with a built-in, or intentionally
  retire, including the former `jetpacs-sync.el` behavior now planned as
  generic `ebp-sync.el`.
- Propose developer-experience tools where they remove repeated reasoning:
  one-command local gates, schema/vocabulary drift checks, lookup-table
  generation, golden refresh/verification, module-boundary lint, device
  selection, fixture builders, and concise machine-readable audit reports.

Land only low-risk cleanup needed to make Step 3 legible. Larger abstractions
require at least two demonstrated consumers or a measured duplication/problem,
plus characterization coverage that proves behavior before and after the move.

### Step 3 — restore synchronization as generic `ebp-sync.el`

Port the behavior of POC 1's `emacs/jetpacs-sync.el`, but name the upstreamable
module `ebp-sync.el` and keep every symbol and dependency Jetpacs-agnostic.
Require built-in `jsonrpc.el` through the EBP transport and built-in
`track-changes.el`; do not hand-roll either subsystem.

For each authorized synchronized buffer:

1. Keep a buffer-local tracker ID, EBP session, sequence, and exact shadow.
   Register with `track-changes-register` using the default deferred signal,
   not `:immediate`, so JSON encoding and transport never run inside low-level
   change hooks.
2. Use a signal accepting an optional disjoint-distance argument. Register with
   `:disjoint t` and, on that special callback, call
   `track-changes-fetch` before returning. The fetch callback may copy and
   enqueue data but must not modify the buffer, block, encode JSON, or perform
   I/O. This prevents two far-apart edits from being widened into one large
   replacement solely for bookkeeping.
3. For the normal deferred callback, call `track-changes-fetch`. Its
   `(beg end before)` tuple already coalesces a command's nearby low-level
   mutations. Build one queued `edit.apply` splice from zero-based scalar
   `start = beg - 1`, `del = scalar_length(before)`, and the current
   `buffer-substring-no-properties` for `beg..end`. Advance a session only
   after the Companion accepts that exact next sequence.
4. Serialize queued applies: only one operation may contend for `seq + 1`.
   A short bounded queue preserves Section 19 ordering while command-level
   coalescing reduces frames and `:disjoint t` avoids oversized unrelated
   regions.
5. Treat `before == 'error`, `track-changes-inconsistent-state-p`, a shadow
   mismatch, or a typed stale result as a resynchronization boundary. Never
   guess a splice or send a blind whole-document replacement.
6. When applying a remote `edit.delta`, use one atomic buffer change while
   honoring write protection. Immediately consume that known self-change with
   public `track-changes-fetch` and an ignore callback so it is not echoed
   back; then update the session shadow and sequence.
7. Validate that the entire document and splice strings are losslessly
   representable as Unicode scalar values before exposing synchronization.
   Emacs positions can be used directly only after that eligibility check.
8. Call `track-changes-unregister` on close, document change, identity change,
   mode disable, and buffer death. Transport loss closes the EBP session even
   if the Emacs buffer survives.

This transfers incremental text only after edits, combines noisy low-level
changes at command granularity, and preserves small independent splices. Full
text remains limited to `edit.open` and explicit `edit.resync` recovery.

### Step 4 — feature modules and Compose Catalog parity

Introduce feature modules only as screens become real: pairing, surface,
settings, and an isolated renderer test app. Use ViewModels that combine
repository `Flow` values into immutable `StateFlow` UI state, following the
local TODO sample. Recreate each Compose Catalog example in Elisp/EBP and test
the dumb renderer against it before adding another example.
