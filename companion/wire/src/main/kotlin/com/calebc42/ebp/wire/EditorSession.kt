// SPDX-License-Identifier: GPL-3.0-or-later
// One synchronized editor shadow (SPEC 19). Positions and lengths are
// zero-based Unicode-scalar counts with half-open ranges; the Kotlin String
// is UTF-16, so every boundary converts through codePoint offsets. The
// Companion is the serialization point: local edits and inbound edit.apply
// requests both advance one shared sequence, and only the operation that
// first claims seq+1 wins.
package com.calebc42.ebp.wire

class EditorSession(
    val document: String,
    val editorId: String,
    var sessionId: String,
) {
    enum class State { OPEN, STALE, CLOSED }
    var state = State.OPEN
    var seq = 0L
    var shadow = ""
    var cursor = 0
    var selStart = 0
    var selEnd = 0

    /** SPEC 19.1: length is a scalar-value count, not a UTF-16 unit count. */
    fun scalarLength(): Int = shadow.codePointCount(0, shadow.length)

    private fun offset(scalarIndex: Int): Int =
        shadow.offsetByCodePoints(0, scalarIndex)

    /**
     * SPEC 4.5 (amendment #84): the document's JCS-serialized UTF-8 size
     * after a prospective splice, or -1 when the range is invalid (splice()
     * refuses that case itself). Escapes are per-character, so fragment
     * arithmetic is exact: whole document minus removed range plus insert.
     */
    fun spliceJcsBytes(start: Int, del: Int, text: String): Long {
        val n = scalarLength()
        if (start < 0 || del < 0 || start + del > n) return -1
        val removed = shadow.substring(offset(start), offset(start + del))
        return jcsUtf8Bytes(shadow) - (jcsUtf8Bytes(removed) - 2) +
            (jcsUtf8Bytes(text) - 2)
    }

    /**
     * SPEC 19.3: validate a half-open scalar splice against the length
     * equation and bounds, then apply it atomically. Returns false (leaving
     * the shadow untouched) for any out-of-range or wrong-length splice.
     */
    fun splice(start: Int, del: Int, text: String, len: Int): Boolean {
        val n = scalarLength()
        if (start < 0 || del < 0 || start + del > n) return false
        val inserted = text.codePointCount(0, text.length)
        if (len != n - del + inserted) return false
        shadow = shadow.substring(0, offset(start)) + text +
            shadow.substring(offset(start + del))
        cursor = start + inserted
        selStart = cursor
        selEnd = cursor
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
         * scalar splice (start, del, insert) that produces it, by trimming the
         * common prefix and suffix. Counts are Unicode scalar values so astral
         * characters stay whole. A synchronized client feeds the result to
         * edit.delta; the Companion derives len from its own shadow. When the
         * client's pre-edit text equals the Companion shadow (the invariant a
         * live session maintains), this splice applies cleanly.
         */
        fun diff(old: String, new: String): Triple<Int, Int, String> {
            val o = old.codePoints().toArray()
            val n = new.codePoints().toArray()
            var pre = 0
            val min = minOf(o.size, n.size)
            while (pre < min && o[pre] == n[pre]) pre++
            var suf = 0
            while (suf < min - pre && o[o.size - 1 - suf] == n[n.size - 1 - suf]) suf++
            val del = o.size - pre - suf
            return Triple(pre, del, String(n, pre, n.size - pre - suf))
        }
    }

    /** SPEC 19.3: caret/selection is paired-or-omitted; cursor is one end of
     * a non-collapsed selection. Returns false on an invalid caret. */
    fun setCaret(cursor: Int, selStart: Int?, selEnd: Int?): Boolean {
        val n = scalarLength()
        if (cursor < 0 || cursor > n) return false
        if ((selStart == null) != (selEnd == null)) return false
        if (selStart != null && selEnd != null) {
            if (selStart < 0 || selEnd > n || selStart > selEnd) return false
            if (cursor != selStart && cursor != selEnd) return false
            this.selStart = selStart; this.selEnd = selEnd
        } else {
            this.selStart = cursor; this.selEnd = cursor
        }
        this.cursor = cursor
        return true
    }
}
