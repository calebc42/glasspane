package com.calebc42.jetpacs.core.database

import androidx.room3.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest

class JetpacsDatabasePersistenceTest {
    @Test
    fun protocolStateAndIssuedIdsSurviveAFileBackedReopen() = runTest {
        val directory = Files.createTempDirectory("jetpacs-room3-reopen-")
        val databasePath = directory.resolve("jetpacs-v3-test.db")
        var database: JetpacsDatabase? = null

        try {
            val runtime =
                testRuntime(
                    nextQueueSequence = 6,
                    nextSurfaceOrdinal = 4,
                    clockHighWaterEpochMs = 5_000,
                    forwardStepClaimEpochMs = 9_000,
                    clockForwardClaimBootId = "boot-a",
                    forwardStepClaimedAtElapsedMs = 100,
                    readyDisconnectedAtEpochMs = 4_000,
                )
            database = openDatabase(databasePath)
            database.insertTestPairing(runtime = runtime)
            database.surfaceDao().insertRecordRow(
                testSurface(
                    surfaceId = "durable-surface",
                    revision = 17,
                    firstSeenOrdinal = 3,
                    specJson = "{\"revision\":17}",
                    staleSpecJson = "{\"stale\":true}",
                    staleAfterSeconds = 30,
                    currentView = "details",
                )
            )
            database.surfaceDao().upsertDraft(
                testDraft(
                    surfaceId = "durable-surface",
                    nodeId = "nullable-input",
                    valueJson = "null",
                )
            )
            val retainedQueue =
                testQueueEvent(
                    queueSequence = 4,
                    eventId = "durable-event",
                    dedupeKey = "replaceable",
                    pendingLocal = true,
                    triggerIdentity = "trigger-a",
                )
            val deletedQueue =
                testQueueEvent(
                    queueSequence = 5,
                    eventId = "deleted-event",
                )
            val retainedGuard = testIssuedEventId(eventId = retainedQueue.eventId)
            val deletedQueueGuard = testIssuedEventId(eventId = deletedQueue.eventId)
            database.queueEventDao().insertEventRow(retainedQueue)
            database.queueEventDao().insertEventRow(deletedQueue)
            database.issuedEventIdDao().insertIssuedEventId(retainedGuard)
            database.issuedEventIdDao().insertIssuedEventId(deletedQueueGuard)
            assertEquals(1, database.queueEventDao().deleteEvent(TEST_PAIRING_A, 5))
            database.close()
            database = null

            database = openDatabase(databasePath)
            assertEquals(
                "credential-$TEST_PAIRING_A",
                database.pairingDao().getPartition(TEST_PAIRING_A)?.credentialKeyAlias,
            )
            assertEquals(runtime, database.pairingDao().getRuntime(TEST_PAIRING_A))
            assertEquals(
                17,
                database.surfaceDao()
                    .getRecord(TEST_PAIRING_A, "durable-surface")
                    ?.revision,
            )
            assertEquals(
                "null",
                database.surfaceDao()
                    .getDrafts(TEST_PAIRING_A, "durable-surface")
                    .single()
                    .valueJson,
            )
            assertEquals(
                retainedQueue,
                database.queueEventDao().getEvent(TEST_PAIRING_A, retainedQueue.queueSequence),
            )
            assertNull(
                database.queueEventDao().getEvent(TEST_PAIRING_A, deletedQueue.queueSequence)
            )
            assertEquals(
                retainedGuard,
                database.issuedEventIdDao()
                    .getIssuedEventId(TEST_PAIRING_A, retainedGuard.eventId),
            )
            assertEquals(
                deletedQueueGuard,
                database.issuedEventIdDao()
                    .getIssuedEventId(TEST_PAIRING_A, deletedQueueGuard.eventId),
            )
            assertNull(database.pairingDao().getPartition(TEST_PAIRING_B))
        } finally {
            database?.close()
            directory.toFile().deleteRecursively()
        }
    }

    @Test
    fun pendingRevocationArtifactsResumeAfterCloseAndReopen() = runTest {
        val directory = Files.createTempDirectory("jetpacs-room3-revocation-")
        val databasePath = directory.resolve("jetpacs-v3-revocation.db")
        var database: JetpacsDatabase? = null

        try {
            database = openDatabase(databasePath)
            database.insertTestPairing()
            assertTrue(
                database.revocationDao()
                    .fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 100)
            )
            val credentialArtifact =
                database.revocationDao()
                    .getPendingArtifacts(TEST_PAIRING_A)
                    .single {
                        it.artifactKind == RevocationArtifactEntity.CREDENTIAL_KEY_ALIAS
                    }
            assertEquals(
                1,
                database.revocationDao().completeArtifact(
                    credentialArtifact.pairingId,
                    credentialArtifact.artifactKind,
                    credentialArtifact.artifactReference,
                    completedAtEpochMs = 125,
                ),
            )
            database.close()
            database = null

            database = openDatabase(databasePath)
            assertEquals(
                listOf(RevocationArtifactEntity.PAYLOAD_KEY_ALIAS),
                database.revocationDao().getPendingArtifacts()
                    .map(RevocationArtifactEntity::artifactKind),
            )
            assertEquals(
                listOf(TEST_PAIRING_A),
                database.revocationDao().getOpenRevocations()
                    .map(PairingRevocationEntity::pairingId),
            )
            val remaining = database.revocationDao().getPendingArtifacts().single()
            assertEquals(
                1,
                database.revocationDao().completeArtifact(
                    remaining.pairingId,
                    remaining.artifactKind,
                    remaining.artifactReference,
                    completedAtEpochMs = 150,
                ),
            )
            assertTrue(
                database.revocationDao()
                    .finalizeRevocation(TEST_PAIRING_A, finalizedAtEpochMs = 200)
            )
            assertNull(database.pairingDao().getPartition(TEST_PAIRING_A))
            assertEquals(
                200,
                database.revocationDao().getRevocation(TEST_PAIRING_A)?.finalizedAtEpochMs,
            )
            assertTrue(database.revocationDao().getPendingArtifacts().isEmpty())
            assertEquals(2, database.revocationDao().getArtifacts(TEST_PAIRING_A).size)
            database.close()
            database = null

            database = openDatabase(databasePath)
            assertNull(database.pairingDao().getPartition(TEST_PAIRING_A))
            assertNull(database.pairingDao().getRuntime(TEST_PAIRING_A))
            assertEquals(
                PairingRevocationEntity(
                    pairingId = TEST_PAIRING_A,
                    pairingCreatedAtEpochMs = 10,
                    fencedAtEpochMs = 100,
                    finalizedAtEpochMs = 200,
                ),
                database.revocationDao().getRevocation(TEST_PAIRING_A),
            )
            assertTrue(
                database.revocationDao()
                    .fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 100)
            )
            assertFailsWith<IllegalStateException> {
                database.revocationDao()
                    .fenceJournalAndEraseState(TEST_PAIRING_A, fencedAtEpochMs = 101)
            }
            assertFailsWith<IllegalStateException> {
                database.pairingDao().insertPairing(testPartition(), testRuntime())
            }
        } finally {
            database?.close()
            directory.toFile().deleteRecursively()
        }
    }

    private fun openDatabase(path: Path): JetpacsDatabase =
        Room.databaseBuilder<JetpacsDatabase>(
            name = path.toString(),
            factory = JetpacsDatabaseConstructor::initialize,
        )
            .setDriver(BundledSQLiteDriver())
            .setQueryCoroutineContext(Dispatchers.IO)
            .build()
}
