// SPDX-License-Identifier: GPL-3.0-or-later
// One synchronized editor shadow (SPEC 19). Positions and lengths are
// zero-based Unicode-scalar counts with half-open ranges; the Kotlin String
// is UTF-16, so every boundary converts through codePoint offsets. The
// Companion is the serialization point: local edits and inbound edit.apply
// requests both advance one shared sequence, and only the operation that
// first claims seq+1 wins.
//
// T2: positions are TYPED at every method boundary — Emacs never let charpos
// and bytepos be the same type (buffer.h states the discipline, insdel.c
// machine-checks it, conversion is always a named call), and LD-4 was exactly
// the mixup that discipline prevents: Compose UTF-16 offsets flowing into
// scalar slots unconverted. ScalarPos and Utf16Pos both erase to Int (zero
// allocation); the ONE conversion pair lives here as named functions.
package com.calebc42.ebp.wire

/** SPEC 19.1: a zero-based Unicode-scalar-value position. */
@JvmInline
value class ScalarPos(val v: Int)

/** A UTF-16 code-unit position (Compose/Java string offsets). */
@JvmInline
value class Utf16Pos(val v: Int)

/**
 * THE UTF-16 -> scalar conversion (with its inverse below, the only pair).
 * Clamps into range and never splits a surrogate pair: an offset landing on
 * the low half backs off to the pair start, so a caret inside an astral
 * character maps to the character's own position (A5 / critic §6).
 */
fun scalarPosIn(text: String, u: Utf16Pos): ScalarPos {
    var at = u.v.coerceIn(0, text.length)
    if (at in 1 until text.length &&
        text[at].isLowSurrogate() && text[at - 1].isHighSurrogate()) at -= 1
    return ScalarPos(text.codePointCount(0, at))
}

/** THE scalar -> UTF-16 conversion; clamps into range. */
fun utf16PosIn(text: String, p: ScalarPos): Utf16Pos {
    val n = text.codePointCount(0, text.length)
    return Utf16Pos(text.offsetByCodePoints(0, p.v.coerceIn(0, n)))
}

/** One half-open scalar splice, as EditorSession.diff derives it. */
data class Splice(val start: ScalarPos, val del: Int, val text: String)

class EditorSession(
    val document: String,
    val editorId: String,
    var sessionId: String,
) {
    enum class State { OPEN, STALE, CLOSED }
    var state = State.OPEN
    var seq = 0L
    var shadow = ""

    // Session caret state, always in the scalar domain (SPEC 19.1). Plain
    // Ints: the typed boundary is the METHOD signatures; inside this class
    // there is exactly one domain.
    var cursor = 0
    var selStart = 0
    var selEnd = 0

    /** SPEC 19.1: length is a scalar-value count, not a UTF-16 unit count. */
    fun scalarLength(): Int = shadow.codePointCount(0, shadow.length)

    private fun offset(scalarIndex: Int): Int =
        utf16PosIn(shadow, ScalarPos(scalarIndex)).v

    /**
     * SPEC 4.5 (amendment #84): the document's JCS-serialized UTF-8 size
     * after a prospective splice, or -1 when the range is invalid (the
     * splice methods refuse that case themselves). Escapes are
     * per-character, so fragment arithmetic is exact: whole document minus
     * removed range plus insert.
     */
    fun spliceJcsBytes(start: ScalarPos, del: Int, text: String): Long {
        val n = scalarLength()
        // Long arithmetic: `start + del` as Int wraps, and a wrapped sum is
        // NOT > n, so a legal SPEC 4.2 integer near Int.MAX_VALUE slipped
        // this guard and reached substring() as a negative index.
        if (start.v < 0 || del < 0 || start.v.toLong() + del > n) return -1
        val removed = shadow.substring(offset(start.v), offset(start.v + del))
        return jcsUtf8Bytes(shadow) - (jcsUtf8Bytes(removed) - 2) +
            (jcsUtf8Bytes(text) - 2)
    }

    /**
     * SPEC 19.3: validate a half-open scalar splice against the length
     * equation and bounds, then apply it atomically. Returns false (leaving
     * the shadow untouched) for any out-of-range or wrong-length splice.
     * LOCAL form: the caret follows the insertion — Emacs's SET_PT, correct
     * for the user's own keystroke and for completion insertion.
     */
    fun splice(start: ScalarPos, del: Int, text: String, len: Int): Boolean {
        val n = scalarLength()
        if (start.v < 0 || del < 0 || start.v.toLong() + del > n) return false
        val inserted = text.codePointCount(0, text.length)
        if (len != n - del + inserted) return false
        shadow = shadow.substring(0, offset(start.v)) + text +
            shadow.substring(offset(start.v + del))
        cursor = start.v + inserted
        selStart = cursor
        selEnd = cursor
        return true
    }

    /**
     * SPEC 19.4: an inbound text-changing `edit.apply`, atomically. The
     * splice AND the peer-dictated post-state caret are validated BEFORE any
     * mutation — a gate failure leaves text, caret, and selection untouched
     * (LD-5: the old path spliced first, then discarded a failed setCaret
     * and answered "applied" over a half-updated session).
     *
     * §19.4 makes `cursor` REQUIRED on every text-changing apply, so the
     * caret's post-splice value is dictated by the peer, not derived — which
     * is why insdel.c's three-case marker adjustment has no live slot here
     * (B2: take the arithmetic only where a derived position exists; the
     * sender computing WHICH cursor to dictate is ebp.el's side of the
     * seam).
     */
    fun spliceRemote(start: ScalarPos, del: Int, text: String, len: Int,
                     cursor: ScalarPos, selStart: ScalarPos?, selEnd: ScalarPos?): Boolean {
        val n = scalarLength()
        if (start.v < 0 || del < 0 || start.v.toLong() + del > n) return false
        val inserted = text.codePointCount(0, text.length)
        if (len != n - del + inserted) return false
        if (!caretValid(len, cursor.v, selStart?.v, selEnd?.v)) return false
        shadow = shadow.substring(0, offset(start.v)) + text +
            shadow.substring(offset(start.v + del))
        applyCaret(cursor.v, selStart?.v, selEnd?.v)
        return true
    }

    companion object {
        /**
         * SPEC 4.5 (amendment #84): `max_editor_bytes` measures the UTF-8
         * length of the JCS-serialized document text — the form both endpoints
         * compute identically (ebp.el uses `string-bytes (json-serialize
         * text)`). Two enclosing quotes; `"` `\` and the five short escapes
         * are 2 bytes; any other C0 control is 6 (\u00XX); everything else
         * its plain UTF-8 length. Matches Emacs 30.1 json_out_string, not
         * org.json's quote() (which also escapes `/` after `<`).
         */
        fun jcsUtf8Bytes(text: String): Long {
            var bytes = 2L
            var i = 0
            while (i < text.length) {
                val cp = text.codePointAt(i)
                bytes += when {
                    cp == '"'.code || cp == '\\'.code -> 2L
                    cp == 0x08 || cp == 0x09 || cp == 0x0A ||
                        cp == 0x0C || cp == 0x0D -> 2L
                    cp < 0x20 -> 6L
                    cp < 0x80 -> 1L
                    cp < 0x800 -> 2L
                    cp < 0x10000 -> 3L
                    else -> 4L
                }
                i += Character.charCount(cp)
            }
            return bytes
        }

        /**
         * SPEC 19.3: reduce an old→new text change to the single half-open
         * scalar splice that produces it, by trimming the common prefix and
         * suffix. Counts are Unicode scalar values so astral characters stay
         * whole. A synchronized client feeds the result to edit.delta; the
         * Companion derives len from its own shadow. When the client's
         * pre-edit text equals the Companion shadow (the invariant a live
         * session maintains), this splice applies cleanly.
         */
        fun diff(old: String, new: String): Splice {
            val o = old.codePoints().toArray()
            val n = new.codePoints().toArray()
            var pre = 0
            val min = minOf(o.size, n.size)
            while (pre < min && o[pre] == n[pre]) pre++
            var suf = 0
            while (suf < min - pre && o[o.size - 1 - suf] == n[n.size - 1 - suf]) suf++
            val del = o.size - pre - suf
            return Splice(ScalarPos(pre), del, String(n, pre, n.size - pre - suf))
        }
    }

    /** SPEC 19.3's caret rules against a document of [len] scalars: in
     * range; selection paired, ordered, in range; cursor equal to one end
     * whenever a pair is present. */
    private fun caretValid(len: Int, cursor: Int, selStart: Int?, selEnd: Int?): Boolean {
        if (cursor < 0 || cursor > len) return false
        if ((selStart == null) != (selEnd == null)) return false
        if (selStart != null && selEnd != null) {
            if (selStart < 0 || selEnd > len || selStart > selEnd) return false
            if (cursor != selStart && cursor != selEnd) return false
        }
        return true
    }

    private fun applyCaret(cursor: Int, selStart: Int?, selEnd: Int?) {
        if (selStart != null && selEnd != null) {
            this.selStart = selStart; this.selEnd = selEnd
        } else {
            this.selStart = cursor; this.selEnd = cursor
        }
        this.cursor = cursor
    }

    /** SPEC 19.3: caret/selection is paired-or-omitted; cursor is one end of
     * a non-collapsed selection. Returns false on an invalid caret. */
    fun setCaret(cursor: ScalarPos, selStart: ScalarPos?, selEnd: ScalarPos?): Boolean {
        if (!caretValid(scalarLength(), cursor.v, selStart?.v, selEnd?.v)) return false
        applyCaret(cursor.v, selStart?.v, selEnd?.v)
        return true
    }
}
