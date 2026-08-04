// SPDX-License-Identifier: GPL-3.0-or-later
// EBP 2 pairing and mutual authentication. Implements ebp/SPEC.md section 9.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * An opaque HMAC capability for one pairing credential.
 *
 * A production implementation may close over a non-exportable
 * [javax.crypto.SecretKey] and initialize a fresh [Mac] for every invocation;
 * neither the engine nor this contract needs the key's encoded bytes.
 */
fun interface CompanionHmacKeyHandle {
    fun hmacSha256(message: ByteArray): ByteArray
}

/** The deliberately non-null result of resolving a pairing credential. */
sealed interface CompanionProofKeyResult {
    /** A known pairing. The key remains behind an operation-only handle. */
    data class Known(val key: CompanionHmacKeyHandle) : CompanionProofKeyResult

    /**
     * An unknown pairing. The engine asks the provider for its fixed dummy
     * handle, so this result still takes the same proof-computation path and
     * cryptographic provider as [Known].
     */
    data class Unknown(val dummyKey: CompanionHmacKeyHandle) : CompanionProofKeyResult
}

/**
 * Resolves a pairing ID to an opaque proof key capability.
 *
 * Android hosts can implement this over AndroidKeyStore without exporting
 * raw key bytes. [CompanionProofKeyResult.Unknown] requires a fixed dummy
 * credential from that same provider, so the engine cannot accidentally fall
 * back to a distinguishable software-only path.
 */
fun interface CompanionProofProvider {
    fun resolve(pairingId: String): CompanionProofKeyResult
}

/** Source-compatible adapter for the original in-memory token map. */
class InMemoryCompanionProofProvider(
    private val pairings: Map<String, ByteArray>,
) : CompanionProofProvider {
    override fun resolve(pairingId: String): CompanionProofKeyResult =
        pairings[pairingId]?.let { token ->
            CompanionProofKeyResult.Known(EbpAuth.inMemoryKeyHandle(token))
        } ?: CompanionProofKeyResult.Unknown(EbpAuth.fixedDummyKeyHandle())
}

object EbpAuth {
    private val NONCE = Regex("[0-9a-f]{32}")
    private val PROOF = Regex("[0-9a-f]{64}")
    private val random = SecureRandom()

    /** SPEC 9.2/4.4: exactly 32 lowercase hexadecimal characters. */
    fun isValidNonce(s: String): Boolean = NONCE.matches(s)

    /** SPEC 4.4: exactly 64 lowercase hexadecimal characters. */
    fun isValidProof(s: String): Boolean = PROOF.matches(s)

    /**
     * SPEC 9.1: the 22-character RFC 4648 base64url display form (padding
     * omitted) decodes to the 16 raw octets both endpoints use as HMAC key.
     */
    fun decodePairingToken(display: String): ByteArray {
        require(display.length == 22) { "pairing token must be 22 base64url characters" }
        val raw = Base64.getUrlDecoder().decode(display)
        require(raw.size == 16) { "pairing token did not decode to 16 octets" }
        return raw
    }

    /** Fresh 32-hex nonce from the platform CSPRNG (SPEC 9.2). */
    fun generateNonce(): String = ByteArray(16).also(random::nextBytes).toHex()

    /** SPEC 9.3 client proof over the exact ASCII concatenation. */
    fun clientProof(token: ByteArray, pairingId: String,
                    clientNonce: String, serverNonce: String): String =
        hmacSha256(token, clientProofMessage(pairingId, clientNonce, serverNonce)).toHex()

    /** SPEC 9.3 companion proof; note the swapped nonce order. */
    fun serverProof(token: ByteArray, pairingId: String,
                    clientNonce: String, serverNonce: String): String =
        hmacSha256(token, serverProofMessage(pairingId, clientNonce, serverNonce)).toHex()

    /**
     * SPEC 9.2: the fixed dummy key the unknown-pairing-ID path verifies
     * against, so that branch does the same HMAC-SHA256 work as a known ID.
     * Its value is irrelevant — only that it is fixed, and that no proof an
     * attacker can produce matches against it.
     */
    val DUMMY_PROOF_KEY: ByteArray = ByteArray(16)

    // Deliberately independent of the publicly mutable compatibility array.
    private val DEFAULT_DUMMY_PROOF_KEY_HANDLE: CompanionHmacKeyHandle =
        inMemoryKeyHandle(ByteArray(16))

    internal fun fixedDummyKeyHandle(): CompanionHmacKeyHandle =
        DEFAULT_DUMMY_PROOF_KEY_HANDLE

    /**
     * SPEC 9.3: compare two fixed-length ASCII identifiers without leaking
     * how many leading characters matched. Both operands are fixed-length by
     * grammar (SPEC 4.4), so a length difference carries nothing secret.
     */
    fun constantTimeEquals(a: String?, b: String?): Boolean {
        if (a == null || b == null) return a == null && b == null
        return MessageDigest.isEqual(
            a.toByteArray(Charsets.UTF_8), b.toByteArray(Charsets.UTF_8))
    }

    /** SPEC 9.3: constant-time comparison; malformed proofs never match. */
    fun verifyClientProof(proof: String, token: ByteArray, pairingId: String,
                          clientNonce: String, serverNonce: String): Boolean =
        isValidProof(proof) && MessageDigest.isEqual(
            proof.toByteArray(Charsets.US_ASCII),
            clientProof(token, pairingId, clientNonce, serverNonce)
                .toByteArray(Charsets.US_ASCII))

    fun verifyServerProof(proof: String, token: ByteArray, pairingId: String,
                          clientNonce: String, serverNonce: String): Boolean =
        isValidProof(proof) && MessageDigest.isEqual(
            proof.toByteArray(Charsets.US_ASCII),
            serverProof(token, pairingId, clientNonce, serverNonce)
                .toByteArray(Charsets.US_ASCII))

    /**
     * Engine-side proof verification over an opaque key capability. The
     * fixed-length presented and expected values are compared with
     * [MessageDigest.isEqual], just like the raw-token compatibility API.
     */
    internal fun verifyClientProof(
        proof: String,
        key: CompanionHmacKeyHandle,
        pairingId: String,
        clientNonce: String,
        serverNonce: String,
    ): Boolean {
        val expected = key.hmacSha256(
            clientProofMessage(pairingId, clientNonce, serverNonce)
                .toByteArray(Charsets.US_ASCII),
        )
        require(expected.size == 32) { "HMAC-SHA256 provider returned ${expected.size} bytes" }
        return isValidProof(proof) && MessageDigest.isEqual(
            proof.toByteArray(Charsets.US_ASCII),
            expected.toHex().toByteArray(Charsets.US_ASCII),
        )
    }

    /** Server proof is requested only after the client proof was accepted. */
    internal fun serverProof(
        key: CompanionHmacKeyHandle,
        pairingId: String,
        clientNonce: String,
        serverNonce: String,
    ): String {
        val proof = key.hmacSha256(
            serverProofMessage(pairingId, clientNonce, serverNonce)
                .toByteArray(Charsets.US_ASCII),
        )
        require(proof.size == 32) { "HMAC-SHA256 provider returned ${proof.size} bytes" }
        return proof.toHex()
    }

    /** SPEC 9.2 `session.hello` params (the Companion validates these). */
    fun helloParams(clientName: String, clientVersion: String, pairingId: String,
                    clientNonce: String, wants: List<String>): JsonObject =
        buildJsonObject {
            put("protocol", 2)
            put("client", buildJsonObject {
                put("name", clientName)
                put("version", clientVersion)
            })
            put("pairing_id", pairingId)
            put("client_nonce", clientNonce)
            put("wants", JsonArray(wants.map { JsonPrimitive(it) }))
        }

    /** SPEC 9.3 `auth.response` params with the computed proof. */
    fun authParams(pairingId: String, clientNonce: String, serverNonce: String,
                   token: ByteArray): JsonObject =
        buildJsonObject {
            put("pairing_id", pairingId)
            put("client_nonce", clientNonce)
            put("server_nonce", serverNonce)
            put("client_proof", clientProof(token, pairingId, clientNonce, serverNonce))
        }

    internal fun inMemoryKeyHandle(key: ByteArray): CompanionHmacKeyHandle {
        val ownedKey = key.copyOf()
        return CompanionHmacKeyHandle { message -> hmacSha256(ownedKey, message) }
    }

    private fun clientProofMessage(
        pairingId: String,
        clientNonce: String,
        serverNonce: String,
    ): String = "EBP/2 client:$pairingId:$clientNonce:$serverNonce"

    private fun serverProofMessage(
        pairingId: String,
        clientNonce: String,
        serverNonce: String,
    ): String = "EBP/2 companion:$pairingId:$serverNonce:$clientNonce"

    private fun hmacSha256(key: ByteArray, message: String): ByteArray =
        hmacSha256(key, message.toByteArray(Charsets.US_ASCII))

    private fun hmacSha256(key: ByteArray, message: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(message)
        }

    private fun ByteArray.toHex(): String =
        joinToString("") { "%02x".format(it) }
}
