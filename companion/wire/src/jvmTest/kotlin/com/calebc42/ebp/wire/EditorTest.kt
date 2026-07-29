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
        .put("max_editor_bytes", 65_536)

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
        assertTrue(s.splice(ScalarPos(2), 1, "X", 5))     // hel -> heXlo
        assertEquals("heXlo", s.shadow)
        assertFalse(s.splice(ScalarPos(0), 10, "", -5))   // del past end
        assertFalse(s.splice(ScalarPos(0), 0, "z", 99))   // wrong len
        // Astral characters count as one scalar each.
        s.shadow = "a😀b" // a😀b : 3 scalars, 4 UTF-16 units
        assertEquals(3, s.scalarLength())
        assertTrue(s.splice(ScalarPos(2), 1, "", 2))       // delete b -> a😀
        assertEquals("a😀", s.shadow)
        assertTrue(s.splice(ScalarPos(1), 1, "!", 2))      // replace the emoji
        assertEquals("a!", s.shadow)
    }

    @Test
    fun diffReducesToMinimalScalarSplice() {
        // Pure prefix/suffix trimming: insertion, deletion, replacement, and
        // the astral-safe path a synchronized field relies on.
        assertEquals(Splice(ScalarPos(5), 0, "a"), EditorSession.diff("org: ", "org: a"))
        assertEquals(Splice(ScalarPos(3), 2, ""), EditorSession.diff("abcde", "abc"))
        assertEquals(Splice(ScalarPos(1), 3, "X"), EditorSession.diff("abcde", "aXe"))
        // No change: prefix consumes all, yielding an empty no-op splice at
        // the end (onValueChange's del>0||insert guard drops it before send).
        assertEquals(Splice(ScalarPos(4), 0, ""), EditorSession.diff("same", "same"))
        // An astral char is one scalar; a replacement around it counts whole.
        assertEquals(Splice(ScalarPos(1), 1, "!"), EditorSession.diff("a😀b", "a!b"))
        assertEquals(Splice(ScalarPos(0), 0, "😀"), EditorSession.diff("xy", "😀xy"))
        // The diff, applied to a shadow equal to `old`, yields `new` — the
        // invariant that keeps a live field and the Companion shadow in step.
        val s = EditorSession("d", "e", "sess"); s.shadow = "hello world"
        val (start, del, ins) = EditorSession.diff(s.shadow, "hey world")
        val len = s.scalarLength() - del + ins.codePointCount(0, ins.length)
        assertTrue(s.splice(start, del, ins, len))
        assertEquals("hey world", s.shadow)
    }

    @Test
    fun openEmitsSeedAndLocalEditMirrors() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abc", cursor = ScalarPos(3))
        val open = out.method("edit.open").single().getJSONObject("params")
        assertEquals("abc", open.getString("text"))
        assertEquals(0, open.getInt("seq"))
        assertEquals(3, open.getInt("cursor"))
        assertEquals(s.sessionId, open.getString("session"))
        // A local edit advances seq and mirrors an edit.delta.
        assertTrue(engine.localEditorEdit("doc:1", "body", ScalarPos(3), 0, "d"))
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
            .put("del", del).put("text", text).put("len", len)
            // The wire cursor is a SCALAR position (SPEC 19.1) — counting
            // text.length here would be the exact LD-4 UTF-16 mixup.
            .put("cursor", start + text.codePointCount(0, text.length)))))

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
        engine.localEditorEdit("doc:1", "body", ScalarPos(0), 0, "X") // seq -> 1
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
        engine.localEditorEdit("doc:1", "body", ScalarPos(5), 0, " world") // seq -> 1
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
        engine.localEditorEdit("doc:1", "body", ScalarPos(0), 0, "x") // seq -> 1
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
        assertFalse(engine.localEditorEdit("doc:1", "body", ScalarPos(0), 0, "x"))
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

    // ---------------------------------- §19.5 annotation validation (audit)

    @Test
    fun annotationBatchesAreRangeCheckedAndRejectedWhole() {
        // Audit §3.9 / SPEC 19.5+19.1: ranges MUST fit the synchronized text
        // and fontify runs MUST be sorted and non-overlapping. Unvalidated,
        // negative-length and out-of-range ranges reached host rendering,
        // where an off-by-one peer throws at layout instead of being refused.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "hello") // 5 scalars
        var delivered = 0
        engine.annotationListener = { _, _, _ -> delivered++ }
        fun diagnostics(vararg entries: JSONObject) =
            engine.feed(frame(JSONObject().put("jsonrpc", "2.0")
                .put("method", "diagnostics.show").put("params", JSONObject()
                    .put("editor_id", "body").put("session", s.sessionId)
                    .put("seq", 0).put("diagnostics", JSONArray(entries.toList())))))
        fun diag(start: Int, end: Int, sev: String = "error") = JSONObject()
            .put("start", start).put("end", end).put("severity", sev)
            .put("message", "m")
        // Out of range, negative length, and an unknown severity are refused.
        diagnostics(diag(0, 900))
        diagnostics(diag(4, 2))
        diagnostics(diag(-1, 3))
        diagnostics(diag(0, 3, "kaboom"))
        assertEquals(0, delivered)
        assertEquals(4, out.method("log.error").size)
        // A whole batch is refused when ANY entry is bad — never partially.
        diagnostics(diag(0, 2), diag(0, 900))
        assertEquals(0, delivered)
        // A conforming batch is delivered.
        diagnostics(diag(0, 2), diag(2, 5))
        assertEquals(1, delivered)
    }

    @Test
    fun fontifyRunsMustBeSortedAndNonOverlapping() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "hello")
        var delivered = 0
        engine.annotationListener = { _, _, _ -> delivered++ }
        fun runs(vararg entries: JSONObject) =
            engine.feed(frame(JSONObject().put("jsonrpc", "2.0")
                .put("method", "fontify.show").put("params", JSONObject()
                    .put("editor_id", "body").put("session", s.sessionId)
                    .put("seq", 0).put("runs", JSONArray(entries.toList())))))
        fun run(start: Int, end: Int) = JSONObject()
            .put("start", start).put("end", end).put("role", "keyword")
        runs(run(3, 5), run(0, 2))  // unsorted
        runs(run(0, 3), run(2, 5))  // overlapping
        assertEquals(0, delivered)
        runs(run(0, 2), run(2, 5))  // sorted, touching but not overlapping
        assertEquals(1, delivered)
    }

    // ------------------------------------- T2: peer caret + typed positions

    @Test
    fun textApplyRequiresCursor() {
        // SPEC 19.4 (LD-5): `cursor` is REQUIRED on every text-changing
        // apply; its absence is structural (-32602), and nothing changes.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abc")
        engine.feed(frame(request("a1", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 1).put("start", 3)
            .put("del", 0).put("text", "d").put("len", 4))))
        assertEquals(-32602, response(out, "a1").getJSONObject("error").getInt("code"))
        assertEquals("abc", s.shadow)
        assertEquals(0L, s.seq)
    }

    @Test
    fun textApplyValidatesPeerCaretAtomically() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abc")
        // An out-of-range peer cursor fails a gate: typed stale, text AND
        // caret untouched (the old path spliced first, then discarded the
        // failed setCaret and answered "applied").
        engine.feed(frame(request("a1", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 1).put("start", 3)
            .put("del", 0).put("text", "d").put("len", 4).put("cursor", 9))))
        assertEquals("stale", response(out, "a1").getJSONObject("result").getString("status"))
        assertEquals("abc", s.shadow)
        assertEquals(0L, s.seq)
        assertEquals(0, s.cursor)
        // An unpaired selection is structural: -32602, nothing changes.
        engine.feed(frame(request("a2", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 1).put("start", 3)
            .put("del", 0).put("text", "d").put("len", 4)
            .put("cursor", 4).put("sel_start", 0))))
        assertEquals(-32602, response(out, "a2").getJSONObject("error").getInt("code"))
        assertEquals("abc", s.shadow)
        // A valid apply adopts the peer's cursor AND selection together.
        engine.feed(frame(request("a3", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 1).put("start", 3)
            .put("del", 0).put("text", "d").put("len", 4)
            .put("cursor", 4).put("sel_start", 1).put("sel_end", 4))))
        assertEquals("applied", response(out, "a3").getJSONObject("result").getString("status"))
        assertEquals("abcd", s.shadow)
        assertEquals(4, s.cursor)
        assertEquals(1, s.selStart)
        assertEquals(4, s.selEnd)
    }

    @Test
    fun moveOnlyApplyRequiresSeqAndStalesOnMismatch() {
        // SPEC 19.4 (amendment #98): the move-only form carries `seq`
        // (REQUIRED in contract.json) and "succeeds only at the current
        // sequence". Unchecked, a caret computed against a superseded
        // document was reported `applied`.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abcde")
        engine.localEditorEdit("doc:1", "body", ScalarPos(0), 0, "X") // seq -> 1
        // Absent seq is structural.
        engine.feed(frame(request("m1", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("cursor", 2))))
        assertEquals(-32602, response(out, "m1").getJSONObject("error").getInt("code"))
        // A stale seq is a typed stale, and the caret does NOT move.
        engine.feed(frame(request("m2", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 0).put("cursor", 2))))
        assertEquals("stale", response(out, "m2").getJSONObject("result").getString("status"))
        assertEquals(1, response(out, "m2").getJSONObject("result").getInt("seq"))
        assertEquals(1, s.cursor) // still where the local edit left it
        // At the current sequence it applies.
        engine.feed(frame(request("m3", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 1).put("cursor", 2))))
        assertEquals("applied", response(out, "m3").getJSONObject("result").getString("status"))
        assertEquals(2, s.cursor)
        assertEquals("Xabcde", s.shadow) // move-only never changes text
    }

    @Test
    fun localEditFromASupersededBaseIsRefused() {
        // SPEC 19.3 (amendment #100): a view keeps its own copy of the text.
        // An inbound apply moves the shadow; a keystroke the view derived
        // from the OLD text is expressed in the old document's coordinates.
        // `len` is computed from the shadow, so the length equation cannot
        // catch it — only the base check stands between a racing keystroke
        // and silent corruption.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "hello")
        val viewText = s.shadow // what the view is showing
        applyText(engine, "a1", s.sessionId, 1, 0, 0, "XXX", 8)
        assertEquals("XXXhello", s.shadow) // shadow moved; view still "hello"
        // The view's keystroke, derived from "hello", is refused whole.
        assertFalse(engine.localEditorEdit("doc:1", "body",
            ScalarPos(5), 0, "!", base = viewText))
        assertEquals("XXXhello", s.shadow)
        assertEquals(1L, s.seq)
        assertTrue(out.method("edit.delta").isEmpty())
        // Derived from the CURRENT shadow, the same keystroke applies.
        assertTrue(engine.localEditorEdit("doc:1", "body",
            ScalarPos(8), 0, "!", base = s.shadow))
        assertEquals("XXXhello!", s.shadow)
    }

    @Test
    fun outOfDomainPositionsAreStaleNotTruncated() {
        // SPEC 4.2 allows integers to 2^53-1; SPEC 16.1 forbids coercing or
        // clamping an out-of-domain member. Reading these with Number.toInt()
        // took the low 32 bits, so start 4294967296 became 0 and a splice
        // Emacs asked for OUTSIDE the text was applied at the head of the
        // document and answered `applied`.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "hello")
        // 2^32 is a legal EBP integer; as an Int it truncates to exactly 0.
        engine.feed(frame(request("a2", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 1).put("start", 4_294_967_296L)
            .put("del", 0).put("text", "X").put("len", 6).put("cursor", 1))))
        assertEquals("stale", response(out, "a2").getJSONObject("result").getString("status"))
        assertEquals("hello", s.shadow)
        assertEquals(0L, s.seq)
    }

    @Test
    fun nearMaxIntSpliceDoesNotOverflowIntoACrash() {
        // start + del as Int WRAPS: 2147483647 + 1 is negative, which is not
        // > n, so the range guard passed and substring() got a negative index
        // — an uncaught exception that closed the whole transport over one
        // legal SPEC 4.2 integer.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "hello")
        engine.feed(frame(request("a1", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 1)
            .put("start", Int.MAX_VALUE).put("del", 1)
            .put("text", "x").put("len", 5).put("cursor", 0))))
        assertEquals("stale", response(out, "a1").getJSONObject("result").getString("status"))
        assertEquals("hello", s.shadow)
        assertEquals(SessionState.READY, engine.state) // transport survives
    }

    @Test
    fun mixedApplyFormIsInvalidParams() {
        // SPEC 19.4: move-only omits ALL of start/del/text/len; a message
        // with only some of them is neither form. The old dispatch keyed on
        // `start` alone, so {del: 2} silently became a move-only apply.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abc")
        engine.feed(frame(request("a1", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 1)
            .put("del", 2).put("cursor", 0))))
        assertEquals(-32602, response(out, "a1").getJSONObject("error").getInt("code"))
        assertEquals("abc", s.shadow)
    }

    @Test
    fun astralApplyCountsScalarsNotUtf16Units() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val s = engine.openEditor("doc:1", "body", "abc")
        // Inserting one astral scalar: len 4, peer cursor 4 — SCALARS.
        applyText(engine, "a1", s.sessionId, 1, 3, 0, "😀", 4)
        assertEquals("applied", response(out, "a1").getJSONObject("result").getString("status"))
        assertEquals("abc😀", s.shadow)
        assertEquals(4, s.cursor)
        // A UTF-16-counting peer says cursor 5 against the 4-scalar doc:
        // gate fails, typed stale, nothing changes — the wire catches the
        // miscounting endpoint instead of silently absorbing it.
        engine.feed(frame(request("a2", "edit.apply", JSONObject()
            .put("document", "doc:1").put("editor_id", "body")
            .put("session", s.sessionId).put("seq", 2).put("start", 4)
            .put("del", 0).put("text", "!").put("len", 5).put("cursor", 6))))
        assertEquals("stale", response(out, "a2").getJSONObject("result").getString("status"))
        assertEquals("abc😀", s.shadow)
    }

    @Test
    fun caretReportConvertsUtf16AndOrders() {
        // T2/LD-4: localEditorCaret takes Compose UTF-16 offsets; the wire
        // carries scalars, ordered, never splitting a surrogate pair.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.openEditor("doc:1", "body", "😀😀😀") // 3 scalars, 6 units
        // Backward drag: active end at unit 2 (inside scalar 1's span is
        // unit 3 — unit 2 is the boundary), anchor at unit 6.
        engine.localEditorCaret("doc:1", "body", Utf16Pos(2),
            Utf16Pos(6), Utf16Pos(2))
        val caret = out.method("edit.caret").single().getJSONObject("params")
        assertEquals(1, caret.getInt("cursor"))
        assertEquals(1, caret.getInt("sel_start"))
        assertEquals(3, caret.getInt("sel_end"))
    }

    // -------------------------------- max_editor_bytes (SPEC 19.4, #84, LD-15)

    @Test
    fun applyPastEditorBytesIsTooLargeAndChangesNothing() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        // JCS-serialized size = length + 2 quotes for plain ASCII.
        val seed = "a".repeat(65_500)
        val s = engine.openEditor("doc:1", "body", seed)
        // +100 would reach 65_602 > 65_536: 1201 editor-too-large, text and
        // seq untouched — not a stale, not an applied.
        applyText(engine, "a1", s.sessionId, 1, 0, 0, "b".repeat(100), 65_600)
        val err = response(out, "a1").getJSONObject("error")
        assertEquals(1201, err.getInt("code"))
        assertEquals("editor-too-large", err.getJSONObject("data").getString("reason"))
        assertEquals(seed, s.shadow)
        assertEquals(0L, s.seq)
        // The session is still healthy: a shrinking apply at seq 1 succeeds.
        applyText(engine, "a2", s.sessionId, 1, 0, 100, "", 65_400)
        assertEquals("applied", response(out, "a2").getJSONObject("result").getString("status"))
    }

    @Test
    fun localEditPastEditorBytesRefusedAsReadOnly() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.openEditor("doc:1", "body", "a".repeat(65_500))
        // SPEC 19.4 (amendment #84): refused as if read-only — no splice, no
        // edit.delta on the wire.
        assertFalse(engine.localEditorEdit("doc:1", "body", ScalarPos(0), 0, "b".repeat(100)))
        assertTrue(out.method("edit.delta").isEmpty())
        // A non-growing local edit still works.
        assertTrue(engine.localEditorEdit("doc:1", "body", ScalarPos(0), 100, ""))
    }

    @Test
    fun anOverLimitSeedIsRefusedAtAcceptance() {
        // SPEC 19.4 (amendment #103): the seed carries max_editor_bytes as a
        // receiver duty. Accepted, it produced an editor that was silently
        // and permanently read-only — edit.open carried the over-limit text
        // and then every edit was refused by the size rules.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 1)
            .put("spec", JSONObject().put("t", "editor").put("id", "body")
                .put("document", "doc:1").put("value", "a".repeat(70_000))))))
        val err = response(out, "s1").getJSONObject("error")
        assertEquals(1201, err.getInt("code"))
        assertEquals("editor-too-large", err.getJSONObject("data").getString("reason"))
        assertTrue(out.method("edit.open").isEmpty())
        // A seed within the limit is accepted and opens normally.
        engine.feed(frame(request("s2", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 2)
            .put("spec", JSONObject().put("t", "editor").put("id", "body")
                .put("document", "doc:1").put("value", "a".repeat(100))))))
        assertEquals("applied", response(out, "s2").getJSONObject("result").getString("status"))
        assertEquals(1, out.method("edit.open").size)
    }

    @Test
    fun advertisingEditorSyncRequiresMaxEditorBytes() {
        // SPEC 4.5 (amendment #84): max_editor_bytes is REQUIRED when
        // editor.sync is advertised — a host that omits it must not construct.
        val bare = JSONObject()
            .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
            .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
            .put("max_surfaces", 16).put("max_surface_ids", 1024)
            .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
            .put("max_capture_fields", 64).put("max_editor_sessions", 8)
        val failed = runCatching {
            CompanionEngine(CompanionConfig(
                serverName = "kat", serverVersion = "1",
                pairings = mapOf(katPid to katToken),
                supportedCapabilities = setOf("editor.sync"),
                surfaceProfiles = JSONObject(),
                limits = bare, nonceSource = { katSn })) { }
        }.isFailure
        assertTrue(failed)
    }
}
