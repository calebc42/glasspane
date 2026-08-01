// SPDX-License-Identifier: GPL-3.0-or-later
// W8 conformance: durable trigger registrations (SPEC 21.1/21.2). Registrations
// and their runtime records (throttle floor, one-shot/boot receipts, schedule
// anchor) survive a process death; baselines are deliberately NOT persisted
// (SPEC 21.5 re-establishes them silently after restart); the unchanged-id
// carry-forward is preserved across a reload; a storage failure restores the
// prior set.
package com.calebc42.ebp.wire

import java.io.File
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class TriggerBackingTest {

    @get:Rule
    val tmp = TemporaryFolder()

    // A minimal normalized entry (the store stores validated, normalized ones).
    private fun entry(id: String, below: Int = 20) = buildJsonObject {
        put("id", id)
        put("type", "battery.level")
        putJsonObject("params") { put("below", below) }
        put("when", JsonArray(emptyList()))
        put("policy", "drop")
        put("on_fire", JsonArray(emptyList()))
    }

    @Test
    fun entriesAndRecordsSurviveReloadButBaselinesDoNot() {
        val file = File(tmp.root, "triggers.json")
        val a = TriggerStore(FileTriggerBacking(file))
        a.replace("id", listOf(entry("t1"), entry("t2")))
        a.registration("id", "t1")!!.apply {
            throttleFloorMs = 5000; oneShotCompleted = true; bootGeneration = "boot#7"
            baselines["side"] = true
        }
        a.persistRecords()
        // Process death: a fresh store over the same file restores it all.
        val b = TriggerStore(FileTriggerBacking(file))
        assertEquals(2, b.count("id"))
        val r = b.registration("id", "t1")!!
        assertEquals(5000L, r.throttleFloorMs)
        assertTrue(r.oneShotCompleted)
        assertEquals("boot#7", r.bootGeneration)
        assertTrue(r.baselines.isEmpty()) // SPEC 21.5: re-established on arm, not persisted
    }

    @Test
    fun carryForwardKeepsRecordsAcrossReloadChangedDrops() {
        val file = File(tmp.root, "triggers.json")
        val a = TriggerStore(FileTriggerBacking(file))
        a.replace("id", listOf(entry("t1")))
        a.registration("id", "t1")!!.throttleFloorMs = 9000
        // Re-push the SAME normalized entry: carry-forward keeps the record,
        // and replace persists it (SPEC 21.1).
        a.replace("id", listOf(entry("t1")))
        assertEquals(9000L, a.registration("id", "t1")!!.throttleFloorMs)
        assertEquals(9000L, TriggerStore(FileTriggerBacking(file))
            .registration("id", "t1")!!.throttleFloorMs)
        // A changed entry is a fresh registration — records discarded.
        a.replace("id", listOf(entry("t1", below = 15)))
        assertNull(a.registration("id", "t1")!!.throttleFloorMs)
        assertNull(TriggerStore(FileTriggerBacking(file))
            .registration("id", "t1")!!.throttleFloorMs)
    }

    private class FlakyTriggerBacking : TriggerBacking {
        var fail = false
        var state = TriggerState(emptyMap())
        override fun load() = state
        override fun replace(state: TriggerState) {
            if (fail) throw java.io.IOException("disk gone")
            this.state = state
        }
    }

    @Test
    fun storageFailureRestoresPriorSetAndThrows() {
        val backing = FlakyTriggerBacking()
        val store = TriggerStore(backing)
        store.replace("id", listOf(entry("t1")))
        backing.fail = true
        var threw = false
        try {
            store.replace("id", listOf(entry("t2")))
        } catch (e: Exception) { threw = true }
        assertTrue(threw)
        assertEquals(1, store.count("id"))       // prior set still in force
        assertTrue(store.registration("id", "t1") != null)
        assertNull(store.registration("id", "t2"))
    }

    @Test
    fun emptyReplaceClearsIdentityAndPersists() {
        val file = File(tmp.root, "triggers.json")
        val a = TriggerStore(FileTriggerBacking(file))
        a.replace("id", listOf(entry("t1")))
        a.replace("id", emptyList())
        assertEquals(0, a.count("id"))
        assertEquals(0, TriggerStore(FileTriggerBacking(file)).count("id"))
    }
}
