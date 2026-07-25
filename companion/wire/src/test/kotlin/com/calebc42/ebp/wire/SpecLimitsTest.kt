// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 4.5: max_rich_spans and max_table_cells are AGGREGATE counts across
// one SurfaceSpec or dialog document (LD-22) — enforced at validation exactly
// like max_chart_points across all series. Per-node innocence is no defense:
// the sum is what the limit bounds.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SpecLimitsTest {

    private fun spans(n: Int) = JSONArray().also { arr ->
        repeat(n) { arr.put(JSONObject().put("text", "s$it")) }
    }

    private fun richText(n: Int) = JSONObject()
        .put("t", "rich_text").put("spans", spans(n))

    private fun column(children: List<JSONObject>) = JSONObject()
        .put("t", "column").put("children", JSONArray(children))

    private fun table(rows: Int, cellsPerRow: Int, spansPerCell: Int = 1) = JSONObject()
        .put("t", "table").put("rows", JSONArray().also { arr ->
            repeat(rows) {
                arr.put(JSONObject().put("kind", "data")
                    .put("cells", JSONArray().also { cells ->
                        repeat(cellsPerRow) {
                            cells.put(JSONObject().put("spans", spans(spansPerCell)))
                        }
                    }))
            }
        })

    @Test
    fun richSpansAggregateAcrossTheDocument() {
        val doc = column(listOf(richText(3), richText(3)))
        // 6 spans total: each node is under a per-node reading of 5, so only
        // the aggregate check can refuse this document.
        val err = runCatching {
            SpecValidator.validateSurfaceSpec(doc, maxRichSpans = 5)
        }.exceptionOrNull()
        assertTrue(err is ContentInvalid)
        assertEquals("exceeds max_rich_spans", (err as ContentInvalid).reason)
        // Exactly at the limit is legal.
        SpecValidator.validateSurfaceSpec(doc, maxRichSpans = 6)
    }

    @Test
    fun tableCellsAggregateAcrossTheDocument() {
        val doc = column(listOf(table(rows = 2, cellsPerRow = 3),
            table(rows = 1, cellsPerRow = 3)))
        // 9 cells across two tables.
        val err = runCatching {
            SpecValidator.validateSurfaceSpec(doc, maxTableCells = 8)
        }.exceptionOrNull()
        assertTrue(err is ContentInvalid)
        assertEquals("exceeds max_table_cells", (err as ContentInvalid).reason)
        SpecValidator.validateSurfaceSpec(doc, maxTableCells = 9)
    }

    @Test
    fun identifierOctetBoundAppliesToActionIconAndInputKey() {
        // LD-19: the SPEC 4.4/4.5 128-octet identifier bound applied to the
        // two sites that had only the grammar check — a notification action's
        // icon and its inline-reply input.key (both feed process-lifetime
        // maps keyed on the wire string).
        val longId = "a".repeat(WireLimits.MAX_IDENTIFIER_OCTETS + 1)
        val remote = JSONObject().put("action", "demo.act")
        fun notif(action: JSONObject) = JSONObject()
            .put("body", JSONObject().put("t", "text").put("text", "x"))
            .put("meta", JSONObject().put("actions", JSONArray().put(action)))
        val iconErr = runCatching {
            SpecValidator.validateNotificationSpec(notif(JSONObject()
                .put("label", "L").put("on_tap", remote).put("icon", longId)))
        }.exceptionOrNull()
        assertTrue(iconErr is ContentInvalid)
        val keyErr = runCatching {
            SpecValidator.validateNotificationSpec(notif(JSONObject()
                .put("label", "L").put("on_tap", remote)
                .put("input", JSONObject().put("key", longId))))
        }.exceptionOrNull()
        assertTrue(keyErr is ContentInvalid)
        // Exactly at the bound stays legal.
        SpecValidator.validateNotificationSpec(notif(JSONObject()
            .put("label", "L").put("on_tap", remote)
            .put("icon", "a".repeat(WireLimits.MAX_IDENTIFIER_OCTETS))))
    }

    @Test
    fun tableCellSpansSpendTheRichSpanAllowance() {
        // Every RichSpan in the document spends max_rich_spans — table cells
        // hold RichSpan[] too, and a "rich_text only" count would let a table
        // smuggle an unbounded span total past the aggregate limit.
        val doc = column(listOf(richText(2), table(1, 2, spansPerCell = 2)))
        val err = runCatching {
            SpecValidator.validateSurfaceSpec(doc, maxRichSpans = 5)
        }.exceptionOrNull()
        assertTrue(err is ContentInvalid)
        SpecValidator.validateSurfaceSpec(doc, maxRichSpans = 6)
    }
}
