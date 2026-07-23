// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: notification surfaces (SPEC 13.4 + 18.5). A notification:*
// spec is {body: Node, meta?}, never multi-view, with no input drafts; the
// §18.5 meta (channel/ongoing/category/priority/chronometer/actions) and its
// action rules (input/dismiss require a remote on_tap; inline reply forbids
// capture_fields) validate before the surface is accepted.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class NotificationSurfaceTest {

    private fun store() = SurfaceStore(16, 1024)

    private fun body() = JSONObject().put("t", "text").put("text", "Meeting at 3")

    private fun notif(spec: JSONObject, store: SurfaceStore = store(), rev: Long = 1) =
        store.update("notification:agenda", rev, spec, null, null, null)

    private fun spec(meta: JSONObject? = null) = JSONObject().put("body", body())
        .also { if (meta != null) it.put("meta", meta) }

    @Test
    fun bodyAndMetaAccepted() {
        val meta = JSONObject().put("channel", "agenda").put("ongoing", false)
            .put("category", "reminder").put("priority", "high")
            .put("chronometer", JSONObject().put("base_ms", 1784700000000L)
                .put("count_down", true))
            .put("actions", JSONArray().put(JSONObject().put("label", "Open")
                .put("on_tap", JSONObject().put("action", "agenda.open"))))
        assertEquals("applied", notif(spec(meta)).status)
        // Bare body (no meta) is valid.
        assertEquals("applied", notif(spec(), rev = 2, store = store()).status)
    }

    private fun rejects(spec: JSONObject, fragment: String) {
        try { notif(spec); fail("accepted: $fragment") }
        catch (e: ContentInvalid) {
            assertTrue("${e.reason} @ ${e.path} !~ $fragment",
                e.reason.contains(fragment) || e.path.contains(fragment))
        }
    }

    @Test
    fun shapeRules() {
        // Not {body, meta}: a bare node is not a notification spec.
        rejects(JSONObject().put("t", "text").put("text", "x"), "unknown notification member")
        // Multi-view prohibited (13.4).
        rejects(JSONObject().put("views", JSONObject().put("a", body()))
            .put("initial_view", "a"), "multi-view")
        // Body must be a node.
        rejects(JSONObject().put("body", JSONObject().put("no", "t")), "must be a node")
        // Unknown meta member.
        rejects(spec(JSONObject().put("mystery", 1)), "unknown meta member")
        // Bad priority.
        rejects(spec(JSONObject().put("priority", "urgent")), "min|low|default|high|max")
        // channel must be an identifier.
        rejects(spec(JSONObject().put("channel", "not a channel")), "identifier")
    }

    @Test
    fun actionRules() {
        fun action(a: JSONObject) = spec(JSONObject().put("actions", JSONArray().put(a)))
        // Missing on_tap.
        rejects(action(JSONObject().put("label", "X")), "required")
        // input requires a remote on_tap (a builtin is not remote).
        rejects(action(JSONObject().put("label", "Reply")
            .put("on_tap", JSONObject().put("builtin", "dialog.dismiss"))
            .put("input", JSONObject())), "remote action for input/dismiss")
        // dismiss:true likewise requires remote.
        rejects(action(JSONObject().put("label", "Done").put("dismiss", true)
            .put("on_tap", JSONObject().put("builtin", "dialog.dismiss"))),
            "remote action for input/dismiss")
        // An inline reply must not capture_fields.
        rejects(action(JSONObject().put("label", "Reply")
            .put("input", JSONObject().put("hint", "Reply..."))
            .put("on_tap", JSONObject().put("action", "note.reply")
                .put("capture_fields", JSONArray().put("x")))),
            "must not capture_fields")
        // A well-formed inline-reply action is accepted.
        assertEquals("applied", notif(action(JSONObject().put("label", "Reply")
            .put("input", JSONObject().put("hint", "Reply...").put("key", "text"))
            .put("on_tap", JSONObject().put("action", "note.reply")))).status)
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
                JSONArray().put("x"))
            fail("reset_input_ids accepted")
        } catch (e: ContentInvalid) { assertTrue(e.path.contains("reset_input_ids")) }
        // Applied notification contributes no input_state.
        notif(spec(), store = s)
        assertEquals(0, s.inputState().length())
    }
}
