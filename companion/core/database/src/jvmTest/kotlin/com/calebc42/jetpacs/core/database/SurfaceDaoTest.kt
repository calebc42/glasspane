package com.calebc42.jetpacs.core.database

import androidx.room3.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest

class SurfaceDaoTest {
    private lateinit var database: JetpacsDatabase
    private lateinit var dao: SurfaceDao

    @BeforeTest
    fun setUp() {
        database = Room.inMemoryDatabaseBuilder<JetpacsDatabase>()
            .setDriver(BundledSQLiteDriver())
            .setQueryCoroutineContext(Dispatchers.IO)
            .build()
        dao = database.surfaceDao()
    }

    @AfterTest
    fun tearDown() {
        database.close()
    }

    @Test
    fun presentQueryIsScopedByPairingAndExcludesTombstones() = runTest {
        dao.upsert(record(pairingId = "pair-a", surfaceId = "visible"))
        dao.upsert(record(pairingId = "pair-a", surfaceId = "removed", present = false))
        dao.upsert(record(pairingId = "pair-b", surfaceId = "other-pair"))

        assertEquals(
            listOf("visible"),
            dao.observePresent("pair-a").first().map(SurfaceRecordEntity::surfaceId),
        )
        assertNull(dao.observePresent("pair-a", "removed").first())
    }

    @Test
    fun upsertReplacesTheRecordAtItsCompositeKey() = runTest {
        dao.upsert(record(revision = 1, specJson = "{\"revision\":1}"))
        dao.upsert(record(revision = 2, specJson = "{\"revision\":2}"))

        assertEquals(
            record(revision = 2, specJson = "{\"revision\":2}"),
            dao.getRecord("pair-a", "surface-a"),
        )
    }

    private fun record(
        pairingId: String = "pair-a",
        surfaceId: String = "surface-a",
        revision: Long = 1,
        present: Boolean = true,
        specJson: String? = if (present) "{}" else null,
    ) = SurfaceRecordEntity(
        pairingId = pairingId,
        surfaceId = surfaceId,
        revision = revision,
        present = present,
        specJson = specJson,
        staleSpecJson = null,
        staleAfterSeconds = null,
        acceptedAtEpochMs = revision,
        disconnectedAtEpochMs = if (present) null else revision,
    )
}
