// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 4.3 structural JSON equality: objects unordered, arrays ordered,
// numbers by binary64 value, null only equal to null.
//
// LD-20: the decisive discipline is Emacs's type-tag gate (fns.c
// internal_equal: `if (XTYPE (o1) != XTYPE (o2)) return false;`) — no
// cross-type comparison is reachable, and the terminal case is never
// delegated to the host language's equality. Every clause below is total
// for its type pair; there is no else over live wire types.
//
// C2 (R5): kotlinx's own `JsonPrimitive.equals` is NOT usable here. It
// compares the literal CONTENT STRING, so `1` and `1.0` come out unequal —
// a direct SPEC 4.3 violation, and the exact defect that would silently
// break trigger carry-forward (canonicalEquals delegates here) and dedupe.
// The type-tag gate is therefore reimplemented over JsonPrimitive:
// - strings by isString + content,
// - booleans by content ("true"/"false"),
// - numbers by content.toDouble() VALUE — exact under the T1 parser's
//   +/-(2^53-1) bound, so `60` == `60.0` as SPEC 4.3 requires,
// - JsonNull only equal to JsonNull,
// - Kotlin null ("absent" — what an absent member reads as) only equal to
//   Kotlin null, which SPEC 4.1 keeps distinct from JSON null.
// Pinned by JsonEqualityTest and EnvelopeIdTest.idEqualityIsTypedAtTheEqualityLayer.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

fun jsonValueEquals(a: JsonElement?, b: JsonElement?): Boolean = when {
    // Kotlin null is "absent"; JSON null is JsonNull. Distinct (SPEC 4.1).
    a == null || b == null -> a == null && b == null
    a is JsonNull || b is JsonNull -> a is JsonNull && b is JsonNull
    a is JsonPrimitive || b is JsonPrimitive ->
        a is JsonPrimitive && b is JsonPrimitive && primitiveEquals(a, b)
    a is JsonObject || b is JsonObject ->
        a is JsonObject && b is JsonObject &&
            a.keys == b.keys &&
            a.keys.all { jsonValueEquals(a[it], b[it]) }
    a is JsonArray || b is JsonArray ->
        a is JsonArray && b is JsonArray &&
            a.size == b.size &&
            a.indices.all { jsonValueEquals(a[it], b[it]) }
    // Not a SPEC 4.2 value kind: never equal to anything, itself included.
    else -> false
}

private fun primitiveEquals(a: JsonPrimitive, b: JsonPrimitive): Boolean = when {
    // A JSON string is never equal to a number or a boolean, whatever it
    // spells: `"1"` != `1`, `"true"` != `true`.
    a.isString || b.isString -> a.isString && b.isString && a.content == b.content
    else -> {
        val ab = a.content.toBooleanStrictOrNull()
        val bb = b.content.toBooleanStrictOrNull()
        if (ab != null || bb != null) ab != null && bb != null && ab == bb
        else {
            val an = a.content.toDoubleOrNull()
            val bn = b.content.toDoubleOrNull()
            an != null && bn != null && an == bn
        }
    }
}
