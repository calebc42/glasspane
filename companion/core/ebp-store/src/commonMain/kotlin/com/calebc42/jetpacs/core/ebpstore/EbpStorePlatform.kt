// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.jetpacs.core.ebpstore

import com.calebc42.ebp.wire.DurableOutboxPolicy
import com.calebc42.ebp.wire.EventId
import com.calebc42.ebp.wire.PairingId
import kotlinx.serialization.json.JsonObject

/**
 * Authentication material provisioned by the host platform for one pairing.
 * Alias values are Jetpacs storage configuration, never EBP protocol state.
 */
data class ProvisionedPairingAliases(
    val credentialKeyAlias: String,
    val payloadKeyAlias: String,
) {
    init {
        require(credentialKeyAlias.isNotBlank())
        require(payloadKeyAlias.isNotBlank())
        require(credentialKeyAlias != payloadKeyAlias) {
            "Credential and payload keys must use distinct aliases"
        }
    }
}

/**
 * Resolves aliases already provisioned by the host pairing flow. This must be
 * a pure, non-blocking lookup: it must never provision or touch a Keystore.
 * Returning null means the host has not completed provisioning.
 */
fun interface ProvisionedPairingAliasResolver {
    fun resolve(pairingId: PairingId): ProvisionedPairingAliases?
}

/**
 * Pure resolver over a snapshot that the completed onboarding coordinator
 * supplies. Merely deriving platform key names is intentionally insufficient
 * to populate this resolver.
 */
class SnapshotProvisionedPairingAliasResolver(
    provisioned: Map<PairingId, ProvisionedPairingAliases>,
) : ProvisionedPairingAliasResolver {
    private val snapshot = provisioned.toMap()

    override fun resolve(pairingId: PairingId): ProvisionedPairingAliases? =
        snapshot[pairingId]
}

/**
 * Immutable row metadata authenticated together with an outbox payload.
 * Mutable delivery state such as `pendingLocal` is deliberately excluded from
 * these AAD inputs so it can change without resealing the occurrence.
 */
data class OutboxEnvelopeMetadata(
    val pairingId: PairingId,
    val eventId: EventId,
    val queueSequence: Long,
    val storageGeneration: String,
    val policy: DurableOutboxPolicy,
    val occurredAtMs: Long,
    val queuedAtMs: Long,
    val expiresAtMs: Long,
    val dedupeKey: String?,
    val accountedBytes: Long,
    val triggerIdentity: String?,
) {
    init {
        require(queueSequence >= 1)
        require(STORAGE_GENERATION.matches(storageGeneration)) {
            "storageGeneration must be 32 lowercase hex digits"
        }
        require(occurredAtMs >= 0)
        require(queuedAtMs >= occurredAtMs)
        require(expiresAtMs >= queuedAtMs)
        require(accountedBytes > 0)
        require(dedupeKey == null || dedupeKey.isNotBlank())
        require(triggerIdentity == null || triggerIdentity.isNotBlank())
    }
}

/**
 * Host-supplied authenticated envelope codec. Calls are deliberately made
 * outside Room connections; production has no plaintext or fake fallback.
 */
interface OutboxPayloadEnvelopeCodec {
    suspend fun encode(
        payload: JsonObject,
        metadata: OutboxEnvelopeMetadata,
        payloadKeyAlias: String,
    ): ByteArray

    suspend fun decode(
        envelope: ByteArray,
        metadata: OutboxEnvelopeMetadata,
        payloadKeyAlias: String,
    ): JsonObject
}

/** Supplies an unpredictable immutable generation for each newly sealed row. */
fun interface StorageGenerationSource {
    suspend fun next(): String
}

internal val STORAGE_GENERATION = Regex("[0-9a-f]{32}")
