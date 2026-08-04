// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 17.5 visualization nodes, ported from poc-v1 with the format-6
// vocabulary: canvas ops carry width/height (not w/h), radius (not r),
// stroke_width (not stroke), and {x,y} path points (not [x,y] pairs); a
// chart's on_point_tap returns the COMPLETE authored point object (§17.5, poc
// returned only {index,y}); month_grid keys its shown month on the §16.1
// presentation identity. Unknown canvas ops are skipped, never fatal.
package com.calebc42.ebp.companion.render

import android.graphics.Paint
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import java.text.DateFormatSymbols
import java.util.Calendar
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// -------------------------------------------------------------------- chart

private val CHART_PALETTE = listOf(
    Color(0xFF4C6FFF), Color(0xFF00A676), Color(0xFFFF8A3D),
    Color(0xFFB05CE6), Color(0xFFE64980), Color(0xFF12B5CB))

private class ChartSeriesData(val points: List<JsonObject>, val ys: DoubleArray, val color: Color)

@Composable
internal fun RenderChart(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val kind = node.stringOr("kind", "line")
    val seriesArr = node.arrOrNull("series") ?: JsonArray(emptyList())
    val onPointTap = node.objOrNull("on_point_tap")
    // C6: `height` is FIELD_TYPES "number" and the validator gates it as
    // positive-finite only, so 12.5 is legal traffic; dimInt truncates it the
    // way org.json's optInt did instead of defaulting the chart to 160dp.
    val heightDp = node.dimInt("height", 160).coerceAtLeast(0)
    val scheme = MaterialTheme.colorScheme

    val series = ArrayList<ChartSeriesData>()
    var yMin = Double.POSITIVE_INFINITY
    var yMax = Double.NEGATIVE_INFINITY
    var maxLen = 0
    for (s in 0 until seriesArr.size) {
        val so = seriesArr[s] as? JsonObject ?: continue
        val ptsArr = so.arrOrNull("points") ?: JsonArray(emptyList())
        val pts = ArrayList<JsonObject>(ptsArr.size)
        val ys = DoubleArray(ptsArr.size)
        for (i in 0 until ptsArr.size) {
            val p = ptsArr[i] as? JsonObject ?: JsonObject(emptyMap())
            pts.add(p)
            val y = p.doubleOr("y", 0.0)
            ys[i] = y
            if (y < yMin) yMin = y
            if (y > yMax) yMax = y
        }
        maxLen = maxOf(maxLen, ys.size)
        val color = resolveColorIn(scheme, so.stringOr("color").takeIf { it.isNotEmpty() })
            ?: CHART_PALETTE[s % CHART_PALETTE.size]
        series.add(ChartSeriesData(pts, ys, color))
    }
    node.arrOrNull("y_range")?.let {
        // C6: the length guard is now load-bearing — org.json's indexed
        // optDouble(i, default) folded a short array into the default, kotlinx's
        // [i] throws, so the bound stays and each read keeps its own fallback.
        if (it.size == 2) {
            yMin = it.getOrNull(0)?.numOrNull() ?: yMin
            yMax = it.getOrNull(1)?.numOrNull() ?: yMax
        }
    }
    // SPEC 17.5: bars/areas read against a zero baseline — but an explicit
    // y_range is authoritative, so only default the baseline when none was given.
    if ((kind == "bar" || kind == "area") && "y_range" !in node && yMin > 0.0) yMin = 0.0
    if (!yMin.isFinite() || !yMax.isFinite()) { yMin = 0.0; yMax = 1.0 }
    if (yMax == yMin) yMax += 1.0

    // C6: kotlinx JsonObject has structural equals (org.json's JSONObject had
    // none), so remember(node) would now key by value — the toString() keys
    // below are kept verbatim rather than changed inside a mechanical port.
    var started by remember(node.toString()) { mutableStateOf(false) }
    LaunchedEffect(Unit) { started = true }
    val progress by animateFloatAsState(
        targetValue = if (started) 1f else 0f, animationSpec = tween(600), label = "chart-grow")

    var mod = m.fillMaxWidth().height(heightDp.dp)
    if (onPointTap != null) {
        mod = mod.pointerInput(node.toString()) {
            detectTapGestures { off ->
                val s0 = series.firstOrNull() ?: return@detectTapGestures
                if (s0.points.isEmpty()) return@detectTapGestures
                // Map tap-x on the SAME denominator the layout uses (maxLen),
                // then select the first series' point at that index (clamped) so
                // the tapped x-position and the returned point agree.
                val idx = if (maxLen <= 1) 0
                    else ((off.x / size.width.toFloat()) * (maxLen - 1)).roundToInt()
                        .coerceIn(0, s0.points.size - 1)
                // SPEC 17.5/14.3 (amendment #114): the COMPLETE authored
                // point object as `value`, AND the resolved ordinal `index`.
                // The echoed point is not an identity — §17.5 does not require
                // authored points to be distinct and §4.3 makes 1 and 1.0
                // equal, so without the index a duplicate point is
                // unresolvable by any comparator.
                ctx.actionInjecting(onPointTap, buildJsonObject { put("index", idx) },
                    s0.points.getOrNull(idx))
            }
        }
    }
    val desc = node.stringOr("summary").ifEmpty { "$kind chart" }
    Canvas(modifier = mod.semantics { contentDescription = desc }) {
        val w = size.width
        val h = size.height
        val n = maxLen
        fun xLine(i: Int): Float = if (n <= 1) w / 2f else w * i / (n - 1)
        fun yAt(v: Double): Float {
            val t = ((v - yMin) / (yMax - yMin)).toFloat().coerceIn(0f, 1f)
            return h - t * h
        }
        val baseY = yAt(if (yMin <= 0.0 && yMax >= 0.0) 0.0 else yMin)
        for (cs in series) {
            if (cs.ys.isEmpty()) continue
            when (kind) {
                "bar" -> {
                    val slot = w / cs.ys.size
                    val bw = slot * 0.6f
                    for (i in cs.ys.indices) {
                        val cx = slot * (i + 0.5f)
                        val top = baseY + (yAt(cs.ys[i]) - baseY) * progress
                        drawRect(cs.color, Offset(cx - bw / 2f, minOf(top, baseY)),
                            Size(bw, abs(baseY - top)))
                    }
                }
                else -> {
                    val path = Path()
                    for (i in cs.ys.indices) {
                        val x = xLine(i)
                        val y = baseY + (yAt(cs.ys[i]) - baseY) * progress
                        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                    }
                    if (kind == "area") {
                        val fill = Path().apply {
                            addPath(path); lineTo(xLine(cs.ys.size - 1), baseY)
                            lineTo(xLine(0), baseY); close()
                        }
                        drawPath(fill, cs.color.copy(alpha = 0.18f))
                    }
                    val stroke = if (kind == "sparkline") 2.dp.toPx() else 2.5.dp.toPx()
                    drawPath(path, cs.color, style = Stroke(width = stroke))
                }
            }
        }
    }
}

// ------------------------------------------------------------------- canvas

@Composable
internal fun RenderCanvas(node: JsonObject, m: Modifier) {
    // C6: canvas width/height are validated positive-finite (not integral), so
    // they read through dimInt — truncating, exactly as optInt did.
    val wDp = node.dimInt("width", 100).coerceAtLeast(0)
    val hDp = node.dimInt("height", 100).coerceAtLeast(0)
    val ops = node.arrOrNull("ops") ?: JsonArray(emptyList())
    val scheme = MaterialTheme.colorScheme
    val fallback = scheme.onSurface
    // Resolve each op colour up front — the DrawScope below is not composable.
    val colors: List<Color> = (0 until ops.size).map { i ->
        resolveColorIn(scheme, (ops[i] as? JsonObject)?.stringOr("color")
            ?.takeIf { it.isNotEmpty() }) ?: fallback
    }
    Canvas(modifier = m.size(wDp.dp, hDp.dp)) {
        // C6: org.json's ONE-arg optDouble defaulted to NaN, and a NaN
        // coordinate draws nothing — so an absent or non-numeric op member
        // arrives here as null and stays NaN. It must never become 0.0, which
        // would paint a malformed op at the origin instead of skipping it.
        fun px(v: Double?): Float = (v ?: Double.NaN).toFloat().dp.toPx()
        for (i in 0 until ops.size) {
            val o = ops[i] as? JsonObject ?: continue
            val color = colors[i]
            // SPEC 17.5: `fill` is a Color; its presence means fill the interior
            // (omission = stroke only). A stroked shape uses the op's `color`.
            val fillColor = resolveColorIn(scheme,
                o.stringOr("fill").takeIf { it.isNotEmpty() })
            val filled = fillColor != null
            val strokeW = px(o.doubleOr("stroke_width", 1.0))
            when (o.stringOr("op")) {
                "line" -> drawLine(color,
                    Offset(px(o["x1"]?.numOrNull()), px(o["y1"]?.numOrNull())),
                    Offset(px(o["x2"]?.numOrNull()), px(o["y2"]?.numOrNull())),
                    strokeWidth = px(o.doubleOr("width", 1.0)))
                "rect" -> {
                    val tl = Offset(px(o["x"]?.numOrNull()), px(o["y"]?.numOrNull()))
                    val sz = Size(px(o["width"]?.numOrNull()), px(o["height"]?.numOrNull()))
                    if (filled) drawRect(fillColor ?: color, tl, sz)
                    else drawRect(color, tl, sz, style = Stroke(strokeW))
                }
                "circle" -> {
                    val center = Offset(px(o["cx"]?.numOrNull()), px(o["cy"]?.numOrNull()))
                    val r = px(o["radius"]?.numOrNull())
                    if (filled) drawCircle(fillColor ?: color, r, center)
                    else drawCircle(color, r, center, style = Stroke(strokeW))
                }
                "path" -> {
                    val pts = o.arrOrNull("points") ?: JsonArray(emptyList())
                    if (pts.size >= 2) {
                        val path = Path()
                        for (j in 0 until pts.size) {
                            val p = pts[j] as? JsonObject ?: continue
                            val x = px(p["x"]?.numOrNull()); val y = px(p["y"]?.numOrNull())
                            if (j == 0) path.moveTo(x, y) else path.lineTo(x, y)
                        }
                        if (o.boolOr("closed")) path.close()
                        if (filled) drawPath(path, fillColor ?: color)
                        else drawPath(path, color, style = Stroke(strokeW))
                    }
                }
                "text" -> drawIntoCanvas { c ->
                    val paint = Paint().apply {
                        this.color = color.toArgb()
                        textSize = px(o.doubleOr("size", 12.0))
                        isAntiAlias = true
                    }
                    c.nativeCanvas.drawText(o.stringOr("text"),
                        px(o["x"]?.numOrNull()), px(o["y"]?.numOrNull()), paint)
                }
                else -> {} // SPEC 17.5: unknown op skipped, never fatal
            }
        }
    }
}

// --------------------------------------------------------------- month_grid

@Composable
internal fun RenderMonthGrid(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val specMonth = node.stringOr("month").takeIf { it.matches(Regex("""\d{4}-\d{2}""")) }
        ?: return
    val marks = node.objOrNull("marks")
    val selected = node.stringOr("selected")
    val minMonth = node.stringOr("min_month").ifEmpty { null }
    val maxMonth = node.stringOr("max_month").ifEmpty { null }
    // §17.5 day-level bounds: out-of-range and listed weekdays render
    // disabled and never dispatch; min_month/max_month keep gating only
    // the month arrows, as before. The range pair shades the inclusive
    // span; ISO dates compare as strings.
    val minDate = node.stringOr("min_date").ifEmpty { null }
    val maxDate = node.stringOr("max_date").ifEmpty { null }
    val disabledWeekdays = node.arrOrNull("disabled_weekdays")
        ?.mapNotNull { it.numOrNull()?.toInt() } ?: emptyList()
    val rangeStart = node.stringOr("range_start").ifEmpty { null }
    val rangeEnd = node.stringOr("range_end").ifEmpty { null }
    val onDayTap = node.objOrNull("on_day_tap")
    val onMonthChange = node.objOrNull("on_month_change")

    // §16.1: the shown month keys on the presentation identity, re-seeded from
    // the spec when the authored month changes; mark-only re-pushes keep it.
    key(ctx.path) {
        var shownMonth by remember(specMonth) { mutableStateOf(specMonth) }
        val changeMonth: (Int) -> Unit = { delta ->
            val next = monthAdd(shownMonth, delta)
            if ((minMonth == null || next >= minMonth) && (maxMonth == null || next <= maxMonth)) {
                shownMonth = next
                // §17.5 new month value
                onMonthChange?.let { ctx.action(it, JsonPrimitive(next)) }
            }
        }
        val year = shownMonth.substring(0, 4).toInt()
        val month = shownMonth.substring(5, 7).toInt()
        val cal = Calendar.getInstance()
        val weekStart = cal.firstDayOfWeek
        cal.clear(); cal.set(year, month - 1, 1)
        val daysInMonth = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
        val leadingBlanks = (cal.get(Calendar.DAY_OF_WEEK) - weekStart + 7) % 7
        val today = Calendar.getInstance().let {
            "%04d-%02d-%02d".format(it.get(Calendar.YEAR),
                it.get(Calendar.MONTH) + 1, it.get(Calendar.DAY_OF_MONTH))
        }
        val symbols = remember { DateFormatSymbols() }
        val density = LocalDensity.current
        val swipeThresholdPx = with(density) { 60.dp.toPx() }
        var dragTotal by remember { mutableFloatStateOf(0f) }

        Column(modifier = m.fillMaxWidth()) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                IconButton(onClick = { changeMonth(-1) },
                    enabled = minMonth == null || monthAdd(shownMonth, -1) >= minMonth) {
                    Icon(IconMap.get("chevron_left"), contentDescription = "Previous month")
                }
                Text("${symbols.months[month - 1]} $year",
                    style = MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                IconButton(onClick = { changeMonth(1) },
                    enabled = maxMonth == null || monthAdd(shownMonth, 1) <= maxMonth) {
                    Icon(IconMap.get("chevron_right"), contentDescription = "Next month")
                }
            }
            Row(Modifier.fillMaxWidth()) {
                for (i in 0 until 7) {
                    val dow = (weekStart - 1 + i) % 7 + 1
                    Text(symbols.shortWeekdays[dow].take(2),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                }
            }
            Column(Modifier.fillMaxWidth().pointerInput(shownMonth) {
                detectHorizontalDragGestures(
                    onDragStart = { dragTotal = 0f },
                    onDragEnd = {
                        when {
                            dragTotal <= -swipeThresholdPx -> changeMonth(1)
                            dragTotal >= swipeThresholdPx -> changeMonth(-1)
                        }
                    },
                    onHorizontalDrag = { _, a -> dragTotal += a })
            }) {
                val weeks = (leadingBlanks + daysInMonth + 6) / 7
                for (week in 0 until weeks) {
                    Row(Modifier.fillMaxWidth()) {
                        for (col in 0 until 7) {
                            val day = week * 7 + col - leadingBlanks + 1
                            if (day < 1 || day > daysInMonth) {
                                Spacer(Modifier.weight(1f).aspectRatio(1f))
                            } else {
                                val date = "%s-%02d".format(shownMonth, day)
                                // 0 = Sunday, matching the contract.
                                val weekday = (weekStart - 1 + col) % 7
                                val dayEnabled =
                                    (minDate == null || date >= minDate) &&
                                    (maxDate == null || date <= maxDate) &&
                                    weekday !in disabledWeekdays
                                val inRange = rangeStart != null && rangeEnd != null &&
                                    date >= rangeStart && date <= rangeEnd
                                MonthGridDay(day, date, marks?.objOrNull(date),
                                    date == today, date == selected,
                                    // §17.5 ISO date; a disabled day never
                                    // dispatches.
                                    if (dayEnabled) onDayTap?.let {
                                        { ctx.action(it, JsonPrimitive(date)) }
                                    } else null,
                                    Modifier.weight(1f),
                                    enabled = dayEnabled,
                                    inRange = inRange,
                                    rangeCap = inRange &&
                                        (date == rangeStart || date == rangeEnd))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MonthGridDay(
    day: Int, date: String, mark: JsonObject?, isToday: Boolean, isSelected: Boolean,
    onTap: (() -> Unit)?, modifier: Modifier,
    enabled: Boolean = true, inRange: Boolean = false, rangeCap: Boolean = false,
) {
    // C6: `dots` is validated integral BY VALUE upstream (asDoubleOrNull +
    // Math.floor), so "dots": 2.0 is accepted traffic and must still read 2.
    val dots = (mark?.intByValue("dots", 0) ?: 0).coerceIn(0, 3)
    val dotColor = resolveColor(mark?.stringOr("color")?.takeIf { it.isNotEmpty() })
        ?: MaterialTheme.colorScheme.primary
    val desc = date + if (dots > 0) ", $dots marked" else ""
    // A range's interior cells fill edge to edge (the span reads as one
    // band); its two caps and a plain selection stay circles.
    val filled = isSelected || rangeCap
    Box(
        modifier.aspectRatio(1f).padding(if (inRange && !rangeCap) 0.dp else 2.dp)
            .then(if (inRange && !rangeCap)
                Modifier.background(MaterialTheme.colorScheme.secondaryContainer)
            else Modifier)
            .clip(CircleShape).then(
            when {
                filled -> Modifier.background(MaterialTheme.colorScheme.primary)
                isToday -> Modifier.border(1.5.dp, MaterialTheme.colorScheme.primary, CircleShape)
                else -> Modifier
            }).then(if (onTap != null) Modifier.clickable { onTap() } else Modifier)
            .semantics { contentDescription = desc },
        contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(day.toString(), style = MaterialTheme.typography.bodySmall,
                color = when {
                    filled -> MaterialTheme.colorScheme.onPrimary
                    !enabled -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                    inRange -> MaterialTheme.colorScheme.onSecondaryContainer
                    else -> MaterialTheme.colorScheme.onSurface
                })
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                repeat(dots) {
                    Box(Modifier.size(4.dp).clip(CircleShape).background(
                        if (filled) MaterialTheme.colorScheme.onPrimary else dotColor))
                }
            }
        }
    }
}

/** MONTH ("YYYY-MM") shifted by DELTA months. */
internal fun monthAdd(month: String, delta: Int): String {
    val y = month.substring(0, 4).toInt()
    val mo = month.substring(5, 7).toInt()
    val total = y * 12 + (mo - 1) + delta
    return "%04d-%02d".format(total / 12, total % 12 + 1)
}
