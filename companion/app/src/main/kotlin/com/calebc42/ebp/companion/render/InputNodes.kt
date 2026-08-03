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
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ButtonShapes
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedAssistChip
import androidx.compose.material3.ElevatedButton
import androidx.compose.material3.ElevatedFilterChip
import androidx.compose.material3.ElevatedSuggestionChip
import androidx.compose.material3.ElevatedToggleButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.InputChip
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedToggleButton
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.ToggleButtonDefaults
import androidx.compose.material3.TonalToggleButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
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
    val content: @Composable () -> Unit = {
        if (iconName.isNotEmpty()) {
            Icon(IconMap.get(iconName), null, Modifier.size(iconSize))
            androidx.compose.foundation.layout.Spacer(Modifier.size(iconGap))
        }
        val label = @Composable {
            Text(node.stringOr("label"), maxLines = 1, softWrap = false,
                overflow = TextOverflow.Ellipsis)
        }
        if (h != null) ProvideTextStyle(ButtonDefaults.textStyleFor(h)) { label() }
        else label()
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
        val tShapes = ToggleButtonDefaults.shapesFor(h ?: ButtonDefaults.MinHeight)
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
    val body: @Composable () -> Unit = {
        val icon: @Composable () -> Unit = {
            Icon(IconMap.get(shownIcon),
                modifier = if (glyphSize != null) Modifier.size(glyphSize) else Modifier,
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
    when (node.stringOr("variant")) {
        "elevated" -> ElevatedFilterChip(selected, click, label, m, enabled,
            leadingIcon = lead, trailingIcon = trail)
        "input" -> InputChip(selected, click, label, m, enabled,
            leadingIcon = lead, trailingIcon = trail)
        else -> FilterChip(selected, click, label, m, enabled,
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
internal fun RenderMenu(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    var open by remember { mutableStateOf(false) }
    val items = node.arrOrNull("items")
    Box(modifier = m) {
        IconButton(
            onClick = { open = true },
            enabled = node.boolOr("enabled", true)) {
            Icon(IconMap.get(node.stringOr("icon", "more_vert")),
                contentDescription = "More")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (items != null) for (i in 0 until items.size) {
                val item = items[i] as? JsonObject ?: continue
                val itemIcon = item.stringOr("icon")
                // SPEC 17.4: a disabled MenuItem shows the disabled affordance
                // and MUST NOT dispatch.
                val itemEnabled = item.boolOr("enabled", true)
                DropdownMenuItem(
                    text = { Text(item.stringOr("label")) },
                    enabled = itemEnabled,
                    onClick = {
                        open = false
                        if (itemEnabled) item.objOrNull("on_tap")?.let { onButton(it, ctx) }
                    },
                    leadingIcon = if (itemIcon.isNotEmpty()) {
                        { Icon(IconMap.get(itemIcon), null, Modifier.size(18.dp)) }
                    } else null)
            }
        }
    }
}

// §17.4: every flip produces state.changed (boolean), then on_change with the
// boolean in args.value — in that order (the single executor preserves it).
@Composable
internal fun RenderCheckbox(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true)
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
    val onChange = node.objOrNull("on_change")
    Row(verticalAlignment = Alignment.CenterVertically, modifier = m) {
        Checkbox(checked = checked, enabled = enabled, onCheckedChange = {
            checked = it
            ctx.state(id, JsonPrimitive(it))
            if (onChange != null) ctx.action(onChange, JsonPrimitive(it))
        })
        node.stringOr("label").takeIf { it.isNotEmpty() }?.let {
            Text(it, modifier = Modifier.padding(start = 8.dp))
        }
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
 * toolkit step arithmetic.
 */
@Composable
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
internal fun RenderSlider(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true)
    val onChange = node.objOrNull("on_change")
    val values = node.arrOrNull("values")
    // §17.4 presentation members. `color` tints the thumb and the active
    // track together, which is the pair every upstream custom-colour sample
    // sets; `track` picks M3's centred track; `thumb_icon` names a vector,
    // since IconMap is the only path a drawable reaches the device.
    val tint = resolveColor(node.stringOr("color").takeIf { it.isNotEmpty() })
    val sliderColors = if (tint != null)
        SliderDefaults.colors(thumbColor = tint, activeTrackColor = tint)
        else SliderDefaults.colors()
    val centered = node.stringOr("track") == "centered"
    val thumbIconName = node.stringOr("thumb_icon")
    // SliderDefaults.Thumb wants the slider's OWN interaction source, so it is
    // hoisted and handed to both — otherwise the default thumb loses its
    // press/hover feedback the moment we supply the slot at all.
    val interaction = remember { MutableInteractionSource() }
    if (values != null && values.size >= 2) {
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
                ctx.state(id, exact)
                if (onChange != null) ctx.action(onChange, exact)
            },
            valueRange = 0f..(n - 1).toFloat(),
            steps = (n - 2).coerceAtLeast(0),
            enabled = enabled,
            colors = sliderColors,
            track = { st ->
                if (centered) SliderDefaults.CenteredTrack(st, colors = sliderColors)
                else SliderDefaults.Track(st, colors = sliderColors)
            },
            interactionSource = interaction,
            thumb = {
                if (thumbIconName.isNotEmpty())
                    Icon(IconMap.get(thumbIconName), null,
                        Modifier.size(24.dp), tint = tint ?: LocalContentColor.current)
                else SliderDefaults.Thumb(interaction, colors = sliderColors,
                    enabled = enabled)
            },
            modifier = m.fillMaxWidth())
    } else {
        val min = node.doubleOr("min", 0.0).toFloat()
        val max = node.doubleOr("max", 1.0).toFloat()
        var pos by remember(ctx.surface, id, ctx.epochOf(id)) {
            mutableFloatStateOf(
                (ctx.storeValue(id)?.numOrNull()?.toFloat()
                    ?: node.doubleOr("value", min.toDouble()).toFloat()))
        }
        Slider(
            value = pos,
            onValueChange = { pos = it },
            onValueChangeFinished = {
                ctx.state(id, JsonPrimitive(pos.toDouble()))
                if (onChange != null) ctx.action(onChange, JsonPrimitive(pos.toDouble()))
            },
            valueRange = min..max,
            enabled = enabled,
            colors = sliderColors,
            track = { st ->
                if (centered) SliderDefaults.CenteredTrack(st, colors = sliderColors)
                else SliderDefaults.Track(st, colors = sliderColors)
            },
            interactionSource = interaction,
            thumb = {
                if (thumbIconName.isNotEmpty())
                    Icon(IconMap.get(thumbIconName), null,
                        Modifier.size(24.dp), tint = tint ?: LocalContentColor.current)
                else SliderDefaults.Thumb(interaction, colors = sliderColors,
                    enabled = enabled)
            },
            modifier = m.fillMaxWidth())
    }
}

/** §17.4 date_button: value is YYYY-MM-DD local civil time; on_pick gets the
 * picked date injected as args.value. */
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
        val state = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
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

/** §17.4 time_button: value is HH:MM local civil time. */
@OptIn(ExperimentalMaterial3Api::class)
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
        AlertDialog(
            onDismissRequest = { show = false },
            confirmButton = {
                TextButton(onClick = {
                    show = false
                    if (onPick != null)
                        ctx.action(onPick, JsonPrimitive(
                            String.format("%02d:%02d", state.hour, state.minute)))
                }) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { show = false }) { Text("Cancel") }
            },
            text = { TimePicker(state = state) })
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
