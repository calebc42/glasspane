// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: toasts (SPEC 18.2). toast.show is a best-effort READY
// notification, gated on presentation.toast, with duration_s in 1..10.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ToastTest {

    private fun readyEngine(seen: MutableList<Pair<String, Long?>>,
                            grant: Boolean = true): CompanionEngine {
        val wants = if (grant) listOf("presentation.toast") else emptyList()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("presentation.toast"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(listOf("text").map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_rich_spans" to 4096, "max_table_cells" to 4096),
            nonceSource = { katSn })) { }
        engine.toastListener = { text, d -> seen.add(text to d) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        engine.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        return engine
    }

    private fun toast(vararg kv: Pair<String, JsonElement>) = frame(notification(
        "toast.show", buildJsonObject { kv.forEach { put(it.first, it.second) } }))

    @Test
    fun toastDuringSyncingIsDropped() {
        val seen = mutableListOf<Pair<String, Long?>>()
        // Reach SYNCING (auth ok) but NOT READY — no session.ready.
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1", pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("presentation.toast"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(listOf("text").map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_rich_spans" to 4096, "max_table_cells" to 4096),
            nonceSource = { katSn })) { }
        engine.toastListener = { text, d -> seen.add(text to d) }
        engine.feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, listOf("presentation.toast")))))
        engine.feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        // SPEC 10.1: a READY-only toast.show arriving during SYNCING is dropped.
        engine.feed(toast("text" to JsonPrimitive("Saved")))
        assertTrue(seen.isEmpty())
    }

    @Test
    fun plainToastAndDurationBounds() {
        val seen = mutableListOf<Pair<String, Long?>>()
        val engine = readyEngine(seen)
        engine.feed(toast("text" to JsonPrimitive("Saved")))
        assertEquals("Saved" to null, seen.last())
        engine.feed(toast("text" to JsonPrimitive("Done"), "duration_s" to JsonPrimitive(3)))
        assertEquals("Done" to 3L, seen.last())
        // Out-of-range durations are dropped (SPEC 18.2: 1..10).
        val before = seen.size
        engine.feed(toast("text" to JsonPrimitive("x"), "duration_s" to JsonPrimitive(0)))
        engine.feed(toast("text" to JsonPrimitive("x"), "duration_s" to JsonPrimitive(11)))
        engine.feed(toast("duration_s" to JsonPrimitive(3))) // missing required text
        assertEquals(before, seen.size)
        // A best-effort notification never produces a frame.
        assertEquals(SessionState.READY, engine.state)
    }

    @Test
    fun ungrantedToastIsDropped() {
        val seen = mutableListOf<Pair<String, Long?>>()
        val engine = readyEngine(seen, grant = false)
        engine.feed(toast("text" to JsonPrimitive("nope")))
        assertEquals(0, seen.size)
    }

    @Test
    fun toastBeforeReadyIsDropped() {
        val seen = mutableListOf<Pair<String, Long?>>()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "k", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("presentation.toast"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(NODE_SCHEMA.keys.map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = testLimits("max_rich_spans" to 4096, "max_table_cells" to 4096),
            nonceSource = { katSn })) { }
        engine.toastListener = { t, d -> seen.add(t to d) }
        // Pre-auth: SPEC 10.1 drops the notification.
        engine.feed(toast("text" to JsonPrimitive("early")))
        assertEquals(0, seen.size)
    }
}
