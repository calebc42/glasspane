// SPDX-License-Identifier: GPL-3.0-or-later
// P1 SPEC 19.5: the display-side annotation model. Scalar→UTF-16 conversion
// across an astral pair, the bounded shift window, all 15 contract roles
// resolving, an unregistered role staying inert, the diagnostics content gate,
// and the composition rule (Emacs runs win, the tokenizer is the fallback).
// Pure Kotlin, no Compose harness — the SyntaxHighlightTest shape.
package com.calebc42.ebp.companion.render

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontWeight
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorAnnotationsTest {

    private val colors = SyntaxColors.forBackground(dark = true)
    private val diagColors = DiagnosticColors.forBackground(dark = true)

    private fun run(start: Int, end: Int, role: String) = buildJsonObject {
        put("start", start); put("end", end); put("role", role)
    }

    private fun fontifyParams(vararg runs: JsonObject, seq: Long = 0) =
        buildJsonObject {
            put("editor_id", "body"); put("session", "s"); put("seq", seq)
            put("runs", JsonArray(runs.toList()))
        }

    private fun diag(start: Int, end: Int, severity: String = "error") =
        buildJsonObject {
            put("start", start); put("end", end)
            put("severity", severity); put("message", "m")
        }

    private fun diagParams(vararg d: JsonObject, seq: Long = 0) = buildJsonObject {
        put("editor_id", "body"); put("session", "s"); put("seq", seq)
        put("diagnostics", JsonArray(d.toList()))
    }

    // ------------------------------------------------ scalar ↔ UTF-16

    @Test
    fun scalarOffsetsConvertAcrossAnAstralPair() {
        // "a😀b": 3 scalars, 4 UTF-16 units. A run over the trailing "b" is
        // scalars [2,3) and UTF-16 [3,4) — the exact off-by-one that puts a
        // colour on the wrong character.
        val text = "a😀b"
        assertEquals(3, text.codePointCount(0, text.length))
        val set = parseFontify(fontifyParams(run(2, 3, "keyword")), text)!!
        assertEquals(listOf(FontifyRun(3, 4, "keyword")), set.runs)
        // Sequential conversion is order-independent for a sorted batch and
        // restarts cleanly for one that is not.
        val idx = ScalarIndex(text)
        assertEquals(0, idx.toUtf16(0))
        assertEquals(1, idx.toUtf16(1))
        assertEquals(3, idx.toUtf16(2))
        assertEquals(4, idx.toUtf16(3))
        assertEquals(1, idx.toUtf16(1))   // backwards: restarts, still right
    }

    @Test
    fun outOfRangeAndEmptyRunsAreDropped() {
        val text = "hello"
        val set = parseFontify(fontifyParams(
            run(0, 2, "keyword"), run(3, 3, "string"), run(4, 900, "comment")), text)!!
        // The zero-width run vanishes; the over-long one clamps to the text.
        assertEquals(listOf(FontifyRun(0, 2, "keyword"), FontifyRun(4, 5, "comment")),
            set.runs)
    }

    @Test
    fun aBatchWithNoArrayIsNotABatch() {
        assertNull(parseFontify(buildJsonObject { put("session", "s") }, "x"))
        assertNull(parseDiagnostics(buildJsonObject { put("session", "s") }, "x"))
        assertNull(parseEldoc(buildJsonObject { put("session", "s") }))
        // An EMPTY batch is a real batch — it is how Emacs clears squiggles.
        assertEquals(0, parseFontify(fontifyParams(), "x")!!.runs.size)
        assertEquals(0, parseDiagnostics(diagParams(), "x")!!.diags.size)
        assertEquals("", parseEldoc(buildJsonObject { put("text", "") })!!.text)
    }

    // --------------------------------------------------------- shifting

    @Test
    fun shiftRunsSurvivesOneSmallEdit() {
        val runs = listOf(FontifyRun(0, 5, "comment"), FontifyRun(8, 12, "string"))
        // Insert 2 units at 6, between the runs: the first is untouched, the
        // second slides by the delta.
        val after = shiftRuns(runs, TextSplice(6, 0, "xy"))
        assertEquals(listOf(FontifyRun(0, 5, "comment"), FontifyRun(10, 14, "string")),
            after)
        // An edit INSIDE a run stretches it: text typed mid-comment stays
        // comment-coloured rather than punching a hole.
        assertEquals(listOf(FontifyRun(0, 8, "comment")),
            shiftRuns(listOf(FontifyRun(0, 5, "comment")), TextSplice(2, 0, "abc")))
        // A deletion that swallows a run drops it entirely.
        assertEquals(emptyList<FontifyRun>(),
            shiftRuns(listOf(FontifyRun(2, 4, "string")), TextSplice(0, 10, "")))
    }

    @Test
    fun shiftWindowIsBoundedAndFallsBackToTheTokenizer() {
        val base = "(defun f () nil)"
        val set = FontifySet("s", 0, base, listOf(FontifyRun(1, 6, "keyword")))
        // One character typed: still inside the window, Emacs's run applies.
        val small = base + "x"
        val shifted = annotationSpans(small, set, null, "elisp", colors, diagColors)
        assertTrue(shifted.any { it.item.color == colors.keyword && it.start == 1 })
        // A paste past FONTIFY_SHIFT_MAX_EDIT abandons the runs and the client
        // tokenizer takes over — colour that is approximately right beats runs
        // that are precisely wrong.
        val huge = base + "y".repeat(FONTIFY_SHIFT_MAX_EDIT + 1)
        val fallback = annotationSpans(huge, set, null, "elisp", colors, diagColors)
        assertTrue(fallback.isNotEmpty())
        assertEquals(emptyList<Any>(),
            annotationSpans(huge, set, null, "", colors, diagColors))
    }

    // ------------------------------------------------------------ roles

    @Test
    fun allFifteenContractRolesResolveAndUnknownIsInert() {
        assertEquals(15, SYNTAX_ROLES.size)
        for (role in SYNTAX_ROLES)
            assertNotNull("role $role must resolve", roleStyle(role, colors))
        // The three that had no SyntaxColors field before this rung.
        assertEquals(colors.variable, roleStyle("variable", colors)!!.color)
        assertEquals(colors.type, roleStyle("type", colors)!!.color)
        assertEquals(colors.operator, roleStyle("operator", colors)!!.color)
        // `preprocessor` is the pre-existing alias onto the `meta` field.
        assertEquals(colors.meta, roleStyle("preprocessor", colors)!!.color)
        assertEquals(FontWeight.Bold, roleStyle("keyword", colors)!!.fontWeight)
        // SPEC 18.4: an unregistered role is IGNORED, never guessed at — and it
        // draws nothing rather than falling through to the tokenizer.
        assertNull(roleStyle("kaboom", colors))
        val set = FontifySet("s", 0, "hello", listOf(FontifyRun(0, 5, "kaboom")))
        assertEquals(emptyList<Any>(),
            annotationSpans("hello", set, null, "elisp", colors, diagColors))
    }

    // ------------------------------------------------------ composition

    @Test
    fun emacsRunsWinAndTheTokenizerIsTheFallback() {
        val src = "(defun f () nil)"
        // No batch at all: the client tokenizer colours, which is what keeps an
        // editor with `syntax` but no attached buffer (the hub REPL) alive.
        val tokenized = annotationSpans(src, null, null, "elisp", colors, diagColors)
        assertTrue(tokenized.isNotEmpty())
        // With a batch for this exact text, ONLY the batch's runs draw.
        val set = FontifySet("s", 0, src, listOf(FontifyRun(0, 3, "string")))
        val fromEmacs = annotationSpans(src, set, null, "elisp", colors, diagColors)
        assertEquals(listOf(AnnotatedString.Range(
            SpanStyle(color = colors.string), 0, 3)), fromEmacs)
    }

    @Test
    fun diagnosticsGateOnContentAndDrawOverBoth() {
        val src = "hello"
        val diags = parseDiagnostics(diagParams(diag(0, 2)), src)!!
        val spans = annotationSpans(src, null, diags, "", colors, diagColors)
        assertEquals(1, spans.size)
        assertEquals(diagColors.error.copy(alpha = 0.15f), spans[0].item.background)
        // The moment the text moves, the squiggle is withheld: mis-placed is
        // worse than absent, and there is no shift path for diagnostics.
        assertEquals(emptyList<Any>(),
            annotationSpans("hello!", null, diags, "", colors, diagColors))
        // A zero-width diagnostic still marks one character.
        val point = parseDiagnostics(diagParams(diag(5, 5)), src)!!
        assertEquals(listOf(DiagRange(4, 5, "error", "m")), point.diags)
    }

    // ------------------------------------------------------- transform

    @Test
    fun transformationIsIdentityAndMemoized() {
        val src = "(defun f () nil)"
        val t = AnnotationTransformation(null, null, "elisp", colors, diagColors)
        val first = t.filter(AnnotatedString(src))
        // Identity: the character count is untouched, so cursor/selection/IME
        // behave exactly as on a plain field.
        assertEquals(src, first.text.text)
        assertEquals(7, first.offsetMapping.originalToTransformed(7))
        // `filter` re-runs per LAYOUT pass; the same text must not re-tokenize.
        val second = t.filter(AnnotatedString(src))
        assertTrue(first.text === second.text)
        // A different text is a real miss.
        assertTrue(t.filter(AnnotatedString(src + "x")).text !== second.text)
    }

    @Test
    fun textSpliceNeverCutsASurrogatePair() {
        // Replacing the emoji: the boundaries widen to whole UTF-16 pairs
        // rather than splitting one, which would be unrepresentable.
        val s = textSplice("a😀b", "a!b")!!
        assertEquals(1, s.start)
        assertEquals(2, s.deleted)
        assertEquals("!", s.inserted)
        assertNull(textSplice("same", "same"))
    }

    // -------------------------------------------------------- doc line

    @Test
    fun diagnosticAtPicksTheCaretAndOutranksBySeverity() {
        val src = "hello world"
        // Overlapping entries: the caret sits in both, the ERROR wins so a
        // real problem is never hidden behind a hint.
        val diags = parseDiagnostics(
            diagParams(diag(0, 5, "hint"), diag(0, 5, "error")), src)!!
        assertEquals("error", diagnosticAt(diags, src, 2)!!.severity)
        // Outside every range: nothing to say, and eldoc gets the line.
        assertNull(diagnosticAt(diags, src, 9))
        // Same content gate as the squiggles: a batch whose text has moved on
        // describes offsets that no longer mean what they said.
        assertNull(diagnosticAt(diags, "hello world!", 2))
        assertNull(diagnosticAt(null, src, 2))
    }
}
