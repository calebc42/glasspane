// SPDX-License-Identifier: GPL-3.0-or-later
// The Core Node Set renderer (SPEC 16.2/24.1): text, row, column, box,
// spacer, divider, button, text_input — plus the 16.2 unknown-node degrade.
// A DialogContext (SPEC 18.1) rebinds button builtins to dialog completion
// and text_input edits to dialog-local state; without it, buttons dispatch
// remote actions and inputs publish state.changed. The full poc-v1 renderer
// ports at W8.
package com.calebc42.ebp.companion

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
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
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
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
        "scaffold" -> RenderScaffold(node, surface, bridge)
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

/**
 * SPEC 17.6: the scaffold's application chrome. This W7 slice renders
 * top_bar, body, and a snackbar (with an optional snackbar_action whose
 * on_tap dispatches on a user tap only, never on timeout). The remaining
 * chrome — bottom_bar, fab, floating_toolbar, drawer, on_refresh — ports
 * from poc-v1's SduiScaffold at W8.
 */
@Composable
fun RenderScaffold(node: JSONObject, surface: String, bridge: DeviceBridge) {
    val hostState = remember { SnackbarHostState() }
    val snackbar = node.optString("snackbar").takeIf { it.isNotEmpty() }
    val action = node.optJSONObject("snackbar_action")
    // Show once when the message changes; SPEC 17.6 dispatches the action
    // only on a user tap, distinguished from a timeout dismissal here.
    LaunchedEffect(snackbar) {
        if (snackbar != null) {
            val result = hostState.showSnackbar(
                message = snackbar,
                actionLabel = action?.optString("label")?.takeIf { it.isNotEmpty() },
                duration = SnackbarDuration.Short)
            if (result == SnackbarResult.ActionPerformed)
                bridge.action(surface, action?.optJSONObject("on_tap"))
        }
    }
    Scaffold(
        snackbarHost = { SnackbarHost(hostState) },
        topBar = {
            node.optJSONObject("top_bar")?.let { RenderNode(it, surface, bridge) }
        },
    ) { inner ->
        Box(Modifier.padding(inner)) {
            node.optJSONObject("body")?.let { RenderNode(it, surface, bridge) }
        }
    }
}

/**
 * SPEC 18.3: a radial pie menu. Categories are placed on a circle; a leaf
 * dispatches its selection, a nested category expands to its items. This
 * W7 slice is a functional radial overlay; poc-v1's RadialMenu gesture UI
 * ports at W8.
 */
@Composable
fun RenderPieMenu(menuId: String, spec: JSONObject, bridge: DeviceBridge) {
    val categories = spec.optJSONArray("categories") ?: return
    var expanded by remember(menuId) { mutableStateOf<Int?>(null) }
    Dialog(onDismissRequest = { bridge.pieMenuDismiss(menuId) }) {
        Box(Modifier.size(320.dp), contentAlignment = Alignment.Center) {
            spec.optString("center_label").takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.titleMedium)
            }
            val active = expanded
            val ring = if (active == null) categories
                else categories.getJSONObject(active).optJSONArray("items")
            val n = ring?.length() ?: 0
            for (k in 0 until n) {
                val entry = ring!!.getJSONObject(k)
                val angle = 2 * PI * k / n - PI / 2
                Button(
                    onClick = {
                        if (active == null && entry.has("items")) expanded = k
                        else if (active == null) bridge.pieMenuSelect(menuId, k, null)
                        else bridge.pieMenuSelect(menuId, active, k)
                    },
                    modifier = Modifier.offset(
                        x = (120 * cos(angle)).dp, y = (120 * sin(angle)).dp),
                ) { Text(entry.optString("label")) }
            }
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
