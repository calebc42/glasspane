// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: pie menus (SPEC 18.3). pie_menu.show/dismiss are READY
// notifications gated on presentation.pie-menu: validation, max_pie_menus
// (replace vs new), index injection on selection, drop-only context-less
// events, ephemeral dismiss-on-close.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PieMenuTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits(maxPie: Long = 1) = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64).put("max_pie_menus", maxPie)

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    private fun engine(out: MutableList<JSONObject>,
                       presented: MutableList<Pair<String, JSONObject?>>,
                       maxPie: Long = 1, grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("presentation.pie-menu") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("presentation.pie-menu"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(maxPie), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.pieMenuListener = { id, spec -> presented.add(id to spec) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        return engine
    }

    private fun leaf(action: String) = JSONObject().put("label", "cat")
        .put("on_tap", JSONObject().put("action", action))

    private fun nested(vararg itemActions: String): JSONObject {
        val items = JSONArray()
        itemActions.forEachIndexed { j, a -> items.put(JSONObject().put("label", "i$j")
            .put("on_tap", JSONObject().put("action", a))) }
        return JSONObject().put("label", "parent").put("items", items)
    }

    private fun show(engine: CompanionEngine, menuId: String, categories: JSONArray,
                     centerLabel: String? = null) = engine.feed(frame(notification(
        "pie_menu.show", JSONObject().put("menu_id", menuId)
            .put("categories", categories)
            .also { if (centerLabel != null) it.put("center_label", centerLabel) })))

    @Test
    fun showValidatesPresentsAndDismisses() {
        val out = mutableListOf<JSONObject>()
        val presented = mutableListOf<Pair<String, JSONObject?>>()
        val engine = engine(out, presented)
        show(engine, "capture", JSONArray().put(leaf("demo.todo")), "Capture")
        assertEquals("capture", presented.single().first)
        assertEquals("Capture", presented.single().second!!.getString("center_label"))
        // Explicit dismiss.
        engine.feed(frame(notification("pie_menu.dismiss",
            JSONObject().put("menu_id", "capture"))))
        assertEquals("capture" to null, presented.last())
        // Dismissing an unknown id is a no-op.
        val before = presented.size
        engine.feed(frame(notification("pie_menu.dismiss",
            JSONObject().put("menu_id", "nope"))))
        assertEquals(before, presented.size)
    }

    @Test
    fun invalidMenuIdIsDropped() {
        val presented = mutableListOf<Pair<String, JSONObject?>>()
        val engine = engine(mutableListOf(), presented)
        // SPEC 4.4/18.3: menu_id must be a valid identifier — a spaced string
        // and an over-128-char one are both dropped, not presented.
        show(engine, "not a menu id", JSONArray().put(leaf("demo.todo")))
        show(engine, "m".repeat(129), JSONArray().put(leaf("demo.todo")))
        assertTrue(presented.isEmpty())
        // A valid id still presents.
        show(engine, "capture", JSONArray().put(leaf("demo.todo")))
        assertEquals("capture", presented.single().first)
    }

    @Test
    fun leafSelectionInjectsCategoryIndex() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, mutableListOf())
        show(engine, "m", JSONArray().put(leaf("demo.a")).put(leaf("demo.b")))
        engine.selectPieMenu("m", 1)
        val event = out.last { it.opt("method") == "event.action" }.getJSONObject("params")
        assertEquals("demo.b", event.getString("action"))
        // SPEC 14.4: pie-menu events carry no surface/revision context.
        assertTrue(!event.has("surface") && !event.has("revision_seen"))
        val args = event.getJSONObject("args")
        assertEquals("m", args.getString("menu_id"))
        assertEquals(1, args.getInt("category_index"))
        assertTrue(!args.has("item_index"))
    }

    @Test
    fun nestedSelectionInjectsItemIndex() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out, mutableListOf())
        show(engine, "m", JSONArray().put(nested("demo.x", "demo.y")))
        engine.selectPieMenu("m", 0, 1)
        val args = out.last { it.opt("method") == "event.action" }
            .getJSONObject("params").getJSONObject("args")
        assertEquals(0, args.getInt("category_index"))
        assertEquals(1, args.getInt("item_index"))
        // The menu was dismissed on selection (ephemeral).
        val second = out.size
        engine.selectPieMenu("m", 0, 1) // gone: no new event
        assertEquals(second, out.size)
    }

    @Test
    fun invalidMenusAreDropped() {
        val out = mutableListOf<JSONObject>()
        val presented = mutableListOf<Pair<String, JSONObject?>>()
        val engine = engine(out, presented)
        // A category with both items and on_tap.
        show(engine, "a", JSONArray().put(leaf("x").put("items", JSONArray())))
        // A queued (not drop) descriptor.
        show(engine, "b", JSONArray().put(JSONObject().put("label", "c")
            .put("on_tap", JSONObject().put("action", "x")
                .put("when_offline", "queue").put("ttl_s", 60))))
        // An authored injected-key conflict.
        show(engine, "c", JSONArray().put(JSONObject().put("label", "c")
            .put("on_tap", JSONObject().put("action", "x")
                .put("args", JSONObject().put("menu_id", "sneaky")))))
        // Eleven categories.
        val many = JSONArray()
        repeat(11) { many.put(leaf("x")) }
        show(engine, "d", many)
        assertTrue(presented.isEmpty())
        // SPEC 18.3 (amendment #132): each drop is REPORTED, not silent — an
        // author's invalid menu previously produced nothing on either side.
        val invalid = out.filter {
            it.optString("method") == "log.error" &&
                it.optJSONObject("params")?.optJSONObject("data")
                    ?.optString("reason") == "pie-menu-invalid"
        }
        assertEquals(4, invalid.size)
        val params = invalid.first().getJSONObject("params")
        assertEquals(1201, params.getInt("code"))
        assertEquals("content-invalid", params.getJSONObject("data").getString("kind"))
        // data.path names the offending member.
        assertEquals("categories", params.getJSONObject("data").getString("path"))
    }

    @Test
    fun aMalformedMenuIdIsReportedNotJustDropped() {
        val out = mutableListOf<JSONObject>()
        val presented = mutableListOf<Pair<String, JSONObject?>>()
        val engine = engine(out, presented)
        show(engine, "has space", JSONArray().put(leaf("x")))
        assertTrue(presented.isEmpty())
        val invalid = out.single {
            it.optString("method") == "log.error" &&
                it.optJSONObject("params")?.optJSONObject("data")
                    ?.optString("reason") == "pie-menu-invalid"
        }
        assertEquals("menu_id",
            invalid.getJSONObject("params").getJSONObject("data").getString("path"))
    }

    @Test
    fun limitDropsNewButAllowsReplace() {
        val out = mutableListOf<JSONObject>()
        val presented = mutableListOf<Pair<String, JSONObject?>>()
        val engine = engine(out, presented, maxPie = 1)
        show(engine, "m1", JSONArray().put(leaf("a")))
        // A second distinct id over the limit: dropped + log.error.
        show(engine, "m2", JSONArray().put(leaf("b")))
        assertEquals(1, presented.size)
        val err = out.last { it.opt("method") == "log.error" }.getJSONObject("params")
        assertEquals("pie-menu-limit", err.getJSONObject("data").getString("reason"))
        // Replacing the existing id stays legal at the limit.
        show(engine, "m1", JSONArray().put(leaf("c")))
        assertEquals("m1", presented.last().first)
        assertEquals(2, presented.size)
    }

    @Test
    fun closeDismissesAllPieMenus() {
        val out = mutableListOf<JSONObject>()
        val presented = mutableListOf<Pair<String, JSONObject?>>()
        val engine = engine(out, presented, maxPie = 4)
        show(engine, "a", JSONArray().put(leaf("x")))
        show(engine, "b", JSONArray().put(leaf("y")))
        engine.close("transport closed")
        assertEquals(listOf("a", "b"),
            presented.filter { it.second == null }.map { it.first })
    }

    @Test
    fun ungrantedPieMenuIsDropped() {
        val out = mutableListOf<JSONObject>()
        val presented = mutableListOf<Pair<String, JSONObject?>>()
        val engine = engine(out, presented, grant = false)
        show(engine, "m", JSONArray().put(leaf("x")))
        assertTrue(presented.isEmpty())
    }
}
