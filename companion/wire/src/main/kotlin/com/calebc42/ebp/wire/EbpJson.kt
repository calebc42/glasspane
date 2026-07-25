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

import org.json.JSONArray
import org.json.JSONObject

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
     * Lossless projection into the org.json tree the engine still consumes.
     * The value has already passed every boundary rule, so the projection
     * cannot smuggle anything the parser rejects: integers arrive as
     * Int/Long within +/-2^53-1 (Int when it fits, matching what the old
     * tokener produced so response-id lookups keep working), numbers are
     * finite Doubles, strings are scalar-clean, and null is JSONObject.NULL.
     */
    fun toOrgJson(v: EbpValue): Any = when (v) {
        is EbpValue.EObj -> JSONObject().also { o ->
            for ((k, m) in v.members) o.put(k, toOrgJson(m))
        }
        is EbpValue.EArr -> JSONArray().also { a ->
            for (item in v.items) a.put(toOrgJson(item))
        }
        is EbpValue.EStr -> v.v
        is EbpValue.EInt ->
            if (v.v in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) v.v.toInt() else v.v
        is EbpValue.ENum -> v.v
        is EbpValue.EBool -> v.v
        EbpValue.ENull -> JSONObject.NULL
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
                val d = Character.digit(s[k], 16)
                if (d < 0) throw WireParseError("invalid escape")
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
                // A literal like 1e999 overflows binary64: not representable,
                // not conformant, refused — never Infinity (SPEC 4.2).
                if (!v.isFinite()) throw WireParseError("number out of range")
                EbpValue.ENum(v)
            }
        }
    }
}
