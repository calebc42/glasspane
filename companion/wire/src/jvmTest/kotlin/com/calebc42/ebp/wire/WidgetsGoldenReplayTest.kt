// SPDX-License-Identifier: GPL-3.0-or-later
// W9 conformance: the contract's widget corpus replays through SpecValidator.
// goldens/widgets.golden is the per-widget conformance floor (validate.py
// enforces every node type has a line) — every line MUST validate, which
// guards the deep 17.x rules against over-strictness exactly where the
// contract pins the vocabulary. Mirrors validate.py's dispatch: a top-level
// action/builtin line is an ActionDescriptor, anything else is a node.
package com.calebc42.ebp.wire

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class WidgetsGoldenReplayTest {

    // The contract repo location comes from the ebp.dir system property
    // (set on the jvmTest task) — no cwd-dependent upward walk.
    private fun goldensDir(): File =
        File(System.getProperty("ebp.dir")
            ?: error("ebp.dir system property not set")).resolve("goldens")

    private fun goldenLines(name: String): List<Pair<String, String>> =
        File(goldensDir(), name).readLines()
            .filter { it.isNotBlank() }
            .map { line ->
                val idx = line.substringBefore(' ')
                idx to line.substringAfter(' ')
            }

    /** An action line validates inside a document that supplies a stateful
     * node for every captured field (capture resolution is document-wide). */
    private fun wrapAction(action: JsonObject): JsonObject = buildJsonObject {
        put("t", "column")
        putJsonArray("children") {
            action.arrOrNull("capture_fields")?.forEach { cf ->
                addJsonObject { put("t", "text_input"); put("id", cf.asStringOrNull()!!) }
            }
            addJsonObject { put("t", "button"); put("label", "x"); put("on_tap", action) }
        }
    }

    @Test
    fun everyWidgetsGoldenLineValidates() {
        val lines = goldenLines("widgets.golden")
        assertTrue("expected the full corpus, got ${lines.size}", lines.size >= 72)
        for ((idx, json) in lines) {
            val obj = Json.parseToJsonElement(json) as JsonObject
            val doc = if ("action" in obj || "builtin" in obj) wrapAction(obj) else obj
            try {
                SpecValidator.validateSurfaceSpec(doc, "widgets:$idx")
            } catch (e: ContentInvalid) {
                fail("widgets.golden line $idx rejected: ${e.reason} at ${e.path}")
            }
        }
    }

    @Test
    fun everyHypertextGoldenLineValidates() {
        for ((idx, json) in goldenLines("hypertext.golden")) {
            val doc = buildJsonObject {
                put("t", "column")
                put("children", Json.parseToJsonElement(json) as JsonArray)
            }
            try {
                SpecValidator.validateSurfaceSpec(doc, "hypertext:$idx")
            } catch (e: ContentInvalid) {
                fail("hypertext.golden line $idx rejected: ${e.reason} at ${e.path}")
            }
        }
    }
}
