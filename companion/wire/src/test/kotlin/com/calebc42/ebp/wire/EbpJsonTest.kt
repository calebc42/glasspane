// SPDX-License-Identifier: GPL-3.0-or-later
// T1: the strict RFC 8259 boundary parser. Every rejection below was
// ACCEPTED (and often silently coerced) by the org.json tokener this parser
// replaces — probed on the pinned jar during the 2026-07-25 review: {n:1},
// {'n':'v'}, [1,2,], +1, 007, 0x10 all parsed; NaN/Infinity became the
// STRINGS "NaN"/"Infinity"; 2^53 returned a widened Long/BigInteger; a lone
// surrogate escape survived to be re-encoded as '?'.
package com.calebc42.ebp.wire

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class EbpJsonTest {

    private fun rejects(text: String, kind: Class<out Exception> = WireParseError::class.java) {
        try {
            EbpJson.parse(text)
            fail("accepted: $text")
        } catch (e: Exception) {
            assertTrue("wrong error ${e.javaClass.simpleName} for: $text",
                kind.isInstance(e))
        }
    }

    @Test
    fun acceptsTheSevenValueKinds() {
        val v = EbpJson.parse(
            """{"s":"x","i":42,"n":1.5,"t":true,"f":false,"z":null,"a":[1],"o":{}}""")
        val obj = (v as EbpValue.EObj).members
        assertEquals(EbpValue.EStr("x"), obj["s"])
        assertEquals(EbpValue.EInt(42), obj["i"])
        assertEquals(EbpValue.ENum(1.5), obj["n"])
        assertEquals(EbpValue.EBool(true), obj["t"])
        assertEquals(EbpValue.EBool(false), obj["f"])
        assertEquals(EbpValue.ENull, obj["z"])
    }

    @Test
    fun laxGrammarOrgJsonToleratedIsRefused() {
        rejects("""{n:1}""")          // unquoted key
        rejects("""{'n':'v'}""")      // single quotes
        rejects("""[1,2,]""")         // trailing comma
        rejects("""[+1]""")           // plus sign
        rejects("""[007]""")          // leading zeros
        rejects("""[0x10]""")         // hex
        rejects("""[NaN]""")          // non-finite literal
        rejects("""[Infinity]""")     // non-finite literal
        rejects("""[-Infinity]""")
        rejects("""[1.]""")           // bare fraction point
        rejects("""[.5]""")           // no int part
        rejects("""[01]""")
        rejects("""{"a":1} x""")      // trailing data
        rejects("\"a\u0001b\"")   // raw control character in string
    }

    @Test
    fun integerRangeIsTheSpecRange() {
        assertEquals(EbpValue.EInt(9_007_199_254_740_991L),
            EbpJson.parse("9007199254740991"))
        assertEquals(EbpValue.EInt(-9_007_199_254_740_991L),
            EbpJson.parse("-9007199254740991"))
        rejects("9007199254740992")   // 2^53: org.json silently widened
        rejects("-9007199254740992")
        rejects("99999999999999999999999999")  // BigInteger territory
        // With an exponent it is a binary64 number, not an integer literal.
        assertEquals(EbpValue.ENum(1e300), EbpJson.parse("1e300"))
        rejects("1e309")              // overflows binary64 -> refused
    }

    @Test
    fun surrogatePolicyIsScalarValuesOnly() {
        // A paired escape is one astral scalar.
        val v = EbpJson.parse(""""😀"""") as EbpValue.EStr
        assertEquals("😀", v.v)
        // LD-8: a lone surrogate escape is not a scalar value.
        rejects(""""A\ud800B"""")
        rejects(""""\ud800"""")
        rejects(""""\udc00"""")       // lone low
        rejects(""""\ud800\ud800"""") // high followed by high
    }

    @Test
    fun duplicateMembersAreInvalidRequestInParse() {
        rejects("""{"a":1,"a":2}""", InvalidRequest::class.java)
        // Semantic comparison after escape decoding, like the reference scanner.
        rejects("""{"a":1,"\u0061":2}""", InvalidRequest::class.java)
        // Same name in DIFFERENT objects is fine.
        EbpJson.parse("""{"a":1,"b":{"a":2}}""")
    }

    @Test
    fun depthCapsAtSixtyFour() {
        val ok = "[".repeat(64) + "]".repeat(64)
        EbpJson.parse(ok)
        rejects("[".repeat(65) + "]".repeat(65))
    }

    @Test
    fun orgJsonProjectionPreservesTypesAndIds() {
        val obj = EbpJson.toOrgJson(EbpJson.parse(
            """{"id":7,"big":9007199254740991,"n":1.5,"z":null,"s":"x"}""")) as JSONObject
        // Small integers project as Int — response-id lookups depend on it.
        assertTrue(obj.get("id") is Int)
        assertTrue(obj.get("big") is Long)
        assertTrue(obj.get("n") is Double)
        assertTrue(obj.get("z") === JSONObject.NULL)
        assertEquals("x", obj.getString("s"))
    }
}
