package com.calebc42.jetpacs.core.database

import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.Query

/** Mechanical storage primitives; the portable reducer owns reuse eligibility and retention. */
@Dao
interface IssuedEventIdDao {
    @Insert
    suspend fun insertIssuedEventId(record: IssuedEventIdEntity)

    @Query(
        """
        SELECT * FROM issued_event_ids
        WHERE pairing_id = :pairingId AND event_id = :eventId
        """
    )
    suspend fun getIssuedEventId(
        pairingId: String,
        eventId: String,
    ): IssuedEventIdEntity?

    /** Pairing-wide deterministic order used when reconstructing a durable snapshot. */
    @Query(
        """
        SELECT * FROM issued_event_ids
        WHERE pairing_id = :pairingId
        ORDER BY reusable_after_epoch_ms, event_id
        """
    )
    suspend fun getIssuedEventIds(pairingId: String): List<IssuedEventIdEntity>

    @Query(
        """
        SELECT * FROM issued_event_ids
        WHERE pairing_id = :pairingId
          AND reusable_after_epoch_ms <= :nowEpochMs
        ORDER BY reusable_after_epoch_ms, event_id
        LIMIT :limit
        """
    )
    suspend fun getReusableAtOrBefore(
        pairingId: String,
        nowEpochMs: Long,
        limit: Int,
    ): List<IssuedEventIdEntity>

    @Query(
        """
        DELETE FROM issued_event_ids
        WHERE pairing_id = :pairingId AND event_id = :eventId
        """
    )
    suspend fun deleteIssuedEventId(
        pairingId: String,
        eventId: String,
    ): Int

    @Query("DELETE FROM issued_event_ids WHERE pairing_id = :pairingId")
    suspend fun deleteAllIssuedEventIds(pairingId: String): Int

    @Query("SELECT COUNT(*) FROM issued_event_ids WHERE pairing_id = :pairingId")
    suspend fun countIssuedEventIds(pairingId: String): Long
}
