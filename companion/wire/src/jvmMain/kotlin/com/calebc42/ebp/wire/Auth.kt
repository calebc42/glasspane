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
        hmacSha256(token, "EBP/2 client:$pairingId:$clientNonce:$serverNonce").toHex()

    /** SPEC 9.3 companion proof; note the swapped nonce order. */
    fun serverProof(token: ByteArray, pairingId: String,
                    clientNonce: String, serverNonce: String): String =
        hmacSha256(token, "EBP/2 companion:$pairingId:$serverNonce:$clientNonce").toHex()

    /**
     * SPEC 9.2: the fixed dummy key the unknown-pairing-ID path verifies
     * against, so that branch does the same HMAC-SHA256 work as a known ID.
     * Its value is irrelevant — only that it is fixed, and that no proof an
     * attacker can produce matches against it.
     */
    val DUMMY_PROOF_KEY: ByteArray = ByteArray(16)

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

    private fun hmacSha256(key: ByteArray, message: String): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(message.toByteArray(Charsets.US_ASCII))
        }

    private fun ByteArray.toHex(): String =
        joinToString("") { "%02x".format(it) }
}
