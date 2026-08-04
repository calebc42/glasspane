package com.calebc42.jetpacs.core.database

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.Query
import androidx.room3.Transaction
import androidx.room3.Update
import kotlinx.coroutines.flow.Flow

@Dao
abstract class PairingDao {
    @Insert
    protected abstract suspend fun insertPartitionRow(partition: PairingPartitionEntity)

    @Insert
    abstract suspend fun insertRuntime(runtime: PairingRuntimeEntity)

    /**
     * Mechanical full-row persistence primitive. The portable reducer is the sole authority for
     * counter and clock transitions; its future Room adapter invokes this inside one transaction.
     */
    @Update
    abstract suspend fun updateRuntime(runtime: PairingRuntimeEntity): Int

    /**
     * Inserts a new durable pairing only when its identity has never crossed the revocation fence.
     * The revocation journal deliberately survives partition deletion, so checking only
     * pairing_partitions would permit an implicitly reactivated identity.
     */
    @Transaction
    open suspend fun insertPartition(partition: PairingPartitionEntity) {
        check(countRevocationFences(partition.pairingId) == 0L) {
            "A revoked pairing identity cannot be reactivated"
        }
        insertPartitionRow(partition)
    }

    @Transaction
    open suspend fun insertPairing(
        partition: PairingPartitionEntity,
        runtime: PairingRuntimeEntity,
    ) {
        require(partition.pairingId == runtime.pairingId) {
            "Partition and runtime pairing IDs must match"
        }
        check(countRevocationFences(partition.pairingId) == 0L) {
            "A revoked pairing identity cannot be reactivated"
        }
        insertPartitionRow(partition)
        insertRuntime(runtime)
    }

    @Query("SELECT * FROM pairing_partitions WHERE pairing_id = :pairingId")
    abstract suspend fun getPartition(pairingId: String): PairingPartitionEntity?

    @Query("SELECT * FROM pairing_runtime WHERE pairing_id = :pairingId")
    abstract suspend fun getRuntime(pairingId: String): PairingRuntimeEntity?

    @Query("SELECT * FROM pairing_runtime WHERE pairing_id = :pairingId")
    abstract fun observeRuntime(pairingId: String): Flow<PairingRuntimeEntity?>

    /**
     * Monotonic protocol-state transition which leaves key aliases, creation time, and
     * authentication metadata untouched.
     */
    @Query(
        """
        UPDATE pairing_partitions
        SET state = 'REVOKING'
        WHERE pairing_id = :pairingId AND state = 'ACTIVE'
        """
    )
    abstract suspend fun markPartitionRevoking(pairingId: String): Int

    @Query(
        """
        UPDATE pairing_partitions
        SET last_authenticated_at_epoch_ms = :authenticatedAtEpochMs
        WHERE pairing_id = :pairingId AND state = 'ACTIVE'
        """
    )
    abstract suspend fun recordAuthentication(
        pairingId: String,
        authenticatedAtEpochMs: Long,
    ): Int

    @Query("SELECT COUNT(*) FROM pairing_revocations WHERE pairing_id = :pairingId")
    protected abstract suspend fun countRevocationFences(pairingId: String): Long
}

