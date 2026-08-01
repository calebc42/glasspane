// SPDX-License-Identifier: GPL-3.0-or-later
// W9-l SPEC 18.5: a notification action tap routes its remote on_tap through
// the context-less §14.4 pipeline; an inline reply's typed text lands in
// event.action.fields under the action's key, and the descriptor's authored
// args are preserved. Deterministic — a fake LiveSession captures the drop.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationActionTest {

    private fun queue() = DurableQueue(MemoryQueueStore(), 256, 8_388_608)

    private class FakeLive : LiveSession {
        var dropped: JsonObject? = null
        override fun deliverLiveDrop(params: JsonObject, callback: ((String?, JsonObject?) -> Unit)?) {
            dropped = params
            callback?.invoke("accepted", null)
        }
        override fun onDurableAdmitted(policy: String) {}
    }

    @Test
    fun inlineReplyLandsInFieldsUnderTheKey() {
        val live = FakeLive()
        var status: String? = null
        // A drop action so it delivers live to the fake session.
        val onTap = buildJsonObject {
            put("action", "chat.reply")
            put("when_offline", "drop")
            putJsonObject("args") { put("thread", "t1") }
        }
        routeNotificationAction(queue(), 262_144, onTap, "reply", "on my way", live) { s, _ ->
            status = s
        }
        assertEquals("accepted", status)
        val p = live.dropped!!
        assertEquals("chat.reply", p.reqString("action"))
        // Authored args preserved.
        assertEquals("t1", p.reqObj("args").reqString("thread"))
        // SPEC 18.5: the typed text is in fields under the key.
        assertEquals("on my way", p.reqObj("fields").reqString("reply"))
    }

    @Test
    fun aPlainActionCarriesNoFields() {
        val live = FakeLive()
        val onTap = buildJsonObject {
            put("action", "task.done")
            put("when_offline", "drop")
        }
        routeNotificationAction(queue(), 262_144, onTap, null, null, live)
        val p = live.dropped!!
        assertEquals("task.done", p.reqString("action"))
        assertTrue("fields" !in p)
    }

    @Test
    fun queuePolicyAdmitsDurablyWithoutASession() {
        val q = queue()
        var status: String? = null
        // A validated queue/wake action always carries ttl_s (SpecValidator).
        val onTap = buildJsonObject {
            put("action", "task.snooze")
            put("when_offline", "queue")
            put("ttl_s", 3600)
        }
        // No live session: a queue action still admits to the durable queue.
        routeNotificationAction(q, 262_144, onTap, null, null, null) { s, _ -> status = s }
        assertEquals("queued", status)
        assertTrue(q.count() > 0)
    }
}
