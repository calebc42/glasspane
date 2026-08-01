// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: the dialog module (SPEC 18.1). dialog.show is held as a
// deferred request; dialog.submit/dialog.dismiss builtins and rpc.cancel
// complete it; duplicate ids are 1201, over-limit is 1401, transport loss
// dismisses every outstanding dialog.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DialogTest {

    private fun readyEngine(out: MutableList<JsonObject>,
                            presented: MutableList<Pair<String, JsonObject?>>)
            : CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("surfaces.dialog"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types",
                        JsonArray(listOf("text", "column", "button").map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
                putJsonObject("dialog") {
                    put("node_types", JsonArray(listOf("text", "column",
                        "button", "text_input", "checkbox", "switch").map(::JsonPrimitive)))
                    put("builtins",
                        JsonArray(listOf("dialog.submit", "dialog.dismiss").map(::JsonPrimitive)))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_dialogs" to 2), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.dialogListener = { id, spec -> presented.add(id to spec) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("surfaces.dialog")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        assertEquals(SessionState.READY, engine.state)
        return engine
    }

    private fun dialogSpec() = buildJsonObject {
        put("t", "column")
        putJsonArray("children") { addJsonObject { put("t", "text_input"); put("id", "name") } }
    }

    private fun show(engine: CompanionEngine, reqId: String, dialogId: String) =
        engine.feed(frame(request(reqId, "dialog.show", buildJsonObject {
            put("dialog_id", dialogId); put("spec", dialogSpec()) })))

    private fun responseFor(out: List<JsonObject>, reqId: String) =
        out.lastOrNull { it["id"] == JsonPrimitive(reqId) }

    @Test
    fun dialogDefaultsCarryEachStatefulNodesLogicalValue() {
        // T3/LD-3: the engine computes these while validating the spec and
        // used to discard them, leaving capture_fields with nothing to fall
        // back to for a field the user never touched.
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = readyEngine(out, presented)
        val spec = buildJsonObject {
            put("t", "column")
            putJsonArray("children") {
                addJsonObject { put("t", "text_input"); put("id", "name")
                    put("value", "Untitled") }
                addJsonObject { put("t", "checkbox"); put("id", "agree")
                    put("checked", true) }
                addJsonObject { put("t", "switch"); put("id", "off") }
            }
        }
        engine.feed(frame(request("d1", "dialog.show", buildJsonObject {
            put("dialog_id", "rename"); put("spec", spec) })))
        val d = engine.dialogDefaults("rename")!!
        // Types are the node's LOGICAL types, not strings.
        assertEquals("Untitled", d.reqString("name"))
        assertEquals(true, d.boolOrNull("agree"))
        assertEquals(false, d.boolOrNull("off")) // omitted `checked` is false
        // They are released with the dialog.
        engine.completeDialogDismiss("rename")
        assertNull(engine.dialogDefaults("rename"))
    }

    @Test
    fun showIsHeldThenSubmitCompletesIt() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = readyEngine(out, presented)
        show(engine, "d1", "rename")
        // SPEC 18.1: held outstanding — no reply yet, but presented.
        assertNull(responseFor(out, "d1"))
        assertEquals("rename", presented.single().first)
        assertNotNull(presented.single().second)
        // dialog.submit builtin completes it with value + captured fields.
        engine.completeDialogSubmit("rename", JsonPrimitive("ok"),
            buildJsonObject { put("name", "typed") })
        val result = responseFor(out, "d1")!!.reqObj("result")
        assertEquals("submitted", result.reqString("status"))
        assertEquals("ok", result.reqString("value"))
        assertEquals("typed", result.reqObj("fields").reqString("name"))
        // The presentation was dismissed after completion.
        assertEquals("rename" to null, presented.last())
    }

    @Test
    fun oversizeSubmitKeepsDialogOutstanding() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out, mutableListOf())
        val overflowed = mutableListOf<String>()
        engine.dialogOverflowListener = { overflowed.add(it) }
        show(engine, "d1", "rename")
        // SPEC 18.1: a submit whose prospective response exceeds max_frame_bytes
        // writes nothing and does NOT complete the dialog.
        engine.completeDialogSubmit("rename", JsonPrimitive("ok"),
            buildJsonObject { put("blob", "x".repeat(4_300_000)) })
        assertNull(responseFor(out, "d1"))          // no part of the response written
        assertEquals(listOf("rename"), overflowed)  // host told to diagnose + erase
        // The dialog is still outstanding: a shrunk submit now completes it.
        engine.completeDialogSubmit("rename", JsonPrimitive("ok"),
            buildJsonObject { put("name", "small") })
        assertEquals("submitted",
            responseFor(out, "d1")!!.reqObj("result").reqString("status"))
    }

    @Test
    fun dismissCompletesAsDismissed() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out, mutableListOf())
        show(engine, "d1", "rename")
        engine.completeDialogDismiss("rename")
        assertEquals("dismissed",
            responseFor(out, "d1")!!.reqObj("result").reqString("status"))
        // A second completion is a no-op (the request is gone).
        engine.completeDialogSubmit("rename", JsonPrimitive("late"))
        assertEquals("dismissed",
            responseFor(out, "d1")!!.reqObj("result").reqString("status"))
    }

    @Test
    fun cancelConcludesWith1301() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out, mutableListOf())
        show(engine, "d1", "rename")
        engine.feed(frame(notification("rpc.cancel", buildJsonObject { put("id", "d1") })))
        assertEquals(1301L, responseFor(out, "d1")!!.reqObj("error").reqLong("code"))
    }

    @Test
    fun rpcCancelWithIntegerIdConcludesDialog() {
        // P0 pre-swap pin (PLAN-rf2 §0.2 item 8). The outstanding-dialog map
        // is keyed by the REQUEST ID with its JSON type intact. jsonrpc.el
        // numbers its requests with integers (amendment #34), so a dialog
        // shown by request id 7 is cancelled by `rpc.cancel {id: 7}` — and
        // NOT by `{id: "7"}` (SPEC 4.3: no coercion). Post-swap this map
        // compares JsonElement to JsonElement, where data-class equality
        // distinguishes 7 from "7"; a coercing lookup would conclude the
        // wrong dialog and leave the real one outstanding forever.
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out, mutableListOf())
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0"); put("id", 7)
            put("method", "dialog.show")
            putJsonObject("params") {
                put("dialog_id", "rename"); put("spec", dialogSpec()) }
        }))
        // The string spelling of that id concludes nothing.
        engine.feed(frame(notification("rpc.cancel", buildJsonObject { put("id", "7") })))
        assertNull("a string id must not cancel an integer-id dialog",
            out.lastOrNull { it["id"] == JsonPrimitive(7) })
        // The integer spelling concludes it.
        engine.feed(frame(notification("rpc.cancel", buildJsonObject { put("id", 7) })))
        assertEquals(1301L, out.replyTo(7L).reqObj("error").reqLong("code"))
    }

    @Test
    fun duplicateDialogIdIs1201FirstUntouched() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out, mutableListOf())
        show(engine, "d1", "rename")
        show(engine, "d2", "rename")
        assertEquals("content-invalid", responseFor(out, "d2")!!
            .reqObj("error").reqObj("data").reqString("kind"))
        // The first request is still outstanding (no response).
        assertNull(responseFor(out, "d1"))
        // And it still completes normally.
        engine.completeDialogDismiss("rename")
        assertEquals("dismissed",
            responseFor(out, "d1")!!.reqObj("result").reqString("status"))
    }

    @Test
    fun exceedingMaxDialogsIs1401ExistingStand() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out, mutableListOf())
        show(engine, "d1", "a")
        show(engine, "d2", "b")     // now at max_dialogs = 2
        show(engine, "d3", "c")
        assertEquals(1401L, responseFor(out, "d3")!!.reqObj("error").reqLong("code"))
        assertNull(responseFor(out, "d1"))
        assertNull(responseFor(out, "d2"))
    }

    @Test
    fun invalidDialogSpecIs1201() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out, mutableListOf())
        engine.feed(frame(request("d1", "dialog.show", buildJsonObject {
            put("dialog_id", "bad")
            putJsonObject("spec") { put("t", "text") } }))) // missing required text
        assertEquals(1201L, responseFor(out, "d1")!!.reqObj("error").reqLong("code"))
    }

    @Test
    fun transportLossDismissesOutstandingDialogs() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = readyEngine(out, presented)
        show(engine, "d1", "a")
        show(engine, "d2", "b")
        engine.close("transport closed")
        // SPEC 18.1: both dismissed locally on loss.
        assertEquals(listOf("a", "b"),
            presented.filter { it.second == null }.map { it.first })
        // A late completion after close does nothing.
        engine.completeDialogSubmit("a", JsonPrimitive("x"))
        assertNull(responseFor(out, "d1"))
    }

    private fun assertNotNull(v: Any?) = assertTrue(v != null)

    // SPEC 18.1/14.4: a REMOTE descriptor inside a dialog dispatches in
    // DIALOG context — dialog_id INSTEAD of surface/revision, the capture
    // snapshot from the dialog-local layer.  The JA-5 device gate found the
    // generic dispatch silently dropping every such descriptor (it resolved
    // a revision for the pseudo-surface, got null, returned).
    @Test
    fun remoteDescriptorInDialogDispatchesInDialogContext() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = readyEngine(out, presented)
        show(engine, "d1", "a")
        val descriptor = buildJsonObject {
            put("action", "jetpacs.org.archive")
            putJsonObject("args") { put("token", "o1234-1") }
            put("capture_fields", JsonArray(listOf("name").map(::JsonPrimitive)))
        }
        val fields = buildJsonObject { put("name", "typed value") }
        engine.dispatchDialogAction("a", descriptor, null, fields)
        val event = out.events().last().reqObj("params")
        assertEquals("jetpacs.org.archive", event.reqString("action"))
        assertEquals("a", event.reqString("dialog_id"))
        assertFalse("surface" in event)
        assertFalse("revision_seen" in event)
        assertEquals("o1234-1",
            event.reqObj("args").reqString("token"))
        assertEquals("typed value",
            event.reqObj("fields").reqString("name"))
    }

    @Test
    fun remoteDescriptorAfterConclusionDispatchesNothing() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = readyEngine(out, presented)
        show(engine, "d1", "a")
        engine.completeDialogSubmit("a", JsonPrimitive("done"))
        val before = out.size
        engine.dispatchDialogAction("a",
            buildJsonObject { put("action", "jetpacs.org.archive") }, null, null)
        // The tap raced the conclusion: no event, no crash.
        assertEquals(before, out.size)
    }
}
