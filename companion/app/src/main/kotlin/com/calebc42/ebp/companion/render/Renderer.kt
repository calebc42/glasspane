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
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.calebc42.ebp.companion.DeviceBridge
import com.calebc42.ebp.wire.EditorSession
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** SPEC 18.1: a dialog's local state — its captured field values — and the
 * id needed to complete the outstanding request. Stateful dialog nodes are
 * local and never emit state.changed. */
class DialogContext(
    val dialogId: String,
    // Raw scalar values (string, boolean, number) so §14.6 capture returns
    // each stateful node's logical value, not a stringified one.
    val fields: SnapshotStateMap<String, Any?>,
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

    fun action(descriptor: JSONObject?, value: Any? = null) {
        // SPEC 18.1 (T3c, closes LD-1): inside a dialog the dialog.submit /
        // dialog.dismiss builtins complete the outstanding request instead of
        // dispatching remotely — resolved HERE, in the one ordinary dispatch
        // chain (command_remapping's shape: an override is an ordinary
        // binding), so every dispatch site is correct without knowing about
        // dialogs. Before this, only the five button-shaped sites rebound;
        // a text_input Done key, an empty_state tap, a section_header
        // trailing action, or any on_tap inside a dialog document fell into
        // the engine's when with no dialog.submit arm and hung Emacs forever.
        val d = dialog
        if (d != null && descriptor != null && descriptor.has("builtin")) {
            when (descriptor.optString("builtin")) {
                "dialog.submit" -> {
                    val fields = JSONObject()
                    descriptor.optJSONArray("capture_fields")?.let { capture ->
                        for (i in 0 until capture.length()) {
                            val fieldId = capture.getString(i)
                            fields.put(fieldId, d.fields[fieldId] ?: "")
                        }
                    }
                    d.bridge.dialogSubmit(d.dialogId,
                        if (descriptor.has("value")) descriptor.opt("value") else null,
                        fields)
                    return
                }
                "dialog.dismiss" -> {
                    d.bridge.dialogDismiss(d.dialogId)
                    return
                }
            }
        }
        bridge.action(surface, descriptor, value)
    }

    /** §14.3 multi-member hooks (on_reorder, on_add_row/col, swipe sides). */
    fun actionInjecting(descriptor: JSONObject?, injected: JSONObject) =
        bridge.actionInjecting(surface, descriptor, injected)

    /** §14.6 an app-surface password on_submit — the secret rides `fields`,
     * never `args` and never a retained draft. (In a dialog the secret is
     * captured dialog-locally via dialog.submit + capture_fields instead.) */
    fun actionWithFields(descriptor: JSONObject?, fields: JSONObject) =
        bridge.actionWithFields(surface, descriptor, fields)

    val inDialog: Boolean get() = dialog != null

    fun state(id: String, value: Any?) {
        if (dialog != null) dialog.fields[id] = value // SPEC 18.1: local only
        else bridge.state(surface, id, value)
    }

    /** §17.7 toolbar `command` -> edit.command with the live editor context. */
    fun editorCommand(document: String, editorId: String, command: String,
                      cursor: Int, selStart: Int, selEnd: Int) =
        bridge.editorCommand(surface, document, editorId, command, cursor, selStart, selEnd)
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
    val fields = remember(dialogId) { mutableStateMapOf<String, Any?>() }
    RenderNode(spec, RenderCtx("dialog:$dialogId", bridge,
        DialogContext(dialogId, fields, bridge)))
}

@Composable
fun RenderNode(node: JSONObject, ctx: RenderCtx, modifier: Modifier = Modifier) {
    val type = node.optString("t")
    // SPEC 17.1/16.2: a type not advertised for THIS target (a dialog advertises
    // fewer than the app profile) is unsupported — degrade to its children as a
    // neutral column, never render its semantics or dispatch its actions.
    val advertised = if (ctx.inDialog) NodeSupport.DIALOG_NODE_TYPES else NodeSupport.APP_NODE_TYPES
    if (type !in advertised) {
        node.optJSONArray("children")?.let { kids ->
            Column(modifier) { RenderChildren(kids, ctx) }
        }
        return
    }
    val m = modifier.universal(node)
    when (type) {
        "text" -> RenderText(node, m)
        "rich_text" -> RenderRichText(node, ctx, m)
        "icon" -> RenderIcon(node, m)
        "badge" -> RenderBadge(node, ctx, m)
        "image" -> RenderImage(node, m)
        "section_header" -> RenderSectionHeader(node, ctx, m)
        "empty_state" -> RenderEmptyState(node, ctx, m)
        "progress" -> RenderProgress(node, m)
        "date_stamp" -> RenderDateStamp(node, m)
        "row" -> RenderRow(node, ctx, m)
        "column" -> RenderColumn(node, ctx, m)
        "flow_row" -> RenderFlowRow(node, ctx, m)
        "box" -> RenderBox(node, ctx, m)
        "surface" -> RenderSurfaceNode(node, ctx, m)
        "lazy_column" -> RenderLazyColumn(node, ctx, m)
        "card" -> RenderCard(node, ctx, m)
        "collapsible" -> RenderCollapsible(node, ctx, m)
        "tabs" -> RenderTabs(node, ctx, m)
        "table" -> RenderTable(node, ctx, m)
        "reorderable_list" -> RenderReorderableList(node, ctx, m)
        "chart" -> RenderChart(node, ctx, m)
        "canvas" -> RenderCanvas(node, m)
        "month_grid" -> RenderMonthGrid(node, ctx, m)
        "spacer" -> Spacer(m
            .width((safeDp(node.optDouble("width", 0.0)) ?: 0f).dp)
            .height((safeDp(node.optDouble("height", 0.0)) ?: 0f).dp))
        "divider" -> HorizontalDivider(modifier = m)
        "scaffold" -> RenderScaffold(node, ctx)
        "editor" -> RenderEditor(node, ctx, m)
        "button" -> RenderButton(node, ctx, m)
        "icon_button" -> RenderIconButton(node, ctx, m)
        "chip" -> RenderChip(node, ctx, m)
        "assist_chip" -> RenderAssistChip(node, ctx, m)
        "menu" -> RenderMenu(node, ctx, m)
        "checkbox" -> RenderCheckbox(node, ctx, m)
        "switch" -> RenderSwitch(node, ctx, m)
        "enum_list" -> RenderEnumList(node, ctx, m)
        "slider" -> RenderSlider(node, ctx, m)
        "date_button" -> RenderDateButton(node, ctx, m)
        "time_button" -> RenderTimeButton(node, ctx, m)
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
    val password = node.optBoolean("password")
    val singleLine = node.optBoolean("single_line")
    val onChange = node.optJSONObject("on_change")
    val onSubmit = node.optJSONObject("on_submit")
    // SPEC 14.6: a password value MUST NOT be persisted to saved-instance-state.
    // A non-password draft keys on the §13.6 wire address (surface+id), NOT the
    // key-first presentation path, so changing only a `key` keeps a compatible
    // draft (§16.1 input-draft exception).
    var value by if (password)
        remember(id) { mutableStateOf("") } // never seeded, never saved
    else
        rememberSaveable(ctx.surface, id, key = "ti:${ctx.surface}:$id") {
            mutableStateOf(node.optString("value"))
        }
    // SPEC 18.4/17.4: a `syntax` language recolours the field in place; a
    // password masks with dots instead (a syntax highlight on a secret is moot).
    val language = node.optString("syntax")
    val syntaxColors = LocalSyntaxColors.current
    val transform = remember(language, syntaxColors, password) {
        when {
            password -> androidx.compose.ui.text.input.PasswordVisualTransformation()
            language.isEmpty() -> VisualTransformation.None
            else -> SyntaxTransformation(language, syntaxColors)
        }
    }
    fun submit() {
        val v = value
        when {
            onSubmit == null -> {}
            // SPEC 14.6/14.3: a password submission carries the secret in
            // `fields.<id>`, never in `args`.
            password -> ctx.actionWithFields(onSubmit, JSONObject().put(id, v))
            else -> ctx.action(onSubmit, v) // §14.3 value injection
        }
        // SPEC 17.4: clear_on_submit resets the field after submit.
        if (node.optBoolean("clear_on_submit")) value = ""
    }
    OutlinedTextField(
        value = value,
        enabled = enabled,
        visualTransformation = transform,
        onValueChange = { raw ->
            // SPEC 17.4: single_line strips every U+000A from entered text.
            val next = if (singleLine) raw.replace("\n", "") else raw
            value = next
            // SPEC 14.6: a password MUST NOT emit state.changed. On an app
            // surface, suppress state entirely; in a dialog the value stays
            // dialog-local in memory for a dialog.submit capture.
            if (!password) {
                ctx.state(id, next)           // state.changed (14.6) or dialog-local
                onChange?.let { ctx.action(it, next) } // §14.6: after state.changed
            } else if (ctx.inDialog) {
                ctx.state(id, next)           // dialog-local only, in memory
            }
        },
        label = node.optString("label").takeIf { it.isNotEmpty() }
            ?.let { { Text(it) } },
        singleLine = singleLine,
        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
            keyboardType = keyboardTypeOf(node.optString("keyboard"), password),
            imeAction = if (onSubmit != null) androidx.compose.ui.text.input.ImeAction.Done
                else androidx.compose.ui.text.input.ImeAction.Default),
        keyboardActions = androidx.compose.foundation.text.KeyboardActions(
            onDone = { submit() }),
        modifier = m)
}

/** SPEC 17.4 `keyboard`: text|number|decimal|email|phone|uri; password wins. */
private fun keyboardTypeOf(name: String, password: Boolean): androidx.compose.ui.text.input.KeyboardType {
    val kt = androidx.compose.ui.text.input.KeyboardType
    if (password) return kt.Password
    return when (name) {
        "number" -> kt.Number
        "decimal" -> kt.Decimal
        "email" -> kt.Email
        "phone" -> kt.Phone
        "uri" -> kt.Uri
        else -> kt.Text
    }
}

@Composable
private fun RenderEditor(node: JSONObject, ctx: RenderCtx, m: Modifier) {
    val id = node.optString("id")
    val document = node.optString("document")
    // SPEC 17.4: `read_only` governs editing permission and `enabled` the
    // platform disabled state; a disabled/read-only node MUST NOT dispatch.
    val readOnly = node.optBoolean("read_only", false)
    val enabled = node.optBoolean("enabled", true)
    // A TextFieldValue (not a bare String) so the toolbar can read the live
    // selection/caret for ${selection}, placements, line ops, and edit.command.
    // SPEC 16.1/13.6: the draft keys on the wire address (surface+id), not the
    // key-first path — changing only a `key` keeps a compatible draft.
    var value by rememberSaveable(ctx.surface, id, stateSaver = TextFieldValue.Saver,
        key = "ed:${ctx.surface}:$id") {
        mutableStateOf(TextFieldValue(node.optString("value")))
    }
    // T2/LD-5: the engine shadow is the text authority for a synchronized
    // editor. Adopt every mirror publication — an inbound edit.apply, or the
    // snap-back after a refused local edit — keyed on epoch so adoption
    // happens exactly once per publication. The caret arrives peer-dictated
    // (SPEC 19.4 requires cursor on every text-changing apply), already
    // converted to UTF-16 against the mirrored text.
    if (document.isNotEmpty()) {
        val mirrors by ctx.bridge.editorMirrors.collectAsState()
        val mirror = mirrors[document to id]
        LaunchedEffect(mirror?.epoch) {
            mirror?.let {
                value = TextFieldValue(it.text,
                    if (it.selStartU != it.selEndU)
                        androidx.compose.ui.text.TextRange(it.selStartU, it.selEndU)
                    else androidx.compose.ui.text.TextRange(it.cursorU))
            }
        }
    }
    // SPEC 18.4/17.4: a `syntax` language recolours the field in place via an
    // identity VisualTransformation (never changes the character count, so the
    // cursor/selection/IME behave exactly as on a plain field).
    val language = node.optString("syntax")
    val syntaxColors = LocalSyntaxColors.current
    val transform = remember(language, syntaxColors) {
        if (language.isEmpty()) VisualTransformation.None
        else SyntaxTransformation(language, syntaxColors)
    }
    // Commit a new field state: mirror any TEXT change (§19.3 splice for a
    // synchronized editor, else state.changed); a selection-only change just
    // updates the local value. A read-only editor is server-authoritative.
    val commit: (TextFieldValue) -> Unit = commit@{ new ->
        // SPEC 17.4: a read-only OR disabled editor MUST NOT dispatch — the
        // toolbar is otherwise an unblocked side channel around the field.
        if (readOnly || !enabled) return@commit
        val old = value.text
        if (new.text != old) {
            if (document.isNotEmpty()) {
                val (start, del, ins) = EditorSession.diff(old, new.text)
                if (del > 0 || ins.isNotEmpty())
                    ctx.bridge.editorEdit(document, id, start, del, ins)
            } else {
                ctx.state(id, new.text) // local editor: state.changed
            }
        }
        value = new
    }
    Column(modifier = m) {
        // SPEC 17.7: the toolbar rail above the field. `command` is valid only
        // for a synchronized editor (document present) in READY — the wire side
        // enforces the session/state gate; a local editor's command no-ops.
        node.optJSONArray("toolbar")?.let { items ->
            EditorToolbar(
                items = items,
                enabled = enabled && !readOnly, // §17.4: disabled/read-only inert
                value = { value },
                onValueChange = commit,
                dispatch = { ctx.action(it) },
                onCommand = { command ->
                    // T2/LD-4: cursor is the ACTIVE selection end (where the
                    // caret is); a backward drag has start > end and the
                    // engine orders the pair during scalar conversion.
                    if (document.isNotEmpty())
                        ctx.editorCommand(document, id, command,
                            value.selection.end, value.selection.start, value.selection.end)
                },
                localDate = ::localDateStamp,
                localTime = ::localTimeStamp)
        }
        OutlinedTextField(
            value = value,
            readOnly = readOnly,
            enabled = enabled,
            visualTransformation = transform,
            onValueChange = commit,
            minLines = 3,
            modifier = Modifier.fillMaxWidth())
    }
}

/** SPEC 17.7 `${date}`: local `YYYY-MM-DD Day`. */
private fun localDateStamp(): String {
    val cal = java.util.Calendar.getInstance()
    val days = arrayOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
    return "%04d-%02d-%02d %s".format(
        cal.get(java.util.Calendar.YEAR), cal.get(java.util.Calendar.MONTH) + 1,
        cal.get(java.util.Calendar.DAY_OF_MONTH),
        days[cal.get(java.util.Calendar.DAY_OF_WEEK) - 1])
}

/** SPEC 17.7 `${time}`: local `HH:MM`. */
private fun localTimeStamp(): String {
    val cal = java.util.Calendar.getInstance()
    return "%02d:%02d".format(
        cal.get(java.util.Calendar.HOUR_OF_DAY), cal.get(java.util.Calendar.MINUTE))
}

// ------------------------------------------------------------ scaffold

/**
 * SPEC 17.6: the scaffold's application chrome — every slot (top_bar, body,
 * bottom_bar, fab, floating_toolbar, drawer) is structural NODE content with
 * no hidden navigation behavior beyond its own nodes. The snackbar action
 * dispatches only on a user tap (never timeout); on_refresh only after a user
 * refresh gesture (the spinner self-clears — there is no completion signal,
 * the refreshed push lands in roughly the same window). A drawer opens from
 * the hamburger (Companion-local, like view switching) and closes by scrim.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun RenderScaffold(node: JSONObject, ctx: RenderCtx) {
    val hostState = remember { SnackbarHostState() }
    val snackbar = node.optString("snackbar").takeIf { it.isNotEmpty() }
    val action = node.optJSONObject("snackbar_action")
    val drawer = node.optJSONObject("drawer")
    val drawerState = androidx.compose.material3.rememberDrawerState(
        androidx.compose.material3.DrawerValue.Closed)
    val scope = androidx.compose.runtime.rememberCoroutineScope()
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
    val scaffold: @Composable () -> Unit = {
        Scaffold(
            snackbarHost = { SnackbarHost(hostState) },
            topBar = {
                val topBar = node.optJSONObject("top_bar")
                if (topBar != null || drawer != null) {
                    // §17.6: the top bar is drawn edge-to-edge, so it MUST clear
                    // the system status bar itself (a plain Row, unlike M3's
                    // TopAppBar, gets no automatic inset) — else the hamburger
                    // sits under the status icons and is neither visible nor
                    // tappable.
                    Row(
                        modifier = Modifier.fillMaxWidth().statusBarsPadding(),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        if (drawer != null) {
                            androidx.compose.material3.IconButton(
                                onClick = {
                                    scope.launch {
                                        if (drawerState.isClosed) drawerState.open()
                                        else drawerState.close()
                                    }
                                }) {
                                androidx.compose.material3.Icon(
                                    IconMap.get("menu"), contentDescription = "Menu")
                            }
                        }
                        topBar?.let { RenderNode(it, ctx.child(it, 0)) }
                    }
                }
            },
            floatingActionButton = {
                node.optJSONObject("fab")?.let { RenderNode(it, ctx.child(it, 2)) }
            },
            bottomBar = {
                val floatingToolbar = node.optJSONObject("floating_toolbar")
                val bottomBar = node.optJSONObject("bottom_bar")
                if (floatingToolbar != null || bottomBar != null) {
                    Column {
                        floatingToolbar?.let {
                            androidx.compose.material3.Surface(
                                tonalElevation = 3.dp, shadowElevation = 4.dp,
                                modifier = Modifier.fillMaxWidth()) {
                                RenderNode(it, ctx.child(it, 3))
                            }
                        }
                        bottomBar?.let {
                            androidx.compose.material3.Surface(
                                tonalElevation = 2.dp,
                                modifier = Modifier.fillMaxWidth()) {
                                RenderNode(it, ctx.child(it, 4))
                            }
                        }
                    }
                }
            },
        ) { inner ->
            // Edge-to-edge: lift keyboard-adjacent body content clear of the
            // IME while the bottom bar stays put; consumeWindowInsets keeps
            // descendants with their own imePadding from double-padding.
            val bodyModifier = Modifier.padding(inner)
                .consumeWindowInsets(inner)
                .imePadding()
            val onRefresh = node.optJSONObject("on_refresh")
            val body = node.optJSONObject("body")
            if (onRefresh != null) {
                var refreshing by remember { mutableStateOf(false) }
                LaunchedEffect(refreshing) {
                    if (refreshing) { kotlinx.coroutines.delay(1200); refreshing = false }
                }
                androidx.compose.material3.pulltorefresh.PullToRefreshBox(
                    isRefreshing = refreshing,
                    onRefresh = {
                        refreshing = true
                        ctx.action(onRefresh) // §17.6: user gesture only
                    },
                    modifier = bodyModifier) {
                    body?.let { RenderNode(it, ctx.child(it, 1)) }
                }
            } else {
                Box(bodyModifier) { body?.let { RenderNode(it, ctx.child(it, 1)) } }
            }
        }
    }
    if (drawer != null) {
        androidx.compose.material3.ModalNavigationDrawer(
            drawerState = drawerState,
            drawerContent = {
                androidx.compose.material3.ModalDrawerSheet(
                    modifier = Modifier.fillMaxWidth(0.75f)) {
                    RenderNode(drawer, ctx.child(drawer, 5))
                }
            }) { scaffold() }
    } else scaffold()
}

// ------------------------------------------------------------ actions

// The dialog rebinding lives in RenderCtx.action (T3c) — button sites are
// plain dispatches like every other descriptor site.
fun onButton(onTap: JSONObject?, ctx: RenderCtx) {
    onTap ?: return
    ctx.action(onTap)
}
