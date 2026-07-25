// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 4.3/4.1 (LD-20): equality has a type-tag gate and never delegates
// the terminal case to the host language. Three of the twelve call sites
// are validator MUST-rejects and three decide whether a user's draft is
// silently erased, so an asymmetric clause is user-visible data loss.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JsonEqualityTest {

    @Test
    fun absentAndJsonNullAreDistinctBothDirections() {
        // org.json: NULL.equals(null) is true, so the old else-clause made
        // this hold in exactly one direction (Kotlin == dispatches left).
        assertFalse(jsonValueEquals(JSONObject.NULL, null))
        assertFalse(jsonValueEquals(null, JSONObject.NULL))
        assertTrue(jsonValueEquals(null, null))
        assertTrue(jsonValueEquals(JSONObject.NULL, JSONObject.NULL))
    }

    @Test
    fun numbersCompareByBinary64Value() {
        assertTrue(jsonValueEquals(1, 1.0))
        assertTrue(jsonValueEquals(1L, 1))
        assertFalse(jsonValueEquals(1, 2))
        // The boundary parser refuses anything past 2^53-1, so toDouble()
        // is exact for every integer that can reach this function.
        assertTrue(jsonValueEquals(9_007_199_254_740_991L, 9.007199254740991E15))
    }

    @Test
    fun crossTypeIsNeverEqual() {
        assertFalse(jsonValueEquals("1", 1))
        assertFalse(jsonValueEquals(true, 1))
        assertFalse(jsonValueEquals(false, JSONObject.NULL))
        assertFalse(jsonValueEquals("", JSONObject.NULL))
        assertFalse(jsonValueEquals(JSONObject(), JSONArray()))
    }

    @Test
    fun structuralRulesHold() {
        assertTrue(jsonValueEquals(
            JSONObject("""{"a":1,"b":[1,2]}"""), JSONObject("""{"b":[1,2],"a":1.0}""")))
        assertFalse(jsonValueEquals(
            JSONArray("[1,2]"), JSONArray("[2,1]"))) // arrays ordered
        assertFalse(jsonValueEquals(
            JSONObject("""{"a":null}"""), JSONObject("""{}""")))
    }
}
