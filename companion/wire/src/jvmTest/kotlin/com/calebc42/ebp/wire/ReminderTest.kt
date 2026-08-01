// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: owner-scoped reminders (SPEC 18.6). reminders.set is a
// request gated on reminders.owner: validation, atomic per-owner replace
// with {count}, max_reminders across owners, the fired-receipt lifecycle,
// and a tap that injects owner/reminder_id and honors the offline policy.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderTest {

    private fun engine(out: MutableList<JsonObject>, maxReminders: Long = 256,
                       grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("reminders.owner") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("reminders.owner"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(listOf("text").map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_reminders" to maxReminders),
            nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        return engine
    }

    private fun reminder(id: String, atMs: Long, onTap: JsonObject? = null) =
        buildJsonObject {
            put("id", id); put("title", "T $id"); put("at_ms", atMs)
            if (onTap != null) put("on_tap", onTap)
        }

    private var reqN = 0
    private fun set(engine: CompanionEngine, out: MutableList<JsonObject>,
                    owner: String, vararg rs: JsonObject): JsonObject {
        val rid = "m${reqN++}"
        engine.feed(frame(request(rid, "reminders.set", buildJsonObject {
            put("owner", owner); put("reminders", JsonArray(rs.toList()))
        })))
        return out.replyTo(rid)
    }

    @Test
    fun ownerScopedReplaceReturnsCount() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        assertEquals(2L, set(engine, out, "org.a",
            reminder("x", 1000), reminder("y", 2000))
            .reqObj("result").reqLong("count"))
        // A different owner's set is independent; count is per-owner.
        assertEquals(1L, set(engine, out, "org.b", reminder("z", 3000))
            .reqObj("result").reqLong("count"))
        assertEquals(2, engine.reminders.ownerCount("org.a"))
        assertEquals(3, engine.reminders.totalCount())
        // Replacing org.a shrinks only org.a; an empty array clears it.
        assertEquals(0L, set(engine, out, "org.a").reqObj("result").reqLong("count"))
        assertEquals(0, engine.reminders.ownerCount("org.a"))
        assertEquals(1, engine.reminders.ownerCount("org.b"))
    }

    @Test
    fun validationTaxonomy() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        fun reason(vararg rs: JsonObject): String {
            val r = set(engine, out, "org.a", *rs)
            return r.reqObj("error").reqObj("data").reqString("reason")
        }
        // Duplicate id within the owner's set.
        assertEquals("duplicate reminder id",
            reason(reminder("x", 1), reminder("x", 2)))
        // Empty title.
        assertEquals("non-empty string required", reason(
            buildJsonObject { put("id", "x"); put("title", ""); put("at_ms", 1) }))
        // Missing at_ms.
        assertEquals("must be a non-negative integer timestamp", reason(
            buildJsonObject { put("id", "x"); put("title", "T") }))
        // SPEC 4.3: a non-integer at_ms (JSON float) is rejected, not truncated.
        assertEquals("must be a non-negative integer timestamp", reason(
            buildJsonObject { put("id", "x"); put("title", "T"); put("at_ms", 1.5) }))
        // Unknown member (closed object).
        assertEquals("unknown reminder member", reason(
            reminder("x", 1).with("extra", JsonPrimitive(true))))
        // on_tap injection conflict.
        assertEquals("owner/reminder_id are injected", reason(reminder("x", 1,
            buildJsonObject {
                put("action", "a.b")
                putJsonObject("args") { put("owner", "sneaky") }
            })))
        // A queue on_tap without ttl_s.
        assertEquals("queue requires ttl_s", reason(reminder("x", 1,
            buildJsonObject { put("action", "a.b"); put("when_offline", "queue") })))
        // SPEC 14.5/18.6 (#133): capture_fields is surface/dialog-scoped —
        // a reminder tap has no input state to capture from.
        assertEquals("capture_fields is surface/dialog-scoped", reason(reminder("x", 1,
            buildJsonObject {
                put("action", "a.b")
                put("capture_fields", JsonArray(listOf(JsonPrimitive("note"))))
            })))
    }

    @Test
    fun maxRemindersCountsAcrossOwners() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, maxReminders = 3)
        set(engine, out, "org.a", reminder("x", 1), reminder("y", 2))
        // org.b may add one (total 3).
        assertEquals(1L, set(engine, out, "org.b", reminder("z", 3))
            .reqObj("result").reqLong("count"))
        // A fourth across owners is refused; prior sets unchanged.
        val err = set(engine, out, "org.b", reminder("z", 3), reminder("w", 4))
        assertEquals("reminder-limit", err.reqObj("error")
            .reqObj("data").reqString("reason"))
        assertEquals(1, engine.reminders.ownerCount("org.b"))
    }

    @Test
    fun firedReceiptLifecycle() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        set(engine, out, "org.a", reminder("x", 1000))
        // First presentation fires; a second returns false (present once).
        assertTrue(engine.markReminderFired("org.a", "x"))
        assertFalse(engine.markReminderFired("org.a", "x"))
        // Replacing with the SAME (id, at_ms) preserves the fired receipt.
        set(engine, out, "org.a", reminder("x", 1000).with("body", JsonPrimitive("changed")))
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
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        // A drop on_tap: live event, owner/reminder_id injected, no context.
        set(engine, out, "org.a", reminder("x", 1000,
            buildJsonObject {
                put("action", "agenda.open")
                putJsonObject("args") { put("k", 1) }
            }))
        engine.dispatchReminderTap("org.a", "x")
        val ev = out.events().last().reqObj("params")
        assertEquals("agenda.open", ev.reqString("action"))
        assertFalse("surface" in ev); assertFalse("revision_seen" in ev)
        val args = ev.reqObj("args")
        assertEquals("org.a", args.reqString("owner"))
        assertEquals("x", args.reqString("reminder_id"))
        assertEquals(1L, args.reqLong("k"))
        // A queue on_tap admits to the durable queue instead.
        set(engine, out, "org.a", reminder("y", 2000,
            buildJsonObject {
                put("action", "agenda.snooze")
                put("when_offline", "queue"); put("ttl_s", 3600)
            }))
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
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, grant = false)
        val r = set(engine, out, "org.a", reminder("x", 1))
        assertEquals(-32601L, r.reqObj("error").reqLong("code"))
    }
}
