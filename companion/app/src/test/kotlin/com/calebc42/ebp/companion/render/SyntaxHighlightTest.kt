// SPDX-License-Identifier: GPL-3.0-or-later
// W9-h2 SPEC 18.4: best-effort syntax fontification. The tokenizer emits
// non-empty span sets for each supported language and never changes the source
// length (identity transform); emacsSyntaxColors reads each pushed role's
// SyntaxStyle `fg`, merging holes from the polarity fallback.
package com.calebc42.ebp.companion.render

import androidx.compose.ui.graphics.Color
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SyntaxHighlightTest {

    private val c = SyntaxColors.forBackground(dark = true)

    @Test
    fun highlightsEachSupportedLanguage() {
        assertTrue(highlightSpans("elisp", "(defun f (x) ;; c\n  \"s\")", c).isNotEmpty())
        assertTrue(highlightSpans("python", "def f():\n  return 'x'  # c", c).isNotEmpty())
        assertTrue(highlightSpans("rust", "fn main() { let x = 1; }", c).isNotEmpty())
        assertTrue(highlightSpans("org", "* TODO heading :tag:\n- item", c).isNotEmpty())
        // An unknown language degrades to no styles, never throws.
        assertEquals(emptyList<Any>(), highlightSpans("brainfuck", "+++.", c))
    }

    @Test
    fun elispKeywordAndCommentAreColoured() {
        val spans = highlightSpans("elisp", "(defun f () nil) ; done", c)
        // The `defun` keyword and the `;` comment both produce coloured spans.
        assertTrue(spans.any { it.item.color == c.keyword })
        assertTrue(spans.any { it.item.color == c.comment })
    }

    @Test
    fun transformationPreservesLength() {
        val src = androidx.compose.ui.text.AnnotatedString("(let ((x 1)) x)")
        val out = SyntaxTransformation("elisp", c).filter(src)
        assertEquals(src.text.length, out.text.text.length)
    }

    @Test
    fun highlightingDoesNotStopAtTwentyThousandChars() {
        // LD-7: the tokenizers silently stopped at a 20,000-char cap, leaving
        // the tail of any larger document permanently unstyled. With
        // max_editor_bytes at the 65536 floor bounding every synchronized
        // document, the whole text is tokenized.
        val src = "x".repeat(20_100) + "\n;; tail comment\n(defun tail ())\n"
        val spans = highlightSpans("elisp", src, c)
        assertTrue(spans.any { it.start > 20_000 })
    }

    @Test
    fun emacsSyntaxColorsOverlaysFgAndKeepsFallback() {
        val fallback = SyntaxColors.forBackground(dark = false)
        val payload = buildJsonObject {
            putJsonObject("keyword") {
                put("fg", "#ff0000")
                put("italic", true)
            }
            put("string", "#00ff00") // lenient: a bare color string is accepted
        }
        val merged = emacsSyntaxColors(payload, fallback)
        assertEquals(Color(0xFFFF0000), merged.keyword)
        assertEquals(Color(0xFF00FF00), merged.string)
        // Un-pushed roles keep the fallback.
        assertEquals(fallback.comment, merged.comment)
        assertNotEquals(fallback.keyword, merged.keyword)
        // A null map is the plain fallback.
        assertEquals(fallback, emacsSyntaxColors(null, fallback))
    }

    @Test
    fun pushedHeadingRecoloursTheWholeRainbowUniformly() {
        val merged = emacsSyntaxColors(
            buildJsonObject { putJsonObject("heading") { put("fg", "#123456") } },
            SyntaxColors.forBackground(dark = true))
        assertTrue(merged.heading.all { it == Color(0xFF123456) })
    }

    // Amendment #126 option B: registered roles only.
    @Test
    fun tagDrivesOrgTagsAndPreprocessorDrivesMetaLines() {
        val fallback = SyntaxColors.forBackground(dark = true)
        val merged = emacsSyntaxColors(
            buildJsonObject {
                putJsonObject("tag") { put("fg", "#caa6df") }
                putJsonObject("preprocessor") { put("fg", "#ff7f9f") }
            },
            fallback)
        assertEquals(Color(0xFFCAA6DF), merged.tag)
        assertEquals(Color(0xFFFF7F9F), merged.meta)
        // The live Emacs payload: an org :work: tag renders in the TAG
        // color, not the preprocessor pink.
        val spans = highlightSpans("org", "* Heading :work:", merged)
        assertTrue(spans.any { it.item.color == merged.tag })
        assertTrue(spans.none { it.item.color == Color(0xFFFF7F9F) })
    }

    @Test
    fun unregisteredMetaAndParenAreIgnored() {
        val fallback = SyntaxColors.forBackground(dark = false)
        val merged = emacsSyntaxColors(
            buildJsonObject {
                putJsonObject("meta") { put("fg", "#111111") }
                putJsonObject("paren") { put("fg", "#222222") }
            },
            fallback)
        // SPEC 18.4: unknown roles MUST be ignored — meta keeps the
        // static value and the paren rainbow keeps its depth cue.
        assertEquals(fallback.meta, merged.meta)
        assertEquals(fallback.paren, merged.paren)
        assertTrue(merged.paren.size > 1)
    }
}
