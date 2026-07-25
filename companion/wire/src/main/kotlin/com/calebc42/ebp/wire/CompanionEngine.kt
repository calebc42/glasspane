// SPDX-License-Identifier: GPL-3.0-or-later
// The Companion's session engine: SPEC 9 handshake validation, SPEC 10
// lifecycle with fail-closed pre-auth behavior, welcome construction with
// the SPEC 4.5 reservation check, and SPEC 7.3 dispatch rules.
// Transport-agnostic: feed() consumes bytes, sink receives outbound bytes.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject

/** Static configuration for one Companion endpoint. */
data class CompanionConfig(
    val serverName: String,
    val serverVersion: String,
    /** pairing_id (32 hex) -> decoded 16-octet token. */
    val pairings: Map<String, ByteArray>,
    /** Capabilities this Companion supports (SPEC 22.1 names). */
    val supportedCapabilities: Set<String>,
    /** surface_profiles welcome member, exactly as advertised (SPEC 10.2). */
    val surfaceProfiles: JSONObject,
    /** The welcome limits object (SPEC 4.5). */
    val limits: JSONObject,
    /** SPEC 20.1: the device report, echoed in the welcome when `capabilities`
     * or `triggers` is granted. Its `caps` are the exact capability.invoke
     * catalog this Companion supports; empty means neither module is offered. */
    val deviceReport: JSONObject = JSONObject(),
    /** SPEC 20.2: the platform executor for capability.invoke. REQUIRED when
     * `device.caps` is non-empty; a null handler fails every invoke as 1003. */
    val capabilityHandler: CapabilityHandler? = null,
    /** SPEC 21.4: whether the user approved substituting sensitive-source
     * (sms/call/calendar) trigger data into an on_fire sink. Default deny. */
    val sensitiveSubstitutionApproved: Boolean = false,
    /** Nonce source, injectable for tests. */
    val nonceSource: () -> String = EbpAuth::generateNonce,
)

class CompanionEngine(
    private val config: CompanionConfig,
    /** Shared across connections: surface state outlives a session (13.5). */
    val surfaces: SurfaceStore = SurfaceStore(
        config.limits.getLong("max_surfaces"), config.limits.getLong("max_surface_ids"),
        config.limits.optLong("max_capture_fields", 64),
        config.limits.optLong("max_chart_points", Long.MAX_VALUE),
        config.limits.optLong("max_canvas_ops", Long.MAX_VALUE),
        config.limits.optLong("max_rich_spans", Long.MAX_VALUE),
        config.limits.optLong("max_table_cells", Long.MAX_VALUE),
        nodeTypesFromProfiles(config.surfaceProfiles, "app"),
        nodeTypesFromProfiles(config.surfaceProfiles, "notification")),
    /** Shared across connections AND restarts: the SPEC 15 durable queue. */
    val queue: DurableQueue = DurableQueue(
        MemoryQueueStore(),
        config.limits.getLong("max_queued_events"),
        config.limits.getLong("max_queued_bytes")),
    /** Shared across connections AND restarts: SPEC 18.6 reminders + fired
     * receipts outlive a session exactly like the queue and surfaces. */
    val reminders: ReminderStore = ReminderStore(),
    /** Shared across connections AND restarts: SPEC 21.1 trigger registrations
     * + runtime records outlive a session (baselines re-established on arm). */
    val triggers: TriggerStore = TriggerStore(),
    /** Device-lifetime SPEC 21.2 firing service. The app injects one shared
     * instance; the default builds a per-engine one for tests. This engine
     * attaches as the LiveSession for live drop delivery + wake/pump. */
    val firing: TriggerFiringService = TriggerFiringService(
        triggers, queue, maxEventBytes = config.limits.getLong("max_event_bytes"),
        triggerCaps = jsonStringSet(config.deviceReport, "trigger_caps"),
        capabilityHandler = config.capabilityHandler),
    private val sink: (ByteArray) -> Unit,
) : LiveSession {
    var state: SessionState = SessionState.CONNECTED
        private set
    var closeReason: String? = null
        private set
    private var granted: List<String> = emptyList()

    /** Presentation hook: called with the surface ID after an applied
     * update or remove, so a host can re-render (the mechanism is the
     * endpoint's, what to draw is the application's). */
    var surfaceListener: ((String) -> Unit)? = null

    private val decoder = FrameDecoder()
    private var pendingPairingId: String? = null
    private var pendingClientNonce: String? = null
    private var pendingServerNonce: String? = null

    init {
        // SPEC 4.5: the welcome reservation must hold before any session.
        checkLimits()
        // SPEC 5.2: become the firing service's live session (newest wins).
        firing.attach(this)
    }

    // Synchronized with sendRequest/dispatchAction/publishState: the UI
    // thread and the reader thread share one ordered sink (SPEC 7.4).
    @Synchronized
    fun feed(bytes: ByteArray) {
        if (state == SessionState.CLOSED) return
        try {
            decoder.feed(bytes) { msg ->
                if (state != SessionState.CLOSED) {
                    try {
                        dispatch(msg)
                    } catch (e: Exception) {
                        // A dispatch failure must fail closed, never
                        // crash-loop the host (review: poison-record).
                        close("dispatch failure: ${e.message}")
                    }
                }
            }
        } catch (e: FrameClose) { return close("frame: ${e.message}") }
        catch (e: FrameIncomplete) { return close("frame: ${e.message}") }
        catch (e: WireParseError) {
            // SPEC 6.2: a complete body that is invalid UTF-8 or JSON gets a
            // Parse Error with id:null; the stream stayed synchronized, so
            // the connection MAY (and here does) continue.
            emitFramingError(-32700, "Parse error", "parse-error")
        } catch (e: InvalidRequest) {
            // SPEC 6.2/4.1: a non-object top level, batch array, or duplicate
            // member names get one Invalid Request with id:null; continue.
            emitFramingError(-32600, "Invalid Request", "invalid-request")
        }
    }

    @Synchronized
    fun close(reason: String) {
        state = SessionState.CLOSED
        closeReason = reason
        // LD-18: leave the device-lifetime slot FIRST — a throw from any
        // host callout below must never park a dead engine in the firing
        // service's AtomicReference for the connection's afterlife.
        firing.detach(this)
        // P0 (review): the in-flight marker is connection state. If this
        // engine's request dies with the connection, the record MUST
        // return to plain queued so the next session's replay can move
        // (SPEC 15.3: events without a permanent result remain queued).
        queue.clearInFlight(myInFlightSeq)
        myInFlightSeq = null
        // SPEC 22.3 (LD-13): outstanding requests fail locally — every
        // pending callback gets one synthetic terminal error, so no caller
        // waits forever on a response the dead transport will never carry.
        if (pending.isNotEmpty()) {
            val callbacks = pending.values.toList()
            pending.clear()
            val err = JSONObject()
                .put("code", -32603).put("message", "Connection closed")
                .put("data", JSONObject().put("kind", "connection-closed"))
            callbacks.forEach { cb -> runCatching { cb(null, err) } }
        }
        // SPEC 18.1: on transport loss every outstanding dialog is
        // dismissed locally; its request dies with the connection.
        // LD-18: callouts are best-effort — a throwing host listener must
        // not abort the rest of teardown (serve()'s finally has no retry).
        if (dialogs.isNotEmpty()) {
            val ids = dialogs.keys.toList()
            dialogs.clear()
            ids.forEach { runCatching { dialogListener?.invoke(it, null) } }
        }
        // SPEC 18.3: pie menus are ephemeral to the session — dismiss all.
        if (pieMenus.isNotEmpty()) {
            val ids = pieMenus.keys.toList()
            pieMenus.clear()
            ids.forEach { runCatching { pieMenuListener?.invoke(it, null) } }
        }
        // SPEC 19: transport loss closes all editor sessions locally; the
        // session IDs are dead and new sessions are created after reconnect.
        editors.values.forEach { it.state = EditorSession.State.CLOSED }
        editors.clear()
        surfaceEditors.clear()
        pendingEditors.clear()
    }

    /** The queue_seq this engine's connection put in flight, if any. */
    private var myInFlightSeq: Long? = null

    // ------------------------------------------------------------ dispatch

    private fun dispatch(msg: JSONObject) {
        when (classifyMessage(msg)) {
            MessageClass.REQUEST ->
                // SPEC 4.1/7.3: the raw params reach handleRequest so a
                // non-object (a positional array) is rejected, not coerced.
                handleRequest(msg.get("id"), msg.getString("method"), msg.opt("params"))
            MessageClass.NOTIFICATION ->
                handleNotification(msg.getString("method"), msg.opt("params"))
            MessageClass.RESPONSE -> {
                val callback = (msg.opt("id") as? Int)?.let(pending::remove)
                callback?.invoke(msg.optJSONObject("result"),
                    msg.optJSONObject("error"))
            }
            null ->
                // SPEC 7.3: structurally invalid; answer only when an id exists.
                if (msg.has("id") && msg.has("method"))
                    respondError(msg.get("id"), -32600, "Invalid Request", "invalid-request")
        }
    }

    // ------------------------------------------ outbound requests (SPEC 7)

    private var nextOutboundId = 0
    private val pending = HashMap<Int, (JSONObject?, JSONObject?) -> Unit>()

    /** Send a Companion-originated request; integer ids per SPEC 7.2. */
    @Synchronized
    fun sendRequest(method: String, params: JSONObject,
                    callback: (JSONObject?, JSONObject?) -> Unit) {
        val id = ++nextOutboundId
        pending[id] = callback
        emit(JSONObject().put("jsonrpc", "2.0").put("id", id)
            .put("method", method).put("params", params))
    }

    // ---------------------------------------- actions and input (SPEC 14)

    /** SPEC 14.2: clipboard.copy / share.send / companion.settings.open are
     * host-platform duties — (builtin name, descriptor) for the app layer. */
    var hostBuiltinListener: ((String, JSONObject) -> Unit)? = null

    /**
     * SPEC 14.2: execute a Companion-local builtin from a surface hook. The
     * descriptor's shape was validated at accept time (unknown builtin or bad
     * members rejected the document); an invalid CONTEXT here — a view.switch
     * on a single-view surface, an unknown view, a dialog completion outside
     * a dialog — is a safe no-op, never a crash.
     */
    private fun executeBuiltin(surface: String, descriptor: JSONObject) {
        when (descriptor.optString("builtin")) {
            "view.switch" -> {
                val view = descriptor.opt("view") as? String ?: return
                if (!surfaces.switchView(surface, view)) return
                surfaceListener?.invoke(surface)
                // SPEC 14.2: while READY, report view.switched with the view
                // in args — when_offline drop, so never queued.
                if (state != SessionState.READY) return
                val revision = surfaces.revisionOf(surface) ?: return
                val params = JSONObject()
                    .put("event_id", EbpAuth.generateNonce())
                    .put("action", "view.switched")
                    .put("surface", surface)
                    .put("revision_seen", revision)
                    .put("occurred_at_ms", queue.effectiveNow())
                    .put("args", JSONObject().put("view", view))
                if (params.toString().toByteArray(Charsets.UTF_8).size <=
                    config.limits.getLong("max_event_bytes"))
                    sendRequest("event.action", params) { _, _ -> }
            }
            "trigger.fire" -> {
                // SPEC 14.2/21.5: fire the named manual trigger through the
                // normal pipeline; requires the triggers capability.
                if ("triggers" !in granted) return
                val id = descriptor.opt("id") as? String ?: return
                pendingPairingId?.let { firing.fireManual(it, id, "tap") }
            }
            "clipboard.copy", "share.send", "companion.settings.open" ->
                hostBuiltinListener?.invoke(descriptor.optString("builtin"), descriptor)
            // dialog.submit/dismiss are valid only inside their dialog; the
            // renderer routes those through DialogContext. Reaching here is an
            // invalid context: no-op.
        }
    }

    /**
     * SPEC 14.1/14.3/14.4: dispatch a remote user action from a surface
     * node. W5 carries the live path only: while READY the event is a
     * request awaiting its 4-status result; otherwise the occurrence is
     * dropped, which is exactly `when_offline: "drop"` — the durable
     * queue and wake policies land at W6, builtins at W7.
     */
    @Synchronized
    fun dispatchAction(surface: String, descriptor: JSONObject, hookValue: Any?,
                       injected: JSONObject? = null,
                       extraFields: JSONObject? = null,
                       callback: ((String?, JSONObject?) -> Unit)? = null) {
        if (descriptor.has("builtin")) return executeBuiltin(surface, descriptor)
        val revision = surfaces.revisionOf(surface) ?: return
        val args = JSONObject(descriptor.optJSONObject("args")?.toString() ?: "{}")
        // SPEC 14.3: the hook's produced value is injected, never authored.
        if (hookValue != null) args.put("value", hookValue)
        // SPEC 14.3: multi-member hooks (on_reorder from/to/order, on_add_row/
        // on_add_col index, swipe on_trigger direction) inject a copy of their
        // produced members; authored conflicts were rejected at accept time.
        injected?.let { for (k in it.keySet()) args.put(k, it.get(k)) }
        val params = JSONObject()
            .put("event_id", EbpAuth.generateNonce())
            .put("action", descriptor.getString("action"))
            .put("surface", surface)
            .put("revision_seen", revision)
            .put("occurred_at_ms", queue.effectiveNow())
        if (args.length() > 0) params.put("args", args)
        // SPEC 14.1: capture_fields is one occurrence-time snapshot,
        // stored inside the durable record for queued policies (15.1).
        val fields = JSONObject()
        descriptor.optJSONArray("capture_fields")?.let { capture ->
            for (i in 0 until capture.length()) {
                val fieldId = capture.getString(i)
                fields.put(fieldId,
                    surfaces.currentValue(surface, fieldId) ?: JSONObject.NULL)
            }
        }
        // SPEC 14.6: a value the renderer supplies at occurrence time — a
        // text_input password's on_submit, whose secret has no retained draft
        // for currentValue() to read (it never emits state.changed).
        extraFields?.let { for (k in it.keySet()) fields.put(k, it.get(k)) }
        if (fields.length() > 0) params.put("fields", fields)
        val policy = descriptor.optString("when_offline", OFFLINE_DEFAULT)
        // SPEC 15.1: a durable policy persists a queued_at_ms; it is part of
        // the stored and replayed params, so add it BEFORE the size check.
        if (policy == "queue" || policy == "wake")
            params.put("queued_at_ms", queue.effectiveNow())
        // SPEC 14.4/15.4: verify the COMPLETE params against max_event_bytes
        // before persistence or transmission; an oversized occurrence is a
        // local diagnostic, never a frame or a record.
        if (params.toString().toByteArray(Charsets.UTF_8).size >
            config.limits.getLong("max_event_bytes")) {
            callback?.invoke(null, JSONObject()
                .put("code", 1201).put("message", "Event exceeds max_event_bytes")
                .put("data", JSONObject().put("kind", "content-invalid")
                    .put("reason", "event-too-large")))
            return
        }
        when (policy) {
            "queue", "wake" -> {
                // SPEC 22.3/15.1: durable admission precedes every wake or
                // delivery attempt, including when READY right now.
                when (queue.admit(params, policy,
                        descriptor.optString("dedupe").takeIf { it.isNotEmpty() },
                        descriptor.getLong("ttl_s"))) {
                    is AdmitResult.Admitted -> {
                        if (policy == "wake" && state != SessionState.READY &&
                            queue.effectiveNow() - lastWakeMs >= 60_000) {
                            lastWakeMs = queue.effectiveNow()
                            wakeListener?.invoke()
                        }
                        callback?.invoke("queued", null)
                        pumpAdvance() // no-op unless READY and unpaused
                    }
                    AdmitResult.QueueFull ->
                        // SPEC 15.1: the 1601 queue-full equivalent, local.
                        callback?.invoke(null, JSONObject()
                            .put("code", 1601).put("message", "Queue full")
                            .put("data", JSONObject().put("kind", "queue-full")))
                    AdmitResult.StorageFailed ->
                        // SPEC 15.1: MUST NOT claim the interaction queued.
                        callback?.invoke(null, JSONObject()
                            .put("code", -32603).put("message", "Storage failed")
                            .put("data", JSONObject().put("kind", "internal-error")))
                }
            }
            else -> { // drop: live delivery only (SPEC 15.1)
                if (state != SessionState.READY) return
                sendRequest("event.action", params) { result, error ->
                    callback?.invoke(result?.optString("status"), error)
                }
            }
        }
    }

    /**
     * SPEC 14.6: record a user edit and publish it while READY. W5 sends
     * immediately (a zero debounce conforms to the 500 ms cap), so the
     * P1 #2 flush barrier holds trivially — nothing is ever pending.
     * State-before-action ordering falls out of the shared ordered sink.
     */
    private val syncingDirty = LinkedHashSet<Pair<String, String>>()

    @Synchronized
    fun publishState(surface: String, id: String, value: Any?) {
        // SPEC 14.6: a password node MUST NOT emit state.changed, and
        // only stateful nodes in the accepted snapshot have a wire
        // address at all.
        if (!surfaces.isStatefulNode(surface, id)) return
        if (surfaces.isPasswordNode(surface, id)) return
        surfaces.putDraft(surface, id, value)
        if (state != SessionState.READY) {
            // SPEC 10.3: divergent values changed before READY flush on
            // entering READY, ahead of any released event.
            syncingDirty.add(surface to id)
            return
        }
        val revision = surfaces.revisionOf(surface) ?: return
        emit(JSONObject().put("jsonrpc", "2.0").put("method", "state.changed")
            .put("params", JSONObject()
                .put("surface", surface).put("revision_seen", revision)
                .put("id", id).put("value", value ?: JSONObject.NULL)))
    }

    private fun handleRequest(id: Any, method: String, rawParams: Any?) {
        // SPEC 7.2 (amendment #34): ids are strings or safe integers.
        if (!isValidRequestId(id))
            return respondError(id, -32600, "Invalid Request", "invalid-request")
        // SPEC 10.1: fail closed before authentication on method and state,
        // BEFORE params — a non-handshake request is 1200 even when its
        // params are malformed.
        when (state) {
            SessionState.CONNECTED ->
                if (method != "session.hello")
                    return respondError(id, 1200, "Not authenticated", "not-authenticated")
            SessionState.CHALLENGED ->
                if (method != "auth.response")
                    return respondError(id, 1200, "Not authenticated", "not-authenticated")
            else -> Unit
        }
        // SPEC 4.1/7.3: params, when present, MUST be an object — no
        // positional array, no coercion. A legal handshake method with
        // malformed params is -32602 here too (SPEC 10.1).
        val params = when (rawParams) {
            null -> JSONObject()
            is JSONObject -> rawParams
            else -> return respondError(id, -32602, "Invalid params", "invalid-params")
        }
        when (state) {
            SessionState.CONNECTED -> return handleHello(id, params)
            SessionState.CHALLENGED -> return handleAuth(id, params)
            else -> Unit
        }
        // SPEC 11/4.5 (amendment #93): a method name that is not a §4.4
        // identifier within 128 octets is -32601 WITHOUT consulting the
        // registry — no allocation is keyed by an unvalidated name.
        if (!isValidMethodName(method))
            return respondError(id, -32601, "Method not found", "method-not-found")
        val spec = METHOD_REGISTRY[method]
            ?: return respondError(id, -32601, "Method not found", "method-not-found")
        if (spec.sender == Sender.COMPANION || !spec.isRequest)
            // SPEC 7.3: wrong endpoint or wrong class.
            return respondError(id, -32600, "Invalid Request", "invalid-request")
        if (state !in spec.states)
            // SPEC 10.1: post-auth, wrong-state requests get 1204.
            return respondError(id, 1204, "Not legal in this session state", "session-state")
        when (method) {
            "surface.update" -> handleSurfaceUpdate(id, params)
            "surface.remove" -> handleSurfaceRemove(id, params)
            "queue.replay" -> handleQueueReplay(id)
            "dialog.show" -> handleDialogShow(id, params)
            "reminders.set" -> handleRemindersSet(id, params)
            "triggers.set" -> handleTriggersSet(id, params)
            "capability.invoke" -> handleCapabilityInvoke(id, params)
            "edit.apply" -> handleEditApply(id, params)
            "edit.resync" -> handleEditResync(id, params)
            "session.ready" -> {
                // SPEC 10.3: the {} response serializes ahead of every
                // READY-only frame; emitting before transitioning does that.
                respondResult(id, JSONObject())
                state = sessionStep(state, SessionEvent.READY_CONFIRMED) ?: state
                // SPEC 10.3: flush every divergent value changed during
                // SYNCING as ordered state.changed BEFORE releasing events.
                for ((surface, nodeId) in syncingDirty.toList()) {
                    if (!surfaces.hasDraft(surface, nodeId)) continue
                    val revision = surfaces.revisionOf(surface) ?: continue
                    emit(notification("state.changed", JSONObject()
                        .put("surface", surface).put("revision_seen", revision)
                        .put("id", nodeId)
                        .put("value", surfaces.draft(surface, nodeId)
                            ?: JSONObject.NULL)))
                }
                syncingDirty.clear()
                // SPEC 19: open editor sessions accepted during SYNCING.
                val pend = pendingEditors.toList()
                pendingEditors.clear()
                for ((doc, eid, seed) in pend) openEditor(doc, eid, seed)
                // SPEC 15.3: only after that flush may events flow.
                pumpAdvance()
            }
            else ->
                // Registered in SPEC 11 but its rung has not landed yet.
                respondError(id, -32603, "Not implemented at this rung", "internal-error")
        }
    }

    // -------------------------------------- durable delivery pump (SPEC 15)

    /** Platform hook for the `wake` policy: called after durable admission
     * (SPEC 15.1: persistence precedes every wake attempt). */
    var wakeListener: (() -> Unit)? = null
    private var lastWakeMs = 0L

    private var pumpPaused = false
    private var replayId: Any? = null
    private var replayDelivered = 0
    private var replayRejected = 0
    private var blockedBy: Any = JSONObject.NULL

    private fun handleQueueReplay(id: Any) {
        // SPEC 15.3: only one replay may be active.
        if (replayId != null)
            return respondError(id, 1600, "A replay is already active", "queue-busy")
        replayId = id
        replayDelivered = 0
        replayRejected = 0
        blockedBy = JSONObject.NULL
        pumpPaused = false // an explicit replay resumes a paused pump
        queue.sweepExpired()
        // SPEC 15.3: join an in-flight durable request rather than duplicate
        // it; its disposition lands in this summary via onPumpResult.
        if (!queue.hasInFlight()) pumpAdvance()
    }

    private fun replayActive() = replayId != null

    /** Send the head event when the pump is free; conclude a replay at a
     * stable stop (SPEC 15.3). */
    private fun pumpAdvance() {
        if (queue.hasInFlight() || pumpPaused) {
            if (pumpPaused) concludeReplay()
            return
        }
        // Auto-delivery needs READY; an explicit replay drives the pump in
        // SYNCING too — that IS the 10.3 barrier draining the backlog.
        if (!replayActive() && state != SessionState.READY) return
        if (replayActive() && state != SessionState.SYNCING &&
            state != SessionState.READY) return
        // SPEC 15.3/21.2: atomically select + mark-in-flight the head, applying
        // the SYNCING replay barrier and the pending-local gate inside one queue
        // critical section — closing the head()+assign compaction race and the
        // headIsPendingLocal()/head() TOCTOU.
        val barrier = if (state == SessionState.SYNCING) sessionBoundarySeq else null
        when (val d = queue.beginDelivery(barrier)) {
            is Delivery.Ready -> {
                val seq = d.record.getLong("queue_seq")
                myInFlightSeq = seq
                // SPEC 15.3: the stored record replays with its stored event_id.
                sendRequest("event.action", d.record.getJSONObject("event")) { result, error ->
                    onPumpResult(seq, result, error)
                }
            }
            Delivery.PendingLocal -> return                  // wait for on_fire (Step 4)
            Delivery.Empty, Delivery.BarrierHeld -> concludeReplay()
        }
    }

    private fun onPumpResult(seq: Long, result: JSONObject?, error: JSONObject?) {
        queue.clearInFlight(seq)
        myInFlightSeq = null
        when {
            error != null -> {
                // SPEC 15.3: any well-formed error retains the head and
                // pauses the pump; later admissions never bypass it.
                pumpPaused = true
                // SPEC 15.3: only a valid string kind rides blocked_by.
                blockedBy = ((error.opt("data") as? JSONObject)
                    ?.opt("kind") as? String)?.takeIf { it.isNotEmpty() }
                    ?: "json-rpc-error"
                concludeReplay()
            }
            result?.optString("status") in listOf("accepted", "duplicate") -> {
                replayDelivered++
                queue.deleteRecord(seq)
                pumpAdvance()
            }
            result?.optString("status") in listOf("stale", "rejected") -> {
                replayRejected++
                queue.deleteRecord(seq)
                pumpAdvance()
            }
            else -> {
                // SPEC 15.3: unknown status is a protocol violation —
                // retain the event, one safe log.error, close.
                emit(notification("log.error", JSONObject()
                    .put("code", -32603)
                    .put("message", "event.action result with unknown status")
                    .put("data", JSONObject().put("kind", "internal-error"))))
                close("event.action result with unknown status")
            }
        }
    }

    private fun concludeReplay() {
        val id = replayId ?: return
        replayId = null
        respondResult(id, JSONObject()
            .put("delivered", replayDelivered)
            .put("rejected", replayRejected)
            .put("expired", queue.takeExpiredCount())
            .put("remaining", queue.count())
            .put("blocked_by", blockedBy))
    }

    // ------------------------------------------------------ surfaces (13)

    private fun surfaceRevision(value: Any?): Long? =
        when (value) {
            is Int -> value.toLong()
            is Long -> value
            else -> null
        }?.takeIf { it in 0..9_007_199_254_740_991L } // SPEC 4.2

    private fun handleSurfaceUpdate(id: Any, params: JSONObject) {
        val surface = params.opt("surface") as? String
        val revision = surfaceRevision(params.opt("revision"))
        val spec = params.optJSONObject("spec")
        if (surface == null || revision == null || spec == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        if (!surfaces.isValidSurfaceId(surface))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("reason", "surface-id"))
        // SPEC 13.1: the namespace's capability must have been granted.
        val requiredCap = when (surfaces.namespace(surface)) {
            "notification" -> "surfaces.notification"
            "widget" -> "surfaces.widget"
            else -> null
        }
        if (requiredCap != null && requiredCap !in granted)
            return respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("reason", "namespace-not-granted"))
        // SPEC 19: count distinct synchronized-editor identities the whole
        // mutation would yield — every other surface's editors plus this
        // spec's — and reject before applying if it exceeds the limit.
        val newEditors = if ("editor.sync" in granted) scanSyncedEditors(spec)
            else emptyMap()
        val othersEditorCount = surfaceEditors.entries
            .filter { it.key != surface }.sumOf { it.value.size }
        if (othersEditorCount + newEditors.size >
            config.limits.optLong("max_editor_sessions", 8))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("reason", "editor-session-limit"))
        try {
            val result = surfaces.update(
                surface, revision, spec,
                params.optJSONObject("stale_spec"),
                params.opt("current_view") as? String,
                params.optJSONArray("reset_input_ids"))
            respondResult(id, JSONObject()
                .put("status", result.status)
                .put("revision", result.revision)
                .put("present", result.present))
            if (result.status == "applied") {
                reconcileEditors(surface, newEditors)
                surfaceListener?.invoke(surface)
            }
        } catch (e: ContentInvalid) {
            respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("path", e.path).put("reason", e.reason))
        }
    }

    // Per-surface synchronized editors: surface -> (editor_id -> document).
    private val surfaceEditors = HashMap<String, MutableMap<String, String>>()
    // Editors accepted during SYNCING, opened on entering READY (SPEC 19).
    private val pendingEditors = ArrayList<Triple<String, String, String>>()

    /** SPEC 17.4/19: an `editor` node with a `document` is synchronized;
     * its editor_id is the node id. Walks the spec (all views). */
    private fun scanSyncedEditors(spec: JSONObject): Map<String, JSONObject> {
        val out = LinkedHashMap<String, JSONObject>()
        fun walk(v: Any?) {
            when (v) {
                is JSONArray -> for (i in 0 until v.length()) walk(v.get(i))
                is JSONObject -> {
                    if (v.opt("t") == "editor" && v.opt("document") is String &&
                        v.opt("id") is String)
                        out[v.getString("id")] = v
                    for (k in v.keySet()) walk(v.get(k))
                }
            }
        }
        walk(spec)
        return out
    }

    /** SPEC 19: open sessions for newly present synchronized editors (or
     * queue them until READY), and close those removed or whose document
     * changed. Same document+editor_id preserves the session. */
    private fun reconcileEditors(surface: String, newEditors: Map<String, JSONObject>) {
        val prev = surfaceEditors[surface] ?: emptyMap()
        val next = LinkedHashMap<String, String>()
        for ((editorId, node) in newEditors) {
            val document = node.getString("document")
            next[editorId] = document
            val existed = prev[editorId]
            if (existed == document) continue // identity preserved
            if (existed != null) closeEditor(existed, editorId) // document changed
            val seed = node.optString("value", "")
            if (state == SessionState.READY) openEditor(document, editorId, seed)
            else pendingEditors.add(Triple(document, editorId, seed))
        }
        // Editors that vanished from this surface close.
        for ((editorId, document) in prev)
            if (editorId !in next) closeEditor(document, editorId)
        if (next.isEmpty()) surfaceEditors.remove(surface)
        else surfaceEditors[surface] = next
    }

    private fun closeSurfaceEditors(surface: String) {
        surfaceEditors.remove(surface)?.forEach { (editorId, document) ->
            closeEditor(document, editorId)
        }
    }

    private fun handleSurfaceRemove(id: Any, params: JSONObject) {
        val surface = params.opt("surface") as? String
        val revision = surfaceRevision(params.opt("revision"))
        if (surface == null || revision == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 13.1: a structurally invalid ID must not become a tombstone —
        // it would enter the welcome `surfaces` map and consume a
        // max_surface_ids slot. surface.update rejects it identically.
        if (!surfaces.isValidSurfaceId(surface))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("reason", "surface-id"))
        // SPEC 13.1: removal is legal for any reported surface, no cap gate.
        try {
            val result = surfaces.remove(surface, revision)
            respondResult(id, JSONObject()
                .put("status", result.status)
                .put("revision", result.revision)
                .put("present", result.present))
            if (result.status == "applied") {
                closeSurfaceEditors(surface)
                surfaceListener?.invoke(surface)
            }
        } catch (e: ContentInvalid) {
            respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("path", e.path).put("reason", e.reason))
        }
    }

    private fun handleNotification(method: String, rawParams: Any?) {
        // Pre-auth (SPEC 10.1) and unknown/wrong-direction (SPEC 7.3)
        // notifications are logged and dropped; nothing is emitted.
        if (state == SessionState.CONNECTED || state == SessionState.CHALLENGED) return
        // SPEC 11 (amendment #93): a non-identifier or over-long method name
        // is dropped without consulting the registry.
        if (!isValidMethodName(method)) return
        val spec = METHOD_REGISTRY[method] ?: return
        if (spec.sender == Sender.COMPANION || spec.isRequest) return
        // SPEC 10.1: a notification not legal in this session state is dropped
        // (a notification has no id, so the request's 1204 has no analogue) —
        // e.g. a READY-only toast/pie/annotation arriving during SYNCING.
        if (state !in spec.states) return
        // SPEC 7.3: structurally invalid notification params are dropped —
        // a notification has no id to answer (log.error arrives with W9).
        val params = rawParams as? JSONObject ?: return
        // SPEC 7.5/18.1: rpc.cancel concludes an outstanding dialog with 1301.
        when (method) {
            "rpc.cancel" -> {
                val cancelId = params.opt("id")
                val entry = dialogs.entries.find { it.value == cancelId } ?: return
                dialogs.remove(entry.key)
                respondError(entry.value, 1301, "Request was cancelled",
                    "request-cancelled")
                dialogListener?.invoke(entry.key, null)
            }
            "toast.show" -> handleToastShow(params)
            "theme.set" -> handleThemeSet(params)
            "pie_menu.show" -> handlePieMenuShow(params)
            "pie_menu.dismiss" -> handlePieMenuDismiss(params)
            "diagnostics.show", "eldoc.show", "fontify.show" ->
                handleAnnotation(method, params)
        }
    }

    // ----------------------------------------------------- pie menus (18.3)

    // menu_id -> the categories array of an open menu (ephemeral).
    private val pieMenus = LinkedHashMap<String, JSONArray>()

    /** Present hook: (menu_id, {categories, center_label?}) to show;
     * (menu_id, null) to dismiss. */
    var pieMenuListener: ((String, JSONObject?) -> Unit)? = null

    private fun handlePieMenuShow(params: JSONObject) {
        if ("presentation.pie-menu" !in granted) return
        val menuId = params.opt("menu_id") as? String ?: return
        // SPEC 4.4/18.3: menu_id MUST be a valid identifier, not any string.
        if (!identifier.matches(menuId)) return
        val categories = params.optJSONArray("categories") ?: return
        // SPEC 18.3: an invalid menu is dropped, not partially shown.
        if (!validPieCategories(categories)) return
        // SPEC 18.3: a new id over the limit is dropped with a diagnostic;
        // replacing an existing id stays legal at the limit.
        if (!pieMenus.containsKey(menuId) &&
            pieMenus.size >= config.limits.optLong("max_pie_menus", 1)) {
            // SHOULD send a rate-limited log.error (rate limiting is W9).
            emit(notification("log.error", JSONObject().put("code", 1201)
                .put("message", "Too many pie menus")
                .put("data", JSONObject().put("kind", "content-invalid")
                    .put("reason", "pie-menu-limit"))))
            return
        }
        pieMenus[menuId] = categories
        val present = JSONObject().put("categories", categories)
        (params.opt("center_label") as? String)?.let { present.put("center_label", it) }
        pieMenuListener?.invoke(menuId, present)
    }

    private fun handlePieMenuDismiss(params: JSONObject) {
        if ("presentation.pie-menu" !in granted) return
        val menuId = params.opt("menu_id") as? String ?: return
        // SPEC 18.3: dismissing an unknown id is a no-op.
        if (pieMenus.remove(menuId) != null) pieMenuListener?.invoke(menuId, null)
    }

    private fun validPieCategories(categories: JSONArray): Boolean {
        if (categories.length() !in 1..10) return false
        for (i in 0 until categories.length()) {
            val cat = categories.optJSONObject(i) ?: return false
            if (cat.opt("label") !is String) return false
            val hasItems = cat.has("items")
            val hasOnTap = cat.has("on_tap")
            if (hasItems == hasOnTap) return false // exactly one
            if (hasOnTap) {
                if (!validPieDescriptor(cat.optJSONObject("on_tap"))) return false
            } else {
                val items = cat.optJSONArray("items") ?: return false
                if (items.length() < 1) return false
                for (j in 0 until items.length()) {
                    val item = items.optJSONObject(j) ?: return false
                    if (item.opt("label") !is String) return false
                    if (!validPieDescriptor(item.optJSONObject("on_tap"))) return false
                }
            }
        }
        return true
    }

    /** SPEC 18.3: a pie-menu descriptor is a remote action, drop-only, with
     * no authored conflict on the injected members. */
    private fun validPieDescriptor(d: JSONObject?): Boolean {
        if (d == null || d.opt("action") !is String) return false
        if (d.optString("when_offline", OFFLINE_DEFAULT) != "drop") return false
        val args = d.optJSONObject("args") ?: return true
        return !(args.has("menu_id") || args.has("category_index") ||
            args.has("item_index"))
    }

    /**
     * SPEC 18.3: a user selection. Injects menu_id, zero-based
     * category_index, and (for a nested item) item_index into a copy of
     * the descriptor's args, dismisses the ephemeral menu, and dispatches
     * the drop-only, context-less event.
     */
    @Synchronized
    fun selectPieMenu(menuId: String, categoryIndex: Int, itemIndex: Int? = null) {
        val categories = pieMenus[menuId] ?: return
        val category = categories.optJSONObject(categoryIndex) ?: return
        val descriptor = if (itemIndex != null)
            category.optJSONArray("items")?.optJSONObject(itemIndex)?.optJSONObject("on_tap")
        else category.optJSONObject("on_tap")
        descriptor ?: return
        val args = JSONObject(descriptor.optJSONObject("args")?.toString() ?: "{}")
            .put("menu_id", menuId).put("category_index", categoryIndex)
        if (itemIndex != null) args.put("item_index", itemIndex)
        pieMenus.remove(menuId)
        pieMenuListener?.invoke(menuId, null)
        dispatchDescriptorContextless(descriptor, args)
    }

    /**
     * A context-less event.action (SPEC 14.4: pie-menu and reminder events
     * omit surface/revision_seen/dialog_id), honoring the descriptor's
     * offline policy. A drop descriptor delivers live or is lost; queue and
     * wake admit to the durable queue exactly as a surface action would.
     */
    private fun dispatchDescriptorContextless(descriptor: JSONObject, args: JSONObject,
                                              callback: ((String?, JSONObject?) -> Unit)? = null) =
        dispatchContextless(queue, config.limits.getLong("max_event_bytes"),
            descriptor, args, this, callback)

    // ------- LiveSession: the connection-bound half of a context-less event.
    // Held as a newest-wins slot by cold senders (reminder taps, the firing
    // service); invoked never while the caller holds another module's monitor.

    /** SPEC 15.1: a drop event.action delivers live only while READY. */
    @Synchronized
    override fun deliverLiveDrop(params: JSONObject,
                                 callback: ((String?, JSONObject?) -> Unit)?) {
        if (state != SessionState.READY) return
        sendRequest("event.action", params) { result, error ->
            callback?.invoke(result?.optString("status"), error)
        }
    }

    /** SPEC 15.3: after a durable admit, wake (for `wake`) and advance the pump. */
    @Synchronized
    override fun onDurableAdmitted(policy: String) {
        if (policy == "wake" && state != SessionState.READY &&
            queue.effectiveNow() - lastWakeMs >= 60_000) {
            lastWakeMs = queue.effectiveNow()
            wakeListener?.invoke()
        }
        pumpAdvance()
    }

    // ------------------------------------------------------ reminders (18.6)

    /** Schedule hook after an accepted replace: (owner, complete NEW set,
     * complete PRIOR set) so the host can cancel removed alarms and arm only
     * new/changed tuples (SPEC 18.6). */
    var reminderListener: ((String, JSONArray, JSONArray) -> Unit)? = null

    // SPEC 4.4: an identifier is 1..128 ASCII chars (the leading char plus up
    // to 127 more) — the length bound applies to reminder owner/id, cap names,
    // and pie menu_id alike.
    private val identifier = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}")
    private val reminderMembers = setOf("id", "title", "body", "at_ms", "on_tap")

    private fun handleRemindersSet(id: Any, params: JSONObject) {
        if ("reminders.owner" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        val owner = params.opt("owner") as? String
        val arr = params.optJSONArray("reminders")
        if (owner.isNullOrEmpty() || !identifier.matches(owner) || arr == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        val parsed = ArrayList<JSONObject>(arr.length())
        val seen = HashSet<String>()
        for (i in 0 until arr.length()) {
            val r = arr.optJSONObject(i)
                ?: return respondError(id, 1201, "Invalid content", "content-invalid",
                    JSONObject().put("path", "reminders[$i]").put("reason", "not-an-object"))
            try {
                validateReminder(r, seen)
            } catch (e: ContentInvalid) {
                return respondError(id, 1201, "Invalid content", "content-invalid",
                    JSONObject().put("path", "reminders[$i].${e.path}").put("reason", e.reason))
            }
            parsed.add(r)
        }
        // SPEC 18.6: replacement plus OTHER owners must fit max_reminders.
        val others = reminders.totalCount() - reminders.ownerCount(owner)
        if (others + parsed.size > config.limits.optLong("max_reminders", 256))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("reason", "reminder-limit"))
        // SPEC 18.6: the accepted set commits durably before it is claimed; a
        // storage failure leaves the prior set in force and answers an error.
        // Capture the prior set BEFORE the replace so the host can cancel
        // alarms for removed tuples.
        val prior = reminders.reminders(owner)
        val count = try {
            reminders.replace(owner, parsed)
        } catch (e: Exception) {
            return respondError(id, -32603, "Storage failed", "internal-error")
        }
        respondResult(id, JSONObject().put("count", count))
        reminderListener?.invoke(owner, JSONArray(parsed), JSONArray(prior))
    }

    private fun validateReminder(r: JSONObject, seen: MutableSet<String>) {
        for (k in r.keySet()) if (k !in reminderMembers)
            throw ContentInvalid(k, "unknown reminder member")
        val rid = r.opt("id") as? String
        if (rid == null || !identifier.matches(rid))
            throw ContentInvalid("id", "must be an identifier")
        if (!seen.add(rid)) throw ContentInvalid("id", "duplicate reminder id")
        val title = r.opt("title") as? String
        if (title.isNullOrEmpty()) throw ContentInvalid("title", "non-empty string required")
        if (r.has("body") && r.opt("body") !is String)
            throw ContentInvalid("body", "must be a string")
        val at = r.opt("at_ms")
        // SPEC 4.3: an epoch timestamp is a non-negative INTEGER — a JSON number
        // with a fractional part (e.g. 1.5, silently truncated by toLong) is
        // rejected, not accepted. Integrality is checked by value so it holds
        // whether the parser boxed it as Double or BigDecimal.
        if (at !is Number || at.toLong() < 0 || at.toLong() > 9_007_199_254_740_991L ||
            at.toDouble() != Math.floor(at.toDouble()))
            throw ContentInvalid("at_ms", "must be a non-negative integer timestamp")
        r.optJSONObject("on_tap")?.let { onTap ->
            if (onTap.opt("action") !is String)
                throw ContentInvalid("on_tap", "must be a remote ActionDescriptor")
            val policy = onTap.optString("when_offline", OFFLINE_DEFAULT)
            if ((policy == "queue" || policy == "wake") && !onTap.has("ttl_s"))
                throw ContentInvalid("on_tap", "$policy requires ttl_s")
            // SPEC 18.6: the injected members must not be authored.
            onTap.optJSONObject("args")?.let { a ->
                if (a.has("owner") || a.has("reminder_id"))
                    throw ContentInvalid("on_tap.args", "owner/reminder_id are injected")
            }
        }
    }

    /** SPEC 18.6: mark a reminder presented (once per tuple). Returns true
     * when the host should present it now, false if already fired. */
    @Synchronized
    fun markReminderFired(owner: String, reminderId: String): Boolean =
        reminders.markFired(owner, reminderId)

    /** SPEC 18.6: an explicit tap enters the Section 14 pipeline with the
     * authored offline policy; owner and reminder_id are injected. A
     * reminder with no on_tap dispatches nothing (dismissal is not a tap). */
    @Synchronized
    fun dispatchReminderTap(owner: String, reminderId: String,
                            callback: ((String?, JSONObject?) -> Unit)? = null) {
        routeReminderTap(reminders, queue, config.limits.getLong("max_event_bytes"),
            owner, reminderId, this, callback)
    }

    // -------------------------------------------- device triggers (SPEC 21)

    /** Arm hook: (identity, its complete new registration list) after an
     * accepted replace. The host arms/cancels platform event sources. */
    var triggerListener: ((String, List<JSONObject>) -> Unit)? = null

    /** SPEC 21.3/21.7: current sample for a state type (delegates to the shared
     * firing service, which owns the runtime). */
    var triggerStateProvider: (String) -> JSONObject?
        get() = firing.stateProvider
        set(v) { firing.stateProvider = v }

    /** SPEC 21.4: post a substituted on_fire notification (delegates to the
     * shared firing service). */
    var triggerNotifyListener: ((JSONObject) -> Unit)?
        get() = firing.notifyListener
        set(v) { firing.notifyListener = v }

    /** SPEC 21.5: a level-type observation. Firing lives in the device-lifetime
     * service and needs no live session (SPEC 21.1/21.2); the observe entry
     * points remain for a session-driven source and delegate to it. */
    @Synchronized
    fun observeTriggerSample(type: String, sample: JSONObject) =
        firing.observeSample(type, sample)

    /** SPEC 21.5: an external occurrence (package/sms/boot/time/timezone/manual). */
    @Synchronized
    fun observeTriggerEvent(type: String, data: JSONObject) =
        firing.observeExternal(type, data)

    /** SPEC 21.4/21.5: a `manual` trigger fired via the builtin or trigger.fire. */
    @Synchronized
    fun fireManualTrigger(triggerId: String, source: String) {
        val id = pendingPairingId ?: return
        if ("triggers" !in granted) return
        firing.fireManual(id, triggerId, source)
    }

    /**
     * SPEC 21.1: atomically replace the pairing identity's trigger set. The
     * whole set is validated first (types, predicates, policy/ttl/dedupe,
     * on_fire structure, resource limits); on any failure nothing changes and
     * the reply is 1101 identifying the offending trigger. An accepted set
     * carries forward every unchanged id's runtime records (SPEC 21.1).
     */
    private fun handleTriggersSet(id: Any, params: JSONObject) {
        if ("triggers" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        val identity = pendingPairingId
            ?: return respondError(id, 1200, "Not authenticated", "not-authenticated")
        val caps = TriggerCaps(
            triggerTypes = jsonStringSet(config.deviceReport, "trigger_types"),
            stateTypes = jsonStringSet(config.deviceReport, "state_types"),
            trackableStateTypes = jsonStringSet(config.deviceReport, "trackable_state_types"),
            triggerCaps = jsonStringSet(config.deviceReport, "trigger_caps"),
            maxResponses = config.limits.optLong("max_trigger_responses", 16).toInt(),
            sensitiveSubstitutionApproved = config.sensitiveSubstitutionApproved)
        val entries = try {
            TriggerValidator.validateSet(params, caps)
        } catch (e: ContentInvalid) {
            return respondError(id, 1101, "Triggers rejected", "triggers-rejected",
                JSONObject().put("path", e.path).put("reason", e.reason))
        }
        // SPEC 21.1: the replace-set size MUST fit max_triggers; reject, never
        // truncate. Validated before any registration changes.
        if (entries.size > config.limits.optLong("max_triggers", 64))
            return respondError(id, 1101, "Triggers rejected", "triggers-rejected",
                JSONObject().put("reason", "trigger-limit"))
        // SPEC 21.5: a newly added or changed one-shot time.at_ms MUST be later
        // than the wall clock at acceptance. An unchanged entry (same id,
        // canonically equal to the prior) stays valid past its time, even once
        // completed. Reject the whole set — never apply it partially.
        val nowMs = queue.effectiveNow()
        for (e in entries) {
            val p = e.optJSONObject("params") ?: continue
            if (e.getString("type") != "time" || !p.has("at_ms")) continue
            val prior = firing.store.registration(identity, e.getString("id"))?.entry
            val changed = prior == null || !TriggerStore.canonicalEquals(prior, e)
            if (changed && p.getLong("at_ms") <= nowMs)
                return respondError(id, 1101, "Triggers rejected", "triggers-rejected",
                    JSONObject().put("path", "triggers[${e.getString("id")}].params.at_ms")
                        .put("reason", "at_ms-not-future"))
        }
        // SPEC 21.1: the accepted set commits durably (via the firing service)
        // before it is claimed, then the new/changed registrations are silently
        // baselined; a storage failure leaves the prior set in force.
        val count = try {
            firing.replaceSet(identity, entries)
        } catch (e: Exception) {
            return respondError(id, -32603, "Storage failed", "internal-error")
        }
        respondResult(id, JSONObject().put("count", count))
        triggerListener?.invoke(identity, entries)
    }

    // ---------------------------------------- device capabilities (SPEC 20)

    /**
     * SPEC 20.2: run one advertised platform operation. The library gates cap
     * existence (1001) and validates the closed Args before any side effect
     * (-32602); the host handler then re-checks authorization and executes,
     * its typed refusal (1002 cap-permission / 1003 cap-failed) forwarded
     * verbatim. capability.invoke is available only when `capabilities` was
     * granted; invocations are session-scoped and non-durable (SPEC 20.2).
     */
    private fun handleCapabilityInvoke(id: Any, params: JSONObject) {
        if ("capabilities" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        for (k in params.keySet()) if (k != "cap" && k != "args")
            return respondError(id, -32602, "Invalid params", "invalid-params")
        val cap = params.opt("cap") as? String
        if (cap == null || !identifier.matches(cap))
            return respondError(id, -32602, "Invalid params", "invalid-params")
        val args = when (val a = params.opt("args")) {
            null, JSONObject.NULL -> JSONObject()
            is JSONObject -> a
            else -> return respondError(id, -32602, "Invalid params", "invalid-params")
        }
        // SPEC 20.2: cap MUST appear in device.caps, else 1001.
        val caps = config.deviceReport.optJSONArray("caps") ?: JSONArray()
        if ((0 until caps.length()).none { caps.opt(it) == cap })
            return respondError(id, 1001, "Unsupported capability", "cap-unsupported")
        // SPEC 20.3: validate the closed Args before any side effect.
        try {
            CapabilityCatalog.validateArgs(cap, args)
        } catch (e: ContentInvalid) {
            return respondError(id, -32602, "Invalid params", "invalid-params",
                JSONObject().put("path", e.path).put("reason", e.reason))
        }
        // SPEC 20.2: the host re-checks authorization at invocation and runs it.
        val handler = config.capabilityHandler
            ?: return respondError(id, 1003, "Capability failed", "cap-failed",
                JSONObject().put("reason", "no-handler"))
        when (val out = handler.invoke(cap, args)) {
            is CapabilityOutcome.Ok -> respondResult(id, out.result)
            is CapabilityOutcome.Fail -> respondError(id, out.code, "Capability failed",
                if (out.code == 1002) "cap-permission" else "cap-failed",
                JSONObject().put("reason", out.reason))
        }
    }

    // ------------------------------------------------- editor sync (SPEC 19)

    // Keyed by (document, editor_id); the Companion is the shadow's owner.
    private val editors = LinkedHashMap<Pair<String, String>, EditorSession>()

    /** Re-render hook: the session's shadow changed from an inbound apply or
     * a resync (the host editor must reflect it). */
    var editorListener: ((EditorSession) -> Unit)? = null
    /** Annotation hook: (kind, editorId, payload) after a session/seq match. */
    var annotationListener: ((String, String, JSONObject) -> Unit)? = null

    private fun findEditor(session: String): EditorSession? =
        editors.values.firstOrNull { it.sessionId == session &&
            it.state != EditorSession.State.CLOSED }

    /** SPEC 19: create a fresh session and seed it, sending edit.open. Called
     * by the host when a synchronized editor node first becomes present in
     * READY (the surface-node lifecycle wiring is a later atom). */
    @Synchronized
    fun openEditor(document: String, editorId: String, seed: String,
                   cursor: ScalarPos = ScalarPos(0)): EditorSession {
        val s = EditorSession(document, editorId, EbpAuth.generateNonce())
        s.shadow = seed
        s.setCaret(ScalarPos(cursor.v.coerceIn(0, s.scalarLength())), null, null)
        editors[document to editorId] = s
        emit(notification("edit.open", JSONObject()
            .put("document", document).put("editor_id", editorId)
            .put("session", s.sessionId).put("seq", 0).put("text", seed)
            .put("cursor", s.cursor).put("sel_start", s.selStart)
            .put("sel_end", s.selEnd)))
        return s
    }

    /** SPEC 19.3: a local edit applies to the shadow immediately, advances
     * seq, and mirrors as an edit.delta. Read-only unless OPEN and READY. */
    @Synchronized
    fun localEditorEdit(document: String, editorId: String,
                        start: ScalarPos, del: Int, text: String): Boolean {
        val s = editors[document to editorId] ?: return false
        if (s.state != EditorSession.State.OPEN || state != SessionState.READY)
            return false
        // SPEC 19.4 (amendment #84): a local edit that would carry the
        // document past max_editor_bytes is refused as if read-only.
        if (s.spliceJcsBytes(start, del, text) >
            config.limits.optLong("max_editor_bytes", Long.MAX_VALUE)) return false
        val len = s.scalarLength() - del + text.codePointCount(0, text.length)
        if (!s.splice(start, del, text, len)) return false
        s.seq += 1
        emit(notification("edit.delta", JSONObject()
            .put("document", document).put("editor_id", editorId)
            .put("session", s.sessionId).put("seq", s.seq)
            .put("start", start.v).put("del", del).put("text", text).put("len", len)))
        return true
    }

    /** SPEC 19.3: best-effort caret context; throttled at the source.
     * T2/LD-4: takes Compose UTF-16 positions and converts against the
     * shadow — the one text authority — clamped, ordered, never splitting a
     * surrogate pair; the wire carries scalars only. */
    @Synchronized
    fun localEditorCaret(document: String, editorId: String, cursor: Utf16Pos,
                         selStart: Utf16Pos? = null, selEnd: Utf16Pos? = null) {
        val s = editors[document to editorId] ?: return
        if (s.state != EditorSession.State.OPEN || state != SessionState.READY) return
        val (c, lo, hi) = scalarCaret(s.shadow, cursor, selStart, selEnd) ?: return
        if (!s.setCaret(c, lo, hi)) return
        val p = JSONObject().put("document", document).put("editor_id", editorId)
            .put("session", s.sessionId).put("seq", s.seq).put("cursor", s.cursor)
        if (lo != null) p.put("sel_start", s.selStart).put("sel_end", s.selEnd)
        emit(notification("edit.caret", p))
    }

    /** SPEC 19.1/19.3 (LD-4): convert a Compose caret to the scalar domain
     * against TEXT — sel pair ordered (a backward drag arrives reversed),
     * cursor snapped to an end when a pair is present (lo when it falls
     * before the selection, else hi). Null only for a half-present pair. */
    private fun scalarCaret(text: String, cursor: Utf16Pos, selStart: Utf16Pos?,
                            selEnd: Utf16Pos?): Triple<ScalarPos, ScalarPos?, ScalarPos?>? {
        if ((selStart == null) != (selEnd == null)) return null
        val c = scalarPosIn(text, cursor)
        if (selStart == null || selEnd == null) return Triple(c, null, null)
        val a = scalarPosIn(text, selStart).v
        val b = scalarPosIn(text, selEnd).v
        val lo = minOf(a, b)
        val hi = maxOf(a, b)
        val snapped = if (c.v != lo && c.v != hi)
            ScalarPos(if (c.v < lo) lo else hi) else c
        return Triple(snapped, ScalarPos(lo), ScalarPos(hi))
    }

    /**
     * SPEC 17.7 `command`: a non-durable edit.command event.action. Valid only
     * for a synchronized editor in READY (an OPEN session); connection loss or
     * any transient error abandons it without replay, so it never touches the
     * durable queue. args carry command + full editor context; Emacs allowlists
     * edit.command and then the nested command, never evaluating either string.
     */
    @Synchronized
    fun editorCommand(surface: String, document: String, editorId: String,
                      command: String, cursor: Utf16Pos,
                      selStart: Utf16Pos, selEnd: Utf16Pos): Boolean {
        val s = editors[document to editorId] ?: return false
        if (s.state != EditorSession.State.OPEN || state != SessionState.READY) return false
        val revision = surfaces.revisionOf(surface) ?: return false
        // SPEC 19.1 / SPEC.md 2590+2640 (LD-4): Compose UTF-16 positions are
        // converted to scalars against the shadow BEFORE they reach the wire,
        // and the pair is ordered — ten emoji with the caret at the end is
        // cursor 10, never 20, and a backward drag never emits
        // sel_start > sel_end. This was the one editor path bypassing
        // EditorSession's conversions.
        val (c, lo, hi) = scalarCaret(s.shadow, cursor, selStart, selEnd)
            ?: return false
        val params = JSONObject()
            .put("event_id", EbpAuth.generateNonce())
            .put("action", "edit.command")
            .put("surface", surface)
            .put("revision_seen", revision)
            .put("occurred_at_ms", queue.effectiveNow())
            .put("args", JSONObject()
                .put("command", command).put("document", document)
                .put("editor_id", editorId).put("session", s.sessionId)
                .put("seq", s.seq).put("cursor", c.v)
                .put("sel_start", lo!!.v).put("sel_end", hi!!.v))
        if (params.toString().toByteArray(Charsets.UTF_8).size >
            config.limits.getLong("max_event_bytes")) return false
        sendRequest("event.action", params) { _, _ -> }
        return true
    }

    /** SPEC 19: close a session (removal, identity/document change). */
    @Synchronized
    fun closeEditor(document: String, editorId: String) {
        val s = editors.remove(document to editorId) ?: return
        if (s.state == EditorSession.State.CLOSED) return
        s.state = EditorSession.State.CLOSED
        if (state == SessionState.READY)
            emit(notification("edit.close", JSONObject()
                .put("document", document).put("editor_id", editorId)
                .put("session", s.sessionId)))
    }

    private fun editorStale(id: Any) = respondError(id, 1201, "Invalid content",
        "content-invalid", JSONObject().put("reason", "editor-stale"))

    private fun handleEditApply(id: Any, params: JSONObject) {
        if ("editor.sync" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        val doc = params.opt("document") as? String
        val eid = params.opt("editor_id") as? String
        val session = params.opt("session") as? String
        if (doc == null || eid == null || session == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        val s = editors[doc to eid]
        // SPEC 19.2: an unknown or CLOSED tuple, or a stale session id, is
        // editor-stale (a later request, not a silently-ignored notification).
        if (s == null || s.state == EditorSession.State.CLOSED || s.sessionId != session)
            return editorStale(id)
        // SPEC 19.4: the move-only form omits ALL of start/del/text/len and
        // keeps seq; the text form carries all four. A message with only
        // some of them is neither form — structurally invalid.
        val hasSplice = listOf("start", "del", "text", "len").count(params::has)
        if (hasSplice == 0) {
            val cursor = (params.opt("cursor") as? Number)?.toInt()
                ?: return respondError(id, -32602, "Invalid params", "invalid-params")
            val selStart = (params.opt("sel_start") as? Number)?.toInt()
            val selEnd = (params.opt("sel_end") as? Number)?.toInt()
            if (!s.setCaret(ScalarPos(cursor),
                    selStart?.let(::ScalarPos), selEnd?.let(::ScalarPos)))
                return respondResult(id, JSONObject().put("status", "stale").put("seq", s.seq))
            editorListener?.invoke(s)
            return respondResult(id, JSONObject().put("status", "applied").put("seq", s.seq))
        }
        val seq = (params.opt("seq") as? Number)?.toLong()
        val start = (params.opt("start") as? Number)?.toInt()
        val del = (params.opt("del") as? Number)?.toInt()
        val text = params.opt("text") as? String
        val len = (params.opt("len") as? Number)?.toInt()
        if (seq == null || start == null || del == null || text == null || len == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 19.4 (LD-5): `cursor` is REQUIRED on every text-changing
        // apply — the peer dictates the post-splice caret — and selection
        // members are paired-or-omitted. Structural absence is -32602, like
        // any other missing required member.
        val cursor = (params.opt("cursor") as? Number)?.toInt()
            ?: return respondError(id, -32602, "Invalid params", "invalid-params")
        val selStart = (params.opt("sel_start") as? Number)?.toInt()
        val selEnd = (params.opt("sel_end") as? Number)?.toInt()
        if (params.has("sel_start") != params.has("sel_end"))
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 19.4: apply only at seq+1 with a valid splice; otherwise a
        // typed stale result leaves this (winning) session OPEN.
        if (seq != s.seq + 1)
            return respondResult(id, JSONObject().put("status", "stale").put("seq", s.seq))
        // SPEC 19.4 (amendment #84): an inbound apply that would carry the
        // document past max_editor_bytes is 1201 editor-too-large, text
        // unchanged. Only a splice that would otherwise be valid can be
        // too large — a range- or length-invalid one is stale, as before.
        val grown = s.spliceJcsBytes(ScalarPos(start), del, text)
        if (grown >= 0 &&
            len == s.scalarLength() - del + text.codePointCount(0, text.length) &&
            grown > config.limits.optLong("max_editor_bytes", Long.MAX_VALUE))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("reason", "editor-too-large"))
        // SPEC 19.4 (LD-5): the splice AND the peer's post-state caret are
        // validated together, atomically — a failed gate changes nothing.
        // The old path spliced, then silently discarded a failed setCaret
        // and answered "applied" over a half-updated session.
        if (!s.spliceRemote(ScalarPos(start), del, text, len, ScalarPos(cursor),
                selStart?.let(::ScalarPos), selEnd?.let(::ScalarPos)))
            return respondResult(id, JSONObject().put("status", "stale").put("seq", s.seq))
        s.seq = seq
        editorListener?.invoke(s)
        respondResult(id, JSONObject().put("status", "applied").put("seq", s.seq))
    }

    private fun handleEditResync(id: Any, params: JSONObject) {
        if ("editor.sync" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        val doc = params.opt("document") as? String
        val eid = params.opt("editor_id") as? String
        val session = params.opt("session") as? String
        if (doc == null || eid == null || session == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        val s = editors[doc to eid]
        if (s == null || s.state == EditorSession.State.CLOSED || s.sessionId != session)
            return editorStale(id)
        // SPEC 19.4: close the prior session, mint a fresh id at seq 0,
        // return the complete current state; old-session messages are dead.
        s.sessionId = EbpAuth.generateNonce()
        s.seq = 0
        s.state = EditorSession.State.OPEN
        respondResult(id, JSONObject()
            .put("document", doc).put("editor_id", eid)
            .put("session", s.sessionId).put("seq", 0).put("text", s.shadow)
            .put("cursor", s.cursor).put("sel_start", s.selStart)
            .put("sel_end", s.selEnd))
    }

    /** SPEC 19.3: ask Emacs to complete at the current cursor. The result's
     * {prefix, candidates} reach CALLBACK; candidate selection is a later
     * local edit via [selectCompletion]. Non-durable, session-scoped. */
    @Synchronized
    fun requestCompletion(document: String, editorId: String,
                          callback: (String, JSONArray) -> Unit) {
        val s = editors[document to editorId] ?: return
        if (s.state != EditorSession.State.OPEN || state != SessionState.READY) return
        val atSession = s.sessionId
        val atSeq = s.seq
        val atCursor = s.cursor
        sendRequest("edit.complete", JSONObject()
            .put("document", document).put("editor_id", editorId)
            .put("session", atSession).put("seq", atSeq).put("cursor", atCursor)) { result, error ->
            if (error == null && result != null &&
                editors[document to editorId]?.sessionId == atSession)
                callback(result.optString("prefix"),
                    result.optJSONArray("candidates") ?: JSONArray())
        }
    }

    /**
     * SPEC 19.3: apply a chosen candidate. Only when the session, seq, and
     * cursor still match and the prefix still precedes the cursor does the
     * Companion replace that prefix with `insert` as one local edit (an
     * edit.delta); otherwise it discards the result without changing text.
     */
    @Synchronized
    fun selectCompletion(document: String, editorId: String, atSession: String,
                         atSeq: Long, atCursor: Int, prefix: String, insert: String): Boolean {
        val s = editors[document to editorId] ?: return false
        if (s.state != EditorSession.State.OPEN || state != SessionState.READY) return false
        if (s.sessionId != atSession || s.seq != atSeq || s.cursor != atCursor) return false
        val prefixLen = prefix.codePointCount(0, prefix.length)
        val start = atCursor - prefixLen
        if (start < 0) return false
        // The prefix must still be the text immediately before the cursor.
        val from = s.shadow.offsetByCodePoints(0, start)
        val to = s.shadow.offsetByCodePoints(0, atCursor)
        if (s.shadow.substring(from, to) != prefix) return false
        return localEditorEdit(document, editorId, ScalarPos(start), prefixLen, insert)
    }

    /** T2/LD-5: run F over a live editor session under the engine monitor —
     * the host's one safe read path for shadow/caret state (the mirror it
     * publishes to the display, and the snap-back after a refused edit). */
    @Synchronized
    fun <T> withEditor(document: String, editorId: String,
                       f: (EditorSession) -> T): T? =
        editors[document to editorId]?.let(f)

    private fun handleAnnotation(method: String, params: JSONObject) {
        if ("editor.sync" !in granted) return
        val eid = params.opt("editor_id") as? String ?: return
        val session = params.opt("session") as? String ?: return
        val seq = (params.opt("seq") as? Number)?.toLong() ?: return
        val s = findEditor(session) ?: return
        // SPEC 19.5: discard an annotation whose session or seq does not
        // match the current state (latest-wins, never delays text sync).
        if (s.editorId != eid || s.seq != seq) return
        annotationListener?.invoke(method, eid, params)
    }

    // ------------------------------------------------------- themes (18.4)

    /** The latest accepted theme (SPEC 18.4): each notification is a
     * complete replacement. `dark` is a Boolean, or null for follow-system
     * (amendment #36). `colors`/`syntax` are role maps, or null to clear. */
    var themeListener: ((dark: Boolean?, colors: JSONObject?, syntax: JSONObject?) -> Unit)? = null
    private var theme: JSONObject = JSONObject()

    private fun handleThemeSet(params: JSONObject) {
        if ("theme" !in granted) return
        // SPEC 18.4: a complete replacement of the previously pushed values.
        // `dark` absent => follow system; present => forced polarity.
        val dark = when (val d = params.opt("dark")) {
            is Boolean -> d
            else -> null
        }
        // `colors`/`syntax`: an object replaces, JSON null clears the mirror.
        val colors = params.opt("colors").let {
            if (it == JSONObject.NULL) null else it as? JSONObject
        }
        val syntax = params.opt("syntax").let {
            if (it == JSONObject.NULL) null else it as? JSONObject
        }
        theme = JSONObject()
            .put("dark", if (dark == null) JSONObject.NULL else dark)
            .put("colors", colors ?: JSONObject.NULL)
            .put("syntax", syntax ?: JSONObject.NULL)
        themeListener?.invoke(dark, colors, syntax)
    }

    /** SPEC 18.4: the persisted theme, for rendering across reconnects. */
    fun currentTheme(): JSONObject = theme

    // ------------------------------------------------------- toasts (18.2)

    /** Present hook: (text, duration_s or null for the platform default).
     * Best-effort presentation — never an acknowledgement (SPEC 18.2). */
    var toastListener: ((String, Long?) -> Unit)? = null

    private fun handleToastShow(params: JSONObject) {
        // SPEC 22.1: presentation.toast must have been granted.
        if ("presentation.toast" !in granted) return
        // SPEC 18.2: text REQUIRED plain text; duration_s in 1..10 or absent.
        val text = params.opt("text") as? String ?: return
        val duration = when (val d = params.opt("duration_s")) {
            null -> null
            is Int -> d.toLong().takeIf { it in 1..10 } ?: return
            is Long -> d.takeIf { it in 1..10 } ?: return
            else -> return
        }
        toastListener?.invoke(text, duration)
    }

    // ------------------------------------------------------ dialogs (18.1)

    // dialog_id -> the outstanding dialog.show request id (deferred reply).
    private val dialogs = LinkedHashMap<String, Any>()

    /** Present hook: (dialog_id, spec) to show; (dialog_id, null) to
     * dismiss. What the dialog contains is the application's; the request
     * correlation is the endpoint's. */
    var dialogListener: ((String, JSONObject?) -> Unit)? = null
    /** SPEC 18.1: a submit whose prospective response would exceed
     * max_frame_bytes. The dialog stays outstanding; the host MUST show a
     * local validation diagnostic and erase any volatile password (§14.6). */
    var dialogOverflowListener: ((String) -> Unit)? = null

    private fun handleDialogShow(id: Any, params: JSONObject) {
        val dialogId = params.opt("dialog_id") as? String
        val spec = params.optJSONObject("spec")
        if (dialogId.isNullOrEmpty() || spec == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 18.1: gated on surfaces.dialog.
        if ("surfaces.dialog" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        // SPEC 18.1: a second outstanding request with the same id is
        // content-invalid; the first is neither replaced nor aliased.
        if (dialogs.containsKey(dialogId))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("reason", "dialog-duplicate"))
        // SPEC 18.1: exceeding max_dialogs is 1401; existing dialogs stand.
        if (dialogs.size >= config.limits.optLong("max_dialogs", 4))
            return respondError(id, 1401, "Too many dialogs", "overloaded")
        try {
            SpecValidator.validateSurfaceSpec(
                spec, maxCaptureFields = config.limits.optLong("max_capture_fields", 64),
                maxChartPoints = config.limits.optLong("max_chart_points", Long.MAX_VALUE),
                maxCanvasOps = config.limits.optLong("max_canvas_ops", Long.MAX_VALUE),
                maxRichSpans = config.limits.optLong("max_rich_spans", Long.MAX_VALUE),
                maxTableCells = config.limits.optLong("max_table_cells", Long.MAX_VALUE),
                // SPEC 17.1: a dialog spec is gated to the dialog profile's
                // advertised node_types — an app-only type (chart/editor/
                // scaffold) degrades instead of rendering + dispatching here.
                advertisedTypes = nodeTypesFromProfiles(config.surfaceProfiles, "dialog"))
        } catch (e: ContentInvalid) {
            return respondError(id, 1201, "Invalid content", "content-invalid",
                JSONObject().put("path", e.path).put("reason", e.reason))
        }
        // SPEC 18.1: held outstanding — no reply until a builtin or cancel.
        dialogs[dialogId] = id
        dialogListener?.invoke(dialogId, spec)
    }

    /** SPEC 18.1: dialog.submit builtin completes the request as submitted.
     * VALUE is the builtin's authored value; FIELDS the captured node
     * values (the renderer holds dialog-local state, SPEC 18.1). */
    @Synchronized
    fun completeDialogSubmit(dialogId: String, value: Any? = null,
                             fields: JSONObject? = null) {
        val reqId = dialogs[dialogId] ?: return
        val result = JSONObject().put("status", "submitted")
        if (value != null) result.put("value", value)
        if (fields != null && fields.length() > 0) result.put("fields", fields)
        // SPEC 18.1: serialize the prospective complete response FIRST. If its
        // body would exceed max_frame_bytes, write no part of it and do NOT
        // complete the dialog — the dialog stays outstanding so the user can
        // shrink the input, and the host concludes any password attempt with a
        // §14.6 erasure. This ordering prevents orphaning the request in
        // encodeFrame after the dialog was already removed.
        val body = JSONObject().put("jsonrpc", "2.0").put("id", reqId)
            .put("result", result).toString().toByteArray(Charsets.UTF_8).size
        if (body > WireLimits.MAX_BODY_OCTETS) {
            dialogOverflowListener?.invoke(dialogId)
            return
        }
        dialogs.remove(dialogId)
        respondResult(reqId, result)
        dialogListener?.invoke(dialogId, null)
    }

    /** SPEC 18.1: dialog.dismiss builtin or a platform dismissal. */
    @Synchronized
    fun completeDialogDismiss(dialogId: String) {
        val reqId = dialogs.remove(dialogId) ?: return
        respondResult(reqId, JSONObject().put("status", "dismissed"))
        dialogListener?.invoke(dialogId, null)
    }

    // ----------------------------------------------------------- handshake

    private val hexId = Regex("[0-9a-f]{32}")

    private fun handleHello(id: Any, params: JSONObject) {
        val protocol = params.opt("protocol")
        if (protocol != 2) {
            // SPEC 9.2/12: protocol mismatch is 1202 with data.supported.
            return respondError(id, 1202, "Unsupported protocol major", "protocol-version",
                JSONObject().put("supported", JSONArray(listOf(2))))
        }
        val client = params.optJSONObject("client")
        val pairingId = params.opt("pairing_id")
        val clientNonce = params.opt("client_nonce")
        val wants = params.optJSONArray("wants")
        val clientOk = client != null &&
            client.keySet() == setOf("name", "version") &&
            client.opt("name").let { it is String && it.isNotEmpty() && it.utf8Len() <= 128 } &&
            client.opt("version").let { it is String && it.isNotEmpty() && it.utf8Len() <= 128 }
        val wantsList = wants?.let { arr ->
            (0 until arr.length()).map { arr.opt(it) }
        }
        val wantsOk = wantsList != null && wantsList.size <= 128 &&
            wantsList.all { it is String } &&
            wantsList.toSet().size == wantsList.size // duplicates are invalid
        if (!clientOk || pairingId !is String || !hexId.matches(pairingId) ||
            clientNonce !is String || !EbpAuth.isValidNonce(clientNonce) || !wantsOk)
            // SPEC 10.1: a legal handshake method with malformed params.
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 9.1: never reveal whether the pairing ID is known; challenge
        // regardless and fail at the proof.
        lastWants = wantsList!!.map { it as String }
        pendingPairingId = pairingId
        pendingClientNonce = clientNonce
        pendingServerNonce = config.nonceSource()
        respondResult(id, JSONObject().put("server_nonce", pendingServerNonce))
        state = sessionStep(state, SessionEvent.HELLO_ACCEPTED) ?: state
    }

    private fun handleAuth(id: Any, params: JSONObject) {
        val pid = params.opt("pairing_id")
        val cn = params.opt("client_nonce")
        val sn = params.opt("server_nonce")
        val proof = params.opt("client_proof")
        // SPEC 9.3: type/grammar failures are -32602 followed by close.
        if (pid !is String || !hexId.matches(pid) ||
            cn !is String || !EbpAuth.isValidNonce(cn) ||
            sn !is String || !EbpAuth.isValidNonce(sn) ||
            proof !is String || !EbpAuth.isValidProof(proof)) {
            respondError(id, -32602, "Invalid params", "invalid-params")
            return close("malformed auth.response")
        }
        // SPEC 9.3: well-formed but reused, mismatched, or incorrect -> 1203.
        val token = config.pairings[pendingPairingId]
        val ok = pid == pendingPairingId && cn == pendingClientNonce &&
            sn == pendingServerNonce && token != null &&
            EbpAuth.verifyClientProof(proof, token, pid, cn, sn)
        if (!ok) {
            respondError(id, 1203, "Authentication failed", "auth-failed")
            return close("auth failed")
        }
        respondResult(id, buildWelcome(token!!))
        state = sessionStep(state, SessionEvent.AUTH_VERIFIED) ?: state
    }

    // ------------------------------------------------------------- welcome

    private var lastWants: List<String> = emptyList()
    private var sessionBoundarySeq = Long.MAX_VALUE

    private fun buildWelcome(token: ByteArray): JSONObject {
        granted = lastWants.filter { it in config.supportedCapabilities }
        sessionBoundarySeq = queue.boundarySeq()
        val welcome = JSONObject()
            .put("server_proof", EbpAuth.serverProof(
                token, pendingPairingId!!, pendingClientNonce!!, pendingServerNonce!!))
            .put("protocol", 2)
            .put("server", JSONObject()
                .put("name", config.serverName).put("version", config.serverVersion))
            .put("granted", JSONArray(granted))
            .put("surface_profiles", config.surfaceProfiles)
            .put("surfaces", surfaces.snapshot()) // snapshots AND tombstones (10.2)
            // SPEC 10.2: the count visible to the next replay, after the
            // already-identified expired records are gone.
            .put("queued_events", queue.let { it.sweepExpired(); it.count() })
            .put("limits", config.limits)
        // SPEC 10.2: input_state MUST be omitted when empty; device waits
        // for the capability/trigger modules.
        surfaces.inputState().takeIf { it.length() > 0 }
            ?.let { welcome.put("input_state", it) }
        // SPEC 20.1: the device report is REQUIRED once capabilities or
        // triggers is granted. trigger_caps MUST be empty unless triggers is
        // granted, and the trigger-only members MAY be empty then too — so a
        // capabilities-only session never sees a non-empty trigger surface.
        if ("capabilities" in granted || "triggers" in granted) {
            val report = JSONObject(config.deviceReport.toString())
            if ("triggers" !in granted) {
                report.put("trigger_caps", JSONArray())
                report.put("trigger_types", JSONArray())
                report.put("trackable_state_types", JSONArray())
                report.put("trigger_unavailable", JSONObject())
                // state_types is REQUIRED only when triggers granted or
                // state.get is in caps; otherwise it too may be empty.
                val caps = report.optJSONArray("caps") ?: JSONArray()
                if ((0 until caps.length()).none { caps.opt(it) == "state.get" })
                    report.put("state_types", JSONArray())
            }
            welcome.put("device", report)
        }
        return welcome
    }

    /**
     * SPEC 4.5: B + max_input_state_bytes - 2 <= max_frame_bytes, where B
     * is the prospective complete welcome response body with the longest
     * legal request ID and input_state {}. Also enforces the table floors.
     */
    private fun checkLimits() {
        val l = config.limits
        fun floor(name: String, min: Long) {
            val v = l.optLong(name, -1)
            require(v >= min) { "limits.$name must be at least $min" }
        }
        require(l.optLong("max_frame_bytes") == WireLimits.MAX_BODY_OCTETS.toLong()) {
            "limits.max_frame_bytes must equal ${WireLimits.MAX_BODY_OCTETS}"
        }
        floor("max_queued_events", 256); floor("max_queued_bytes", 8_388_608)
        floor("max_event_bytes", 262_144); floor("max_surfaces", 16)
        floor("max_surface_ids", 1024); floor("max_field_bytes", 65_536)
        floor("max_input_state_bytes", 262_144); floor("max_capture_fields", 64)
        require(l.getLong("max_event_bytes") <= l.getLong("max_frame_bytes") - 256) {
            "max_event_bytes exceeds max_frame_bytes - 256"
        }
        require(l.getLong("max_field_bytes") <= l.getLong("max_frame_bytes") - 2048) {
            "max_field_bytes exceeds max_frame_bytes - 2048"
        }
        require(l.getLong("max_surfaces") <= l.getLong("max_surface_ids")) {
            "max_surfaces exceeds max_surface_ids"
        }
        // SPEC 4.5: conditional limits are REQUIRED the moment the capability
        // or node type they bound is advertised — a host that advertises
        // editor.sync/rich_text/table without them ships a non-conforming
        // welcome (amendment #84; LD-15/LD-22).
        if ("editor.sync" in config.supportedCapabilities) {
            floor("max_editor_bytes", 65_536)
            require(l.getLong("max_editor_bytes") <= l.getLong("max_frame_bytes") - 4096) {
                "max_editor_bytes exceeds max_frame_bytes - 4096"
            }
        }
        for (target in config.surfaceProfiles.keySet()) {
            val types = nodeTypesFromProfiles(config.surfaceProfiles, target) ?: continue
            if ("rich_text" in types) floor("max_rich_spans", 1)
            if ("table" in types) floor("max_table_cells", 1)
        }
        // SPEC 4.5: the actual server strings must fit the 128-octet bound
        // the reservation reserves for them (SPEC 10.2).
        require(config.serverName.toByteArray(Charsets.UTF_8).size <= 128 &&
            config.serverVersion.toByteArray(Charsets.UTF_8).size <= 128) {
            "server name/version exceed 128 UTF-8 octets"
        }
        // SPEC 4.5: `surfaces` at its worst case — max_surface_ids distinct
        // maximum-length IDs, maximum revision, and the longer `present`
        // encoding (`false`). Counting it empty was the reservation's hole.
        val worstSurfaces = JSONObject()
        for (i in 0 until l.getLong("max_surface_ids"))
            // A distinct 128-octet key: a byte-size probe, not a real ID.
            worstSurfaces.put(i.toString().padStart(WireLimits.MAX_IDENTIFIER_OCTETS, 'a'),
                JSONObject().put("revision", 9_007_199_254_740_991L).put("present", false))
        val prospective = JSONObject()
            .put("jsonrpc", "2.0")
            .put("id", "a".repeat(WireLimits.MAX_REQUEST_ID_OCTETS))
            .put("result", JSONObject()
                .put("server_proof", "0".repeat(64))
                .put("protocol", 2)
                // SPEC 4.5: fixed members at their maximum legal encoded size.
                .put("server", JSONObject()
                    .put("name", "a".repeat(128)).put("version", "a".repeat(128)))
                .put("granted", JSONArray(config.supportedCapabilities.toList()))
                .put("surface_profiles", config.surfaceProfiles)
                .put("surfaces", worstSurfaces)
                .put("queued_events", l.getLong("max_queued_events"))
                .put("input_state", JSONObject())
                .put("limits", l))
        // SPEC 4.5/20.1 (amendment #40): the welcome device report is a variable
        // member emitted when capabilities or triggers is granted. Reserve
        // max_device_report_bytes for it (rather than embed it in `prospective`,
        // which cannot see a per-session grant), and require the configured
        // report to fit that bound so it never depends on truncation.
        val emitsReport = "capabilities" in config.supportedCapabilities ||
            "triggers" in config.supportedCapabilities
        val deviceBudget = if (emitsReport) l.optLong("max_device_report_bytes", 0) else 0
        if (deviceBudget > 0)
            require(config.deviceReport.toString().toByteArray(Charsets.UTF_8).size <= deviceBudget) {
                "device report exceeds max_device_report_bytes"
            }
        val b = prospective.toString().toByteArray(Charsets.UTF_8).size.toLong()
        require(b + deviceBudget + l.getLong("max_input_state_bytes") - 2 <=
            l.getLong("max_frame_bytes")) {
            "welcome reservation violated: B=$b, device=$deviceBudget"
        }
    }

    // -------------------------------------------------------------- output

    private fun respondResult(id: Any, result: JSONObject) =
        emit(JSONObject().put("jsonrpc", "2.0").put("id", id).put("result", result))

    private fun respondError(id: Any, code: Int, message: String, kind: String,
                             data: JSONObject = JSONObject()) {
        // SPEC 7.2 (amendment #34): ids are strings or safe integers.
        if (isValidRequestId(id))
            emit(JSONObject().put("jsonrpc", "2.0").put("id", id)
                .put("error", JSONObject().put("code", code).put("message", message)
                    .put("data", data.put("kind", kind))))
    }

    /** SPEC 6.2/8: a framing-level error carries `id: null`, which
     * `respondError` deliberately rejects (a request id is never null). */
    private fun emitFramingError(code: Int, message: String, kind: String) {
        if (state == SessionState.CLOSED) return
        emit(JSONObject().put("jsonrpc", "2.0").put("id", JSONObject.NULL)
            .put("error", JSONObject().put("code", code).put("message", message)
                .put("data", JSONObject().put("kind", kind))))
    }

    private fun emit(msg: JSONObject) = sink(encodeFrame(msg.toString()))

    private fun Any?.utf8Len(): Int =
        (this as String).toByteArray(Charsets.UTF_8).size
}
