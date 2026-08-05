// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 19.1 conformance: goldens/editor.golden replays through EditorSession
// on BOTH apply paths. Positions and lengths count Unicode scalar values;
// the Kotlin String is UTF-16, so these cases fail loudly if any boundary
// slips back to code-unit or grapheme indexing (LD-4's mixup) — pinned at
// the contract level instead of only in this module's own unit tests. The
// corpus is shared verbatim with validate.py's reference reducer and the
// ERT suite's mirror replay.
package com.calebc42.ebp.wire

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EditorGoldenReplayTest {

    // The contract repo location comes from the ebp.dir system property
    // (set on the jvmTest task) — no cwd-dependent upward walk.
    private fun goldensDir(): File =
        File(System.getProperty("ebp.dir")
            ?: error("ebp.dir system property not set")).resolve("goldens")

    private fun goldenLines(name: String): List<Pair<String, String>> =
        File(goldensDir(), name).readLines()
            .filter { it.isNotBlank() }
            .map { it.substringBefore(' ') to it.substringAfter(' ') }

    private fun session(text: String) =
        EditorSession("doc:golden", "body", "00112233445566778899aabbccddeeff")
            .apply { shadow = text }

    @Test
    fun everyEditorGoldenCaseReplaysOnBothApplyPaths() {
        val lines = goldenLines("editor.golden")
        assertTrue("expected the splice corpus, got ${lines.size}", lines.size >= 9)
        for ((idx, json) in lines) {
            val case = Json.parseToJsonElement(json) as JsonObject
            val seed = case["text"]!!.jsonPrimitive.content
            val local = session(seed)
            val remote = session(seed)
            for ((i, el) in case["ops"]!!.jsonArray.withIndex()) {
                val op = el.jsonObject
                val start = op["start"]!!.jsonPrimitive.int
                val del = op["del"]!!.jsonPrimitive.int
                val text = op["text"]!!.jsonPrimitive.content
                val len = op["len"]!!.jsonPrimitive.int
                val applies = op["applies"]!!.jsonPrimitive.boolean
                assertEquals("editor.golden $idx op $i (local splice)",
                    applies, local.splice(ScalarPos(start), del, text, len))
                // The inbound edit.apply path: the peer dictates the caret;
                // follow-the-insertion is always a valid dictation for an
                // accepted splice (start <= old - del, so start + inserted
                // <= len). A refused splice never reaches the caret gate.
                val caret = ScalarPos(start + text.codePointCount(0, text.length))
                assertEquals("editor.golden $idx op $i (remote apply)",
                    applies,
                    remote.spliceRemote(ScalarPos(start), del, text, len,
                        caret, null, null))
            }
            val final = case["final"]!!.jsonPrimitive.content
            assertEquals("editor.golden $idx final (local)", final, local.shadow)
            assertEquals("editor.golden $idx final (remote)", final, remote.shadow)
            assertEquals("editor.golden $idx scalar length",
                case["scalars"]!!.jsonPrimitive.int, local.scalarLength())
        }
    }
}
