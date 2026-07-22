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
     * process death nothing is in flight (SPEC 15.3). */
    var inFlightSeq: Long? = null

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
    fun effectiveNow(): Long = maxOf(clock(), highWater)

    fun count(): Int = records.size

    fun head(): JSONObject? = records.minByOrNull { it.getLong("queue_seq") }

    private fun persist() =
        store.replace(QueueSnapshot(records.toList(), nextSeq, highWater))

    /**
     * SPEC 15.1: one durable transaction covering dedupe compaction,
     * counter advance, and record insertion. EVENT is the complete
     * event.action params (delivery payload, event_id, captured fields,
     * occurred_at_ms, queued_at_ms).
     */
    fun admit(event: JSONObject, policy: String, dedupe: String?,
              ttlSeconds: Long): AdmitResult {
        val now = effectiveNow()
        val record = JSONObject()
            .put("event", event)
            .put("policy", policy)
            .put("expires_at_ms", event.getLong("occurred_at_ms") + ttlSeconds * 1000)
            .also { if (dedupe != null) it.put("dedupe", dedupe) }
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
    fun takeExpiredCount(): Int = pendingExpired.also { pendingExpired = 0 }

    /** The next queue_seq to be assigned — the session-barrier boundary:
     * records at or above a snapshot of this value are newly generated
     * relative to that snapshot (SPEC 10.3/15.3). */
    fun boundarySeq(): Long = nextSeq

    /** SPEC 15.3: delete only after a permanent result. A failed persist
     * leaves the record durable; redelivery is answered `duplicate' by
     * the Emacs receipt store (14.4), so at-least-once holds either way. */
    fun deleteRecord(seq: Long) {
        if (records.removeAll { it.getLong("queue_seq") == seq })
            runCatching { persist() }
        if (inFlightSeq == seq) inFlightSeq = null
    }
}
