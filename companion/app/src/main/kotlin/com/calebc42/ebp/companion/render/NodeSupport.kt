// SPDX-License-Identifier: GPL-3.0-or-later
// The single source of truth for what THIS build's renderer honors, per
// presentation target (SPEC 10.2/16.2): DeviceBridge builds its advertised
// surface_profiles FROM these sets, so the bridge can never drift from the
// registry; NodeSupportPinTest pins the renderer's dispatch to APP_NODE_TYPES,
// so a renderer case cannot land without being advertised (or vice versa).
// Every W9 family atom widens these sets in the SAME commit as its renderer
// cases — that is the §16.2 discipline (an unadvertised node in a
// surface.update is a whole-surface 1201; an advertised one must render).
package com.calebc42.ebp.companion.render

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

object NodeSupport {

    /** SPEC 17.2 content nodes shared by the app and dialog profiles. */
    private val CONTENT_NODE_TYPES: Set<String> = sortedSetOf(
        "rich_text", "icon", "badge", "image", "section_header", "empty_state",
        "progress", "date_stamp", "tooltip")

    /** SPEC 17.2: advertising `image` REQUIRES at least one form feature in the
     * same profile — the guarded loader handles both https and base64 data. */
    private val IMAGE_FEATURES: Set<String> = sortedSetOf("image.https", "image.data")

    /** SPEC 17.4 input nodes shared by the app and dialog profiles. */
    private val INPUT_NODE_TYPES: Set<String> = sortedSetOf(
        "icon_button", "chip", "assist_chip", "menu", "checkbox", "switch",
        "enum_list", "slider", "date_button", "time_button", "split_button",
        "navigation_rail", "search_bar", "dropdown", "segmented_button")

    /** SPEC 17.3 layout nodes (app profile). */
    private val LAYOUT_NODE_TYPES: Set<String> = sortedSetOf(
        "flow_row", "surface", "lazy_column", "card", "collapsible",
        "reorderable_list", "tabs", "table", "pane_scaffold",
        "app_bar_row", "app_bar_column", "carousel")

    /** SPEC 17.5 visualization nodes (app profile). */
    private val VIZ_NODE_TYPES: Set<String> = sortedSetOf("chart", "canvas", "month_grid")

    /** SPEC 10.2: the app profile MUST include the Core Node Set plus
     * view.switch and companion.settings.open. */
    val APP_NODE_TYPES: Set<String> = sortedSetOf(
        "text", "row", "column", "box", "spacer", "divider", "button",
        "text_input", "scaffold", "editor") + CONTENT_NODE_TYPES + INPUT_NODE_TYPES +
        LAYOUT_NODE_TYPES + VIZ_NODE_TYPES

    /** SPEC 18.1/19 (JC-4b): `editor` IS advertised for dialogs. The engine
     * already opened, counted, size-checked and closed a dialog's editor
     * sessions with the dialog; only the profile withheld the type, so a
     * dialog-hosted synchronized editor degraded instead of rendering. It is
     * what a completing-read picker is built from: a field whose keystrokes
     * flow through §19 and whose `edit.complete` results Emacs answers from
     * the collection being completed. */
    val DIALOG_NODE_TYPES: Set<String> = sortedSetOf(
        "text", "row", "column", "box", "spacer", "divider", "button",
        "text_input", "editor") + CONTENT_NODE_TYPES + INPUT_NODE_TYPES

    val NOTIFICATION_NODE_TYPES: Set<String> = sortedSetOf(
        "text", "row", "column", "box", "spacer", "divider")

    /** SPEC 14.2: view.switch + companion.settings.open REQUIRED; the
     * optional clipboard.copy / share.send / trigger.fire are implemented by
     * the host and positively advertised here. */
    val APP_BUILTINS: Set<String> = sortedSetOf(
        "view.switch", "companion.settings.open", "clipboard.copy",
        "share.send", "trigger.fire")

    /** SPEC 10.2: the dialog profile MUST include dialog.submit/dismiss. */
    val DIALOG_BUILTINS: Set<String> = sortedSetOf("dialog.submit", "dialog.dismiss")

    /** SPEC 17.2 image forms / §17.7 registered toolbars land here with their
     * renderer support (image.https, image.data, toolbar.<id>). */
    val APP_FEATURES: Set<String> = IMAGE_FEATURES
    val DIALOG_FEATURES: Set<String> = IMAGE_FEATURES
    val NOTIFICATION_FEATURES: Set<String> = sortedSetOf()

    // C6: the advertised ORDER is observable — these arrays ride the welcome's
    // surface_profiles verbatim — so the `.toList()` of the sorted sets stays,
    // and JsonArray preserves list order exactly as JSONArray(Collection) did.
    // Every entry must stay a JSON string: the engine gates node types and
    // builtins with `it.asStringOrNull() == …`, so a non-string entry would
    // advertise nothing at all.
    private fun profile(nodes: Set<String>, builtins: Set<String>,
                        features: Set<String>) = buildJsonObject {
        put("node_types", JsonArray(nodes.toList().map(::JsonPrimitive)))
        put("builtins", JsonArray(builtins.toList().map(::JsonPrimitive)))
        put("features", JsonArray(features.toList().map(::JsonPrimitive)))
    }

    /** The advertised SPEC 10.2 surface_profiles, derived — never hand-kept. */
    fun surfaceProfiles(): JsonObject = buildJsonObject {
        put("app", profile(APP_NODE_TYPES, APP_BUILTINS, APP_FEATURES))
        put("dialog", profile(DIALOG_NODE_TYPES, DIALOG_BUILTINS, DIALOG_FEATURES))
        put("notification",
            profile(NOTIFICATION_NODE_TYPES, sortedSetOf(), NOTIFICATION_FEATURES))
    }
}
