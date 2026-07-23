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

import org.json.JSONArray
import org.json.JSONObject

object NodeSupport {

    /** SPEC 10.2: the app profile MUST include the Core Node Set plus
     * view.switch and companion.settings.open. */
    val APP_NODE_TYPES: Set<String> = sortedSetOf(
        "text", "row", "column", "box", "spacer", "divider", "button",
        "text_input", "scaffold", "editor")

    val DIALOG_NODE_TYPES: Set<String> = sortedSetOf(
        "text", "row", "column", "box", "spacer", "divider", "button",
        "text_input")

    val NOTIFICATION_NODE_TYPES: Set<String> = sortedSetOf(
        "text", "row", "column", "box", "spacer", "divider")

    val APP_BUILTINS: Set<String> = sortedSetOf("view.switch", "companion.settings.open")

    /** SPEC 10.2: the dialog profile MUST include dialog.submit/dismiss. */
    val DIALOG_BUILTINS: Set<String> = sortedSetOf("dialog.submit", "dialog.dismiss")

    /** SPEC 17.2 image forms / §17.7 registered toolbars land here with their
     * renderer support (image.https, image.data, toolbar.<id>). */
    val APP_FEATURES: Set<String> = sortedSetOf()
    val DIALOG_FEATURES: Set<String> = sortedSetOf()
    val NOTIFICATION_FEATURES: Set<String> = sortedSetOf()

    private fun profile(nodes: Set<String>, builtins: Set<String>,
                        features: Set<String>) = JSONObject()
        .put("node_types", JSONArray(nodes.toList()))
        .put("builtins", JSONArray(builtins.toList()))
        .put("features", JSONArray(features.toList()))

    /** The advertised SPEC 10.2 surface_profiles, derived — never hand-kept. */
    fun surfaceProfiles(): JSONObject = JSONObject()
        .put("app", profile(APP_NODE_TYPES, APP_BUILTINS, APP_FEATURES))
        .put("dialog", profile(DIALOG_NODE_TYPES, DIALOG_BUILTINS, DIALOG_FEATURES))
        .put("notification",
            profile(NOTIFICATION_NODE_TYPES, sortedSetOf(), NOTIFICATION_FEATURES))
}
