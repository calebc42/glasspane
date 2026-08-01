// SPDX-License-Identifier: GPL-3.0-or-later
// W9-i SPEC 17.7 `command`: a toolbar command op on a synchronized editor emits
// a NON-durable edit.command event.action carrying the full editor context
// (command/document/editor_id/session/seq/cursor/sel_start/sel_end). It is
// valid only for an OPEN session in READY; otherwise it is a silent no-op and
// never queues.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorCommandTest {

    private fun readyEngine(out: MutableList<JsonObject>): CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("editor.sync"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(listOf("text", "editor").map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_editor_bytes" to 65_536),
            nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("editor.sync")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        assertEquals(SessionState.READY, engine.state)
        return engine
    }

    @Test
    fun commandEmitsEditCommandWithFullContext() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 7)
            putJsonObject("spec") { put("t", "text"); put("text", "x") }
        })))
        engine.openEditor("doc.org", "ed1", "hello world", cursor = ScalarPos(3))
        val ok = engine.editorCommand("app:main", "doc.org", "ed1",
            "org-todo", cursor = Utf16Pos(5), selStart = Utf16Pos(2), selEnd = Utf16Pos(5))
        assertTrue(ok)
        val ev = out.last { it.stringOrNull("method") == "event.action" }.reqObj("params")
        assertEquals("edit.command", ev.reqString("action"))
        assertEquals("app:main", ev.reqString("surface"))
        assertEquals(7L, ev.reqLong("revision_seen"))
        assertTrue(EbpAuth.isValidNonce(ev.reqString("event_id")))
        val args = ev.reqObj("args")
        assertEquals("org-todo", args.reqString("command"))
        assertEquals("doc.org", args.reqString("document"))
        assertEquals("ed1", args.reqString("editor_id"))
        assertEquals(5L, args.reqLong("cursor"))
        assertEquals(2L, args.reqLong("sel_start"))
        assertEquals(5L, args.reqLong("sel_end"))
        // The session + seq come from the live EditorSession.
        assertTrue(args.reqString("session").isNotEmpty())
        assertTrue("seq" in args)
    }

    @Test
    fun astralCommandConvertsUtf16ToScalars() {
        // LD-4: ten emoji with the caret at the end used to go on the wire
        // as cursor 20 against a 10-scalar document, and a backward drag as
        // sel_start > sel_end — two MUST violations on one line
        // (SPEC.md 2590: convert before sending; 2640: ordering).
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 1)
            putJsonObject("spec") { put("t", "text"); put("text", "x") }
        })))
        engine.openEditor("doc.org", "ed1", "😀".repeat(10)) // 10 scalars, 20 units
        // Caret at the very end, whole document selected backward.
        assertTrue(engine.editorCommand("app:main", "doc.org", "ed1",
            "org-todo", Utf16Pos(20), Utf16Pos(20), Utf16Pos(0)))
        val a1 = out.last { it.stringOrNull("method") == "event.action" }
            .reqObj("params").reqObj("args")
        assertEquals(10L, a1.reqLong("cursor"))
        assertEquals(0L, a1.reqLong("sel_start"))
        assertEquals(10L, a1.reqLong("sel_end"))
        // A caret landing INSIDE an astral pair (unit 3) backs off to the
        // character's own position — a splice boundary is never mid-scalar.
        assertTrue(engine.editorCommand("app:main", "doc.org", "ed1",
            "org-todo", Utf16Pos(3), Utf16Pos(3), Utf16Pos(3)))
        val a2 = out.last { it.stringOrNull("method") == "event.action" }
            .reqObj("params").reqObj("args")
        assertEquals(1L, a2.reqLong("cursor"))
        assertEquals(1L, a2.reqLong("sel_start"))
        assertEquals(1L, a2.reqLong("sel_end"))
    }

    @Test
    fun commandOnUnknownEditorIsANoOp() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 1)
            putJsonObject("spec") { put("t", "text"); put("text", "x") }
        })))
        val before = out.size
        val ok = engine.editorCommand("app:main", "nope.org", "ed9",
            "org-todo", Utf16Pos(0), Utf16Pos(0), Utf16Pos(0))
        assertFalse(ok)
        assertEquals(before, out.size) // nothing emitted, nothing queued
    }
}
