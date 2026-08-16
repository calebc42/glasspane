// SPDX-License-Identifier: GPL-3.0-or-later
// S11: the presented screen's back target, read out of the spec as data.
// CHROME-VOCABULARY's back contract — "every pushed screen participates in the
// stack and the system back gesture" — only holds if the system gesture runs
// the SAME descriptor the on-screen arrow carries, so exactly one reader
// decides what back means and MainActivity's BackHandler dispatches what it
// returns. Pure: no Compose, no bridge, no Android.
package com.calebc42.ebp.companion.render

import kotlinx.serialization.json.JsonObject

/**
 * The `view.switch` descriptor of VIEW's chrome back arrow, or null when this
 * screen has none — the stack bottom, a non-scaffold root, or a top bar whose
 * leading slot is something else. Null means the system default proceeds and
 * the Activity finishes, which is the pre-S11 behavior for every screen.
 *
 * VIEW is the RESOLVED current view (DeviceBridge.resolveView collapses the
 * stack's multi_view before publishing), so "this screen's back arrow" is
 * unambiguous — the views below it are not in this tree at all.
 *
 * The match is deliberately narrow, because whatever this returns HIJACKS the
 * system back gesture. Only the top bar's LEADING spine is considered, so a
 * drawer row, a body button, or a trailing bar action carrying `view.switch`
 * can never claim back — they switch views on tap and must keep doing only
 * that. The spine descends first-children through the plain containers because
 * a bar is authored either as the icon row itself (jetpacs-chrome-screen) or
 * as a box that row fills (the m3 catalog's center-aligned bar, whose title is
 * centered OVER the icons).
 *
 * A `view.switch` naming no view is refused: CompanionEngine.executeBuiltin
 * drops it, and an ENABLED handler that does nothing is strictly worse than
 * the system default it displaced.
 */
fun chromeBackDescriptor(view: JsonObject): JsonObject? {
    if (view.stringOr("t") != "scaffold") return null
    val topBar = view.objOrNull("top_bar") ?: return null
    val leading = leadingNode(topBar) ?: return null
    if (leading.stringOr("t") != "icon_button") return null
    if (leading.stringOr("icon") != "arrow_back") return null
    // A spec-disabled arrow is untappable on screen; the gesture must not
    // out-tap the button it mirrors.
    if (!leading.boolOr("enabled", true)) return null
    val onTap = leading.objOrNull("on_tap") ?: return null
    if (onTap.stringOr("builtin") != "view.switch") return null
    if (onTap.stringOr("view").isEmpty()) return null
    return onTap
}

/** The containers a top bar wraps its icons in; each one's FIRST child is the
 * leading position. `tooltip` belongs here because the house style wraps bar
 * icons in one (`jetpacs-tooltip` carries its anchor as its first child, the
 * badge shape) — without it, a tipped back arrow would silently lose the
 * system gesture while still drawing the button. `content_description` is NOT
 * part of the test: it is a11y metadata a hand-authored `jetpacs-scaffold`
 * screen may omit while wearing a structurally identical arrow, and such a
 * screen is exactly what the contract sentence says must participate. */
private val BAR_CONTAINERS = setOf("row", "box", "column", "tooltip")

/** Bounded so a deep first-child chain cannot walk out of the bar and into
 * content that is not the back affordance: the authored shapes need one
 * descent (row), two (box > row), or three with a tipped arrow
 * (box > row > tooltip). */
private const val MAX_BAR_NESTING = 3

private fun leadingNode(topBar: JsonObject): JsonObject? {
    var node = topBar
    var depth = 0
    while (node.stringOr("t") in BAR_CONTAINERS) {
        if (depth++ == MAX_BAR_NESTING) return null
        node = node.arrOrNull("children")?.firstOrNull() as? JsonObject ?: return null
    }
    return node
}
