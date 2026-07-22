// SPDX-License-Identifier: GPL-3.0-or-later
// W3 conformance: the Companion engine against SPEC 9-10 — the KAT
// handshake end to end, pre-auth fail-closed vectors (SPEC 24.6 items 4-5),
// state gating, ready-response ordering, the welcome reservation check,
// and the method-registry-vs-contract drift guard.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class CompanionEngineTest {

    private val ebpDir = File(System.getProperty("ebp.dir")
        ?: error("ebp.dir system property not set"))

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits(): JSONObject = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64)

    private fun profiles(): JSONObject = JSONObject().put("app", JSONObject()
        .put("node_types", JSONArray(listOf(
            "text", "row", "column", "box", "spacer", "divider",
            "button", "text_input")))
        .put("builtins", JSONArray(listOf("view.switch", "companion.settings.open")))
        .put("features", JSONArray()))

    private fun engine(sink: MutableList<JSONObject>,
                       supported: Set<String> = setOf("theme")): CompanionEngine =
        CompanionEngine(
            CompanionConfig(
                serverName = "kat-companion", serverVersion = "1.0.0",
                pairings = mapOf(katPid to katToken),
                supportedCapabilities = supported,
                surfaceProfiles = profiles(),
                limits = limits(),
                nonceSource = { katSn },
            )
        ) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(sink::add); d.finish() }
        }

    private fun frame(msg: JSONObject): ByteArray = encodeFrame(msg.toString())

    private fun hello(wants: List<String> = listOf("theme")): JSONObject =
        request("h1", "session.hello", EbpAuth.helloParams(
            "test-client", "0.0.1", katPid, katCn, wants))

    private fun auth(): JSONObject =
        request("h2", "auth.response", EbpAuth.authParams(katPid, katCn, katSn, katToken))

    // ---------------------------------------------------------- handshake

    @Test
    fun katHandshakeReachesReadyInBarrierOrder() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.feed(frame(hello()))
        assertEquals(SessionState.CHALLENGED, engine.state)
        assertEquals(katSn, out.last().getJSONObject("result").getString("server_nonce"))

        engine.feed(frame(auth()))
        assertEquals(SessionState.SYNCING, engine.state)
        val welcome = out.last().getJSONObject("result")
        // SPEC 9.3: the welcome carries the exact KAT server proof.
        assertEquals(EbpAuth.serverProof(katToken, katPid, katCn, katSn),
            welcome.getString("server_proof"))
        // SPEC 10.2 required members; wants intersection.
        for (m in listOf("server_proof", "protocol", "server", "granted",
                         "surface_profiles", "surfaces", "queued_events", "limits"))
            assertTrue("welcome missing $m", welcome.has(m))
        assertEquals(listOf("theme"),
            welcome.getJSONArray("granted").let { a ->
                (0 until a.length()).map { a.getString(it) } })

        engine.feed(frame(request("q1", "queue.replay", JSONObject())))
        val replay = out.last().getJSONObject("result")
        assertEquals(0, replay.getInt("remaining"))
        assertEquals(JSONObject.NULL, replay.get("blocked_by"))
        assertEquals(SessionState.SYNCING, engine.state)

        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        // SPEC 10.3: the {} response is emitted, and only then READY.
        assertEquals("r1", out.last().getString("id"))
        assertEquals(0, out.last().getJSONObject("result").length())
        assertEquals(SessionState.READY, engine.state)
    }

    // ------------------------------------- pre-auth fail-closed (24.6 4-5)

    @Test
    fun preAuthRequestsAreRefusedWithoutInformation() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        // SPEC 10.1: in CONNECTED, even an unknown or later-legal request
        // gets 1200 — never -32601, never a method-specific answer.
        for (method in listOf("surface.update", "no.such.method", "session.ready")) {
            engine.feed(frame(request("x1", method, JSONObject())))
            assertEquals(1200, out.last().getJSONObject("error").getInt("code"))
            assertEquals(SessionState.CONNECTED, engine.state)
        }
        // Notifications before authentication are dropped without output.
        val before = out.size
        engine.feed(frame(notification("state.changed", JSONObject())))
        assertEquals(before, out.size)
        // CHALLENGED refuses everything but auth.response identically.
        engine.feed(frame(hello()))
        engine.feed(frame(request("x2", "queue.replay", JSONObject())))
        assertEquals(1200, out.last().getJSONObject("error").getInt("code"))
    }

    @Test
    fun badProofFailsClosedWithoutDistinguishingCause() {
        val out = mutableListOf<JSONObject>()
        // Unknown pairing ID and wrong proof must be indistinguishable: 1203.
        val engine = engine(out)
        engine.feed(frame(hello()))
        val wrong = auth().also {
            it.getJSONObject("params").put("client_proof", "0".repeat(64))
        }
        engine.feed(frame(wrong))
        assertEquals(1203, out.last().getJSONObject("error").getInt("code"))
        assertEquals(SessionState.CLOSED, engine.state)
    }

    @Test
    fun malformedAuthIsInvalidParamsThenClose() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.feed(frame(hello()))
        val malformed = request("h2", "auth.response", JSONObject()
            .put("pairing_id", katPid).put("client_nonce", katCn)
            .put("server_nonce", katSn).put("client_proof", "not-hex"))
        engine.feed(frame(malformed))
        assertEquals(-32602, out.last().getJSONObject("error").getInt("code"))
        assertEquals(SessionState.CLOSED, engine.state)
    }

    @Test
    fun wrongProtocolMajorIs1202WithSupportedList() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val h = hello().also { it.getJSONObject("params").put("protocol", 1) }
        engine.feed(frame(h))
        val error = out.last().getJSONObject("error")
        assertEquals(1202, error.getInt("code"))
        assertEquals(2, error.getJSONObject("data").getJSONArray("supported").getInt(0))
    }

    @Test
    fun duplicateWantsAreInvalidParams() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.feed(frame(hello(wants = listOf("theme", "theme"))))
        assertEquals(-32602, out.last().getJSONObject("error").getInt("code"))
    }

    // ------------------------------------------------- post-auth dispatch

    private fun authedEngine(out: MutableList<JSONObject>): CompanionEngine =
        engine(out).also {
            it.feed(frame(hello()))
            it.feed(frame(auth()))
        }

    @Test
    fun postAuthDispatchRules() {
        val out = mutableListOf<JSONObject>()
        val engine = authedEngine(out)
        // READY-only request during SYNCING -> 1204 (SPEC 10.1).
        engine.feed(frame(request("d1", "capability.invoke",
            JSONObject().put("cap", "vibrate"))))
        assertEquals(1204, out.last().getJSONObject("error").getInt("code"))
        // Unknown request post-auth -> -32601 (SPEC 7.3).
        engine.feed(frame(request("d2", "no.such", JSONObject())))
        assertEquals(-32601, out.last().getJSONObject("error").getInt("code"))
        // Companion-direction method arriving inbound as a request -> -32600.
        engine.feed(frame(request("d3", "event.action", JSONObject())))
        assertEquals(-32600, out.last().getJSONObject("error").getInt("code"))
        // Notification-class method sent as a request -> -32600.
        engine.feed(frame(request("d4", "theme.set", JSONObject())))
        assertEquals(-32600, out.last().getJSONObject("error").getInt("code"))
        // Integer request id conforms (SPEC 7.2, amendment #34 — the
        // jsonrpc.el floor) and is answered under the same id.
        engine.feed(frame(JSONObject().put("jsonrpc", "2.0").put("id", 7)
            .put("method", "queue.replay").put("params", JSONObject())))
        assertEquals(7, out.last().getInt("id"))
        assertTrue(out.last().has("result"))
        // None of that killed the session.
        assertEquals(SessionState.SYNCING, engine.state)
    }

    @Test
    fun framingErrorClosesTheConnection() {
        val out = mutableListOf<JSONObject>()
        val engine = authedEngine(out)
        engine.feed("X-No-Length: 1\r\n\r\n".toByteArray(Charsets.US_ASCII))
        assertEquals(SessionState.CLOSED, engine.state)
        assertNotNull(engine.closeReason)
    }

    // ------------------------------------------------- limits reservation

    @Test
    fun welcomeReservationViolationIsRejectedAtConstruction() {
        // A frame budget too small for the promised input_state must fail
        // fast (SPEC 4.5), not at the first welcome: this leaves only ~300
        // octets of headroom for a prospective welcome that needs ~800.
        val bad = limits().put("max_input_state_bytes", 4_194_000)
        try {
            CompanionEngine(CompanionConfig(
                serverName = "kat-companion", serverVersion = "1.0.0",
                pairings = mapOf(katPid to katToken),
                supportedCapabilities = emptySet(),
                surfaceProfiles = profiles(), limits = bad)) { }
            fail("reservation violation accepted")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("reservation")
                || e.message!!.contains("max_"))
        }
    }

    // ------------------------------------------------- surfaces via wire

    @Test
    fun surfaceLifecycleThroughEngineAndAcrossConnections() {
        val out = mutableListOf<JSONObject>()
        val store = SurfaceStore(16, 1024)
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat-companion", serverVersion = "1.0.0",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = profiles(), limits = limits(),
            nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        // Reuse the shared-store constructor path.
        val engineWithStore = CompanionEngine(CompanionConfig(
            serverName = "kat-companion", serverVersion = "1.0.0",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = profiles(), limits = limits(),
            nonceSource = { katSn }), store) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engineWithStore.feed(frame(hello()))
        engineWithStore.feed(frame(auth()))
        // Applied result through the wire.
        val spec = JSONObject().put("t", "text").put("text", "hi")
        engineWithStore.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 5).put("spec", spec))))
        val applied = out.last().getJSONObject("result")
        assertEquals("applied", applied.getString("status"))
        assertEquals(5, applied.getLong("revision"))
        // Structural params failure is -32602, not 1201.
        engineWithStore.feed(frame(request("s2", "surface.update", JSONObject()
            .put("surface", "app:main").put("spec", spec))))
        assertEquals(-32602, out.last().getJSONObject("error").getInt("code"))
        // Content failure is 1201 with the failing path (SPEC 13.2).
        engineWithStore.feed(frame(request("s3", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 6)
            .put("spec", JSONObject().put("t", "text")))))
        val contentError = out.last().getJSONObject("error")
        assertEquals(1201, contentError.getInt("code"))
        assertTrue(contentError.getJSONObject("data").has("path"))
        // Ungranted namespace is 1201 (SPEC 13.1).
        engineWithStore.feed(frame(request("s4", "surface.update", JSONObject()
            .put("surface", "widget:w").put("revision", 1).put("spec", spec))))
        assertEquals("namespace-not-granted", out.last().getJSONObject("error")
            .getJSONObject("data").getString("reason"))
        // Removal tombstones; the shared store carries floors to the next
        // connection's welcome (SPEC 10.4/13.3).
        engineWithStore.feed(frame(request("s5", "surface.remove", JSONObject()
            .put("surface", "app:main").put("revision", 9))))
        assertEquals(false, out.last().getJSONObject("result").getBoolean("present"))
        val secondOut = mutableListOf<JSONObject>()
        val second = CompanionEngine(CompanionConfig(
            serverName = "kat-companion", serverVersion = "1.0.0",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = profiles(), limits = limits(),
            nonceSource = { katSn }), store) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(secondOut::add); d.finish() }
        }
        second.feed(frame(hello()))
        second.feed(frame(auth()))
        val reported = secondOut.last().getJSONObject("result")
            .getJSONObject("surfaces").getJSONObject("app:main")
        assertEquals(9, reported.getLong("revision"))
        assertEquals(false, reported.getBoolean("present"))
        // The first engine (fresh store) never saw any of it.
        assertEquals(SessionState.CONNECTED, engine.state)
    }

    // -------------------------------------------- registry drift guard --

    @Test
    fun methodRegistryMatchesContract() {
        val contract = JSONObject(ebpDir.resolve("contract.json").readText())
        val methods = contract.getJSONObject("methods")
        assertEquals(methods.keySet(), METHOD_REGISTRY.keys)
        for (name in methods.keySet()) {
            val row = methods.getJSONObject(name)
            val spec = METHOD_REGISTRY.getValue(name)
            assertEquals("$name sender", row.getString("sender"),
                spec.sender.name.lowercase())
            assertEquals("$name class", row.getString("class"),
                if (spec.isRequest) "request" else "notification")
            val states = row.getJSONArray("states").let { a ->
                (0 until a.length()).map { a.getString(it) }.toSet()
            }
            assertEquals("$name states", states,
                spec.states.map { it.name }.toSet())
        }
    }
}
