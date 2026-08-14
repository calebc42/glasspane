// SPDX-License-Identifier: GPL-3.0-or-later
// The Companion's session engine: SPEC 9 handshake validation, SPEC 10
// lifecycle with fail-closed pre-auth behavior, welcome construction with
// the SPEC 4.5 reservation check, and SPEC 7.3 dispatch rules.
// Transport-agnostic: feed() consumes bytes, sink receives outbound bytes.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Static configuration for one Companion endpoint. */
data class CompanionConfig(
    val serverName: String,
    val serverVersion: String,
    /** pairing_id (32 hex) -> decoded 16-octet token. */
    val pairings: Map<String, ByteArray>,
    /** Capabilities this Companion supports (SPEC 22.1 names). */
    val supportedCapabilities: Set<String>,
    /** surface_profiles welcome member, exactly as advertised (SPEC 10.2). */
    val surfaceProfiles: JsonObject,
    /** The welcome limits object (SPEC 4.5). */
    val limits: JsonObject,
    /** SPEC 20.1: the device report, echoed in the welcome when `capabilities`
     * or `triggers` is granted. Its `caps` are the exact capability.invoke
     * catalog this Companion supports; empty means neither module is offered. */
    val deviceReport: JsonObject = JsonObject(emptyMap()),
    /** SPEC 20.2: the platform executor for capability.invoke. REQUIRED when
     * `device.caps` is non-empty; a null handler fails every invoke as 1003. */
    val capabilityHandler: CapabilityHandler? = null,
    /** SPEC 21.4: whether the user approved substituting sensitive-source
     * (sms/call/calendar) trigger data into an on_fire sink. Default deny. */
    val sensitiveSubstitutionApproved: Boolean = false,
    /** Nonce source, injectable for tests. */
    val nonceSource: () -> String = EbpAuth::generateNonce,
    /**
     * Operation-only authentication seam. The default preserves the original
     * in-memory pairing map API; Android hosts can instead resolve
     * non-exportable AndroidKeyStore-backed HMAC handles.
     */
    val proofProvider: CompanionProofProvider? = null,
)

class CompanionEngine(
    private val config: CompanionConfig,
    /** Shared across connections: surface state outlives a session (13.5). */
    val surfaces: SurfaceStore = SurfaceStore(
        config.limits.reqLong("max_surfaces"), config.limits.reqLong("max_surface_ids"),
        config.limits.longOr("max_capture_fields", 64),
        config.limits.longOr("max_chart_points", Long.MAX_VALUE),
        config.limits.longOr("max_canvas_ops", Long.MAX_VALUE),
        config.limits.longOr("max_rich_spans", Long.MAX_VALUE),
        config.limits.longOr("max_table_cells", Long.MAX_VALUE),
        nodeTypesFromProfiles(config.surfaceProfiles, "app"),
        nodeTypesFromProfiles(config.surfaceProfiles, "notification"),
        builtinsFromProfiles(config.surfaceProfiles, "app"),
        builtinsFromProfiles(config.surfaceProfiles, "notification")),
    /** Shared across connections AND restarts: the SPEC 15 durable queue. */
    val queue: DurableQueue = DurableQueue(
        MemoryQueueStore(),
        config.limits.reqLong("max_queued_events"),
        config.limits.reqLong("max_queued_bytes")),
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
        triggers, queue, maxEventBytes = config.limits.reqLong("max_event_bytes"),
        triggerCaps = jsonStringSet(config.deviceReport, "trigger_caps"),
        capabilityHandler = config.capabilityHandler),
    private val sink: (ByteArray) -> Unit,
) : LiveSession {
    private val proofProvider: CompanionProofProvider =
        config.proofProvider ?: InMemoryCompanionProofProvider(config.pairings)

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

    /** Re-entry marker for feed()'s post-fault drain: no new bytes. */
    private val EMPTY_CHUNK = ByteArray(0)
    private var pendingPairingId: String? = null

    /** SPEC 9.1: the authenticated pairing identity, for host state that must
     * be scoped to it (§17.2's image cache, §21.5's queued data). Null until
     * `auth.response` verifies. */
    val pairingIdentity: String? get() = pendingPairingId
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
        // A recoverable body fault unwinds the decoder's drain loop, so any
        // frames PIPELINED BEHIND the bad one stay buffered. Re-entering with
        // no new bytes drains them: the decoder already advanced past the bad
        // frame before throwing, so the stream is still synchronized. Without
        // this, a request behind a malformed frame is never dispatched and
        // never answered until more bytes happen to arrive — the unbounded
        // stall amendment #91 forbids. Terminates: every pass either drains
        // to completion or consumes at least one more whole frame.
        var input: ByteArray? = bytes
        while (input != null) {
            val chunk = input
            input = null
            try {
                decoder.feed(chunk) { msg ->
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
                // SPEC 6.2: a complete body that is invalid UTF-8 or JSON gets
                // a Parse Error with id:null; the stream stayed synchronized,
                // so the connection MAY (and here does) continue.
                emitFramingError(-32700, "Parse error", "parse-error")
                if (state != SessionState.CLOSED) input = EMPTY_CHUNK
            } catch (e: InvalidRequest) {
                // SPEC 6.2/4.1: a non-object top level, batch array, or
                // duplicate member names get one Invalid Request with
                // id:null; continue.
                emitFramingError(-32600, "Invalid Request", "invalid-request")
                if (state != SessionState.CLOSED) input = EMPTY_CHUNK
            }
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
            val err = buildJsonObject {
                put("code", -32603)
                put("message", "Connection closed")
                put("data", buildJsonObject { put("kind", "connection-closed") })
            }
            callbacks.forEach { cb -> runCatching { cb(null, err) } }
        }
        // SPEC 18.1: on transport loss every outstanding dialog is
        // dismissed locally; its request dies with the connection.
        // LD-18: callouts are best-effort — a throwing host listener must
        // not abort the rest of teardown (serve()'s finally has no retry).
        if (dialogs.isNotEmpty()) {
            val ids = dialogs.keys.toList()
            dialogs.clear()
            dialogEditors.clear() // sessions die with the connection anyway
            dialogDefaults.clear()
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
    }

    /** The queue_seq this engine's connection put in flight, if any. */
    private var myInFlightSeq: Long? = null

    // ------------------------------------------------------------ dispatch

    private fun dispatch(msg: JsonObject) {
        when (classifyMessage(msg)) {
            MessageClass.REQUEST ->
                // SPEC 4.1/7.3: the raw params reach handleRequest so a
                // non-object (a positional array) is rejected, not coerced.
                // classifyMessage guarantees id and a string method exist.
                handleRequest(msg.getValue("id"), methodOf(msg)!!, msg["params"])
            MessageClass.NOTIFICATION ->
                handleNotification(methodOf(msg)!!, msg["params"])
            MessageClass.RESPONSE -> {
                // SPEC 7.2: Companion-issued ids are integers; requestIdKey's
                // isString guard keeps a response with the STRING "1" from
                // concluding the pending integer id 1 (EnvelopeIdTest).
                val callback = requestIdKey(msg["id"])?.let(pending::remove)
                callback?.invoke(msg["result"] as? JsonObject,
                    msg["error"] as? JsonObject)
            }
            null ->
                // SPEC 7.3: structurally invalid; answer only when an id exists.
                if ("id" in msg && "method" in msg)
                    respondError(msg.getValue("id"), -32600, "Invalid Request", "invalid-request")
        }
    }

    // ------------------------------------------ outbound requests (SPEC 7)

    private var nextOutboundId = 0L
    private val pending = HashMap<Long, (JsonObject?, JsonObject?) -> Unit>()

    // SPEC 22.3 (LD-13 bound half): outstanding-request count is a MUST-bound
    // resource — `pending` grew without limit against a peer that stops
    // answering. Emacs's kbd_buffer is the calibration: a fixed ring that
    // holds off its source at half full and resumes at a quarter, because a
    // single cap thrashes at the boundary (accept one, refuse one, accept
    // one). Once HOLD is reached, new requests fail locally until the peer's
    // answers drain the map below RESUME.
    private var pendingHeld = false

    private companion object {
        const val PENDING_HOLD = 512
        const val PENDING_RESUME = 128
    }

    /** Send a Companion-originated request; integer ids per SPEC 7.2. A
     * request refused by the outstanding-request bound fails locally with a
     * synthetic 1401 — the caller's callback always runs exactly once.
     *
     * [bounded] = false exempts a caller that carries its OWN bound. Only the
     * durable-queue pump does: SPEC 15.3 lets exactly one delivery be in
     * flight at a time (`queue.hasInFlight()`), so it can never be the
     * resource this ceiling protects — while refusing it would be actively
     * wrong, because `onPumpResult` reads any error as a PEER response and
     * would pause the pump and report `blocked_by: "overloaded"` for an error
     * the peer never sent, stalling durable delivery on our own load. */
    @Synchronized
    fun sendRequest(method: String, params: JsonObject,
                    bounded: Boolean = true,
                    callback: (JsonObject?, JsonObject?) -> Unit) {
        if (pendingHeld && pending.size <= PENDING_RESUME) pendingHeld = false
        if (bounded && (pendingHeld || pending.size >= PENDING_HOLD)) {
            pendingHeld = true
            callback(null, buildJsonObject {
                put("code", 1401)
                put("message", "Outstanding requests exhausted")
                put("data", buildJsonObject { put("kind", "overloaded") })
            })
            return
        }
        val id = ++nextOutboundId
        pending[id] = callback
        emit(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", id)
            put("method", method)
            put("params", params)
        })
    }

    // ---------------------------------------- actions and input (SPEC 14)

    /** SPEC 14.2: clipboard.copy / share.send / companion.settings.open are
     * host-platform duties — (builtin name, descriptor) for the app layer. */
    var hostBuiltinListener: ((String, JsonObject) -> Unit)? = null

    /**
     * SPEC 14.2: execute a Companion-local builtin from a surface hook. The
     * descriptor's shape was validated at accept time (unknown builtin or bad
     * members rejected the document); an invalid CONTEXT here — a view.switch
     * on a single-view surface, an unknown view, a dialog completion outside
     * a dialog — is a safe no-op, never a crash.
     */
    /** SPEC 18.1/14.4: dispatch a remote user action from INSIDE a dialog.
     * The event carries `dialog_id` INSTEAD of surface + revision_seen —
     * 14.4's contexts are exclusive — and its capture snapshot is the
     * DIALOG's local field layer, which the caller (the renderer owns it;
     * dialog statefuls never enter the store, SPEC 18.1) passes in.
     * READY-only by construction: 18.1 makes every dialog descriptor
     * drop-mode, so there is no durable arm.  A concluded dialog dispatches
     * nothing — the tap raced the conclusion and the occurrence is void.
     *
     * Found by the JA-5 device gate: the generic `dispatchAction` resolves
     * a revision for the `dialog:` pseudo-surface, gets null, and silently
     * returns — every remote descriptor inside a dialog (the token+confirm
     * Archive, the date-pick relay) was dead while all the dialog BUILTINS
     * worked, because those route through DialogContext instead.  The
     * JA-6 lesson verbatim: a wire member is not implemented because the
     * validator accepts it. */
    fun dispatchDialogAction(dialogId: String, descriptor: JsonObject,
                             hookValue: JsonElement?, fields: JsonObject?,
                             callback: ((String?, JsonObject?) -> Unit)? = null) {
        if ("builtin" in descriptor) return  // builtins are the renderer's
        if (state != SessionState.READY) return
        if (!dialogs.containsKey(dialogId)) return
        // R4: the authored args share directly — immutable trees need no
        // deep copy — and the injection is a single-builder merge (R3).
        val args = buildJsonObject {
            descriptor.objOrNull("args")?.forEach { (k, v) -> put(k, v) }
            // SPEC 14.3: the hook's produced value is injected, never
            // authored. The null guard survives AS a guard: a null hookValue
            // means NO value member, exactly as before the swap.
            if (hookValue != null) put("value", hookValue)
        }
        val params = buildJsonObject {
            put("event_id", EbpAuth.generateNonce())
            put("action", descriptor.reqString("action"))
            put("dialog_id", dialogId)
            put("occurred_at_ms", queue.effectiveNow())
            if (args.isNotEmpty()) put("args", args)
            val capture = descriptor.arrOrNull("capture_fields")
            if (capture != null && capture.isNotEmpty())
                put("fields", buildJsonObject {
                    for (el in capture) {
                        // Accept-time validation makes every entry a string.
                        val fieldId = el.asStringOrNull() ?: continue
                        // An uncaptured field IS a JSON null (SPEC 14.1), not
                        // an absent member — JsonNull here is deliberate.
                        put(fieldId, fields?.get(fieldId) ?: JsonNull)
                    }
                })
        }
        // SPEC 14.4/15.4: the COMPLETE params against max_event_bytes.
        if (wireSerialize(params).utf8Len() >
            config.limits.reqLong("max_event_bytes")) return
        sendRequest("event.action", params) { result, error ->
            callback?.invoke(result?.stringOr("status"), error)
        }
    }

    private fun executeBuiltin(surface: String, descriptor: JsonObject) {
        when (descriptor.stringOr("builtin")) {
            "view.switch" -> {
                val view = descriptor.stringOrNull("view") ?: return
                if (!surfaces.switchView(surface, view)) return
                surfaceListener?.invoke(surface)
                // SPEC 14.2: while READY, report view.switched with the view
                // in args — when_offline drop, so never queued.
                if (state != SessionState.READY) return
                val revision = surfaces.revisionOf(surface) ?: return
                val params = buildJsonObject {
                    put("event_id", EbpAuth.generateNonce())
                    put("action", "view.switched")
                    put("surface", surface)
                    put("revision_seen", revision)
                    put("occurred_at_ms", queue.effectiveNow())
                    put("args", buildJsonObject { put("view", view) })
                }
                if (wireSerialize(params).utf8Len() <=
                    config.limits.reqLong("max_event_bytes"))
                    sendRequest("event.action", params) { _, _ -> }
            }
            "trigger.fire" -> {
                // SPEC 14.2/21.5: fire the named manual trigger through the
                // normal pipeline; requires the triggers capability.
                if ("triggers" !in granted) return
                val id = descriptor.stringOrNull("id") ?: return
                pendingPairingId?.let { firing.fireManual(it, id, "tap") }
            }
            "clipboard.copy", "share.send", "companion.settings.open" ->
                hostBuiltinListener?.invoke(descriptor.stringOr("builtin"), descriptor)
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
    fun dispatchAction(surface: String, descriptor: JsonObject, hookValue: JsonElement?,
                       injected: JsonObject? = null,
                       extraFields: JsonObject? = null,
                       /** The id of the node whose hook fired, when the host
                        * knows it. Required for a synchronized `editor`'s
                        * hooks so the §19 read-only rule can be enforced. */
                       sourceId: String? = null,
                       callback: ((String?, JsonObject?) -> Unit)? = null) {
        // SPEC 19: "A synchronized editor MUST become read-only whenever the
        // connection is not READY. It MUST NOT create an offline input draft,
        // delta, save, completion, or editor command." Its every other path
        // is READY-gated in this class; a hook owned by the editor node —
        // `on_save`, `on_enter` — reaches the DURABLE queue through the
        // generic dispatch, so it is gated here rather than in the renderer.
        if (sourceId != null && state != SessionState.READY &&
            surfaceEditors[surface]?.containsKey(sourceId) == true) return
        if ("builtin" in descriptor) return executeBuiltin(surface, descriptor)
        val revision = surfaces.revisionOf(surface) ?: return
        // R3/R4: authored args + hook value + multi-member injections merge
        // in ONE builder; the immutable authored tree shares, no deep copy.
        val args = buildJsonObject {
            descriptor.objOrNull("args")?.forEach { (k, v) -> put(k, v) }
            // SPEC 14.3: the hook's produced value is injected, never
            // authored. The null guard survives AS a guard — null means no
            // member, not a JsonNull write.
            if (hookValue != null) put("value", hookValue)
            // SPEC 14.3: multi-member hooks (on_reorder from/to/order,
            // on_add_row/on_add_col index, swipe on_trigger direction) inject
            // their produced members; authored conflicts were rejected at
            // accept time.
            injected?.forEach { (k, v) -> put(k, v) }
        }
        // SPEC 14.1: capture_fields is one occurrence-time snapshot,
        // stored inside the durable record for queued policies (15.1).
        val fields = buildJsonObject {
            descriptor.arrOrNull("capture_fields")?.let { capture ->
                for (el in capture) {
                    // Accept-time validation makes every entry a string.
                    val fieldId = el.asStringOrNull() ?: continue
                    // An uncaptured field IS a JSON null (SPEC 14.1) — the
                    // JsonNull write is deliberate, not a collapsed guard.
                    put(fieldId, surfaces.currentValue(surface, fieldId) ?: JsonNull)
                }
            }
            // SPEC 14.6: a value the renderer supplies at occurrence time — a
            // text_input password's on_submit, whose secret has no retained
            // draft for currentValue() to read (it never emits state.changed).
            extraFields?.forEach { (k, v) -> put(k, v) }
        }
        val policy = descriptor.stringOr("when_offline", OFFLINE_DEFAULT)
        val params = buildJsonObject {
            put("event_id", EbpAuth.generateNonce())
            put("action", descriptor.reqString("action"))
            put("surface", surface)
            put("revision_seen", revision)
            put("occurred_at_ms", queue.effectiveNow())
            if (args.isNotEmpty()) put("args", args)
            if (fields.isNotEmpty()) put("fields", fields)
            // SPEC 15.1: a durable policy persists a queued_at_ms; it is part
            // of the stored and replayed params, so add it BEFORE the size
            // check.
            if (policy == "queue" || policy == "wake")
                put("queued_at_ms", queue.effectiveNow())
        }
        // SPEC 14.4/15.4: verify the COMPLETE params against max_event_bytes
        // before persistence or transmission; an oversized occurrence is a
        // local diagnostic, never a frame or a record.
        if (wireSerialize(params).utf8Len() >
            config.limits.reqLong("max_event_bytes")) {
            callback?.invoke(null, buildJsonObject {
                put("code", 1201)
                put("message", "Event exceeds max_event_bytes")
                put("data", buildJsonObject {
                    put("kind", "content-invalid")
                    put("reason", "event-too-large")
                })
            })
            return
        }
        when (policy) {
            "queue", "wake" -> {
                // SPEC 22.3/15.1: durable admission precedes every wake or
                // delivery attempt, including when READY right now.
                // ttl_s reads by VALUE (integralLongOrNull): SpecValidator
                // bounds it to an integral number and PreSwapNumberTest pins
                // the binary64 spelling 60.0 as accepted-and-functional —
                // org.json's getLong truncated it; a strict integer-spelling
                // read would refuse a legal older peer. Same shape as
                // dispatchContextless (C3).
                when (queue.admit(params, policy,
                        descriptor.stringOr("dedupe").takeIf { it.isNotEmpty() },
                        integralLongOrNull(descriptor["ttl_s"])
                            ?: throw NoSuchElementException("ttl_s"))) {
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
                        callback?.invoke(null, buildJsonObject {
                            put("code", 1601)
                            put("message", "Queue full")
                            put("data", buildJsonObject { put("kind", "queue-full") })
                        })
                    AdmitResult.StorageFailed ->
                        // SPEC 15.1: MUST NOT claim the interaction queued.
                        callback?.invoke(null, buildJsonObject {
                            put("code", -32603)
                            put("message", "Storage failed")
                            put("data", buildJsonObject { put("kind", "internal-error") })
                        })
                }
            }
            else -> { // drop: live delivery only (SPEC 15.1)
                if (state != SessionState.READY) return
                sendRequest("event.action", params) { result, error ->
                    callback?.invoke(result?.stringOr("status"), error)
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
    fun publishState(surface: String, id: String, value: JsonElement?,
                     caret: Int? = null) {
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
        // R6: Kotlin null means JSON null at this seam — the elvis survives.
        emit(notification("state.changed", buildJsonObject {
            put("surface", surface)
            put("revision_seen", revision)
            put("id", id)
            put("value", value ?: JsonNull)
            // SPEC 14.6.1: transient presentation context, present only for
            // a node authored with report_caret.
            caret?.let { put("caret", it) }
        }))
    }

    private fun handleRequest(id: JsonElement, method: String, rawParams: JsonElement?) {
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
        // positional array, no coercion (an explicit JSON null is not an
        // object either). A legal handshake method with malformed params is
        // -32602 here too (SPEC 10.1).
        val params = when (rawParams) {
            null -> JsonObject(emptyMap())
            is JsonObject -> rawParams
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
            "snackbar.show" -> handleSnackbarShow(id, params)
            "reminders.set" -> handleRemindersSet(id, params)
            "triggers.set" -> handleTriggersSet(id, params)
            "capability.invoke" -> handleCapabilityInvoke(id, params)
            "edit.apply" -> handleEditApply(id, params)
            "edit.resync" -> handleEditResync(id, params)
            "session.ready" -> {
                // SPEC 10.3: the {} response serializes ahead of every
                // READY-only frame; emitting before transitioning does that.
                respondResult(id, JsonObject(emptyMap()))
                state = sessionStep(state, SessionEvent.READY_CONFIRMED) ?: state
                // SPEC 10.3: flush every divergent value changed during
                // SYNCING as ordered state.changed BEFORE releasing events.
                for ((surface, nodeId) in syncingDirty.toList()) {
                    if (!surfaces.hasDraft(surface, nodeId)) continue
                    val revision = surfaces.revisionOf(surface) ?: continue
                    emit(notification("state.changed", buildJsonObject {
                        put("surface", surface)
                        put("revision_seen", revision)
                        put("id", nodeId)
                        // R6: a null draft is JSON null — the elvis survives.
                        put("value", surfaces.draft(surface, nodeId) ?: JsonNull)
                    }))
                }
                syncingDirty.clear()
                // SPEC 19: every synchronized editor on a present surface
                // gets a session now — including ones this connection never
                // saw an update for (a reconnect over cached snapshots).
                openPresentEditors()
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
    private var replayId: JsonElement? = null
    private var replayDelivered = 0
    private var replayRejected = 0
    private var blockedBy: JsonElement = JsonNull

    private fun handleQueueReplay(id: JsonElement) {
        // SPEC 15.3: only one replay may be active.
        if (replayId != null)
            return respondError(id, 1600, "A replay is already active", "queue-busy")
        replayId = id
        replayDelivered = 0
        replayRejected = 0
        blockedBy = JsonNull
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
                val seq = d.record.reqLong("queue_seq")
                myInFlightSeq = seq
                // SPEC 15.3: the stored record replays with its stored event_id.
                // SPEC 15.3: single-flight by construction, and a local
                // refusal here would be misread as a peer error — exempt.
                sendRequest("event.action", d.record.reqObj("event"),
                    bounded = false) { result, error ->
                    onPumpResult(seq, result, error)
                }
            }
            Delivery.PendingLocal -> return                  // wait for on_fire (Step 4)
            Delivery.Empty, Delivery.BarrierHeld -> concludeReplay()
        }
    }

    private fun onPumpResult(seq: Long, result: JsonObject?, error: JsonObject?) {
        queue.clearInFlight(seq)
        myInFlightSeq = null
        when {
            error != null -> {
                // SPEC 15.3: any well-formed error retains the head and
                // pauses the pump; later admissions never bypass it.
                pumpPaused = true
                // SPEC 15.3: only a valid string kind rides blocked_by.
                blockedBy = JsonPrimitive(error.objOrNull("data")
                    ?.stringOrNull("kind")?.takeIf { it.isNotEmpty() }
                    ?: "json-rpc-error")
                concludeReplay()
            }
            result?.stringOr("status") in listOf("accepted", "duplicate") -> {
                replayDelivered++
                queue.deleteRecord(seq)
                pumpAdvance()
            }
            result?.stringOr("status") in listOf("stale", "rejected") -> {
                replayRejected++
                queue.deleteRecord(seq)
                pumpAdvance()
            }
            else -> {
                // SPEC 15.3: unknown status is a protocol violation —
                // retain the event, one safe log.error, close.
                emit(notification("log.error", buildJsonObject {
                    put("code", -32603)
                    put("message", "event.action result with unknown status")
                    put("data", buildJsonObject { put("kind", "internal-error") })
                }))
                close("event.action result with unknown status")
            }
        }
    }

    private fun concludeReplay() {
        val id = replayId ?: return
        replayId = null
        respondResult(id, buildJsonObject {
            put("delivered", replayDelivered)
            put("rejected", replayRejected)
            put("expired", queue.takeExpiredCount())
            put("remaining", queue.count())
            put("blocked_by", blockedBy)
        })
    }

    // ------------------------------------------------------ surfaces (13)

    private fun surfaceRevision(value: JsonElement?): Long? =
        // Integer SPELLING only, recovering the old `is Int || is Long`
        // predicate: revision rejects both 1.0 and "1" with -32602
        // (PreSwapNumberTest pins the taxonomy).
        (value as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }
            ?.content?.toLongOrNull()
            ?.takeIf { it in 0..9_007_199_254_740_991L } // SPEC 4.2

    private fun handleSurfaceUpdate(id: JsonElement, params: JsonObject) {
        val surface = params.stringOrNull("surface")
        val revision = surfaceRevision(params["revision"])
        val spec = params.objOrNull("spec")
        if (surface == null || revision == null || spec == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        if (!surfaces.isValidSurfaceId(surface))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("reason", "surface-id") })
        // SPEC 13.1: the namespace's capability must have been granted.
        val requiredCap = when (surfaces.namespace(surface)) {
            "notification" -> "surfaces.notification"
            "widget" -> "surfaces.widget"
            else -> null
        }
        if (requiredCap != null && requiredCap !in granted)
            return respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("reason", "namespace-not-granted") })
        // SPEC 19: count distinct synchronized-editor identities the whole
        // mutation would yield — every other surface's editors plus this
        // spec's — and reject before applying if it exceeds the limit.
        val newEditors = if ("editor.sync" in granted) scanSyncedEditors(spec)
            else emptyMap()
        val othersEditorCount = editorIdentityCount(excludingSurface = surface)
        if (othersEditorCount + newEditors.size >
            config.limits.longOr("max_editor_sessions", 8))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("reason", "editor-session-limit") })
        // SPEC 19.4 (amendment #103): the seed carries max_editor_bytes as a
        // RECEIVER duty. Without this the sender-side rule has no enforcement
        // point at the seed: an over-limit document is accepted, edit.open
        // carries it, and every later edit — local and inbound — is refused
        // by the size rules, leaving the editor silently and permanently
        // read-only with no diagnostic in either direction.
        val maxEditorBytes = config.limits.longOr("max_editor_bytes", Long.MAX_VALUE)
        for ((eid, node) in newEditors)
            if (EditorSession.jcsUtf8Bytes(node.stringOr("value")) > maxEditorBytes)
                return respondError(id, 1201, "Invalid content", "content-invalid",
                    buildJsonObject {
                        put("path", "spec.$eid.value")
                        put("reason", "editor-too-large")
                    })
        // SPEC 19 (amendment #104): a synchronized editor session is keyed by
        // (document, presentation identity), so only ONE surface may present
        // a given tuple. Silently accepting a second surface's claim
        // overwrote the first surface's session with no `edit.close`: Emacs
        // then got `editor-stale` for a session it was never told had died,
        // `edit.resync` could not recover it (§19.4 forbids creating a
        // session there), and removing EITHER surface closed the survivor.
        for ((identity, node) in newEditors) {
            val document = node.reqString("document")
            val owner = surfaceEditors.entries.firstOrNull { (s, map) ->
                s != surface && map[identity] == document
            }?.key
            if (owner != null)
                return respondError(id, 1201, "Invalid content", "content-invalid",
                    buildJsonObject {
                        put("path", "spec.$identity")
                        put("reason", "editor-duplicate")
                    })
        }
        try {
            val result = surfaces.update(
                surface, revision, spec,
                params.objOrNull("stale_spec"),
                params.stringOrNull("current_view"),
                params.arrOrNull("reset_input_ids"))
            respondResult(id, buildJsonObject {
                put("status", result.status)
                put("revision", result.revision)
                put("present", result.present)
            })
            if (result.status == "applied") {
                reconcileEditors(surface, newEditors)
                surfaceListener?.invoke(surface)
            }
        } catch (e: ContentInvalid) {
            respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("path", e.path); put("reason", e.reason) })
        }
    }

    /** SPEC 16/17: members whose value is an ARRAY of child nodes.
     *
     * The `node-array` half is DERIVED, for the same reason [NODE_SLOT_MEMBERS]
     * is: a member the contract adds and this set forgets is a silently dead
     * editor session. `items` cannot be derived — the contract types it
     * `varies-per-node`, because a `tabs.items` entry is a TabItem label object
     * and a `menu.items` entry is a menu item, neither of them a node. The
     * `t`-guard in the walk below is what keeps those out. */
    private val NODE_ARRAY_MEMBERS: Set<String> =
        FIELD_TYPES.filterValues { it == "node-array" }.keys + "items"

    /** SPEC 13.4/17: members whose value is a single child node — the
     * scaffold slots and the envelope/decoration slots.
     *
     * DERIVED from the generated `FIELD_TYPES`, never hand-listed. The hand
     * list this replaces had drifted five members behind the contract —
     * `sheet`, `rail`, `list`, `detail` and `extra` were all missing — and the
     * failure was SILENT and total: an `editor` with a `document` in any of
     * them was never seen by [scanSyncedEditors], so no session opened, no
     * `edit.complete` was ever issued, and `edit.delta` never flowed, while the
     * field still accepted typing locally. A REPL in a bottom sheet looked
     * alive and sent nothing. Deriving costs one filter and makes the drift
     * impossible: `VocabularyDriftTest` already pins `FIELD_TYPES` to
     * `ebp/contract.json`. */
    private val NODE_SLOT_MEMBERS: Set<String> =
        FIELD_TYPES.filterValues { it == "node" }.keys +
            // `empty` is a SPEC 22 widget-surface member, not a NODE member, so
            // the contract's node field types do not carry it. This walk covers
            // widget specs too, so it is unioned in by hand rather than lost.
            "empty"

    // Per-surface synchronized editors: surface -> (identity -> document),
    // where identity is the SPEC 16.1 presentation identity (key else id).
    private val surfaceEditors = HashMap<String, MutableMap<String, String>>()
    // SPEC 19: the same, for editors presented in an outstanding dialog. A
    // dialog's sessions live exactly as long as the dialog does.
    private val dialogEditors = HashMap<String, MutableMap<String, String>>()
    // T3/LD-3: the authored value of each stateful node in an outstanding
    // dialog — the layer under the user's dialog-local edits. Dialog state is
    // dialog-local (SPEC 18.1), so nothing else holds these.
    private val dialogDefaults = HashMap<String, JsonObject>()

    /** SPEC 14.1/18.1 (T3/LD-3): the authored values for an outstanding
     * dialog's stateful nodes, so `capture_fields` can resolve a field the
     * user never touched to its LOGICAL value instead of inventing one. */
    @Synchronized
    fun dialogDefaults(dialogId: String): JsonObject? = dialogDefaults[dialogId]

    /** SPEC 19/4.5: distinct synchronized-editor identities presented right
     * now, across accepted surface AND dialog documents. */
    private fun editorIdentityCount(excludingSurface: String? = null): Long =
        surfaceEditors.entries.filter { it.key != excludingSurface }
            .sumOf { it.value.size }.toLong() +
            dialogEditors.values.sumOf { it.size }.toLong()

    /** SPEC 18.1/19: an outstanding dialog's editor sessions close with it. */
    private fun closeDialogEditors(dialogId: String) {
        dialogEditors.remove(dialogId)?.forEach { (identity, document) ->
            closeEditor(document, identity)
        }
    }

    /**
     * SPEC 17.4/19: an `editor` node with a `document` is synchronized. The
     * key is its SPEC 16.1 presentation identity — `key` when present, else
     * `id` — because §19 preserves a session across surface replacements by
     * that identity, and closes when it changes.
     *
     * Only NODE POSITIONS count. The old walk recursed into every JSON object
     * in the spec, so an `{"t":"editor", …}` buried in an action's free-form
     * `args` (which §14.1 leaves opaque) opened a real session for a node that
     * does not exist — and, because the map was keyed last-write-wins over
     * unspecified member order, could shadow a real editor's identity. It also
     * ignored the target profile, so a build that does not advertise `editor`
     * still opened sessions for nodes §17.1 degrades and never renders.
     */
    private fun scanSyncedEditors(spec: JsonObject,
                                  target: String = "app"): Map<String, JsonObject> {
        val out = LinkedHashMap<String, JsonObject>()
        val advertised = nodeTypesFromProfiles(config.surfaceProfiles, target)
        if (advertised != null && "editor" !in advertised) return out
        fun visit(node: JsonObject) {
            if (node.stringOrNull("t") == "editor" &&
                node.stringOrNull("document") != null) {
                val identity = node.stringOrNull("key") ?: node.stringOrNull("id")
                if (identity != null) out[identity] = node
            }
            // Descend only where §16/§17 place child NODES: the children
            // array, the §13.4 scaffold/envelope slots, and multi-view roots.
            for ((key, child) in node) {
                when (child) {
                    is JsonArray ->
                        if (key in NODE_ARRAY_MEMBERS)
                            for (item in child)
                                (item as? JsonObject)
                                    ?.takeIf { it.stringOrNull("t") != null }
                                    ?.let(::visit)
                    is JsonObject ->
                        if (key in NODE_SLOT_MEMBERS && child.stringOrNull("t") != null)
                            visit(child)
                    else -> Unit
                }
            }
        }
        val views = spec.objOrNull("views")
        if (views != null) for (name in views.keys)
            (views[name] as? JsonObject)
                ?.takeIf { it.stringOrNull("t") != null }?.let(::visit)
        else if (spec.stringOrNull("t") != null) visit(spec)
        return out
    }

    /** SPEC 19: open sessions for newly present synchronized editors, and
     * close those removed or whose document or presentation identity changed.
     * The same identity and document preserve the session. During `SYNCING`
     * the mapping is only RECORDED — §19 makes opening wait for `READY`,
     * where [openPresentEditors] opens everything recorded. */
    private fun reconcileEditors(surface: String, newEditors: Map<String, JsonObject>) {
        val prev = surfaceEditors[surface] ?: emptyMap()
        val next = LinkedHashMap<String, String>()
        for ((identity, node) in newEditors) {
            val document = node.reqString("document")
            next[identity] = document
            val existed = prev[identity]
            if (existed == document) continue // identity preserved
            if (existed != null) closeEditor(existed, identity) // document changed
            if (state == SessionState.READY)
                openEditor(document, identity, node.stringOr("value"))
        }
        // Editors that vanished from this surface close.
        for ((identity, document) in prev)
            if (identity !in next) closeEditor(document, identity)
        if (next.isEmpty()) surfaceEditors.remove(surface)
        else surfaceEditors[surface] = next
    }

    /**
     * SPEC 19: on entering `READY`, every synchronized editor on a PRESENT
     * surface gets a session. Rebuilt from the SurfaceStore rather than from
     * connection-local state, which is what makes a reconnection correct: the
     * store outlives the connection, so a fresh session that receives no
     * `surface.update` (legal — the cached snapshot is unchanged and still
     * rendered per §13.5) previously opened NOTHING, leaving every rendered
     * editor permanently read-only with no diagnostic. This also replaces the
     * old `pendingEditors` list, which was appended to but never pruned, so a
     * SYNCING-accepted editor whose surface was then removed still opened on
     * READY and left a session no close path could reach.
     */
    private fun openPresentEditors() {
        surfaceEditors.clear()
        for (surface in surfaces.presentSurfaces()) {
            if (surfaces.namespace(surface) != "app") continue
            val spec = surfaces.spec(surface) ?: continue
            val found = runCatching { scanSyncedEditors(spec) }.getOrNull() ?: continue
            if (found.isEmpty()) continue
            val map = LinkedHashMap<String, String>()
            for ((identity, node) in found) {
                val document = node.reqString("document")
                // One session per (document, identity) — a second surface
                // claiming the same tuple is refused at acceptance, so this
                // can only be a stale record.
                if (editors.containsKey(document to identity)) continue
                map[identity] = document
                openEditor(document, identity, node.stringOr("value"))
            }
            if (map.isNotEmpty()) surfaceEditors[surface] = map
        }
    }

    private fun closeSurfaceEditors(surface: String) {
        surfaceEditors.remove(surface)?.forEach { (editorId, document) ->
            closeEditor(document, editorId)
        }
    }

    private fun handleSurfaceRemove(id: JsonElement, params: JsonObject) {
        val surface = params.stringOrNull("surface")
        val revision = surfaceRevision(params["revision"])
        if (surface == null || revision == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 13.1: a structurally invalid ID must not become a tombstone —
        // it would enter the welcome `surfaces` map and consume a
        // max_surface_ids slot. surface.update rejects it identically.
        if (!surfaces.isValidSurfaceId(surface))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("reason", "surface-id") })
        // SPEC 13.1: removal is legal for any reported surface, no cap gate.
        try {
            val result = surfaces.remove(surface, revision)
            respondResult(id, buildJsonObject {
                put("status", result.status)
                put("revision", result.revision)
                put("present", result.present)
            })
            if (result.status == "applied") {
                closeSurfaceEditors(surface)
                surfaceListener?.invoke(surface)
            }
        } catch (e: ContentInvalid) {
            respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("path", e.path); put("reason", e.reason) })
        }
    }

    private fun handleNotification(method: String, rawParams: JsonElement?) {
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
        val params = rawParams as? JsonObject ?: return
        // SPEC 7.5/18.1: rpc.cancel concludes an outstanding dialog with 1301.
        when (method) {
            "rpc.cancel" -> {
                // JsonElement data-class equality keeps id matching TYPED:
                // 5 concludes 5, never "5" (EnvelopeIdTest pins the
                // distinction). NOT jsonValueEquals — that layer compares
                // numbers by value, right for SPEC 4.3, wrong for ids.
                val cancelId = params["id"]
                val entry = dialogs.entries.find { it.value == cancelId } ?: return
                dialogs.remove(entry.key)
                closeDialogEditors(entry.key)
                dialogDefaults.remove(entry.key)
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
    private val pieMenus = LinkedHashMap<String, JsonArray>()

    /** Present hook: (menu_id, {categories, center_label?}) to show;
     * (menu_id, null) to dismiss. */
    var pieMenuListener: ((String, JsonObject?) -> Unit)? = null

    private fun handlePieMenuShow(params: JsonObject) {
        if ("presentation.pie-menu" !in granted) return
        val menuId = params.stringOrNull("menu_id")
            ?: return reportPieMenuInvalid("menu_id")
        // SPEC 4.4/18.3: menu_id MUST be a valid identifier, not any string.
        if (!identifier.matches(menuId)) return reportPieMenuInvalid("menu_id")
        val categories = params.arrOrNull("categories")
            ?: return reportPieMenuInvalid("categories")
        // SPEC 18.3: an invalid menu is dropped, not partially shown — and
        // (amendment #132) the drop is REPORTED. A silent discard left an
        // authoring error with no diagnostic anywhere on either side, so a
        // Tier-1 author's first invalid menu produced nothing at all.
        if (!validPieCategories(categories)) return reportPieMenuInvalid("categories")
        // SPEC 18.3: a new id over the limit is dropped with a diagnostic;
        // replacing an existing id stays legal at the limit.
        if (!pieMenus.containsKey(menuId) &&
            pieMenus.size >= config.limits.longOr("max_pie_menus", 1)) {
            // SHOULD send a rate-limited log.error (rate limiting is W9).
            emit(notification("log.error", buildJsonObject {
                put("code", 1201)
                put("message", "Too many pie menus")
                put("data", buildJsonObject {
                    put("kind", "content-invalid")
                    put("reason", "pie-menu-limit")
                })
            }))
            return
        }
        pieMenus[menuId] = categories
        val present = buildJsonObject {
            put("categories", categories)
            params.stringOrNull("center_label")?.let { put("center_label", it) }
        }
        pieMenuListener?.invoke(menuId, present)
    }

    /** SPEC 18.3 (amendment #132): report a discarded-as-invalid pie menu.
     * `path` names the offending member. Returns Unit so the call sites can
     * `return` it directly from the drop point. */
    private fun reportPieMenuInvalid(path: String) {
        emit(notification("log.error", buildJsonObject {
            put("code", 1201)
            put("message", "Invalid pie menu")
            put("data", buildJsonObject {
                put("kind", "content-invalid")
                put("reason", "pie-menu-invalid")
                put("path", path)
            })
        }))
    }

    private fun handlePieMenuDismiss(params: JsonObject) {
        if ("presentation.pie-menu" !in granted) return
        val menuId = params.stringOrNull("menu_id") ?: return
        // SPEC 18.3: dismissing an unknown id is a no-op.
        if (pieMenus.remove(menuId) != null) pieMenuListener?.invoke(menuId, null)
    }

    private fun validPieCategories(categories: JsonArray): Boolean {
        if (categories.size !in 1..10) return false
        for (el in categories) {
            val cat = el as? JsonObject ?: return false
            if (cat.stringOrNull("label") == null) return false
            val hasItems = "items" in cat
            val hasOnTap = "on_tap" in cat
            if (hasItems == hasOnTap) return false // exactly one
            if (hasOnTap) {
                if (!validPieDescriptor(cat.objOrNull("on_tap"))) return false
            } else {
                val items = cat.arrOrNull("items") ?: return false
                if (items.size < 1) return false
                for (itemEl in items) {
                    val item = itemEl as? JsonObject ?: return false
                    if (item.stringOrNull("label") == null) return false
                    if (!validPieDescriptor(item.objOrNull("on_tap"))) return false
                }
            }
        }
        return true
    }

    /** SPEC 18.3: a pie-menu descriptor is a remote action, drop-only, with
     * no authored conflict on the injected members. */
    private fun validPieDescriptor(d: JsonObject?): Boolean {
        if (d == null || d.stringOrNull("action") == null) return false
        if (d.stringOr("when_offline", OFFLINE_DEFAULT) != "drop") return false
        val args = d.objOrNull("args") ?: return true
        return !("menu_id" in args || "category_index" in args ||
            "item_index" in args)
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
        val category = categories.getOrNull(categoryIndex) as? JsonObject ?: return
        val descriptor = if (itemIndex != null)
            (category.arrOrNull("items")?.getOrNull(itemIndex) as? JsonObject)
                ?.objOrNull("on_tap")
        else category.objOrNull("on_tap")
        descriptor ?: return
        // R3/R4: the injected members merge into a single builder over the
        // shared (immutable) authored args — no deep copy, no dropped result.
        val args = buildJsonObject {
            descriptor.objOrNull("args")?.forEach { (k, v) -> put(k, v) }
            put("menu_id", menuId)
            put("category_index", categoryIndex)
            if (itemIndex != null) put("item_index", itemIndex)
        }
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
    private fun dispatchDescriptorContextless(descriptor: JsonObject, args: JsonObject,
                                              callback: ((String?, JsonObject?) -> Unit)? = null) =
        dispatchContextless(queue, config.limits.reqLong("max_event_bytes"),
            descriptor, args, this, callback)

    // ------- LiveSession: the connection-bound half of a context-less event.
    // Held as a newest-wins slot by cold senders (reminder taps, the firing
    // service); invoked never while the caller holds another module's monitor.

    /** SPEC 15.1: a drop event.action delivers live only while READY. */
    @Synchronized
    override fun deliverLiveDrop(params: JsonObject,
                                 callback: ((String?, JsonObject?) -> Unit)?) {
        if (state != SessionState.READY) return
        sendRequest("event.action", params) { result, error ->
            callback?.invoke(result?.stringOr("status"), error)
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
    var reminderListener: ((String, JsonArray, JsonArray) -> Unit)? = null

    // SPEC 4.4: an identifier is 1..128 ASCII chars (the leading char plus up
    // to 127 more) — the length bound applies to reminder owner/id, cap names,
    // and pie menu_id alike.
    private val identifier = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}")
    private val reminderMembers = setOf("id", "title", "body", "at_ms", "on_tap")

    private fun handleRemindersSet(id: JsonElement, params: JsonObject) {
        if ("reminders.owner" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        val owner = params.stringOrNull("owner")
        val arr = params.arrOrNull("reminders")
        if (owner.isNullOrEmpty() || !identifier.matches(owner) || arr == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        val parsed = ArrayList<JsonObject>(arr.size)
        val seen = HashSet<String>()
        for (i in 0 until arr.size) {
            val r = arr[i] as? JsonObject
                ?: return respondError(id, 1201, "Invalid content", "content-invalid",
                    buildJsonObject {
                        put("path", "reminders[$i]")
                        put("reason", "not-an-object")
                    })
            try {
                validateReminder(r, seen)
            } catch (e: ContentInvalid) {
                return respondError(id, 1201, "Invalid content", "content-invalid",
                    buildJsonObject {
                        put("path", "reminders[$i].${e.path}")
                        put("reason", e.reason)
                    })
            }
            parsed.add(r)
        }
        // SPEC 18.6: replacement plus OTHER owners must fit max_reminders.
        val others = reminders.totalCount() - reminders.ownerCount(owner)
        if (others + parsed.size > config.limits.longOr("max_reminders", 256))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("reason", "reminder-limit") })
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
        respondResult(id, buildJsonObject { put("count", count) })
        reminderListener?.invoke(owner, JsonArray(parsed), JsonArray(prior))
    }

    private fun validateReminder(r: JsonObject, seen: MutableSet<String>) {
        for (k in r.keys) if (k !in reminderMembers)
            throw ContentInvalid(k, "unknown reminder member")
        val rid = r.stringOrNull("id")
        if (rid == null || !identifier.matches(rid))
            throw ContentInvalid("id", "must be an identifier")
        if (!seen.add(rid)) throw ContentInvalid("id", "duplicate reminder id")
        val title = r.stringOrNull("title")
        if (title.isNullOrEmpty()) throw ContentInvalid("title", "non-empty string required")
        if ("body" in r && r.stringOrNull("body") == null)
            throw ContentInvalid("body", "must be a string")
        // SPEC 4.3: an epoch timestamp is a non-negative INTEGER — a JSON
        // number with a fractional part (e.g. 1.5) is rejected, not accepted.
        // integralLongOrNull checks integrality by VALUE, so the binary64
        // spelling 5000.0 from an older peer stays accepted-and-functional
        // (PreSwapNumberTest pins it) while 1.5 and the string "5" are not.
        val at = integralLongOrNull(r["at_ms"])
        if (at == null || at < 0 || at > 9_007_199_254_740_991L)
            throw ContentInvalid("at_ms", "must be a non-negative integer timestamp")
        r.objOrNull("on_tap")?.let { onTap ->
            if (onTap.stringOrNull("action") == null)
                throw ContentInvalid("on_tap", "must be a remote ActionDescriptor")
            val policy = onTap.stringOr("when_offline", OFFLINE_DEFAULT)
            if ((policy == "queue" || policy == "wake") && "ttl_s" !in onTap)
                throw ContentInvalid("on_tap", "$policy requires ttl_s")
            // SPEC 14.5/18.6: capture_fields is surface/dialog-scoped — a
            // reminder tap has no input state to capture from (#133).
            if ("capture_fields" in onTap)
                throw ContentInvalid("on_tap", "capture_fields is surface/dialog-scoped")
            // SPEC 18.6: the injected members must not be authored.
            onTap.objOrNull("args")?.let { a ->
                if ("owner" in a || "reminder_id" in a)
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
                            callback: ((String?, JsonObject?) -> Unit)? = null) {
        routeReminderTap(reminders, queue, config.limits.reqLong("max_event_bytes"),
            owner, reminderId, this, callback)
    }

    // -------------------------------------------- device triggers (SPEC 21)

    /** Arm hook: (identity, its complete new registration list) after an
     * accepted replace. The host arms/cancels platform event sources. */
    var triggerListener: ((String, List<JsonObject>) -> Unit)? = null

    /** SPEC 21.3/21.7: current sample for a state type (delegates to the shared
     * firing service, which owns the runtime). */
    var triggerStateProvider: (String) -> JsonObject?
        get() = firing.stateProvider
        set(v) { firing.stateProvider = v }

    /** SPEC 21.4: post a substituted on_fire notification (delegates to the
     * shared firing service). */
    var triggerNotifyListener: ((JsonObject) -> Unit)?
        get() = firing.notifyListener
        set(v) { firing.notifyListener = v }

    /** SPEC 21.5: a level-type observation. Firing lives in the device-lifetime
     * service and needs no live session (SPEC 21.1/21.2); the observe entry
     * points remain for a session-driven source and delegate to it. */
    @Synchronized
    fun observeTriggerSample(type: String, sample: JsonObject) =
        firing.observeSample(type, sample)

    /** SPEC 21.5: an external occurrence (package/sms/boot/time/timezone/manual). */
    @Synchronized
    fun observeTriggerEvent(type: String, data: JsonObject) =
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
    private fun handleTriggersSet(id: JsonElement, params: JsonObject) {
        if ("triggers" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        val identity = pendingPairingId
            ?: return respondError(id, 1200, "Not authenticated", "not-authenticated")
        val caps = TriggerCaps(
            triggerTypes = jsonStringSet(config.deviceReport, "trigger_types"),
            stateTypes = jsonStringSet(config.deviceReport, "state_types"),
            trackableStateTypes = jsonStringSet(config.deviceReport, "trackable_state_types"),
            triggerCaps = jsonStringSet(config.deviceReport, "trigger_caps"),
            maxResponses = config.limits.longOr("max_trigger_responses", 16).toInt(),
            sensitiveSubstitutionApproved = config.sensitiveSubstitutionApproved)
        val entries = try {
            TriggerValidator.validateSet(params, caps)
        } catch (e: ContentInvalid) {
            return respondError(id, 1101, "Triggers rejected", "triggers-rejected",
                buildJsonObject { put("path", e.path); put("reason", e.reason) })
        }
        // SPEC 21.1: the replace-set size MUST fit max_triggers; reject, never
        // truncate. Validated before any registration changes.
        if (entries.size > config.limits.longOr("max_triggers", 64))
            return respondError(id, 1101, "Triggers rejected", "triggers-rejected",
                buildJsonObject { put("reason", "trigger-limit") })
        // SPEC 21.5: a newly added or changed one-shot time.at_ms MUST be later
        // than the wall clock at acceptance. An unchanged entry (same id,
        // canonically equal to the prior) stays valid past its time, even once
        // completed. Reject the whole set — never apply it partially.
        val nowMs = queue.effectiveNow()
        for (e in entries) {
            val p = e.objOrNull("params") ?: continue
            if (e.reqString("type") != "time" || "at_ms" !in p) continue
            val prior = firing.store.registration(identity, e.reqString("id"))?.entry
            val changed = prior == null || !TriggerStore.canonicalEquals(prior, e)
            // The validator re-emitted at_ms as a normalized Long (its
            // intField), so the strict integer-spelled reader is total here.
            if (changed && p.reqLong("at_ms") <= nowMs)
                return respondError(id, 1101, "Triggers rejected", "triggers-rejected",
                    buildJsonObject {
                        put("path", "triggers[${e.reqString("id")}].params.at_ms")
                        put("reason", "at_ms-not-future")
                    })
        }
        // SPEC 21.1: the accepted set commits durably (via the firing service)
        // before it is claimed, then the new/changed registrations are silently
        // baselined; a storage failure leaves the prior set in force.
        val count = try {
            firing.replaceSet(identity, entries)
        } catch (e: Exception) {
            return respondError(id, -32603, "Storage failed", "internal-error")
        }
        respondResult(id, buildJsonObject { put("count", count) })
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
    private fun handleCapabilityInvoke(id: JsonElement, params: JsonObject) {
        if ("capabilities" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        for (k in params.keys) if (k != "cap" && k != "args")
            return respondError(id, -32602, "Invalid params", "invalid-params")
        val cap = params.stringOrNull("cap")
        if (cap == null || !identifier.matches(cap))
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // Absent and explicit-null args both mean {}, as before the swap.
        val args = when (val a = params["args"]) {
            null, JsonNull -> JsonObject(emptyMap())
            is JsonObject -> a
            else -> return respondError(id, -32602, "Invalid params", "invalid-params")
        }
        // SPEC 20.2: cap MUST appear in device.caps, else 1001. A non-string
        // entry never equals a string cap name, before and after the swap.
        val caps = config.deviceReport.arrOrNull("caps") ?: JsonArray(emptyList())
        if (caps.none { it.asStringOrNull() == cap })
            return respondError(id, 1001, "Unsupported capability", "cap-unsupported")
        // SPEC 20.3: validate the closed Args before any side effect.
        try {
            CapabilityCatalog.validateArgs(cap, args)
        } catch (e: ContentInvalid) {
            return respondError(id, -32602, "Invalid params", "invalid-params",
                buildJsonObject { put("path", e.path); put("reason", e.reason) })
        }
        // SPEC 20.2: the host re-checks authorization at invocation and runs it.
        val handler = config.capabilityHandler
            ?: return respondError(id, 1003, "Capability failed", "cap-failed",
                buildJsonObject { put("reason", "no-handler") })
        when (val out = handler.invoke(cap, args)) {
            is CapabilityOutcome.Ok -> respondResult(id, out.result)
            is CapabilityOutcome.Fail -> respondError(id, out.code, "Capability failed",
                if (out.code == 1002) "cap-permission" else "cap-failed",
                buildJsonObject { put("reason", out.reason) })
        }
    }

    // ------------------------------------------------- editor sync (SPEC 19)

    // Keyed by (document, editor_id); the Companion is the shadow's owner.
    private val editors = LinkedHashMap<Pair<String, String>, EditorSession>()

    /** Re-render hook: the session's shadow changed from an inbound apply or
     * a resync (the host editor must reflect it). */
    var editorListener: ((EditorSession) -> Unit)? = null
    /** Close hook: (document, editorId) after the session is gone. The
     * counterpart to [editorListener] — a display that publishes per-editor
     * state on every apply needs the one event that ENDS it. */
    var editorClosedListener: ((String, String) -> Unit)? = null
    /** Annotation hook: (kind, document, editorId, payload) after a session/seq
     * match. The DOCUMENT rides along because §19.5 payloads carry only
     * `editor_id` while a display keys its editor state by (document,
     * editorId) — the same key `editors` and every host-side map use. The
     * resolved session knows it; without it a consumer would have to invent a
     * second keying scheme for annotations alone. */
    var annotationListener: ((String, String, String, JsonObject) -> Unit)? = null

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
        emit(notification("edit.open", buildJsonObject {
            put("document", document)
            put("editor_id", editorId)
            put("session", s.sessionId)
            put("seq", 0)
            put("text", seed)
            put("cursor", s.cursor)
            put("sel_start", s.selStart)
            put("sel_end", s.selEnd)
        }))
        // The seed is the new authoritative text for the display too: a
        // reopened (document, editor_id) — same node, later session — would
        // otherwise leave a view still holding the PREVIOUS session's text,
        // with nothing to reconcile it against (the amendment-#100 base gate
        // would then refuse every keystroke). Publishing here reseeds it.
        editorListener?.invoke(s)
        return s
    }

    /** SPEC 19.3: a local edit applies to the shadow immediately, advances
     * seq, and mirrors as an edit.delta. Read-only unless OPEN and READY. */
    @Synchronized
    fun localEditorEdit(document: String, editorId: String,
                        start: ScalarPos, del: Int, text: String,
                        base: String? = null,
                        accept: Boolean = false): Boolean {
        val s = editors[document to editorId] ?: return false
        if (s.state != EditorSession.State.OPEN || state != SessionState.READY)
            return false
        // SPEC 19.3 (amendment #100): a local edit derived from a document
        // state that is no longer the shadow MUST NOT be applied. On a
        // Companion whose editing surface is a separate view (every Compose /
        // UIKit / web renderer), an inbound edit.apply moves the shadow while
        // the view still holds the old text; the splice the view then derives
        // is expressed in the OLD document's coordinates, and the length
        // equation cannot catch it — `len` is computed from the shadow, so it
        // is self-satisfying and only the bounds check stands between a stale
        // keystroke and silent corruption. BASE is the view's pre-edit text;
        // a mismatch refuses the edit, and the host re-presents the shadow.
        if (base != null && base != s.shadow) return false
        // SPEC 19.4 (amendment #84): a local edit that would carry the
        // document past max_editor_bytes is refused as if read-only.
        if (s.spliceJcsBytes(start, del, text) >
            config.limits.longOr("max_editor_bytes", Long.MAX_VALUE)) return false
        val len = s.scalarLength() - del + text.codePointCount(0, text.length)
        if (!s.splice(start, del, text, len)) return false
        s.seq += 1
        // Amendments #170/#171: the accept splice consumes the offer; any
        // other local splice either extends it (del 0 at the region end)
        // or kills it — the tracker IS rule (a).
        if (accept) s.offer.clear() else s.offer.onLocalSplice(start.v, del, text)
        emit(notification("edit.delta", buildJsonObject {
            put("document", document)
            put("editor_id", editorId)
            put("session", s.sessionId)
            put("seq", s.seq)
            put("start", start.v)
            put("del", del)
            put("text", text)
            put("len", len)
            // Amendment #170: presence IS the assertion — the tap path is
            // the ONLY caller passing the flag (THE FUNNEL RULE: a future
            // accept gesture calls selectCompletion, never re-implements
            // the splice-and-stamp), so a typed delta can never carry it.
            if (accept) put("accept", true)
        }))
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
        emit(notification("edit.caret", buildJsonObject {
            put("document", document)
            put("editor_id", editorId)
            put("session", s.sessionId)
            put("seq", s.seq)
            put("cursor", s.cursor)
            // The guard survives: no selection means NO sel members, not a
            // pair of JSON nulls.
            if (lo != null) {
                put("sel_start", s.selStart)
                put("sel_end", s.selEnd)
            }
        }))
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
        val params = buildJsonObject {
            put("event_id", EbpAuth.generateNonce())
            put("action", "edit.command")
            put("surface", surface)
            put("revision_seen", revision)
            put("occurred_at_ms", queue.effectiveNow())
            put("args", buildJsonObject {
                put("command", command)
                put("document", document)
                put("editor_id", editorId)
                put("session", s.sessionId)
                put("seq", s.seq)
                put("cursor", c.v)
                put("sel_start", lo!!.v)
                put("sel_end", hi!!.v)
            })
        }
        if (wireSerialize(params).utf8Len() >
            config.limits.reqLong("max_event_bytes")) return false
        sendRequest("event.action", params) { _, _ -> }
        return true
    }

    /** SPEC 19: close a session (removal, identity/document change). */
    @Synchronized
    fun closeEditor(document: String, editorId: String) {
        val s = editors.remove(document to editorId) ?: return
        // The display keys its per-editor state — mirror text, completion
        // offers, annotations — by this same (document, editorId) tuple, and a
        // close is the ONLY event that ends it. Without this hook every one of
        // those maps outlives its session until transport loss clears the lot:
        // stale text seeding a reopened editor, and unbounded growth across a
        // long connection that opens many editors.
        editorClosedListener?.invoke(document, editorId)
        if (s.state == EditorSession.State.CLOSED) return
        s.state = EditorSession.State.CLOSED
        if (state == SessionState.READY)
            emit(notification("edit.close", buildJsonObject {
                put("document", document)
                put("editor_id", editorId)
                put("session", s.sessionId)
            }))
    }

    private fun editorStale(id: JsonElement) = respondError(id, 1201, "Invalid content",
        "content-invalid", buildJsonObject { put("reason", "editor-stale") })

    private fun handleEditApply(id: JsonElement, params: JsonObject) {
        if ("editor.sync" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        val doc = params.stringOrNull("document")
        val eid = params.stringOrNull("editor_id")
        val session = params.stringOrNull("session")
        if (doc == null || eid == null || session == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        val s = editors[doc to eid]
        // SPEC 19.2: an unknown or CLOSED tuple, or a stale session id, is
        // editor-stale (a later request, not a silently-ignored notification).
        if (s == null || s.state == EditorSession.State.CLOSED || s.sessionId != session)
            return editorStale(id)
        // Position/seq members read by VALUE (integralLongOrNull), the old
        // `as? Number → toLong` shape minus its silent truncation: 5.0 still
        // reads as 5, but a genuinely fractional 5.5 — which org.json
        // truncated to 5 — is now the -32602 the SPEC 4.2 no-coercion rule
        // always required. Strings and booleans were never accepted.
        val hasSplice = listOf("start", "del", "text", "len").count { it in params }
        if (hasSplice == 0) {
            val cursorL = integralLongOrNull(params["cursor"])
                ?: return respondError(id, -32602, "Invalid params", "invalid-params")
            // SPEC 19.4 (amendment #98): the move-only form carries `seq`
            // (REQUIRED for edit.apply in contract.json) and "succeeds only
            // at the current sequence" — an unchecked move let a caret
            // computed against a superseded document be reported `applied`,
            // so Emacs believed a position the document no longer has.
            val moveSeq = integralLongOrNull(params["seq"])
                ?: return respondError(id, -32602, "Invalid params", "invalid-params")
            if (("sel_start" in params) != ("sel_end" in params))
                return respondError(id, -32602, "Invalid params", "invalid-params")
            if (moveSeq != s.seq)
                return respondResult(id, buildJsonObject { put("status", "stale"); put("seq", s.seq) })
            val selStartL = integralLongOrNull(params["sel_start"])
            val selEndL = integralLongOrNull(params["sel_end"])
            // Out-of-domain positions fail the 19.1 range gate (see the
            // text-form path below) rather than truncating to 32 bits.
            if (listOfNotNull(cursorL, selStartL, selEndL)
                    .any { it < 0 || it > Int.MAX_VALUE })
                return respondResult(id, buildJsonObject { put("status", "stale"); put("seq", s.seq) })
            val cursor = cursorL.toInt()
            val selStart = selStartL?.toInt()
            val selEnd = selEndL?.toInt()
            if (!s.setCaret(ScalarPos(cursor),
                    selStart?.let(::ScalarPos), selEnd?.let(::ScalarPos)))
                return respondResult(id, buildJsonObject { put("status", "stale"); put("seq", s.seq) })
            editorListener?.invoke(s)
            return respondResult(id, buildJsonObject { put("status", "applied"); put("seq", s.seq) })
        }
        val seq = integralLongOrNull(params["seq"])
        val startL = integralLongOrNull(params["start"])
        val delL = integralLongOrNull(params["del"])
        val text = params.stringOrNull("text")
        val lenL = integralLongOrNull(params["len"])
        if (seq == null || startL == null || delL == null || text == null || lenL == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 19.4 (LD-5): `cursor` is REQUIRED on every text-changing
        // apply — the peer dictates the post-splice caret — and selection
        // members are paired-or-omitted. Structural absence is -32602, like
        // any other missing required member.
        val cursorL = integralLongOrNull(params["cursor"])
            ?: return respondError(id, -32602, "Invalid params", "invalid-params")
        val selStartL = integralLongOrNull(params["sel_start"])
        val selEndL = integralLongOrNull(params["sel_end"])
        if (("sel_start" in params) != ("sel_end" in params))
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 4.2/16.1/19.1: a legal EBP integer (up to 2^53-1) that cannot
        // address this document is OUT OF DOMAIN — "a receiver MUST NOT
        // coerce, clamp, or silently drop an out-of-domain member". Reading
        // these with Number.toInt() truncated to the low 32 bits, so
        // start 4294967296 became 0 and a splice Emacs asked for OUTSIDE the
        // text was applied at the head of the document and reported
        // `applied`. Out-of-domain fails the 19.1 range gate, whose 19.4
        // result contract is a typed stale.
        val positions = listOfNotNull(startL, delL, lenL, cursorL, selStartL, selEndL)
        if (positions.any { it < 0 || it > Int.MAX_VALUE })
            return respondResult(id, buildJsonObject { put("status", "stale"); put("seq", s.seq) })
        val start = startL.toInt()
        val del = delL.toInt()
        val len = lenL.toInt()
        val cursor = cursorL.toInt()
        val selStart = selStartL?.toInt()
        val selEnd = selEndL?.toInt()
        // SPEC 19.4: apply only at seq+1 with a valid splice; otherwise a
        // typed stale result leaves this (winning) session OPEN.
        if (seq != s.seq + 1)
            return respondResult(id, buildJsonObject { put("status", "stale"); put("seq", s.seq) })
        // SPEC 19.4 (amendment #84): an inbound apply that would carry the
        // document past max_editor_bytes is 1201 editor-too-large, text
        // unchanged. Only a splice that would otherwise be valid can be
        // too large — a range- or length-invalid one is stale, as before.
        val grown = s.spliceJcsBytes(ScalarPos(start), del, text)
        if (grown >= 0 &&
            len == s.scalarLength() - del + text.codePointCount(0, text.length) &&
            grown > config.limits.longOr("max_editor_bytes", Long.MAX_VALUE))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("reason", "editor-too-large") })
        // SPEC 19.4 (LD-5): the splice AND the peer's post-state caret are
        // validated together, atomically — a failed gate changes nothing.
        // The old path spliced, then silently discarded a failed setCaret
        // and answered "applied" over a half-updated session.
        if (!s.spliceRemote(ScalarPos(start), del, text, len, ScalarPos(cursor),
                selStart?.let(::ScalarPos), selEnd?.let(::ScalarPos)))
            return respondResult(id, buildJsonObject { put("status", "stale"); put("seq", s.seq) })
        s.seq = seq
        // Amendment #171: a remote apply is a non-qualifying advance -
        // the offer's coordinates describe a document state now left.
        s.offer.onForeignAdvance()
        editorListener?.invoke(s)
        respondResult(id, buildJsonObject { put("status", "applied"); put("seq", s.seq) })
    }

    private fun handleEditResync(id: JsonElement, params: JsonObject) {
        if ("editor.sync" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        val doc = params.stringOrNull("document")
        val eid = params.stringOrNull("editor_id")
        val session = params.stringOrNull("session")
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
        // Amendment #171: a resync is a foreign advance the tracker cannot
        // see for itself - the session the offer's reply named is dead, and
        // seq restarting at 0 is indistinguishable from an offer armed at
        // seq 0, so without this an accept could be emitted into a session
        // the offer never belonged to. The listener retires the display's
        // dropdown, exactly as the edit.apply path does.
        s.offer.onForeignAdvance()
        editorListener?.invoke(s)
        respondResult(id, buildJsonObject {
            put("document", doc)
            put("editor_id", eid)
            put("session", s.sessionId)
            put("seq", 0)
            put("text", s.shadow)
            put("cursor", s.cursor)
            put("sel_start", s.selStart)
            put("sel_end", s.selEnd)
        })
    }

    /** SPEC 19.3: ask Emacs to complete at the current cursor. The result's
     * {prefix, candidates} reach CALLBACK together with the (session, seq,
     * cursor) the request was ISSUED against — a UI offering candidates must
     * hand those back to [selectCompletion] so its staleness check is real.
     * Re-reading them at selection time would compare the engine's state
     * with itself and always pass, which is exactly the race (the caret
     * moved while the user read the list) the check exists to catch.
     * Candidate selection is a later local edit via [selectCompletion].
     * Non-durable, session-scoped. */
    @Synchronized
    fun requestCompletion(document: String, editorId: String,
                          callback: (String, JsonArray, String, Long, Int) -> Unit) {
        val s = editors[document to editorId] ?: return
        if (s.state != EditorSession.State.OPEN || state != SessionState.READY) return
        val atSession = s.sessionId
        val atSeq = s.seq
        val atCursor = s.cursor
        sendRequest("edit.complete", buildJsonObject {
            put("document", document)
            put("editor_id", editorId)
            put("session", atSession)
            put("seq", atSeq)
            put("cursor", atCursor)
        }) { result, error ->
            // SPEC 19.3: "The result and each candidate are closed objects.
            // `prefix` MUST be a string and `candidates` MUST be an array.
            // Each candidate MUST contain a non-empty string `label`."
            // optString() coerced instead: an ABSENT prefix became "", which
            // selectCompletion's substring check then trivially satisfied, so
            // a malformed result INSERTED at the cursor without replacing —
            // §19.2's "never a wrong edit". A non-conforming result is
            // discarded whole; a completion has no response to carry an error.
            if (error == null && result != null &&
                editors[document to editorId]?.sessionId == atSession) {
                val prefix = result.stringOrNull("prefix") ?: return@sendRequest
                val cands = result.arrOrNull("candidates") ?: return@sendRequest
                for (k in result.keys)
                    if (k != "prefix" && k != "candidates") return@sendRequest
                for (el in cands) {
                    val c = el as? JsonObject ?: return@sendRequest
                    if (c.stringOrNull("label").isNullOrEmpty()) return@sendRequest
                    if ("annotation" in c && c.stringOrNull("annotation") == null)
                        return@sendRequest
                    if ("insert" in c && c.stringOrNull("insert") == null) return@sendRequest
                    // Amendment #169: `kind` is a feature-gated optional string.
                    // Only its TYPE is checked here - an unrecognized VALUE is a
                    // presentation gap (no icon), never a reason to discard the
                    // reply; the render layer's explicit map decides decoration.
                    if ("kind" in c && c.stringOrNull("kind") == null) return@sendRequest
                    for (k in c.keys)
                        if (k != "label" && k != "annotation" && k != "insert" &&
                            k != "kind")
                            return@sendRequest
                }
                // Amendment #171: arm the survive-typing tracker - but only
                // when the session still sits at the issued TEXT state: seq
                // equality is the whole test, because every text mutation
                // advances seq while a caret move does not - the caret is
                // §19.3's best-effort context, never the comparand (a wiggle
                // during the request's flight must not suppress the offer;
                // selectCompletion still verifies the cursor at the tap).
                // The CALLBACK rides inside the gate: a reply the tracker
                // refused must never reach the display, or the rows shown
                // would be validated against an older candidate set.
                val live = editors[document to editorId]
                if (live != null && live.sessionId == atSession &&
                    live.seq == atSeq) {
                    live.offer.setOffer(prefix, atCursor, atSeq, cands.mapNotNull { el ->
                        (el as? JsonObject)?.let { c ->
                            val label = c.stringOrNull("label") ?: return@let null
                            // Default on ABSENCE only: the validator above
                            // admitted an explicit "" (SPEC: "MAY be empty"
                            // - a selection that DELETES the prefix), so
                            // null here means the member is absent.
                            OfferCandidate(
                                label,
                                c.stringOrNull("insert") ?: label,
                                c.stringOrNull("kind"))
                        }
                    })
                    callback(prefix, cands, atSession, atSeq, atCursor)
                }
            }
        }
    }

    /**
     * SPEC 19.3 (amendments #170/#171): apply a chosen candidate. The tap
     * is legal while the tracker survived - every advance since the reply
     * a qualifying extension - AND, at this very emission, the candidate
     * still satisfies the ACTIVE narrowing predicate over the EXTENDED
     * PREFIX: the re-proof that closes the stale-row tap race (display
     * narrowing is asynchronous; this point is not). The replacement spans
     * the extension region and its delta carries `accept: true` - THE
     * FUNNEL: every accept gesture, present and future, goes through here.
     */
    @Synchronized
    fun selectCompletion(document: String, editorId: String,
                         label: String, insert: String,
                         narrowing: CompletionNarrowing): Boolean {
        val s = editors[document to editorId] ?: return false
        if (s.state != EditorSession.State.OPEN || state != SessionState.READY) return false
        val o = s.offer
        if (!o.active) return false
        // Rule (a), settled by construction: the tracker qualified every
        // advance, so a live seq it did not count is a foreign advance.
        if (s.seq != o.expectedSeq || s.cursor != o.regionEnd()) {
            o.clear(); return false
        }
        // Membership: the tapped candidate must be of THAT reply.
        val cand = o.candidates.firstOrNull {
            it.label == label && it.insert == insert }
            ?: run { o.clear(); return false }
        // Amendment #171: the emission-time re-proof.
        if (!o.matches(narrowing, cand)) { o.clear(); return false }
        val ep = o.extendedPrefix()
        val epLen = ep.codePointCount(0, ep.length)
        val start = o.regionEnd() - epLen
        if (start < 0) { o.clear(); return false }
        // The extended prefix must still be the text before the cursor.
        val from = s.shadow.offsetByCodePoints(0, start)
        val to = s.shadow.offsetByCodePoints(0, o.regionEnd())
        if (s.shadow.substring(from, to) != ep) { o.clear(); return false }
        return localEditorEdit(document, editorId, ScalarPos(start), epLen,
            insert, accept = true)
    }

    /** SPEC 19.3 (amendment #172): documentation for the INDEX-th candidate
     * of a RETAINED edit.complete reply. SESSION and SEQ are the CALLER's
     * frozen pair — the (session, seq) of the reply the displayed offer was
     * built from — never live engine state: mid-#171-extension the live seq
     * has legitimately advanced past the reply's, and those requests are
     * exactly what the method exists for (the tracker has no session field
     * and its expectedSeq mutates per qualifying splice, so nothing here
     * could reconstruct the pair anyway).
     *
     * CALLBACK fires on EVERY reply conclusion, with the doc or null (an
     * error, a malformed result, a discarded reply) — conclusion is split
     * from publication, because requestCompletion's refuse-with-a-bare-
     * return precedent would leave a one-outstanding display slot marked
     * in-flight forever after a single 1201 or -32601 (a pre-R5 Emacs),
     * killing docs for that editor for the process's life. The Boolean
     * return says whether anything was SENT at all. A 1201 or -32601 is a
     * silent no-op for the display; the request still concludes, so
     * §22.2's transmitted-request duty is met without rpc.cancel.
     * Non-durable, session-scoped. */
    @Synchronized
    fun requestCandidateDoc(document: String, editorId: String,
                            session: String, seq: Long, index: Int,
                            callback: (String?) -> Unit): Boolean {
        val s = editors[document to editorId] ?: return false
        if (s.state != EditorSession.State.OPEN || state != SessionState.READY) return false
        sendRequest("edit.candidate.doc", buildJsonObject {
            put("document", document)
            put("editor_id", editorId)
            put("session", session)
            put("seq", seq)
            put("index", index)
        }) { result, error ->
            // `doc` MUST be a string — an explicit "" is a valid empty
            // doc (the MAY-be-empty arm); absent or mistyped discards.
            // Unknown result members are IGNORED, not grounds to
            // discard: SPEC 12 rule 1 makes ignore the receiver default
            // and 19.3 declares closed objects only for edit.complete's
            // result — candidate.doc's paragraph never does, so the
            // requestCompletion-style closed-key loop here was an
            // over-reject that would break additive 25-class growth
            // (R5 review, DECISIONS-wire-growth-model asymmetry).
            var doc: String? = null
            if (error == null && result != null) doc = result.stringOrNull("doc")
            callback(doc)
        }
        return true
    }

    /** Render-facing snapshot of the survive-typing offer (amendment
     * #171): the narrowing operand plus liveness, for display filtering.
     * Candidates ride the answer callback as before. */
    @Synchronized
    fun completionOfferView(document: String, editorId: String): CompletionOfferView? =
        editors[document to editorId]?.let {
            CompletionOfferView(it.offer.extendedPrefix(), it.offer.ext,
                it.offer.active)
        }

    /** T2/LD-5: run F over a live editor session under the engine monitor —
     * the host's one safe read path for shadow/caret state (the mirror it
     * publishes to the display, and the snap-back after a refused edit). */
    @Synchronized
    fun <T> withEditor(document: String, editorId: String,
                       f: (EditorSession) -> T): T? =
        editors[document to editorId]?.let(f)

    private fun handleAnnotation(method: String, params: JsonObject) {
        if ("editor.sync" !in granted) return
        val eid = params.stringOrNull("editor_id") ?: return
        val session = params.stringOrNull("session") ?: return
        val seq = integralLongOrNull(params["seq"]) ?: return
        val s = findEditor(session) ?: return
        // SPEC 19.5: discard an annotation whose session or seq does not
        // match the current state (latest-wins, never delays text sync).
        if (s.editorId != eid || s.seq != seq) return
        // SPEC 19.5/19.1: ranges MUST fit the synchronized text, and
        // `fontify.show` runs MUST additionally be sorted and non-
        // overlapping. Unvalidated, negative-length, out-of-range, unsorted
        // and overlapping ranges reached host rendering code, where an
        // off-by-one peer throws at layout instead of being refused here.
        // The whole batch is rejected — never partially applied — because a
        // prefix of a bad batch is not what the peer described.
        if (!annotationBatchValid(method, params, s.scalarLength())) {
            // SPEC 8/22.3: a notification has no id to answer, so the refusal
            // is a diagnostic rather than a silent drop.
            emit(notification("log.error", buildJsonObject {
                put("code", 1201)
                put("message", "Invalid annotation batch")
                put("data", buildJsonObject {
                    put("kind", "content-invalid")
                    put("path", method)
                    put("reason", "annotation-invalid")
                })
            }))
            return
        }
        annotationListener?.invoke(method, s.document, eid, params)
    }

    private val DIAGNOSTIC_SEVERITIES = setOf("error", "warning", "info", "hint")

    /** SPEC 19.5: the shape and range rules for one annotation batch. */
    private fun annotationBatchValid(method: String, params: JsonObject, len: Int): Boolean {
        when (method) {
            "eldoc.show" -> return params.stringOrNull("text") != null
            "diagnostics.show", "fontify.show" -> Unit
            else -> return false
        }
        val member = if (method == "fontify.show") "runs" else "diagnostics"
        val arr = params.arrOrNull(member) ?: return false
        var prevEnd = -1
        for (el in arr) {
            val e = el as? JsonObject ?: return false
            val start = integralLongOrNull(e["start"]) ?: return false
            val end = integralLongOrNull(e["end"]) ?: return false
            // Half-open, non-negative length, inside the synchronized text.
            if (start < 0 || end < start || end > len) return false
            if (method == "fontify.show") {
                if (e.stringOrNull("role") == null) return false
                // Sorted and non-overlapping, in one pass.
                if (start < prevEnd) return false
                prevEnd = end.toInt()
            } else {
                if (e.stringOrNull("severity") !in DIAGNOSTIC_SEVERITIES) return false
                if (e.stringOrNull("message") == null) return false
            }
        }
        return true
    }

    // ------------------------------------------------------- themes (18.4)

    /** The latest accepted theme (SPEC 18.4): each notification is a
     * complete replacement. `dark` is a Boolean, or null for follow-system
     * (amendment #36). `colors`/`syntax` are role maps, or null to clear. */
    var themeListener: ((dark: Boolean?, colors: JsonObject?, syntax: JsonObject?) -> Unit)? = null
    private var theme: JsonObject = JsonObject(emptyMap())

    private fun handleThemeSet(params: JsonObject) {
        if ("theme" !in granted) return
        // SPEC 18.4: a complete replacement of the previously pushed values.
        // `dark` absent => follow system; present => forced polarity. A
        // non-boolean reads as null — follow-system — as before the swap.
        val dark = params.boolOrNull("dark")
        // `colors`/`syntax`: an object replaces; JSON null (or any non-object)
        // clears the mirror — the `as? JsonObject` covers both arms the old
        // NULL-then-cast dance needed.
        val colors = params["colors"] as? JsonObject
        val syntax = params["syntax"] as? JsonObject
        // 18.4 presentation trio: dynamic (wallpaper-derived base scheme),
        // font_scale (0.4..2.0, one number for the whole surface),
        // layout_direction (ltr|rtl). Absent — or any invalid spelling —
        // follows the device/system, the same tri-state as `dark`.
        val dynamic = params.boolOrNull("dynamic")
        val fontScale: Double? = params["font_scale"]?.asDoubleOrNull()
            ?.takeIf { it in 0.4..2.0 }
        val direction: String? = params.stringOrNull("layout_direction")
            ?.takeIf { it == "ltr" || it == "rtl" }
        theme = buildJsonObject {
            put("dark", dark?.let(::JsonPrimitive) ?: JsonNull)
            put("colors", colors ?: JsonNull)
            put("syntax", syntax ?: JsonNull)
            put("dynamic", dynamic?.let(::JsonPrimitive) ?: JsonNull)
            put("font_scale", fontScale?.let(::JsonPrimitive) ?: JsonNull)
            put("layout_direction", direction?.let(::JsonPrimitive) ?: JsonNull)
        }
        themeListener?.invoke(dark, colors, syntax)
    }

    /** SPEC 18.4: the persisted theme, for rendering across reconnects. */
    fun currentTheme(): JsonObject = theme

    // ------------------------------------------------- window (20.1.1)

    /** SPEC 20.1.1: the last-reported geometry, mirrored in the welcome. */
    private var windowGeom: JsonObject? = null

    private fun sizeClassOf(dp: Int, mediumAt: Int, expandedAt: Int): String =
        when {
            dp >= expandedAt -> "expanded"
            dp >= mediumAt -> "medium"
            else -> "compact"
        }

    /** SPEC 20.1.1: report the window geometry. Stores always (the welcome
     * mirror), emits only on a post-auth session, and never re-sends an
     * unchanged geometry. */
    fun windowChanged(widthDp: Int, heightDp: Int) {
        val geom = buildJsonObject {
            put("width_dp", widthDp)
            put("height_dp", heightDp)
            put("width_class", sizeClassOf(widthDp, 600, 840))
            put("height_class", sizeClassOf(heightDp, 480, 900))
        }
        if (geom == windowGeom) return
        windowGeom = geom
        if (state == SessionState.READY || state == SessionState.SYNCING)
            emit(notification("window.changed", geom))
    }

    // ------------------------------------------------------- toasts (18.2)

    /** Present hook: (text, duration_s or null for the platform default).
     * Best-effort presentation — never an acknowledgement (SPEC 18.2). */
    var toastListener: ((String, Long?) -> Unit)? = null

    private fun handleToastShow(params: JsonObject) {
        // SPEC 22.1: presentation.toast must have been granted.
        if ("presentation.toast" !in granted) return
        // SPEC 18.2: text REQUIRED plain text; duration_s in 1..10 or absent.
        val text = params.stringOrNull("text") ?: return
        // Integer SPELLING only: a duration_s of 2.0 or "5" drops the whole
        // notification, never coerces (PreSwapNumberTest pins it).
        val duration = if ("duration_s" in params)
            params.wireIntOrNull("duration_s")?.takeIf { it in 1..10 } ?: return
        else null
        toastListener?.invoke(text, duration)
    }

    // ---------------------------------------------- snackbar raise (18.2.1)

    /** Present hook: (message, action_label, duration, respond) — call
     * respond with "action" or "dismissed" exactly once as the snackbar
     * leaves the screen; the pending request completes then. */
    var snackbarListener: ((String, String?, String?, (String) -> Unit) -> Unit)? = null

    private fun handleSnackbarShow(id: JsonElement, params: JsonObject) {
        // SPEC 22.1: presentation.snackbar must have been granted.
        if ("presentation.snackbar" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        val message = params.stringOrNull("message")
            ?: return respondError(id, -32602, "Invalid params", "invalid-params")
        val action = params.stringOrNull("action_label")
        val duration = params.stringOrNull("duration")
        val listener = snackbarListener
        if (listener == null) {
            // SPEC 18.2.1: no scaffold host on screen — toast, dismissed.
            toastListener?.invoke(message, null)
            return respondResult(id, buildJsonObject { put("result", "dismissed") })
        }
        listener(message, action, duration) { outcome ->
            respondResult(id, buildJsonObject { put("result", outcome) })
        }
    }

    // ------------------------------------------------------ dialogs (18.1)

    // dialog_id -> the outstanding dialog.show request id (deferred reply).
    // The id is held as the peer's original JsonElement and echoed verbatim:
    // a string id stays a string, an integer stays an integer (SPEC 7.2), and
    // rpc.cancel's lookup uses JsonElement data-class equality so 5 != "5".
    private val dialogs = LinkedHashMap<String, JsonElement>()

    /** Present hook: (dialog_id, spec) to show; (dialog_id, null) to
     * dismiss. What the dialog contains is the application's; the request
     * correlation is the endpoint's. */
    var dialogListener: ((String, JsonObject?) -> Unit)? = null
    /** SPEC 18.1: a submit whose prospective response would exceed
     * max_frame_bytes. The dialog stays outstanding; the host MUST show a
     * local validation diagnostic and erase any volatile password (§14.6). */
    var dialogOverflowListener: ((String) -> Unit)? = null

    private fun handleDialogShow(id: JsonElement, params: JsonObject) {
        val dialogId = params.stringOrNull("dialog_id")
        val spec = params.objOrNull("spec")
        if (dialogId.isNullOrEmpty() || spec == null)
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 18.1: gated on surfaces.dialog.
        if ("surfaces.dialog" !in granted)
            return respondError(id, -32601, "Method not found", "method-not-found")
        // SPEC 18.1: a second outstanding request with the same id is
        // content-invalid; the first is neither replaced nor aliased.
        if (dialogs.containsKey(dialogId))
            return respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("reason", "dialog-duplicate") })
        // SPEC 18.1: exceeding max_dialogs is 1401; existing dialogs stand.
        if (dialogs.size >= config.limits.longOr("max_dialogs", 4))
            return respondError(id, 1401, "Too many dialogs", "overloaded")
        val statefuls: Map<String, JsonObject>
        try {
            statefuls = SpecValidator.validateSurfaceSpec(
                spec, maxCaptureFields = config.limits.longOr("max_capture_fields", 64),
                maxChartPoints = config.limits.longOr("max_chart_points", Long.MAX_VALUE),
                maxCanvasOps = config.limits.longOr("max_canvas_ops", Long.MAX_VALUE),
                maxRichSpans = config.limits.longOr("max_rich_spans", Long.MAX_VALUE),
                maxTableCells = config.limits.longOr("max_table_cells", Long.MAX_VALUE),
                // SPEC 17.1: a dialog spec is gated to the dialog profile's
                // advertised node_types — an app-only type (chart/editor/
                // scaffold) degrades instead of rendering + dispatching here.
                advertisedTypes = nodeTypesFromProfiles(config.surfaceProfiles, "dialog"),
                // SPEC 14.2 (LD-17): a builtin outside the dialog profile's
                // advertised set is an invalid context here — e.g. a
                // clipboard.copy in a dialog rejects the document.
                advertisedBuiltins = builtinsFromProfiles(config.surfaceProfiles, "dialog"))
        } catch (e: ContentInvalid) {
            return respondError(id, 1201, "Invalid content", "content-invalid",
                buildJsonObject { put("path", e.path); put("reason", e.reason) })
        }
        // SPEC 19: the editor-session count is over "accepted surface OR
        // DIALOG documents", and a synchronized editor presented in a dialog
        // is presented in READY like any other — so it is counted, size-
        // checked, and OPENED. Before this a dialog's editor was rendered as
        // synchronized and never synchronized: no session, no edit.open, and
        // `editor-session-limit` could never fire from a dialog at all.
        val dialogEditorNodes = if ("editor.sync" in granted)
            scanSyncedEditors(spec, "dialog") else emptyMap()
        if (dialogEditorNodes.isNotEmpty()) {
            val others = editorIdentityCount()
            if (others + dialogEditorNodes.size >
                config.limits.longOr("max_editor_sessions", 8))
                return respondError(id, 1201, "Invalid content", "content-invalid",
                    buildJsonObject { put("reason", "editor-session-limit") })
            val maxBytes = config.limits.longOr("max_editor_bytes", Long.MAX_VALUE)
            for ((identity, node) in dialogEditorNodes) {
                if (EditorSession.jcsUtf8Bytes(node.stringOr("value")) > maxBytes)
                    return respondError(id, 1201, "Invalid content", "content-invalid",
                        buildJsonObject {
                            put("path", "spec.$identity")
                            put("reason", "editor-too-large")
                        })
                if (editors.containsKey(node.reqString("document") to identity))
                    return respondError(id, 1201, "Invalid content", "content-invalid",
                        buildJsonObject {
                            put("path", "spec.$identity")
                            put("reason", "editor-duplicate")
                        })
            }
        }
        // SPEC 18.1: held outstanding — no reply until a builtin or cancel.
        dialogs[dialogId] = id
        // T3/LD-3: keep the authored defaults this validation just computed.
        // They were discarded, so `capture_fields` had nothing to fall back
        // to and invented `""` for any field the user had not touched — an
        // untouched `checkbox` authored `checked: true` shipped the STRING ""
        // where §14.1 requires the node's logical value, boolean `true`.
        // Dialog state is dialog-local (§18.1), so this is the only place the
        // authored layer exists; the store's `currentValue` covers surfaces.
        dialogDefaults[dialogId] = buildJsonObject {
            // A stateful with no authored value defaults to JSON null — the
            // JsonNull write is the logical value, not a collapsed guard.
            for ((nodeId, node) in statefuls)
                put(nodeId, SurfaceStore.authoredValueOf(node) ?: JsonNull)
        }
        if (dialogEditorNodes.isNotEmpty()) {
            val map = LinkedHashMap<String, String>()
            for ((identity, node) in dialogEditorNodes) {
                val document = node.reqString("document")
                map[identity] = document
                openEditor(document, identity, node.stringOr("value"))
            }
            dialogEditors[dialogId] = map
        }
        dialogListener?.invoke(dialogId, spec)
    }

    /** SPEC 18.1: dialog.submit builtin completes the request as submitted.
     * VALUE is the builtin's authored value; FIELDS the captured node
     * values (the renderer holds dialog-local state, SPEC 18.1). */
    @Synchronized
    fun completeDialogSubmit(dialogId: String, value: JsonElement? = null,
                             fields: JsonObject? = null) {
        val reqId = dialogs[dialogId] ?: return
        // The null guard survives AS a guard: a null VALUE means the member is
        // absent from the result, exactly as org.json's put(k, null) removal
        // behaved (an authored JSON null arrives as JsonNull, which is
        // non-null here and is written through).
        val result = buildJsonObject {
            put("status", "submitted")
            if (value != null) put("value", value)
            if (fields != null && fields.isNotEmpty()) put("fields", fields)
        }
        // SPEC 18.1: serialize the prospective complete response FIRST. If its
        // body would exceed max_frame_bytes, write no part of it and do NOT
        // complete the dialog — the dialog stays outstanding so the user can
        // shrink the input, and the host concludes any password attempt with a
        // §14.6 erasure. This ordering prevents orphaning the request in
        // encodeFrame after the dialog was already removed.
        val body = wireSerialize(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", reqId)
            put("result", result)
        }).utf8Len()
        if (body > WireLimits.MAX_BODY_OCTETS) {
            dialogOverflowListener?.invoke(dialogId)
            return
        }
        dialogs.remove(dialogId)
        closeDialogEditors(dialogId)
        dialogDefaults.remove(dialogId)
        respondResult(reqId, result)
        dialogListener?.invoke(dialogId, null)
    }

    /** SPEC 18.1: dialog.dismiss builtin or a platform dismissal. */
    @Synchronized
    fun completeDialogDismiss(dialogId: String) {
        val reqId = dialogs.remove(dialogId) ?: return
        closeDialogEditors(dialogId)
        dialogDefaults.remove(dialogId)
        respondResult(reqId, buildJsonObject { put("status", "dismissed") })
        dialogListener?.invoke(dialogId, null)
    }

    // ----------------------------------------------------------- handshake

    private val hexId = Regex("[0-9a-f]{32}")

    private fun handleHello(id: JsonElement, params: JsonObject) {
        // Integer SPELLING only: the number 2 is the protocol marker; 2.0 and
        // "2" are mismatches, exactly as the old Int-equality check had it.
        if (params.wireIntOrNull("protocol") != 2L) {
            // SPEC 9.2/12: protocol mismatch is 1202 with data.supported.
            return respondError(id, 1202, "Unsupported protocol major", "protocol-version",
                buildJsonObject { put("supported", buildJsonArray { add(2) }) })
        }
        val client = params.objOrNull("client")
        val pairingId = params.stringOrNull("pairing_id")
        val clientNonce = params.stringOrNull("client_nonce")
        val clientOk = client != null &&
            client.keys == setOf("name", "version") &&
            client.stringOrNull("name").let { it != null && it.isNotEmpty() && it.utf8Len() <= 128 } &&
            client.stringOrNull("version").let { it != null && it.isNotEmpty() && it.utf8Len() <= 128 }
        val wantsList = params.arrOrNull("wants")?.map { it.asStringOrNull() }
        val wantsOk = wantsList != null && wantsList.size <= 128 &&
            wantsList.all { it != null } &&
            wantsList.toSet().size == wantsList.size // duplicates are invalid
        if (!clientOk || pairingId == null || !hexId.matches(pairingId) ||
            clientNonce == null || !EbpAuth.isValidNonce(clientNonce) || !wantsOk)
            // SPEC 10.1: a legal handshake method with malformed params.
            return respondError(id, -32602, "Invalid params", "invalid-params")
        // SPEC 9.1: never reveal whether the pairing ID is known; challenge
        // regardless and fail at the proof.
        lastWants = wantsList!!.map { it!! }
        pendingPairingId = pairingId
        pendingClientNonce = clientNonce
        pendingServerNonce = config.nonceSource()
        respondResult(id, buildJsonObject { put("server_nonce", pendingServerNonce!!) })
        state = sessionStep(state, SessionEvent.HELLO_ACCEPTED) ?: state
    }

    private fun handleAuth(id: JsonElement, params: JsonObject) {
        val pid = params.stringOrNull("pairing_id")
        val cn = params.stringOrNull("client_nonce")
        val sn = params.stringOrNull("server_nonce")
        val proof = params.stringOrNull("client_proof")
        // SPEC 9.3: type/grammar failures are -32602 followed by close.
        if (pid == null || !hexId.matches(pid) ||
            cn == null || !EbpAuth.isValidNonce(cn) ||
            sn == null || !EbpAuth.isValidNonce(sn) ||
            proof == null || !EbpAuth.isValidProof(proof)) {
            respondError(id, -32602, "Invalid params", "invalid-params")
            return close("malformed auth.response")
        }
        // SPEC 9.3: well-formed but reused, mismatched, or incorrect -> 1203.
        // SPEC 9.2: an unknown pairing ID MUST be verified "with work
        // equivalent to the known-ID path — an HMAC-SHA256 computation
        // against a fixed dummy key and a constant-time comparison — so
        // neither the failure stage, the error code, nor response TIMING
        // distinguishes an unknown pairing ID from an incorrect proof."
        // Short-circuiting on `token != null` skipped the HMAC entirely and
        // separated the two branches by exactly one HMAC of timing, on a
        // loopback transport where the attacker's clock is the local one.
        val proofKey = proofProvider.resolve(pendingPairingId!!)
        val keyed = when (proofKey) {
            is CompanionProofKeyResult.Known -> proofKey.key
            is CompanionProofKeyResult.Unknown -> proofKey.dummyKey
        }
        val proofOk = EbpAuth.verifyClientProof(proof, keyed, pid, cn, sn)
        // Fixed-length hex identifiers compare without early exit too (§9.3
        // applies the same rule to this path); `&` not `&&` so no branch is
        // skipped once a mismatch is known.
        val ok = EbpAuth.constantTimeEquals(pid, pendingPairingId) and
            EbpAuth.constantTimeEquals(cn, pendingClientNonce) and
            EbpAuth.constantTimeEquals(sn, pendingServerNonce) and
            (proofKey is CompanionProofKeyResult.Known) and proofOk
        if (!ok) {
            respondError(id, 1203, "Authentication failed", "auth-failed")
            return close("auth failed")
        }
        // The second HMAC is unreachable until both the client proof and the
        // challenged-session identifiers have verified. A KeyStore-backed
        // handle therefore never signs a server proof for a rejected client.
        check(proofKey is CompanionProofKeyResult.Known)
        val serverProof = EbpAuth.serverProof(
            proofKey.key, pendingPairingId!!, pendingClientNonce!!, pendingServerNonce!!)
        respondResult(id, buildWelcome(serverProof))
        state = sessionStep(state, SessionEvent.AUTH_VERIFIED) ?: state
    }

    // ------------------------------------------------------------- welcome

    private var lastWants: List<String> = emptyList()
    private var sessionBoundarySeq = Long.MAX_VALUE

    private fun buildWelcome(serverProof: String): JsonObject {
        granted = lastWants.filter { it in config.supportedCapabilities }
        sessionBoundarySeq = queue.boundarySeq()
        return buildJsonObject {
            put("server_proof", serverProof)
            put("protocol", 2)
            put("server", buildJsonObject {
                put("name", config.serverName)
                put("version", config.serverVersion)
            })
            put("granted", buildJsonArray { granted.forEach { add(it) } })
            put("surface_profiles", config.surfaceProfiles)
            put("surfaces", surfaces.snapshot()) // snapshots AND tombstones (10.2)
            // SPEC 10.2: the count visible to the next replay, after the
            // already-identified expired records are gone.
            put("queued_events", queue.let { it.sweepExpired(); it.count() })
            put("limits", config.limits)
            // SPEC 20.1.1: mirror the known geometry so the FIRST snapshot
            // can be authored for the right class; omitted when unknown.
            windowGeom?.let { put("window", it) }
            // SPEC 10.2: input_state MUST be omitted when empty; device waits
            // for the capability/trigger modules.
            surfaces.inputState().takeIf { it.isNotEmpty() }
                ?.let { put("input_state", it) }
            // SPEC 20.1: the device report is REQUIRED once capabilities or
            // triggers is granted. trigger_caps MUST be empty unless triggers
            // is granted, and the trigger-only members MAY be empty then too —
            // so a capabilities-only session never sees a non-empty trigger
            // surface. (R4: the old deep copy is gone — the immutable report
            // shares safely, and the suppressed variant is a `with` rebuild.)
            if ("capabilities" in granted || "triggers" in granted) {
                var report = config.deviceReport
                if ("triggers" !in granted) {
                    val empty = JsonArray(emptyList())
                    report = report.with("trigger_caps", empty)
                        .with("trigger_types", empty)
                        .with("trackable_state_types", empty)
                        .with("trigger_unavailable", JsonObject(emptyMap()))
                    // state_types is REQUIRED only when triggers granted or
                    // state.get is in caps; otherwise it too may be empty.
                    val caps = report.arrOrNull("caps") ?: JsonArray(emptyList())
                    if (caps.none { it.asStringOrNull() == "state.get" })
                        report = report.with("state_types", empty)
                }
                put("device", report)
            }
        }
    }

    /**
     * SPEC 4.5: B + max_input_state_bytes - 2 <= max_frame_bytes, where B
     * is the prospective complete welcome response body with the longest
     * legal request ID and input_state {}. Also enforces the table floors.
     */
    private fun checkLimits() {
        val l = config.limits
        fun floor(name: String, min: Long) {
            val v = l.longOr(name, -1)
            require(v >= min) { "limits.$name must be at least $min" }
        }
        require(l.longOr("max_frame_bytes") == WireLimits.MAX_BODY_OCTETS.toLong()) {
            "limits.max_frame_bytes must equal ${WireLimits.MAX_BODY_OCTETS}"
        }
        floor("max_queued_events", 256); floor("max_queued_bytes", 8_388_608)
        floor("max_event_bytes", 262_144); floor("max_surfaces", 16)
        floor("max_surface_ids", 1024); floor("max_field_bytes", 65_536)
        floor("max_input_state_bytes", 262_144); floor("max_capture_fields", 64)
        require(l.reqLong("max_event_bytes") <= l.reqLong("max_frame_bytes") - 256) {
            "max_event_bytes exceeds max_frame_bytes - 256"
        }
        require(l.reqLong("max_field_bytes") <= l.reqLong("max_frame_bytes") - 2048) {
            "max_field_bytes exceeds max_frame_bytes - 2048"
        }
        require(l.reqLong("max_surfaces") <= l.reqLong("max_surface_ids")) {
            "max_surfaces exceeds max_surface_ids"
        }
        // SPEC 4.5: conditional limits are REQUIRED the moment the capability
        // or node type they bound is advertised — a host that advertises
        // editor.sync/rich_text/table without them ships a non-conforming
        // welcome (amendment #84; LD-15/LD-22).
        if ("editor.sync" in config.supportedCapabilities) {
            floor("max_editor_bytes", 65_536)
            require(l.reqLong("max_editor_bytes") <= l.reqLong("max_frame_bytes") - 4096) {
                "max_editor_bytes exceeds max_frame_bytes - 4096"
            }
        }
        for (target in config.surfaceProfiles.keys) {
            val types = nodeTypesFromProfiles(config.surfaceProfiles, target) ?: continue
            if ("rich_text" in types) floor("max_rich_spans", 1)
            if ("table" in types) floor("max_table_cells", 1)
        }
        // SPEC 4.5: the actual server strings must fit the 128-octet bound
        // the reservation reserves for them (SPEC 10.2).
        require(config.serverName.utf8Len() <= 128 &&
            config.serverVersion.utf8Len() <= 128) {
            "server name/version exceed 128 UTF-8 octets"
        }
        // SPEC 4.5: `surfaces` at its worst case — max_surface_ids distinct
        // maximum-length IDs, maximum revision, and the longer `present`
        // encoding (`false`). Counting it empty was the reservation's hole.
        val worstSurfaces = buildJsonObject {
            for (i in 0 until l.reqLong("max_surface_ids"))
                // A distinct 128-octet key: a byte-size probe, not a real ID.
                put(i.toString().padStart(WireLimits.MAX_IDENTIFIER_OCTETS, 'a'),
                    buildJsonObject {
                        put("revision", 9_007_199_254_740_991L)
                        put("present", false)
                    })
        }
        val prospective = buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", "a".repeat(WireLimits.MAX_REQUEST_ID_OCTETS))
            put("result", buildJsonObject {
                put("server_proof", "0".repeat(64))
                put("protocol", 2)
                // SPEC 4.5: fixed members at their maximum legal encoded size.
                put("server", buildJsonObject {
                    put("name", "a".repeat(128))
                    put("version", "a".repeat(128))
                })
                put("granted", buildJsonArray {
                    config.supportedCapabilities.forEach { add(it) }
                })
                put("surface_profiles", config.surfaceProfiles)
                put("surfaces", worstSurfaces)
                put("queued_events", l.reqLong("max_queued_events"))
                put("input_state", JsonObject(emptyMap()))
                put("limits", l)
            })
        }
        // SPEC 4.5/20.1 (amendment #40): the welcome device report is a variable
        // member emitted when capabilities or triggers is granted. Reserve
        // max_device_report_bytes for it (rather than embed it in `prospective`,
        // which cannot see a per-session grant), and require the configured
        // report to fit that bound so it never depends on truncation.
        val emitsReport = "capabilities" in config.supportedCapabilities ||
            "triggers" in config.supportedCapabilities
        val deviceBudget = if (emitsReport) l.longOr("max_device_report_bytes", 0) else 0L
        if (deviceBudget > 0)
            require(wireSerialize(config.deviceReport).utf8Len() <= deviceBudget) {
                "device report exceeds max_device_report_bytes"
            }
        val b = wireSerialize(prospective).utf8Len().toLong()
        require(b + deviceBudget + l.reqLong("max_input_state_bytes") - 2 <=
            l.reqLong("max_frame_bytes")) {
            "welcome reservation violated: B=$b, device=$deviceBudget"
        }
    }

    // -------------------------------------------------------------- output

    private fun respondResult(id: JsonElement, result: JsonObject) {
        // SPEC 7.1: "A responder that computes a result but cannot serialize
        // the response body MUST answer the request with -32603
        // internal-error; it MUST NOT leave the request unanswered." Every
        // result here is host-supplied (a capability outcome, a device
        // sample), so the shape is not ours to trust: kotlinx THROWS where
        // org.json's toString() swallowed its own JSONException and handed
        // back null, and a pathologically nested host result still overflows
        // the recursive encoder. Both used to escape as a thrown frame out of
        // feed(), which answers nothing and leaves Emacs holding an id that
        // never concludes — serializeReply is the funnel that prevents it.
        val body = serializeReply(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", id)
            put("result", result)
        })
        if (body == null) {
            // The error body is small, fixed, and built from constants — it
            // serializes on a stack that has already unwound.
            respondError(id, -32603, "Internal error", "internal-error")
            return
        }
        sink(encodeFrame(body))
    }

    /** null when the body cannot be encoded. Both arms stay across the
     * kotlinx swap: an Exception where org.json returned null from
     * `toString()`, and a StackOverflowError for a deep host-supplied tree. */
    private fun serializeReply(msg: JsonObject): String? =
        try {
            wireSerialize(msg)
        } catch (e: Exception) {
            null
        } catch (e: StackOverflowError) {
            null
        }

    private fun respondError(id: JsonElement, code: Int, message: String, kind: String,
                             data: JsonObject = JsonObject(emptyMap())) {
        // SPEC 7.2 (amendment #34): ids are strings or safe integers.
        // errorResponse merges `kind` into a COPY of data (C2 retired the
        // caller-visible write-through).
        if (isValidRequestId(id))
            emit(errorResponse(id, code, message, kind, data))
    }

    /** SPEC 6.2/8: a framing-level error carries `id: null`, which
     * `respondError` deliberately rejects (a request id is never null). */
    private fun emitFramingError(code: Int, message: String, kind: String) {
        if (state == SessionState.CLOSED) return
        emit(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", JsonNull)
            put("error", buildJsonObject {
                put("code", code)
                put("message", message)
                put("data", buildJsonObject { put("kind", kind) })
            })
        })
    }

    private fun emit(msg: JsonObject) = sink(encodeFrame(wireSerialize(msg)))

    /** The ONE outbound serializer: every emit site and every byte-measuring
     * site go through it, so the SPEC 4.5/14.4/15.4 gates measure exactly the
     * bytes the wire carries (W6QueueTest.byteGateMeasuresWhatItEmits). */
    private fun wireSerialize(msg: JsonElement): String = msg.toString()

    private fun String.utf8Len(): Int = toByteArray(Charsets.UTF_8).size
}
