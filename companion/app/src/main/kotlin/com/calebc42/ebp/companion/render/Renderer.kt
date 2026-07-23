// SPDX-License-Identifier: GPL-3.0-or-later
// The node dispatcher (SPEC 16-17): one flat when-over-type whose case labels
// ARE the renderer's supported set — NodeSupportPinTest source-scans them and
// pins them to NodeSupport.APP_NODE_TYPES, which in turn feeds the advertised
// surface_profiles. §16.5 universal attributes apply once here; §16.1
// presentation identity (key > id > tree path) threads through RenderCtx.path
// and keys all local widget state. A DialogContext (SPEC 18.1) rebinds button
// builtins to dialog completion and text_input edits to dialog-local state.
package com.calebc42.ebp.companion.render

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
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
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.calebc42.ebp.companion.DeviceBridge
import com.calebc42.ebp.wire.EditorSession
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

/**
 * Everything a node render needs beside the node itself: the surface, the
 * engine seam (bridge.action/state/editorEdit on the ebp-dispatch executor),
 * the optional dialog rebinding, and the §16.1 identity path.
 */
class RenderCtx(
    val surface: String,
    val bridge: DeviceBridge,
    val dialog: DialogContext? = null,
    val path: String = "",
) {
    fun child(node: JSONObject?, index: Int): RenderCtx =
        RenderCtx(surface, bridge, dialog, identityPath(path, node, index))

    fun action(descriptor: JSONObject?, value: Any? = null) =
        bridge.action(surface, descriptor, value)

    fun state(id: String, value: Any?) {
        if (dialog != null) dialog.fields[id] = value?.toString() ?: ""
        else bridge.state(surface, id, value)
    }
}

/** Root entry for a surface (MainActivity). */
@Composable
fun RenderNode(node: JSONObject, surface: String, bridge: DeviceBridge,
               dialog: DialogContext? = null) {
    RenderNode(node, RenderCtx(surface, bridge, dialog))
}

/** Root of a dialog's node tree: owns the local field map (SPEC 18.1). */
@Composable
fun RenderDialogRoot(dialogId: String, spec: JSONObject, bridge: DeviceBridge) {
    val fields = remember(dialogId) { mutableStateMapOf<String, String>() }
    RenderNode(spec, RenderCtx("dialog:$dialogId", bridge,
        DialogContext(dialogId, fields, bridge)))
}

@Composable
fun RenderNode(node: JSONObject, ctx: RenderCtx, modifier: Modifier = Modifier) {
    val type = node.optString("t")
    val m = modifier.universal(node)
    when (type) {
        "text" -> RenderText(node, m)
        "rich_text" -> RenderRichText(node, ctx, m)
        "icon" -> RenderIcon(node, m)
        "badge" -> RenderBadge(node, ctx, m)
        "section_header" -> RenderSectionHeader(node, ctx, m)
        "empty_state" -> RenderEmptyState(node, ctx, m)
        "progress" -> RenderProgress(node, m)
        "date_stamp" -> RenderDateStamp(node, m)
        "row" -> Row(modifier = m) {
            RenderRowChildren(node.optJSONArray("children"), ctx) }
        "column" -> Column(modifier = m) {
            RenderColumnChildren(node.optJSONArray("children"), ctx) }
        "box" -> Box(modifier = m) {
            RenderChildren(node.optJSONArray("children"), ctx) }
        "spacer" -> Spacer(m
            .width((safeDp(node.optDouble("width", 0.0)) ?: 0f).dp)
            .height((safeDp(node.optDouble("height", 0.0)) ?: 0f).dp))
        "divider" -> HorizontalDivider(modifier = m)
        "scaffold" -> RenderScaffold(node, ctx)
        "editor" -> RenderEditor(node, ctx, m)
        "button" -> Button(
            enabled = node.optBoolean("enabled", true), // SPEC 17.4
            onClick = { onButton(node.optJSONObject("on_tap"), ctx) },
            modifier = m) { Text(node.optString("label")) }
        "text_input" -> RenderTextInput(node, ctx, m)
        else ->
            // SPEC 16.2: unknown types render children as a neutral
            // vertical sequence, or nothing.
            node.optJSONArray("children")?.let { children ->
                Column(modifier = m) { RenderColumnChildren(children, ctx) }
            }
    }
}

// ------------------------------------------------------------ children

@Composable
fun RenderChildren(children: JSONArray?, ctx: RenderCtx) {
    if (children == null) return
    for (i in 0 until children.length()) {
        (children.opt(i) as? JSONObject)?.let { RenderNode(it, ctx.child(it, i)) }
    }
}

// SPEC 16.5: `weight` distributes remaining main-axis space — it needs the
// Row/Column scope, so the container cases route through these.
private fun weightOf(node: JSONObject): Float? =
    node.optDouble("weight", 0.0).toFloat().takeIf { it.isFinite() && it > 0f }

@Composable
fun RowScope.RenderRowChildren(children: JSONArray?, ctx: RenderCtx) {
    if (children == null) return
    for (i in 0 until children.length()) {
        val child = children.opt(i) as? JSONObject ?: continue
        val m = weightOf(child)?.let { Modifier.weight(it) } ?: Modifier
        RenderNode(child, ctx.child(child, i), m)
    }
}

@Composable
fun ColumnScope.RenderColumnChildren(children: JSONArray?, ctx: RenderCtx) {
    if (children == null) return
    for (i in 0 until children.length()) {
        val child = children.opt(i) as? JSONObject ?: continue
        val m = weightOf(child)?.let { Modifier.weight(it) } ?: Modifier
        RenderNode(child, ctx.child(child, i), m)
    }
}

// ------------------------------------------------------------ input nodes

@Composable
private fun RenderTextInput(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val id = node.optString("id")
    val enabled = node.optBoolean("enabled", true) // SPEC 17.4
    // §16.1: local widget state keys on the presentation identity path, so a
    // structural re-push with the same key/id keeps the draft and a new
    // identity discards it.
    var value by rememberSaveable(ctx.path, id) { mutableStateOf(node.optString("value")) }
    OutlinedTextField(
        value = value,
        enabled = enabled,
        onValueChange = {
            value = it
            ctx.state(id, it) // dialog-local (18.1) or state.changed (14.6)
        },
        label = node.optString("label").takeIf { it.isNotEmpty() }
            ?.let { { Text(it) } },
        singleLine = node.optBoolean("single_line"),
        modifier = m)
}

@Composable
private fun RenderEditor(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val id = node.optString("id")
    val document = node.optString("document")
    // SPEC 17.4: `read_only` governs editing permission and `enabled` the
    // platform disabled state; a disabled/read-only node MUST NOT dispatch.
    val readOnly = node.optBoolean("read_only", false)
    val enabled = node.optBoolean("enabled", true)
    var text by rememberSaveable(ctx.path, id) { mutableStateOf(node.optString("value")) }
    OutlinedTextField(
        value = text,
        readOnly = readOnly,
        enabled = enabled,
        onValueChange = { new ->
            // A read-only editor's value is authoritative from the server:
            // never mirror a local edit (SPEC 17.4).
            if (!readOnly) {
                // SPEC 19.3: mirror each local edit as a minimal splice — the
                // changed span only — so deltas stay small and the shadow
                // tracks the field scalar-for-scalar.
                if (document.isNotEmpty()) {
                    val (start, del, ins) = EditorSession.diff(text, new)
                    if (del > 0 || ins.isNotEmpty())
                        ctx.bridge.editorEdit(document, id, start, del, ins)
                } else {
                    ctx.state(id, new) // local editor: state.changed
                }
                text = new
            }
        },
        minLines = 3,
        modifier = m)
}

// ------------------------------------------------------------ scaffold

/**
 * SPEC 17.6: the scaffold's application chrome. This slice renders top_bar,
 * body, and a snackbar (whose action dispatches on a user tap only, never on
 * timeout). bottom_bar / fab / floating_toolbar / drawer / on_refresh land
 * at W9-g.
 */
@Composable
fun RenderScaffold(node: JSONObject, ctx: RenderCtx) {
    val hostState = remember { SnackbarHostState() }
    val snackbar = node.optString("snackbar").takeIf { it.isNotEmpty() }
    val action = node.optJSONObject("snackbar_action")
    LaunchedEffect(snackbar) {
        if (snackbar != null) {
            val result = hostState.showSnackbar(
                message = snackbar,
                actionLabel = action?.optString("label")?.takeIf { it.isNotEmpty() },
                duration = SnackbarDuration.Short)
            if (result == SnackbarResult.ActionPerformed)
                ctx.action(action?.optJSONObject("on_tap"))
        }
    }
    Scaffold(
        snackbarHost = { SnackbarHost(hostState) },
        topBar = {
            node.optJSONObject("top_bar")?.let { RenderNode(it, ctx.child(it, 0)) }
        },
    ) { inner ->
        Box(Modifier.padding(inner)) {
            node.optJSONObject("body")?.let { RenderNode(it, ctx.child(it, 1)) }
        }
    }
}

// ------------------------------------------------------------ actions

fun onButton(onTap: JSONObject?, ctx: RenderCtx) {
    onTap ?: return
    val dialog = ctx.dialog
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
    ctx.action(onTap)
}
