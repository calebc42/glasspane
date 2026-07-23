// SPDX-License-Identifier: GPL-3.0-or-later
// EBP 2 framing, Companion side. Implements ebp/SPEC.md sections 6 and 4.1.
// The Kotlin twin of emacs/ebp.el's decoder: same error taxonomy, same
// chunk-size independence, verified by the same goldens/wire corpus.
package com.calebc42.ebp.wire

import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/** SPEC 4.5 fixed limits (contract.json `limits.fixed`). */
object WireLimits {
    const val MAX_HEADER_OCTETS = 8192
    const val MAX_BODY_OCTETS = 4_194_304
    const val MAX_NODES_PER_SNAPSHOT = 10_000
    const val MAX_CHILDREN_PER_NODE = 10_000
    const val MAX_IDENTIFIER_OCTETS = 128
    const val MAX_REQUEST_ID_OCTETS = 64
}

/** SPEC 6.2: conditions that force connection closure. */
class FrameClose(message: String) : Exception(message)

/** SPEC 6.2: EOF in the middle of a frame terminates the session. */
class FrameIncomplete(message: String) : Exception(message)

/** SPEC 6.2: invalid UTF-8 or invalid JSON after a complete body. */
class WireParseError(message: String) : Exception(message)

/** SPEC 6.2 / 4.1: non-object top level, batch array, duplicate members. */
class InvalidRequest(message: String) : Exception(message)

/**
 * Incremental SPEC 6.2 receiver. Feed transport reads of any size; complete
 * messages come back in wire order. Errors are thrown as the taxonomy above.
 */
class FrameDecoder {
    private var buffer = ByteArray(0)

    fun feed(bytes: ByteArray): List<JSONObject> {
        buffer += bytes
        val messages = mutableListOf<JSONObject>()
        while (true) {
            val term = indexOfTerminator(buffer)
            if (term < 0) {
                // SPEC 6.2: the header section may not exceed 8,192 octets.
                if (buffer.size > WireLimits.MAX_HEADER_OCTETS)
                    throw FrameClose("header section too large")
                return messages
            }
            if (term + 4 > WireLimits.MAX_HEADER_OCTETS)
                throw FrameClose("header section too large")
            val length = parseHeader(String(buffer, 0, term, StandardCharsets.ISO_8859_1))
            val bodyStart = term + 4
            val bodyEnd = bodyStart + length
            if (buffer.size < bodyEnd) return messages // retain partial data
            val body = buffer.copyOfRange(bodyStart, bodyEnd)
            buffer = buffer.copyOfRange(bodyEnd, buffer.size)
            messages.add(parseBody(body))
        }
    }

    /** SPEC 6.2: EOF mid-frame terminates the session. */
    fun finish() {
        if (buffer.isNotEmpty())
            throw FrameIncomplete("stream ended with ${buffer.size} pending octets")
    }

    private fun indexOfTerminator(buf: ByteArray): Int {
        for (i in 0..buf.size - 4) {
            if (buf[i] == CR && buf[i + 1] == LF && buf[i + 2] == CR && buf[i + 3] == LF)
                return i
        }
        return -1
    }

    private companion object {
        const val CR = '\r'.code.toByte()
        const val LF = '\n'.code.toByte()
        val CONTENT_LENGTH_VALUE = Regex("0|[1-9][0-9]*")
    }

    /** SPEC 6.2 header rules; returns the declared body length. */
    private fun parseHeader(head: String): Int {
        val lengths = mutableListOf<Long>()
        for (line in head.split("\r\n")) {
            if (line.isEmpty()) throw FrameClose("malformed header line")
            val colon = line.indexOf(':')
            if (colon < 0) throw FrameClose("malformed header line")
            val name = line.substring(0, colon)
            if (name.any { it.code > 0x7E || it.code < 0x21 })
                throw FrameClose("malformed header name")
            // Receiver MAY accept optional horizontal whitespace around a value.
            val value = line.substring(colon + 1).trim(' ', '\t')
            if (name.equals("Content-Length", ignoreCase = true)) {
                if (!CONTENT_LENGTH_VALUE.matches(value))
                    throw FrameClose("invalid Content-Length value")
                lengths.add(value.toLongOrNull() ?: throw FrameClose("overflowing Content-Length"))
            }
        }
        when {
            lengths.isEmpty() -> throw FrameClose("missing Content-Length")
            lengths.size > 1 -> throw FrameClose("duplicate Content-Length")
        }
        val length = lengths.single()
        // SPEC 6.2: close immediately on an oversized declaration.
        if (length > WireLimits.MAX_BODY_OCTETS) throw FrameClose("oversized body declaration")
        return length.toInt()
    }

    /** SPEC 6.2 + 4.1: strict UTF-8, valid single JSON object, no duplicates. */
    private fun parseBody(body: ByteArray): JSONObject {
        val text = try {
            StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(body)).toString()
        } catch (_: CharacterCodingException) {
            throw WireParseError("invalid UTF-8")
        }
        val tokener = JSONTokener(text)
        val value = try {
            tokener.nextValue()
        } catch (_: JSONException) {
            // The reference org.json throws on duplicate keys during parse;
            // Android's implementation does not. Classify uniformly with our
            // own scanner so both platforms reject per SPEC 4.1.
            if (runCatching { hasDuplicateMembers(text) }.getOrDefault(false))
                throw InvalidRequest("duplicate member names")
            throw WireParseError("invalid JSON")
        }
        if (tokener.nextClean().code != 0) throw WireParseError("trailing data after message")
        if (value !is JSONObject)
            throw InvalidRequest("top-level value is not a single message object")
        if (hasDuplicateMembers(text)) throw InvalidRequest("duplicate member names")
        return value
    }
}

/** SPEC 6.1 sender: exact header syntax, octet-counted UTF-8 body. */
fun encodeFrame(jsonText: String): ByteArray {
    val body = jsonText.toByteArray(StandardCharsets.UTF_8)
    if (body.size > WireLimits.MAX_BODY_OCTETS)
        throw FrameClose("body exceeds max_frame_bytes")
    return "Content-Length: ${body.size}\r\n\r\n".toByteArray(StandardCharsets.US_ASCII) + body
}

/**
 * SPEC 4.1 duplicate-member detection over already-valid JSON text.
 * Key comparison is semantic (after escape decoding), so "a" and "a"
 * collide. Same algorithm as ebp.el's scanner.
 */
fun hasDuplicateMembers(text: String): Boolean {
    var i = 0
    val n = text.length
    // Object frames carry (seen keys, parse position); arrays are null markers.
    class ObjFrame { val keys = HashSet<String>(); var state = 'k' }
    val stack = ArrayDeque<ObjFrame?>()
    while (i < n) {
        when (val c = text[i]) {
            ' ', '\t', '\n', '\r' -> i++
            '{' -> { stack.addLast(ObjFrame()); i++ }
            '[' -> { stack.addLast(null); i++ }
            '}', ']' -> { stack.removeLastOrNull(); i++ }
            '"' -> {
                val end = stringTokenEnd(text, i)
                val top = stack.lastOrNull()
                if (top is ObjFrame && top.state == 'k') {
                    val key = unescapeJsonString(text.substring(i + 1, end))
                    if (!top.keys.add(key)) return true
                    top.state = ':'
                }
                i = end + 1
            }
            ':' -> { (stack.lastOrNull())?.let { if (it.state == ':') it.state = 'v' }; i++ }
            ',' -> { (stack.lastOrNull())?.let { it.state = 'k' }; i++ }
            else -> { // number / true / false / null
                while (i < n && text[i] !in charArrayOf(',', '}', ']', ' ', '\t', '\n', '\r')) i++
            }
        }
    }
    return false
}

private fun stringTokenEnd(text: String, start: Int): Int {
    var i = start + 1
    while (i < text.length && text[i] != '"') {
        i += if (text[i] == '\\') 2 else 1
    }
    if (i >= text.length) throw WireParseError("unterminated string")
    return i
}

private fun unescapeJsonString(inner: String): String {
    val out = StringBuilder(inner.length)
    var i = 0
    while (i < inner.length) {
        val c = inner[i]
        if (c != '\\') { out.append(c); i++; continue }
        when (val e = inner[i + 1]) {
            '"', '\\', '/' -> { out.append(e); i += 2 }
            'b' -> { out.append('\b'); i += 2 }
            'f' -> { out.append('\u000C'); i += 2 }
            'n' -> { out.append('\n'); i += 2 }
            'r' -> { out.append('\r'); i += 2 }
            't' -> { out.append('\t'); i += 2 }
            'u' -> {
                out.append(inner.substring(i + 2, i + 6).toInt(16).toChar())
                i += 6
            }
            else -> throw WireParseError("invalid escape")
        }
    }
    return out.toString()
}
