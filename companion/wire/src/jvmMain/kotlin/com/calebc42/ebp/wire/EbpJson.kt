// SPDX-License-Identifier: GPL-3.0-or-later
// T1: the strict RFC 8259 parser at the frame boundary (SPEC 4.1/4.2/4.5).
//
// Emacs is the precedent, and recently: it shipped libjansson for 27-29,
// concluded a general-purpose JSON library was the wrong thing at the wire
// boundary, and in 30.1 replaced it with hand-written C (etc/NEWS: "Native
// JSON support is now always available; libjansson is no longer used").
// The reason transfers exactly: org.json's laxity (unquoted keys, single
// quotes, trailing commas, hex and leading-zero numbers, NaN/Infinity
// stringification, silent BigInteger widening, lone-surrogate passthrough)
// is not EBP's policy, and none of it is correctable from the caller's
// side — you can only re-scan afterward, which is what FrameCodec's two
// compensating full-text scans did. Everything here is enforced IN-PARSE,
// one pass: grammar, duplicate member names, nesting depth <= 64, surrogate
// pairing, integer magnitude <= 2^53-1, finite numbers.
//
// Error taxonomy is the wire's: a malformed text is WireParseError
// (-32700); duplicate member names are InvalidRequest (-32600, SPEC 4.1).
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** SPEC 4.2's seven value kinds, closed. Integers and binary64 numbers are
 * distinct on the wire and distinct here; both are within EBP's ranges by
 * construction once [EbpJson.parse] has accepted the text. */
sealed interface EbpValue {
    data class EObj(val members: Map<String, EbpValue>) : EbpValue
    data class EArr(val items: List<EbpValue>) : EbpValue
    data class EStr(val v: String) : EbpValue
    data class EInt(val v: Long) : EbpValue
    data class ENum(val v: Double) : EbpValue
    data class EBool(val v: Boolean) : EbpValue
    data object ENull : EbpValue
}

object EbpJson {

    /** SPEC 4.2: the largest integer either endpoint may carry: 2^53 - 1. */
    const val MAX_SAFE_INTEGER = 9_007_199_254_740_991L

    /**
     * Parse one complete JSON text strictly. Throws [WireParseError] for any
     * grammar violation, unescaped control character, unpaired surrogate
     * (escaped or raw), non-finite or out-of-range number, over-deep nesting,
     * or trailing data; throws [InvalidRequest] for duplicate member names.
     */
    fun parse(text: String): EbpValue {
        val p = Parser(text)
        p.skipWs()
        val v = p.value(0)
        p.skipWs()
        if (!p.atEnd()) throw WireParseError("trailing data after message")
        return v
    }

    /**
     * Lossless projection into kotlinx.serialization's tree (C2: this
     * replaced `toOrgJson`, deleted with the org.json dependency). The value
     * has already passed every boundary rule, so the projection cannot
     * smuggle anything the parser rejects: integers are within +/-2^53-1,
     * numbers are finite, strings are scalar-clean, null is JsonNull.
     *
     * Integers project as Long *always*. `toOrgJson`'s Int narrowing existed
     * for exactly one customer — the response-id lookup's `as? Int` — and that
     * map is keyed on Long now, so the narrowing died with it.
     *
     * The wire path is [parse] followed by this projection, never
     * `Json.parseToJsonElement`: kotlinx's own parser has the wrong taxonomy at
     * the frame boundary (it accepts duplicate member names and integers past
     * 2^53-1). kotlinx parses persisted store files, where leniency is the
     * requirement; it never parses wire bytes.
     */
    fun toJsonElement(v: EbpValue): JsonElement = when (v) {
        is EbpValue.EObj -> JsonObject(v.members.mapValues { (_, m) -> toJsonElement(m) })
        is EbpValue.EArr -> JsonArray(v.items.map { toJsonElement(it) })
        is EbpValue.EStr -> JsonPrimitive(v.v)
        is EbpValue.EInt -> JsonPrimitive(v.v)
        is EbpValue.ENum -> JsonPrimitive(v.v)
        is EbpValue.EBool -> JsonPrimitive(v.v)
        EbpValue.ENull -> JsonNull
    }

    private class Parser(private val s: String) {
        var i = 0

        fun atEnd() = i >= s.length

        fun skipWs() {
            // RFC 8259 ws is exactly these four characters.
            while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
                i++
        }

        fun value(depth: Int): EbpValue {
            if (atEnd()) throw WireParseError("unexpected end of message")
            return when (s[i]) {
                '{' -> obj(depth + 1)
                '[' -> arr(depth + 1)
                '"' -> EbpValue.EStr(string())
                't' -> { literal("true"); EbpValue.EBool(true) }
                'f' -> { literal("false"); EbpValue.EBool(false) }
                'n' -> { literal("null"); EbpValue.ENull }
                '-', in '0'..'9' -> number()
                else -> throw WireParseError("invalid JSON")
            }
        }

        private fun checkDepth(depth: Int) {
            // SPEC 4.5: at most 64 nested containers; the 65th open rejects.
            if (depth > WireLimits.MAX_JSON_DEPTH)
                throw WireParseError("nesting depth exceeds 64")
        }

        private fun obj(depth: Int): EbpValue {
            checkDepth(depth)
            i++ // '{'
            val members = LinkedHashMap<String, EbpValue>()
            skipWs()
            if (!atEnd() && s[i] == '}') { i++; return EbpValue.EObj(members) }
            while (true) {
                skipWs()
                if (atEnd() || s[i] != '"')
                    throw WireParseError("object member name must be a string")
                val key = string()
                // SPEC 4.1: duplicate member names invalidate the message —
                // detected here, at the allocation site, not by a re-scan.
                if (members.containsKey(key))
                    throw InvalidRequest("duplicate member names")
                skipWs()
                if (atEnd() || s[i] != ':') throw WireParseError("expected ':'")
                i++
                skipWs()
                members[key] = value(depth)
                skipWs()
                when {
                    atEnd() -> throw WireParseError("unexpected end of message")
                    s[i] == ',' -> i++
                    s[i] == '}' -> { i++; return EbpValue.EObj(members) }
                    else -> throw WireParseError("expected ',' or '}'")
                }
            }
        }

        private fun arr(depth: Int): EbpValue {
            checkDepth(depth)
            i++ // '['
            val items = mutableListOf<EbpValue>()
            skipWs()
            if (!atEnd() && s[i] == ']') { i++; return EbpValue.EArr(items) }
            while (true) {
                skipWs()
                items.add(value(depth))
                skipWs()
                when {
                    atEnd() -> throw WireParseError("unexpected end of message")
                    s[i] == ',' -> i++
                    s[i] == ']' -> { i++; return EbpValue.EArr(items) }
                    else -> throw WireParseError("expected ',' or ']'")
                }
            }
        }

        private fun literal(word: String) {
            if (!s.startsWith(word, i)) throw WireParseError("invalid JSON")
            i += word.length
        }

        private fun string(): String {
            i++ // opening '"'
            val out = StringBuilder()
            while (true) {
                if (atEnd()) throw WireParseError("unterminated string")
                val c = s[i]
                when {
                    c == '"' -> { i++; return out.toString() }
                    c == '\\' -> escape(out)
                    c < ' ' ->
                        // RFC 8259: control characters MUST be escaped.
                        throw WireParseError("unescaped control character")
                    c.isHighSurrogate() -> {
                        // Raw astral input arrives as a valid pair (the UTF-8
                        // decode already rejected malformed input); this guard
                        // keeps parse() total on arbitrary Strings too.
                        if (i + 1 >= s.length || !s[i + 1].isLowSurrogate())
                            throw WireParseError("unpaired surrogate")
                        out.append(c).append(s[i + 1])
                        i += 2
                    }
                    c.isLowSurrogate() -> throw WireParseError("unpaired surrogate")
                    else -> { out.append(c); i++ }
                }
            }
        }

        private fun escape(out: StringBuilder) {
            if (i + 1 >= s.length) throw WireParseError("unterminated string")
            when (val e = s[i + 1]) {
                '"', '\\', '/' -> { out.append(e); i += 2 }
                'b' -> { out.append('\b'); i += 2 }
                'f' -> { out.append('\u000C'); i += 2 }
                'n' -> { out.append('\n'); i += 2 }
                'r' -> { out.append('\r'); i += 2 }
                't' -> { out.append('\t'); i += 2 }
                'u' -> {
                    val hi = hex4(i + 2)
                    i += 6
                    when {
                        Character.isHighSurrogate(hi) -> {
                            // SPEC 4.1 (LD-8): a lone surrogate escape is not
                            // a scalar value. org.json accepted it and later
                            // re-encoded it as '?' — silent content damage.
                            if (i + 1 >= s.length || s[i] != '\\' || s[i + 1] != 'u')
                                throw WireParseError("unpaired surrogate escape")
                            val lo = hex4(i + 2)
                            if (!Character.isLowSurrogate(lo))
                                throw WireParseError("unpaired surrogate escape")
                            i += 6
                            out.append(hi).append(lo)
                        }
                        Character.isLowSurrogate(hi) ->
                            throw WireParseError("unpaired surrogate escape")
                        else -> out.append(hi)
                    }
                }
                else -> throw WireParseError("invalid escape")
            }
        }

        private fun hex4(at: Int): Char {
            if (at + 4 > s.length) throw WireParseError("unterminated string")
            var v = 0
            for (k in at until at + 4) {
                // RFC 8259 HEXDIG is ASCII-only. Character.digit is
                // UNICODE-aware: it maps 372 other code points (every
                // fullwidth and Indic/Arabic decimal digit block, plus
                // fullwidth A-F) onto 0..15, so "０FF10FF12FF12" —
                // fullwidth digits — decoded to a bare U+0022 quote, and a
                // fullwidth-spelled surrogate pair reached the pairing logic
                // below. This is the org.json class of laxity in the parser
                // written to close it: content the sender never encoded.
                val d = when (val ch = s[k]) {
                    in '0'..'9' -> ch - '0'
                    in 'a'..'f' -> ch - 'a' + 10
                    in 'A'..'F' -> ch - 'A' + 10
                    else -> throw WireParseError("invalid escape")
                }
                v = (v shl 4) or d
            }
            return v.toChar()
        }

        private fun number(): EbpValue {
            val start = i
            if (s[i] == '-') i++
            // int part: 0, or [1-9][0-9]* — leading zeros are not JSON.
            when {
                atEnd() -> throw WireParseError("invalid number")
                s[i] == '0' -> {
                    i++
                    if (!atEnd() && s[i] in '0'..'9')
                        throw WireParseError("invalid number")
                }
                s[i] in '1'..'9' -> while (!atEnd() && s[i] in '0'..'9') i++
                else -> throw WireParseError("invalid number")
            }
            var integral = true
            if (!atEnd() && s[i] == '.') {
                integral = false
                i++
                if (atEnd() || s[i] !in '0'..'9') throw WireParseError("invalid number")
                while (!atEnd() && s[i] in '0'..'9') i++
            }
            if (!atEnd() && (s[i] == 'e' || s[i] == 'E')) {
                integral = false
                i++
                if (!atEnd() && (s[i] == '+' || s[i] == '-')) i++
                if (atEnd() || s[i] !in '0'..'9') throw WireParseError("invalid number")
                while (!atEnd() && s[i] in '0'..'9') i++
            }
            val text = s.substring(start, i)
            return if (integral) {
                // SPEC 4.2: integers live in +/-(2^53 - 1). org.json widened
                // an overflow to BigInteger silently; here it is a refusal.
                val v = text.toLongOrNull()
                    ?: throw WireParseError("integer out of range")
                if (v > MAX_SAFE_INTEGER || v < -MAX_SAFE_INTEGER)
                    throw WireParseError("integer out of range")
                EbpValue.EInt(v)
            } else {
                val v = text.toDouble()
                // SPEC 4.2: a literal that overflows binary64 is refused —
                // the only value it could take is an infinity, which "is not
                // a JSON value and MUST NOT be transmitted". A literal that
                // UNDERFLOWS to zero is deliberately accepted as 0.0: the
                // sender violated the same sentence, but zero IS a
                // representable EBP value, so there is something conformant
                // to hand downstream. Asymmetric on purpose (amendment #99).
                if (!v.isFinite()) throw WireParseError("number out of range")
                EbpValue.ENum(v)
            }
        }
    }
}
