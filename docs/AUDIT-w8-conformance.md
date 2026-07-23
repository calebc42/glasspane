# W8 durable-offline conformance audit (reminders §18.6 + triggers §21)

Date: 2026-07-23. Target: the W8 durable-offline subsystem of the Jetpacs EBP
companion (`companion/wire` library + `companion/app` host), commits `1c176d7`
(W8-a) … `2cb3682` (W8-f/d′). Method: six parallel adversarial auditors
(concurrency/locks, §21.2 transaction + recovery, §21.5 scheduling, §18.6
reminders, persistence/durability, SPEC gaps/amendments), then every headline
finding **re-verified against the cited code** by hand — subagent claims are
candidates, not conclusions. Two auditors independently refuted the
"unbounded fired-receipt growth" hypothesis (bounded by the set); three
independently found the one-shot recovery defect.

**Verdict:** the durable *data* model is sound (atomic writes, TTL/expiry,
store rollback, single-instance-per-file, at-most-once reminder state machine,
`every_s` coalescing math, unchanged-carry-forward all verified correct, and the
deferral design is genuinely deadlock-free), but the subsystem is **not yet
reference-correct**: a crash between its two durable writes double-fires an
exactly-once trigger, three concurrency data races (one a live crash) sit on the
firing path, and the reminder presentation layer is owner-blind. Plus two SPEC
holes the reference itself trips over.

Severity: **P1** = data loss / duplicate-or-lost delivery / crash / MUST
violation. **P2** = narrow race, robustness, or interop ambiguity. **P3** =
minor / latent / editorial.

---

## P1 — implementation (must fix before this is a reference)

### P1-1 · Recovery reconstructs the throttle floor but NOT the one-shot / `every_s` completion markers → an A/B-split crash double-fires an exactly-once trigger
*(found independently by the transaction, scheduling, and persistence auditors; verified)*

The §21.2 transaction spans **two** durable files that cannot commit atomically:
**A** = `DurableQueue.admit()` (`ebp-queue.json`) and **B** =
`store.persistRecords()` (`ebp-triggers.json`, `TriggerRuntime.kt:264`, called
**bare** — no `runCatching`). `recover()`
(`TriggerFiringService.kt:209-225`) reconstructs only `throttleFloorMs`
(`:219-220`); it never restores `oneShotCompleted` or `lastFireFloorMs`.

Scenario (one-shot `time.at_ms`, `policy:"queue"`, no `throttle_s`): the alarm
fires → A commits event E1 → process is killed (or `persistRecords()` throws)
before B. On restart `TriggerStore.init` loads `oneShotCompleted=false`;
`recover()` floors the throttle from E1 — a **no-op**, because a one-shot has no
`throttle_s`. Then `EbpApplication.onCreate → TriggerAlarms.reschedule →
timeSchedule()` re-offers the `at_ms` alarm (`oneShotCompleted==false`), which
`setExactAndAllowWhileIdle` fires immediately (past due) → **E2**. Emacs receives
E1 (replay) **and** E2 — two occurrences of a trigger that must fire exactly
once. Violates §21.5 ("MUST commit a completed marker in Section 21.2's
transaction … MUST NOT create another occurrence while that unchanged entry
remains registered") and §21.2 ("persist enough … to prevent a restart from
producing an immediate duplicate").

Two aggravations, both verified: (a) the **bare** `persistRecords()` throw
propagates out of `TimeAlarmReceiver.onReceive` (`TriggerAlarms.kt:51`)
*before* `reschedule` (`:52`) → the repeat/one-shot alarm is **never re-armed**
for the rest of the process lifetime (a silent halt), then double-fires on the
next cold start. (b) a **`drop`** one-shot has *zero* recovery coverage —
`recover()` scans `queue.events()`, but a drop leaves no queued event, so a
crash after the live fire but before B re-fires unrecoverably. `boot` is NOT
affected (the generation is re-recorded from the current value and the receiver
feeds boot once per generation, so the gate still suppresses).

**Fix:** in `recover()`, for each surviving `trigger.fired` whose registration
is a one-shot `time.at_ms` set `oneShotCompleted=true`, and floor `every_s`
`lastFireFloorMs` to `occurred_at_ms` (mirroring the throttle reconstruction);
guard the `commit`-path `persistRecords()` so its failure rolls back A (see
P1-2) rather than propagating out of a receiver. For the `drop` gap, persist the
completed marker crash-atomically with the fire decision (as `ReminderStore.markFired`
already does for reminders).

### P1-2 · A failed transaction B does not roll back the queued event A → the Companion claims remote admission on a failed durable transaction
*(transaction auditor; verified)*

`TriggerFiringService.admit()` Admitted branch runs `commit()` (B) with **no**
`try/catch` to delete A on throw (`:161-165`). `persistRecords()` can throw
(atomic `renameTo` failure, `TriggerBacking.kt`). On a B-throw, `on_fire` is
correctly skipped, but E stays durably queued — remote admission is effectively
**claimed** while the record write failed. Violates §21.2 ("If the durable
transaction fails, the Companion MUST NOT execute local responses or claim
remote admission"). Latent escalation: if any feed path ever *catches* the
throw and the process survives, the uncleared `pending_local` head permanently
withholds the pump (`CompanionEngine.kt:433`) → a wedged queue.

**Fix:** wrap `commit()` so a throw does `queue.deleteRecord(queue_seq)` before
propagating — true all-or-nothing for the A+B pair.

### P1-3 · `DurableQueue.inFlightSeq` is mutated from the engine outside the queue monitor → cross-monitor data race can drop an in-flight record
*(concurrency auditor; verified)*

`inFlightSeq` is a **public non-`@Volatile` `var`** (`DurableQueue.kt:30`). It is
read under the *queue* monitor in `admit()`'s compaction filter (`:79`),
`sweepExpired` (`:113`), `deleteRecord` (`:145`), but written/read from the
*engine* monitor at `CompanionEngine.kt:413,421,441,450`. There is **no common
lock and no happens-before** across the two monitors. `pumpAdvance` selects
`head()`=record 5 (`:434`, queue lock already released) and only *then* sets
`queue.inFlightSeq=5` (`:441`); in that window a device-source thread's
`admit()` with record 5's dedupe key sees `inFlightSeq` still un-set, treats
record 5 as not-in-flight, and **compacts it away**. The engine then delivers a
record that is already gone; on an error result `onPumpResult` retains the head
for retry (§15.3) but it no longer exists → never redelivered. **At-least-once
is broken.**

**Fix:** make `inFlightSeq` `private @Volatile`, touched only inside
`DurableQueue` `@Synchronized` methods; add an atomic `beginDelivery()` that
selects the deliverable head, skips `pending_local`, and marks in-flight in one
critical section (this also closes P2-4); `finishInFlight`/`releaseIfOwned` for
`onPumpResult`/`close`. The engine must never assign `queue.inFlightSeq`.

### P1-4 · Cold receivers run on the Android main thread; a live-connected fire does a synchronous socket write → `NetworkOnMainThreadException` crash
*(concurrency auditor; verified — the device matrix missed this because every W8-f fire happened while disconnected)*

`TriggerSources` registers the battery `BroadcastReceiver` with no handler
(`TriggerSources.kt:42`) → `onReceive` on the **main thread** → `firing.observeSample`
→ `runLocked` runs the deferred `pending` callbacks **synchronously on the same
thread**. When a session is live+`READY`, that callback is
`session.deliverLiveDrop`/`onDurableAdmitted` → `sendRequest` → the `DeviceBridge`
sink, which writes the socket **inline** (`DeviceBridge.kt:181-190`, comment:
"runs on whatever thread emits"). The renderer hooks avoid this via
`dispatchExecutor` (`:125`), but the firing path bypasses it entirely.
`NetworkOnMainThreadException` is a `RuntimeException`, so the sink's
`catch (java.io.IOException)` (`:187`) does **not** catch it → it propagates out
of `onReceive` → **app crash**. Same for `ReminderTapReceiver`,
`TimeAlarmReceiver`, `BootReceiver`. (Short of the crash, `observeSample` also
runs `persistRecords` file I/O and `capabilityHandler` vibrate/clipboard on the
main thread → StrictMode/ANR.)

**Fix:** give `TriggerFiringService` a single background executor and run its
`pending` callbacks on it (and/or `goAsync()` + worker in each receiver); the
engine's emitting `LiveSession` methods must never run on the main thread.

### P1-5 · Live-session slot lost-update: a superseded connection's clear can null out the newer session
*(concurrency auditor; verified)*

`TriggerFiringService.attach{session=s}` / `detach{if(session===s)session=null}`
(`:53-54`) is a non-atomic read-modify-write (`@Volatile` makes each access
atomic, not the compound). `CompanionStores.liveSession` is **set unsynchronized**
(`DeviceBridge.kt:194`) but **cleared synchronized** (`:235-237`) — so the lock
serializes nothing against the set. On §5.2 supersession (conn2 supersedes
conn1): conn1's `detach`/clear reads `=== engine1` (true, engine2 not yet
attached), then conn2 sets `engine2`, then conn1 writes `null` → `session==null`
while engine2 is live+`READY`. For engine2's whole lifetime, deferred
`deliverLiveDrop` sees null → **live `drop` events lost**; `onDurableAdmitted`
sees null → no wake/pump. The identical race on `CompanionStores.liveSession`
makes cold reminder taps treat a live session as offline.

**Fix:** hold each slot in an `AtomicReference`; `attach=set`,
`detach=compareAndSet(s,null)` (won't clobber a newer value); same for
`CompanionStores.liveSession` (`set` on connect, `compareAndSet(engine,null)` on
clear).

### P1-6 · Reminder notification + alarm identity ignores `owner` → a cross-owner same-id reminder loses its presentation permanently
*(reminders auditor; verified)*

Reminder ids are unique only *within an owner's set* (§18.6), so two owners
sharing an id is valid. But the Android notification identity is
`(tag="reminder", id=rid.hashCode())` — `owner` appears nowhere
(`Notifications.kt:98` post, `:168` cancel) — and the alarm request code is
`"$owner $id".hashCode()` (`:46`), a 32-bit `String.hashCode()` (trivially
collidable, e.g. `"Aa"`/`"BB"`; `AlarmManager` keys by requestCode +
`Intent.filterEquals`, which ignores extras). Consequences, both verified as
§18.6 present-once violations: `owner="a"` and `owner="b"` sharing `id="ping"`
→ b's fire **replaces** a's still-present notification; a is recorded fired and
skip-armed on restart → **a presents zero times**. And a reqCode collision
collapses two reminders to one alarm slot → the shadowed one never fires.

**Fix:** qualify the notification identity and the alarm request code by a
collision-resistant per-`(owner,id)` key (owner-qualified tag + a persisted
small-int allocation, or truncated SHA-256) rather than `String.hashCode()`.

---

## P1 — SPEC (amendments; the reference implementation trips over these)

### S1 · The device-lifetime firing/presentation authority — and what authorizes it with no session — is never modeled
*(SPEC-gaps auditor)*

§22.1 lists `triggers` / `reminders.owner` as **session** capabilities; §20.1
says "re-check authorization at … trigger-arm time"; §5.2 models only sessions
and defers "trigger execution" to a future profile. Yet §21.2 mandates firing
with **no `READY` session** and §21.1 mandates persistence across restarts. A
careful implementer can read §20.1/§22.1 as "no session ⇒ capability not granted
⇒ do not fire," directly contradicting §21.2. W8 resolves it the other way
(fire on durable-registration presence, no session gate) — a load-bearing,
silent interop divergence.

**Amendment (§21.1 new paragraph + one line in §5.2):** firing, durable
admission, `on_fire`, and reminder presentation are obligations of the Companion
as a **device-lifetime entity**, authorized by the persisted registration/set
itself (in force until replaced by an empty set, the pairing is revoked (§9.1),
or a required OS permission is withdrawn), not by an active session's capability
negotiation; a later session that does not re-grant MUST NOT by itself disarm
prior durable registrations; session supersession does not interrupt firing.
(The ttl bound is already adequate — an admitted queue/wake event's max wait is
`ttl_s` and the wait counts against it via `occurred_at_ms`; worth one clarifying
clause in §15.2, no more.)

### S2 · Catalog "Fire data" members are not normatively REQUIRED-present → the reference ships `time` with no `precision` and `timezone.changed` with no `tz`
*(SPEC-gaps + scheduling auditors; verified the impl emits empty `data`)*

§21.5's "Fire data" column shows `time → {precision}` and `timezone.changed →
{tz}`, but no clause makes those members required in the emitted `args.data`;
the only `precision` sentence is a MUST-**NOT** (don't over-claim), trivially
met by omission. So the impl emits `data:{}` for both
(`TriggerRuntime.fireScheduled` → `JSONObject()`, `TriggerAlarms.kt:71`), and
`inexact` has no defined tolerance — a consumer that reads `data.tz` or switches
on `data.precision` gets nothing. Both types are advertised.

**Amendment (§21.5):** every member in a type's Fire-data column is REQUIRED in
that occurrence's frozen `args.data` unless marked optional; `time.precision`
MUST be present, and MUST be `inexact` unless delivered on an exact-alarm
facility within an advertised bound. **Impl fix (P2-class):** populate `data.tz`
on `timezone.changed` and `data.precision` on `time` from the alarm class used.

---

## P2 — implementation

- **P2-1 · `every_s` alarm spin (RTC_WAKEUP storm).** *(scheduling; verified)*
  `lastFireFloorMs` advances only inside a successful `commit`; a boundary alarm
  that is **gated / throttled / QueueFull** returns before `emit`
  (`TriggerRuntime.kt:226,230`; `TriggerFiringService.kt:166`), so `reschedule`
  recomputes the **same past-due** boundary (`nextRepeatDueMs`) and
  `setExactAndAllowWhileIdle` fires it immediately → a tight wake/battery loop
  until the condition clears. Fix: advance the phase cursor on every elapsed
  boundary regardless of admission (compute next due off `max(lastFire, now)`).
- **P2-2 · `time.window` uses a `ZoneId` frozen at first `firing()`.** *(scheduling; verified — `CompanionStores.firing` never passes `zone`)* `BootReceiver` fires
  `timezone.changed` triggers but never updates the runtime's zone, so civil-time
  gates evaluate in the old zone until process restart (DST *within* a zone is
  correct; only a zone *change* goes stale). Fix: read `ZoneId.systemDefault()`
  per evaluation, or refresh on `TIMEZONE_CHANGED`.
- **P2-3 · No `MY_PACKAGE_REPLACED` receiver.** *(scheduling; verified in manifest)*
  An app update cancels all alarms and leaves the app stopped; `EbpApplication`
  re-arms only on the next process start, which post-update needs a manual
  launch → time alarms and reminders silently stop firing though the
  registrations persist (§21.1). Fix: add `MY_PACKAGE_REPLACED` to
  `BootReceiver`'s intent-filter (it already does exactly this work).
- **P2-4 · `pending_local` pump TOCTOU.** *(concurrency)* `pumpAdvance` checks
  `headIsPendingLocal()` (`:433`) then re-fetches `head()` (`:434`) without
  re-checking; a concurrent `admit` can compact + insert a `pending_local` head
  whose `on_fire` hasn't run → delivered before Step 4. Fixed by the same atomic
  `beginDelivery()` as P1-3.
- **P2-5 · Reminder tap dismisses the notification without safe admission.**
  *(reminders)* `ReminderTapReceiver` calls `routeReminderTap` with no callback
  then cancels unconditionally + `setAutoCancel(true)` (`Notifications.kt:107,173-180`);
  a `QueueFull`/`StorageFailed` or a `drop`-with-no-session tap is dropped yet
  the notification is already gone (§18.6 "dismiss only after safe admission" +
  §14.4). Fix: callback-gated cancel; drop `setAutoCancel`.
- **P2-6 · `recover()` mis-attributes throttle across pairings.** *(transaction;
  multi-pairing only)* the queued event carries no identity, so recovery floors
  the throttle of **every** identity holding that trigger id → a sibling pairing
  is spuriously throttled (over-suppression, never bypass). Fix: stamp the
  pairing identity on the queue record and match it in `recover()`.
- **P2-7 · Sensitive-payload plaintext / no encryption seam.** *(persistence +
  SPEC auditors; latent P1)* `FileQueueStore` writes uniform plaintext; a queued
  `sms.received`/`call.state` payload would land `{from,body}`/`{state,number}`
  in `ebp-queue.json` in the clear — a §21.5 MUST violation. **Not live today**
  (only `battery.level/boot/time/timezone.changed` are advertised; the validator
  rejects unadvertised types), but it becomes P1 the instant those sources are
  advertised. Fix before advertising: a sensitivity flag + keystore-backed
  encryption seam (`EncryptedFile`), and/or force `policy:"drop"` for `SENSITIVE`
  types until the seam exists.

## P2 — SPEC amendments
- **`every_s` coalescing is under-defined** — "at most one" permits zero-or-one
  and never says *when* the coalesced occurrence fires or the resumed phase; two
  conformant impls diverge. Amend: fire once promptly at rearm and resume on the
  original `anchor + k·interval` grid (do not re-phase to the delivery instant).
- **`time.at_ms` clock semantics** — which clock a *pending* one-shot fires
  against, and behavior under an NTP/manual clock change, are unspecified. Amend:
  absolute wall instant; fire when the effective clock (§15.2) first reaches
  `at_ms`; a forward jump fires promptly, a backward change neither retracts a
  completed one-shot nor advances an unfired one earlier than `at_ms`.
- **Sensitive-payload encryption boundary** — the MUST doesn't say *what* is
  encrypted (record? `args.data`? captured fields?) nor acknowledge the
  single-plaintext-queue design. Amend to name the boundary and permit
  non-sensitive records to stay plaintext.
- **Reminders are scoped to `owner`, never to the pairing identity** — unlike
  triggers/queue/shortcuts, §18.6 never partitions the durable format by pairing;
  §9.1 per-identity erase can't target one pairing's reminders. Amend §18.6 to
  require identity-partitioned reminder storage.
- **Boot with neither a generation nor a durable marker is unspecified** — the
  impl leaves `boot` **ungated** when `BOOT_COUNT` is null, relying on the
  broadcast arriving once; a redelivered broadcast double-fires. Amend: no
  generation and no durable marker ⇒ MUST NOT advertise `boot`; "broadcast
  delivered once" MUST NOT substitute for a durable gate.

---

## P3 — minor / latent / editorial
- `every_s`/boot anchor persist is best-effort (`runCatching`,
  `TriggerRuntime.kt:114`, added in W8-f) → a lost persist re-phases the cadence
  on restart (§21.5 "preserves acceptance anchor"). Consider a hard persist or
  deterministic reconstruction. *(persistence)*
- `recover()` clears `pending_local` without the §21.4-required diagnostic for
  the skipped `on_fire`. *(transaction)*
- `pendingExpired` replay-summary count is not durable → under-reports `expired`
  after a crash (observability only). *(persistence)*
- Service listener fields (`stateProvider`/`notifyListener`/`onTimeScheduleChanged`)
  are non-`@Volatile` (`TriggerFiringService.kt:43-49`); no live race today
  (set-once before the `@Volatile firingInstance` publish) but make them
  `@Volatile`. `executeOnFire` runs `capabilityHandler`+`persistRecords` under
  the service monitor. *(concurrency)*
- `at_ms` validation accepts a non-integer `Number` (Double `1.5` truncates;
  `CompanionEngine.kt:863-865`) — reject non-integral with `1201`. *(reminders)*
- `markFired` keys on the store's *current* `at_ms`, not the fired alarm's;
  narrow race if `at_ms` changes between fire and receipt. Carry `at_ms` in the
  alarm intent. *(reminders)*
- `USE_EXACT_ALARM` is Play-policy-restricted to alarm/calendar apps; a general
  companion may need `SCHEDULE_EXACT_ALARM` + `canScheduleExactAlarms()`.
  *(scheduling)*
- Boot generation `null→available` transition can silence the first real boot
  (arm records the now-current generation before the receiver fires). Narrow.
  *(scheduling)*
- A forward high-water excursion can durably reject a legitimately-future
  `at_ms` until real time passes it (fail-closed; robustness nit). *(scheduling)*
- Editorial SPEC notes: reminder `on_tap` defaults to `drop`, so a physically
  tapped-while-offline reminder is silently discarded (SHOULD-note authors to use
  `queue`/`wake`); a one-line §18.6 note that fired receipts are bounded by
  `max_reminders` (no separate GC). *(SPEC)*

---

## Verified sound (adversarially checked, no defect — recorded so it isn't re-litigated)
- **Atomic write path** (all four backings): `write → fd.sync() → renameTo →`
  best-effort dir fsync; temp is same-dir/same-FS; a mid-write crash preserves
  the prior fully-synced file; a cross-FS rename throws and keeps the old file.
  No torn-target bug.
- **TTL/expiry** is rollback-resistant: `expires = occurred + ttl`, swept before
  every delivery, `effectiveNow = max(clock, highWater)` with `highWater`
  persisted — a days-old queued event is correctly expired, a rollback can't
  un-expire it.
- **Single-instance-per-file**: `CompanionStores` is the sole constructor of
  every `File*Backing`; no `android:process`, so all receivers + the bridge share
  one process → one instance per file. No snapshot tearing.
- **`state.edge` baseline not persisted** is spec-*mandated* (§21.5/§21.6 silent
  re-establishment); a transition while dead is correctly missed.
- **Store-level restore-prior-and-rethrow** leaves in-memory == disk after a
  failed `replace`.
- **`every_s` coalescing math** fires the dead-window occurrence exactly once and
  resumes on phase (`k = elapsed/interval + 1`, past-due guarded); **unchanged
  carry-forward** keeps anchor/floor/one-shot/boot-receipt intact vs a fresh
  Registration for a changed id (§21.1); a completed one-shot stays in the
  set/`count` and never re-fires unchanged.
- **Reminder at-most-once state machine** and the **bounded fired set** (pruned
  on removal/`at_ms`-change, ⊆ live tuples ≤ `max_reminders`) — no leak; two
  auditors converged.
- **Deadlock-freedom**: the `runLocked`/`collect` deferral means the service
  never holds its monitor while calling a `LiveSession`; the `pending` list is
  concurrency-safe (snapshot-outside-lock); supersession of an in-flight deferred
  delivery resolves newest-wins via the `@Volatile session` read.
- **QueueFull/StorageFailed and event-size overflow** consume no throttle and run
  no `on_fire`; **drop** commits throttle+marker+`on_fire` with no session,
  remote gated to `READY`; the pump **waits** (not skips) on a `pending_local`
  head.

---

## Recommended fix order
1. **P1-4** (main-thread socket write — a live crash on the happy path) and
   **P1-1** (one-shot double-fire on crash) — the two that break real usage; both
   land as an atom with tests (a JVM crash-injection test for P1-1, a
   threading/executor test for P1-4).
2. **P1-3 + P2-4** together (the `beginDelivery()` refactor closes both), then
   **P1-5** (`AtomicReference` slots) and **P1-2** (A-rollback on B-failure) —
   the concurrency/transaction-atomicity cluster.
3. **P1-6 + P2-5** (reminder owner-scoping + tap-dismiss safety) — one
   presentation-layer atom.
4. **P2-1/P2-2/P2-3** (alarm spin, stale zone, `MY_PACKAGE_REPLACED`) — one
   scheduling-robustness atom.
5. **SPEC amendments S1, S2 + the five P2 SPEC items** — land in the contract
   repo (`ebp/llm-poc` slop-fork/main) as amendments #44+, then conform the impl
   (populate `tz`/`precision`; identity-scope reminders when multi-identity
   lands; encryption seam gated behind advertising `sms`/`call`).
6. P3 sweep.

---

## Remediation status (2026-07-23) — all P1s + P2s fixed

| Finding | Fix | Commit |
|---|---|---|
| P1-1 one-shot double-fire | recover() reconstructs oneShotCompleted/lastFireFloorMs | RA-2 `bff9166` |
| P1-2 txn-B no rollback | admit rolls back queued A on commit throw + in-memory restore | RA-4 `6004821` |
| P1-3 inFlightSeq race | private @Volatile + atomic beginDelivery() | RA-3 `9d1b049` |
| P1-4 main-thread crash | firing on a background executor; goAsync receivers | RA-1 `e069809` (device-verified) |
| P1-5 session-slot lost-update | AtomicReference slots (attach set / detach compareAndSet) | RA-4 `6004821` |
| P1-6 reminder owner-blind id | owner-scoped truncated-SHA-256 key for alarm/notif | RA-5 `6d34a94` |
| S1 firing authority (SPEC) | amendment #44 (§21.1/§5.2) | contract `e52b6a9` |
| S2 fire-data presence (SPEC+impl) | amendment #45 + emit tz/precision | contract `e52b6a9`, impl `af4f8cb` |
| P2-1 every_s alarm spin | cursor advances on every elapsed boundary | RA-6 `315d4a3` |
| P2-2 stale ZoneId | zone read fresh per evaluation | RA-6 `315d4a3` |
| P2-3 no MY_PACKAGE_REPLACED | added to BootReceiver | RA-6 `315d4a3` |
| P2-4 pending_local TOCTOU | folded into beginDelivery() | RA-3 `9d1b049` |
| P2-5 tap dismiss unsafe | callback-gated cancel; no setAutoCancel | RA-5 `6d34a94` |
| P2-6 multi-pairing throttle | trigger_identity stamped + matched in recover | RA-8 `9eb23f4` |
| P2-7 sensitive plaintext | validator refuses durable policy for sms/call | RA-8 `9eb23f4` |
| SPEC P2 ×5 (#46–#50) | every_s/at_ms/encryption/reminder-scope/boot amendments | contract `e52b6a9` |

Deferred P3s (rationale in RA-8's commit): markFired-carries-at_ms (~ms race),
recover() on_fire diagnostic (needs a log sink), pendingExpired durability
(cosmetic, §15.2 permits), USE_EXACT_ALARM (Play-policy note, not a functional
bug at minSdk 34), boot null→available (cannot occur where BOOT_COUNT exists).

Baseline after remediation: 192 wire tests / 26 elisp green; the P1-4 crash fix
device-verified (a live-connected battery fire delivers FIRED without crashing).
