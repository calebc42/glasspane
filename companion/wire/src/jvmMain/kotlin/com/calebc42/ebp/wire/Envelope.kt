// SPDX-License-Identifier: GPL-3.0-or-later
// EBP 2 JSON-RPC envelope conventions. Implements ebp/SPEC.md section 7.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

enum class MessageClass { REQUEST, NOTIFICATION, RESPONSE }

private val REQUEST_ID = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]*")
private const val MAX_SAFE_INTEGER = 9_007_199_254_740_991L

/**
 * SPEC 7.2 (amendment #34): a string identifier of at most 64 ASCII octets,
 * or a safe integer — jsonrpc.el's sequential ids conform.
 *
 * C2: the argument is a [JsonElement], so the string/number distinction is
 * carried by the tree rather than by Kotlin's runtime type. `isString`
 * discriminates the two: a JSON string `"7"` and the number `7` are
 * different ids (SPEC 4.3, no coercion) and org.json's `getLong` coercion of
 * `"7"` to `7` does not survive the swap. Pinned by EnvelopeIdTest.
 */
fun isValidRequestId(id: JsonElement?): Boolean {
    val p = id as? JsonPrimitive ?: return false
    if (p is kotlinx.serialization.json.JsonNull) return false
    return if (p.isString) {
        // ASCII by the regex, so length is the octet count.
        p.content.length in 1..WireLimits.MAX_REQUEST_ID_OCTETS &&
            REQUEST_ID.matches(p.content)
    } else {
        // Numeric ids must be safe INTEGERS: `7.0` and `true` are not ids.
        val n = p.content.toLongOrNull() ?: return false
        n in -MAX_SAFE_INTEGER..MAX_SAFE_INTEGER
    }
}

/** SPEC 11/4.5 (amendment #93): a method name is a §4.4 identifier of at
 * most 128 octets — validated BEFORE any registry consult or allocation. */
fun isValidMethodName(method: String): Boolean =
    method.length in 1..WireLimits.MAX_METHOD_OCTETS && REQUEST_ID.matches(method)

/** The `method` member as a string, or null when absent OR not a JSON
 * string. A non-string `method` is a malformed envelope, never a lookup:
 * see [classifyMessage]. */
fun methodOf(msg: JsonObject): String? =
    (msg["method"] as? JsonPrimitive)?.takeIf { it.isString }?.content

/**
 * Classify a parsed message per SPEC 7.1, or null when structurally invalid
 * (wrong version marker, id/result/error combinations that fit no class).
 *
 * C2 taxonomy change, deliberate: `jsonrpc` must be the JSON STRING "2.0"
 * (the number 2.0 is not the version marker) and `method`, when present,
 * must be a JSON string. Pre-swap, org.json's `opt("jsonrpc") != "2.0"`
 * already rejected a numeric 2.0 by Kotlin equality, but a non-string
 * `method` reached the dispatcher and closed the connection with no frame.
 * It is now an unclassifiable envelope, which routes to the -32600
 * Invalid Request path like every other structural fault. PreSwapNumberTest
 * pins the old behavior so this flip is a conscious test update, not a
 * silent drift.
 */
fun classifyMessage(msg: JsonObject): MessageClass? {
    val version = msg["jsonrpc"] as? JsonPrimitive
    if (version == null || !version.isString || version.content != "2.0") return null
    val hasMethod = "method" in msg
    if (hasMethod && methodOf(msg) == null) return null
    val hasId = "id" in msg
    val hasResult = "result" in msg
    val hasError = "error" in msg
    return when {
        hasMethod && hasId && !hasResult && !hasError -> MessageClass.REQUEST
        hasMethod && !hasId && !hasResult && !hasError -> MessageClass.NOTIFICATION
        !hasMethod && hasId && (hasResult xor hasError) -> MessageClass.RESPONSE
        else -> null
    }
}

/** SPEC 7.1 builders. `params` MUST be a JSON object; {} when empty. */
fun request(id: String, method: String, params: JsonObject): JsonObject {
    require(isValidRequestId(JsonPrimitive(id))) { "invalid request id: $id" }
    return buildJsonObject {
        put("jsonrpc", "2.0")
        put("id", id)
        put("method", method)
        put("params", params)
    }
}

/** The peer's own id echoed back verbatim — string stays string, integer
 * stays integer (SPEC 7.2). A response that respells the id matches nothing
 * on the sender's side. */
fun request(id: JsonElement, method: String, params: JsonObject): JsonObject {
    require(isValidRequestId(id)) { "invalid request id: $id" }
    return buildJsonObject {
        put("jsonrpc", "2.0")
        put("id", id)
        put("method", method)
        put("params", params)
    }
}

fun notification(method: String, params: JsonObject): JsonObject =
    buildJsonObject {
        put("jsonrpc", "2.0")
        put("method", method)
        put("params", params)
    }

fun resultResponse(id: JsonElement, result: JsonObject): JsonObject =
    buildJsonObject {
        put("jsonrpc", "2.0")
        put("id", id)
        put("result", result)
    }

/** SPEC 8: numeric code, concise message, `data.kind` plus optional members.
 *
 * C2 (R3): `data` is no longer mutated in place — kotlinx trees are
 * immutable, so `kind` is merged into a COPY. The old
 * `data.put("kind", kind)` wrote through to the caller's object, which was a
 * latent aliasing bug that immutability retires by construction. */
fun errorResponse(id: JsonElement, code: Int, message: String, kind: String,
                  data: JsonObject = JsonObject(emptyMap())): JsonObject =
    buildJsonObject {
        put("jsonrpc", "2.0")
        put("id", id)
        put("error", buildJsonObject {
            put("code", code)
            put("message", message)
            put("data", JsonObject(data + ("kind" to JsonPrimitive(kind))))
        })
    }
