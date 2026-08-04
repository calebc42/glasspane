package com.calebc42.jetpacs.core.database

import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class RevocationDaoTest {
    private lateinit var database: JetpacsDatabase
    private lateinit var dao: RevocationDao

    @BeforeTest
    fun setUp() {
        database = inMemoryTestDatabase()
        dao = database.revocationDao()
    }

    @AfterTest
    fun tearDown() {
        database.close()
    }

    @Test
    fun fenceJournalsAliasesErasesStateAndFinalizesOnlyAfterCleanup() = runTest {
        database.insertTestPairing(
            runtime =
                testRuntime(
                    nextQueueSequence = 9,
                    nextSurfaceOrdinal = 7,
                    clockHighWaterEpochMs = 5_000,
                    forwardStepClaimEpochMs = 9_000,
                    clockForwardClaimBootId = "boot-a",
                    forwardStepClaimedAtElapsedMs = 100,
                    readyDisconnectedAtEpochMs = 4_000,
                )
        )
        database.surfaceDao().insertRecordRow(testSurface())
        database.surfaceDao().upsertDraft(testDraft())
        database.queueEventDao().insertEventRow(testQueueEvent())
        database.issuedEventIdDao().insertIssuedEventId(testIssuedEventId())
        val additional = testArtifact(kind = "temporary_file", reference = "/private/cache/a")

        assertTrue(
            dao.fenceJournalAndEraseState(
                pairingId = TEST_PAIRING_A,
                fencedAtEpochMs = 100,
                additionalArtifacts = listOf(additional),
            )
        )
        assertEquals(
            PairingPartitionEntity.REVOKING,
            database.pairingDao().getPartition(TEST_PAIRING_A)?.state,
        )
        assertEquals(testRuntime(), database.pairingDao().getRuntime(TEST_PAIRING_A))
        assertTrue(database.surfaceDao().getRecords(TEST_PAIRING_A).isEmpty())
        assertTrue(database.surfaceDao().getDrafts(TEST_PAIRING_A).isEmpty())
        assertTrue(database.queueEventDao().getEvents(TEST_PAIRING_A).isEmpty())
        assertEquals(0L, database.issuedEventIdDao().countIssuedEventIds(TEST_PAIRING_A))
        assertEquals(
            PairingRevocationEntity(
                pairingId = TEST_PAIRING_A,
                pairingCreatedAtEpochMs = 10,
                fencedAtEpochMs = 100,
            ),
            dao.getRevocation(TEST_PAIRING_A),
        )

        val expectedArtifactKeys =
            setOf(
                RevocationArtifactEntity.CREDENTIAL_KEY_ALIAS to
                    "credential-$TEST_PAIRING_A",
                RevocationArtifactEntity.PAYLOAD_KEY_ALIAS to
                    "payload-$TEST_PAIRING_A",
                "temporary_file" to "/private/cache/a",
            )
        assertEquals(
            expectedArtifactKeys,
            dao.getPendingArtifacts(TEST_PAIRING_A)
                .map { it.artifactKind to it.artifactReference }
                .toSet(),
        )

        assertFailsWith<IllegalStateException> {
            dao.fenceJournalAndEraseState(
                pairingId = TEST_PAIRING_A,
                fencedAtEpochMs = 999,
                additionalArtifacts = listOf(additional),
            )
        }
        assertTrue(
            dao.fenceJournalAndEraseState(
                pairingId = TEST_PAIRING_A,
                fencedAtEpochMs = 100,
                additionalArtifacts = listOf(additional),
            )
        )
        assertEquals(100, dao.getRevocation(TEST_PAIRING_A)?.fencedAtEpochMs)
        assertEquals(3, dao.getArtifacts(TEST_PAIRING_A).size)
        assertFalse(dao.finalizeRevocation(TEST_PAIRING_A, finalizedAtEpochMs = 200))
        assertEquals(
            PairingPartitionEntity.REVOKING,
            database.pairingDao().getPartition(TEST_PAIRING_A)?.state,
        )

        val first = dao.getPendingArtifacts(TEST_PAIRING_A).first()
        assertEquals(
            1,
            dao.completeArtifact(
                first.pairingId,
                first.artifactKind,
                first.artifactReference,
                completedAtEpochMs = 150,
            ),
        )
        assertFalse(dao.finalizeRevocation(TEST_PAIRING_A, finalizedAtEpochMs = 200))

        dao.getPendingArtifacts(TEST_PAIRING_A).forEach { artifact ->
            assertEquals(
                1,
                dao.completeArtifact(
                    artifact.pairingId,
                    artifact.artifactKind,
                    artifact.artifactReference,
                    completedAtEpochMs = 175,
                ),
            )
        }
        assertTrue(dao.finalizeRevocation(TEST_PAIRING_A, finalizedAtEpochMs = 200))
        assertNull(database.pairingDao().getPartition(TEST_PAIRING_A))
        assertNull(database.pairingDao().getRuntime(TEST_PAIRING_A))
        assertEquals(200, dao.getRevocation(TEST_PAIRING_A)?.finalizedAtEpochMs)
        assertTrue(dao.getPendingArtifacts(TEST_PAIRING_A).isEmpty())
        assertEquals(3, dao.getArtifacts(TEST_PAIRING_A).size)
        assertTrue(dao.finalizeRevocation(TEST_PAIRING_A, finalizedAtEpochMs = 250))
        assertTrue(dao.fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 100))
        assertFailsWith<IllegalArgumentException> {
            dao.fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 9)
        }
        assertFailsWith<IllegalStateException> {
            dao.fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 300)
        }
        assertFailsWith<IllegalStateException> {
            database.pairingDao().insertPairing(testPartition(), testRuntime())
        }
    }

    @Test
    fun fenceCannotPredatePairingCreationAndLeavesActiveStateUntouched() = runTest {
        database.insertTestPairing()
        database.surfaceDao().insertRecordRow(testSurface())

        assertFailsWith<IllegalArgumentException> {
            dao.fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 9)
        }

        assertEquals(
            PairingPartitionEntity.ACTIVE,
            database.pairingDao().getPartition(TEST_PAIRING_A)?.state,
        )
        assertNull(dao.getRevocation(TEST_PAIRING_A))
        assertEquals(listOf(testSurface()), database.surfaceDao().getRecords(TEST_PAIRING_A))

        assertTrue(dao.fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 10))
        assertTrue(dao.fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 10))
        assertEquals(10, dao.getRevocation(TEST_PAIRING_A)?.fencedAtEpochMs)
    }

    @Test
    fun fenceAndCleanupArePairingIsolated() = runTest {
        database.insertTestPairing(TEST_PAIRING_A)
        database.insertTestPairing(TEST_PAIRING_B)
        database.surfaceDao().insertRecordRow(testSurface(pairingId = TEST_PAIRING_A))
        database.surfaceDao().insertRecordRow(testSurface(pairingId = TEST_PAIRING_B))
        database.queueEventDao().insertEventRow(testQueueEvent(pairingId = TEST_PAIRING_A))
        database.queueEventDao().insertEventRow(testQueueEvent(pairingId = TEST_PAIRING_B))
        database.issuedEventIdDao().insertIssuedEventId(testIssuedEventId(TEST_PAIRING_A))
        database.issuedEventIdDao().insertIssuedEventId(testIssuedEventId(TEST_PAIRING_B))

        assertTrue(dao.fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 100))

        assertTrue(database.surfaceDao().getRecords(TEST_PAIRING_A).isEmpty())
        assertTrue(database.queueEventDao().getEvents(TEST_PAIRING_A).isEmpty())
        assertEquals(0L, database.issuedEventIdDao().countIssuedEventIds(TEST_PAIRING_A))
        assertEquals(PairingPartitionEntity.REVOKING, database.pairingDao().getPartition(TEST_PAIRING_A)?.state)

        assertEquals(1, database.surfaceDao().getRecords(TEST_PAIRING_B).size)
        assertEquals(1, database.queueEventDao().getEvents(TEST_PAIRING_B).size)
        assertEquals(1L, database.issuedEventIdDao().countIssuedEventIds(TEST_PAIRING_B))
        assertEquals(PairingPartitionEntity.ACTIVE, database.pairingDao().getPartition(TEST_PAIRING_B)?.state)
        assertNull(dao.getRevocation(TEST_PAIRING_B))
        assertEquals(
            setOf(TEST_PAIRING_A),
            dao.getPendingArtifacts().map(RevocationArtifactEntity::pairingId).toSet(),
        )
    }

    @Test
    fun missingPairingCannotCreateARevocationJournal() = runTest {
        assertFalse(dao.fenceJournalAndEraseState("missing", fencedAtEpochMs = 100))
        assertNull(dao.getRevocation("missing"))
        assertTrue(dao.getPendingArtifacts().isEmpty())
    }

    @Test
    fun artifactCompletionRejectsNegativeTimestampsWithoutMutatingTheJournal() = runTest {
        database.insertTestPairing()
        assertTrue(dao.fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 100))
        val artifact = dao.getPendingArtifacts(TEST_PAIRING_A).first()

        assertFailsWith<IllegalArgumentException> {
            dao.completeArtifact(
                artifact.pairingId,
                artifact.artifactKind,
                artifact.artifactReference,
                completedAtEpochMs = -1,
            )
        }

        assertNull(
            dao.getArtifacts(TEST_PAIRING_A)
                .single {
                    it.artifactKind == artifact.artifactKind &&
                        it.artifactReference == artifact.artifactReference
                }
                .completedAtEpochMs
        )
    }
}
