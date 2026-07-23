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
