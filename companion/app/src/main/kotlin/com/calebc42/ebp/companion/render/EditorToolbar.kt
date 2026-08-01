// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 17.7 editor toolbar chrome: a horizontally-scrolling rail of ToolbarItems
// above the editor. Each item runs exactly one operation — on_tap (remote
// action), line (a Companion-local structural edit via ToolbarEdits), snippet
// (local substitution, prompting once for ${input:...}), command (a non-durable
// edit.command for a synchronized editor), or a menu of non-menu items — plus an
// optional long_press secondary. The pure transforms live in the wire
// ToolbarEdits; this file is only the Compose surface + the edit application.
package com.calebc42.ebp.companion.render

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.unit.dp
import com.calebc42.ebp.wire.ToolbarEdit
import com.calebc42.ebp.wire.ToolbarEdits
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun EditorToolbar(
    items: JsonArray,
    value: () -> TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    dispatch: (JsonObject) -> Unit,
    onCommand: (String) -> Unit,
    localDate: () -> String,
    localTime: () -> String,
    enabled: Boolean = true,
) {
    // The op whose snippet carries ${input:...} parks here while its dialog shows.
    var pendingInput by remember { mutableStateOf<JsonObject?>(null) }

    fun applyEdit(snippet: String, placement: String, input: String?) {
        val v = value()
        val edit = ToolbarEdit(v.text, v.selection.start, v.selection.end)
        val r = ToolbarEdits.applySnippet(
            edit, snippet, placement, input, localDate(), localTime())
        onValueChange(TextFieldValue(r.text, TextRange(r.selStart, r.selEnd)))
    }

    val runOp: (JsonObject) -> Unit = runOp@{ op ->
        // SPEC 17.4: a disabled/read-only editor's toolbar dispatches nothing.
        if (!enabled) return@runOp
        val tap = op.objOrNull("on_tap")
        val line = op.stringOr("line")
        // SPEC 17.7 (exactly one operation per item): the branch ORDER is the
        // priority, and the emptiness/presence asymmetry is deliberate — `line`
        // tests non-emptiness while `snippet`/`command` test membership, so a
        // `snippet: ""` still parks/applies but a `command: ""` dispatches
        // nothing (the takeIf below). C6 spells the presence test `in`, which is
        // the same containsKey org.json's `has` was: a member explicitly set to
        // null is still PRESENT, and reads as "" through stringOr either way.
        when {
            tap != null -> dispatch(tap)
            line.isNotEmpty() -> {
                val v = value()
                ToolbarEdits.lineOp(line, ToolbarEdit(v.text, v.selection.start, v.selection.end))
                    ?.let { onValueChange(TextFieldValue(it.text, TextRange(it.selStart, it.selEnd))) }
            }
            "snippet" in op -> {
                val snippet = op.stringOr("snippet")
                if (ToolbarEdits.needsInput(snippet)) pendingInput = op
                else applyEdit(snippet, op.stringOr("placement"), null)
            }
            // §17.7: the nested command is passed verbatim; Emacs allowlists it.
            "command" in op -> op.stringOr("command").takeIf { it.isNotEmpty() }?.let(onCommand)
        }
    }

    Surface(tonalElevation = 3.dp, shadowElevation = 4.dp, modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState())
                .padding(horizontal = 4.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically) {
            for (i in 0 until items.size) (items[i] as? JsonObject)?.let { ToolbarItem(it, runOp) }
        }
    }

    pendingInput?.let { op ->
        val snippet = op.stringOr("snippet")
        SnippetInputDialog(
            prompt = ToolbarEdits.inputPrompt(snippet),
            onDismiss = { pendingInput = null },
            onConfirm = { entry ->
                pendingInput = null
                applyEdit(snippet, op.stringOr("placement"), entry)
            })
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ToolbarItem(item: JsonObject, runOp: (JsonObject) -> Unit) {
    val icon = item.stringOr("icon")
    val label = item.stringOr("label")
    val menu = item.arrOrNull("menu")
    val longPress = item.objOrNull("long_press")
    when {
        menu != null -> {
            var expanded by remember { mutableStateOf(false) }
            Box {
                ToolbarChip(icon, label) { expanded = true }
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    for (i in 0 until menu.size) {
                        val sub = menu[i] as? JsonObject ?: continue
                        DropdownMenuItem(
                            text = { Text(sub.stringOr("label").ifEmpty { sub.stringOr("icon") }) },
                            onClick = { expanded = false; runOp(sub) })
                    }
                }
            }
        }
        longPress != null -> {
            val haptic = LocalHapticFeedback.current
            Surface(
                shape = MaterialTheme.shapes.small,
                tonalElevation = 1.dp,
                modifier = Modifier.combinedClickable(
                    onClick = { runOp(item) },
                    onLongClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        runOp(longPress)
                    })) {
                ToolbarInner(icon, label)
            }
        }
        else -> ToolbarChip(icon, label) { runOp(item) }
    }
}

@Composable
private fun ToolbarChip(icon: String, label: String, onClick: () -> Unit) {
    Surface(
        shape = MaterialTheme.shapes.small,
        tonalElevation = 1.dp,
        modifier = Modifier.clickable(onClick = onClick)) {
        ToolbarInner(icon, label)
    }
}

@Composable
private fun ToolbarInner(icon: String, label: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        if (icon.isNotEmpty()) {
            Icon(IconMap.get(icon), contentDescription = label.ifEmpty { null },
                modifier = Modifier.size(18.dp))
            if (label.isNotEmpty()) Spacer(Modifier.width(4.dp))
        }
        if (label.isNotEmpty()) Text(label, style = MaterialTheme.typography.labelSmall)
    }
}

/** SPEC 17.7: the one Companion-local dialog behind ${input:Prompt} — free
 * text only (preset choices are the app's `menu` items, not this). */
@Composable
private fun SnippetInputDialog(prompt: String, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var entry by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(prompt) },
        text = {
            OutlinedTextField(
                value = entry, onValueChange = { entry = it },
                singleLine = true, modifier = Modifier.fillMaxWidth())
        },
        confirmButton = {
            TextButton(onClick = { if (entry.isNotBlank()) onConfirm(entry.trim()) },
                enabled = entry.isNotBlank()) { Text("OK") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
}
