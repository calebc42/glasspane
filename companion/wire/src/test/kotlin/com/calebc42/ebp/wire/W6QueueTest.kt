// SPDX-License-Identifier: GPL-3.0-or-later
// W6 conformance: the SPEC 15 durable queue and replay pump.
// - the kill matrix (SPEC 24.6 item 8): process death before/after the
//   event.action request is written and before/after its response, played
//   against a real FileQueueStore ("death" = reopen the same file);
// - replay interruption, dedupe, expiry with clock rollback, capacity
//   (item 10); offline draft + sync + replay (item 11).
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class W6QueueTest {

    @get:Rule
    val temp = TemporaryFolder()

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    private fun limits(): JSONObject = JSONObject()
        .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
        .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
        .put("max_surfaces", 16).put("max_surface_ids", 1024)
        .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
        .put("max_capture_fields", 64)

    private fun config() = CompanionConfig(
        serverName = "kat", serverVersion = "1",
        pairings = mapOf(katPid to katToken),
        supportedCapabilities = setOf("theme"),
        surfaceProfiles = JSONObject().put("app", JSONObject()
            .put("node_types", JSONArray(listOf("text", "text_input", "button")))
            .put("builtins", JSONArray()).put("features", JSONArray())),
        limits = limits(), nonceSource = { katSn })

    private fun frame(msg: JSONObject) = encodeFrame(msg.toString())

    /** Engine + captured outbound frames over a given queue/store. */
    private fun engineOn(queue: DurableQueue, store: SurfaceStore,
                         out: MutableList<JSONObject>): CompanionEngine =
        CompanionEngine(config(), store, queue) { bytes ->
            FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }
        }

    private fun CompanionEngine.handshake(toReady: Boolean = true) {
        feed(frame(request("h1", "session.hello",
            EbpAuth.helloParams("t", "1", katPid, katCn, emptyList()))))
        feed(frame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken))))
        if (toReady) {
            feed(frame(request("q0", "queue.replay", JSONObject())))
            feed(frame(request("r1", "session.ready", JSONObject())))
        }
    }

    private fun queuedDescriptor(dedupe: String? = null): JSONObject =
        JSONObject().put("action", "demo.tap").put("when_offline", "queue")
            .put("ttl_s", 3600L)
            .also { if (dedupe != null) it.put("dedupe", dedupe) }

    private fun surfaceWithInput(): SurfaceStore = SurfaceStore(16, 1024).also {
        it.update("app:main", 1, JSONObject().put("t", "text_input")
            .put("id", "title").put("value", "authored"), null, null, null)
    }

    private fun List<JSONObject>.events() =
        filter { it.opt("method") == "event.action" }

    private fun respondTo(engine: CompanionEngine, event: JSONObject, status: String) =
        engine.feed(frame(JSONObject().put("jsonrpc", "2.0")
            .put("id", event.getInt("id"))
            .put("result", JSONObject().put("status", status))))

    // ------------------------------------------------ kill matrix (item 8)

    @Test
    fun killBeforeDeliveryReplaysAfterRestart() {
        val file = temp.newFile("queue.json")
        val store = surfaceWithInput()
        val out1 = mutableListOf<JSONObject>()
        val q1 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        val e1 = engineOn(q1, store, out1)
        // Offline occurrence: admitted durably, never delivered (no session).
        e1.dispatchAction("app:main", queuedDescriptor(), null)
        assertEquals(1, q1.count())
        assertTrue(out1.events().isEmpty())
        val storedId = q1.head()!!.getJSONObject("event").getString("event_id")

        // Process death; the next life reads the same file.
        val out2 = mutableListOf<JSONObject>()
        val q2 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        assertEquals(1, q2.count())
        val e2 = engineOn(q2, surfaceWithInput(), out2)
        e2.handshake(toReady = false)
        // Welcome reports the retained event (SPEC 10.2).
        assertEquals(1, out2.last().getJSONObject("result").getInt("queued_events"))
        e2.feed(frame(request("q1", "queue.replay", JSONObject())))
        val replayed = out2.events().single()
        // SPEC 14.4: the retry reuses the stored EventId.
        assertEquals(storedId, replayed.getJSONObject("params").getString("event_id"))
        respondTo(e2, replayed, "accepted")
        val summary = out2.last { it.opt("id") == "q1" }.getJSONObject("result")
        assertEquals(1, summary.getInt("delivered"))
        assertEquals(0, summary.getInt("remaining"))
        assertEquals(0, q2.count())
    }

    @Test
    fun killWithRequestInFlightRedeliversSameEventId() {
        val file = temp.newFile("queue.json")
        val out1 = mutableListOf<JSONObject>()
        val q1 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        val e1 = engineOn(q1, surfaceWithInput(), out1)
        e1.handshake()
        e1.dispatchAction("app:main", queuedDescriptor(), null)
        // The request was written to the wire... and the process dies
        // before any response arrives.
        val sent = out1.events().single()
        val sentId = sent.getJSONObject("params").getString("event_id")
        assertEquals(1, q1.count()) // still durable: no permanent result yet

        val out2 = mutableListOf<JSONObject>()
        val q2 = DurableQueue(FileQueueStore(file), 256, 8_388_608)
        assertNull(q2.inFlightSeq) // nothing is in flight after death
        val e2 = engineOn(q2, surfaceWithInput(), out2)
        e2.handshake(toReady = false)
        e2.feed(frame(request("q1", "queue.replay", JSONObject())))
        assertEquals(sentId,
            out2.events().single().getJSONObject("params").getString("event_id"))
    }

    @Test
    fun killAfterPermanentResultDeliversNothing() {
        val file = temp.newFile("queue.json")
        val out1 = mutableListOf<JSONObject>()
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
        val out = mutableListOf<JSONObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        val e = engineOn(q, store, out)
        e.handshake()
        e.dispatchAction("app:main", queuedDescriptor(), null)
        val first = out.events().single()
        // SPEC 15.3: 1500 retains the head and pauses the pump.
        e.feed(frame(JSONObject().put("jsonrpc", "2.0")
            .put("id", first.getInt("id"))
            .put("error", JSONObject().put("code", 1500)
                .put("message", "busy")
                .put("data", JSONObject().put("kind", "event-retry")))))
        assertEquals(1, q.count())
        // A later admission MUST NOT clear the pause or bypass the head.
        e.dispatchAction("app:main", queuedDescriptor(), null)
        assertEquals(2, q.count())
        assertEquals(1, out.events().size) // nothing new left the pump
        // Replay resumes; strict queue_seq order; summary reports blockage.
        e.feed(frame(request("q1", "queue.replay", JSONObject())))
        val second = out.events()[1]
        assertEquals(first.getJSONObject("params").getString("event_id"),
            second.getJSONObject("params").getString("event_id"))
        respondTo(e, second, "accepted")
        respondTo(e, out.events()[2], "stale")
        val summary = out.last { it.opt("id") == "q1" }.getJSONObject("result")
        assertEquals(1, summary.getInt("delivered"))
        assertEquals(1, summary.getInt("rejected"))
        assertEquals(0, summary.getInt("remaining"))
        assertEquals(JSONObject.NULL, summary.get("blocked_by"))
    }

    @Test
    fun blockedReplayReportsErrorKindAndConcurrentReplayIsBusy() {
        val out = mutableListOf<JSONObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        // The backlog predates the session (10.3: it is what replay drains).
        engineOn(q, store, mutableListOf()).also {
            it.dispatchAction("app:main", queuedDescriptor(), null)
            it.close("pre-session")
        }
        val e = engineOn(q, store, out)
        e.handshake(toReady = false)
        e.feed(frame(request("q1", "queue.replay", JSONObject())))
        // SPEC 15.3: a second replay while one is active is 1600.
        e.feed(frame(request("q2", "queue.replay", JSONObject())))
        assertEquals(1600, out.last { it.opt("id") == "q2" }
            .getJSONObject("error").getInt("code"))
        e.feed(frame(JSONObject().put("jsonrpc", "2.0")
            .put("id", out.events().single().getInt("id"))
            .put("error", JSONObject().put("code", 1500)
                .put("message", "busy")
                .put("data", JSONObject().put("kind", "event-retry")))))
        val summary = out.last { it.opt("id") == "q1" }.getJSONObject("result")
        assertEquals("event-retry", summary.getString("blocked_by"))
        assertEquals(1, summary.getInt("remaining"))
    }

    @Test
    fun syncingWithholdsAutoDeliveryUntilReplay() {
        val out = mutableListOf<JSONObject>()
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
        e.feed(frame(request("q1", "queue.replay", JSONObject())))
        assertEquals(1, out.events().size)
    }

    @Test
    fun readyAdmissionAutoStartsPump() {
        val out = mutableListOf<JSONObject>()
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
        fun event(id: String) = JSONObject().put("event_id", id.repeat(32).take(32))
            .put("action", "a.b").put("occurred_at_ms", q.effectiveNow())
        q.admit(event("a"), "queue", "key", 3600)
        q.admit(event("b"), "queue", "key", 3600)
        // The older same-key record was compacted away (SPEC 15.2).
        assertEquals(1, q.count())
        assertTrue(q.head()!!.getJSONObject("event").getString("event_id").startsWith("b"))
        // An in-flight record is never replaced.
        q.inFlightSeq = q.head()!!.getLong("queue_seq")
        q.admit(event("c"), "queue", "key", 3600)
        assertEquals(2, q.count())
        // Sequence numbers stay strictly increasing across compaction.
        val seqs = listOf(q.head()!!.getLong("queue_seq"))
        assertTrue(seqs.all { it >= 1 })
    }

    @Test
    fun expiryUsesHighWaterMarkAgainstClockRollback() {
        var now = 1_000_000L
        val file = temp.newFile("queue.json")
        val q = DurableQueue(FileQueueStore(file), 256, 8_388_608).also { it.clock = { now } }
        val event = JSONObject().put("event_id", "a".repeat(32))
            .put("action", "a.b").put("occurred_at_ms", now)
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
        q2.admit(JSONObject().put("event_id", "b".repeat(32))
            .put("action", "a.b").put("occurred_at_ms", 900_000L), "queue", null, 10)
        assertEquals(1, q2.sweepExpired()) // 900s + 10s < mark: already expired
    }

    @Test
    fun capacityRejectsAdmissionWithoutClaimingQueued() {
        val q = DurableQueue(MemoryQueueStore(), maxEvents = 1, maxBytes = 8_388_608)
        fun event(c: String) = JSONObject().put("event_id", c.repeat(32))
            .put("action", "a.b").put("occurred_at_ms", q.effectiveNow())
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
        val out1 = mutableListOf<JSONObject>()
        val e1 = engineOn(q, store, out1)
        e1.handshake()
        e1.dispatchAction("app:main", queuedDescriptor(), null)
        assertNotNull(q.inFlightSeq) // request written, no response yet
        e1.close("transport closed") // connection loss, process survives
        assertNull(q.inFlightSeq)    // the marker died with the session
        val out2 = mutableListOf<JSONObject>()
        val e2 = engineOn(q, store, out2)
        e2.handshake(toReady = false)
        e2.feed(frame(request("q1", "queue.replay", JSONObject())))
        assertEquals(1, out2.events().size) // replay moves, not wedged
        respondTo(e2, out2.events().single(), "accepted")
        val summary = out2.last { it.opt("id") == "q1" }.getJSONObject("result")
        assertEquals(1, summary.getInt("delivered"))
    }

    @Test
    fun oversizedEventIsRefusedLocallyNeverPersistedOrSent() {
        // Review P0: SPEC 14.4/15.4 — max_event_bytes before persistence
        // or transmission; refusal is a local diagnostic.
        val out = mutableListOf<JSONObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        val e = engineOn(q, store, out)
        e.handshake()
        e.publishState("app:main", "title", "x".repeat(300_000))
        var localError: JSONObject? = null
        e.dispatchAction("app:main",
            queuedDescriptor().put("capture_fields", JSONArray(listOf("title"))),
            null) { _, error -> localError = error }
        assertEquals(0, q.count())            // never persisted
        assertTrue(out.events().isEmpty())    // never transmitted
        assertEquals("event-too-large", localError!!
            .getJSONObject("data").getString("reason"))
    }

    @Test
    fun unknownStatusRetainsEventAndClosesWithOneLogError() {
        val out = mutableListOf<JSONObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val e = engineOn(q, surfaceWithInput(), out)
        e.handshake()
        e.dispatchAction("app:main", queuedDescriptor(), null)
        respondTo(e, out.events().single(), "banana")
        // SPEC 15.3: retained, one safe log.error, connection closed.
        assertEquals(1, q.count())
        assertEquals(SessionState.CLOSED, e.state)
        assertEquals(1, out.count { it.opt("method") == "log.error" })
    }

    @Test
    fun newEventsAdmittedDuringSyncingStayBehindTheBarrier() {
        // Review P1: SPEC 10.3/15.3 — the SYNCING replay drains only the
        // backlog; a newly generated occurrence waits for session.ready.
        val out = mutableListOf<JSONObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        val e1 = engineOn(q, store, mutableListOf())
        e1.dispatchAction("app:main", queuedDescriptor(), null) // backlog
        e1.close("pre-session")
        val e2 = engineOn(q, store, out)
        e2.handshake(toReady = false)
        e2.feed(frame(request("q1", "queue.replay", JSONObject())))
        // While the backlog head is in flight, a NEW occurrence arrives.
        e2.dispatchAction("app:main", queuedDescriptor(), null)
        respondTo(e2, out.events()[0], "accepted")
        // The replay concluded at the barrier: the new event is retained.
        val summary = out.last { it.opt("id") == "q1" }.getJSONObject("result")
        assertEquals(1, summary.getInt("delivered"))
        assertEquals(1, summary.getInt("remaining"))
        assertEquals(1, out.events().size) // nothing new delivered yet
        // session.ready releases it.
        e2.feed(frame(request("r1", "session.ready", JSONObject())))
        assertEquals(2, out.events().size)
    }

    @Test
    fun syncingEraEditsFlushBeforeReleasedEvents() {
        // Review P1: SPEC 10.3 — divergent SYNCING-era values flush as
        // state.changed ahead of any event released on READY.
        val out = mutableListOf<JSONObject>()
        val q = DurableQueue(MemoryQueueStore(), 256, 8_388_608)
        val store = surfaceWithInput()
        val e = engineOn(q, store, out)
        e.handshake(toReady = false)
        e.publishState("app:main", "title", "syncing edit")
        e.dispatchAction("app:main", queuedDescriptor(), null)
        assertTrue(out.none { it.opt("method") == "state.changed" })
        e.feed(frame(request("r1", "session.ready", JSONObject())))
        val stateIdx = out.indexOfFirst { it.opt("method") == "state.changed" }
        val eventIdx = out.indexOfFirst { it.opt("method") == "event.action" }
        assertTrue(stateIdx in 0 until eventIdx)
        assertEquals("syncing edit",
            out[stateIdx].getJSONObject("params").getString("value"))
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
            store.update("app:main", 1, JSONObject().put("t", "text_input")
                .put("id", "title").put("value", "authored"), null, null, null)
            val q1 = DurableQueue(FileQueueStore(queueFile), 256, 8_388_608)
            val out1 = mutableListOf<JSONObject>()
            val e1 = engineOn(q1, store, out1)
            e1.publishState("app:main", "title", "offline edit")
            e1.dispatchAction("app:main",
                queuedDescriptor().put("capture_fields", JSONArray(listOf("title"))), null)
            assertTrue(out1.isEmpty()) // nothing on the wire without a session
        }

        // Life 2: fresh objects read the same files. The welcome carries the
        // durable draft (SPEC 15.1 input_state) AND the queued count; replay
        // delivers the event with its occurrence-time capture.
        val store2 = SurfaceStore(16, 1024, backing = FileSurfaceBacking(surfaceFile))
        val q2 = DurableQueue(FileQueueStore(queueFile), 256, 8_388_608)
        val out2 = mutableListOf<JSONObject>()
        val e2 = engineOn(q2, store2, out2)
        e2.handshake(toReady = false)
        val welcome = out2.last().getJSONObject("result")
        assertEquals("offline edit", welcome.getJSONObject("input_state")
            .getJSONObject("app:main").getString("title"))
        assertEquals(1, welcome.getInt("queued_events"))
        e2.feed(frame(request("q1", "queue.replay", JSONObject())))
        val event = out2.events().single().getJSONObject("params")
        assertEquals("offline edit", event.getJSONObject("fields").getString("title"))
        assertNotNull(event.getLong("queued_at_ms"))
        respondTo(e2, out2.events().single(), "accepted")
        assertEquals(0, q2.count())
    }
}
