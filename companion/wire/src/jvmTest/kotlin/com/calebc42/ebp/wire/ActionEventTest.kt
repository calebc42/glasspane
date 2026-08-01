// SPDX-License-Identifier: GPL-3.0-or-later
// W5 conformance: event.action construction and the 4-status protocol
// (SPEC 14.1/14.3/14.4), occurrence-time capture_fields, state-before-
// action ordering (SPEC 14.6), and response correlation for
// Companion-originated requests.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActionEventTest {

    private fun readyEngine(out: MutableList<JsonObject>): CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat-companion", serverVersion = "1.0.0",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(listOf("text", "text_input", "button")
                        .map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_rich_spans" to 4096, "max_table_cells" to 4096),
            nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, emptyList()))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 5)
            putJsonObject("spec") {
                put("t", "text_input"); put("id", "title"); put("value", "authored")
            }
        })))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        assertEquals(SessionState.READY, engine.state)
        return engine
    }

    private fun descriptor(vararg capture: String): JsonObject = buildJsonObject {
        put("action", "demo.tap")
        putJsonObject("args") { put("k", 1) }
        if (capture.isNotEmpty())
            put("capture_fields", JsonArray(capture.toList().map(::JsonPrimitive)))
    }

    @Test
    fun eventConstructionAndStatusRoundTrip() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        var status: String? = null
        engine.publishState("app:main", "title", JsonPrimitive("typed"))
        engine.dispatchAction("app:main", descriptor("title"), JsonPrimitive("clicked")) { s, _ ->
            status = s
        }
        // SPEC 14.6: state.changed precedes the action on the wire.
        val stateIdx = out.indexOfFirst { it.stringOrNull("method") == "state.changed" }
        val eventIdx = out.indexOfFirst { it.stringOrNull("method") == "event.action" }
        assertTrue(stateIdx in 0 until eventIdx)
        val stateParams = out[stateIdx].reqObj("params")
        assertEquals(5L, stateParams.reqLong("revision_seen"))
        assertEquals("typed", stateParams.reqString("value"))
        // SPEC 14.4 event shape.
        val event = out[eventIdx]
        val params = event.reqObj("params")
        assertTrue(EbpAuth.isValidNonce(params.reqString("event_id")))
        assertEquals("demo.tap", params.reqString("action"))
        assertEquals("app:main", params.reqString("surface"))
        assertEquals(5L, params.reqLong("revision_seen"))
        assertTrue(params.reqLong("occurred_at_ms") > 0)
        // SPEC 14.3 injection beside authored args.
        assertEquals("clicked", params.reqObj("args").reqString("value"))
        assertEquals(1L, params.reqObj("args").reqLong("k"))
        // SPEC 14.1: the occurrence-time captured draft.
        assertEquals("typed", params.reqObj("fields").reqString("title"))
        // The 4-status result resolves the callback.
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", event["id"]!!)
            putJsonObject("result") { put("status", "accepted") }
        }))
        assertEquals("accepted", status)
    }

    @Test
    fun multiMemberInjectionRidesBesideAuthoredArgs() {
        // SPEC 14.3: on_reorder-style hooks inject several members (from/to/
        // order), not just `value`; they land in a COPY beside authored args.
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        val injected = buildJsonObject {
            put("from", 2); put("to", 0)
            put("order", JsonArray(listOf("c", "a", "b").map(::JsonPrimitive)))
        }
        engine.dispatchAction("app:main", descriptor(), null, injected)
        val args = out.first { it.stringOrNull("method") == "event.action" }
            .reqObj("params").reqObj("args")
        assertEquals(2L, args.reqLong("from"))
        assertEquals(0L, args.reqLong("to"))
        assertEquals("c", args.reqArr("order")[0].asStringOrNull())
        assertEquals(1L, args.reqLong("k")) // authored args intact
    }

    @Test
    fun captureIsOccurrenceTimeNotDeliveryTime() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        engine.publishState("app:main", "title", JsonPrimitive("first"))
        engine.dispatchAction("app:main", descriptor("title"), null)
        // A later edit must not rewrite the already-built occurrence.
        engine.publishState("app:main", "title", JsonPrimitive("second"))
        val event = out.first { it.stringOrNull("method") == "event.action" }
        assertEquals("first",
            event.reqObj("params").reqObj("fields").reqString("title"))
    }

    @Test
    fun captureFallsBackToAuthoredValue() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        // No draft: the authored value is the logical value (SPEC 13.6).
        engine.dispatchAction("app:main", descriptor("title"), null)
        val event = out.first { it.stringOrNull("method") == "event.action" }
        assertEquals("authored",
            event.reqObj("params").reqObj("fields").reqString("title"))
    }

    @Test
    fun notReadyMeansDrop() {
        val out = mutableListOf<JsonObject>()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "s", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = emptySet(),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(NODE_SCHEMA.keys.map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_rich_spans" to 4096, "max_table_cells" to 4096))) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        // The cached snapshot from an earlier session gives the node its
        // wire address (SPEC 13.5); this session never reached READY.
        engine.surfaces.update("app:main", 5,
            buildJsonObject { put("t", "text_input"); put("id", "title") },
            null, null, null)
        engine.dispatchAction("app:main",
            buildJsonObject { put("action", "demo.tap") }, null)
        engine.publishState("app:main", "title", JsonPrimitive("offline draft"))
        // Nothing on the wire pre-READY; the draft is retained locally
        // for the next welcome's input_state (SPEC 14.6).
        assertTrue(out.isEmpty())
        assertEquals(JsonPrimitive("offline draft"), engine.surfaces.draft("app:main", "title"))
    }

    @Test
    fun responseCorrelationSurvivesReordering() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        val statuses = mutableListOf<String?>()
        engine.dispatchAction("app:main", descriptor(), null) { s, _ -> statuses.add(s) }
        engine.dispatchAction("app:main", descriptor(), null) { s, _ -> statuses.add(s) }
        val events = out.filter { it.stringOrNull("method") == "event.action" }
        assertEquals(2, events.size)
        // Answer the second first: callbacks must match ids, not order.
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", events[1]["id"]!!)
            putJsonObject("result") { put("status", "rejected") }
        }))
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", events[0]["id"]!!)
            putJsonObject("result") { put("status", "accepted") }
        }))
        assertEquals(listOf("rejected", "accepted"), statuses)
        // An unknown response id is ignored, not fatal.
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", 999)
            putJsonObject("result") { put("status", "accepted") }
        }))
        assertEquals(SessionState.READY, engine.state)
    }

    @Test
    fun passwordNodesNeverEmitStateChanged() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        // SPEC 14.6: a password node MUST NOT emit state.changed, hold a
        // draft, or enter input_state — the value never leaves volatile
        // widget memory through this path.
        engine.feed(frame(request("s2", "surface.update", buildJsonObject {
            put("surface", "app:pw"); put("revision", 1)
            putJsonObject("spec") {
                put("t", "text_input"); put("id", "secret"); put("password", true)
            }
        })))
        val before = out.size
        engine.publishState("app:pw", "secret", JsonPrimitive("hunter2"))
        assertEquals(before, out.size) // nothing on the wire
        assertNull(engine.surfaces.draft("app:pw", "secret"))
        assertFalse("app:pw" in engine.surfaces.inputState())
        // And an ID with no stateful address publishes nothing either.
        engine.publishState("app:main", "no-such-node", JsonPrimitive("x"))
        assertEquals(before, out.size)
    }
}
