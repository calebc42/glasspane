// SPDX-License-Identifier: GPL-3.0-or-later
// RB-2 SPEC 14.6: a renderer-supplied occurrence-time field (a text_input
// password's on_submit) rides event.action.fields, merged beside any
// capture_fields, never args. Deterministic against a READY engine.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DispatchFieldsTest {

    private fun readyEngine(out: MutableList<JsonObject>): CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(listOf("text", "text_input").map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, emptyList()))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        assertEquals(SessionState.READY, engine.state)
        return engine
    }

    @Test
    fun passwordSubmitCarriesSecretInFieldsNotArgs() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 1)
            putJsonObject("spec") {
                put("t", "text_input"); put("id", "pw"); put("password", true)
            }
        })))
        // The password on_submit: a drop action carrying the secret via extraFields.
        val onSubmit = buildJsonObject { put("action", "auth.login"); put("when_offline", "drop") }
        engine.dispatchAction("app:main", onSubmit, null, null,
            buildJsonObject { put("pw", "s3cret") })
        val ev = out.last { it.stringOrNull("method") == "event.action" }.reqObj("params")
        assertEquals("auth.login", ev.reqString("action"))
        // SPEC 14.6: the secret is in fields.<id>, NOT in args.
        assertEquals("s3cret", ev.reqObj("fields").reqString("pw"))
        assertFalse("secret must not appear in args",
            ev.objOrNull("args")?.containsKey("value") == true)
    }

    @Test
    fun extraFieldsMergeBesideCaptureFields() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        // A stateful text_input whose draft capture_fields will read, plus a
        // renderer-supplied extra field — both land in fields.
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 1)
            putJsonObject("spec") {
                put("t", "column")
                putJsonArray("children") {
                    addJsonObject { put("t", "text_input"); put("id", "name"); put("value", "Ann") }
                }
            }
        })))
        val desc = buildJsonObject {
            put("action", "form.save"); put("when_offline", "drop")
            put("capture_fields", buildJsonArray { add("name") })
        }
        engine.dispatchAction("app:main", desc, null, null, buildJsonObject { put("pw", "x") })
        val fields = out.last { it.stringOrNull("method") == "event.action" }
            .reqObj("params").reqObj("fields")
        assertEquals("Ann", fields.reqString("name"))  // capture_fields
        assertEquals("x", fields.reqString("pw"))       // extraFields
        assertTrue(fields.size == 2)
    }
}
