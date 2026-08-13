// SPDX-License-Identifier: GPL-3.0-or-later
// R5 (amendment #172): the one-outstanding latest-wins doc-request slot.
// A pure class precisely so these transitions are testable: DeviceBridge
// is constructor-coupled to android.content.Context, and every slot-state
// mutant (stale publish, dropped reissue, never-freed slot) would be
// unkillable through it (R5 review F18).
package com.calebc42.ebp.companion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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
    fun staleConclusionAfterRetireIsIgnored() {
        val slot = CandidateDocSlot()
        val a = slot.request(7L, 0)!!
        slot.retire()
        // A fresh offer's flight now owns the slot.
        val b = slot.request(8L, 5)!!
        // A's conclusion arrives late: it must neither free the slot nor
        // hand back a desired pair (the wedge/cross-offer publish mutant).
        assertNull(slot.concluded(a.ticket))
        // B is still the outstanding flight; a highlight queues behind it
        // and B's own conclusion hands it over.
        assertNull(slot.request(8L, 6))
        val next = slot.concluded(b.ticket)
        assertEquals(6, next!!.index)
    }

    @Test
    fun retireDropsTheDesiredPairToo() {
        val slot = CandidateDocSlot()
        val a = slot.request(7L, 0)!!
        assertNull(slot.request(7L, 1))
        slot.retire()
        // Neither the stale conclusion nor anything else revives index 1.
        assertNull(slot.concluded(a.ticket))
        val fresh = slot.request(9L, 2)
        assertNotNull(fresh)
        assertNull(slot.concluded(fresh!!.ticket))
    }
}
