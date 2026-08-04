package com.calebc42.jetpacs.core.database

import androidx.sqlite.SQLiteException
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class JetpacsDatabaseTest {
    private lateinit var database: JetpacsDatabase

    @BeforeTest
    fun setUp() {
        database = inMemoryTestDatabase()
    }

    @AfterTest
    fun tearDown() {
        database.close()
    }

    @Test
    fun foreignKeysOrdinalsAndIdentifiersArePairingScoped() = runTest {
        assertFailsWith<SQLiteException> {
            database.surfaceDao().insertRecordRow(testSurface(pairingId = "missing"))
        }

        database.insertTestPairing(TEST_PAIRING_A)
        database.insertTestPairing(TEST_PAIRING_B)

        database.surfaceDao().insertRecordRow(
            testSurface(
                pairingId = TEST_PAIRING_A,
                surfaceId = "surface-a",
                firstSeenOrdinal = 1,
            )
        )
        assertFailsWith<SQLiteException> {
            database.surfaceDao().insertRecordRow(
                testSurface(
                    pairingId = TEST_PAIRING_A,
                    surfaceId = "same-ordinal",
                    firstSeenOrdinal = 1,
                )
            )
        }
        database.surfaceDao().insertRecordRow(
            testSurface(
                pairingId = TEST_PAIRING_B,
                surfaceId = "surface-b",
                firstSeenOrdinal = 1,
            )
        )
        assertFailsWith<SQLiteException> {
            database.surfaceDao().upsertDraft(
                testDraft(pairingId = TEST_PAIRING_B, surfaceId = "missing")
            )
        }

        database.queueEventDao().insertEventRow(
            testQueueEvent(
                pairingId = TEST_PAIRING_A,
                queueSequence = 1,
                eventId = "shared-event",
                dedupeKey = "same-key",
            )
        )
        assertFailsWith<SQLiteException> {
            database.queueEventDao().insertEventRow(
                testQueueEvent(
                    pairingId = TEST_PAIRING_A,
                    queueSequence = 2,
                    eventId = "shared-event",
                )
            )
        }
        database.queueEventDao().insertEventRow(
            testQueueEvent(
                pairingId = TEST_PAIRING_B,
                queueSequence = 1,
                eventId = "shared-event",
                dedupeKey = "same-key",
            )
        )

        database.issuedEventIdDao().insertIssuedEventId(
            testIssuedEventId(TEST_PAIRING_A, eventId = "shared-issued")
        )
        database.issuedEventIdDao().insertIssuedEventId(
            testIssuedEventId(TEST_PAIRING_B, eventId = "shared-issued")
        )
        assertFailsWith<SQLiteException> {
            database.issuedEventIdDao().insertIssuedEventId(
                testIssuedEventId(TEST_PAIRING_A, eventId = "shared-issued")
            )
        }

        assertEquals(1L, database.queueEventDao().countEvents(TEST_PAIRING_A))
        assertEquals(1L, database.queueEventDao().countEvents(TEST_PAIRING_B))
        assertEquals(1L, database.issuedEventIdDao().countIssuedEventIds(TEST_PAIRING_A))
        assertEquals(1L, database.issuedEventIdDao().countIssuedEventIds(TEST_PAIRING_B))
    }

    @Test
    fun mechanicalRowsDoNotOwnReducerCountersAndExposeRestorePrimitives() = runTest {
        database.insertTestPairing()
        val surfaceDao = database.surfaceDao()
        val queueDao = database.queueEventDao()

        surfaceDao.insertRecordRow(testSurface(surfaceId = "present", firstSeenOrdinal = 42))
        surfaceDao.insertRecordRow(
            testSurface(
                surfaceId = "tombstone",
                firstSeenOrdinal = 43,
                present = false,
            )
        )
        surfaceDao.upsertDraft(testDraft(surfaceId = "present", nodeId = "z"))
        surfaceDao.upsertDraft(testDraft(surfaceId = "present", nodeId = "a"))
        queueDao.insertEventRow(
            testQueueEvent(queueSequence = 8, eventId = "event-eight", dedupeKey = "replace")
        )
        queueDao.insertEventRow(
            testQueueEvent(queueSequence = 7, eventId = "event-seven")
        )

        assertEquals(testRuntime(), database.pairingDao().getRuntime(TEST_PAIRING_A))
        assertEquals(
            SurfaceCardinalityRow(total = 2, present = 1),
            surfaceDao.getCardinality(TEST_PAIRING_A),
        )
        assertEquals(
            listOf("a", "z"),
            surfaceDao.getDrafts(TEST_PAIRING_A).map(SurfaceDraftEntity::nodeId),
        )
        assertEquals(
            listOf(
                QueueEventIndexRow(7, "event-seven", "00000000000000000000000000000007", 61_000, null, 128),
                QueueEventIndexRow(8, "event-eight", "00000000000000000000000000000008", 61_000, "replace", 128),
            ),
            queueDao.getEventIndex(TEST_PAIRING_A),
        )

        assertEquals(1, surfaceDao.deleteDraft(TEST_PAIRING_A, "present", "a"))
        assertEquals(1, surfaceDao.deleteRecord(TEST_PAIRING_A, "present"))
        assertTrue(surfaceDao.getDrafts(TEST_PAIRING_A, "present").isEmpty())
        assertEquals("tombstone", surfaceDao.getRecords(TEST_PAIRING_A).single().surfaceId)

        val reducerChosenRuntime =
            testRuntime(nextQueueSequence = 9, nextSurfaceOrdinal = 44)
        assertEquals(1, database.pairingDao().updateRuntime(reducerChosenRuntime))
        assertEquals(reducerChosenRuntime, database.pairingDao().getRuntime(TEST_PAIRING_A))
    }

    @Test
    fun adapterPrimitivesArePairingScopedAndPreservePartitionMetadata() = runTest {
        database.insertTestPairing(TEST_PAIRING_A)
        database.insertTestPairing(TEST_PAIRING_B)
        val pairingDao = database.pairingDao()
        val before = pairingDao.getPartition(TEST_PAIRING_A)!!

        assertEquals(1, pairingDao.markPartitionRevoking(TEST_PAIRING_A))
        assertEquals(before.copy(state = PairingPartitionEntity.REVOKING), pairingDao.getPartition(TEST_PAIRING_A))
        assertEquals(0, pairingDao.markPartitionRevoking(TEST_PAIRING_A))

        database.surfaceDao().insertRecordRow(testSurface(pairingId = TEST_PAIRING_A))
        database.surfaceDao().upsertDraft(testDraft(pairingId = TEST_PAIRING_A))
        database.surfaceDao().insertRecordRow(testSurface(pairingId = TEST_PAIRING_B))
        assertEquals(1, database.surfaceDao().deleteAllRecords(TEST_PAIRING_A))
        assertTrue(database.surfaceDao().getRecords(TEST_PAIRING_A).isEmpty())
        assertTrue(database.surfaceDao().getDrafts(TEST_PAIRING_A).isEmpty())
        assertEquals(1, database.surfaceDao().getRecords(TEST_PAIRING_B).size)

        val queued = testQueueEvent(pairingId = TEST_PAIRING_A, pendingLocal = true)
        database.queueEventDao().insertEventRow(queued)
        database.queueEventDao().insertEventRow(testQueueEvent(pairingId = TEST_PAIRING_B))
        assertEquals(
            QueueEventVersionRow(
                queueSequence = queued.queueSequence,
                eventId = queued.eventId,
                storageGeneration = queued.storageGeneration,
                pendingLocal = true,
            ),
            database.queueEventDao().getEventVersionById(TEST_PAIRING_A, queued.eventId),
        )
        assertNull(database.queueEventDao().getEventVersionById(TEST_PAIRING_A, "missing"))
        assertEquals(
            1,
            database.queueEventDao().clearPendingLocal(
                TEST_PAIRING_A,
                queued.queueSequence,
            ),
        )
        assertEquals(
            false,
            database.queueEventDao()
                .getEventVersionById(TEST_PAIRING_A, queued.eventId)!!
                .pendingLocal,
        )
        assertEquals(
            0,
            database.queueEventDao().clearPendingLocal(
                TEST_PAIRING_A,
                queued.queueSequence,
            ),
        )
        assertEquals(1, database.queueEventDao().deleteAllEvents(TEST_PAIRING_A))
        assertEquals(0L, database.queueEventDao().countEvents(TEST_PAIRING_A))
        assertEquals(1L, database.queueEventDao().countEvents(TEST_PAIRING_B))
    }

    @Test
    fun issuedEventIdGuardOutlivesQueueRowsAndRetainsPairingIsolation() = runTest {
        database.insertTestPairing(TEST_PAIRING_A)
        database.insertTestPairing(TEST_PAIRING_B)
        val guardA =
            testIssuedEventId(
                pairingId = TEST_PAIRING_A,
                eventId = "reusable-later",
                reusableAfterEpochMs = TEST_SEVEN_DAYS_MS,
            )
        val guardB = guardA.copy(pairingId = TEST_PAIRING_B)
        database.issuedEventIdDao().insertIssuedEventId(guardA)
        database.issuedEventIdDao().insertIssuedEventId(guardB)
        database.queueEventDao().insertEventRow(
            testQueueEvent(eventId = guardA.eventId)
        )

        assertEquals(1, database.queueEventDao().deleteEvent(TEST_PAIRING_A, 1))
        assertNull(database.queueEventDao().getEventById(TEST_PAIRING_A, guardA.eventId))
        assertEquals(
            guardA,
            database.issuedEventIdDao().getIssuedEventId(TEST_PAIRING_A, guardA.eventId),
        )
        assertEquals(
            guardB,
            database.issuedEventIdDao().getIssuedEventId(TEST_PAIRING_B, guardB.eventId),
        )
        assertTrue(
            database.issuedEventIdDao()
                .getReusableAtOrBefore(TEST_PAIRING_A, TEST_SEVEN_DAYS_MS - 1, 10)
                .isEmpty()
        )
        assertEquals(
            listOf(guardA),
            database.issuedEventIdDao()
                .getReusableAtOrBefore(TEST_PAIRING_A, TEST_SEVEN_DAYS_MS, 10),
        )
    }

    @Test
    fun issuedEventIdsRestoreInDeterministicPortableOrder() = runTest {
        database.insertTestPairing()
        val late =
            testIssuedEventId(
                eventId = "z-late",
                issuedAtEpochMs = 200,
                reusableAfterEpochMs = 400,
            )
        val sameFloorB =
            testIssuedEventId(
                eventId = "b-same-floor",
                issuedAtEpochMs = 100,
                reusableAfterEpochMs = 300,
            )
        val sameFloorA = sameFloorB.copy(eventId = "a-same-floor")

        val dao = database.issuedEventIdDao()
        dao.insertIssuedEventId(late)
        dao.insertIssuedEventId(sameFloorB)
        dao.insertIssuedEventId(sameFloorA)

        assertEquals(
            listOf(sameFloorA, sameFloorB, late),
            dao.getIssuedEventIds(TEST_PAIRING_A),
        )
    }

    @Test
    fun entityConstructionRejectsImpossibleDurableRows() {
        assertFailsWith<IllegalArgumentException> {
            testSurface(staleAfterSeconds = 0)
        }
        assertFailsWith<IllegalArgumentException> {
            testSurface(present = false, specJson = "{}")
        }
        assertFailsWith<IllegalArgumentException> {
            testQueueEvent().copy(accountedByteCount = 0)
        }
        assertFailsWith<IllegalArgumentException> {
            testQueueEvent(storageGeneration = "ABC")
        }
        assertFailsWith<IllegalArgumentException> {
            testQueueEvent(
                occurredAtEpochMs = 1_000,
                queuedAtEpochMs = 2_000,
                expiresAtEpochMs = 1_500,
            )
        }
        assertFailsWith<IllegalArgumentException> {
            testQueueEvent(
                occurredAtEpochMs = 2_000,
                queuedAtEpochMs = 1_000,
                expiresAtEpochMs = 3_000,
            )
        }
        assertFailsWith<IllegalArgumentException> {
            testRuntime(
                forwardStepClaimEpochMs = 9_000,
                forwardStepClaimedAtElapsedMs = 100,
            )
        }
        assertFailsWith<IllegalArgumentException> {
            testRuntime(clockForwardClaimBootId = "boot-a")
        }
        assertFailsWith<IllegalArgumentException> {
            testRuntime(
                forwardStepClaimEpochMs = 9_000,
                clockForwardClaimBootId = " ",
                forwardStepClaimedAtElapsedMs = 100,
            )
        }
        assertFailsWith<IllegalArgumentException> {
            testIssuedEventId(reusableAfterEpochMs = -1)
        }
        assertFailsWith<IllegalArgumentException> {
            testIssuedEventId(issuedAtEpochMs = -1)
        }
        assertFailsWith<IllegalArgumentException> {
            val partition = testPartition()
            partition.copy(payloadKeyAlias = partition.credentialKeyAlias)
        }
        assertFailsWith<IllegalArgumentException> {
            PairingRevocationEntity(
                pairingId = TEST_PAIRING_A,
                pairingCreatedAtEpochMs = 10,
                fencedAtEpochMs = 9,
                finalizedAtEpochMs = null,
            )
        }
        assertFailsWith<IllegalArgumentException> {
            testIssuedEventId(
                issuedAtEpochMs = 2_000,
                reusableAfterEpochMs = 1_999,
            )
        }

        val validClaim =
            testRuntime(
                forwardStepClaimEpochMs = 9_000,
                clockForwardClaimBootId = "boot-a",
                forwardStepClaimedAtElapsedMs = 100,
            )
        assertEquals("boot-a", validClaim.clockForwardClaimBootId)
    }
}
