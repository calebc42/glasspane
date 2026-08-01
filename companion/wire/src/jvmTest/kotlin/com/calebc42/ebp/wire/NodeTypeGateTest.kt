// SPDX-License-Identifier: GPL-3.0-or-later
// RB-3 SPEC 17.1/16.2: a known contract type absent from the TARGET profile's
// advertised node_types is treated as unsupported — it degrades (its subtree is
// scanned, but its per-type schema is not applied and it registers no stateful
// draft), instead of validating strictly or dispatching.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NodeTypeGateTest {

    // A dialog-like profile: text/row/column/text_input, but NOT chart/editor.
    private val dialogTypes = setOf("text", "row", "column", "box", "text_input")

    @Test
    fun advertisedTypesValidateStrictlyAndRegisterStatefuls() {
        val spec = buildJsonObject {
            put("t", "column")
            putJsonArray("children") {
                add(buildJsonObject { put("t", "text_input"); put("id", "name") })
            }
        }
        val statefuls = SpecValidator.validateSurfaceSpec(
            spec, advertisedTypes = dialogTypes)
        assertTrue("name" in statefuls) // an advertised input registers
    }

    @Test
    fun unadvertisedKnownTypeDegradesInsteadOfRejecting() {
        // A `chart` is a real contract type but not advertised to the dialog.
        // It MUST NOT throw (degrade), and its per-type schema (series required)
        // is NOT enforced — an otherwise-invalid chart passes because it degrades.
        val spec = buildJsonObject {
            put("t", "column")
            putJsonArray("children") {
                add(buildJsonObject { put("t", "chart") }) // no `series` — would be 1201 if validated
            }
        }
        // No exception:
        SpecValidator.validateSurfaceSpec(spec, advertisedTypes = dialogTypes)
    }

    @Test
    fun unadvertisedStatefulTypeDoesNotRegisterADraft() {
        // An `editor` (a stateful type) not advertised to the dialog must not
        // register as stateful, so no state.changed address exists for it.
        val spec = buildJsonObject {
            put("t", "column")
            putJsonArray("children") {
                add(buildJsonObject {
                    put("t", "editor"); put("id", "ed"); put("publish_state", true)
                })
            }
        }
        val statefuls = SpecValidator.validateSurfaceSpec(spec, advertisedTypes = dialogTypes)
        assertFalse("ed" in statefuls)
    }

    @Test
    fun nestedAdvertisedNodesInsideAnUnadvertisedParentStillValidate() {
        // The degrade scans the subtree: a text_input nested in an unadvertised
        // chart still registers (it renders as the neutral fallback content).
        val spec = buildJsonObject {
            put("t", "column")
            putJsonArray("children") {
                add(buildJsonObject {
                    put("t", "chart")
                    putJsonArray("children") {
                        add(buildJsonObject { put("t", "text_input"); put("id", "inner") })
                    }
                })
            }
        }
        val statefuls = SpecValidator.validateSurfaceSpec(spec, advertisedTypes = dialogTypes)
        assertTrue("inner" in statefuls)
    }

    @Test
    fun nullAdvertisedTypesAllowsEverything() {
        // The default (unit tests / golden corpus) gates nothing.
        val spec = buildJsonObject {
            put("t", "chart")
            put("series", JsonArray(emptyList()))
        }
        SpecValidator.validateSurfaceSpec(spec, advertisedTypes = null)
    }
}
