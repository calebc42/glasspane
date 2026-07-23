// SPDX-License-Identifier: GPL-3.0-or-later
// W8 conformance: scheduled + boot triggers (SPEC 21.5). A one-shot time.at_ms
// fires exactly once and never again; a boot registration fires at most once
// per device boot generation; a repeating time.every_s anchors its cadence at
// acceptance, coalesces every interval missed while the Companion was dead into
// a single occurrence (no catch-up burst), and advances its floor past the
// present so the next occurrence resumes on phase. timeSchedule() reports the
// host-armable next due per time entry, dropping a completed one-shot.
package com.calebc42.ebp.wire

import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TriggerScheduleTest {

    private val caps = TriggerCaps(
        triggerTypes = setOf("time", "boot", "manual"),
        stateTypes = emptySet(), trackableStateTypes = emptySet(),
        triggerCaps = emptySet(), maxResponses = 4)

    private var clock = 1_000L
    private var generation: String? = "1"
    private val fired = mutableListOf<Pair<String, JSONObject>>()
    private val store = TriggerStore()
    private val rt = TriggerRuntime(store, { clock }, ZoneId.of("UTC"), { null },
        emit = { reg, data, commit -> commit(); fired.add(reg.entry.getString("id") to data) },
        bootGeneration = { generation })

    private fun trig(id: String, type: String, block: JSONObject.() -> Unit = {}) =
        JSONObject().put("id", id).put("type", type).apply(block)

    private fun register(vararg triggers: JSONObject) {
        val entries = TriggerValidator.validateSet(
            JSONObject().put("triggers", JSONArray(triggers.toList())), caps)
        store.replace("id", entries)
        rt.armBaselines("id")
    }

    private fun reg(id: String) = store.registration("id", id)!!
    private fun firedIds() = fired.map { it.first }

    // ---------------------------------------------------- one-shot time.at_ms

    @Test
    fun oneShotAtMsFiresExactlyOnce() {
        register(trig("os", "time") { put("params", JSONObject().put("at_ms", 5_000)) })
        rt.fireScheduled("id", "os", JSONObject())
        rt.fireScheduled("id", "os", JSONObject())   // eligibility skips the repeat
        assertEquals(listOf("os"), firedIds())
        assertTrue(reg("os").oneShotCompleted)
    }

    // -------------------------------------------------------- boot generation

    @Test
    fun bootRecordsAtInstallAndFiresOnNextGeneration() {
        generation = "1"
        register(trig("b", "boot"))                     // arm records gen "1" silently
        assertEquals("1", reg("b").bootGeneration)
        rt.onExternal("id", "boot", JSONObject())        // same boot: must NOT fire
        assertEquals(0, fired.size)
        generation = "2"
        rt.onExternal("id", "boot", JSONObject())        // next boot: fires once
        assertEquals(1, fired.size)
        assertEquals("2", reg("b").bootGeneration)
        rt.onExternal("id", "boot", JSONObject())        // same gen again: no refire
        assertEquals(1, fired.size)
    }

    @Test
    fun bootSameGenerationProcessRestartCreatesNoOccurrence() {
        generation = "1"
        register(trig("b", "boot"))
        // A Companion process restart in the same boot re-arms baselines; the
        // recorded generation is kept, so no occurrence is created (SPEC 21.5).
        rt.armBaselines("id")
        assertEquals("1", reg("b").bootGeneration)
        rt.onExternal("id", "boot", JSONObject())
        assertEquals(0, fired.size)
    }

    @Test
    fun unknownGenerationLeavesBootUngated() {
        // A null generation (BOOT_COUNT unavailable) never gates — the receiver
        // is the sole once-per-boot guard, so each fed occurrence fires.
        generation = null
        register(trig("b", "boot"))
        rt.onExternal("id", "boot", JSONObject())
        rt.onExternal("id", "boot", JSONObject())
        assertEquals(2, fired.size)
    }

    // ----------------------------------------------- every_s coalescing

    @Test
    fun everySAnchorsAtAcceptanceAndFirstDueIsOneInterval() {
        clock = 1_000
        register(trig("ev", "time") { put("params", JSONObject().put("every_s", 60)) })
        // Arming anchors the cadence at acceptance; the first occurrence is one
        // interval later, never at arm time.
        assertEquals(1_000L, reg("ev").scheduleAnchorMs)
        assertEquals(61_000L, TriggerRuntime.nextRepeatDueMs(reg("ev")))
    }

    @Test
    fun everySCoalescesDeadWindowIntoOneOccurrence() {
        clock = 1_000
        register(trig("ev", "time") { put("params", JSONObject().put("every_s", 60)) })
        // The device was dead across eight interval boundaries; the host arms
        // the single past-due alarm and it elapses at t=500_000.
        clock = 500_000
        rt.fireScheduled("id", "ev", JSONObject())
        assertEquals(1, fired.size)                       // coalesced, not a burst
        assertEquals(500_000L, reg("ev").lastFireFloorMs)
        // The next occurrence is strictly in the future, back on phase.
        val next = TriggerRuntime.nextRepeatDueMs(reg("ev"))!!
        assertTrue(next > 500_000)
        assertEquals(541_000L, next)                      // 1000 + 9·60000
    }

    @Test
    fun nextRepeatDueMsPureCases() {
        // No anchor yet ⇒ nothing to schedule.
        val bare = TriggerStore.Registration(trig("x", "time")
            .put("params", JSONObject().put("every_s", 60)))
        assertNull(TriggerRuntime.nextRepeatDueMs(bare))
        bare.scheduleAnchorMs = 0
        assertEquals(60_000L, TriggerRuntime.nextRepeatDueMs(bare))
        // A one-shot has no repeat schedule.
        assertNull(TriggerRuntime.nextRepeatDueMs(TriggerStore.Registration(
            trig("y", "time").put("params", JSONObject().put("at_ms", 5_000)))))
    }

    // ----------------------------------------------- timeSchedule (host seam)

    @Test
    fun timeScheduleReportsDuesAndDropsCompletedOneShot() {
        // The service's runtime clocks off queue.effectiveNow() (real wall
        // time), so the anchor is whatever now was at acceptance; the exact
        // every_s cadence math lives in the pure-runtime tests above.
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val service = TriggerFiringService(store, queue, 262_144, bootGeneration = { generation })
        service.replaceSet("id", TriggerValidator.validateSet(JSONObject().put("triggers",
            JSONArray()
                .put(trig("os", "time") { put("params", JSONObject().put("at_ms", 90_000)) })
                .put(trig("ev", "time") { put("params", JSONObject().put("every_s", 60)) })), caps))
        val before = service.timeSchedule().associate { it.triggerId to it.dueMs }
        assertEquals(90_000L, before["os"])               // at_ms is its own due
        assertEquals(reg("ev").scheduleAnchorMs!! + 60_000L, before["ev"]) // anchor + interval
        // Firing the one-shot completes it — it leaves the schedule; the
        // repeat stays (its next occurrence).
        service.fireScheduled("id", "os")
        val after = service.timeSchedule().map { it.triggerId }
        assertTrue("os" !in after)
        assertTrue("ev" in after)
    }
}
