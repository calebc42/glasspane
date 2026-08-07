// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 19.5 annotations: the display-side model for `fontify.show' and
// `diagnostics.show'. Emacs sends ROLE NAMES (the contract's fixed 15) and
// SCALAR positions; Compose wants SpanStyles and UTF-16 offsets, so this file
// is the whole translation — plus the shift that keeps a stamped annotation
// usable across the keystroke that outran it.
//
// Re-expressed from POC 1's EditorSync.kt, NOT ported: POC 1 carried literal
// colors per run and applied them through an OutputTransformation over a
// TextFieldState. This tree is entirely TextFieldValue + VisualTransformation,
// and §19.5 carries roles rather than colors — so only the SHAPE of POC 1's
// solution survives (the sequential index, the bounded shift window, the
// content gate on diagnostics).
//
// Validation is NOT repeated here. The wire engine already refuses a batch
// whose session or seq does not match, whose ranges fall outside the
// synchronized text, or whose fontify runs are unsorted or overlapping —
// whole-batch, with a 1201 log.error. What arrives has been checked.
package com.calebc42.ebp.companion.render

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextDecoration
import kotlinx.serialization.json.JsonObject

/** One `fontify.show` run, converted to UTF-16 offsets into the text it was
 * computed over. [role] is one of the contract's 15 `syntax_roles`; an
 * unregistered name is kept as-is and styles nothing (SPEC 18.4: unknown roles
 * MUST be ignored, never guessed at). */
data class FontifyRun(val start: Int, val end: Int, val role: String)

/** One `diagnostics.show` entry, UTF-16. [severity] is error|warning|info|hint. */
data class DiagRange(
    val start: Int,
    val end: Int,
    val severity: String,
    val message: String,
)

/**
 * A whole fontify batch, pinned to the exact [text] its offsets index.
 *
 * The text is carried rather than re-derived because that is what makes the
 * batch usable at all: [session] and [seq] say WHICH document state Emacs
 * described, but a field whose text has moved on needs to know HOW far, and
 * only the base text answers that. Content-matching also means undoing back to
 * synced text restores exact Emacs colours instantly, with no round trip.
 */
class FontifySet(
    val session: String,
    val seq: Long,
    val text: String,
    val runs: List<FontifyRun>,
)

/** A whole diagnostics batch, pinned to the text its offsets index. */
class DiagSet(
    val session: String,
    val seq: Long,
    val text: String,
    val diags: List<DiagRange>,
)

/** The `eldoc.show` line, pinned to the state it describes. */
class EldocLine(val session: String, val seq: Long, val text: String)

/**
 * Sequential scalar → UTF-16 offset converter.
 *
 * SPEC 19.1 positions count Unicode SCALARS; Compose counts UTF-16 units, and
 * the two differ the moment an astral character appears. Batch offsets arrive
 * sorted, so each conversion walks forward from the previous one and a whole
 * batch converts in one pass instead of rescanning from the string head per
 * entry. An out-of-order target restarts rather than misreporting.
 *
 * Targets must already be clamped to the text's scalar count.
 */
class ScalarIndex(private val text: String) {
    private var scalar = 0
    private var utf16 = 0

    fun toUtf16(targetScalar: Int): Int {
        if (targetScalar < scalar) {
            scalar = 0
            utf16 = 0
        }
        utf16 = text.offsetByCodePoints(utf16, targetScalar - scalar)
        scalar = targetScalar
        return utf16
    }
}

/** One UTF-16 text splice: replace [start, start+deleted) with [inserted]. */
data class TextSplice(val start: Int, val deleted: Int, val inserted: String)

/**
 * Minimal single-splice diff via common prefix/suffix, in UTF-16 units.
 *
 * Deliberately NOT `EditorSession.diff`: that one speaks scalars because it
 * feeds the wire, and everything here is already UTF-16. Boundaries are nudged
 * off surrogate pairs — widening a splice by one unit is always correct;
 * splitting a code point is never representable. Null when the two contents are
 * equal.
 */
fun textSplice(old: CharSequence, new: CharSequence): TextSplice? {
    if (old.contentEquals(new)) return null
    var p = 0
    val maxP = minOf(old.length, new.length)
    while (p < maxP && old[p] == new[p]) p++
    if (p > 0 && old[p - 1].isHighSurrogate()) p--
    var so = old.length
    var sn = new.length
    while (so > p && sn > p && old[so - 1] == new[sn - 1]) {
        so--
        sn--
    }
    if (so < old.length && old[so].isLowSurrogate()) {
        so++
        sn++
    }
    return TextSplice(p, so - p, new.subSequence(p, sn).toString())
}

/**
 * Text more than this many changed UTF-16 units away from the batch's base
 * falls back to the client tokenizer rather than shifting.
 *
 * Keystrokes, IME batches and toolbar inserts sit far below it; a big paste is
 * where approximate re-tokenizing beats a large wrongly-placed run set.
 */
const val FONTIFY_SHIFT_MAX_EDIT = 256

/**
 * [runs] shifted across one local edit, so Emacs's colours survive the gap
 * between a keystroke and the next push instead of flapping to the client
 * palette on every character.
 *
 * Runs before the splice keep their offsets; runs after it slide by the length
 * delta; a run the edit lands inside stretches over the typed text, so
 * characters typed mid-comment stay comment-coloured. Runs the deletion
 * swallowed drop out, and a run clipped at one end keeps its survivor. This is
 * cosmetic and can be wrong (typing a quote will not restyle the rest of the
 * line) — exactly as wrong as the tokenizer it stands in for, but STABLE, and
 * Emacs's next push corrects both.
 */
fun shiftRuns(runs: List<FontifyRun>, s: TextSplice): List<FontifyRun> {
    val delta = s.inserted.length - s.deleted
    val delEnd = s.start + s.deleted
    return buildList {
        for (r in runs) {
            val b = when {
                r.start < s.start -> r.start
                r.start >= delEnd -> r.start + delta
                else -> s.start + s.inserted.length
            }
            val e = when {
                r.end <= s.start -> r.end
                r.end >= delEnd -> r.end + delta
                else -> s.start
            }
            if (e > b) add(if (b == r.start && e == r.end) r else r.copy(start = b, end = e))
        }
    }
}

/** The contract's fixed `syntax_roles` set (ebp/contract.json). A role outside
 * it is inert by construction — [roleStyle] returns null and the run draws
 * nothing rather than borrowing a neighbouring colour. */
val SYNTAX_ROLES = listOf(
    "comment", "string", "keyword", "function", "constant", "variable",
    "type", "number", "operator", "preprocessor", "heading", "link",
    "todo", "done", "tag")

/**
 * A §19.5 role resolved against the live palette, or null for an unregistered
 * name. The weight/slant/underline decisions are this side's, not Emacs's:
 * §19.5 sends a role, and how a role LOOKS is the Companion's business — the
 * same division the client tokenizer already works to.
 */
fun roleStyle(role: String, c: SyntaxColors): SpanStyle? = when (role) {
    "comment" -> SpanStyle(color = c.comment, fontStyle = FontStyle.Italic)
    "string" -> SpanStyle(color = c.string)
    "keyword" -> SpanStyle(color = c.keyword, fontWeight = FontWeight.Bold)
    "function" -> SpanStyle(color = c.function)
    "constant" -> SpanStyle(color = c.constant)
    "variable" -> SpanStyle(color = c.variable)
    "type" -> SpanStyle(color = c.type)
    "number" -> SpanStyle(color = c.number)
    "operator" -> SpanStyle(color = c.operator)
    "preprocessor" -> SpanStyle(color = c.meta)
    "heading" -> SpanStyle(color = c.heading.first(), fontWeight = FontWeight.Bold)
    "link" -> SpanStyle(color = c.link, textDecoration = TextDecoration.Underline)
    "todo" -> SpanStyle(color = c.todo, fontWeight = FontWeight.Bold)
    "done" -> SpanStyle(color = c.done, fontWeight = FontWeight.Bold)
    "tag" -> SpanStyle(color = c.tag)
    else -> null
}

/** Severity colours for the diagnostic underlay. Supplied by the composable so
 * `error` is the scheme's real error colour; the fallback keeps this file
 * testable without a Compose theme. */
data class DiagnosticColors(
    val error: Color,
    val warning: Color,
    val info: Color,
    val hint: Color,
) {
    fun forSeverity(severity: String): Color = when (severity) {
        "error" -> error
        "warning" -> warning
        "info" -> info
        "hint" -> hint
        else -> warning
    }

    companion object {
        fun forBackground(dark: Boolean): DiagnosticColors =
            if (dark) DiagnosticColors(
                error = Color(0xFFBF616A), warning = Color(0xFFEBCB8B),
                info = Color(0xFF81A1C1), hint = Color(0xFF616E88))
            else DiagnosticColors(
                error = Color(0xFFA01F2C), warning = Color(0xFF9A7A1E),
                info = Color(0xFF3B5B8C), hint = Color(0xFF7B88A1))
    }
}

/** A phone has no wavy underline primitive, so a diagnostic reads as an
 * underline plus a translucent severity wash — legible at a glance and
 * survivable under a caret. */
fun diagnosticStyle(severity: String, c: DiagnosticColors): SpanStyle {
    val tint = c.forSeverity(severity)
    return SpanStyle(
        textDecoration = TextDecoration.Underline,
        background = tint.copy(alpha = 0.15f))
}

/** SPEC 19.5 `fontify.show` → runs against [text], the shadow those scalar
 * offsets index. Null when the payload carries no `runs` array. */
fun parseFontify(params: JsonObject, text: String): FontifySet? {
    val arr = params.arrOrNull("runs") ?: return null
    val total = text.codePointCount(0, text.length)
    val idx = ScalarIndex(text)
    val runs = buildList {
        for (e in arr) {
            val r = e as? JsonObject ?: continue
            val startS = (r.numOrNullAt("start") ?: continue).coerceIn(0, total)
            val endS = (r.numOrNullAt("end") ?: continue).coerceIn(startS, total)
            val start = idx.toUtf16(startS)
            val end = idx.toUtf16(endS)
            if (end <= start) continue
            add(FontifyRun(start, end, r.stringOr("role")))
        }
    }
    return FontifySet(params.stringOr("session"), params.longOrZero("seq"), text, runs)
}

/** SPEC 19.5 `diagnostics.show` → ranges against [text]. Null when the payload
 * carries no `diagnostics` array. */
fun parseDiagnostics(params: JsonObject, text: String): DiagSet? {
    val arr = params.arrOrNull("diagnostics") ?: return null
    val total = text.codePointCount(0, text.length)
    val idx = ScalarIndex(text)
    val diags = buildList {
        for (e in arr) {
            val d = e as? JsonObject ?: continue
            val startS = (d.numOrNullAt("start") ?: continue).coerceIn(0, total)
            val endS = (d.numOrNullAt("end") ?: continue).coerceIn(startS, total)
            var start = idx.toUtf16(startS)
            var end = idx.toUtf16(endS)
            // A zero-width diagnostic still deserves a visible mark: flymake
            // reports "here", and an empty span draws nothing at all.
            if (end == start) {
                if (end < text.length) end++ else if (start > 0) start--
            }
            if (end > start)
                add(DiagRange(start, end, d.stringOr("severity", "warning"),
                    d.stringOr("message")))
        }
    }
    return DiagSet(params.stringOr("session"), params.longOrZero("seq"), text, diags)
}

/** SPEC 19.5 `eldoc.show` → the documentation line. `text` is REQUIRED by the
 * wire validator, so its absence here means a malformed payload, not a clear. */
fun parseEldoc(params: JsonObject): EldocLine? {
    val text = params.stringOrNull("text") ?: return null
    return EldocLine(params.stringOr("session"), params.longOrZero("seq"), text)
}

private fun JsonObject.numOrNullAt(k: String): Int? = this[k]?.numOrNull()?.toInt()

private fun JsonObject.longOrZero(k: String): Long = this[k]?.numOrNull()?.toLong() ?: 0L

/**
 * Every span for [src]: Emacs's runs where they apply, the client tokenizer
 * where they do not, and diagnostics on top of whichever won.
 *
 * The composition is the point. Emacs's font-lock is the user's real theme
 * over every mode Emacs can highlight, so it wins wherever it is usable — the
 * batch's own text, or within one small edit of it via [shiftRuns]. The
 * tokenizer is the FALLBACK, not the loser: first paint, big pastes, and every
 * editor that has a `syntax` language but no attached buffer at all (the hub
 * REPL is exactly that) still colour. Diagnostics draw over both under a strict
 * content gate — a squiggle two characters off is worse than no squiggle.
 */
fun annotationSpans(
    src: String,
    fontify: FontifySet?,
    diags: DiagSet?,
    language: String,
    colors: SyntaxColors,
    diagColors: DiagnosticColors,
): List<AnnotatedString.Range<SpanStyle>> {
    val n = src.length
    val out = mutableListOf<AnnotatedString.Range<SpanStyle>>()
    val runs = fontify?.let { f ->
        when (val sp = textSplice(f.text, src)) {
            null -> f.runs
            else ->
                if (sp.deleted + sp.inserted.length <= FONTIFY_SHIFT_MAX_EDIT)
                    shiftRuns(f.runs, sp)
                else null
        }
    }
    if (runs != null) {
        for (r in runs) {
            val style = roleStyle(r.role, colors) ?: continue
            val s = r.start.coerceIn(0, n)
            val e = r.end.coerceIn(s, n)
            if (e > s) out.add(AnnotatedString.Range(style, s, e))
        }
    } else if (language.isNotEmpty()) {
        out.addAll(highlightSpans(language, src, colors))
    }
    if (diags != null && diags.text == src) {
        for (d in diags.diags) {
            val s = d.start.coerceIn(0, n)
            val e = d.end.coerceIn(s, n)
            if (e > s) out.add(AnnotatedString.Range(diagnosticStyle(d.severity, diagColors), s, e))
        }
    }
    return out
}

/**
 * The diagnostic the caret is standing in, or null.
 *
 * The doc line shows ONE thing, and a diagnostic under the caret outranks
 * documentation: a user who moved the caret onto a squiggle is asking what is
 * wrong there, not what the symbol means. The same content gate as the
 * squiggles applies — a batch whose text has moved on describes offsets that
 * no longer mean what they said, and the wrong error is worse than none.
 * Severity breaks a tie, so an error is never hidden behind a hint.
 */
fun diagnosticAt(diags: DiagSet?, src: String, caret: Int): DiagRange? {
    if (diags == null || diags.text != src) return null
    return diags.diags
        .filter { caret >= it.start && caret <= it.end }
        .minByOrNull { severityRank(it.severity) }
}

private fun severityRank(severity: String): Int = when (severity) {
    "error" -> 0
    "warning" -> 1
    "info" -> 2
    else -> 3
}

/**
 * The editor's whole styling pipeline as one identity [VisualTransformation]:
 * never changes the character count, so cursor, selection and IME behave
 * exactly as on a plain field.
 *
 * MEMOIZED, and that is not an optimization detail — it is why this shape is
 * viable at all. `filter` re-runs per LAYOUT pass rather than per text change
 * (POC 1 moved off VisualTransformation for precisely this reason, but this
 * tree has no TextFieldState anywhere and cannot follow it there). Re-running
 * the tokenizer over a 64 KiB buffer on every scroll frame would jank; the
 * cache is keyed on the text plus the two batches, which together are the
 * whole input, so a repeat pass costs one string comparison.
 */
class AnnotationTransformation(
    private val fontify: FontifySet?,
    private val diags: DiagSet?,
    private val language: String,
    private val colors: SyntaxColors,
    private val diagColors: DiagnosticColors,
) : VisualTransformation {

    private var cachedSrc: String? = null
    private var cached: AnnotatedString? = null

    override fun filter(text: AnnotatedString): TransformedText {
        val src = text.text
        val hit = cached?.takeIf { cachedSrc == src }
        val styled = hit ?: run {
            val spans = annotationSpans(src, fontify, diags, language, colors, diagColors)
            val a = if (spans.isEmpty()) AnnotatedString(src)
                else AnnotatedString(src, spanStyles = spans)
            cachedSrc = src
            cached = a
            a
        }
        return TransformedText(styled, OffsetMapping.Identity)
    }
}
