// SPDX-License-Identifier: GPL-3.0-or-later
// GENERATED from ebp/contract.json (format 6,
// spec 2.0.0-draft) by tools/gen-vocabulary.py — DO NOT EDIT.
// VocabularyDriftTest re-reads the contract and fails on any disagreement.
package com.calebc42.ebp.wire

data class NodeRow(val required: Set<String>, val optional: Set<String>)
data class ActionRow(val required: Set<String>, val optional: Set<String>)

const val CONTRACT_FORMAT = 6
const val SPEC_VERSION = "2.0.0-draft"

val CORE_NODE_SET: Set<String> = setOf("text", "row", "column", "box", "spacer", "divider", "button", "text_input")

val UNIVERSAL_NODE_ATTRIBUTES: Set<String> = setOf("key", "id", "scroll_here", "padding", "pad", "width", "height", "min_width", "max_width", "min_height", "max_height", "fill_fraction", "aspect_ratio", "weight", "bg", "corner", "border", "alpha", "clip", "align_self")

/** SPEC 14.6: node types whose id/value participate in input state. */
val STATEFUL_NODE_TYPES: Set<String> = setOf(
    "text_input", "checkbox", "switch", "enum_list", "slider", "editor")

val ACTION_HOOK_KEYS: Set<String> = setOf("on_tap", "on_change", "on_submit", "on_save", "on_enter", "on_pick", "on_reorder", "on_refresh", "on_long_tap", "on_add_row", "on_add_col", "on_day_tap", "on_month_change", "on_point_tap", "on_trigger", "header_action")

val OFFLINE_POLICIES: Set<String> = setOf("drop", "queue", "wake")
const val OFFLINE_DEFAULT = "drop"

val NODE_SCHEMA: Map<String, NodeRow> = mapOf(
    "text" to NodeRow(setOf("text"), setOf("style", "font_weight", "color", "selectable", "max_lines", "syntax")),
    "rich_text" to NodeRow(setOf("spans"), setOf("style")),
    "icon" to NodeRow(setOf("name"), setOf("size", "color", "badge", "content_description")),
    "image" to NodeRow(setOf("url"), setOf("content_description", "content_scale")),
    "date_stamp" to NodeRow(setOf(), setOf("day", "month", "month_index", "year", "time")),
    "section_header" to NodeRow(setOf("title"), setOf("trailing")),
    "empty_state" to NodeRow(setOf(), setOf("icon", "title", "caption", "action_label", "on_tap")),
    "progress" to NodeRow(setOf(), setOf("variant", "value")),
    "badge" to NodeRow(setOf("label"), setOf("icon", "color", "children")),
    "row" to NodeRow(setOf("children"), setOf("spacing", "align", "arrange", "scroll", "fill")),
    "column" to NodeRow(setOf("children"), setOf("spacing", "align", "arrange", "scroll", "fill")),
    "flow_row" to NodeRow(setOf("children"), setOf("spacing", "run_spacing", "align", "arrange")),
    "box" to NodeRow(setOf("children"), setOf("alignment", "on_tap")),
    "surface" to NodeRow(setOf("children"), setOf("color", "shape", "elevation")),
    "lazy_column" to NodeRow(setOf("children"), setOf("spacing", "content_padding")),
    "spacer" to NodeRow(setOf(), setOf()),
    "divider" to NodeRow(setOf(), setOf("color", "thickness")),
    "card" to NodeRow(setOf("children"), setOf("on_tap", "on_long_tap", "swipe_start", "swipe_end")),
    "collapsible" to NodeRow(setOf("id", "header", "children"), setOf("collapsed", "on_long_tap", "swipe_start", "swipe_end")),
    "reorderable_list" to NodeRow(setOf("items"), setOf("on_reorder")),
    "tabs" to NodeRow(setOf("items", "children"), setOf("initial", "scrollable", "pager_only", "on_change", "id")),
    "table" to NodeRow(setOf("rows"), setOf("aligns", "on_add_row", "on_add_col")),
    "button" to NodeRow(setOf("label", "on_tap"), setOf("icon", "variant", "enabled")),
    "icon_button" to NodeRow(setOf("icon", "on_tap"), setOf("content_description", "badge", "enabled")),
    "chip" to NodeRow(setOf("label"), setOf("on_tap", "selected", "icon", "enabled")),
    "assist_chip" to NodeRow(setOf("label"), setOf("on_tap", "icon", "enabled")),
    "menu" to NodeRow(setOf("items"), setOf("icon", "enabled")),
    "text_input" to NodeRow(setOf("id"), setOf("value", "hint", "label", "on_change", "on_submit", "single_line", "min_lines", "max_lines", "monospace", "syntax", "password", "keyboard", "autofocus", "clear_on_submit", "enabled")),
    "editor" to NodeRow(setOf("id"), setOf("document", "value", "on_save", "on_enter", "read_only", "syntax", "line_numbers", "complete", "chromeless", "publish_state", "autofocus", "toolbar", "enabled")),
    "checkbox" to NodeRow(setOf("id"), setOf("checked", "label", "on_change", "enabled")),
    "switch" to NodeRow(setOf("id"), setOf("checked", "label", "on_change", "enabled")),
    "enum_list" to NodeRow(setOf("id", "options"), setOf("value", "multi_select", "allow_add", "on_change", "enabled")),
    "date_button" to NodeRow(setOf("label", "on_pick"), setOf("value", "enabled")),
    "time_button" to NodeRow(setOf("label", "on_pick"), setOf("value", "enabled")),
    "slider" to NodeRow(setOf("id", "on_change"), setOf("value", "min", "max", "values", "enabled")),
    "chart" to NodeRow(setOf("series"), setOf("kind", "height", "y_range", "summary", "on_point_tap", "children")),
    "canvas" to NodeRow(setOf("width", "height", "ops"), setOf("children")),
    "month_grid" to NodeRow(setOf("month"), setOf("marks", "selected", "min_month", "max_month", "on_day_tap", "on_month_change", "children")),
    "scaffold" to NodeRow(setOf(), setOf("top_bar", "body", "bottom_bar", "fab", "floating_toolbar", "drawer", "snackbar", "snackbar_action", "on_refresh")),
)

val ACTION_SCHEMA: Map<String, ActionRow> = mapOf(
    "remote" to ActionRow(setOf("action"), setOf("args", "when_offline", "dedupe", "ttl_s", "confirm", "capture_fields")),
    "view.switch" to ActionRow(setOf("builtin", "view"), setOf()),
    "clipboard.copy" to ActionRow(setOf("builtin", "text"), setOf()),
    "share.send" to ActionRow(setOf("builtin", "text"), setOf("title")),
    "companion.settings.open" to ActionRow(setOf("builtin"), setOf()),
    "trigger.fire" to ActionRow(setOf("builtin", "id"), setOf()),
    "dialog.submit" to ActionRow(setOf("builtin"), setOf("value", "capture_fields")),
    "dialog.dismiss" to ActionRow(setOf("builtin"), setOf()),
)
