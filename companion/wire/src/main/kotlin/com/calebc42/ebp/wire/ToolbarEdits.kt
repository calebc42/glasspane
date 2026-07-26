// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 17.7 editor-toolbar local edits: the pure text transforms behind a
// `snippet` (with its closed placeholder set + placement) and the four `line`
// ops. Kept in the wire module — no Compose — so the whole substitution engine
// is JVM-unit-tested; the app layer wraps these around a TextFieldValue and
// dispatches `command` separately. Every function is total: an unknown token,
// an unknown line value, or an out-of-range cursor yields a no-op or a literal,
// never an exception.
package com.calebc42.ebp.wire

/** A text field state: the buffer plus the selection ends (equal = a caret). */
data class ToolbarEdit(val text: String, val selStart: Int, val selEnd: Int) {
    companion object {
        fun caret(text: String, at: Int) = ToolbarEdit(text, at, at)
    }
}

// SPEC 17.7: the heading forms — one-or-more (demote) and two-or-more
// (promote) `*` FOLLOWED BY A SPACE. The space matters: without it a line
// like `*bold* text` is treated as an outline heading and corrupted.
private val HEADING_1PLUS = Regex("""^\*+ """)
private val HEADING_2PLUS = Regex("""^\*\*+ """)

object ToolbarEdits {

    /** The rendered snippet: substituted text plus where the position tokens
     * resolved (−1 = absent). */
    private class Rendered(val text: String, val cursor: Int, val selStart: Int, val selEnd: Int)

    /**
     * SPEC 17.7 single-pass substitution of the closed placeholder set.
     * `${selection}` is filled by [selText] (its FIRST occurrence records the
     * selection range); `${cursor}` records the final caret; `${date}`/`${time}`
     * use the supplied strings; `${input:...}` uses [input] when present. `$${`
     * yields a literal `${` WITHOUT starting a placeholder (a format-6 rule the
     * poc predates); any other `${...}` stays literal. Substituted text is never
     * rescanned.
     */
    private fun render(
        snippet: String, selText: String, input: String?, date: String, time: String,
    ): Rendered {
        val sb = StringBuilder()
        var cursor = -1
        var selStart = -1
        var selEnd = -1
        var i = 0
        val n = snippet.length
        while (i < n) {
            val c = snippet[i]
            // $${ -> literal ${ (escape wins before placeholder detection).
            if (c == '$' && i + 2 < n && snippet[i + 1] == '$' && snippet[i + 2] == '{') {
                sb.append("\${"); i += 3; continue
            }
            if (c == '$' && i + 1 < n && snippet[i + 1] == '{') {
                val end = snippet.indexOf('}', i + 2)
                if (end < 0) { sb.append(snippet, i, n); break }
                val token = snippet.substring(i + 2, end)
                when {
                    token == "selection" && selStart < 0 -> {
                        selStart = sb.length; sb.append(selText); selEnd = sb.length
                    }
                    token == "selection" -> sb.append(selText)
                    token == "cursor" && cursor < 0 -> cursor = sb.length
                    // A repeat ${cursor} is a KNOWN position token — consume it
                    // (only the first records the caret); it MUST NOT leak as
                    // literal "${cursor}" text.
                    token == "cursor" -> {}
                    token == "date" -> sb.append(date)
                    token == "time" -> sb.append(time)
                    token.startsWith("input:") && input != null -> sb.append(input)
                    else -> sb.append(snippet, i, end + 1) // literal, never fatal
                }
                i = end + 1
                continue
            }
            sb.append(c); i++
        }
        return Rendered(sb.toString(), cursor, selStart, selEnd)
    }

    /** The `${input:Prompt}` title from the first input token, or "Input". */
    fun inputPrompt(snippet: String): String {
        val start = snippet.indexOf("\${input:")
        if (start < 0) return "Input"
        val end = snippet.indexOf('}', start)
        if (end < 0) return "Input"
        return snippet.substring(start + 8, end).ifEmpty { "Input" }
    }

    /** True when [snippet] carries a `${input:...}` token needing a prompt. */
    fun needsInput(snippet: String): Boolean = snippet.contains("\${input:")

    /**
     * Apply [snippet] to [edit] under [placement] (`cursor` default,
     * `line-start`, or `block`), supplying [input]/[date]/[time] for the
     * matching placeholders. Returns the resulting field state.
     */
    fun applySnippet(
        edit: ToolbarEdit, snippet: String, placement: String,
        input: String? = null, date: String = "", time: String = "",
    ): ToolbarEdit {
        val text = edit.text
        val lo = minOf(edit.selStart, edit.selEnd).coerceIn(0, text.length)
        val hi = maxOf(edit.selStart, edit.selEnd).coerceIn(0, text.length)
        val selText = if (lo == hi) "" else text.substring(lo, hi)
        val r = render(snippet, selText, input, date, time)
        return when (placement) {
            "line-start" -> insertAtLineStart(edit, r.text)
            "block" -> insertBlock(edit, r)
            else -> insertAtCursor(edit, r)
        }
    }

    /** `cursor` placement: a `${selection}` snippet wraps the selection (and
     * leaves the substituted content selected); otherwise it inserts at the
     * caret. `${cursor}` wins the final caret; else the caret ends after the
     * insertion. */
    private fun insertAtCursor(edit: ToolbarEdit, r: Rendered): ToolbarEdit {
        val text = edit.text
        val collapsed = edit.selStart == edit.selEnd
        val consume = r.selStart >= 0 && !collapsed
        val lo = minOf(edit.selStart, edit.selEnd).coerceIn(0, text.length)
        val hi = maxOf(edit.selStart, edit.selEnd).coerceIn(0, text.length)
        val start = if (consume) lo else edit.selStart.coerceIn(0, text.length)
        val end = if (consume) hi else start
        val newText = text.substring(0, start) + r.text + text.substring(end)
        return when {
            r.cursor >= 0 -> ToolbarEdit.caret(newText, start + r.cursor)
            r.selStart in 0 until r.selEnd -> ToolbarEdit(newText, start + r.selStart, start + r.selEnd)
            r.selStart >= 0 -> ToolbarEdit.caret(newText, start + r.selStart)
            else -> ToolbarEdit.caret(newText, start + r.text.length)
        }
    }

    /** `line-start` placement: insert [prefix] at the caret line's start;
     * SPEC 17.7 no-op when the line already begins with that literal prefix. */
    private fun insertAtLineStart(edit: ToolbarEdit, prefix: String): ToolbarEdit {
        val text = edit.text
        val cursor = edit.selStart.coerceIn(0, text.length)
        val lineStart = text.lastIndexOf('\n', cursor - 1) + 1
        // SPEC 17.7: no-op when the line already starts with the EXACT literal
        // inserted prefix (a whitespace-trimmed match is not the exact prefix).
        if (prefix.isNotEmpty() && text.regionMatches(lineStart, prefix, 0, prefix.length))
            return edit
        val newText = text.substring(0, lineStart) + prefix + text.substring(lineStart)
        return ToolbarEdit.caret(newText, cursor + prefix.length)
    }

    /** `block` placement: the snippet lands on its own line(s), adding the
     * surrounding newlines as needed; `${cursor}` places the caret inside. */
    private fun insertBlock(edit: ToolbarEdit, r: Rendered): ToolbarEdit {
        val text = edit.text
        val cursor = edit.selStart.coerceIn(0, text.length)
        val needLead = cursor > 0 && text[cursor - 1] != '\n'
        val needTrail = cursor < text.length && text[cursor] != '\n'
        val insert = buildString {
            if (needLead) append('\n')
            append(r.text)
            if (needTrail) append('\n')
        }
        val newText = text.substring(0, cursor) + insert + text.substring(cursor)
        val insertStart = cursor + if (needLead) 1 else 0
        val pos = insertStart + if (r.cursor >= 0) r.cursor else r.text.length
        return ToolbarEdit.caret(newText, pos)
    }

    // ---------------------------------------------------- line ops (17.7)

    /** Dispatch a `line` op; null for an unrecognized name (SPEC 17.7 no-op). */
    fun lineOp(name: String, edit: ToolbarEdit): ToolbarEdit? = when (name) {
        "promote" -> promote(edit)
        "demote" -> demote(edit)
        "move-up" -> moveUp(edit)
        "move-down" -> moveDown(edit)
        else -> null
    }

    private fun lineBounds(text: String, cursor: Int): Pair<Int, Int> {
        val c = cursor.coerceIn(0, text.length)
        val start = text.lastIndexOf('\n', c - 1) + 1
        val end = text.indexOf('\n', c).let { if (it == -1) text.length else it }
        return start to end
    }

    /** SPEC 17.7 promote: −1 outline step — two-or-more `*` FOLLOWED BY A
     * SPACE loses one, else a 2+-space indent loses two (but a `*` bullet is
     * never de-indented to column 0), else unchanged. */
    private fun promote(edit: ToolbarEdit): ToolbarEdit {
        val text = edit.text
        val cursor = edit.selStart.coerceIn(0, text.length)
        val (ls, le) = lineBounds(text, cursor)
        val line = text.substring(ls, le)
        // The heading form requires the following space, and an indented `*`
        // bullet MUST NOT reach column 0: there it would BECOME a heading,
        // which demote cannot undo, so the pair would not be inverse.
        val newLine = when {
            HEADING_2PLUS.containsMatchIn(line) -> line.removePrefix("*")
            line.startsWith("  ") -> {
                val indent = line.length - line.trimStart().length
                if (indent == 2 && line.trimStart().startsWith("*")) return edit
                line.substring(2)
            }
            else -> return edit
        }
        val shift = newLine.length - line.length
        val newText = text.substring(0, ls) + newLine + text.substring(le)
        return ToolbarEdit.caret(newText, (cursor + shift).coerceAtLeast(ls))
    }

    /** SPEC 17.7 demote: +1 outline step — a `*` line gains one; else a bullet
     * or ordered list item gains two leading spaces; else unchanged. */
    private fun demote(edit: ToolbarEdit): ToolbarEdit {
        val text = edit.text
        val cursor = edit.selStart.coerceIn(0, text.length)
        val (ls, le) = lineBounds(text, cursor)
        val line = text.substring(ls, le)
        // SPEC 17.7: unordered bullets are `-`, `+`, AND `*` — promote can
        // de-indent any of them, so demote must be able to restore each. Each
        // marker must be FOLLOWED BY A SPACE, or emphasis like `*bold* text`
        // is misread as a bullet and silently indented.
        val opensList = line.trimStart().let {
            it.startsWith("- ") || it.startsWith("+ ") || it.startsWith("* ") ||
                it.matches(Regex("""\d+[.)] .*"""))
        }
        val newLine = when {
            HEADING_1PLUS.containsMatchIn(line) -> "*$line"
            opensList -> "  $line"
            // Any other already-indented line: promote de-indents it, so
            // demote re-indents it, keeping the pair inverse.
            line.startsWith(" ") -> "  $line"
            else -> return edit
        }
        val shift = newLine.length - line.length
        val newText = text.substring(0, ls) + newLine + text.substring(le)
        return ToolbarEdit.caret(newText, cursor + shift)
    }

    /** SPEC 17.7 move-up: swap the caret line with the one above (no-op on the
     * first line), keeping the caret at the same column. */
    private fun moveUp(edit: ToolbarEdit): ToolbarEdit {
        val text = edit.text
        val cursor = edit.selStart.coerceIn(0, text.length)
        val (ls, le) = lineBounds(text, cursor)
        if (ls == 0) return edit
        val prevStart = text.lastIndexOf('\n', ls - 2) + 1
        val prevEnd = ls - 1
        val cur = text.substring(ls, le)
        val prev = text.substring(prevStart, prevEnd)
        val newText = text.substring(0, prevStart) + cur + "\n" + prev + text.substring(le)
        val col = cursor - ls
        return ToolbarEdit.caret(newText, prevStart + col)
    }

    /** SPEC 17.7 move-down: swap the caret line with the one below (no-op on
     * the last line), keeping the caret at the same column. */
    private fun moveDown(edit: ToolbarEdit): ToolbarEdit {
        val text = edit.text
        val cursor = edit.selStart.coerceIn(0, text.length)
        val (ls, _) = lineBounds(text, cursor)
        val le = text.indexOf('\n', cursor)
        if (le == -1) return edit
        val nextStart = le + 1
        val nextEnd = text.indexOf('\n', nextStart).let { if (it == -1) text.length else it }
        val cur = text.substring(ls, le)
        val next = text.substring(nextStart, nextEnd)
        val newText = text.substring(0, ls) + next + "\n" + cur + text.substring(nextEnd)
        val col = cursor - ls
        val newLineStart = ls + next.length + 1
        return ToolbarEdit.caret(newText, newLineStart + col)
    }
}
