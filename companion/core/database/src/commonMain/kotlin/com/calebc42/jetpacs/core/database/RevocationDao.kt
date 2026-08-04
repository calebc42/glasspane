package com.calebc42.jetpacs.core.database

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.OnConflictStrategy
import androidx.room3.Query
import androidx.room3.Transaction

@Dao
abstract class RevocationDao {
    @Query("SELECT * FROM pairing_revocations WHERE pairing_id = :pairingId")
    abstract suspend fun getRevocation(pairingId: String): PairingRevocationEntity?

    @Query(
        """
        SELECT * FROM pairing_revocations
        WHERE finalized_at_epoch_ms IS NULL
        ORDER BY fenced_at_epoch_ms, pairing_id
        """
    )
    abstract suspend fun getOpenRevocations(): List<PairingRevocationEntity>

    @Query(
        """
        SELECT * FROM revocation_artifacts
        WHERE pairing_id = :pairingId
        ORDER BY artifact_kind, artifact_reference
        """
    )
    abstract suspend fun getArtifacts(pairingId: String): List<RevocationArtifactEntity>

    @Query(
        """
        SELECT * FROM revocation_artifacts
        WHERE pairing_id = :pairingId AND completed_at_epoch_ms IS NULL
        ORDER BY artifact_kind, artifact_reference
        """
    )
    abstract suspend fun getPendingArtifacts(
        pairingId: String,
    ): List<RevocationArtifactEntity>

    @Query(
        """
        SELECT * FROM revocation_artifacts
        WHERE completed_at_epoch_ms IS NULL
        ORDER BY pairing_id, artifact_kind, artifact_reference
        """
    )
    abstract suspend fun getPendingArtifacts(): List<RevocationArtifactEntity>

    suspend fun completeArtifact(
        pairingId: String,
        artifactKind: String,
        artifactReference: String,
        completedAtEpochMs: Long,
    ): Int {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(artifactKind.isNotBlank()) { "artifactKind must not be blank" }
        require(artifactReference.isNotBlank()) { "artifactReference must not be blank" }
        require(completedAtEpochMs >= 0) { "completedAtEpochMs must be non-negative" }
        return markArtifactCompleted(
            pairingId = pairingId,
            artifactKind = artifactKind,
            artifactReference = artifactReference,
            completedAtEpochMs = completedAtEpochMs,
        )
    }

    @Transaction
    open suspend fun addPendingArtifact(artifact: RevocationArtifactEntity): Boolean {
        require(artifact.completedAtEpochMs == null) { "A new cleanup artifact must be pending" }
        val revocation = getRevocation(artifact.pairingId) ?: return false
        check(revocation.finalizedAtEpochMs == null) { "Revocation is already finalized" }
        return insertArtifactIfAbsent(artifact) != -1L
    }

    @Transaction
    open suspend fun fenceJournalAndEraseState(
        pairingId: String,
        fencedAtEpochMs: Long,
        additionalArtifacts: List<RevocationArtifactEntity> = emptyList(),
    ): Boolean {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(fencedAtEpochMs >= 0) { "fencedAtEpochMs must be non-negative" }
        additionalArtifacts.forEach { artifact ->
            require(artifact.pairingId == pairingId) {
                "Additional cleanup artifacts must belong to the fenced pairing"
            }
            require(artifact.completedAtEpochMs == null) {
                "Additional cleanup artifacts must start pending"
            }
        }

        val existingRevocation = getRevocation(pairingId)
        val partition = getPartitionForRevocation(pairingId)
        val originalCreatedAtEpochMs =
            existingRevocation?.pairingCreatedAtEpochMs ?: partition?.createdAtEpochMs
        if (originalCreatedAtEpochMs != null) {
            require(fencedAtEpochMs >= originalCreatedAtEpochMs) {
                "fencedAtEpochMs must not precede the pairing creation time"
            }
        }
        if (partition == null) {
            if (existingRevocation == null) return false
            check(existingRevocation.fencedAtEpochMs == fencedAtEpochMs) {
                "A repeated revocation must retain its original fence time"
            }
            return true
        }
        check(existingRevocation?.finalizedAtEpochMs == null) {
            "A finalized revocation cannot retain a pairing partition"
        }
        require(fencedAtEpochMs >= partition.createdAtEpochMs) {
            "A revocation fence cannot precede pairing creation"
        }

        if (existingRevocation != null) {
            check(existingRevocation.pairingCreatedAtEpochMs == partition.createdAtEpochMs) {
                "A repeated revocation must retain the original pairing creation time"
            }
            check(existingRevocation.fencedAtEpochMs == fencedAtEpochMs) {
                "A repeated revocation must retain its original fence time"
            }
        }

        if (partition.state == PairingPartitionEntity.ACTIVE) {
            check(markPartitionRevoking(pairingId) == 1) {
                "Pairing revocation fence changed concurrently"
            }
        } else {
            check(partition.state == PairingPartitionEntity.REVOKING) {
                "Pairing has an invalid revocation state"
            }
        }

        if (existingRevocation == null) {
            insertRevocation(
                PairingRevocationEntity(
                    pairingId = pairingId,
                    pairingCreatedAtEpochMs = partition.createdAtEpochMs,
                    fencedAtEpochMs = fencedAtEpochMs,
                )
            )
        }
        insertArtifactsIfAbsent(
            listOf(
                RevocationArtifactEntity(
                    pairingId = pairingId,
                    artifactKind = RevocationArtifactEntity.CREDENTIAL_KEY_ALIAS,
                    artifactReference = partition.credentialKeyAlias,
                ),
                RevocationArtifactEntity(
                    pairingId = pairingId,
                    artifactKind = RevocationArtifactEntity.PAYLOAD_KEY_ALIAS,
                    artifactReference = partition.payloadKeyAlias,
                ),
            ) + additionalArtifacts
        )

        eraseSurfaceState(pairingId)
        eraseQueueState(pairingId)
        eraseIssuedEventIds(pairingId)
        check(resetRuntime(pairingId) == 1) { "Pairing runtime is missing" }
        return true
    }

    @Transaction
    open suspend fun finalizeRevocation(
        pairingId: String,
        finalizedAtEpochMs: Long,
    ): Boolean {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        val revocation = getRevocation(pairingId) ?: return false
        if (revocation.finalizedAtEpochMs != null) return true
        require(finalizedAtEpochMs >= revocation.fencedAtEpochMs) {
            "finalizedAtEpochMs must not precede the revocation fence"
        }
        if (countPendingArtifacts(pairingId) != 0L) return false

        val partition = getPartitionForRevocation(pairingId)
        if (partition != null) {
            check(partition.state == PairingPartitionEntity.REVOKING) {
                "Only a REVOKING partition can be finalized"
            }
            check(deleteRevokingPartitionIfCleanupComplete(pairingId) == 1) {
                "Pairing finalization preconditions changed concurrently"
            }
        }
        check(markRevocationFinalized(pairingId, finalizedAtEpochMs) == 1) {
            "Revocation finalization changed concurrently"
        }
        return true
    }

    @Query("SELECT * FROM pairing_partitions WHERE pairing_id = :pairingId")
    protected abstract suspend fun getPartitionForRevocation(
        pairingId: String,
    ): PairingPartitionEntity?

    @Query(
        """
        UPDATE pairing_partitions
        SET state = 'REVOKING'
        WHERE pairing_id = :pairingId AND state = 'ACTIVE'
        """
    )
    protected abstract suspend fun markPartitionRevoking(pairingId: String): Int

    @Insert
    protected abstract suspend fun insertRevocation(revocation: PairingRevocationEntity)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    protected abstract suspend fun insertArtifactIfAbsent(
        artifact: RevocationArtifactEntity,
    ): Long

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    protected abstract suspend fun insertArtifactsIfAbsent(
        artifacts: List<RevocationArtifactEntity>,
    )

    @Query("DELETE FROM surface_records WHERE pairing_id = :pairingId")
    protected abstract suspend fun eraseSurfaceState(pairingId: String): Int

    @Query("DELETE FROM queue_events WHERE pairing_id = :pairingId")
    protected abstract suspend fun eraseQueueState(pairingId: String): Int

    @Query("DELETE FROM issued_event_ids WHERE pairing_id = :pairingId")
    protected abstract suspend fun eraseIssuedEventIds(pairingId: String): Int

    @Query(
        """
        UPDATE pairing_runtime
        SET next_queue_sequence = 1,
            next_surface_ordinal = 1,
            clock_high_water_epoch_ms = 0,
            forward_step_claim_epoch_ms = NULL,
            clock_forward_claim_boot_id = NULL,
            forward_step_claimed_at_elapsed_ms = NULL,
            ready_disconnected_at_epoch_ms = NULL
        WHERE pairing_id = :pairingId
        """
    )
    protected abstract suspend fun resetRuntime(pairingId: String): Int

    @Query(
        """
        SELECT COUNT(*) FROM revocation_artifacts
        WHERE pairing_id = :pairingId AND completed_at_epoch_ms IS NULL
        """
    )
    protected abstract suspend fun countPendingArtifacts(pairingId: String): Long

    @Query(
        """
        UPDATE revocation_artifacts
        SET completed_at_epoch_ms = :completedAtEpochMs
        WHERE pairing_id = :pairingId
          AND artifact_kind = :artifactKind
          AND artifact_reference = :artifactReference
          AND completed_at_epoch_ms IS NULL
          AND EXISTS (
              SELECT 1 FROM pairing_revocations
              WHERE pairing_id = :pairingId AND finalized_at_epoch_ms IS NULL
          )
        """
    )
    protected abstract suspend fun markArtifactCompleted(
        pairingId: String,
        artifactKind: String,
        artifactReference: String,
        completedAtEpochMs: Long,
    ): Int

    @Query(
        """
        DELETE FROM pairing_partitions
        WHERE pairing_id = :pairingId
          AND state = 'REVOKING'
          AND EXISTS (
              SELECT 1 FROM pairing_revocations
              WHERE pairing_id = :pairingId AND finalized_at_epoch_ms IS NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM revocation_artifacts
              WHERE pairing_id = :pairingId AND completed_at_epoch_ms IS NULL
          )
        """
    )
    protected abstract suspend fun deleteRevokingPartitionIfCleanupComplete(
        pairingId: String,
    ): Int

    @Query(
        """
        UPDATE pairing_revocations
        SET finalized_at_epoch_ms = :finalizedAtEpochMs
        WHERE pairing_id = :pairingId
          AND finalized_at_epoch_ms IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM revocation_artifacts
              WHERE pairing_id = :pairingId AND completed_at_epoch_ms IS NULL
          )
        """
    )
    protected abstract suspend fun markRevocationFinalized(
        pairingId: String,
        finalizedAtEpochMs: Long,
    ): Int
}
