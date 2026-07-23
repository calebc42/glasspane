// SPDX-License-Identifier: GPL-3.0-or-later
// The SPEC 15 durable event queue: admission with per-pairing queue_seq
// FIFO, dedupe as queue compaction, rollback-proof expiry, and the
// capacity limits — all over an atomic-replace QueueStore.
package com.calebc42.ebp.wire

import org.json.JSONObject

sealed class AdmitResult {
    /** The complete durable record, already committed. */
    data class Admitted(val record: JSONObject) : AdmitResult()
    /** SPEC 15.1: capacity exhaustion, the 1601 queue-full equivalent. */
    object QueueFull : AdmitResult()
    /** SPEC 15.1: storage failed — the interaction was NOT queued. */
    object StorageFailed : AdmitResult()
}

/** SPEC 15.3/21.2: the atomic outcome of selecting the next event to deliver.
 * Folding head-selection, the pending-local gate, and the SYNCING replay barrier
 * into one critical section — together with the in-flight mark — closes the
 * TOCTOU where a concurrent admit could compact a head between select and mark. */
sealed class Delivery {
    /** Ready to send; the record is now marked in-flight. */
    data class Ready(val record: JSONObject) : Delivery()
    /** Queue empty — a replay concludes. */
    object Empty : Delivery()
    /** Head is still running its on_fire (SPEC 21.2) — wait, do not conclude. */
    object PendingLocal : Delivery()
    /** Head is a newly generated event beyond the replay barrier — conclude. */
    object BarrierHeld : Delivery()
}

class DurableQueue(
    private val store: QueueStore,
    private val maxEvents: Long,
    private val maxBytes: Long,
    var clock: () -> Long = System::currentTimeMillis,
) {
    private var records: MutableList<JSONObject>
    private var nextSeq: Long
    private var highWater: Long

    /** queue_seq of the record currently in flight, runtime-only: after a
     * process death nothing is in flight (SPEC 15.3). Private + touched only
     * under this monitor — the engine drives it via beginDelivery/clearInFlight
     * so it is never raced across the engine and queue monitors. */
    @Volatile private var inFlightSeq: Long? = null

    /** Expiry deletions not yet reported in a replay summary (SPEC 15.2:
     * counted in the NEXT summary). In-memory: informational count. */
    var pendingExpired: Int = 0
        private set

    init {
        val snapshot = store.load()
        records = snapshot.records.toMutableList()
        nextSeq = snapshot.nextSeq
        highWater = snapshot.clockHighWater
    }

    /** SPEC 15.2: the effective wall clock never runs backwards. */
    @Synchronized
    fun effectiveNow(): Long = maxOf(clock(), highWater)

    @Synchronized
    fun count(): Int = records.size

    @Synchronized
    fun head(): JSONObject? = records.minByOrNull { it.getLong("queue_seq") }

    /**
     * SPEC 15.3/21.2: atomically pick the next deliverable head and mark it
     * in-flight, all under this monitor. Sweeps expired first; a pending-local
     * head yields PendingLocal (the pump waits, does NOT conclude), a head at or
     * beyond `barrierSeq` (the SYNCING replay barrier; null = no barrier) yields
     * BarrierHeld, an empty queue yields Empty. Only `Ready` sets the in-flight
     * mark — so no concurrent `admit` can compact the selected record between
     * selection and the mark (the old head()+assign race). The caller MUST
     * `clearInFlight(seq)` when the delivery reaches a permanent result.
     */
    @Synchronized
    fun beginDelivery(barrierSeq: Long?): Delivery {
        sweepExpired()
        val record = records.minByOrNull { it.getLong("queue_seq") } ?: return Delivery.Empty
        if (record.optBoolean("pending_local")) return Delivery.PendingLocal
        if (barrierSeq != null && record.getLong("queue_seq") >= barrierSeq)
            return Delivery.BarrierHeld
        inFlightSeq = record.getLong("queue_seq")
        return Delivery.Ready(record)
    }

    /** SPEC 15.3: is a record in flight (a replay must join, not duplicate it). */
    @Synchronized
    fun hasInFlight(): Boolean = inFlightSeq != null

    /** Release the in-flight marker iff it is still `seq` — owner-safe and
     * idempotent, so a stale releaser (a superseded connection's close) cannot
     * clear a newer delivery's marker. */
    @Synchronized
    fun clearInFlight(seq: Long?) { if (seq != null && inFlightSeq == seq) inFlightSeq = null }

    private fun persist() =
        store.replace(QueueSnapshot(records.toList(), nextSeq, highWater))

    /**
     * SPEC 15.1: one durable transaction covering dedupe compaction,
     * counter advance, and record insertion. EVENT is the complete
     * event.action params (delivery payload, event_id, captured fields,
     * occurred_at_ms, queued_at_ms).
     */
    @Synchronized
    fun admit(event: JSONObject, policy: String, dedupe: String?,
              ttlSeconds: Long, pendingLocal: Boolean = false): AdmitResult {
        val now = effectiveNow()
        val record = JSONObject()
            .put("event", event)
            .put("policy", policy)
            .put("expires_at_ms", event.getLong("occurred_at_ms") + ttlSeconds * 1000)
            .also { if (dedupe != null) it.put("dedupe", dedupe) }
            // SPEC 21.2: a pending-local record is not yet eligible for remote
            // delivery — the pump waits on it until on_fire completes (clear).
            .also { if (pendingLocal) it.put("pending_local", true) }
        // SPEC 15.2: replace older queued, non-in-flight, same-key events.
        val kept = if (dedupe == null) records.toMutableList()
        else records.filterNot {
            it.optString("dedupe", "") == dedupe &&
                it.getLong("queue_seq") != (inFlightSeq ?: -1L)
        }.toMutableList()
        // SPEC 15.4: enforce both capacity limits atomically at admission.
        record.put("queue_seq", nextSeq)
        val prospectiveBytes = kept.sumOf { it.toString().toByteArray(Charsets.UTF_8).size } +
            record.toString().toByteArray(Charsets.UTF_8).size
        if (kept.size >= maxEvents || prospectiveBytes > maxBytes)
            return AdmitResult.QueueFull
        val savedRecords = records
        val savedSeq = nextSeq
        val savedWater = highWater
        return try {
            records = kept
            records.add(record)
            nextSeq += 1
            if (clock() > highWater) highWater = clock()
            persist()
            AdmitResult.Admitted(record)
        } catch (_: Exception) {
            // SPEC 15.1: storage failure MUST NOT claim the queueing.
            records = savedRecords
            nextSeq = savedSeq
            highWater = savedWater
            AdmitResult.StorageFailed
        }
    }

    /** SPEC 15.2: delete expired records before delivery; rollback-proof
     * via the durable high-water mark. Returns the number deleted. */
    @Synchronized
    fun sweepExpired(): Int {
        val now = effectiveNow()
        val (expired, kept) = records.partition {
            it.getLong("expires_at_ms") <= now &&
                it.getLong("queue_seq") != (inFlightSeq ?: -1L)
        }
        if (expired.isEmpty() && now <= highWater) return 0
        records = kept.toMutableList()
        if (now > highWater) highWater = now
        try {
            persist()
        } catch (_: Exception) {
            // Deletion that fails to persist re-runs next sweep; keep the
            // in-memory view honest either way.
        }
        pendingExpired += expired.size
        return expired.size
    }

    /** Consume the accumulated expiry count for a replay summary. */
    @Synchronized
    fun takeExpiredCount(): Int = pendingExpired.also { pendingExpired = 0 }

    /** The next queue_seq to be assigned — the session-barrier boundary:
     * records at or above a snapshot of this value are newly generated
     * relative to that snapshot (SPEC 10.3/15.3). */
    @Synchronized
    fun boundarySeq(): Long = nextSeq

    /** SPEC 15.3: delete only after a permanent result. A failed persist
     * leaves the record durable; redelivery is answered `duplicate' by
     * the Emacs receipt store (14.4), so at-least-once holds either way. */
    @Synchronized
    fun deleteRecord(seq: Long) {
        if (records.removeAll { it.getLong("queue_seq") == seq })
            runCatching { persist() }
        if (inFlightSeq == seq) inFlightSeq = null
    }

    /** True while the lowest-seq record is still running its on_fire (SPEC
     * 21.2): the pump MUST wait rather than deliver ahead of Step 4. */
    @Synchronized
    fun headIsPendingLocal(): Boolean = head()?.optBoolean("pending_local") == true

    /** SPEC 21.2: clear a record's pending-local marker once its on_fire has
     * completed (or recovery has resolved it), making it deliverable. */
    @Synchronized
    fun clearPendingLocal(seq: Long) {
        records.firstOrNull { it.getLong("queue_seq") == seq }
            ?.takeIf { it.has("pending_local") }
            ?.let { it.remove("pending_local"); runCatching { persist() } }
    }

    /** SPEC 21.2 recovery: every record still marked pending-local (a crash
     * during on_fire). Returns their (queue_seq, event) so the firing service
     * can resume/resolve them, then clear the markers. */
    @Synchronized
    fun pendingLocalRecords(): List<Pair<Long, JSONObject>> =
        records.filter { it.optBoolean("pending_local") }
            .map { it.getLong("queue_seq") to it.getJSONObject("event") }

    /** A read-only snapshot of the queued event payloads (for SPEC 21.2
     * throttle reconstruction at recovery). */
    @Synchronized
    fun events(): List<JSONObject> = records.map { it.getJSONObject("event") }
}
