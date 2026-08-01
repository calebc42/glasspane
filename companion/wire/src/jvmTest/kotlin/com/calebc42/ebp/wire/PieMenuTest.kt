// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: pie menus (SPEC 18.3). pie_menu.show/dismiss are READY
// notifications gated on presentation.pie-menu: validation, max_pie_menus
// (replace vs new), index injection on selection, drop-only context-less
// events, ephemeral dismiss-on-close.
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
import org.junit.Test

class PieMenuTest {

    private fun engine(out: MutableList<JsonObject>,
                       presented: MutableList<Pair<String, JsonObject?>>,
                       maxPie: Long = 1, grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("presentation.pie-menu") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("presentation.pie-menu"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    putJsonArray("node_types") { add("text") }
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_pie_menus" to maxPie),
            nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.pieMenuListener = { id, spec -> presented.add(id to spec) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        return engine
    }

    private fun leaf(action: String) = buildJsonObject {
        put("label", "cat")
        putJsonObject("on_tap") { put("action", action) }
    }

    private fun nested(vararg itemActions: String): JsonObject = buildJsonObject {
        put("label", "parent")
        putJsonArray("items") {
            itemActions.forEachIndexed { j, a ->
                addJsonObject {
                    put("label", "i$j")
                    putJsonObject("on_tap") { put("action", a) }
                }
            }
        }
    }

    private fun show(engine: CompanionEngine, menuId: String, categories: JsonArray,
                     centerLabel: String? = null) = engine.feed(frame(notification(
        "pie_menu.show", buildJsonObject {
            put("menu_id", menuId)
            put("categories", categories)
            if (centerLabel != null) put("center_label", centerLabel)
        })))

    @Test
    fun showValidatesPresentsAndDismisses() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = engine(out, presented)
        show(engine, "capture", buildJsonArray { add(leaf("demo.todo")) }, "Capture")
        assertEquals("capture", presented.single().first)
        assertEquals("Capture", presented.single().second!!.reqString("center_label"))
        // Explicit dismiss.
        engine.feed(frame(notification("pie_menu.dismiss",
            buildJsonObject { put("menu_id", "capture") })))
        assertEquals("capture" to null, presented.last())
        // Dismissing an unknown id is a no-op.
        val before = presented.size
        engine.feed(frame(notification("pie_menu.dismiss",
            buildJsonObject { put("menu_id", "nope") })))
        assertEquals(before, presented.size)
    }

    @Test
    fun invalidMenuIdIsDropped() {
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = engine(mutableListOf(), presented)
        // SPEC 4.4/18.3: menu_id must be a valid identifier — a spaced string
        // and an over-128-char one are both dropped, not presented.
        show(engine, "not a menu id", buildJsonArray { add(leaf("demo.todo")) })
        show(engine, "m".repeat(129), buildJsonArray { add(leaf("demo.todo")) })
        assertTrue(presented.isEmpty())
        // A valid id still presents.
        show(engine, "capture", buildJsonArray { add(leaf("demo.todo")) })
        assertEquals("capture", presented.single().first)
    }

    @Test
    fun leafSelectionInjectsCategoryIndex() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, mutableListOf())
        show(engine, "m", buildJsonArray { add(leaf("demo.a")); add(leaf("demo.b")) })
        engine.selectPieMenu("m", 1)
        val event = out.last { it.stringOrNull("method") == "event.action" }.reqObj("params")
        assertEquals("demo.b", event.reqString("action"))
        // SPEC 14.4: pie-menu events carry no surface/revision context.
        assertTrue("surface" !in event && "revision_seen" !in event)
        val args = event.reqObj("args")
        assertEquals("m", args.reqString("menu_id"))
        assertEquals(1L, args.reqLong("category_index"))
        assertTrue("item_index" !in args)
    }

    @Test
    fun nestedSelectionInjectsItemIndex() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out, mutableListOf())
        show(engine, "m", buildJsonArray { add(nested("demo.x", "demo.y")) })
        engine.selectPieMenu("m", 0, 1)
        val args = out.last { it.stringOrNull("method") == "event.action" }
            .reqObj("params").reqObj("args")
        assertEquals(0L, args.reqLong("category_index"))
        assertEquals(1L, args.reqLong("item_index"))
        // The menu was dismissed on selection (ephemeral).
        val second = out.size
        engine.selectPieMenu("m", 0, 1) // gone: no new event
        assertEquals(second, out.size)
    }

    @Test
    fun invalidMenusAreDropped() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = engine(out, presented)
        // A category with both items and on_tap.
        show(engine, "a", buildJsonArray {
            add(leaf("x").with("items", JsonArray(emptyList())))
        })
        // A queued (not drop) descriptor.
        show(engine, "b", buildJsonArray {
            addJsonObject {
                put("label", "c")
                putJsonObject("on_tap") {
                    put("action", "x")
                    put("when_offline", "queue")
                    put("ttl_s", 60)
                }
            }
        })
        // An authored injected-key conflict.
        show(engine, "c", buildJsonArray {
            addJsonObject {
                put("label", "c")
                putJsonObject("on_tap") {
                    put("action", "x")
                    putJsonObject("args") { put("menu_id", "sneaky") }
                }
            }
        })
        // Eleven categories.
        val many = buildJsonArray { repeat(11) { add(leaf("x")) } }
        show(engine, "d", many)
        assertTrue(presented.isEmpty())
        // SPEC 18.3 (amendment #132): each drop is REPORTED, not silent — an
        // author's invalid menu previously produced nothing on either side.
        val invalid = out.filter {
            it.stringOrNull("method") == "log.error" &&
                it.objOrNull("params")?.objOrNull("data")
                    ?.stringOrNull("reason") == "pie-menu-invalid"
        }
        assertEquals(4, invalid.size)
        val params = invalid.first().reqObj("params")
        assertEquals(1201L, params.reqLong("code"))
        assertEquals("content-invalid", params.reqObj("data").reqString("kind"))
        // data.path names the offending member.
        assertEquals("categories", params.reqObj("data").reqString("path"))
    }

    @Test
    fun aMalformedMenuIdIsReportedNotJustDropped() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = engine(out, presented)
        show(engine, "has space", buildJsonArray { add(leaf("x")) })
        assertTrue(presented.isEmpty())
        val invalid = out.single {
            it.stringOrNull("method") == "log.error" &&
                it.objOrNull("params")?.objOrNull("data")
                    ?.stringOrNull("reason") == "pie-menu-invalid"
        }
        assertEquals("menu_id",
            invalid.reqObj("params").reqObj("data").reqString("path"))
    }

    @Test
    fun limitDropsNewButAllowsReplace() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = engine(out, presented, maxPie = 1)
        show(engine, "m1", buildJsonArray { add(leaf("a")) })
        // A second distinct id over the limit: dropped + log.error.
        show(engine, "m2", buildJsonArray { add(leaf("b")) })
        assertEquals(1, presented.size)
        val err = out.last { it.stringOrNull("method") == "log.error" }.reqObj("params")
        assertEquals("pie-menu-limit", err.reqObj("data").reqString("reason"))
        // Replacing the existing id stays legal at the limit.
        show(engine, "m1", buildJsonArray { add(leaf("c")) })
        assertEquals("m1", presented.last().first)
        assertEquals(2, presented.size)
    }

    @Test
    fun closeDismissesAllPieMenus() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = engine(out, presented, maxPie = 4)
        show(engine, "a", buildJsonArray { add(leaf("x")) })
        show(engine, "b", buildJsonArray { add(leaf("y")) })
        engine.close("transport closed")
        assertEquals(listOf("a", "b"),
            presented.filter { it.second == null }.map { it.first })
    }

    @Test
    fun ungrantedPieMenuIsDropped() {
        val out = mutableListOf<JsonObject>()
        val presented = mutableListOf<Pair<String, JsonObject?>>()
        val engine = engine(out, presented, grant = false)
        show(engine, "m", buildJsonArray { add(leaf("x")) })
        assertTrue(presented.isEmpty())
    }
}
