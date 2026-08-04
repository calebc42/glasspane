package com.calebc42.jetpacs.core.database

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index

/**
 * Durable Companion-issued EventId guard independent of queue-row lifetime.
 *
 * The portable reducer is the sole authority for the seven-day floor and supplies the timestamp;
 * Room enforces pairing scope, uniqueness, persistence, and deterministic pruning order.
 */
@Entity(
    tableName = "issued_event_ids",
    primaryKeys = ["pairing_id", "event_id"],
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
            name = "index_issued_event_ids_pairing_reusable",
            value = ["pairing_id", "reusable_after_epoch_ms", "event_id"],
        ),
    ],
)
data class IssuedEventIdEntity(
    @ColumnInfo(name = "pairing_id")
    val pairingId: String,
    @ColumnInfo(name = "event_id")
    val eventId: String,
    @ColumnInfo(name = "issued_at_epoch_ms")
    val issuedAtEpochMs: Long,
    @ColumnInfo(name = "reusable_after_epoch_ms")
    val reusableAfterEpochMs: Long,
) {
    init {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(eventId.isNotBlank()) { "eventId must not be blank" }
        require(issuedAtEpochMs >= 0) { "issuedAtEpochMs must be non-negative" }
        require(reusableAfterEpochMs >= issuedAtEpochMs) {
            "reusableAfterEpochMs must not precede issuedAtEpochMs"
        }
    }
}
