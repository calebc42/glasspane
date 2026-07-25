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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.unit.dp
import com.calebc42.ebp.wire.jsonValueEquals
import org.json.JSONArray
import org.json.JSONObject

/** §17.4 button with variant/icon/enabled; single-line ellipsised label. */
@Composable
internal fun RenderButton(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val enabled = node.optBoolean("enabled", true)
    val onTap = node.optJSONObject("on_tap")
    val iconName = node.optString("icon")
    val onClick = { onButton(onTap, ctx) }
    val pad = PaddingValues(horizontal = 12.dp, vertical = 8.dp)
    val content: @Composable () -> Unit = {
        if (iconName.isNotEmpty()) {
            Icon(IconMap.get(iconName), null, Modifier.size(18.dp))
            androidx.compose.foundation.layout.Spacer(Modifier.size(6.dp))
        }
        Text(node.optString("label"), maxLines = 1, softWrap = false,
            overflow = TextOverflow.Ellipsis)
    }
    when (node.optString("variant")) {
        "text" -> TextButton(onClick, m, enabled, contentPadding = pad) { content() }
        "outlined" -> OutlinedButton(onClick, m, enabled, contentPadding = pad) { content() }
        "tonal" -> FilledTonalButton(onClick, m, enabled, contentPadding = pad) { content() }
        else -> Button(onClick, m, enabled, contentPadding = pad) { content() }
    }
}

/** §17.4 icon_button: icon + on_tap, badge/content_description/enabled. */
@Composable
internal fun RenderIconButton(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val badge = node.optString("badge")
    IconButton(
        onClick = { onButton(node.optJSONObject("on_tap"), ctx) },
        enabled = node.optBoolean("enabled", true),
        modifier = m) {
        val icon: @Composable () -> Unit = {
            Icon(IconMap.get(node.optString("icon")),
                contentDescription = node.optString("content_description")
                    .takeIf { it.isNotEmpty() })
        }
        if (badge.isNotEmpty())
            BadgedBox(badge = { Badge { Text(badge) } }) { icon() }
        else icon()
    }
}

/** §17.4 chip: selectable filter chip. `selected` is authored presentation
 * state; the tap dispatches — Emacs flips selected on the next snapshot. */
@Composable
internal fun RenderChip(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.optJSONObject("on_tap")
    val iconName = node.optString("icon")
    FilterChip(
        selected = node.optBoolean("selected"),
        enabled = node.optBoolean("enabled", true),
        onClick = { if (onTap != null) onButton(onTap, ctx) },
        label = { Text(node.optString("label")) },
        leadingIcon = if (iconName.isNotEmpty()) {
            { Icon(IconMap.get(iconName), null, Modifier.size(18.dp)) }
        } else null,
        modifier = m)
}

@Composable
internal fun RenderAssistChip(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val onTap = node.optJSONObject("on_tap")
    val iconName = node.optString("icon")
    AssistChip(
        enabled = node.optBoolean("enabled", true),
        onClick = { if (onTap != null) onButton(onTap, ctx) },
        label = { Text(node.optString("label")) },
        leadingIcon = if (iconName.isNotEmpty()) {
            { Icon(IconMap.get(iconName), null, Modifier.size(18.dp)) }
        } else null,
        modifier = m)
}

/** §17.4 menu: an overflow icon opening a dropdown; each item dispatches its
 * on_tap and closes the menu. */
@Composable
internal fun RenderMenu(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    var open by remember { mutableStateOf(false) }
    val items = node.optJSONArray("items")
    Box(modifier = m) {
        IconButton(
            onClick = { open = true },
            enabled = node.optBoolean("enabled", true)) {
            Icon(IconMap.get(node.optString("icon", "more_vert")),
                contentDescription = "More")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (items != null) for (i in 0 until items.length()) {
                val item = items.optJSONObject(i) ?: continue
                val itemIcon = item.optString("icon")
                // SPEC 17.4: a disabled MenuItem shows the disabled affordance
                // and MUST NOT dispatch.
                val itemEnabled = item.optBoolean("enabled", true)
                DropdownMenuItem(
                    text = { Text(item.optString("label")) },
                    enabled = itemEnabled,
                    onClick = {
                        open = false
                        if (itemEnabled) item.optJSONObject("on_tap")?.let { onButton(it, ctx) }
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
internal fun RenderCheckbox(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val id = node.optString("id")
    val enabled = node.optBoolean("enabled", true)
    var checked by rememberSaveable(ctx.surface, id, ctx.epochOf(id),
        key = "in:${ctx.surface}:$id") {
        mutableStateOf(node.optBoolean("checked", false))
    }
    val onChange = node.optJSONObject("on_change")
    Row(verticalAlignment = Alignment.CenterVertically, modifier = m) {
        Checkbox(checked = checked, enabled = enabled, onCheckedChange = {
            checked = it
            ctx.state(id, it)
            if (onChange != null) ctx.action(onChange, it)
        })
        node.optString("label").takeIf { it.isNotEmpty() }?.let {
            Text(it, modifier = Modifier.padding(start = 8.dp))
        }
    }
}

@Composable
internal fun RenderSwitch(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val id = node.optString("id")
    val enabled = node.optBoolean("enabled", true)
    var checked by rememberSaveable(ctx.surface, id, ctx.epochOf(id),
        key = "in:${ctx.surface}:$id") {
        mutableStateOf(node.optBoolean("checked", false))
    }
    val onChange = node.optJSONObject("on_change")
    Row(verticalAlignment = Alignment.CenterVertically, modifier = m) {
        node.optString("label").takeIf { it.isNotEmpty() }?.let {
            Text(it, modifier = Modifier.weight(1f))
        }
        Switch(checked = checked, enabled = enabled, onCheckedChange = {
            checked = it
            ctx.state(id, it)
            if (onChange != null) ctx.action(onChange, it)
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
internal fun RenderEnumList(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val id = node.optString("id")
    val enabled = node.optBoolean("enabled", true)
    val multi = node.optBoolean("multi_select")
    val allowAdd = node.optBoolean("allow_add")
    val onChange = node.optJSONObject("on_change")
    val options = node.optJSONArray("options") ?: JSONArray()

    val optionValues = (0 until options.length()).mapNotNull { options.optJSONObject(it)?.opt("value") }
    // Seed selection from the authored value (§4.3 equality), keeping only
    // values that match an authored option.
    fun seedValues(): List<Any> {
        val v = node.opt("value") ?: return emptyList()
        val wanted: List<Any> = if (v is JSONArray)
            (0 until v.length()).map { v.get(it) } else listOf(v)
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
    fun isSelected(optValue: Any?): Boolean =
        optValue != null && selectedValues.any { jsonValueEquals(it, optValue) }

    fun currentValue(): Any? {
        val values = selectedValues + selectedAdded.toList()
        return if (multi) JSONArray(values)
        else values.firstOrNull() ?: JSONObject.NULL
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
        for (i in 0 until options.length()) {
            val opt = options.optJSONObject(i) ?: continue
            val ov = opt.opt("value")
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
                label = { Text(opt.optString("label")) })
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
internal fun RenderSlider(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val id = node.optString("id")
    val enabled = node.optBoolean("enabled", true)
    val onChange = node.optJSONObject("on_change")
    val values = node.optJSONArray("values")
    if (values != null && values.length() >= 2) {
        val n = values.length()
        fun seedIndex(): Int {
            val v = node.opt("value") as? Number ?: return 0
            for (i in 0 until n)
                if (jsonValueEquals(values.get(i), v)) return i
            return 0
        }
        var index by remember(ctx.surface, id, ctx.epochOf(id)) { mutableIntStateOf(seedIndex()) }
        Slider(
            value = index.toFloat(),
            onValueChange = { index = it.toInt().coerceIn(0, n - 1) },
            onValueChangeFinished = {
                val exact = values.get(index) // the authored number, exactly
                ctx.state(id, exact)
                if (onChange != null) ctx.action(onChange, exact)
            },
            valueRange = 0f..(n - 1).toFloat(),
            steps = (n - 2).coerceAtLeast(0),
            enabled = enabled,
            modifier = m.fillMaxWidth())
    } else {
        val min = node.optDouble("min", 0.0).toFloat()
        val max = node.optDouble("max", 1.0).toFloat()
        var pos by remember(ctx.surface, id, ctx.epochOf(id)) {
            mutableFloatStateOf(node.optDouble("value", min.toDouble()).toFloat())
        }
        Slider(
            value = pos,
            onValueChange = { pos = it },
            onValueChangeFinished = {
                ctx.state(id, pos.toDouble())
                if (onChange != null) ctx.action(onChange, pos.toDouble())
            },
            valueRange = min..max,
            enabled = enabled,
            modifier = m.fillMaxWidth())
    }
}

/** §17.4 date_button: value is YYYY-MM-DD local civil time; on_pick gets the
 * picked date injected as args.value. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RenderDateButton(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val onPick = node.optJSONObject("on_pick")
    var show by remember { mutableStateOf(false) }
    OutlinedButton(
        onClick = { show = true },
        enabled = node.optBoolean("enabled", true),
        modifier = m) { Text(node.optString("label")) }
    if (show) {
        val initialMillis = remember { parseIsoDateUtc(node.optString("value")) }
        val state = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
        DatePickerDialog(
            onDismissRequest = { show = false },
            confirmButton = {
                TextButton(onClick = {
                    val millis = state.selectedDateMillis
                    show = false
                    if (millis != null && onPick != null)
                        ctx.action(onPick, isoDateFromUtcMillis(millis))
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
internal fun RenderTimeButton(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val onPick = node.optJSONObject("on_pick")
    var show by remember { mutableStateOf(false) }
    OutlinedButton(
        onClick = { show = true },
        enabled = node.optBoolean("enabled", true),
        modifier = m) { Text(node.optString("label")) }
    if (show) {
        val (h, min) = remember { parseHm(node.optString("value")) }
        val state = rememberTimePickerState(initialHour = h, initialMinute = min)
        AlertDialog(
            onDismissRequest = { show = false },
            confirmButton = {
                TextButton(onClick = {
                    show = false
                    if (onPick != null)
                        ctx.action(onPick,
                            String.format("%02d:%02d", state.hour, state.minute))
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
