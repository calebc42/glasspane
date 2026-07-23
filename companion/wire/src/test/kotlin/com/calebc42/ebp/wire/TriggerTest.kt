// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: the device-trigger module replace-set (SPEC 21.1/21.5/21.7).
// triggers.set validation (closed trigger + type-param + predicate schemas,
// policy/ttl/dedupe cross-rules, on_fire structure, resource limits), atomic
// {count}/1101 dispatch, and the SPEC 21.1 unchanged-id runtime-record
// carry-forward that rides on SPEC 4.3 equality of normalized entries.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class TriggerTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private val caps = TriggerCaps(
        triggerTypes = setOf("battery.level", "screen", "time", "power", "boot",
            "sms.received", "state.edge", "manual", "network"),
        stateTypes = setOf("battery.level", "screen", "power"),
        trackableStateTypes = setOf("battery.level", "screen", "power"),
        triggerCaps = setOf("vibrate"),
        maxResponses = 4)

    private fun limits() = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64).put("max_trigger_responses", 4)
        .put("max_triggers", 3).put("max_device_report_bytes", 8192)

    private fun report() = JSONObject()
        .put("caps", JSONArray()).put("trigger_caps", JSONArray(listOf("vibrate")))
        .put("permissions", JSONObject())
        .put("trigger_types", JSONArray(caps.triggerTypes.toList()))
        .put("state_types", JSONArray(caps.stateTypes.toList()))
        .put("trackable_state_types", JSONArray(caps.trackableStateTypes.toList()))

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())
    private fun response(out: List<JSONObject>, id: String) = out.last { it.opt("id") == id }

    private fun engine(out: MutableList<JSONObject>, grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("triggers") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("triggers"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray()).put("builtins", JSONArray())
                .put("features", JSONArray())),
            limits = limits(), deviceReport = report(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        return engine
    }

    private fun set(engine: CompanionEngine, id: String, vararg triggers: JSONObject) =
        engine.feed(frame(request(id, "triggers.set", JSONObject()
            .put("triggers", JSONArray(triggers.toList())))))

    private fun reason(out: List<JSONObject>, id: String) =
        response(out, id).getJSONObject("error").getJSONObject("data").getString("reason")

    private fun count(out: List<JSONObject>, id: String) =
        response(out, id).getJSONObject("result").getInt("count")

    private fun trig(id: String, type: String, block: JSONObject.() -> Unit = {}) =
        JSONObject().put("id", id).put("type", type).apply(block)

    // ---------------------------------------------------------- dispatch

    @Test
    fun acceptedSetReturnsCount() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        set(engine, "s1",
            trig("battery-low", "battery.level") {
                put("params", JSONObject().put("below", 20))
                put("when", JSONArray().put(JSONObject().put("type", "screen").put("state", "off")))
                put("policy", "queue").put("ttl_s", 86_400).put("dedupe", "battery-low")
                put("throttle_s", 3_600)
                put("on_fire", JSONArray().put(JSONObject().put("notify",
                    JSONObject().put("text", "Battery \${data.level}%"))))
            },
            trig("boot-hi", "boot"))
        assertEquals(2, count(out, "s1"))
    }

    @Test
    fun ungrantedIsMethodNotFound() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, grant = false)
        set(engine, "s1", trig("t", "boot"))
        assertEquals(-32601, response(out, "s1").getJSONObject("error").getInt("code"))
    }

    @Test
    fun overLimitSetIsRejected() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        // max_triggers is 3; a 4-entry set is rejected, not truncated (SPEC 21.1).
        set(engine, "s1", trig("a", "boot"), trig("b", "boot"),
            trig("c", "boot"), trig("d", "boot"))
        assertEquals(1101, response(out, "s1").getJSONObject("error").getInt("code"))
        assertEquals("trigger-limit", reason(out, "s1"))
        assertEquals(0, engine.triggers.count(katPid)) // nothing armed
    }

    @Test
    fun emptySetClears() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        set(engine, "s1", trig("t", "boot"))
        assertEquals(1, count(out, "s1"))
        engine.feed(frame(request("s2", "triggers.set",
            JSONObject().put("triggers", JSONArray()))))
        assertEquals(0, count(out, "s2"))
    }

    @Test
    fun rejectionLeavesPriorSetArmed() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        set(engine, "s1", trig("keep", "boot"))
        assertEquals(1, count(out, "s1"))
        // A set with an unknown type is rejected atomically; the prior stays.
        set(engine, "s2", trig("keep", "boot"), trig("bad", "no.such.type"))
        assertEquals(1101, response(out, "s2").getJSONObject("error").getInt("code"))
        assertEquals("triggers-rejected", response(out, "s2").getJSONObject("error")
            .getJSONObject("data").getString("kind"))
        assertEquals(1, engine.triggers.count(katPid))
        assertTrue(engine.triggers.registration(katPid, "keep") != null)
    }

    // -------------------------------------------------- validation reject

    @Test
    fun rejects() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        var n = 0
        fun bad(reason: String, vararg t: JSONObject) {
            set(engine, "b${n++}", *t)
            assertEquals("case ${n - 1}", 1101, response(out, "b${n - 1}").getJSONObject("error").getInt("code"))
        }
        bad("unknown type", trig("x", "no.such"))
        bad("dup id", trig("x", "boot"), trig("x", "boot"))
        bad("unknown member", trig("x", "boot").apply { put("bogus", 1) })
        bad("queue needs ttl", trig("x", "boot").apply { put("policy", "queue") })
        bad("drop forbids ttl", trig("x", "boot").apply { put("ttl_s", 10) })
        bad("dedupe needs durable", trig("x", "boot").apply { put("dedupe", "d") })
        // SPEC 21.5: a sensitive sms.received/call.state must not queue plaintext
        // until the keystore seam exists — a durable policy is rejected.
        bad("sensitive needs drop", trig("x", "sms.received")
            .apply { put("policy", "queue").put("ttl_s", 3600) })
        bad("battery both", trig("x", "battery.level").apply {
            put("params", JSONObject().put("above", 10).put("below", 90)) })
        bad("battery range", trig("x", "battery.level").apply {
            put("params", JSONObject().put("below", 200)) })
        bad("time both", trig("x", "time").apply {
            put("params", JSONObject().put("at_ms", 1).put("every_s", 60)) })
        bad("every_s floor", trig("x", "time").apply {
            put("params", JSONObject().put("every_s", 59)) })
        bad("gate type not advertised", trig("x", "boot").apply {
            put("when", JSONArray().put(JSONObject().put("type", "network"))) })
        bad("bad enum", trig("x", "screen").apply {
            put("params", JSONObject().put("state", "sideways")) })
        bad("on_fire cap not trig", trig("x", "boot").apply {
            put("on_fire", JSONArray().put(JSONObject().put("cap", "flashlight"))) })
        bad("notify needs text", trig("x", "boot").apply {
            put("on_fire", JSONArray().put(JSONObject().put("notify", JSONObject()))) })
        bad("on_fire both", trig("x", "boot").apply {
            put("on_fire", JSONArray().put(JSONObject().put("cap", "vibrate")
                .put("notify", JSONObject().put("text", "x")))) })
        bad("over responses", trig("x", "boot").apply {
            val a = JSONArray()
            repeat(5) { a.put(JSONObject().put("notify", JSONObject().put("text", "x"))) }
            put("on_fire", a) })
        bad("id over 128 chars", trig("x".repeat(129), "boot")) // SPEC 4.4
        bad("state.edge non-trackable+timewindow", trig("x", "state.edge").apply {
            put("params", JSONObject().put("when", JSONArray()
                .put(JSONObject().put("type", "time.window")))) })
    }

    @Test
    fun timeWindowValidInGateNotInEdge() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        // time.window is accepted inside a trigger's when gate.
        set(engine, "s1", trig("x", "boot").apply {
            put("when", JSONArray().put(JSONObject().put("type", "time.window")
                .put("after", "22:00").put("before", "06:00")))
        })
        assertEquals(1, count(out, "s1"))
    }

    // ------------------------------------- normalization + carry-forward

    @Test
    fun defaultsMaterializeForEquality() {
        // Two logically-identical entries differing only by omitted defaults
        // normalize equal (SPEC 4.3), so canonicalEquals holds.
        val bare = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(trig("t", "sms.received"))), caps).single()
        val explicit = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(trig("t", "sms.received").apply {
                put("params", JSONObject().put("include_body", false))
                put("when", JSONArray()).put("policy", "drop").put("on_fire", JSONArray())
            })), caps).single()
        assertTrue(TriggerStore.canonicalEquals(bare, explicit))
        // A real difference is not equal.
        val bodyOn = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(trig("t", "sms.received").apply {
                put("params", JSONObject().put("include_body", true)) })), caps).single()
        assertFalse(TriggerStore.canonicalEquals(bare, bodyOn))
    }

    @Test
    fun unchangedIdCarriesRuntimeRecords() {
        val store = TriggerStore()
        val v1 = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(trig("t", "sms.received"))), caps)
        store.replace(katPid, v1)
        val reg = store.registration(katPid, "t")!!
        reg.throttleFloorMs = 12_345          // a runtime record the runtime set
        // Re-send an equivalent set (defaults spelled out): id unchanged.
        val v2 = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(trig("t", "sms.received").apply {
                put("params", JSONObject().put("include_body", false)) })), caps)
        store.replace(katPid, v2)
        assertSame(reg, store.registration(katPid, "t"))          // same record
        assertEquals(12_345L, store.registration(katPid, "t")!!.throttleFloorMs)
        // Change the trigger: the record is discarded (fresh registration).
        val v3 = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(trig("t", "sms.received").apply {
                put("params", JSONObject().put("include_body", true)) })), caps)
        store.replace(katPid, v3)
        assertNotSame(reg, store.registration(katPid, "t"))
        assertEquals(null, store.registration(katPid, "t")!!.throttleFloorMs)
    }
}
