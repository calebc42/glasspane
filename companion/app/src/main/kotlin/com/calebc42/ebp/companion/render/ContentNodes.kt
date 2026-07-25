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
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
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
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject

/**
 * SPEC 17.2 image: fetch through the guarded ImageLoader off the main thread,
 * showing a neutral placeholder (labelled by content_description) while it
 * loads AND on any failure — a blocked address, an over-limit or undecodable
 * response, a non-advertised form. The response is never treated as an
 * executable format. content_scale maps fit/crop/fill; width/height/
 * aspect_ratio size the box.
 */
@Composable
internal fun RenderImage(node: JSONObject, m: Modifier) {
    val url = node.optString("url")
    val desc = node.optString("content_description").takeIf { it.isNotEmpty() }
    val limits = ImageLoader.DEFAULT_LIMITS
    // LD-11: through the cache, so scrolling a lazy_column back to a seen
    // image does not re-fetch, and N nodes on one URL share one load.
    val bitmap by androidx.compose.runtime.produceState<android.graphics.Bitmap?>(null, url) {
        value = ImageCache.get(url, limits)
    }
    val scale = when (node.optString("content_scale")) {
        "crop" -> androidx.compose.ui.layout.ContentScale.Crop
        "fill" -> androidx.compose.ui.layout.ContentScale.FillBounds
        else -> androidx.compose.ui.layout.ContentScale.Fit
    }
    val sizeMod = m.then(
        when {
            node.has("width") && node.has("height") ->
                Modifier.size(node.optInt("width").dp, node.optInt("height").dp)
            node.has("aspect_ratio") ->
                Modifier.fillMaxWidth().then(
                    Modifier.aspectRatio(node.optDouble("aspect_ratio", 1.0).toFloat()))
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

/** §17.1/§17.2: font_weight as a number (100..900) or a named weight. */
internal fun fontWeightOf(value: Any?): FontWeight? = when (value) {
    is Number -> value.toInt().takeIf { it in 1..1000 }?.let { FontWeight(it) }
    "bold" -> FontWeight.Bold
    "medium" -> FontWeight.Medium
    "normal" -> FontWeight.Normal
    "light" -> FontWeight.Light
    else -> null
}

/** The full §17.2 text node (style/font_weight/color/selectable/max_lines). */
@Composable
internal fun RenderText(node: JSONObject, m: Modifier) {
    val style = textStyleForName(node.optString("style"))
    val maxLines = node.optInt("max_lines", Int.MAX_VALUE)
        .takeIf { it > 0 } ?: Int.MAX_VALUE
    val raw = node.optString("text")
    // SPEC 18.4: a `syntax` language fontifies the text with the active (pushed
    // or fallback) token palette; absent, it renders plain.
    val language = node.optString("syntax")
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
            fontWeight = fontWeightOf(node.opt("font_weight")),
            color = resolveColor(node.optString("color").takeIf { it.isNotEmpty() })
                ?: Color.Unspecified,
            maxLines = maxLines,
            modifier = m)
    }
    // `selectable` enables long-press selection/copy; plain labels stay
    // non-selectable so taps on surrounding cards aren't intercepted.
    if (node.optBoolean("selectable")) SelectionContainer { content() } else content()
}

/**
 * Build an AnnotatedString from a §17.2 `spans` array — the shared span
 * vocabulary of rich_text and table cells. Built per composition (bodies are
 * small): the click lambdas close over the dispatcher, so memoizing risks a
 * stale one. Span text is plain text (§16.4); a span on_tap renders as a
 * link and dispatches through §14.
 */
internal fun buildSpanString(
    spans: JSONArray?,
    linkColor: Color,
    resolve: (String?) -> Color?,
    dispatch: (JSONObject) -> Unit,
): AnnotatedString = buildAnnotatedString {
    if (spans == null) return@buildAnnotatedString
    for (i in 0 until spans.length()) {
        val s = spans.optJSONObject(i) ?: continue
        val text = s.optString("text")
        if (text.isEmpty()) continue
        val span = SpanStyle(
            fontWeight = fontWeightOf(s.opt("font_weight")),
            fontStyle = if (s.optBoolean("italic")) FontStyle.Italic else null,
            fontFamily = if (s.optBoolean("mono")) FontFamily.Monospace else null,
            textDecoration = if (s.optBoolean("underline")) TextDecoration.Underline else null,
            background = resolve(s.optString("bg").takeIf { it.isNotEmpty() })
                ?: Color.Unspecified,
            color = resolve(s.optString("color").takeIf { it.isNotEmpty() })
                ?: Color.Unspecified,
        )
        val onTap = s.optJSONObject("on_tap")
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
internal fun RenderRichText(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val style = textStyleForName(node.optString("style"))
    val scheme = MaterialTheme.colorScheme
    val annotated = buildSpanString(
        node.optJSONArray("spans"),
        linkColor = scheme.primary,
        resolve = { resolveColorIn(scheme, it) },
        dispatch = { ctx.action(it) })
    Text(text = annotated, style = style, modifier = m)
}

/** §17.2 icon: name/size/color/badge/content_description. */
@Composable
internal fun RenderIcon(node: JSONObject, m: Modifier) {
    val tint = resolveColor(node.optString("color").takeIf { it.isNotEmpty() })
        ?: LocalContentColor.current
    val size = node.optDouble("size", 0.0)
    val icon: @Composable () -> Unit = {
        Icon(
            IconMap.get(node.optString("name")),
            contentDescription = node.optString("content_description")
                .takeIf { it.isNotEmpty() },
            tint = tint,
            modifier = m.then(
                safeDp(size)?.takeIf { it > 0f }?.let { Modifier.size(it.dp) }
                    ?: Modifier))
    }
    val badge = node.optString("badge")
    if (badge.isNotEmpty())
        BadgedBox(badge = { Badge { Text(badge) } }) { icon() }
    else icon()
}

/** §17.2 badge: a compact status pill; an empty label is an attention dot;
 * with children it decorates them (BadgedBox). The exact value stays the
 * accessible text even if visually capped. */
@Composable
internal fun RenderBadge(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val label = node.optString("label")
    val color = resolveColor(node.optString("color").takeIf { it.isNotEmpty() })
        ?: MaterialTheme.colorScheme.onSurfaceVariant
    val children = node.optJSONArray("children")
    if (children != null) {
        BadgedBox(
            modifier = m,
            badge = {
                if (label.isEmpty()) Badge()
                else Badge { Text(label) }
            }) { RenderChildren(children, ctx) }
        return
    }
    val iconName = node.optString("icon")
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
internal fun RenderSectionHeader(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = m.fillMaxWidth().padding(top = 8.dp, bottom = 2.dp)) {
        Text(
            text = node.optString("title"),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.weight(1f))
        node.optJSONObject("trailing")?.let { RenderNode(it, ctx.child(it, 0)) }
    }
}

@Composable
internal fun RenderEmptyState(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val actionJson = node.optJSONObject("on_tap")
    val actionLabel = node.optString("action_label")
    Column(
        modifier = m.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(
            IconMap.get(node.optString("icon", "inbox")),
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
        node.optString("title").takeIf { it.isNotEmpty() }?.let {
            Text(it, style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center)
        }
        node.optString("caption").takeIf { it.isNotEmpty() }?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                textAlign = TextAlign.Center)
        }
        // §17.2: action_label and on_tap appear together (validated).
        if (actionJson != null && actionLabel.isNotEmpty())
            OutlinedButton(onClick = { ctx.action(actionJson) }) { Text(actionLabel) }
    }
}

/** §17.2 progress: circular (default) or linear; no value = indeterminate. */
@Composable
internal fun RenderProgress(node: JSONObject, m: Modifier) {
    val linear = node.optString("variant") == "linear"
    if (node.has("value")) {
        val v = node.optDouble("value", 0.0).toFloat().coerceIn(0f, 1f)
        if (linear) LinearProgressIndicator(progress = { v }, modifier = m)
        else CircularProgressIndicator(progress = { v }, modifier = m)
    } else {
        if (linear) LinearProgressIndicator(modifier = m)
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
internal fun RenderDateStamp(node: JSONObject, m: Modifier) {
    // Format-6 vocabulary: day and year are INTEGERS (poc-v1 sent strings),
    // month and time are display strings.
    val day = if (node.has("day")) node.optInt("day").toString() else ""
    val month = node.optString("month")
    val year = if (node.has("year")) node.optInt("year").toString() else ""
    val time = node.optString("time")
    val (headerColor, headerText) = monthColors(node.optInt("month_index", 0))
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
