package com.calebc42.jetpacs.core.database

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index
import androidx.room3.PrimaryKey

/** Intentionally has no foreign key to pairing_partitions so cleanup survives finalization. */
@Entity(tableName = "pairing_revocations")
data class PairingRevocationEntity(
    @PrimaryKey
    @ColumnInfo(name = "pairing_id")
    val pairingId: String,
    @ColumnInfo(name = "pairing_created_at_epoch_ms")
    val pairingCreatedAtEpochMs: Long,
    @ColumnInfo(name = "fenced_at_epoch_ms")
    val fencedAtEpochMs: Long,
    @ColumnInfo(name = "finalized_at_epoch_ms")
    val finalizedAtEpochMs: Long? = null,
) {
    init {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(pairingCreatedAtEpochMs >= 0) {
            "pairingCreatedAtEpochMs must be non-negative"
        }
        require(fencedAtEpochMs >= 0) { "fencedAtEpochMs must be non-negative" }
        require(fencedAtEpochMs >= pairingCreatedAtEpochMs) {
            "fencedAtEpochMs must not precede pairing creation"
        }
        require(finalizedAtEpochMs == null || finalizedAtEpochMs >= fencedAtEpochMs) {
            "finalizedAtEpochMs must not precede fencedAtEpochMs"
        }
    }
}

/**
 * External cleanup work journaled before pairing-owned Room state is erased.
 *
 * Its only foreign key is to the non-cascading revocation journal, never to the pairing partition.
 */
@Entity(
    tableName = "revocation_artifacts",
    primaryKeys = ["pairing_id", "artifact_kind", "artifact_reference"],
    foreignKeys = [
        ForeignKey(
            entity = PairingRevocationEntity::class,
            parentColumns = ["pairing_id"],
            childColumns = ["pairing_id"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index(
            name = "index_revocation_artifacts_pairing_pending",
            value = [
                "pairing_id",
                "completed_at_epoch_ms",
                "artifact_kind",
                "artifact_reference",
            ],
        ),
    ],
)
data class RevocationArtifactEntity(
    @ColumnInfo(name = "pairing_id")
    val pairingId: String,
    @ColumnInfo(name = "artifact_kind")
    val artifactKind: String,
    @ColumnInfo(name = "artifact_reference")
    val artifactReference: String,
    @ColumnInfo(name = "completed_at_epoch_ms")
    val completedAtEpochMs: Long? = null,
) {
    init {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(artifactKind.isNotBlank()) { "artifactKind must not be blank" }
        require(artifactReference.isNotBlank()) { "artifactReference must not be blank" }
        require(completedAtEpochMs == null || completedAtEpochMs >= 0) {
            "completedAtEpochMs must be non-negative"
        }
    }

    companion object {
        const val CREDENTIAL_KEY_ALIAS = "credential_key_alias"
        const val PAYLOAD_KEY_ALIAS = "payload_key_alias"
    }
}
