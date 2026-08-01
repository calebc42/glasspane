// SPDX-License-Identifier: GPL-3.0-or-later
// W8 conformance: durable reminders (SPEC 18.6). The accepted set and the
// fired receipts survive a process death (re-open the same file), receipts
// commit BEFORE presentation is allowed, a storage failure withholds both
// the accept and the presentation, and the unchanged-tuple receipt rule
// holds across a reload.
package com.calebc42.ebp.wire

import java.io.File
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ReminderBackingTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private fun reminder(id: String, atMs: Long, title: String = "t") = buildJsonObject {
        put("id", id); put("title", title); put("at_ms", atMs)
    }

    @Test
    fun setAndReceiptsSurviveReload() {
        val file = File(tmp.root, "reminders.json")
        val a = ReminderStore(FileReminderBacking(file))
        a.replace("owner", listOf(reminder("r1", 1000), reminder("r2", 2000)))
        assertTrue(a.markFired("owner", "r1"))
        // Process death: a fresh store over the same file sees everything.
        val b = ReminderStore(FileReminderBacking(file))
        assertEquals(2, b.ownerCount("owner"))
        assertEquals("r1", b.reminders("owner")[0].reqString("id"))
        assertTrue(b.isFired("owner", "r1"))       // receipt survived
        assertFalse(b.isFired("owner", "r2"))
        // At-most-once across the restart: the survived receipt blocks re-fire.
        assertFalse(b.markFired("owner", "r1"))
        assertTrue(b.markFired("owner", "r2"))
    }

    @Test
    fun unchangedTupleKeepsReceiptChangedResets() {
        val file = File(tmp.root, "reminders.json")
        val a = ReminderStore(FileReminderBacking(file))
        a.replace("owner", listOf(reminder("r1", 1000)))
        assertTrue(a.markFired("owner", "r1"))
        // Re-push unchanged tuple: receipt kept (also across reload).
        a.replace("owner", listOf(reminder("r1", 1000)))
        assertTrue(ReminderStore(FileReminderBacking(file)).isFired("owner", "r1"))
        // Changing at_ms creates a new schedule: receipt reset.
        a.replace("owner", listOf(reminder("r1", 5000)))
        val b = ReminderStore(FileReminderBacking(file))
        assertFalse(b.isFired("owner", "r1"))
        assertTrue(b.markFired("owner", "r1"))
    }

    // A backing that fails on demand, for the storage-failure contracts.
    private class FlakyBacking : ReminderBacking {
        var fail = false
        var state = ReminderState(emptyMap(), emptySet())
        override fun load() = state
        override fun replace(state: ReminderState) {
            if (fail) throw java.io.IOException("disk gone")
            this.state = state
        }
    }

    @Test
    fun storageFailureRestoresPriorSetAndThrows() {
        val backing = FlakyBacking()
        val store = ReminderStore(backing)
        store.replace("owner", listOf(reminder("r1", 1000)))
        backing.fail = true
        var threw = false
        try {
            store.replace("owner", listOf(reminder("r2", 2000)))
        } catch (e: Exception) { threw = true }
        assertTrue(threw)
        // The prior set is still in force, in memory and on disk.
        assertEquals(1, store.ownerCount("owner"))
        assertEquals("r1", store.reminders("owner")[0].reqString("id"))
        assertEquals("r1", backing.state.owners.getValue("owner")[0].reqString("id"))
    }

    @Test
    fun failedReceiptCommitWithholdsPresentation() {
        val backing = FlakyBacking()
        val store = ReminderStore(backing)
        store.replace("owner", listOf(reminder("r1", 1000)))
        backing.fail = true
        // SPEC 18.6: fired state persists before/atomically with presentation;
        // an uncommittable receipt means DO NOT present (returns false), and
        // the tuple stays eligible once storage recovers.
        assertFalse(store.markFired("owner", "r1"))
        assertFalse(store.isFired("owner", "r1"))
        backing.fail = false
        assertTrue(store.markFired("owner", "r1"))
    }

    // ------------------------------------------------- tap routing (cold path)

    private fun withOnTap(r: JsonObject, action: String, offline: String? = null) =
        r.with("on_tap", buildJsonObject {
            put("action", action)
            if (offline != null) { put("when_offline", offline); put("ttl_s", 3600) }
            put("args", buildJsonObject { put("k", "v") })
        })

    private class RecordingSession : LiveSession {
        var dropped: JsonObject? = null
        var admittedPolicy: String? = null
        override fun deliverLiveDrop(params: JsonObject, callback: ((String?, JsonObject?) -> Unit)?) {
            dropped = params
        }
        override fun onDurableAdmitted(policy: String) { admittedPolicy = policy }
    }

    @Test
    fun tapQueuePolicyAdmitsDurablyWithNoSession() {
        val store = ReminderStore()
        store.replace("org", listOf(withOnTap(reminder("r1", 1000), "reminder.done", "queue")))
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        // No live session: a queue-policy tap still lands durably (SPEC 18.6/15).
        routeReminderTap(store, queue, 262_144, "org", "r1", live = null)
        assertEquals(1, queue.count())
        val ev = queue.head()!!.reqObj("event")
        assertEquals("reminder.done", ev.reqString("action"))
        assertEquals("org", ev.reqObj("args").reqString("owner"))     // injected
        assertEquals("r1", ev.reqObj("args").reqString("reminder_id")) // injected
        assertEquals("v", ev.reqObj("args").reqString("k"))           // authored
    }

    @Test
    fun tapDropIsLostWithoutSessionAndDeliversWithOne() {
        val store = ReminderStore()
        store.replace("org", listOf(withOnTap(reminder("r1", 1000), "reminder.done"))) // default drop
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        routeReminderTap(store, queue, 262_144, "org", "r1", live = null)
        assertEquals(0, queue.count()) // drop + no session = lost, nothing durable
        val live = RecordingSession()
        routeReminderTap(store, queue, 262_144, "org", "r1", live = live)
        assertEquals("reminder.done", live.dropped!!.reqString("action"))
        assertEquals("r1", live.dropped!!.reqObj("args").reqString("reminder_id"))
    }

    @Test
    fun tapWithNoOnTapDispatchesNothing() {
        val store = ReminderStore()
        store.replace("org", listOf(reminder("r1", 1000))) // no on_tap
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val live = RecordingSession()
        routeReminderTap(store, queue, 262_144, "org", "r1", live = live)
        assertEquals(0, queue.count())
        assertEquals(null, live.dropped)
        assertEquals(null, live.admittedPolicy)
    }

    @Test
    fun engineAcceptsInjectedStoreAndAnswersStorageFailure() {
        // The engine takes the store as a constructor param (between queue and
        // sink) and answers -32603 on a storage-failed replace, leaving the
        // prior set in force.
        val backing = FlakyBacking()
        val store = ReminderStore(backing)
        val out = mutableListOf<JsonObject>()
        val engine = CompanionEngine(
            CompanionConfig(
                serverName = "kat", serverVersion = "1",
                pairings = mapOf(katPid to katToken),
                supportedCapabilities = setOf("reminders.owner"),
                surfaceProfiles = buildJsonObject {
                    putJsonObject("app") {
                        put("node_types", JsonArray(emptyList()))
                        put("builtins", JsonArray(emptyList()))
                        put("features", JsonArray(emptyList()))
                    }
                },
                limits = testLimits("max_reminders" to 256),
                nonceSource = { katSn }),
            reminders = store) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("reminders.owner")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        fun set(id: String, vararg rs: JsonObject) =
            engine.feed(frame(request(id, "reminders.set", buildJsonObject {
                put("owner", "org"); put("reminders", JsonArray(rs.toList()))
            })))
        set("s1", reminder("r1", 1000))
        assertEquals(1L, out.replyTo("s1").reqObj("result").reqLong("count"))
        backing.fail = true
        set("s2", reminder("r2", 2000))
        val err = out.errorOf("s2")
        assertEquals(-32603L, err.reqLong("code"))
        assertEquals(1, store.ownerCount("org"))   // prior set still in force
        assertEquals("r1", store.reminders("org")[0].reqString("id"))
    }
}
