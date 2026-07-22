// SPDX-License-Identifier: GPL-3.0-or-later
// EBP 2 JSON-RPC envelope conventions. Implements ebp/SPEC.md section 7.
package com.calebc42.ebp.wire

import org.json.JSONObject

enum class MessageClass { REQUEST, NOTIFICATION, RESPONSE }

private val REQUEST_ID = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]*")

/** SPEC 7.2: a string identifier of at most 64 ASCII octets, never empty. */
fun isValidRequestId(id: Any?): Boolean =
    id is String && id.length in 1..WireLimits.MAX_REQUEST_ID_OCTETS &&
        REQUEST_ID.matches(id)

/**
 * Classify a parsed message per SPEC 7.1, or null when structurally invalid
 * (wrong version marker, id/result/error combinations that fit no class).
 */
fun classifyMessage(msg: JSONObject): MessageClass? {
    if (msg.opt("jsonrpc") != "2.0") return null
    val hasMethod = msg.has("method")
    val hasId = msg.has("id")
    val hasResult = msg.has("result")
    val hasError = msg.has("error")
    return when {
        hasMethod && hasId && !hasResult && !hasError -> MessageClass.REQUEST
        hasMethod && !hasId && !hasResult && !hasError -> MessageClass.NOTIFICATION
        !hasMethod && hasId && (hasResult xor hasError) -> MessageClass.RESPONSE
        else -> null
    }
}

/** SPEC 7.1 builders. `params` MUST be a JSON object; {} when empty. */
fun request(id: String, method: String, params: JSONObject): JSONObject {
    require(isValidRequestId(id)) { "invalid request id: $id" }
    return JSONObject()
        .put("jsonrpc", "2.0").put("id", id)
        .put("method", method).put("params", params)
}

fun notification(method: String, params: JSONObject): JSONObject =
    JSONObject().put("jsonrpc", "2.0").put("method", method).put("params", params)

fun resultResponse(id: String, result: JSONObject): JSONObject =
    JSONObject().put("jsonrpc", "2.0").put("id", id).put("result", result)

/** SPEC 8: numeric code, concise message, `data.kind` plus optional members. */
fun errorResponse(id: String, code: Int, message: String, kind: String,
                  data: JSONObject = JSONObject()): JSONObject =
    JSONObject().put("jsonrpc", "2.0").put("id", id)
        .put("error", JSONObject()
            .put("code", code).put("message", message)
            .put("data", data.put("kind", kind)))
