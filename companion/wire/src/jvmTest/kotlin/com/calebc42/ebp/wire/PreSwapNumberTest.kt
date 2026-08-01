// SPDX-License-Identifier: GPL-3.0-or-later
// P0 pre-swap pins (PLAN-rf2 §0.2 items 2 and 8): the NUMBER TAXONOMY.
//
// Where org.json was lax and kotlinx.serialization is strict, this file is the
// record of what the wire accepts. Every frame below is built as raw TEXT
// rather than through a builder, because org.json re-spelled an integral
// double as an integer on serialization (`put("at_ms", 5000.0).toString()`
// yielded `{"at_ms":5000}`) — a builder-built fixture could not put a genuine
// float on the wire at all; raw text still cannot be second-guessed by any
// serializer, so the fixtures stay text after the swap too.
//
// Post-swap these stay green because the readers normalize by VALUE at
// ACCEPT time (integralLongOrNull, the TriggerValidator shape). A naive
// `jsonPrimitive.long` port fails these at tap time, on the device, in the
// hands of a user.
//
// C5 note: this file keeps every helper LOCAL on purpose (PLAN-rf2 §0.1's
// "a single file to keep green" hermeticity) — do not adopt TestSupport here.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PreSwapNumberTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits(): JsonObject = buildJsonObject {
        put("max_frame_bytes", 4_194_304); put("max_queued_events", 256)
        put("max_queued_bytes", 8_388_608); put("max_event_bytes", 262_144)
        put("max_surfaces", 16); put("max_surface_ids", 1024)
        put("max_field_bytes", 65_536); put("max_input_state_bytes", 262_144)
        put("max_capture_fields", 64); put("max_reminders", 256)
        put("max_device_report_bytes", 8192)
    }

    private val invoked = mutableListOf<Pair<String, JsonObject>>()

    private fun engine(
        out: MutableList<JsonObject>,
        reminders: ReminderStore = ReminderStore(MemoryReminderBacking()),
    ): CompanionEngine {
        val wants = listOf("reminders.owner", "presentation.toast", "capabilities")
        val engine = CompanionEngine(CompanionConfig(
            serverName = "kat", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("reminders.owner", "presentation.toast",
                "capabilities"),
            surfaceProfiles = buildJsonObject {
                putJsonObject("app") {
                    put("node_types", JsonArray(listOf("text", "button").map(::JsonPrimitive)))
                    put("builtins", JsonArray(emptyList()))
                    put("features", JsonArray(emptyList()))
                }
            },
            limits = limits(),
            deviceReport = buildJsonObject {
                put("caps", JsonArray(listOf(JsonPrimitive("vibrate"))))
                put("trigger_caps", JsonArray(emptyList()))
                put("permissions", JsonObject(emptyMap()))
            },
            capabilityHandler = CapabilityHandler { cap, args ->
                invoked.add(cap to args)
                CapabilityOutcome.Ok(JsonObject(emptyMap()))
            },
            nonceSource = { katSn }),
            reminders = reminders) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }
        }
        engine.feed(encodeFrame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, wants)).toString()))
        engine.feed(encodeFrame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken)).toString()))
        engine.feed(encodeFrame(request("r1", "session.ready",
            JsonObject(emptyMap())).toString()))
        return engine
    }

    /** Feed a hand-written body so number SPELLING reaches the parser intact. */
    private fun CompanionEngine.feedRaw(raw: String) = feed(encodeFrame(raw))

    private fun replyTo(out: List<JsonObject>, id: String) =
        out.last { it["id"] == JsonPrimitive(id) }
    private fun errorCode(out: List<JsonObject>, id: String) =
        replyTo(out, id).reqObj("error").reqLong("code")

    // ------------------------------------- integral doubles ARE accepted (2)

    @Test
    fun integralDoubleAtMsIsAcceptedAndFunctional() {
        val out = mutableListOf<JsonObject>()
        val reminders = ReminderStore(MemoryReminderBacking())
        val engine = engine(out, reminders)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"p1","method":"reminders.set","params":""" +
            """{"owner":"o","reminders":[{"id":"x","title":"T","at_ms":5000.0}]}}""")
        assertEquals(1L, replyTo(out, "p1").reqObj("result").reqLong("count"))
        // Functional, not merely accepted: the reminder is stored VERBATIM
        // (content "5000.0") and its at_ms reads back as the VALUE 5000. The
        // read is by value (integralLongOrNull) — a spelling-strict reqLong
        // port would fail here against correct production code.
        val stored = reminders.reminder("o", "x")
        assertNotNull("an accepted reminder must be stored", stored)
        assertEquals(5_000L, integralLongOrNull(stored!!["at_ms"]))
    }

    @Test
    fun fractionalAtMsIsRejected() {
        // The boundary the acceptance above sits against: integral doubles
        // pass, genuinely fractional ones are 1201 (SPEC 4.3, no coercion).
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"p2","method":"reminders.set","params":""" +
            """{"owner":"o","reminders":[{"id":"x","title":"T","at_ms":1.5}]}}""")
        assertEquals(1201L, errorCode(out, "p2"))
        assertEquals("must be a non-negative integer timestamp",
            replyTo(out, "p2").reqObj("error").reqObj("data").reqString("reason"))
    }

    @Test
    fun integralDoubleTtlSIsAcceptedInAnActionDescriptor() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"p3","method":"surface.update","params":""" +
            """{"surface":"app:t","revision":3,"spec":{"t":"button","label":"b",""" +
            """"on_tap":{"action":"a.b","when_offline":"queue","ttl_s":60.0}}}}""")
        assertEquals("applied",
            replyTo(out, "p3").reqObj("result").reqString("status"))
        // FUNCTIONAL, not merely accepted (strengthened at C5 by the mutation
        // matrix, M2): the accepted spec stores the descriptor VERBATIM, so
        // the 60.0 spelling reaches dispatchAction's own ttl_s read at TAP
        // time. A spelling-strict reader there throws out of the tap and
        // closes the session on the device — acceptance alone never covered
        // that read.
        val onTap = engine.surfaces.spec("app:t")!!.reqObj("on_tap")
        var status: String? = null
        engine.dispatchAction("app:t", onTap, null) { s, _ -> status = s }
        assertEquals("a stored 60.0 ttl_s must still queue at tap time",
            "queued", status)
    }

    @Test
    fun integralDoubleCapabilityArgReachesTheHandler() {
        val out = mutableListOf<JsonObject>()
        invoked.clear()
        val engine = engine(out)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"p4","method":"capability.invoke",""" +
            """"params":{"cap":"vibrate","args":{"ms":100.0}}}""")
        // Whatever the spelling, the host sees an args object it can read a
        // duration from; the swap must not turn this into a crash or a 1201.
        // The args pass through VERBATIM (content "100.0"), so the read is
        // by value — integralLongOrNull, never a spelling-strict reader.
        assertTrue("the float-spelled invocation must reach the host",
            invoked.any { it.first == "vibrate" })
        assertEquals(100L, integralLongOrNull(invoked.last().second["ms"]))
    }

    // ---------------------------------------- typed rejections stay typed (8)

    @Test
    fun revisionMustBeAnIntegerNotAFloatOrString() {
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        engine.feedRaw("""{"jsonrpc":"2.0","id":"r-float","method":"surface.update",""" +
            """"params":{"surface":"app:main","revision":1.0,"spec":{"t":"text","text":"hi"}}}""")
        assertEquals(-32602L, errorCode(out, "r-float"))
        engine.feedRaw("""{"jsonrpc":"2.0","id":"r-str","method":"surface.update",""" +
            """"params":{"surface":"app:main","revision":"1","spec":{"t":"text","text":"hi"}}}""")
        // org.json's getLong would coerce "1" to 1; the validator refuses
        // first. THIS is the laxity the swap removes — and it must stay
        // removed at exactly this taxonomy (-32602, not 1201).
        assertEquals(-32602L, errorCode(out, "r-str"))
    }

    @Test
    fun toastDurationFloatOrStringIsIgnoredNotCoerced() {
        val out = mutableListOf<JsonObject>()
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
    fun nonStringMethodIsInvalidRequestNotSilentClose() {
        // THE ONE DELIBERATE FLIP of this migration (PLAN-rf2-c5-tests §3.7).
        // Pre-swap this pin recorded the org.json behavior: a non-string
        // `method` was a malformed envelope and the connection closed with no
        // frame. C2's Envelope rewrite routes it to the -32600 Invalid
        // Request path DELIBERATELY (classifyMessage returns null for a
        // non-string method; the dispatcher answers when both id and method
        // exist — Envelope.kt's C2 comment is the decision of record). This
        // rewrite is where that decision becomes visible rather than
        // accidental: one error frame, the id echoed verbatim as the STRING
        // "m5", and the session SURVIVES.
        val out = mutableListOf<JsonObject>()
        val engine = engine(out)
        assertEquals(SessionState.READY, engine.state)
        val before = out.size
        engine.feedRaw("""{"jsonrpc":"2.0","id":"m5","method":5,"params":{}}""")
        assertEquals("exactly one error frame answers it", before + 1, out.size)
        val reply = out.last { it["id"] == JsonPrimitive("m5") }
        assertEquals(-32600L, reply.reqObj("error").reqLong("code"))
        assertEquals("invalid-request",
            reply.reqObj("error").reqObj("data").reqString("kind"))
        assertEquals(SessionState.READY, engine.state)
    }
}
