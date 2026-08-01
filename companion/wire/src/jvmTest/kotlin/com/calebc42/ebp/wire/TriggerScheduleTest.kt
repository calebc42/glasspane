// SPDX-License-Identifier: GPL-3.0-or-later
// W8 conformance: scheduled + boot triggers (SPEC 21.5). A one-shot time.at_ms
// fires exactly once and never again; a boot registration fires at most once
// per device boot generation; a repeating time.every_s anchors its cadence at
// acceptance, coalesces every interval missed while the Companion was dead into
// a single occurrence (no catch-up burst), and advances its floor past the
// present so the next occurrence resumes on phase. timeSchedule() reports the
// host-armable next due per time entry, dropping a completed one-shot.
package com.calebc42.ebp.wire

import java.io.File
import java.time.ZoneId
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class TriggerScheduleTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private val caps = TriggerCaps(
        triggerTypes = setOf("time", "boot", "manual"),
        stateTypes = emptySet(), trackableStateTypes = emptySet(),
        triggerCaps = emptySet(), maxResponses = 4)

    private var clock = 1_000L
    private var generation: String? = "1"
    private val fired = mutableListOf<Pair<String, JsonObject>>()
    private val store = TriggerStore()
    private val rt = TriggerRuntime(store, { clock }, { ZoneId.of("UTC") }, { null },
        emit = { reg, data, commit -> commit(); fired.add(reg.entry.reqString("id") to data) },
        bootGeneration = { generation })

    private fun trig(id: String, type: String, block: JsonObjectBuilder.() -> Unit = {}) =
        buildJsonObject { put("id", id); put("type", type); block() }

    private fun register(vararg triggers: JsonObject) {
        val entries = TriggerValidator.validateSet(
            buildJsonObject { put("triggers", JsonArray(triggers.toList())) }, caps)
        store.replace("id", entries)
        rt.armBaselines("id")
    }

    private fun reg(id: String) = store.registration("id", id)!!
    private fun firedIds() = fired.map { it.first }

    // ---------------------------------------------------- one-shot time.at_ms

    @Test
    fun oneShotAtMsFiresExactlyOnce() {
        register(trig("os", "time") { putJsonObject("params") { put("at_ms", 5_000) } })
        rt.fireScheduled("id", "os", JsonObject(emptyMap()))
        rt.fireScheduled("id", "os", JsonObject(emptyMap()))   // eligibility skips the repeat
        assertEquals(listOf("os"), firedIds())
        assertTrue(reg("os").oneShotCompleted)
    }

    // -------------------------------------------------------- boot generation

    @Test
    fun bootRecordsAtInstallAndFiresOnNextGeneration() {
        generation = "1"
        register(trig("b", "boot"))                     // arm records gen "1" silently
        assertEquals("1", reg("b").bootGeneration)
        rt.onExternal("id", "boot", JsonObject(emptyMap()))  // same boot: must NOT fire
        assertEquals(0, fired.size)
        generation = "2"
        rt.onExternal("id", "boot", JsonObject(emptyMap()))  // next boot: fires once
        assertEquals(1, fired.size)
        assertEquals("2", reg("b").bootGeneration)
        rt.onExternal("id", "boot", JsonObject(emptyMap()))  // same gen again: no refire
        assertEquals(1, fired.size)
    }

    @Test
    fun recordedGenerationAndAnchorPersistAcrossReload() {
        // SPEC 21.1: armBaselines' silent recordings (boot generation, every_s
        // anchor) are durable records — they MUST survive a restart, or a boot
        // would re-fire and a repeating cadence would re-phase on every restart.
        val file = File(tmp.root, "t.json")
        val store = TriggerStore(FileTriggerBacking(file))
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val service = TriggerFiringService(store, queue, 262_144, bootGeneration = { "7" })
        service.replaceSet("id", TriggerValidator.validateSet(buildJsonObject {
            putJsonArray("triggers") {
                add(trig("b", "boot"))
                add(trig("ev", "time") { putJsonObject("params") { put("every_s", 60) } })
            }
        }, caps))
        val reloaded = TriggerStore(FileTriggerBacking(file))  // a restart
        assertEquals("7", reloaded.registration("id", "b")!!.bootGeneration)
        assertNotNull(reloaded.registration("id", "ev")!!.scheduleAnchorMs)
    }

    @Test
    fun bootSameGenerationProcessRestartCreatesNoOccurrence() {
        generation = "1"
        register(trig("b", "boot"))
        // A Companion process restart in the same boot re-arms baselines; the
        // recorded generation is kept, so no occurrence is created (SPEC 21.5).
        rt.armBaselines("id")
        assertEquals("1", reg("b").bootGeneration)
        rt.onExternal("id", "boot", JsonObject(emptyMap()))
        assertEquals(0, fired.size)
    }

    @Test
    fun unknownGenerationLeavesBootUngated() {
        // A null generation (BOOT_COUNT unavailable) never gates — the receiver
        // is the sole once-per-boot guard, so each fed occurrence fires.
        generation = null
        register(trig("b", "boot"))
        rt.onExternal("id", "boot", JsonObject(emptyMap()))
        rt.onExternal("id", "boot", JsonObject(emptyMap()))
        assertEquals(2, fired.size)
    }

    // ----------------------------------------------- every_s coalescing

    @Test
    fun everySAnchorsAtAcceptanceAndFirstDueIsOneInterval() {
        clock = 1_000
        register(trig("ev", "time") { putJsonObject("params") { put("every_s", 60) } })
        // Arming anchors the cadence at acceptance; the first occurrence is one
        // interval later, never at arm time.
        assertEquals(1_000L, reg("ev").scheduleAnchorMs)
        assertEquals(61_000L, TriggerRuntime.nextRepeatDueMs(reg("ev")))
    }

    @Test
    fun everySCoalescesDeadWindowIntoOneOccurrence() {
        clock = 1_000
        register(trig("ev", "time") { putJsonObject("params") { put("every_s", 60) } })
        // The device was dead across eight interval boundaries; the host arms
        // the single past-due alarm and it elapses at t=500_000.
        clock = 500_000
        rt.fireScheduled("id", "ev", JsonObject(emptyMap()))
        assertEquals(1, fired.size)                       // coalesced, not a burst
        assertEquals(500_000L, reg("ev").lastFireFloorMs)
        // The next occurrence is strictly in the future, back on phase.
        val next = TriggerRuntime.nextRepeatDueMs(reg("ev"))!!
        assertTrue(next > 500_000)
        assertEquals(541_000L, next)                      // 1000 + 9·60000
    }

    @Test
    fun everySThrottledBoundaryAdvancesCursorNoSpin() {
        clock = 1_000
        register(trig("ev", "time") {
            putJsonObject("params") { put("every_s", 60) }; put("throttle_s", 3600)
        })
        clock = 61_000
        rt.fireScheduled("id", "ev", JsonObject(emptyMap()))  // first boundary: admits
        assertEquals(1, fired.size)
        // A later boundary inside the throttle window is NOT admitted — but the
        // schedule cursor MUST still advance so the host re-arms the NEXT
        // boundary, never re-arming a past-due one (the RTC_WAKEUP spin).
        clock = 121_000
        rt.fireScheduled("id", "ev", JsonObject(emptyMap()))
        assertEquals(1, fired.size)                        // throttled: no new fire
        assertEquals(121_000L, reg("ev").lastFireFloorMs)  // cursor advanced past now
        assertTrue(TriggerRuntime.nextRepeatDueMs(reg("ev"))!! > 121_000)
    }

    @Test
    fun nextRepeatDueMsPureCases() {
        // No anchor yet ⇒ nothing to schedule.
        val bare = TriggerStore.Registration(trig("x", "time") {
            putJsonObject("params") { put("every_s", 60) }
        })
        assertNull(TriggerRuntime.nextRepeatDueMs(bare))
        bare.scheduleAnchorMs = 0
        assertEquals(60_000L, TriggerRuntime.nextRepeatDueMs(bare))
        // A one-shot has no repeat schedule.
        assertNull(TriggerRuntime.nextRepeatDueMs(TriggerStore.Registration(
            trig("y", "time") { putJsonObject("params") { put("at_ms", 5_000) } })))
    }

    // ----------------------------------------------- timeSchedule (host seam)

    @Test
    fun timeScheduleReportsDuesAndDropsCompletedOneShot() {
        // The service's runtime clocks off queue.effectiveNow() (real wall
        // time), so the anchor is whatever now was at acceptance; the exact
        // every_s cadence math lives in the pure-runtime tests above.
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val service = TriggerFiringService(store, queue, 262_144, bootGeneration = { generation })
        service.replaceSet("id", TriggerValidator.validateSet(buildJsonObject {
            putJsonArray("triggers") {
                add(trig("os", "time") { putJsonObject("params") { put("at_ms", 90_000) } })
                add(trig("ev", "time") { putJsonObject("params") { put("every_s", 60) } })
            }
        }, caps))
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
