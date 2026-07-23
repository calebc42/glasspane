// SPDX-License-Identifier: GPL-3.0-or-later
// W5 conformance: event.action construction and the 4-status protocol
// (SPEC 14.1/14.3/14.4), occurrence-time capture_fields, state-before-
// action ordering (SPEC 14.6), and response correlation for
// Companion-originated requests.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActionEventTest {

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

    private fun readyEngine(out: MutableList<JSONObject>): CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat-companion", serverVersion = "1.0.0",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text", "text_input", "button")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        fun frame(msg: JSONObject) = encodeFrame(msg.toString())
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, emptyList()))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 5)
            .put("spec", JSONObject().put("t", "text_input")
                .put("id", "title").put("value", "authored")))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        assertEquals(SessionState.READY, engine.state)
        return engine
    }

    private fun descriptor(vararg capture: String): JSONObject =
        JSONObject().put("action", "demo.tap")
            .put("args", JSONObject().put("k", 1))
            .also {
                if (capture.isNotEmpty())
                    it.put("capture_fields", JSONArray(capture.toList()))
            }

    @Test
    fun eventConstructionAndStatusRoundTrip() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        var status: String? = null
        engine.publishState("app:main", "title", "typed")
        engine.dispatchAction("app:main", descriptor("title"), "clicked") { s, _ ->
            status = s
        }
        // SPEC 14.6: state.changed precedes the action on the wire.
        val stateIdx = out.indexOfFirst { it.opt("method") == "state.changed" }
        val eventIdx = out.indexOfFirst { it.opt("method") == "event.action" }
        assertTrue(stateIdx in 0 until eventIdx)
        val stateParams = out[stateIdx].getJSONObject("params")
        assertEquals(5, stateParams.getLong("revision_seen"))
        assertEquals("typed", stateParams.getString("value"))
        // SPEC 14.4 event shape.
        val event = out[eventIdx]
        val params = event.getJSONObject("params")
        assertTrue(EbpAuth.isValidNonce(params.getString("event_id")))
        assertEquals("demo.tap", params.getString("action"))
        assertEquals("app:main", params.getString("surface"))
        assertEquals(5, params.getLong("revision_seen"))
        assertTrue(params.getLong("occurred_at_ms") > 0)
        // SPEC 14.3 injection beside authored args.
        assertEquals("clicked", params.getJSONObject("args").getString("value"))
        assertEquals(1, params.getJSONObject("args").getInt("k"))
        // SPEC 14.1: the occurrence-time captured draft.
        assertEquals("typed", params.getJSONObject("fields").getString("title"))
        // The 4-status result resolves the callback.
        engine.feed(encodeFrame(JSONObject().put("jsonrpc", "2.0")
            .put("id", event.getInt("id"))
            .put("result", JSONObject().put("status", "accepted")).toString()))
        assertEquals("accepted", status)
    }

    @Test
    fun multiMemberInjectionRidesBesideAuthoredArgs() {
        // SPEC 14.3: on_reorder-style hooks inject several members (from/to/
        // order), not just `value`; they land in a COPY beside authored args.
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        val injected = JSONObject().put("from", 2).put("to", 0)
            .put("order", JSONArray(listOf("c", "a", "b")))
        engine.dispatchAction("app:main", descriptor(), null, injected)
        val args = out.first { it.opt("method") == "event.action" }
            .getJSONObject("params").getJSONObject("args")
        assertEquals(2, args.getInt("from"))
        assertEquals(0, args.getInt("to"))
        assertEquals("c", args.getJSONArray("order").getString(0))
        assertEquals(1, args.getInt("k")) // authored args intact
    }

    @Test
    fun captureIsOccurrenceTimeNotDeliveryTime() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        engine.publishState("app:main", "title", "first")
        engine.dispatchAction("app:main", descriptor("title"), null)
        // A later edit must not rewrite the already-built occurrence.
        engine.publishState("app:main", "title", "second")
        val event = out.first { it.opt("method") == "event.action" }
        assertEquals("first",
            event.getJSONObject("params").getJSONObject("fields").getString("title"))
    }

    @Test
    fun captureFallsBackToAuthoredValue() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        // No draft: the authored value is the logical value (SPEC 13.6).
        engine.dispatchAction("app:main", descriptor("title"), null)
        val event = out.first { it.opt("method") == "event.action" }
        assertEquals("authored",
            event.getJSONObject("params").getJSONObject("fields").getString("title"))
    }

    @Test
    fun notReadyMeansDrop() {
        val out = mutableListOf<JSONObject>()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "s", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = emptySet(),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(NODE_SCHEMA.keys.toList())).put("builtins", JSONArray())
                .put("features", JSONArray())),
            limits = limits())) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        // The cached snapshot from an earlier session gives the node its
        // wire address (SPEC 13.5); this session never reached READY.
        engine.surfaces.update("app:main", 5,
            JSONObject().put("t", "text_input").put("id", "title"),
            null, null, null)
        engine.dispatchAction("app:main",
            JSONObject().put("action", "demo.tap"), null)
        engine.publishState("app:main", "title", "offline draft")
        // Nothing on the wire pre-READY; the draft is retained locally
        // for the next welcome's input_state (SPEC 14.6).
        assertTrue(out.isEmpty())
        assertEquals("offline draft", engine.surfaces.draft("app:main", "title"))
    }

    @Test
    fun responseCorrelationSurvivesReordering() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        val statuses = mutableListOf<String?>()
        engine.dispatchAction("app:main", descriptor(), null) { s, _ -> statuses.add(s) }
        engine.dispatchAction("app:main", descriptor(), null) { s, _ -> statuses.add(s) }
        val events = out.filter { it.opt("method") == "event.action" }
        assertEquals(2, events.size)
        // Answer the second first: callbacks must match ids, not order.
        engine.feed(encodeFrame(JSONObject().put("jsonrpc", "2.0")
            .put("id", events[1].getInt("id"))
            .put("result", JSONObject().put("status", "rejected")).toString()))
        engine.feed(encodeFrame(JSONObject().put("jsonrpc", "2.0")
            .put("id", events[0].getInt("id"))
            .put("result", JSONObject().put("status", "accepted")).toString()))
        assertEquals(listOf("rejected", "accepted"), statuses)
        // An unknown response id is ignored, not fatal.
        engine.feed(encodeFrame(JSONObject().put("jsonrpc", "2.0")
            .put("id", 999)
            .put("result", JSONObject().put("status", "accepted")).toString()))
        assertEquals(SessionState.READY, engine.state)
    }

    @Test
    fun passwordNodesNeverEmitStateChanged() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        // SPEC 14.6: a password node MUST NOT emit state.changed, hold a
        // draft, or enter input_state — the value never leaves volatile
        // widget memory through this path.
        engine.feed(encodeFrame(request("s2", "surface.update", JSONObject()
            .put("surface", "app:pw").put("revision", 1)
            .put("spec", JSONObject().put("t", "text_input")
                .put("id", "secret").put("password", true))).toString()))
        val before = out.size
        engine.publishState("app:pw", "secret", "hunter2")
        assertEquals(before, out.size) // nothing on the wire
        assertNull(engine.surfaces.draft("app:pw", "secret"))
        assertFalse(engine.surfaces.inputState().has("app:pw"))
        // And an ID with no stateful address publishes nothing either.
        engine.publishState("app:main", "no-such-node", "x")
        assertEquals(before, out.size)
    }
}
