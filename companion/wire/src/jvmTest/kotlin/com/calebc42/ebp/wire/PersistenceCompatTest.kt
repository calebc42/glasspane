// SPDX-License-Identifier: GPL-3.0-or-later
// P0 pre-swap pin (PLAN-rf2 §0.2 item 1 + item 6): the UPGRADE GATE.
//
// Pre-swap, every fixture here was written at runtime by the org.json code
// that shipped then. The swap replaced that writer, so the legacy-file pins
// now carry their fixtures as FROZEN raw text in org.json's spelling
// (integral doubles written as integer literals, explicit "value":null) —
// the gate keeps testing yesterday's file under tomorrow's parser instead of
// decaying into a kotlinx self-round-trip (C5 decision of record,
// PLAN-rf2-c5-tests §3.8). The round-trip pins still exercise today's writer.
//
// THE RULE THIS FILE ENFORCES: persistence reads MUST be lenient
// (`Json.parseToJsonElement`), NEVER the strict wire parser
// (`EbpJson.parse`). `strictParserRejectsWhatTheStoreMustAccept` proves the
// two disagree on a legal stored file — a strict re-parse crash-loops the
// app on its own durable state.
//
// C5 note: this file keeps every helper LOCAL on purpose (PLAN-rf2 §0.1's
// "a single file to keep green" hermeticity) — do not adopt TestSupport here.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
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

    /** `args` nested [depth] containers deep, innermost carrying a value —
     * built bottom-up; the trees are immutable. */
    private fun deepArgs(depth: Int): JsonObject {
        var node = buildJsonObject { put("leaf", "bottom") }
        repeat(depth - 1) { node = JsonObject(mapOf("n" to node)) }
        return node
    }

    /** The same shape as raw TEXT, spelled the way org.json wrote it. */
    private fun deepArgsText(depth: Int): String =
        """{"n":""".repeat(depth - 1) + """{"leaf":"bottom"}""" + "}".repeat(depth - 1)

    private fun jsonDepth(v: JsonElement?): Int = when (v) {
        is JsonObject -> 1 + (v.values.maxOfOrNull(::jsonDepth) ?: 0)
        is JsonArray -> 1 + (v.maxOfOrNull(::jsonDepth) ?: 0)
        else -> 0
    }

    // ------------------------------------------------------- durable queue

    @Test
    fun queueRecordWithDeepArgsSurvivesRoundTrip() {
        val file = temp.newFile("queue.json")
        // FROZEN legacy fixture: 62 deep inside `args`, which the record and
        // the file's own {records:[...]} wrapper push past 64 in the stored
        // document — legal on disk, and beyond what the WIRE parser accepts.
        file.writeText(
            """{"records":[{"event_id":"e1","queue_seq":7,"action":"a.b","args":""" +
                deepArgsText(62) +
                ""","occurred_at_ms":1000,"ttl_s":3600}],"next_seq":8,"clock_high_water":1234}""",
            Charsets.UTF_8)

        val back = FileQueueStore(file).load()
        assertEquals(1, back.records.size)
        assertEquals(8L, back.nextSeq)
        assertEquals(1_234L, back.clockHighWater)
        val r = back.records[0]
        assertEquals("e1", r.reqString("event_id"))
        assertEquals(7L, r.reqLong("queue_seq"))
        // Fidelity all the way down: the 62nd level still carries its leaf.
        var node = r.reqObj("args")
        repeat(61) { node = node.reqObj("n") }
        assertEquals("bottom", node.reqString("leaf"))

        // And TODAY'S writer keeps the depth: replace() + reload round-trips
        // the same record, so the write path stays under test too.
        FileQueueStore(file).replace(
            QueueSnapshot(back.records, back.nextSeq, back.clockHighWater))
        var again = FileQueueStore(file).load().records[0].reqObj("args")
        repeat(61) { again = again.reqObj("n") }
        assertEquals("bottom", again.reqString("leaf"))
    }

    @Test
    fun strictParserRejectsWhatTheStoreMustAccept() {
        val file = temp.newFile("queue-deep.json")
        // FROZEN legacy fixture, same construction as above.
        val text = """{"records":[{"event_id":"e1","args":""" + deepArgsText(62) +
            """}],"next_seq":2,"clock_high_water":0}"""
        file.writeText(text, Charsets.UTF_8)
        // The stored document really is past the wire's depth ceiling.
        assertTrue("fixture must exceed MAX_JSON_DEPTH to have teeth",
            jsonDepth(Json.parseToJsonElement(text)) > WireLimits.MAX_JSON_DEPTH)
        // The lenient store path loads it — this is the required behavior.
        assertEquals(1, FileQueueStore(file).load().records.size)
        // The strict WIRE parser refuses the same bytes. Wiring persistence
        // to EbpJson.parse (or any depth-checked reader) turns this legal
        // file into a boot crash. This try-block MUST stay EbpJson.parse —
        // the strictness IS the assertion.
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
        // FROZEN legacy fixture: a records file in the PRE-SPLIT format,
        // drafts inside it, explicit "value":null spelled as org.json wrote it.
        val legacy = temp.newFile("surfaces.json")
        legacy.writeText(
            """{"records":[{"surface":"app:main","revision":42,"present":true,""" +
                """"spec":{"t":"text","text":"hi"},"current_view":"home"}],""" +
                """"drafts":[{"surface":"app:main","id":"title","value":"half-typed"},""" +
                """{"surface":"app:main","id":"cleared","value":null}]}""",
            Charsets.UTF_8)

        val backing = FileSurfaceBacking(legacy)
        val state = backing.load()
        assertEquals(1, state.records.size)
        state.records[0].let {
            assertEquals("app:main", it.surface)
            assertEquals(42L, it.revision)
            assertTrue(it.present)
            assertEquals("hi", it.spec!!.reqString("text"))
            assertEquals("home", it.currentView)
        }
        assertEquals(2, state.drafts.size)
        assertEquals(JsonPrimitive("half-typed"), state.drafts[0].value)
        // A JSON null draft loads as Kotlin null (PersistedDraft's documented
        // exception: Kotlin null IS the JSON null draft), never the string
        // "null".
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
            PersistedDraft("app:main", "typed", JsonPrimitive("text")),
            PersistedDraft("app:main", "explicitNull", null)))
        val drafts = FileSurfaceBacking(file).load().drafts
        assertEquals(2, drafts.size)
        assertEquals(JsonPrimitive("text"), drafts[0].value)
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
        store.update("app:main", 1, buildJsonObject {
            put("t", "text_input")
            put("id", "title")
            put("value", "authored")
        }, null, null, null)
        assertFalse(store.hasDraft("app:main", "title"))
        store.putDraft("app:main", "title", null)
        // A null draft is a PRESENT draft whose value is JSON null.
        assertTrue(store.hasDraft("app:main", "title"))
    }

    // ------------------------------------------------------------ reminders

    @Test
    fun reminderWithIntegralDoubleAtMsLoadsAsLong() {
        val file = temp.newFile("reminders.json")
        // FROZEN legacy fixture: org.json wrote an integral Double as an
        // integer literal, so the stored form is `5000`. The fidelity that
        // matters is that the VALUE still answers as 5000 on reload,
        // whatever the spelling — so the read is integralLongOrNull.
        file.writeText(
            """{"owners":{"o":[{"id":"x","title":"T","at_ms":5000,"owner":"o"}]},""" +
                """"fired":["o|x|5000"]}""",
            Charsets.UTF_8)
        val back = FileReminderBacking(file).load()
        assertEquals(1, back.owners["o"]!!.size)
        assertEquals(5_000L, integralLongOrNull(back.owners["o"]!![0]["at_ms"]))
        assertEquals(setOf("o|x|5000"), back.fired)
    }

    @Test
    fun reminderWithFractionalAtMsIsPreservedVerbatim() {
        // Not legal to ACCEPT over the wire (ReminderTest pins the 1201),
        // but a store must never silently rewrite what it was handed.
        // FROZEN legacy fixture — org.json preserved the fractional 1.5.
        val file = temp.newFile("reminders-frac.json")
        file.writeText(
            """{"owners":{"o":[{"id":"x","title":"T","at_ms":1.5}]},"fired":[]}""",
            Charsets.UTF_8)
        val back = FileReminderBacking(file).load()
        assertEquals(1.5, back.owners["o"]!![0]["at_ms"]!!.asDoubleOrNull()!!, 0.0)
    }

    // ------------------------------------------------------------- triggers

    @Test
    fun triggerRuntimeRecordsSurviveRoundTrip() {
        val file = temp.newFile("triggers.json")
        val entry = buildJsonObject {
            put("id", "t1")
            put("type", "battery.level")
            putJsonObject("params") { put("below", 20) }
            put("policy", "queue")
            put("ttl_s", 3600)
            put("throttle_s", 60)
        }
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
            assertEquals("battery.level", it.entry.reqString("type"))
            assertEquals(20L, it.entry.reqObj("params").reqLong("below"))
        }
    }

    @Test
    fun triggerAbsentRuntimeFieldsStayAbsentNotZero() {
        val file = temp.newFile("triggers-sparse.json")
        val reg = PersistedRegistration(
            entry = buildJsonObject { put("id", "t1"); put("type", "screen") },
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
