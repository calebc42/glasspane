// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.ebp.companion.render

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation

/** §17.4 `text_input.mask`: a display template over the STORED value.
 *
 * Every `#` consumes one stored character; everything else is literal filler
 * that displays but never enters `value` or `state.changed` — the wire form
 * of upstream's phone-number OutputTransformation, where formatting happens
 * locally, per keystroke, and the round trip never sees the parentheses.
 *
 * Stored text beyond the mask's `#` capacity displays raw after the template,
 * mapped 1:1, so a mask never TRUNCATES a value it cannot format (`max_length`
 * is the member that limits length). Both offset mappings are total functions
 * over their domains — Compose crashes on a partial one. */
internal class MaskTransformation(private val mask: String) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val raw = text.text
        val out = StringBuilder()
        // transformedAt[o] = transformed offset where original offset o lands.
        val transformedAt = IntArray(raw.length + 1)
        var consumed = 0
        for (ch in mask) {
            if (consumed >= raw.length) break
            if (ch == '#') {
                transformedAt[consumed] = out.length
                out.append(raw[consumed])
                consumed++
            } else out.append(ch)
        }
        // Anything past the template (or a template with fewer `#` than
        // characters) rides raw, 1:1.
        for (i in consumed until raw.length) {
            transformedAt[i] = out.length
            out.append(raw[i])
        }
        transformedAt[raw.length] = out.length
        val transformed = out.toString()
        val mapping = object : OffsetMapping {
            override fun originalToTransformed(offset: Int): Int =
                transformedAt[offset.coerceIn(0, raw.length)]
            override fun transformedToOriginal(offset: Int): Int {
                val t = offset.coerceIn(0, transformed.length)
                // The original offset is how many stored characters sit at or
                // before t — the count of transformed positions below t that
                // carry a stored character.
                var o = raw.length
                for (i in 0..raw.length) {
                    if (transformedAt[i] >= t) { o = i; break }
                }
                return o
            }
        }
        return TransformedText(AnnotatedString(transformed), mapping)
    }
}
