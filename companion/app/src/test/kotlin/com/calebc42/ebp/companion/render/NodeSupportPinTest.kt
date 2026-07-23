// SPDX-License-Identifier: GPL-3.0-or-later
// Pins the renderer's `when (type)` dispatch to NodeSupport.APP_NODE_TYPES —
// which is also what DeviceBridge advertises (surface_profiles is BUILT from
// NodeSupport), so: dispatch == advertised ⊆ contract. A renderer case added
// without advertising fails here; advertising without a case fails here;
// advertising outside the contract vocabulary fails here. Ported from
// poc-v1's SduiRendererNodeTypesTest source-scan walker (a `when`'s string
// labels are not introspectable at runtime; only the shallowest case indent
// inside the dispatch `when` is collected, so nested `when`s for
// style/variant sit deeper and are ignored).
package com.calebc42.ebp.companion.render

import com.calebc42.ebp.wire.CORE_NODE_SET
import com.calebc42.ebp.wire.NODE_SCHEMA
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NodeSupportPinTest {

    private val relPath =
        "src/main/kotlin/com/calebc42/ebp/companion/render/Renderer.kt"

    private fun rendererSource(): String {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null) {
            for (candidate in listOf(File(dir, relPath), File(dir, "app/$relPath"),
                File(dir, "companion/app/$relPath"))) {
                if (candidate.isFile) return candidate.readText()
            }
            dir = dir.parentFile
        }
        error("Renderer.kt not found from ${System.getProperty("user.dir")}")
    }

    private fun dispatchTypes(src: String): Set<String> {
        val lines = src.lines()
        // The literal `when (type) {` — the opening brace keeps a prose
        // mention in a comment from matching.
        val start = lines.indexOfFirst { it.contains("when (type) {") }
        require(start >= 0) { "dispatch `when (type) {` not found" }
        val label = Regex("""^(\s+)"[a-z_]+"(\s*,\s*"[a-z_]+")*\s*->""")
        val quoted = Regex(""""([a-z_]+)"""")
        val types = sortedSetOf<String>()
        var depth = 0
        var started = false
        var caseIndent = -1
        for (i in start until lines.size) {
            val line = lines[i]
            depth += line.count { it == '{' } - line.count { it == '}' }
            if (!started) {
                if (depth >= 1) started = true
                continue
            }
            label.find(line)?.let { m ->
                val indent = m.groupValues[1].length
                if (caseIndent < 0) caseIndent = indent
                if (indent == caseIndent) {
                    quoted.findAll(line.substringBefore("->"))
                        .forEach { types += it.groupValues[1] }
                }
            }
            if (depth <= 0) break
        }
        return types
    }

    @Test
    fun dispatchMatchesAdvertisedAppNodeTypes() {
        assertEquals(NodeSupport.APP_NODE_TYPES.toSortedSet(),
            dispatchTypes(rendererSource()))
    }

    @Test
    fun everyAdvertisedTypeIsInTheContract() {
        for (set in listOf(NodeSupport.APP_NODE_TYPES, NodeSupport.DIALOG_NODE_TYPES,
            NodeSupport.NOTIFICATION_NODE_TYPES)) {
            val unknown = set - NODE_SCHEMA.keys
            assertTrue("advertised outside the contract: $unknown", unknown.isEmpty())
        }
    }

    @Test
    fun coreNodeSetIsAlwaysAdvertised() {
        // SPEC 10.2/16.2: the app and dialog profiles carry the Core Node Set.
        assertTrue((CORE_NODE_SET - NodeSupport.APP_NODE_TYPES).isEmpty())
        assertTrue((CORE_NODE_SET - NodeSupport.DIALOG_NODE_TYPES).isEmpty())
    }

    @Test
    fun requiredBuiltinsAreAdvertised() {
        // SPEC 10.2: app carries view.switch + companion.settings.open;
        // dialog carries dialog.submit + dialog.dismiss.
        assertTrue(NodeSupport.APP_BUILTINS.containsAll(
            setOf("view.switch", "companion.settings.open")))
        assertTrue(NodeSupport.DIALOG_BUILTINS.containsAll(
            setOf("dialog.submit", "dialog.dismiss")))
    }

    @Test
    fun imageRequiresAFormFeature() {
        // SPEC 17.2: advertising `image` requires image.https or image.data in
        // the SAME profile's features.
        for ((nodes, features) in listOf(
            NodeSupport.APP_NODE_TYPES to NodeSupport.APP_FEATURES,
            NodeSupport.DIALOG_NODE_TYPES to NodeSupport.DIALOG_FEATURES,
            NodeSupport.NOTIFICATION_NODE_TYPES to NodeSupport.NOTIFICATION_FEATURES)) {
            if ("image" in nodes)
                assertTrue("image advertised without a form feature",
                    "image.https" in features || "image.data" in features)
        }
    }

    @Test
    fun pureHelpersClampNotThrow() {
        // The render-never-throws philosophy: bad numbers skip, not crash.
        assertEquals(null, safeDp(-1.0))
        assertEquals(null, safeDp(Double.NaN))
        assertEquals(12f, safeDp(12.0))
        assertEquals(null, safeFraction(1.5))
        assertEquals(0.5f, safeFraction(0.5))
        assertEquals(null, safeAspect(0.0))
        assertEquals(null, safeAlpha(1.01))
    }

    @Test
    fun hexColorForms() {
        // §16.6: #rgb / #rgba / #rrggbb / #rrggbbaa, case-insensitive.
        assertEquals(0xFFFF0000L, parseHexColor("#f00"))
        assertEquals(0xFFFF0000L, parseHexColor("#FF0000"))
        assertEquals(0x80FF0000L, parseHexColor("#ff000080"))
        assertEquals(0xFF00FF00L.let { it }, parseHexColor("#0f0"))
        assertEquals(null, parseHexColor("#12345"))
        assertEquals(null, parseHexColor("primary"))
        assertEquals(null, parseHexColor("#gg0000"))
        // #rgba: alpha nibble widened, alpha in the high byte.
        assertEquals(0x88FF0000L, parseHexColor("#f008"))
    }

    @Test
    fun lazyKeysAreStableAndUnique() {
        val children = org.json.JSONArray("""[
            {"t":"text","key":"a"},
            {"t":"text_input","id":"field"},
            {"t":"text"},
            {"t":"text","key":"a"}
        ]""")
        val keys = lazyChildKeys(children)
        assertEquals(listOf("k:a", "id:field", "i:2", "k:a#1"), keys)
        assertEquals(keys.size, keys.toSet().size)
    }

    @Test
    fun identityPathPrefersKeyThenIdThenTreePath() {
        val n = org.json.JSONObject("""{"t":"text","key":"k","id":"i"}""")
        assertEquals("/k:k", identityPath("", n, 3))
        assertEquals("/id:i", identityPath("",
            org.json.JSONObject("""{"t":"text","id":"i"}"""), 3))
        assertEquals("/3:text", identityPath("",
            org.json.JSONObject("""{"t":"text"}"""), 3))
    }
}
