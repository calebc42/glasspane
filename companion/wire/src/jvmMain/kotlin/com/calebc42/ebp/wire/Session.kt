// SPDX-License-Identifier: GPL-3.0-or-later
// EBP 2 session lifecycle, Companion view. Implements ebp/SPEC.md 10.1.
// Pure: transport wiring and the welcome arrive at rung W3.
package com.calebc42.ebp.wire

/** SPEC 10.1 connection states as the Companion (the server) sees them. */
enum class SessionState { CONNECTED, CHALLENGED, SYNCING, READY, CLOSED }

/** Companion-side transition triggers. */
enum class SessionEvent {
    /** `session.hello` validated and the nonce response issued. */
    HELLO_ACCEPTED,
    /** `auth.response` proof verified and the welcome committed. */
    AUTH_VERIFIED,
    /** `session.ready` succeeded; its response is serialized first (10.3). */
    READY_CONFIRMED,
    /** Any failure, timeout, replacement, or shutdown (10.1). */
    CLOSE,
}

/**
 * Pure transition function; null means the event is illegal in that state.
 * The caller owns the fail-closed behavior SPEC 10.1 attaches to illegal
 * traffic (1200 pre-auth, 1204 post-auth, drop-and-log for notifications).
 */
fun sessionStep(state: SessionState, event: SessionEvent): SessionState? = when {
    event == SessionEvent.CLOSE -> SessionState.CLOSED
    state == SessionState.CONNECTED && event == SessionEvent.HELLO_ACCEPTED ->
        SessionState.CHALLENGED
    state == SessionState.CHALLENGED && event == SessionEvent.AUTH_VERIFIED ->
        SessionState.SYNCING
    state == SessionState.SYNCING && event == SessionEvent.READY_CONFIRMED ->
        SessionState.READY
    else -> null
}
