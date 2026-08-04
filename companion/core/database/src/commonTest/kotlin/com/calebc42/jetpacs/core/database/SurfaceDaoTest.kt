package com.calebc42.jetpacs.core.database

import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest

class SurfaceDaoTest {
    private lateinit var database: JetpacsDatabase
    private lateinit var dao: SurfaceDao

    @BeforeTest
    fun setUp() {
        database = inMemoryTestDatabase()
        dao = database.surfaceDao()
    }

    @AfterTest
    fun tearDown() {
        database.close()
    }

    @Test
    fun presentQueryIsScopedByPairingAndExcludesTombstones() = runTest {
        database.insertTestPairing("pair-a")
        database.insertTestPairing("pair-b")
        dao.insertRecordRow(record(pairingId = "pair-a", surfaceId = "later", firstSeenOrdinal = 3))
        dao.insertRecordRow(
            record(pairingId = "pair-a", surfaceId = "visible", firstSeenOrdinal = 1)
        )
        dao.insertRecordRow(
            record(
                pairingId = "pair-a",
                surfaceId = "removed",
                present = false,
                firstSeenOrdinal = 2,
            )
        )
        dao.insertRecordRow(record(pairingId = "pair-b", surfaceId = "other-pair", firstSeenOrdinal = 1))

        assertEquals(
            listOf("visible", "later"),
            dao.observePresent("pair-a").first().map(SurfaceRecordEntity::surfaceId),
        )
        assertNull(dao.observePresent("pair-a", "removed").first())
    }

    @Test
    fun explicitUpdateReplacesTheRecordAtItsCompositeKey() = runTest {
        database.insertTestPairing()
        dao.insertRecordRow(record(revision = 1, specJson = "{\"revision\":1}"))
        assertEquals(1, dao.updateRecordRow(record(revision = 2, specJson = "{\"revision\":2}")))

        assertEquals(
            record(revision = 2, specJson = "{\"revision\":2}"),
            dao.getRecord("pair-a", "surface-a"),
        )
    }

    @Test
    fun genericDeleteErasesOneSurfaceAndItsDraftsWithoutCrossingPairings() = runTest {
        database.insertTestPairing("pair-a")
        database.insertTestPairing("pair-b")
        dao.insertRecordRow(record(pairingId = "pair-a", surfaceId = "deleted", firstSeenOrdinal = 1))
        dao.insertRecordRow(record(pairingId = "pair-a", surfaceId = "retained", firstSeenOrdinal = 2))
        dao.insertRecordRow(record(pairingId = "pair-b", surfaceId = "preserved", firstSeenOrdinal = 1))
        dao.upsertDraft(testDraft(pairingId = "pair-a", surfaceId = "deleted"))
        dao.upsertDraft(testDraft(pairingId = "pair-a", surfaceId = "retained"))
        dao.upsertDraft(testDraft(pairingId = "pair-b", surfaceId = "preserved"))

        assertEquals(1, dao.deleteRecord("pair-a", "deleted"))

        assertNull(dao.getRecord("pair-a", "deleted"))
        assertEquals(emptyList(), dao.getDrafts("pair-a", "deleted"))
        assertEquals("retained", dao.getRecord("pair-a", "retained")?.surfaceId)
        assertEquals(1, dao.getDrafts("pair-a", "retained").size)
        assertEquals("preserved", dao.getRecord("pair-b", "preserved")?.surfaceId)
        assertEquals(1, dao.getDrafts("pair-b", "preserved").size)
    }

    private fun record(
        pairingId: String = "pair-a",
        surfaceId: String = "surface-a",
        revision: Long = 1,
        present: Boolean = true,
        specJson: String? = if (present) "{}" else null,
        firstSeenOrdinal: Long = 1,
    ) = SurfaceRecordEntity(
        pairingId = pairingId,
        surfaceId = surfaceId,
        revision = revision,
        present = present,
        specJson = specJson,
        staleSpecJson = null,
        staleAfterSeconds = null,
        currentView = null,
        acceptedAtEpochMs = revision,
        firstSeenOrdinal = firstSeenOrdinal,
    )
}
