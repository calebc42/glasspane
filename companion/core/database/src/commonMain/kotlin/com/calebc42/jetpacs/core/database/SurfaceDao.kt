package com.calebc42.jetpacs.core.database

import androidx.room3.Dao
import androidx.room3.Query
import androidx.room3.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface SurfaceDao {
    @Query(
        """
        SELECT * FROM surface_records
        WHERE pairingId = :pairingId AND present = 1
        ORDER BY surfaceId
        """
    )
    fun observePresent(pairingId: String): Flow<List<SurfaceRecordEntity>>

    @Query(
        """
        SELECT * FROM surface_records
        WHERE pairingId = :pairingId AND surfaceId = :surfaceId AND present = 1
        """
    )
    fun observePresent(
        pairingId: String,
        surfaceId: String,
    ): Flow<SurfaceRecordEntity?>

    @Query(
        """
        SELECT * FROM surface_records
        WHERE pairingId = :pairingId AND surfaceId = :surfaceId
        """
    )
    suspend fun getRecord(
        pairingId: String,
        surfaceId: String,
    ): SurfaceRecordEntity?

    @Upsert
    suspend fun upsert(record: SurfaceRecordEntity)
}
