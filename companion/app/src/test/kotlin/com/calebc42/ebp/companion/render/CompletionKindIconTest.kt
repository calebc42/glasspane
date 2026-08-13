// SPDX-License-Identifier: GPL-3.0-or-later
// Amendment #169 (R3): the candidate `kind` icon map. Every mapped name must
// resolve a REAL material icon (IconMap is reflective, so a typo silently
// draws the HelpOutline placeholder — the exact decoration the unrecognized-
// value degrade forbids), and anything outside the map — the vocabulary's
// unmapped names, future names, null — decorates nothing.
package com.calebc42.ebp.companion.render

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.HelpOutline
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class CompletionKindIconTest {
    /** The vocabulary comes from the CONTRACT, not a frozen copy (the R3
     * review: a hardcoded list never visits a future enum addition, so a
     * typo'd icon arm would fall to the placeholder on device unasserted).
     * Same repo-root walk NodeSupportPinTest uses for source files. */
    private val vocabulary: List<String> by lazy {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        var contract: File? = null
        while (dir != null && contract == null) {
            for (candidate in listOf(File(dir, "ebp/contract.json"),
                File(dir.parentFile ?: dir, "ebp/contract.json"))) {
                if (candidate.isFile) { contract = candidate; break }
            }
            dir = dir.parentFile
        }
        val root = Json.parseToJsonElement(
            (contract ?: error("ebp/contract.json not found")).readText())
        root.jsonObject["candidate_schema"]!!.jsonObject["kind_enum"]!!
            .jsonArray.map { it.jsonPrimitive.content }
    }

    @Test
    fun mappedKindsResolveRealIcons() {
        assertTrue("contract vocabulary loads", vocabulary.size >= 25)
        for (kind in vocabulary) {
            val name = completionKindIcon(kind) ?: continue
            assertNotEquals("kind `$kind` -> `$name` fell to the placeholder",
                Icons.Outlined.HelpOutline, IconMap.get(name))
        }
    }

    @Test
    fun unknownAndAbsentKindsDecorateNothing() {
        assertNull(completionKindIcon("kind-from-the-future"))
        assertNull(completionKindIcon(null))
        // `unit` is registered vocabulary the map leaves undecorated — the
        // conforming degrade covers recognized-but-unmapped too.
        assertNull(completionKindIcon("unit"))
    }
}
