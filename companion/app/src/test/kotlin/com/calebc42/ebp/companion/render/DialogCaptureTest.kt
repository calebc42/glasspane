// SPDX-License-Identifier: GPL-3.0-or-later
// T3/LD-3: dialog capture resolves the user's edit over the authored default,
// and distinguishes "the user cleared this" from "the user never touched it".
package com.calebc42.ebp.companion.render

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DialogCaptureTest {

    private fun defaults(build: JsonObjectBuilder.() -> Unit) = buildJsonObject(build)

    // C6: every expected value is wrapped in JsonPrimitive. captureValue
    // returns a JsonElement?, so a bare `true`/`3`/`"Untitled"` would resolve
    // to assertEquals(Object, Object), compile, and never match — the app's
    // analogue of the L-suffix rule.

    @Test
    fun anUntouchedFieldCapturesItsAuthoredLogicalValue() {
        // The LD-3 repro: a checkbox authored `checked: true` and never
        // touched. With no defaults layer the capture substituted "", so the
        // STRING "" went on the wire where §14.1 requires boolean `true` —
        // the wrong JSON type for the commonest dialog shape there is.
        val d = defaults {
            put("agree", true)
            put("name", "Untitled")
            put("count", 3)
        }
        assertEquals(JsonPrimitive(true), captureValue("agree", emptyMap(), d))
        assertEquals(JsonPrimitive("Untitled"), captureValue("name", emptyMap(), d))
        assertEquals(JsonPrimitive(3), captureValue("count", emptyMap(), d))
    }

    @Test
    fun aDeliberatelyClearedFieldIsNotTreatedAsAbsent() {
        // The reason the lookup is a containment test and not an elvis: a
        // user who cleared a field holds "", false, or 0, and `?:` would fall
        // through to the authored default and silently restore a value the
        // user removed.
        val d = defaults {
            put("agree", true)
            put("name", "Untitled")
            put("count", 3)
        }
        assertEquals(JsonPrimitive(false),
            captureValue("agree", mapOf("agree" to JsonPrimitive(false)), d))
        assertEquals(JsonPrimitive(""),
            captureValue("name", mapOf("name" to JsonPrimitive("")), d))
        assertEquals(JsonPrimitive(0),
            captureValue("count", mapOf("count" to JsonPrimitive(0)), d))
    }

    @Test
    fun theUserLayerWinsAndTypesAreNotCoerced() {
        val d = defaults { put("name", "Untitled"); put("agree", false) }
        assertEquals(JsonPrimitive("typed"),
            captureValue("name", mapOf("name" to JsonPrimitive("typed")), d))
        assertEquals(JsonPrimitive(true),
            captureValue("agree", mapOf("agree" to JsonPrimitive(true)), d))
        // A multi-select value stays an array, not a stringified one.
        val arr = JsonArray(listOf("a", "b").map(::JsonPrimitive))
        assertTrue(captureValue("tags", mapOf("tags" to arr), d) is JsonArray)
    }

    @Test
    fun aNullDefaultAndAnUnknownFieldBothResolveToNull() {
        // JSON null in the defaults layer means "no authored value" (an
        // enum_list with no selection); an id in neither layer means the spec
        // and the field map disagree. Neither invents a value.
        val d = defaults { put("choice", JsonNull) }
        assertNull(captureValue("choice", emptyMap(), d))
        assertNull(captureValue("nope", emptyMap(), d))
        assertNull(captureValue("anything", emptyMap(), null))
    }
}
