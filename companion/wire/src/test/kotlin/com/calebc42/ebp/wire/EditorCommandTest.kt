// SPDX-License-Identifier: GPL-3.0-or-later
// W9-i SPEC 17.7 `command`: a toolbar command op on a synchronized editor emits
// a NON-durable edit.command event.action carrying the full editor context
// (command/document/editor_id/session/seq/cursor/sel_start/sel_end). It is
// valid only for an OPEN session in READY; otherwise it is a silent no-op and
// never queues.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorCommandTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits() = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64).put("max_editor_bytes", 65_536)

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    private fun readyEngine(out: MutableList<JSONObject>): CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("editor.sync"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text", "editor")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("editor.sync")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        assertEquals(SessionState.READY, engine.state)
        return engine
    }

    @Test
    fun commandEmitsEditCommandWithFullContext() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 7)
            .put("spec", JSONObject().put("t", "text").put("text", "x")))))
        engine.openEditor("doc.org", "ed1", "hello world", cursor = 3)
        val ok = engine.editorCommand("app:main", "doc.org", "ed1",
            "org-todo", cursor = 5, selStart = 2, selEnd = 5)
        assertTrue(ok)
        val ev = out.last { it.opt("method") == "event.action" }.getJSONObject("params")
        assertEquals("edit.command", ev.getString("action"))
        assertEquals("app:main", ev.getString("surface"))
        assertEquals(7L, ev.getLong("revision_seen"))
        assertTrue(EbpAuth.isValidNonce(ev.getString("event_id")))
        val args = ev.getJSONObject("args")
        assertEquals("org-todo", args.getString("command"))
        assertEquals("doc.org", args.getString("document"))
        assertEquals("ed1", args.getString("editor_id"))
        assertEquals(5, args.getInt("cursor"))
        assertEquals(2, args.getInt("sel_start"))
        assertEquals(5, args.getInt("sel_end"))
        // The session + seq come from the live EditorSession.
        assertTrue(args.getString("session").isNotEmpty())
        assertTrue(args.has("seq"))
    }

    @Test
    fun commandOnUnknownEditorIsANoOp() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 1)
            .put("spec", JSONObject().put("t", "text").put("text", "x")))))
        val before = out.size
        val ok = engine.editorCommand("app:main", "nope.org", "ed9",
            "org-todo", 0, 0, 0)
        assertFalse(ok)
        assertEquals(before, out.size) // nothing emitted, nothing queued
    }
}
