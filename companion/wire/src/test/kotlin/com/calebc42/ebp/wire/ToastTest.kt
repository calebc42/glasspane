// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: toasts (SPEC 18.2). toast.show is a best-effort READY
// notification, gated on presentation.toast, with duration_s in 1..10.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ToastTest {

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
        .put("max_rich_spans", 4096).put("max_table_cells", 4096)

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    private fun readyEngine(seen: MutableList<Pair<String, Long?>>,
                            grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("presentation.toast") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("presentation.toast"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { }
        engine.toastListener = { text, d -> seen.add(text to d) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        return engine
    }

    private fun toast(vararg kv: Pair<String, Any>) = frame(notification(
        "toast.show", JSONObject().apply { kv.forEach { put(it.first, it.second) } }))

    @Test
    fun toastDuringSyncingIsDropped() {
        val seen = mutableListOf<Pair<String, Long?>>()
        // Reach SYNCING (auth ok) but NOT READY — no session.ready.
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1", pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("presentation.toast"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { }
        engine.toastListener = { text, d -> seen.add(text to d) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("presentation.toast")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        // SPEC 10.1: a READY-only toast.show arriving during SYNCING is dropped.
        engine.feed(toast("text" to "Saved"))
        assertTrue(seen.isEmpty())
    }

    @Test
    fun plainToastAndDurationBounds() {
        val seen = mutableListOf<Pair<String, Long?>>()
        val engine = readyEngine(seen)
        engine.feed(toast("text" to "Saved"))
        assertEquals("Saved" to null, seen.last())
        engine.feed(toast("text" to "Done", "duration_s" to 3))
        assertEquals("Done" to 3L, seen.last())
        // Out-of-range durations are dropped (SPEC 18.2: 1..10).
        val before = seen.size
        engine.feed(toast("text" to "x", "duration_s" to 0))
        engine.feed(toast("text" to "x", "duration_s" to 11))
        engine.feed(toast("duration_s" to 3)) // missing required text
        assertEquals(before, seen.size)
        // A best-effort notification never produces a frame.
        assertEquals(SessionState.READY, engine.state)
    }

    @Test
    fun ungrantedToastIsDropped() {
        val seen = mutableListOf<Pair<String, Long?>>()
        val engine = readyEngine(seen, grant = false)
        engine.feed(toast("text" to "nope"))
        assertEquals(0, seen.size)
    }

    @Test
    fun toastBeforeReadyIsDropped() {
        val seen = mutableListOf<Pair<String, Long?>>()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "k", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("presentation.toast"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(NODE_SCHEMA.keys.toList())).put("builtins", JSONArray())
                .put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { }
        engine.toastListener = { t, d -> seen.add(t to d) }
        // Pre-auth: SPEC 10.1 drops the notification.
        engine.feed(toast("text" to "early"))
        assertEquals(0, seen.size)
    }
}
