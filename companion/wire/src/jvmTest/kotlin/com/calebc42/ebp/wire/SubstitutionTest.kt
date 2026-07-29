// SPDX-License-Identifier: GPL-3.0-or-later
// W7 conformance: on_fire fire-time substitution (SPEC 21.4). Single-pass
// ${id}/${type}/${data.FIELD} over string VALUES only, JSON spelling for
// numbers/booleans, missing/null left literal, $${ -> literal ${, recursion
// through objects and arrays, and the referencesData install-time probe.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubstitutionTest {

    private fun sub(s: String, data: JSONObject = JSONObject()) =
        Substitution.apply(s, "low-batt", "battery.level", data) as String

    @Test
    fun tokensResolveAndSpell() {
        val data = JSONObject().put("level", 19).put("on", true).put("name", "AC")
        assertEquals("id low-batt", sub("id \${id}"))
        assertEquals("battery.level", sub("\${type}"))
        assertEquals("19%", sub("\${data.level}%", data))     // number JSON spelling
        assertEquals("true", sub("\${data.on}", data))        // boolean spelling
        assertEquals("AC", sub("\${data.name}", data))
    }

    @Test
    fun missingUnknownAndEscapeStayLiteral() {
        val data = JSONObject().put("x", JSONObject.NULL)
        assertEquals("\${data.gone}", sub("\${data.gone}", data)) // missing
        assertEquals("\${data.x}", sub("\${data.x}", data))       // null
        assertEquals("\${bogus}", sub("\${bogus}"))               // unknown token
        assertEquals("\${data.level}", sub("$\${data.level}"))    // $${ escape
        assertEquals("a \$ b", sub("a \$ b"))                     // lone dollar
    }

    @Test
    fun recursesValuesNotMemberNames() {
        val data = JSONObject().put("level", 5)
        val node = JSONObject()
            .put("notify", JSONObject().put("text", "Battery \${data.level}%"))
            .put("\${id}", "\${type}") // key must NOT be interpolated; value must
        val out = Substitution.apply(node, "low-batt", "battery.level", data) as JSONObject
        assertEquals("Battery 5%", out.getJSONObject("notify").getString("text"))
        assertTrue(out.has("\${id}"))                       // member name untouched
        assertEquals("battery.level", out.getString("\${id}"))
    }

    @Test
    fun recursesArraysAndLeavesScalars() {
        val arr = JSONArray().put("\${id}").put(200).put(true)
        val out = Substitution.apply(arr, "low-batt", "battery.level", JSONObject()) as JSONArray
        assertEquals("low-batt", out.getString(0))
        assertEquals(200, out.getInt(1)) // numbers pass through unchanged
        assertEquals(true, out.getBoolean(2))
    }

    @Test
    fun referencesDataDetectsLiveTokensOnly() {
        assertTrue(Substitution.referencesData(
            JSONObject().put("notify", JSONObject().put("text", "\${data.body}"))))
        assertFalse(Substitution.referencesData(
            JSONObject().put("notify", JSONObject().put("text", "\${id} \${type}"))))
        assertFalse(Substitution.referencesData(
            JSONObject().put("notify", JSONObject().put("text", "$\${data.body}")))) // escaped
        assertFalse(Substitution.referencesData(JSONObject().put("args",
            JSONObject().put("ms", 200))))
    }
}
