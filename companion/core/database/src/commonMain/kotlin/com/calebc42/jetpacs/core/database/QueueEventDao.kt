package com.calebc42.jetpacs.core.database

import androidx.room3.ColumnInfo
import androidx.room3.Dao
import androidx.room3.Insert
import androidx.room3.Query

data class QueueEventIndexRow(
    @ColumnInfo(name = "queue_seq")
    val queueSequence: Long,
    @ColumnInfo(name = "event_id")
    val eventId: String,
    @ColumnInfo(name = "storage_generation")
    val storageGeneration: String,
    @ColumnInfo(name = "expires_at_epoch_ms")
    val expiresAtEpochMs: Long,
    @ColumnInfo(name = "dedupe_key")
    val dedupeKey: String?,
    @ColumnInfo(name = "accounted_byte_count")
    val accountedByteCount: Long,
)

/**
 * Payload-free identity used to revalidate an outbox observation after encryption or decryption
 * has completed outside Room's sole-writer transaction.
 */
data class QueueEventVersionRow(
    @ColumnInfo(name = "queue_seq")
    val queueSequence: Long,
    @ColumnInfo(name = "event_id")
    val eventId: String,
    @ColumnInfo(name = "storage_generation")
    val storageGeneration: String,
    @ColumnInfo(name = "pending_local")
    val pendingLocal: Boolean,
)

@Dao
interface QueueEventDao {
    /** Mechanical row primitive; admission and counter changes belong only to the reducer. */
    @Insert
    suspend fun insertEventRow(event: QueueEventEntity)

    @Query(
        """
        SELECT * FROM queue_events
        WHERE pairing_id = :pairingId AND queue_seq = :queueSequence
        """
    )
    suspend fun getEvent(
        pairingId: String,
        queueSequence: Long,
    ): QueueEventEntity?

    @Query(
        """
        SELECT * FROM queue_events
        WHERE pairing_id = :pairingId AND event_id = :eventId
        """
    )
    suspend fun getEventById(
        pairingId: String,
        eventId: String,
    ): QueueEventEntity?

    @Query(
        """
        SELECT queue_seq, event_id, storage_generation, pending_local
        FROM queue_events
        WHERE pairing_id = :pairingId AND event_id = :eventId
        """
    )
    suspend fun getEventVersionById(
        pairingId: String,
        eventId: String,
    ): QueueEventVersionRow?

    @Query(
        """
        SELECT * FROM queue_events
        WHERE pairing_id = :pairingId
        ORDER BY queue_seq
        """
    )
    suspend fun getEvents(pairingId: String): List<QueueEventEntity>

    @Query(
        """
        SELECT queue_seq, event_id, storage_generation, expires_at_epoch_ms,
               dedupe_key, accounted_byte_count
        FROM queue_events
        WHERE pairing_id = :pairingId
        ORDER BY queue_seq
        """
    )
    suspend fun getEventIndex(pairingId: String): List<QueueEventIndexRow>

    @Query(
        """
        SELECT * FROM queue_events
        WHERE pairing_id = :pairingId AND dedupe_key = :dedupeKey
        ORDER BY queue_seq
        """
    )
    suspend fun getEventsByDedupeKey(
        pairingId: String,
        dedupeKey: String,
    ): List<QueueEventEntity>

    @Query(
        """
        SELECT * FROM queue_events
        WHERE pairing_id = :pairingId AND pending_local = 1
        ORDER BY queue_seq
        """
    )
    suspend fun getPendingLocalEvents(pairingId: String): List<QueueEventEntity>

    @Query(
        """
        UPDATE queue_events
        SET pending_local = 0
        WHERE pairing_id = :pairingId
          AND queue_seq = :queueSequence
          AND pending_local = 1
        """
    )
    suspend fun clearPendingLocal(
        pairingId: String,
        queueSequence: Long,
    ): Int

    @Query(
        """
        DELETE FROM queue_events
        WHERE pairing_id = :pairingId AND queue_seq = :queueSequence
        """
    )
    suspend fun deleteEvent(
        pairingId: String,
        queueSequence: Long,
    ): Int

    @Query("DELETE FROM queue_events WHERE pairing_id = :pairingId")
    suspend fun deleteAllEvents(pairingId: String): Int

    @Query("SELECT COUNT(*) FROM queue_events WHERE pairing_id = :pairingId")
    suspend fun countEvents(pairingId: String): Long

    @Query(
        """
        SELECT COALESCE(SUM(accounted_byte_count), 0)
        FROM queue_events
        WHERE pairing_id = :pairingId
        """
    )
    suspend fun accountedByteCount(pairingId: String): Long
}
