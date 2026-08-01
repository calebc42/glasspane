// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 4.3/4.1 (LD-20): equality has a type-tag gate and never delegates
// the terminal case to the host language. Three of the twelve call sites
// are validator MUST-rejects and three decide whether a user's draft is
// silently erased, so an asymmetric clause is user-visible data loss.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JsonEqualityTest {

    @Test
    fun absentAndJsonNullAreDistinctBothDirections() {
        // Kotlin null = ABSENT, JsonNull = JSON null (module convention).
        // org.json's NULL.equals(null) was true, so the old else-clause held
        // this in exactly one direction; the swap made it symmetric.
        assertFalse(jsonValueEquals(JsonNull, null))
        assertFalse(jsonValueEquals(null, JsonNull))
        assertTrue(jsonValueEquals(null, null))
        assertTrue(jsonValueEquals(JsonNull, JsonNull))
    }

    @Test
    fun numbersCompareByBinary64Value() {
        // 1 and 1.0 are DIFFERENTLY SPELLED primitives now (kotlinx keeps the
        // literal), so these compare by value only if the LD-20 number arm
        // does its job — the pin has more teeth post-swap, not fewer.
        assertTrue(jsonValueEquals(JsonPrimitive(1), JsonPrimitive(1.0)))
        assertTrue(jsonValueEquals(JsonPrimitive(1L), JsonPrimitive(1)))
        assertFalse(jsonValueEquals(JsonPrimitive(1), JsonPrimitive(2)))
        // The boundary parser refuses anything past 2^53-1, so toDouble()
        // is exact for every integer that can reach this function.
        assertTrue(jsonValueEquals(
            JsonPrimitive(9_007_199_254_740_991L), JsonPrimitive(9.007199254740991E15)))
    }

    @Test
    fun crossTypeIsNeverEqual() {
        assertFalse(jsonValueEquals(JsonPrimitive("1"), JsonPrimitive(1)))
        assertFalse(jsonValueEquals(JsonPrimitive(true), JsonPrimitive(1)))
        assertFalse(jsonValueEquals(JsonPrimitive(false), JsonNull))
        assertFalse(jsonValueEquals(JsonPrimitive(""), JsonNull))
        assertFalse(jsonValueEquals(JsonObject(emptyMap()), JsonArray(emptyList())))
    }

    @Test
    fun structuralRulesHold() {
        assertTrue(jsonValueEquals(
            Json.parseToJsonElement("""{"a":1,"b":[1,2]}"""),
            Json.parseToJsonElement("""{"b":[1,2],"a":1.0}""")))
        assertFalse(jsonValueEquals(
            Json.parseToJsonElement("[1,2]"),
            Json.parseToJsonElement("[2,1]"))) // arrays ordered
        assertFalse(jsonValueEquals(
            Json.parseToJsonElement("""{"a":null}"""),
            Json.parseToJsonElement("""{}""")))
    }
}
