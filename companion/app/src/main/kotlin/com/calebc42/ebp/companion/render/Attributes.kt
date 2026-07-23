// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 16.5 universal node attributes, applied ONCE at the dispatcher (a
// port-and-centralize of poc-v1's per-node scatter): padding/pad, sizes and
// min/max bounds, fill_fraction, aspect_ratio, bg, corner, border, alpha,
// clip — in the SPEC's visual-op order corner → clip → bg → border. `weight`
// and `align_self` need the parent Row/Column scope and are applied by the
// container cases. Out-of-range numbers are SKIPPED, not applied: wire
// validation already rejected invalid content, so anything reaching here is
// either valid or a nonconforming sender the renderer must survive without
// throwing (a composition throw blanks the whole surface — poc-v1's safe*
// philosophy, kept because the clamps are pure and JVM-testable).
package com.calebc42.ebp.companion.render

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject

// ------------------------------------------------------- pure clamps (JVM)

/** Non-negative finite dp, else null (skip the modifier, never throw). */
internal fun safeDp(v: Double): Float? =
    v.toFloat().takeIf { it.isFinite() && it >= 0f }

internal fun safeFraction(v: Double): Float? =
    v.toFloat().takeIf { it.isFinite() && it > 0f && it <= 1f }

internal fun safeAspect(v: Double): Float? =
    v.toFloat().takeIf { it.isFinite() && it > 0f }

internal fun safeAlpha(v: Double): Float? =
    v.toFloat().takeIf { it.isFinite() && it >= 0f && it <= 1f }

/**
 * Stable, unique reconciliation keys for a lazy container's children (ported
 * from poc-v1): prefer explicit `key`, then a stateful child's `id`, else a
 * namespaced index; duplicates disambiguate with #n so Compose never sees a
 * duplicate key (which would crash the list). Pure, JVM-testable — and the
 * key precedence mirrors §16.1 presentation identity.
 */
internal fun lazyChildKeys(children: JSONArray): List<String> {
    val seen = HashMap<String, Int>()
    return (0 until children.length()).map { i ->
        val c = children.optJSONObject(i)
        val explicit = c?.optString("key").orEmpty()
        val id = c?.optString("id").orEmpty()
        val base = when {
            explicit.isNotEmpty() -> "k:$explicit"
            id.isNotEmpty() -> "id:$id"
            else -> "i:$i"
        }
        val n = seen.getOrDefault(base, 0)
        seen[base] = n + 1
        if (n == 0) base else "$base#$n"
    }
}

/** §16.1 presentation identity for a child at index i under `parentPath`:
 * key > id > tree path including the type discriminator. Pure. */
internal fun identityPath(parentPath: String, node: JSONObject?, i: Int): String {
    val key = node?.optString("key").orEmpty()
    val id = node?.optString("id").orEmpty()
    return when {
        key.isNotEmpty() -> "$parentPath/k:$key"
        id.isNotEmpty() -> "$parentPath/id:$id"
        else -> "$parentPath/$i:${node?.optString("t").orEmpty()}"
    }
}

// ---------------------------------------------------- the §16.5 modifier

/** The node's corner shape: a number or per-corner object; 0/absent is
 * rectangular. Exposed so containers can stroke borders with the same shape. */
internal fun cornerShape(node: JSONObject): Shape {
    val c = node.opt("corner") ?: return RectangleShape
    return when (c) {
        is Number -> safeDp(c.toDouble())?.takeIf { it > 0f }
            ?.let { RoundedCornerShape(it.dp) } ?: RectangleShape
        is JSONObject -> {
            fun side(k: String): Dp = safeDp(c.optDouble(k, 0.0))?.dp ?: 0.dp
            RoundedCornerShape(side("top_start"), side("top_end"),
                side("bottom_end"), side("bottom_start"))
        }
        else -> RectangleShape
    }
}

/**
 * Apply the SPEC 16.5 universal attributes. Order inside: sizing and padding
 * first (layout), then the visual ops corner → clip → bg → border, then alpha.
 */
@Composable
internal fun Modifier.universal(node: JSONObject): Modifier {
    var m = this
    // padding / pad (per-side wins over its axis shorthand).
    val pad = node.optJSONObject("pad")
    if (pad != null) {
        fun side(specific: String, axis: String): Dp {
            val v = when {
                pad.has(specific) -> pad.optDouble(specific, 0.0)
                pad.has(axis) -> pad.optDouble(axis, 0.0)
                else -> node.optDouble("padding", 0.0)
            }
            return (safeDp(v) ?: 0f).dp
        }
        m = m.padding(start = side("start", "horizontal"), top = side("top", "vertical"),
            end = side("end", "horizontal"), bottom = side("bottom", "vertical"))
    } else if (node.has("padding")) {
        safeDp(node.optDouble("padding", 0.0))?.let { m = m.padding(it.dp) }
    }
    // Requested size + constraints.
    if (node.has("width")) safeDp(node.optDouble("width"))?.let { m = m.width(it.dp) }
    if (node.has("height")) safeDp(node.optDouble("height"))?.let { m = m.height(it.dp) }
    val minW = node.takeIf { it.has("min_width") }?.let { safeDp(it.optDouble("min_width")) }
    val maxW = node.takeIf { it.has("max_width") }?.let { safeDp(it.optDouble("max_width")) }
    if (minW != null || maxW != null)
        m = m.widthIn(min = minW?.dp ?: Dp.Unspecified, max = maxW?.dp ?: Dp.Unspecified)
    val minH = node.takeIf { it.has("min_height") }?.let { safeDp(it.optDouble("min_height")) }
    val maxH = node.takeIf { it.has("max_height") }?.let { safeDp(it.optDouble("max_height")) }
    if (minH != null || maxH != null)
        m = m.heightIn(min = minH?.dp ?: Dp.Unspecified, max = maxH?.dp ?: Dp.Unspecified)
    if (node.has("fill_fraction"))
        safeFraction(node.optDouble("fill_fraction"))?.let { m = m.fillMaxWidth(it) }
    if (node.has("aspect_ratio"))
        safeAspect(node.optDouble("aspect_ratio"))?.let { m = m.aspectRatio(it) }
    // Visual ops in SPEC order: corner shape, clipping, background, border.
    val shape = cornerShape(node)
    if (node.optBoolean("clip") && shape != RectangleShape) m = m.clip(shape)
    resolveColor(node.optString("bg").takeIf { it.isNotEmpty() })?.let {
        m = m.background(it, shape)
    }
    node.optJSONObject("border")?.let { b ->
        val width = (safeDp(b.optDouble("width", 1.0)) ?: 1f).dp
        val color = resolveColor(b.optString("color").takeIf { it.isNotEmpty() })
            ?: MaterialTheme.colorScheme.outline
        m = m.border(width, color, shape)
    }
    if (node.has("alpha")) safeAlpha(node.optDouble("alpha"))?.let { m = m.alpha(it) }
    return m
}
