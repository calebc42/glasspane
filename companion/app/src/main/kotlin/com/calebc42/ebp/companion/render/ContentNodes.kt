// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 17.2 content nodes, ported from poc-v1's SduiContentNodes with the
// format-6 vocabulary: RichSpan is {text, font_weight, italic, underline,
// color, bg, mono, on_tap} (poc's strike/tag/baseline/code members are gone;
// code→mono); Colors resolve as roles OR hex (§16.6) everywhere, not hex-only.
// buildSpanString is shared with table cells at W9-e. A `text.syntax` language
// fontifies the text through SyntaxHighlight (W9-h) with the active palette.
package com.calebc42.ebp.companion.render

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.CircularWavyProgressIndicator
import androidx.compose.material3.ContainedLoadingIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.RichTooltip
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * SPEC 17.2 image: fetch through the guarded ImageLoader off the main thread,
 * showing a neutral placeholder (labelled by content_description) while it
 * loads AND on any failure — a blocked address, an over-limit or undecodable
 * response, a non-advertised form. The response is never treated as an
 * executable format. content_scale maps fit/crop/fill; width/height/
 * aspect_ratio size the box.
 */
@Composable
internal fun RenderImage(node: JsonObject, m: Modifier) {
    val url = node.stringOr("url")
    val desc = node.stringOr("content_description").takeIf { it.isNotEmpty() }
    val limits = ImageLoader.DEFAULT_LIMITS
    // LD-11: through the cache, so scrolling a lazy_column back to a seen
    // image does not re-fetch, and N nodes on one URL share one load.
    val bitmap by androidx.compose.runtime.produceState<android.graphics.Bitmap?>(null, url) {
        value = ImageCache.get(url, limits)
    }
    val scale = when (node.stringOr("content_scale")) {
        "crop" -> androidx.compose.ui.layout.ContentScale.Crop
        "fill" -> androidx.compose.ui.layout.ContentScale.FillBounds
        else -> androidx.compose.ui.layout.ContentScale.Fit
    }
    val sizeMod = m.then(
        when {
            // C6: width/height are UNIVERSAL_NODE_ATTRIBUTES typed "number" and
            // validated finite-only, so `"width": 120.5` is legal traffic that
            // org.json's optInt truncated — [dimInt] truncates the same way and
            // folds a non-numeric member into 0 as the no-default optInt did.
            "width" in node && "height" in node ->
                Modifier.size(node.dimInt("width", 0).dp, node.dimInt("height", 0).dp)
            "aspect_ratio" in node ->
                Modifier.fillMaxWidth().then(
                    Modifier.aspectRatio(node.doubleOr("aspect_ratio", 1.0).toFloat()))
            else -> Modifier
        })
    val bmp = bitmap
    if (bmp != null) {
        androidx.compose.foundation.Image(
            bitmap = bmp.asImageBitmap(),
            contentDescription = desc,
            contentScale = scale,
            modifier = sizeMod)
    } else {
        // Neutral placeholder: a broken-image glyph + the description, never the
        // response content.
        Box(
            modifier = sizeMod.then(
                Modifier.background(
                    MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(8.dp))),
            contentAlignment = Alignment.Center) {
            Icon(
                IconMap.get("broken_image"),
                contentDescription = desc,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(32.dp))
        }
    }
}

/** Map a §17.2 text style name to a TextStyle; unknown falls back to body. */
@Composable
internal fun textStyleForName(name: String): TextStyle = when (name) {
    "title" -> MaterialTheme.typography.titleLarge
    "headline" -> MaterialTheme.typography.headlineSmall
    "caption" -> MaterialTheme.typography.bodySmall
    "label" -> MaterialTheme.typography.labelMedium
    "mono" -> MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace)
    else -> MaterialTheme.typography.bodyLarge
}

/** §17.1/§17.2: font_weight as a number (100..900) or a named weight.
 *
 * C6: the org.json `when (value) { is Number -> …; "bold" -> … }` dispatch
 * splits into an explicit number-then-string read, because a JsonElement is
 * never a Kotlin Number or String. FIELD_TYPES maps font_weight to
 * "font-weight", which SpecValidator leaves unvalidated, so a hostile
 * `"font_weight": "9"` reaches here — [numOrNull]'s isString guard is what
 * keeps it out of the numeric branch, exactly as `is Number` did. */
internal fun fontWeightOf(value: JsonElement?): FontWeight? {
    val n = value?.numOrNull()
    if (n != null) return n.toInt().takeIf { it in 1..1000 }?.let { FontWeight(it) }
    return when (value?.strOrNull()) {
        "bold" -> FontWeight.Bold
        "medium" -> FontWeight.Medium
        "normal" -> FontWeight.Normal
        "light" -> FontWeight.Light
        else -> null
    }
}

/** The full §17.2 text node (style/font_weight/color/selectable/max_lines). */
@Composable
internal fun RenderText(node: JsonObject, m: Modifier) {
    val style = textStyleForName(node.stringOr("style"))
    // C6: max_lines is validated integral BY VALUE upstream (validatePositiveInt
    // floors an asDoubleOrNull), so `"max_lines": 3.0` is accepted traffic and
    // must not silently fall back to the default here.
    val maxLines = node.intByValue("max_lines", Int.MAX_VALUE)
        .takeIf { it > 0 } ?: Int.MAX_VALUE
    val raw = node.stringOr("text")
    // SPEC 18.4: a `syntax` language fontifies the text with the active (pushed
    // or fallback) token palette; absent, it renders plain.
    val language = node.stringOr("syntax")
    val syntaxColors = LocalSyntaxColors.current
    val text: AnnotatedString = remember(raw, language, syntaxColors) {
        if (language.isEmpty()) AnnotatedString(raw)
        else highlightSpans(language, raw, syntaxColors).let { spans ->
            if (spans.isEmpty()) AnnotatedString(raw)
            else AnnotatedString(raw, spanStyles = spans)
        }
    }
    val content: @Composable () -> Unit = {
        Text(
            text = text,
            style = style,
            fontWeight = fontWeightOf(node["font_weight"]),
            color = resolveColor(node.stringOr("color").takeIf { it.isNotEmpty() })
                ?: Color.Unspecified,
            maxLines = maxLines,
            modifier = m)
    }
    // `selectable` enables long-press selection/copy; plain labels stay
    // non-selectable so taps on surrounding cards aren't intercepted.
    if (node.boolOr("selectable")) SelectionContainer { content() } else content()
}

/**
 * Build an AnnotatedString from a §17.2 `spans` array — the shared span
 * vocabulary of rich_text and table cells. Built per composition (bodies are
 * small): the click lambdas close over the dispatcher, so memoizing risks a
 * stale one. Span text is plain text (§16.4); a span on_tap renders as a
 * link and dispatches through §14.
 */
internal fun buildSpanString(
    spans: JsonArray?,
    linkColor: Color,
    resolve: (String?) -> Color?,
    dispatch: (JsonObject) -> Unit,
): AnnotatedString = buildAnnotatedString {
    if (spans == null) return@buildAnnotatedString
    for (i in 0 until spans.size) {
        // The index is bounded by `size`, so `spans[i]` cannot throw; a
        // non-object entry is skipped exactly as optJSONObject's null was.
        val s = spans[i] as? JsonObject ?: continue
        val text = s.stringOr("text")
        if (text.isEmpty()) continue
        val span = SpanStyle(
            fontWeight = fontWeightOf(s["font_weight"]),
            fontStyle = if (s.boolOr("italic")) FontStyle.Italic else null,
            fontFamily = if (s.boolOr("mono")) FontFamily.Monospace else null,
            textDecoration = if (s.boolOr("underline")) TextDecoration.Underline else null,
            background = resolve(s.stringOr("bg").takeIf { it.isNotEmpty() })
                ?: Color.Unspecified,
            color = resolve(s.stringOr("color").takeIf { it.isNotEmpty() })
                ?: Color.Unspecified,
        )
        val onTap = s.objOrNull("on_tap")
        if (onTap != null) {
            val linkSpan = if (span.color == Color.Unspecified)
                span.copy(color = linkColor) else span
            withLink(LinkAnnotation.Clickable(
                tag = "span$i",
                styles = TextLinkStyles(style = linkSpan)) { dispatch(onTap) }
            ) { append(text) }
        } else {
            withStyle(span) { append(text) }
        }
    }
}

@Composable
internal fun RenderRichText(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val style = textStyleForName(node.stringOr("style"))
    val scheme = MaterialTheme.colorScheme
    val annotated = buildSpanString(
        node.arrOrNull("spans"),
        linkColor = scheme.primary,
        resolve = { resolveColorIn(scheme, it) },
        dispatch = { ctx.action(it) })
    Text(text = annotated, style = style, modifier = m)
}

/** §17.2 icon: name/size/color/badge/content_description. */
@Composable
internal fun RenderIcon(node: JsonObject, m: Modifier) {
    val tint = resolveColor(node.stringOr("color").takeIf { it.isNotEmpty() })
        ?: LocalContentColor.current
    val size = node.doubleOr("size", 0.0)
    val icon: @Composable () -> Unit = {
        Icon(
            IconMap.get(node.stringOr("name")),
            contentDescription = node.stringOr("content_description")
                .takeIf { it.isNotEmpty() },
            tint = tint,
            modifier = m.then(
                safeDp(size)?.takeIf { it > 0f }?.let { Modifier.size(it.dp) }
                    ?: Modifier))
    }
    val badge = node.stringOr("badge")
    if (badge.isNotEmpty())
        BadgedBox(badge = { Badge { Text(badge) } }) { icon() }
    else icon()
}

/** §17.2 badge: a compact status pill; an empty label is an attention dot;
 * with children it decorates them (BadgedBox). The exact value stays the
 * accessible text even if visually capped. */
@Composable
internal fun RenderBadge(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val label = node.stringOr("label")
    val color = resolveColor(node.stringOr("color").takeIf { it.isNotEmpty() })
        ?: MaterialTheme.colorScheme.onSurfaceVariant
    val children = node.arrOrNull("children")
    if (children != null) {
        BadgedBox(
            modifier = m,
            badge = {
                if (label.isEmpty()) Badge()
                else Badge { Text(label) }
            }) { RenderChildren(children, ctx) }
        return
    }
    val iconName = node.stringOr("icon")
    Surface(
        modifier = m,
        shape = RoundedCornerShape(percent = 50),
        color = color.copy(alpha = 0.12f),
        contentColor = color) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (iconName.isNotEmpty())
                Icon(IconMap.get(iconName), null, Modifier.size(14.dp))
            if (label.isEmpty())
                Surface(Modifier.size(8.dp), shape = RoundedCornerShape(percent = 50),
                    color = color) {} // attention dot
            else Text(label, style = MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
internal fun RenderSectionHeader(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = m.fillMaxWidth().padding(top = 8.dp, bottom = 2.dp)) {
        Text(
            text = node.stringOr("title"),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.weight(1f))
        node.objOrNull("trailing")?.let { RenderNode(it, ctx.child(it, 0)) }
    }
}

@Composable
internal fun RenderEmptyState(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val actionJson = node.objOrNull("on_tap")
    val actionLabel = node.stringOr("action_label")
    Column(
        modifier = m.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(
            IconMap.get(node.stringOr("icon", "inbox")),
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
        node.stringOr("title").takeIf { it.isNotEmpty() }?.let {
            Text(it, style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center)
        }
        node.stringOr("caption").takeIf { it.isNotEmpty() }?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                textAlign = TextAlign.Center)
        }
        // §17.2: action_label and on_tap appear together (validated).
        if (actionJson != null && actionLabel.isNotEmpty())
            OutlinedButton(onClick = { ctx.action(actionJson) }) { Text(actionLabel) }
    }
}

/** §17.2 progress: circular (default), linear, the two wavy indicators, or
 * M3's LoadingIndicator in bare and contained form. `value` alone still
 * decides determinate vs indeterminate for every variant, so the expressive
 * members needed no second member. Unknown values fall back to circular. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderProgress(node: JsonObject, m: Modifier) {
    val v = if ("value" in node)
        node.doubleOr("value", 0.0).toFloat().coerceIn(0f, 1f) else null
    when (node.stringOr("variant")) {
        "linear" ->
            if (v != null) LinearProgressIndicator(progress = { v }, modifier = m)
            else LinearProgressIndicator(modifier = m)
        "linear_wavy" ->
            if (v != null) LinearWavyProgressIndicator(progress = { v }, modifier = m)
            else LinearWavyProgressIndicator(modifier = m)
        "circular_wavy" ->
            if (v != null) CircularWavyProgressIndicator(progress = { v }, modifier = m)
            else CircularWavyProgressIndicator(modifier = m)
        "loading" ->
            if (v != null) LoadingIndicator(progress = { v }, modifier = m)
            else LoadingIndicator(modifier = m)
        "contained_loading" ->
            if (v != null) ContainedLoadingIndicator(progress = { v }, modifier = m)
            else ContainedLoadingIndicator(modifier = m)
        else ->
            if (v != null) CircularProgressIndicator(progress = { v }, modifier = m)
            else CircularProgressIndicator(modifier = m)
    }
}

/** Month-tinted (header, header-text) color pair for a 1-12 month index. */
@Composable
private fun monthColors(monthIndex: Int): Pair<Color, Color> {
    val cs = MaterialTheme.colorScheme
    return when (((monthIndex - 1).coerceAtLeast(0)) % 6) {
        0 -> cs.primary to cs.onPrimary
        1 -> cs.secondary to cs.onSecondary
        2 -> cs.tertiary to cs.onTertiary
        3 -> cs.primaryContainer to cs.onPrimaryContainer
        4 -> cs.secondaryContainer to cs.onSecondaryContainer
        else -> cs.tertiaryContainer to cs.onTertiaryContainer
    }
}

/** §17.2 date_stamp: a compact date (and optional time) chip-card —
 * presentation data, not a clock. */
@Composable
internal fun RenderDateStamp(node: JsonObject, m: Modifier) {
    // Format-6 vocabulary: day and year are INTEGERS (poc-v1 sent strings),
    // month and time are display strings. C6: their validators (integer-1-31 /
    // non-negative-integer / integer-1-12) all check integrality BY VALUE, so
    // `"day": 5.0` is accepted traffic and reads through [intByValue]; the
    // presence gate keeps an absent member rendering as "" as before.
    val day = if ("day" in node) node.intByValue("day", 0).toString() else ""
    val month = node.stringOr("month")
    val year = if ("year" in node) node.intByValue("year", 0).toString() else ""
    val time = node.stringOr("time")
    val (headerColor, headerText) = monthColors(node.intByValue("month_index", 0))
    Column(modifier = m) {
        ElevatedCard(shape = RoundedCornerShape(6.dp), modifier = Modifier.width(64.dp)) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.fillMaxWidth()) {
                if (month.isNotEmpty()) {
                    Text(month, style = MaterialTheme.typography.labelMedium,
                        color = headerText, textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                            .background(headerColor,
                                RoundedCornerShape(topStart = 6.dp, topEnd = 6.dp))
                            .padding(vertical = 2.dp))
                }
                Text(day, style = MaterialTheme.typography.headlineMedium,
                    modifier = Modifier.padding(vertical = 2.dp))
                if (year.isNotEmpty())
                    Text(year, style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.outline,
                        modifier = Modifier.padding(bottom = 2.dp))
            }
        }
        if (time.isNotEmpty()) {
            ElevatedCard(shape = RoundedCornerShape(6.dp),
                modifier = Modifier.width(64.dp).padding(top = 6.dp)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("TIME", style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                            .background(MaterialTheme.colorScheme.primary)
                            .padding(vertical = 2.dp))
                    Text(time, style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.padding(top = 4.dp, bottom = 2.dp))
                }
            }
        }
    }
}

/** §17.2 tooltip: wraps its ANCHOR children in M3's TooltipBox, exactly as
 * `badge` wraps its children in a BadgedBox. The anchor keeps its own on_tap —
 * a tooltip is raised by long press (or hover), never by consuming the tap.
 *
 * `position` places the bubble against the anchor; `left`/`right` are ABSOLUTE
 * sides and stay distinct from the direction-relative `start`/`end`, which is
 * why this enum is its own rather than a reuse of the alignment enums.
 * `caret` grows the pointer aimed back at the anchor. `rich` selects M3's
 * RichTooltip, which is the only form with a title and an action. `shown` is
 * authored presentation state: a true value asks the Companion to display the
 * tooltip without the long press, which is how a "Display tooltip" button
 * raises one over a sibling anchor with no new action descriptor. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RenderTooltip(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val text = node.stringOr("text")
    val rich = node.boolOr("rich")
    val caret = node.boolOr("caret")
    // `caret_width`/`caret_height` resize the pointer — meaningful only with
    // `caret`, which the validator enforces as both-or-neither dp.
    val caretShape = if (!caret) null else {
        val w = node["caret_width"]?.numOrNull()?.toFloat()
        val h = node["caret_height"]?.numOrNull()?.toFloat()
        if (w != null && h != null) TooltipDefaults.caretShape(DpSize(w.dp, h.dp))
        else TooltipDefaults.caretShape()
    }
    val position = when (node.stringOr("position")) {
        "below" -> TooltipAnchorPosition.Below
        "left" -> TooltipAnchorPosition.Left
        "right" -> TooltipAnchorPosition.Right
        "start" -> TooltipAnchorPosition.Start
        "end" -> TooltipAnchorPosition.End
        else -> TooltipAnchorPosition.Above          // §12 rule 6 fallback
    }
    val state = rememberTooltipState(isPersistent = rich)
    // `shown` drives the state rather than the composition: re-pushing a
    // snapshot whose value flipped shows or dismisses it.
    val shown = node.boolOr("shown")
    LaunchedEffect(shown) { if (shown) state.show() else state.dismiss() }
    val title = node.stringOr("title")
    val actionLabel = node.stringOr("action_label")
    val onAction = node.objOrNull("on_action")
    TooltipBox(
        positionProvider = TooltipDefaults.rememberTooltipPositionProvider(position),
        state = state,
        modifier = m,
        tooltip = {
            if (rich) RichTooltip(
                title = title.takeIf { it.isNotEmpty() }?.let { { Text(it) } },
                action = actionLabel.takeIf { it.isNotEmpty() }?.let {
                    {
                        TextButton(onClick = {
                            if (onAction != null) ctx.action(onAction)
                            state.dismiss()
                        }) { Text(it) }
                    }
                },
                caretShape = caretShape,
            ) { Text(text) }
            else PlainTooltip(
                caretShape = caretShape,
            ) { Text(text) }
        }) {
        RenderChildren(node.arrOrNull("children"), ctx)
    }
}
