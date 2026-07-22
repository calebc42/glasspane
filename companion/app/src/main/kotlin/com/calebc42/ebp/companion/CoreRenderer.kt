// SPDX-License-Identifier: GPL-3.0-or-later
// The Core Node Set renderer (SPEC 16.2/24.1): text, row, column, box,
// spacer, divider, button, text_input — plus the 16.2 unknown-node degrade.
// A DialogContext (SPEC 18.1) rebinds button builtins to dialog completion
// and text_input edits to dialog-local state; without it, buttons dispatch
// remote actions and inputs publish state.changed. The full poc-v1 renderer
// ports at W8.
package com.calebc42.ebp.companion

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject

/** SPEC 18.1: a dialog's local state — its captured field values — and the
 * id needed to complete the outstanding request. Stateful dialog nodes are
 * local and never emit state.changed. */
class DialogContext(
    val dialogId: String,
    val fields: SnapshotStateMap<String, String>,
    val bridge: DeviceBridge,
)

/** Root of a dialog's node tree: owns the local field map (SPEC 18.1). */
@Composable
fun RenderDialogRoot(dialogId: String, spec: JSONObject, bridge: DeviceBridge) {
    val fields = remember(dialogId) { mutableStateMapOf<String, String>() }
    RenderNode(spec, "dialog:$dialogId", bridge, DialogContext(dialogId, fields, bridge))
}

@Composable
fun RenderNode(node: JSONObject, surface: String, bridge: DeviceBridge,
               dialog: DialogContext? = null) {
    val padding = Modifier.padding((node.optDouble("padding", 0.0)).dp)
    when (node.optString("t")) {
        "text" -> Text(
            text = node.optString("text"),
            style = when (node.optString("style")) {
                "title" -> MaterialTheme.typography.titleLarge
                "headline" -> MaterialTheme.typography.headlineMedium
                "caption" -> MaterialTheme.typography.bodySmall
                else -> MaterialTheme.typography.bodyLarge
            },
            modifier = padding)
        "row" -> Row(modifier = padding) {
            RenderChildren(node.optJSONArray("children"), surface, bridge, dialog) }
        "column" -> Column(modifier = padding) {
            RenderChildren(node.optJSONArray("children"), surface, bridge, dialog) }
        "box" -> Box(modifier = padding) {
            RenderChildren(node.optJSONArray("children"), surface, bridge, dialog) }
        "spacer" -> Spacer(Modifier
            .width((node.optDouble("width", 0.0)).dp)
            .height((node.optDouble("height", 0.0)).dp))
        "divider" -> HorizontalDivider(modifier = padding)
        "button" -> Button(
            onClick = { onButton(node.optJSONObject("on_tap"), surface, bridge, dialog) },
            modifier = padding) { Text(node.optString("label")) }
        "text_input" -> {
            val id = node.optString("id")
            var value by rememberSaveable(id) { mutableStateOf(node.optString("value")) }
            OutlinedTextField(
                value = value,
                onValueChange = {
                    value = it
                    if (dialog != null)
                        dialog.fields[id] = it        // SPEC 18.1: local only
                    else
                        bridge.state(surface, id, it) // SPEC 14.6: state.changed
                },
                label = node.optString("label").takeIf { it.isNotEmpty() }
                    ?.let { { Text(it) } },
                singleLine = node.optBoolean("single_line"),
                modifier = padding)
        }
        else ->
            // SPEC 16.2: unknown types render children as a neutral
            // vertical sequence, or nothing.
            node.optJSONArray("children")?.let { children ->
                Column { RenderChildren(children, surface, bridge, dialog) }
            }
    }
}

private fun onButton(onTap: JSONObject?, surface: String, bridge: DeviceBridge,
                     dialog: DialogContext?) {
    onTap ?: return
    // SPEC 18.1: inside a dialog, dialog.submit/dismiss builtins complete
    // the outstanding request rather than dispatching a remote action.
    if (dialog != null && onTap.has("builtin")) {
        when (onTap.optString("builtin")) {
            "dialog.submit" -> {
                val fields = JSONObject()
                onTap.optJSONArray("capture_fields")?.let { capture ->
                    for (i in 0 until capture.length()) {
                        val fieldId = capture.getString(i)
                        fields.put(fieldId, dialog.fields[fieldId] ?: "")
                    }
                }
                dialog.bridge.dialogSubmit(dialog.dialogId,
                    if (onTap.has("value")) onTap.opt("value") else null, fields)
            }
            "dialog.dismiss" -> dialog.bridge.dialogDismiss(dialog.dialogId)
        }
        return
    }
    bridge.action(surface, onTap)
}

@Composable
private fun RenderChildren(children: JSONArray?, surface: String,
                          bridge: DeviceBridge, dialog: DialogContext?) {
    if (children == null) return
    for (i in 0 until children.length()) {
        (children.opt(i) as? JSONObject)?.let { RenderNode(it, surface, bridge, dialog) }
    }
}
