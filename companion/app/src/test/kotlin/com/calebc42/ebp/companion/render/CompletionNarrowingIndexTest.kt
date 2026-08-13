// SPDX-License-Identifier: GPL-3.0-or-later
// R5: display narrowing preserves WIRE indices — edit.candidate.doc names
// candidates by position in the retained reply, so a row that survives
// filter + take must keep the index Emacs knows it by, not its screen slot.
package com.calebc42.ebp.companion.render

import com.calebc42.ebp.companion.CompletionCandidate
import com.calebc42.ebp.wire.CompletionNarrowing
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CompletionNarrowingIndexTest {

    private fun cand(label: String, insert: String = label) =
        CompletionCandidate(label, null, insert, null)

    private val candidates = listOf(
        cand("xaa"),          // 0
        cand("xb"),           // 1
        cand("xab"),          // 2
        cand("zz", "xa-ins"), // 3: only the INSERT matches
    )

    @Test
    fun strictNarrowingKeepsWireIndices() {
        val r = narrowedWithWireIndex(candidates, true, "xa", "a",
            CompletionNarrowing.STRICT)
        assertEquals(listOf(0, 2, 3), r.map { it.index })
        assertEquals("xaa", r[0].value.label)
        // take() — the visible cut — cannot renumber what filter kept.
        assertEquals(listOf(0, 2), r.take(2).map { it.index })
    }

    @Test
    fun containsNarrowingKeepsWireIndices() {
        val r = narrowedWithWireIndex(candidates, true, "ab", "b",
            CompletionNarrowing.CONTAINS)
        assertEquals(listOf(2), r.map { it.index })
    }

    @Test
    fun pristineOfferDisplaysUnfiltered() {
        // The R4 pin holds through the R5 rewrite: an empty ext is the
        // base path — no predicate applies, whatever the prefix looks
        // like (Emacs tables are not prefix engines).
        val r = narrowedWithWireIndex(candidates, true, "xa", "",
            CompletionNarrowing.STRICT)
        assertEquals(listOf(0, 1, 2, 3), r.map { it.index })
    }

    @Test
    fun inactiveOfferShowsNothing() {
        assertTrue(narrowedWithWireIndex(candidates, false, "", "",
            CompletionNarrowing.STRICT).isEmpty())
    }

    // ---- the doc panel's three-condition show gate (all required) ----

    @Test
    fun docPanelShowsOnlyForTheCurrentEpochsVisibleRow() {
        val doc = com.calebc42.ebp.companion.CandidateDoc(2, "Prints.", 7L)
        assertTrue(candidateDocVisible(doc, 7L, listOf(0, 2, 3)))
        // A stale fetch or a fresh offer: epoch mismatch hides it.
        assertTrue(!candidateDocVisible(doc, 8L, listOf(0, 2, 3)))
        // The offer survived a qualifying extension (same epoch) but
        // narrowing dropped the documented row off screen.
        assertTrue(!candidateDocVisible(doc, 7L, listOf(0, 3)))
        assertTrue(!candidateDocVisible(null, 7L, listOf(2)))
    }

    @Test
    fun emptyDocShowsNoPanel() {
        // "" is the universal degradation arm — every picker candidate,
        // timeout, latch collision, and failure — not a rare case; a
        // panel for it would be indistinguishable from a regression.
        val empty = com.calebc42.ebp.companion.CandidateDoc(2, "", 7L)
        assertTrue(!candidateDocVisible(empty, 7L, listOf(2)))
    }
}
