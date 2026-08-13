// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.ebp.companion

/**
 * SPEC 19.3 (amendment #172, R5): one editor's one-outstanding
 * candidate-documentation request slot, latest-wins.
 *
 * The SPEC's SHOULD — at most one `edit.candidate.doc` outstanding per
 * session — meets a user who drags a highlight across rows faster than
 * round trips conclude: a new (epoch, index) wanted while one is in
 * flight OVERWRITES the previously desired pair rather than queueing
 * behind it, and the desired request is issued at the in-flight one's
 * conclusion.  Tickets pair each conclusion with the exact flight it
 * ends: after a [retire] (the offer died) a stale conclusion must not
 * free — or re-arm — a slot a fresh offer's flight now owns.
 *
 * Extracted as a pure class because DeviceBridge is constructor-coupled
 * to android.content.Context and has no unit test: every slot-state
 * mutant (stale publish, dropped reissue, never-freed slot) would
 * otherwise be unkillable (R5 review F18).  Thread-safe: the request
 * path runs on the bridge's dispatch executor, conclusions on the
 * engine's reader thread.
 */
class CandidateDocSlot {

    /** One issued flight: what was asked, and the ticket its conclusion
     * must present. */
    data class Flight(val epoch: Long, val index: Int, val ticket: Long)

    private var nextTicket = 0L
    private var outstanding: Flight? = null
    private var desired: Pair<Long, Int>? = null

    /** A highlight wants (EPOCH, INDEX).  Returns the [Flight] to issue
     * NOW, or null when it was recorded as the desired pair behind the
     * in-flight one (latest wins — any earlier desired pair is gone). */
    @Synchronized
    fun request(epoch: Long, index: Int): Flight? =
        if (outstanding == null)
            Flight(epoch, index, ++nextTicket).also { outstanding = it }
        else {
            desired = epoch to index
            null
        }

    /** The flight holding TICKET concluded.  Returns the next [Flight]
     * to issue (the desired pair, now outstanding), or null when the
     * slot is free.  A stale ticket — a conclusion outliving [retire] —
     * is ignored entirely. */
    @Synchronized
    fun concluded(ticket: Long): Flight? {
        if (outstanding?.ticket != ticket) return null
        outstanding = desired?.let { (e, i) -> Flight(e, i, ++nextTicket) }
        desired = null
        return outstanding
    }

    /** The offer died: nothing in flight matters any more.  A conclusion
     * that still arrives presents a ticket no longer outstanding. */
    @Synchronized
    fun retire() {
        outstanding = null
        desired = null
    }
}
