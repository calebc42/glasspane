// SPDX-License-Identifier: GPL-3.0-or-later
// W9 conformance: the deep per-type MUST-reject rules (SPEC 17.2-17.5, 17.7)
// added for the organ port — a Companion advertising a type must be able to
// reject its nonconforming shapes (whole-surface 1201), or advertising it
// would accept invalid content. Accept-side coverage is the golden replay.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class SpecValidatorCompletenessTest {

    private fun node(t: String, vararg kv: Pair<String, Any?>) =
        JSONObject().put("t", t).apply { kv.forEach { put(it.first, it.second) } }

    private fun accepts(spec: JSONObject) {
        SpecValidator.validateSurfaceSpec(spec)
    }

    private fun rejects(spec: JSONObject, fragment: String) {
        try {
            SpecValidator.validateSurfaceSpec(spec)
            fail("accepted, expected reject matching: $fragment")
        } catch (e: ContentInvalid) {
            assertTrue("${e.reason} @ ${e.path} !~ $fragment",
                e.reason.contains(fragment) || e.path.contains(fragment))
        }
    }

    // ------------------------------------------------------- content (17.2)

    @Test
    fun contentRules() {
        rejects(node("text", "text" to "x", "max_lines" to 0), "positive integer")
        rejects(node("text", "text" to "x", "max_lines" to 1.5), "positive integer")
        rejects(node("rich_text", "spans" to JSONArray().put(JSONObject().put("bold", true))),
            "span text must be a string")
        rejects(node("rich_text", "spans" to "nope"), "array of spans")
        rejects(node("empty_state", "action_label" to "Go"), "together")
        rejects(node("empty_state",
            "on_tap" to JSONObject().put("action", "a.b")), "together")
        accepts(node("empty_state", "action_label" to "Go",
            "on_tap" to JSONObject().put("action", "a.b")))
        rejects(node("progress", "value" to 1.5), "0..1")
        rejects(node("progress", "value" to -0.1), "0..1")
        accepts(node("progress", "value" to 0.5))
        rejects(node("date_stamp", "day" to 32), "1..31")
        rejects(node("date_stamp", "month_index" to 0), "1..12")
        rejects(node("date_stamp", "year" to -1), "non-negative")
    }

    // -------------------------------------------------------- layout (17.3)

    @Test
    fun reorderableListNeedsUniqueKeys() {
        fun list(vararg items: JSONObject) =
            node("reorderable_list", "items" to JSONArray(items.toList()))
        rejects(list(node("text", "text" to "a")), "key or id")
        rejects(list(node("text", "text" to "a", "key" to "k"),
            node("text", "text" to "b", "key" to "k")), "duplicate item key")
        accepts(list(node("text", "text" to "a", "key" to "k1"),
            node("text", "text" to "b", "id" to "k2")))
    }

    @Test
    fun tabsPairingAndInitial() {
        fun tabs(items: JSONArray, children: JSONArray, initial: Any? = null) =
            node("tabs", "items" to items, "children" to children)
                .apply { if (initial != null) put("initial", initial) }
        val item = JSONObject().put("label", "One")
        val child = node("text", "text" to "one")
        rejects(tabs(JSONArray(), JSONArray()), "equal non-zero length")
        rejects(tabs(JSONArray().put(item), JSONArray()), "equal non-zero length")
        rejects(tabs(JSONArray().put(JSONObject().put("icon", "star")),
            JSONArray().put(child)), "label")
        rejects(tabs(JSONArray().put(item), JSONArray().put(child), 1), "index")
        rejects(tabs(JSONArray().put(item), JSONArray().put(child), -1), "index")
        accepts(tabs(JSONArray().put(item), JSONArray().put(child), 0))
    }

    @Test
    fun tableRowRules() {
        fun table(vararg rows: JSONObject) =
            node("table", "rows" to JSONArray(rows.toList()))
        val cell = JSONObject().put("spans",
            JSONArray().put(JSONObject().put("text", "v")))
        rejects(table(JSONObject().put("kind", "mystery")), "unknown table row kind")
        rejects(table(JSONObject().put("kind", "data")
            .put("cells", JSONArray().put(JSONObject().put("text", "bare")))), "spans")
        accepts(table(JSONObject().put("kind", "header")
            .put("cells", JSONArray().put(cell)),
            JSONObject().put("kind", "rule")))
        rejects(node("table", "rows" to JSONArray()
            .put(JSONObject().put("kind", "rule")),
            "aligns" to JSONArray().put("wide")), "start|center|end")
    }

    // --------------------------------------------------------- input (17.4)

    @Test
    fun lineCountRules() {
        rejects(node("text_input", "id" to "a", "min_lines" to 0), "positive integer")
        rejects(node("text_input", "id" to "a", "min_lines" to 3, "max_lines" to 2),
            "must not exceed")
        rejects(node("text_input", "id" to "a", "single_line" to true,
            "min_lines" to 2, "max_lines" to 2), "line counts of 1")
        accepts(node("text_input", "id" to "a", "min_lines" to 2, "max_lines" to 4))
    }

    @Test
    fun sliderValueRules() {
        rejects(node("slider", "id" to "s", "on_change" to JSONObject().put("action", "a.b"),
            "values" to JSONArray(listOf(1, 5, 9)), "value" to 4),
            "listed discrete value")
        accepts(node("slider", "id" to "s", "on_change" to JSONObject().put("action", "a.b"),
            "values" to JSONArray(listOf(1, 5, 9)), "value" to 5))
        rejects(node("slider", "id" to "s", "on_change" to JSONObject().put("action", "a.b"),
            "min" to 0, "max" to 10, "value" to 11), "within min..max")
        accepts(node("slider", "id" to "s", "on_change" to JSONObject().put("action", "a.b"),
            "min" to 0, "max" to 10, "value" to 10))
    }

    @Test
    fun enumListValueMembership() {
        val options = JSONArray()
            .put(JSONObject().put("label", "A").put("value", "a"))
            .put(JSONObject().put("label", "B").put("value", "b"))
        rejects(node("enum_list", "id" to "e", "options" to options, "value" to "zzz"),
            "not in options")
        accepts(node("enum_list", "id" to "e", "options" to options, "value" to "b"))
        // allow_add admits an unlisted string.
        accepts(node("enum_list", "id" to "e", "options" to options,
            "allow_add" to true, "value" to "new-entry"))
        rejects(node("enum_list", "id" to "e", "options" to options,
            "multi_select" to true, "value" to "a"), "must be an array")
        rejects(node("enum_list", "id" to "e", "options" to options,
            "multi_select" to true, "value" to JSONArray(listOf("a", "a"))),
            "duplicate selected")
        accepts(node("enum_list", "id" to "e", "options" to options,
            "multi_select" to true, "value" to JSONArray(listOf("a", "b"))))
        rejects(node("enum_list", "id" to "e", "options" to options,
            "value" to JSONArray(listOf("a"))), "scalar")
    }

    // ------------------------------------------------------- editor (17.7)

    @Test
    fun editorCompleteAndToolbarRules() {
        rejects(node("editor", "id" to "e", "complete" to true), "complete requires document")
        fun toolbar(vararg items: JSONObject) = node("editor", "id" to "e",
            "toolbar" to JSONArray(items.toList()))
        rejects(toolbar(JSONObject().put("label", "X")), "exactly one primary operation")
        rejects(toolbar(JSONObject().put("label", "X").put("snippet", "s")
            .put("line", "promote")), "exactly one primary operation")
        rejects(toolbar(JSONObject().put("snippet", "s")), "label or icon")
        // SPEC 17.7 (amendment #61): at most one ${input:...} token per snippet.
        rejects(toolbar(JSONObject().put("label", "X")
            .put("snippet", "\${input:First} \${input:Second}")), "at most one")
        accepts(node("editor", "id" to "e", "toolbar" to JSONArray()
            .put(JSONObject().put("label", "X").put("snippet", "hi \${input:Name}"))))
        rejects(toolbar(JSONObject().put("label", "X").put("command", "fmt")),
            "command requires document")
        accepts(node("editor", "id" to "e", "document" to "doc.org",
            "toolbar" to JSONArray().put(JSONObject().put("label", "X")
                .put("command", "fmt"))))
        // menu holds only non-menu items.
        rejects(toolbar(JSONObject().put("label", "M").put("menu", JSONArray()
            .put(JSONObject().put("label", "N").put("menu", JSONArray())))),
            "non-menu")
        // long_press carries exactly one non-menu operation.
        rejects(toolbar(JSONObject().put("label", "X").put("snippet", "s")
            .put("long_press", JSONObject().put("label", "L")
                .put("menu", JSONArray()))), "non-menu")
        rejects(toolbar(JSONObject().put("label", "X").put("snippet", "s")
            .put("placement", "everywhere")), "cursor|line-start|block")
        // An unrecognized `line` VALUE is a render no-op, never a reject.
        accepts(toolbar(JSONObject().put("label", "X").put("line", "sideways")))
        // A registered-identifier toolbar is structurally a string.
        accepts(node("editor", "id" to "e", "toolbar" to "org-basic"))
        rejects(node("editor", "id" to "e", "toolbar" to 7), "identifier or item array")
    }

    // ------------------------------------------------- visualization (17.5)

    @Test
    fun chartRules() {
        fun chart(points: JSONArray) = node("chart", "series" to JSONArray()
            .put(JSONObject().put("points", points)))
        rejects(chart(JSONArray().put(JSONObject().put("x", 1))), "finite number")
        // org.json refuses to CONSTRUCT non-finite numbers, but an overflowing
        // JSON literal parses to Infinity — the wire-reachable vector.
        rejects(chart(JSONArray().put(JSONObject("""{"x":1,"y":1e999}"""))), "finite")
        accepts(chart(JSONArray().put(JSONObject().put("x", 1).put("y", 2))))
        rejects(node("chart", "series" to JSONArray(),
            "y_range" to JSONArray(listOf(5, 5))), "min < max")
        rejects(node("chart", "series" to JSONArray(), "height" to 0), "positive")
    }

    @Test
    fun canvasRules() {
        fun canvas(vararg ops: JSONObject) = node("canvas",
            "width" to 100, "height" to 100, "ops" to JSONArray(ops.toList()))
        rejects(node("canvas", "width" to 0, "height" to 10,
            "ops" to JSONArray()), "positive")
        rejects(canvas(JSONObject().put("op", "line").put("x1", 0).put("y1", 0)
            .put("x2", 5)), "missing required y2")
        rejects(canvas(JSONObject().put("op", "circle").put("cx", 0).put("cy", 0)
            .put("radius", -1)), "non-negative")
        rejects(canvas(JSONObject().put("op", "path")
            .put("points", JSONArray().put(JSONObject().put("x", 1)))), "finite number")
        // An unknown op is skipped, never rejected (SPEC 17.5).
        accepts(canvas(JSONObject().put("op", "sparkle").put("magic", true)))
        accepts(canvas(JSONObject().put("op", "rect").put("x", 0).put("y", 0)
            .put("width", 10).put("height", 10)))
    }

    @Test
    fun monthGridRules() {
        rejects(node("month_grid", "month" to "2026-13"), "YYYY-MM")
        rejects(node("month_grid", "month" to "2026-07", "selected" to "2026-7-4"),
            "YYYY-MM-DD")
        rejects(node("month_grid", "month" to "2026-07",
            "min_month" to "2026-08", "max_month" to "2026-06"), "must not follow")
        rejects(node("month_grid", "month" to "2026-07",
            "marks" to JSONObject().put("2026-07-04", JSONObject().put("dots", 4))),
            "0..3")
        rejects(node("month_grid", "month" to "2026-07",
            "marks" to JSONObject().put("July 4", JSONObject().put("dots", 1))),
            "YYYY-MM-DD")
        accepts(node("month_grid", "month" to "2026-07",
            "min_month" to "2026-01", "max_month" to "2026-12",
            "selected" to "2026-07-04",
            "marks" to JSONObject().put("2026-07-04",
                JSONObject().put("dots", 2).put("color", "primary"))))
    }
}
