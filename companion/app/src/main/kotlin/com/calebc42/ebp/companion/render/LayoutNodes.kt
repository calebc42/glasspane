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

import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AppBarColumn
import androidx.compose.material3.AppBarMenuState
import androidx.compose.material3.AppBarOverflowIndicator
import androidx.compose.material3.AppBarRow
import androidx.compose.material3.AppBarScope
import androidx.compose.material3.Badge
import androidx.compose.material3.ButtonGroup
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.ButtonGroupMenuState
import androidx.compose.material3.FloatingActionButtonMenu
import androidx.compose.material3.FloatingActionButtonMenuItem
import androidx.compose.material3.ToggleFloatingActionButton
import androidx.compose.material3.ToggleFloatingActionButtonDefaults
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Card
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LeadingIconTab
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.toShape
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.SecondaryScrollableTabRow
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.carousel.CarouselItemScope
import androidx.compose.material3.carousel.HorizontalCenteredHeroCarousel
import androidx.compose.material3.carousel.HorizontalMultiBrowseCarousel
import androidx.compose.material3.carousel.HorizontalUncontainedCarousel
import androidx.compose.material3.carousel.rememberCarouselState
import androidx.compose.material3.rememberTooltipState
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffold
import androidx.compose.material3.adaptive.layout.SupportingPaneScaffold
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldPaneScope
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.material3.adaptive.navigation.rememberSupportingPaneScaffoldNavigator
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.rememberVectorPainter
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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// ------------------------------------------------------ row/column/flow_row

// §17.3: arrange distributes available space; a non-start value takes
// precedence over spacing.
private fun horizontalArrange(node: JsonObject): Arrangement.Horizontal =
    when (node.stringOr("arrange")) {
        "center" -> Arrangement.Center
        "end" -> Arrangement.End
        "space_between" -> Arrangement.SpaceBetween
        "space_around" -> Arrangement.SpaceAround
        "space_evenly" -> Arrangement.SpaceEvenly
        else -> Arrangement.spacedBy(
            (safeDp(node.doubleOr("spacing", 0.0)) ?: 0f).dp)
    }

private fun verticalArrange(node: JsonObject): Arrangement.Vertical =
    when (node.stringOr("arrange")) {
        "center" -> Arrangement.Center
        "end" -> Arrangement.Bottom
        "space_between" -> Arrangement.SpaceBetween
        "space_around" -> Arrangement.SpaceAround
        "space_evenly" -> Arrangement.SpaceEvenly
        else -> Arrangement.spacedBy(
            (safeDp(node.doubleOr("spacing", 0.0)) ?: 0f).dp)
    }

@Composable
internal fun RenderRow(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val scroll = node.boolOr("scroll")
    val fill = node.boolOr("fill")
    val mod = when {
        scroll -> m.fillMaxWidth().horizontalScroll(rememberScrollState())
        fill -> m.fillMaxWidth()
        else -> m
    }
    Row(
        modifier = mod,
        horizontalArrangement = horizontalArrange(node),
        verticalAlignment = when (node.stringOr("align")) {
            "top" -> Alignment.Top
            "bottom" -> Alignment.Bottom
            // baseline needs per-child alignBy; center is the honest default.
            else -> Alignment.CenterVertically
        }) {
        // Weights are meaningless with unbounded width (§ port note).
        if (scroll) RenderChildren(node.arrOrNull("children"), ctx)
        else RenderRowChildren(node.arrOrNull("children"), ctx)
    }
}

@Composable
internal fun RenderColumn(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val scroll = node.boolOr("scroll")
    // The §17.6 body-scroll signal: a scrolling column inside a scaffold
    // body publishes whether it rests at its start.
    val signal = LocalBodyScrollSignal.current
    val fill = node.boolOr("fill")
    val mod = (if (fill) m.fillMaxWidth() else m).let {
        if (scroll) {
            val state = rememberScrollState()
            if (signal != null) {
                val atStart by remember { derivedStateOf { state.value == 0 } }
                LaunchedEffect(atStart) { signal.atStart = atStart }
            }
            it.verticalScroll(state,
                reverseScrolling = node.boolOr("reverse_scroll"))
        } else it
    }
    Column(
        modifier = mod,
        verticalArrangement = verticalArrange(node),
        horizontalAlignment = when (node.stringOr("align")) {
            "center" -> Alignment.CenterHorizontally
            "end" -> Alignment.End
            else -> Alignment.Start
        }) {
        RenderColumnChildren(node.arrOrNull("children"), ctx)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun RenderFlowRow(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    FlowRow(
        modifier = m,
        horizontalArrangement = horizontalArrange(node),
        // SPEC 17.3: flow_row.align is the per-run cross-axis alignment
        // (top|center|bottom, default top).
        itemVerticalAlignment = when (node.stringOr("align")) {
            "center" -> Alignment.CenterVertically
            "bottom" -> Alignment.Bottom
            else -> Alignment.Top
        },
        verticalArrangement = Arrangement.spacedBy(
            (safeDp(node.doubleOr("run_spacing", 0.0)) ?: 0f).dp)) {
        RenderChildren(node.arrOrNull("children"), ctx)
    }
}

// ------------------------------------------------------------- box/surface

@Composable
internal fun RenderBox(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.objOrNull("on_tap")
    // §17.3: the full 9-value alignment vocabulary; default top_start.
    val alignment = when (node.stringOr("alignment")) {
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
        RenderChildren(node.arrOrNull("children"), ctx)
    }
}

@Composable
internal fun RenderSurfaceNode(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val color = resolveColor(node.stringOr("color").takeIf { it.isNotEmpty() })
        ?: MaterialTheme.colorScheme.surface
    // §16.5: a numeric universal corner overrides shape, except circle.
    // Beyond the three classics, `shape` accepts the M3 MaterialShapes
    // polygon vocabulary — resolved here so bg/clip/border honor it; an
    // unknown name stays rectangular per §12 rule 6.
    val base = when (val s = node.stringOr("shape")) {
        "rounded" -> RoundedCornerShape(8.dp)
        "rounded_small" -> RoundedCornerShape(4.dp)
        "circle" -> CircleShape
        else -> materialShapeOf(s) ?: RectangleShape
    }
    val shape = if ("corner" in node && base != CircleShape)
        cornerShape(node) else base
    Surface(
        modifier = m,
        color = color,
        shape = shape,
        tonalElevation = (safeDp(node.doubleOr("elevation", 0.0)) ?: 0f).dp,
        // §17.3: `elevation` is TONAL — applyTonalElevation returns the colour
        // unchanged for every container but colorScheme.surface, so it can
        // never make a container float. `shadow_elevation` is the cast shadow.
        shadowElevation = (safeDp(node.doubleOr("shadow_elevation", 0.0)) ?: 0f).dp) {
        RenderChildren(node.arrOrNull("children"), ctx)
    }
}

// ------------------------------------------------------------- lazy_column

@Composable
internal fun RenderLazyColumn(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val children = node.arrOrNull("children") ?: return
    // scroll_here: scroll to the marked child on first show and whenever its
    // index changes; an index-stable re-push never disturbs the position.
    var scrollTarget = -1
    for (i in 0 until children.size) {
        if ((children[i] as? JsonObject)?.boolOr("scroll_here") == true) {
            scrollTarget = i; break
        }
    }
    val listState = rememberLazyListState()
    // The §17.6 body-scroll signal (see BodyScrollSignal).
    LocalBodyScrollSignal.current?.let { signal ->
        val atStart by remember {
            derivedStateOf { listState.firstVisibleItemIndex == 0 }
        }
        LaunchedEffect(atStart) { signal.atStart = atStart }
    }
    if (scrollTarget >= 0) {
        LaunchedEffect(scrollTarget) { listState.scrollToItem(scrollTarget) }
    }
    // Stable per-child keys so structural pushes preserve row identity.
    val keys = remember(children) { lazyChildKeys(children) }
    LazyColumn(
        state = listState,
        modifier = m.fillMaxSize(),
        contentPadding = PaddingValues(
            (safeDp(node.doubleOr("content_padding", 0.0)) ?: 0f).dp),
        verticalArrangement = Arrangement.spacedBy(
            (safeDp(node.doubleOr("spacing", 0.0)) ?: 0f).dp)) {
        items(count = children.size, key = { keys[it] }) { i ->
            (children.getOrNull(i) as? JsonObject)?.let {
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
    swipeStart: JsonObject?,
    swipeEnd: JsonObject?,
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
            side?.objOrNull("on_trigger")?.let {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                // §14.3: the swipe direction rides as an injected member.
                ctx.actionInjecting(it, buildJsonObject {
                    put("direction",
                        if (value == SwipeToDismissBoxValue.StartToEnd) "start" else "end")
                })
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
            val bg = resolveColor(side.stringOr("color").takeIf { it.isNotEmpty() })
                ?: MaterialTheme.colorScheme.secondaryContainer
            val fg = if (bg.luminance() < 0.5f)
                androidx.compose.ui.graphics.Color.White
            else androidx.compose.ui.graphics.Color(0xFF1A1A1A)
            val label = side.stringOr("label")
            Box(
                Modifier.fillMaxSize().padding(vertical = 4.dp)
                    .background(bg, RoundedCornerShape(12.dp))
                    .padding(horizontal = 20.dp),
                contentAlignment =
                    if (state.dismissDirection == SwipeToDismissBoxValue.StartToEnd)
                        Alignment.CenterStart else Alignment.CenterEnd) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    side.stringOr("icon").takeIf { it.isNotEmpty() }?.let {
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
internal fun RenderCard(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.objOrNull("on_tap")
    val onLongTap = node.objOrNull("on_long_tap")
    val cardModifier = m.fillMaxWidth().then(
        if (onLongTap != null) Modifier.combinedClickable(
            onClick = { if (onTap != null) ctx.action(onTap) },
            onLongClick = { ctx.action(onLongTap) })
        else Modifier.clickable(enabled = onTap != null) {
            if (onTap != null) ctx.action(onTap)
        })
    val body: @Composable () -> Unit = {
        Box(Modifier.padding(16.dp)) {
            RenderChildren(node.arrOrNull("children"), ctx)
        }
    }
    // §17.3 `card.variant`: omitted stays `elevated`, which is the only card
    // this renderer has ever drawn, so no existing traffic changes meaning.
    val content: @Composable () -> Unit = {
        when (node.stringOr("variant")) {
            "filled" -> Card(modifier = cardModifier) { body() }
            "outlined" -> OutlinedCard(modifier = cardModifier) { body() }
            else -> ElevatedCard(modifier = cardModifier) { body() }
        }
    }
    val swipeStart = node.objOrNull("swipe_start")
    val swipeEnd = node.objOrNull("swipe_end")
    if (swipeStart != null || swipeEnd != null)
        SwipeActionBox(swipeStart, swipeEnd, ctx) { content() }
    else content()
}

// ------------------------------------------------------------- collapsible

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun RenderCollapsible(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val collapsed = node.boolOr("collapsed")
    // §17.3: `collapsed` seeds only the FIRST snapshot for a presentation
    // identity; later same-identity pushes keep the user's expansion state.
    var expanded by rememberSaveable(ctx.path) { mutableStateOf(!collapsed) }
    val header = node.objOrNull("header")
    val onLongTap = node.objOrNull("on_long_tap")
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
        val swipeStart = node.objOrNull("swipe_start")
        val swipeEnd = node.objOrNull("swipe_end")
        if (swipeStart != null || swipeEnd != null)
            SwipeActionBox(swipeStart, swipeEnd, ctx) { headerRow() }
        else headerRow()
        if (expanded) RenderColumnChildren(node.arrOrNull("children"), ctx)
    }
}

// -------------------------------------------------------------------- tabs

@Composable
internal fun RenderTabs(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val items = node.arrOrNull("items")
    val children = node.arrOrNull("children") ?: return
    val pageCount = children.size
    if (pageCount == 0) return
    // C6: `initial` is integer-TYPED but validated integral BY VALUE upstream
    // (SpecValidator floors an asDouble read, so `"initial": 2.0` is accepted
    // traffic and org.json's optInt truncated it). A spelling-strict read would
    // default it to 0 and silently open the tabs on the first page.
    val initial = node.intByValue("initial", 0).coerceIn(0, pageCount - 1)
    val onChange = node.objOrNull("on_change")

    // §16.1/§17.3: selection keys on the presentation identity — a new
    // identity resets to `initial`; a same-identity push preserves it.
    key(ctx.path) {
        val pagerState = rememberPagerState(initialPage = initial) { pageCount }
        val scope = rememberCoroutineScope()
        var lastReported by remember { mutableIntStateOf(initial) }
        // §17.3: a smaller same-identity snapshot with an invalid retained
        // index selects `initial` WITHOUT emitting on_change.
        LaunchedEffect(pageCount) {
            // SPEC 17.3: if the RETAINED index is no longer valid under a
            // smaller snapshot, select `initial` WITHOUT emitting on_change.
            // Check lastReported (the retained user index), not currentPage —
            // Compose silently coerces currentPage into range, which would mask
            // the invalid retained page.
            if (lastReported >= pageCount || pagerState.currentPage >= pageCount) {
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
                onChange?.let { ctx.action(it, JsonPrimitive(pagerState.settledPage)) }
            }
        }
        Column(modifier = m.fillMaxWidth()) {
            if (!node.boolOr("pager_only") && items != null) {
                val selected = pagerState.currentPage.coerceIn(0, pageCount - 1)
                val tabs: @Composable () -> Unit = {
                    for (i in 0 until minOf(items.size, pageCount)) {
                        val item = items[i] as? JsonObject ?: continue
                        val icon = item.stringOr("icon")
                        // §17.3: an ABSENT label is the icon-only 48dp tab.
                        // `label ""` is NOT the same thing — an empty Text
                        // still fills the slot and forces the 72dp two-line
                        // tab with a blank line, which is why the member is
                        // optional rather than defaulted.
                        val hasLabel = "label" in item
                        val badge = item.stringOr("badge")
                        val leading = icon.isNotEmpty() &&
                            item.stringOr("icon_position") == "leading"
                        val onClick = { scope.launch { pagerState.animateScrollToPage(i) }; Unit }
                        val badged: @Composable (@Composable () -> Unit) -> Unit = { c ->
                            BadgedBox(badge = {
                                if (badge.isNotEmpty()) Badge { Text(badge) } else Badge()
                            }) { c() }
                        }
                        val iconSlot: @Composable () -> Unit = {
                            val glyph: @Composable () -> Unit = {
                                Icon(IconMap.get(icon), contentDescription =
                                    if (hasLabel) null else item.stringOr("label")
                                        .ifEmpty { icon })
                            }
                            // A LeadingIconTab hangs its badge on the TITLE
                            // (M3's own sample) — badging the glyph there would
                            // stack two ornaments at the row's start.
                            if ("badge" in item && !leading) badged { glyph() }
                            else glyph()
                        }
                        val textSlot: (@Composable () -> Unit)? =
                            if (!hasLabel) null
                            else if ("badge" in item && leading)
                                { { badged { Text(item.stringOr("label")) } } }
                            else { { Text(item.stringOr("label")) } }
                        val tab: @Composable () -> Unit = {
                            if (leading)
                                LeadingIconTab(
                                    selected = selected == i, onClick = onClick,
                                    text = textSlot ?: {}, icon = iconSlot)
                            else Tab(
                                selected = selected == i, onClick = onClick,
                                text = textSlot,
                                icon = if (icon.isNotEmpty()) iconSlot else null)
                        }
                        // §17.3 `tooltip`: the PlainTooltip M3 wants on an
                        // icon-only tab, anchored Above — its own default.
                        val tip = item.stringOr("tooltip")
                        if (tip.isNotEmpty())
                            TooltipBox(
                                positionProvider = TooltipDefaults
                                    .rememberTooltipPositionProvider(
                                        TooltipAnchorPosition.Above),
                                tooltip = { PlainTooltip { Text(tip) } },
                                state = rememberTooltipState()) { tab() }
                        else tab()
                    }
                }
                // §17.3 `style`: secondary (the default) is the full-width
                // indicator this renderer has always drawn; primary is M3's
                // content-width rounded one. Naming them explicitly also
                // retires the deprecated TabRow/ScrollableTabRow calls.
                val primary = node.stringOr("style") == "primary"
                if (node.boolOr("scrollable")) {
                    if (primary) PrimaryScrollableTabRow(selectedTabIndex = selected) { tabs() }
                    else SecondaryScrollableTabRow(selectedTabIndex = selected) { tabs() }
                } else {
                    if (primary) PrimaryTabRow(selectedTabIndex = selected) { tabs() }
                    else SecondaryTabRow(selectedTabIndex = selected) { tabs() }
                }
            }
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top) { page ->
                (children.getOrNull(page) as? JsonObject)?.let {
                    RenderNode(it, ctx.child(it, page))
                }
            }
        }
    }
}

// ------------------------------------------------------------------- table

private sealed interface TableRowSpec
private data class CellsSpec(val cells: List<JsonObject>, val header: Boolean) : TableRowSpec
private data class RuleSpec(val afterHeader: Boolean) : TableRowSpec

/** §17.3 table: columns size to their widest cell; rules draw as dividers;
 * header rows emphasize; on_add_row/on_add_col inject `index` (§14.3). */
@Composable
internal fun RenderTable(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val rowsJson = node.arrOrNull("rows") ?: return
    val specs = buildList {
        var prevHeader = false
        for (i in 0 until rowsJson.size) {
            val row = rowsJson[i] as? JsonObject ?: continue
            when (row.stringOr("kind")) { // format 6: kind, not booleans
                "rule" -> { add(RuleSpec(afterHeader = prevHeader)); prevHeader = false }
                "header", "data" -> {
                    val cellsJson = row.arrOrNull("cells") ?: continue
                    val cells = buildList {
                        for (c in 0 until cellsJson.size)
                            (cellsJson[c] as? JsonObject)?.let { add(it) }
                    }
                    val header = row.stringOr("kind") == "header"
                    add(CellsSpec(cells, header))
                    prevHeader = header
                }
            }
        }
    }
    if (specs.none { it is CellsSpec && it.cells.isNotEmpty() }) return
    val aligns = buildList {
        node.arrOrNull("aligns")?.let { a ->
            for (i in 0 until a.size) add(a[i].strOrNull().orEmpty())
        }
    }
    val nrows = specs.count { it is CellsSpec }
    val ncols = specs.filterIsInstance<CellsSpec>().maxOf { it.cells.size }
    val onAddRow = node.objOrNull("on_add_row")
    val onAddCol = node.objOrNull("on_add_col")
    Column(modifier = m) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.horizontalScroll(rememberScrollState())) {
            TableGrid(specs, aligns, ctx)
            if (onAddCol != null) AddAffordance("Add column") {
                ctx.actionInjecting(onAddCol, buildJsonObject { put("index", ncols) })
            }
        }
        if (onAddRow != null) AddAffordance("Add row") {
            ctx.actionInjecting(onAddRow, buildJsonObject { put("index", nrows) })
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
private fun TableCell(cell: JsonObject, header: Boolean, ctx: RenderCtx) {
    val onTap = cell.objOrNull("on_tap")
    val onLongTap = cell.objOrNull("on_long_tap")
    val scheme = MaterialTheme.colorScheme
    val annotated = buildSpanString(
        cell.arrOrNull("spans"), scheme.primary,
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
internal fun RenderReorderableList(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val onReorder = node.objOrNull("on_reorder")
    val itemsJson = node.arrOrNull("items") ?: return
    val itemKey = { i: Int ->
        val it = itemsJson.getOrNull(i) as? JsonObject
        it?.stringOr("key").takeIf { k -> !k.isNullOrEmpty() }
            ?: it?.stringOr("id").orEmpty()
    }
    // SPEC 14.3: `order` is an array of closed identity OBJECTS — {key: id} or
    // {id: id}, choosing `key` when the child has both — not bare strings.
    val itemIdentity = { i: Int ->
        val it = itemsJson.getOrNull(i) as? JsonObject
        val key = it?.stringOr("key").takeIf { k -> !k.isNullOrEmpty() }
        if (key != null) buildJsonObject { put("key", key) }
        else buildJsonObject { put("id", it?.stringOr("id").orEmpty()) }
    }
    // Display order as authored indices; reset when the authored list CHANGES
    // by value. Two steps on purpose: org.json's JSONArray had no equals, so
    // keying the state on the instance would reset the user's reorder on every
    // re-push, while serializing on every recomposition burned a full toString
    // each frame. The identity-keyed remember serializes once per accepted
    // snapshot; the value-keyed remember resets only when content moved.
    // C6: kotlinx JsonArray DOES implement structural equals (it delegates to
    // the backing List), so the second step is now redundant — remember(itemsJson)
    // alone would compare by value. The two steps remain CORRECT as written, and
    // collapsing them changes remember-key equality, so that is a separate pass.
    val itemsSig = remember(itemsJson) { itemsJson.toString() }
    var order by remember(itemsSig) {
        mutableStateOf((0 until itemsJson.size).toList())
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
            val item = itemsJson.getOrNull(authored) as? JsonObject ?: return@items
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
                        // SPEC 17.3: key the gesture on the item's STABLE
                        // identity, not the mutating `order` — keying on `order`
                        // restarts pointerInput mid-drag and aborts the gesture
                        // after the first swap.
                        .pointerInput(itemKey(authored)) {
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
                                        // §14.3: from/to/order injected; order
                                        // is the post-move identity-object list.
                                        ctx.actionInjecting(onReorder, buildJsonObject {
                                            put("from", dragStartPos)
                                            put("to", to)
                                            put("order", buildJsonArray {
                                                order.forEach { add(itemIdentity(it)) }
                                            })
                                        })
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

/** §17.3 pane_scaffold: M3's adaptive two- or three-pane layout. The panes are
 * placed BY WINDOW SIZE — side by side where there is room, one at a time
 * where there is not — which is why a `row` of two columns was never a
 * substitute for it: a row is the wide layout always, on every screen.
 *
 * The navigator supplies both the directive (derived from the current window)
 * and the scaffold state, so the adaptation and the back stack come from one
 * object rather than needing a window-size message on the wire. */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
internal fun RenderPaneScaffold(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val list = node.objOrNull("list") ?: return
    val detail = node.objOrNull("detail") ?: return
    val extra = node.objOrNull("extra")
    val supporting = node.stringOr("variant") == "supporting"
    // Each variant needs its OWN navigator. They differ in which pane ROLE is
    // the initial destination: the list-detail navigator opens on Secondary
    // (the list), the supporting one on Primary (the main pane). Sharing the
    // list-detail navigator across both made a single-pane `supporting`
    // scaffold surface its SUPPORTING pane first, where upstream surfaces the
    // main one — the panes were right and the entry point was wrong.
    val navigator =
        if (supporting) rememberSupportingPaneScaffoldNavigator<Any>()
        else rememberListDetailPaneScaffoldNavigator<Any>()
    val listPane: @Composable ThreePaneScaffoldPaneScope.() -> Unit = {
        AnimatedPane { RenderNode(list, ctx.child(list, 0)) }
    }
    val detailPane: @Composable ThreePaneScaffoldPaneScope.() -> Unit = {
        AnimatedPane { RenderNode(detail, ctx.child(detail, 1)) }
    }
    val extraPane: (@Composable ThreePaneScaffoldPaneScope.() -> Unit)? =
        extra?.let { { AnimatedPane { RenderNode(it, ctx.child(it, 2)) } } }
    if (supporting) SupportingPaneScaffold(
        directive = navigator.scaffoldDirective,
        scaffoldState = navigator.scaffoldState,
        mainPane = listPane,
        supportingPane = detailPane,
        extraPane = extraPane,
        modifier = m)
    else ListDetailPaneScaffold(
        directive = navigator.scaffoldDirective,
        scaffoldState = navigator.scaffoldState,
        listPane = listPane,
        detailPane = detailPane,
        extraPane = extraPane,
        modifier = m)
}

/** §17.3 app_bar_row / app_bar_column: M3's measuring overflow containers.
 *
 * `items` are {icon, label, on_tap, enabled?} records, rendered inline as
 * icon buttons while they FIT and folded into an overflow menu at measure
 * time — each folded item's label becoming its menu row. Which items fold
 * is a width decision made on the device per layout pass; Emacs never
 * learns it, which is why a static row-plus-menu split could never be
 * this component. `overflow_icon` renames the more_vert indicator;
 * `max_items` caps the inline count below what would fit. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderAppBarStrip(
    node: JsonObject, ctx: RenderCtx, m: Modifier, vertical: Boolean,
) {
    val items = node.arrOrNull("items") ?: return
    val overflowIcon = node.stringOr("overflow_icon")
    val maxItems = node.doubleOr("max_items", 0.0).toInt()
        .takeIf { it > 0 } ?: Int.MAX_VALUE
    val indicator: @Composable (AppBarMenuState) -> Unit =
        if (overflowIcon.isEmpty()) { state -> AppBarOverflowIndicator(state) }
        else { state ->
            IconButton(onClick = { state.show() }) {
                Icon(IconMap.get(overflowIcon), contentDescription = "More")
            }
        }
    val fill: AppBarScope.() -> Unit = {
        for (i in 0 until items.size) {
            val item = items[i] as? JsonObject ?: continue
            val onTap = item.objOrNull("on_tap")
            clickableItem(
                onClick = { if (onTap != null) ctx.action(onTap) },
                icon = { Icon(IconMap.get(item.stringOr("icon")),
                    contentDescription = null) },
                label = item.stringOr("label"),
                enabled = item.boolOr("enabled", true))
        }
    }
    if (vertical)
        AppBarColumn(modifier = m, overflowIndicator = indicator,
            maxItemCount = maxItems) { fill() }
    else AppBarRow(modifier = m, overflowIndicator = indicator,
        maxItemCount = maxItems) { fill() }
}

/** §17.3 carousel: M3's keyline carousel. The Companion runs ALL the
 * keyline math and the per-frame item mask; Emacs supplies `children`
 * only and never learns the width — the same device-owns-presentation
 * split as tabs' page and collapsible's expansion.
 *
 * `strategy` picks the M3 form: multi_browse (the default —
 * preferredItemWidth keylines with small items at the edges),
 * uncontained (fixed itemWidth, items run off the edge), or
 * centered_hero (one large centered item). `item_corner` is the
 * maskClip radius, applied to the item's LIVE mask rect rather than
 * the node box — a carousel clip breathes with the keylines. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class,
    androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderCarousel(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val children = node.arrOrNull("children") ?: return
    val state = rememberCarouselState { children.size }
    val spacing = (safeDp(node.doubleOr("item_spacing", 0.0)) ?: 0f).dp
    val contentPad = PaddingValues(
        horizontal = (safeDp(node.doubleOr("content_padding", 0.0)) ?: 0f).dp)
    val itemWidth = (safeDp(node.doubleOr("item_width", 186.0)) ?: 186f).dp
    val corner = node["item_corner"]?.numOrNull()
    val item: @Composable CarouselItemScope.(Int) -> Unit = { i ->
        val child = children[i] as? JsonObject
        if (child != null) {
            val mask = if (corner != null)
                Modifier.maskClip(RoundedCornerShape(corner.toFloat().dp))
            else Modifier
            Box(mask) { RenderNode(child, ctx.child(child, i)) }
        }
    }
    when (node.stringOr("strategy")) {
        "uncontained" -> HorizontalUncontainedCarousel(
            state = state, modifier = m.fillMaxWidth(),
            itemWidth = itemWidth, itemSpacing = spacing,
            contentPadding = contentPad, content = item)
        "centered_hero" -> HorizontalCenteredHeroCarousel(
            state = state, modifier = m.fillMaxWidth(),
            itemSpacing = spacing, contentPadding = contentPad,
            content = item)
        else -> HorizontalMultiBrowseCarousel(
            state = state, modifier = m.fillMaxWidth(),
            preferredItemWidth = itemWidth, itemSpacing = spacing,
            contentPadding = contentPad, content = item)
    }
}

/** §17.3 fab_menu: the checkable FAB whose menu unfolds above it.
 *
 * The ToggleFloatingActionButton drives an Add-to-Close icon morph from
 * its own checked progress (`icon`/`close_icon` name the two ends); the
 * expansion is Companion-local presentation, exactly search_bar's split —
 * a menu that snapped shut on every re-push would be unusable. Items are
 * {icon, label, on_tap} records, each a FloatingActionButtonMenuItem. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderFabMenu(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val items = node.arrOrNull("items") ?: return
    val openName = node.stringOr("icon").ifEmpty { "add" }
    val closeName = node.stringOr("close_icon").ifEmpty { "close" }
    var expanded by rememberSaveable { mutableStateOf(false) }
    FloatingActionButtonMenu(
        modifier = m,
        expanded = expanded,
        button = {
            ToggleFloatingActionButton(
                checked = expanded,
                onCheckedChange = { expanded = !expanded },
            ) {
                // The morph swaps the glyph at half progress and animates
                // it with the container — upstream's own recipe.
                val glyph by remember {
                    derivedStateOf {
                        if (checkedProgress > 0.5f) closeName else openName
                    }
                }
                with(ToggleFloatingActionButtonDefaults) {
                    Icon(
                        painter = rememberVectorPainter(IconMap.get(glyph)),
                        contentDescription =
                            if (expanded) "Close menu" else "Open menu",
                        modifier = Modifier.animateIcon({ checkedProgress }),
                    )
                }
            }
        }) {
        for (i in 0 until items.size) {
            val item = items[i] as? JsonObject ?: continue
            val onTap = item.objOrNull("on_tap")
            FloatingActionButtonMenuItem(
                onClick = {
                    expanded = false
                    if (onTap != null) ctx.action(onTap)
                },
                icon = { Icon(IconMap.get(item.stringOr("icon")),
                    contentDescription = null) },
                text = { Text(item.stringOr("label")) })
        }
    }
}

/** §17.3 button_group: M3's ButtonGroup. {label, on_tap, icon?, enabled?}
 * items whose press animation couples neighbours; what does not fit moves
 * into an overflow menu at MEASURE time — the same never-ask-Emacs width
 * rule as the app-bar strips. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderButtonGroup(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val items = node.arrOrNull("items") ?: return
    val overflowIcon = node.stringOr("overflow_icon")
    val indicator: @Composable (ButtonGroupMenuState) -> Unit =
        if (overflowIcon.isEmpty()) { state ->
            ButtonGroupDefaults.OverflowIndicator(menuState = state)
        } else { state ->
            IconButton(onClick = { state.show() }) {
                Icon(IconMap.get(overflowIcon), contentDescription = "More")
            }
        }
    ButtonGroup(modifier = m, overflowIndicator = indicator) {
        for (i in 0 until items.size) {
            val item = items[i] as? JsonObject ?: continue
            val onTap = item.objOrNull("on_tap")
            val iconName = item.stringOr("icon")
            clickableItem(
                onClick = { if (onTap != null) ctx.action(onTap) },
                label = item.stringOr("label"),
                icon = iconName.takeIf { it.isNotEmpty() }?.let {
                    { Icon(IconMap.get(it), contentDescription = null) }
                },
                enabled = item.boolOr("enabled", true))
        }
    }
}

/** §17.3 lazy_grid: LazyVerticalGrid over the child array, order preserved
 * exactly as lazy_column. `min_item_width` (GridCells.Adaptive) outranks
 * `columns` (GridCells.Fixed, default 2); `reverse` is reverseLayout —
 * the Companion never asks Emacs which end is the start. */
@Composable
internal fun RenderLazyGrid(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val children = node.arrOrNull("children") ?: return
    val minItem = node["min_item_width"]?.numOrNull()?.let { safeDp(it) }
    val cells = if (minItem != null) GridCells.Adaptive(minItem.dp)
        else GridCells.Fixed(node.doubleOr("columns", 2.0).toInt().coerceAtLeast(1))
    val spacing = (safeDp(node.doubleOr("spacing", 0.0)) ?: 0f).dp
    val pad = (safeDp(node.doubleOr("content_padding", 0.0)) ?: 0f).dp
    val gridState = androidx.compose.foundation.lazy.grid.rememberLazyGridState()
    // The §17.6 body-scroll signal; the Companion derives at-start itself,
    // reverseLayout included — never Emacs.
    LocalBodyScrollSignal.current?.let { signal ->
        val atStart by remember {
            derivedStateOf { gridState.firstVisibleItemIndex == 0 }
        }
        LaunchedEffect(atStart) { signal.atStart = atStart }
    }
    LazyVerticalGrid(
        columns = cells,
        state = gridState,
        reverseLayout = node.boolOr("reverse"),
        verticalArrangement = Arrangement.spacedBy(spacing),
        horizontalArrangement = Arrangement.spacedBy(spacing),
        contentPadding = PaddingValues(pad),
        modifier = m.fillMaxWidth()) {
        items(children.size) { i ->
            (children[i] as? JsonObject)?.let {
                RenderNode(it, ctx.child(it, i))
            }
        }
    }
}

/** §17.3 `surface.shape`: the M3 MaterialShapes polygon vocabulary, one
 * wire name per polygon, resolved to a Shape so the surface's own clip
 * carries it (upstream clips a bare Spacer the same way). */
@OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun materialShapeOf(name: String): Shape? = when (name) {
        "square" -> MaterialShapes.Square
        "slanted" -> MaterialShapes.Slanted
        "arch" -> MaterialShapes.Arch
        "fan" -> MaterialShapes.Fan
        "arrow" -> MaterialShapes.Arrow
        "semi_circle" -> MaterialShapes.SemiCircle
        "oval" -> MaterialShapes.Oval
        "pill" -> MaterialShapes.Pill
        "triangle" -> MaterialShapes.Triangle
        "diamond" -> MaterialShapes.Diamond
        "clam_shell" -> MaterialShapes.ClamShell
        "pentagon" -> MaterialShapes.Pentagon
        "gem" -> MaterialShapes.Gem
        "sunny" -> MaterialShapes.Sunny
        "very_sunny" -> MaterialShapes.VerySunny
        "cookie_4_sided" -> MaterialShapes.Cookie4Sided
        "cookie_6_sided" -> MaterialShapes.Cookie6Sided
        "cookie_7_sided" -> MaterialShapes.Cookie7Sided
        "cookie_9_sided" -> MaterialShapes.Cookie9Sided
        "cookie_12_sided" -> MaterialShapes.Cookie12Sided
        "ghostish" -> MaterialShapes.Ghostish
        "clover_4_leaf" -> MaterialShapes.Clover4Leaf
        "clover_8_leaf" -> MaterialShapes.Clover8Leaf
        "burst" -> MaterialShapes.Burst
        "soft_burst" -> MaterialShapes.SoftBurst
        "boom" -> MaterialShapes.Boom
        "soft_boom" -> MaterialShapes.SoftBoom
        "flower" -> MaterialShapes.Flower
        "puffy" -> MaterialShapes.Puffy
        "puffy_diamond" -> MaterialShapes.PuffyDiamond
        "pixel_circle" -> MaterialShapes.PixelCircle
        "pixel_triangle" -> MaterialShapes.PixelTriangle
        "bun" -> MaterialShapes.Bun
        "heart" -> MaterialShapes.Heart
    else -> null
}?.toShape()
