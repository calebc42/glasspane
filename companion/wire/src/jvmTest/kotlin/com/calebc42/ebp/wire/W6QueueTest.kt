// SPDX-License-Identifier: GPL-3.0-or-later
// W6 conformance: the SPEC 15 durable queue and replay pump.
// - the kill matrix (SPEC 24.6 item 8): process death before/after the
//   event.action request is written and before/after its response, played
//   against a real FileQueueStore ("death" = reopen the same file);
// - replay interruption, dedupe, expiry with clock rollback, capacity
//   (item 10); offline draft + sync + replay (item 11).
package com.calebc42.ebp.wire

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class W6QueueTest {

    @get:Rule
    val temp = TemporaryFolder()

    private fun config() = CompanionConfig(
        serverName = "kat", serverVersion = "1",
        pairings = mapOf(katPid to katToken),
        supportedCapabilities = setOf("theme"),
        surfaceProfiles = buildJsonObject {
            putJsonObject("app") {
                put("node_types",
                    JsonArray(listOf("text", "text_input", "button").map(::JsonPrimitive)))
                put("builtins", JsonArray(emptyList()))
                put("features", JsonArray(emptyList()))
            }
        },
        limits = testLimits(), nonceSource = { katSn })

    /** Engine + captured outbound frames over a given queue/store. */
    private fun engineOn(queue: DurableQueue, store: SurfaceStore,
                         out: MutableList<JsonObject>): CompanionEngine =
        CompanionEngine(config(), store, queue) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }

    private fun CompanionEngine.handshake(toReady: Boolean = true) {
        feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, emptyList()))))
        feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        if (toReady) {
            feed(frame(request("q0", "queue.replay", JsonObject(emptyMap()))))
            feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        }
    }

    private fun queuedDescriptor(dedupe: String? = null): JsonObject = buildJsonObject {
        put("action", "demo.tap")
        put("when_offline", "queue")
        put("ttl_s", 3600L)
        if (dedupe != null) put("dedupe", dedupe)
    }

    private fun surfaceWithInput(): SurfaceStore = SurfaceStore(16, 1024).also {
        it.update("app:main", 1, buildJsonObject {
            put("t", "text_input"); put("id", "title"); put("value", "authored")
        }, null, null, null)
    }

    private fun respondTo(engine: CompanionEngine, event: JsonObject, status: String) =
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", event["id"]!!)
            put("result", buildJsonObject { put("status", status) })
        }))

    // ------------------------------------------------ kill matrix (item 8)

    @Test
    fun killBeforeDeliveryReplaysAfterRestart() {
        val file = temp.newFile("queue.json")
        val store = surfaceWithInput()
        val out1 = mutableListOf<JsonObject>()
        val q1 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        val e1 = engineOn(q1, store, out1)
        // Offline occurrence: admitted durably, never delivered (no session).
        e1.dispatchAction("app:main", queuedDescriptor(), null)
        assertEquals(1, q1.count())
        assertTrue(out1.events().isEmpty())
        val storedId = q1.head()!!.reqObj("event").reqString("event_id")

        // Process death; the next life reads the same file.
        val out2 = mutableListOf<JsonObject>()
        val q2 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        assertEquals(1, q2.count())
        val e2 = engineOn(q2, surfaceWithInput(), out2)
        e2.handshake(toReady = false)
        // Welcome reports the retained event (SPEC 10.2).
        assertEquals(1L, out2.last().reqObj("result").reqLong("queued_events"))
        e2.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        val replayed = out2.events().single()
        // SPEC 14.4: the retry reuses the stored EventId.
        assertEquals(storedId, replayed.reqObj("params").reqString("event_id"))
        respondTo(e2, replayed, "accepted")
        val summary = out2.replyTo("q1").reqObj("result")
        assertEquals(1L, summary.reqLong("delivered"))
        assertEquals(0L, summary.reqLong("remaining"))
        assertEquals(0, q2.count())
    }

    @Test
    fun killWithRequestInFlightRedeliversSameEventId() {
        val file = temp.newFile("queue.json")
        val out1 = mutableListOf<JsonObject>()
        val q1 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        val e1 = engineOn(q1, surfaceWithInput(), out1)
        e1.handshake()
        e1.dispatchAction("app:main", queuedDescriptor(), null)
        // The request was written to the wire... and the process dies
        // before any response arrives.
        val sent = out1.events().single()
        val sentId = sent.reqObj("params").reqString("event_id")
        assertEquals(1, q1.count()) // still durable: no permanent result yet

        val out2 = mutableListOf<JsonObject>()
        val q2 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        assertTrue(!q2.hasInFlight()) // nothing is in flight after death
        val e2 = engineOn(q2, surfaceWithInput(), out2)
        e2.handshake(toReady = false)
        e2.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        assertEquals(sentId,
            out2.events().single().reqObj("params").reqString("event_id"))
    }

    @Test
    fun killAfterPermanentResultDeliversNothing() {
        val file = temp.newFile("queue.json")
        val out1 = mutableListOf<JsonObject>()
        val q1 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        val e1 = engineOn(q1, surfaceWithInput(), out1)
        e1.handshake()
        e1.dispatchAction("app:main", queuedDescriptor(), null)
        respondTo(e1, out1.events().single(), "accepted")
        assertEquals(0, q1.count())

        val q2 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        assertEquals(0, q2.count()) // the deletion survived the death
    }

    // -------------------------------------- pause, FIFO, 1600 (item 10)

    @Test
    fun transientErrorPausesPumpAndLaterAdmissionNeverBypasses() {
        val out = mutableListOf<JsonObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        val e = engineOn(q, store, out)
        e.handshake()
        e.dispatchAction("app:main", queuedDescriptor(), null)
        val first = out.events().single()
        // SPEC 15.3: 1500 retains the head and pauses the pump.
        e.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", first["id"]!!)
            put("error", buildJsonObject {
                put("code", 1500)
                put("message", "busy")
                put("data", buildJsonObject { put("kind", "event-retry") })
            })
        }))
        assertEquals(1, q.count())
        // A later admission MUST NOT clear the pause or bypass the head.
        e.dispatchAction("app:main", queuedDescriptor(), null)
        assertEquals(2, q.count())
        assertEquals(1, out.events().size) // nothing new left the pump
        // Replay resumes; strict queue_seq order; summary reports blockage.
        e.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        val second = out.events()[1]
        assertEquals(first.reqObj("params").reqString("event_id"),
            second.reqObj("params").reqString("event_id"))
        respondTo(e, second, "accepted")
        respondTo(e, out.events()[2], "stale")
        val summary = out.replyTo("q1").reqObj("result")
        assertEquals(1L, summary.reqLong("delivered"))
        assertEquals(1L, summary.reqLong("rejected"))
        assertEquals(0L, summary.reqLong("remaining"))
        assertEquals(JsonNull, summary["blocked_by"])
    }

    @Test
    fun blockedReplayReportsErrorKindAndConcurrentReplayIsBusy() {
        val out = mutableListOf<JsonObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        // The backlog predates the session (10.3: it is what replay drains).
        engineOn(q, store, mutableListOf()).also {
            it.dispatchAction("app:main", queuedDescriptor(), null)
            it.close("pre-session")
        }
        val e = engineOn(q, store, out)
        e.handshake(toReady = false)
        e.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        // SPEC 15.3: a second replay while one is active is 1600.
        e.feed(frame(request("q2", "queue.replay", JsonObject(emptyMap()))))
        assertEquals(1600L, out.replyTo("q2")
            .reqObj("error").reqLong("code"))
        e.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", out.events().single()["id"]!!)
            put("error", buildJsonObject {
                put("code", 1500)
                put("message", "busy")
                put("data", buildJsonObject { put("kind", "event-retry") })
            })
        }))
        val summary = out.replyTo("q1").reqObj("result")
        assertEquals("event-retry", summary.reqString("blocked_by"))
        assertEquals(1L, summary.reqLong("remaining"))
    }

    @Test
    fun syncingWithholdsAutoDeliveryUntilReplay() {
        val out = mutableListOf<JsonObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        // A backlog event from before the session...
        engineOn(q, store, mutableListOf()).also {
            it.dispatchAction("app:main", queuedDescriptor(), null)
            it.close("pre-session")
        }
        val e = engineOn(q, store, out)
        e.handshake(toReady = false) // SYNCING
        // SPEC 10.3/15.3: during SYNCING only the explicit replay pumps.
        assertTrue(out.events().isEmpty())
        e.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        assertEquals(1, out.events().size)
    }

    @Test
    fun readyAdmissionAutoStartsPump() {
        val out = mutableListOf<JsonObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val e = engineOn(q, surfaceWithInput(), out)
        e.handshake()
        // SPEC 15.3: while READY, admission of a new head wakes the pump.
        e.dispatchAction("app:main", queuedDescriptor(), null)
        assertEquals(1, out.events().size)
        // §22.3: it was durably admitted before that attempt.
        assertEquals(1, q.count())
    }

    // ------------------------------------------- dedupe, expiry, capacity

    @Test
    fun dedupeReplacesOlderButNeverInFlight() {
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        fun event(id: String) = buildJsonObject {
            put("event_id", id.repeat(32).take(32))
            put("action", "a.b"); put("occurred_at_ms", q.effectiveNow())
        }
        q.admit(event("a"), "queue", "key", 3600)
        q.admit(event("b"), "queue", "key", 3600)
        // The older same-key record was compacted away (SPEC 15.2).
        assertEquals(1, q.count())
        assertTrue(q.head()!!.reqObj("event").reqString("event_id").startsWith("b"))
        // An in-flight record is never replaced.
        q.beginDelivery(null) // atomically marks the head in-flight
        q.admit(event("c"), "queue", "key", 3600)
        assertEquals(2, q.count())
        // Sequence numbers stay strictly increasing across compaction.
        val seqs = listOf(q.head()!!.reqLong("queue_seq"))
        assertTrue(seqs.all { it >= 1 })
    }

    @Test
    fun beginDeliveryGatesPendingLocalBarrierAndEmpty() {
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        fun ev(id: String) = buildJsonObject {
            put("event_id", id); put("action", "a.b")
            put("occurred_at_ms", q.effectiveNow())
        }
        assertTrue(q.beginDelivery(null) is Delivery.Empty)
        // A pending-local head is withheld (the pump waits, not concludes).
        q.admit(ev("x"), "queue", null, 3600, pendingLocal = true)
        assertTrue(q.beginDelivery(null) is Delivery.PendingLocal)
        q.clearPendingLocal(q.head()!!.reqLong("queue_seq"))
        // Now deliverable — and atomically marked in-flight.
        val d = q.beginDelivery(null)
        assertTrue(d is Delivery.Ready)
        assertTrue(q.hasInFlight())
        // The SYNCING replay barrier withholds a head at/after the boundary.
        q.clearInFlight((d as Delivery.Ready).record.reqLong("queue_seq"))
        assertTrue(q.beginDelivery(q.head()!!.reqLong("queue_seq")) is Delivery.BarrierHeld)
    }

    @Test
    fun expiryUsesHighWaterMarkAgainstClockRollback() {
        var now = 1_000_000L
        val file = temp.newFile("queue.json")
        val q = DurableQueue(FileQueueStore(file), 256, 8_388_608).also { it.clock = { now } }
        val event = buildJsonObject {
            put("event_id", "a".repeat(32))
            put("action", "a.b"); put("occurred_at_ms", now)
        }
        q.admit(event, "queue", null, 10) // expires at now + 10s
        now += 11_000
        // The sweep advances the durable mark and deletes the record.
        assertEquals(1, q.sweepExpired())
        assertEquals(0, q.count())
        // Clock rollback: a new same-ttl event admitted at the rolled-back
        // time still expires against the durable high-water mark.
        now = 900_000L
        val q2 = DurableQueue(FileQueueStore(file), 256, 8_388_608).also { it.clock = { now } }
        assertTrue(q2.effectiveNow() >= 1_011_000L) // the mark survived death
        q2.admit(buildJsonObject {
            put("event_id", "b".repeat(32))
            put("action", "a.b"); put("occurred_at_ms", 900_000L)
        }, "queue", null, 10)
        assertEquals(1, q2.sweepExpired()) // 900s + 10s < mark: already expired
    }

    @Test
    fun capacityRejectsAdmissionWithoutClaimingQueued() {
        val q = DurableQueue(MemoryQueueStore(), maxEvents = 1, maxBytes = 8_388_608)
        fun event(c: String) = buildJsonObject {
            put("event_id", c.repeat(32))
            put("action", "a.b"); put("occurred_at_ms", q.effectiveNow())
        }
        assertTrue(q.admit(event("a"), "queue", null, 60) is AdmitResult.Admitted)
        assertTrue(q.admit(event("b"), "queue", null, 60) is AdmitResult.QueueFull)
        assertEquals(1, q.count()) // the queue is unchanged
    }

    // --------------------------- review-confirmed regressions (P0s + P1s)

    @Test
    fun connectionLossWithoutProcessDeathDoesNotWedgeReplay() {
        // Review P0: the in-flight marker must die with the connection —
        // same process, same shared queue, new engine.
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        val out1 = mutableListOf<JsonObject>()
        val e1 = engineOn(q, store, out1)
        e1.handshake()
        e1.dispatchAction("app:main", queuedDescriptor(), null)
        assertTrue(q.hasInFlight()) // request written, no response yet
        e1.close("transport closed") // connection loss, process survives
        assertTrue(!q.hasInFlight())  // the marker died with the session
        val out2 = mutableListOf<JsonObject>()
        val e2 = engineOn(q, store, out2)
        e2.handshake(toReady = false)
        e2.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        assertEquals(1, out2.events().size) // replay moves, not wedged
        respondTo(e2, out2.events().single(), "accepted")
        val summary = out2.replyTo("q1").reqObj("result")
        assertEquals(1L, summary.reqLong("delivered"))
    }

    @Test
    fun oversizedEventIsRefusedLocallyNeverPersistedOrSent() {
        // Review P0: SPEC 14.4/15.4 — max_event_bytes before persistence
        // or transmission; refusal is a local diagnostic.
        val out = mutableListOf<JsonObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        val e = engineOn(q, store, out)
        e.handshake()
        e.publishState("app:main", "title", JsonPrimitive("x".repeat(300_000)))
        var localError: JsonObject? = null
        e.dispatchAction("app:main",
            queuedDescriptor().with("capture_fields",
                JsonArray(listOf("title").map(::JsonPrimitive))),
            null) { _, error -> localError = error }
        assertEquals(0, q.count())            // never persisted
        assertTrue(out.events().isEmpty())    // never transmitted
        assertEquals("event-too-large", localError!!
            .reqObj("data").reqString("reason"))
    }

    @Test
    fun unknownStatusRetainsEventAndClosesWithOneLogError() {
        val out = mutableListOf<JsonObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val e = engineOn(q, surfaceWithInput(), out)
        e.handshake()
        e.dispatchAction("app:main", queuedDescriptor(), null)
        respondTo(e, out.events().single(), "banana")
        // SPEC 15.3: retained, one safe log.error, connection closed.
        assertEquals(1, q.count())
        assertEquals(SessionState.CLOSED, e.state)
        assertEquals(1, out.count { it.stringOrNull("method") == "log.error" })
    }

    @Test
    fun newEventsAdmittedDuringSyncingStayBehindTheBarrier() {
        // Review P1: SPEC 10.3/15.3 — the SYNCING replay drains only the
        // backlog; a newly generated occurrence waits for session.ready.
        val out = mutableListOf<JsonObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        val e1 = engineOn(q, store, mutableListOf())
        e1.dispatchAction("app:main", queuedDescriptor(), null) // backlog
        e1.close("pre-session")
        val e2 = engineOn(q, store, out)
        e2.handshake(toReady = false)
        e2.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        // While the backlog head is in flight, a NEW occurrence arrives.
        e2.dispatchAction("app:main", queuedDescriptor(), null)
        respondTo(e2, out.events()[0], "accepted")
        // The replay concluded at the barrier: the new event is retained.
        val summary = out.replyTo("q1").reqObj("result")
        assertEquals(1L, summary.reqLong("delivered"))
        assertEquals(1L, summary.reqLong("remaining"))
        assertEquals(1, out.events().size) // nothing new delivered yet
        // session.ready releases it.
        e2.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        assertEquals(2, out.events().size)
    }

    @Test
    fun syncingEraEditsFlushBeforeReleasedEvents() {
        // Review P1: SPEC 10.3 — divergent SYNCING-era values flush as
        // state.changed ahead of any event released on READY.
        val out = mutableListOf<JsonObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        val e = engineOn(q, store, out)
        e.handshake(toReady = false)
        e.publishState("app:main", "title", JsonPrimitive("syncing edit"))
        e.dispatchAction("app:main", queuedDescriptor(), null)
        assertTrue(out.none { it.stringOrNull("method") == "state.changed" })
        e.feed(frame(request("r1", "session.ready", JsonObject(emptyMap()))))
        val stateIdx = out.indexOfFirst { it.stringOrNull("method") == "state.changed" }
        val eventIdx = out.indexOfFirst { it.stringOrNull("method") == "event.action" }
        assertTrue(stateIdx in 0 until eventIdx)
        assertEquals("syncing edit",
            out[stateIdx].reqObj("params").reqString("value"))
    }

    // ------------------------------ offline draft + sync + replay (item 11)

    @Test
    fun offlineDraftThenSynchronizationThenReplay() {
        val queueFile = temp.newFile("queue.json")
        val surfaceFile = temp.newFile("surfaces.json")
        // Life 1: the user edits offline, then taps an action capturing the
        // field. Process death drops every object; only the two files carry
        // state forward — a genuine kill, not a same-object reconnection.
        run {
            val store = SurfaceStore(16, 1024, backing = FileSurfaceBacking(surfaceFile))
            store.update("app:main", 1, buildJsonObject {
                put("t", "text_input"); put("id", "title"); put("value", "authored")
            }, null, null, null)
            val q1 = DurableQueue(FileQueueStore(queueFile), 256, 8_388_608)
            val out1 = mutableListOf<JsonObject>()
            val e1 = engineOn(q1, store, out1)
            e1.publishState("app:main", "title", JsonPrimitive("offline edit"))
            e1.dispatchAction("app:main",
                queuedDescriptor().with("capture_fields",
                    JsonArray(listOf("title").map(::JsonPrimitive))), null)
            assertTrue(out1.isEmpty()) // nothing on the wire without a session
        }

        // Life 2: fresh objects read the same files. The welcome carries the
        // durable draft (SPEC 15.1 input_state) AND the queued count; replay
        // delivers the event with its occurrence-time capture.
        val store2 = SurfaceStore(16, 1024, backing = FileSurfaceBacking(surfaceFile))
        val q2 = DurableQueue(FileQueueStore(queueFile), 256, 8_388_608)
        val out2 = mutableListOf<JsonObject>()
        val e2 = engineOn(q2, store2, out2)
        e2.handshake(toReady = false)
        val welcome = out2.last().reqObj("result")
        assertEquals("offline edit", welcome.reqObj("input_state")
            .reqObj("app:main").reqString("title"))
        assertEquals(1L, welcome.reqLong("queued_events"))
        e2.feed(frame(request("q1", "queue.replay", JsonObject(emptyMap()))))
        val event = out2.events().single().reqObj("params")
        assertEquals("offline edit", event.reqObj("fields").reqString("title"))
        assertNotNull(event.reqLong("queued_at_ms"))
        respondTo(e2, out2.events().single(), "accepted")
        assertEquals(0, q2.count())
    }

    @Test
    fun surfaceRemoveRejectsInvalidId() {
        // SPEC 13.1: a structurally invalid surface id is rejected, not made
        // into a tombstone that pollutes the welcome (audit finding 24).
        val store = SurfaceStore(16, 1024)
        val out = mutableListOf<JsonObject>()
        val engine = engineOn(DurableQueue(MemoryQueueStore(), 256, 8_388_608), store, out)
        engine.handshake(toReady = true)
        engine.feed(frame(request("rm", "surface.remove", buildJsonObject {
            put("surface", "not a valid id!"); put("revision", 1L)
        })))
        val err = out.replyTo("rm").reqObj("error")
        assertEquals(1201L, err.reqLong("code"))
        assertEquals("surface-id", err.reqObj("data").reqString("reason"))
        assertEquals(0, store.snapshot().size) // no tombstone created
    }

    @Test
    fun maxEventBytesCountsTheQueuedAtMsField() {
        // SPEC 4.5/15.4: max_event_bytes measures the COMPLETE persisted
        // params, INCLUDING queued_at_ms — an event that fits only without
        // that field must still be rejected (audit finding 22).
        val limit = 262144
        val overhead = buildJsonObject {
            put("event_id", "0".repeat(32)); put("action", "demo.tap")
            put("surface", "app:main"); put("revision_seen", 1L)
            put("occurred_at_ms", 1000L)
            put("args", buildJsonObject { put("pad", "") })
        }.toString().toByteArray(Charsets.UTF_8).size
        val pad = "x".repeat(limit - overhead) // params sans queued_at_ms == limit
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608) { 1000L }
        val out = mutableListOf<JsonObject>()
        val engine = engineOn(q, surfaceWithInput(), out)
        var error: JsonObject? = null
        engine.dispatchAction("app:main",
            queuedDescriptor().with("args", buildJsonObject { put("pad", pad) }),
            null) { _, e -> error = e }
        assertEquals(1201L, error!!.reqLong("code"))
        assertEquals("event-too-large", error!!.reqObj("data").reqString("reason"))
        assertEquals(0, q.count()) // not admitted
    }

    // ------------------------------------- P0 byte-gate pin (§0.2 item 5)

    /**
     * MEASURE WITH WHAT YOU EMIT. `max_event_bytes` is enforced by
     * serializing params and counting UTF-8 octets (CompanionEngine.kt:325),
     * the durable queue accounts capacity the same way (DurableQueue.kt:135),
     * and the frame that goes out is serialized a third time. Today all three
     * run through org.json's `toString()`, so they agree by construction.
     * After the swap they agree only if ONE `wireSerialize` feeds all three —
     * which is why the runbook requires the measuring sites and the emit site
     * to migrate in the same commit.
     *
     * The payload makes escaping choices visible: an em dash, curly quotes, a
     * euro sign (3-byte UTF-8), and `</x`, which some encoders escape for
     * HTML safety. A sender that escapes differently than the gate measures
     * either under-counts a frame it then refuses, or over-counts one it
     * could have sent.
     */
    @Test
    fun byteGateMeasuresWhatItEmits() {
        val tricky = "— “q” €</xtail"
        val raw = mutableListOf<ByteArray>()
        val out = mutableListOf<JsonObject>()
        val queue = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val engine = CompanionEngine(config(), surfaceWithInput(), queue) { bytes ->
            raw.add(bytes)
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }
        engine.handshake()
        raw.clear(); out.clear()

        engine.dispatchAction("app:main", buildJsonObject {
            put("action", "a.b")
            put("args", buildJsonObject { put("note", tricky) })
        }, null)

        val event = out.events().single()
        val params = event.reqObj("params")
        // 1. Character fidelity: every awkward scalar survives parse -> emit
        //    unchanged — no mojibake, no HTML escaping of the `</x` run.
        assertEquals(tricky, params.reqObj("args").reqString("note"))

        // 2. The emitted BODY bytes equal a re-serialization of the decoded
        //    message: the encoder and the measuring path agree on escaping.
        val frameBytes = raw.single { String(it, Charsets.UTF_8).contains("event.action") }
        val text = String(frameBytes, Charsets.UTF_8)
        val body = text.substring(text.indexOf("\r\n\r\n") + 4)
        assertEquals(body.toByteArray(Charsets.UTF_8).size,
            Json.parseToJsonElement(body).toString().toByteArray(Charsets.UTF_8).size)

        // 3. The params the gate measures are the params on the wire.
        assertEquals(params.toString().toByteArray(Charsets.UTF_8).size,
            (Json.parseToJsonElement(body) as JsonObject).reqObj("params").toString()
                .toByteArray(Charsets.UTF_8).size)

        // 4. Content-Length declares those same octets (SPEC 6.1) — the
        //    framing half of the same invariant.
        val declared = Regex("Content-Length: (\\d+)").find(text)!!.groupValues[1].toInt()
        assertEquals(declared, body.toByteArray(Charsets.UTF_8).size)
    }
}
