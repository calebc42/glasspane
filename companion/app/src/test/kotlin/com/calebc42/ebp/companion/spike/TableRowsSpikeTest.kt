// SPDX-License-Identifier: GPL-3.0-or-later
// THROWAWAY — spike-kotlin of PLAN-refound's data-spike rung. See README.md
// in this directory for the questions, kill criteria, and removal commit.
//
// Drives the REAL engine with the app's REAL advertisement
// (NodeSupport.surfaceProfiles()) and the same limits DeviceBridge declares,
// through the full frame path: encodeFrame -> FrameDecoder -> EbpJson.parse ->
// SpecValidator -> SurfaceStore. Rows are SYNTHETIC, matching the distribution
// spike-elisp measured on the live vault (586 notes; full row mean 524 B,
// p95 581, max 679, no tail) — the repo is public and vault content stays out
// of it. Timings print with a SPIKE prefix; read them from the test XML.
package com.calebc42.ebp.companion.spike

import com.calebc42.ebp.companion.render.NodeSupport
import com.calebc42.ebp.wire.CompanionConfig
import com.calebc42.ebp.wire.CompanionEngine
import com.calebc42.ebp.wire.EbpAuth
import com.calebc42.ebp.wire.FrameDecoder
import com.calebc42.ebp.wire.encodeFrame
import com.calebc42.ebp.wire.request
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TableRowsSpikeTest {

    private val katToken = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
    private val katPid = "101112131415161718191a1b1c1d1e1f"
    private val katCn = "202122232425262728292a2b2c2d2e2f"
    private val katSn = "303132333435363738393a3b3c3d3e3f"

    /** The vault spike-elisp measured: the halves bridge on these numbers. */
    private companion object {
        const val NOTES = 586
        const val MINIMAL_COLS = 5   // id/title/todo/tags/level
        const val FULL_COLS = 16     // every struct scalar + props
        const val CELL_CAP = 4096L   // max_table_cells, aggregate (LD-22)
    }

    /** The app's own limits, mirrored from DeviceBridge.kt — integer-spelled. */
    private fun appLimits(): JsonObject = buildJsonObject {
        put("max_frame_bytes", 4_194_304)
        put("max_queued_events", 256)
        put("max_queued_bytes", 8_388_608)
        put("max_event_bytes", 262_144)
        put("max_surfaces", 64)
        put("max_surface_ids", 4096)
        put("max_field_bytes", 65_536)
        put("max_input_state_bytes", 262_144)
        put("max_capture_fields", 64)
        put("max_dialogs", 4)
        put("max_pie_menus", 1)
        put("max_reminders", 256)
        put("max_editor_sessions", 8)
        put("max_trigger_responses", 8)
        put("max_triggers", 64)
        put("max_device_report_bytes", 8192)
        put("max_chart_points", 4096)
        put("max_canvas_ops", 4096)
        put("max_rich_spans", 4096)
        put("max_table_cells", CELL_CAP)
        put("max_editor_bytes", 262_144)
    }

    private fun engine(out: MutableList<JsonObject>): CompanionEngine {
        val decoder = FrameDecoder()
        val engine = CompanionEngine(CompanionConfig(
            serverName = "spike", serverVersion = "1",
            pairings = mapOf(katPid to katToken),
            supportedCapabilities = setOf("theme"),
            // The app's REAL advertisement — the whole point of running this
            // in :app. table is advertised here or the spike does not ride.
            surfaceProfiles = NodeSupport.surfaceProfiles(),
            limits = appLimits(), nonceSource = { katSn })) { bytes ->
            decoder.feed(bytes) { out.add(it) }
        }
        engine.feed(encodeFrame(request("h1", "session.hello",
            EbpAuth.helloParams("spike", "1", katPid, katCn, emptyList())).toString()))
        engine.feed(encodeFrame(request("h2", "auth.response",
            EbpAuth.authParams(katPid, katCn, katSn, katToken)).toString()))
        engine.feed(encodeFrame(request("r1", "session.ready", JsonObject(emptyMap())).toString()))
        return engine
    }

    // ------------------------------------------------------- synthetic rows

    /** Deterministic filler sized to hit the elisp-measured byte shape. */
    private fun filler(seed: Int, len: Int): String {
        val alphabet = "abcdefghijklmnopqrstuvwxyz-"
        val sb = StringBuilder(len)
        var x = seed * 2654435761.toInt() + 1
        repeat(len) { sb.append(alphabet[((x ushr 16) and 0x7fff) % alphabet.length]); x = x * 1103515245 + 12345 }
        return sb.toString()
    }

    private fun cell(text: String): JsonObject = buildJsonObject {
        putJsonArray("spans") { add(buildJsonObject { put("text", text) }) }
    }

    /** One synthetic note as a table data row with [cols] cells.
     * Column 0 is a UUID-shaped id (36 chars, like the real vault's), the
     * rest are filler split so the row's serialized weight matches the
     * measured mean (minimal ~179 B, full ~524 B). */
    private fun dataRow(i: Int, cols: Int): JsonObject = buildJsonObject {
        put("kind", "data")
        putJsonArray("cells") {
            add(cell("%08x-spike-4000-8000-%012x".format(i, i.toLong())))
            if (cols > 1) {
                val budget = if (cols == MINIMAL_COLS) 60 else 300
                val per = budget / (cols - 1)
                repeat(cols - 1) { c -> add(cell(filler(i * 31 + c, per))) }
            }
        }
    }

    private fun tableSpec(rows: Int, cols: Int, startAt: Int = 0): JsonObject =
        buildJsonObject {
            put("t", "table")
            putJsonArray("rows") {
                repeat(rows) { r -> add(dataRow(startAt + r, cols)) }
            }
        }

    private fun update(id: String, surface: String, rev: Long, spec: JsonObject): String =
        buildJsonObject {
            put("jsonrpc", "2.0"); put("id", id)
            put("method", "surface.update")
            put("params", buildJsonObject {
                put("surface", surface); put("revision", rev); put("spec", spec)
            })
        }.toString()

    private fun reply(out: List<JsonObject>, id: String): JsonObject =
        out.last { (it["id"] as? JsonPrimitive)?.content == id }

    private fun status(out: List<JsonObject>, id: String): String {
        val r = reply(out, id)
        (r["result"] as? JsonObject)?.let {
            return (it["status"] as? JsonPrimitive)?.content ?: "?"
        }
        val err = r["error"] as? JsonObject ?: return "?"
        val code = (err["code"] as? JsonPrimitive)?.content
        val reason = ((err["data"] as? JsonObject)?.get("reason") as? JsonPrimitive)?.content
        return "error:$code:${reason ?: "-"}"
    }

    // ------------------------------------------------------------ questions

    @Test
    fun q1MinimalVaultRidesOneUpdate() {
        val out = mutableListOf<JsonObject>()
        val e = engine(out)
        val spec = tableSpec(NOTES, MINIMAL_COLS)
        val raw = update("q1", "app:vault", 1, spec)
        val bytes = raw.toByteArray(Charsets.UTF_8).size
        val t0 = System.nanoTime()
        e.feed(encodeFrame(raw))
        val ms = (System.nanoTime() - t0) / 1e6
        println("SPIKE q1 minimal ${NOTES}x$MINIMAL_COLS cells=${NOTES * MINIMAL_COLS} " +
            "bytes=$bytes status=${status(out, "q1")} accept_ms=%.1f".format(ms))
        assertEquals("applied", status(out, "q1"))
    }

    @Test
    fun q1FullVaultIsRejectedInOneUpdate() {
        val out = mutableListOf<JsonObject>()
        val e = engine(out)
        val spec = tableSpec(NOTES, FULL_COLS)
        val raw = update("q1f", "app:vault", 1, spec)
        val bytes = raw.toByteArray(Charsets.UTF_8).size
        e.feed(encodeFrame(raw))
        val s = status(out, "q1f")
        println("SPIKE q1 full ${NOTES}x$FULL_COLS cells=${NOTES * FULL_COLS} " +
            "bytes=$bytes status=$s")
        assertTrue("the 16-col vault must exceed the aggregate cell cap: $s",
            s.startsWith("error:1201"))
    }

    @Test
    fun q2BoundaryIsExactlyTheCap() {
        val out = mutableListOf<JsonObject>()
        val e = engine(out)
        // 4096 cells exactly: 512 rows x 8 cols.
        e.feed(encodeFrame(update("at", "app:b1", 1, tableSpec(512, 8))))
        val atCap = status(out, "at")
        // 4097 cells: same plus one single-cell row.
        val over = buildJsonObject {
            put("t", "table")
            putJsonArray("rows") {
                repeat(512) { r -> add(dataRow(r, 8)) }
                add(dataRow(999, 1))
            }
        }
        e.feed(encodeFrame(update("over", "app:b2", 1, over)))
        val overCap = status(out, "over")
        println("SPIKE q2 boundary cap=$CELL_CAP at-cap=$atCap over-cap=$overCap")
        assertEquals("applied", atCap)
        assertTrue(overCap.startsWith("error:1201"))
    }

    @Test
    fun q3q4FullVaultChunksAndCosts() {
        val out = mutableListOf<JsonObject>()
        val e = engine(out)
        val rowsPerChunk = (CELL_CAP / FULL_COLS).toInt()   // 256
        val chunks = (NOTES + rowsPerChunk - 1) / rowsPerChunk
        var total = 0.0
        var totalBytes = 0
        var start = 0
        var n = 0
        while (start < NOTES) {
            val rows = minOf(rowsPerChunk, NOTES - start)
            val raw = update("c$n", "app:vault-$n", 1, tableSpec(rows, FULL_COLS, start))
            totalBytes += raw.toByteArray(Charsets.UTF_8).size
            val t0 = System.nanoTime()
            e.feed(encodeFrame(raw))
            val ms = (System.nanoTime() - t0) / 1e6
            total += ms
            assertEquals("chunk $n applied", "applied", status(out, "c$n"))
            println("SPIKE q3 chunk=$n rows=$rows accept_ms=%.1f".format(ms))
            start += rows; n++
        }
        println("SPIKE q4 full-vault chunked chunks=$chunks rowsPerChunk=$rowsPerChunk " +
            "totalBytes=$totalBytes total_accept_ms=%.1f".format(total))
        assertEquals(chunks, n)
    }

    @Test
    fun q5ApplyRowsReadsBackWithFullFidelity() {
        val out = mutableListOf<JsonObject>()
        val e = engine(out)
        e.feed(encodeFrame(update("a1", "app:vault", 1, tableSpec(NOTES, MINIMAL_COLS))))
        assertEquals("applied", status(out, "a1"))
        // The consumer motion: stored spec -> flat rows of first-cell texts.
        val t0 = System.nanoTime()
        val spec = e.surfaces.spec("app:vault")!!
        val rows = spec.jsonObject["rows"]!!.jsonArray
        val ids = rows.mapNotNull { row ->
            val cells = (row as JsonObject)["cells"]?.jsonArray ?: return@mapNotNull null
            ((cells[0] as JsonObject)["spans"]!!.jsonArray[0] as JsonObject)["text"]!!
                .jsonPrimitive.content
        }
        val ms = (System.nanoTime() - t0) / 1e6
        println("SPIKE q5 apply-rows extracted=${ids.size} extract_ms=%.2f".format(ms))
        assertEquals(NOTES, ids.size)
        assertEquals(NOTES, ids.toSet().size) // ids unique — nothing collapsed
    }
}
