// SPDX-License-Identifier: GPL-3.0-or-later
// The device-capability module (SPEC 20), library half. capability.invoke
// lets Emacs run finite Companion-advertised platform operations. The wire
// library owns the closed-contract parts — arg validation before any side
// effect (-32602), the cap-existence gate (1001), and the closed-result
// discipline — and delegates the actual platform work to a host-provided
// CapabilityHandler, whose typed refusal (1002/1003) it forwards verbatim.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** SPEC 20.2: the host's outcome for one capability.invoke. */
sealed class CapabilityOutcome {
    /** Success: the exact closed Result object from the catalog row. */
    data class Ok(val result: JsonObject) : CapabilityOutcome()
    /** A typed refusal: 1002 (cap-permission) or 1003 (cap-failed). The reason
     * becomes error.data.reason. */
    data class Fail(val code: Int, val reason: String) : CapabilityOutcome()
}

/**
 * SPEC 20.2: the platform executor. The engine has already validated cap
 * existence and the closed Args schema; the handler re-checks authorization
 * at invocation time and performs the bounded operation, returning Ok with
 * the exact catalog Result or a typed Fail. It MUST NOT treat a string
 * argument as executable code.
 */
fun interface CapabilityHandler {
    fun invoke(cap: String, args: JsonObject): CapabilityOutcome
}

/**
 * SPEC 20.3: the closed Args schemas this build knows how to validate. A
 * Companion advertising a cap in `device.caps` outside this set is
 * misconfigured — an advertised row is normative, and the library validates
 * every argument before a side effect begins.
 */
object CapabilityCatalog {

    private val VOLUME_STREAMS = setOf(
        "music", "ring", "alarm", "notification", "call", "system")
    private val MEDIA_KEYS = setOf(
        "play_pause", "play", "pause", "next", "previous", "stop",
        "fast_forward", "rewind")
    private val RINGER_MODES = setOf("normal", "vibrate", "silent")
    private val DND_MODES = setOf("on", "off", "priority")

    /** Caps whose Args this build validates and can therefore accept. */
    val VALIDATED = setOf(
        "vibrate", "volume.set", "tts.speak", "ringer.mode", "flashlight",
        "media.key", "screen.keep_on", "brightness.set", "dnd.set",
        "clipboard.read")

    /**
     * SPEC 20.2/20.3: validate a closed Args object against the catalog row
     * for `cap`. Throws ContentInvalid (which the engine maps to -32602)
     * before any side effect. A cap outside VALIDATED throws — the host must
     * not advertise what the library cannot validate.
     */
    fun validateArgs(cap: String, args: JsonObject) {
        when (cap) {
            "vibrate" -> validateVibrate(args)
            "volume.set" -> {
                closed(args, "stream", "level")
                enumArg(args, "stream", VOLUME_STREAMS)
                intArg(args, "level", 0, Int.MAX_VALUE.toLong())
            }
            "tts.speak" -> {
                closed(args, "text", "pitch", "rate")
                strArg(args, "text")
                if ("pitch" in args) numArg(args, "pitch", 0.5, 2.0)
                if ("rate" in args) numArg(args, "rate", 0.5, 2.0)
            }
            "ringer.mode" -> { closed(args, "mode"); enumArg(args, "mode", RINGER_MODES) }
            "flashlight" -> { closed(args, "on"); boolArg(args, "on") }
            "media.key" -> { closed(args, "key"); enumArg(args, "key", MEDIA_KEYS) }
            "screen.keep_on" -> { closed(args, "on"); boolArg(args, "on") }
            "brightness.set" -> { closed(args, "level"); intArg(args, "level", 0, 255) }
            "dnd.set" -> { closed(args, "mode"); enumArg(args, "mode", DND_MODES) }
            "clipboard.read" -> closed(args) // no members
            else -> throw ContentInvalid("cap", "capability not validated by this build")
        }
    }

    // SPEC 20.3: `vibrate` takes exactly one of {ms} or {pattern}.
    private fun validateVibrate(args: JsonObject) {
        val hasMs = "ms" in args
        val hasPattern = "pattern" in args
        if (hasMs == hasPattern)
            throw ContentInvalid("args", "exactly one of ms or pattern")
        if (hasMs) {
            closed(args, "ms")
            intArg(args, "ms", 1, 60_000)
        } else {
            closed(args, "pattern")
            val p = args.arrOrNull("pattern")
                ?: throw ContentInvalid("args.pattern", "must be an array")
            if (p.size < 1 || p.size > 64)
                throw ContentInvalid("args.pattern", "1..64 entries")
            var total = 0L
            for (i in p.indices)
                total += integer(p[i], "args.pattern[$i]", 0, 60_000)
            if (total > 60_000)
                throw ContentInvalid("args.pattern", "total exceeds 60000 ms")
        }
    }

    // ------------------------------------------------------------ primitives

    private fun closed(o: JsonObject, vararg allowed: String) {
        for (k in o.keys) if (k !in allowed)
            throw ContentInvalid("args.$k", "unknown member")
    }

    private fun strArg(o: JsonObject, key: String): String =
        o.stringOrNull(key) ?: throw ContentInvalid("args.$key", "must be a string")

    private fun boolArg(o: JsonObject, key: String): Boolean =
        o.boolOrNull(key) ?: throw ContentInvalid("args.$key", "must be a boolean")

    private fun enumArg(o: JsonObject, key: String, allowed: Set<String>): String {
        val v = o.stringOrNull(key) ?: throw ContentInvalid("args.$key", "must be a string")
        if (v !in allowed) throw ContentInvalid("args.$key", "not a permitted value")
        return v
    }

    private fun intArg(o: JsonObject, key: String, min: Long, max: Long): Long =
        integer(o[key], "args.$key", min, max)

    /** An integral JSON number in [min, max]; rejects fractions and non-finite.
     * The value is normalized at accept time, so an older peer's `{"ms": 100.0}`
     * is the same 100 ms it was under org.json (whose getLong truncated a
     * Double) — pinned by PreSwapNumberTest. */
    private fun integer(v: JsonElement?, path: String, min: Long, max: Long): Long {
        val n = integralLongOrNull(v) ?: throw ContentInvalid(path, "must be an integer")
        if (n < min || n > max) throw ContentInvalid(path, "out of range $min..$max")
        return n
    }

    private fun numArg(o: JsonObject, key: String, min: Double, max: Double): Double {
        // A binary64 arg (tts pitch/rate): any JSON number, integral or not.
        // The reader's isString guard is what keeps the string "1.5" out —
        // org.json's `as? Number` cast refused it the same way. A non-finite
        // value cannot reach here from the wire (EbpJson refuses it), but a
        // host-built tree can carry one, and it stays an out-of-range refusal
        // rather than a "must be a number" one, exactly as before.
        val d = o[key]?.asDoubleOrNull()
            ?: throw ContentInvalid("args.$key", "must be a number")
        if (d.isNaN() || d.isInfinite() || d < min || d > max)
            throw ContentInvalid("args.$key", "out of range $min..$max")
        return d
    }
}
