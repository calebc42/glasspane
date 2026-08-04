// SPDX-License-Identifier: GPL-3.0-or-later
// Storage-neutral durable state for the Kotlin EBP implementation. These
// types deliberately contain no Room, Android, Jetpacs, renderer, or JVM API.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

/** EBP Section 4.2's largest non-negative integer, including timestamps. */
const val EBP_MAX_SAFE_INTEGER: Long = 9_007_199_254_740_991L

fun requireEbpTimestamp(value: Long, name: String) {
    require(value in 0..EBP_MAX_SAFE_INTEGER) {
        "$name must be a non-negative EBP safe integer"
    }
}

/** Opaque pairing partition key. Authentication material is not EBP state. */
data class PairingId(val value: String) {
    init {
        require(PAIRING_ID.matches(value)) { "pairing id must be 32 lowercase hex digits" }
    }
}
/** Stable 16-octet durable delivery identifier from EBP Section 14.4. */
data class EventId(val value: String) {
    init {
        require(EVENT_ID.matches(value)) { "event id must be 32 lowercase hex digits" }
    }
}
private val EVENT_ID = Regex("[0-9a-f]{32}")

private val PAIRING_ID = Regex("[0-9a-f]{32}")

/** Durable admission fence. REVOKING is never implicitly made ACTIVE again. */
enum class PairingFence { ACTIVE, REVOKING }

data class DurablePairing(
    val id: PairingId,
    val fence: PairingFence,
    val createdAtMs: Long,
) {
    init { requireEbpTimestamp(createdAtMs, "createdAtMs") }
}

/** Pairing-local counters which must survive process death. */
data class PairingRuntime(
    val nextQueueSequence: Long = 1,
    val nextSurfaceOrdinal: Long = 1,
    val effectiveClockHighWaterMs: Long = 0,
    val clockForwardClaimWallMs: Long? = null,
    val clockForwardClaimMonotonicStartedMs: Long? = null,
    val clockForwardClaimBootId: String? = null,
    val readyDisconnectedAtMs: Long? = null,
) {
    init {
        require(nextQueueSequence >= 1)
        require(nextSurfaceOrdinal >= 1)
        require(effectiveClockHighWaterMs >= 0)
        require(clockForwardClaimWallMs == null || clockForwardClaimWallMs >= 0)
        require(
            clockForwardClaimMonotonicStartedMs == null ||
                clockForwardClaimMonotonicStartedMs >= 0,
        )
        require(clockForwardClaimBootId == null || clockForwardClaimBootId.isNotBlank())
        require(
            (
                clockForwardClaimWallMs == null &&
                    clockForwardClaimMonotonicStartedMs == null &&
                    clockForwardClaimBootId == null
                ) || (
                clockForwardClaimWallMs != null &&
                    clockForwardClaimMonotonicStartedMs != null &&
                    clockForwardClaimBootId != null
                ),
        ) {
            "forward-clock claim values must all be present or all be absent"
        }
        require(readyDisconnectedAtMs == null || readyDisconnectedAtMs >= 0)
    }
}

/**
 * Accepted EBP surface state. A tombstone retains its revision and first-seen
 * position but no presentation payload. [spec] is raw accepted protocol state,
 * not renderer IR.
 */
data class DurableSurfaceRecord(
    val surfaceId: String,
    val revision: Long,
    val present: Boolean,
    val spec: JsonObject?,
    val staleSpec: JsonObject? = null,
    val staleAfterSeconds: Long? = null,
    val currentView: String? = null,
    val acceptedAtMs: Long,
    val firstSeenOrdinal: Long,
) {
    init {
        require(surfaceId.isNotBlank())
        require(revision >= 0)
        require(acceptedAtMs >= 0)
        require(firstSeenOrdinal >= 1)
        if (present) {
            requireNotNull(spec) { "a present surface requires its accepted spec" }
            require(staleAfterSeconds == null || staleAfterSeconds > 0)
        } else {
            require(spec == null && staleSpec == null && staleAfterSeconds == null && currentView == null) {
                "a tombstone retains no presentation payload"
            }
        }
    }
}
/** Lightweight aggregate used for revision/limit decisions without specs. */
data class SurfaceCardinality(val total: Long, val present: Long) {
    init {
        require(total >= 0)
        require(present >= 0 && present <= total)
    }
}


/** JSON null is represented by JsonNull; row absence means no draft. */
data class DurableDraft(
    val surfaceId: String,
    val nodeId: String,
    val value: JsonElement,
) {
    init {
        require(surfaceId.isNotBlank())
        require(nodeId.isNotBlank())
    }
}

enum class DurableOutboxPolicy { QUEUE, WAKE }

/** Complete immutable payload and metadata for one durable event occurrence. */
data class DurableOutboxEvent(
    val queueSequence: Long,
    val eventId: EventId,
    val payload: JsonObject,
    val policy: DurableOutboxPolicy,
    val occurredAtMs: Long,
    val queuedAtMs: Long,
    val expiresAtMs: Long,
    val dedupeKey: String? = null,
    val accountedBytes: Long,
    val pendingLocal: Boolean = false,
    val triggerIdentity: String? = null,
) {
    init {
        require(queueSequence >= 1)
        requireEbpTimestamp(occurredAtMs, "occurredAtMs")
        requireEbpTimestamp(queuedAtMs, "queuedAtMs")
        requireEbpTimestamp(expiresAtMs, "expiresAtMs")
        require(queuedAtMs >= occurredAtMs)
        require(expiresAtMs >= queuedAtMs)
        require(accountedBytes > 0)
        require(dedupeKey == null || dedupeKey.isNotBlank())
        require(triggerIdentity == null || triggerIdentity.isNotBlank())
        requireAuthoritativeEventPayload(payload, eventId, occurredAtMs, queuedAtMs)
    }
}
/** Indexed queue metadata; admission and expiry do not need decrypted payloads. */
data class DurableOutboxIndexEntry(
    val queueSequence: Long,
    val eventId: EventId,
    val expiresAtMs: Long,
    val dedupeKey: String?,
    val accountedBytes: Long,
) {
    init {
        require(queueSequence >= 1 && accountedBytes > 0)
        requireEbpTimestamp(expiresAtMs, "expiresAtMs")
    }
}

/**
 * Store-owned, opaque preparation for one admission attempt. Platform
 * implementations keep ciphertext, key handles, and storage generations in
 * their private implementation; portable reducers can only pass the
 * capability back to the transaction that receives it.
 */
interface PreparedOutboxAdmission {
    val pairingId: PairingId
    val eventId: EventId
}


/**
 * Pairing-scoped record that prevents a delivered or otherwise removed queue
 * row from erasing EventId idempotency. It is independent of outbox lifetime.
 */
data class IssuedEventId(
    val eventId: EventId,
    val issuedAtMs: Long,
    val reusableAfterMs: Long,
) {
    init {
        requireEbpTimestamp(issuedAtMs, "issuedAtMs")
        requireEbpTimestamp(reusableAfterMs, "reusableAfterMs")
        require(reusableAfterMs >= issuedAtMs)
    }
}

/** Immutable restore result, ordered exactly as protocol reducers consume it. */
data class DurableSnapshot(
    val pairing: DurablePairing?,
    val runtime: PairingRuntime,
    val surfaces: List<DurableSurfaceRecord>,
    val drafts: List<DurableDraft>,
    val outbox: List<DurableOutboxEvent>,
    val issuedEventIds: List<IssuedEventId>,
) {
    companion object {
        fun empty(): DurableSnapshot = DurableSnapshot(
            pairing = null,
            runtime = PairingRuntime(),
            surfaces = emptyList(),
            drafts = emptyList(),
            outbox = emptyList(),
            issuedEventIds = emptyList(),
        )
    }
}

/**
 * One pairing-confined durable transaction. Operations are EBP records and
 * bounded collections, never tables, entities, cursors, or DAO methods.
 * Implementations must invalidate the scope when [EbpDurableStore.write]
 * returns or throws.
 *
 * Every operation is suspending so a Room adapter can issue only the indexed
 * DAO calls a reducer actually requests, lazily inside one Room transaction.
 */
interface EbpWriteTransaction {
    suspend fun pairing(): DurablePairing?
    suspend fun putPairing(pairing: DurablePairing)

    suspend fun runtime(): PairingRuntime
    suspend fun putRuntime(runtime: PairingRuntime)

    /**
     * Atomically install the one-way revocation fence, durably schedule any
     * adapter-owned external cleanup, erase pairing-owned protocol state, and
     * reset pairing-local runtime. Generic pairing writes cannot change fences.
     *
     * A repeated call for an already-revoking pairing is idempotent.
     */
    suspend fun fenceAndErasePairingState(fencedAtMs: Long): DurablePairing?

    suspend fun surface(surfaceId: String): DurableSurfaceRecord?
    suspend fun surfaceCardinality(): SurfaceCardinality
    suspend fun putSurface(record: DurableSurfaceRecord)
    suspend fun deleteSurface(surfaceId: String)
    suspend fun deleteAllSurfaces()

    suspend fun drafts(surfaceId: String): List<DurableDraft>
    suspend fun putDraft(draft: DurableDraft)
    suspend fun deleteDraft(surfaceId: String, nodeId: String)
    suspend fun deleteDrafts(surfaceId: String)

    suspend fun outboxIndex(): List<DurableOutboxIndexEntry>

    /**
     * Confirm that the preparation's payload-free row observation is still
     * current, then return its already-decoded event or null for stable absence.
     * A stale observation must abort and retry the complete prepared write.
     */
    suspend fun resolvePreparedOutbox(
        preparation: PreparedOutboxAdmission,
    ): DurableOutboxEvent?

    /** Insert the already-sealed payload owned by [preparation]. */
    suspend fun putPreparedOutbox(
        preparation: PreparedOutboxAdmission,
        event: DurableOutboxEvent,
    )
    suspend fun clearOutboxPendingLocal(queueSequence: Long): Boolean
    suspend fun deleteOutbox(queueSequence: Long)
    suspend fun deleteAllOutbox()

    suspend fun issuedEventId(eventId: EventId): IssuedEventId?
    suspend fun putIssuedEventId(record: IssuedEventId)
    suspend fun deleteIssuedEventId(eventId: EventId)
    suspend fun issuedEventIdsReusableAtOrBefore(
        effectiveNowMs: Long,
        limit: Int,
    ): List<IssuedEventId>
    suspend fun deleteAllIssuedEventIds()
}

/**
 * Permanent storage SPI. A successful result is returned only after commit;
 * throwing from [block], or a storage exception while committing it, rolls the
 * entire pairing-confined write back.
 */
interface EbpDurableStore {
    suspend fun restore(pairingId: PairingId): DurableSnapshot

    suspend fun <T> write(
        pairingId: PairingId,
        block: suspend EbpWriteTransaction.() -> T,
    ): T

    /**
     * Prepare payload storage before opening the pairing-confined write, then
     * invoke [block] with an opaque capability. Implementations may roll back
     * and repeat [block] with a fresh capability when the prepared row
     * observation becomes stale. The block must therefore contain no effects
     * outside this durable transaction.
     *
     * Outbox payload serialization and decoding, plus all cryptographic and
     * key access, must run with no Room connection (read or write) held.
     * Bounded generic surface/draft JSON mapping may remain inside its ordinary
     * durable transaction.
     */
    suspend fun <T> writePreparedOutbox(
        command: AdmitOutboxCommand,
        block: suspend EbpWriteTransaction.(PreparedOutboxAdmission) -> T,
    ): T
}

/** Require the protocol copy and indexed metadata to describe one occurrence. */
internal fun requireAuthoritativeEventPayload(
    payload: JsonObject,
    eventId: EventId,
    occurredAtMs: Long,
    queuedAtMs: Long,
) {
    val payloadEventId = payload["event_id"] as? JsonPrimitive
    require(
        payloadEventId != null &&
            payloadEventId.isString &&
            payloadEventId.content == eventId.value,
    ) { "payload event_id must be a string matching eventId" }
    requireExactJsonLong(payload, "occurred_at_ms", occurredAtMs)
    requireExactJsonLong(payload, "queued_at_ms", queuedAtMs)
}

private fun requireExactJsonLong(payload: JsonObject, name: String, expected: Long) {
    val value = payload[name] as? JsonPrimitive
    require(value != null && !value.isString && value.longOrNull == expected) {
        "payload $name must be an integer matching indexed metadata"
    }
}
