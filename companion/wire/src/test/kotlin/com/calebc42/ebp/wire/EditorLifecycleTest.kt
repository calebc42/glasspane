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
            supportedCapabilities = setOf("editor.sync", "surfaces.dialog"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text", "column", "editor")))
                .put("builtins", JSONArray()).put("features", JSONArray()))
                .put("dialog", JSONObject()
                    .put("node_types", JSONArray(listOf("text", "column", "editor")))
                    .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(maxEditors), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn,
                listOf("editor.sync", "surfaces.dialog")))))
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

    // ------------------------------- audit §3: lifecycle conformance (P1 1-5)

    @Test
    fun anEditorInsideActionArgsOpensNothing() {
        // Audit §3.1: the scan walked EVERY JSON object in a spec, so an
        // editor-shaped object inside an action's free-form `args` (§14.1
        // leaves args opaque) opened a real session for a node that does not
        // exist — burning a max_editor_sessions slot for the connection, and
        // able to shadow a real editor's identity via member order.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val node = JSONObject().put("t", "text").put("text", "go")
            .put("on_tap", JSONObject().put("action", "demo.go")
                .put("args", JSONObject().put("t", "editor")
                    .put("id", "ghost").put("document", "doc:ghost")))
        push(engine, out, "app:main", 1, node)
        assertTrue(out.method("edit.open").isEmpty())
    }

    @Test
    fun aReconnectOverCachedSurfacesOpensSessions() {
        // Audit §3.2: sessions only ever opened from surface.update, so a
        // reconnect that receives none — legal, the cached snapshot is
        // unchanged and still rendered per §13.5 — opened NOTHING and left
        // every rendered editor permanently read-only with no diagnostic.
        val out = mutableListOf<JSONObject>()
        val store = SurfaceStore(16, 1024)
        fun connect(): CompanionEngine {
            val e = CompanionEngine(CompanionConfig(
                serverName = "kat", serverVersion = "1",
                pairings = mapOf(katPid to katToken),
                supportedCapabilities = setOf("editor.sync", "surfaces.dialog"),
                surfaceProfiles = JSONObject().put("app", JSONObject()
                    .put("node_types", JSONArray(listOf("text", "column", "editor")))
                    .put("builtins", JSONArray()).put("features", JSONArray())),
                limits = limits(), nonceSource = { katSn }), store) { bytes ->
                FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
            }
            e.feed(frame(request("h1", "session.hello",
                EbpAuth.helloParams("t", "1", katPid, katCn,
                listOf("editor.sync", "surfaces.dialog")))))
            e.feed(frame(request("h2", "auth.response",
                EbpAuth.authParams(katPid, katCn, katSn, katToken))))
            return e
        }
        val first = connect()
        first.feed(frame(request("r1", "session.ready", JSONObject())))
        push(first, out, "app:main", 1, editorNode("body", "doc:1", "hello"))
        assertEquals(1, out.method("edit.open").size)
        first.close("transport closed")
        // Second connection: no surface.update at all, just session.ready.
        out.clear()
        val second = connect()
        second.feed(frame(request("r1", "session.ready", JSONObject())))
        val reopened = out.method("edit.open").single().getJSONObject("params")
        assertEquals("doc:1", reopened.getString("document"))
        assertEquals("hello", reopened.getString("text"))
        // ...and it is a live session, not a bare notification.
        assertTrue(second.localEditorEdit("doc:1", "body", ScalarPos(5), 0, "!"))
    }

    @Test
    fun aSecondSurfaceClaimingTheSameEditorIsRefused() {
        // Audit §3.3 (amendment #104): the second claim silently overwrote
        // the first surface's session with NO edit.close — Emacs then got
        // editor-stale for a session it was never told died, edit.resync
        // could not recover it, and removing either surface closed the
        // survivor.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        push(engine, out, "app:a", 1, editorNode("body", "doc:1", "A"))
        val session = out.method("edit.open").single()
            .getJSONObject("params").getString("session")
        val refused = push(engine, out, "app:b", 1, editorNode("body", "doc:1", "B"))
        assertEquals("editor-duplicate",
            refused.getJSONObject("error").getJSONObject("data").getString("reason"))
        // The original session is untouched: still one open, none closed.
        assertEquals(1, out.method("edit.open").size)
        assertTrue(out.method("edit.close").isEmpty())
        assertEquals(session, out.method("edit.open").single()
            .getJSONObject("params").getString("session"))
    }

    @Test
    fun anEditorRemovedDuringSyncingNeverOpens() {
        // Audit §3.4 (LD-6): pendingEditors was appended to but never pruned,
        // so an editor accepted during SYNCING and then removed still opened
        // on READY — a session no close path could reach, invisible to the
        // max_editor_sessions count.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, toReady = false)
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "seed"))
        assertTrue(out.method("edit.open").isEmpty()) // waits for READY
        engine.feed(frame(request("x1", "surface.remove", JSONObject()
            .put("surface", "app:main").put("revision", 2))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        assertTrue(out.method("edit.open").isEmpty())
    }

    @Test
    fun aDialogEditorIsCountedOpenedAndClosedWithTheDialog() {
        // Audit §3.8: §19 counts identities across "accepted surface OR
        // DIALOG documents", but handleDialogShow had no count, no limit
        // check, and never opened sessions — so a dialog's editor rendered
        // as synchronized and was never synchronized, and the limit could
        // never fire from a dialog at all.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, maxEditors = 1)
        engine.feed(frame(request("d1", "dialog.show", JSONObject()
            .put("dialog_id", "dlg").put("spec", editorNode("body", "doc:2", "hi")))))
        // The dialog's editor got a real session.
        val open = out.method("edit.open").single().getJSONObject("params")
        assertEquals("doc:2", open.getString("document"))
        // It counts: a surface editor now exceeds max_editor_sessions of 1.
        val refused = push(engine, out, "app:main", 1, editorNode("other", "doc:3"))
        assertEquals("editor-session-limit",
            refused.getJSONObject("error").getJSONObject("data").getString("reason"))
        // Completing the dialog closes its session and frees the slot.
        engine.completeDialogDismiss("dlg")
        assertEquals(1, out.method("edit.close").size)
        val accepted = push(engine, out, "app:main", 2, editorNode("other", "doc:3"))
        assertEquals("applied", accepted.getJSONObject("result").getString("status"))
    }

    @Test
    fun aSynchronizedEditorNeverBecomesADraft() {
        // Audit §3.7 / SPEC 13.6: "a local editor draft requires
        // publish_state: true and no document ... A synchronized editor never
        // participates in draft reconciliation." Registering it as stateful
        // let publishState write a DURABLE draft — the offline draft §19
        // forbids, reportable in the next welcome's input_state.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        push(engine, out, "app:main", 1, editorNode("body", "doc:1", "seed")
            .put("publish_state", true))
        engine.publishState("app:main", "body", "typed offline")
        assertFalse(engine.surfaces.hasDraft("app:main", "body"))
        // A LOCAL editor (publish_state, no document) still drafts normally.
        push(engine, out, "app:local", 1, JSONObject().put("t", "editor")
            .put("id", "note").put("publish_state", true))
        engine.publishState("app:local", "note", "kept")
        assertTrue(engine.surfaces.hasDraft("app:local", "note"))
    }

    @Test
    fun aPresentationKeyChangeClosesAndReopens() {
        // Audit §3.5: §16.1 makes `key` the presentation identity when
        // present and §19 closes the session when identity changes, but the
        // scan keyed on `id` alone — so a key change neither closed the old
        // session nor opened a new one, leaving a live shadow on text the
        // renderer had already replaced.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        push(engine, out, "app:main", 1,
            editorNode("body", "doc:1", "A").put("key", "k1"))
        assertEquals(1, out.method("edit.open").size)
        push(engine, out, "app:main", 2,
            editorNode("body", "doc:1", "B").put("key", "k2"))
        assertEquals(1, out.method("edit.close").size)
        assertEquals(2, out.method("edit.open").size)
        assertEquals("B", out.method("edit.open").last()
            .getJSONObject("params").getString("text"))
    }
}
