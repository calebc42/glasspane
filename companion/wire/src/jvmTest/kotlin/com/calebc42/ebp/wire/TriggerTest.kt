// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: the device-trigger module replace-set (SPEC 21.1/21.5/21.7).
// triggers.set validation (closed trigger + type-param + predicate schemas,
// policy/ttl/dedupe cross-rules, on_fire structure, resource limits), atomic
// {count}/1101 dispatch, and the SPEC 21.1 unchanged-id runtime-record
// carry-forward that rides on SPEC 4.3 equality of normalized entries.
package com.calebc42.ebp.wire

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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class TriggerTest {

    private val caps = TriggerCaps(
        triggerTypes = setOf("battery.level", "screen", "time", "power", "boot",
            "sms.received", "state.edge", "manual", "network"),
        stateTypes = setOf("battery.level", "screen", "power"),
        trackableStateTypes = setOf("battery.level", "screen", "power"),
        triggerCaps = setOf("vibrate"),
        maxResponses = 4)

    private fun report() = buildJsonObject {
        put("caps", JsonArray(emptyList()))
        put("trigger_caps", JsonArray(listOf("vibrate").map(::JsonPrimitive)))
        put("permissions", JsonObject(emptyMap()))
        put("trigger_types", JsonArray(caps.triggerTypes.map(::JsonPrimitive)))
        put("state_types", JsonArray(caps.stateTypes.map(::JsonPrimitive)))
        put("trackable_state_types", JsonArray(caps.trackableStateTypes.map(::JsonPrimitive)))
    }

    private fun engine(out: MutableList<JsonObject>, grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("triggers") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("triggers"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(NODE_SCHEMA.keys.map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_triggers" to 3, "max_trigger_responses" to 4,
                "max_rich_spans" to 4096, "max_table_cells" to 4096,
                "max_device_report_bytes" to 8192),
            deviceReport = report(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        return engine
    }

    private fun set(engine: CompanionEngine, id: String, vararg triggers: JsonObject) =
        engine.feed(frame(request(id, "triggers.set", buildJsonObject {
            put("triggers", JsonArray(triggers.toList()))
        })))

    private fun reason(out: List<JsonObject>, id: String) =
        out.errorOf(id).reqObj("data").reqString("reason")

    private fun count(out: List<JsonObject>, id: String) =
        out.replyTo(id).reqObj("result").reqLong("count")

    private fun trig(id: String, type: String, block: JsonObjectBuilder.() -> Unit = {}) =
        buildJsonObject { put("id", id); put("type", type); block() }

    // ---------------------------------------------------------- dispatch

    @Test
    fun rescheduleThrowAfterCommitStillClaimsTheSet() {
        // LD-16: the set is durably committed and armed BEFORE the host's
        // alarm-reschedule callout runs. A throw there must not be reported
        // as -32603 "Storage failed" (Emacs would believe the PRIOR set is
        // in force while the new one is live) and must not skip the listener.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        var listened = 0
        engine.triggerListener = { _, _ -> listened++ }
        engine.firing.onTimeScheduleChanged = { throw IllegalStateException("alarm host down") }
        set(engine, "s1", trig("boot-hi", "boot"))
        assertEquals(1L, count(out, "s1"))
        assertEquals(1, listened)
    }

    @Test
    fun acceptedSetReturnsCount() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        set(engine, "s1",
            trig("battery-low", "battery.level") {
                putJsonObject("params") { put("below", 20) }
                putJsonArray("when") { addJsonObject { put("type", "screen"); put("state", "off") } }
                put("policy", "queue"); put("ttl_s", 86_400); put("dedupe", "battery-low")
                put("throttle_s", 3_600)
                putJsonArray("on_fire") { addJsonObject { putJsonObject("notify") {
                    put("text", "Battery \${data.level}%") } } }
            },
            trig("boot-hi", "boot"))
        assertEquals(2L, count(out, "s1"))
    }

    @Test
    fun ungrantedIsMethodNotFound() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, grant = false)
        set(engine, "s1", trig("t", "boot"))
        assertEquals(-32601L, out.errorOf("s1").reqLong("code"))
    }

    @Test
    fun overLimitSetIsRejected() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        // max_triggers is 3; a 4-entry set is rejected, not truncated (SPEC 21.1).
        set(engine, "s1", trig("a", "boot"), trig("b", "boot"),
            trig("c", "boot"), trig("d", "boot"))
        assertEquals(1101L, out.errorOf("s1").reqLong("code"))
        assertEquals("trigger-limit", reason(out, "s1"))
        assertEquals(0, engine.triggers.count(katPid)) // nothing armed
    }

    @Test
    fun emptySetClears() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        set(engine, "s1", trig("t", "boot"))
        assertEquals(1L, count(out, "s1"))
        engine.feed(frame(request("s2", "triggers.set",
            buildJsonObject { put("triggers", JsonArray(emptyList())) })))
        assertEquals(0L, count(out, "s2"))
    }

    @Test
    fun rejectionLeavesPriorSetArmed() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        set(engine, "s1", trig("keep", "boot"))
        assertEquals(1L, count(out, "s1"))
        // A set with an unknown type is rejected atomically; the prior stays.
        set(engine, "s2", trig("keep", "boot"), trig("bad", "no.such.type"))
        assertEquals(1101L, out.errorOf("s2").reqLong("code"))
        assertEquals("triggers-rejected", out.errorOf("s2").reqObj("data").reqString("kind"))
        assertEquals(1, engine.triggers.count(katPid))
        assertTrue(engine.triggers.registration(katPid, "keep") != null)
    }

    // -------------------------------------------------- validation reject

    @Test
    fun rejects() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        var n = 0
        fun bad(reason: String, vararg t: JsonObject) {
            set(engine, "b${n++}", *t)
            assertEquals("case ${n - 1}", 1101L, out.errorOf("b${n - 1}").reqLong("code"))
        }
        bad("unknown type", trig("x", "no.such"))
        bad("dup id", trig("x", "boot"), trig("x", "boot"))
        bad("unknown member", trig("x", "boot") { put("bogus", 1) })
        bad("queue needs ttl", trig("x", "boot") { put("policy", "queue") })
        bad("drop forbids ttl", trig("x", "boot") { put("ttl_s", 10) })
        bad("dedupe needs durable", trig("x", "boot") { put("dedupe", "d") })
        // SPEC 21.5: a sensitive sms.received/call.state must not queue plaintext
        // until the keystore seam exists — a durable policy is rejected.
        bad("sensitive needs drop", trig("x", "sms.received") {
            put("policy", "queue"); put("ttl_s", 3600) })
        bad("battery both", trig("x", "battery.level") {
            putJsonObject("params") { put("above", 10); put("below", 90) } })
        bad("battery range", trig("x", "battery.level") {
            putJsonObject("params") { put("below", 200) } })
        bad("time both", trig("x", "time") {
            putJsonObject("params") { put("at_ms", 1); put("every_s", 60) } })
        bad("every_s floor", trig("x", "time") {
            putJsonObject("params") { put("every_s", 59) } })
        bad("gate type not advertised", trig("x", "boot") {
            putJsonArray("when") { addJsonObject { put("type", "network") } } })
        bad("bad enum", trig("x", "screen") {
            putJsonObject("params") { put("state", "sideways") } })
        bad("on_fire cap not trig", trig("x", "boot") {
            putJsonArray("on_fire") { addJsonObject { put("cap", "flashlight") } } })
        bad("notify needs text", trig("x", "boot") {
            putJsonArray("on_fire") { addJsonObject { put("notify", JsonObject(emptyMap())) } } })
        bad("on_fire both", trig("x", "boot") {
            putJsonArray("on_fire") { addJsonObject { put("cap", "vibrate")
                putJsonObject("notify") { put("text", "x") } } } })
        bad("over responses", trig("x", "boot") {
            putJsonArray("on_fire") {
                repeat(5) { addJsonObject { putJsonObject("notify") { put("text", "x") } } }
            } })
        bad("id over 128 chars", trig("x".repeat(129), "boot")) // SPEC 4.4
        bad("state.edge non-trackable+timewindow", trig("x", "state.edge") {
            putJsonObject("params") { putJsonArray("when") {
                addJsonObject { put("type", "time.window") } } } })
    }

    @Test
    fun timeWindowValidInGateNotInEdge() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        // time.window is accepted inside a trigger's when gate.
        set(engine, "s1", trig("x", "boot") {
            putJsonArray("when") { addJsonObject { put("type", "time.window")
                put("after", "22:00"); put("before", "06:00") } }
        })
        assertEquals(1L, count(out, "s1"))
    }

    // ------------------------------------- normalization + carry-forward

    @Test
    fun defaultsMaterializeForEquality() {
        // Two logically-identical entries differing only by omitted defaults
        // normalize equal (SPEC 4.3), so canonicalEquals holds.
        val bare = TriggerValidator.validateSet(buildJsonObject {
            put("triggers", JsonArray(listOf(trig("t", "sms.received"))))
        }, caps).single()
        val explicit = TriggerValidator.validateSet(buildJsonObject {
            put("triggers", JsonArray(listOf(trig("t", "sms.received") {
                putJsonObject("params") { put("include_body", false) }
                put("when", JsonArray(emptyList())); put("policy", "drop")
                put("on_fire", JsonArray(emptyList()))
            })))
        }, caps).single()
        assertTrue(TriggerStore.canonicalEquals(bare, explicit))
        // A real difference is not equal.
        val bodyOn = TriggerValidator.validateSet(buildJsonObject {
            put("triggers", JsonArray(listOf(trig("t", "sms.received") {
                putJsonObject("params") { put("include_body", true) } })))
        }, caps).single()
        assertFalse(TriggerStore.canonicalEquals(bare, bodyOn))
    }

    @Test
    fun unchangedIdCarriesRuntimeRecords() {
        val store = TriggerStore()
        val v1 = TriggerValidator.validateSet(buildJsonObject {
            put("triggers", JsonArray(listOf(trig("t", "sms.received"))))
        }, caps)
        store.replace(katPid, v1)
        val reg = store.registration(katPid, "t")!!
        reg.throttleFloorMs = 12_345          // a runtime record the runtime set
        // Re-send an equivalent set (defaults spelled out): id unchanged.
        val v2 = TriggerValidator.validateSet(buildJsonObject {
            put("triggers", JsonArray(listOf(trig("t", "sms.received") {
                putJsonObject("params") { put("include_body", false) } })))
        }, caps)
        store.replace(katPid, v2)
        assertSame(reg, store.registration(katPid, "t"))          // same record
        assertEquals(12_345L, store.registration(katPid, "t")!!.throttleFloorMs)
        // Change the trigger: the record is discarded (fresh registration).
        val v3 = TriggerValidator.validateSet(buildJsonObject {
            put("triggers", JsonArray(listOf(trig("t", "sms.received") {
                putJsonObject("params") { put("include_body", true) } })))
        }, caps)
        store.replace(katPid, v3)
        assertNotSame(reg, store.registration(katPid, "t"))
        assertEquals(null, store.registration(katPid, "t")!!.throttleFloorMs)
    }

    @Test
    fun canonicalEqualsIgnoresNumberSpelling() {
        // P0 pre-swap pin (PLAN-rf2 §0.2 item 4). canonicalEquals decides
        // whether a re-`triggers.set` is the SAME registration and therefore
        // carries its runtime records forward. If a respelled number
        // (`60` vs `60.0`) ever compares unequal, the throttle floor and the
        // one-shot completion are dropped: the trigger double-fires, and a
        // completed one-shot re-arms. SPEC 4.3 equality is by VALUE.
        assertTrue(TriggerStore.canonicalEquals(
            buildJsonObject { put("throttle_s", 60) },
            buildJsonObject { put("throttle_s", 60.0) }))
        assertTrue(TriggerStore.canonicalEquals(
            buildJsonObject { put("a", JsonArray(listOf(JsonPrimitive(1), JsonPrimitive(2L)))) },
            buildJsonObject { put("a", JsonArray(listOf(JsonPrimitive(1.0), JsonPrimitive(2.0)))) }))
        // Type identity still holds across the string/number boundary.
        assertFalse(TriggerStore.canonicalEquals(
            buildJsonObject { put("ttl_s", 60) },
            buildJsonObject { put("ttl_s", "60") }))
        // And a real value difference is still a difference.
        assertFalse(TriggerStore.canonicalEquals(
            buildJsonObject { put("throttle_s", 60) },
            buildJsonObject { put("throttle_s", 61) }))
    }

}
