// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: editor session lifecycle (SPEC 19) — sessions open from
// synchronized editor nodes in a pushed surface, preserve across refreshes,
// close on removal/document-change/tombstone, wait for READY when accepted
// during SYNCING, respect max_editor_sessions, and edit.complete round-trips.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorLifecycleTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits(maxEditors: Long = 8) = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64).put("max_editor_sessions", maxEditors)
        .put("max_editor_bytes", 65_536)

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    private fun engine(out: MutableList<JSONObject>, maxEditors: Long = 8,
                       toReady: Boolean = true): CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("editor.sync"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text", "column", "editor")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(maxEditors), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("editor.sync")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        if (toReady) engine.feed(frame(request("r1", "session.ready", JSONObject())))
        return engine
    }

    private fun editorNode(id: String, document: String, value: String = "") =
        JSONObject().put("t", "editor").put("id", id).put("document", document)
            .put("publish_state", false)
            .also { if (value.isNotEmpty()) it.put("value", value) }

    private fun push(engine: CompanionEngine, out: MutableList<JSONObject>,
                     surface: String, revision: Long, spec: JSONObject): JSONObject {
        val rid = "s$revision-${surface.hashCode()}"
        engine.feed(frame(request(rid, "surface.update", JSONObject()
            .put("surface", surface).put("revision", revision).put("spec", spec))))
        return out.last { it.opt("id") == rid }
    }

    private fun List<JSONObject>.method(m: String) = filter { it.opt("method") == m }

    @Test
    fun editorNodeOpensAndSurviveRefreshThenCloses() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        // A surface with a synchronized editor opens one session (edit.open).
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "hello"))
        val open = out.method("edit.open").single().getJSONObject("params")
        assertEquals("hello", open.getString("text"))
        assertEquals("doc:1", open.getString("document"))
        val session = open.getString("session")
        // A refresh with the same document+editor_id preserves the session
        // (no second edit.open, no edit.close).
        push(engine, out, "app:main", 2, editorNode("body", "doc:1", "ignored seed"))
        assertEquals(1, out.method("edit.open").size)
        assertEquals(0, out.method("edit.close").size)
        // Removing the editor node from the surface closes it.
        push(engine, out, "app:main", 3, JSONObject().put("t", "text").put("text", "gone"))
        val close = out.method("edit.close").single().getJSONObject("params")
        assertEquals(session, close.getString("session"))
    }

    @Test
    fun documentChangeReopens() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "a"))
        val first = out.method("edit.open").single().getJSONObject("params").getString("session")
        // Same editor_id, different document: close the old, open the new.
        push(engine, out, "app:main", 2, editorNode("body", "doc:2", "b"))
        assertEquals(1, out.method("edit.close").size)
        assertEquals(2, out.method("edit.open").size)
        val second = out.method("edit.open").last().getJSONObject("params")
        assertEquals("doc:2", second.getString("document"))
        assertTrue(second.getString("session") != first)
    }

    @Test
    fun acceptedDuringSyncingOpensOnReady() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, toReady = false) // SYNCING
        // The editor node is accepted, but no edit.open yet (not READY).
        engine.feed(frame(request("q0", "queue.replay", JSONObject())))
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "seed"))
        assertEquals(0, out.method("edit.open").size)
        // session.ready opens it.
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        assertEquals("seed", out.method("edit.open").single()
            .getJSONObject("params").getString("text"))
    }

    @Test
    fun maxEditorSessionsRejectsBeforeApplying() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, maxEditors = 1)
        push(engine, out, "app:a", 1, editorNode("body", "doc:1"))
        // A second surface with another editor exceeds the limit: rejected.
        val r = push(engine, out, "app:b", 1, editorNode("body2", "doc:2"))
        assertEquals("editor-session-limit", r.getJSONObject("error")
            .getJSONObject("data").getString("reason"))
        // The first surface's editor is untouched; a same-surface refresh at
        // the limit (still one editor) stays legal.
        assertEquals("applied", push(engine, out, "app:a", 2,
            editorNode("body", "doc:1")).getJSONObject("result").getString("status"))
    }

    @Test
    fun completionRoundTripReplacesPrefix() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "pri", cursor = ScalarPos(3))
        var got: Pair<String, JSONArray>? = null
        engine.requestCompletion("doc:1", "body") { prefix, cands -> got = prefix to cands }
        // The Companion sent edit.complete as a request; answer it.
        val req = out.method("edit.complete").single()
        engine.feed(encodeFrame(JSONObject().put("jsonrpc", "2.0")
            .put("id", req.getInt("id"))
            .put("result", JSONObject().put("prefix", "pri")
                .put("candidates", JSONArray().put(JSONObject()
                    .put("label", "print").put("insert", "print()")))).toString()))
        assertEquals("pri", got!!.first)
        // Selecting the candidate replaces the prefix with insert as one edit.
        assertTrue(engine.selectCompletion("doc:1", "body", s.sessionId, s.seq,
            s.cursor, "pri", "print()"))
        assertEquals("print()", s.shadow)
        assertEquals(1, s.seq) // one advancing edit.delta
        // A stale selection (cursor moved) is discarded without changing text.
        assertFalse(engine.selectCompletion("doc:1", "body", s.sessionId, 99,
            0, "x", "y"))
    }
}
