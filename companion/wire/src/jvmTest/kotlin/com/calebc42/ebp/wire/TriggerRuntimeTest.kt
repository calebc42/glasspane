// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: the trigger firing runtime (SPEC 21.2/21.3/21.5/21.6).
// Silent baselining and crossing/transition/edge detection, the state gate
// (flat AND, unevaluable = not holding), throttle, civil-time windows, and
// the drop trigger.fired event actually reaching the pipeline. The clock,
// state, and emit are injected, so the semantics are exercised with no device.
package com.calebc42.ebp.wire

import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
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
    private val state = HashMap<String, JsonObject>()
    private val fired = mutableListOf<Pair<String, JsonObject>>()
    private val store = TriggerStore()
    private val rt = TriggerRuntime(store, { clock }, { ZoneId.of("UTC") },
        { state[it] }, emit = { reg, data, commit ->
            commit(); fired.add(reg.entry.reqString("id") to data) })

    private fun trig(id: String, type: String, block: JsonObjectBuilder.() -> Unit = {}) =
        buildJsonObject { put("id", id); put("type", type); block() }

    private fun register(vararg triggers: JsonObject) {
        val entries = TriggerValidator.validateSet(
            buildJsonObject { put("triggers", JsonArray(triggers.toList())) }, caps)
        store.replace("id", entries)
        rt.armBaselines("id")
    }

    private fun battery(level: Int) = buildJsonObject { put("level", level) }
    private fun sample(type: String, s: JsonObject) { state[type] = s; rt.onSample("id", type, s) }
    private fun firedIds() = fired.map { it.first }

    // ------------------------------------------- crossing + silent baseline

    @Test
    fun batteryFiresOnCrossingNotSticky() {
        state["battery.level"] = battery(50)
        register(trig("bat", "battery.level") { putJsonObject("params") { put("below", 20) } })
        sample("battery.level", battery(50)); assertTrue(fired.isEmpty())   // sticky baseline
        sample("battery.level", battery(19)); assertEquals(1, fired.size)   // crossing in
        assertEquals(19L, integralLongOrNull(fired[0].second["level"]))
        sample("battery.level", battery(15)); assertEquals(1, fired.size)   // already below
        sample("battery.level", battery(25)); assertEquals(1, fired.size)   // leaving
        sample("battery.level", battery(10)); assertEquals(2, fired.size)   // re-cross
    }

    @Test
    fun armedBelowNeverFiresWithoutLeaving() {
        // Arming while already on the configured side must not fire; a sticky
        // repeat of that side must not either (SPEC 21.5).
        state["battery.level"] = battery(10)
        register(trig("bat", "battery.level") { putJsonObject("params") { put("below", 20) } })
        sample("battery.level", battery(10)); assertTrue(fired.isEmpty())
        sample("battery.level", battery(5)); assertTrue(fired.isEmpty())
    }

    @Test
    fun screenFiltersTransitionIntoState() {
        state["screen"] = buildJsonObject { put("state", "on") }
        register(trig("scr", "screen") { putJsonObject("params") { put("state", "off") } })
        sample("screen", buildJsonObject { put("state", "off") }); assertEquals(1, fired.size)
        sample("screen", buildJsonObject { put("state", "off") }); assertEquals(1, fired.size) // sticky
        sample("screen", buildJsonObject { put("state", "on") }); assertEquals(1, fired.size)
        sample("screen", buildJsonObject { put("state", "off") }); assertEquals(2, fired.size)
    }

    @Test
    fun unfilteredScreenFiresOnAnyChange() {
        state["screen"] = buildJsonObject { put("state", "on") }
        register(trig("scr", "screen"))
        sample("screen", buildJsonObject { put("state", "off") }); assertEquals(1, fired.size)
        sample("screen", buildJsonObject { put("state", "unlocked") }); assertEquals(2, fired.size)
        sample("screen", buildJsonObject { put("state", "unlocked") }); assertEquals(2, fired.size) // no change
    }

    // ---------------------------------------------------------- state gate

    @Test
    fun gateAndUnevaluableBlocks() {
        state["battery.level"] = battery(50)
        state["screen"] = buildJsonObject { put("state", "on") }
        register(trig("bat", "battery.level") {
            putJsonObject("params") { put("below", 20) }
            putJsonArray("when") { addJsonObject { put("type", "screen"); put("state", "off") } }
        })
        sample("battery.level", battery(19)); assertTrue(fired.isEmpty())   // gate: screen on
        state["screen"] = buildJsonObject { put("state", "off") }
        sample("battery.level", battery(25))                                // reset side
        sample("battery.level", battery(18)); assertEquals(1, fired.size)   // gate now holds
    }

    @Test
    fun unevaluablePredicateDoesNotHold() {
        state["battery.level"] = battery(50)  // no "power" state at all
        register(trig("bat", "battery.level") {
            putJsonObject("params") { put("below", 20) }
            putJsonArray("when") { addJsonObject { put("type", "power"); put("state", "connected") } }
        })
        sample("battery.level", battery(19)); assertTrue(fired.isEmpty())
    }

    // ----------------------------------------------------------- edges

    @Test
    fun stateEdgeRiseAndFall() {
        state["battery.level"] = battery(50)
        register(trig("edge", "state.edge") {
            putJsonObject("params") {
                putJsonArray("when") { addJsonObject { put("type", "battery.level"); put("below", 20) } }
                put("edge", "both")
            }
        })
        state["battery.level"] = battery(19); rt.onSample("id", "battery.level", battery(19))
        assertEquals(1, fired.size)
        assertEquals("rise", fired[0].second.reqString("edge"))
        assertTrue(fired[0].second.boolOr("holds"))
        state["battery.level"] = battery(50); rt.onSample("id", "battery.level", battery(50))
        assertEquals(2, fired.size)
        assertEquals("fall", fired[1].second.reqString("edge"))
    }

    // ---------------------------------------------------------- throttle

    @Test
    fun throttleSuppressesWithinWindow() {
        state["battery.level"] = battery(50)
        register(trig("bat", "battery.level") {
            putJsonObject("params") { put("below", 20) }; put("throttle_s", 60)
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
            putJsonArray("when") { addJsonObject {
                put("type", "time.window"); put("after", "22:00"); put("before", "06:00") } }
        })
        clock = Instant.parse("2026-01-05T23:30:00Z").toEpochMilli()       // inside
        rt.onExternal("id", "boot", JsonObject(emptyMap())); assertEquals(1, fired.size)
        clock = Instant.parse("2026-01-05T12:00:00Z").toEpochMilli()       // outside
        rt.onExternal("id", "boot", JsonObject(emptyMap())); assertEquals(1, fired.size)
        clock = Instant.parse("2026-01-06T02:00:00Z").toEpochMilli()       // inside (wrapped)
        rt.onExternal("id", "boot", JsonObject(emptyMap())); assertEquals(2, fired.size)
    }

    // ------------------------------------------------------- external

    @Test
    fun externalFiresWithoutBaseline() {
        register(trig("m", "manual"))
        rt.onExternal("id", "manual", buildJsonObject { put("source", "tap") })
        assertEquals(listOf("m"), firedIds())
        assertEquals("tap", fired[0].second.reqString("source"))
    }

    @Test
    fun fireManualFiresOnlyNamedTrigger() {
        register(trig("m1", "manual"), trig("m2", "manual"))
        rt.fireManual("id", "m1", buildJsonObject { put("source", "emacs") })
        assertEquals(listOf("m1"), firedIds()) // not m2
    }

    // -------------------------------------- engine integration: real event

    @Test
    fun triggerFiredReachesEventPipeline() {
        val out = mutableListOf<JsonObject>()
        val report = buildJsonObject {
            put("caps", JsonArray(emptyList()))
            put("trigger_caps", JsonArray(emptyList()))
            put("permissions", JsonObject(emptyMap()))
            put("trigger_types", JsonArray(listOf("battery.level").map(::JsonPrimitive)))
            put("state_types", JsonArray(listOf("battery.level").map(::JsonPrimitive)))
            put("trackable_state_types", JsonArray(listOf("battery.level").map(::JsonPrimitive)))
        }
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1", pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("triggers"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(NODE_SCHEMA.keys.map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_trigger_responses" to 4,
                "max_rich_spans" to 4096, "max_table_cells" to 4096),
            deviceReport = report, nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.triggerStateProvider = { if (it == "battery.level") battery(50) else null }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("triggers")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        engine.feed(frame(request("s1", "triggers.set", buildJsonObject {
            putJsonArray("triggers") {
                add(trig("bat", "battery.level") {
                    putJsonObject("params") { put("below", 20) } })
            }
        })))
        // A crossing produces a live drop trigger.fired as an event.action.
        engine.observeTriggerSample("battery.level", battery(19))
        val event = out.events().last().reqObj("params")
        assertEquals("trigger.fired", event.reqString("action"))
        assertEquals("bat", event.reqObj("args").reqString("id"))
        assertEquals(19L, integralLongOrNull(event.reqObj("args").reqObj("data")["level"]))
    }
}
