// SPDX-License-Identifier: GPL-3.0-or-later
// The device-lifetime trigger firing service (SPEC 21.2). Owns the one
// TriggerRuntime + the durable TriggerStore + a reference to the durable
// queue, so firing works with NO live session: device sources feed
// observations here regardless of a socket, and an admitted occurrence's
// durable half (throttle/records + queued event) commits without a connection
// — the next session's replay delivers it. A live engine registers itself as
// the LiveSession (newest-wins slot) for live drop delivery and the wake/pump
// after a durable admit.
//
// Concurrency: public methods run the runtime under THIS monitor, collecting
// the live-session calls, and invoke them only AFTER the monitor is released.
// So the service never calls a LiveSession (engine monitor) while holding its
// own lock — the strict order is engine -> service -> queue, and DurableQueue
// is an internally-synchronized leaf.
package com.calebc42.ebp.wire

import java.time.ZoneId
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Read a JSON string array from `o[key]` as a Set (top-level so it can seed a
 * constructor default). A non-string entry is FILTERED, never an error — a
 * misdeclared device report costs one advertised name, not the whole set. */
fun jsonStringSet(o: JsonObject, key: String): Set<String> {
    val arr = o.arrOrNull(key) ?: return emptySet()
    return arr.mapNotNull { it.asStringOrNull() }.toSet()
}

/** SPEC 21.5: one host-armable time alarm — fire `triggerId` for `identity`
 * when the device wall clock reaches `dueMs`. */
data class TimeAlarm(val identity: String, val triggerId: String, val dueMs: Long)

class TriggerFiringService(
    val store: TriggerStore,
    private val queue: DurableQueue,
    private val maxEventBytes: Long,
    private val triggerCaps: Set<String> = emptySet(),
    private val capabilityHandler: CapabilityHandler? = null,
    private val zone: () -> ZoneId = { ZoneId.systemDefault() },
    /** SPEC 21.5: current device boot generation (Settings.Global.BOOT_COUNT). */
    private val bootGeneration: () -> String? = { null },
) {
    /** SPEC 21.3/21.7: current sample for a state type (gate/edge/window). */
    @Volatile var stateProvider: (String) -> JsonObject? = { null }
    /** SPEC 21.4: post a substituted local notification from an on_fire entry. */
    @Volatile var notifyListener: ((JsonObject) -> Unit)? = null
    /** SPEC 21.5: the time schedule changed (a set replaced time.* triggers) —
     * the Android host re-queries timeSchedule() and arms alarms. Invoked after
     * the service monitor is released; a no-op off-device. */
    @Volatile var onTimeScheduleChanged: (() -> Unit)? = null

    // Newest-wins live session (SPEC 5.2); read after releasing the monitor.
    // AtomicReference so attach/detach are atomic: a superseded connection's
    // detach (compareAndSet on itself) can never null out a newer session that
    // attached in between (the lost-update race of a plain volatile RMW).
    private val session = java.util.concurrent.atomic.AtomicReference<LiveSession?>()
    fun attach(s: LiveSession) { session.set(s) }
    fun detach(s: LiveSession) { session.compareAndSet(s, null) }

    private val runtime = TriggerRuntime(
        store, { queue.effectiveNow() }, zone, { stateProvider(it) },
        emit = ::admit, onFire = ::executeOnFire, persistRecords = store::persistRecords,
        bootGeneration = { bootGeneration() })

    // Live-session calls collected under the monitor, run after it is released.
    private val pending = ArrayList<() -> Unit>()

    private fun runLocked(block: () -> Unit) {
        collect(block).forEach { it() }
    }

    @Synchronized
    private fun collect(block: () -> Unit): List<() -> Unit> {
        pending.clear()
        block()
        return pending.toList()
    }

    // ------------------------------------------------ observation feed

    /** SPEC 21.5: a level-type observation from a device source (identity-
     * agnostic — fans out over every registered identity). Eligibility is the
     * presence of durable registrations, NO live-session gate (SPEC 21.1/21.2). */
    fun observeSample(type: String, sample: JsonObject) =
        runLocked { store.identities().forEach { runtime.onSample(it, type, sample) } }

    /** SPEC 21.5: an external occurrence (package/sms/boot/time/timezone/manual). */
    fun observeExternal(type: String, data: JsonObject) =
        runLocked { store.identities().forEach { runtime.onExternal(it, type, data) } }

    /** SPEC 21.5 (manual): fire exactly the named manual registration. */
    fun fireManual(identity: String, triggerId: String, source: String) =
        runLocked { runtime.fireManual(identity, triggerId,
            buildJsonObject { put("source", source) }) }

    /** SPEC 21.5 (time): a host alarm for exactly this time.* registration
     * elapsed — fire only it (each time entry has its own due time). The fire
     * data carries `precision` (SPEC 21.5 fire-data): the host arms
     * setExactAndAllowWhileIdle, whose Doze / allow-while-idle quota MAY defer
     * it, so the honest never-over-claimed value is `inexact`. */
    fun fireScheduled(identity: String, triggerId: String) =
        runLocked { runtime.fireScheduled(identity, triggerId,
            buildJsonObject { put("precision", "inexact") }) }

    /** SPEC 21.5: every time.* registration that still needs a host alarm, with
     * its next due wall-clock ms. A completed one-shot time.at_ms is omitted; a
     * repeating time.every_s reports its next occurrence (possibly already past,
     * i.e. immediately due — the host arms it now and fireScheduled coalesces).
     * The Android host arms one alarm per entry and re-queries after each fire
     * and on boot/time-change. */
    @Synchronized
    fun timeSchedule(): List<TimeAlarm> {
        val out = ArrayList<TimeAlarm>()
        for (identity in store.identities()) for (reg in store.registrations(identity)) {
            if (reg.entry.reqString("type") != "time") continue
            val params = reg.entry.objOrNull("params") ?: continue
            val due = when {
                "at_ms" in params -> if (reg.oneShotCompleted) null else params.reqLong("at_ms")
                "every_s" in params -> TriggerRuntime.nextRepeatDueMs(reg)
                else -> null
            }
            if (due != null) out.add(TimeAlarm(identity, reg.entry.reqString("id"), due))
        }
        return out
    }

    /** SPEC 21.5: silently baseline this identity's new/changed registrations. */
    @Synchronized
    fun armBaselines(identity: String) = runtime.armBaselines(identity)

    /** SPEC 21.5: re-establish silent baselines for every stored identity —
     * called at process start after the sticky sources have seeded state. */
    @Synchronized
    fun armAllBaselines() { store.identities().forEach { runtime.armBaselines(it) } }

    /** SPEC 21.1: replace an identity's set (durable) then re-baseline the
     * new/changed registrations. Throws on storage failure. The host time-alarm
     * re-arm runs after the monitor is released (it re-enters timeSchedule). */
    fun replaceSet(identity: String, entries: List<JsonObject>): Int {
        val count = synchronized(this) {
            store.replace(identity, entries).also { runtime.armBaselines(identity) }
        }
        // LD-16: the set is already durably committed and armed — a throw
        // from the host's alarm-reschedule callout must not travel back into
        // handleTriggersSet's catch and be reported as "Storage failed",
        // leaving Emacs believing the PRIOR set is in force while the new
        // one is live (SPEC 21.1). Cold-start re-arm recovers alarms anyway.
        runCatching { onTimeScheduleChanged?.invoke() }
        return count
    }

    // ---------------------------------------------- admission (SPEC 21.2)

    // Moved from the engine: build the context-less trigger.fired, run the
    // durable half here, DEFER the live half. `commit` (throttle + persist +
    // on_fire) runs only for a durably-admitted occurrence.
    private fun admit(reg: TriggerStore.Registration, data: JsonObject, commit: () -> Unit) {
        val entry = reg.entry
        val args = buildJsonObject {
            put("id", entry.reqString("id"))
            put("type", entry.reqString("type"))
            put("data", data)
        }
        val policy = entry.reqString("policy")
        // C3: one build instead of build-then-mutate — a JsonObject is
        // immutable, so `queued_at_ms` joins the same builder rather than being
        // appended to a live object. Member order is unchanged.
        val params = buildJsonObject {
            put("event_id", EbpAuth.generateNonce())
            put("action", "trigger.fired")
            put("occurred_at_ms", queue.effectiveNow())
            put("args", args)
            if (policy == "queue" || policy == "wake")
                put("queued_at_ms", queue.effectiveNow())
        }
        // An event that cannot be created is a failed admission: commit nothing.
        if (params.toString().toByteArray(Charsets.UTF_8).size > maxEventBytes) return
        val hasLocal = entry.reqArr("on_fire").size > 0
        when (policy) {
            "queue", "wake" -> when (val r = queue.admit(params, policy,
                    entry.stringOr("dedupe").takeIf { it.isNotEmpty() },
                    entry.reqLong("ttl_s"), pendingLocal = hasLocal,
                    triggerIdentity = reg.identity)) {
                is AdmitResult.Admitted -> {
                    // SPEC 21.2: A (the event record) is committed. If B (throttle
                    // + records + on_fire) fails, roll A back so a failed durable
                    // transaction never claims remote admission; commit() restores
                    // its in-memory records before it rethrows.
                    try {
                        commit() // step 3 (throttle + persist) + step 4 (on_fire)
                    } catch (_: Exception) {
                        queue.deleteRecord(r.record.reqLong("queue_seq"))
                        return
                    }
                    if (hasLocal) queue.clearPendingLocal(r.record.reqLong("queue_seq"))
                    pending.add { session.get()?.onDurableAdmitted(policy) } // step 5, post-lock
                }
                else -> Unit // durable transaction failed: no throttle, no on_fire
            }
            // SPEC 21.2: a drop commits throttle + on_fire even with no session;
            // only the remote event is READY-gated (deferred, post-lock). A commit
            // failure (nothing durable to roll back) is swallowed so one identity's
            // storage error never aborts the fan-out over the others.
            else -> {
                try { commit() } catch (_: Exception) { return }
                pending.add { session.get()?.deliverLiveDrop(params, null) }
            }
        }
    }

    // SPEC 21.4: execute one already-substituted on_fire entry (moved from the
    // engine). A notify posts through the host; a cap re-checks trigger_caps
    // membership + its Args schema and runs through the same executor as
    // capability.invoke. Every failure mode is a safe no-op.
    private fun executeOnFire(entry: JsonObject) {
        if ("notify" in entry) {
            notifyListener?.invoke(entry.reqObj("notify"))
            return
        }
        val cap = entry.reqString("cap")
        if (cap !in triggerCaps) return
        val args = entry.objOrNull("args") ?: JsonObject(emptyMap())
        try {
            CapabilityCatalog.validateArgs(cap, args)
        } catch (e: ContentInvalid) {
            return
        }
        capabilityHandler?.invoke(cap, args)
    }

    // -------------------------------------------------- recovery (SPEC 21.2)

    /**
     * SPEC 21.2/21.4: at process start, resolve any occurrence a crash left
     * mid-transaction. (1) Clear every pending-local marker so its remote event
     * becomes eligible — recovery MUST NOT strand a remote event because a
     * local effect cannot be proven; the skipped local effect is the accepted
     * cost. (2) Reconstruct each registration's runtime records from surviving
     * queued trigger.fired records so an A-committed/B-lost window (the queue
     * event durably written but the record write lost to a crash) cannot re-fire
     * after restart: floor the throttle, AND — critically for the un-throttled
     * cases — re-assert a one-shot's completion and a repeat's last-fire floor,
     * which a bare throttle floor does not cover (SPEC 21.5: the completion
     * marker MUST survive; a completed one-shot MUST NOT create another
     * occurrence). A `drop` needs no coverage here: its marker persists before
     * any live delivery, so no torn window exists.
     */
    @Synchronized
    fun recover() {
        for ((seq, _) in queue.pendingLocalRecords()) queue.clearPendingLocal(seq)
        var changed = false
        for ((recIdentity, event) in queue.firedRecords()) {
            if (event.stringOr("action") != "trigger.fired") continue
            val a = event.objOrNull("args") ?: continue
            val id = a.stringOr("id")
            val occurred = event.longOr("occurred_at_ms", 0)
            // Scope to the firing pairing when the record carries it; fall back
            // to every identity for a record admitted before identity-stamping.
            val identities = recIdentity?.let { listOf(it) } ?: store.identities()
            for (identity in identities) {
                val reg = store.registration(identity, id) ?: continue
                if (occurred > (reg.throttleFloorMs ?: Long.MIN_VALUE)) {
                    reg.throttleFloorMs = occurred; changed = true
                }
                val params = reg.entry.objOrNull("params")
                if (reg.entry.reqString("type") == "time" && params != null) {
                    if ("at_ms" in params && !reg.oneShotCompleted) {
                        reg.oneShotCompleted = true; changed = true
                    } else if ("every_s" in params &&
                        occurred > (reg.lastFireFloorMs ?: Long.MIN_VALUE)) {
                        reg.lastFireFloorMs = occurred; changed = true
                    }
                }
            }
        }
        if (changed) runCatching { store.persistRecords() }
    }
}
