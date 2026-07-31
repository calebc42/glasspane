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

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

object Substitution {

    private const val DOLLAR = '$'
    private const val OPEN = '{'
    private const val CLOSE = '}'

    /** SPEC 21.4: return a copy of `node` with every string value substituted
     * against the fire context. Non-string scalars pass through untouched.
     *
     * C3: the nullable in/out signature is the [JsonElement] translation of
     * the old `Any?` one, but a null can only ever be the CALLER's — a member
     * of an object and an element of an array are non-null by kotlinx's
     * types, which is why the recursion runs through [applyValue] and cannot
     * drop a member. (Under org.json, `put(k, null)` REMOVED the member; the
     * old code was safe only because `opt` over `keySet` never returned it.) */
    fun apply(node: JsonElement?, id: String, type: String, data: JsonObject): JsonElement? =
        if (node == null) null else applyValue(node, id, type, data)

    private fun applyValue(node: JsonElement, id: String, type: String,
                           data: JsonObject): JsonElement = when {
        node is JsonPrimitive && node.isString ->
            JsonPrimitive(applyString(node.content, id, type, data))
        node is JsonObject -> buildJsonObject {
            for ((k, v) in node) put(k, applyValue(v, id, type, data))
        }
        node is JsonArray -> JsonArray(node.map { applyValue(it, id, type, data) })
        else -> node
    }

    private fun applyString(s: String, id: String, type: String, data: JsonObject): String {
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

    private fun resolve(token: String, id: String, type: String, data: JsonObject): String? = when {
        token == "id" -> id
        token == "type" -> type
        token.startsWith("data.") -> {
            val field = token.substring(5)
            if (field !in data) null
            else when (val v = data[field]) {
                null, is JsonNull -> null
                // One JSON kind, three Java types before the swap. A
                // JsonPrimitive carries the same three, discriminated by
                // `isString` plus the shape of its literal: a non-string
                // primitive spells either a boolean or a number.
                is JsonPrimitive -> when {
                    v.isString -> v.content
                    v.content.toBooleanStrictOrNull() != null -> v.content
                    // An integer literal renders from the LONG, never through
                    // a Double: binary64 cannot hold every integer past 2^53,
                    // so the Double route would substitute a ROUNDED value
                    // into user-visible text (987654321012345678 renders
                    // ...680). Wire data is capped at 2^53-1 by the T1
                    // parser, but host-built trigger fire-data reaches here
                    // unbounded (TriggerFiringService.observeExternal ->
                    // TriggerRuntime.onExternal -> apply). Try-Long-first is
                    // the same shape as JsonAccess.integralLongOrNull.
                    else -> v.content.toLongOrNull()?.toString()
                        ?: v.content.toDoubleOrNull()?.let { n -> jsonNumber(n) }
                }
                else -> null // arrays/objects are not scalar sinks: leave literal
            }
        }
        else -> null
    }

    /**
     * Fire data lands in USER-VISIBLE notification text, so an integral value
     * renders without a decimal point: a battery level of 19 reads "19%",
     * never "19.0%". Pinned by
     * SubstitutionTest.integralDoubleSubstitutesWithoutDecimalPoint.
     *
     * C3: unchanged, and the value — not the literal — is what reaches it.
     * org.json normalized `2.0` back to `2` on its own; kotlinx keeps a
     * primitive's spelling verbatim, so the content string is exactly where
     * "2.0" would start leaking into a toast. Reading the numeric value and
     * re-rendering it here is what keeps that spelling out of the text.
     */
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
    fun referencesData(node: JsonElement?): Boolean = when {
        node is JsonPrimitive && node.isString -> containsDataToken(node.content)
        node is JsonObject -> node.values.any { referencesData(it) }
        node is JsonArray -> node.any { referencesData(it) }
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
