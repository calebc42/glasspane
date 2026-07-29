// SPDX-License-Identifier: GPL-3.0-or-later
// W9 conformance: the contract's widget corpus replays through SpecValidator.
// goldens/widgets.golden is the per-widget conformance floor (validate.py
// enforces every node type has a line) — every line MUST validate, which
// guards the deep 17.x rules against over-strictness exactly where the
// contract pins the vocabulary. Mirrors validate.py's dispatch: a top-level
// action/builtin line is an ActionDescriptor, anything else is a node.
package com.calebc42.ebp.wire

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class WidgetsGoldenReplayTest {

    // The contract repo rides as the ebp/ submodule at the repo root; tests
    // run from companion/wire, so resolve upward.
    private fun goldensDir(): File {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val g = File(dir, "ebp/goldens")
            if (File(g, "widgets.golden").isFile) return g
            dir = dir.parentFile
        }
        fail("ebp/goldens not found above ${System.getProperty("user.dir")}")
        throw IllegalStateException()
    }

    private fun goldenLines(name: String): List<Pair<String, String>> =
        File(goldensDir(), name).readLines()
            .filter { it.isNotBlank() }
            .map { line ->
                val idx = line.substringBefore(' ')
                idx to line.substringAfter(' ')
            }

    /** An action line validates inside a document that supplies a stateful
     * node for every captured field (capture resolution is document-wide). */
    private fun wrapAction(action: JSONObject): JSONObject {
        val children = JSONArray()
        action.optJSONArray("capture_fields")?.let { cf ->
            for (i in 0 until cf.length())
                children.put(JSONObject().put("t", "text_input")
                    .put("id", cf.getString(i)))
        }
        children.put(JSONObject().put("t", "button").put("label", "x")
            .put("on_tap", action))
        return JSONObject().put("t", "column").put("children", children)
    }

    @Test
    fun everyWidgetsGoldenLineValidates() {
        val lines = goldenLines("widgets.golden")
        assertTrue("expected the full corpus, got ${lines.size}", lines.size >= 72)
        for ((idx, json) in lines) {
            val obj = JSONObject(json)
            val doc = if (obj.has("action") || obj.has("builtin")) wrapAction(obj) else obj
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
            val doc = JSONObject().put("t", "column").put("children", JSONArray(json))
            try {
                SpecValidator.validateSurfaceSpec(doc, "hypertext:$idx")
            } catch (e: ContentInvalid) {
                fail("hypertext.golden line $idx rejected: ${e.reason} at ${e.path}")
            }
        }
    }
}
