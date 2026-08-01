// SPDX-License-Identifier: GPL-3.0-or-later
// C5 shared test support: the byte-identical helpers that were duplicated
// across suites pre-C5 (KAT constants x20 files, limits() x17, frame() x17,
// the response-selector idiom x6), converted once. Deliberately NOT here:
// the per-suite engine()/readyEngine() factories — they differ meaningfully
// in grants, device reports and stores, and one blended factory is how a
// grant leaks into a dispatch test and flips a -32601/1204 taxonomy. The
// three pin files (PersistenceCompatTest, PreSwapNumberTest, EnvelopeIdTest)
// keep fully local helpers on purpose: PLAN-rf2 §0.1 wants "a single file to
// keep green", and that hermeticity is worth sixty duplicated lines.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// --- KAT identity (SPEC 9.3 known-answer vectors) ----------------------------

internal val katToken: ByteArray = EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")
internal const val katPid = "101112131415161718191a1b1c1d1e1f"
internal const val katCn = "202122232425262728292a2b2c2d2e2f"
internal const val katSn = "303132333435363738393a3b3c3d3e3f"

/**
 * The nine-member limits core every suite carried verbatim; per-suite extras
 * (max_triggers, max_editor_bytes, max_dialogs, ...) ride [overrides], which
 * may also REPLACE a core member (later put wins). Values are integer
 * literals on purpose: limits members are integer-SPELLED on the wire and
 * the engine's readers are strict (§1 Int-literal rule).
 */
internal fun testLimits(vararg overrides: Pair<String, Number>): JsonObject =
    buildJsonObject {
        put("max_frame_bytes", 4_194_304)
        put("max_queued_events", 256)
        put("max_queued_bytes", 8_388_608)
        put("max_event_bytes", 262_144)
        put("max_surfaces", 16)
        put("max_surface_ids", 1024)
        put("max_field_bytes", 65_536)
        put("max_input_state_bytes", 262_144)
        put("max_capture_fields", 64)
        for ((k, v) in overrides) put(k, v)
    }

/** kotlinx `toString()` IS the production wire serializer (wireSerialize). */
internal fun frame(msg: JsonObject): ByteArray = encodeFrame(msg.toString())

// --- decoded-output selectors -------------------------------------------------
//
// Id matching is TYPED element equality (R2): JsonPrimitive(7) == JsonPrimitive(7L)
// but != JsonPrimitive("7") — the distinction several pins exist to test.
// Selectors THROW when nothing matches: a predicate gone vacuous must fail the
// test loudly, never let it pass by matching nothing.

internal fun List<JsonObject>.replyTo(id: String): JsonObject =
    last { it["id"] == JsonPrimitive(id) }

internal fun List<JsonObject>.replyTo(id: Long): JsonObject =
    last { it["id"] == JsonPrimitive(id) }

internal fun List<JsonObject>.errorOf(id: String): JsonObject =
    replyTo(id).reqObj("error")

internal fun List<JsonObject>.events(): List<JsonObject> =
    filter { it.stringOrNull("method") == "event.action" }
