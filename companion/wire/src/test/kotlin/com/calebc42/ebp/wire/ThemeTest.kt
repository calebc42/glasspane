// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: themes (SPEC 18.4 incl. amendment #36). theme.set is a
// complete replacement; `dark` is forced-polarity or absent=follow-system;
// `colors`/`syntax` are role maps or null-to-clear; gated on theme.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemeTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    data class Applied(val dark: Boolean?, val colors: JSONObject?, val syntax: JSONObject?)

    private fun limits() = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64)

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    private fun readyEngine(applied: MutableList<Applied>,
                            grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("theme") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(), nonceSource = { katSn })) { }
        engine.themeListener = { d, c, s -> applied.add(Applied(d, c, s)) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JSONObject())))
        return engine
    }

    private fun themeSet(body: JSONObject) = frame(notification("theme.set", body))

    @Test
    fun darkTriStateAndCompleteReplacement() {
        val applied = mutableListOf<Applied>()
        val engine = readyEngine(applied)
        // Forced dark.
        engine.feed(themeSet(JSONObject().put("dark", true)
            .put("colors", JSONObject().put("primary", "#3366ff"))))
        assertEquals(true, applied.last().dark)
        assertEquals("#3366ff", applied.last().colors!!.getString("primary"))
        // Forced light.
        engine.feed(themeSet(JSONObject().put("dark", false)))
        assertEquals(false, applied.last().dark)
        // Amendment #36: dark absent => follow-system (null), and this is a
        // complete replacement — the previous colors are gone.
        engine.feed(themeSet(JSONObject().put("colors", JSONObject().put("primary", "#00ff00"))))
        assertNull(applied.last().dark)
        assertEquals("#00ff00", applied.last().colors!!.getString("primary"))
        // The stored theme reflects the latest replacement.
        assertEquals(JSONObject.NULL, engine.currentTheme().get("dark"))
    }

    @Test
    fun nullClearsColorMirror() {
        val applied = mutableListOf<Applied>()
        val engine = readyEngine(applied)
        engine.feed(themeSet(JSONObject().put("colors", JSONObject().put("primary", "#111"))))
        assertEquals("#111", applied.last().colors!!.getString("primary"))
        // colors: null selects the Companion's native scheme (clears mirror).
        engine.feed(themeSet(JSONObject().put("colors", JSONObject.NULL)))
        assertNull(applied.last().colors)
        assertEquals(JSONObject.NULL, engine.currentTheme().get("colors"))
    }

    @Test
    fun ungrantedThemeIsDropped() {
        val applied = mutableListOf<Applied>()
        val engine = readyEngine(applied, grant = false)
        engine.feed(themeSet(JSONObject().put("dark", true)))
        assertTrue(applied.isEmpty())
    }
}
