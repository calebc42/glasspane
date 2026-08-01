// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 4.5: max_rich_spans and max_table_cells are AGGREGATE counts across
// one SurfaceSpec or dialog document (LD-22) — enforced at validation exactly
// like max_chart_points across all series. Per-node innocence is no defense:
// the sum is what the limit bounds.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SpecLimitsTest {

    private fun spans(n: Int) = buildJsonArray {
        repeat(n) { add(buildJsonObject { put("text", "s$it") }) }
    }

    private fun richText(n: Int) = buildJsonObject {
        put("t", "rich_text"); put("spans", spans(n))
    }

    private fun column(children: List<JsonObject>) = buildJsonObject {
        put("t", "column"); put("children", JsonArray(children))
    }

    private fun table(rows: Int, cellsPerRow: Int, spansPerCell: Int = 1) = buildJsonObject {
        put("t", "table")
        putJsonArray("rows") {
            repeat(rows) {
                add(buildJsonObject {
                    put("kind", "data")
                    putJsonArray("cells") {
                        repeat(cellsPerRow) {
                            add(buildJsonObject { put("spans", spans(spansPerCell)) })
                        }
                    }
                })
            }
        }
    }

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
        val remote = buildJsonObject { put("action", "demo.act") }
        fun notif(action: JsonObject) = buildJsonObject {
            putJsonObject("body") { put("t", "text"); put("text", "x") }
            putJsonObject("meta") { putJsonArray("actions") { add(action) } }
        }
        val iconErr = runCatching {
            SpecValidator.validateNotificationSpec(notif(buildJsonObject {
                put("label", "L"); put("on_tap", remote); put("icon", longId)
            }))
        }.exceptionOrNull()
        assertTrue(iconErr is ContentInvalid)
        val keyErr = runCatching {
            SpecValidator.validateNotificationSpec(notif(buildJsonObject {
                put("label", "L"); put("on_tap", remote)
                putJsonObject("input") { put("key", longId) }
            }))
        }.exceptionOrNull()
        assertTrue(keyErr is ContentInvalid)
        // Exactly at the bound stays legal.
        SpecValidator.validateNotificationSpec(notif(buildJsonObject {
            put("label", "L"); put("on_tap", remote)
            put("icon", "a".repeat(WireLimits.MAX_IDENTIFIER_OCTETS))
        }))
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

    @Test
    fun wireLimitsAreExactlyContractLimitsFixed() {
        // SPEC 4.5 / 24.1: `contract.limits.fixed` is the machine-readable
        // form of the §4.5 table, and validate.py reads its constants FROM
        // that object — so the Python reference cannot drift. The Kotlin side
        // hardcodes them, which is the whole reason this test exists: it makes
        // the second copy of the fact provably equal to the first, and makes a
        // NEW contract constant fail here rather than sit silently unenforced
        // (which is how max_send_header_bytes reached the contract with no
        // Kotlin constant behind it at all).
        val contract = Json.parseToJsonElement(
            File(System.getProperty("ebp.dir")
                ?: error("ebp.dir system property not set"), "contract.json")
                .readText()) as JsonObject
        val fixed = contract.reqObj("limits").reqObj("fixed")
        val implemented = mapOf(
            "max_header_bytes" to WireLimits.MAX_HEADER_OCTETS,
            "max_body_bytes" to WireLimits.MAX_BODY_OCTETS,
            "max_json_depth" to WireLimits.MAX_JSON_DEPTH,
            "max_nodes_per_snapshot" to WireLimits.MAX_NODES_PER_SNAPSHOT,
            "max_children_per_node" to WireLimits.MAX_CHILDREN_PER_NODE,
            "max_identifier_bytes" to WireLimits.MAX_IDENTIFIER_OCTETS,
            "max_request_id_bytes" to WireLimits.MAX_REQUEST_ID_OCTETS,
            "max_method_bytes" to WireLimits.MAX_METHOD_OCTETS,
            "max_send_header_bytes" to WireLimits.MAX_SEND_HEADER_OCTETS,
            "max_node_depth" to WireLimits.MAX_NODE_DEPTH,
        )
        assertEquals(fixed.keys.toSortedSet(), implemented.keys.toSortedSet())
        for ((key, value) in implemented)
            assertEquals("limits.fixed.$key", fixed.reqLong(key), value.toLong())
    }

    @Test
    fun emittedHeaderSectionStaysInsideTheSenderAllowance() {
        // SPEC 4.5: 8,192 is a RECEIVER rejection threshold; a sender may only
        // rely on 128 being accepted. Even the widest legal Content-Length
        // line is nowhere near it, and encodeFrame now says so out loud.
        val frame = encodeFrame("{\"jsonrpc\":\"2.0\"}")
        val headerEnd = String(frame, Charsets.US_ASCII).indexOf("\r\n\r\n") + 4
        assertTrue(headerEnd <= WireLimits.MAX_SEND_HEADER_OCTETS)
        val widest = "Content-Length: ${WireLimits.MAX_BODY_OCTETS}\r\n\r\n"
        assertTrue(widest.length <= WireLimits.MAX_SEND_HEADER_OCTETS)
    }
}
