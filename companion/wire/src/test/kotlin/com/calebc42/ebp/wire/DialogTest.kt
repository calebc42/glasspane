// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: the dialog module (SPEC 18.1). dialog.show is held as a
// deferred request; dialog.submit/dialog.dismiss builtins and rpc.cancel
// complete it; duplicate ids are 1201, over-limit is 1401, transport loss
// dismisses every outstanding dialog.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DialogTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits(): JSONObject = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64).put("max_dialogs", 2)

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    private fun readyEngine(out: MutableList<JSONObject>,
                            presented: MutableList<Pair<String, JSONObject?>>)
            : CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("surfaces.dialog"),
            surfaceProfiles = JSONObject()
                .put("app", JSONObject()
                    .put("node_types", JSONArray(listOf("text", "column", "button")))
                    .put("builtins", JSONArray()).put("features", JSONArray()))
                .put("dialog", JSONObject()
                    .put("node_types", JSONArray(listOf("text", "column",
                        "button", "text_input")))
                    .put("builtins", JSONArray(listOf("dialog.submit", "dialog.dismiss")))
                    .put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.dialogListener = { id, spec -> presented.add(id to spec) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("surfaces.dialog")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        assertEquals(SessionState.READY, engine.state)
        return engine
    }

    private fun dialogSpec() = JSONObject().put("t", "column").put("children",
        JSONArray().put(JSONObject().put("t", "text_input").put("id", "name")))

    private fun show(engine: CompanionEngine, reqId: String, dialogId: String) =
        engine.feed(frame(request(reqId, "dialog.show", JSONObject()
            .put("dialog_id", dialogId).put("spec", dialogSpec()))))

    private fun responseFor(out: List<JSONObject>, reqId: String) =
        out.lastOrNull { it.opt("id") == reqId }

    @Test
    fun showIsHeldThenSubmitCompletesIt() {
        val out = mutableListOf<JSONObject>()
        val presented = mutableListOf<Pair<String, JSONObject?>>()
        val engine = readyEngine(out, presented)
        show(engine, "d1", "rename")
        // SPEC 18.1: held outstanding — no reply yet, but presented.
        assertNull(responseFor(out, "d1"))
        assertEquals("rename", presented.single().first)
        assertNotNull(presented.single().second)
        // dialog.submit builtin completes it with value + captured fields.
        engine.completeDialogSubmit("rename", "ok",
            JSONObject().put("name", "typed"))
        val result = responseFor(out, "d1")!!.getJSONObject("result")
        assertEquals("submitted", result.getString("status"))
        assertEquals("ok", result.getString("value"))
        assertEquals("typed", result.getJSONObject("fields").getString("name"))
        // The presentation was dismissed after completion.
        assertEquals("rename" to null, presented.last())
    }

    @Test
    fun dismissCompletesAsDismissed() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out, mutableListOf())
        show(engine, "d1", "rename")
        engine.completeDialogDismiss("rename")
        assertEquals("dismissed",
            responseFor(out, "d1")!!.getJSONObject("result").getString("status"))
        // A second completion is a no-op (the request is gone).
        engine.completeDialogSubmit("rename", "late")
        assertEquals("dismissed",
            responseFor(out, "d1")!!.getJSONObject("result").getString("status"))
    }

    @Test
    fun cancelConcludesWith1301() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out, mutableListOf())
        show(engine, "d1", "rename")
        engine.feed(frame(notification("rpc.cancel", JSONObject().put("id", "d1"))))
        assertEquals(1301, responseFor(out, "d1")!!.getJSONObject("error").getInt("code"))
    }

    @Test
    fun duplicateDialogIdIs1201FirstUntouched() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out, mutableListOf())
        show(engine, "d1", "rename")
        show(engine, "d2", "rename")
        assertEquals("content-invalid", responseFor(out, "d2")!!
            .getJSONObject("error").getJSONObject("data").getString("kind"))
        // The first request is still outstanding (no response).
        assertNull(responseFor(out, "d1"))
        // And it still completes normally.
        engine.completeDialogDismiss("rename")
        assertEquals("dismissed",
            responseFor(out, "d1")!!.getJSONObject("result").getString("status"))
    }

    @Test
    fun exceedingMaxDialogsIs1401ExistingStand() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out, mutableListOf())
        show(engine, "d1", "a")
        show(engine, "d2", "b")     // now at max_dialogs = 2
        show(engine, "d3", "c")
        assertEquals(1401, responseFor(out, "d3")!!.getJSONObject("error").getInt("code"))
        assertNull(responseFor(out, "d1"))
        assertNull(responseFor(out, "d2"))
    }

    @Test
    fun invalidDialogSpecIs1201() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out, mutableListOf())
        engine.feed(frame(request("d1", "dialog.show", JSONObject()
            .put("dialog_id", "bad")
            .put("spec", JSONObject().put("t", "text"))))) // missing required text
        assertEquals(1201, responseFor(out, "d1")!!.getJSONObject("error").getInt("code"))
    }

    @Test
    fun transportLossDismissesOutstandingDialogs() {
        val out = mutableListOf<JSONObject>()
        val presented = mutableListOf<Pair<String, JSONObject?>>()
        val engine = readyEngine(out, presented)
        show(engine, "d1", "a")
        show(engine, "d2", "b")
        engine.close("transport closed")
        // SPEC 18.1: both dismissed locally on loss.
        assertEquals(listOf("a", "b"),
            presented.filter { it.second == null }.map { it.first })
        // A late completion after close does nothing.
        engine.completeDialogSubmit("a", "x")
        assertNull(responseFor(out, "d1"))
    }

    private fun assertNotNull(v: Any?) = assertTrue(v != null)
}
