// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 4.3 structural JSON equality: objects unordered, arrays ordered,
// numbers by binary64 value, null only equal to null.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject

fun jsonValueEquals(a: Any?, b: Any?): Boolean = when {
    a is JSONObject && b is JSONObject ->
        a.keySet() == b.keySet() && a.keySet().all { jsonValueEquals(a.get(it), b.get(it)) }
    a is JSONArray && b is JSONArray ->
        a.length() == b.length() &&
            (0 until a.length()).all { jsonValueEquals(a.get(it), b.get(it)) }
    a is Number && b is Number -> a.toDouble() == b.toDouble()
    a == JSONObject.NULL && b == JSONObject.NULL -> true
    else -> a == b
}
