// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 4.3 structural JSON equality: objects unordered, arrays ordered,
// numbers by binary64 value, null only equal to null.
//
// LD-20: the decisive discipline is Emacs's type-tag gate (fns.c
// internal_equal: `if (XTYPE (o1) != XTYPE (o2)) return false;`) — no
// cross-type comparison is reachable, and the terminal case is never
// delegated to the host language's equality. The old `else -> a == b`
// delegated exactly that, and org.json's NULL.equals(null) is true, so
// jsonValueEquals(JSONObject.NULL, null) held in one direction only —
// conflating JSON null with an ABSENT member, which SPEC 4.1 makes
// distinct (and Kotlin null is precisely what authoredValue returns for
// an absent member). Every clause below is total for its type pair; there
// is no else over live wire types. The number clause is conformant
// because the T1 parser refuses integers outside +/-(2^53-1) at the
// boundary, so toDouble() is exact.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject

fun jsonValueEquals(a: Any?, b: Any?): Boolean = when {
    // Kotlin null is "absent"; JSON null is JSONObject.NULL. Distinct.
    a == null || b == null -> a == null && b == null
    a === JSONObject.NULL || b === JSONObject.NULL ->
        a === JSONObject.NULL && b === JSONObject.NULL
    a is Boolean || b is Boolean -> a is Boolean && b is Boolean && a == b
    a is String || b is String -> a is String && b is String && a == b
    a is Number || b is Number ->
        a is Number && b is Number && a.toDouble() == b.toDouble()
    a is JSONObject || b is JSONObject ->
        a is JSONObject && b is JSONObject &&
            a.keySet() == b.keySet() &&
            a.keySet().all { jsonValueEquals(a.get(it), b.get(it)) }
    a is JSONArray || b is JSONArray ->
        a is JSONArray && b is JSONArray &&
            a.length() == b.length() &&
            (0 until a.length()).all { jsonValueEquals(a.get(it), b.get(it)) }
    // Not a SPEC 4.2 value kind: never equal to anything, itself included.
    else -> false
}
