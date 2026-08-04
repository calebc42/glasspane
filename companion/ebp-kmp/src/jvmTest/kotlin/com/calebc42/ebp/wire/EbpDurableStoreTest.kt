// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.ebp.wire

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class EbpDurableStoreTest {
    private val roomySurfaces = SurfaceLimits(maxPresentSurfaces = 16, maxSurfaceIds = 32)
    private val roomyOutbox = OutboxLimits(maxEvents = 32, maxBytes = 1_000_000)

    @Test
    fun commitFailureRollsBackDraftDedupeAndQueueCounterTogether() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('0')
        activate(store, pairing)
        assertTrue(store.applySurface(surface(pairing, revision = 1)) is SurfaceWriteResult.Applied)
        val initial = CommitDraftAndOutboxCommand(
            draft = PutDraftCommand(pairing, "app:catalog", "query", JsonNull),
            outbox = event(pairing, eventId('1'), dedupeKey = "search"),
        )
        assertTrue(store.commitDraftAndOutbox(initial) is DraftOutboxCommitResult.Committed)
        val newerDraft = JsonPrimitive("newer")
        assertEquals(
            DraftWriteResult.Committed,
            store.putDraft(PutDraftCommand(pairing, "app:catalog", "query", newerDraft)),
        )
        assertTrue(store.commitDraftAndOutbox(initial) is DraftOutboxCommitResult.Committed)
        assertEquals(newerDraft, store.restore(pairing).drafts.single().value)
        assertEquals(
            DraftWriteResult.Committed,
            store.putDraft(PutDraftCommand(pairing, "app:catalog", "query", JsonNull)),
        )
        store.failNextCommit()
        expectInjectedFailure {
            store.commitDraftAndOutbox(
                CommitDraftAndOutboxCommand(
                    draft = PutDraftCommand(
                        pairing, "app:catalog", "query", JsonPrimitive("next"),
                    ),
                    outbox = event(pairing, eventId('2'), dedupeKey = "search"),
                ),
            )
        }

        val restored = store.restore(pairing)
        assertEquals(1L, restored.surfaces.single().revision)
        assertEquals(JsonNull, restored.drafts.single().value)
        assertEquals(listOf(eventId('1')), restored.outbox.map { it.eventId })
        assertEquals(2L, restored.runtime.nextQueueSequence)
        assertEquals(listOf(eventId('1')), restored.issuedEventIds.map { it.eventId })
    }

    @Test
    fun queueFullInteractionCommitsDraftAndCommitFailureRollsItBack() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('1')
        activate(store, pairing)
        assertTrue(store.applySurface(surface(pairing, revision = 1)) is SurfaceWriteResult.Applied)
        val full = event(
            pairing = pairing,
            eventId = eventId('b'),
            limits = OutboxLimits(maxEvents = 0, maxBytes = 0),
        )

        assertEquals(
            DraftOutboxCommitResult.QueueFull,
            store.commitDraftAndOutbox(
                CommitDraftAndOutboxCommand(
                    draft = PutDraftCommand(
                        pairing, "app:catalog", "query", JsonPrimitive("kept"),
                    ),
                    outbox = full,
                ),
            ),
        )
        val committed = store.restore(pairing)
        assertEquals(JsonPrimitive("kept"), committed.drafts.single().value)
        assertTrue(committed.outbox.isEmpty())
        assertTrue(committed.issuedEventIds.isEmpty())
        assertEquals(1L, committed.runtime.nextQueueSequence)
        assertEquals(OutboxAdmissionResult.QueueFull, store.admitOutbox(full))

        store.failNextCommit()
        expectInjectedFailure {
            store.commitDraftAndOutbox(
                CommitDraftAndOutboxCommand(
                    draft = PutDraftCommand(
                        pairing, "app:catalog", "other", JsonPrimitive("rolled-back"),
                    ),
                    outbox = full.copy(eventId = eventId('c'), payload = eventPayload(eventId('c'), 9, 10)),
                ),
            )
        }
        val restored = store.restore(pairing)
        assertEquals(listOf("query"), restored.drafts.map { it.nodeId })
        assertTrue(restored.issuedEventIds.isEmpty())
    }

    @Test
    fun revocationFencesAndClearsOnlyItsPairingPartition() = runTest {
        val store = MemoryEbpDurableStore()
        val alpha = pairingId('a')
        val beta = pairingId('b')
        activate(store, alpha)
        activate(store, beta)

        store.applySurface(surface(alpha, revision = 3))
        store.applySurface(surface(beta, revision = 7))
        val alphaEvent = store.admitOutbox(event(alpha, eventId('3')))
        val betaEvent = store.admitOutbox(event(beta, eventId('3')))
        assertEquals(1L, (alphaEvent as OutboxAdmissionResult.Admitted).event.queueSequence)
        assertEquals(1L, (betaEvent as OutboxAdmissionResult.Admitted).event.queueSequence)

        assertEquals(
            DraftWriteResult.Committed,
            store.putDraft(PutDraftCommand(alpha, "app:catalog", "query", JsonNull)),
        )
        assertTrue(store.revokePairingState(
            RevokePairingStateCommand(alpha, fencedAtMs = 40),
        ) is
            RevokePairingStateResult.Revoked)
        assertEquals(
            SurfaceWriteResult.PairingNotActive,
            store.applySurface(surface(alpha, revision = 4)),
        )
        assertEquals(
            OutboxAdmissionResult.PairingNotActive,
            store.admitOutbox(event(alpha, eventId('4'))),
        )
        assertTrue(store.applySurface(surface(beta, revision = 8)) is SurfaceWriteResult.Applied)

        val alphaState = store.restore(alpha)
        val betaState = store.restore(beta)
        assertEquals(PairingFence.REVOKING, alphaState.pairing!!.fence)
        assertTrue(alphaState.surfaces.isEmpty())
        assertTrue(alphaState.drafts.isEmpty())
        assertTrue(alphaState.outbox.isEmpty())
        assertTrue(alphaState.issuedEventIds.isEmpty())
        assertEquals(PairingRuntime(), alphaState.runtime)
        assertEquals(PairingFence.ACTIVE, betaState.pairing!!.fence)
        assertEquals(8L, betaState.surfaces.single().revision)
        assertEquals(listOf(eventId('3')), betaState.outbox.map { it.eventId })
        assertEquals(listOf(eventId('3')), betaState.issuedEventIds.map { it.eventId })
    }

    @Test
    fun pairingMetadataAndFenceTransitionsAreStoreOwned() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('7')
        val original = DurablePairing(
            id = pairing,
            fence = PairingFence.ACTIVE,
            createdAtMs = 7,
        )
        store.write(pairing) {
            putPairing(original)
            putRuntime(PairingRuntime())
        }

        expectIllegalArgument {
            store.write(pairing) {
                putPairing(original.copy(createdAtMs = 8))
            }
        }
        expectIllegalArgument {
            store.write(pairing) {
                putPairing(original.copy(fence = PairingFence.REVOKING))
            }
        }
        assertEquals(original, store.restore(pairing).pairing)

        expectIllegalArgument {
            store.revokePairingState(
                RevokePairingStateCommand(pairing, fencedAtMs = 6),
            )
        }
        assertEquals(PairingFence.ACTIVE, store.restore(pairing).pairing!!.fence)
        assertTrue(
            store.revokePairingState(
                RevokePairingStateCommand(pairing, fencedAtMs = 11),
            ) is RevokePairingStateResult.Revoked,
        )
        assertTrue(
            store.revokePairingState(
                RevokePairingStateCommand(pairing, fencedAtMs = 11),
            ) is RevokePairingStateResult.Revoked,
        )
        expectIllegalState {
            store.revokePairingState(
                RevokePairingStateCommand(pairing, fencedAtMs = 12),
            )
        }
        expectIllegalArgument {
            store.write(pairing) {
                putPairing(original)
            }
        }
        assertEquals(PairingFence.REVOKING, store.restore(pairing).pairing!!.fence)

        expectIllegalArgument {
            store.write(pairingId('8')) {
                putPairing(
                    DurablePairing(pairingId('8'), PairingFence.REVOKING, createdAtMs = 0),
                )
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            RevokePairingStateCommand(pairing, EBP_MAX_SAFE_INTEGER + 1)
        }
        assertEquals(
            EBP_MAX_SAFE_INTEGER,
            DurablePairing(pairing, PairingFence.ACTIVE, EBP_MAX_SAFE_INTEGER).createdAtMs,
        )
        assertThrows(IllegalArgumentException::class.java) {
            DurablePairing(pairing, PairingFence.ACTIVE, EBP_MAX_SAFE_INTEGER + 1)
        }
    }

    @Test
    fun surfaceFirstSeenOrdinalIsImmutable() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('9')
        activate(store, pairing)
        assertTrue(store.applySurface(surface(pairing, revision = 1)) is SurfaceWriteResult.Applied)
        val original = store.restore(pairing).surfaces.single()

        expectIllegalArgument {
            store.write(pairing) {
                putSurface(original.copy(firstSeenOrdinal = 2))
            }
        }

        assertEquals(original, store.restore(pairing).surfaces.single())
    }

    @Test
    fun tombstoneKeepsRevisionFloorAndFirstSeenOrderUntilRelease() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('c')
        activate(store, pairing)

        val applied = store.applySurface(surface(pairing, revision = 3))
            as SurfaceWriteResult.Applied
        assertEquals(1L, applied.firstSeenOrdinal)
        assertEquals(
            SurfaceWriteResult.Stale(revisionFloor = 3, present = true),
            store.applySurface(surface(pairing, revision = 2)),
        )

        val removed = store.removeSurface(
            RemoveSurfaceCommand(pairing, "app:catalog", 4, 4, roomySurfaces),
        ) as SurfaceWriteResult.Applied
        assertFalse(removed.present)
        assertEquals(1L, removed.firstSeenOrdinal)
        assertEquals(
            SurfaceWriteResult.Stale(revisionFloor = 4, present = false),
            store.applySurface(surface(pairing, revision = 4)),
        )

        val revived = store.applySurface(surface(pairing, revision = 5))
            as SurfaceWriteResult.Applied
        assertEquals(1L, revived.firstSeenOrdinal)
        val second = store.applySurface(
            surface(pairing, surfaceId = "app:second", revision = 1),
        ) as SurfaceWriteResult.Applied
        assertEquals(2L, second.firstSeenOrdinal)
        assertEquals(
            listOf("app:catalog", "app:second"),
            store.restore(pairing).surfaces.map { it.surfaceId },
        )
        assertTrue(
            store.removeSurface(
                RemoveSurfaceCommand(pairing, "app:second", 2, 2, roomySurfaces),
            ) is SurfaceWriteResult.Applied,
        )
        store.write(pairing) {
            putDraft(DurableDraft("app:second", "orphan", JsonNull))
        }
        assertEquals(
            ReleaseSurfaceResult.Released,
            store.releaseSurface(ReleaseSurfaceCommand(pairing, "app:second")),
        )
        assertTrue(store.restore(pairing).drafts.isEmpty())
        val recreated = store.applySurface(
            surface(pairing, surfaceId = "app:second", revision = 3),
        ) as SurfaceWriteResult.Applied
        assertEquals(3L, recreated.firstSeenOrdinal)
        assertEquals(4L, store.restore(pairing).runtime.nextSurfaceOrdinal)
    }

    @Test
    fun outboxSequencesAreStrictIdempotentAndDedupeRespectsProtectedRecords() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('d')
        activate(store, pairing)

        val firstCommand = event(pairing, eventId('5'), dedupeKey = "same-intent")
        val first = store.admitOutbox(firstCommand) as OutboxAdmissionResult.Admitted
        assertEquals(1L, first.event.queueSequence)

        val retried = store.admitOutbox(firstCommand) as OutboxAdmissionResult.AlreadyAdmitted
        assertEquals(first.event, retried.event)
        assertEquals(2L, store.restore(pairing).runtime.nextQueueSequence)
        expectConflictingEventId {
            store.admitOutbox(
                firstCommand.copy(
                    payload = buildJsonObject {
                        put("event_id", eventId('5').value)
                        put("occurred_at_ms", firstCommand.occurredAtMs)
                        put("queued_at_ms", firstCommand.queuedAtMs)
                        put("changed", true)
                    },
                ),
            )
        }

        val protected = store.admitOutbox(
            event(
                pairing,
                eventId('6'),
                dedupeKey = "same-intent",
                protected = setOf(first.event.queueSequence),
            ),
        ) as OutboxAdmissionResult.Admitted
        assertEquals(2L, protected.event.queueSequence)
        assertTrue(protected.replacedQueueSequences.isEmpty())
        assertEquals(listOf(1L, 2L), store.restore(pairing).outbox.map { it.queueSequence })

        val replacement = store.admitOutbox(
            event(pairing, eventId('7'), dedupeKey = "same-intent"),
        ) as OutboxAdmissionResult.Admitted
        assertEquals(3L, replacement.event.queueSequence)
        assertEquals(listOf(1L, 2L), replacement.replacedQueueSequences)
        assertEquals(listOf(3L), store.restore(pairing).outbox.map { it.queueSequence })
        assertEquals(4L, store.restore(pairing).runtime.nextQueueSequence)

        val retryReplacement = store.admitOutbox(
            event(pairing, eventId('7'), dedupeKey = "same-intent"),
        ) as OutboxAdmissionResult.AlreadyAdmitted
        assertEquals(3L, retryReplacement.event.queueSequence)
        assertEquals(4L, store.restore(pairing).runtime.nextQueueSequence)

        val overflow = store.admitOutbox(
            event(
                pairing = pairing,
                eventId = eventId('8'),
                accountedBytes = Long.MAX_VALUE,
                limits = OutboxLimits(maxEvents = 32, maxBytes = Long.MAX_VALUE),
            ),
        )
        assertEquals(OutboxAdmissionResult.QueueFull, overflow)
        assertEquals(4L, store.restore(pairing).runtime.nextQueueSequence)
        assertEquals(
            listOf(eventId('5'), eventId('6'), eventId('7')),
            store.restore(pairing).issuedEventIds
                .map { it.eventId }
                .sortedBy { it.value },
        )

        val other = pairingId('e')
        activate(store, other)
        val sameIdElsewhere = store.admitOutbox(
            event(other, eventId('7'), dedupeKey = "same-intent"),
        ) as OutboxAdmissionResult.Admitted
        assertEquals(1L, sameIdElsewhere.event.queueSequence)
        assertEquals(listOf(eventId('7')), store.restore(other).issuedEventIds.map { it.eventId })
    }

    @Test
    fun expiryUsesTheDurableClockAndDoesNotDeleteProtectedSequences() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('f')
        activate(store, pairing)
        val first = store.admitOutbox(event(pairing, eventId('9'), expiresAtMs = 20))
            as OutboxAdmissionResult.Admitted
        val second = store.admitOutbox(event(pairing, eventId('a'), expiresAtMs = 30))
            as OutboxAdmissionResult.Admitted

        val protected = store.expireOutbox(
            ExpireOutboxCommand(
                pairingId = pairing,
                corroboratedEffectiveNowMs = 20,
                protectedQueueSequences = setOf(first.event.queueSequence),
            ),
        ) as ExpireOutboxResult.Expired
        assertTrue(protected.queueSequences.isEmpty())
        assertEquals(2L, protected.remaining)
        assertEquals(20L, store.restore(pairing).runtime.effectiveClockHighWaterMs)

        val expired = store.expireOutbox(
            ExpireOutboxCommand(pairing, corroboratedEffectiveNowMs = 30),
        ) as ExpireOutboxResult.Expired
        assertEquals(
            listOf(first.event.queueSequence, second.event.queueSequence),
            expired.queueSequences,
        )
        assertEquals(0L, expired.remaining)
        assertTrue(store.restore(pairing).outbox.isEmpty())
        assertEquals(30L, store.restore(pairing).runtime.effectiveClockHighWaterMs)
        assertEquals(
            listOf(eventId('9'), eventId('a')),
            store.restore(pairing).issuedEventIds.map { it.eventId },
        )
    }

    @Test
    fun eventPayloadMetadataMustBeTypedAndExactlyMatchAdmission() {
        val id = eventId('c')
        val valid = event(pairingId('2'), id)
        val malformed = listOf(
            buildJsonObject {
                put("occurred_at_ms", valid.occurredAtMs)
                put("queued_at_ms", valid.queuedAtMs)
            },
            buildJsonObject {
                put("event_id", 1)
                put("occurred_at_ms", valid.occurredAtMs)
                put("queued_at_ms", valid.queuedAtMs)
            },
            buildJsonObject {
                put("event_id", eventId('d').value)
                put("occurred_at_ms", valid.occurredAtMs)
                put("queued_at_ms", valid.queuedAtMs)
            },
            buildJsonObject {
                put("event_id", id.value)
                put("occurred_at_ms", valid.occurredAtMs.toString())
                put("queued_at_ms", valid.queuedAtMs)
            },
            buildJsonObject {
                put("event_id", id.value)
                put("occurred_at_ms", valid.occurredAtMs.toDouble())
                put("queued_at_ms", valid.queuedAtMs)
            },
            buildJsonObject {
                put("event_id", id.value)
                put("occurred_at_ms", valid.occurredAtMs + 1)
                put("queued_at_ms", valid.queuedAtMs)
            },
            buildJsonObject {
                put("event_id", id.value)
                put("occurred_at_ms", valid.occurredAtMs)
                put("queued_at_ms", valid.queuedAtMs.toString())
            },
            buildJsonObject {
                put("event_id", id.value)
                put("occurred_at_ms", valid.occurredAtMs)
                put("queued_at_ms", valid.queuedAtMs.toDouble())
            },
            buildJsonObject {
                put("event_id", id.value)
                put("occurred_at_ms", valid.occurredAtMs)
                put("queued_at_ms", valid.queuedAtMs + 1)
            },
        )

        malformed.forEach { payload ->
            assertThrows(IllegalArgumentException::class.java) {
                valid.copy(payload = payload)
            }
        }
    }

    @Test
    fun forwardClockClaimRequiresWallMonotonicAndBootIdentityTogether() {
        assertThrows(IllegalArgumentException::class.java) {
            PairingRuntime(
                clockForwardClaimWallMs = 1,
                clockForwardClaimMonotonicStartedMs = 2,
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            PairingRuntime(clockForwardClaimBootId = "boot")
        }
        assertThrows(IllegalArgumentException::class.java) {
            PairingRuntime(
                clockForwardClaimWallMs = 1,
                clockForwardClaimMonotonicStartedMs = 2,
                clockForwardClaimBootId = " ",
            )
        }
        assertEquals(
            "boot",
            PairingRuntime(
                clockForwardClaimWallMs = 1,
                clockForwardClaimMonotonicStartedMs = 2,
                clockForwardClaimBootId = "boot",
            ).clockForwardClaimBootId,
        )
    }

    @Test
    fun pendingLocalProgressDoesNotMakeAnOccurrenceConflictOnRetry() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('3')
        val id = eventId('e')
        activate(store, pairing)
        val command = event(pairing, id, pendingLocal = true)
        val admitted = store.admitOutbox(command) as OutboxAdmissionResult.Admitted
        assertTrue(admitted.event.pendingLocal)

        assertTrue(store.write(pairing) {
            clearOutboxPendingLocal(admitted.event.queueSequence)
        })
        val retried = store.admitOutbox(command) as OutboxAdmissionResult.AlreadyAdmitted
        assertFalse(retried.event.pendingLocal)
        assertEquals(1L, retried.event.queueSequence)
        assertEquals(2L, store.restore(pairing).runtime.nextQueueSequence)
        assertEquals(listOf(id), store.restore(pairing).issuedEventIds.map { it.eventId })
    }

    @Test
    fun issuedIdSurvivesQueueDeletionAndRejectsReuseUntilTheExactFloor() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('4')
        val id = eventId('f')
        val issuedAt = 100L
        val reusableAt = issuedAt + EVENT_ID_RETENTION_FLOOR_MS
        activate(store, pairing)
        val first = store.admitOutbox(
            event(
                pairing = pairing,
                eventId = id,
                occurredAtMs = issuedAt,
                queuedAtMs = issuedAt,
                expiresAtMs = issuedAt + 1,
            ),
        ) as OutboxAdmissionResult.Admitted

        store.write(pairing) { deleteOutbox(first.event.queueSequence) }
        val restoredAfterQueueDelete = store.restore(pairing)
        assertTrue(restoredAfterQueueDelete.outbox.isEmpty())
        assertEquals(
            listOf(IssuedEventId(id, issuedAt, reusableAt)),
            restoredAfterQueueDelete.issuedEventIds,
        )

        expectEventIdReuseRejected {
            store.admitOutbox(
                event(
                    pairing = pairing,
                    eventId = id,
                    occurredAtMs = reusableAt - 1,
                    queuedAtMs = reusableAt - 1,
                    expiresAtMs = reusableAt,
                ),
            )
        }
        assertEquals(
            listOf(IssuedEventId(id, issuedAt, reusableAt)),
            store.restore(pairing).issuedEventIds,
        )

        val reused = store.admitOutbox(
            event(
                pairing = pairing,
                eventId = id,
                occurredAtMs = reusableAt,
                queuedAtMs = reusableAt,
                expiresAtMs = reusableAt + 1,
            ),
        ) as OutboxAdmissionResult.Admitted
        assertEquals(2L, reused.event.queueSequence)
        assertEquals(
            listOf(
                IssuedEventId(
                    eventId = id,
                    issuedAtMs = reusableAt,
                    reusableAfterMs = reusableAt + EVENT_ID_RETENTION_FLOOR_MS,
                ),
            ),
            store.restore(pairing).issuedEventIds,
        )
    }

    @Test
    fun issuedIdRetentionReachesSafeIntegerCeilingWithoutSaturation() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('5')
        val id = eventId('d')
        val latestIssuedAt = LATEST_EVENT_ID_ISSUED_AT_MS
        activate(store, pairing)
        val admitted = store.admitOutbox(
            event(
                pairing = pairing,
                eventId = id,
                occurredAtMs = latestIssuedAt,
                queuedAtMs = EBP_MAX_SAFE_INTEGER,
                expiresAtMs = EBP_MAX_SAFE_INTEGER,
                corroboratedEffectiveNowMs = EBP_MAX_SAFE_INTEGER,
            ),
        ) as OutboxAdmissionResult.Admitted
        assertEquals(EBP_MAX_SAFE_INTEGER, admitted.event.queuedAtMs)
        assertEquals(EBP_MAX_SAFE_INTEGER, admitted.event.expiresAtMs)
        assertEquals(
            IssuedEventId(id, latestIssuedAt, EBP_MAX_SAFE_INTEGER),
            store.restore(pairing).issuedEventIds.single(),
        )

        store.write(pairing) { deleteOutbox(admitted.event.queueSequence) }
        assertThrows(IllegalArgumentException::class.java) {
            event(
                pairing = pairing,
                eventId = id,
                occurredAtMs = latestIssuedAt + 1,
                queuedAtMs = latestIssuedAt + 1,
                expiresAtMs = EBP_MAX_SAFE_INTEGER,
            )
        }
        assertEquals(
            listOf(IssuedEventId(id, latestIssuedAt, EBP_MAX_SAFE_INTEGER)),
            store.restore(pairing).issuedEventIds,
        )
    }

    @Test
    fun outboxAdmissionRejectsEveryTimestampAboveEbpSafeInteger() {
        val pairing = pairingId('5')
        val id = eventId('f')
        val tooLarge = EBP_MAX_SAFE_INTEGER + 1

        assertThrows(IllegalArgumentException::class.java) {
            event(pairing, id, occurredAtMs = tooLarge, queuedAtMs = tooLarge, expiresAtMs = tooLarge)
        }
        assertThrows(IllegalArgumentException::class.java) {
            event(pairing, id, queuedAtMs = tooLarge, expiresAtMs = tooLarge)
        }
        assertThrows(IllegalArgumentException::class.java) {
            event(pairing, id, expiresAtMs = tooLarge)
        }
        assertThrows(IllegalArgumentException::class.java) {
            event(pairing, id, corroboratedEffectiveNowMs = tooLarge)
        }
    }

    @Test
    fun issuedIdPruningUsesDurableClockAndAStableBatchLimit() = runTest {
        val store = MemoryEbpDurableStore()
        val pairing = pairingId('6')
        val ids = listOf(eventId('1'), eventId('2'), eventId('3'))
        activate(store, pairing)
        ids.forEachIndexed { index, id ->
            val time = index.toLong() + 1
            assertTrue(
                store.admitOutbox(
                    event(
                        pairing = pairing,
                        eventId = id,
                        occurredAtMs = time,
                        queuedAtMs = time,
                        expiresAtMs = 10,
                    ),
                ) is OutboxAdmissionResult.Admitted,
            )
        }
        store.write(pairing) { deleteAllOutbox() }
        assertEquals(ids, store.restore(pairing).issuedEventIds.map { it.eventId })

        val beforeFloor = store.pruneIssuedEventIds(
            PruneIssuedEventIdsCommand(pairing, EVENT_ID_RETENTION_FLOOR_MS, limit = 1),
        ) as PruneIssuedEventIdsResult.Pruned
        assertTrue(beforeFloor.eventIds.isEmpty())

        val firstBatch = store.pruneIssuedEventIds(
            PruneIssuedEventIdsCommand(pairing, EVENT_ID_RETENTION_FLOOR_MS + 2, limit = 1),
        ) as PruneIssuedEventIdsResult.Pruned
        assertEquals(listOf(ids[0]), firstBatch.eventIds)
        assertEquals(listOf(ids[1], ids[2]), store.restore(pairing).issuedEventIds.map { it.eventId })

        val secondBatch = store.pruneIssuedEventIds(
            PruneIssuedEventIdsCommand(pairing, EVENT_ID_RETENTION_FLOOR_MS + 2, limit = 1),
        ) as PruneIssuedEventIdsResult.Pruned
        assertEquals(listOf(ids[1]), secondBatch.eventIds)
        assertEquals(listOf(ids[2]), store.restore(pairing).issuedEventIds.map { it.eventId })

        val finalBatch = store.pruneIssuedEventIds(
            PruneIssuedEventIdsCommand(pairing, EVENT_ID_RETENTION_FLOOR_MS + 3, limit = 8),
        ) as PruneIssuedEventIdsResult.Pruned
        assertEquals(listOf(ids[2]), finalBatch.eventIds)
        assertTrue(store.restore(pairing).issuedEventIds.isEmpty())
        assertEquals(
            EVENT_ID_RETENTION_FLOOR_MS + 3,
            store.restore(pairing).runtime.effectiveClockHighWaterMs,
        )
    }

    private suspend fun activate(store: EbpDurableStore, pairing: PairingId) {
        assertTrue(
            store.activatePairing(ActivatePairingCommand(pairing, createdAtMs = 0))
                is ActivatePairingResult.Activated,
        )
    }

    private fun surface(
        pairing: PairingId,
        surfaceId: String = "app:catalog",
        revision: Long,
    ) = ApplySurfaceCommand(
        pairingId = pairing,
        surfaceId = surfaceId,
        revision = revision,
        spec = buildJsonObject { put("kind", "catalog") },
        acceptedAtMs = revision,
        retainedDraftIds = setOf("query"),
        limits = roomySurfaces,
    )

    private fun event(
        pairing: PairingId,
        eventId: EventId,
        dedupeKey: String? = null,
        protected: Set<Long> = emptySet(),
        occurredAtMs: Long = 9,
        queuedAtMs: Long = 10,
        expiresAtMs: Long = 20,
        corroboratedEffectiveNowMs: Long = queuedAtMs,
        accountedBytes: Long = 100,
        pendingLocal: Boolean = false,
        limits: OutboxLimits = roomyOutbox,
    ) = AdmitOutboxCommand(
        pairingId = pairing,
        eventId = eventId,
        payload = eventPayload(eventId, occurredAtMs, queuedAtMs),
        policy = DurableOutboxPolicy.QUEUE,
        occurredAtMs = occurredAtMs,
        queuedAtMs = queuedAtMs,
        expiresAtMs = expiresAtMs,
        corroboratedEffectiveNowMs = corroboratedEffectiveNowMs,
        dedupeKey = dedupeKey,
        accountedBytes = accountedBytes,
        pendingLocal = pendingLocal,
        protectedQueueSequences = protected,
        limits = limits,
    )

    private fun eventPayload(
        eventId: EventId,
        occurredAtMs: Long,
        queuedAtMs: Long,
    ): JsonObject = buildJsonObject {
        put("event_id", eventId.value)
        put("occurred_at_ms", occurredAtMs)
        put("queued_at_ms", queuedAtMs)
    }

    private fun pairingId(hex: Char): PairingId =
        PairingId(hex.toString().repeat(32))

    private fun eventId(hex: Char): EventId =
        EventId(hex.toString().repeat(32))

    private suspend fun expectInjectedFailure(block: suspend () -> Unit) {
        var failed = false
        try {
            block()
        } catch (_: InjectedStoreFailure) {
            failed = true
        }
        assertTrue("expected injected commit failure", failed)
    }

    private suspend fun expectConflictingEventId(block: suspend () -> Unit) {
        var failed = false
        try {
            block()
        } catch (_: ConflictingEventId) {
            failed = true
        }
        assertTrue("expected conflicting EventId failure", failed)
    }

    private suspend fun expectEventIdReuseRejected(block: suspend () -> Unit) {
        var failed = false
        try {
            block()
        } catch (_: EventIdReuseBeforeRetention) {
            failed = true
        }
        assertTrue("expected EventId retention-floor rejection", failed)
    }

    private suspend fun expectIllegalArgument(block: suspend () -> Unit) {
        var failed = false
        try {
            block()
        } catch (_: IllegalArgumentException) {
            failed = true
        }
        assertTrue("expected illegal-argument failure", failed)
    }

    private suspend fun expectIllegalState(block: suspend () -> Unit) {
        var failed = false
        try {
            block()
        } catch (_: IllegalStateException) {
            failed = true
        }
        assertTrue("expected illegal-state failure", failed)
    }
}
