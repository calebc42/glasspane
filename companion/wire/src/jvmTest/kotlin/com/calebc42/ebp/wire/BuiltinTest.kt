// SPDX-License-Identifier: GPL-3.0-or-later
// W9 conformance: SPEC 14.2 Companion-local builtins. view.switch switches
// the multi-view surface locally and (while READY) reports view.switched with
// when_offline-drop semantics; an unknown view or single-view surface is a
// safe no-op; trigger.fire routes to the manual-trigger pipeline; the host
// builtins (clipboard/share/settings) reach the host listener.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BuiltinTest {

    private fun readyEngine(out: MutableList<JsonObject>): CompanionEngine {
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(listOf("text", "button").map(::JsonPrimitive)))
                    put("builtins", JsonArray(listOf(
                        "view.switch", "companion.settings.open", "clipboard.copy")
                        .map(::JsonPrimitive)))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits(), nonceSource = { katSn })) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, emptyList()))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        assertEquals(SessionState.READY, engine.state)
        return engine
    }

    private fun multiViewSpec() = buildJsonObject {
        put("initial_view", "main")
        putJsonObject("views") {
            putJsonObject("main") { put("t", "text"); put("text", "m") }
            putJsonObject("detail") { put("t", "text"); put("text", "d") }
        }
    }

    @Test
    fun viewSwitchSwitchesLocallyAndReportsWhileReady() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 1)
            put("spec", multiViewSpec())
        })))
        // Attach AFTER the update (which notifies the listener itself).
        val changed = mutableListOf<String>()
        engine.surfaceListener = { changed.add(it) }
        // The builtin switches the local view and notifies the host.
        engine.dispatchAction("app:main",
            buildJsonObject { put("builtin", "view.switch"); put("view", "detail") }, null)
        assertEquals(listOf("app:main"), changed)
        // SPEC 14.2: while READY, view.switched reports with args.view.
        val event = out.last { it.stringOrNull("method") == "event.action" }
            .reqObj("params")
        assertEquals("view.switched", event.reqString("action"))
        assertEquals("app:main", event.reqString("surface"))
        assertEquals("detail", event.reqObj("args").reqString("view"))
        assertTrue(EbpAuth.isValidNonce(event.reqString("event_id")))
    }

    @Test
    fun viewSwitchInvalidContextIsANoOp() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        // A single-view surface: view.switch is invalid context — no-op.
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 1)
            put("spec", buildJsonObject { put("t", "text"); put("text", "solo") })
        })))
        val changed = mutableListOf<String>()
        engine.surfaceListener = { changed.add(it) }
        val before = out.size
        engine.dispatchAction("app:main",
            buildJsonObject { put("builtin", "view.switch"); put("view", "detail") }, null)
        assertTrue(changed.isEmpty())
        assertEquals(before, out.size)
        // A multi-view surface but an unknown view: also a no-op.
        engine.feed(frame(request("s2", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 2)
            put("spec", multiViewSpec())
        })))
        changed.clear() // the update itself notified the listener
        val before2 = out.size
        engine.dispatchAction("app:main",
            buildJsonObject { put("builtin", "view.switch"); put("view", "nope") }, null)
        assertTrue(changed.isEmpty())
        assertEquals(before2, out.size)
    }

    @Test
    fun hostBuiltinsReachTheHostListener() {
        val out = mutableListOf<JsonObject>()
        val engine = readyEngine(out)
        engine.feed(frame(request("s1", "surface.update", buildJsonObject {
            put("surface", "app:main"); put("revision", 1)
            put("spec", buildJsonObject { put("t", "text"); put("text", "x") })
        })))
        val seen = mutableListOf<Pair<String, String>>()
        engine.hostBuiltinListener = { name, d ->
            seen.add(name to d.stringOr("text"))
        }
        engine.dispatchAction("app:main",
            buildJsonObject { put("builtin", "clipboard.copy"); put("text", "hello") }, null)
        engine.dispatchAction("app:main",
            buildJsonObject { put("builtin", "companion.settings.open") }, null)
        assertEquals(listOf("clipboard.copy" to "hello",
            "companion.settings.open" to ""), seen)
        // Builtins never create event.action frames of their own.
        assertTrue(out.events().isEmpty())
    }
}
