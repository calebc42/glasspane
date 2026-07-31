// SPDX-License-Identifier: GPL-3.0-or-later
// P0 pre-swap pins (PLAN-rf2 §0.2 items 2 and 8): the NUMBER TAXONOMY.
//
// Where org.json is lax and kotlinx.serialization is strict, this file is the
// record of what the wire accepts TODAY. Every frame below is built as raw
// TEXT rather than through JSONObject, because org.json re-spells an integral
// double as an integer on serialization (`put("at_ms", 5000.0).toString()`
// yields `{"at_ms":5000}`) — a JSONObject-built fixture cannot put a genuine
// float on the wire at all.
//
// Post-swap, keep these green by normalizing to Long at ACCEPT time (the
// TriggerValidator.kt:148 shape) or with integrality-checked readers. A naive
// `jsonPrimitive.long` port fails these at tap time, on the device, in the
// hands of a user.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PreSwapNumberTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits() = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64).put("max_reminders", 256)
        .put("max_device_report_bytes", 8192)

    private val invoked = mutableListOf<Pair<String, JSONObject>>()

    private fun engine(
        out: MutableList<JSONObject>,
        reminders: ReminderStore = ReminderStore(MemoryReminderBacking()),
    ): CompanionEngine {
        val wants = listOf("reminders.owner", "presentation.toast", "capabilities")
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("reminders.owner", "presentation.toast",
                "capabilities"),
            surfaceProfiles = JSONObject().put("app", JSONObject()
                .put("node_types", JSONArray(listOf("text", "button")))
                .put("builtins", JSONArray()).put("features", JSONArray())),
            limits = limits(),
            deviceReport = JSONObject()
                .put("caps", JSONArray(listOf("vibrate")))
                .put("trigger_caps", JSONArray())
                .put("permissions", JSONObject()),
            capabilityHandler = CapabilityHandler { cap, args ->
                invoked.add(cap to args)
                CapabilityOutcome.Ok(JSONObject())
            },
            nonceSource = { katSn }),
            reminders = reminders) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(encodeFrame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants)).toString()))
        engine.feed(encodeFrame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken)).toString()))
        engine.feed(encodeFrame(request("r1", "session.ready", JSONObject()).toString()))
        return engine
    }

    /** Feed a hand-written body so number SPELLING reaches the parser intact. */
    private fun CompanionEngine.feedRaw(raw: String) = feed(encodeFrame(raw))

    private fun replyTo(out: List<JSONObject>, id: String) = out.last { it.opt("id") == id }
    private fun errorCode(out: List<JSONObject>, id: String) =
        replyTo(out, id).getJSONObject("error").getInt("code")

    // ------------------------------------- integral doubles ARE accepted (2)

    @Test
    fun integralDoubleAtMsIsAcceptedAndFunctional() {
        val out = mutableListOf<JSONObject>()
        val reminders = ReminderStore(MemoryReminderBacking())
        val engine = engine(out, reminders)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"p1","method":"reminders.set","params":""" +
            """{"owner":"o","reminders":[{"id":"x","title":"T","at_ms":5000.0}]}}""")
        assertEquals(1, replyTo(out, "p1").getJSONObject("result").getInt("count"))
        // Functional, not merely accepted: the reminder is stored and its
        // at_ms reads back as the integer 5000 (org.json getLong truncates a
        // Double; a jsonPrimitive.long port would throw here instead).
        val stored = reminders.reminder("o", "x")
        assertNotNull("an accepted reminder must be stored", stored)
        assertEquals(5_000L, stored!!.getLong("at_ms"))
    }

    @Test
    fun fractionalAtMsIsRejected() {
        // The boundary the acceptance above sits against: integral doubles
        // pass, genuinely fractional ones are 1201 (SPEC 4.3, no coercion).
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"p2","method":"reminders.set","params":""" +
            """{"owner":"o","reminders":[{"id":"x","title":"T","at_ms":1.5}]}}""")
        assertEquals(1201, errorCode(out, "p2"))
        assertEquals("must be a non-negative integer timestamp",
            replyTo(out, "p2").getJSONObject("error").getJSONObject("data")
                .getString("reason"))
    }

    @Test
    fun integralDoubleTtlSIsAcceptedInAnActionDescriptor() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"p3","method":"surface.update","params":""" +
            """{"surface":"app:t","revision":3,"spec":{"t":"button","label":"b",""" +
            """"on_tap":{"action":"a.b","when_offline":"queue","ttl_s":60.0}}}}""")
        assertEquals("applied",
            replyTo(out, "p3").getJSONObject("result").getString("status"))
    }

    @Test
    fun integralDoubleCapabilityArgReachesTheHandler() {
        val out = mutableListOf<JSONObject>()
        invoked.clear()
        val engine = engine(out)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"p4","method":"capability.invoke",""" +
            """"params":{"cap":"vibrate","args":{"ms":100.0}}}""")
        // Whatever the spelling, the host sees an args object it can read a
        // duration from; the swap must not turn this into a crash or a 1201.
        assertTrue("the float-spelled invocation must reach the host",
            invoked.any { it.first == "vibrate" })
        assertEquals(100L, invoked.last().second.getLong("ms"))
    }

    // ---------------------------------------- typed rejections stay typed (8)

    @Test
    fun revisionMustBeAnIntegerNotAFloatOrString() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"r-float","method":"surface.update",""" +
            """"params":{"surface":"app:main","revision":1.0,"spec":{"t":"text","text":"hi"}}}""")
        assertEquals(-32602, errorCode(out, "r-float"))
        engine.feedRaw("""{"jsonrpc":"2.0","id":"r-str","method":"surface.update",""" +
            """"params":{"surface":"app:main","revision":"1","spec":{"t":"text","text":"hi"}}}""")
        // org.json's getLong would coerce "1" to 1; the validator refuses
        // first. THIS is the laxity the swap removes — and it must stay
        // removed at exactly this taxonomy (-32602, not 1201).
        assertEquals(-32602, errorCode(out, "r-str"))
    }

    @Test
    fun toastDurationFloatOrStringIsIgnoredNotCoerced() {
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        val seen = mutableListOf<Pair<String, Long?>>()
        engine.toastListener = { text, d -> seen.add(text to d) }
        // Control: an integer duration presents.
        engine.feedRaw("""{"jsonrpc":"2.0","method":"toast.show","params":{"text":"int","duration_s":3}}""")
        assertEquals("int" to 3L, seen.last())
        // A float or string duration makes the whole notification invalid;
        // it is DROPPED (best-effort, SPEC 18.2), never coerced to 2 or 5.
        val before = seen.size
        engine.feedRaw("""{"jsonrpc":"2.0","method":"toast.show","params":{"text":"flt","duration_s":2.0}}""")
        engine.feedRaw("""{"jsonrpc":"2.0","method":"toast.show","params":{"text":"str","duration_s":"5"}}""")
        assertEquals("a float/string duration_s must present nothing",
            before, seen.size)
        assertEquals(SessionState.READY, engine.state)
    }

    @Test
    fun nonStringMethodClosesTheConnection() {
        // Recorded because the swap MAY flip it deliberately: today a
        // non-string `method` is a malformed envelope and the connection
        // closes with no frame. C2's Envelope rewrite routes it to -32600
        // instead — a conscious taxonomy change, and this pin is where that
        // decision becomes visible rather than accidental.
        val out = mutableListOf<JSONObject>()
        val engine = engine(out)
        assertEquals(SessionState.READY, engine.state)
        val before = out.size
        engine.feedRaw("""{"jsonrpc":"2.0","id":"m5","method":5,"params":{}}""")
        assertEquals(SessionState.CLOSED, engine.state)
        assertEquals("today the close is silent — no error frame", before, out.size)
    }
}
