// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: on_fire fire-time substitution (SPEC 21.4). Single-pass
// ${id}/${type}/${data.FIELD} over string VALUES only, JSON spelling for
// numbers/booleans, missing/null left literal, $${ -> literal ${, recursion
// through objects and arrays, and the referencesData install-time probe.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubstitutionTest {

    private fun sub(s: String, data: JsonObject = JsonObject(emptyMap())) =
        Substitution.apply(JsonPrimitive(s), "low-batt", "battery.level", data)!!
            .asStringOrNull()!!

    @Test
    fun tokensResolveAndSpell() {
        val data = buildJsonObject {
            put("level", 19)
            put("on", true)
            put("name", "AC")
        }
        assertEquals("id low-batt", sub("id \${id}"))
        assertEquals("battery.level", sub("\${type}"))
        assertEquals("19%", sub("\${data.level}%", data))     // number JSON spelling
        assertEquals("true", sub("\${data.on}", data))        // boolean spelling
        assertEquals("AC", sub("\${data.name}", data))
    }

    @Test
    fun missingUnknownAndEscapeStayLiteral() {
        val data = buildJsonObject { put("x", JsonNull) }
        assertEquals("\${data.gone}", sub("\${data.gone}", data)) // missing
        assertEquals("\${data.x}", sub("\${data.x}", data))       // null
        assertEquals("\${bogus}", sub("\${bogus}"))               // unknown token
        assertEquals("\${data.level}", sub("$\${data.level}"))    // $${ escape
        assertEquals("a \$ b", sub("a \$ b"))                     // lone dollar
    }

    @Test
    fun recursesValuesNotMemberNames() {
        val data = buildJsonObject { put("level", 5) }
        val node = buildJsonObject {
            putJsonObject("notify") { put("text", "Battery \${data.level}%") }
            put("\${id}", "\${type}") // key must NOT be interpolated; value must
        }
        val out = Substitution.apply(node, "low-batt", "battery.level", data) as JsonObject
        assertEquals("Battery 5%", out.reqObj("notify").reqString("text"))
        assertTrue("\${id}" in out)                         // member name untouched
        assertEquals("battery.level", out.reqString("\${id}"))
    }

    @Test
    fun recursesArraysAndLeavesScalars() {
        val arr = buildJsonArray {
            add(JsonPrimitive("\${id}"))
            add(JsonPrimitive(200))
            add(JsonPrimitive(true))
        }
        val out = Substitution.apply(arr, "low-batt", "battery.level",
            JsonObject(emptyMap())) as JsonArray
        assertEquals("low-batt", out[0].asStringOrNull())
        assertEquals(JsonPrimitive(200), out[1]) // numbers pass through unchanged
        assertEquals(JsonPrimitive(true), out[2])
    }

    @Test
    fun referencesDataDetectsLiveTokensOnly() {
        assertTrue(Substitution.referencesData(buildJsonObject {
            putJsonObject("notify") { put("text", "\${data.body}") }
        }))
        assertFalse(Substitution.referencesData(buildJsonObject {
            putJsonObject("notify") { put("text", "\${id} \${type}") }
        }))
        assertFalse(Substitution.referencesData(buildJsonObject {
            putJsonObject("notify") { put("text", "$\${data.body}") } // escaped
        }))
        assertFalse(Substitution.referencesData(buildJsonObject {
            putJsonObject("args") { put("ms", 200) }
        }))
    }

    @Test
    fun integralDoubleSubstitutesWithoutDecimalPoint() {
        // P0 pre-swap pin (PLAN-rf2 §0.2 item 7). Trigger fire-data arrives
        // as JSON numbers and lands in user-visible notification text: a
        // battery level of 19 must read "19%", never "19.0%". Keep
        // Substitution.jsonNumber verbatim through the swap — kotlinx
        // preserves the literal spelling where org.json normalized it (a
        // built 2.0 now genuinely carries content "2.0" into apply), so
        // this is exactly where "2.0" would start leaking into a toast.
        assertEquals("2", sub("\${data.x}", buildJsonObject { put("x", 2.0) }))
        assertEquals("2", sub("\${data.x}", buildJsonObject { put("x", 2) }))
        assertEquals("2", sub("\${data.x}", buildJsonObject { put("x", 2L) }))
        // A genuinely fractional value keeps its point.
        assertEquals("2.5", sub("\${data.x}", buildJsonObject { put("x", 2.5) }))
        // Negative and zero integral doubles collapse the same way.
        assertEquals("-7", sub("\${data.x}", buildJsonObject { put("x", -7.0) }))
        assertEquals("0", sub("\${data.x}", buildJsonObject { put("x", 0.0) }))
    }

}
