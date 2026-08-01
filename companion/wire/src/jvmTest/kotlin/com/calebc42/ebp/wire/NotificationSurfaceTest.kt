// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: notification surfaces (SPEC 13.4 + 18.5). A notification:*
// spec is {body: Node, meta?}, never multi-view, with no input drafts; the
// §18.5 meta (channel/ongoing/category/priority/chronometer/actions) and its
// action rules (input/dismiss require a remote on_tap; inline reply forbids
// capture_fields) validate before the surface is accepted.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class NotificationSurfaceTest {

    private fun store() = SurfaceStore(16, 1024)

    private fun body() = buildJsonObject { put("t", "text"); put("text", "Meeting at 3") }

    private fun notif(spec: JsonObject, store: SurfaceStore = store(), rev: Long = 1) =
        store.update("notification:agenda", rev, spec, null, null, null)

    private fun spec(meta: JsonObject? = null) = buildJsonObject {
        put("body", body())
        if (meta != null) put("meta", meta)
    }

    @Test
    fun bodyAndMetaAccepted() {
        val meta = buildJsonObject {
            put("channel", "agenda"); put("ongoing", false)
            put("category", "reminder"); put("priority", "high")
            putJsonObject("chronometer") {
                put("base_ms", 1784700000000L); put("count_down", true)
            }
            putJsonArray("actions") {
                addJsonObject {
                    put("label", "Open")
                    putJsonObject("on_tap") { put("action", "agenda.open") }
                }
            }
        }
        assertEquals("applied", notif(spec(meta)).status)
        // Bare body (no meta) is valid.
        assertEquals("applied", notif(spec(), rev = 2, store = store()).status)
    }

    private fun rejects(spec: JsonObject, fragment: String) {
        try { notif(spec); fail("accepted: $fragment") }
        catch (e: ContentInvalid) {
            assertTrue("${e.reason} @ ${e.path} !~ $fragment",
                e.reason.contains(fragment) || e.path.contains(fragment))
        }
    }

    @Test
    fun shapeRules() {
        // Not {body, meta}: a bare node is not a notification spec.
        rejects(buildJsonObject { put("t", "text"); put("text", "x") },
            "unknown notification member")
        // Multi-view prohibited (13.4).
        rejects(buildJsonObject {
            putJsonObject("views") { put("a", body()) }
            put("initial_view", "a")
        }, "multi-view")
        // Body must be a node.
        rejects(buildJsonObject { putJsonObject("body") { put("no", "t") } }, "must be a node")
        // Unknown meta member.
        rejects(spec(buildJsonObject { put("mystery", 1) }), "unknown meta member")
        // Bad priority.
        rejects(spec(buildJsonObject { put("priority", "urgent") }), "min|low|default|high|max")
        // channel must be an identifier.
        rejects(spec(buildJsonObject { put("channel", "not a channel") }), "identifier")
    }

    @Test
    fun actionRules() {
        fun action(a: JsonObject) = spec(buildJsonObject { put("actions", JsonArray(listOf(a))) })
        // Missing on_tap.
        rejects(action(buildJsonObject { put("label", "X") }), "required")
        // SPEC 14.2/18.5 (audit I10): a notification action's on_tap MUST be a
        // remote action — a builtin has no context-less execution path here and
        // would throw at tap time, so it is rejected outright.
        rejects(action(buildJsonObject {
            put("label", "Reply")
            putJsonObject("on_tap") { put("builtin", "dialog.dismiss") }
            put("input", JsonObject(emptyMap()))
        }), "not a builtin")
        rejects(action(buildJsonObject {
            put("label", "Done"); put("dismiss", true)
            putJsonObject("on_tap") { put("builtin", "dialog.dismiss") }
        }), "not a builtin")
        // An inline reply must not capture_fields.
        rejects(action(buildJsonObject {
            put("label", "Reply")
            putJsonObject("input") { put("hint", "Reply...") }
            putJsonObject("on_tap") {
                put("action", "note.reply")
                putJsonArray("capture_fields") { add("x") }
            }
        }), "must not capture_fields")
        // A well-formed inline-reply action is accepted.
        assertEquals("applied", notif(action(buildJsonObject {
            put("label", "Reply")
            putJsonObject("input") { put("hint", "Reply..."); put("key", "text") }
            putJsonObject("on_tap") { put("action", "note.reply") }
        })).status)
        // SPEC 14.2/18.5: ANY builtin on_tap rejects (I10) — known or unknown.
        rejects(action(buildJsonObject {
            put("label", "X")
            putJsonObject("on_tap") { put("builtin", "no.such.builtin") }
        }), "not a builtin")
        // SPEC 14.1: ttl_s is an integer 1..604800.
        rejects(action(buildJsonObject {
            put("label", "X")
            putJsonObject("on_tap") {
                put("action", "a.b"); put("when_offline", "queue"); put("ttl_s", 0)
            }
        }), "1..604800")
        // SPEC 14.1: a drop action MUST NOT carry ttl_s/dedupe.
        rejects(action(buildJsonObject {
            put("label", "X")
            putJsonObject("on_tap") { put("action", "a.b"); put("ttl_s", 100) }
        }), "invalid for drop")
        // A plain remote action (no input/dismiss) is accepted.
        assertEquals("applied", notif(action(buildJsonObject {
            put("label", "Snooze")
            putJsonObject("on_tap") { put("action", "task.snooze"); put("when_offline", "drop") }
        })).status)
    }

    @Test
    fun notificationHasNoDraftsOrViews() {
        val s = store()
        // current_view and reset_input_ids are invalid for notification.
        try {
            s.update("notification:a", 1, spec(), null, "v", null)
            fail("current_view accepted")
        } catch (e: ContentInvalid) { assertTrue(e.path.contains("current_view")) }
        try {
            s.update("notification:a", 1, spec(), null, null,
                buildJsonArray { add("x") })
            fail("reset_input_ids accepted")
        } catch (e: ContentInvalid) { assertTrue(e.path.contains("reset_input_ids")) }
        // Applied notification contributes no input_state.
        notif(spec(), store = s)
        assertEquals(0, s.inputState().size)
    }
}
