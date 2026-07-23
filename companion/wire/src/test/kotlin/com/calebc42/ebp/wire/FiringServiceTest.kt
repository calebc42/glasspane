// SPDX-License-Identifier: GPL-3.0-or-later
// W8 conformance: the device-lifetime firing service (SPEC 21.2). Triggers
// fire with NO live session and admit durably; the throttle floor persists so
// a restart produces no immediate duplicate; a QueueFull transaction runs no
// on_fire and consumes no throttle; and recovery clears a crashed pending-local
// marker and floors throttle from surviving queued events.
package com.calebc42.ebp.wire

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class FiringServiceTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private val caps = TriggerCaps(
        triggerTypes = setOf("battery.level", "manual"),
        stateTypes = setOf("battery.level"),
        trackableStateTypes = setOf("battery.level"),
        triggerCaps = setOf("vibrate"), maxResponses = 4)

    private fun trig(id: String, block: JSONObject.() -> Unit) =
        JSONObject().put("id", id).put("type", "battery.level")
            .put("params", JSONObject().put("below", 20)).apply(block)

    private fun entries(vararg t: JSONObject) =
        TriggerValidator.validateSet(JSONObject().put("triggers", JSONArray(t.toList())), caps)

    private fun battery(level: Int) = JSONObject().put("level", level)

    @Test
    fun firesWithNoSessionAndAdmitsDurablyRunningOnFire() {
        val storeFile = File(tmp.root, "t.json")
        val store = TriggerStore(FileTriggerBacking(storeFile))
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val notified = mutableListOf<JSONObject>()
        val state = hashMapOf<String, JSONObject>("battery.level" to battery(50))
        val service = TriggerFiringService(store, queue, 262_144, setOf("vibrate"))
        service.stateProvider = { state[it] }
        service.notifyListener = { notified.add(it) }
        // No engine attached (session == null).
        service.replaceSet("id", entries(trig("bat") {
            put("policy", "queue").put("ttl_s", 86_400)
            put("on_fire", JSONArray().put(JSONObject().put("notify",
                JSONObject().put("text", "low"))))
        }))
        state["battery.level"] = battery(19)
        service.observeSample("battery.level", battery(19))
        // Admitted durably, and its pending-local marker was cleared.
        assertEquals(1, queue.count())
        val ev = queue.head()!!.getJSONObject("event")
        assertEquals("trigger.fired", ev.getString("action"))
        assertEquals(19, ev.getJSONObject("args").getJSONObject("data").getInt("level"))
        assertTrue(!queue.headIsPendingLocal())
        // on_fire ran even with no session (SPEC 21.2).
        assertEquals(listOf("low"), notified.map { it.getString("text") })
        // Throttle floor persisted across a store reload.
        assertNotNull(TriggerStore(FileTriggerBacking(storeFile))
            .registration("id", "bat")!!.throttleFloorMs)
    }

    @Test
    fun throttleSurvivesServiceReconstruction() {
        val storeFile = File(tmp.root, "t.json")
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val state = hashMapOf<String, JSONObject>("battery.level" to battery(50))
        val store1 = TriggerStore(FileTriggerBacking(storeFile))
        val svc1 = TriggerFiringService(store1, queue, 262_144).also { it.stateProvider = { t -> state[t] } }
        svc1.replaceSet("id", entries(trig("bat") {
            put("policy", "drop"); put("throttle_s", 3_600)
        }))
        state["battery.level"] = battery(19); svc1.observeSample("battery.level", battery(19))
        // A fresh store + service over the same file (a restart): throttle
        // survives, so a re-cross inside the window does NOT fire again.
        val store2 = TriggerStore(FileTriggerBacking(storeFile))
        val fired2 = mutableListOf<String>()
        val svc2 = TriggerFiringService(store2, DurableQueue(MemoryQueueStore(), 256, 8_388_608), 262_144)
        svc2.stateProvider = { t -> state[t] }
        svc2.notifyListener = { fired2.add("x") }
        svc2.armAllBaselines()
        state["battery.level"] = battery(50); svc2.observeSample("battery.level", battery(50))
        state["battery.level"] = battery(18); svc2.observeSample("battery.level", battery(18))
        assertNotNull(store2.registration("id", "bat")!!.throttleFloorMs) // survived
    }

    @Test
    fun queueFullRunsNoOnFireAndNoThrottle() {
        val store = TriggerStore()
        // A queue at capacity: the next admit is QueueFull.
        val queue = DurableQueue(MemoryQueueStore(), 1, 8_388_608)
        queue.admit(JSONObject().put("occurred_at_ms", 0L), "queue", null, 3_600)
        val notified = mutableListOf<JSONObject>()
        val state = hashMapOf<String, JSONObject>("battery.level" to battery(50))
        val service = TriggerFiringService(store, queue, 262_144)
        service.stateProvider = { state[it] }
        service.notifyListener = { notified.add(it) }
        service.replaceSet("id", entries(trig("bat") {
            put("policy", "queue").put("ttl_s", 86_400)
            put("on_fire", JSONArray().put(JSONObject().put("notify",
                JSONObject().put("text", "low"))))
        }))
        state["battery.level"] = battery(19); service.observeSample("battery.level", battery(19))
        assertTrue(notified.isEmpty())                                       // no on_fire
        assertNull(store.registration("id", "bat")!!.throttleFloorMs)         // no throttle
    }

    @Test
    fun recoverClearsPendingLocalAndFloorsThrottle() {
        val store = TriggerStore()
        store.replace("id", entries(trig("bat") { put("policy", "queue").put("ttl_s", 86_400) }))
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        // Simulate a crash mid-transaction: a trigger.fired admitted with
        // pending_local still set, and the registration's throttle NOT persisted.
        val event = JSONObject().put("event_id", "e").put("action", "trigger.fired")
            .put("occurred_at_ms", 12_345L)
            .put("args", JSONObject().put("id", "bat").put("type", "battery.level")
                .put("data", battery(19)))
        queue.admit(event, "queue", null, 86_400, pendingLocal = true)
        assertTrue(queue.headIsPendingLocal())
        assertNull(store.registration("id", "bat")!!.throttleFloorMs)
        val service = TriggerFiringService(store, queue, 262_144)
        service.recover()
        assertTrue(!queue.headIsPendingLocal())                              // marker cleared
        assertEquals(12_345L, store.registration("id", "bat")!!.throttleFloorMs) // floored
    }

    private val timeCaps = TriggerCaps(
        triggerTypes = setOf("time"), stateTypes = emptySet(),
        trackableStateTypes = emptySet(), triggerCaps = emptySet(), maxResponses = 4)

    private fun timeEntries(id: String, params: JSONObject) =
        TriggerValidator.validateSet(JSONObject().put("triggers", JSONArray().put(
            JSONObject().put("id", id).put("type", "time").put("params", params)
                .put("policy", "queue").put("ttl_s", 86_400))), timeCaps)

    private fun firedEvent(id: String, occurred: Long) = JSONObject()
        .put("event_id", "e-$id").put("action", "trigger.fired")
        .put("occurred_at_ms", occurred)
        .put("args", JSONObject().put("id", id).put("type", "time").put("data", JSONObject()))

    private class ThrowOnReplace(
        private val delegate: TriggerBacking = MemoryTriggerBacking(),
        var throwNow: Boolean = false,
    ) : TriggerBacking {
        override fun load() = delegate.load()
        override fun replace(state: TriggerState) {
            if (throwNow) throw java.io.IOException("disk full")
            delegate.replace(state)
        }
    }

    @Test
    fun transactionBFailureRollsBackTheQueuedEvent() {
        // A committed (queue.admit), then B (persistRecords) fails: the event
        // record MUST be rolled back so a failed durable transaction never claims
        // remote admission, and no throttle is consumed (SPEC 21.2).
        val backing = ThrowOnReplace()
        val store = TriggerStore(backing)
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val state = hashMapOf<String, JSONObject>("battery.level" to battery(50))
        val service = TriggerFiringService(store, queue, 262_144)
            .also { it.stateProvider = { t -> state[t] } }
        service.replaceSet("id", entries(trig("bat") {
            put("policy", "queue").put("ttl_s", 86_400)
        }))
        backing.throwNow = true                                 // next persist (B) fails
        state["battery.level"] = battery(19)
        service.observeSample("battery.level", battery(19))
        assertEquals(0, queue.count())                          // A rolled back
        assertNull(store.registration("id", "bat")!!.throttleFloorMs) // throttle restored
    }

    @Test
    fun recoverReconstructsOneShotAndEverySMarkers() {
        // A torn A/B commit: the trigger.fired event is durably queued but the
        // registration record (oneShotCompleted / lastFireFloorMs) was lost to a
        // crash. recover() must re-assert both so a restart cannot re-fire an
        // exactly-once one-shot nor re-phase a repeat (SPEC 21.5).
        val storeFile = File(tmp.root, "t.json")
        val store = TriggerStore(FileTriggerBacking(storeFile))
        store.replace("os", timeEntries("os", JSONObject().put("at_ms", 9_999_999_999L)))
        store.replace("ev", timeEntries("ev", JSONObject().put("every_s", 60)))
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        queue.admit(firedEvent("os", 5_000L), "queue", null, 86_400)
        queue.admit(firedEvent("ev", 7_000L), "queue", null, 86_400)
        // Records lost: neither marker is set on disk before recovery.
        assertFalse(store.registration("os", "os")!!.oneShotCompleted)
        assertNull(store.registration("ev", "ev")!!.lastFireFloorMs)

        TriggerFiringService(store, queue, 262_144).recover()

        assertTrue(store.registration("os", "os")!!.oneShotCompleted)     // reconstructed
        assertEquals(7_000L, store.registration("ev", "ev")!!.lastFireFloorMs)
        // And both survive a store reload (persisted, not just in memory).
        val reloaded = TriggerStore(FileTriggerBacking(storeFile))
        assertTrue(reloaded.registration("os", "os")!!.oneShotCompleted)
        assertEquals(7_000L, reloaded.registration("ev", "ev")!!.lastFireFloorMs)
    }
}
