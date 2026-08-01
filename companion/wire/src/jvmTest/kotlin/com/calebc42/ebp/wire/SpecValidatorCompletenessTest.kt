// SPDX-License-Identifier: GPL-3.0-or-later
// W9 conformance: the deep per-type MUST-reject rules (SPEC 17.2-17.5, 17.7)
// added for the organ port — a Companion advertising a type must be able to
// reject its nonconforming shapes (whole-surface 1201), or advertising it
// would accept invalid content. Accept-side coverage is the golden replay.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class SpecValidatorCompletenessTest {

    private fun node(t: String, vararg kv: Pair<String, JsonElement>) =
        buildJsonObject { put("t", t); kv.forEach { put(it.first, it.second) } }

    private fun remote() = buildJsonObject { put("action", "demo.act") }

    private fun accepts(spec: JsonObject) {
        SpecValidator.validateSurfaceSpec(spec)
    }

    private fun rejects(spec: JsonObject, fragment: String) {
        try {
            SpecValidator.validateSurfaceSpec(spec)
            fail("accepted, expected reject matching: $fragment")
        } catch (e: ContentInvalid) {
            assertTrue("${e.reason} @ ${e.path} !~ $fragment",
                e.reason.contains(fragment) || e.path.contains(fragment))
        }
    }

    // ------------------------------ A6/#108: node nesting depth (SPEC 4.5)

    @Test
    fun nodeNestingDepthIsBounded() {
        // The 4.5 JSON-container limit is a RECEIVER acceptance bound, not a
        // budget a sender may spend: host encoders cap well below it (Emacs's
        // json-serialize stops at 50 containers with no override), so a
        // document nested to the JSON limit is unemittable by a conforming
        // Emacs endpoint and its reply would be lost, not refused.
        fun nest(levels: Int): JsonObject {
            var n = node("text", "text" to JsonPrimitive("leaf"))
            repeat(levels - 1) { n = node("column", "children" to JsonArray(listOf(n))) }
            return n
        }
        accepts(nest(20))
        rejects(nest(21), "node-depth")
        // Depth is per PATH, not a running total: many shallow siblings are
        // fine even though the node count is high.
        val wide = buildJsonArray { repeat(50) { add(nest(19)) } }
        accepts(node("column", "children" to wide))
    }

    // ------------------------------------- LD-10: contract field-type checks

    @Test
    fun scalarMembersAreTypeCheckedNotCoerced() {
        // The org.json accessors coerced silently. Each of these was ACCEPTED
        // and rendered with the wrong meaning; now the document is refused.
        // A disabled node that rendered enabled (optBoolean default trap):
        rejects(node("button", "label" to JsonPrimitive("x"), "on_tap" to remote(),
            "enabled" to JsonPrimitive(0)), "enabled must be a boolean")
        // A password field flagged with the STRING "true":
        rejects(node("text_input", "id" to JsonPrimitive("p"),
            "password" to JsonPrimitive("true")),
            "password must be a boolean")
        // An object coerced into a heading string:
        rejects(node("section_header", "title" to buildJsonObject { put("secret", "x") }),
            "title must be a string")
        // A dp attribute given a string (spacing is a column dp member):
        rejects(node("column", "children" to JsonArray(emptyList()),
            "spacing" to JsonPrimitive("5")),
            "spacing must be a finite number")
        // The logical values still pass.
        accepts(node("button", "label" to JsonPrimitive("x"), "on_tap" to remote(),
            "enabled" to JsonPrimitive(false)))
        accepts(node("text_input", "id" to JsonPrimitive("p"),
            "password" to JsonPrimitive(true)))
        accepts(node("section_header", "title" to JsonPrimitive("Heading")))
    }

    // --------------------------------------- LD-17: builtin-context gate (14.2)

    @Test
    fun aBuiltinOutsideTheTargetProfileRejectsTheDocument() {
        val dialogBuiltins = setOf("dialog.submit", "dialog.dismiss")
        // clipboard.copy is a real builtin but not advertised for a dialog —
        // invalid context, so the whole document is refused (not degraded).
        val spec = node("button", "label" to JsonPrimitive("Copy"),
            "on_tap" to buildJsonObject { put("builtin", "clipboard.copy") })
        try {
            SpecValidator.validateSurfaceSpec(spec,
                advertisedTypes = setOf("button", "column"),
                advertisedBuiltins = dialogBuiltins)
            fail("accepted a builtin outside the target profile")
        } catch (e: ContentInvalid) {
            assertTrue(e.reason.contains("not valid in this context"))
        }
        // An advertised builtin in the same target is accepted.
        SpecValidator.validateSurfaceSpec(
            node("button", "label" to JsonPrimitive("OK"),
                "on_tap" to buildJsonObject { put("builtin", "dialog.submit") }),
            advertisedTypes = setOf("button", "column"),
            advertisedBuiltins = dialogBuiltins)
    }

    // ------------------------------------------------------- content (17.2)

    @Test
    fun contentRules() {
        rejects(node("text", "text" to JsonPrimitive("x"),
            "max_lines" to JsonPrimitive(0)), "positive integer")
        rejects(node("text", "text" to JsonPrimitive("x"),
            "max_lines" to JsonPrimitive(1.5)), "positive integer")
        rejects(node("rich_text", "spans" to buildJsonArray {
            add(buildJsonObject { put("bold", true) })
        }), "span text must be a string")
        rejects(node("rich_text", "spans" to JsonPrimitive("nope")), "array of spans")
        rejects(node("empty_state", "action_label" to JsonPrimitive("Go")), "together")
        rejects(node("empty_state",
            "on_tap" to buildJsonObject { put("action", "a.b") }), "together")
        accepts(node("empty_state", "action_label" to JsonPrimitive("Go"),
            "on_tap" to buildJsonObject { put("action", "a.b") }))
        rejects(node("progress", "value" to JsonPrimitive(1.5)), "0..1")
        rejects(node("progress", "value" to JsonPrimitive(-0.1)), "0..1")
        accepts(node("progress", "value" to JsonPrimitive(0.5)))
        rejects(node("date_stamp", "day" to JsonPrimitive(32)), "1..31")
        rejects(node("date_stamp", "month_index" to JsonPrimitive(0)), "1..12")
        rejects(node("date_stamp", "year" to JsonPrimitive(-1)), "non-negative")
    }

    // -------------------------------------------------------- layout (17.3)

    @Test
    fun reorderableListNeedsUniqueKeys() {
        fun list(vararg items: JsonObject) =
            node("reorderable_list", "items" to JsonArray(items.toList()))
        rejects(list(node("text", "text" to JsonPrimitive("a"))), "key or id")
        rejects(list(node("text", "text" to JsonPrimitive("a"), "key" to JsonPrimitive("k")),
            node("text", "text" to JsonPrimitive("b"), "key" to JsonPrimitive("k"))),
            "duplicate item key")
        accepts(list(node("text", "text" to JsonPrimitive("a"), "key" to JsonPrimitive("k1")),
            node("text", "text" to JsonPrimitive("b"), "id" to JsonPrimitive("k2"))))
    }

    @Test
    fun tabsPairingAndInitial() {
        fun tabs(items: JsonArray, children: JsonArray, initial: JsonElement? = null) =
            node("tabs", "items" to items, "children" to children)
                .let { if (initial != null) it.with("initial", initial) else it }
        val item = buildJsonObject { put("label", "One") }
        val child = node("text", "text" to JsonPrimitive("one"))
        rejects(tabs(JsonArray(emptyList()), JsonArray(emptyList())),
            "equal non-zero length")
        rejects(tabs(JsonArray(listOf(item)), JsonArray(emptyList())),
            "equal non-zero length")
        rejects(tabs(JsonArray(listOf(buildJsonObject { put("icon", "star") })),
            JsonArray(listOf(child))), "label")
        rejects(tabs(JsonArray(listOf(item)), JsonArray(listOf(child)),
            JsonPrimitive(1)), "index")
        // A negative `initial` is caught by the LD-10 field-type check
        // (contract non-negative-integer) before the tabs range rule.
        rejects(tabs(JsonArray(listOf(item)), JsonArray(listOf(child)), JsonPrimitive(-1)),
            "non-negative integer")
        accepts(tabs(JsonArray(listOf(item)), JsonArray(listOf(child)), JsonPrimitive(0)))
    }

    @Test
    fun tableRowRules() {
        fun table(vararg rows: JsonObject) =
            node("table", "rows" to JsonArray(rows.toList()))
        val cell = buildJsonObject {
            putJsonArray("spans") { add(buildJsonObject { put("text", "v") }) }
        }
        rejects(table(buildJsonObject { put("kind", "mystery") }), "unknown table row kind")
        rejects(table(buildJsonObject {
            put("kind", "data")
            putJsonArray("cells") { add(buildJsonObject { put("text", "bare") }) }
        }), "spans")
        accepts(table(buildJsonObject {
            put("kind", "header")
            putJsonArray("cells") { add(cell) }
        }, buildJsonObject { put("kind", "rule") }))
        rejects(node("table",
            "rows" to buildJsonArray { add(buildJsonObject { put("kind", "rule") }) },
            "aligns" to JsonArray(listOf(JsonPrimitive("wide")))), "start|center|end")
    }

    // --------------------------------------------------------- input (17.4)

    @Test
    fun lineCountRules() {
        rejects(node("text_input", "id" to JsonPrimitive("a"),
            "min_lines" to JsonPrimitive(0)), "positive integer")
        rejects(node("text_input", "id" to JsonPrimitive("a"),
            "min_lines" to JsonPrimitive(3), "max_lines" to JsonPrimitive(2)),
            "must not exceed")
        rejects(node("text_input", "id" to JsonPrimitive("a"),
            "single_line" to JsonPrimitive(true),
            "min_lines" to JsonPrimitive(2), "max_lines" to JsonPrimitive(2)),
            "line counts of 1")
        accepts(node("text_input", "id" to JsonPrimitive("a"),
            "min_lines" to JsonPrimitive(2), "max_lines" to JsonPrimitive(4)))
    }

    @Test
    fun sliderValueRules() {
        rejects(node("slider", "id" to JsonPrimitive("s"),
            "on_change" to buildJsonObject { put("action", "a.b") },
            "values" to JsonArray(listOf(1, 5, 9).map(::JsonPrimitive)),
            "value" to JsonPrimitive(4)),
            "listed discrete value")
        accepts(node("slider", "id" to JsonPrimitive("s"),
            "on_change" to buildJsonObject { put("action", "a.b") },
            "values" to JsonArray(listOf(1, 5, 9).map(::JsonPrimitive)),
            "value" to JsonPrimitive(5)))
        rejects(node("slider", "id" to JsonPrimitive("s"),
            "on_change" to buildJsonObject { put("action", "a.b") },
            "min" to JsonPrimitive(0), "max" to JsonPrimitive(10),
            "value" to JsonPrimitive(11)), "within min..max")
        accepts(node("slider", "id" to JsonPrimitive("s"),
            "on_change" to buildJsonObject { put("action", "a.b") },
            "min" to JsonPrimitive(0), "max" to JsonPrimitive(10),
            "value" to JsonPrimitive(10)))
    }

    @Test
    fun enumListValueMembership() {
        val options = buildJsonArray {
            add(buildJsonObject { put("label", "A"); put("value", "a") })
            add(buildJsonObject { put("label", "B"); put("value", "b") })
        }
        rejects(node("enum_list", "id" to JsonPrimitive("e"), "options" to options,
            "value" to JsonPrimitive("zzz")),
            "not in options")
        accepts(node("enum_list", "id" to JsonPrimitive("e"), "options" to options,
            "value" to JsonPrimitive("b")))
        // allow_add admits an unlisted string.
        accepts(node("enum_list", "id" to JsonPrimitive("e"), "options" to options,
            "allow_add" to JsonPrimitive(true), "value" to JsonPrimitive("new-entry")))
        rejects(node("enum_list", "id" to JsonPrimitive("e"), "options" to options,
            "multi_select" to JsonPrimitive(true), "value" to JsonPrimitive("a")),
            "must be an array")
        rejects(node("enum_list", "id" to JsonPrimitive("e"), "options" to options,
            "multi_select" to JsonPrimitive(true),
            "value" to JsonArray(listOf("a", "a").map(::JsonPrimitive))),
            "duplicate selected")
        accepts(node("enum_list", "id" to JsonPrimitive("e"), "options" to options,
            "multi_select" to JsonPrimitive(true),
            "value" to JsonArray(listOf("a", "b").map(::JsonPrimitive))))
        rejects(node("enum_list", "id" to JsonPrimitive("e"), "options" to options,
            "value" to JsonArray(listOf("a").map(::JsonPrimitive))), "scalar")
    }

    // ------------------------------------------------------- editor (17.7)

    @Test
    fun editorCompleteAndToolbarRules() {
        rejects(node("editor", "id" to JsonPrimitive("e"),
            "complete" to JsonPrimitive(true)), "complete requires document")
        fun toolbar(vararg items: JsonObject) = node("editor", "id" to JsonPrimitive("e"),
            "toolbar" to JsonArray(items.toList()))
        rejects(toolbar(buildJsonObject { put("label", "X") }),
            "exactly one primary operation")
        rejects(toolbar(buildJsonObject {
            put("label", "X"); put("snippet", "s"); put("line", "promote")
        }), "exactly one primary operation")
        rejects(toolbar(buildJsonObject { put("snippet", "s") }), "label or icon")
        // SPEC 17.7 (amendment #61): at most one ${input:...} token per snippet.
        rejects(toolbar(buildJsonObject {
            put("label", "X"); put("snippet", "\${input:First} \${input:Second}")
        }), "at most one")
        accepts(node("editor", "id" to JsonPrimitive("e"), "toolbar" to buildJsonArray {
            add(buildJsonObject { put("label", "X"); put("snippet", "hi \${input:Name}") })
        }))
        rejects(toolbar(buildJsonObject { put("label", "X"); put("command", "fmt") }),
            "command requires document")
        accepts(node("editor", "id" to JsonPrimitive("e"),
            "document" to JsonPrimitive("doc.org"),
            "toolbar" to buildJsonArray {
                add(buildJsonObject { put("label", "X"); put("command", "fmt") })
            }))
        // menu holds only non-menu items.
        rejects(toolbar(buildJsonObject {
            put("label", "M")
            putJsonArray("menu") {
                add(buildJsonObject { put("label", "N"); putJsonArray("menu") {} })
            }
        }), "non-menu")
        // long_press carries exactly one non-menu operation.
        rejects(toolbar(buildJsonObject {
            put("label", "X"); put("snippet", "s")
            putJsonObject("long_press") { put("label", "L"); putJsonArray("menu") {} }
        }), "non-menu")
        // SPEC 17.7: long_press is an OP PLIST — no label/icon required
        // (the JA-5 device gate: rejecting bare ops killed every toolbar
        // whose long-press was authored to spec).
        accepts(toolbar(buildJsonObject {
            put("label", "X"); put("snippet", "s")
            putJsonObject("long_press") { put("snippet", "[%]") }
        }))
        rejects(toolbar(buildJsonObject {
            put("label", "X"); put("snippet", "s")
            put("long_press", JsonObject(emptyMap()))
        }), "exactly one")
        rejects(toolbar(buildJsonObject {
            put("label", "X"); put("snippet", "s"); put("placement", "everywhere")
        }), "cursor|line-start|block")
        // An unrecognized `line` VALUE is a render no-op, never a reject.
        accepts(toolbar(buildJsonObject { put("label", "X"); put("line", "sideways") }))
        // A registered-identifier toolbar is structurally a string.
        accepts(node("editor", "id" to JsonPrimitive("e"),
            "toolbar" to JsonPrimitive("org-basic")))
        rejects(node("editor", "id" to JsonPrimitive("e"),
            "toolbar" to JsonPrimitive(7)), "identifier or item array")
    }

    // ------------------------------------------------- visualization (17.5)

    @Test
    fun chartRules() {
        fun chart(points: JsonArray) = node("chart", "series" to buildJsonArray {
            add(buildJsonObject { put("points", points) })
        })
        rejects(chart(buildJsonArray { add(buildJsonObject { put("x", 1) }) }),
            "finite number")
        // A builder never produces a non-finite number, but an overflowing
        // JSON literal ("1e999") parses fine under the LENIENT reader and its
        // binary64 VALUE reads as Infinity. The wire cannot deliver this —
        // EbpJson refuses overflow in-parse (EbpJsonTest pins 1e309) — but the
        // PERSISTENCE path can (stores read via Json.parseToJsonElement), so
        // the validator's finite gate still needs the fixture; it stays raw
        // text because no builder can spell it.
        rejects(chart(buildJsonArray {
            add(Json.parseToJsonElement("""{"x":1,"y":1e999}""") as JsonObject)
        }), "finite")
        accepts(chart(buildJsonArray {
            add(buildJsonObject { put("x", 1); put("y", 2) })
        }))
        rejects(node("chart", "series" to JsonArray(emptyList()),
            "y_range" to JsonArray(listOf(5, 5).map(::JsonPrimitive))), "min < max")
        rejects(node("chart", "series" to JsonArray(emptyList()),
            "height" to JsonPrimitive(0)), "positive")
    }

    @Test
    fun canvasRules() {
        fun canvas(vararg ops: JsonObject) = node("canvas",
            "width" to JsonPrimitive(100), "height" to JsonPrimitive(100),
            "ops" to JsonArray(ops.toList()))
        rejects(node("canvas", "width" to JsonPrimitive(0), "height" to JsonPrimitive(10),
            "ops" to JsonArray(emptyList())), "positive")
        rejects(canvas(buildJsonObject {
            put("op", "line"); put("x1", 0); put("y1", 0); put("x2", 5)
        }), "missing required y2")
        rejects(canvas(buildJsonObject {
            put("op", "circle"); put("cx", 0); put("cy", 0); put("radius", -1)
        }), "non-negative")
        rejects(canvas(buildJsonObject {
            put("op", "path")
            putJsonArray("points") { add(buildJsonObject { put("x", 1) }) }
        }), "finite number")
        // An unknown op is skipped, never rejected (SPEC 17.5).
        accepts(canvas(buildJsonObject { put("op", "sparkle"); put("magic", true) }))
        accepts(canvas(buildJsonObject {
            put("op", "rect"); put("x", 0); put("y", 0)
            put("width", 10); put("height", 10)
        }))
    }

    @Test
    fun monthGridRules() {
        rejects(node("month_grid", "month" to JsonPrimitive("2026-13")), "YYYY-MM")
        rejects(node("month_grid", "month" to JsonPrimitive("2026-07"),
            "selected" to JsonPrimitive("2026-7-4")),
            "YYYY-MM-DD")
        rejects(node("month_grid", "month" to JsonPrimitive("2026-07"),
            "min_month" to JsonPrimitive("2026-08"),
            "max_month" to JsonPrimitive("2026-06")), "must not follow")
        rejects(node("month_grid", "month" to JsonPrimitive("2026-07"),
            "marks" to buildJsonObject {
                putJsonObject("2026-07-04") { put("dots", 4) }
            }),
            "0..3")
        rejects(node("month_grid", "month" to JsonPrimitive("2026-07"),
            "marks" to buildJsonObject {
                putJsonObject("July 4") { put("dots", 1) }
            }),
            "YYYY-MM-DD")
        accepts(node("month_grid", "month" to JsonPrimitive("2026-07"),
            "min_month" to JsonPrimitive("2026-01"), "max_month" to JsonPrimitive("2026-12"),
            "selected" to JsonPrimitive("2026-07-04"),
            "marks" to buildJsonObject {
                putJsonObject("2026-07-04") { put("dots", 2); put("color", "primary") }
            }))
    }
}
