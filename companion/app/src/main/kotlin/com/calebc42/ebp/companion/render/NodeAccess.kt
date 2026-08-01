// SPDX-License-Identifier: GPL-3.0-or-later
// C6: the app-side JSON readers, one decision each. :app CANNOT see :wire's
// internal JsonAccess (separate Gradle module, no friend path), so these are
// re-derived with the same guard discipline: the isString/JsonNull takeIf is
// what keeps a JSON string out of a number/boolean read and stops JsonNull
// from stringifying to "null". Same-name helpers in :wire are internal there;
// no collision is possible.
package com.calebc42.ebp.companion.render

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.floor

/** The binary64 VALUE of a JSON number; null for strings/booleans/JsonNull. */
internal fun JsonElement.numOrNull(): Double? =
    (this as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }
        ?.content?.toDoubleOrNull()

/** The value as a JSON string; null for every other kind. */
internal fun JsonElement.strOrNull(): String? =
    (this as? JsonPrimitive)?.takeIf { it.isString }?.content

internal fun JsonObject.stringOrNull(k: String): String? = this[k]?.strOrNull()

/** org.json's optString(k, d) fold (absent AND explicit null -> default),
 * minus its string coercion — the members are validator-gated upstream. */
internal fun JsonObject.stringOr(k: String, d: String = ""): String =
    stringOrNull(k) ?: d

internal fun JsonObject.boolOrNull(k: String): Boolean? =
    (this[k] as? JsonPrimitive)?.takeIf { !it.isString }
        ?.content?.toBooleanStrictOrNull()

internal fun JsonObject.boolOr(k: String, d: Boolean = false): Boolean =
    boolOrNull(k) ?: d

internal fun JsonObject.objOrNull(k: String): JsonObject? = this[k] as? JsonObject

internal fun JsonObject.arrOrNull(k: String): JsonArray? = this[k] as? JsonArray

/** org.json's 2-arg optDouble; the 1-arg NaN-default sites read
 * `node["k"]?.numOrNull()` and keep their skip-on-absent shape instead. */
internal fun JsonObject.doubleOr(k: String, d: Double): Double =
    this[k]?.numOrNull() ?: d

/**
 * Dimension members (FIELD_TYPES dp/number) are LEGALLY FRACTIONAL —
 * SpecValidator gates them as finite numbers only — and org.json's optInt
 * TRUNCATED them. Truncate (never round) to reproduce it, and fold a
 * non-numeric member into the default exactly as optInt did.
 */
internal fun JsonObject.dimInt(k: String, d: Int): Int =
    this[k]?.numOrNull()?.toInt() ?: d

/**
 * Integer-typed spec members (initial, max_lines, day, year, month_index,
 * dots) are validated integral BY VALUE upstream — "2.0" is accepted — so
 * the render read must be by value too, or the member silently defaults.
 */
internal fun JsonObject.intByValue(k: String, d: Int): Int =
    this[k]?.numOrNull()?.takeIf { it == floor(it) }?.toInt() ?: d

/**
 * The at_ms/base_ms/capability-arg class: values that PASS THROUGH the
 * engine verbatim, where the P0 pins guarantee integral-double spellings
 * ("at_ms": 5000.0, "ms": 100.0) are working device traffic. Integer
 * spelling first, then the binary64 value with org.json's getLong
 * truncation as the fallback (mirrors :wire ReminderStore.atMs).
 */
internal fun longByValue(e: JsonElement?): Long? {
    val p = (e as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }
        ?: return null
    p.content.toLongOrNull()?.let { return it }
    val d = p.content.toDoubleOrNull() ?: return null
    return if (d.isFinite()) d.toLong() else null
}
