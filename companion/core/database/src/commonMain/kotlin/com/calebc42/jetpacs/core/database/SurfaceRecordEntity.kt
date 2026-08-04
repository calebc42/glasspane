package com.calebc42.jetpacs.core.database

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index

@Entity(
    tableName = "surface_records",
    primaryKeys = ["pairing_id", "surface_id"],
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
            name = "index_surface_records_pairing_first_seen",
            value = ["pairing_id", "first_seen_ordinal"],
            unique = true,
        ),
        Index(
            name = "index_surface_records_pairing_present_order",
            value = ["pairing_id", "present", "first_seen_ordinal"],
        ),
    ],
)
data class SurfaceRecordEntity(
    @ColumnInfo(name = "pairing_id")
    val pairingId: String,
    @ColumnInfo(name = "surface_id")
    val surfaceId: String,
    @ColumnInfo(name = "revision")
    val revision: Long,
    @ColumnInfo(name = "present")
    val present: Boolean,
    @ColumnInfo(name = "spec_json")
    val specJson: String?,
    @ColumnInfo(name = "stale_spec_json")
    val staleSpecJson: String?,
    @ColumnInfo(name = "stale_after_seconds")
    val staleAfterSeconds: Long?,
    @ColumnInfo(name = "current_view")
    val currentView: String?,
    @ColumnInfo(name = "accepted_at_epoch_ms")
    val acceptedAtEpochMs: Long,
    @ColumnInfo(name = "first_seen_ordinal")
    val firstSeenOrdinal: Long,
) {
    init {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(surfaceId.isNotBlank()) { "surfaceId must not be blank" }
        require(revision >= 0) { "revision must be non-negative" }
        require(firstSeenOrdinal >= 1) { "firstSeenOrdinal must be positive" }
        require(acceptedAtEpochMs >= 0) { "acceptedAtEpochMs must be non-negative" }
        require(staleAfterSeconds == null || staleAfterSeconds > 0) {
            "staleAfterSeconds must be positive"
        }
        if (present) {
            requireNotNull(specJson) { "A present surface requires specJson" }
        } else {
            require(specJson == null) { "A tombstone cannot retain specJson" }
            require(staleSpecJson == null) { "A tombstone cannot retain staleSpecJson" }
            require(staleAfterSeconds == null) { "A tombstone cannot retain staleAfterSeconds" }
            require(currentView == null) { "A tombstone cannot retain currentView" }
        }
    }
}
