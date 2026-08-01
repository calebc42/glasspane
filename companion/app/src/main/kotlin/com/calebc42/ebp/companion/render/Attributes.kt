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
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

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
internal fun lazyChildKeys(children: JsonArray): List<String> {
    val seen = HashMap<String, Int>()
    return (0 until children.size).map { i ->
        val c = children[i] as? JsonObject
        val explicit = c?.stringOrNull("key").orEmpty()
        val id = c?.stringOrNull("id").orEmpty()
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
internal fun identityPath(parentPath: String, node: JsonObject?, i: Int): String {
    val key = node?.stringOrNull("key").orEmpty()
    val id = node?.stringOrNull("id").orEmpty()
    return when {
        key.isNotEmpty() -> "$parentPath/k:$key"
        id.isNotEmpty() -> "$parentPath/id:$id"
        else -> "$parentPath/$i:${node?.stringOrNull("t").orEmpty()}"
    }
}

// ---------------------------------------------------- the §16.5 modifier

/** The node's corner shape: a number or per-corner object; 0/absent is
 * rectangular. Exposed so containers can stroke borders with the same shape. */
internal fun cornerShape(node: JsonObject): Shape {
    val c = node["corner"] ?: return RectangleShape
    return when (c) {
        // numOrNull carries the old `is Number` guard: a string, boolean or
        // JSON null corner reads as no number and stays rectangular, exactly
        // as it did when this arm tested for a boxed Number.
        is JsonPrimitive -> c.numOrNull()?.let { safeDp(it) }?.takeIf { it > 0f }
            ?.let { RoundedCornerShape(it.dp) } ?: RectangleShape
        is JsonObject -> {
            fun side(k: String): Dp = safeDp(c.doubleOr(k, 0.0))?.dp ?: 0.dp
            RoundedCornerShape(side("top_start"), side("top_end"),
                side("bottom_end"), side("bottom_start"))
        }
        // FIELD_TYPES has no `corner` entry, so SpecValidator never types it:
        // this arm is what keeps a nonconforming corner (an array) harmless.
        else -> RectangleShape
    }
}

/**
 * Apply the SPEC 16.5 universal attributes. Order inside: sizing and padding
 * first (layout), then the visual ops corner → clip → bg → border, then alpha.
 */
@Composable
internal fun Modifier.universal(node: JsonObject): Modifier {
    var m = this
    // padding / pad (per-side wins over its axis shorthand).
    val pad = node.objOrNull("pad")
    if (pad != null) {
        fun side(specific: String, axis: String): Dp {
            val v = when {
                specific in pad -> pad.doubleOr(specific, 0.0)
                axis in pad -> pad.doubleOr(axis, 0.0)
                else -> node.doubleOr("padding", 0.0)
            }
            return (safeDp(v) ?: 0f).dp
        }
        m = m.padding(start = side("start", "horizontal"), top = side("top", "vertical"),
            end = side("end", "horizontal"), bottom = side("bottom", "vertical"))
    } else if ("padding" in node) {
        safeDp(node.doubleOr("padding", 0.0))?.let { m = m.padding(it.dp) }
    }
    // Requested size + constraints. These read a member that may be absent
    // AND may be non-numeric, and both must SKIP the modifier: the 1-arg
    // optDouble they ported from defaulted to NaN, which every safe* clamp
    // rejects. Never `?: 0.0` — that would apply a 0.dp width and collapse
    // the node. The null-safe read carries the old has() gate with it.
    node["width"]?.numOrNull()?.let { v -> safeDp(v)?.let { m = m.width(it.dp) } }
    node["height"]?.numOrNull()?.let { v -> safeDp(v)?.let { m = m.height(it.dp) } }
    val minW = node["min_width"]?.numOrNull()?.let { safeDp(it) }
    val maxW = node["max_width"]?.numOrNull()?.let { safeDp(it) }
    if (minW != null || maxW != null)
        m = m.widthIn(min = minW?.dp ?: Dp.Unspecified, max = maxW?.dp ?: Dp.Unspecified)
    val minH = node["min_height"]?.numOrNull()?.let { safeDp(it) }
    val maxH = node["max_height"]?.numOrNull()?.let { safeDp(it) }
    if (minH != null || maxH != null)
        m = m.heightIn(min = minH?.dp ?: Dp.Unspecified, max = maxH?.dp ?: Dp.Unspecified)
    node["fill_fraction"]?.numOrNull()
        ?.let { v -> safeFraction(v)?.let { m = m.fillMaxWidth(it) } }
    node["aspect_ratio"]?.numOrNull()
        ?.let { v -> safeAspect(v)?.let { m = m.aspectRatio(it) } }
    // Visual ops in SPEC order: corner shape, clipping, background, border.
    val shape = cornerShape(node)
    // SPEC 16.5: `clip` applies overflow clipping to the node's shape — a
    // rectangular shape (no corner) still clips the bounding box, so this MUST
    // NOT be gated on a non-rectangular corner.
    if (node.boolOr("clip")) m = m.clip(shape)
    resolveColor(node.stringOr("bg").takeIf { it.isNotEmpty() })?.let {
        m = m.background(it, shape)
    }
    node.objOrNull("border")?.let { b ->
        val width = (safeDp(b.doubleOr("width", 1.0)) ?: 1f).dp
        val color = resolveColor(b.stringOr("color").takeIf { it.isNotEmpty() })
            ?: MaterialTheme.colorScheme.outline
        m = m.border(width, color, shape)
    }
    node["alpha"]?.numOrNull()?.let { v -> safeAlpha(v)?.let { m = m.alpha(it) } }
    return m
}
