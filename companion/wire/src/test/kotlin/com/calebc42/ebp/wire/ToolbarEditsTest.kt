// SPDX-License-Identifier: GPL-3.0-or-later
// W9-i SPEC 17.7: the editor-toolbar local-edit transforms. Snippet
// substitution is single-pass over the closed placeholder set with the `$${`
// escape and literal unknown tokens; the four line ops are structural edits on
// the caret's line. Every case is a pure text→text assertion.
package com.calebc42.ebp.wire

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ToolbarEditsTest {

    private fun caret(text: String, at: Int) = ToolbarEdit.caret(text, at)

    // ----------------------------------------------------- substitution

    @Test
    fun selectionWrapsAndStaysSelected() {
        // "**word**" wrapping the selected "word".
        val edit = ToolbarEdit("a word b", 2, 6) // selects "word"
        val out = ToolbarEdits.applySnippet(edit, "**\${selection}**", "cursor")
        assertEquals("a **word** b", out.text)
        // The substituted "word" (between the stars) stays selected.
        assertEquals("word", out.text.substring(out.selStart, out.selEnd))
    }

    @Test
    fun cursorTokenPlacesTheCaret() {
        val edit = caret("", 0)
        val out = ToolbarEdits.applySnippet(edit, "[[\${cursor}]]", "cursor")
        assertEquals("[[]]", out.text)
        assertEquals(2, out.selStart) // caret between the brackets
        assertEquals(out.selStart, out.selEnd)
    }

    @Test
    fun dateTimeInputTokensSubstitute() {
        val out = ToolbarEdits.applySnippet(
            caret("", 0), "\${date} \${time} \${input:Who}", "cursor",
            input = "Sam", date = "2026-07-23 Thu", time = "14:05")
        assertEquals("2026-07-23 Thu 14:05 Sam", out.text)
    }

    @Test
    fun dollarDollarBraceIsLiteralAndDoesNotStartAPlaceholder() {
        // SPEC 17.7: `$${` produces a literal `${` and does NOT begin a
        // placeholder — the token inside stays verbatim.
        val out = ToolbarEdits.applySnippet(caret("", 0), "price = $\${cursor}", "cursor")
        assertEquals("price = \${cursor}", out.text)
        // No cursor token was consumed, so the caret lands after the insertion.
        assertEquals(out.text.length, out.selStart)
    }

    @Test
    fun secondCursorTokenIsConsumedNotLeakedLiterally() {
        // Only the first ${cursor} records the caret; a repeat is a KNOWN token
        // and MUST be consumed, not emitted as literal "${cursor}" text.
        val out = ToolbarEdits.applySnippet(caret("", 0), "[\${cursor}]\${cursor}", "cursor")
        assertEquals("[]", out.text)
        assertEquals(1, out.selStart) // the first cursor, between the brackets
    }

    @Test
    fun lineStartNoOpIsTheExactLiteralPrefixNotATrimmedMatch() {
        // "* head" already starts with the exact "* " -> no-op.
        assertEquals("* head",
            ToolbarEdits.applySnippet(caret("* head", 2), "* ", "line-start").text)
        // "  * head" does NOT literally start with "* " (it starts with spaces),
        // so the prefix IS inserted — a trimmed match would have wrongly no-op'd.
        assertEquals("* " + "  * head",
            ToolbarEdits.applySnippet(caret("  * head", 4), "* ", "line-start").text)
    }

    @Test
    fun unknownTokenStaysLiteral() {
        val out = ToolbarEdits.applySnippet(caret("x", 1), "\${bogus}", "cursor")
        assertEquals("x\${bogus}", out.text)
    }

    @Test
    fun substitutedTextIsNotRescanned() {
        // The selection itself contains a token; it must NOT be interpreted.
        val edit = ToolbarEdit("\${time}", 0, 7) // the literal text is selected
        val out = ToolbarEdits.applySnippet(edit, "<\${selection}>", "cursor",
            time = "99:99")
        assertEquals("<\${time}>", out.text) // the selected ${time} stayed literal
    }

    // --------------------------------------------------------- placement

    @Test
    fun lineStartInsertsPrefixOnceAndIsIdempotent() {
        val first = ToolbarEdits.applySnippet(caret("todo item", 4), "- ", "line-start")
        assertEquals("- todo item", first.text)
        // A second application on the now-prefixed line is a no-op.
        val second = ToolbarEdits.applySnippet(
            caret(first.text, 6), "- ", "line-start")
        assertEquals(first.text, second.text)
    }

    @Test
    fun blockPlacesSnippetOnItsOwnLines() {
        val out = ToolbarEdits.applySnippet(
            caret("before after", 6), "#+begin\ncode\n#+end", "block")
        assertEquals("before\n#+begin\ncode\n#+end\n after", out.text)
    }

    // --------------------------------------------------------- line ops

    @Test
    fun promoteRemovesOneStarThenTwoSpacesThenStops() {
        assertEquals("* h", ToolbarEdits.lineOp("promote", caret("** h", 3))!!.text)
        assertEquals("x", ToolbarEdits.lineOp("promote", caret("  x", 3))!!.text)
        // A single-star heading or a flush line is already at minimum depth.
        assertEquals("* h", ToolbarEdits.lineOp("promote", caret("* h", 2))!!.text)
        assertEquals("flush", ToolbarEdits.lineOp("promote", caret("flush", 2))!!.text)
    }

    @Test
    fun demoteAddsStarOrIndentsListsOnly() {
        assertEquals("** h", ToolbarEdits.lineOp("demote", caret("* h", 2))!!.text)
        assertEquals("  - item", ToolbarEdits.lineOp("demote", caret("- item", 3))!!.text)
        assertEquals("  1. item", ToolbarEdits.lineOp("demote", caret("1. item", 3))!!.text)
        // A plain paragraph line is unchanged.
        assertEquals("plain", ToolbarEdits.lineOp("demote", caret("plain", 2))!!.text)
    }

    @Test
    fun moveUpAndDownSwapLinesAndNoOpAtEnds() {
        val text = "one\ntwo\nthree"
        // caret on "two" (offset 5) moves it up.
        assertEquals("two\none\nthree",
            ToolbarEdits.lineOp("move-up", caret(text, 5))!!.text)
        // caret on "two" moves it down.
        assertEquals("one\nthree\ntwo",
            ToolbarEdits.lineOp("move-down", caret(text, 5))!!.text)
        // First line up / last line down are no-ops.
        assertEquals(text, ToolbarEdits.lineOp("move-up", caret(text, 1))!!.text)
        assertEquals(text, ToolbarEdits.lineOp("move-down", caret(text, 11))!!.text)
    }

    @Test
    fun unknownLineOpIsNull() {
        assertNull(ToolbarEdits.lineOp("rotate", caret("x", 0)))
    }

    @Test
    fun inputPromptAndNeedsInput() {
        assertEquals("Who", ToolbarEdits.inputPrompt("hi \${input:Who}"))
        assertEquals("Input", ToolbarEdits.inputPrompt("\${input:}"))
        assert(ToolbarEdits.needsInput("\${input:X}"))
        assert(!ToolbarEdits.needsInput("\${cursor}"))
    }

    @Test
    fun promoteAndDemoteAreInverse() {
        // SPEC 17.7 (A6): "Within one line these two operations MUST be
        // inverse." The old rules were not: an INDENTED `*` bullet promoted
        // to column 0 became a heading, which demote then turned into `**`.
        fun promote(t: String) = ToolbarEdits.lineOp("promote", caret(t, t.length))!!.text
        fun demote(t: String) = ToolbarEdits.lineOp("demote", caret(t, t.length))!!.text
        // The bullet that used to be destroyed: promote leaves it alone,
        // because de-indenting it to column 0 would manufacture a heading.
        assertEquals("  * sub item", promote("  * sub item"))
        // Emphasis is not an outline heading — the `*` form needs a space.
        assertEquals("*bold* text", promote("*bold* text"))
        assertEquals("*bold* text", demote("*bold* text"))
        // Round-trips, both directions, for each line shape §17.7 names.
        for (line in listOf("** head", "*** head", "  - bullet", "  + bullet",
                            "  1. ordered", "  2) ordered", "   indented")) {
            assertEquals("promote∘demote on '" + line + "'",
                line, promote(demote(line)))
        }
        for (line in listOf("** head", "  - bullet", "  + bullet", "    deep")) {
            assertEquals("demote∘promote on '" + line + "'",
                line, demote(promote(line)))
        }
    }
}
