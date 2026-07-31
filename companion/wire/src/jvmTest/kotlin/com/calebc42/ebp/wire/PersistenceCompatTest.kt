// SPDX-License-Identifier: GPL-3.0-or-later
// P0 pre-swap pin (PLAN-rf2 §0.2 item 1 + item 6): the UPGRADE GATE.
//
// Every fixture here is written by the org.json code that ships TODAY and
// re-loaded through the same File*Backing the app uses, so these tests pass
// against org.json and must keep passing after the kotlinx.serialization
// swap. The load path is the whole point: a device that upgrades reads
// yesterday's files with tomorrow's parser.
//
// THE RULE THIS FILE ENFORCES: persistence reads MUST be lenient
// (`Json.parseToJsonElement`), NEVER the strict wire parser
// (`EbpJson.parse`). `strictParserRejectsWhatTheStoreMustAccept` proves the
// two disagree on a legal stored file — a strict re-parse crash-loops the
// app on its own durable state.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class PersistenceCompatTest {

    @get:Rule
    val temp = TemporaryFolder()

    /** `args` nested [depth] containers deep, innermost carrying a value. */
    private fun deepArgs(depth: Int): JSONObject {
        var node = JSONObject().put("leaf", "bottom")
        repeat(depth - 1) { node = JSONObject().put("n", node) }
        return node
    }

    private fun jsonDepth(v: Any?): Int = when (v) {
        is JSONObject -> 1 + (v.keySet().maxOfOrNull { jsonDepth(v.get(it)) } ?: 0)
        is JSONArray -> 1 + ((0 until v.length()).maxOfOrNull { jsonDepth(v.get(it)) } ?: 0)
        else -> 0
    }

    // ------------------------------------------------------- durable queue

    @Test
    fun queueRecordWithDeepArgsSurvivesRoundTrip() {
        val file = temp.newFile("queue.json")
        // 62 deep inside `args`, which the record and the file's own
        // {records:[...]} wrapper push past 64 in the stored document —
        // legal on disk, and beyond what the WIRE parser accepts.
        val args = deepArgs(62)
        val record = JSONObject()
            .put("event_id", "e1").put("queue_seq", 7)
            .put("action", "a.b").put("args", args)
            .put("occurred_at_ms", 1_000L).put("ttl_s", 3600)
        FileQueueStore(file).replace(QueueSnapshot(listOf(record), 8, 1_234))

        val back = FileQueueStore(file).load()
        assertEquals(1, back.records.size)
        assertEquals(8L, back.nextSeq)
        assertEquals(1_234L, back.clockHighWater)
        val r = back.records[0]
        assertEquals("e1", r.getString("event_id"))
        assertEquals(7L, r.getLong("queue_seq"))
        // Fidelity all the way down: the 62nd level still carries its leaf.
        var node = r.getJSONObject("args")
        repeat(61) { node = node.getJSONObject("n") }
        assertEquals("bottom", node.getString("leaf"))
    }

    @Test
    fun strictParserRejectsWhatTheStoreMustAccept() {
        val file = temp.newFile("queue-deep.json")
        val record = JSONObject().put("event_id", "e1").put("args", deepArgs(62))
        FileQueueStore(file).replace(QueueSnapshot(listOf(record), 2, 0))
        val text = file.readText()
        // The stored document really is past the wire's depth ceiling.
        assertTrue("fixture must exceed MAX_JSON_DEPTH to have teeth",
            jsonDepth(JSONObject(text)) > WireLimits.MAX_JSON_DEPTH)
        // The lenient store path loads it — this is the required behavior.
        assertEquals(1, FileQueueStore(file).load().records.size)
        // The strict WIRE parser refuses the same bytes. Post-swap, wiring
        // persistence to EbpJson.parse (or any depth-checked reader) turns
        // this legal file into a boot crash.
        try {
            EbpJson.parse(text)
            fail("EbpJson.parse must reject a >64-deep document")
        } catch (e: WireParseError) {
            assertTrue(e.message!!.contains("depth"))
        }
    }

    // ------------------------------------------- surfaces: legacy migration

    @Test
    fun legacyPreSplitSurfacesFileMigratesItsDrafts() {
        // A records file in the PRE-SPLIT format: drafts live inside it.
        val legacy = temp.newFile("surfaces.json")
        legacy.writeText(JSONObject()
            .put("records", JSONArray().put(JSONObject()
                .put("surface", "app:main").put("revision", 42).put("present", true)
                .put("spec", JSONObject().put("t", "text").put("text", "hi"))
                .put("current_view", "home")))
            .put("drafts", JSONArray()
                .put(JSONObject().put("surface", "app:main").put("id", "title")
                    .put("value", "half-typed"))
                .put(JSONObject().put("surface", "app:main").put("id", "cleared")
                    .put("value", JSONObject.NULL)))
            .toString(), Charsets.UTF_8)

        val backing = FileSurfaceBacking(legacy)
        val state = backing.load()
        assertEquals(1, state.records.size)
        state.records[0].let {
            assertEquals("app:main", it.surface)
            assertEquals(42L, it.revision)
            assertTrue(it.present)
            assertEquals("hi", it.spec!!.getString("text"))
            assertEquals("home", it.currentView)
        }
        assertEquals(2, state.drafts.size)
        assertEquals("half-typed", state.drafts[0].value)
        // A JSON null draft loads as Kotlin null, never JSONObject.NULL and
        // never the string "null".
        assertNull(state.drafts[1].value)

        // Migration is EAGER: the split file exists after one load, so a
        // records-only rewrite cannot drop the legacy array.
        val draftsFile = java.io.File(legacy.parentFile, "surfaces-drafts.json")
        assertTrue("drafts must be migrated to the split file eagerly",
            draftsFile.exists())
        backing.replaceRecords(state.records)
        assertEquals(2, FileSurfaceBacking(legacy).load().drafts.size)
    }

    @Test
    fun draftNullRoundTripsAsJsonNull() {
        val file = temp.newFile("s.json")
        val backing = FileSurfaceBacking(file)
        backing.replaceDrafts(listOf(
            PersistedDraft("app:main", "typed", "text"),
            PersistedDraft("app:main", "explicitNull", null)))
        val drafts = FileSurfaceBacking(file).load().drafts
        assertEquals(2, drafts.size)
        assertEquals("text", drafts[0].value)
        assertNull(drafts[1].value)
        // The on-disk spelling is a JSON null, not the STRING "null" — the
        // delta a naive `put(k, v.toString())` port would introduce.
        val raw = java.io.File(file.parentFile, "s-drafts.json").readText()
        assertTrue(raw, raw.contains("\"value\":null"))
        assertFalse(raw, raw.contains("\"value\":\"null\""))
    }

    @Test
    fun storeLevelDraftNullIsDistinctFromAbsent() {
        val store = SurfaceStore(16, 1024)
        store.update("app:main", 1, JSONObject().put("t", "text_input")
            .put("id", "title").put("value", "authored"), null, null, null)
        assertFalse(store.hasDraft("app:main", "title"))
        store.putDraft("app:main", "title", null)
        // A null draft is a PRESENT draft whose value is JSON null.
        assertTrue(store.hasDraft("app:main", "title"))
    }

    // ------------------------------------------------------------ reminders

    @Test
    fun reminderWithIntegralDoubleAtMsLoadsAsLong() {
        val file = temp.newFile("reminders.json")
        // org.json writes an integral Double as an integer literal, so the
        // stored form is `5000`; the fidelity that matters is that getLong
        // still answers on reload whatever the spelling.
        val rec = JSONObject().put("id", "x").put("title", "T")
            .put("at_ms", 5_000.0).put("owner", "o")
        FileReminderBacking(file).replace(
            ReminderState(mapOf("o" to listOf(rec)), setOf("o|x|5000")))
        val back = FileReminderBacking(file).load()
        assertEquals(1, back.owners["o"]!!.size)
        assertEquals(5_000L, back.owners["o"]!![0].getLong("at_ms"))
        assertEquals(setOf("o|x|5000"), back.fired)
    }

    @Test
    fun reminderWithFractionalAtMsIsPreservedVerbatim() {
        // Not legal to ACCEPT over the wire (ReminderTest pins the 1201),
        // but a store must never silently rewrite what it was handed.
        val file = temp.newFile("reminders-frac.json")
        val rec = JSONObject().put("id", "x").put("title", "T").put("at_ms", 1.5)
        FileReminderBacking(file).replace(ReminderState(mapOf("o" to listOf(rec)), emptySet()))
        val back = FileReminderBacking(file).load()
        assertEquals(1.5, back.owners["o"]!![0].getDouble("at_ms"), 0.0)
    }

    // ------------------------------------------------------------- triggers

    @Test
    fun triggerRuntimeRecordsSurviveRoundTrip() {
        val file = temp.newFile("triggers.json")
        val entry = JSONObject().put("id", "t1").put("type", "battery.level")
            .put("params", JSONObject().put("below", 20))
            .put("policy", "queue").put("ttl_s", 3600).put("throttle_s", 60)
        val reg = PersistedRegistration(
            entry = entry,
            throttleFloorMs = 9_000L,
            oneShotCompleted = true,
            scheduleAnchorMs = 1_000L,
            lastFireFloorMs = 8_000L,
            bootGeneration = "boot-7")
        FileTriggerBacking(file).replace(TriggerState(mapOf("pid" to listOf(reg))))

        val back = FileTriggerBacking(file).load().identities["pid"]!!
        assertEquals(1, back.size)
        back[0].let {
            // Every runtime field survives: a lost throttle floor double-fires
            // a trigger, a lost one-shot completion re-arms it.
            assertEquals(9_000L, it.throttleFloorMs)
            assertTrue(it.oneShotCompleted)
            assertEquals(1_000L, it.scheduleAnchorMs)
            assertEquals(8_000L, it.lastFireFloorMs)
            assertEquals("boot-7", it.bootGeneration)
            assertEquals("battery.level", it.entry.getString("type"))
            assertEquals(20, it.entry.getJSONObject("params").getInt("below"))
        }
    }

    @Test
    fun triggerAbsentRuntimeFieldsStayAbsentNotZero() {
        val file = temp.newFile("triggers-sparse.json")
        val reg = PersistedRegistration(
            entry = JSONObject().put("id", "t1").put("type", "screen"),
            throttleFloorMs = null, oneShotCompleted = false,
            scheduleAnchorMs = null, lastFireFloorMs = null, bootGeneration = null)
        FileTriggerBacking(file).replace(TriggerState(mapOf("pid" to listOf(reg))))
        val back = FileTriggerBacking(file).load().identities["pid"]!![0]
        // null must not decay to 0: a zero floor is "fire immediately".
        assertNull(back.throttleFloorMs)
        assertNull(back.scheduleAnchorMs)
        assertNull(back.lastFireFloorMs)
        assertNull(back.bootGeneration)
        assertFalse(back.oneShotCompleted)
        assertNotNull(back.entry)
    }
}
