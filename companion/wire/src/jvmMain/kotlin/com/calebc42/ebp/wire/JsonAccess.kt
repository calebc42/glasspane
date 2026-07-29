// SPDX-License-Identifier: GPL-3.0-or-later
// RF-2b: the org.json -> kotlinx.serialization translation layer. Every
// translation decision is encoded here exactly once, so the ~625 call sites in
// :wire read as intent rather than as a per-site re-derivation of what
// org.json's laxity used to do for them.
//
// Module-wide null convention: Kotlin `null` = member ABSENT; `JsonNull` = JSON
// null. `JsonObject` is a `Map<String, JsonElement>`, so `obj[k]` is null
// exactly when the member is absent — a distinction org.json blurred (its
// `opt*(k, default)` folded explicit null INTO the default, and its `get*`
// coerced across types, e.g. the string "42" read back as the number 42).
// These helpers keep the fold where behavior depends on it and drop the
// coercion everywhere: every such site is validator-gated upstream, so stricter
// is correct, and a test that trips on the change has found real latent laxity.
//
// This file is commonMain-clean by construction (RF-2c hoists it first, H1).
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// --- structural readers (absent and JSON-null both read as Kotlin null) ------

internal fun JsonObject.objOrNull(k: String): JsonObject? = this[k] as? JsonObject

internal fun JsonObject.arrOrNull(k: String): JsonArray? = this[k] as? JsonArray

// --- scalar readers ---------------------------------------------------------
//
// The `isString` guard is what keeps a JSON string out of a number/boolean
// reader (and vice versa); JsonNull reports isString=false and content "null",
// so it is filtered by the same guards rather than stringified into "null".

internal fun JsonObject.stringOrNull(k: String): String? =
    (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content

internal fun JsonObject.stringOr(k: String, d: String = ""): String = stringOrNull(k) ?: d

/**
 * The wire's integer reader: recovers today's `is Int || is Long` predicate
 * exactly. A parsed [EbpValue.EInt]'s content never carries '.' or an exponent,
 * so `toLongOrNull` accepts precisely the integer spellings and rejects
 * binary64 ones. Integral doubles written by older peers (`5000.0`) are NOT
 * accepted here — normalize those at accept time, the way
 * [TriggerValidator] already does.
 */
internal fun JsonObject.wireIntOrNull(k: String): Long? =
    (this[k] as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }?.content?.toLongOrNull()

internal fun JsonObject.longOr(k: String, d: Long = 0L): Long = wireIntOrNull(k) ?: d

internal fun JsonObject.boolOr(k: String, d: Boolean = false): Boolean =
    (this[k] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toBooleanStrictOrNull() ?: d

// --- throwing (get-style) accessors -----------------------------------------
//
// These keep the crash-vs-reply shape of the org.json `get*` family: the caller
// is inside a guarded dispatch arm that turns the throw into an error reply.
// The exception type changes (NoSuchElementException, not JSONException) — only
// catch-sites that named JSONException care, and they are being migrated too.

internal fun JsonObject.reqString(k: String): String = stringOrNull(k) ?: throw NoSuchElementException(k)

internal fun JsonObject.reqLong(k: String): Long = wireIntOrNull(k) ?: throw NoSuchElementException(k)

internal fun JsonObject.reqObj(k: String): JsonObject = objOrNull(k) ?: throw NoSuchElementException(k)

internal fun JsonObject.reqArr(k: String): JsonArray = arrOrNull(k) ?: throw NoSuchElementException(k)

// --- persistent "mutation" --------------------------------------------------
//
// JsonObject is immutable: these RETURN a new object. A call whose result is
// dropped compiles cleanly and does nothing — the one migration hazard the
// compiler cannot catch (org.json's put/remove mutated in place).

internal fun JsonObject.with(k: String, v: JsonElement): JsonObject = JsonObject(this + (k to v))

internal fun JsonObject.without(k: String): JsonObject = JsonObject(this - k)

// --- predicates -------------------------------------------------------------

/** SPEC 4.2's integer-vs-binary64 discrimination, for the validators. */
internal val JsonPrimitive.isIntegral: Boolean
    get() = !isString && content.toLongOrNull() != null

/**
 * org.json's `isNull(k)`: true for JSON null AND for an absent member. Preserved
 * deliberately — the call sites read it as "no usable value here".
 */
internal fun JsonObject.isNullOrAbsent(k: String): Boolean {
    val v = this[k]
    return v == null || v is JsonNull
}

/**
 * Outbound-response correlation. Companion-issued request ids are integers
 * (SPEC 7.2), so a response carrying the STRING "1" must never conclude the
 * pending integer id 1 — the isString guard is the whole point, and the entire
 * durable pump hangs on it.
 */
internal fun requestIdKey(e: JsonElement?): Long? =
    (e as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }?.content?.toLongOrNull()
