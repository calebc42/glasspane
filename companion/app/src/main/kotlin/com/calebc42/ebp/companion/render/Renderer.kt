// SPDX-License-Identifier: GPL-3.0-or-later
// The node dispatcher (SPEC 16-17): one flat when-over-type whose case labels
// ARE the renderer's supported set — NodeSupportPinTest source-scans them and
// pins them to NodeSupport.APP_NODE_TYPES, which in turn feeds the advertised
// surface_profiles. §16.5 universal attributes apply once here; §16.1
// presentation identity (key > id > tree path) threads through RenderCtx.path
// and keys all local widget state. A DialogContext (SPEC 18.1) rebinds button
// builtins to dialog completion and text_input edits to dialog-local state.
package com.calebc42.ebp.companion.render

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingToolbarDefaults
import androidx.compose.material3.FloatingToolbarExitDirection
import androidx.compose.material3.FloatingToolbarScrollBehavior
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.HorizontalFloatingToolbar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MediumTopAppBar
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.material3.VerticalFloatingToolbar
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.calebc42.ebp.companion.DeviceBridge
import com.calebc42.ebp.wire.EditorSession
import com.calebc42.ebp.wire.InputDisplay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** SPEC 18.1: a dialog's local state — its captured field values — and the
 * id needed to complete the outstanding request. Stateful dialog nodes are
 * local and never emit state.changed. */
class DialogContext(
    val dialogId: String,
    // Raw scalar values (string, boolean, number) so §14.6 capture returns
    // each stateful node's logical value, not a stringified one.
    val fields: SnapshotStateMap<String, JsonElement?>,
    val bridge: DeviceBridge,
    /** T3/LD-3: the authored values the engine computed while validating this
     * dialog's spec — the layer UNDER the user's edits. */
    val defaults: JsonObject? = null,
) {
    /**
     * SPEC 14.1: the logical value of a stateful node at occurrence time —
     * the user's dialog-local edit when there is one, else the authored
     * default.
     *
     * The lookup is a CONTAINMENT test, not `?:`, and that distinction is the
     * whole point: a field the user deliberately cleared holds an empty
     * string, `false`, or `0`, and an elvis would treat those exactly like a
     * field never touched. The old capture had no defaults layer at all and
     * substituted `""`, so an untouched `checkbox` authored `checked: true`
     * shipped the STRING `""` where §14.1 requires boolean `true` — the wrong
     * JSON type, silently, for the commonest dialog shape there is.
     *
     * Emacs's `swap_in_symval_forwarding` is the model: fall back to the
     * default cell, with an explicit `found` bit deciding which layer answers
     * rather than the value's own emptiness.
     */
    fun capture(id: String): JsonElement? = captureValue(id, fields, defaults)
}

/** The two-layer lookup of [DialogContext.capture], as pure logic so the
 * layering rule is testable without a live bridge. */
fun captureValue(id: String, fields: Map<String, JsonElement?>, defaults: JsonObject?): JsonElement? = when {
    fields.containsKey(id) -> fields[id]
    // C6: the engine writes `put(nodeId, authoredValueOf(node) ?: JsonNull)`,
    // so a stateful node with no authored value is PRESENT and JSON null; the
    // sentinel filter is what turns that into "no default", exactly as the
    // JSONObject.NULL test did.
    defaults != null && id in defaults -> defaults[id]?.takeIf { it !is JsonNull }
    // Neither layer has it. §14.1 makes an unresolvable capture a
    // document-level error the Companion already refused at validation, so
    // reaching here means the spec and this map disagree — surface null
    // rather than inventing a value of the wrong type.
    else -> null
}

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
    /** T3/LD-2: what each of this surface's stateful nodes should display,
     * and the generation that value belongs to. */
    val displays: Map<Pair<String, String>, InputDisplay> = emptyMap(),
) {
    fun child(node: JsonObject?, index: Int): RenderCtx =
        RenderCtx(surface, bridge, dialog, identityPath(path, node, index), displays)

    /**
     * T3/LD-2: the generation of the value this node's widget should show.
     * It belongs in BOTH the `remember` inputs and the saveable `key`: the
     * inputs make the seeding lambda re-run, and the key stops Compose
     * restoring the value saved under the previous generation — a restore
     * beats changed inputs, so an epoch carried only in the inputs is
     * silently defeated wherever state is saved and restored (a recycled
     * `lazy_column` row, a `HorizontalPager` page, process death).
     */
    fun epochOf(id: String): Long = displays[surface to id]?.epoch ?: 0L

    /**
     * T3/LD-2: the value the STORE says this node holds — the draft when the
     * user has one, else the authored value — or null when the store has no
     * opinion (a dialog, or a node not in an accepted snapshot), in which
     * case the caller falls back to the authored member.
     *
     * The store is the seed authority because it is what `capture_fields`
     * (§14.1) and the welcome `input_state` (§15.1) read. Seeding from the
     * node instead means a widget that is disposed and recomposed while a
     * draft stands — a view switch, a fold, a recycled row — silently
     * reverts to the authored value while the store still holds the user's,
     * which is the LD-2 divergence by a route no epoch can detect, because
     * nothing in the store changed.
     */
    fun storeValue(id: String): JsonElement? = displays[surface to id]?.value

    fun action(descriptor: JsonObject?, value: JsonElement? = null) {
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
        if (d != null && descriptor != null && "builtin" in descriptor) {
            when (descriptor.stringOr("builtin")) {
                "dialog.submit" -> {
                    val fields = buildJsonObject {
                        descriptor.arrOrNull("capture_fields")?.let { capture ->
                            for (i in capture.indices) {
                                val fieldId = capture[i].strOrNull()!!
                                // T3/LD-3: user layer, then authored layer.
                                put(fieldId,
                                    d.capture(fieldId) ?: JsonNull)
                            }
                        }
                    }
                    d.bridge.dialogSubmit(d.dialogId,
                        if ("value" in descriptor) descriptor["value"] else null,
                        fields)
                    return
                }
                "dialog.dismiss" -> {
                    d.bridge.dialogDismiss(d.dialogId)
                    return
                }
            }
        }
        if (d != null && descriptor != null && "builtin" !in descriptor) {
            // SPEC 18.1/14.4: a REMOTE descriptor inside a dialog dispatches
            // in DIALOG context, its capture snapshot read from the local
            // field layer exactly like dialog.submit (T3/LD-3).  The generic
            // surface path silently dropped these — the JA-5 device gate's
            // token+confirm Archive and date-pick relay were dead taps.
            val fields = buildJsonObject {
                descriptor.arrOrNull("capture_fields")?.let { capture ->
                    for (i in capture.indices) {
                        val fieldId = capture[i].strOrNull()!!
                        put(fieldId, d.capture(fieldId) ?: JsonNull)
                    }
                }
            }
            d.bridge.dialogAction(d.dialogId, descriptor, value, fields)
            return
        }
        bridge.action(surface, descriptor, value)
    }

    /** §14.3 multi-member hooks (on_reorder, on_add_row/col, swipe sides). */
    fun actionInjecting(descriptor: JsonObject?, injected: JsonObject,
                        value: JsonElement? = null) =
        bridge.actionInjecting(surface, descriptor, injected, value)

    /** §14.6 an app-surface password on_submit — the secret rides `fields`,
     * never `args` and never a retained draft. (In a dialog the secret is
     * captured dialog-locally via dialog.submit + capture_fields instead.) */
    fun actionWithFields(descriptor: JsonObject?, fields: JsonObject) =
        bridge.actionWithFields(surface, descriptor, fields)

    val inDialog: Boolean get() = dialog != null

    fun state(id: String, value: JsonElement?) {
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
fun RenderNode(node: JsonObject, surface: String, bridge: DeviceBridge,
               dialog: DialogContext? = null) {
    // T3/LD-2: collected once at the root and carried down the tree, so a
    // stateful widget reads its generation and its seed without each one
    // subscribing.
    val displays by bridge.inputDisplays.collectAsState()
    RenderNode(node, RenderCtx(surface, bridge, dialog, displays = displays))
}

/** Root of a dialog's node tree: owns the local field map (SPEC 18.1). */
@Composable
fun RenderDialogRoot(dialogId: String, spec: JsonObject, bridge: DeviceBridge) {
    val fields = remember(dialogId) { mutableStateMapOf<String, JsonElement?>() }
    // T3/LD-3: the authored layer, computed by the engine while it validated
    // this spec — read once per presented dialog, so the two layers can never
    // disagree about which nodes are stateful.
    val defaults = remember(dialogId) { bridge.dialogDefaults(dialogId) }
    RenderNode(spec, RenderCtx("dialog:$dialogId", bridge,
        DialogContext(dialogId, fields, bridge, defaults)))
}

@Composable
fun RenderNode(node: JsonObject, ctx: RenderCtx, modifier: Modifier = Modifier) {
    val type = node.stringOr("t")
    // SPEC 17.1/16.2: a type not advertised for THIS target (a dialog advertises
    // fewer than the app profile) is unsupported — degrade to its children as a
    // neutral column, never render its semantics or dispatch its actions.
    val advertised = if (ctx.inDialog) NodeSupport.DIALOG_NODE_TYPES else NodeSupport.APP_NODE_TYPES
    if (type !in advertised) {
        node.arrOrNull("children")?.let { kids ->
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
        "tooltip" -> RenderTooltip(node, ctx, m)
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
        "pane_scaffold" -> RenderPaneScaffold(node, ctx, m)
        "reorderable_list" -> RenderReorderableList(node, ctx, m)
        "chart" -> RenderChart(node, ctx, m)
        "canvas" -> RenderCanvas(node, m)
        "month_grid" -> RenderMonthGrid(node, ctx, m)
        "spacer" -> Spacer(m
            .width((safeDp(node.doubleOr("width", 0.0)) ?: 0f).dp)
            .height((safeDp(node.doubleOr("height", 0.0)) ?: 0f).dp))
        "divider" -> HorizontalDivider(modifier = m)
        "scaffold" -> RenderScaffold(node, ctx)
        "editor" -> RenderEditor(node, ctx, m)
        "button" -> RenderButton(node, ctx, m)
        "icon_button" -> RenderIconButton(node, ctx, m)
        "split_button" -> RenderSplitButton(node, ctx, m)
        "navigation_rail" -> RenderNavigationRail(node, ctx, m)
        "search_bar" -> RenderSearchBar(node, ctx, m)
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
            node.arrOrNull("children")?.let { children ->
                Column(modifier = m) { RenderColumnChildren(children, ctx) }
            }
    }
}

// ------------------------------------------------------------ children

@Composable
fun RenderChildren(children: JsonArray?, ctx: RenderCtx) {
    if (children == null) return
    for (i in 0 until children.size) {
        (children[i] as? JsonObject)?.let { RenderNode(it, ctx.child(it, i)) }
    }
}

// SPEC 16.5: `weight` distributes remaining main-axis space — it needs the
// Row/Column scope, so the container cases route through these. `align_self`
// (start|center|end|stretch, SPEC 16.5) overrides the parent's CROSS-axis
// alignment and needs the same scope: in a Row the cross axis is vertical, in
// a Column it is horizontal. Attributes.kt has always claimed the containers
// applied it; they did not, so it was a declared, elisp-validated, never-read
// member — the `badge ""` defect class.
private fun weightOf(node: JsonObject): Float? =
    node.doubleOr("weight", 0.0).toFloat().takeIf { it.isFinite() && it > 0f }

@Composable
fun RowScope.RenderRowChildren(children: JsonArray?, ctx: RenderCtx) {
    if (children == null) return
    for (i in 0 until children.size) {
        val child = children[i] as? JsonObject ?: continue
        var m = weightOf(child)?.let { Modifier.weight(it) } ?: Modifier
        m = when (child.stringOr("align_self")) {
            "start" -> m.align(Alignment.Top)
            "center" -> m.align(Alignment.CenterVertically)
            "end" -> m.align(Alignment.Bottom)
            "stretch" -> m.fillMaxHeight()
            else -> m
        }
        RenderNode(child, ctx.child(child, i), m)
    }
}

@Composable
fun ColumnScope.RenderColumnChildren(children: JsonArray?, ctx: RenderCtx) {
    if (children == null) return
    for (i in 0 until children.size) {
        val child = children[i] as? JsonObject ?: continue
        var m = weightOf(child)?.let { Modifier.weight(it) } ?: Modifier
        m = when (child.stringOr("align_self")) {
            "start" -> m.align(Alignment.Start)
            "center" -> m.align(Alignment.CenterHorizontally)
            "end" -> m.align(Alignment.End)
            "stretch" -> m.fillMaxWidth()
            else -> m
        }
        RenderNode(child, ctx.child(child, i), m)
    }
}

// ------------------------------------------------------------ input nodes

@Composable
private fun RenderTextInput(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val enabled = node.boolOr("enabled", true) // SPEC 17.4
    val password = node.boolOr("password")
    val singleLine = node.boolOr("single_line")
    val onChange = node.objOrNull("on_change")
    val onSubmit = node.objOrNull("on_submit")
    // SPEC 14.6: a password value MUST NOT be persisted to saved-instance-state.
    // A non-password draft keys on the §13.6 wire address (surface+id), NOT the
    // key-first presentation path, so changing only a `key` keeps a compatible
    // draft (§16.1 input-draft exception).
    var value by if (password)
        remember(id) { mutableStateOf("") } // never seeded, never saved
    else
        rememberSaveable(ctx.surface, id, ctx.epochOf(id),
            key = "ti:${ctx.surface}:$id:${ctx.epochOf(id)}") {
            // C6: the store's value is a JsonElement, so the seed reads the
            // STRING primitive explicitly — a safe cast to a Kotlin String
            // would compile and be forever null, silently reverting the widget
            // to the authored value while the store still held the user's
            // draft (LD-2).
            mutableStateOf((ctx.storeValue(id) as? JsonPrimitive)
                ?.takeIf { it.isString }?.content ?: node.stringOr("value"))
        }
    // SPEC 18.4/17.4: a `syntax` language recolours the field in place; a
    // password masks with dots instead (a syntax highlight on a secret is
    // moot); a `mask` template formats the stored value for DISPLAY only —
    // its literals never enter value/state.changed — and outranks syntax.
    val language = node.stringOr("syntax")
    val syntaxColors = LocalSyntaxColors.current
    val maskSpec = node.stringOr("mask")
    val transform = remember(language, syntaxColors, password, maskSpec) {
        when {
            password -> androidx.compose.ui.text.input.PasswordVisualTransformation()
            maskSpec.isNotEmpty() -> MaskTransformation(maskSpec)
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
            password -> ctx.actionWithFields(onSubmit, buildJsonObject { put(id, v) })
            else -> ctx.action(onSubmit, JsonPrimitive(v)) // §14.3 value injection
        }
        // SPEC 17.4: clear_on_submit resets the field after submit.
        if (node.boolOr("clear_on_submit")) value = ""
    }
    val isError = node.boolOr("is_error")
    val supporting = node.stringOr("supporting_text")
    val leadingName = node.stringOr("leading_icon")
    val trailingName = node.stringOr("trailing_icon")
    val prefixText = node.stringOr("prefix")
    val suffixText = node.stringOr("suffix")
    // §17.4 shared slots. M3 measures the helper line to the FIELD's own
    // width and tints it from (enabled, isError, focused), which is exactly
    // why a sibling `text` node underneath is not a substitute.
    val labelSlot: (@Composable () -> Unit)? = node.stringOr("label")
        .takeIf { it.isNotEmpty() }?.let { { Text(it) } }
    val placeholderSlot: (@Composable () -> Unit)? = node.stringOr("hint")
        .takeIf { it.isNotEmpty() }?.let { { Text(it) } }
    val supportingSlot: (@Composable () -> Unit)? =
        supporting.takeIf { it.isNotEmpty() }?.let { { Text(it) } }
    val leadingSlot: (@Composable () -> Unit)? =
        leadingName.takeIf { it.isNotEmpty() }?.let { { Icon(IconMap.get(it), null) } }
    val trailingSlot: (@Composable () -> Unit)? =
        trailingName.takeIf { it.isNotEmpty() }?.let { { Icon(IconMap.get(it), null) } }
    val prefixSlot: (@Composable () -> Unit)? =
        prefixText.takeIf { it.isNotEmpty() }?.let { { Text(it) } }
    val suffixSlot: (@Composable () -> Unit)? =
        suffixText.takeIf { it.isNotEmpty() }?.let { { Text(it) } }
    val onValueChange: (String) -> Unit = { raw ->
        // SPEC 17.4: single_line strips every U+000A from entered text.
        var next = if (singleLine) raw.replace("\n", "") else raw
        // `filter` reverts characters outside the class at the keystroke,
        // locally — the companion half of `mask`, so a phone field never
        // round-trips an alphabetic keypress to Emacs and back.
        next = when (node.stringOr("filter")) {
            "digits" -> next.filter { it.isDigit() }
            "alnum" -> next.filter { it.isLetterOrDigit() }
            else -> next
        }
        // `max_length` refuses committed text past N — paste and IME included,
        // the same discipline as the single_line newline rule.
        val cap = node.doubleOr("max_length", 0.0).toInt()
        if (cap > 0 && next.length > cap) next = next.take(cap)
        value = next
        if (!password) {
            ctx.state(id, JsonPrimitive(next))
            onChange?.let { ctx.action(it, JsonPrimitive(next)) }
        } else if (ctx.inDialog) {
            ctx.state(id, JsonPrimitive(next))
        }
    }
    val keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
        keyboardType = keyboardTypeOf(node.stringOr("keyboard"), password),
        imeAction = if (onSubmit != null) androidx.compose.ui.text.input.ImeAction.Done
            else androidx.compose.ui.text.input.ImeAction.Default)
    // §17.4 `hide_keyboard_on_submit`: Compose's default hide-on-Done is
    // SUPPRESSED the moment KeyboardActions supplies onDone, so without this
    // member the IME stays up after every submit and nothing can ask otherwise.
    val keyboardController = LocalSoftwareKeyboardController.current
    val hideOnSubmit = node.boolOr("hide_keyboard_on_submit")
    val keyboardActions = androidx.compose.foundation.text.KeyboardActions(
        onDone = { submit(); if (hideOnSubmit) keyboardController?.hide() })
    // §17.4 `content_padding`: the field's INTERIOR padding, which only the
    // DecorationBox overload owns — the universal `padding` lands outside the
    // widget as margin and `min_height` cannot shrink the ~56dp interior.
    val innerPad = node["content_padding"]?.numOrNull()
    if (innerPad != null && !password) {
        RenderDenseTextInput(node, value, onValueChange, transform,
            keyboardOptions, keyboardActions, enabled, singleLine, isError,
            innerPad.toFloat(), labelSlot, placeholderSlot, supportingSlot,
            leadingSlot, trailingSlot, prefixSlot, suffixSlot, m)
        return
    }
    // §17.4 `selection`: seeds the initial TextRange only — re-seeded on an
    // input-reset epoch exactly like `value` — so the field composes through
    // the TextFieldValue overload while the draft store still carries the
    // bare string.
    val selSpec = node.arrOrNull("selection")
    if (selSpec != null && !password) {
        var sel by remember(ctx.surface, id, ctx.epochOf(id)) {
            val a = selSpec.mapNotNull { it.numOrNull()?.toInt() }
            val start = (a.getOrNull(0) ?: 0).coerceIn(0, value.length)
            val end = (a.getOrNull(1) ?: start).coerceIn(start, value.length)
            mutableStateOf(androidx.compose.ui.text.TextRange(start, end))
        }
        val tfv = androidx.compose.ui.text.input.TextFieldValue(value, sel)
        val onTfv: (androidx.compose.ui.text.input.TextFieldValue) -> Unit = {
            sel = it.selection
            onValueChange(it.text)
        }
        if (node.stringOr("variant") == "filled")
            TextField(
                value = tfv, enabled = enabled, visualTransformation = transform,
                onValueChange = onTfv, label = labelSlot,
                placeholder = placeholderSlot, singleLine = singleLine,
                isError = isError, supportingText = supportingSlot,
                leadingIcon = leadingSlot, trailingIcon = trailingSlot,
                prefix = prefixSlot, suffix = suffixSlot,
                keyboardOptions = keyboardOptions, keyboardActions = keyboardActions,
                modifier = m)
        else OutlinedTextField(
            value = tfv, enabled = enabled, visualTransformation = transform,
            onValueChange = onTfv, label = labelSlot,
            placeholder = placeholderSlot, singleLine = singleLine,
            isError = isError, supportingText = supportingSlot,
            leadingIcon = leadingSlot, trailingIcon = trailingSlot,
            prefix = prefixSlot, suffix = suffixSlot,
            keyboardOptions = keyboardOptions, keyboardActions = keyboardActions,
            modifier = m)
        return
    }
    if (node.stringOr("variant") == "filled") {
        TextField(
            value = value, enabled = enabled, visualTransformation = transform,
            onValueChange = onValueChange, label = labelSlot,
            placeholder = placeholderSlot, singleLine = singleLine,
            isError = isError, supportingText = supportingSlot,
            leadingIcon = leadingSlot, trailingIcon = trailingSlot,
            prefix = prefixSlot, suffix = suffixSlot,
            keyboardOptions = keyboardOptions, keyboardActions = keyboardActions,
            modifier = m)
        return
    }
    OutlinedTextField(
        value = value,
        enabled = enabled,
        isError = isError,
        supportingText = supportingSlot,
        leadingIcon = leadingSlot,
        trailingIcon = trailingSlot,
        prefix = prefixSlot,
        suffix = suffixSlot,
        visualTransformation = transform,
        onValueChange = onValueChange,
        label = labelSlot,
        // SPEC 17.4 `hint` is the M3 placeholder — shown while the field is
        // unfocused and empty. It was declared, elisp-validated and never
        // passed here, so every authored hint rendered as nothing.
        placeholder = placeholderSlot,
        singleLine = singleLine,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        modifier = m)
}

/** §17.4 `content_padding`: BasicTextField under the variant's own
 * DecorationBox, which is the only seam where M3 exposes the interior
 * padding. Everything else — slots, transform, keyboard — is the same
 * machinery RenderTextInput hoisted; only the decoration differs. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun RenderDenseTextInput(
    node: JsonObject,
    value: String,
    onValueChange: (String) -> Unit,
    transform: VisualTransformation,
    keyboardOptions: androidx.compose.foundation.text.KeyboardOptions,
    keyboardActions: androidx.compose.foundation.text.KeyboardActions,
    enabled: Boolean,
    singleLine: Boolean,
    isError: Boolean,
    innerPadDp: Float,
    labelSlot: (@Composable () -> Unit)?,
    placeholderSlot: (@Composable () -> Unit)?,
    supportingSlot: (@Composable () -> Unit)?,
    leadingSlot: (@Composable () -> Unit)?,
    trailingSlot: (@Composable () -> Unit)?,
    prefixSlot: (@Composable () -> Unit)?,
    suffixSlot: (@Composable () -> Unit)?,
    m: Modifier,
) {
    val interaction = remember { MutableInteractionSource() }
    val padding = PaddingValues(innerPadDp.dp)
    val filled = node.stringOr("variant") == "filled"
    val textStyle = MaterialTheme.typography.bodyLarge.copy(
        color = MaterialTheme.colorScheme.onSurface)
    androidx.compose.foundation.text.BasicTextField(
        value = value,
        onValueChange = onValueChange,
        enabled = enabled,
        singleLine = singleLine,
        textStyle = textStyle,
        cursorBrush = androidx.compose.ui.graphics.SolidColor(
            MaterialTheme.colorScheme.primary),
        visualTransformation = transform,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        interactionSource = interaction,
        modifier = m,
    ) { inner ->
        if (filled)
            TextFieldDefaults.DecorationBox(
                value = value, innerTextField = inner, enabled = enabled,
                singleLine = singleLine, visualTransformation = transform,
                interactionSource = interaction, isError = isError,
                label = labelSlot, placeholder = placeholderSlot,
                leadingIcon = leadingSlot, trailingIcon = trailingSlot,
                prefix = prefixSlot, suffix = suffixSlot,
                supportingText = supportingSlot,
                contentPadding = padding)
        else OutlinedTextFieldDefaults.DecorationBox(
            value = value, innerTextField = inner, enabled = enabled,
            singleLine = singleLine, visualTransformation = transform,
            interactionSource = interaction, isError = isError,
            label = labelSlot, placeholder = placeholderSlot,
            leadingIcon = leadingSlot, trailingIcon = trailingSlot,
            prefix = prefixSlot, suffix = suffixSlot,
            supportingText = supportingSlot,
            contentPadding = padding,
            container = {
                OutlinedTextFieldDefaults.Container(
                    enabled = enabled, isError = isError,
                    interactionSource = interaction)
            })
    }
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
private fun RenderEditor(node: JsonObject, ctx: RenderCtx, m: Modifier) {
    val id = node.stringOr("id")
    val document = node.stringOr("document")
    // SPEC 17.4: `read_only` governs editing permission and `enabled` the
    // platform disabled state; a disabled/read-only node MUST NOT dispatch.
    val readOnly = node.boolOr("read_only", false)
    val enabled = node.boolOr("enabled", true)
    val onSave = node.objOrNull("on_save")
    // A TextFieldValue (not a bare String) so the toolbar can read the live
    // selection/caret for ${selection}, placements, line ops, and edit.command.
    // SPEC 16.1/13.6: the draft keys on the wire address (surface+id), not the
    // key-first path — changing only a `key` keeps a compatible draft.
    var value by rememberSaveable(ctx.surface, id, ctx.epochOf(id),
        stateSaver = TextFieldValue.Saver,
        key = "ed:${ctx.surface}:$id:${ctx.epochOf(id)}") {
        // C6: the explicit STRING primitive read, for the reason spelled out
        // at the text_input seed — a Kotlin-String safe cast on a JsonElement
        // is always null.
        mutableStateOf(TextFieldValue(
            (ctx.storeValue(id) as? JsonPrimitive)?.takeIf { it.isString }?.content
                ?: node.stringOr("value")))
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
    val language = node.stringOr("syntax")
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
                // `old` is the base this splice is expressed against; the
                // engine refuses it if the shadow has moved since (#100).
                if (del > 0 || ins.isNotEmpty())
                    ctx.bridge.editorEdit(document, id, start, del, ins, old)
            } else {
                ctx.state(id, JsonPrimitive(new.text)) // local editor: state.changed
            }
            // SPEC 19.3 (JC-4b): the offer described the text as it WAS; drop
            // it the moment the text moves, so no stale candidate is tappable
            // even in the window before the next answer arrives.
            if (document.isNotEmpty()) ctx.bridge.clearCompletions(document, id)
        }
        value = new
    }
    // SPEC 19.3 (JC-4b): ask for completions once the text settles. Keyed on
    // the text so it re-arms per keystroke, and the delay coalesces a typing
    // burst into ONE request — §22.2 conflation, and what makes a
    // type-to-narrow picker cost a round trip per pause rather than per key.
    // SPEC 17.4: `complete` is the node's own request for completion, so it
    // gates both the round trips and the dropdown. Without it every
    // synchronized editor would pay for completions it never asked for.
    val wantsCompletion = node.boolOr("complete", false)
    val offers by ctx.bridge.completionOffers.collectAsState()
    val offer = if (wantsCompletion) offers[document to id] else null
    if (wantsCompletion && document.isNotEmpty() && !readOnly && enabled) {
        LaunchedEffect(document, id, value.text) {
            if (value.text.isEmpty()) return@LaunchedEffect
            kotlinx.coroutines.delay(180)
            ctx.bridge.editorComplete(document, id)
        }
    }
    Column(modifier = m) {
        // SPEC 17.7: the toolbar rail above the field. `command` is valid only
        // for a synchronized editor (document present) in READY — the wire side
        // enforces the session/state gate; a local editor's command no-ops.
        node.arrOrNull("toolbar")?.let { items ->
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
        // SPEC 17.4 `on_save`: the save affordance for a value+on_save
        // editor — dispatches the descriptor with the LIVE text injected
        // as `value` (§14.3, the same injection as text_input's
        // on_submit). Missing from the first shipped renderer: the
        // member was in the contract, the validator, and the elisp
        // goldens, and no chrome ever dispatched it — found by the JA-6
        // device gate when a hardware save had nothing to tap.
        if (onSave != null) {
            Row(modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End) {
                IconButton(
                    onClick = { ctx.action(onSave, JsonPrimitive(value.text)) },
                    // §17.4: a read-only or disabled editor MUST NOT
                    // dispatch — same rule the commit path pins.
                    enabled = enabled && !readOnly) {
                    Icon(IconMap.get("save"), contentDescription = "Save")
                }
            }
        }
        // SPEC 19.3 (JC-4b): the candidate list. Plain rows rather than a
        // floating DropdownMenu: this must work inside a dialog whose host
        // container scrolls, and a popup anchored to a field inside a
        // scrolling column drifts away from it.
        offer?.candidates?.take(MAX_VISIBLE_COMPLETIONS)?.forEach { cand ->
            Row(
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        ctx.bridge.editorSelectCompletion(
                            document, id, offer, cand.insert)
                    }
                    .padding(horizontal = 12.dp, vertical = 8.dp)) {
                Text(cand.label, style = MaterialTheme.typography.bodyMedium)
                cand.annotation?.let {
                    Spacer(Modifier.width(8.dp))
                    Text(it, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** How many candidates one editor shows. Emacs decides what to send; this
 * bounds what a phone-sized surface renders from it. */
private const val MAX_VISIBLE_COMPLETIONS = 12

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
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class,
    androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun RenderScaffold(node: JsonObject, ctx: RenderCtx) {
    val hostState = remember { SnackbarHostState() }
    val snackbar = node.stringOr("snackbar").takeIf { it.isNotEmpty() }
    val action = node.objOrNull("snackbar_action")
    val drawer = node.objOrNull("drawer")
    val drawerState = androidx.compose.material3.rememberDrawerState(
        androidx.compose.material3.DrawerValue.Closed)
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    LaunchedEffect(snackbar) {
        if (snackbar != null) {
            val result = hostState.showSnackbar(
                message = snackbar,
                actionLabel = action?.stringOr("label")?.takeIf { it.isNotEmpty() },
                duration = SnackbarDuration.Short)
            if (result == SnackbarResult.ActionPerformed)
                ctx.action(action?.objOrNull("on_tap"))
        }
    }
    // §17.6 `top_bar_style`: an ABSENT style keeps the plain status-bar-padded
    // Row this renderer has always drawn, so no existing chrome moves. A
    // present one asks for the real M3 TopAppBar, which is the only thing a
    // scroll behavior can attach to — the authored `top_bar` node becomes its
    // title slot, and the drawer hamburger its navigationIcon.
    val topBarStyle = node.stringOr("top_bar_style")
    val scrollBehavior: TopAppBarScrollBehavior? =
        if (topBarStyle.isEmpty()) null else when (node.stringOr("scroll_behavior")) {
            "pinned" -> TopAppBarDefaults.pinnedScrollBehavior()
            "enter_always" -> TopAppBarDefaults.enterAlwaysScrollBehavior()
            "exit_until_collapsed" -> TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
            else -> null
        }
    // §17.6 floating toolbar. Absent orientation keeps the full-width band in
    // the bottomBar slot; present, it becomes M3's real pill floating OVER the
    // body, which is what every upstream sample actually shows.
    val toolbarOrientation = node.stringOr("floating_toolbar_orientation")
    val toolbarScroll = node.boolOr("floating_toolbar_scroll")
    val toolbarBehavior: FloatingToolbarScrollBehavior? =
        if (!toolbarScroll || toolbarOrientation.isEmpty()) null
        else FloatingToolbarDefaults.exitAlwaysScrollBehavior(
            exitDirection = when (node.stringOr("floating_toolbar_exit_direction")) {
                "top" -> FloatingToolbarExitDirection.Top
                "start" -> FloatingToolbarExitDirection.Start
                "end" -> FloatingToolbarExitDirection.End
                else -> FloatingToolbarExitDirection.Bottom
            })
    val scaffold: @Composable () -> Unit = {
        Scaffold(
            modifier = Modifier
                .let { m -> scrollBehavior?.let { m.nestedScroll(it.nestedScrollConnection) } ?: m }
                .let { m -> toolbarBehavior?.let { m.nestedScroll(it) } ?: m },
            snackbarHost = { SnackbarHost(hostState) },
            topBar = {
                val topBar = node.objOrNull("top_bar")
                if (topBarStyle.isNotEmpty()) {
                    val title: @Composable () -> Unit = {
                        topBar?.let { RenderNode(it, ctx.child(it, 0)) }
                    }
                    val nav: @Composable () -> Unit = {
                        if (drawer != null) IconButton(onClick = {
                            scope.launch {
                                if (drawerState.isClosed) drawerState.open()
                                else drawerState.close()
                            }
                        }) { Icon(IconMap.get("menu"), contentDescription = "Menu") }
                    }
                    val subtitle = node.stringOr("top_bar_subtitle")
                    // Only the small TopAppBar takes a `subtitle`; the
                    // center-aligned one carries the alignment instead, so a
                    // subtitled centre bar is the small overload with
                    // titleHorizontalAlignment rather than a different bar.
                    when {
                        subtitle.isNotEmpty() && topBarStyle != "medium" &&
                            topBarStyle != "large" ->
                            TopAppBar(title = title, subtitle = { Text(subtitle) },
                                navigationIcon = nav,
                                titleHorizontalAlignment =
                                    if (topBarStyle == "center") Alignment.CenterHorizontally
                                    else Alignment.Start,
                                scrollBehavior = scrollBehavior)
                        topBarStyle == "center" -> CenterAlignedTopAppBar(
                            title = title, navigationIcon = nav,
                            scrollBehavior = scrollBehavior)
                        topBarStyle == "medium" -> MediumTopAppBar(
                            title = title, navigationIcon = nav,
                            scrollBehavior = scrollBehavior)
                        topBarStyle == "large" -> LargeTopAppBar(
                            title = title, navigationIcon = nav,
                            scrollBehavior = scrollBehavior)
                        else -> TopAppBar(title = title, navigationIcon = nav,
                            scrollBehavior = scrollBehavior)
                    }
                } else if (topBar != null || drawer != null) {
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
                node.objOrNull("fab")?.let { RenderNode(it, ctx.child(it, 2)) }
            },
            bottomBar = {
                // §17.6: a STYLED floating toolbar floats over the body
                // instead, so it is excluded here — the band below is the
                // unstyled rendering this slot has always drawn.
                val floatingToolbar =
                    if (toolbarOrientation.isEmpty()) node.objOrNull("floating_toolbar")
                    else null
                val bottomBar = node.objOrNull("bottom_bar")
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
                            // A DOCKED bar, not a floating toolbar: the M3
                            // navigation-bar container color makes it read as
                            // a band flush with the screen edge, and it owns
                            // the system navigation inset (a plain Surface,
                            // unlike M3's NavigationBar, gets no automatic
                            // inset — without it the items sit in the gesture
                            // area).
                            androidx.compose.material3.Surface(
                                color = MaterialTheme.colorScheme.surfaceContainer,
                                modifier = Modifier.fillMaxWidth()) {
                                Box(Modifier.navigationBarsPadding()
                                        .padding(horizontal = 8.dp, vertical = 6.dp)) {
                                    RenderNode(it, ctx.child(it, 4))
                                }
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
            val onRefresh = node.objOrNull("on_refresh")
            val body = node.objOrNull("body")
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
            // The pill sits OVER the body, aligned by `placement`.
            val toolbar = node.objOrNull("floating_toolbar")
            if (toolbar != null && toolbarOrientation.isNotEmpty()) {
                val expanded = node.boolOr("floating_toolbar_expanded", true)
                val fab = node.objOrNull("floating_toolbar_fab")
                val align = when (node.stringOr("floating_toolbar_placement")) {
                    "bottom_start" -> Alignment.BottomStart
                    "bottom_end" -> Alignment.BottomEnd
                    "center_start" -> Alignment.CenterStart
                    "center_end" -> Alignment.CenterEnd
                    else -> Alignment.BottomCenter
                }
                Box(Modifier.padding(inner).fillMaxSize()) {
                    val pill = Modifier.align(align).padding(16.dp)
                    val content: @Composable RowScope.() -> Unit = {
                        RenderNode(toolbar, ctx.child(toolbar, 3))
                    }
                    val vContent: @Composable ColumnScope.() -> Unit = {
                        RenderNode(toolbar, ctx.child(toolbar, 3))
                    }
                    if (toolbarOrientation == "vertical") {
                        if (fab != null) VerticalFloatingToolbar(
                            expanded = expanded, modifier = pill,
                            scrollBehavior = toolbarBehavior,
                            floatingActionButton = { RenderNode(fab, ctx.child(fab, 6)) },
                            content = vContent)
                        else VerticalFloatingToolbar(
                            expanded = expanded, modifier = pill,
                            scrollBehavior = toolbarBehavior, content = vContent)
                    } else {
                        if (fab != null) HorizontalFloatingToolbar(
                            expanded = expanded, modifier = pill,
                            scrollBehavior = toolbarBehavior,
                            floatingActionButton = { RenderNode(fab, ctx.child(fab, 6)) },
                            content = content)
                        else HorizontalFloatingToolbar(
                            expanded = expanded, modifier = pill,
                            scrollBehavior = toolbarBehavior, content = content)
                    }
                }
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
fun onButton(onTap: JsonObject?, ctx: RenderCtx) {
    onTap ?: return
    ctx.action(onTap)
}
