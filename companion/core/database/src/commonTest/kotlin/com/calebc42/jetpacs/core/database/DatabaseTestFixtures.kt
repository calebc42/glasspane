package com.calebc42.jetpacs.core.database

import androidx.room3.Room
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.coroutines.Dispatchers

internal const val TEST_PAIRING_A = "pair-a"
internal const val TEST_PAIRING_B = "pair-b"
internal const val TEST_SEVEN_DAYS_MS = 7L * 24 * 60 * 60 * 1_000

internal fun inMemoryTestDatabase(): JetpacsDatabase =
    Room.inMemoryDatabaseBuilder<JetpacsDatabase>()
        .setDriver(BundledSQLiteDriver())
        .setQueryCoroutineContext(Dispatchers.IO)
        .build()

internal fun testPartition(
    pairingId: String = TEST_PAIRING_A,
    state: String = PairingPartitionEntity.ACTIVE,
) =
    PairingPartitionEntity(
        pairingId = pairingId,
        credentialKeyAlias = "credential-$pairingId",
        payloadKeyAlias = "payload-$pairingId",
        state = state,
        createdAtEpochMs = 10,
        lastAuthenticatedAtEpochMs = 20,
    )

internal fun testRuntime(
    pairingId: String = TEST_PAIRING_A,
    nextQueueSequence: Long = 1,
    nextSurfaceOrdinal: Long = 1,
    clockHighWaterEpochMs: Long = 0,
    forwardStepClaimEpochMs: Long? = null,
    clockForwardClaimBootId: String? = null,
    forwardStepClaimedAtElapsedMs: Long? = null,
    readyDisconnectedAtEpochMs: Long? = null,
) =
    PairingRuntimeEntity(
        pairingId = pairingId,
        nextQueueSequence = nextQueueSequence,
        nextSurfaceOrdinal = nextSurfaceOrdinal,
        clockHighWaterEpochMs = clockHighWaterEpochMs,
        forwardStepClaimEpochMs = forwardStepClaimEpochMs,
        clockForwardClaimBootId = clockForwardClaimBootId,
        forwardStepClaimedAtElapsedMs = forwardStepClaimedAtElapsedMs,
        readyDisconnectedAtEpochMs = readyDisconnectedAtEpochMs,
    )

internal suspend fun JetpacsDatabase.insertTestPairing(
    pairingId: String = TEST_PAIRING_A,
    runtime: PairingRuntimeEntity = testRuntime(pairingId),
) {
    pairingDao().insertPairing(testPartition(pairingId), runtime)
}

internal fun testSurface(
    pairingId: String = TEST_PAIRING_A,
    surfaceId: String = "surface-a",
    revision: Long = 1,
    firstSeenOrdinal: Long = 1,
    present: Boolean = true,
    specJson: String? = if (present) "{}" else null,
    staleSpecJson: String? = null,
    staleAfterSeconds: Long? = null,
    currentView: String? = null,
) =
    SurfaceRecordEntity(
        pairingId = pairingId,
        surfaceId = surfaceId,
        revision = revision,
        present = present,
        specJson = specJson,
        staleSpecJson = staleSpecJson,
        staleAfterSeconds = staleAfterSeconds,
        currentView = currentView,
        acceptedAtEpochMs = revision,
        firstSeenOrdinal = firstSeenOrdinal,
    )

internal fun testDraft(
    pairingId: String = TEST_PAIRING_A,
    surfaceId: String = "surface-a",
    nodeId: String = "input-a",
    valueJson: String = "\"draft\"",
) =
    SurfaceDraftEntity(
        pairingId = pairingId,
        surfaceId = surfaceId,
        nodeId = nodeId,
        valueJson = valueJson,
    )

internal fun testQueueEvent(
    pairingId: String = TEST_PAIRING_A,
    queueSequence: Long = 1,
    eventId: String = "event-$queueSequence",
    storageGeneration: String = queueSequence.toString(16).padStart(32, '0'),
    dedupeKey: String? = null,
    pendingLocal: Boolean = false,
    triggerIdentity: String? = null,
    occurredAtEpochMs: Long = 1_000,
    queuedAtEpochMs: Long = 1_000,
    expiresAtEpochMs: Long = 61_000,
) =
    QueueEventEntity(
        pairingId = pairingId,
        queueSequence = queueSequence,
        eventId = eventId,
        storageGeneration = storageGeneration,
        payloadEnvelope = byteArrayOf(1, queueSequence.toByte(), 3),
        accountedByteCount = 128,
        policy = QueueEventEntity.POLICY_QUEUE,
        occurredAtEpochMs = occurredAtEpochMs,
        queuedAtEpochMs = queuedAtEpochMs,
        expiresAtEpochMs = expiresAtEpochMs,
        dedupeKey = dedupeKey,
        pendingLocal = pendingLocal,
        triggerIdentity = triggerIdentity,
    )

internal fun testIssuedEventId(
    pairingId: String = TEST_PAIRING_A,
    eventId: String = "issued-event",
    issuedAtEpochMs: Long = 0,
    reusableAfterEpochMs: Long = TEST_SEVEN_DAYS_MS,
) =
    IssuedEventIdEntity(
        pairingId = pairingId,
        eventId = eventId,
        issuedAtEpochMs = issuedAtEpochMs,
        reusableAfterEpochMs = reusableAfterEpochMs,
    )

internal fun testArtifact(
    pairingId: String = TEST_PAIRING_A,
    kind: String = "file",
    reference: String = "artifact",
) =
    RevocationArtifactEntity(
        pairingId = pairingId,
        artifactKind = kind,
        artifactReference = reference,
    )
