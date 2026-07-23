// SPDX-License-Identifier: GPL-3.0-or-later
// W8 conformance: durable reminders (SPEC 18.6). The accepted set and the
// fired receipts survive a process death (re-open the same file), receipts
// commit BEFORE presentation is allowed, a storage failure withholds both
// the accept and the presentation, and the unchanged-tuple receipt rule
// holds across a reload.
package com.calebc42.ebp.wire

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ReminderBackingTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private fun reminder(id: String, atMs: Long, title: String = "t") = JSONObject()
        .put("id", id).put("title", title).put("at_ms", atMs)

    @Test
    fun setAndReceiptsSurviveReload() {
        val file = File(tmp.root, "reminders.json")
        val a = ReminderStore(FileReminderBacking(file))
        a.replace("owner", listOf(reminder("r1", 1000), reminder("r2", 2000)))
        assertTrue(a.markFired("owner", "r1"))
        // Process death: a fresh store over the same file sees everything.
        val b = ReminderStore(FileReminderBacking(file))
        assertEquals(2, b.ownerCount("owner"))
        assertEquals("r1", b.reminders("owner")[0].getString("id"))
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
        assertEquals("r1", store.reminders("owner")[0].getString("id"))
        assertEquals("r1", backing.state.owners.getValue("owner")[0].getString("id"))
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

    @Test
    fun engineAcceptsInjectedStoreAndAnswersStorageFailure() {
        // The engine takes the store as a constructor param (between queue and
        // sink) and answers -32603 on a storage-failed replace, leaving the
        // prior set in force.
        val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
        val katPid = "101112131415161718191a1b1c1d1e1f"
        val katCn = "202122232425262728292a2b2c2d2e2f"
        val katSn = "303132333435363738393a3b3c3d3e3f"
        val backing = FlakyBacking()
        val store = ReminderStore(backing)
        val out = mutableListOf<JSONObject>()
        val engine = CompanionEngine(
            CompanionConfig(
                serverName = "kat", serverVersion = "1",
                pairings = mapOf(katPid to katToken),
                supportedCapabilities = setOf("reminders.owner"),
                surfaceProfiles = JSONObject().put("app", JSONObject()
                    .put("node_types", org.json.JSONArray())
                    .put("builtins", org.json.JSONArray())
                    .put("features", org.json.JSONArray())),
                limits = JSONObject()
                    .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
                    .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
                    .put("max_surfaces", 16).put("max_surface_ids", 1024)
                    .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
                    .put("max_capture_fields", 64).put("max_reminders", 256),
                nonceSource = { katSn }),
            reminders = store) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        fun frame(m: JSONObject) = encodeFrame(m.toString())
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("reminders.owner")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        fun set(id: String, vararg rs: JSONObject) =
            engine.feed(frame(request(id, "reminders.set", JSONObject()
                .put("owner", "org").put("reminders", org.json.JSONArray(rs.toList())))))
        set("s1", reminder("r1", 1000))
        assertEquals(1, out.last { it.opt("id") == "s1" }
            .getJSONObject("result").getInt("count"))
        backing.fail = true
        set("s2", reminder("r2", 2000))
        val err = out.last { it.opt("id") == "s2" }.getJSONObject("error")
        assertEquals(-32603, err.getInt("code"))
        assertEquals(1, store.ownerCount("org"))   // prior set still in force
        assertEquals("r1", store.reminders("org")[0].getString("id"))
    }
}
