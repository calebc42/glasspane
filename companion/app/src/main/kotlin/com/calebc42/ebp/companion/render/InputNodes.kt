// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 17.4 input nodes, ported from poc-v1's SduiInputNodes/SduiRenderer with
// the format-6 vocabulary applied:
// - `enabled` honored on EVERY input (§17.4: disabled affordance + total
//   dispatch suppression) — poc-v1 ignored it everywhere.
// - checkbox/switch publish state.changed FIRST (a JSON boolean, not a
//   string), then on_change with the boolean injected as args.value.
// - enum_list options are {label, value} OBJECTS (poc-v1: plain strings);
//   no implicit first selection (null / []); allow_add publishes a new string
//   value without mutating the authored option list.
// - slider is continuous (min/max) OR discrete (`values`, returning the EXACT
//   authored number — no toolkit step arithmetic); dispatches once on commit.
// - button gains its §17.4 variant (filled/tonal/outlined/text) and icon.
// The poc ActionReceiver/debounce plumbing is replaced by ctx.state/action on
// the single ordered dispatch executor (state-before-action holds by FIFO).
package com.calebc42.ebp.companion.render

import android.icu.util.Calendar
import android.icu.util.TimeZone
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ButtonShapes
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.DropdownMenuGroup
import androidx.compose.material3.ToggleButtonShapes
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDefaults
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DockedSearchBar
import androidx.compose.material3.DisplayMode
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedAssistChip
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.ElevatedFilterChip
import androidx.compose.material3.ElevatedSuggestionChip
import androidx.compose.material3.ElevatedToggleButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.InputChip
import androidx.compose.material3.InputChipDefaults
import androidx.compose.material3.Label
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.ModalWideNavigationRail
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.MultiChoiceSegmentedButtonRow
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedToggleButton
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.RadioButton
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.RangeSliderState
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.SliderState
import androidx.compose.material3.SplitButtonDefaults
import androidx.compose.material3.SplitButtonLayout
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimeInput
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TimePickerDialog
import androidx.compose.material3.TimePickerDialogDefaults
import androidx.compose.material3.TimePickerDisplayMode
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.ToggleButtonDefaults
import androidx.compose.material3.TonalToggleButton
import androidx.compose.material3.TriStateCheckbox
import androidx.compose.material3.VerticalSlider
import androidx.compose.material3.WideNavigationRail
import androidx.compose.material3.WideNavigationRailItem
import androidx.compose.material3.WideNavigationRailValue
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.material3.rememberWideNavigationRailState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.calebc42.ebp.wire.SurfaceStore
import com.calebc42.ebp.wire.jsonValueEquals
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** §17.4 `button.size`: the M3 container scale. A step is a COORDINATED token
 * set — height, content padding, icon size, icon spacing and label typography
 * all derive from the one height — so it is resolved once, here, and never
 * applied in part: a container stretched around unscaled content is a
 * different component, not a larger one. An unrecognized value falls back to
 * the unscaled default per §12 rule 6. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
private fun buttonHeightOf(name: String): Dp? = when (name) {
    "xsmall" -> ButtonDefaults.ExtraSmallContainerHeight
    "small" -> ButtonDefaults.MinHeight
    "medium" -> ButtonDefaults.MediumContainerHeight
    "large" -> ButtonDefaults.LargeContainerHeight
    "xlarge" -> ButtonDefaults.ExtraLargeContainerHeight
    else -> null
}

/** §17.4 `checked` on button/icon_button: device-held toggle state keyed on
 * the node's id, seeded from the store (the user's draft) and falling back to
 * the authored member — the same machine RenderCheckbox uses, including its
 * state-BEFORE-action ordering (§14.6). A node without `checked` is not
 * stateful at all and never reaches here. */
@Composable
private fun rememberToggle(node: JsonObject, ctx: RenderCtx, id: String): MutableState<Boolean> =
    rememberSaveable(ctx.surface, id, ctx.epochOf(id),
        key = "tg:${ctx.surface}:$id:${ctx.epochOf(id)}") {
        mutableStateOf((ctx.storeValue(id) as? JsonPrimitive)
            ?.takeIf { !it.isString }?.content?.toBooleanStrictOrNull()
            ?: node.boolOr("checked"))
    }

/** §17.4 button with variant/size/shape/animate_shape/icon/checked/enabled. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderButton(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val enabled = node.boolOr("enabled", true)
    val onTap = node.objOrNull("on_tap")
    val iconName = node.stringOr("icon")
    val isToggle = "checked" in node
    val id = node.stringOr("id")
    val toggle = if (isToggle) rememberToggle(node, ctx, id) else null
    val onChange = node.objOrNull("on_change")
    val onClick = if (toggle != null) {
        {
            val next = !toggle.value
            toggle.value = next
            ctx.state(id, JsonPrimitive(next))          // §14.6 state first
            // ONE action per tap. A toggle's semantic event is on_change; the
            // required on_tap is the fallback for a toggle that authors none.
            // Firing both would double-dispatch every tap.
            if (onChange != null) ctx.action(onChange, JsonPrimitive(next))
            else onButton(onTap, ctx)
        }
    } else { { onButton(onTap, ctx) } }
    val h = buttonHeightOf(node.stringOr("size"))
    // Absent `size` keeps the literals this renderer has always used, so no
    // existing traffic changes meaning.
    val pad = if (h != null) ButtonDefaults.contentPaddingFor(h)
        else PaddingValues(horizontal = 12.dp, vertical = 8.dp)
    val iconSize = if (h != null) ButtonDefaults.iconSizeFor(h) else 18.dp
    val iconGap = if (h != null) ButtonDefaults.iconSpacingFor(h) else 6.dp
    val mm = if (h != null) m.heightIn(min = h) else m
    // §17.4 `expanded`: absent/true is icon+label as always; false is the
    // icon-only FAB; "auto" derives from the scaffold body's own scroll
    // signal — expanded while the body rests at its start — entirely
    // device-local, so no per-scroll traffic ever crosses the wire.
    val hasExpanded = "expanded" in node
    val expandedNow = when (val e = node["expanded"]) {
        is JsonPrimitive ->
            if (e.isString)
                e.content != "auto" ||
                    (LocalBodyScrollSignal.current?.atStart ?: true)
            else e.content.toBooleanStrictOrNull() ?: true
        else -> true
    }
    // §17.4 `checked_icon`: the glyph drawn while the LIVE checked state is
    // true (upstream swaps Outlined for Filled) — `icon` stays the resting one.
    val checkedIconName = node.stringOr("checked_icon")
    val shownIcon = if (toggle?.value == true && checkedIconName.isNotEmpty())
        checkedIconName else iconName
    val content: @Composable () -> Unit = {
        if (shownIcon.isNotEmpty())
            Icon(IconMap.get(shownIcon), null, Modifier.size(iconSize))
        val label = @Composable {
            Text(node.stringOr("label"), maxLines = 1, softWrap = false,
                overflow = TextOverflow.Ellipsis)
        }
        val styled = @Composable {
            if (h != null) ProvideTextStyle(ButtonDefaults.textStyleFor(h)) { label() }
            else label()
        }
        if (hasExpanded)
            // The label animates in and out the way ExtendedFAB's own
            // expanded parameter does; the icon stays put.
            androidx.compose.animation.AnimatedVisibility(
                visible = expandedNow,
                enter = androidx.compose.animation.fadeIn() +
                    androidx.compose.animation.expandHorizontally(),
                exit = androidx.compose.animation.fadeOut() +
                    androidx.compose.animation.shrinkHorizontally()) {
                Row {
                    if (shownIcon.isNotEmpty())
                        androidx.compose.foundation.layout.Spacer(
                            Modifier.size(iconGap))
                    styled()
                }
            }
        else {
            if (shownIcon.isNotEmpty())
                androidx.compose.foundation.layout.Spacer(Modifier.size(iconGap))
            styled()
        }
    }
    // `shape` names the container's OWN shape, which universal `corner` cannot
    // reach — that decorates the modifier outside minimumInteractiveComponentSize,
    // i.e. the 48dp touch box rather than the container.
    val square = node.stringOr("shape") == "square"
    val shapes: ButtonShapes? = when {
        !node.boolOr("animate_shape") -> null
        h != null -> ButtonDefaults.shapesFor(h)
        else -> ButtonDefaults.shapes()
    }
    val variant = node.stringOr("variant")
    // A `checked` button is M3's ToggleButton, not a Button wearing state: the
    // toggle has its OWN checked container and its own selected/unselected
    // shape pair, so holding the boolean while drawing a plain Button would
    // make checked and unchecked look identical — the state would be real and
    // invisible, which is the defect class this whole pass exists to remove.
    if (toggle != null) {
        val onCheckedChange: (Boolean) -> Unit = { onClick() }
        // §17.4: on a toggle, `shape` names the RESTING shape and
        // `checked_shape` the one it morphs to while checked — so the
        // inverted square-at-rest/round-checked set is two members, each
        // saying exactly one thing. (`shape` on a toggle used to be read
        // and silently ignored; this closes that too.)
        val checkedShapeName = node.stringOr("checked_shape")
        val base = ToggleButtonDefaults.shapesFor(h ?: ButtonDefaults.MinHeight)
        // §17.4 `shape_role`: one position of a CONNECTED group. The M3
        // leading/middle/trailing shape sets carry the caps, the press morph
        // and the checked morph; top/bottom are the vertical caps upstream
        // builds by copying CornerSize(100) onto the middle shape.
        val roleShapes: ToggleButtonShapes? = when (node.stringOr("shape_role")) {
            "leading" -> ButtonGroupDefaults.connectedLeadingButtonShapes()
            "middle" -> ButtonGroupDefaults.connectedMiddleButtonShapes()
            "trailing" -> ButtonGroupDefaults.connectedTrailingButtonShapes()
            "top", "bottom" -> {
                val mid = ButtonGroupDefaults.connectedMiddleButtonShapes()
                val midShape = mid.shape as? RoundedCornerShape
                val capped = if (midShape != null) {
                    if (node.stringOr("shape_role") == "top")
                        midShape.copy(topStart = CornerSize(100), topEnd = CornerSize(100))
                    else
                        midShape.copy(bottomStart = CornerSize(100), bottomEnd = CornerSize(100))
                } else mid.shape
                ToggleButtonShapes(shape = capped,
                    pressedShape = mid.pressedShape,
                    checkedShape = ButtonGroupDefaults.connectedButtonCheckedShape)
            }
            else -> null
        }
        val tShapes = if (roleShapes != null) roleShapes
        else if (square || checkedShapeName.isNotEmpty())
            ToggleButtonDefaults.shapes(
                shape = if (square) ToggleButtonDefaults.squareShape
                    else ToggleButtonDefaults.roundShape,
                pressedShape = base.pressedShape,
                checkedShape = when (checkedShapeName) {
                    "round" -> ToggleButtonDefaults.roundShape
                    "square" -> ToggleButtonDefaults.squareShape
                    else -> base.checkedShape
                })
        else base
        when (variant) {
            "elevated" -> ElevatedToggleButton(toggle.value, onCheckedChange, mm,
                enabled, shapes = tShapes, contentPadding = pad) { content() }
            "tonal" -> TonalToggleButton(toggle.value, onCheckedChange, mm,
                enabled, shapes = tShapes, contentPadding = pad) { content() }
            "outlined" -> OutlinedToggleButton(toggle.value, onCheckedChange, mm,
                enabled, shapes = tShapes, contentPadding = pad) { content() }
            else -> ToggleButton(toggle.value, onCheckedChange, mm,
                enabled, shapes = tShapes, contentPadding = pad) { content() }
        }
        return
    }
    if (shapes != null) {
        // The shapes= overloads carry the press-state morph. They take
        // `shapes` as the SECOND positional parameter, so every argument here
        // is named — positional order differs from the shape= overloads.
        when (variant) {
            "text" -> TextButton(onClick = onClick, shapes = shapes,
                modifier = mm, enabled = enabled, contentPadding = pad) { content() }
            "outlined" -> OutlinedButton(onClick = onClick, shapes = shapes,
                modifier = mm, enabled = enabled, contentPadding = pad) { content() }
            "tonal" -> FilledTonalButton(onClick = onClick, shapes = shapes,
                modifier = mm, enabled = enabled, contentPadding = pad) { content() }
            "elevated" -> ElevatedButton(onClick = onClick, shapes = shapes,
                modifier = mm, enabled = enabled, contentPadding = pad) { content() }
            else -> Button(onClick = onClick, shapes = shapes,
                modifier = mm, enabled = enabled, contentPadding = pad) { content() }
        }
    } else {
        val shape = if (square) ButtonDefaults.squareShape else ButtonDefaults.shape
        when (variant) {
            "text" -> TextButton(onClick, mm, enabled, shape = shape, contentPadding = pad) { content() }
            "outlined" -> OutlinedButton(onClick, mm, enabled, shape = shape, contentPadding = pad) { content() }
            "tonal" -> FilledTonalButton(onClick, mm, enabled, shape = shape, contentPadding = pad) { content() }
            "elevated" -> ElevatedButton(onClick, mm, enabled, shape = shape, contentPadding = pad) { content() }
            else -> Button(onClick, mm, enabled, shape = shape, contentPadding = pad) { content() }
        }
    }
}

/** §17.4 icon_button: icon + on_tap, badge/content_description/variant/
 * size/shape/width_mode/checked/enabled. Omitted `variant` keeps the plain,
 * container-less IconButton and omitted `size` keeps its baseline geometry. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderIconButton(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val badge = node.stringOr("badge")
    val enabled = node.boolOr("enabled", true)
    val isToggle = "checked" in node
    val id = node.stringOr("id")
    val toggle = if (isToggle) rememberToggle(node, ctx, id) else null
    val onChange = node.objOrNull("on_change")
    val onTap = node.objOrNull("on_tap")
    val onClick = if (toggle != null) {
        {
            val next = !toggle.value
            toggle.value = next
            ctx.state(id, JsonPrimitive(next))
            // One action per tap — see RenderButton.
            if (onChange != null) ctx.action(onChange, JsonPrimitive(next))
            else onButton(onTap, ctx)
        }
    } else { { onButton(onTap, ctx) } }
    // `checked_icon` swaps the glyph while checked; IconMap is the only path a
    // vector reaches the device, so the swap is by NAME.
    val checkedIcon = node.stringOr("checked_icon")
    val shownIcon = if (toggle?.value == true && checkedIcon.isNotEmpty())
        checkedIcon else node.stringOr("icon")
    // §17.4 icon_button geometry. A size step is a coordinated set here too:
    // the CONTAINER grows via IconButtonDefaults.<step>ContainerSize(width) and
    // the inner Icon must be sized to match, because RenderIconButton draws it
    // with no size modifier at all — a container member alone would leave a
    // baseline glyph rattling inside a large button.
    val sizeName = node.stringOr("size")
    val square = node.stringOr("shape") == "square"
    val widthOption = when (node.stringOr("width_mode")) {
        "narrow" -> IconButtonDefaults.IconButtonWidthOption.Narrow
        "wide" -> IconButtonDefaults.IconButtonWidthOption.Wide
        else -> IconButtonDefaults.IconButtonWidthOption.Uniform
    }
    val containerSize = when (sizeName) {
        "xsmall" -> IconButtonDefaults.extraSmallContainerSize(widthOption)
        "small" -> IconButtonDefaults.smallContainerSize(widthOption)
        "medium" -> IconButtonDefaults.mediumContainerSize(widthOption)
        "large" -> IconButtonDefaults.largeContainerSize(widthOption)
        else -> null
    }
    val stepShape = when (sizeName) {
        "xsmall" -> if (square) IconButtonDefaults.extraSmallSquareShape else IconButtonDefaults.extraSmallRoundShape
        "small" -> if (square) IconButtonDefaults.smallSquareShape else IconButtonDefaults.smallRoundShape
        "medium" -> if (square) IconButtonDefaults.mediumSquareShape else IconButtonDefaults.mediumRoundShape
        "large" -> if (square) IconButtonDefaults.largeSquareShape else IconButtonDefaults.largeRoundShape
        else -> null
    }
    val glyphSize = when (sizeName) {
        "xsmall" -> IconButtonDefaults.extraSmallIconSize
        "small" -> IconButtonDefaults.smallIconSize
        "medium" -> IconButtonDefaults.mediumIconSize
        "large" -> IconButtonDefaults.largeIconSize
        else -> null
    }
    val mm = if (containerSize != null) m.size(containerSize) else m
    // §17.4 `color`: the Icon's tint — the one member TintedIconButtonSample
    // exists for. The node draws its own Icon, so without this no §16.6 color
    // could ever reach the glyph.
    val iconTint = resolveColor(node.stringOr("color").takeIf { it.isNotEmpty() })
    val body: @Composable () -> Unit = {
        val icon: @Composable () -> Unit = {
            Icon(IconMap.get(shownIcon),
                modifier = if (glyphSize != null) Modifier.size(glyphSize) else Modifier,
                tint = iconTint ?: LocalContentColor.current,
                contentDescription = node.stringOr("content_description")
                    .takeIf { it.isNotEmpty() })
        }
        if (badge.isNotEmpty())
            BadgedBox(badge = { Badge { Text(badge) } }) { icon() }
        else icon()
    }
    when (node.stringOr("variant")) {
        "filled" -> if (stepShape != null)
            FilledIconButton(onClick, mm, enabled, shape = stepShape) { body() }
            else FilledIconButton(onClick, mm, enabled) { body() }
        "tonal" -> if (stepShape != null)
            FilledTonalIconButton(onClick, mm, enabled, shape = stepShape) { body() }
            else FilledTonalIconButton(onClick, mm, enabled) { body() }
        "outlined" -> if (stepShape != null)
            OutlinedIconButton(onClick, mm, enabled, shape = stepShape) { body() }
            else OutlinedIconButton(onClick, mm, enabled) { body() }
        else -> IconButton(onClick, mm, enabled) { body() }
    }
}

/** §17.4 chip: selectable filter chip. `selected` is authored presentation
 * state; the tap dispatches — Emacs flips selected on the next snapshot. */
@Composable
internal fun RenderChip(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.objOrNull("on_tap")
    val iconName = node.stringOr("icon")
    val trailingName = node.stringOr("trailing_icon")
    val selected = node.boolOr("selected")
    val enabled = node.boolOr("enabled", true)
    val click = { if (onTap != null) onButton(onTap, ctx) }
    val label: @Composable () -> Unit = { Text(node.stringOr("label")) }
    val lead: (@Composable () -> Unit)? = if (iconName.isNotEmpty()) {
        { Icon(IconMap.get(iconName), null, Modifier.size(18.dp)) }
    } else null
    // `icon` has always been spent on leadingIcon; the trailing slot was
    // simply never passed, so an authored trailing affordance vanished.
    val trail: (@Composable () -> Unit)? = if (trailingName.isNotEmpty()) {
        { Icon(IconMap.get(trailingName), null, Modifier.size(18.dp)) }
    } else null
    // §17.4 `avatar`: InputChip's 24dp circular slot — distinct from the
    // 18dp leadingIcon, which is why it is its own member (input only).
    val avatarName = node.stringOr("avatar")
    val avatar: (@Composable () -> Unit)? = if (avatarName.isNotEmpty()) {
        { Icon(IconMap.get(avatarName), null,
            Modifier.size(InputChipDefaults.AvatarSize)) }
    } else null
    // §17.4 `content_spacing`: the gap between the chip's own slots —
    // FilterChipDefaults.horizontalArrangement, not a modifier.
    val spacing = node["content_spacing"]?.numOrNull()
    when (node.stringOr("variant")) {
        "elevated" -> ElevatedFilterChip(selected, click, label, m, enabled,
            leadingIcon = lead, trailingIcon = trail)
        "input" -> InputChip(selected, click, label, m, enabled,
            leadingIcon = lead, avatar = avatar, trailingIcon = trail)
        else ->
            if (spacing != null)
                FilterChip(selected, click, label, m, enabled,
                    leadingIcon = lead, trailingIcon = trail,
                    horizontalArrangement =
                        FilterChipDefaults.horizontalArrangement(
                            spacing.toFloat().dp))
            else FilterChip(selected, click, label, m, enabled,
                leadingIcon = lead, trailingIcon = trail)
    }
}

@Composable
internal fun RenderAssistChip(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.objOrNull("on_tap")
    val iconName = node.stringOr("icon")
    val enabled = node.boolOr("enabled", true)
    val click = { if (onTap != null) onButton(onTap, ctx) }
    val label: @Composable () -> Unit = { Text(node.stringOr("label")) }
    val lead: (@Composable () -> Unit)? = if (iconName.isNotEmpty()) {
        { Icon(IconMap.get(iconName), null, Modifier.size(18.dp)) }
    } else null
    when (node.stringOr("variant")) {
        "elevated" -> ElevatedAssistChip(click, label, m, enabled, leadingIcon = lead)
        // A SuggestionChip's single graphic slot IS its icon slot, so the
        // authored `icon` rides it rather than being dropped.
        "suggestion" -> SuggestionChip(click, label, m, enabled, icon = lead)
        "elevated_suggestion" ->
            ElevatedSuggestionChip(click, label, m, enabled, icon = lead)
        else -> AssistChip(click, label, m, enabled, leadingIcon = lead)
    }
}

/** §17.4 menu: an overflow icon opening a dropdown; each item dispatches its
 * on_tap and closes the menu. */
@Composable
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
internal fun RenderMenu(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    var open by remember { mutableStateOf(false) }
    val items = node.arrOrNull("items")
    val groups = node.arrOrNull("groups")
    val scrollState = rememberScrollState()
    // `initial_scroll: end` — the literal upstream effect: every open lands
    // the popup at the bottom of a list longer than the screen.
    if (node.stringOr("initial_scroll") == "end") {
        LaunchedEffect(open) { if (open) scrollState.scrollTo(scrollState.maxValue) }
    }
    Box(modifier = m) {
        IconButton(
            onClick = { open = true },
            enabled = node.boolOr("enabled", true)) {
            Icon(IconMap.get(node.stringOr("icon", "more_vert")),
                contentDescription = "More")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false },
            scrollState = scrollState) {
            if (groups != null) for (g in 0 until groups.size) {
                val group = groups[g] as? JsonObject ?: continue
                if (g > 0) Spacer(Modifier.height(MenuDefaults.GroupSpacing))
                DropdownMenuGroup(shapes = MenuDefaults.groupShape(g, groups.size)) {
                    val label = group.stringOr("label")
                    if (label.isNotEmpty()) {
                        Text(label,
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier
                                .padding(MenuDefaults.DropdownMenuGroupLabelHorizontalPadding)
                                .padding(vertical = 8.dp))
                        HorizontalDivider(
                            modifier = Modifier.padding(MenuDefaults.HorizontalDividerPadding))
                    }
                    val gi = group.arrOrNull("items")
                    if (gi != null) for (i in 0 until gi.size) {
                        (gi[i] as? JsonObject)?.let { item ->
                            MenuItemRow(item, ctx, i, gi.size) { open = false }
                        }
                    }
                }
            }
            if (items != null) for (i in 0 until items.size) {
                val item = items[i] as? JsonObject ?: continue
                MenuItemRow(item, ctx, null, 0) { open = false }
            }
            // The footer is popup content below the items — the client
            // includes or omits it per its own state (SPEC 17.4).
            node.objOrNull("footer")?.let { RenderNode(it, ctx) }
        }
    }
}

/** One MenuItem row. `checked` present selects the M3 expressive checkable
 * overload: checked is AUTHORED presentation state (the client flips it on
 * the next snapshot, like chip.selected), checked_icon replaces the leading
 * icon while checked, and a toggle keeps the popup open the way upstream
 * checkable menus do. INDEX/COUNT carry the group item shapes when grouped. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun MenuItemRow(
    item: JsonObject, ctx: RenderCtx,
    index: Int?, count: Int, closeMenu: () -> Unit,
) {
    // SPEC 17.4: a disabled MenuItem shows the disabled affordance and MUST
    // NOT dispatch.
    val itemEnabled = item.boolOr("enabled", true)
    val itemIcon = item.stringOr("icon")
    val trailingIcon = item.stringOr("trailing_icon")
    val supporting = item.stringOr("supporting_text")
    val leading: (@Composable () -> Unit)? = if (itemIcon.isNotEmpty()) {
        { Icon(IconMap.get(itemIcon), null, Modifier.size(18.dp)) }
    } else null
    val trailing: (@Composable () -> Unit)? = if (trailingIcon.isNotEmpty()) {
        { Icon(IconMap.get(trailingIcon), null, Modifier.size(18.dp)) }
    } else null
    val supportingText: (@Composable () -> Unit)? = if (supporting.isNotEmpty()) {
        { Text(supporting) }
    } else null
    if ("checked" in item) {
        val checkedIcon = item.stringOr("checked_icon", "check")
        DropdownMenuItem(
            text = { Text(item.stringOr("label")) },
            checked = item.boolOr("checked", false),
            onCheckedChange = {
                if (itemEnabled) item.objOrNull("on_tap")?.let { onButton(it, ctx) }
            },
            supportingText = supportingText,
            shapes = if (index != null) MenuDefaults.itemShape(index, count)
                else MenuDefaults.itemShape(0, 1),
            leadingIcon = leading,
            checkedLeadingIcon = {
                Icon(IconMap.get(checkedIcon), null, Modifier.size(18.dp))
            },
            trailingIcon = trailing,
            enabled = itemEnabled)
    } else {
        DropdownMenuItem(
            text = { Text(item.stringOr("label")) },
            enabled = itemEnabled,
            onClick = {
                closeMenu()
                if (itemEnabled) item.objOrNull("on_tap")?.let { onButton(it, ctx) }
            },
            leadingIcon = leading,
            trailingIcon = trailing)
    }
}

// §17.4: every flip produces state.changed (boolean), then on_change with the
// boolean in args.value — in that order (the single executor preserves it).
/** §17.4 checkbox. Plain: a boolean keyed on `id`. `state` present makes it
 * M3's TriStateCheckbox over off|on|indeterminate — a click cycles
 * indeterminate/off -> on -> off, publishes the ENUM STRING (not a boolean)
 * first, then dispatches on_change with it injected. `stroke`
 * ({width?, cap?, join?}) reaches Checkbox's checkmarkStroke/outlineStroke
 * pair — the rounded-strokes samples are exactly this member. */
@Composable
internal fun RenderCheckbox(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true)
    val onChange = node.objOrNull("on_change")
    val strokes = node.objOrNull("stroke")?.let { spec ->
        val width = with(LocalDensity.current) {
            ((spec["width"]?.numOrNull()?.toFloat())?.dp
                ?: CheckboxDefaults.StrokeWidth).toPx()
        }
        val cap = when (spec.stringOr("cap")) {
            "butt" -> StrokeCap.Butt
            "square" -> StrokeCap.Square
            else -> StrokeCap.Round
        }
        val join = when (spec.stringOr("join")) {
            "miter" -> StrokeJoin.Miter
            "bevel" -> StrokeJoin.Bevel
            else -> StrokeJoin.Round
        }
        Stroke(width = width, cap = cap, join = join)
    }
    val label: @Composable () -> Unit = {
        node.stringOr("label").takeIf { it.isNotEmpty() }?.let {
            Text(it, modifier = Modifier.padding(start = 8.dp))
        }
    }
    if ("state" in node) {
        var tri by rememberSaveable(ctx.surface, id, ctx.epochOf(id),
            key = "in:${ctx.surface}:$id:${ctx.epochOf(id)}") {
            mutableStateOf((ctx.storeValue(id) as? JsonPrimitive)
                ?.takeIf { it.isString && it.content in SurfaceStore.TRI_STATES }
                ?.content ?: node.stringOr("state").ifEmpty { "off" })
        }
        val toggleable = when (tri) {
            "on" -> ToggleableState.On
            "indeterminate" -> ToggleableState.Indeterminate
            else -> ToggleableState.Off
        }
        val onClick = {
            tri = if (tri == "on") "off" else "on"
            ctx.state(id, JsonPrimitive(tri))
            if (onChange != null) ctx.action(onChange, JsonPrimitive(tri))
        }
        Row(verticalAlignment = Alignment.CenterVertically, modifier = m) {
            if (strokes != null)
                TriStateCheckbox(state = toggleable, onClick = onClick,
                    checkmarkStroke = strokes, outlineStroke = strokes,
                    enabled = enabled)
            else TriStateCheckbox(state = toggleable, onClick = onClick,
                enabled = enabled)
            label()
        }
        return
    }
    var checked by rememberSaveable(ctx.surface, id, ctx.epochOf(id),
        key = "in:${ctx.surface}:$id:${ctx.epochOf(id)}") {
        // C6: the store value is a JsonElement, so `as? Boolean` would compile
        // and be ALWAYS null — the widget would silently revert to the authored
        // value while the store still holds the user's draft (the LD-2
        // divergence). Read the boolean out of the primitive explicitly; a
        // JSON string "true" is not a boolean (SpecValidator gates the member).
        mutableStateOf((ctx.storeValue(id) as? JsonPrimitive)
            ?.takeIf { !it.isString }?.content?.toBooleanStrictOrNull()
            ?: node.boolOr("checked"))
    }
    val flip: (Boolean) -> Unit = {
        checked = it
        ctx.state(id, JsonPrimitive(it))
        if (onChange != null) ctx.action(onChange, JsonPrimitive(it))
    }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = m) {
        if (strokes != null)
            Checkbox(checked = checked, onCheckedChange = flip,
                checkmarkStroke = strokes, outlineStroke = strokes,
                enabled = enabled)
        else Checkbox(checked = checked, enabled = enabled, onCheckedChange = flip)
        label()
    }
}

@Composable
internal fun RenderSwitch(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true)
    var checked by rememberSaveable(ctx.surface, id, ctx.epochOf(id),
        key = "in:${ctx.surface}:$id:${ctx.epochOf(id)}") {
        // C6: the explicit primitive read, same reasoning as RenderCheckbox.
        mutableStateOf((ctx.storeValue(id) as? JsonPrimitive)
            ?.takeIf { !it.isString }?.content?.toBooleanStrictOrNull()
            ?: node.boolOr("checked"))
    }
    val onChange = node.objOrNull("on_change")
    Row(verticalAlignment = Alignment.CenterVertically, modifier = m) {
        node.stringOr("label").takeIf { it.isNotEmpty() }?.let {
            Text(it, modifier = Modifier.weight(1f))
        }
        val thumbIcon = node.stringOr("thumb_icon")
        Switch(checked = checked, enabled = enabled,
            // Drawn only while the LIVE checked value is true, matching the
            // upstream sample's own lambda.
            thumbContent = if (thumbIcon.isNotEmpty() && checked) {
                { Icon(IconMap.get(thumbIcon), null,
                    Modifier.size(SwitchDefaults.IconSize)) }
            } else null,
            onCheckedChange = {
            checked = it
            ctx.state(id, JsonPrimitive(it))
            if (onChange != null) ctx.action(onChange, JsonPrimitive(it))
        })
    }
}

/**
 * §17.4 enum_list: options are {label, value} objects; selection is tracked
 * by option INDEX (publishing the exact authored scalar), plus locally added
 * string values under allow_add (published like a selection, never mutating
 * the authored list). No implicit first selection: an omitted value is null /
 * [] until the user chooses.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun RenderEnumList(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true)
    val multi = node.boolOr("multi_select")
    val allowAdd = node.boolOr("allow_add")
    val onChange = node.objOrNull("on_change")
    val options = node.arrOrNull("options") ?: JsonArray(emptyList())

    val optionValues = options.mapNotNull { (it as? JsonObject)?.get("value") }
    // Seed selection from the authored value (§4.3 equality), keeping only
    // values that match an authored option.
    fun seedValues(): List<JsonElement> {
        // T3/LD-2: the store's value (the draft when one stands, else the
        // authored value) — the node member is only the fallback.
        val v = ctx.storeValue(id) ?: node["value"] ?: return emptyList()
        val wanted: List<JsonElement> = if (v is JsonArray)
            v.toList() else listOf(v)
        return wanted.filter { w -> optionValues.any { jsonValueEquals(w, it) } }
    }
    // SPEC 16.1/13.6: input drafts key on the wire address (surface+id), NOT the
    // key-first presentation path — changing only a `key` keeps the draft.
    // Selection is retained by VALUE, not index, so a same-identity re-push that
    // reorders/changes options never re-points a stale index at a new value.
    var selectedValues by remember(ctx.surface, id, ctx.epochOf(id)) {
        mutableStateOf(seedValues())
    }
    var added by remember(ctx.surface, id, ctx.epochOf(id)) { mutableStateOf(listOf<String>()) }
    var selectedAdded by remember(ctx.surface, id, ctx.epochOf(id)) { mutableStateOf(setOf<String>()) }
    var showAdd by remember { mutableStateOf(false) }

    // SPEC 17.4 (audit I7): drop a retained selected value that the new options
    // no longer offer, mirroring the tabs invalid-index reset. Identity-keyed
    // serialize (once per accepted snapshot), value-keyed effect — a bare
    // toString here re-serialized the options on every recomposition.
    val optSig = remember(options) { options.toString() }
    LaunchedEffect(optSig) {
        val pruned = selectedValues.filter { s -> optionValues.any { jsonValueEquals(s, it) } }
        if (pruned.size != selectedValues.size) selectedValues = pruned
    }
    fun isSelected(optValue: JsonElement?): Boolean =
        optValue != null && selectedValues.any { jsonValueEquals(it, optValue) }

    fun currentValue(): JsonElement? {
        // A locally added option is a new STRING value: it becomes a
        // JsonPrimitive here so both the multi array and the single-value arm
        // carry JSON elements.
        val values = selectedValues + selectedAdded.map(::JsonPrimitive)
        // C6: `JsonNull`, never Kotlin null. This value reaches putDraft, and
        // the draft feeds back into the seeding elvis at storeValue(id) ?:
        // node["value"] — a Kotlin null would fall through and re-seed a
        // selection the user just cleared. On the wire both spell `null`.
        return if (multi) JsonArray(values)
        else values.firstOrNull() ?: JsonNull
    }

    fun publish() {
        val v = currentValue()
        ctx.state(id, v)
        if (onChange != null) ctx.action(onChange, v)
    }

    // SPEC 17.4 `variant` radio / `children`: the SAME id/options/value/
    // on_change state path rendered as one selectable ROW per option —
    // RadioButton targets in a selectableGroup for single-select, Checkbox
    // rows for multi — with the parallel child node as the row body when
    // `children` is authored (its universal attributes ride, so a segmented
    // bg/corner reaches each row whole). allow_add stays a chips-only
    // affordance; the elisp constructor refuses the pairing.
    val childRows = node.arrOrNull("children")
    if (node.stringOr("variant") == "radio" || childRows != null) {
        Column(modifier = m.fillMaxWidth().selectableGroup()) {
            for (i in 0 until options.size) {
                val opt = options[i] as? JsonObject ?: continue
                val ov = opt["value"] ?: continue
                val selected = isSelected(ov)
                val toggle = {
                    selectedValues = when {
                        multi && selected ->
                            selectedValues.filterNot { jsonValueEquals(it, ov) }
                        multi -> selectedValues + ov
                        else -> listOf(ov)
                    }
                    publish()
                }
                val child = childRows?.getOrNull(i) as? JsonObject
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                        .selectable(selected = selected, enabled = enabled,
                            role = if (multi) Role.Checkbox else Role.RadioButton,
                            onClick = toggle)
                        .padding(horizontal = 16.dp, vertical = 8.dp)) {
                    if (multi)
                        Checkbox(checked = selected, onCheckedChange = null,
                            enabled = enabled)
                    else RadioButton(selected = selected, onClick = null,
                        enabled = enabled)
                    androidx.compose.foundation.layout.Spacer(
                        Modifier.size(16.dp))
                    if (child != null) RenderNode(child, ctx.child(child, i))
                    else Text(opt.stringOr("label"))
                }
            }
        }
        return
    }
    FlowRow(
        modifier = m.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (i in 0 until options.size) {
            val opt = options[i] as? JsonObject ?: continue
            val ov = opt["value"]
            FilterChip(
                selected = isSelected(ov),
                enabled = enabled,
                onClick = {
                    if (ov == null) return@FilterChip
                    selectedValues = when {
                        isSelected(ov) -> selectedValues.filterNot { jsonValueEquals(it, ov) }
                        multi -> selectedValues + ov
                        else -> listOf(ov).also { selectedAdded = emptySet() }
                    }
                    publish()
                },
                label = { Text(opt.stringOr("label")) })
        }
        for (extra in added) {
            FilterChip(
                selected = extra in selectedAdded,
                enabled = enabled,
                onClick = {
                    selectedAdded = if (extra in selectedAdded) selectedAdded - extra
                    else (if (multi) selectedAdded + extra else setOf(extra))
                        .also { if (!multi) selectedValues = emptyList() }
                    publish()
                },
                label = { Text(extra) })
        }
        if (allowAdd) AssistChip(
            enabled = enabled,
            onClick = { showAdd = true },
            label = { Text("+ Add") })
    }

    if (showAdd) {
        var newOption by remember { mutableStateOf("") }
        val commit = {
            val v = newOption.trim()
            if (v.isNotEmpty() && v !in added) {
                added = added + v
                selectedAdded = if (multi) selectedAdded + v else setOf(v)
                if (!multi) selectedValues = emptyList()
                publish()
            }
            showAdd = false
        }
        AlertDialog(
            onDismissRequest = { showAdd = false },
            title = { Text("Add option") },
            text = {
                OutlinedTextField(value = newOption,
                    onValueChange = { newOption = it }, singleLine = true)
            },
            confirmButton = { TextButton(onClick = commit) { Text("Add") } },
            dismissButton = {
                TextButton(onClick = { showAdd = false }) { Text("Cancel") }
            })
    }
}

/**
 * §17.4 slider. Continuous: min/max/value, dispatching once on gesture
 * commit. Discrete: `values` (strictly increasing authored numbers) — the
 * thumb moves over indices and the EXACT authored number is returned, never
 * toolkit step arithmetic. `value_end` present makes it a RangeSlider and
 * the published value a two-number array; with `values` authored each thumb
 * SNAPS to the nearest authored number on commit, keeping the discrete rule.
 * `orientation` vertical renders M3's VerticalSlider and deliberately does
 * NOT fillMaxWidth — the author's universal height is the length of the
 * rail. `value_label` wraps the thumb in M3's Label/PlainTooltip showing
 * the in-flight position, which never crosses the wire (dispatch stays on
 * commit). `track_icon_start`/`track_icon_end` reproduce the M3 sample's
 * drawWithContent recipe: icons at both edges of each track segment, tinted
 * active/inactive, suppressed when the segment is narrower than the icon.
 */
@Composable
@OptIn(ExperimentalMaterial3ExpressiveApi::class, ExperimentalMaterial3Api::class)
internal fun RenderSlider(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true)
    val onChange = node.objOrNull("on_change")
    val values = node.arrOrNull("values")
    // §17.4 presentation members. `color` tints the thumb and the active
    // track together, which is the pair every upstream custom-colour sample
    // sets; `color_end` tints the END thumb of a range alone; `track` picks
    // M3's centred track; `thumb_icon` names a vector, since IconMap is the
    // only path a drawable reaches the device.
    val tint = resolveColor(node.stringOr("color").takeIf { it.isNotEmpty() })
    val endTint = resolveColor(node.stringOr("color_end").takeIf { it.isNotEmpty() })
    val sliderColors = if (tint != null)
        SliderDefaults.colors(thumbColor = tint, activeTrackColor = tint)
        else SliderDefaults.colors()
    val endColors = if (endTint != null)
        SliderDefaults.colors(thumbColor = endTint) else sliderColors
    val centered = node.stringOr("track") == "centered"
    val vertical = node.stringOr("orientation") == "vertical"
    val showLabel = node.boolOr("value_label")
    val thumbIconName = node.stringOr("thumb_icon")
    val startIconName = node.stringOr("track_icon_start")
    val endIconName = node.stringOr("track_icon_end")
    // SliderDefaults.Thumb wants the slider's OWN interaction source, so it is
    // hoisted and handed to both — otherwise the default thumb loses its
    // press/hover feedback the moment we supply the slot at all.
    val interaction = remember { MutableInteractionSource() }
    fun publish(v: JsonElement) {
        ctx.state(id, v)
        if (onChange != null) ctx.action(onChange, v)
    }
    // The upstream SliderWithTrackIconsSample recipe, driven by two icon
    // NAMES: drawn at both edges of the active and inactive segments, active
    // tick colour on the active side, suppressed when a segment is narrower
    // than icon + padding. No DrawScope ever crosses the wire.
    val trackIcons = startIconName.isNotEmpty() || endIconName.isNotEmpty()
    val startPainter = if (startIconName.isNotEmpty())
        rememberVectorPainter(IconMap.get(startIconName)) else null
    val endPainter = if (endIconName.isNotEmpty())
        rememberVectorPainter(IconMap.get(endIconName)) else null
    val activeIconColor = sliderColors.activeTickColor
    val inactiveIconColor = sliderColors.inactiveTickColor
    fun trackIconModifier(fraction: () -> Float): Modifier =
        if (!trackIcons) Modifier else Modifier.height(36.dp).drawWithContent {
            drawContent()
            val iconSize = Size(20.dp.toPx(), 20.dp.toPx())
            val iconPad = 10.dp.toPx()
            val gap = 6.dp.toPx()
            val yOffset = size.height / 2 - iconSize.height / 2
            fun drawPair(startX: Float, endX: Float, color: Color) {
                if (iconSize.width >= endX - startX - iconPad * 2) return
                startPainter?.let {
                    translate(startX + iconPad, yOffset) {
                        with(it) { draw(iconSize, colorFilter = ColorFilter.tint(color)) }
                    }
                }
                endPainter?.let {
                    translate(endX - iconPad - iconSize.width, yOffset) {
                        with(it) { draw(iconSize, colorFilter = ColorFilter.tint(color)) }
                    }
                }
            }
            val activeEnd = size.width * fraction() - gap
            drawPair(0f, activeEnd, activeIconColor)
            drawPair(activeEnd + gap * 2, size.width, inactiveIconColor)
        }
    // The label is presentation only: the in-flight position shows over the
    // thumb and dispatch still happens once, on commit (§17.4). Each thumb
    // hands its OWN interaction source, or a range's end label would pop
    // while the start thumb is the one being dragged.
    val labelledThumb: @Composable (source: MutableInteractionSource, position: () -> Float, content: @Composable () -> Unit) -> Unit =
        { source, position, content ->
            if (showLabel)
                Label(label = {
                    PlainTooltip(Modifier.sizeIn(45.dp, 25.dp).wrapContentWidth()) {
                        Text("%.2f".format(position()))
                    }
                }, interactionSource = source) { content() }
            else content()
        }
    val defaultThumb: @Composable () -> Unit = {
        if (thumbIconName.isNotEmpty())
            Icon(IconMap.get(thumbIconName), null,
                Modifier.size(24.dp), tint = tint ?: LocalContentColor.current)
        else SliderDefaults.Thumb(interaction, colors = sliderColors,
            enabled = enabled)
    }
    val min = node.doubleOr("min", 0.0).toFloat()
    val max = node.doubleOr("max", 1.0).toFloat()
    fun nearestAuthored(x: Float): JsonElement? =
        values?.minByOrNull { v ->
            val n = v.numOrNull()?.toFloat() ?: return@minByOrNull Float.MAX_VALUE
            kotlin.math.abs(n - x)
        }
    if ("value_end" in node) {
        // ---- RangeSlider: two thumbs, a two-number array on the wire.
        val lo = if (values != null && values.isNotEmpty())
            values.first().numOrNull()?.toFloat() ?: min else min
        val hi = if (values != null && values.isNotEmpty())
            values.last().numOrNull()?.toFloat() ?: max else max
        val steps = if (values != null) (values.size - 2).coerceAtLeast(0) else 0
        val state = remember(ctx.surface, id, ctx.epochOf(id)) {
            val draft = (ctx.storeValue(id) as? JsonArray)?.takeIf { it.size == 2 }
            val start = draft?.get(0)?.numOrNull()?.toFloat()
                ?: node.doubleOr("value", lo.toDouble()).toFloat()
            val end = draft?.get(1)?.numOrNull()?.toFloat()
                ?: node.doubleOr("value_end", hi.toDouble()).toFloat()
            RangeSliderState(start, end, steps = steps, valueRange = lo..hi)
        }
        state.onValueChangeFinished = {
            // With authored `values`, publish the EXACT authored numbers the
            // thumbs settle nearest to — never toolkit step arithmetic.
            val a = nearestAuthored(state.activeRangeStart)
                ?: JsonPrimitive(state.activeRangeStart.toDouble())
            val b = nearestAuthored(state.activeRangeEnd)
                ?: JsonPrimitive(state.activeRangeEnd.toDouble())
            publish(JsonArray(listOf(a, b)))
        }
        val endInteraction = remember { MutableInteractionSource() }
        RangeSlider(
            state = state,
            enabled = enabled,
            colors = sliderColors,
            startInteractionSource = interaction,
            endInteractionSource = endInteraction,
            startThumb = {
                labelledThumb(interaction, { state.activeRangeStart }) { defaultThumb() }
            },
            endThumb = {
                // Each thumb carries its own Label upstream, so the end
                // thumb is wrapped too — reading its own end of the range.
                labelledThumb(endInteraction, { state.activeRangeEnd }) {
                    if (endTint != null)
                        SliderDefaults.Thumb(endInteraction, colors = endColors,
                            enabled = enabled)
                    else SliderDefaults.Thumb(endInteraction, colors = sliderColors,
                        enabled = enabled)
                }
            },
            track = { st ->
                SliderDefaults.Track(rangeSliderState = st, colors = sliderColors,
                    modifier = trackIconModifier {
                        (st.activeRangeEnd - st.valueRange.start) /
                            (st.valueRange.endInclusive - st.valueRange.start)
                    })
            },
            modifier = m.fillMaxWidth())
    } else if (vertical) {
        // ---- VerticalSlider: the author's height is the rail length, so no
        // fillMaxWidth — the flattening the audit warned about.
        val lo = if (values != null && values.isNotEmpty())
            values.first().numOrNull()?.toFloat() ?: min else min
        val hi = if (values != null && values.isNotEmpty())
            values.last().numOrNull()?.toFloat() ?: max else max
        val steps = if (values != null) (values.size - 2).coerceAtLeast(0) else 0
        val state = remember(ctx.surface, id, ctx.epochOf(id)) {
            val seed = ctx.storeValue(id)?.numOrNull()?.toFloat()
                ?: node.doubleOr("value", lo.toDouble()).toFloat()
            SliderState(seed, steps = steps, valueRange = lo..hi)
        }
        state.onValueChangeFinished = {
            publish(nearestAuthored(state.value)
                ?: JsonPrimitive(state.value.toDouble()))
        }
        VerticalSlider(
            state = state,
            enabled = enabled,
            colors = sliderColors,
            interactionSource = interaction,
            thumb = { labelledThumb(interaction, { state.value }) { defaultThumb() } },
            track = { st ->
                if (centered) SliderDefaults.CenteredTrack(sliderState = st,
                    colors = sliderColors)
                else SliderDefaults.Track(sliderState = st, colors = sliderColors)
            },
            modifier = m)
    } else if (values != null && values.size >= 2) {
        val n = values.size
        fun seedIndex(): Int {
            // C6: the org.json gate was `as? Number ?: return 0` — keep only a
            // NUMERIC element, so a string/boolean/null draft seeds index 0 as
            // before. jsonValueEquals then does the §4.3 numeric compare.
            val v = (ctx.storeValue(id) ?: node["value"])
                ?.takeIf { it.numOrNull() != null } ?: return 0
            for (i in 0 until n)
                if (jsonValueEquals(values[i], v)) return i
            return 0
        }
        var index by remember(ctx.surface, id, ctx.epochOf(id)) { mutableIntStateOf(seedIndex()) }
        Slider(
            value = index.toFloat(),
            onValueChange = { index = it.toInt().coerceIn(0, n - 1) },
            onValueChangeFinished = {
                val exact = values[index] // the authored number, exactly
                publish(exact)
            },
            valueRange = 0f..(n - 1).toFloat(),
            steps = (n - 2).coerceAtLeast(0),
            enabled = enabled,
            colors = sliderColors,
            track = { st ->
                if (centered) SliderDefaults.CenteredTrack(st, colors = sliderColors)
                else SliderDefaults.Track(st, colors = sliderColors,
                    modifier = trackIconModifier { st.coercedValueAsFraction })
            },
            interactionSource = interaction,
            thumb = {
                labelledThumb(interaction, { values[index].numOrNull()?.toFloat() ?: 0f }) {
                    defaultThumb()
                }
            },
            modifier = m.fillMaxWidth())
    } else {
        var pos by remember(ctx.surface, id, ctx.epochOf(id)) {
            mutableFloatStateOf(
                (ctx.storeValue(id)?.numOrNull()?.toFloat()
                    ?: node.doubleOr("value", min.toDouble()).toFloat()))
        }
        Slider(
            value = pos,
            onValueChange = { pos = it },
            onValueChangeFinished = {
                publish(JsonPrimitive(pos.toDouble()))
            },
            valueRange = min..max,
            enabled = enabled,
            colors = sliderColors,
            track = { st ->
                if (centered) SliderDefaults.CenteredTrack(st, colors = sliderColors)
                else SliderDefaults.Track(st, colors = sliderColors,
                    modifier = trackIconModifier { st.coercedValueAsFraction })
            },
            interactionSource = interaction,
            thumb = { labelledThumb(interaction, { pos }) { defaultThumb() } },
            modifier = m.fillMaxWidth())
    }
}

/** §17.4 date_button: value is YYYY-MM-DD local civil time; on_pick gets the
 * picked date injected as args.value. `mode` seeds the dialog's display mode:
 * `input` is M3's typed date-entry field with its own mask and validation,
 * and the dialog keeps its built-in toggle between the two either way. Any
 * other value falls back to the calendar (§12 rule 6). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RenderDateButton(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val onPick = node.objOrNull("on_pick")
    var show by remember { mutableStateOf(false) }
    OutlinedButton(
        onClick = { show = true },
        enabled = node.boolOr("enabled", true),
        modifier = m) { Text(node.stringOr("label")) }
    if (show) {
        val initialMillis = remember { parseIsoDateUtc(node.stringOr("value")) }
        // §17.4 day-level bounds: the declarative predicate is the ONLY form
        // the wire can carry — SelectableDates is a Kotlin lambda — and the
        // weekday rule covers every navigable month, which a per-date list
        // could not.
        val minMillis = remember { parseIsoDateUtc(node.stringOr("min_date")) }
        val maxMillis = remember { parseIsoDateUtc(node.stringOr("max_date")) }
        val disabledDays = node.arrOrNull("disabled_weekdays")
            ?.mapNotNull { it.numOrNull()?.toInt() } ?: emptyList()
        val bounded = minMillis != null || maxMillis != null ||
            disabledDays.isNotEmpty()
        val selectable = if (!bounded) DatePickerDefaults.AllDates
            else object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                    if (minMillis != null && utcTimeMillis < minMillis) return false
                    // max_date is an inclusive DAY.
                    if (maxMillis != null &&
                        utcTimeMillis >= maxMillis + 86_400_000L) return false
                    if (disabledDays.isNotEmpty()) {
                        val c = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
                        c.timeInMillis = utcTimeMillis
                        // 0 = Sunday, matching the contract.
                        if (c.get(Calendar.DAY_OF_WEEK) - 1 in disabledDays)
                            return false
                    }
                    return true
                }
                override fun isSelectableYear(year: Int): Boolean {
                    val minYear = minMillis?.let {
                        Calendar.getInstance(TimeZone.getTimeZone("UTC"))
                            .apply { timeInMillis = it }.get(Calendar.YEAR)
                    }
                    val maxYear = maxMillis?.let {
                        Calendar.getInstance(TimeZone.getTimeZone("UTC"))
                            .apply { timeInMillis = it }.get(Calendar.YEAR)
                    }
                    return (minYear == null || year >= minYear) &&
                        (maxYear == null || year <= maxYear)
                }
            }
        val state = rememberDatePickerState(
            initialSelectedDateMillis = initialMillis,
            initialDisplayMode = if (node.stringOr("mode") == "input")
                DisplayMode.Input else DisplayMode.Picker,
            selectableDates = selectable)
        DatePickerDialog(
            onDismissRequest = { show = false },
            confirmButton = {
                TextButton(onClick = {
                    val millis = state.selectedDateMillis
                    show = false
                    if (millis != null && onPick != null)
                        ctx.action(onPick, JsonPrimitive(isoDateFromUtcMillis(millis)))
                }) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { show = false }) { Text("Cancel") }
            }) { DatePicker(state = state) }
    }
}

/** §17.4 time_button: value is HH:MM local civil time. `display_mode`
 * selects what fills the dialog: the clock-face `picker` (the default),
 * M3's `input` — the keyboard-first pair of HH/MM fields TimeInput draws —
 * or `switchable`, M3's TimePickerDialog carrying its own DisplayModeToggle
 * so the user flips between the two mid-dialog. Any other value falls back
 * to the picker (§12 rule 6). */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderTimeButton(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val onPick = node.objOrNull("on_pick")
    var show by remember { mutableStateOf(false) }
    OutlinedButton(
        onClick = { show = true },
        enabled = node.boolOr("enabled", true),
        modifier = m) { Text(node.stringOr("label")) }
    if (show) {
        val (h, min) = remember { parseHm(node.stringOr("value")) }
        val state = rememberTimePickerState(initialHour = h, initialMinute = min)
        val confirm: @Composable () -> Unit = {
            TextButton(onClick = {
                show = false
                if (onPick != null)
                    ctx.action(onPick, JsonPrimitive(
                        String.format("%02d:%02d", state.hour, state.minute)))
            }) { Text("OK") }
        }
        val dismiss: @Composable () -> Unit = {
            TextButton(onClick = { show = false }) { Text("Cancel") }
        }
        if (node.stringOr("display_mode") == "switchable") {
            // The mid-dialog flip is the whole member: TimePickerDialog owns
            // the Title(displayMode) and the toggle affordance itself.
            var mode by remember { mutableStateOf(TimePickerDisplayMode.Picker) }
            TimePickerDialog(
                onDismissRequest = { show = false },
                confirmButton = { confirm() },
                dismissButton = { dismiss() },
                title = { TimePickerDialogDefaults.Title(displayMode = mode) },
                modeToggleButton = {
                    TimePickerDialogDefaults.DisplayModeToggle(
                        onDisplayModeChange = {
                            mode = if (mode == TimePickerDisplayMode.Picker)
                                TimePickerDisplayMode.Input
                            else TimePickerDisplayMode.Picker
                        },
                        displayMode = mode)
                }) {
                if (mode == TimePickerDisplayMode.Input) TimeInput(state = state)
                else TimePicker(state = state)
            }
        } else AlertDialog(
            onDismissRequest = { show = false },
            confirmButton = { confirm() },
            dismissButton = { dismiss() },
            text = {
                if (node.stringOr("display_mode") == "input")
                    TimeInput(state = state)
                else TimePicker(state = state)
            })
    }
}

// ------------------------------------------------- pure date/time helpers

internal fun parseHm(s: String): Pair<Int, Int> {
    val parts = s.split(":")
    val h = parts.getOrNull(0)?.toIntOrNull() ?: 9
    val m = parts.getOrNull(1)?.toIntOrNull() ?: 0
    return h.coerceIn(0, 23) to m.coerceIn(0, 59)
}

/** Parse YYYY-MM-DD to UTC-midnight millis for the picker; null if invalid. */
internal fun parseIsoDateUtc(iso: String): Long? {
    val parts = iso.split("-")
    if (parts.size != 3) return null
    val y = parts[0].toIntOrNull() ?: return null
    val mo = parts[1].toIntOrNull() ?: return null
    val d = parts[2].toIntOrNull() ?: return null
    return Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
        clear(); set(y, mo - 1, d)
    }.timeInMillis
}

/** Format the picker's UTC-midnight millis back to YYYY-MM-DD. */
internal fun isoDateFromUtcMillis(millis: Long): String {
    val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        .apply { timeInMillis = millis }
    return String.format("%04d-%02d-%02d",
        cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1,
        cal.get(Calendar.DAY_OF_MONTH))
}

/** §17.4 split_button: M3's SplitButtonLayout — ONE component whose two halves
 * share an outline and a 2dp gap, with full outer corners and small inner
 * ones that morph together on press. That fused geometry is the whole subject
 * of the upstream samples, and it is why a `row` of two buttons was never a
 * recreation of it.
 *
 * The trailing half is one of three things, in precedence order: `items` opens
 * a dropdown; `checked` makes it a toggle whose arrow rotates 180° (device-held
 * state keyed on the id, so the node is stateful only when `checked` is
 * present); otherwise `on_trailing_tap` fires plainly. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderSplitButton(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val enabled = node.boolOr("enabled", true)
    val h = buttonHeightOf(node.stringOr("size")) ?: SplitButtonDefaults.SmallContainerHeight
    val variant = node.stringOr("variant")
    val id = node.stringOr("id")
    val isToggle = "checked" in node
    val toggle = if (isToggle) rememberToggle(node, ctx, id) else null
    val onChange = node.objOrNull("on_change")
    val items = node.arrOrNull("items")
    var menuOpen by remember { mutableStateOf(false) }

    // Both halves take the same colour treatment, so the pair reads as one
    // component rather than two buttons that happen to touch.
    val colors = when (variant) {
        "tonal" -> ButtonDefaults.filledTonalButtonColors()
        "elevated" -> ButtonDefaults.elevatedButtonColors()
        "outlined" -> ButtonDefaults.outlinedButtonColors()
        else -> ButtonDefaults.buttonColors()
    }
    val border = if (variant == "outlined") ButtonDefaults.outlinedButtonBorder(enabled) else null

    SplitButtonLayout(
        modifier = m,
        leadingButton = {
            SplitButtonDefaults.LeadingButton(
                onClick = { onButton(node.objOrNull("on_tap"), ctx) },
                enabled = enabled,
                shapes = SplitButtonDefaults.leadingButtonShapesFor(h),
                colors = colors,
                border = border,
                contentPadding = SplitButtonDefaults.leadingButtonContentPaddingFor(h),
            ) {
                // §17.4: the leading half is a label, an icon, or both — never
                // neither (the constructor refuses it). Icon-only keeps its
                // accessible name via the icon identifier, the tabs precedent
                // for §16.4's icon-not-sole-carrier rule.
                val iconName = node.stringOr("icon")
                val label = node.stringOr("label")
                if (iconName.isNotEmpty()) {
                    Icon(IconMap.get(iconName),
                        contentDescription = if (label.isEmpty()) iconName else null,
                        modifier = Modifier.size(SplitButtonDefaults.LeadingIconSize))
                    if (label.isNotEmpty())
                        androidx.compose.foundation.layout.Spacer(
                            Modifier.size(ButtonDefaults.IconSpacing))
                }
                if (label.isNotEmpty())
                    Text(label, maxLines = 1, softWrap = false,
                        overflow = TextOverflow.Ellipsis)
            }
        },
        trailingButton = {
            val trailingLabel = node.stringOr("trailing_label")
            val trailingIcon = node.stringOr("trailing_icon").ifEmpty { "keyboard_arrow_down" }
            val expanded = toggle?.value == true || menuOpen
            // The arrow flips with the state — the sample's own animateFloatAsState.
            val rotation by animateFloatAsState(
                targetValue = if (expanded) 180f else 0f, label = "trailing arrow")
            val trailingContent: @Composable RowScope.() -> Unit = {
                if (trailingLabel.isNotEmpty())
                    Text(trailingLabel, maxLines = 1, softWrap = false,
                        overflow = TextOverflow.Ellipsis)
                else Icon(IconMap.get(trailingIcon),
                    contentDescription = node.stringOr("trailing_description")
                        .takeIf { it.isNotEmpty() },
                    modifier = Modifier
                        .size(SplitButtonDefaults.TrailingIconSize)
                        .graphicsLayer { this.rotationZ = rotation })
            }
            val shapes = SplitButtonDefaults.trailingButtonShapesFor(h)
            val pad = SplitButtonDefaults.trailingButtonContentPaddingFor(h)
            Box {
                when {
                    items != null -> SplitButtonDefaults.TrailingButton(
                        checked = menuOpen, onCheckedChange = { menuOpen = it },
                        enabled = enabled, shapes = shapes, colors = colors,
                        border = border, contentPadding = pad, content = trailingContent)
                    toggle != null -> SplitButtonDefaults.TrailingButton(
                        checked = toggle.value,
                        onCheckedChange = {
                            toggle.value = it
                            ctx.state(id, JsonPrimitive(it))       // §14.6 state first
                            if (onChange != null) ctx.action(onChange, JsonPrimitive(it))
                        },
                        enabled = enabled, shapes = shapes, colors = colors,
                        border = border, contentPadding = pad, content = trailingContent)
                    else -> SplitButtonDefaults.TrailingButton(
                        onClick = { onButton(node.objOrNull("on_trailing_tap"), ctx) },
                        enabled = enabled, shapes = shapes, colors = colors,
                        border = border, contentPadding = pad, content = trailingContent)
                }
                if (items != null) DropdownMenu(
                    expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    for (i in 0 until items.size) {
                        val item = items[i] as? JsonObject ?: continue
                        DropdownMenuItem(
                            text = { Text(item.stringOr("label")) },
                            enabled = item.boolOr("enabled", true),
                            onClick = {
                                menuOpen = false
                                onButton(item.objOrNull("on_tap"), ctx)
                            })
                    }
                }
            }
        })
}

/** §17.4 navigation_rail: the vertical sibling of a bottom navigation bar.
 *
 * `variant: "wide"` is M3's WideNavigationRail, the only one that can EXPAND
 * to show labels beside the icons rather than under them — which is why
 * `expanded` requires it and the elisp constructor refuses the pair otherwise.
 * `arrangement` places the destinations within the rail's height, and
 * `header` is the node above them, canonically the menu button that toggles
 * the expansion. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun RenderNavigationRail(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val items = node.arrOrNull("items") ?: return
    val header = node.objOrNull("header")
    val variant = node.stringOr("variant")
    val wide = variant == "wide" || variant == "modal"
    val expanded = node.boolOr("expanded")
    val onExpandChange = node.objOrNull("on_expand_change")
    val arrangement = when (node.stringOr("arrangement")) {
        "center" -> Arrangement.Center
        "bottom" -> Arrangement.Bottom
        else -> Arrangement.Top
    }
    val headerSlot: (@Composable () -> Unit)? =
        header?.let { { RenderNode(it, ctx.child(it, 0)) } }
    val railState = if (wide) rememberWideNavigationRailState(
        initialValue = if (expanded) WideNavigationRailValue.Expanded
            else WideNavigationRailValue.Collapsed) else null
    val destinations: @Composable () -> Unit = {
        for (i in 0 until items.size) {
            val item = items[i] as? JsonObject ?: continue
            val onTap = item.objOrNull("on_tap")
            val selected = item.boolOr("selected")
            val enabled = item.boolOr("enabled", true)
            val badge = item.stringOr("badge")
            val icon: @Composable () -> Unit = {
                val glyph: @Composable () -> Unit = {
                    Icon(IconMap.get(item.stringOr("icon")), contentDescription = null)
                }
                if ("badge" in item)
                    BadgedBox(badge = {
                        if (badge.isNotEmpty()) Badge { Text(badge) } else Badge()
                    }) { glyph() }
                else glyph()
            }
            val label: @Composable () -> Unit = { Text(item.stringOr("label")) }
            val click = { onButton(onTap, ctx) }
            if (wide) WideNavigationRailItem(
                railExpanded = railState?.targetValue ==
                    WideNavigationRailValue.Expanded,
                selected = selected, onClick = click,
                icon = icon, label = label, enabled = enabled)
            else NavigationRailItem(
                selected = selected, onClick = click, icon = icon,
                label = label, enabled = enabled)
        }
    }
    if (wide) {
        val state = railState!!
        // §17.4 `expanded` is SYNCED authored state (the tooltip.shown
        // discipline): a re-push whose value changed animates the open
        // rail, and a settle the author did not write — a modal scrim
        // dismissal — reports back through on_expand_change so a re-push
        // cannot slam the rail back open.
        LaunchedEffect(expanded) {
            if (expanded) state.expand() else state.collapse()
        }
        val settled = state.currentValue
        var reported by remember { mutableStateOf(settled) }
        LaunchedEffect(settled) {
            if (settled != reported) {
                reported = settled
                val isOpen = settled == WideNavigationRailValue.Expanded
                if (isOpen != expanded && onExpandChange != null)
                    ctx.action(onExpandChange, JsonPrimitive(isOpen))
            }
        }
        if (variant == "modal")
            ModalWideNavigationRail(
                modifier = m,
                state = state,
                hideOnCollapse = node.boolOr("hide_on_collapse"),
                header = headerSlot,
                arrangement = arrangement,
                content = destinations)
        else WideNavigationRail(
            modifier = m,
            state = state,
            header = headerSlot,
            arrangement = arrangement,
            content = destinations)
    } else NavigationRail(
        modifier = m, header = headerSlot?.let { { it() } },
        content = { destinations() })
}

/** §17.4 search_bar: the query field plus the results it reveals when expanded.
 *
 * Two pieces of device-held state, and they are deliberately different. The
 * QUERY rides the store keyed on `id`, exactly as text_input's does, so it
 * survives a re-push and is reported in state.changed. EXPANSION does not:
 * it is a Companion-local presentation mode with no wire member, because a
 * search bar that collapsed every time Emacs re-rendered would be unusable.
 *
 * `children` are the suggestions M3 shows inside the expanded bar — which is
 * why they are the node's children rather than a sibling the author places:
 * only the bar knows where its own expanded surface is. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RenderSearchBar(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true)
    val onSearch = node.objOrNull("on_search")
    val onChange = node.objOrNull("on_change")
    var query by rememberSaveable(ctx.surface, id, ctx.epochOf(id),
        key = "sb:${ctx.surface}:$id:${ctx.epochOf(id)}") {
        mutableStateOf((ctx.storeValue(id) as? JsonPrimitive)
            ?.takeIf { it.isString }?.content ?: node.stringOr("value"))
    }
    var expanded by rememberSaveable(ctx.surface, id) { mutableStateOf(false) }
    val leading = node.stringOr("leading_icon")
    val trailing = node.stringOr("trailing_icon")
    val inputField: @Composable () -> Unit = {
        SearchBarDefaults.InputField(
            query = query,
            onQueryChange = {
                query = it
                ctx.state(id, JsonPrimitive(it))          // §14.6 state first
                if (onChange != null) ctx.action(onChange, JsonPrimitive(it))
            },
            onSearch = {
                expanded = false
                if (onSearch != null) ctx.action(onSearch, JsonPrimitive(it))
            },
            expanded = expanded,
            onExpandedChange = { expanded = it },
            enabled = enabled,
            placeholder = node.stringOr("hint").takeIf { it.isNotEmpty() }
                ?.let { { Text(it) } },
            leadingIcon = leading.takeIf { it.isNotEmpty() }
                ?.let { { Icon(IconMap.get(it), contentDescription = null) } },
            trailingIcon = trailing.takeIf { it.isNotEmpty() }
                ?.let { { Icon(IconMap.get(it), contentDescription = null) } })
    }
    val results: @Composable ColumnScope.() -> Unit = {
        RenderChildren(node.arrOrNull("children"), ctx)
    }
    if (node.stringOr("variant") == "docked")
        DockedSearchBar(inputField = inputField, expanded = expanded,
            onExpandedChange = { expanded = it }, modifier = m, content = results)
    else SearchBar(inputField = inputField, expanded = expanded,
        onExpandedChange = { expanded = it }, modifier = m, content = results)
}

/** §17.4 dropdown: M3's ExposedDropdownMenuBox — the popup anchored to a
 * FIELD, which `menu` (popup off its own anchor icon) and `text_input`
 * (no menuAnchor) could never compose.
 *
 * Two forms, one node. Plain (`editable` absent): the field is read-only,
 * displays the picked option's LABEL, and the device-held value keyed on
 * `id` is the option VALUE, exactly enum_list's schema. Editable: the
 * field is a real text field, the TEXT is the value (published per
 * keystroke like text_input), and the popup filters the options to those
 * whose label contains the text — locally, per keystroke, no round trip. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RenderDropdown(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true)
    val editable = node.boolOr("editable")
    val onChange = node.objOrNull("on_change")
    val options = node.arrOrNull("options") ?: return
    fun labelOf(v: String): String {
        for (o in options) {
            val obj = o as? JsonObject ?: continue
            if ((obj["value"] as? JsonPrimitive)?.content == v)
                return obj.stringOr("label")
        }
        return v
    }
    var value by rememberSaveable(ctx.surface, id, ctx.epochOf(id),
        key = "dd:${ctx.surface}:$id:${ctx.epochOf(id)}") {
        mutableStateOf((ctx.storeValue(id) as? JsonPrimitive)
            ?.takeIf { it.isString }?.content ?: node.stringOr("value"))
    }
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { if (enabled) expanded = it },
        modifier = m) {
        OutlinedTextField(
            value = if (editable) value else labelOf(value),
            onValueChange = {
                if (editable) {
                    value = it
                    ctx.state(id, JsonPrimitive(it))
                }
            },
            readOnly = !editable,
            enabled = enabled,
            singleLine = true,
            label = node.stringOr("label").takeIf { it.isNotEmpty() }
                ?.let { { Text(it) } },
            placeholder = node.stringOr("hint").takeIf { it.isNotEmpty() }
                ?.let { { Text(it) } },
            trailingIcon = {
                ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded)
            },
            modifier = Modifier
                .menuAnchor(if (editable) MenuAnchorType.PrimaryEditable
                    else MenuAnchorType.PrimaryNotEditable)
                .fillMaxWidth())
        // The editable filter is Companion-local presentation: the options
        // shown are those whose label CONTAINS the draft, case-insensitive
        // (upstream's own filter), and the authored list is never mutated.
        val shown = if (editable && value.isNotEmpty())
            options.filter {
                (it as? JsonObject)?.stringOr("label")
                    ?.contains(value, ignoreCase = true) == true
            }
        else options.toList()
        if (shown.isNotEmpty()) ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }) {
            for (o in shown) {
                val obj = o as? JsonObject ?: continue
                val optValue = (obj["value"] as? JsonPrimitive)?.content ?: continue
                val label = obj.stringOr("label")
                DropdownMenuItem(
                    text = { Text(label) },
                    onClick = {
                        // Editable publishes the LABEL (it becomes the field
                        // text); plain publishes the option VALUE (§14.6
                        // state first, then on_change).
                        val published = if (editable) label else optValue
                        value = published
                        expanded = false
                        ctx.state(id, JsonPrimitive(published))
                        if (onChange != null)
                            ctx.action(onChange, JsonPrimitive(published))
                    },
                    contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding)
            }
        }
    }
}

/** §17.4 segmented_button: the connected single/multi-choice track.
 *
 * A node rather than members on enum_list because the three things the
 * component exists for are renderer behaviour: per-segment
 * SegmentedButtonDefaults.itemShape(index, count), the fused seam the
 * row draws (negative spacing no wire dp could carry), and the checked
 * crossfade + Role.RadioButton semantics. The value schema mirrors
 * enum_list exactly: one option value, or an array under multi_select. */
@Composable
internal fun RenderSegmentedButton(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true)
    val multi = node.boolOr("multi_select")
    val onChange = node.objOrNull("on_change")
    val options = node.arrOrNull("options") ?: return
    val n = options.size
    val segIcon: @Composable (JsonObject, Boolean) -> (@Composable () -> Unit)? =
        { obj, active ->
            obj.stringOr("icon").takeIf { it.isNotEmpty() }?.let { name ->
                {
                    SegmentedButtonDefaults.Icon(active = active) {
                        Icon(IconMap.get(name), contentDescription = null,
                            modifier = Modifier.size(SegmentedButtonDefaults.IconSize))
                    }
                }
            }
        }
    if (multi) {
        var chosen by remember(ctx.surface, id, ctx.epochOf(id)) {
            mutableStateOf((ctx.storeValue(id) as? JsonArray)?.toList()
                ?: (node["value"] as? JsonArray)?.toList() ?: emptyList())
        }
        MultiChoiceSegmentedButtonRow(modifier = m) {
            options.forEachIndexed { i, o ->
                val obj = o as? JsonObject ?: return@forEachIndexed
                val v = obj["value"] ?: return@forEachIndexed
                val checked = chosen.any { jsonValueEquals(it, v) }
                val slot = segIcon(obj, checked)
                val body: @Composable () -> Unit = {
                    Text(obj.stringOr("label"))
                }
                val flip: (Boolean) -> Unit = {
                    chosen = if (checked) chosen.filterNot { jsonValueEquals(it, v) }
                        else chosen + v
                    val arr = JsonArray(chosen)
                    ctx.state(id, arr)          // §14.6 state first
                    if (onChange != null) ctx.action(onChange, arr)
                }
                if (slot != null)
                    SegmentedButton(checked = checked, onCheckedChange = flip,
                        shape = SegmentedButtonDefaults.itemShape(index = i, count = n),
                        enabled = enabled, icon = slot, label = body)
                else SegmentedButton(checked = checked, onCheckedChange = flip,
                    shape = SegmentedButtonDefaults.itemShape(index = i, count = n),
                    enabled = enabled, label = body)
            }
        }
    } else {
        var value by remember(ctx.surface, id, ctx.epochOf(id)) {
            mutableStateOf(ctx.storeValue(id) ?: node["value"])
        }
        SingleChoiceSegmentedButtonRow(modifier = m) {
            options.forEachIndexed { i, o ->
                val obj = o as? JsonObject ?: return@forEachIndexed
                val v = obj["value"] ?: return@forEachIndexed
                val selected = value != null && jsonValueEquals(value!!, v)
                val slot = segIcon(obj, selected)
                val body: @Composable () -> Unit = {
                    Text(obj.stringOr("label"))
                }
                val pick = {
                    value = v
                    ctx.state(id, v)            // §14.6 state first
                    if (onChange != null) ctx.action(onChange, v)
                }
                if (slot != null)
                    SegmentedButton(selected = selected, onClick = pick,
                        shape = SegmentedButtonDefaults.itemShape(index = i, count = n),
                        enabled = enabled, icon = slot, label = body)
                else SegmentedButton(selected = selected, onClick = pick,
                    shape = SegmentedButtonDefaults.itemShape(index = i, count = n),
                    enabled = enabled, label = body)
            }
        }
    }
}
