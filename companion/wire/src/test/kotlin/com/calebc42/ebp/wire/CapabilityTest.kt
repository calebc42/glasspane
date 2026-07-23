// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: the device-capability module (SPEC 20). The welcome device
// report, capability.invoke dispatch, the error taxonomy (1001 cap-unsupported
// / 1002 cap-permission / 1003 cap-failed / -32602 invalid-params before any
// side effect / -32601 when ungranted), and the closed Args catalog validators.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CapabilityTest {

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
    private fun response(out: List<JSONObject>, id: String) = out.last { it.opt("id") == id }
    private fun errorOf(out: List<JSONObject>, id: String) = response(out, id).getJSONObject("error")

    private fun report(vararg caps: String) = JSONObject()
        .put("caps", JSONArray(caps.toList()))
        .put("trigger_caps", JSONArray())
        .put("permissions", JSONObject())

    // A recording handler: every invocation that reaches the host is logged,
    // so a test can prove -32602 / 1001 refuse BEFORE any side effect.
    private val calls = mutableListOf<Pair<String, JSONObject>>()

    private fun engine(out: MutableList<JSONObject>,
                       grant: Boolean = true,
                       deviceReport: JSONObject = report("vibrate", "clipboard.read", "volume.set"),
                       handler: CapabilityHandler? = CapabilityHandler { cap, args ->
                           calls.add(cap to args)
                           when (cap) {
                               "clipboard.read" -> CapabilityOutcome.Ok(JSONObject().put("text", "hi"))
                               "volume.set" -> CapabilityOutcome.Ok(JSONObject().put("max", 15))
                               else -> CapabilityOutcome.Ok(JSONObject())
                           }
                       }): CompanionEngine {
        val wants = if (grant) listOf("capabilities") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("capabilities"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray()).put("builtins", JSONArray())
                .put("features", JSONArray())),
            limits = limits(), deviceReport = deviceReport,
            capabilityHandler = handler, nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        return engine
    }

    private fun invoke(engine: CompanionEngine, id: String, cap: String, args: JSONObject? = null) {
        val p = JSONObject().put("cap", cap)
        if (args != null) p.put("args", args)
        engine.feed(frame(request(id, "capability.invoke", p)))
    }

    // ------------------------------------------------ welcome device report

    @Test
    fun welcomeCarriesDeviceReportOnlyWhenAModuleGranted() {
        val out = mutableListOf<JSONObject>()
        engine(out)
        val device = response(out, "h2").getJSONObject("result").getJSONObject("device")
        assertEquals("vibrate", device.getJSONArray("caps").getString(0))
        // Ungranted: no device member at all.
        val out2 = mutableListOf<JSONObject>()
        engine(out2, grant = false)
        assertFalse(response(out2, "h2").getJSONObject("result").has("device"))
    }

    @Test
    fun capabilitiesOnlyWelcomeEmptiesTriggerSurface() {
        val out = mutableListOf<JSONObject>()
        // A report that lists a trigger surface while only capabilities is
        // granted: SPEC 20.1 requires trigger_caps empty (and the trigger-only
        // members MAY be empty) in that session.
        val report = report("vibrate")
            .put("trigger_caps", JSONArray(listOf("vibrate")))
            .put("trigger_types", JSONArray(listOf("battery.level")))
            .put("trackable_state_types", JSONArray(listOf("battery.level")))
            .put("state_types", JSONArray(listOf("battery.level")))
        engine(out, deviceReport = report)
        val device = response(out, "h2").getJSONObject("result").getJSONObject("device")
        assertEquals(0, device.getJSONArray("trigger_caps").length())
        assertEquals(0, device.getJSONArray("trigger_types").length())
        assertEquals(0, device.getJSONArray("state_types").length()) // no state.get in caps
    }

    // ------------------------------------------------- invoke happy + gating

    @Test
    fun invokeForwardsHandlerResultExactly() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        invoke(engine, "c1", "clipboard.read", JSONObject())
        assertEquals("hi", response(out, "c1").getJSONObject("result").getString("text"))
        invoke(engine, "c2", "volume.set", JSONObject().put("stream", "music").put("level", 3))
        assertEquals(15, response(out, "c2").getJSONObject("result").getInt("max"))
    }

    @Test
    fun ungrantedModuleIsMethodNotFound() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, grant = false)
        invoke(engine, "c1", "vibrate", JSONObject().put("ms", 100))
        assertEquals(-32601, errorOf(out, "c1").getInt("code"))
        assertTrue(calls.isEmpty())
    }

    @Test
    fun unknownCapIsCapUnsupported() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        // flashlight is a real catalog entry but not in this device's caps.
        invoke(engine, "c1", "flashlight", JSONObject().put("on", true))
        assertEquals(1001, errorOf(out, "c1").getInt("code"))
        assertEquals("cap-unsupported", errorOf(out, "c1").getJSONObject("data").getString("kind"))
        assertTrue(calls.isEmpty()) // no side effect
    }

    // --------------------------------------------- validation before effect

    @Test
    fun invalidArgsIsInvalidParamsBeforeSideEffect() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        // vibrate with both ms and pattern is ambiguous.
        invoke(engine, "c1", "vibrate", JSONObject().put("ms", 100)
            .put("pattern", JSONArray(listOf(0, 100))))
        assertEquals(-32602, errorOf(out, "c1").getInt("code"))
        // out-of-range ms.
        invoke(engine, "c2", "vibrate", JSONObject().put("ms", 0))
        assertEquals(-32602, errorOf(out, "c2").getInt("code"))
        // an unknown top-level param member is -32602.
        engine.feed(frame(request("c3", "capability.invoke", JSONObject()
            .put("cap", "clipboard.read").put("args", JSONObject()).put("extra", 1))))
        assertEquals(-32602, errorOf(out, "c3").getInt("code"))
        assertTrue(calls.isEmpty()) // nothing reached the host
    }

    // ----------------------------------------------- handler typed refusals

    @Test
    fun handlerRefusalsAreForwardedTyped() {
        val out = mutableListOf<JSONObject>()
        // Real validated caps whose host executor refuses at invocation time.
        val engine = engine(out, deviceReport = report("flashlight", "vibrate"),
            handler = CapabilityHandler { cap, _ ->
                if (cap == "flashlight") CapabilityOutcome.Fail(1002, "needs-grant")
                else CapabilityOutcome.Fail(1003, "hardware-busy")
            })
        invoke(engine, "c1", "flashlight", JSONObject().put("on", true))
        assertEquals(1002, errorOf(out, "c1").getInt("code"))
        assertEquals("cap-permission", errorOf(out, "c1").getJSONObject("data").getString("kind"))
        invoke(engine, "c2", "vibrate", JSONObject().put("ms", 100))
        assertEquals(1003, errorOf(out, "c2").getInt("code"))
        assertEquals("hardware-busy", errorOf(out, "c2").getJSONObject("data").getString("reason"))
    }

    @Test
    fun nullHandlerFailsCapFailed() {
        val out = mutableListOf<JSONObject>()
        // A device advertising caps but with no executor is misconfigured.
        val engine = engine(out, handler = null)
        invoke(engine, "c1", "clipboard.read", JSONObject())
        assertEquals(1003, errorOf(out, "c1").getInt("code"))
        assertEquals("no-handler", errorOf(out, "c1").getJSONObject("data").getString("reason"))
    }

    // ------------------------------------------------- catalog Args schemas

    private fun ok(cap: String, args: JSONObject): Boolean =
        try { CapabilityCatalog.validateArgs(cap, args); true }
        catch (e: ContentInvalid) { false }

    @Test
    fun vibrateSchema() {
        assertTrue(ok("vibrate", JSONObject().put("ms", 1)))
        assertTrue(ok("vibrate", JSONObject().put("ms", 60_000)))
        assertTrue(ok("vibrate", JSONObject().put("pattern", JSONArray(listOf(0, 100, 0, 100)))))
        assertFalse(ok("vibrate", JSONObject().put("ms", 0)))          // below 1
        assertFalse(ok("vibrate", JSONObject().put("ms", 60_001)))     // above 60000
        assertFalse(ok("vibrate", JSONObject()))                       // neither
        assertFalse(ok("vibrate", JSONObject().put("ms", 5).put("pattern", JSONArray(listOf(0)))))
        assertFalse(ok("vibrate", JSONObject().put("pattern", JSONArray(listOf<Int>()))))   // empty
        assertFalse(ok("vibrate", JSONObject().put("pattern", JSONArray(listOf(60_000, 60_000))))) // total > 60000
        assertFalse(ok("vibrate", JSONObject().put("pattern", JSONArray(listOf(1.5)))))     // non-integer
    }

    @Test
    fun scalarSchemas() {
        assertTrue(ok("volume.set", JSONObject().put("stream", "music").put("level", 5)))
        assertFalse(ok("volume.set", JSONObject().put("stream", "bogus").put("level", 5)))
        assertFalse(ok("volume.set", JSONObject().put("stream", "music").put("level", -1)))
        assertFalse(ok("volume.set", JSONObject().put("stream", "music")))    // missing level

        assertTrue(ok("tts.speak", JSONObject().put("text", "hi")))
        assertTrue(ok("tts.speak", JSONObject().put("text", "hi").put("pitch", 1.5).put("rate", 0.8)))
        assertFalse(ok("tts.speak", JSONObject().put("text", "hi").put("pitch", 3.0)))
        assertFalse(ok("tts.speak", JSONObject().put("text", 123)))
        assertFalse(ok("tts.speak", JSONObject()))                            // missing text

        assertTrue(ok("ringer.mode", JSONObject().put("mode", "silent")))
        assertFalse(ok("ringer.mode", JSONObject().put("mode", "loud")))

        assertTrue(ok("flashlight", JSONObject().put("on", true)))
        assertFalse(ok("flashlight", JSONObject().put("on", "yes")))
        assertFalse(ok("flashlight", JSONObject()))

        assertTrue(ok("media.key", JSONObject().put("key", "play_pause")))
        assertFalse(ok("media.key", JSONObject().put("key", "eject")))

        assertTrue(ok("screen.keep_on", JSONObject().put("on", false)))

        assertTrue(ok("brightness.set", JSONObject().put("level", 255)))
        assertFalse(ok("brightness.set", JSONObject().put("level", 256)))
        assertFalse(ok("brightness.set", JSONObject().put("level", 1.5)))

        assertTrue(ok("dnd.set", JSONObject().put("mode", "priority")))
        assertFalse(ok("dnd.set", JSONObject().put("mode", "maybe")))

        assertTrue(ok("clipboard.read", JSONObject()))
        assertFalse(ok("clipboard.read", JSONObject().put("x", 1)))

        // A real catalog entry this build does not yet validate must throw,
        // never silently pass an unvalidated Args object to a side effect.
        assertFalse(ok("state.get", JSONObject()))
    }
}
