// SPDX-License-Identifier: GPL-3.0-or-later
// Named, storage-neutral transactions for the first durable-store slice.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

const val EVENT_ID_RETENTION_FLOOR_MS: Long = 604_800_000L
internal const val LATEST_EVENT_ID_ISSUED_AT_MS: Long =
    EBP_MAX_SAFE_INTEGER - EVENT_ID_RETENTION_FLOOR_MS

data class ActivatePairingCommand(
    val pairingId: PairingId,
    val createdAtMs: Long,
)

sealed interface ActivatePairingResult {
    data class Activated(val pairing: DurablePairing) : ActivatePairingResult
    data class AlreadyActive(val pairing: DurablePairing) : ActivatePairingResult
    data class Fenced(val pairing: DurablePairing) : ActivatePairingResult
}

suspend fun EbpDurableStore.activatePairing(
    command: ActivatePairingCommand,
): ActivatePairingResult = write(command.pairingId) {
    val current = pairing()
    when {
        current == null -> {
            val created = DurablePairing(
                id = command.pairingId,
                fence = PairingFence.ACTIVE,
                createdAtMs = command.createdAtMs,
            )
            putPairing(created)
            putRuntime(PairingRuntime())
            ActivatePairingResult.Activated(created)
        }
        current.fence == PairingFence.ACTIVE -> ActivatePairingResult.AlreadyActive(current)
        else -> ActivatePairingResult.Fenced(current)
    }
}

data class RevokePairingStateCommand(
    val pairingId: PairingId,
    val fencedAtMs: Long,
) {
    init { requireEbpTimestamp(fencedAtMs, "fencedAtMs") }
}

sealed interface RevokePairingStateResult {
    object Missing : RevokePairingStateResult
    data class Revoked(val pairing: DurablePairing) : RevokePairingStateResult
}

/**
 * Use the backend's indivisible revocation primitive. A Room adapter maps this
 * directly to its fence + cleanup-journal + erasure transaction; composing the
 * generic row operations here would permit an unjournaled fence.
 */
suspend fun EbpDurableStore.revokePairingState(
    command: RevokePairingStateCommand,
): RevokePairingStateResult = write(command.pairingId) {
    val revoked = fenceAndErasePairingState(command.fencedAtMs)
        ?: return@write RevokePairingStateResult.Missing
    RevokePairingStateResult.Revoked(revoked)
}

data class SurfaceLimits(
    val maxPresentSurfaces: Long,
    val maxSurfaceIds: Long,
) {
    init {
        require(maxPresentSurfaces >= 0)
        require(maxSurfaceIds >= 0)
    }
}

/**
 * A structurally and semantically validated surface snapshot. The protocol
 * reducer supplies draft IDs that survived Section 13.6 compatibility; this
 * transaction applies that complete reconciliation with the revision write.
 */
data class ApplySurfaceCommand(
    val pairingId: PairingId,
    val surfaceId: String,
    val revision: Long,
    val spec: JsonObject,
    val staleSpec: JsonObject? = null,
    val staleAfterSeconds: Long? = null,
    val currentView: String? = null,
    val acceptedAtMs: Long,
    val retainedDraftIds: Set<String> = emptySet(),
    val resetDraftIds: Set<String> = emptySet(),
    val limits: SurfaceLimits,
) {
    init {
        require(surfaceId.isNotBlank())
        require(revision >= 0)
        require(acceptedAtMs >= 0)
        require(staleAfterSeconds == null || staleAfterSeconds > 0)
    }
}

data class RemoveSurfaceCommand(
    val pairingId: PairingId,
    val surfaceId: String,
    val revision: Long,
    val acceptedAtMs: Long,
    val limits: SurfaceLimits,
) {
    init {
        require(surfaceId.isNotBlank())
        require(revision >= 0)
        require(acceptedAtMs >= 0)
    }
}

sealed interface SurfaceWriteResult {
    data class Applied(
        val revision: Long,
        val present: Boolean,
        val firstSeenOrdinal: Long,
    ) : SurfaceWriteResult

    data class Stale(val revisionFloor: Long, val present: Boolean) : SurfaceWriteResult
    object PairingNotActive : SurfaceWriteResult
    object SurfaceLimitReached : SurfaceWriteResult
}

suspend fun EbpDurableStore.applySurface(
    command: ApplySurfaceCommand,
): SurfaceWriteResult = write(command.pairingId) {
    if (!isActive()) return@write SurfaceWriteResult.PairingNotActive
    val current = surface(command.surfaceId)
    val floor = current?.revision ?: -1
    if (command.revision <= floor)
        return@write SurfaceWriteResult.Stale(floor, current?.present == true)

    val cardinality = surfaceCardinality()
    if (current == null && cardinality.total >= command.limits.maxSurfaceIds)
        return@write SurfaceWriteResult.SurfaceLimitReached
    if (current?.present != true &&
        cardinality.present >= command.limits.maxPresentSurfaces)
        return@write SurfaceWriteResult.SurfaceLimitReached

    val firstSeen = current?.firstSeenOrdinal ?: allocateFirstSeenOrdinal()
    putSurface(
        DurableSurfaceRecord(
            surfaceId = command.surfaceId,
            revision = command.revision,
            present = true,
            spec = command.spec,
            staleSpec = command.staleSpec,
            staleAfterSeconds = command.staleAfterSeconds,
            currentView = command.currentView,
            acceptedAtMs = command.acceptedAtMs,
            firstSeenOrdinal = firstSeen,
        ),
    )
    drafts(command.surfaceId).forEach { draft ->
        if (draft.nodeId !in command.retainedDraftIds || draft.nodeId in command.resetDraftIds)
            deleteDraft(command.surfaceId, draft.nodeId)
    }
    SurfaceWriteResult.Applied(
        revision = command.revision,
        present = true,
        firstSeenOrdinal = firstSeen,
    )
}

suspend fun EbpDurableStore.removeSurface(
    command: RemoveSurfaceCommand,
): SurfaceWriteResult = write(command.pairingId) {
    if (!isActive()) return@write SurfaceWriteResult.PairingNotActive
    val current = surface(command.surfaceId)
    val floor = current?.revision ?: -1
    if (command.revision <= floor)
        return@write SurfaceWriteResult.Stale(floor, current?.present == true)

    val cardinality = surfaceCardinality()
    if (current == null && cardinality.total >= command.limits.maxSurfaceIds)
        return@write SurfaceWriteResult.SurfaceLimitReached
    val firstSeen = current?.firstSeenOrdinal ?: allocateFirstSeenOrdinal()
    putSurface(
        DurableSurfaceRecord(
            surfaceId = command.surfaceId,
            revision = command.revision,
            present = false,
            spec = null,
            acceptedAtMs = command.acceptedAtMs,
            firstSeenOrdinal = firstSeen,
        ),
    )
    deleteDrafts(command.surfaceId)
    SurfaceWriteResult.Applied(
        revision = command.revision,
        present = false,
        firstSeenOrdinal = firstSeen,
    )
}

data class ReleaseSurfaceCommand(val pairingId: PairingId, val surfaceId: String)

sealed interface ReleaseSurfaceResult {
    object Released : ReleaseSurfaceResult
    object Missing : ReleaseSurfaceResult
    object Present : ReleaseSurfaceResult
    object PairingNotActive : ReleaseSurfaceResult
}

suspend fun EbpDurableStore.releaseSurface(
    command: ReleaseSurfaceCommand,
): ReleaseSurfaceResult = write(command.pairingId) {
    if (!isActive()) return@write ReleaseSurfaceResult.PairingNotActive
    val current = surface(command.surfaceId) ?: return@write ReleaseSurfaceResult.Missing
    if (current.present) return@write ReleaseSurfaceResult.Present
    deleteDrafts(command.surfaceId)
    deleteSurface(command.surfaceId)
    ReleaseSurfaceResult.Released
}

/**
 * A draft already validated against the accepted non-password stateful node.
 * Raw node semantics stay in the protocol reducer until ValidatedSurfaceSpec.
 */
data class PutDraftCommand(
    val pairingId: PairingId,
    val surfaceId: String,
    val nodeId: String,
    val value: JsonElement,
)

sealed interface DraftWriteResult {
    object Committed : DraftWriteResult
    object SurfaceNotPresent : DraftWriteResult
    object PairingNotActive : DraftWriteResult
}

suspend fun EbpDurableStore.putDraft(
    command: PutDraftCommand,
): DraftWriteResult = write(command.pairingId) {
    if (!isActive()) return@write DraftWriteResult.PairingNotActive
    if (surface(command.surfaceId)?.present != true)
        return@write DraftWriteResult.SurfaceNotPresent
    putDraft(DurableDraft(command.surfaceId, command.nodeId, command.value))
    DraftWriteResult.Committed
}

data class OutboxLimits(val maxEvents: Long, val maxBytes: Long) {
    init {
        require(maxEvents >= 0)
        require(maxBytes >= 0)
    }
}

/**
 * One already validated durable occurrence. [protectedQueueSequences] names
 * runtime-owned in-flight or retained-head records which dedupe must not
 * remove; those ownership markers themselves are intentionally not durable.
 */
data class AdmitOutboxCommand(
    val pairingId: PairingId,
    val eventId: EventId,
    val payload: JsonObject,
    val policy: DurableOutboxPolicy,
    val occurredAtMs: Long,
    val queuedAtMs: Long,
    val expiresAtMs: Long,
    /**
     * Already-corroborated effective-clock candidate. This storage slice only
     * commits that value; SPEC 15.2 forward-jump corroboration/clamping remains
     * deliberately deferred and raw wall-clock time must not be passed here.
     */
    val corroboratedEffectiveNowMs: Long,
    val dedupeKey: String? = null,
    val accountedBytes: Long,
    val pendingLocal: Boolean = false,
    val triggerIdentity: String? = null,
    val protectedQueueSequences: Set<Long> = emptySet(),
    val limits: OutboxLimits,
) {
    init {
        requireEbpTimestamp(occurredAtMs, "occurredAtMs")
        requireEbpTimestamp(queuedAtMs, "queuedAtMs")
        requireEbpTimestamp(expiresAtMs, "expiresAtMs")
        requireEbpTimestamp(corroboratedEffectiveNowMs, "corroboratedEffectiveNowMs")
        require(occurredAtMs <= LATEST_EVENT_ID_ISSUED_AT_MS) {
            "occurredAtMs leaves no representable seven-day EventId retention floor"
        }
        require(queuedAtMs >= occurredAtMs)
        require(expiresAtMs >= queuedAtMs)
        require(dedupeKey == null || dedupeKey.isNotBlank())
        require(triggerIdentity == null || triggerIdentity.isNotBlank())
        require(accountedBytes > 0)
        require(protectedQueueSequences.all { it >= 1 })
        requireAuthoritativeEventPayload(payload, eventId, occurredAtMs, queuedAtMs)
    }
}

sealed interface OutboxAdmissionResult {
    data class Admitted(
        val event: DurableOutboxEvent,
        val replacedQueueSequences: List<Long>,
    ) : OutboxAdmissionResult

    /** Retrying the same local occurrence does not allocate another sequence. */
    data class AlreadyAdmitted(val event: DurableOutboxEvent) : OutboxAdmissionResult
    object QueueFull : OutboxAdmissionResult
    object PairingNotActive : OutboxAdmissionResult
}

class ConflictingEventId(val conflictingEventId: EventId) :
    IllegalStateException("event id ${conflictingEventId.value} has conflicting immutable data")

internal class EventIdReuseBeforeRetention(
    val reusedEventId: EventId,
    val reusableAfterMs: Long,
) : IllegalStateException(
    "event id ${reusedEventId.value} cannot be reused before $reusableAfterMs",
)

suspend fun EbpDurableStore.admitOutbox(
    command: AdmitOutboxCommand,
): OutboxAdmissionResult = writePreparedOutbox(command) { preparation ->
    if (!isActive()) {
        return@writePreparedOutbox OutboxAdmissionResult.PairingNotActive
    }
    admitOutboxForActivePairing(command, preparation)
}

data class CommitDraftAndOutboxCommand(
    val draft: PutDraftCommand,
    val outbox: AdmitOutboxCommand,
) {
    init { require(draft.pairingId == outbox.pairingId) { "cross-pairing interaction" } }
}

sealed interface DraftOutboxCommitResult {
    data class Committed(val admission: OutboxAdmissionResult) : DraftOutboxCommitResult
    object QueueFull : DraftOutboxCommitResult
    object SurfaceNotPresent : DraftOutboxCommitResult
    object PairingNotActive : DraftOutboxCommitResult
}

/**
 * Commit a prevalidated, non-password draft and its durable occurrence as one
 * all-or-nothing transaction. No raw node-schema interpretation belongs here.
 */
suspend fun EbpDurableStore.commitDraftAndOutbox(
    command: CommitDraftAndOutboxCommand,
): DraftOutboxCommitResult = writePreparedOutbox(command.outbox) { preparation ->
    if (!isActive()) {
        return@writePreparedOutbox DraftOutboxCommitResult.PairingNotActive
    }
    if (surface(command.draft.surfaceId)?.present != true) {
        return@writePreparedOutbox DraftOutboxCommitResult.SurfaceNotPresent
    }
    when (val admission = admitOutboxForActivePairing(command.outbox, preparation)) {
        is OutboxAdmissionResult.Admitted -> {
            putDraft(
                DurableDraft(
                    surfaceId = command.draft.surfaceId,
                    nodeId = command.draft.nodeId,
                    value = command.draft.value,
                ),
            )
            DraftOutboxCommitResult.Committed(admission)
        }
        is OutboxAdmissionResult.AlreadyAdmitted ->
            DraftOutboxCommitResult.Committed(admission)
        OutboxAdmissionResult.QueueFull -> {
            putDraft(
                DurableDraft(
                    surfaceId = command.draft.surfaceId,
                    nodeId = command.draft.nodeId,
                    value = command.draft.value,
                ),
            )
            DraftOutboxCommitResult.QueueFull
        }
        OutboxAdmissionResult.PairingNotActive ->
            error("active-pairing reducer returned an inactive result")
    }
}

data class ExpireOutboxCommand(
    val pairingId: PairingId,
    val corroboratedEffectiveNowMs: Long,
    val protectedQueueSequences: Set<Long> = emptySet(),
) {
    init {
        require(corroboratedEffectiveNowMs >= 0)
        require(protectedQueueSequences.all { it >= 1 })
    }
}

sealed interface ExpireOutboxResult {
    data class Expired(
        val queueSequences: List<Long>,
        val remaining: Long,
        val effectiveNowMs: Long,
    ) : ExpireOutboxResult
    object PairingNotActive : ExpireOutboxResult
}

/** Delete expired, non-protected records and advance the clock in one commit. */
suspend fun EbpDurableStore.expireOutbox(
    command: ExpireOutboxCommand,
): ExpireOutboxResult = write(command.pairingId) {
    if (!isActive()) return@write ExpireOutboxResult.PairingNotActive
    val before = runtime()
    val effectiveNow = maxOf(
        before.effectiveClockHighWaterMs,
        command.corroboratedEffectiveNowMs,
    )
    val index = outboxIndex()
    val expired = index.filter {
        it.expiresAtMs <= effectiveNow &&
            it.queueSequence !in command.protectedQueueSequences
    }.map { it.queueSequence }.sorted()
    expired.forEach { deleteOutbox(it) }
    if (effectiveNow != before.effectiveClockHighWaterMs)
        putRuntime(before.copy(effectiveClockHighWaterMs = effectiveNow))
    ExpireOutboxResult.Expired(
        queueSequences = expired,
        remaining = index.size.toLong() - expired.size.toLong(),
        effectiveNowMs = effectiveNow,
    )
}

data class PruneIssuedEventIdsCommand(
    val pairingId: PairingId,
    val corroboratedEffectiveNowMs: Long,
    val limit: Int,
) {
    init {
        require(corroboratedEffectiveNowMs >= 0)
        require(limit > 0) { "receipt-prune limit must be positive" }
    }
}

sealed interface PruneIssuedEventIdsResult {
    data class Pruned(
        val eventIds: List<EventId>,
        val effectiveNowMs: Long,
    ) : PruneIssuedEventIdsResult

    object PairingNotActive : PruneIssuedEventIdsResult
}

/**
 * Delete at most [PruneIssuedEventIdsCommand.limit] reusable receipts and
 * advance the pairing's effective clock in the same commit.
 */
suspend fun EbpDurableStore.pruneIssuedEventIds(
    command: PruneIssuedEventIdsCommand,
): PruneIssuedEventIdsResult = write(command.pairingId) {
    if (!isActive()) return@write PruneIssuedEventIdsResult.PairingNotActive
    val before = runtime()
    val effectiveNow = maxOf(
        before.effectiveClockHighWaterMs,
        command.corroboratedEffectiveNowMs,
    )
    val reusable = issuedEventIdsReusableAtOrBefore(effectiveNow, command.limit)
    reusable.forEach { deleteIssuedEventId(it.eventId) }
    if (effectiveNow != before.effectiveClockHighWaterMs)
        putRuntime(before.copy(effectiveClockHighWaterMs = effectiveNow))
    PruneIssuedEventIdsResult.Pruned(
        eventIds = reusable.map { it.eventId },
        effectiveNowMs = effectiveNow,
    )
}

private suspend fun EbpWriteTransaction.admitOutboxForActivePairing(
    command: AdmitOutboxCommand,
    preparation: PreparedOutboxAdmission,
): OutboxAdmissionResult {
    val before = runtime()
    val advancedClock = maxOf(
        before.effectiveClockHighWaterMs,
        command.corroboratedEffectiveNowMs,
    )
    val existing = resolvePreparedOutbox(preparation)
    if (existing != null) {
        if (!existing.sameImmutableOccurrence(command))
            throw ConflictingEventId(command.eventId)
        if (advancedClock != before.effectiveClockHighWaterMs)
            putRuntime(before.copy(effectiveClockHighWaterMs = advancedClock))
        return OutboxAdmissionResult.AlreadyAdmitted(existing)
    }

    val issued = issuedEventId(command.eventId)
    if (issued != null) {
        if (advancedClock < issued.reusableAfterMs)
            throw EventIdReuseBeforeRetention(command.eventId, issued.reusableAfterMs)
        deleteIssuedEventId(command.eventId)
    }
    check(before.nextQueueSequence < Long.MAX_VALUE) { "queue sequence exhausted" }
    val event = DurableOutboxEvent(
        queueSequence = before.nextQueueSequence,
        eventId = command.eventId,
        payload = command.payload,
        policy = command.policy,
        occurredAtMs = command.occurredAtMs,
        queuedAtMs = command.queuedAtMs,
        expiresAtMs = command.expiresAtMs,
        dedupeKey = command.dedupeKey,
        accountedBytes = command.accountedBytes,
        pendingLocal = command.pendingLocal,
        triggerIdentity = command.triggerIdentity,
    )
    val index = outboxIndex()
    val replaced = if (command.dedupeKey == null) emptyList() else index.filter {
        it.dedupeKey == command.dedupeKey &&
            it.queueSequence !in command.protectedQueueSequences
    }
    val replacedSequences = replaced.map { it.queueSequence }.sorted()
    val kept = index.filterNot { it.queueSequence in replacedSequences }
    if (kept.size.toLong() + 1 > command.limits.maxEvents ||
        exceedsByteLimit(kept, event.accountedBytes, command.limits.maxBytes)) {
        if (advancedClock != before.effectiveClockHighWaterMs)
            putRuntime(before.copy(effectiveClockHighWaterMs = advancedClock))
        return OutboxAdmissionResult.QueueFull
    }

    replacedSequences.forEach { deleteOutbox(it) }
    putIssuedEventId(
        IssuedEventId(
            eventId = command.eventId,
            issuedAtMs = command.occurredAtMs,
            reusableAfterMs = command.occurredAtMs + EVENT_ID_RETENTION_FLOOR_MS,
        ),
    )
    putPreparedOutbox(preparation, event)
    putRuntime(
        before.copy(
            nextQueueSequence = before.nextQueueSequence + 1,
            effectiveClockHighWaterMs = advancedClock,
        ),
    )
    return OutboxAdmissionResult.Admitted(event, replacedSequences)
}

private suspend fun EbpWriteTransaction.isActive(): Boolean =
    pairing()?.fence == PairingFence.ACTIVE

private suspend fun EbpWriteTransaction.allocateFirstSeenOrdinal(): Long {
    val before = runtime()
    check(before.nextSurfaceOrdinal < Long.MAX_VALUE) {
        "surface first-seen ordinal exhausted"
    }
    putRuntime(before.copy(nextSurfaceOrdinal = before.nextSurfaceOrdinal + 1))
    return before.nextSurfaceOrdinal
}

internal fun DurableOutboxEvent.sameImmutableOccurrence(command: AdmitOutboxCommand): Boolean =
    eventId == command.eventId &&
        payload == command.payload &&
        policy == command.policy &&
        occurredAtMs == command.occurredAtMs &&
        queuedAtMs == command.queuedAtMs &&
        expiresAtMs == command.expiresAtMs &&
        dedupeKey == command.dedupeKey &&
        accountedBytes == command.accountedBytes &&
        triggerIdentity == command.triggerIdentity

private fun exceedsByteLimit(
    kept: List<DurableOutboxIndexEntry>,
    additionalBytes: Long,
    maxBytes: Long,
): Boolean {
    if (additionalBytes > maxBytes) return true
    var used = additionalBytes
    for (event in kept) {
        if (event.accountedBytes > maxBytes - used) return true
        used += event.accountedBytes
    }
    return false
}
