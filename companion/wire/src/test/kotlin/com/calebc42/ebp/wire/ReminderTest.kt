// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: owner-scoped reminders (SPEC 18.6). reminders.set is a
// request gated on reminders.owner: validation, atomic per-owner replace
// with {count}, max_reminders across owners, the fired-receipt lifecycle,
// and a tap that injects owner/reminder_id and honors the offline policy.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits(maxReminders: Long = 256) = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64).put("max_reminders", maxReminders)

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    private fun engine(out: MutableList<JSONObject>, maxReminders: Long = 256,
                       grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("reminders.owner") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("reminders.owner"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(maxReminders), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        return engine
    }

    private fun reminder(id: String, atMs: Long, onTap: JSONObject? = null) =
        JSONObject().put("id", id).put("title", "T $id").put("at_ms", atMs)
            .also { if (onTap != null) it.put("on_tap", onTap) }

    private var reqN = 0
    private fun set(engine: CompanionEngine, out: MutableList<JSONObject>,
                    owner: String, vararg rs: JSONObject): JSONObject {
        val rid = "m${reqN++}"
        engine.feed(frame(request(rid, "reminders.set", JSONObject()
            .put("owner", owner).put("reminders", JSONArray(rs.toList())))))
        return out.last { it.opt("id") == rid }
    }

    @Test
    fun ownerScopedReplaceReturnsCount() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        assertEquals(2, set(engine, out, "org.a",
            reminder("x", 1000), reminder("y", 2000))
            .getJSONObject("result").getInt("count"))
        // A different owner's set is independent; count is per-owner.
        assertEquals(1, set(engine, out, "org.b", reminder("z", 3000))
            .getJSONObject("result").getInt("count"))
        assertEquals(2, engine.reminders.ownerCount("org.a"))
        assertEquals(3, engine.reminders.totalCount())
        // Replacing org.a shrinks only org.a; an empty array clears it.
        assertEquals(0, set(engine, out, "org.a").getJSONObject("result").getInt("count"))
        assertEquals(0, engine.reminders.ownerCount("org.a"))
        assertEquals(1, engine.reminders.ownerCount("org.b"))
    }

    @Test
    fun validationTaxonomy() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        fun reason(vararg rs: JSONObject): String {
            val r = set(engine, out, "org.a", *rs)
            return r.getJSONObject("error").getJSONObject("data").getString("reason")
        }
        // Duplicate id within the owner's set.
        assertEquals("duplicate reminder id",
            reason(reminder("x", 1), reminder("x", 2)))
        // Empty title.
        assertEquals("non-empty string required", reason(
            JSONObject().put("id", "x").put("title", "").put("at_ms", 1)))
        // Missing at_ms.
        assertEquals("must be a non-negative integer timestamp", reason(
            JSONObject().put("id", "x").put("title", "T")))
        // SPEC 4.3: a non-integer at_ms (JSON float) is rejected, not truncated.
        assertEquals("must be a non-negative integer timestamp", reason(
            JSONObject().put("id", "x").put("title", "T").put("at_ms", 1.5)))
        // Unknown member (closed object).
        assertEquals("unknown reminder member", reason(
            reminder("x", 1).put("extra", true)))
        // on_tap injection conflict.
        assertEquals("owner/reminder_id are injected", reason(reminder("x", 1,
            JSONObject().put("action", "a.b")
                .put("args", JSONObject().put("owner", "sneaky")))))
        // A queue on_tap without ttl_s.
        assertEquals("queue requires ttl_s", reason(reminder("x", 1,
            JSONObject().put("action", "a.b").put("when_offline", "queue"))))
    }

    @Test
    fun maxRemindersCountsAcrossOwners() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, maxReminders = 3)
        set(engine, out, "org.a", reminder("x", 1), reminder("y", 2))
        // org.b may add one (total 3).
        assertEquals(1, set(engine, out, "org.b", reminder("z", 3))
            .getJSONObject("result").getInt("count"))
        // A fourth across owners is refused; prior sets unchanged.
        val err = set(engine, out, "org.b", reminder("z", 3), reminder("w", 4))
        assertEquals("reminder-limit", err.getJSONObject("error")
            .getJSONObject("data").getString("reason"))
        assertEquals(1, engine.reminders.ownerCount("org.b"))
    }

    @Test
    fun firedReceiptLifecycle() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        set(engine, out, "org.a", reminder("x", 1000))
        // First presentation fires; a second returns false (present once).
        assertTrue(engine.markReminderFired("org.a", "x"))
        assertFalse(engine.markReminderFired("org.a", "x"))
        // Replacing with the SAME (id, at_ms) preserves the fired receipt.
        set(engine, out, "org.a", reminder("x", 1000).put("body", "changed"))
        assertTrue(engine.reminders.isFired("org.a", "x"))
        // Changing at_ms is a new schedule: the receipt resets.
        set(engine, out, "org.a", reminder("x", 2000))
        assertFalse(engine.reminders.isFired("org.a", "x"))
        assertTrue(engine.markReminderFired("org.a", "x"))
        // Removing the id drops its receipt; re-adding may fire again.
        set(engine, out, "org.a")
        set(engine, out, "org.a", reminder("x", 2000))
        assertFalse(engine.reminders.isFired("org.a", "x"))
    }

    @Test
    fun tapInjectsAndHonorsPolicy() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        // A drop on_tap: live event, owner/reminder_id injected, no context.
        set(engine, out, "org.a", reminder("x", 1000,
            JSONObject().put("action", "agenda.open").put("args", JSONObject().put("k", 1))))
        engine.dispatchReminderTap("org.a", "x")
        val ev = out.last { it.opt("method") == "event.action" }.getJSONObject("params")
        assertEquals("agenda.open", ev.getString("action"))
        assertFalse(ev.has("surface")); assertFalse(ev.has("revision_seen"))
        val args = ev.getJSONObject("args")
        assertEquals("org.a", args.getString("owner"))
        assertEquals("x", args.getString("reminder_id"))
        assertEquals(1, args.getInt("k"))
        // A queue on_tap admits to the durable queue instead.
        set(engine, out, "org.a", reminder("y", 2000,
            JSONObject().put("action", "agenda.snooze")
                .put("when_offline", "queue").put("ttl_s", 3600)))
        var status: String? = null
        engine.dispatchReminderTap("org.a", "y") { s, _ -> status = s }
        assertEquals("queued", status)
        assertEquals(1, engine.queue.count())
        // A reminder with no on_tap dispatches nothing (dismissal != tap).
        set(engine, out, "org.a", reminder("z", 3000))
        val before = out.size
        engine.dispatchReminderTap("org.a", "z")
        assertEquals(before, out.size)
    }

    @Test
    fun ungrantedRemindersIsMethodNotFound() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, grant = false)
        val r = set(engine, out, "org.a", reminder("x", 1))
        assertEquals(-32601, r.getJSONObject("error").getInt("code"))
    }
}
