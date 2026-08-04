// SPDX-License-Identifier: GPL-3.0-or-later
// Rollback-capable reference oracle for every durable-store adapter.
package com.calebc42.ebp.wire

/** Deterministic commit failure used by backend-neutral transaction tests. */
class InjectedStoreFailure(message: String = "injected durable-store commit failure") :
    RuntimeException(message)

/**
 * Pure common-Kotlin oracle. The protocol actor is the single writer, so this
 * implementation intentionally supplies transaction isolation by copy/commit
 * rather than a JVM lock. A thrown block or injected commit failure discards
 * the private copy.
 */
class MemoryEbpDurableStore : EbpDurableStore {
    private data class Partition(
        var pairing: DurablePairing? = null,
        var runtime: PairingRuntime = PairingRuntime(),
        var revocationFencedAtMs: Long? = null,
        val surfaces: LinkedHashMap<String, DurableSurfaceRecord> = LinkedHashMap(),
        val drafts: LinkedHashMap<Pair<String, String>, DurableDraft> = LinkedHashMap(),
        val outbox: LinkedHashMap<Long, DurableOutboxEvent> = LinkedHashMap(),
        val issuedEventIds: LinkedHashMap<EventId, IssuedEventId> = LinkedHashMap(),
    ) {
        fun copyForWrite(): Partition = Partition(
            pairing = pairing,
            runtime = runtime,
            revocationFencedAtMs = revocationFencedAtMs,
            surfaces = LinkedHashMap(surfaces),
            drafts = LinkedHashMap(drafts),
            outbox = LinkedHashMap(outbox),
            issuedEventIds = LinkedHashMap(issuedEventIds),
        )
    }

    private val partitions = LinkedHashMap<PairingId, Partition>()
    private val preparationOwner = Any()
    private var nextCommitFailure: Throwable? = null

    private class MemoryPreparedOutboxAdmission(
        override val pairingId: PairingId,
        override val eventId: EventId,
        val command: AdmitOutboxCommand,
        val owner: Any,
    ) : PreparedOutboxAdmission {
        private var open = true

        fun checkOpen() {
            check(open) { "prepared outbox capability is closed" }
        }

        fun close() {
            open = false
        }
    }

    /** Fail the next transaction that reaches commit; the block still runs. */
    fun failNextCommit(cause: Throwable = InjectedStoreFailure()) {
        check(nextCommitFailure == null) { "a commit failure is already armed" }
        nextCommitFailure = cause
    }

    override suspend fun restore(pairingId: PairingId): DurableSnapshot {
        val state = partitions[pairingId] ?: return DurableSnapshot.empty()
        return DurableSnapshot(
            pairing = state.pairing,
            runtime = state.runtime,
            surfaces = state.surfaces.values.sortedBy { it.firstSeenOrdinal },
            drafts = state.drafts.values.sortedWith(
                compareBy<DurableDraft> { it.surfaceId }.thenBy { it.nodeId },
            ),
            outbox = state.outbox.values.sortedBy { it.queueSequence },
            issuedEventIds = state.issuedEventIds.values.sortedWith(
                compareBy<IssuedEventId> { it.reusableAfterMs }
                    .thenBy { it.eventId.value },
            ),
        )
    }

    override suspend fun <T> write(
        pairingId: PairingId,
        block: suspend EbpWriteTransaction.() -> T,
    ): T {
        val working = partitions[pairingId]?.copyForWrite() ?: Partition()
        val transaction = MemoryTransaction(pairingId, working, preparationOwner)
        val result = try {
            transaction.block()
        } catch (failure: Throwable) {
            transaction.close()
            throw failure
        }
        transaction.close()
        nextCommitFailure?.let { failure ->
            nextCommitFailure = null
            throw failure
        }
        if (working.pairing == null) partitions.remove(pairingId)
        else partitions[pairingId] = working
        return result
    }

    override suspend fun <T> writePreparedOutbox(
        command: AdmitOutboxCommand,
        block: suspend EbpWriteTransaction.(PreparedOutboxAdmission) -> T,
    ): T {
        val preparation = MemoryPreparedOutboxAdmission(
            pairingId = command.pairingId,
            eventId = command.eventId,
            command = command,
            owner = preparationOwner,
        )
        return try {
            write(command.pairingId) { block(preparation) }
        } finally {
            preparation.close()
        }
    }

    private class MemoryTransaction(
        private val pairingId: PairingId,
        private val state: Partition,
        private val preparationOwner: Any,
    ) : EbpWriteTransaction {
        private var open = true
        private var resolvedPreparation: MemoryPreparedOutboxAdmission? = null
        private var resolvedPreparationWasAbsent = false

        fun close() { open = false }

        private fun checkOpen() = check(open) { "transaction scope is closed" }
        private fun checkPartition() = check(
            state.pairing?.fence == PairingFence.ACTIVE,
        ) { "pairing-owned state can only be written for an ACTIVE pairing" }

        override suspend fun pairing(): DurablePairing? {
            checkOpen()
            return state.pairing
        }

        override suspend fun putPairing(pairing: DurablePairing) {
            checkOpen()
            require(pairing.id == pairingId) { "cross-partition pairing write" }
            val current = state.pairing
            if (current == null) {
                require(pairing.fence == PairingFence.ACTIVE) {
                    "a pairing must be created ACTIVE"
                }
            } else {
                require(pairing.createdAtMs == current.createdAtMs) {
                    "pairing creation time is immutable"
                }
                require(pairing.fence == current.fence) {
                    "generic pairing writes cannot change the revocation fence"
                }
            }
            state.pairing = pairing
        }

        override suspend fun fenceAndErasePairingState(
            fencedAtMs: Long,
        ): DurablePairing? {
            checkOpen()
            requireEbpTimestamp(fencedAtMs, "fencedAtMs")
            val current = state.pairing ?: return null
            require(fencedAtMs >= current.createdAtMs) {
                "revocation fence cannot predate pairing creation"
            }
            val fenced = current.copy(fence = PairingFence.REVOKING)
            if (current.fence == PairingFence.ACTIVE) {
                state.revocationFencedAtMs = fencedAtMs
            } else {
                val originalFencedAtMs = state.revocationFencedAtMs
                check(originalFencedAtMs != null) {
                    "revoking pairing is missing its durable fence record"
                }
                check(originalFencedAtMs == fencedAtMs) {
                    "a repeated revocation must retain its original fence time"
                }
            }
            state.pairing = fenced
            state.surfaces.clear()
            state.drafts.clear()
            state.outbox.clear()
            state.issuedEventIds.clear()
            state.runtime = PairingRuntime()
            return fenced
        }

        override suspend fun runtime(): PairingRuntime {
            checkOpen()
            return state.runtime
        }

        override suspend fun putRuntime(runtime: PairingRuntime) {
            checkOpen()
            checkPartition()
            state.runtime = runtime
        }

        override suspend fun surface(surfaceId: String): DurableSurfaceRecord? {
            checkOpen()
            return state.surfaces[surfaceId]
        }

        override suspend fun surfaceCardinality(): SurfaceCardinality {
            checkOpen()
            return SurfaceCardinality(
                total = state.surfaces.size.toLong(),
                present = state.surfaces.values.count { it.present }.toLong(),
            )
        }

        override suspend fun putSurface(record: DurableSurfaceRecord) {
            checkOpen()
            checkPartition()
            val current = state.surfaces[record.surfaceId]
            require(current == null || current.firstSeenOrdinal == record.firstSeenOrdinal) {
                "surface first-seen ordinal is immutable"
            }
            val ordinalOwner = state.surfaces.values.firstOrNull {
                it.firstSeenOrdinal == record.firstSeenOrdinal &&
                    it.surfaceId != record.surfaceId
            }
            require(ordinalOwner == null) {
                "surface first-seen ordinal already belongs to another surface"
            }
            state.surfaces[record.surfaceId] = record
        }

        override suspend fun deleteSurface(surfaceId: String) {
            checkOpen()
            checkPartition()
            state.surfaces.remove(surfaceId)
            state.drafts.keys.removeAll { it.first == surfaceId }
        }

        override suspend fun deleteAllSurfaces() {
            checkOpen()
            checkPartition()
            state.surfaces.clear()
            state.drafts.clear()
        }

        override suspend fun drafts(surfaceId: String): List<DurableDraft> {
            checkOpen()
            return state.drafts.values.filter { it.surfaceId == surfaceId }
        }

        override suspend fun putDraft(draft: DurableDraft) {
            checkOpen()
            checkPartition()
            require(draft.surfaceId in state.surfaces) {
                "draft requires an existing parent surface"
            }
            state.drafts[draft.surfaceId to draft.nodeId] = draft
        }

        override suspend fun deleteDraft(surfaceId: String, nodeId: String) {
            checkOpen()
            checkPartition()
            state.drafts.remove(surfaceId to nodeId)
        }

        override suspend fun deleteDrafts(surfaceId: String) {
            checkOpen()
            checkPartition()
            state.drafts.keys.removeAll { it.first == surfaceId }
        }

        override suspend fun outboxIndex(): List<DurableOutboxIndexEntry> {
            checkOpen()
            return state.outbox.values.sortedBy { it.queueSequence }.map { event ->
                DurableOutboxIndexEntry(
                    queueSequence = event.queueSequence,
                    eventId = event.eventId,
                    expiresAtMs = event.expiresAtMs,
                    dedupeKey = event.dedupeKey,
                    accountedBytes = event.accountedBytes,
                )
            }
        }

        override suspend fun resolvePreparedOutbox(
            preparation: PreparedOutboxAdmission,
        ): DurableOutboxEvent? {
            val prepared = requirePreparation(preparation)
            check(resolvedPreparation == null) {
                "prepared outbox capability was already resolved"
            }
            val existing = state.outbox.values.firstOrNull {
                it.eventId == prepared.eventId
            }
            resolvedPreparation = prepared
            resolvedPreparationWasAbsent = existing == null
            return existing
        }

        override suspend fun putPreparedOutbox(
            preparation: PreparedOutboxAdmission,
            event: DurableOutboxEvent,
        ) {
            val prepared = requirePreparation(preparation)
            checkPartition()
            check(resolvedPreparation === prepared && resolvedPreparationWasAbsent) {
                "prepared outbox must resolve stable absence before insertion"
            }
            require(event.sameImmutableOccurrence(prepared.command)) {
                "inserted outbox event does not match its preparation"
            }
            require(event.pendingLocal == prepared.command.pendingLocal) {
                "inserted pending-local state does not match its preparation"
            }
            val sameSequence = state.outbox[event.queueSequence]
            require(sameSequence == null || sameSequence.eventId == event.eventId) {
                "queue sequence already belongs to another event"
            }
            val sameId = state.outbox.values.firstOrNull { it.eventId == event.eventId }
            require(sameId == null || sameId.queueSequence == event.queueSequence) {
                "event id already belongs to another queue sequence"
            }
            state.outbox[event.queueSequence] = event
        }

        override suspend fun clearOutboxPendingLocal(queueSequence: Long): Boolean {
            checkOpen()
            checkPartition()
            val current = state.outbox[queueSequence] ?: return false
            if (!current.pendingLocal) return false
            state.outbox[queueSequence] = current.copy(pendingLocal = false)
            return true
        }

        private fun requirePreparation(
            preparation: PreparedOutboxAdmission,
        ): MemoryPreparedOutboxAdmission {
            checkOpen()
            require(preparation is MemoryPreparedOutboxAdmission &&
                preparation.owner === preparationOwner) {
                "prepared outbox capability belongs to another store"
            }
            preparation.checkOpen()
            require(preparation.pairingId == pairingId) {
                "prepared outbox capability belongs to another pairing"
            }
            return preparation
        }

        override suspend fun deleteOutbox(queueSequence: Long) {
            checkOpen()
            checkPartition()
            state.outbox.remove(queueSequence)
        }

        override suspend fun deleteAllOutbox() {
            checkOpen()
            checkPartition()
            state.outbox.clear()
        }

        override suspend fun issuedEventId(eventId: EventId): IssuedEventId? {
            checkOpen()
            return state.issuedEventIds[eventId]
        }

        override suspend fun putIssuedEventId(record: IssuedEventId) {
            checkOpen()
            checkPartition()
            require(record.eventId !in state.issuedEventIds) {
                "event id receipt already exists"
            }
            state.issuedEventIds[record.eventId] = record
        }

        override suspend fun deleteIssuedEventId(eventId: EventId) {
            checkOpen()
            checkPartition()
            state.issuedEventIds.remove(eventId)
        }

        override suspend fun issuedEventIdsReusableAtOrBefore(
            effectiveNowMs: Long,
            limit: Int,
        ): List<IssuedEventId> {
            checkOpen()
            require(effectiveNowMs >= 0)
            require(limit > 0) { "receipt-prune limit must be positive" }
            return state.issuedEventIds.values
                .asSequence()
                .filter { it.reusableAfterMs <= effectiveNowMs }
                .sortedWith(
                    compareBy<IssuedEventId> { it.reusableAfterMs }
                        .thenBy { it.eventId.value },
                )
                .take(limit)
                .toList()
        }

        override suspend fun deleteAllIssuedEventIds() {
            checkOpen()
            checkPartition()
            state.issuedEventIds.clear()
        }
    }
}
