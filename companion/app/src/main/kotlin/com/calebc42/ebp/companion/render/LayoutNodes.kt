// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 17.3 layout nodes, ported from poc-v1 with the format-6 vocabulary:
// - `fill` defaults FALSE (§17.1 optional booleans; poc filled by default) and
//   `spacing` defaults 0; `arrange` (start/center/end/space_between/
//   space_around/space_evenly) distributes space and beats spacing (§17.3).
// - box grows the full 9-value alignment set (poc missed the corners).
// - card/collapsible keep ONLY the contract's swipe_start/swipe_end sides via
//   SwipeActionBox (poc's legacy single-action on_swipe is gone).
// - collapsible expansion + tabs selection key on §16.1 presentation identity
//   (ctx.path: key > id > tree path); a same-identity re-push preserves the
//   user's state, a new identity reseeds. Tabs additionally shrink-clamp to
//   `initial` WITHOUT emitting on_change when a smaller same-identity snapshot
//   invalidates the retained index (§17.3).
// - table rows carry `kind` (data/header/rule — poc used booleans) with span
//   cells; on_add_row/on_add_col inject `index` (§14.3).
// - reorderable_list is a contract-shaped rebuild of poc's drag list:
//   items are arbitrary nodes with unique key/id; a completed drag injects
//   from/to/order (§14.3), and the vertical drag mechanics survive while the
//   org-specific promote/demote does not.
package com.calebc42.ebp.companion.render

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

// ------------------------------------------------------ row/column/flow_row

// §17.3: arrange distributes available space; a non-start value takes
// precedence over spacing.
private fun horizontalArrange(node: JSONObject): Arrangement.Horizontal =
    when (node.optString("arrange")) {
        "center" -> Arrangement.Center
        "end" -> Arrangement.End
        "space_between" -> Arrangement.SpaceBetween
        "space_around" -> Arrangement.SpaceAround
        "space_evenly" -> Arrangement.SpaceEvenly
        else -> Arrangement.spacedBy(
            (safeDp(node.optDouble("spacing", 0.0)) ?: 0f).dp)
    }

private fun verticalArrange(node: JSONObject): Arrangement.Vertical =
    when (node.optString("arrange")) {
        "center" -> Arrangement.Center
        "end" -> Arrangement.Bottom
        "space_between" -> Arrangement.SpaceBetween
        "space_around" -> Arrangement.SpaceAround
        "space_evenly" -> Arrangement.SpaceEvenly
        else -> Arrangement.spacedBy(
            (safeDp(node.optDouble("spacing", 0.0)) ?: 0f).dp)
    }

@Composable
internal fun RenderRow(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val scroll = node.optBoolean("scroll")
    val fill = node.optBoolean("fill")
    val mod = when {
        scroll -> m.fillMaxWidth().horizontalScroll(rememberScrollState())
        fill -> m.fillMaxWidth()
        else -> m
    }
    Row(
        modifier = mod,
        horizontalArrangement = horizontalArrange(node),
        verticalAlignment = when (node.optString("align")) {
            "top" -> Alignment.Top
            "bottom" -> Alignment.Bottom
            // baseline needs per-child alignBy; center is the honest default.
            else -> Alignment.CenterVertically
        }) {
        // Weights are meaningless with unbounded width (§ port note).
        if (scroll) RenderChildren(node.optJSONArray("children"), ctx)
        else RenderRowChildren(node.optJSONArray("children"), ctx)
    }
}

@Composable
internal fun RenderColumn(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val scroll = node.optBoolean("scroll")
    val fill = node.optBoolean("fill")
    val mod = (if (fill) m.fillMaxWidth() else m).let {
        if (scroll) it.verticalScroll(rememberScrollState()) else it
    }
    Column(
        modifier = mod,
        verticalArrangement = verticalArrange(node),
        horizontalAlignment = when (node.optString("align")) {
            "center" -> Alignment.CenterHorizontally
            "end" -> Alignment.End
            else -> Alignment.Start
        }) {
        RenderColumnChildren(node.optJSONArray("children"), ctx)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun RenderFlowRow(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    FlowRow(
        modifier = m,
        horizontalArrangement = horizontalArrange(node),
        verticalArrangement = Arrangement.spacedBy(
            (safeDp(node.optDouble("run_spacing", 0.0)) ?: 0f).dp)) {
        RenderChildren(node.optJSONArray("children"), ctx)
    }
}

// ------------------------------------------------------------- box/surface

@Composable
internal fun RenderBox(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.optJSONObject("on_tap")
    // §17.3: the full 9-value alignment vocabulary; default top_start.
    val alignment = when (node.optString("alignment")) {
        "top_center" -> Alignment.TopCenter
        "top_end" -> Alignment.TopEnd
        "center_start" -> Alignment.CenterStart
        "center" -> Alignment.Center
        "center_end" -> Alignment.CenterEnd
        "bottom_start" -> Alignment.BottomStart
        "bottom_center" -> Alignment.BottomCenter
        "bottom_end" -> Alignment.BottomEnd
        else -> Alignment.TopStart
    }
    val mod = if (onTap != null) m.clickable { ctx.action(onTap) } else m
    Box(modifier = mod, contentAlignment = alignment) {
        RenderChildren(node.optJSONArray("children"), ctx)
    }
}

@Composable
internal fun RenderSurfaceNode(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val color = resolveColor(node.optString("color").takeIf { it.isNotEmpty() })
        ?: MaterialTheme.colorScheme.surface
    // §16.5: a numeric universal corner overrides shape, except circle.
    val base = when (node.optString("shape")) {
        "rounded" -> RoundedCornerShape(8.dp)
        "rounded_small" -> RoundedCornerShape(4.dp)
        "circle" -> CircleShape
        else -> RectangleShape
    }
    val shape = if (node.has("corner") && base != CircleShape)
        cornerShape(node) else base
    Surface(
        modifier = m,
        color = color,
        shape = shape,
        tonalElevation = (safeDp(node.optDouble("elevation", 0.0)) ?: 0f).dp) {
        RenderChildren(node.optJSONArray("children"), ctx)
    }
}

// ------------------------------------------------------------- lazy_column

@Composable
internal fun RenderLazyColumn(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val children = node.optJSONArray("children") ?: return
    // scroll_here: scroll to the marked child on first show and whenever its
    // index changes; an index-stable re-push never disturbs the position.
    var scrollTarget = -1
    for (i in 0 until children.length()) {
        if (children.optJSONObject(i)?.optBoolean("scroll_here") == true) {
            scrollTarget = i; break
        }
    }
    val listState = rememberLazyListState()
    if (scrollTarget >= 0) {
        LaunchedEffect(scrollTarget) { listState.scrollToItem(scrollTarget) }
    }
    // Stable per-child keys so structural pushes preserve row identity.
    val keys = remember(children) { lazyChildKeys(children) }
    LazyColumn(
        state = listState,
        modifier = m.fillMaxSize(),
        contentPadding = PaddingValues(
            (safeDp(node.optDouble("content_padding", 0.0)) ?: 0f).dp),
        verticalArrangement = Arrangement.spacedBy(
            (safeDp(node.optDouble("spacing", 0.0)) ?: 0f).dp)) {
        items(count = children.length(), key = { keys[it] }) { i ->
            children.optJSONObject(i)?.let {
                Box(Modifier.animateItem()) { RenderNode(it, ctx.child(it, i)) }
            }
        }
    }
}

// ----------------------------------------------------------- card + swipes

/** §17.3 swipe side chrome shared by card and collapsible: dispatch
 * on_trigger at most once per completed gesture, never settle dismissed. */
@Composable
internal fun SwipeActionBox(
    swipeStart: JSONObject?,
    swipeEnd: JSONObject?,
    ctx: RenderCtx,
    content: @Composable () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            val side = when (value) {
                SwipeToDismissBoxValue.StartToEnd -> swipeStart
                SwipeToDismissBoxValue.EndToStart -> swipeEnd
                else -> null
            }
            side?.optJSONObject("on_trigger")?.let {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                // §14.3: the swipe direction rides as an injected member.
                ctx.actionInjecting(it, JSONObject().put("direction",
                    if (value == SwipeToDismissBoxValue.StartToEnd) "start" else "end"))
            }
            false // §17.3: the item returns to rest; the server's list decides.
        })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = swipeStart != null,
        enableDismissFromEndToStart = swipeEnd != null,
        backgroundContent = {
            val side = when (state.dismissDirection) {
                SwipeToDismissBoxValue.StartToEnd -> swipeStart
                SwipeToDismissBoxValue.EndToStart -> swipeEnd
                else -> null
            } ?: return@SwipeToDismissBox
            val bg = resolveColor(side.optString("color").takeIf { it.isNotEmpty() })
                ?: MaterialTheme.colorScheme.secondaryContainer
            val fg = if (bg.luminance() < 0.5f)
                androidx.compose.ui.graphics.Color.White
            else androidx.compose.ui.graphics.Color(0xFF1A1A1A)
            val label = side.optString("label")
            Box(
                Modifier.fillMaxSize().padding(vertical = 4.dp)
                    .background(bg, RoundedCornerShape(12.dp))
                    .padding(horizontal = 20.dp),
                contentAlignment =
                    if (state.dismissDirection == SwipeToDismissBoxValue.StartToEnd)
                        Alignment.CenterStart else Alignment.CenterEnd) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    side.optString("icon").takeIf { it.isNotEmpty() }?.let {
                        Icon(IconMap.get(it), contentDescription = label.ifEmpty { null },
                            tint = fg)
                        Spacer(Modifier.width(6.dp))
                    }
                    if (label.isNotEmpty())
                        Text(label, color = fg,
                            style = MaterialTheme.typography.labelLarge)
                }
            }
        }) { content() }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun RenderCard(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.optJSONObject("on_tap")
    val onLongTap = node.optJSONObject("on_long_tap")
    val content: @Composable () -> Unit = {
        ElevatedCard(
            modifier = m.fillMaxWidth().then(
                if (onLongTap != null) Modifier.combinedClickable(
                    onClick = { if (onTap != null) ctx.action(onTap) },
                    onLongClick = { ctx.action(onLongTap) })
                else Modifier.clickable(enabled = onTap != null) {
                    if (onTap != null) ctx.action(onTap)
                })) {
            Box(Modifier.padding(16.dp)) {
                RenderChildren(node.optJSONArray("children"), ctx)
            }
        }
    }
    val swipeStart = node.optJSONObject("swipe_start")
    val swipeEnd = node.optJSONObject("swipe_end")
    if (swipeStart != null || swipeEnd != null)
        SwipeActionBox(swipeStart, swipeEnd, ctx) { content() }
    else content()
}

// ------------------------------------------------------------- collapsible

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun RenderCollapsible(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val collapsed = node.optBoolean("collapsed")
    // §17.3: `collapsed` seeds only the FIRST snapshot for a presentation
    // identity; later same-identity pushes keep the user's expansion state.
    var expanded by rememberSaveable(ctx.path) { mutableStateOf(!collapsed) }
    val header = node.optJSONObject("header")
    val onLongTap = node.optJSONObject("on_long_tap")
    val chevron by animateFloatAsState(
        targetValue = if (expanded) 0f else -90f, label = "chevron")
    Column(modifier = m.fillMaxWidth()) {
        val headerRow: @Composable () -> Unit = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().then(
                    if (onLongTap != null) Modifier.combinedClickable(
                        onClick = { expanded = !expanded },
                        onLongClick = { ctx.action(onLongTap) })
                    else Modifier.clickable { expanded = !expanded })) {
                Icon(
                    IconMap.get("keyboard_arrow_down"),
                    contentDescription = if (expanded) "Collapse" else "Expand",
                    modifier = Modifier.padding(4.dp)
                        .graphicsLayer { rotationZ = chevron })
                header?.let { RenderNode(it, ctx.child(it, 0)) }
            }
        }
        val swipeStart = node.optJSONObject("swipe_start")
        val swipeEnd = node.optJSONObject("swipe_end")
        if (swipeStart != null || swipeEnd != null)
            SwipeActionBox(swipeStart, swipeEnd, ctx) { headerRow() }
        else headerRow()
        if (expanded) RenderColumnChildren(node.optJSONArray("children"), ctx)
    }
}

// -------------------------------------------------------------------- tabs

@Composable
internal fun RenderTabs(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val items = node.optJSONArray("items")
    val children = node.optJSONArray("children") ?: return
    val pageCount = children.length()
    if (pageCount == 0) return
    val initial = node.optInt("initial", 0).coerceIn(0, pageCount - 1)
    val onChange = node.optJSONObject("on_change")

    // §16.1/§17.3: selection keys on the presentation identity — a new
    // identity resets to `initial`; a same-identity push preserves it.
    key(ctx.path) {
        val pagerState = rememberPagerState(initialPage = initial) { pageCount }
        val scope = rememberCoroutineScope()
        var lastReported by remember { mutableIntStateOf(initial) }
        // §17.3: a smaller same-identity snapshot with an invalid retained
        // index selects `initial` WITHOUT emitting on_change.
        LaunchedEffect(pageCount) {
            if (pagerState.currentPage >= pageCount) {
                lastReported = initial
                pagerState.scrollToPage(initial)
            }
        }
        // Report only user-driven settles, once per page.
        LaunchedEffect(pagerState.settledPage) {
            if (pagerState.settledPage != lastReported &&
                pagerState.settledPage < pageCount) {
                lastReported = pagerState.settledPage
                // §17.3: on_change receives the settled index as args.value.
                onChange?.let { ctx.action(it, pagerState.settledPage) }
            }
        }
        Column(modifier = m.fillMaxWidth()) {
            if (!node.optBoolean("pager_only") && items != null) {
                val selected = pagerState.currentPage.coerceIn(0, pageCount - 1)
                val tabs: @Composable () -> Unit = {
                    for (i in 0 until minOf(items.length(), pageCount)) {
                        val item = items.optJSONObject(i) ?: continue
                        val icon = item.optString("icon")
                        Tab(
                            selected = selected == i,
                            onClick = { scope.launch { pagerState.animateScrollToPage(i) } },
                            text = { Text(item.optString("label")) },
                            icon = if (icon.isNotEmpty()) {
                                { Icon(IconMap.get(icon), contentDescription = null) }
                            } else null)
                    }
                }
                if (node.optBoolean("scrollable"))
                    ScrollableTabRow(selectedTabIndex = selected) { tabs() }
                else TabRow(selectedTabIndex = selected) { tabs() }
            }
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top) { page ->
                children.optJSONObject(page)?.let {
                    RenderNode(it, ctx.child(it, page))
                }
            }
        }
    }
}

// ------------------------------------------------------------------- table

private sealed interface TableRowSpec
private data class CellsSpec(val cells: List<JSONObject>, val header: Boolean) : TableRowSpec
private data class RuleSpec(val afterHeader: Boolean) : TableRowSpec

/** §17.3 table: columns size to their widest cell; rules draw as dividers;
 * header rows emphasize; on_add_row/on_add_col inject `index` (§14.3). */
@Composable
internal fun RenderTable(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val rowsJson = node.optJSONArray("rows") ?: return
    val specs = buildList {
        var prevHeader = false
        for (i in 0 until rowsJson.length()) {
            val row = rowsJson.optJSONObject(i) ?: continue
            when (row.optString("kind")) { // format 6: kind, not booleans
                "rule" -> { add(RuleSpec(afterHeader = prevHeader)); prevHeader = false }
                "header", "data" -> {
                    val cellsJson = row.optJSONArray("cells") ?: continue
                    val cells = buildList {
                        for (c in 0 until cellsJson.length())
                            cellsJson.optJSONObject(c)?.let { add(it) }
                    }
                    val header = row.optString("kind") == "header"
                    add(CellsSpec(cells, header))
                    prevHeader = header
                }
            }
        }
    }
    if (specs.none { it is CellsSpec && it.cells.isNotEmpty() }) return
    val aligns = buildList {
        node.optJSONArray("aligns")?.let { a ->
            for (i in 0 until a.length()) add(a.optString(i))
        }
    }
    val nrows = specs.count { it is CellsSpec }
    val ncols = specs.filterIsInstance<CellsSpec>().maxOf { it.cells.size }
    val onAddRow = node.optJSONObject("on_add_row")
    val onAddCol = node.optJSONObject("on_add_col")
    Column(modifier = m) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.horizontalScroll(rememberScrollState())) {
            TableGrid(specs, aligns, ctx)
            if (onAddCol != null) AddAffordance("Add column") {
                ctx.actionInjecting(onAddCol, JSONObject().put("index", ncols))
            }
        }
        if (onAddRow != null) AddAffordance("Add row") {
            ctx.actionInjecting(onAddRow, JSONObject().put("index", nrows))
        }
    }
}

@Composable
private fun AddAffordance(description: String, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(32.dp)) {
        Icon(IconMap.get("add"), contentDescription = description,
            tint = MaterialTheme.colorScheme.outline, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun TableGrid(specs: List<TableRowSpec>, aligns: List<String>, ctx: RenderCtx) {
    val ruleColor = MaterialTheme.colorScheme.outlineVariant
    androidx.compose.ui.layout.Layout(content = {
        specs.forEach { spec ->
            when (spec) {
                is RuleSpec -> HorizontalDivider(
                    thickness = if (spec.afterHeader) 2.dp else 1.dp, color = ruleColor)
                is CellsSpec -> spec.cells.forEach { TableCell(it, spec.header, ctx) }
            }
        }
    }) { measurables, _ ->
        val loose = androidx.compose.ui.unit.Constraints()
        var mi = 0
        val cellRows = arrayOfNulls<List<androidx.compose.ui.layout.Placeable>>(specs.size)
        val pendingRules = mutableListOf<Pair<Int, Int>>()
        specs.forEachIndexed { r, spec ->
            when (spec) {
                is RuleSpec -> pendingRules.add(r to mi++)
                is CellsSpec -> cellRows[r] = spec.cells.map { measurables[mi++].measure(loose) }
            }
        }
        val ncols = specs.filterIsInstance<CellsSpec>().maxOf { it.cells.size }
        val colW = IntArray(ncols)
        cellRows.forEach { row ->
            row?.forEachIndexed { c, p -> if (p.width > colW[c]) colW[c] = p.width }
        }
        val totalW = colW.sum()
        val rules = arrayOfNulls<androidx.compose.ui.layout.Placeable>(specs.size)
        pendingRules.forEach { (r, i) ->
            rules[r] = measurables[i].measure(
                androidx.compose.ui.unit.Constraints.fixedWidth(totalW))
        }
        val rowH = IntArray(specs.size) { r ->
            rules[r]?.height ?: (cellRows[r]?.maxOfOrNull { it.height } ?: 0)
        }
        layout(totalW, rowH.sum()) {
            var y = 0
            specs.forEachIndexed { r, _ ->
                rules[r]?.placeRelative(0, y)
                cellRows[r]?.let { row ->
                    var x = 0
                    row.forEachIndexed { c, p ->
                        val slack = colW[c] - p.width
                        val dx = when (aligns.getOrNull(c)) {
                            "end" -> slack
                            "center" -> slack / 2
                            else -> 0
                        }
                        p.placeRelative(x + dx, y + (rowH[r] - p.height) / 2)
                        x += colW[c]
                    }
                }
                y += rowH[r]
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TableCell(cell: JSONObject, header: Boolean, ctx: RenderCtx) {
    val onTap = cell.optJSONObject("on_tap")
    val onLongTap = cell.optJSONObject("on_long_tap")
    val scheme = MaterialTheme.colorScheme
    val annotated = buildSpanString(
        cell.optJSONArray("spans"), scheme.primary,
        { resolveColorIn(scheme, it) }, { ctx.action(it) })
    val base = MaterialTheme.typography.bodyMedium
    val clickMod = if (onTap != null || onLongTap != null)
        Modifier.combinedClickable(
            onClick = { onTap?.let { ctx.action(it) } },
            onLongClick = onLongTap?.let { { ctx.action(it) } })
    else Modifier
    Box(
        modifier = clickMod.defaultMinSize(minWidth = 28.dp, minHeight = 24.dp)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        contentAlignment = Alignment.CenterStart) {
        Text(annotated, style = if (header)
            base.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
        else base)
    }
}

// --------------------------------------------------------- reorderable_list

/** §17.3 reorderable_list: arbitrary item nodes with unique key/id; a
 * completed handle-drag reorders locally and dispatches on_reorder with
 * from/to/order injected (§14.3). The authored list itself never mutates —
 * the server's next snapshot is the truth. */
@Composable
internal fun RenderReorderableList(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val onReorder = node.optJSONObject("on_reorder")
    val itemsJson = node.optJSONArray("items") ?: return
    val itemKey = { i: Int ->
        val it = itemsJson.optJSONObject(i)
        it?.optString("key").takeIf { k -> !k.isNullOrEmpty() }
            ?: it?.optString("id").orEmpty()
    }
    // Display order as authored indices; reset when the authored list changes.
    var order by remember(itemsJson.toString()) {
        mutableStateOf((0 until itemsJson.length()).toList())
    }
    val listState = rememberLazyListState()
    val haptic = LocalHapticFeedback.current
    var draggedPos by remember { mutableStateOf<Int?>(null) } // position in `order`
    var dragStartPos by remember { mutableIntStateOf(-1) }
    var dragOffsetY by remember { mutableFloatStateOf(0f) }
    LazyColumn(
        state = listState,
        modifier = m.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 4.dp)) {
        items(count = order.size, key = { pos -> itemKey(order[pos]) }) { pos ->
            val authored = order[pos]
            val item = itemsJson.optJSONObject(authored) ?: return@items
            val isDragged = draggedPos == pos
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().then(
                    if (isDragged) Modifier
                        .offset { IntOffset(0, dragOffsetY.roundToInt()) }
                        .zIndex(1f)
                        .background(MaterialTheme.colorScheme.surfaceContainerHigh,
                            RoundedCornerShape(8.dp))
                    else Modifier.animateItem())) {
                Icon(
                    IconMap.get("drag_handle"),
                    contentDescription = "Drag to reorder",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .pointerInput(pos, order) {
                            detectDragGesturesAfterLongPress(
                                onDragStart = {
                                    draggedPos = pos
                                    dragStartPos = pos
                                    dragOffsetY = 0f
                                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                },
                                onDrag = { change, dragAmount ->
                                    change.consume()
                                    dragOffsetY += dragAmount.y
                                    val dragged = draggedPos ?: return@detectDragGesturesAfterLongPress
                                    val info = listState.layoutInfo
                                    val dInfo = info.visibleItemsInfo
                                        .firstOrNull { it.index == dragged }
                                        ?: return@detectDragGesturesAfterLongPress
                                    val center = dInfo.offset + dInfo.size / 2 +
                                        dragOffsetY.roundToInt()
                                    val target = info.visibleItemsInfo.firstOrNull {
                                        it.index != dragged &&
                                            center in it.offset..(it.offset + it.size)
                                    }
                                    if (target != null) {
                                        val shift = if (target.index < dragged)
                                            target.offset - dInfo.offset
                                        else (target.offset + target.size) -
                                            (dInfo.offset + dInfo.size)
                                        order = order.toMutableList().apply {
                                            add(target.index, removeAt(dragged))
                                        }
                                        dragOffsetY -= shift
                                        draggedPos = target.index
                                    }
                                },
                                onDragEnd = {
                                    val to = draggedPos
                                    if (to != null && onReorder != null &&
                                        to != dragStartPos) {
                                        // §14.3: from/to/order injected.
                                        val keys = JSONArray()
                                        order.forEach { keys.put(itemKey(it)) }
                                        ctx.actionInjecting(onReorder, JSONObject()
                                            .put("from", dragStartPos)
                                            .put("to", to)
                                            .put("order", keys))
                                        haptic.performHapticFeedback(
                                            HapticFeedbackType.LongPress)
                                    }
                                    draggedPos = null; dragOffsetY = 0f
                                },
                                onDragCancel = { draggedPos = null; dragOffsetY = 0f })
                        }
                        .padding(12.dp))
                Box(Modifier.weight(1f)) {
                    RenderNode(item, ctx.child(item, authored))
                }
            }
            if (pos < order.size - 1)
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
        }
    }
}
