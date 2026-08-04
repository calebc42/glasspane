package com.calebc42.jetpacs.core.data

import androidx.room3.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import com.calebc42.jetpacs.core.database.JetpacsDatabase
import com.calebc42.jetpacs.core.database.PairingPartitionEntity
import com.calebc42.jetpacs.core.database.PairingRuntimeEntity
import com.calebc42.jetpacs.core.database.SurfaceRecordEntity
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.Dispatchers
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
    fun projectionsArePairingScopedAndExcludeTombstones() = runTest {
        val dao = database.surfaceDao()
        insertPairing("pair-a")
        insertPairing("pair-b")
        dao.insertRecordRow(record(pairingId = "pair-a", surfaceId = "visible"))
        dao.insertRecordRow(record(pairingId = "pair-a", surfaceId = "removed", present = false, firstSeenOrdinal = 2))
        dao.insertRecordRow(record(pairingId = "pair-b", surfaceId = "other-pair"))

        assertEquals(
            listOf("visible"),
            repository.observeSurfaces("pair-a").first().map { it.key.surfaceId },
        )
        assertNull(repository.observeSurface(SurfaceKey("pair-a", "removed")).first())
    }

    @Test
    fun projectionPreservesAcceptedSurfaceMetadata() = runTest {
        insertPairing("pair-a", readyDisconnectedAtEpochMs = 80)
        val expected = record(
            revision = 7,
            specJson = "{\"revision\":7}",
            staleSpecJson = "{\"stale\":true}",
            staleAfterSeconds = 60,
            currentView = "details",
            acceptedAtEpochMs = 70,
        )
        database.surfaceDao().insertRecordRow(expected)

        val actual = repository.observeSurface(SurfaceKey("pair-a", "surface-a")).first()
        assertEquals(expected.revision, actual?.revision)
        assertEquals(expected.specJson, actual?.specJson)
        assertEquals(expected.staleSpecJson, actual?.staleSpecJson)
        assertEquals(expected.staleAfterSeconds, actual?.staleAfterSeconds)
        assertEquals(expected.currentView, actual?.currentView)
        assertEquals(expected.acceptedAtEpochMs, actual?.acceptedAtEpochMs)
        assertEquals(80, actual?.readyDisconnectedAtEpochMs)
    }

    @Test
    fun committedDaoUpdatesFlowThroughTheReadOnlyRepository() = runTest {
        val dao = database.surfaceDao()
        val key = SurfaceKey("pair-a", "surface-a")
        insertPairing("pair-a")
        dao.insertRecordRow(record(revision = 1, specJson = "{\"revision\":1}"))
        assertEquals(1, repository.observeSurface(key).first()?.revision)

        assertEquals(1, dao.updateRecordRow(record(revision = 2, specJson = "{\"revision\":2}")))
        assertEquals(2, repository.observeSurface(key).first()?.revision)
    }

    @Test
    fun pairingRuntimeUpdatesFlowThroughTheReadOnlyRepository() = runTest {
        val key = SurfaceKey("pair-a", "surface-a")
        val runtime = insertPairing("pair-a")
        database.surfaceDao().insertRecordRow(record())

        assertNull(repository.observeSurface(key).first()?.readyDisconnectedAtEpochMs)

        assertEquals(
            1,
            database.pairingDao().updateRuntime(
                runtime.copy(readyDisconnectedAtEpochMs = 90),
            ),
        )
        assertEquals(90, repository.observeSurface(key).first()?.readyDisconnectedAtEpochMs)
    }

    private fun record(
        pairingId: String = "pair-a",
        surfaceId: String = "surface-a",
        revision: Long = 1,
        present: Boolean = true,
        specJson: String? = if (present) "{}" else null,
        staleSpecJson: String? = null,
        staleAfterSeconds: Long? = null,
        currentView: String? = null,
        acceptedAtEpochMs: Long = revision,
        firstSeenOrdinal: Long = 1,
    ) = SurfaceRecordEntity(
        pairingId = pairingId,
        surfaceId = surfaceId,
        revision = revision,
        present = present,
        specJson = specJson,
        staleSpecJson = staleSpecJson,
        staleAfterSeconds = staleAfterSeconds,
        currentView = currentView,
        acceptedAtEpochMs = acceptedAtEpochMs,
        firstSeenOrdinal = firstSeenOrdinal,
    )

    private suspend fun insertPairing(
        pairingId: String,
        readyDisconnectedAtEpochMs: Long? = null,
    ): PairingRuntimeEntity {
        val runtime = PairingRuntimeEntity(
            pairingId = pairingId,
            readyDisconnectedAtEpochMs = readyDisconnectedAtEpochMs,
        )
        database.pairingDao().insertPairing(
            partition = PairingPartitionEntity(
                pairingId = pairingId,
                credentialKeyAlias = "credential-$pairingId",
                payloadKeyAlias = "payload-$pairingId",
                state = PairingPartitionEntity.ACTIVE,
                createdAtEpochMs = 1,
                lastAuthenticatedAtEpochMs = null,
            ),
            runtime = runtime,
        )
        return runtime
    }
}
