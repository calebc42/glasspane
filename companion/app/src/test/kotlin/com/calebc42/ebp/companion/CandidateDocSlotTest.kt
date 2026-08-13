// SPDX-License-Identifier: GPL-3.0-or-later
// R5 (amendment #172): the one-outstanding latest-wins doc-request slot,
// plus the offer-currency rule. Pure classes precisely so these
// transitions are testable: DeviceBridge is constructor-coupled to
// android.content.Context, and every slot-state mutant (stale publish,
// dropped reissue, never-freed slot, double-issue across offer death)
// would be unkillable through it (R5 review F18).
package com.calebc42.ebp.companion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CandidateDocSlotTest {

    @Test
    fun idleSlotIssuesImmediately() {
        val slot = CandidateDocSlot()
        val flight = slot.request(7L, 3)
        assertNotNull(flight)
        assertEquals(7L, flight!!.epoch)
        assertEquals(3, flight.index)
        // Its conclusion frees the slot; the next request issues again.
        assertNull(slot.concluded(flight.ticket))
        assertNotNull(slot.request(7L, 4))
    }

    @Test
    fun latestHighlightWinsBehindTheInFlightOne() {
        val slot = CandidateDocSlot()
        val a = slot.request(7L, 0)!!
        // Two highlights while A flies: only the LAST is desired.
        assertNull(slot.request(7L, 1))
        assertNull(slot.request(7L, 2))
        val next = slot.concluded(a.ticket)
        assertNotNull(next)
        assertEquals(2, next!!.index)
        assertEquals(7L, next.epoch)
        // The reissued flight concludes to a free slot: index 1 never flies.
        assertNull(slot.concluded(next.ticket))
    }

    @Test
    fun retireKeepsTheOutstandingFlightAndDropsDesired() {
        // The R5 review's one-outstanding hole: the offer dies while a
        // flight is on the wire. The flight keeps OCCUPYING the slot —
        // its conclusion is guaranteed — so a long-press on the fresh
        // offer queues behind it instead of double-issuing, and the
        // retired desired pair never flies.
        val slot = CandidateDocSlot()
        val a = slot.request(7L, 0)!!
        assertNull(slot.request(7L, 1))   // desired under the old offer
        slot.retire()
        // Fresh offer's highlight: queued, NOT issued.
        assertNull(slot.request(8L, 5))
        // A's conclusion hands over to the LATEST desired (8,5); the
        // retired (7,1) is gone.
        val next = slot.concluded(a.ticket)
        assertEquals(8L, next!!.epoch)
        assertEquals(5, next.index)
        assertNull(slot.concluded(next.ticket))
    }

    @Test
    fun retireAloneLeavesAConcludedSlotFree() {
        val slot = CandidateDocSlot()
        val a = slot.request(7L, 0)!!
        assertNull(slot.request(7L, 1))
        slot.retire()
        // No fresh highlight arrived: A concludes to a FREE slot and
        // the dead desired pair never issues.
        assertNull(slot.concluded(a.ticket))
        val fresh = slot.request(9L, 2)
        assertNotNull(fresh)
        assertNull(slot.concluded(fresh!!.ticket))
    }

    @Test
    fun staleTicketIsIgnored() {
        // A ticket that is not the outstanding flight's — a double
        // conclusion here; an orphaned-instance conclusion after
        // forgetEditor in the bridge — must neither free the slot nor
        // hand back a desired pair.
        val slot = CandidateDocSlot()
        val a = slot.request(7L, 0)!!
        assertNull(slot.concluded(a.ticket))
        val b = slot.request(8L, 1)!!
        assertNull(slot.concluded(a.ticket))   // A's ticket, again
        assertNull(slot.request(8L, 2))        // still queued behind B
        assertEquals(2, slot.concluded(b.ticket)!!.index)
    }
}

class OfferEpochCurrentTest {

    @Test
    fun exactEpochMatchOnly() {
        assertTrue(offerEpochCurrent(7L, 7L))
        // A fresh reply published between gesture and executor (F11).
        assertFalse(offerEpochCurrent(8L, 7L))
        // The offer died entirely.
        assertFalse(offerEpochCurrent(null, 7L))
    }
}
