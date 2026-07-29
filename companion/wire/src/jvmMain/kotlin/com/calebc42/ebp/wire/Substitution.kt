// SPDX-License-Identifier: GPL-3.0-or-later
// Fire-time substitution for trigger on_fire entries (SPEC 21.4). String
// values inside args and notify — recursively through objects and arrays —
// may use ${id}, ${type}, and ${data.FIELD}. Substitution is single-pass and
// always yields a string: numbers and booleans use their JSON spelling, a
// missing or null value leaves the token literal, and $${ is a literal ${.
// The cap name and JSON member names are never interpolated (only string
// VALUES are visited). referencesData supports the SPEC 21.4 install-time
// source-to-sink approval gate for sensitive trigger types.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject

object Substitution {

    private const val DOLLAR = '$'
    private const val OPEN = '{'
    private const val CLOSE = '}'

    /** SPEC 21.4: return a copy of `node` with every string value substituted
     * against the fire context. Non-string scalars pass through untouched. */
    fun apply(node: Any?, id: String, type: String, data: JSONObject): Any? = when (node) {
        is String -> applyString(node, id, type, data)
        is JSONObject -> JSONObject().also { o ->
            for (k in node.keySet()) o.put(k, apply(node.opt(k), id, type, data))
        }
        is JSONArray -> JSONArray().also { a ->
            for (i in 0 until node.length()) a.put(apply(node.opt(i), id, type, data))
        }
        else -> node
    }

    private fun applyString(s: String, id: String, type: String, data: JSONObject): String {
        val sb = StringBuilder()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            // $${ is a literal ${ (checked before the ${ open, since it starts
            // with the same dollar).
            if (c == DOLLAR && i + 2 < s.length && s[i + 1] == DOLLAR && s[i + 2] == OPEN) {
                sb.append(DOLLAR).append(OPEN); i += 3; continue
            }
            if (c == DOLLAR && i + 1 < s.length && s[i + 1] == OPEN) {
                val end = s.indexOf(CLOSE, i + 2)
                if (end < 0) { sb.append(c); i++; continue } // unterminated: literal
                val token = s.substring(i + 2, end)
                val rep = resolve(token, id, type, data)
                if (rep == null) sb.append(s, i, end + 1)     // missing/unknown: literal
                else sb.append(rep)
                i = end + 1; continue
            }
            sb.append(c); i++
        }
        return sb.toString()
    }

    private fun resolve(token: String, id: String, type: String, data: JSONObject): String? = when {
        token == "id" -> id
        token == "type" -> type
        token.startsWith("data.") -> {
            val field = token.substring(5)
            if (!data.has(field)) null
            else when (val v = data.opt(field)) {
                JSONObject.NULL, null -> null
                is Boolean -> v.toString()
                is Number -> jsonNumber(v)
                is String -> v
                else -> null // arrays/objects are not scalar sinks: leave literal
            }
        }
        else -> null
    }

    private fun jsonNumber(v: Number): String {
        val d = v.toDouble()
        return if (!d.isNaN() && !d.isInfinite() && d == Math.floor(d)) v.toLong().toString()
        else v.toString()
    }

    /**
     * SPEC 21.4: does any string value in `node` carry a LIVE ${data.FIELD}
     * token (an escaped $${data...} does not count)? Used at install time to
     * require approval before a sensitive trigger's data reaches a sink.
     */
    fun referencesData(node: Any?): Boolean = when (node) {
        is String -> containsDataToken(node)
        is JSONObject -> node.keySet().any { referencesData(node.opt(it)) }
        is JSONArray -> (0 until node.length()).any { referencesData(node.opt(it)) }
        else -> false
    }

    private fun containsDataToken(s: String): Boolean {
        var i = 0
        while (i < s.length) {
            if (s[i] == DOLLAR && i + 2 < s.length && s[i + 1] == DOLLAR && s[i + 2] == OPEN) {
                i += 3; continue
            }
            if (s[i] == DOLLAR && i + 1 < s.length && s[i + 1] == OPEN) {
                val end = s.indexOf(CLOSE, i + 2)
                if (end >= 0) {
                    if (s.substring(i + 2, end).startsWith("data.")) return true
                    i = end + 1; continue
                }
            }
            i++
        }
        return false
    }
}
