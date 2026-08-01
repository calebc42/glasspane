// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: the device-capability module (SPEC 20). The welcome device
// report, capability.invoke dispatch, the error taxonomy (1001 cap-unsupported
// / 1002 cap-permission / 1003 cap-failed / -32602 invalid-params before any
// side effect / -32601 when ungranted), and the closed Args catalog validators.
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

class CapabilityTest {

    private fun report(vararg caps: String) = buildJsonObject {
        put("caps", JsonArray(caps.toList().map(::JsonPrimitive)))
        put("trigger_caps", JsonArray(emptyList()))
        put("permissions", JsonObject(emptyMap()))
    }

    // A recording handler: every invocation that reaches the host is logged,
    // so a test can prove -32602 / 1001 refuse BEFORE any side effect.
    private val calls = mutableListOf<Pair<String, JsonObject>>()

    private fun engine(out: MutableList<JsonObject>,
                       grant: Boolean = true,
                       deviceReport: JsonObject = report("vibrate", "clipboard.read", "volume.set"),
                       handler: CapabilityHandler? = CapabilityHandler { cap, args ->
                           calls.add(cap to args)
                           when (cap) {
                               "clipboard.read" -> CapabilityOutcome.Ok(
                                   buildJsonObject { put("text", "hi") })
                               "volume.set" -> CapabilityOutcome.Ok(
                                   buildJsonObject { put("max", 15) })
                               else -> CapabilityOutcome.Ok(JsonObject(emptyMap()))
                           }
                       }): CompanionEngine {
        val wants = if (grant) listOf("capabilities") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("capabilities"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(NODE_SCHEMA.keys.map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_device_report_bytes" to 8192,
                "max_rich_spans" to 4096, "max_table_cells" to 4096),
            deviceReport = deviceReport,
            capabilityHandler = handler, nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        return engine
    }

    private fun invoke(engine: CompanionEngine, id: String, cap: String, args: JsonObject? = null) {
        engine.feed(frame(request(id, "capability.invoke", buildJsonObject {
            put("cap", cap)
            if (args != null) put("args", args)
        })))
    }

    // ------------------------------------------------ welcome device report

    @Test
    fun welcomeCarriesDeviceReportOnlyWhenAModuleGranted() {
        val out = mutableListOf<JsonObject>()
        engine(out)
        val device = out.replyTo("h2").reqObj("result").reqObj("device")
        assertEquals("vibrate", device.reqArr("caps")[0].asStringOrNull()!!)
        // Ungranted: no device member at all.
        val out2 = mutableListOf<JsonObject>()
        engine(out2, grant = false)
        assertFalse("device" in out2.replyTo("h2").reqObj("result"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun oversizeDeviceReportFailsTheReservation() {
        // SPEC 4.5/20.1: a report larger than max_device_report_bytes cannot be
        // reserved for, so construction fails the welcome reservation check.
        val bloated = report("vibrate").with("permissions",
            buildJsonObject { put("blob", "y".repeat(9000)) })
        engine(mutableListOf(), deviceReport = bloated)
    }

    @Test
    fun capabilitiesOnlyWelcomeEmptiesTriggerSurface() {
        val out = mutableListOf<JsonObject>()
        // A report that lists a trigger surface while only capabilities is
        // granted: SPEC 20.1 requires trigger_caps empty (and the trigger-only
        // members MAY be empty) in that session.
        val report = report("vibrate")
            .with("trigger_caps", JsonArray(listOf("vibrate").map(::JsonPrimitive)))
            .with("trigger_types", JsonArray(listOf("battery.level").map(::JsonPrimitive)))
            .with("trackable_state_types", JsonArray(listOf("battery.level").map(::JsonPrimitive)))
            .with("state_types", JsonArray(listOf("battery.level").map(::JsonPrimitive)))
        engine(out, deviceReport = report)
        val device = out.replyTo("h2").reqObj("result").reqObj("device")
        assertEquals(0, device.reqArr("trigger_caps").size)
        assertEquals(0, device.reqArr("trigger_types").size)
        assertEquals(0, device.reqArr("state_types").size) // no state.get in caps
    }

    // ------------------------------------------------- invoke happy + gating

    @Test
    fun invokeForwardsHandlerResultExactly() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        invoke(engine, "c1", "clipboard.read", JsonObject(emptyMap()))
        assertEquals("hi", out.replyTo("c1").reqObj("result").reqString("text"))
        invoke(engine, "c2", "volume.set",
            buildJsonObject { put("stream", "music"); put("level", 3) })
        assertEquals(15L, out.replyTo("c2").reqObj("result").reqLong("max"))
    }

    @Test
    fun unserializableResultIsAnsweredNotDropped() {
        // SPEC 7.1: "A responder that computes a result but cannot serialize
        // the response body MUST answer the request with -32603
        // internal-error; it MUST NOT leave the request unanswered." The
        // result is host-supplied, so its shape is not the engine's to trust
        // — this one nests past what org.json's recursive encoder can walk.
        // Before the guard the encoder's failure escaped out of feed(), and
        // Emacs was left holding an id that never concluded (and which SPEC
        // 7.2 then forbids it from ever reusing).
        var deep = JsonObject(emptyMap())
        repeat(60_000) { deep = JsonObject(mapOf("n" to deep)) }
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, handler = CapabilityHandler { _, _ ->
            CapabilityOutcome.Ok(deep)
        })
        invoke(engine, "c1", "clipboard.read", JsonObject(emptyMap()))
        assertEquals(-32603L, out.errorOf("c1").reqLong("code"))
        assertEquals("internal-error",
            out.errorOf("c1").reqObj("data").reqString("kind"))
        // The session survives: a fresh invocation is answered normally.
        val out2 = mutableListOf<JsonObject>()
        val engine2 = engine(out2)
        invoke(engine2, "c2", "clipboard.read", JsonObject(emptyMap()))
        assertEquals("hi", out2.replyTo("c2").reqObj("result").reqString("text"))
    }

    @Test
    fun ungrantedModuleIsMethodNotFound() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, grant = false)
        invoke(engine, "c1", "vibrate", buildJsonObject { put("ms", 100) })
        assertEquals(-32601L, out.errorOf("c1").reqLong("code"))
        assertTrue(calls.isEmpty())
    }

    @Test
    fun unknownCapIsCapUnsupported() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        // flashlight is a real catalog entry but not in this device's caps.
        invoke(engine, "c1", "flashlight", buildJsonObject { put("on", true) })
        assertEquals(1001L, out.errorOf("c1").reqLong("code"))
        assertEquals("cap-unsupported", out.errorOf("c1").reqObj("data").reqString("kind"))
        assertTrue(calls.isEmpty()) // no side effect
    }

    // --------------------------------------------- validation before effect

    @Test
    fun invalidArgsIsInvalidParamsBeforeSideEffect() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        // vibrate with both ms and pattern is ambiguous.
        invoke(engine, "c1", "vibrate", buildJsonObject {
            put("ms", 100)
            put("pattern", JsonArray(listOf(0, 100).map { JsonPrimitive(it) }))
        })
        assertEquals(-32602L, out.errorOf("c1").reqLong("code"))
        // out-of-range ms.
        invoke(engine, "c2", "vibrate", buildJsonObject { put("ms", 0) })
        assertEquals(-32602L, out.errorOf("c2").reqLong("code"))
        // an unknown top-level param member is -32602.
        engine.feed(frame(request("c3", "capability.invoke", buildJsonObject {
            put("cap", "clipboard.read"); put("args", JsonObject(emptyMap())); put("extra", 1)
        })))
        assertEquals(-32602L, out.errorOf("c3").reqLong("code"))
        assertTrue(calls.isEmpty()) // nothing reached the host
    }

    // ----------------------------------------------- handler typed refusals

    @Test
    fun handlerRefusalsAreForwardedTyped() {
        val out = mutableListOf<JsonObject>()
        // Real validated caps whose host executor refuses at invocation time.
        val engine = engine(out, deviceReport = report("flashlight", "vibrate"),
            handler = CapabilityHandler { cap, _ ->
                if (cap == "flashlight") CapabilityOutcome.Fail(1002, "needs-grant")
                else CapabilityOutcome.Fail(1003, "hardware-busy")
            })
        invoke(engine, "c1", "flashlight", buildJsonObject { put("on", true) })
        assertEquals(1002L, out.errorOf("c1").reqLong("code"))
        assertEquals("cap-permission", out.errorOf("c1").reqObj("data").reqString("kind"))
        invoke(engine, "c2", "vibrate", buildJsonObject { put("ms", 100) })
        assertEquals(1003L, out.errorOf("c2").reqLong("code"))
        assertEquals("hardware-busy", out.errorOf("c2").reqObj("data").reqString("reason"))
    }

    @Test
    fun nullHandlerFailsCapFailed() {
        val out = mutableListOf<JsonObject>()
        // A device advertising caps but with no executor is misconfigured.
        val engine = engine(out, handler = null)
        invoke(engine, "c1", "clipboard.read", JsonObject(emptyMap()))
        assertEquals(1003L, out.errorOf("c1").reqLong("code"))
        assertEquals("no-handler", out.errorOf("c1").reqObj("data").reqString("reason"))
    }

    // ------------------------------------------------- catalog Args schemas

    private fun ok(cap: String, args: JsonObject): Boolean =
        try { CapabilityCatalog.validateArgs(cap, args); true }
        catch (e: ContentInvalid) { false }

    @Test
    fun vibrateSchema() {
        assertTrue(ok("vibrate", buildJsonObject { put("ms", 1) }))
        assertTrue(ok("vibrate", buildJsonObject { put("ms", 60_000) }))
        assertTrue(ok("vibrate", buildJsonObject {
            put("pattern", JsonArray(listOf(0, 100, 0, 100).map { JsonPrimitive(it) })) }))
        assertFalse(ok("vibrate", buildJsonObject { put("ms", 0) }))          // below 1
        assertFalse(ok("vibrate", buildJsonObject { put("ms", 60_001) }))     // above 60000
        assertFalse(ok("vibrate", JsonObject(emptyMap())))                    // neither
        assertFalse(ok("vibrate", buildJsonObject {
            put("ms", 5); put("pattern", JsonArray(listOf(0).map { JsonPrimitive(it) })) }))
        assertFalse(ok("vibrate", buildJsonObject {
            put("pattern", JsonArray(emptyList())) }))                        // empty
        assertFalse(ok("vibrate", buildJsonObject {
            put("pattern", JsonArray(listOf(60_000, 60_000).map { JsonPrimitive(it) })) })) // total > 60000
        assertFalse(ok("vibrate", buildJsonObject {
            put("pattern", JsonArray(listOf(JsonPrimitive(1.5)))) }))         // non-integer
    }

    @Test
    fun scalarSchemas() {
        assertTrue(ok("volume.set", buildJsonObject { put("stream", "music"); put("level", 5) }))
        assertFalse(ok("volume.set", buildJsonObject { put("stream", "bogus"); put("level", 5) }))
        assertFalse(ok("volume.set", buildJsonObject { put("stream", "music"); put("level", -1) }))
        assertFalse(ok("volume.set", buildJsonObject { put("stream", "music") }))    // missing level

        assertTrue(ok("tts.speak", buildJsonObject { put("text", "hi") }))
        assertTrue(ok("tts.speak", buildJsonObject {
            put("text", "hi"); put("pitch", 1.5); put("rate", 0.8) }))
        assertFalse(ok("tts.speak", buildJsonObject { put("text", "hi"); put("pitch", 3.0) }))
        assertFalse(ok("tts.speak", buildJsonObject { put("text", 123) }))
        assertFalse(ok("tts.speak", JsonObject(emptyMap())))                        // missing text

        assertTrue(ok("ringer.mode", buildJsonObject { put("mode", "silent") }))
        assertFalse(ok("ringer.mode", buildJsonObject { put("mode", "loud") }))

        assertTrue(ok("flashlight", buildJsonObject { put("on", true) }))
        assertFalse(ok("flashlight", buildJsonObject { put("on", "yes") }))
        assertFalse(ok("flashlight", JsonObject(emptyMap())))

        assertTrue(ok("media.key", buildJsonObject { put("key", "play_pause") }))
        assertFalse(ok("media.key", buildJsonObject { put("key", "eject") }))

        assertTrue(ok("screen.keep_on", buildJsonObject { put("on", false) }))

        assertTrue(ok("brightness.set", buildJsonObject { put("level", 255) }))
        assertFalse(ok("brightness.set", buildJsonObject { put("level", 256) }))
        assertFalse(ok("brightness.set", buildJsonObject { put("level", 1.5) }))

        assertTrue(ok("dnd.set", buildJsonObject { put("mode", "priority") }))
        assertFalse(ok("dnd.set", buildJsonObject { put("mode", "maybe") }))

        assertTrue(ok("clipboard.read", JsonObject(emptyMap())))
        assertFalse(ok("clipboard.read", buildJsonObject { put("x", 1) }))

        // A real catalog entry this build does not yet validate must throw,
        // never silently pass an unvalidated Args object to a side effect.
        assertFalse(ok("state.get", JsonObject(emptyMap())))
    }
}
