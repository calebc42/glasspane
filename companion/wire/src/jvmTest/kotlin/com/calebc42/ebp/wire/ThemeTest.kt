// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: themes (SPEC 18.4 incl. amendment #36). theme.set is a
// complete replacement; `dark` is forced-polarity or absent=follow-system;
// `colors`/`syntax` are role maps or null-to-clear; gated on theme.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemeTest {

    data class Applied(val dark: Boolean?, val colors: JsonObject?, val syntax: JsonObject?)

    private fun readyEngine(applied: MutableList<Applied>,
                            grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("theme") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    putJsonArray("node_types") { add("text") }
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits(), nonceSource = { katSn })) { }
        engine.themeListener = { d, c, s -> applied.add(Applied(d, c, s)) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        return engine
    }

    private fun themeSet(body: JsonObject) = frame(notification("theme.set", body))

    @Test
    fun darkTriStateAndCompleteReplacement() {
        val applied = mutableListOf<Applied>()
        val engine = readyEngine(applied)
        // Forced dark.
        engine.feed(themeSet(buildJsonObject {
            put("dark", true)
            putJsonObject("colors") { put("primary", "#3366ff") }
        }))
        assertEquals(true, applied.last().dark)
        assertEquals("#3366ff", applied.last().colors!!.reqString("primary"))
        // Forced light.
        engine.feed(themeSet(buildJsonObject { put("dark", false) }))
        assertEquals(false, applied.last().dark)
        // Amendment #36: dark absent => follow-system (null), and this is a
        // complete replacement — the previous colors are gone.
        engine.feed(themeSet(buildJsonObject {
            putJsonObject("colors") { put("primary", "#00ff00") }
        }))
        assertNull(applied.last().dark)
        assertEquals("#00ff00", applied.last().colors!!.reqString("primary"))
        // The stored theme reflects the latest replacement.
        assertEquals(JsonNull, engine.currentTheme()["dark"])
    }

    @Test
    fun nullClearsColorMirror() {
        val applied = mutableListOf<Applied>()
        val engine = readyEngine(applied)
        engine.feed(themeSet(buildJsonObject {
            putJsonObject("colors") { put("primary", "#111") }
        }))
        assertEquals("#111", applied.last().colors!!.reqString("primary"))
        // colors: null selects the Companion's native scheme (clears mirror).
        engine.feed(themeSet(buildJsonObject { put("colors", JsonNull) }))
        assertNull(applied.last().colors)
        assertEquals(JsonNull, engine.currentTheme()["colors"])
    }

    @Test
    fun ungrantedThemeIsDropped() {
        val applied = mutableListOf<Applied>()
        val engine = readyEngine(applied, grant = false)
        engine.feed(themeSet(buildJsonObject { put("dark", true) }))
        assertTrue(applied.isEmpty())
    }
}
