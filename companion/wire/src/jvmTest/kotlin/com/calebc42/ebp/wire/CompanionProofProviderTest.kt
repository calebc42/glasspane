// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.ebp.wire

import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CompanionProofProviderTest {
    private class RecordingKeyHandle(token: ByteArray) : CompanionHmacKeyHandle {
        private val key: SecretKey = SecretKeySpec(token.copyOf(), "HmacSHA256")
        val messages = mutableListOf<String>()

        override fun hmacSha256(message: ByteArray): ByteArray {
            messages += message.toString(Charsets.US_ASCII)
            return Mac.getInstance("HmacSHA256").run {
                init(key)
                doFinal(message)
            }
        }
    }

    private class RecordingProvider(
        private val result: CompanionProofKeyResult,
    ) : CompanionProofProvider {
        val resolvedPairingIds = mutableListOf<String>()

        override fun resolve(pairingId: String): CompanionProofKeyResult {
            resolvedPairingIds += pairingId
            return result
        }
    }

    private fun engine(
        out: MutableList<JsonObject>,
        provider: CompanionProofProvider,
        pairings: Map<String, ByteArray> = emptyMap(),
    ): CompanionEngine = CompanionEngine(
        CompanionConfig(
            serverName = "provider-test",
            serverVersion = "1.0.0",
            pairings = pairings,
            supportedCapabilities = emptySet(),
            surfaceProfiles = JsonObject(emptyMap()),
            limits = testLimits(),
            nonceSource = { katSn },
            proofProvider = provider,
        ),
    ) { bytes ->
        FrameDecoder().let { decoder ->
            decoder.feed(bytes).forEach(out::add)
            decoder.finish()
        }
    }

    private fun hello(pairingId: String = katPid): JsonObject =
        request(
            "h1",
            "session.hello",
            EbpAuth.helloParams("test-client", "1.0.0", pairingId, katCn, emptyList()),
        )

    private fun auth(
        pairingId: String = katPid,
        token: ByteArray = katToken,
        proof: String = EbpAuth.clientProof(token, pairingId, katCn, katSn),
    ): JsonObject = request(
        "h2",
        "auth.response",
        buildJsonObject {
            put("pairing_id", pairingId)
            put("client_nonce", katCn)
            put("server_nonce", katSn)
            put("client_proof", proof)
        },
    )

    @Test
    fun inMemoryAdapterReturnsOpaqueKnownHandleAndExplicitUnknown() {
        val mutableToken = katToken.copyOf()
        val provider = InMemoryCompanionProofProvider(mapOf(katPid to mutableToken))
        val known = provider.resolve(katPid) as CompanionProofKeyResult.Known

        // A resolved capability owns its bytes; later mutation of the legacy
        // map value cannot alter HMACs already delegated to that handle.
        mutableToken.fill(0)
        val message = ("EBP/2 client:" + katPid + ":" + katCn + ":" + katSn)
            .toByteArray(Charsets.US_ASCII)
        assertEquals(
            EbpAuth.clientProof(katToken, katPid, katCn, katSn),
            known.key.hmacSha256(message).toHex(),
        )
        assertTrue(provider.resolve("f".repeat(32)) is CompanionProofKeyResult.Unknown)
    }

    @Test
    fun engineAuthenticatesThroughOpaqueHandleWithoutRawPairingBytes() {
        val out = mutableListOf<JsonObject>()
        val handle = RecordingKeyHandle(katToken)
        val provider = RecordingProvider(CompanionProofKeyResult.Known(handle))
        val engine = engine(out, provider, pairings = emptyMap())

        engine.feed(frame(hello()))
        engine.feed(frame(auth()))

        assertEquals(SessionState.SYNCING, engine.state)
        assertEquals(listOf(katPid), provider.resolvedPairingIds)
        assertEquals(
            listOf(
                "EBP/2 client:" + katPid + ":" + katCn + ":" + katSn,
                "EBP/2 companion:" + katPid + ":" + katSn + ":" + katCn,
            ),
            handle.messages,
        )
        assertEquals(
            EbpAuth.serverProof(katToken, katPid, katCn, katSn),
            out.last().reqObj("result").reqString("server_proof"),
        )
    }

    @Test
    fun badClientProofNeverRequestsServerProof() {
        val out = mutableListOf<JsonObject>()
        val handle = RecordingKeyHandle(katToken)
        val provider = RecordingProvider(CompanionProofKeyResult.Known(handle))
        val engine = engine(out, provider)

        engine.feed(frame(hello()))
        engine.feed(frame(auth(proof = "0".repeat(64))))

        assertEquals(SessionState.CLOSED, engine.state)
        assertEquals(1203L, out.last().reqObj("error").reqLong("code"))
        assertEquals(listOf("EBP/2 client:" + katPid + ":" + katCn + ":" + katSn), handle.messages)
    }

    @Test
    fun copiedConfigDerivesDefaultProviderFromReplacementPairings() {
        val original = CompanionConfig(
            serverName = "provider-test",
            serverVersion = "1.0.0",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = emptySet(),
            surfaceProfiles = JsonObject(emptyMap()),
            limits = testLimits(),
            nonceSource = { katSn },
        )
        val withoutPairings = original.copy(pairings = emptyMap())
        assertEquals(null, withoutPairings.proofProvider)
        val out = mutableListOf<JsonObject>()
        val engine = CompanionEngine(withoutPairings) { bytes ->
            FrameDecoder().let { decoder ->
                decoder.feed(bytes).forEach(out::add)
                decoder.finish()
            }
        }

        engine.feed(frame(hello()))
        engine.feed(frame(auth()))

        assertEquals(SessionState.CLOSED, engine.state)
        assertEquals(1203L, out.last().reqObj("error").reqLong("code"))
    }

    @Test
    fun unknownPairingInvokesProviderSuppliedDummyHandle() {
        val unknownPairingId = "9f9e9d9c9b9a99989796959493929190"
        val out = mutableListOf<JsonObject>()
        val dummy = RecordingKeyHandle(ByteArray(16) { 0x5a })
        val resolvedPairingIds = mutableListOf<String>()
        val provider = CompanionProofProvider { pairingId ->
            resolvedPairingIds += pairingId
            CompanionProofKeyResult.Unknown(dummy)
        }
        val engine = engine(out, provider)

        engine.feed(frame(hello(unknownPairingId)))
        engine.feed(frame(auth(unknownPairingId)))

        assertEquals(SessionState.CLOSED, engine.state)
        assertEquals(1203L, out.last().reqObj("error").reqLong("code"))
        assertEquals(listOf(unknownPairingId), resolvedPairingIds)
        assertEquals(
            listOf("EBP/2 client:" + unknownPairingId + ":" + katCn + ":" + katSn),
            dummy.messages,
        )
    }

    private fun ByteArray.toHex(): String =
        joinToString("") { "%02x".format(it) }
}
