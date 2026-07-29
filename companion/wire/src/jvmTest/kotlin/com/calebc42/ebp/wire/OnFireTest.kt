// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: on_fire local responses (SPEC 21.4). Substituted execution
// in authored order at admission, per-entry failure isolation, the sensitive
// source-to-sink approval gate, and the forbidden-cap rule — all install-time
// or fire-time behaviors the runtime and validator must enforce.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OnFireTest {

    private fun caps(approved: Boolean = false) = TriggerCaps(
        triggerTypes = setOf("battery.level", "sms.received", "manual"),
        stateTypes = setOf("battery.level"),
        trackableStateTypes = setOf("battery.level"),
        triggerCaps = setOf("vibrate"), maxResponses = 4,
        sensitiveSubstitutionApproved = approved)

    private val state = HashMap<String, JSONObject>()
    private val ran = mutableListOf<JSONObject>()
    private val store = TriggerStore()
    private val rt = TriggerRuntime(store, { 1_000L }, { java.time.ZoneId.of("UTC") },
        { state[it] }, emit = { _, _, commit -> commit() }, onFire = { ran.add(it) })

    private fun trig(id: String, type: String, block: JSONObject.() -> Unit = {}) =
        JSONObject().put("id", id).put("type", type).apply(block)

    private fun register(caps: TriggerCaps, vararg triggers: JSONObject) {
        val entries = TriggerValidator.validateSet(
            JSONObject().put("triggers", JSONArray(triggers.toList())), caps)
        store.replace("id", entries)
        rt.armBaselines("id")
    }

    private fun battery(level: Int) = JSONObject().put("level", level)

    // ------------------------------------------------ runtime execution

    @Test
    fun onFireSubstitutesInOrder() {
        state["battery.level"] = battery(50)
        register(caps(), trig("bat", "battery.level") {
            put("params", JSONObject().put("below", 20))
            put("on_fire", JSONArray()
                .put(JSONObject().put("notify", JSONObject().put("text", "Battery \${data.level}%")))
                .put(JSONObject().put("cap", "vibrate").put("args", JSONObject().put("ms", 200))))
        })
        state["battery.level"] = battery(19); rt.onSample("id", "battery.level", battery(19))
        assertEquals(2, ran.size)
        assertEquals("Battery 19%", ran[0].getJSONObject("notify").getString("text"))
        assertEquals("vibrate", ran[1].getString("cap"))
        assertEquals(200, ran[1].getJSONObject("args").getInt("ms")) // number untouched
    }

    @Test
    fun failingEntryIsIsolated() {
        // A throw on the first entry must not stop the second (SPEC 21.4).
        val seen = mutableListOf<String>()
        val rt2 = TriggerRuntime(store, { 1_000L }, { java.time.ZoneId.of("UTC") },
            { state[it] }, emit = { _, _, commit -> commit() }, onFire = { e ->
                if (e.has("notify")) throw RuntimeException("boom")
                seen.add(e.getString("cap"))
            })
        register(caps(), trig("bat", "battery.level") {
            put("params", JSONObject().put("below", 20))
            put("on_fire", JSONArray()
                .put(JSONObject().put("notify", JSONObject().put("text", "x")))
                .put(JSONObject().put("cap", "vibrate")))
        })
        state["battery.level"] = battery(50); rt2.armBaselines("id")
        state["battery.level"] = battery(19); rt2.onSample("id", "battery.level", battery(19))
        assertEquals(listOf("vibrate"), seen) // second entry still ran
    }

    @Test
    fun failedDurableCommitRunsNoOnFireAndKeepsThrottle() {
        // SPEC 21.2: if the durable transaction fails, emit never calls commit,
        // so no local response runs and no throttle floor is consumed.
        state["battery.level"] = battery(50)
        val store2 = TriggerStore()
        val ran2 = mutableListOf<JSONObject>()
        val rt3 = TriggerRuntime(store2, { 1_000L }, { java.time.ZoneId.of("UTC") },
            { state[it] }, emit = { _, _, _ -> /* QueueFull: never commit */ },
            onFire = { ran2.add(it) })
        val entries = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(trig("bat", "battery.level") {
                put("params", JSONObject().put("below", 20)); put("throttle_s", 60)
                put("on_fire", JSONArray().put(JSONObject().put("notify",
                    JSONObject().put("text", "x"))))
            })), caps())
        store2.replace("id", entries)
        rt3.armBaselines("id")
        state["battery.level"] = battery(19); rt3.onSample("id", "battery.level", battery(19))
        assertTrue(ran2.isEmpty())                                         // no on_fire
        assertEquals(null, store2.registration("id", "bat")!!.throttleFloorMs) // no throttle
    }

    // -------------------------------------------- install-time validation

    @Test
    fun sensitiveSubstitutionNeedsApproval() {
        val sms = trig("s", "sms.received") {
            put("on_fire", JSONArray().put(JSONObject().put("notify",
                JSONObject().put("text", "From \${data.from}: \${data.body}"))))
        }
        // Without approval, the set is rejected.
        var rejected = false
        try {
            TriggerValidator.validateSet(JSONObject().put("triggers",
                JSONArray().put(sms)), caps(approved = false))
        } catch (e: ContentInvalid) { rejected = true }
        assertTrue(rejected)
        // With approval, it validates.
        val ok = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(sms)), caps(approved = true))
        assertEquals(1, ok.size)
    }

    @Test
    fun nonSensitiveDataNeedsNoApproval() {
        // battery.level data into a sink is fine without approval.
        val ok = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(trig("b", "battery.level") {
                put("params", JSONObject().put("below", 20))
                put("on_fire", JSONArray().put(JSONObject().put("notify",
                    JSONObject().put("text", "Battery \${data.level}%"))))
            })), caps(approved = false))
        assertEquals(1, ok.size)
        // And a sensitive source that does NOT substitute data is fine too.
        val staticSms = TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray().put(trig("s", "sms.received") {
                put("on_fire", JSONArray().put(JSONObject().put("notify",
                    JSONObject().put("text", "New message"))))
            })), caps(approved = false))
        assertEquals(1, staticSms.size)
    }

    @Test
    fun forbiddenCapRejectedInOnFire() {
        val badCaps = caps().copy(triggerCaps = setOf("vibrate", "clipboard.read"))
        var rejected = false
        try {
            TriggerValidator.validateSet(JSONObject().put("triggers", JSONArray().put(
                trig("b", "manual") {
                    put("on_fire", JSONArray().put(JSONObject().put("cap", "clipboard.read")))
                })), badCaps)
        } catch (e: ContentInvalid) { rejected = true }
        assertTrue(rejected) // clipboard.read is forbidden in on_fire even if advertised
    }
}
