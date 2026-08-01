// SPDX-License-Identifier: GPL-3.0-or-later
// W3 conformance: the Companion engine against SPEC 9-10 — the KAT
// handshake end to end, pre-auth fail-closed vectors (SPEC 24.6 items 4-5),
// state gating, ready-response ordering, the welcome reservation check,
// and the method-registry-vs-contract drift guard.
package com.calebc42.ebp.wire

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class CompanionEngineTest {

    private val ebpDir = File(System.getProperty("ebp.dir")
        ?: error("ebp.dir system property not set"))

    private fun profiles(): JsonObject = buildJsonObject {
        putJsonObject("app") {
            put("node_types", JsonArray(listOf(
                "text", "row", "column", "box", "spacer", "divider",
                "button", "text_input").map(::JsonPrimitive)))
            put("builtins", JsonArray(listOf(
                "view.switch", "companion.settings.open").map(::JsonPrimitive)))
            put("features", JsonArray(emptyList()))
        }
    }

    private fun engine(sink: MutableList<JsonObject>,
                       supported: Set<String> = setOf("theme"),
                       nonce: String = katSn): CompanionEngine =
        CompanionEngine(
            CompanionConfig(
                serverName = "kat-companion", serverVersion = "1.0.0",
                pairings = mapOf(katPid to katToken),
                supportedCapabilities = supported,
                surfaceProfiles = profiles(),
                limits = testLimits(),
                nonceSource = { nonce },
            )
        ) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(sink::add); d.finish() }
        }

    private fun engineWithLimits(limits: JsonObject): CompanionEngine =
        CompanionEngine(
            CompanionConfig(
                serverName = "kat-companion", serverVersion = "1.0.0",
                pairings = mapOf(katPid to katToken),
                supportedCapabilities = setOf("theme"),
                surfaceProfiles = profiles(),
                limits = limits,
                nonceSource = { katSn },
            )
        ) { }

    private fun hello(wants: List<String> = listOf("theme")): JsonObject =
        request("h1", "session.hello", EbpAuth.helloParams(
            "test-client", "0.0.1", katPid, katCn, wants))

    private fun auth(): JsonObject =
        request("h2", "auth.response", EbpAuth.authParams(katPid, katCn, katSn, katToken))

    // ---------------------------------------------------------- handshake

    @Test
    fun katHandshakeReachesReadyInBarrierOrder() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello()))
        assertEquals(SessionState.CHALLENGED, engine.state)
        assertEquals(katSn, out.last().reqObj("result").reqString("server_nonce"))

        engine.feed(frame(auth()))
        assertEquals(SessionState.SYNCING, engine.state)
        val welcome = out.last().reqObj("result")
        // SPEC 9.3: the welcome carries the exact KAT server proof.
        assertEquals(EbpAuth.serverProof(katToken, katPid, katCn, katSn),
            welcome.reqString("server_proof"))
        // SPEC 10.2 required members; wants intersection.
        for (m in listOf("server_proof", "protocol", "server", "granted",
                         "surface_profiles", "surfaces", "queued_events", "limits"))
            assertTrue("welcome missing $m", m in welcome)
        assertEquals(listOf("theme"),
            welcome.reqArr("granted").map { it.asStringOrNull() })

        engine.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        val replay = out.last().reqObj("result")
        assertEquals(0L, replay.reqLong("remaining"))
        assertEquals(JsonNull, replay["blocked_by"])
        assertEquals(SessionState.SYNCING, engine.state)

        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        // SPEC 10.3: the {} response is emitted, and only then READY.
        assertEquals(JsonPrimitive("r1"), out.last()["id"])
        assertEquals(0, out.last().reqObj("result").size)
        assertEquals(SessionState.READY, engine.state)
    }

    // ------------------------------------- pre-auth fail-closed (24.6 4-5)

    @Test
    fun preAuthRequestsAreRefusedWithoutInformation() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        // SPEC 10.1: in CONNECTED, even an unknown or later-legal request
        // gets 1200 — never -32601, never a method-specific answer.
        for (method in listOf("surface.update", "no.such.method", "session.ready")) {
            engine.feed(frame(request("x1", method, JsonObject(emptyMap()))))
            assertEquals(1200L, out.last().reqObj("error").reqLong("code"))
            assertEquals(SessionState.CONNECTED, engine.state)
        }
        // Notifications before authentication are dropped without output.
        val before = out.size
        engine.feed(frame(notification("state.changed", JsonObject(emptyMap()))))
        assertEquals(before, out.size)
        // CHALLENGED refuses everything but auth.response identically.
        engine.feed(frame(hello()))
        engine.feed(frame(request("x2", "queue.replay", JsonObject(emptyMap()))))
        assertEquals(1200L, out.last().reqObj("error").reqLong("code"))
    }

    @Test
    fun badProofFailsClosedWithoutDistinguishingCause() {
        val out = mutableListOf<JsonObject>()
        // Unknown pairing ID and wrong proof must be indistinguishable: 1203.
        val engine = engine(out)
        engine.feed(frame(hello()))
        val wrong = request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken)
                .with("client_proof", JsonPrimitive("0".repeat(64))))
        engine.feed(frame(wrong))
        assertEquals(1203L, out.last().reqObj("error").reqLong("code"))
        assertEquals(SessionState.CLOSED, engine.state)
    }

    @Test
    fun unknownPairingIdIsIndistinguishableFromWrongProof() {
        // SPEC 9.2: an unknown pairing ID MUST be verified "with work
        // equivalent to the known-ID path — an HMAC-SHA256 computation
        // against a fixed dummy key and a constant-time comparison", so
        // neither the failure stage, the error code, nor response timing
        // separates the two. The observable half of that is testable: both
        // paths emit the SAME error frame and reach the same state.
        val unknownPid = "9f9e9d9c9b9a99989796959493929190"
        val someToken = EbpAuth.decodePairingToken("Dw4NDAsKCQgHBgUEAwIBAA")

        val unknownOut = mutableListOf<JsonObject>()
        val e1 = engine(unknownOut)
        e1.feed(frame(request("h1", "session.hello", EbpAuth.helloParams(
            "test-client", "0.0.1", unknownPid, katCn, listOf("theme")))))
        // A proof that is internally consistent — just for a pairing this
        // Companion has never heard of. Reaching 1203 here REQUIRES the dummy
        // HMAC to run: there is no real token to key it with.
        e1.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(unknownPid, katCn, katSn, someToken))))

        val wrongOut = mutableListOf<JsonObject>()
        val e2 = engine(wrongOut)
        e2.feed(frame(hello()))
        e2.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, someToken))))

        // Same challenge shape on the way in, same rejection on the way out.
        assertEquals(unknownOut.size, wrongOut.size)
        assertEquals(unknownOut.first().toString(), wrongOut.first().toString())
        assertEquals(unknownOut.last().toString(), wrongOut.last().toString())
        assertEquals(1203L, unknownOut.last().reqObj("error").reqLong("code"))
        assertEquals(SessionState.CLOSED, e1.state)
        assertEquals(SessionState.CLOSED, e2.state)
    }

    @Test
    fun malformedAuthIsInvalidParamsThenClose() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello()))
        val malformed = request("h2", "auth.response", buildJsonObject {
            put("pairing_id", katPid); put("client_nonce", katCn)
            put("server_nonce", katSn); put("client_proof", "not-hex")
        })
        engine.feed(frame(malformed))
        assertEquals(-32602L, out.last().reqObj("error").reqLong("code"))
        assertEquals(SessionState.CLOSED, engine.state)
    }

    @Test
    fun mismatchedNonceInAuthFailsClosed() {
        // SPEC 24.6 item 6 (mismatched): a well-formed auth.response whose
        // client_nonce is not the one the challenge issued fails at 1203 —
        // the cn == pendingClientNonce guard, exercised in the failing case.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello())) // issues cn = katCn
        val otherCn = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, otherCn, katSn, katToken))))
        assertEquals(1203L, out.last().reqObj("error").reqLong("code"))
        assertEquals(SessionState.CLOSED, engine.state)
    }

    @Test
    fun replayedProofFromAnotherSessionFailsClosed() {
        // SPEC 24.6 item 6 (replayed): a proof bound to a prior session's
        // server_nonce cannot authenticate a session that issued a different
        // one — the sn == pendingServerNonce guard, in the failing case.
        val out = mutableListOf<JsonObject>()
        val snB = "3f3e3d3c3b3a39383736353433323130"
        val engine = engine(out, nonce = snB) // this session issues snB, not katSn
        engine.feed(frame(hello()))
        // Replay a valid proof from a session whose server_nonce was katSn.
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        assertEquals(1203L, out.last().reqObj("error").reqLong("code"))
        assertEquals(SessionState.CLOSED, engine.state)
    }

    @Test
    fun wrongProtocolMajorIs1202WithSupportedList() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        val h = request("h1", "session.hello", EbpAuth.helloParams(
            "test-client", "0.0.1", katPid, katCn, listOf("theme"))
            .with("protocol", JsonPrimitive(1)))
        engine.feed(frame(h))
        val error = out.last().reqObj("error")
        assertEquals(1202L, error.reqLong("code"))
        assertEquals(2L, integralLongOrNull(error.reqObj("data").reqArr("supported")[0]))
    }

    @Test
    fun duplicateWantsAreInvalidParams() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello(wants = listOf("theme", "theme"))))
        assertEquals(-32602L, out.last().reqObj("error").reqLong("code"))
    }

    // ------------------------------------------------- post-auth dispatch

    private fun authedEngine(out: MutableList<JsonObject>): CompanionEngine =
        engine(out).also {
            it.feed(frame(hello()))
            it.feed(frame(auth()))
        }

    @Test
    fun postAuthDispatchRules() {
        val out = mutableListOf<JsonObject>()
        val engine = authedEngine(out)
        // READY-only request during SYNCING -> 1204 (SPEC 10.1).
        engine.feed(frame(request("d1", "capability.invoke",
            buildJsonObject { put("cap", "vibrate") })))
        assertEquals(1204L, out.last().reqObj("error").reqLong("code"))
        // Unknown request post-auth -> -32601 (SPEC 7.3).
        engine.feed(frame(request("d2", "no.such", JsonObject(emptyMap()))))
        assertEquals(-32601L, out.last().reqObj("error").reqLong("code"))
        // Companion-direction method arriving inbound as a request -> -32600.
        engine.feed(frame(request("d3", "event.action", JsonObject(emptyMap()))))
        assertEquals(-32600L, out.last().reqObj("error").reqLong("code"))
        // Notification-class method sent as a request -> -32600.
        engine.feed(frame(request("d4", "theme.set", JsonObject(emptyMap()))))
        assertEquals(-32600L, out.last().reqObj("error").reqLong("code"))
        // Integer request id conforms (SPEC 7.2, amendment #34 — the
        // jsonrpc.el floor) and is answered under the same id.
        engine.feed(frame(buildJsonObject { put("jsonrpc", "2.0"); put("id", 7)
            put("method", "queue.replay"); put("params", JsonObject(emptyMap())) }))
        assertEquals(JsonPrimitive(7), out.last()["id"])
        assertTrue("result" in out.last())
        // None of that killed the session.
        assertEquals(SessionState.SYNCING, engine.state)
    }

    @Test
    fun framingErrorClosesTheConnection() {
        val out = mutableListOf<JsonObject>()
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
        val bad = testLimits("max_input_state_bytes" to 4_194_000)
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
        val out = mutableListOf<JsonObject>()
        val store = SurfaceStore(16, 1024)
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat-companion", serverVersion = "1.0.0",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = profiles(), limits = testLimits(),
            nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        // Reuse the shared-store constructor path.
        val engineWithStore = CompanionEngine(CompanionConfig(
            serverName = "kat-companion", serverVersion = "1.0.0",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = profiles(), limits = testLimits(),
            nonceSource = { katSn }), store) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engineWithStore.feed(frame(hello()))
        engineWithStore.feed(frame(auth()))
        // Applied result through the wire.
        val spec = buildJsonObject { put("t", "text"); put("text", "hi") }
        engineWithStore.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 5); put("spec", spec) })))
        val applied = out.last().reqObj("result")
        assertEquals("applied", applied.reqString("status"))
        assertEquals(5L, applied.reqLong("revision"))
        // Structural params failure is -32602, not 1201.
        engineWithStore.feed(frame(request("s2", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("spec", spec) })))
        assertEquals(-32602L, out.last().reqObj("error").reqLong("code"))
        // Content failure is 1201 with the failing path (SPEC 13.2).
        engineWithStore.feed(frame(request("s3", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 6)
            put("spec", buildJsonObject { put("t", "text") }) })))
        val contentError = out.last().reqObj("error")
        assertEquals(1201L, contentError.reqLong("code"))
        assertTrue("path" in contentError.reqObj("data"))
        // Ungranted namespace is 1201 (SPEC 13.1).
        engineWithStore.feed(frame(request("s4", "surface.update", buildJsonObject {
            put("surface", "widget:w"); put("revision", 1); put("spec", spec) })))
        assertEquals("namespace-not-granted", out.last().reqObj("error")
            .reqObj("data").reqString("reason"))
        // Removal tombstones; the shared store carries floors to the next
        // connection's welcome (SPEC 10.4/13.3).
        engineWithStore.feed(frame(request("s5", "surface.remove", buildJsonObject {
            put("surface", "app:main"); put("revision", 9) })))
        assertEquals(false, out.last().reqObj("result").boolOrNull("present"))
        val secondOut = mutableListOf<JsonObject>()
        val second = CompanionEngine(CompanionConfig(
            serverName = "kat-companion", serverVersion = "1.0.0",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = profiles(), limits = testLimits(),
            nonceSource = { katSn }), store) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(secondOut::add); d.finish() }
        }
        second.feed(frame(hello()))
        second.feed(frame(auth()))
        val reported = secondOut.last().reqObj("result")
            .reqObj("surfaces").reqObj("app:main")
        assertEquals(9L, reported.reqLong("revision"))
        assertEquals(false, reported.boolOrNull("present"))
        // The first engine (fresh store) never saw any of it.
        assertEquals(SessionState.CONNECTED, engine.state)
    }

    // -------------------------------------------- registry drift guard --

    @Test
    fun methodRegistryMatchesContract() {
        val contract = Json.parseToJsonElement(
            ebpDir.resolve("contract.json").readText()) as JsonObject
        val methods = contract.reqObj("methods")
        assertEquals(methods.keys, METHOD_REGISTRY.keys)
        for (name in methods.keys) {
            val row = methods.reqObj(name)
            val spec = METHOD_REGISTRY.getValue(name)
            assertEquals("$name sender", row.reqString("sender"),
                spec.sender.name.lowercase())
            assertEquals("$name class", row.reqString("class"),
                if (spec.isRequest) "request" else "notification")
            val states = row.reqArr("states").map { it.asStringOrNull()!! }.toSet()
            assertEquals("$name states", states,
                spec.states.map { it.name }.toSet())
        }
    }

    // ---------------------------------------- wire error responses (6.2/7.3)

    private fun arrayParamsRequest(id: String, method: String): JsonObject =
        buildJsonObject {
            put("jsonrpc", "2.0"); put("id", id); put("method", method)
            put("params", buildJsonArray { add(1) })
        }

    @Test
    fun nonObjectParamsAreInvalidParamsNotCoerced() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        // SPEC 10.1: a non-handshake pre-auth request is 1200 regardless of
        // params — the state gate precedes the params check.
        engine.feed(frame(arrayParamsRequest("x1", "surface.update")))
        assertEquals(1200L, out.last().reqObj("error").reqLong("code"))
        // SPEC 10.1: the legal handshake method with array params is -32602.
        engine.feed(frame(arrayParamsRequest("h1", "session.hello")))
        assertEquals(-32602L, out.last().reqObj("error").reqLong("code"))
        assertEquals(SessionState.CONNECTED, engine.state)
        // Post-auth: session.ready with a positional array is -32602 and MUST
        // NOT drive the machine to READY (audit finding: coercion to {}).
        engine.feed(frame(hello())); engine.feed(frame(auth()))
        assertEquals(SessionState.SYNCING, engine.state)
        engine.feed(frame(arrayParamsRequest("r1", "session.ready")))
        assertEquals(-32602L, out.last().reqObj("error").reqLong("code"))
        assertEquals(SessionState.SYNCING, engine.state)
        // The well-formed request still reaches READY.
        engine.feed(frame(request("r2", "session.ready", JsonObject(emptyMap()))))
        assertEquals(SessionState.READY, engine.state)
    }

    @Test
    fun bodyErrorsAnswerWithIdNullAndKeepTheConnection() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello())); engine.feed(frame(auth()))
        assertEquals(SessionState.SYNCING, engine.state)
        // SPEC 6.2: invalid JSON -> Parse Error, id:null, connection open.
        engine.feed(encodeFrame("{ not json"))
        assertEquals(JsonNull, out.last()["id"])
        assertEquals(-32700L, out.last().reqObj("error").reqLong("code"))
        assertTrue(engine.state != SessionState.CLOSED)
        // SPEC 6.2/4.1: a top-level array -> Invalid Request, id:null.
        engine.feed(encodeFrame("[]"))
        assertEquals(JsonNull, out.last()["id"])
        assertEquals(-32600L, out.last().reqObj("error").reqLong("code"))
        // SPEC 4.1: duplicate member names -> Invalid Request, id:null.
        engine.feed(encodeFrame("""{"a":1,"a":2}"""))
        assertEquals(-32600L, out.last().reqObj("error").reqLong("code"))
        assertTrue(engine.state != SessionState.CLOSED)
        // The session still works: a valid request is answered normally.
        engine.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        assertEquals(JsonPrimitive("q1"), out.last()["id"])
        assertNotNull(out.last().reqObj("result"))
    }

    @Test
    fun aGoodFramePipelinedBeforeABadOneIsNotLost() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello())); engine.feed(frame(auth()))
        val base = out.size
        // One transport read: a valid queue.replay then an invalid-JSON
        // frame. The good frame is answered AND the bad one gets its id:null
        // Parse Error — the earlier decode is not discarded.
        engine.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))) + encodeFrame("{bad"))
        val emitted = out.drop(base)
        assertTrue("queue.replay answered",
            emitted.any { it["id"] == JsonPrimitive("q1") && "result" in it })
        assertTrue("parse error emitted", emitted.any {
            it["id"] == JsonNull &&
                it.objOrNull("error")?.reqLong("code") == -32700L })
    }

    @Test
    fun overDeepBodyIsRejectedBeforeParsing() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello())); engine.feed(frame(auth()))
        // SPEC 4.5: 65 nested containers exceed the limit -> Parse Error with
        // id:null, and no stack overflow because the check precedes the parse.
        engine.feed(encodeFrame("{\"a\":".repeat(65) + "1" + "}".repeat(65)))
        assertEquals(JsonNull, out.last()["id"])
        assertEquals(-32700L, out.last().reqObj("error").reqLong("code"))
        assertTrue(engine.state != SessionState.CLOSED)
        // Exactly 64 is within the limit: it parses (and, lacking a jsonrpc
        // marker, is dropped) — no Parse Error is emitted.
        val base = out.size
        engine.feed(encodeFrame("{\"a\":".repeat(64) + "1" + "}".repeat(64)))
        assertTrue(out.drop(base).none {
            it.objOrNull("error")?.let { e -> integralLongOrNull(e["code"]) } == -32700L })
    }

    @Test
    fun welcomeReservationCountsWorstCaseSurfaces() {
        // SPEC 4.5: a config whose max_surface_ids reservation alone overflows
        // the frame budget MUST be rejected — surfaces used to be counted as
        // an empty object (audit finding 8).
        val overcommitted = testLimits("max_surfaces" to 30000, "max_surface_ids" to 30000)
        try {
            engineWithLimits(overcommitted)
            fail("reservation-violating config accepted")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("reservation"))
        }
        // The default config still fits with the worst case now counted.
        engineWithLimits(testLimits())
    }

    // -------------------------------------- method-name bound (amendment #93)

    @Test
    fun methodNameGetsGrammarAndBoundBeforeTheRegistry() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello()))
        engine.feed(frame(auth()))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        // Over-long (129+ octets) and non-identifier method names are -32601
        // without consulting the registry (SPEC 11/4.5, amendment #93).
        engine.feed(frame(request("m1", "x".repeat(200), JsonObject(emptyMap()))))
        assertEquals(-32601L, out.replyTo("m1")
            .reqObj("error").reqLong("code"))
        engine.feed(frame(request("m2", "bad name!", JsonObject(emptyMap()))))
        assertEquals(-32601L, out.replyTo("m2")
            .reqObj("error").reqLong("code"))
        // A malformed notification method is dropped silently.
        val before = out.size
        engine.feed(frame(buildJsonObject { put("jsonrpc", "2.0")
            put("method", "y".repeat(200)); put("params", JsonObject(emptyMap())) }))
        assertEquals(before, out.size)
    }

    // ------------------------------------------ post-fault drain (SPEC 6.2)

    @Test
    fun aFramePipelinedBehindABadOneIsStillDispatched() {
        // SPEC 6.2 permits continuing after a recoverable body fault, and
        // amendment #91 forbids an unbounded stall. The fault unwound the
        // decoder's drain loop, so a request pipelined BEHIND the bad frame
        // stayed buffered — never dispatched, never answered — until more
        // bytes happened to arrive. If the peer was waiting on that response
        // before sending anything else, the session deadlocked.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello()))
        engine.feed(frame(auth()))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        val bad = encodeFrame("[1,2]")                       // top-level array
        val good = frame(request("q1", "queue.replay", JsonObject(emptyMap())))
        engine.feed(bad + good)
        // One Invalid Request for the bad frame...
        assertTrue(out.any { it["id"] == JsonNull &&
            it.objOrNull("error")?.let { e -> integralLongOrNull(e["code"]) } == -32600L })
        // ...and the pipelined request behind it was answered in the same feed.
        assertNotNull(out.lastOrNull { it["id"] == JsonPrimitive("q1") })
    }

    @Test
    fun outstandingRequestsAreBoundedWithHysteresis() {
        // SPEC 22.3 (LD-13 bound half): `pending` grew without limit against
        // a peer that stops answering. kbd_buffer's discipline: hold at HIGH,
        // resume only below LOW — a single cap thrashes at the boundary.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello()))
        engine.feed(frame(auth()))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        var refused = 0
        fun send() = engine.sendRequest("event.action", JsonObject(emptyMap())) { _, err ->
            if (err?.let { integralLongOrNull(it["code"]) } == 1401L) refused++
        }
        repeat(512) { send() }   // fills to HOLD; none refused yet
        assertEquals(0, refused)
        send()                   // the 513th fails locally, exactly once
        assertEquals(1, refused)
        // Answering one request does NOT resume (hysteresis, not a cap).
        val firstId = out.events().first()["id"]!!
        engine.feed(frame(buildJsonObject { put("jsonrpc", "2.0"); put("id", firstId)
            put("result", JsonObject(emptyMap())) }))
        send()
        assertEquals(2, refused)
        // Draining below RESUME (128) reopens the gate.
        for (m in out.events().drop(1).take(400))
            engine.feed(frame(buildJsonObject { put("jsonrpc", "2.0")
                put("id", m["id"]!!); put("result", JsonObject(emptyMap())) }))
        send()
        assertEquals(2, refused) // accepted again
    }

    @Test
    fun theDurablePumpIsExemptFromTheOutstandingRequestBound() {
        // The bound's callback fires SYNCHRONOUSLY, and onPumpResult reads any
        // error as a PEER response: an unexempted pump would pause itself and
        // report blocked_by "overloaded" for an error the peer never sent,
        // stalling SPEC 15.3 durable delivery on our own load. The pump is
        // single-flight by construction, so it can never be the resource the
        // ceiling protects.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello()))
        engine.feed(frame(auth()))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 1)
            put("spec", buildJsonObject { put("t", "text"); put("text", "x") }) })))
        // Fill the outstanding-request ceiling with unanswered requests.
        repeat(512) { engine.sendRequest("event.action", JsonObject(emptyMap())) { _, _ -> } }
        // A durable event admitted now must still reach the wire.
        val before = out.count { it.stringOrNull("method") == "event.action" }
        engine.dispatchAction("app:main", buildJsonObject {
            put("action", "demo.act"); put("when_offline", "queue")
            put("ttl_s", 3600) }, null)
        assertEquals("the pump still delivered", before + 1,
            out.count { it.stringOrNull("method") == "event.action" })
        // Answer it, then admit another: the pump must still be running. An
        // unexempted pump would have set pumpPaused on the synthetic error
        // and this second event would never leave the queue.
        val delivered = out.events().last()
        engine.feed(frame(buildJsonObject { put("jsonrpc", "2.0")
            put("id", delivered["id"]!!)
            put("result", buildJsonObject { put("status", "accepted") }) }))
        engine.dispatchAction("app:main", buildJsonObject {
            put("action", "demo.act2"); put("when_offline", "queue")
            put("ttl_s", 3600) }, null)
        assertEquals("the pump was not paused by a local refusal", before + 2,
            out.count { it.stringOrNull("method") == "event.action" })
    }

    // ------------------------------------------------------ close (SPEC 22.3)

    @Test
    fun closeFailsOutstandingRequestsLocally() {
        // SPEC 22.3 (LD-13): "Outstanding requests fail locally" — a callback
        // parked in `pending` when the transport dies is invoked once with a
        // synthetic terminal error, never left waiting forever.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feed(frame(hello()))
        engine.feed(frame(auth()))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        var got: JsonObject? = null
        engine.sendRequest("event.action", buildJsonObject { put("k", "v") }) { _, err -> got = err }
        assertTrue(got == null)
        engine.close("transport closed")
        assertNotNull(got)
        assertEquals("connection-closed", got!!.reqObj("data").reqString("kind"))
    }

    @Test
    fun closeSurvivesAThrowingHostListener() {
        // LD-18: a throwing host callout during teardown must not abort the
        // rest of close() — pending still drains and the engine still reaches
        // CLOSED (serve()'s finally has no retry, and the firing detach runs
        // before any callout can throw).
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, supported = setOf("theme", "surfaces.dialog"))
        engine.feed(frame(hello(listOf("theme", "surfaces.dialog"))))
        engine.feed(frame(auth()))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        engine.dialogListener = { _, spec ->
            if (spec == null) throw RuntimeException("host UI died")
        }
        engine.feed(frame(request("d1", "dialog.show", buildJsonObject {
            put("dialog_id", "dlg")
            put("spec", buildJsonObject { put("t", "text"); put("text", "x") }) })))
        var got: JsonObject? = null
        engine.sendRequest("event.action", JsonObject(emptyMap())) { _, err -> got = err }
        engine.close("transport closed")
        assertEquals(SessionState.CLOSED, engine.state)
        assertNotNull(got)
    }
}
