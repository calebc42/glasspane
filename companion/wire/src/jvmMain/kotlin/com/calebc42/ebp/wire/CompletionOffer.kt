// SPDX-License-Identifier: GPL-3.0-or-later
// Amendments #170/#171 (R4): the survive-typing completion offer.
//
// SPEC 19.3's extension-survival exception is a precisely bounded state
// machine, and this class IS that machine, in the wire layer where its
// conformance is testable: an offer (one edit.complete reply) stays alive
// while every sequence advance is a local `del` 0 splice landing exactly at
// the extension region's end — the POSITIONAL rule; the caret report is
// best-effort context and never the test — and dies on any other advance
// (a remote apply, a deletion, an edit elsewhere). At emission the tapped
// candidate must re-prove itself against the ACTIVE narrowing predicate
// over the EXTENDED PREFIX (the returned prefix plus everything typed
// since): that re-proof is what closes the stale-row tap race, because
// display narrowing is asynchronous and the emit point is not. WHICH of
// the two predicates is active is receiver-local presentation
// (user-settable, no wire member); the predicate family is CLOSED at two.
package com.calebc42.ebp.wire

/** SPEC 19.3 (amendment #171): the closed two-predicate family. */
enum class CompletionNarrowing { STRICT, CONTAINS }

/** One reply candidate. `insert` is defaulted to `label` on ABSENCE
 * only: SPEC 19.3 says it "MAY be empty", and an explicit "" is a
 * selection that DELETES the prefix — conflating it with absence
 * emitted the label where the SPEC required nothing. */
data class OfferCandidate(val label: String, val insert: String,
                          val kind: String?)

class CompletionOfferTracker {
    var active: Boolean = false; private set
    var prefix: String = ""; private set
    var cursor: Int = 0; private set        // the requested cursor (scalars)
    var expectedSeq: Long = 0; private set  // reply seq + qualifying advances
    var ext: String = ""; private set
    var candidates: List<OfferCandidate> = emptyList(); private set

    fun setOffer(prefix: String, cursor: Int, seq: Long,
                 candidates: List<OfferCandidate>) {
        this.prefix = prefix; this.cursor = cursor; this.expectedSeq = seq
        this.ext = ""; this.candidates = candidates; this.active = true
    }

    fun clear() {
        active = false; ext = ""; candidates = emptyList()
    }

    /** Scalar length of the extension typed since the reply. */
    fun extScalars(): Int = ext.codePointCount(0, ext.length)

    /** The extension region's end: requested cursor + extension. */
    fun regionEnd(): Int = cursor + extScalars()

    /** The operand of the emission-time re-proof. */
    fun extendedPrefix(): String = prefix + ext

    /** Every LOCAL splice flows here (the accept splice itself does not —
     * the emitter clears instead). Qualifying = insertion at the region's
     * end; anything else kills the offer, exactly rule (a). */
    fun onLocalSplice(start: Int, del: Int, text: String) {
        if (!active) return
        if (del == 0 && start == regionEnd()) {
            ext += text
            expectedSeq += 1
        } else clear()
    }

    /** A remote apply (or any advance the tracker did not qualify). */
    fun onForeignAdvance() = clear()

    /** The emission-time re-proof over the EXTENDED PREFIX. Well-formed
     * strings make code-unit prefix/substring checks scalar-correct: a
     * scalar boundary in the operand is always a code-unit boundary.
     *
     * A PRISTINE offer bypasses the predicate: SPEC 19.3 makes the
     * narrowing normative only inside the extension exception, and the
     * base path — session, seq, cursor, and prefix verified by the
     * caller — is an unconditional MUST. Emacs completion tables are
     * not prefix engines (case-insensitive, flex, partial-completion):
     * their candidates need not contain the returned prefix at all,
     * and predicate-testing them here discarded every such tap. */
    fun matches(narrowing: CompletionNarrowing, c: OfferCandidate): Boolean {
        if (ext.isEmpty()) return true
        val ep = extendedPrefix()
        return when (narrowing) {
            CompletionNarrowing.STRICT ->
                c.label.startsWith(ep) || c.insert.startsWith(ep)
            CompletionNarrowing.CONTAINS ->
                c.label.contains(ep) || c.insert.contains(ep)
        }
    }
}

/** A render-facing snapshot: what to narrow against, whether any
 * extension has been typed (a pristine offer is the base path — the
 * display, like the emitter, applies no predicate to it), and whether
 * the offer is still alive at all. */
data class CompletionOfferView(val extendedPrefix: String,
                               val ext: String,
                               val active: Boolean)
