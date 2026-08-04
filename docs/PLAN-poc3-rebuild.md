# POC 3 rebuild implementation plan

Status: accepted architecture baseline, 2026-08-03.

This is the cross-platform execution plan for POC 3. The detailed Android
persistence design remains in [`PLAN-room3-rebuild.md`](PLAN-room3-rebuild.md),
and the stable architectural boundaries remain in
[`ARCHITECTURE-POC3.md`](ARCHITECTURE-POC3.md).

## Outcome

POC 3 will make Jetpacs a durable, lifecycle-correct, dumb Android renderer for
EBP documents authored by Emacs. The first product-level proof is the Compose
Catalog authored in Elisp, transferred through EBP, cached by Jetpacs, and
rendered without a compiled Kotlin copy of the catalog.

The rebuild is successful only if later additions such as another Android
screen, a notification renderer, or a Glance widget are adapters over stable
contracts rather than reasons to replace the protocol, storage, or runtime
again.

## Governing decisions

1. **EBP remains Jetpacs-agnostic.** `ebp.el`, `ebp-store.el`,
   `ebp-sqlite.el`, `ebp-sync.el`, and the future `kotlin-ebp` library do not
   depend on Jetpacs, Android, Room, Navigation, Compose, or Glance.
2. **Durable delivery has two ledgers.** Jetpacs owns a Room 3 transactional
   outbox for actions it sends. Emacs owns an independent SQLite transactional
   inbox and recoverable work queue for actions it receives.
3. **The receiver owns acceptance evidence.** Emacs never delegates its
   Section 14.4 receipt/work commitment back to the sending Jetpacs process.
   Jetpacs can crash, disconnect, or be reinstalled without erasing Emacs'
   evidence that an event was accepted.
4. **Room is Jetpacs' single durable application store.** It contains cached
   accepted EBP presentation state, the outbound event queue, trigger/reminder
   state, and revocation progress. POC 2 JSON files remain a migration oracle,
   not a second live store.
5. **The protocol runtime has one ordered writer.** A bounded coroutine actor
   owns state transitions and Room transactions. A dedicated reader only
   decodes/demultiplexes and a dedicated writer only emits frames. No database
   transaction or actor command waits for peer I/O.
6. **Android component lifetime is explicit.** `Application` is a composition
   root, not the owner of a permanent listener. The bridge lifecycle and its
   Android 16 startup/foreground-service policy are an exit gate.
7. **The Kotlin protocol and renderer models are separate seams.** The future
   `kotlin-ebp` ends at validated typed protocol data and transaction commands.
   A target-neutral renderer model normalizes that data for Compose,
   notifications, and later Glance.
8. **Room stores protocol state, not renderer IR.** Renderer IR is derived and
   memoized by accepted revision/profile/version. Changing the normalizer must
   not require a Room migration.
9. **Nav 3 is Jetpacs shell state.** Serializable keys contain identifiers,
   never specs, Room entities, or session-bound dialogs. EBP `view.switch` is
   not Android navigation.
10. **Glance is a later profile.** A future Glance module consumes the same
    cached EBP state and renderer model through a restricted widget registry.
    It is not advertised until its real handler set passes device tests.

## Failure-domain topology

```text
Android user/platform intent
        |
        v
Room 3 outbox transaction          Jetpacs-owned durability
        |
        | event.action (stable EventId; at-least-once)
        v
ebp.el validation
        |
        v
ebp-store.el -> ebp-sqlite.el      Emacs-owned durability
 inbox EventId + serialized work
        |
        | accepted only after commit
        v
idempotent Emacs worker -> durable application effect
```

If the response is lost, Room retains and replays the same EventId. SQLite
returns `duplicate` without deliberately repeating completed work. SQLite and
an Org file cannot share one transaction, so durable work handlers must use
desired-state/idempotent operations and crash recovery; `atomic-change-group`
alone is not a disk transaction.

## Target module graph

### Emacs endpoint

```text
ebp.el
  protocol/session/action orchestration on public jsonrpc.el APIs
       |
       +--> ebp-store.el       neutral receiver-owned inbox/work contract
       |       |
       |       +--> ebp-sqlite.el  built-in sqlite.el implementation
       |
       +--> ebp-sync.el        Step 3 canonical-buffer/track-changes engine
```

`ebp-store.el` defines behavior and errors. `ebp-sqlite.el` owns schema and
SQLite mechanics. A backend can conform only when it is receiver-controlled,
survives independently of the sending session, and commits before the reply.

### Kotlin and Android

```text
:wire  (future kotlin-ebp-core/runtime)
  parser, framing, typed contract, validation, reducers, transaction SPI,
  bounded actor; no Jetpacs/Room/Android/Nav/Compose/Glance
                         |
                         v
:core:ebp-store  ----> :core:database
  Room mapping           Room 3 schema/DAOs/migrations
                         |
                         v
:core:data (read-only Flow projections)
          |                         |
          v                         v
feature ViewModels             :renderer:model
          |                    normalized target-neutral IR
          +------------+------------+---------------+
                       |            |               |
                       v            v               v
              :renderer:compose  notifications  :renderer:glance (later)
                       |
                       v
                 Nav 3 application shell
```

The present `:wire` directory is an incubator. Physical repository extraction
happens only after the public types, transaction SPI, and conformance corpus
stabilize; extraction is then a dependency substitution, not a rewrite.

## API boundaries to establish

### Emacs durable inbox

The neutral store operations are:

- open/close;
- atomically admit `(pairing-id, event-id)` plus one minimal
  serializable work item;
- distinguish a new admission from a previously admitted EventId;
- claim or resume pending work without executing inside JSON-RPC dispatch;
- complete, retry, or visibly block work under a checked lease;
- prune completed receipts only after the Section 14.4 retention floor and only
  when no work row remains; and
- erase one pairing partition without deleting another pairing's records.

The first SQLite schema uses separate `accepted_events` and `action_work`
tables inserted by one checked `BEGIN IMMEDIATE` transaction. Work states are
`pending`, `leased`, and `blocked`; completion deletes the work payload while
retaining the accepted-event receipt. Work payloads are canonical serializable
data plus a registered handler kind; Elisp closures are never persisted.

A repeated EventId is a duplicate under the current SPEC. If a future SPEC
revision distinguishes a same-ID/different-payload protocol violation, add a
canonical digest then; POC 3 must not invent a new wire result first.

### Kotlin durable store

The Kotlin SPI is suspending and domain-oriented. Reducers own EBP decisions;
Room owns atomic persistence. DAOs and Room entities never cross into `:wire`,
the UI, or renderer modules. The in-memory implementation is the reference
oracle and must support rollback/fault injection.

### Renderer model

The renderer model contains immutable typed documents, nodes, universal
attributes, semantic values, action descriptors, state bindings, and stable
presentation identities. It contains no `Modifier`, `Dp`, Android `Context`,
Room entity, `DeviceBridge`, Compose state, or Glance class.

Each backend installs a target-specific handler registry. Advertised EBP
profiles are derived from those registries and checked as contract subsets;
they are not duplicated as manually maintained lookup sets.

## Execution phases

### Phase 0 — Lock inputs and remove false seams

- Keep the POC 1 and POC 2 branches as read-only behavior references.
- Do not rebase `slop-fork/v3` until the current m3-fidelity work is fully
  merged into `slop-fork/main`; then rebase once and rerun every baseline gate.
- Resolve and pin the EBP submodule gitlink to the chosen current
  `slop-fork/main` commit before conformance changes. Never reset an already
  dirty submodule checkout as part of this work.
- Mark the old monitor-to-`WireLock` KMP plan superseded by the coroutine actor
  and suspending transaction design.
- Remove the prototype `core:data` mutation API and unused app dependencies.
  `core:data` is read-only; the future `core:ebp-store` is the only protocol
  mutation path.
- Add the platform-rental register and module-boundary checks.

Exit: documents agree on the inbox/outbox split, no production source calls the
secondary cache acceptance API, and the current JVM/Android/ERT baselines are
recorded.

### Phase 1 — Freeze behavior and contract projections

- Convert POC 2 surface, queue, reminder, trigger, action, and persistence
  behavior into backend-neutral characterization fixtures.
- Add explicit regression fixtures for POC 1 behavior lost in POC 2.
- Classify every mismatch as preserve, repair to SPEC, replace with a platform
  primitive, or intentionally retire.
- Consolidate contract generation for method metadata, vocabulary, fixed
  limits, and Elisp/Kotlin projections. Keep semantic reducers handwritten.
- Generate Kotlin artifacts into `commonMain` and make CI require a zero diff.

Exit: the same fixtures can be run against memory, Room, and the applicable
Emacs store; known gaps fail before implementation is ported.

### Phase 2 — Correct the Emacs endpoint foundation

- Introduce `ebp-store.el` and a contract-test fake.
- Implement `ebp-sqlite.el` using built-in `sqlite.el` with a checked wrapper
  around public transaction, commit, and rollback primitives. Emacs 30.1's
  `with-sqlite-transaction` can return the body value after a false commit and
  rollback, so the acceptance boundary must explicitly verify commit. Remove
  the append-only text fallback from the conforming acceptance path.
- Partition events/work by pairing and make `forget-pairing` erase only that
  partition. Credentials remain behind an injected `auth-source` adapter.
- Add durable action registration with a pure preparation step and a
  serializable work kind. Keep current synchronous handlers characterized while
  migrating them; do not silently call them exactly-once.
- Add kill/restart tests before admission, after admission/before reply, before
  effect, after effect/before completion, and after completion.
- Replace pure-Elisp HMAC, subprocess entropy, and private secret retention with
  built-in crypto/entropy and a late secret provider.
- Eliminate private `jsonrpc--*`, `timer--*`, predicted request IDs, and filter
  implementation dependencies. Add/upstream the smallest public seams needed
  for structured error data, safe request handles, backpressure, and redacted
  logging.

Exit: `accepted` means a local durable effect or work item, restart recovery is
green, an unavailable SQLite backend returns retry rather than false success,
and upstream-facing EBP code uses no private JSON-RPC/timer internals.

### Phase 3 — Establish the real KMP protocol boundary

- Move parser, semantic JSON equality, envelopes, typed profiles, generated
  contract data, validators, reducers, and splice math into `commonMain`.
- Introduce `ValidatedSurfaceSpec` rather than passing arbitrary raw JSON
  through every consumer.
- Add the suspending transaction SPI and rollback-capable in-memory store.
- Replace monitor/executor ownership with a caller-scoped bounded coroutine
  actor and ordered outbound channel.
- Put file import, JCA crypto, Java I/O/time/DNS, Android transport, and other
  platform behavior behind adapters instead of mechanical expect/actual locks.
- Compile a non-JVM target as the permanent common-code purity gate.

Exit: the full wire corpus and reducer contracts pass on common code; injected
store failure rolls back without response/effect; the reader never waits for an
actor, database, or peer response.

### Phase 4 — Build the complete Room 3 store

- Replace the one-table prototype with a new version-1 database containing
  pairing partitions, surfaces/tombstones/views/stale state, drafts, outbound
  events and counters, reminders/receipts, triggers/runtime/effect progress,
  themes, imports, and revocation cleanup.
- Implement `RoomEbpDurableStore` in `:core:ebp-store`; Room revision and
  admission logic never lives in `:core:data`.
- Port vertical slices in this order: pairing/revocation, surfaces/drafts,
  outbox/replay, reminders, triggers/effects, themes/import.
- Test each transaction against memory, in-memory Room, reopened file-backed
  Room, and a connected Android device with fault injection.
- Keep tokens in Keystore, preferences in DataStore, images in a pairing-keyed
  image cache, and session/Nav/editor state out of Room.

Exit: Room is the only Jetpacs live writer, the outbox survives process/device
restart, trigger runtime and event admission are atomic, and no response or
platform effect precedes commit.

### Phase 5 — Fix Android lifecycle and platform effects

- Reduce `EbpApplication` to the application container/composition root.
- Introduce a lifecycle-owned bridge service with a `SupervisorJob`, reader,
  actor, writer, and explicit session generation.
- Decide and test the Android 16 foreground-service category/start policy
  before declaring it in the manifest; do not assume a permanent listener is
  automatically permitted.
- Make alarms, notifications, widget updates, image deletion, and other
  platform work post-commit idempotent effects with reconciliation.
- Use WorkManager only for deferrable retryable work and AlarmManager for exact
  timing; use Activity Results for runtime permission flows.

Exit: process death, background/boot constraints, reconnect, and receiver
redelivery cannot create two runtime owners or lose committed work.

### Phase 6 — Normalize and cut over the renderer/UI

- Add `:renderer:model` and normalize accepted raw EBP into immutable typed IR.
- Add `:renderer:compose`; retain the old raw-JSON renderer only as a parity
  oracle while node families move behind the new registry.
- Convert notifications to the same renderer model so they do not become a
  second tree decoder.
- Derive target profiles from installed handlers and replace source-scanning
  `NodeSupport` pins with generated manifests and completeness tests.
- Add feature ViewModels using read-only Room `Flow -> StateFlow`, lifecycle
  collection, and an isolated renderer test application.
- Install Nav 3 with `Pairing`, `Catalog(pairingId)`,
  `Surface(pairingId, surfaceId)`, and `Settings` keys, one saveable stack
  first, entry-scoped ViewModels, and predictive-back/device tests.
- Recreate Compose Catalog examples in Elisp/EBP and require parity before
  adding Kotlin-only product behavior.

Exit: the Elisp-authored catalog survives rotation, process death, offline cold
start, reconnect, predictive back, pairing isolation, and revocation.

### Phase 7 — Workspace hardening gate

- Complete the POC 1/POC 2 regression matrix and m3-fidelity DSL audit.
- Consolidate duplicated JSON access, contract/vocabulary generators, lookup
  tables, fixture builders, and device scripts only with demonstrated users.
- Add module-boundary lint, schema drift, profile drift, golden verification,
  and one-command JVM/device/ERT gates.
- Replace polling with lifecycle hooks/`file-notify` where applicable and
  replace private Emacs helper calls with public APIs.

Exit: Step 3 can reuse one canonical document/buffer model and one contract
projection rather than growing another parallel set of helpers.

### Phase 8 — Build `ebp-sync.el` on `track-changes.el`

- Restore the useful POC 1 synchronization behavior as generic `ebp-sync.el`.
- Use one normally initialized canonical visited buffer per document so mode,
  local variables, project, Eglot, Flymake, completion, fontification, and
  actions observe the same text.
- Register built-in `track-changes.el` with deferred signals and `:disjoint t`;
  fetch/copy changes before returning from disjoint callbacks and encode/send
  later.
- Coalesce command-local changes into bounded scalar-indexed EBP splices and
  keep only one next-sequence operation in flight.
- Apply remote deltas with `atomic-change-group`, consume their known tracker
  change without echo, and use full text only for open/explicit resync.
- On Android, use state-based text fields and `TextFieldBuffer.changes` so IME,
  paste, accessibility, and hardware edits become transactions rather than
  whole-string diffs.

Exit: ordinary edits transfer deltas, remote edits do not echo, crash/resync
paths are deterministic, and the suite passes on Emacs 30.1 and current Emacs.

### Phase 9 — Extract libraries and add later profiles

- Publish the stabilized local `kotlin-ebp` artifact, substitute it for
  `projects.wire`, run the identical corpus, then remove the incubator.
- Prepare the upstreamable Emacs modules independently of Jetpacs packaging.
- Add `:renderer:glance` only when desired. It reads cached Room projections,
  uses widget-instance configuration separately, routes actions through the
  same Room outbox, and advertises only its restricted implemented profile.
- Keep Quick Settings as a separate `TileService` projection.

Exit: library extraction and Glance require dependency/configuration changes,
not protocol, storage, or runtime redesign.

## Rebuild gates versus contained refactors

A finding can reopen architecture only when it changes one of these:

- source of truth or transaction boundary;
- lifecycle/concurrency owner;
- public protocol/library seam;
- platform/security failure domain;
- renderer/domain model; or
- KMP/module boundary.

Everything else must fit behind one of those ports and land as a tested adapter
or refactor. Image loading, individual Compose deprecations, lookup utilities,
and a future Glance backend are important but are not new POC boundaries.

## Immediate implementation slice

The first landing slice is deliberately small:

1. add this plan and the platform-rental register;
2. correct the Room/SQLite inbox-outbox language in the existing architecture
   and Room plan;
3. remove the prototype `core:data` acceptance methods and unused app module
   dependencies while retaining the Room toolchain proof;
4. mark the obsolete lock-hoist KMP instructions as historical;
5. add standalone `ebp-store.el`/`ebp-sqlite.el` contract tests only if they can
   land without pretending the current effect-then-receipt dispatcher is fixed;
6. run the focused KMP core tests, app assembly, ERT store/wire tests, and
   structural boundary checks.

No file store, renderer, or process owner is deleted in this slice. Those
deletions occur only after its replacement passes the corresponding parity and
restart gates.

## Definition of done

POC 3 is ready to replace POC 2 when:

- the current pinned EBP spec/goldens pass at both endpoints;
- all accepted inbound actions have receiver-owned durable evidence/work;
- all Jetpacs durable outbound actions and accepted presentation state use
  Room transactions partitioned by pairing;
- no second file/cache acceptance authority remains;
- Android has one lifecycle-supported runtime owner;
- Kotlin common code has a non-JVM purity gate and extraction proof;
- the Compose renderer consumes normalized typed IR and generated profiles;
- Nav 3 restores only Jetpacs shell state;
- `ebp-sync.el` uses public Emacs 30.1+ primitives and incremental deltas;
- process/device death, offline/reconnect, revocation, schema migration,
  predictive back, accessibility, and device tests pass; and
- later Glance support is demonstrably an adapter, not a rebuild.
