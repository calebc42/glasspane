// SPDX-License-Identifier: GPL-3.0-or-later
// RB-2 SPEC 14.6: a renderer-supplied occurrence-time field (a text_input
// password's on_submit) rides event.action.fields, merged beside any
// capture_fields, never args. Deterministic against a READY engine.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DispatchFieldsTest {

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
                .put("node_types", JSONArray(listOf("text", "text_input")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
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

    @Test
    fun passwordSubmitCarriesSecretInFieldsNotArgs() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 1)
            .put("spec", JSONObject()
                .put("t", "text_input").put("id", "pw").put("password", true)))))
        // The password on_submit: a drop action carrying the secret via extraFields.
        val onSubmit = JSONObject().put("action", "auth.login").put("when_offline", "drop")
        engine.dispatchAction("app:main", onSubmit, null, null,
            JSONObject().put("pw", "s3cret"))
        val ev = out.last { it.opt("method") == "event.action" }.getJSONObject("params")
        assertEquals("auth.login", ev.getString("action"))
        // SPEC 14.6: the secret is in fields.<id>, NOT in args.
        assertEquals("s3cret", ev.getJSONObject("fields").getString("pw"))
        assertFalse("secret must not appear in args",
            ev.optJSONObject("args")?.has("value") == true)
    }

    @Test
    fun extraFieldsMergeBesideCaptureFields() {
        val out = mutableListOf<JSONObject>()
        val engine = readyEngine(out)
        // A stateful text_input whose draft capture_fields will read, plus a
        // renderer-supplied extra field — both land in fields.
        engine.feed(frame(request("s1", "surface.update", JSONObject()
            .put("surface", "app:main").put("revision", 1)
            .put("spec", JSONObject().put("t", "column").put("children", JSONArray()
                .put(JSONObject().put("t", "text_input").put("id", "name").put("value", "Ann")))))))
        val desc = JSONObject().put("action", "form.save").put("when_offline", "drop")
            .put("capture_fields", JSONArray().put("name"))
        engine.dispatchAction("app:main", desc, null, null, JSONObject().put("pw", "x"))
        val fields = out.last { it.opt("method") == "event.action" }
            .getJSONObject("params").getJSONObject("fields")
        assertEquals("Ann", fields.getString("name"))  // capture_fields
        assertEquals("x", fields.getString("pw"))       // extraFields
        assertTrue(fields.length() == 2)
    }
}
