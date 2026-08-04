package com.calebc42.jetpacs.core.database

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.Query
import androidx.room3.Update
import androidx.room3.Upsert
import kotlinx.coroutines.flow.Flow

data class SurfaceCardinalityRow(
    val total: Long,
    val present: Long,
)

@Dao
interface SurfaceDao {
    @Query(
        """
        SELECT * FROM surface_records
        WHERE pairing_id = :pairingId AND present = 1
        ORDER BY first_seen_ordinal
        """
    )
    fun observePresent(pairingId: String): Flow<List<SurfaceRecordEntity>>

    @Query(
        """
        SELECT * FROM surface_records
        WHERE pairing_id = :pairingId AND surface_id = :surfaceId AND present = 1
        """
    )
    fun observePresent(
        pairingId: String,
        surfaceId: String,
    ): Flow<SurfaceRecordEntity?>

    @Query(
        """
        SELECT * FROM surface_records
        WHERE pairing_id = :pairingId AND surface_id = :surfaceId
        """
    )
    suspend fun getRecord(
        pairingId: String,
        surfaceId: String,
    ): SurfaceRecordEntity?

    @Query(
        """
        SELECT * FROM surface_records
        WHERE pairing_id = :pairingId
        ORDER BY first_seen_ordinal
        """
    )
    suspend fun getRecords(pairingId: String): List<SurfaceRecordEntity>

    @Update
    suspend fun updateRecordRow(record: SurfaceRecordEntity): Int

    /** Mechanical row primitive; admission and ordinal changes belong only to the reducer. */
    @Insert
    suspend fun insertRecordRow(record: SurfaceRecordEntity)

    @Query(
        """
        SELECT COUNT(*) AS total,
               COALESCE(SUM(CASE WHEN present = 1 THEN 1 ELSE 0 END), 0) AS present
        FROM surface_records
        WHERE pairing_id = :pairingId
        """
    )
    suspend fun getCardinality(pairingId: String): SurfaceCardinalityRow

    @Query(
        """
        DELETE FROM surface_records
        WHERE pairing_id = :pairingId AND surface_id = :surfaceId
        """
    )
    suspend fun deleteRecord(
        pairingId: String,
        surfaceId: String,
    ): Int

    /** Pairing-confined bulk primitive; child drafts are removed by the foreign-key cascade. */
    @Query("DELETE FROM surface_records WHERE pairing_id = :pairingId")
    suspend fun deleteAllRecords(pairingId: String): Int

    @Query(
        """
        DELETE FROM surface_records
        WHERE pairing_id = :pairingId
          AND surface_id = :surfaceId
          AND present = 0
        """
    )
    suspend fun releaseTombstone(
        pairingId: String,
        surfaceId: String,
    ): Int

    @Query(
        """
        SELECT * FROM surface_drafts
        WHERE pairing_id = :pairingId AND surface_id = :surfaceId
        ORDER BY node_id
        """
    )
    suspend fun getDrafts(
        pairingId: String,
        surfaceId: String,
    ): List<SurfaceDraftEntity>

    @Query(
        """
        SELECT * FROM surface_drafts
        WHERE pairing_id = :pairingId
        ORDER BY surface_id, node_id
        """
    )
    suspend fun getDrafts(pairingId: String): List<SurfaceDraftEntity>

    @Upsert
    suspend fun upsertDraft(draft: SurfaceDraftEntity)

    @Upsert
    suspend fun upsertDrafts(drafts: List<SurfaceDraftEntity>)

    @Query(
        """
        DELETE FROM surface_drafts
        WHERE pairing_id = :pairingId
          AND surface_id = :surfaceId
          AND node_id = :nodeId
        """
    )
    suspend fun deleteDraft(
        pairingId: String,
        surfaceId: String,
        nodeId: String,
    ): Int

    @Query(
        """
        DELETE FROM surface_drafts
        WHERE pairing_id = :pairingId AND surface_id = :surfaceId
        """
    )
    suspend fun deleteDrafts(
        pairingId: String,
        surfaceId: String,
    ): Int
}
