// SPDX-License-Identifier: GPL-3.0-or-later
// P0 pre-swap pin (PLAN-rf2 §0.2 item 3): request-ID identity.
//
// SPEC 4.3 gives no type coercion: `"1"` and `1` are DIFFERENT ids. The
// Companion numbers its own outbound requests with integers, so a response
// whose id is the STRING "1" must not conclude the pending INTEGER 1.
//
// Everything hangs on this. The durable pump delivers one event.action at a
// time and advances only when its response is matched (SPEC 15.3); match on
// the wrong id and the pump either stalls forever or advances on a stranger's
// answer. Post-swap the id map is keyed on Long and the RESPONSE arm reads
// `requestIdKey` (isString-guarded) — org.json's `getLong` would happily
// coerce "1" to 1, which is exactly the coercion that must NOT survive.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EnvelopeIdTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits() = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64)

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    private fun readyEngine(out: MutableList<JSONObject>): CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text", "text_input", "button")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, emptyList()))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        return engine
    }

    private fun surfaceWithButton(store: SurfaceStore) {
        store.update("app:main", 1, JSONObject().put("t", "button")
            .put("label", "go").put("on_tap", JSONObject().put("action", "a.b")),
            null, null, null)
    }

    /** The one outbound event.action the engine is waiting on. */
    private fun pendingEvent(out: List<JSONObject>): JSONObject =
        out.last { it.opt("method") == "event.action" }

    @Test
    fun responseIdStringNeverMatchesIntegerPending() {
        val out = mutableListOf<JSONObject>()
        val store = SurfaceStore(16, 1024)
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("button")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn }), store, queue) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, emptyList()))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        surfaceWithButton(store)

        // A durable tap: the engine sends event.action and waits.
        engine.dispatchAction("app:main", JSONObject().put("action", "a.b")
            .put("when_offline", "queue").put("ttl_s", 3600), null)
        val event = pendingEvent(out)
        val intId = event.get("id")
        assertTrue("the Companion numbers its own requests with integers",
            intId is Int || intId is Long)
        val queuedBefore = queue.count()

        // The STRING spelling of that id must conclude nothing.
        engine.feed(frame(JSONObject().put("jsonrpc", "2.0")
            .put("id", intId.toString())
            .put("result", JSONObject().put("status", "accepted"))))
        assertEquals("a string id must not conclude an integer pending",
            queuedBefore, queue.count())

        // The INTEGER spelling concludes it: the record is deleted and the
        // pump advances (SPEC 15.3 permanent result).
        engine.feed(frame(JSONObject().put("jsonrpc", "2.0")
            .put("id", intId)
            .put("result", JSONObject().put("status", "accepted"))))
        assertEquals("the integer id must conclude the pending request",
            queuedBefore - 1, queue.count())
    }

    @Test
    fun inboundStringIdsAreEchoedVerbatim() {
        // The mirror image: Emacs numbers ITS requests however it likes, and
        // the Companion echoes the id back with its type intact. jsonrpc.el
        // sends integers (amendment #34), a hand-rolled client may send
        // strings, and a response that changes the spelling matches nothing
        // on the peer's side.
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        engine.feed(frame(JSONObject().put("jsonrpc", "2.0").put("id", 4242)
            .put("method", "queue.replay").put("params", JSONObject())))
        val intReply = out.last { it.opt("id") == 4242 }
        assertTrue("an integer request id echoes as an integer",
            intReply.get("id").let { it is Int || it is Long })

        engine.feed(frame(request("s-1", "queue.replay", JSONObject())))
        val strReply = out.last { it.opt("id") == "s-1" }
        assertEquals("s-1", strReply.get("id"))
        assertTrue("a string request id echoes as a string",
            strReply.get("id") is String)
    }

    @Test
    fun idEqualityIsTypedAtTheEqualityLayer() {
        // The rule stated where the swap will re-implement it (JsonEquality):
        // numbers compare by VALUE across spellings, strings never equal
        // numbers. Marked MUST-PORT-UNCHANGED in the runbook.
        assertTrue(jsonValueEquals(1, 1.0))
        assertTrue(jsonValueEquals(1L, 1))
        assertEquals(false, jsonValueEquals("1", 1))
        assertEquals(false, jsonValueEquals(1, "1"))
    }
}
