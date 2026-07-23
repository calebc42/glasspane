// SPDX-License-Identifier: GPL-3.0-or-later
// W9 conformance: SPEC 14.2 Companion-local builtins. view.switch switches
// the multi-view surface locally and (while READY) reports view.switched with
// when_offline-drop semantics; an unknown view or single-view surface is a
// safe no-op; trigger.fire routes to the manual-trigger pipeline; the host
// builtins (clipboard/share/settings) reach the host listener.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BuiltinTest {

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
                .put("node_types", JSONArray(listOf("text", "button")))
                .put("builtins", JSONArray(listOf(
                    "view.switch", "companion.settings.open", "clipboard.copy")))
                .put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, emptyList()))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        assertEquals(SessionState.READY, engine.state)
        return engine
    }

    private fun multiViewSpec() = JSONObject()
        .put("initial_view", "main")
        .put("views", JSONObject()
            .put("main", JSONObject().put("t", "text").put("text", "m"))
            .put("detail", JSONObject().put("t", "text").put("text", "d")))

    @Test
    fun viewSwitchSwitchesLocallyAndReportsWhileReady() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 1)
            .put("spec", multiViewSpec()))))
        // Attach AFTER the update (which notifies the listener itself).
        val changed = mutableListOf<String>()
        engine.surfaceListener = { changed.add(it) }
        // The builtin switches the local view and notifies the host.
        engine.dispatchAction("app:main",
            JSONObject().put("builtin", "view.switch").put("view", "detail"), null)
        assertEquals(listOf("app:main"), changed)
        // SPEC 14.2: while READY, view.switched reports with args.view.
        val event = out.last { it.opt("method") == "event.action" }
            .getJSONObject("params")
        assertEquals("view.switched", event.getString("action"))
        assertEquals("app:main", event.getString("surface"))
        assertEquals("detail", event.getJSONObject("args").getString("view"))
        assertTrue(EbpAuth.isValidNonce(event.getString("event_id")))
    }

    @Test
    fun viewSwitchInvalidContextIsANoOp() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        // A single-view surface: view.switch is invalid context — no-op.
        engine.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 1)
            .put("spec", JSONObject().put("t", "text").put("text", "solo")))))
        val changed = mutableListOf<String>()
        engine.surfaceListener = { changed.add(it) }
        val before = out.size
        engine.dispatchAction("app:main",
            JSONObject().put("builtin", "view.switch").put("view", "detail"), null)
        assertTrue(changed.isEmpty())
        assertEquals(before, out.size)
        // A multi-view surface but an unknown view: also a no-op.
        engine.feed(frame(request("s2", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 2)
            .put("spec", multiViewSpec()))))
        changed.clear() // the update itself notified the listener
        val before2 = out.size
        engine.dispatchAction("app:main",
            JSONObject().put("builtin", "view.switch").put("view", "nope"), null)
        assertTrue(changed.isEmpty())
        assertEquals(before2, out.size)
    }

    @Test
    fun hostBuiltinsReachTheHostListener() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 1)
            .put("spec", JSONObject().put("t", "text").put("text", "x")))))
        val seen = mutableListOf<Pair<String, String>>()
        engine.hostBuiltinListener = { name, d ->
            seen.add(name to d.optString("text"))
        }
        engine.dispatchAction("app:main",
            JSONObject().put("builtin", "clipboard.copy").put("text", "hello"), null)
        engine.dispatchAction("app:main",
            JSONObject().put("builtin", "companion.settings.open"), null)
        assertEquals(listOf("clipboard.copy" to "hello",
            "companion.settings.open" to ""), seen)
        // Builtins never create event.action frames of their own.
        assertTrue(out.none { it.opt("method") == "event.action" })
    }
}
