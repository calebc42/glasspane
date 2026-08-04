// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.jetpacs.core.ebpstore

import androidx.room3.Room
import androidx.room3.useWriterConnection
import androidx.room3.withWriteTransaction
import androidx.sqlite.SQLiteException
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import com.calebc42.ebp.wire.ActivatePairingCommand
import com.calebc42.ebp.wire.ActivatePairingResult
import com.calebc42.ebp.wire.AdmitOutboxCommand
import com.calebc42.ebp.wire.ApplySurfaceCommand
import com.calebc42.ebp.wire.DraftWriteResult
import com.calebc42.ebp.wire.DurableDraft
import com.calebc42.ebp.wire.DurableOutboxEvent
import com.calebc42.ebp.wire.DurableOutboxPolicy
import com.calebc42.ebp.wire.DurablePairing
import com.calebc42.ebp.wire.DurableSurfaceRecord
import com.calebc42.ebp.wire.EbpWriteTransaction
import com.calebc42.ebp.wire.EventId
import com.calebc42.ebp.wire.IssuedEventId
import com.calebc42.ebp.wire.OutboxAdmissionResult
import com.calebc42.ebp.wire.OutboxLimits
import com.calebc42.ebp.wire.PairingFence
import com.calebc42.ebp.wire.PairingId
import com.calebc42.ebp.wire.PairingRuntime
import com.calebc42.ebp.wire.PutDraftCommand
import com.calebc42.ebp.wire.RevokePairingStateCommand
import com.calebc42.ebp.wire.RevokePairingStateResult
import com.calebc42.ebp.wire.SurfaceLimits
import com.calebc42.ebp.wire.SurfaceWriteResult
import com.calebc42.ebp.wire.activatePairing
import com.calebc42.ebp.wire.admitOutbox
import com.calebc42.ebp.wire.applySurface
import com.calebc42.ebp.wire.putDraft
import com.calebc42.ebp.wire.revokePairingState
import com.calebc42.jetpacs.core.database.IssuedEventIdEntity
import com.calebc42.jetpacs.core.database.JetpacsDatabase
import com.calebc42.jetpacs.core.database.JetpacsDatabaseConstructor
import com.calebc42.jetpacs.core.database.QueueEventEntity
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class RoomEbpDurableStoreTest {
    @Test
    fun activationAndFullSnapshotSurviveCloseAndReopen() = runTest {
        val directory = Files.createTempDirectory("jetpacs-ebp-store-reopen-")
        val path = directory.resolve("ebp-store.db")
        val pairing = pairingId('a')
        val id = eventId('1')
        var fixture: Fixture? = null

        try {
            fixture = fileFixture(path)
            assertTrue(
                fixture.store.activatePairing(ActivatePairingCommand(pairing, createdAtMs = 10))
                    is ActivatePairingResult.Activated,
            )
            val partition = fixture.database.pairingDao().getPartition(pairing.value)
            assertEquals("credential-${pairing.value}", partition?.credentialKeyAlias)
            assertEquals("payload-${pairing.value}", partition?.payloadKeyAlias)

            assertTrue(
                fixture.store.applySurface(surfaceCommand(pairing))
                    is SurfaceWriteResult.Applied,
            )
            assertEquals(
                DraftWriteResult.Committed,
                fixture.store.putDraft(
                    PutDraftCommand(
                        pairingId = pairing,
                        surfaceId = SURFACE_ID,
                        nodeId = "query",
                        value = JsonNull,
                    ),
                ),
            )
            fixture.store.write(pairing) {
                putRuntime(
                    runtime().copy(
                        effectiveClockHighWaterMs = 15,
                        readyDisconnectedAtMs = 14,
                    ),
                )
            }
            val command = eventCommand(
                pairing = pairing,
                eventId = id,
                pendingLocal = true,
                triggerIdentity = "trigger:catalog",
            )
            val admitted = fixture.store.admitOutbox(command) as OutboxAdmissionResult.Admitted
            assertEquals(1L, admitted.event.queueSequence)
            assertEquals(1, fixture.codec.encodeCalls)
            assertFalse(
                String(
                    fixture.database.queueEventDao()
                        .getEvent(pairing.value, 1)!!
                        .payloadEnvelope,
                    StandardCharsets.UTF_8,
                ).contains("event_id"),
            )
            fixture.database.close()
            fixture = null

            fixture = fileFixture(path)
            val snapshot = fixture.store.restore(pairing)
            assertEquals(DurablePairing(pairing, PairingFence.ACTIVE, 10), snapshot.pairing)
            assertEquals(
                PairingRuntime(
                    nextQueueSequence = 2,
                    nextSurfaceOrdinal = 2,
                    effectiveClockHighWaterMs = 15,
                    readyDisconnectedAtMs = 14,
                ),
                snapshot.runtime,
            )
            assertEquals(1, snapshot.surfaces.size)
            assertEquals(SURFACE_ID, snapshot.surfaces.single().surfaceId)
            assertEquals(buildJsonObject { put("kind", "catalog") }, snapshot.surfaces.single().spec)
            assertEquals(buildJsonObject { put("kind", "loading") }, snapshot.surfaces.single().staleSpec)
            assertEquals("details", snapshot.surfaces.single().currentView)
            assertEquals(JsonNull, snapshot.drafts.single().value)
            assertEquals(listOf(admitted.event), snapshot.outbox)
            assertEquals(
                listOf(IssuedEventId(id, 9, 604_800_009)),
                snapshot.issuedEventIds,
            )
            assertEquals(1, fixture.codec.decodeCalls)
            assertTrue(fixture.codec.boundaryChecks >= 1)
        } finally {
            fixture?.database?.close()
            directory.toFile().deleteRecursively()
        }
    }

    @Test
    fun sameOccurrenceIsIdempotentAndKeepsOneReceiptAndGeneration() = runTest {
        withFixture { fixture ->
            val pairing = pairingId('b')
            val id = eventId('2')
            activate(fixture.store, pairing)
            val command = eventCommand(pairing, id)

            val first = fixture.store.admitOutbox(command) as OutboxAdmissionResult.Admitted
            val generation = fixture.database.queueEventDao()
                .getEvent(pairing.value, first.event.queueSequence)!!
                .storageGeneration
            val retried = fixture.store.admitOutbox(command)
                as OutboxAdmissionResult.AlreadyAdmitted

            assertEquals(first.event, retried.event)
            assertEquals(1, fixture.codec.encodeCalls)
            assertEquals(1, fixture.codec.decodeCalls)
            assertEquals(1, fixture.generations.issued.size)
            assertEquals(
                generation,
                fixture.database.queueEventDao()
                    .getEvent(pairing.value, first.event.queueSequence)!!
                    .storageGeneration,
            )
            assertEquals(1L, fixture.database.queueEventDao().countEvents(pairing.value))
            assertEquals(
                listOf(id.value),
                fixture.database.issuedEventIdDao().getIssuedEventIds(pairing.value)
                    .map { it.eventId },
            )
            assertEquals(2L, fixture.store.restore(pairing).runtime.nextQueueSequence)
        }
    }

    @Test
    fun directDuplicateReceiptFailsAndPreservesTheOriginal() = runTest {
        withFixture { fixture ->
            val pairing = pairingId('8')
            val id = eventId('8')
            activate(fixture.store, pairing)
            val original = IssuedEventId(id, issuedAtMs = 10, reusableAfterMs = 20)
            fixture.store.write(pairing) { putIssuedEventId(original) }

            expectSqliteFailure {
                fixture.store.write(pairing) {
                    putIssuedEventId(
                        IssuedEventId(id, issuedAtMs = 30, reusableAfterMs = 40),
                    )
                }
            }

            assertEquals(listOf(original), fixture.store.restore(pairing).issuedEventIds)
            assertEquals(1L, fixture.database.issuedEventIdDao().countIssuedEventIds(pairing.value))
        }
    }

    @Test
    fun preparedInsertMustResolveAbsenceAndFailureRollsBackEarlierWrites() = runTest {
        withFixture { fixture ->
            val pairing = pairingId('9')
            val id = eventId('9')
            activate(fixture.store, pairing)
            val command = eventCommand(pairing, id)

            expectIllegalState {
                fixture.store.writePreparedOutbox(command) { preparation ->
                    putIssuedEventId(IssuedEventId(id, issuedAtMs = 1, reusableAfterMs = 2))
                    putPreparedOutbox(preparation, command.toDurableEvent(queueSequence = 1))
                }
            }

            val restored = fixture.store.restore(pairing)
            assertTrue(restored.outbox.isEmpty())
            assertTrue(restored.issuedEventIds.isEmpty())
            assertEquals(PairingRuntime(), restored.runtime)
            assertEquals(1, fixture.generations.issued.size)
        }
    }

    @Test
    fun pendingLocalClearIsOneWayAndRetrySeesTheUpdatedBit() = runTest {
        withFixture { fixture ->
            val pairing = pairingId('c')
            val id = eventId('3')
            activate(fixture.store, pairing)
            val command = eventCommand(pairing, id, pendingLocal = true)
            val first = fixture.store.admitOutbox(command) as OutboxAdmissionResult.Admitted

            assertTrue(fixture.store.write(pairing) {
                clearOutboxPendingLocal(first.event.queueSequence)
            })
            assertFalse(fixture.store.write(pairing) {
                clearOutboxPendingLocal(first.event.queueSequence)
            })
            val retried = fixture.store.admitOutbox(command)
                as OutboxAdmissionResult.AlreadyAdmitted

            assertFalse(retried.event.pendingLocal)
            assertEquals(first.event.queueSequence, retried.event.queueSequence)
            assertEquals(1, fixture.generations.issued.size)
            assertEquals(1, fixture.database.issuedEventIdDao().getIssuedEventIds(pairing.value).size)
        }
    }

    @Test
    fun pendingLocalChangeDuringDecodeIsOverlaidWithoutAStaleRetry() = runTest {
        withFixture { fixture ->
            val pairing = pairingId('1')
            val id = eventId('a')
            activate(fixture.store, pairing)
            val command = eventCommand(pairing, id, pendingLocal = true)
            val first = fixture.store.admitOutbox(command) as OutboxAdmissionResult.Admitted
            fixture.codec.onNextDecode = { metadata ->
                assertEquals(id, metadata.eventId)
                fixture.database.withWriteTransaction {
                    assertEquals(
                        1,
                        fixture.database.queueEventDao().clearPendingLocal(
                            pairing.value,
                            first.event.queueSequence,
                        ),
                    )
                }
            }

            val retried = fixture.store.admitOutbox(command)
                as OutboxAdmissionResult.AlreadyAdmitted

            assertFalse(retried.event.pendingLocal)
            assertEquals(1, fixture.codec.decodeCalls)
            assertEquals(1, fixture.codec.decodeHooksRun)
            assertEquals(1, fixture.codec.encodeCalls)
            assertEquals(1, fixture.generations.issued.size)
            assertEquals(1L, fixture.database.issuedEventIdDao().countIssuedEventIds(pairing.value))
        }
    }

    @Test
    fun credentialAndPayloadAliasesMustBeDistinct() = runTest {
        expectIllegalArgument {
            ProvisionedPairingAliases(
                credentialKeyAlias = "shared-key",
                payloadKeyAlias = "shared-key",
            )
        }
    }

    @Test
    fun capturedTransactionScopeIsClosedAfterTheWriteReturns() = runTest {
        withFixture { fixture ->
            val pairing = pairingId('d')
            activate(fixture.store, pairing)
            lateinit var captured: EbpWriteTransaction

            fixture.store.write(pairing) { captured = this }

            expectIllegalState { captured.runtime() }
        }
    }

    @Test
    fun exceptionFromWriteBlockRollsBackEveryMutation() = runTest {
        withFixture { fixture ->
            val pairing = pairingId('e')
            val id = eventId('4')
            activate(fixture.store, pairing)

            expectTestFailure {
                fixture.store.write(pairing) {
                    putSurface(
                        DurableSurfaceRecord(
                            surfaceId = SURFACE_ID,
                            revision = 1,
                            present = true,
                            spec = buildJsonObject { put("kind", "rolled-back") },
                            acceptedAtMs = 1,
                            firstSeenOrdinal = 1,
                        ),
                    )
                    putDraft(DurableDraft(SURFACE_ID, "query", JsonPrimitive("rolled-back")))
                    putIssuedEventId(IssuedEventId(id, issuedAtMs = 1, reusableAfterMs = 2))
                    putRuntime(runtime().copy(nextQueueSequence = 9, nextSurfaceOrdinal = 7))
                    throw TestFailure()
                }
            }

            val restored = fixture.store.restore(pairing)
            assertTrue(restored.surfaces.isEmpty())
            assertTrue(restored.drafts.isEmpty())
            assertTrue(restored.issuedEventIds.isEmpty())
            assertEquals(PairingRuntime(), restored.runtime)
        }
    }

    @Test
    fun staleRuntimeSequenceRetriesWithAFreshStorageGeneration() = runTest {
        withFixture { fixture ->
            val pairing = pairingId('f')
            val targetId = eventId('5')
            val competitorId = eventId('6')
            activate(fixture.store, pairing)

            fixture.codec.onNextEncode = { firstMetadata ->
                assertEquals(targetId, firstMetadata.eventId)
                val competitor = eventCommand(pairing, competitorId)
                val competitorGeneration = "f".repeat(32)
                val competitorMetadata = OutboxEnvelopeMetadata(
                    pairingId = pairing,
                    eventId = competitorId,
                    queueSequence = 1,
                    storageGeneration = competitorGeneration,
                    policy = competitor.policy,
                    occurredAtMs = competitor.occurredAtMs,
                    queuedAtMs = competitor.queuedAtMs,
                    expiresAtMs = competitor.expiresAtMs,
                    dedupeKey = competitor.dedupeKey,
                    accountedBytes = competitor.accountedBytes,
                    triggerIdentity = competitor.triggerIdentity,
                )
                fixture.database.withWriteTransaction {
                    fixture.database.queueEventDao().insertEventRow(
                        QueueEventEntity(
                            pairingId = pairing.value,
                            queueSequence = 1,
                            eventId = competitorId.value,
                            storageGeneration = competitorGeneration,
                            payloadEnvelope = fixture.codec.encodeUnchecked(
                                competitor.payload,
                                competitorMetadata,
                                "payload-${pairing.value}",
                            ),
                            accountedByteCount = competitor.accountedBytes,
                            policy = QueueEventEntity.POLICY_QUEUE,
                            occurredAtEpochMs = competitor.occurredAtMs,
                            queuedAtEpochMs = competitor.queuedAtMs,
                            expiresAtEpochMs = competitor.expiresAtMs,
                            dedupeKey = competitor.dedupeKey,
                            pendingLocal = competitor.pendingLocal,
                            triggerIdentity = competitor.triggerIdentity,
                        ),
                    )
                    fixture.database.issuedEventIdDao().insertIssuedEventId(
                        IssuedEventIdEntity(
                            pairingId = pairing.value,
                            eventId = competitorId.value,
                            issuedAtEpochMs = competitor.occurredAtMs,
                            reusableAfterEpochMs = competitor.occurredAtMs + 604_800_000,
                        ),
                    )
                    val runtime = fixture.database.pairingDao().getRuntime(pairing.value)!!
                    assertEquals(1, fixture.database.pairingDao().updateRuntime(
                        runtime.copy(nextQueueSequence = 2),
                    ))
                }
            }

            val admitted = fixture.store.admitOutbox(eventCommand(pairing, targetId))
                as OutboxAdmissionResult.Admitted

            assertEquals(2L, admitted.event.queueSequence)
            assertEquals(2, fixture.codec.encodeCalls)
            assertEquals(2, fixture.generations.issued.size)
            assertNotEquals(fixture.generations.issued[0], fixture.generations.issued[1])
            assertEquals(
                fixture.generations.issued[1],
                fixture.database.queueEventDao().getEvent(pairing.value, 2)!!.storageGeneration,
            )
            assertEquals(
                listOf(competitorId.value, targetId.value),
                fixture.database.queueEventDao().getEvents(pairing.value).map { it.eventId },
            )
            val restored = fixture.store.restore(pairing)
            assertEquals(3L, restored.runtime.nextQueueSequence)
            assertEquals(2, restored.issuedEventIds.size)
            assertEquals(
                setOf(competitorId, targetId),
                restored.issuedEventIds.map { it.eventId }.toSet(),
            )
        }
    }

    @Test
    fun residualRevokingPartitionWithoutJournalFailsClosed() = runTest {
        withFixture { fixture ->
            val pairing = pairingId('2')
            activate(fixture.store, pairing)
            assertEquals(1, fixture.database.pairingDao().markPartitionRevoking(pairing.value))

            expectIllegalState { fixture.store.restore(pairing) }
            expectIllegalState { fixture.store.write(pairing) { pairing() } }
        }
    }

    @Test
    fun finalizedRevocationRestoresSyntheticFenceAndCannotReactivate() = runTest {
        val directory = Files.createTempDirectory("jetpacs-ebp-store-revoked-")
        val path = directory.resolve("revoked.db")
        val pairing = pairingId('7')
        var fixture: Fixture? = null

        try {
            fixture = fileFixture(path)
            activate(fixture.store, pairing, createdAtMs = 10)
            fixture.store.admitOutbox(eventCommand(pairing, eventId('7')))
            val revoked = fixture.store.revokePairingState(
                RevokePairingStateCommand(pairing, fencedAtMs = 50),
            )
            assertEquals(
                RevokePairingStateResult.Revoked(
                    DurablePairing(pairing, PairingFence.REVOKING, createdAtMs = 10),
                ),
                revoked,
            )
            fixture.database.revocationDao().getPendingArtifacts(pairing.value).forEach { artifact ->
                assertEquals(
                    1,
                    fixture.database.revocationDao().completeArtifact(
                        pairingId = artifact.pairingId,
                        artifactKind = artifact.artifactKind,
                        artifactReference = artifact.artifactReference,
                        completedAtEpochMs = 60,
                    ),
                )
            }
            assertTrue(fixture.database.revocationDao().finalizeRevocation(pairing.value, 70))
            assertNull(fixture.database.pairingDao().getPartition(pairing.value))
            fixture.database.close()
            fixture = null

            fixture = fileFixture(path)
            val restored = fixture.store.restore(pairing)
            assertEquals(
                DurablePairing(pairing, PairingFence.REVOKING, createdAtMs = 10),
                restored.pairing,
            )
            assertEquals(PairingRuntime(), restored.runtime)
            assertTrue(restored.surfaces.isEmpty())
            assertTrue(restored.drafts.isEmpty())
            assertTrue(restored.outbox.isEmpty())
            assertTrue(restored.issuedEventIds.isEmpty())
            assertTrue(
                fixture.store.activatePairing(ActivatePairingCommand(pairing, createdAtMs = 80))
                    is ActivatePairingResult.Fenced,
            )
            assertNull(fixture.database.pairingDao().getPartition(pairing.value))
        } finally {
            fixture?.database?.close()
            directory.toFile().deleteRecursively()
        }
    }

    private suspend fun withFixture(block: suspend (Fixture) -> Unit) {
        val fixture = inMemoryFixture()
        try {
            block(fixture)
        } finally {
            fixture.database.close()
        }
    }

    private fun inMemoryFixture(): Fixture {
        val database = Room.inMemoryDatabaseBuilder<JetpacsDatabase>()
            .setDriver(BundledSQLiteDriver())
            .setQueryCoroutineContext(Dispatchers.IO)
            .build()
        return fixture(database)
    }

    private fun fileFixture(path: Path): Fixture {
        val database = Room.databaseBuilder<JetpacsDatabase>(
            name = path.toString(),
            factory = JetpacsDatabaseConstructor::initialize,
        )
            .setDriver(BundledSQLiteDriver())
            .setQueryCoroutineContext(Dispatchers.IO)
            .build()
        return fixture(database)
    }

    private fun fixture(database: JetpacsDatabase): Fixture {
        val codec = TrackingOpaqueCodec(database)
        val generations = SequenceGenerationSource()
        val store = RoomEbpDurableStore(
            database = database,
            aliasResolver = ProvisionedPairingAliasResolver { pairing ->
                ProvisionedPairingAliases(
                    credentialKeyAlias = "credential-${pairing.value}",
                    payloadKeyAlias = "payload-${pairing.value}",
                )
            },
            envelopeCodec = codec,
            generationSource = generations,
        )
        return Fixture(database, store, codec, generations)
    }

    private suspend fun activate(
        store: RoomEbpDurableStore,
        pairing: PairingId,
        createdAtMs: Long = 0,
    ) {
        assertTrue(
            store.activatePairing(ActivatePairingCommand(pairing, createdAtMs))
                is ActivatePairingResult.Activated,
        )
    }

    private fun surfaceCommand(pairing: PairingId) = ApplySurfaceCommand(
        pairingId = pairing,
        surfaceId = SURFACE_ID,
        revision = 4,
        spec = buildJsonObject { put("kind", "catalog") },
        staleSpec = buildJsonObject { put("kind", "loading") },
        staleAfterSeconds = 30,
        currentView = "details",
        acceptedAtMs = 12,
        retainedDraftIds = setOf("query"),
        limits = SurfaceLimits(maxPresentSurfaces = 16, maxSurfaceIds = 32),
    )

    private fun eventCommand(
        pairing: PairingId,
        eventId: EventId,
        pendingLocal: Boolean = false,
        triggerIdentity: String? = null,
    ) = AdmitOutboxCommand(
        pairingId = pairing,
        eventId = eventId,
        payload = eventPayload(eventId),
        policy = DurableOutboxPolicy.QUEUE,
        occurredAtMs = 9,
        queuedAtMs = 10,
        expiresAtMs = 20,
        corroboratedEffectiveNowMs = 10,
        dedupeKey = "intent:${eventId.value}",
        accountedBytes = 128,
        pendingLocal = pendingLocal,
        triggerIdentity = triggerIdentity,
        limits = OutboxLimits(maxEvents = 32, maxBytes = 1_000_000),
    )

    private fun AdmitOutboxCommand.toDurableEvent(queueSequence: Long) = DurableOutboxEvent(
        queueSequence = queueSequence,
        eventId = eventId,
        payload = payload,
        policy = policy,
        occurredAtMs = occurredAtMs,
        queuedAtMs = queuedAtMs,
        expiresAtMs = expiresAtMs,
        dedupeKey = dedupeKey,
        accountedBytes = accountedBytes,
        pendingLocal = pendingLocal,
        triggerIdentity = triggerIdentity,
    )

    private fun eventPayload(eventId: EventId) = buildJsonObject {
        put("event_id", eventId.value)
        put("occurred_at_ms", 9)
        put("queued_at_ms", 10)
        put("kind", "interaction")
    }

    private fun pairingId(hex: Char) = PairingId(hex.toString().repeat(32))

    private fun eventId(hex: Char) = EventId(hex.toString().repeat(32))

    private suspend fun expectIllegalState(block: suspend () -> Unit) {
        try {
            block()
            fail("expected IllegalStateException")
        } catch (_: IllegalStateException) {
            // Expected.
        }
    }

    private suspend fun expectIllegalArgument(block: suspend () -> Unit) {
        try {
            block()
            fail("expected IllegalArgumentException")
        } catch (_: IllegalArgumentException) {
            // Expected.
        }
    }

    private suspend fun expectSqliteFailure(block: suspend () -> Unit) {
        try {
            block()
            fail("expected SQLiteException")
        } catch (_: SQLiteException) {
            // Expected.
        }
    }

    private suspend fun expectTestFailure(block: suspend () -> Unit) {
        try {
            block()
            fail("expected TestFailure")
        } catch (_: TestFailure) {
            // Expected.
        }
    }

    private data class Fixture(
        val database: JetpacsDatabase,
        val store: RoomEbpDurableStore,
        val codec: TrackingOpaqueCodec,
        val generations: SequenceGenerationSource,
    )

    private class SequenceGenerationSource : StorageGenerationSource {
        val issued = mutableListOf<String>()

        override suspend fun next(): String =
            (issued.size + 1).toString(16).padStart(32, '0').also(issued::add)
    }

    private class TrackingOpaqueCodec(
        private val database: JetpacsDatabase,
    ) : OutboxPayloadEnvelopeCodec {
        var encodeCalls: Int = 0
            private set
        var decodeCalls: Int = 0
            private set
        var boundaryChecks: Int = 0
            private set
        var decodeHooksRun: Int = 0
            private set
        var onNextEncode: (suspend (OutboxEnvelopeMetadata) -> Unit)? = null
        var onNextDecode: (suspend (OutboxEnvelopeMetadata) -> Unit)? = null

        override suspend fun encode(
            payload: JsonObject,
            metadata: OutboxEnvelopeMetadata,
            payloadKeyAlias: String,
        ): ByteArray {
            assertOutsideRoomTransaction()
            encodeCalls += 1
            val envelope = encodeUnchecked(payload, metadata, payloadKeyAlias)
            onNextEncode?.also { hook ->
                onNextEncode = null
                hook(metadata)
            }
            return envelope
        }

        override suspend fun decode(
            envelope: ByteArray,
            metadata: OutboxEnvelopeMetadata,
            payloadKeyAlias: String,
        ): JsonObject {
            assertOutsideRoomTransaction()
            decodeCalls += 1
            onNextDecode?.also { hook ->
                onNextDecode = null
                decodeHooksRun += 1
                hook(metadata)
            }
            val clear = xor(envelope).toString(StandardCharsets.UTF_8)
            val separator = clear.indexOf('\u0000')
            check(separator >= 0) { "Malformed test envelope" }
            check(clear.substring(0, separator) == binding(metadata, payloadKeyAlias)) {
                "Envelope metadata or key alias changed"
            }
            return Json.parseToJsonElement(clear.substring(separator + 1)).jsonObject
        }

        fun encodeUnchecked(
            payload: JsonObject,
            metadata: OutboxEnvelopeMetadata,
            payloadKeyAlias: String,
        ): ByteArray {
            val clear = buildString {
                append(binding(metadata, payloadKeyAlias))
                append('\u0000')
                append(Json.encodeToString(JsonObject.serializer(), payload))
            }
            return xor(clear.toByteArray(StandardCharsets.UTF_8))
        }

        private suspend fun assertOutsideRoomTransaction() {
            database.useWriterConnection { connection ->
                check(!connection.inTransaction()) {
                    "Envelope codec was invoked while Room held a transaction"
                }
            }
            boundaryChecks += 1
        }

        private fun binding(
            metadata: OutboxEnvelopeMetadata,
            payloadKeyAlias: String,
        ): String = listOf(
            payloadKeyAlias,
            metadata.pairingId.value,
            metadata.eventId.value,
            metadata.queueSequence,
            metadata.storageGeneration,
            metadata.policy.name,
            metadata.occurredAtMs,
            metadata.queuedAtMs,
            metadata.expiresAtMs,
            metadata.dedupeKey ?: "-",
            metadata.accountedBytes,
            metadata.triggerIdentity ?: "-",
        ).joinToString("|")

        private fun xor(value: ByteArray): ByteArray =
            ByteArray(value.size) { index -> (value[index].toInt() xor XOR_MASK).toByte() }
    }

    private class TestFailure : RuntimeException()

    private companion object {
        const val SURFACE_ID = "app:catalog"
        const val XOR_MASK = 0x5a
    }
}
