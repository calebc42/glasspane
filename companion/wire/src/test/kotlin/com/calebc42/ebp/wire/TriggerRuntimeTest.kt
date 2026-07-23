// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: the trigger firing runtime (SPEC 21.2/21.3/21.5/21.6).
// Silent baselining and crossing/transition/edge detection, the state gate
// (flat AND, unevaluable = not holding), throttle, civil-time windows, and
// the drop trigger.fired event actually reaching the pipeline. The clock,
// state, and emit are injected, so the semantics are exercised with no device.
package com.calebc42.ebp.wire

import java.time.Instant
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TriggerRuntimeTest {

    private val caps = TriggerCaps(
        triggerTypes = setOf("battery.level", "screen", "state.edge", "boot", "manual", "power"),
        stateTypes = setOf("battery.level", "screen", "power"),
        trackableStateTypes = setOf("battery.level", "screen", "power"),
        triggerCaps = setOf("vibrate"), maxResponses = 4)

    private var clock = 1_000L
    private val state = HashMap<String, JSONObject>()
    private val fired = mutableListOf<Pair<String, JSONObject>>()
    private val store = TriggerStore()
    private val rt = TriggerRuntime(store, { clock }, ZoneId.of("UTC"),
        { state[it] }, emit = { reg, data, commit ->
            commit(); fired.add(reg.entry.getString("id") to data) })

    private fun trig(id: String, type: String, block: JSONObject.() -> Unit = {}) =
        JSONObject().put("id", id).put("type", type).apply(block)

    private fun register(vararg triggers: JSONObject) {
        val entries = TriggerValidator.validateSet(
            JSONObject().put("triggers", JSONArray(triggers.toList())), caps)
        store.replace("id", entries)
        rt.armBaselines("id")
    }

    private fun battery(level: Int) = JSONObject().put("level", level)
    private fun sample(type: String, s: JSONObject) { state[type] = s; rt.onSample("id", type, s) }
    private fun firedIds() = fired.map { it.first }

    // ------------------------------------------- crossing + silent baseline

    @Test
    fun batteryFiresOnCrossingNotSticky() {
        state["battery.level"] = battery(50)
        register(trig("bat", "battery.level") { put("params", JSONObject().put("below", 20)) })
        sample("battery.level", battery(50)); assertTrue(fired.isEmpty())   // sticky baseline
        sample("battery.level", battery(19)); assertEquals(1, fired.size)   // crossing in
        assertEquals(19, fired[0].second.getInt("level"))
        sample("battery.level", battery(15)); assertEquals(1, fired.size)   // already below
        sample("battery.level", battery(25)); assertEquals(1, fired.size)   // leaving
        sample("battery.level", battery(10)); assertEquals(2, fired.size)   // re-cross
    }

    @Test
    fun armedBelowNeverFiresWithoutLeaving() {
        // Arming while already on the configured side must not fire; a sticky
        // repeat of that side must not either (SPEC 21.5).
        state["battery.level"] = battery(10)
        register(trig("bat", "battery.level") { put("params", JSONObject().put("below", 20)) })
        sample("battery.level", battery(10)); assertTrue(fired.isEmpty())
        sample("battery.level", battery(5)); assertTrue(fired.isEmpty())
    }

    @Test
    fun screenFiltersTransitionIntoState() {
        state["screen"] = JSONObject().put("state", "on")
        register(trig("scr", "screen") { put("params", JSONObject().put("state", "off")) })
        sample("screen", JSONObject().put("state", "off")); assertEquals(1, fired.size)
        sample("screen", JSONObject().put("state", "off")); assertEquals(1, fired.size) // sticky
        sample("screen", JSONObject().put("state", "on")); assertEquals(1, fired.size)
        sample("screen", JSONObject().put("state", "off")); assertEquals(2, fired.size)
    }

    @Test
    fun unfilteredScreenFiresOnAnyChange() {
        state["screen"] = JSONObject().put("state", "on")
        register(trig("scr", "screen"))
        sample("screen", JSONObject().put("state", "off")); assertEquals(1, fired.size)
        sample("screen", JSONObject().put("state", "unlocked")); assertEquals(2, fired.size)
        sample("screen", JSONObject().put("state", "unlocked")); assertEquals(2, fired.size) // no change
    }

    // ---------------------------------------------------------- state gate

    @Test
    fun gateAndUnevaluableBlocks() {
        state["battery.level"] = battery(50)
        state["screen"] = JSONObject().put("state", "on")
        register(trig("bat", "battery.level") {
            put("params", JSONObject().put("below", 20))
            put("when", JSONArray().put(JSONObject().put("type", "screen").put("state", "off")))
        })
        sample("battery.level", battery(19)); assertTrue(fired.isEmpty())   // gate: screen on
        state["screen"] = JSONObject().put("state", "off")
        sample("battery.level", battery(25))                                // reset side
        sample("battery.level", battery(18)); assertEquals(1, fired.size)   // gate now holds
    }

    @Test
    fun unevaluablePredicateDoesNotHold() {
        state["battery.level"] = battery(50)  // no "power" state at all
        register(trig("bat", "battery.level") {
            put("params", JSONObject().put("below", 20))
            put("when", JSONArray().put(JSONObject().put("type", "power").put("state", "connected")))
        })
        sample("battery.level", battery(19)); assertTrue(fired.isEmpty())
    }

    // ----------------------------------------------------------- edges

    @Test
    fun stateEdgeRiseAndFall() {
        state["battery.level"] = battery(50)
        register(trig("edge", "state.edge") {
            put("params", JSONObject()
                .put("when", JSONArray().put(JSONObject().put("type", "battery.level").put("below", 20)))
                .put("edge", "both"))
        })
        state["battery.level"] = battery(19); rt.onSample("id", "battery.level", battery(19))
        assertEquals(1, fired.size)
        assertEquals("rise", fired[0].second.getString("edge"))
        assertTrue(fired[0].second.getBoolean("holds"))
        state["battery.level"] = battery(50); rt.onSample("id", "battery.level", battery(50))
        assertEquals(2, fired.size)
        assertEquals("fall", fired[1].second.getString("edge"))
    }

    // ---------------------------------------------------------- throttle

    @Test
    fun throttleSuppressesWithinWindow() {
        state["battery.level"] = battery(50)
        register(trig("bat", "battery.level") {
            put("params", JSONObject().put("below", 20)); put("throttle_s", 60)
        })
        sample("battery.level", battery(19)); assertEquals(1, fired.size)   // t=1000
        sample("battery.level", battery(50)); sample("battery.level", battery(18))
        assertEquals(1, fired.size)                                         // within 60s
        clock = 61_000
        sample("battery.level", battery(50)); sample("battery.level", battery(17))
        assertEquals(2, fired.size)                                         // window elapsed
    }

    // ------------------------------------------------------- time.window

    @Test
    fun timeWindowGatesCivilTime() {
        // A wrapping 22:00-06:00 window, evaluated in UTC.
        register(trig("nb", "boot") {
            put("when", JSONArray().put(JSONObject().put("type", "time.window")
                .put("after", "22:00").put("before", "06:00")))
        })
        clock = Instant.parse("2026-01-05T23:30:00Z").toEpochMilli()       // inside
        rt.onExternal("id", "boot", JSONObject()); assertEquals(1, fired.size)
        clock = Instant.parse("2026-01-05T12:00:00Z").toEpochMilli()       // outside
        rt.onExternal("id", "boot", JSONObject()); assertEquals(1, fired.size)
        clock = Instant.parse("2026-01-06T02:00:00Z").toEpochMilli()       // inside (wrapped)
        rt.onExternal("id", "boot", JSONObject()); assertEquals(2, fired.size)
    }

    // ------------------------------------------------------- external

    @Test
    fun externalFiresWithoutBaseline() {
        register(trig("m", "manual"))
        rt.onExternal("id", "manual", JSONObject().put("source", "tap"))
        assertEquals(listOf("m"), firedIds())
        assertEquals("tap", fired[0].second.getString("source"))
    }

    @Test
    fun fireManualFiresOnlyNamedTrigger() {
        register(trig("m1", "manual"), trig("m2", "manual"))
        rt.fireManual("id", "m1", JSONObject().put("source", "emacs"))
        assertEquals(listOf("m1"), firedIds()) // not m2
    }

    // -------------------------------------- engine integration: real event

    @Test
    fun triggerFiredReachesEventPipeline() {
        val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
        val katPid = "101112131415161718191a1b1c1d1e1f"
        val katCn = "202122232425262728292a2b2c2d2e2f"
        val katSn = "303132333435363738393a3b3c3d3e3f"
        val out = mutableListOf<JSONObject>()
        val limits = JSONObject()
            .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
            .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
            .put("max_surfaces", 16).put("max_surface_ids", 1024)
            .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
            .put("max_capture_fields", 64).put("max_trigger_responses", 4)
        val report = JSONObject().put("caps", JSONArray()).put("trigger_caps", JSONArray())
            .put("permissions", JSONObject())
            .put("trigger_types", JSONArray(listOf("battery.level")))
            .put("state_types", JSONArray(listOf("battery.level")))
            .put("trackable_state_types", JSONArray(listOf("battery.level")))
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1", pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("triggers"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray()).put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits, deviceReport = report, nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.triggerStateProvider = { if (it == "battery.level") battery(50) else null }
        fun frame(m: JSONObject) = encodeFrame(m.toString())
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("triggers")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        engine.feed(frame(request("s1", "triggers.set", JSONObject().put("triggers",
            JSONArray().put(trig("bat", "battery.level") {
                put("params", JSONObject().put("below", 20)) })))))
        // A crossing produces a live drop trigger.fired as an event.action.
        engine.observeTriggerSample("battery.level", battery(19))
        val event = out.last { it.opt("method") == "event.action" }.getJSONObject("params")
        assertEquals("trigger.fired", event.getString("action"))
        assertEquals("bat", event.getJSONObject("args").getString("id"))
        assertEquals(19, event.getJSONObject("args").getJSONObject("data").getInt("level"))
    }
}
