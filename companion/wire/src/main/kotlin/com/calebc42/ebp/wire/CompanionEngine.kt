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
    /** Nonce source, injectable for tests. */
    val nonceSource: () -> String = EbpAuth::generateNonce,
)

class CompanionEngine(
    private val config: CompanionConfig,
    private val sink: (ByteArray) -> Unit,
) {
    var state: SessionState = SessionState.CONNECTED
        private set
    var closeReason: String? = null
        private set

    private val decoder = FrameDecoder()
    private var pendingPairingId: String? = null
    private var pendingClientNonce: String? = null
    private var pendingServerNonce: String? = null

    init {
        // SPEC 4.5: the welcome reservation must hold before any session.
        checkLimits()
    }

    fun feed(bytes: ByteArray) {
        if (state == SessionState.CLOSED) return
        val messages = try {
            decoder.feed(bytes)
        } catch (e: FrameClose) { return close("frame: ${e.message}") }
        catch (e: FrameIncomplete) { return close("frame: ${e.message}") }
        catch (e: WireParseError) { return close("body: ${e.message}") }
        catch (e: InvalidRequest) { return close("body: ${e.message}") }
        for (msg in messages) {
            if (state == SessionState.CLOSED) return
            dispatch(msg)
        }
    }

    fun close(reason: String) {
        state = SessionState.CLOSED
        closeReason = reason
    }

    // ------------------------------------------------------------ dispatch

    private fun dispatch(msg: JSONObject) {
        when (classifyMessage(msg)) {
            MessageClass.REQUEST ->
                handleRequest(msg.get("id"), msg.getString("method"),
                    msg.optJSONObject("params") ?: JSONObject())
            MessageClass.NOTIFICATION ->
                handleNotification(msg.getString("method"))
            MessageClass.RESPONSE -> Unit // no outstanding Companion requests yet (W5)
            null ->
                // SPEC 7.3: structurally invalid; answer only when an id exists.
                if (msg.has("id") && msg.has("method"))
                    respondError(msg.get("id"), -32600, "Invalid Request", "invalid-request")
        }
    }

    private fun handleRequest(id: Any, method: String, params: JSONObject) {
        // SPEC 7.2: request IDs are strings.
        if (!isValidRequestId(id))
            return respondError(id, -32600, "Invalid Request", "invalid-request")
        // SPEC 10.1: fail closed before authentication — only the exact
        // expected handshake method is answered on its merits.
        when (state) {
            SessionState.CONNECTED -> {
                if (method != "session.hello")
                    return respondError(id, 1200, "Not authenticated", "not-authenticated")
                return handleHello(id, params)
            }
            SessionState.CHALLENGED -> {
                if (method != "auth.response")
                    return respondError(id, 1200, "Not authenticated", "not-authenticated")
                return handleAuth(id, params)
            }
            else -> Unit
        }
        val spec = METHOD_REGISTRY[method]
            ?: return respondError(id, -32601, "Method not found", "method-not-found")
        if (spec.sender == Sender.COMPANION || !spec.isRequest)
            // SPEC 7.3: wrong endpoint or wrong class.
            return respondError(id, -32600, "Invalid Request", "invalid-request")
        if (state !in spec.states)
            // SPEC 10.1: post-auth, wrong-state requests get 1204.
            return respondError(id, 1204, "Not legal in this session state", "session-state")
        when (method) {
            "queue.replay" -> respondResult(id, JSONObject()
                .put("delivered", 0).put("rejected", 0).put("expired", 0)
                .put("remaining", 0).put("blocked_by", JSONObject.NULL))
            "session.ready" -> {
                // SPEC 10.3: the {} response serializes ahead of every
                // READY-only frame; emitting before transitioning does that.
                respondResult(id, JSONObject())
                state = sessionStep(state, SessionEvent.READY_CONFIRMED) ?: state
            }
            else ->
                // Registered in SPEC 11 but its rung has not landed yet.
                respondError(id, -32603, "Not implemented at this rung", "internal-error")
        }
    }

    private fun handleNotification(method: String) {
        // Pre-auth (SPEC 10.1) and unknown/wrong-direction (SPEC 7.3)
        // notifications are logged and dropped; nothing is emitted.
        if (state == SessionState.CONNECTED || state == SessionState.CHALLENGED) return
        val spec = METHOD_REGISTRY[method] ?: return
        if (spec.sender == Sender.COMPANION || spec.isRequest) return
        // rpc.cancel and friends: nothing cancellable exists at this rung.
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

    private fun buildWelcome(token: ByteArray): JSONObject {
        val granted = lastWants.filter { it in config.supportedCapabilities }
        return JSONObject()
            .put("server_proof", EbpAuth.serverProof(
                token, pendingPairingId!!, pendingClientNonce!!, pendingServerNonce!!))
            .put("protocol", 2)
            .put("server", JSONObject()
                .put("name", config.serverName).put("version", config.serverVersion))
            .put("granted", JSONArray(granted))
            .put("surface_profiles", config.surfaceProfiles)
            .put("surfaces", JSONObject())     // the surface store lands at W4
            .put("queued_events", 0)           // the durable queue lands at W6
            .put("limits", config.limits)
        // input_state omitted while empty; device omitted until granted.
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
        val prospective = JSONObject()
            .put("jsonrpc", "2.0")
            .put("id", "a".repeat(WireLimits.MAX_REQUEST_ID_OCTETS))
            .put("result", JSONObject()
                .put("server_proof", "0".repeat(64))
                .put("protocol", 2)
                .put("server", JSONObject()
                    .put("name", config.serverName).put("version", config.serverVersion))
                .put("granted", JSONArray(config.supportedCapabilities.toList()))
                .put("surface_profiles", config.surfaceProfiles)
                .put("surfaces", JSONObject())
                .put("queued_events", l.getLong("max_queued_events"))
                .put("input_state", JSONObject())
                .put("limits", l))
        val b = prospective.toString().toByteArray(Charsets.UTF_8).size.toLong()
        require(b + l.getLong("max_input_state_bytes") - 2 <= l.getLong("max_frame_bytes")) {
            "welcome reservation violated: B=$b"
        }
    }

    // -------------------------------------------------------------- output

    private fun respondResult(id: Any, result: JSONObject) =
        emit(resultResponse(id as String, result))

    private fun respondError(id: Any, code: Int, message: String, kind: String,
                             data: JSONObject = JSONObject()) {
        if (id is String) emit(errorResponse(id, code, message, kind, data))
    }

    private fun emit(msg: JSONObject) = sink(encodeFrame(msg.toString()))

    private fun Any?.utf8Len(): Int =
        (this as String).toByteArray(Charsets.UTF_8).size
}
