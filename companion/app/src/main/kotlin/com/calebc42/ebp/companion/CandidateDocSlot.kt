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
 * conclusion.
 *
 * [retire] (the offer died) drops only the DESIRED pair: the
 * outstanding flight stays, because it is physically on the wire and
 * its conclusion is guaranteed exactly once (the engine's sendRequest
 * answers locally when it refuses) — keeping it in the slot is what
 * makes a long-press on the FRESH offer queue behind it instead of
 * double-issuing (the R5 review's one-outstanding hole).  A flight the
 * engine refused to send never concludes on its own; the caller
 * concludes it immediately.
 *
 * Tickets pair each conclusion with the exact flight it ends.  With
 * the bridge concluding on the instance a flight was ISSUED from (an
 * R5 review fix — tickets are per-instance, so re-resolving the slot
 * by key let a discarded instance's stale conclusion disown a fresh
 * instance's first flight), the check guards the remaining shapes: a
 * double conclusion, and a conclusion outliving a [forgetEditor]
 * removal onto an orphaned instance.
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
     * slot is free.  A ticket that is not the outstanding flight's — a
     * double conclusion, or one landing on an orphaned instance — is
     * ignored entirely. */
    @Synchronized
    fun concluded(ticket: Long): Flight? {
        if (outstanding?.ticket != ticket) return null
        outstanding = desired?.let { (e, i) -> Flight(e, i, ++nextTicket) }
        desired = null
        return outstanding
    }

    /** The offer died: drop the desired pair.  The outstanding flight —
     * if any — keeps occupying the slot until its guaranteed
     * conclusion, so a fresh offer's highlight queues rather than
     * double-issuing. */
    @Synchronized
    fun retire() {
        desired = null
    }
}
