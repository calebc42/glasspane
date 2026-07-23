# W8 — Durable / offline reminders + triggers (rework plan)

_Design plan, 2026-07-23. Addresses the dominant cluster from the W7 conformance
audit ([AUDIT-w7-conformance.md](AUDIT-w7-conformance.md)): ~10 of the 16 P1s
share one root cause. This is the plan; no code here._

## 1. The defect (root cause)

`ReminderStore` and `TriggerStore` are plain in-memory maps held as **fields of
`CompanionEngine`**, and `DeviceBridge.serve()` mints a **fresh
`CompanionEngine` per accepted socket**. So every reminder/trigger — its
registrations, fired receipts, throttle floors, one-shot/boot markers, schedule
anchors, and silent baselines — is destroyed not only on a process/device
restart but on a **routine SPEC 5.2 reconnect**. Meanwhile `SurfaceStore` and
`DurableQueue` are already file-backed and **constructed once in `DeviceBridge`
and injected** into each per-connection engine.

This breaks, at minimum:

| Spec | Requirement | Audit P1 |
|---|---|---|
| 18.6 | accepted reminder set persists across restart | reminder-persistence |
| 18.6 | fired state durable + consulted, at-most-once | fired-receipt |
| 18.6 | unchanged tuple keeps fired state; re-push must not re-fire | double-fire |
| 18.6 | on_tap enters the §14 pipeline | tap-unwired |
| 18.6 | removed reminders cancelled | removed-not-cancelled |
| 18.6 | (platform) alarms re-armed after reboot | no-boot-receiver |
| 21.1 | registrations persist across restart | trigger-persistence |
| 21.1 | unchanged-id carry-forward survives | per-conn-reset |
| 21.2 | fire while disconnected (drop/queue/wake); throttle persists | offline-firing |

## 2. Design principle

Mirror the durable pattern the codebase already uses for the queue and
surfaces. That pattern is: a small **`Backing` interface** (`load()` /
`replace(snapshot)`) with a `Memory…` and a `File…` implementation
(`QueueStore`/`FileQueueStore`, `SurfaceBacking`/`FileSurfaceBacking`); the
store is **created once in `DeviceBridge` with a `File…` backing** and **passed
into the per-connection `CompanionEngine` constructor**, exactly like
`SurfaceStore`/`DurableQueue` already are.

Concretely:
1. Give `ReminderStore` and `TriggerStore` a `Backing` seam and a file
   implementation, and make them **constructor parameters** of
   `CompanionEngine` (they are engine `val` fields today).
2. Construct both once in `DeviceBridge` (like `store`/`queue`) and inject.
3. Move the parts of firing that must outlive a connection out of the
   per-connection engine into a **device-lifetime firing service**.

## 3. Components

### 3.0 Resolved design decisions (2026-07-23, approved plan)
The seam design was settled after a dedicated architecture pass; where the
subsections below differ, these rulings win:
- **`TriggerFiringService` lives in the wire library** (pure JVM), owns the one
  `TriggerStore` + `TriggerRuntime` + a ref to the shared `DurableQueue`, and is
  process-lifetime. Firing eligibility = durable registrations exist; the
  `granted` gate stays only on `triggers.set`/welcome (§21.1/21.2 impose no
  session precondition on firing).
- **`LiveSession` interface** (wire): `deliverLiveDrop(params)` +
  `onDurableAdmitted(policy)`. The engine implements it, attaches in init /
  detaches in `close()`; the service holds one newest-wins `@Volatile` slot and
  invokes it only AFTER releasing its monitor. Lock order: engine → service →
  queue; `DurableQueue` becomes an internally-synchronized leaf.
- **Baselines are NOT persisted** — §21.5 requires silent re-establishment from
  current state after restart; persisting would wrongly fire on a
  change-while-dead. `FileTriggerBacking` omits them by design.
- **`CompanionStores`** (app object) is the ONLY constructor of the file-backed
  instances (`ebp-queue.json`, `ebp-surfaces.json`, `ebp-reminders.json`,
  `ebp-triggers.json`), so cold manifest receivers and DeviceBridge share one
  instance per file; **`EbpApplication.onCreate`** bootstraps sources +
  `recover()` + `armBaselines()` regardless of MainActivity.
- **`dispatchContextless`** is extracted from the engine's
  `dispatchDescriptorContextless` so cold receivers (reminder tap) and the
  engine share one implementation.
- The queue-record **`pending_local`** flag gates the pump (a pending head is
  not yet eligible), closing the deliver-before-local race; `recover()`
  floor-reconstructs throttle/one-shot from surviving queued `trigger.fired`
  records for the A-committed/B-lost crash window.

### 3.1 Durable `ReminderStore`
- Add `ReminderBacking { load(): ReminderState; replace(state) }` +
  `MemoryReminderBacking` + `FileReminderBacking(file)`; `ReminderState` holds
  the owner→set map **and** the fired-receipt set (keyed `(owner,id,at_ms)`).
- `replace()` and `markFired()` persist atomically (write-temp-then-rename, as
  `FileQueueStore` does).
- Hoist to `DeviceBridge`; inject into the engine constructor.

### 3.2 Reminder presentation wired to the store (closes fired-receipt, double-fire, tap, cancel)
- `Notifications.scheduleReminders` must **cancel** alarms for removed tuples
  (compute the removed set from the store's prior vs new) and **only (re)arm**
  new/changed tuples; a tuple whose durable fired-receipt is set is skipped.
- `ReminderAlarmReceiver.onReceive` **consults + commits** the fired receipt
  (via the shared store) before `notify()`, so a restart never re-fires.
- The posted notification carries a `contentIntent` that routes `(owner,id)`
  into `dispatchReminderTap` → the §14 pipeline with the authored offline
  policy (queue/wake land in the DurableQueue for later replay; drop delivers
  live only if a session is READY).

### 3.3 Durable `TriggerStore`
- `TriggerBacking` + `FileTriggerBacking`; `TriggerState` persists each
  registration's normalized entry **and its runtime records** (throttle floor,
  one-shot completed, schedule anchor, last-fire floor, boot generation,
  silent baselines / edge levels — the §21.1 carry-forward set).
- Hoist + inject like §3.1. Sharing one store across connections is what makes
  the §21.1 unchanged-id carry-forward actually survive.

### 3.4 Device-lifetime firing service (closes offline-firing, throttle-persist)
The hard part. Trigger sources (`TriggerSources`) already run for the app
lifetime, but they feed `engine?.observeTriggerSample`, which no-ops with no
live engine. Split firing from the connection:
- A `TriggerFiringService` (device-lifetime, keyed by pairing identity) owns a
  `TriggerRuntime` bound to the **durable** `TriggerStore`, the durable
  `DurableQueue`, a durable throttle/receipt writer, and the platform on_fire
  executors (notify + trigger_caps). It runs whether or not a socket is open.
- The §21.2 transaction (§3.5) commits durably; **queue/wake** occurrences land
  as records in the already-durable `DurableQueue`, so a later session's replay
  delivers them — no live connection needed at fire time. **drop** occurrences
  deliver live only if a session is READY, but still commit throttle + run
  on_fire (SPEC 21.2), which the service does directly.
- The per-connection engine keeps only the **remote wire** duties (replay pump,
  live drop delivery); it observes the shared runtime rather than owning it.

### 3.5 The §21.2 durable transaction
The runtime's `commit` closure (already gated on a successful durable admit
after the W7 fix) must, in **one persisted transaction**, write: the throttle
floor, any one-shot completion / boot-generation receipt, and (for queue/wake)
the event record + `queue_seq`. Then run on_fire; then make the remote event
eligible. A `pending-local` marker lets recovery finish on_fire after a crash
without stranding the remote event. One-shot `completed` and boot-generation
fields (declared but unread today) get written + consulted here.

### 3.6 Boot re-arm (closes no-boot-receiver; amendment #43)
- A `BootReceiver` on `BOOT_COMPLETED` (+ `TIMEZONE_CHANGED` / `TIME_SET`)
  loads the durable reminder + trigger sets and re-arms platform alarms for
  unfired reminders and `time.*` triggers, and re-establishes trigger silent
  baselines (a fresh boot is a new generation, so `boot` triggers admit once).
- The manifest already declares `RECEIVE_BOOT_COMPLETED`; only the receiver +
  its store access are missing.

## 4. Firing-while-disconnected data flow

```
platform signal ──▶ TriggerSources ──▶ TriggerFiringService.observe
                                              │  (device-lifetime, no socket needed)
                                    gate + throttle (durable)
                                              │
                        ┌─────────────────────┴───────────────────────┐
                     queue/wake                                       drop
                DurableQueue.admit (persisted)              commit throttle + on_fire
                        │                                    live-deliver iff a session READY
             on_fire (persisted progress)
                        │
             next session's queue.replay delivers ──▶ Emacs
```

The DurableQueue is the existing bridge between an offline occurrence and a
future connection: it already survives restarts and replays on the next READY
session. W8's job is to feed it from a firing path that no longer requires a
live engine, and to make the reminder/trigger *state* around it durable.

## 5. Atom breakdown (amended sequence; the approved plan is canonical)

1. **W8-a** `ReminderBacking` + `FileReminderBacking`; `ReminderStore(backing)`
   synchronized, `markFired` persists before returning true; engine constructor
   param; **`CompanionStores`** (queue/surfaces/reminders) consumed by
   DeviceBridge/MainActivity; REWRITE-PLAN renumbered (organ ports → W9).
2. **W8-b** Reminder presentation: diff-based arm/cancel/skip-fired;
   receipt-before-notify in `ReminderAlarmReceiver`; `ReminderTapReceiver` +
   `contentIntent` → `dispatchContextless`; **`LiveSession` + the
   `dispatchContextless` extraction land here**; `CompanionStores.liveSession`.
   Device-verify at-most-once across a force-stop + offline tap replay.
3. **W8-c** `TriggerBacking` + `FileTriggerBacking` (entries + runtime records,
   NO baselines); `TriggerStore(backing)` synchronized + `identities()` +
   `persistRecords()`; engine param; `CompanionStores.triggers`.
4. **W8-d** `TriggerFiringService` owns the runtime; engine delegates +
   attach/detach; grant gate off the firing path; DeviceBridge feeds the
   service; §21.2 A/B transaction + `pending_local` + rollback + `recover()`;
   `DurableQueue` synchronized + `pendingLocal`/`clearPendingLocal` + pump
   gate; `time.at_ms` future check in `replaceSet`; one-shot completed + boot
   generation consult/commit; **`EbpApplication`** bootstrap.
5. **W8-e** `BootReceiver` (BOOT_COMPLETED/TIMEZONE_CHANGED/TIME_SET) re-arm
   for reminders + `time.*`; `TimeAlarmReceiver`; boot generation via
   BOOT_COUNT (admit once per generation); `every_s` scheduling +
   missed-interval coalescing (`nextRepeatDueMs`, wire, unit-tested);
   re-baseline on boot.
6. **W8-f** Device verification matrix: reminder at-most-once across
   force-stop; trigger fires while Emacs disconnected → delivered on next
   connect via replay; throttle survives restart (no immediate duplicate);
   reboot re-arm; offline tap replay.
7. **W8-g** Engine P2 sweep: every on_tap through canonical `validateAction`;
   uniform §4.4 128-octet identifier cap (trigger id/dedupe, pie menu_id,
   reminder owner/id); notification state gate (READY-only notifications
   dropped during SYNCING).

## 6. Also-fixable alongside (from the audit, same neighborhoods)
- `time.every_s` scheduling + missed-interval coalescing, and the one-shot
  `time.at_ms` future check + completed marker (21.5) — natural once the
  durable trigger transaction + boot re-arm exist (W8-d/W8-e).
- Editor "read-only whenever not READY" + reflecting inbound edits (§19) — the
  reactive-connection-state part of the renderer, deferred from the W7 P1 fix.
- Permission-revocation fail-closed + `trigger_unavailable` refresh (21.8).

## 7. Risks / open questions
- **Keystore encryption (21.5):** queued `sms.received`/`call.state` payloads
  must be keystore-backed encrypted at rest, not plaintext JSON — the
  `FileTriggerBacking`/queue payload writer needs an encryption seam for
  sensitive fire data. (P3 today, gated behind advertising those sources.)
- **Multi-identity:** the stores are keyed by pairing identity; the reference
  has one, but the durable format should be identity-scoped from the start.
- **`AlarmManager` exact-alarm budget:** many `time`/reminder alarms compete
  for the exact-alarm allowance; batch where the spec's coalescing allows.
- **Wire/service seam:** the per-connection engine and the device-lifetime
  service share the durable stores + queue; define ownership so both can read
  state but only the service commits fire transactions (avoid double-fire from
  a concurrent live observe + service observe — likely one observe path,
  routed through the service, with the engine subscribing for remote delivery).
