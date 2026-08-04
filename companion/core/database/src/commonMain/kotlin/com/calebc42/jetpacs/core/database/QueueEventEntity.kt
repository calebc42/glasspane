package com.calebc42.jetpacs.core.database

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index

@Entity(
    tableName = "queue_events",
    primaryKeys = ["pairing_id", "queue_seq"],
    foreignKeys = [
        ForeignKey(
            entity = PairingPartitionEntity::class,
            parentColumns = ["pairing_id"],
            childColumns = ["pairing_id"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index(
            name = "index_queue_events_pairing_event_id",
            value = ["pairing_id", "event_id"],
            unique = true,
        ),
        Index(
            name = "index_queue_events_pairing_dedupe",
            value = ["pairing_id", "dedupe_key"],
        ),
        Index(
            name = "index_queue_events_pairing_expiry",
            value = ["pairing_id", "expires_at_epoch_ms", "queue_seq"],
        ),
        Index(
            name = "index_queue_events_pairing_pending_local",
            value = ["pairing_id", "pending_local", "queue_seq"],
        ),
    ],
)
data class QueueEventEntity(
    @ColumnInfo(name = "pairing_id")
    val pairingId: String,
    @ColumnInfo(name = "queue_seq")
    val queueSequence: Long,
    @ColumnInfo(name = "event_id")
    val eventId: String,
    @ColumnInfo(name = "storage_generation")
    val storageGeneration: String,
    @ColumnInfo(name = "payload_envelope", typeAffinity = ColumnInfo.BLOB)
    val payloadEnvelope: ByteArray,
    @ColumnInfo(name = "accounted_byte_count")
    val accountedByteCount: Long,
    @ColumnInfo(name = "policy")
    val policy: String,
    @ColumnInfo(name = "occurred_at_epoch_ms")
    val occurredAtEpochMs: Long,
    @ColumnInfo(name = "queued_at_epoch_ms")
    val queuedAtEpochMs: Long,
    @ColumnInfo(name = "expires_at_epoch_ms")
    val expiresAtEpochMs: Long,
    @ColumnInfo(name = "dedupe_key")
    val dedupeKey: String?,
    @ColumnInfo(name = "pending_local", defaultValue = "0")
    val pendingLocal: Boolean = false,
    @ColumnInfo(name = "trigger_identity")
    val triggerIdentity: String? = null,
) {
    init {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(queueSequence >= 1) { "queueSequence must be positive" }
        require(eventId.isNotBlank()) { "eventId must not be blank" }
        require(STORAGE_GENERATION.matches(storageGeneration)) {
            "storageGeneration must be 32 lowercase hexadecimal characters"
        }
        require(payloadEnvelope.isNotEmpty()) { "payloadEnvelope must not be empty" }
        require(accountedByteCount > 0) { "accountedByteCount must be positive" }
        require(policy == POLICY_QUEUE || policy == POLICY_WAKE) {
            "policy must be queue or wake"
        }
        require(occurredAtEpochMs >= 0) { "occurredAtEpochMs must be non-negative" }
        require(queuedAtEpochMs >= 0) { "queuedAtEpochMs must be non-negative" }
        require(queuedAtEpochMs >= occurredAtEpochMs) {
            "queuedAtEpochMs must not precede occurredAtEpochMs"
        }
        require(expiresAtEpochMs >= occurredAtEpochMs) {
            "expiresAtEpochMs must not precede occurredAtEpochMs"
        }
        require(expiresAtEpochMs >= queuedAtEpochMs) {
            "expiresAtEpochMs must not precede queuedAtEpochMs"
        }
        require(dedupeKey == null || dedupeKey.isNotBlank()) {
            "dedupeKey must be absent or non-blank"
        }
        require(triggerIdentity == null || triggerIdentity.isNotBlank()) {
            "triggerIdentity must be absent or non-blank"
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is QueueEventEntity) return false

        return pairingId == other.pairingId &&
            queueSequence == other.queueSequence &&
            eventId == other.eventId &&
            storageGeneration == other.storageGeneration &&
            payloadEnvelope.contentEquals(other.payloadEnvelope) &&
            accountedByteCount == other.accountedByteCount &&
            policy == other.policy &&
            occurredAtEpochMs == other.occurredAtEpochMs &&
            queuedAtEpochMs == other.queuedAtEpochMs &&
            expiresAtEpochMs == other.expiresAtEpochMs &&
            dedupeKey == other.dedupeKey &&
            pendingLocal == other.pendingLocal &&
            triggerIdentity == other.triggerIdentity
    }

    override fun hashCode(): Int {
        var result = pairingId.hashCode()
        result = 31 * result + queueSequence.hashCode()
        result = 31 * result + eventId.hashCode()
        result = 31 * result + storageGeneration.hashCode()
        result = 31 * result + payloadEnvelope.contentHashCode()
        result = 31 * result + accountedByteCount.hashCode()
        result = 31 * result + policy.hashCode()
        result = 31 * result + occurredAtEpochMs.hashCode()
        result = 31 * result + queuedAtEpochMs.hashCode()
        result = 31 * result + expiresAtEpochMs.hashCode()
        result = 31 * result + (dedupeKey?.hashCode() ?: 0)
        result = 31 * result + pendingLocal.hashCode()
        result = 31 * result + (triggerIdentity?.hashCode() ?: 0)
        return result
    }

    companion object {
        const val POLICY_QUEUE = "queue"
        const val POLICY_WAKE = "wake"
        private val STORAGE_GENERATION = Regex("[0-9a-f]{32}")
    }
}
