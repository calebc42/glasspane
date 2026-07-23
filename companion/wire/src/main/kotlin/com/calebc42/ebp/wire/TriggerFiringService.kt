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
import org.json.JSONObject

/** Read a JSON string array from `o[key]` as a Set (top-level so it can seed a
 * constructor default). */
fun jsonStringSet(o: JSONObject, key: String): Set<String> {
    val arr = o.optJSONArray(key) ?: return emptySet()
    return (0 until arr.length()).mapNotNull { arr.opt(it) as? String }.toSet()
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
    @Volatile var stateProvider: (String) -> JSONObject? = { null }
    /** SPEC 21.4: post a substituted local notification from an on_fire entry. */
    @Volatile var notifyListener: ((JSONObject) -> Unit)? = null
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
    fun observeSample(type: String, sample: JSONObject) =
        runLocked { store.identities().forEach { runtime.onSample(it, type, sample) } }

    /** SPEC 21.5: an external occurrence (package/sms/boot/time/timezone/manual). */
    fun observeExternal(type: String, data: JSONObject) =
        runLocked { store.identities().forEach { runtime.onExternal(it, type, data) } }

    /** SPEC 21.5 (manual): fire exactly the named manual registration. */
    fun fireManual(identity: String, triggerId: String, source: String) =
        runLocked { runtime.fireManual(identity, triggerId, JSONObject().put("source", source)) }

    /** SPEC 21.5 (time): a host alarm for exactly this time.* registration
     * elapsed — fire only it (each time entry has its own due time). */
    fun fireScheduled(identity: String, triggerId: String) =
        runLocked { runtime.fireScheduled(identity, triggerId, JSONObject()) }

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
            if (reg.entry.getString("type") != "time") continue
            val params = reg.entry.optJSONObject("params") ?: continue
            val due = when {
                params.has("at_ms") -> if (reg.oneShotCompleted) null else params.getLong("at_ms")
                params.has("every_s") -> TriggerRuntime.nextRepeatDueMs(reg)
                else -> null
            }
            if (due != null) out.add(TimeAlarm(identity, reg.entry.getString("id"), due))
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
    fun replaceSet(identity: String, entries: List<JSONObject>): Int {
        val count = synchronized(this) {
            store.replace(identity, entries).also { runtime.armBaselines(identity) }
        }
        onTimeScheduleChanged?.invoke()
        return count
    }

    // ---------------------------------------------- admission (SPEC 21.2)

    // Moved from the engine: build the context-less trigger.fired, run the
    // durable half here, DEFER the live half. `commit` (throttle + persist +
    // on_fire) runs only for a durably-admitted occurrence.
    private fun admit(reg: TriggerStore.Registration, data: JSONObject, commit: () -> Unit) {
        val entry = reg.entry
        val args = JSONObject().put("id", entry.getString("id"))
            .put("type", entry.getString("type")).put("data", data)
        val params = JSONObject()
            .put("event_id", EbpAuth.generateNonce())
            .put("action", "trigger.fired")
            .put("occurred_at_ms", queue.effectiveNow()).put("args", args)
        val policy = entry.getString("policy")
        if (policy == "queue" || policy == "wake")
            params.put("queued_at_ms", queue.effectiveNow())
        // An event that cannot be created is a failed admission: commit nothing.
        if (params.toString().toByteArray(Charsets.UTF_8).size > maxEventBytes) return
        val hasLocal = entry.getJSONArray("on_fire").length() > 0
        when (policy) {
            "queue", "wake" -> when (val r = queue.admit(params, policy,
                    entry.optString("dedupe").takeIf { it.isNotEmpty() },
                    entry.getLong("ttl_s"), pendingLocal = hasLocal)) {
                is AdmitResult.Admitted -> {
                    // SPEC 21.2: A (the event record) is committed. If B (throttle
                    // + records + on_fire) fails, roll A back so a failed durable
                    // transaction never claims remote admission; commit() restores
                    // its in-memory records before it rethrows.
                    try {
                        commit() // step 3 (throttle + persist) + step 4 (on_fire)
                    } catch (_: Exception) {
                        queue.deleteRecord(r.record.getLong("queue_seq"))
                        return
                    }
                    if (hasLocal) queue.clearPendingLocal(r.record.getLong("queue_seq"))
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
    private fun executeOnFire(entry: JSONObject) {
        if (entry.has("notify")) {
            notifyListener?.invoke(entry.getJSONObject("notify"))
            return
        }
        val cap = entry.getString("cap")
        if (cap !in triggerCaps) return
        val args = entry.optJSONObject("args") ?: JSONObject()
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
        for (event in queue.events()) {
            if (event.optString("action") != "trigger.fired") continue
            val a = event.optJSONObject("args") ?: continue
            val id = a.optString("id")
            val occurred = event.optLong("occurred_at_ms", 0)
            for (identity in store.identities()) {
                val reg = store.registration(identity, id) ?: continue
                if (occurred > (reg.throttleFloorMs ?: Long.MIN_VALUE)) {
                    reg.throttleFloorMs = occurred; changed = true
                }
                val params = reg.entry.optJSONObject("params")
                if (reg.entry.getString("type") == "time" && params != null) {
                    if (params.has("at_ms") && !reg.oneShotCompleted) {
                        reg.oneShotCompleted = true; changed = true
                    } else if (params.has("every_s") &&
                        occurred > (reg.lastFireFloorMs ?: Long.MIN_VALUE)) {
                        reg.lastFireFloorMs = occurred; changed = true
                    }
                }
            }
        }
        if (changed) runCatching { store.persistRecords() }
    }
}
