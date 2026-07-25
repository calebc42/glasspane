// SPDX-License-Identifier: GPL-3.0-or-later
// W2 conformance suite — the Kotlin twin of test/ebp-wire-test.el, driven by
// the same ebp corpus (SPEC 24.5-24.6): the 9.3 known-answer vector, every
// goldens/wire fixture at whole/1-octet/7-octet chunkings against the
// manifest's expected outcome, encoder byte syntax, and handshake params
// checked against contract.json (format 6).
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class WireConformanceTest {

    private val ebpDir = File(System.getProperty("ebp.dir")
        ?: error("ebp.dir system property not set"))
    private val wireDir = ebpDir.resolve("goldens/wire")

    // ---------------------------------------------------------------- KAT --

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    @Test
    fun katProofsReproduceExactly() {
        assertEquals(
            "03e270fd0af4566336283444b641a722b5828c190ebdbe3dc50c5be2c9c9fb43",
            EbpAuth.clientProof(katToken, katPid, katCn, katSn))
        assertEquals(
            "e9333d48cfc2780d708db4a9782705c5e1c988c7eedc2d1734051f2fb9be58ec",
            EbpAuth.serverProof(katToken, katPid, katCn, katSn))
        assertTrue(EbpAuth.verifyServerProof(
            EbpAuth.serverProof(katToken, katPid, katCn, katSn),
            katToken, katPid, katCn, katSn))
        assertFalse(EbpAuth.verifyServerProof(
            EbpAuth.clientProof(katToken, katPid, katCn, katSn),
            katToken, katPid, katCn, katSn))
        assertTrue(EbpAuth.verifyClientProof(
            EbpAuth.clientProof(katToken, katPid, katCn, katSn),
            katToken, katPid, katCn, katSn))
    }

    // ------------------------------------------------------- wire goldens --

    private fun chunkings(bytes: ByteArray): Map<String, List<ByteArray>> = mapOf(
        "whole" to listOf(bytes),
        "1-octet" to bytes.map { byteArrayOf(it) },
        "7-octet" to (0..bytes.size step 7).mapNotNull { i ->
            if (i >= bytes.size) null
            else bytes.copyOfRange(i, minOf(i + 7, bytes.size))
        },
    )

    private fun runFixture(chunks: List<ByteArray>): Pair<List<JSONObject>?, String?> =
        try {
            val decoder = FrameDecoder()
            val messages = mutableListOf<JSONObject>()
            chunks.forEach { messages += decoder.feed(it) }
            decoder.finish()
            messages to null
        } catch (e: FrameClose) { null to "close" }
        catch (e: FrameIncomplete) { null to "incomplete-frame" }
        catch (e: WireParseError) { null to "parse-error" }
        catch (e: InvalidRequest) { null to "invalid-request" }

    @Test
    fun wireGoldensBehavePerManifestAtAllChunkings() {
        val manifest = JSONObject(wireDir.resolve("manifest.json").readText())
        val fixtures = manifest.getJSONArray("fixtures")
        assertTrue("adversarial set truncated?", fixtures.length() >= 10)
        for (f in 0 until fixtures.length()) {
            val fx = fixtures.getJSONObject(f)
            val bytes = wireDir.resolve(fx.getString("file")).readBytes()
            for ((label, chunks) in chunkings(bytes)) {
                val (messages, error) = runFixture(chunks)
                val context = "${fx.getString("file")} [$label]"
                if (fx.getString("kind") == "positive") {
                    assertNull("$context: unexpected error $error", error)
                    val expected = fx.getJSONArray("expect_messages")
                    assertEquals(context, expected.length(), messages!!.size)
                    for (i in messages.indices) {
                        assertTrue("$context message $i differs",
                            jsonEquals(messages[i], expected.getJSONObject(i)))
                    }
                } else {
                    assertEquals(context, fx.getString("expect_error"), error)
                }
            }
        }
    }

    @Test
    fun utf8FixtureWitnessesOctetCounting() {
        val bytes = wireDir.resolve("03-utf8-length.bin").readBytes()
        val headerEnd = String(bytes, Charsets.ISO_8859_1).indexOf("\r\n\r\n") + 4
        val declared = Regex("Content-Length: ([0-9]+)")
            .find(String(bytes, Charsets.ISO_8859_1))!!.groupValues[1].toInt()
        val body = bytes.copyOfRange(headerEnd, bytes.size)
        val text = String(body, Charsets.UTF_8)
        assertEquals(declared, body.size)
        assertNotEquals(declared, text.length)
        // Re-framing the decoded text reproduces the fixture byte-exactly.
        assertTrue(encodeFrame(text).contentEquals(bytes))
    }

    // ------------------------------------------------------------ encoder --

    @Test
    fun encoderSyntaxIsExact() {
        assertTrue(encodeFrame("{}")
            .contentEquals("Content-Length: 2\r\n\r\n{}".toByteArray(Charsets.US_ASCII)))
        // 9 characters, 10 octets: length counts UTF-8 octets, not chars.
        val frame = encodeFrame("""{"a":"é"}""")
        assertTrue(String(frame, Charsets.UTF_8).startsWith("Content-Length: 10\r\n\r\n"))
    }

    // ----------------------------------------------------------- envelope --

    @Test
    fun envelopeClassification() {
        assertEquals(MessageClass.REQUEST, classifyMessage(
            request("r1", "session.ready", JSONObject())))
        assertEquals(MessageClass.NOTIFICATION, classifyMessage(
            notification("state.changed", JSONObject())))
        assertEquals(MessageClass.RESPONSE, classifyMessage(
            resultResponse("r1", JSONObject())))
        assertEquals(MessageClass.RESPONSE, classifyMessage(
            errorResponse("r1", 1204, "not legal now", "session-state")))
        assertNull(classifyMessage(JSONObject().put("jsonrpc", "1.0").put("method", "x")))
        assertNull(classifyMessage(JSONObject().put("jsonrpc", "2.0").put("id", "r1")
            .put("result", JSONObject()).put("error", JSONObject())))
    }

    @Test
    fun requestIdGrammar() {
        assertTrue(isValidRequestId("r1"))
        assertTrue(isValidRequestId("a".repeat(64)))
        assertFalse(isValidRequestId("a".repeat(65)))
        assertFalse(isValidRequestId(""))
        assertTrue(isValidRequestId(7)) // amendment #34: jsonrpc.el ids
        assertTrue(isValidRequestId(9_007_199_254_740_991L))
        assertFalse(isValidRequestId(9_007_199_254_740_992L))
        assertFalse(isValidRequestId(7.5))
        assertFalse(isValidRequestId(null))
    }

    // ----------------------------------------------- duplicates and nonces --

    @Test
    fun duplicateMemberScan() {
        assertTrue(hasDuplicateMembers("""{"a":1,"a":2}"""))
        // Semantic comparison: a is "a".
        assertTrue(hasDuplicateMembers("""{"a":1,"\u0061":2}"""))
        assertFalse(hasDuplicateMembers("""{"a":1,"b":{"a":2}}"""))
        assertFalse(hasDuplicateMembers("""{"a":[{"x":1},{"x":2}]}"""))
        assertFalse(hasDuplicateMembers("""{"a":"a","b":"a"}"""))
    }

    @Test
    fun nonceGeneration() {
        val n1 = EbpAuth.generateNonce()
        val n2 = EbpAuth.generateNonce()
        assertTrue(EbpAuth.isValidNonce(n1))
        assertTrue(EbpAuth.isValidNonce(n2))
        assertNotEquals(n1, n2)
    }

    // ------------------------------------------- handshake versus contract --

    @Test
    fun handshakeParamsMatchContract() {
        val contract = JSONObject(ebpDir.resolve("contract.json").readText())
        val methods = contract.getJSONObject("methods")
        fun required(method: String): Set<String> =
            methods.getJSONObject(method).getJSONObject("params")
                .getJSONArray("required").let { arr ->
                    (0 until arr.length()).map { arr.getString(it) }.toSet()
                }
        val hello = EbpAuth.helloParams("test-client", "0.0.1", katPid, katCn, emptyList())
        val auth = EbpAuth.authParams(katPid, katCn, katSn, katToken)
        assertEquals(required("session.hello"), hello.keySet())
        assertEquals(required("auth.response"), auth.keySet())
        assertTrue(EbpAuth.isValidProof(auth.getString("client_proof")))
    }

    // ------------------------------------------------------------ session --

    @Test
    fun sessionTransitions() {
        var s = SessionState.CONNECTED
        for ((event, expected) in listOf(
            SessionEvent.HELLO_ACCEPTED to SessionState.CHALLENGED,
            SessionEvent.AUTH_VERIFIED to SessionState.SYNCING,
            SessionEvent.READY_CONFIRMED to SessionState.READY)) {
            s = sessionStep(s, event) ?: fail("illegal: $event from $s").let { return }
            assertEquals(expected, s)
        }
        assertNull(sessionStep(SessionState.CONNECTED, SessionEvent.AUTH_VERIFIED))
        assertNull(sessionStep(SessionState.READY, SessionEvent.HELLO_ACCEPTED))
        assertEquals(SessionState.CLOSED,
            sessionStep(SessionState.READY, SessionEvent.CLOSE))
        assertEquals(SessionState.CLOSED,
            sessionStep(SessionState.CONNECTED, SessionEvent.CLOSE))
    }

    // ----------------------------------------------- decoder scaling (LD-21)

    @Test
    fun largeBodyInEightKiBChunksDecodesOnce() {
        // LD-21: one spec-legal large frame arriving in 8 KiB transport reads
        // (DeviceBridge's read size). The old decoder re-copied and re-scanned
        // every pending byte per read and re-parsed the header until the body
        // completed — measured 229 ms / 1.08 GB of memory traffic for a 4 MiB
        // body on a desktop. State now lives on the decoder: header parsed
        // once, scan resumes at the watermark, reads append in place.
        val payload = "x".repeat(4_000_000)
        val msg = JSONObject().put("jsonrpc", "2.0").put("method", "log.debug")
            .put("params", JSONObject().put("m", payload))
        val encoded = encodeFrame(msg.toString())
        val d = FrameDecoder()
        val out = mutableListOf<JSONObject>()
        var i = 0
        while (i < encoded.size) {
            val n = minOf(8192, encoded.size - i)
            d.feed(encoded.copyOfRange(i, i + n)) { out.add(it) }
            i += n
        }
        d.finish()
        assertEquals(1, out.size)
        assertEquals(payload, out[0].getJSONObject("params").getString("m"))
    }

    @Test
    fun pipelinedFramesDecodeInOrderAtEverySplitPoint() {
        // Two pipelined frames split at every byte boundary — including
        // inside the CRLFCRLF terminator and mid-body — decode identically.
        val a = encodeFrame(JSONObject().put("jsonrpc", "2.0")
            .put("method", "log.debug")
            .put("params", JSONObject().put("m", "first")).toString())
        val b = encodeFrame(JSONObject().put("jsonrpc", "2.0")
            .put("method", "log.debug")
            .put("params", JSONObject().put("m", "second")).toString())
        val joined = a + b
        for (cut in 1 until joined.size) {
            val d = FrameDecoder()
            val out = mutableListOf<JSONObject>()
            d.feed(joined.copyOfRange(0, cut)) { out.add(it) }
            d.feed(joined.copyOfRange(cut, joined.size)) { out.add(it) }
            d.finish()
            assertEquals("cut at $cut", 2, out.size)
            assertEquals("first", out[0].getJSONObject("params").getString("m"))
            assertEquals("second", out[1].getJSONObject("params").getString("m"))
        }
    }

    // ------------------------------------------------------- json equality --

    /** Structural JSON equality: objects unordered, arrays ordered. */
    private fun jsonEquals(a: Any?, b: Any?): Boolean = when {
        a is JSONObject && b is JSONObject ->
            a.keySet() == b.keySet() && a.keySet().all { jsonEquals(a.get(it), b.get(it)) }
        a is JSONArray && b is JSONArray ->
            a.length() == b.length() &&
                (0 until a.length()).all { jsonEquals(a.get(it), b.get(it)) }
        a is Number && b is Number -> a.toDouble() == b.toDouble()
        a == JSONObject.NULL && b == JSONObject.NULL -> true
        else -> a == b
    }
}
