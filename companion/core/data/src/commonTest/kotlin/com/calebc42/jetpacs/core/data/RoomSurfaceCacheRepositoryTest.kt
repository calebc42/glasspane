package com.calebc42.jetpacs.core.data

import androidx.room3.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import com.calebc42.jetpacs.core.database.JetpacsDatabase
import com.calebc42.jetpacs.core.model.CacheWriteResult
import com.calebc42.jetpacs.core.model.CachedSurface
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest

class RoomSurfaceCacheRepositoryTest {
    private lateinit var database: JetpacsDatabase
    private lateinit var repository: RoomSurfaceCacheRepository

    @BeforeTest
    fun setUp() {
        database = Room.inMemoryDatabaseBuilder<JetpacsDatabase>()
            .setDriver(BundledSQLiteDriver())
            .setQueryCoroutineContext(Dispatchers.IO)
            .build()
        repository = RoomSurfaceCacheRepository(database)
    }

    @AfterTest
    fun tearDown() {
        database.close()
    }

    @Test
    fun tombstoneRetainsTheRevisionFloorAndPreventsStaleResurrection() = runTest {
        val key = SurfaceKey("pair-a", "surface-a")

        assertIs<CacheWriteResult.Applied>(repository.accept(surface(key, revision = 1)))
        assertIs<CacheWriteResult.Applied>(
            repository.tombstone(key, revision = 2, observedAtEpochMs = 20),
        )
        assertEquals(
            CacheWriteResult.IgnoredStale(revision = 1, currentRevision = 2),
            repository.accept(surface(key, revision = 1)),
        )

        assertNull(repository.observeSurface(key).first())
        val tombstone = database.surfaceDao().getRecord(key.pairingId, key.surfaceId)
        assertEquals(2, tombstone?.revision)
        assertEquals(false, tombstone?.present)
        assertNull(tombstone?.specJson)
    }

    @Test
    fun concurrentOutOfOrderUpdatesConvergeOnTheNewestRevision() = runTest {
        val key = SurfaceKey("pair-a", "surface-a")

        coroutineScope {
            (1L..25L).map { revision ->
                async(Dispatchers.Default) {
                    repository.accept(surface(key, revision))
                }
            }.awaitAll()
        }

        assertEquals(25, repository.observeSurface(key).first()?.revision)
    }

    private fun surface(
        key: SurfaceKey,
        revision: Long,
    ) = CachedSurface(
        key = key,
        revision = revision,
        specJson = "{\"revision\":$revision}",
        acceptedAtEpochMs = revision,
    )
}
