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
import kotlin.math.floor

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
 * The element-level twin of [stringOrNull], for scanning ARRAY items: the
 * value as a JSON string, or null for every other kind. Array reads have no
 * member name to key on, and the alternative at each site is a raw `.content`
 * — which is exactly the coercion this file exists to centralize (a number
 * would stringify, and JsonNull would read as the literal "null").
 */
internal fun JsonElement.asStringOrNull(): String? =
    (this as? JsonPrimitive)?.takeIf { it.isString }?.content

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

/**
 * The lenient counterpart to [wireIntOrNull]: a JSON number whose VALUE is an
 * integer, however the sender spelled it. `60` and `60.0` both read as 60L;
 * `1.5`, the string `"60"`, a boolean, JSON null and an absent member all read
 * as null. Element-level (arrays have no member name to key on).
 *
 * This is the reader the VALIDATORS want. org.json's `getLong` truncated a
 * Double, so `{"ms": 100.0}` and `{"ttl_s": 60.0}` from an older peer are
 * working traffic today (PLAN 0.2 item 2, pinned by PreSwapNumberTest); a
 * `jsonPrimitive.long` port would begin refusing them on the device. A
 * validator normalizes with this at ACCEPT time and re-emits the Long, so the
 * normalized value is integer-spelled whatever arrived — the shape
 * [TriggerValidator] already practised before the swap.
 *
 * The binary64 path is exact for everything the wire can carry: EbpJson bounds
 * integers at +/-(2^53-1), which binary64 represents without loss.
 */
internal fun integralLongOrNull(e: JsonElement?): Long? {
    val p = e as? JsonPrimitive ?: return null
    if (p.isString || p is JsonNull) return null
    // Integer spelling first: a Long is never round-tripped through a double.
    p.content.toLongOrNull()?.let { return it }
    val d = p.content.toDoubleOrNull() ?: return null
    return if (d.isFinite() && d == floor(d)) d.toLong() else null
}

/**
 * The binary64 VALUE of a JSON number, or null for a string, a boolean,
 * JsonNull — anything that is not a number. Element-level, so it serves both
 * `obj[k]?.asDoubleOrNull()` and array scans.
 *
 * It does NOT filter non-finite values: the wire parser already refuses those
 * (SPEC 4.2), and the validators that read binary64 args report a non-finite
 * host-built value as out-of-range rather than as "not a number" — the
 * distinction org.json's `as? Number` cast made, and which their error
 * messages still carry.
 */
internal fun JsonElement.asDoubleOrNull(): Double? =
    (this as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }?.content?.toDoubleOrNull()

/**
 * The boolean under [k], or null when the member is absent or is not a JSON
 * boolean — the discrimination [boolOr] deliberately folds into its default,
 * and which the validators must instead report as a content fault (their old
 * shape was org.json's `opt(k) as? Boolean` cast).
 */
internal fun JsonObject.boolOrNull(k: String): Boolean? =
    (this[k] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toBooleanStrictOrNull()

internal fun JsonObject.boolOr(k: String, d: Boolean = false): Boolean = boolOrNull(k) ?: d

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
