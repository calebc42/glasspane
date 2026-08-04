package com.calebc42.jetpacs.core.database

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.PrimaryKey

@Entity(tableName = "pairing_partitions")
data class PairingPartitionEntity(
    @PrimaryKey
    @ColumnInfo(name = "pairing_id")
    val pairingId: String,
    @ColumnInfo(name = "credential_key_alias")
    val credentialKeyAlias: String,
    @ColumnInfo(name = "payload_key_alias")
    val payloadKeyAlias: String,
    @ColumnInfo(name = "state")
    val state: String,
    @ColumnInfo(name = "created_at_epoch_ms")
    val createdAtEpochMs: Long,
    @ColumnInfo(name = "last_authenticated_at_epoch_ms")
    val lastAuthenticatedAtEpochMs: Long?,
) {
    init {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(credentialKeyAlias.isNotBlank()) { "credentialKeyAlias must not be blank" }
        require(payloadKeyAlias.isNotBlank()) { "payloadKeyAlias must not be blank" }
        require(credentialKeyAlias != payloadKeyAlias) {
            "Credential and payload key aliases must be distinct"
        }
        require(state == ACTIVE || state == REVOKING) {
            "state must be ACTIVE or REVOKING"
        }
        require(createdAtEpochMs >= 0) { "createdAtEpochMs must be non-negative" }
        require(lastAuthenticatedAtEpochMs == null || lastAuthenticatedAtEpochMs >= 0) {
            "lastAuthenticatedAtEpochMs must be non-negative"
        }
    }

    companion object {
        const val ACTIVE = "ACTIVE"
        const val REVOKING = "REVOKING"
    }
}

@Entity(
    tableName = "pairing_runtime",
    foreignKeys = [
        ForeignKey(
            entity = PairingPartitionEntity::class,
            parentColumns = ["pairing_id"],
            childColumns = ["pairing_id"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
)
data class PairingRuntimeEntity(
    @PrimaryKey
    @ColumnInfo(name = "pairing_id")
    val pairingId: String,
    @ColumnInfo(name = "next_queue_sequence", defaultValue = "1")
    val nextQueueSequence: Long = 1,
    @ColumnInfo(name = "next_surface_ordinal", defaultValue = "1")
    val nextSurfaceOrdinal: Long = 1,
    @ColumnInfo(name = "clock_high_water_epoch_ms", defaultValue = "0")
    val clockHighWaterEpochMs: Long = 0,
    @ColumnInfo(name = "forward_step_claim_epoch_ms")
    val forwardStepClaimEpochMs: Long? = null,
    @ColumnInfo(name = "clock_forward_claim_boot_id")
    val clockForwardClaimBootId: String? = null,
    @ColumnInfo(name = "forward_step_claimed_at_elapsed_ms")
    val forwardStepClaimedAtElapsedMs: Long? = null,
    @ColumnInfo(name = "ready_disconnected_at_epoch_ms")
    val readyDisconnectedAtEpochMs: Long? = null,
) {
    init {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(nextQueueSequence >= 1) { "nextQueueSequence must be positive" }
        require(nextSurfaceOrdinal >= 1) { "nextSurfaceOrdinal must be positive" }
        require(clockHighWaterEpochMs >= 0) { "clockHighWaterEpochMs must be non-negative" }
        require(
            setOf(
                forwardStepClaimEpochMs == null,
                clockForwardClaimBootId == null,
                forwardStepClaimedAtElapsedMs == null,
            ).size == 1
        ) {
            "Forward-step claim fields must all be absent or present"
        }
        require(forwardStepClaimEpochMs == null || forwardStepClaimEpochMs >= 0) {
            "forwardStepClaimEpochMs must be non-negative"
        }
        require(forwardStepClaimedAtElapsedMs == null || forwardStepClaimedAtElapsedMs >= 0) {
            "forwardStepClaimedAtElapsedMs must be non-negative"
        }
        require(clockForwardClaimBootId == null || clockForwardClaimBootId.isNotBlank()) {
            "clockForwardClaimBootId must be absent or non-blank"
        }
        require(readyDisconnectedAtEpochMs == null || readyDisconnectedAtEpochMs >= 0) {
            "readyDisconnectedAtEpochMs must be non-negative"
        }
    }
}
