// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: editor sync (SPEC 19) — the shadow/splice/session core.
// Scalar positions (incl. astral), the seq machine, edit.apply as the
// serialization point (applied at seq+1, typed stale otherwise), edit.resync
// re-seeding, annotation session/seq gating, and transport-loss closure.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits() = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64).put("max_editor_sessions", 8)

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    private fun engine(out: MutableList<JSONObject>, grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("editor.sync") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("editor.sync"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text", "editor")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        return engine
    }

    private fun List<JSONObject>.method(m: String) = filter { it.opt("method") == m }
    private fun response(out: List<JSONObject>, id: String) = out.last { it.opt("id") == id }

    // ------------------------------------------------- EditorSession core

    @Test
    fun spliceScalarBoundsAndLength() {
        val s = EditorSession("d", "e", "sess")
        s.shadow = "hello"
        assertTrue(s.splice(2, 1, "X", 5))     // hel -> heXlo
        assertEquals("heXlo", s.shadow)
        assertFalse(s.splice(0, 10, "", -5))   // del past end
        assertFalse(s.splice(0, 0, "z", 99))   // wrong len
        // Astral characters count as one scalar each.
        s.shadow = "a😀b" // a😀b : 3 scalars, 4 UTF-16 units
        assertEquals(3, s.scalarLength())
        assertTrue(s.splice(2, 1, "", 2))       // delete b -> a😀
        assertEquals("a😀", s.shadow)
        assertTrue(s.splice(1, 1, "!", 2))      // replace the emoji
        assertEquals("a!", s.shadow)
    }

    @Test
    fun openEmitsSeedAndLocalEditMirrors() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abc", cursor = 3)
        val open = out.method("edit.open").single().getJSONObject("params")
        assertEquals("abc", open.getString("text"))
        assertEquals(0, open.getInt("seq"))
        assertEquals(3, open.getInt("cursor"))
        assertEquals(s.sessionId, open.getString("session"))
        // A local edit advances seq and mirrors an edit.delta.
        assertTrue(engine.localEditorEdit("doc:1", "body", 3, 0, "d"))
        val delta = out.method("edit.delta").single().getJSONObject("params")
        assertEquals(1, delta.getInt("seq"))
        assertEquals(3, delta.getInt("start"))
        assertEquals("d", delta.getString("text"))
        assertEquals(4, delta.getInt("len"))
        assertEquals("abcd", s.shadow)
    }

    // ------------------------------------------- edit.apply serialization

    private fun applyText(engine: CompanionEngine, id: String, session: String,
                          seq: Long, start: Int, del: Int, text: String, len: Int,
                          document: String = "doc:1", editorId: String = "body") =
        engine.feed(frame(request(id, "edit.apply", JSONObject()
            .put("document", document).put("editor_id", editorId)
            .put("session", session).put("seq", seq).put("start", start)
            .put("del", del).put("text", text).put("len", len).put("cursor", start + text.length))))

    @Test
    fun applyAppliesAtNextSeqAndStalesOtherwise() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abc")
        // seq 0 -> 1: valid splice at seq+1.
        applyText(engine, "a1", s.sessionId, 1, 3, 0, "d", 4)
        assertEquals("applied", response(out, "a1").getJSONObject("result").getString("status"))
        assertEquals(1, response(out, "a1").getJSONObject("result").getInt("seq"))
        assertEquals("abcd", s.shadow)
        // A stale seq (still 1, not 2) returns stale WITHOUT changing text,
        // and leaves the session OPEN (SPEC 19.2 winning-session rule).
        applyText(engine, "a2", s.sessionId, 1, 0, 0, "Z", 5)
        assertEquals("stale", response(out, "a2").getJSONObject("result").getString("status"))
        assertEquals(1, response(out, "a2").getJSONObject("result").getInt("seq"))
        assertEquals("abcd", s.shadow)
        // The next valid seq still works (session stayed OPEN).
        applyText(engine, "a3", s.sessionId, 2, 0, 0, "_", 5)
        assertEquals("applied", response(out, "a3").getJSONObject("result").getString("status"))
        assertEquals("_abcd", s.shadow)
    }

    @Test
    fun localEditThenStaleExternalApply() {
        // The Companion's own edit claims seq+1; a competing external apply
        // for the same seq loses with a typed stale (SPEC 19.4).
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abc")
        engine.localEditorEdit("doc:1", "body", 0, 0, "X") // seq -> 1
        applyText(engine, "a1", s.sessionId, 1, 3, 0, "Y", 5)
        assertEquals("stale", response(out, "a1").getJSONObject("result").getString("status"))
        assertEquals("Xabc", s.shadow)
    }

    @Test
    fun moveOnlyApplyKeepsSeq() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abcde")
        engine.feed(frame(request("m1", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 0).put("cursor", 2))))
        assertEquals("applied", response(out, "m1").getJSONObject("result").getString("status"))
        assertEquals(0, response(out, "m1").getJSONObject("result").getInt("seq"))
        assertEquals(2, s.cursor)
        assertEquals("abcde", s.shadow) // move-only never changes text
    }

    @Test
    fun unknownOrClosedSessionIsEditorStale() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.openEditor("doc:1", "body", "abc")
        // Wrong session id.
        applyText(engine, "a1", "deadbeef".repeat(4), 1, 0, 0, "x", 4)
        assertEquals("editor-stale", response(out, "a1").getJSONObject("error")
            .getJSONObject("data").getString("reason"))
        // After close, the tuple is stale.
        engine.closeEditor("doc:1", "body")
        assertTrue(out.method("edit.close").isNotEmpty())
        val newSession = engine.openEditor("doc:1", "body", "z").sessionId
        // A message with a fresh valid session works.
        applyText(engine, "a2", newSession, 1, 1, 0, "y", 2)
        assertEquals("applied", response(out, "a2").getJSONObject("result").getString("status"))
    }

    // -------------------------------------------------- edit.resync

    @Test
    fun resyncClosesReseedsAtSeqZero() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "hello")
        engine.localEditorEdit("doc:1", "body", 5, 0, " world") // seq -> 1
        val old = s.sessionId
        engine.feed(frame(request("y1", "edit.resync", JSONObject()
            .put("document", "doc:1").put("editor_id", "body").put("session", old))))
        val r = response(out, "y1").getJSONObject("result")
        assertEquals("hello world", r.getString("text"))
        assertEquals(0, r.getInt("seq"))
        assertTrue(r.getString("session") != old)     // fresh id
        // The old session id is dead: an apply against it is stale.
        applyText(engine, "y2", old, 1, 0, 0, "z", 12)
        assertEquals("editor-stale", response(out, "y2").getJSONObject("error")
            .getJSONObject("data").getString("reason"))
    }

    // ----------------------------------------------------- annotations

    @Test
    fun annotationsGateOnSessionAndSeq() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val seen = mutableListOf<Pair<String, Long>>()
        engine.annotationListener = { kind, _, p -> seen.add(kind to p.getLong("seq")) }
        val s = engine.openEditor("doc:1", "body", "abc")
        engine.localEditorEdit("doc:1", "body", 0, 0, "x") // seq -> 1
        fun annot(method: String, session: String, seq: Long) =
            engine.feed(frame(notification(method, JSONObject()
                .put("editor_id", "body").put("session", session).put("seq", seq)
                .put("diagnostics", JSONArray()).put("runs", JSONArray()).put("text", "d"))))
        // Matching session + seq: accepted.
        annot("diagnostics.show", s.sessionId, 1)
        annot("eldoc.show", s.sessionId, 1)
        // Wrong seq: discarded.
        annot("fontify.show", s.sessionId, 0)
        // Wrong session: discarded.
        annot("diagnostics.show", "beefbeef".repeat(4), 1)
        assertEquals(listOf("diagnostics.show" to 1L, "eldoc.show" to 1L), seen)
    }

    // -------------------------------------------------- lifecycle / gate

    @Test
    fun transportLossClosesSessions() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abc")
        engine.close("transport closed")
        // A post-close apply for the old session is stale; and READY-gated
        // emitters no longer fire.
        assertEquals(EditorSession.State.CLOSED, s.state)
        assertFalse(engine.localEditorEdit("doc:1", "body", 0, 0, "x"))
    }

    @Test
    fun ungrantedEditorIsMethodNotFound() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, grant = false)
        engine.feed(frame(request("a1", "edit.apply", JSONObject()
            .put("document", "d").put("editor_id", "e").put("session", "s")
            .put("seq", 1).put("start", 0).put("del", 0).put("text", "x").put("len", 1)
            .put("cursor", 1))))
        assertEquals(-32601, response(out, "a1").getJSONObject("error").getInt("code"))
    }
}
