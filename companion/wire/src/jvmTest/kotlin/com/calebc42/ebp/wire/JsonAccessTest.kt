// SPDX-License-Identifier: GPL-3.0-or-later
// RF-2b (B1): pins the translation layer's semantics BEFORE any call site moves
// onto it. Every assertion here is a decision the ~625 org.json sites will be
// migrated against; if one of them is wrong, it is cheaper to find out now than
// once CompanionEngine is half-converted.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class JsonAccessTest {

    private val o = buildJsonObject {
        put("s", "text")
        put("i", 42L)
        put("neg", -7L)
        put("d", 2.5)
        put("integralDouble", 2.0)
        put("b", true)
        put("numericString", "42")
        put("boolString", "true")
        put("nul", JsonNull)
        put("obj", buildJsonObject { put("k", "v") })
        put("arr", JsonArray(listOf(JsonPrimitive(1L))))
    }

    // --- the null convention: absent vs JSON null ---------------------------

    @Test fun absentMemberIsKotlinNull() = assertNull(o["missing"])

    @Test fun jsonNullIsPresentButNotAKotlinNull() = assertSame(JsonNull, o["nul"])

    @Test fun isNullOrAbsentIsTrueForBothLikeOrgJson() {
        assertTrue(o.isNullOrAbsent("nul"))
        assertTrue(o.isNullOrAbsent("missing"))
        assertFalse(o.isNullOrAbsent("s"))
    }

    // --- readers: no cross-type coercion ------------------------------------

    @Test fun stringReaderTakesStringsOnly() {
        assertEquals("text", o.stringOrNull("s"))
        assertNull(o.stringOrNull("i"))     // org.json's optString stringified it
        assertNull(o.stringOrNull("nul"))   // never the literal "null"
        assertNull(o.stringOrNull("missing"))
    }

    @Test fun intReaderTakesIntegerSpellingsOnly() {
        assertEquals(42L, o.wireIntOrNull("i"))
        assertEquals(-7L, o.wireIntOrNull("neg"))
        assertNull(o.wireIntOrNull("numericString"))     // org.json read "42" as 42
        assertNull(o.wireIntOrNull("d"))
        assertNull(o.wireIntOrNull("integralDouble"))    // normalize at accept time
        assertNull(o.wireIntOrNull("nul"))
    }

    @Test fun boolReaderTakesBooleansOnly() {
        assertTrue(o.boolOr("b"))
        assertFalse(o.boolOr("boolString", false))       // org.json coerced "true"
        assertFalse(o.boolOr("missing"))
        assertTrue(o.boolOr("nul", true))                // JSON null folds to the default
    }

    @Test fun defaultingReadersFoldExplicitNullIntoTheDefault() {
        assertEquals("d", o.stringOr("nul", "d"))
        assertEquals(9L, o.longOr("nul", 9L))
    }

    @Test fun throwingAccessorsThrowOnAbsentAndOnWrongType() {
        for (call in listOf<() -> Any>(
            { o.reqString("missing") }, { o.reqString("i") },
            { o.reqLong("missing") }, { o.reqLong("s") },
            { o.reqObj("arr") }, { o.reqArr("obj") },
        )) {
            try {
                call()
                throw AssertionError("expected NoSuchElementException")
            } catch (_: NoSuchElementException) {
                // the guarded dispatch arm turns this into an error reply
            }
        }
        assertEquals("text", o.reqString("s"))
        assertEquals(42L, o.reqLong("i"))
    }

    // --- persistent mutation ------------------------------------------------

    @Test fun withAndWithoutReturnNewObjectsAndLeaveTheOriginalAlone() {
        val added = o.with("fresh", JsonPrimitive(1L))
        assertEquals(JsonPrimitive(1L), added["fresh"])
        assertNull(o["fresh"])

        val removed = o.without("s")
        assertNull(removed["s"])
        assertEquals(JsonPrimitive("text"), o["s"])
    }

    @Test fun withReplacesInPlaceKeepingKeyOrder() {
        val replaced = o.with("s", JsonPrimitive("other"))
        assertEquals("other", replaced.stringOrNull("s"))
        assertEquals(o.keys.toList(), replaced.keys.toList())
    }

    // --- predicates ---------------------------------------------------------

    @Test fun isIntegralDiscriminatesIntegersFromBinary64() {
        assertTrue((o["i"] as JsonPrimitive).isIntegral)
        assertFalse((o["d"] as JsonPrimitive).isIntegral)
        assertFalse((o["integralDouble"] as JsonPrimitive).isIntegral)  // spelled 2.0
        assertFalse((o["numericString"] as JsonPrimitive).isIntegral)
        assertFalse(JsonNull.isIntegral)
    }

    @Test fun requestIdKeyNeverMatchesAStringIdToAnIntegerPendingId() {
        assertEquals(1L, requestIdKey(JsonPrimitive(1L)))
        assertNull(requestIdKey(JsonPrimitive("1")))   // the durable pump hangs on this
        assertNull(requestIdKey(JsonNull))
        assertNull(requestIdKey(null))
        assertNull(requestIdKey(JsonPrimitive(1.5)))
    }

    // --- EbpJson.toJsonElement: the wire projection -------------------------

    @Test fun projectionCarriesEverySpecValueKind() {
        val v = EbpJson.parse(
            """{"s":"x","i":9007199254740991,"d":2.5,"b":false,"n":null,"a":[1,2],"o":{"k":1}}"""
        )
        val e = EbpJson.toJsonElement(v) as JsonObject
        assertEquals("x", e.stringOrNull("s"))
        assertEquals(9_007_199_254_740_991L, e.wireIntOrNull("i"))
        assertEquals(2.5, (e["d"] as JsonPrimitive).content.toDouble(), 0.0)
        assertFalse(e.boolOr("b", true))
        assertSame(JsonNull, e["n"])
        assertEquals(2, e.reqArr("a").size)
        assertEquals(1L, e.reqObj("o").wireIntOrNull("k"))
    }

    @Test fun projectionKeepsSmallIntegersAsIntegersNotInts() {
        // toOrgJson narrowed small integers to Int for the response-id lookup;
        // the projection does not, and small integers stay integer-spelled.
        val e = EbpJson.toJsonElement(EbpJson.parse("""{"id":1}""")) as JsonObject
        assertEquals("1", (e["id"] as JsonPrimitive).content)
        assertEquals(1L, e.wireIntOrNull("id"))
    }

    @Test fun projectionKeepsIntegerAndBinary64Spellings() {
        val e = EbpJson.toJsonElement(EbpJson.parse("""{"i":2,"d":2.0}""")) as JsonObject
        assertTrue((e["i"] as JsonPrimitive).isIntegral)
        assertFalse((e["d"] as JsonPrimitive).isIntegral)
    }

    @Test fun projectionPreservesMemberOrder() {
        val e = EbpJson.toJsonElement(EbpJson.parse("""{"z":1,"a":2,"m":3}""")) as JsonObject
        assertEquals(listOf("z", "a", "m"), e.keys.toList())
    }
}
