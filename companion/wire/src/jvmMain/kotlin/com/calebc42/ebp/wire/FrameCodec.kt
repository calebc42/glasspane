// SPDX-License-Identifier: GPL-3.0-or-later
// EBP 2 framing, Companion side. Implements ebp/SPEC.md sections 6 and 4.1.
// The Kotlin twin of emacs/ebp.el's decoder: same error taxonomy, same
// chunk-size independence, verified by the same goldens/wire corpus.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonObject
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/** SPEC 4.5 fixed limits (contract.json `limits.fixed`). */
object WireLimits {
    const val MAX_HEADER_OCTETS = 8192
    const val MAX_BODY_OCTETS = 4_194_304
    const val MAX_JSON_DEPTH = 64
    const val MAX_NODES_PER_SNAPSHOT = 10_000
    const val MAX_CHILDREN_PER_NODE = 10_000
    const val MAX_IDENTIFIER_OCTETS = 128
    const val MAX_REQUEST_ID_OCTETS = 64
    const val MAX_METHOD_OCTETS = 128
    // SPEC 4.5 (amendment #108): node nesting depth in one document. Far
    // below max_json_depth because a node level costs ~2 JSON containers and
    // host ENCODERS cap lower than receivers accept — Emacs's json-serialize
    // stops at 50 containers with no override, so a document nested to the
    // JSON limit is unemittable by a conforming Emacs endpoint.
    const val MAX_NODE_DEPTH = 20
    // SPEC 4.5 (amendment #113): the header section a SENDER may rely on a
    // peer accepting. The 8,192 figure above is a receiver rejection
    // threshold, not a sender allowance.
    const val MAX_SEND_HEADER_OCTETS = 128
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
    // LD-21: the naive shape — reallocate-and-copy every pending byte on each
    // read, rescan for the terminator from index 0, re-parse the header until
    // the body completes — is O(n²) per frame: measured 229 ms and 1.08 GB of
    // memory traffic for ONE spec-legal 4 MiB body arriving in 8 KiB reads.
    // Emacs's discipline, both halves: carry parse state on the connection
    // (jsonrpc.el stores `expected-bytes`, so the header regexp runs once)
    // and never rescan consumed input (read_process_output's fixed buffer
    // carries over only the undecoded remainder). Indices below are absolute
    // positions in `buffer`; `offset` is the current frame's first byte.
    private var buffer = ByteArray(8192)
    private var size = 0       // valid bytes in buffer
    private var offset = 0     // consumed bytes — the current frame starts here
    private var scanned = 0    // no terminator STARTS before this index
    private var expected = -1  // declared body length, once the header parsed
    private var bodyStart = -1 // absolute index of the body's first byte

    fun feed(bytes: ByteArray): List<JsonObject> =
        mutableListOf<JsonObject>().also { feed(bytes, it::add) }

    /**
     * Deliver each complete message to CONSUMER in wire order as it is
     * decoded, then throw the taxonomy error for a bad frame. Because good
     * frames are handed off before the throw, a well-formed frame pipelined
     * ahead of a bad one in the same read is not lost — the live receiver
     * can answer the bad frame per SPEC 6.2 and keep the earlier work.
     */
    fun feed(bytes: ByteArray, consumer: (JsonObject) -> Unit) {
        append(bytes)
        while (true) {
            if (expected < 0) {
                val term = indexOfTerminator(maxOf(offset, scanned))
                if (term < 0) {
                    scanned = maxOf(offset, size - 3)
                    // SPEC 6.2: the header section may not exceed 8,192 octets.
                    if (size - offset > WireLimits.MAX_HEADER_OCTETS)
                        throw FrameClose("header section too large")
                    return
                }
                if (term - offset + 4 > WireLimits.MAX_HEADER_OCTETS)
                    throw FrameClose("header section too large")
                expected = parseHeader(
                    String(buffer, offset, term - offset, StandardCharsets.ISO_8859_1))
                bodyStart = term + 4
            }
            if (size - bodyStart < expected) return // retain partial data
            val body = buffer.copyOfRange(bodyStart, bodyStart + expected)
            offset = bodyStart + expected
            scanned = offset
            expected = -1
            bodyStart = -1
            compact()
            consumer(parseBody(body))
        }
    }

    /** SPEC 6.2: EOF mid-frame terminates the session. */
    fun finish() {
        if (size - offset > 0)
            throw FrameIncomplete("stream ended with ${size - offset} pending octets")
    }

    private fun append(bytes: ByteArray) {
        if (size + bytes.size > buffer.size)
            buffer = buffer.copyOf(maxOf(buffer.size * 2, size + bytes.size))
        System.arraycopy(bytes, 0, buffer, size, bytes.size)
        size += bytes.size
    }

    /** Reclaim consumed space between frames (never while a header/body is
     * mid-parse — `bodyStart` is absolute). */
    private fun compact() {
        if (offset == size) {
            offset = 0; size = 0; scanned = 0
        } else if (offset > 65_536) {
            System.arraycopy(buffer, offset, buffer, 0, size - offset)
            size -= offset
            scanned -= offset
            offset = 0
        }
    }

    private fun indexOfTerminator(from: Int): Int {
        val buf = buffer
        for (i in from..size - 4) {
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

    /** SPEC 6.2 + 4.1: strict UTF-8, then the strict one-pass parser (T1).
     * Grammar, duplicate members, depth <= 64, surrogate pairing, integer
     * range, and finiteness are all enforced IN-PARSE by EbpJson — the two
     * compensating full-text re-scans this method used to run are gone. */
    private fun parseBody(body: ByteArray): JsonObject {
        val text = try {
            StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(body)).toString()
        } catch (_: CharacterCodingException) {
            throw WireParseError("invalid UTF-8")
        }
        val value = EbpJson.parse(text)
        if (value !is EbpValue.EObj)
            throw InvalidRequest("top-level value is not a single message object")
        // The cast is the top-level-object check, same as before the swap:
        // `value` is already known to be an EObj, so this cannot fail.
        return EbpJson.toJsonElement(value) as JsonObject
    }
}

/** SPEC 6.1 sender: exact header syntax, octet-counted UTF-8 body. */
fun encodeFrame(jsonText: String): ByteArray {
    val body = jsonText.toByteArray(StandardCharsets.UTF_8)
    if (body.size > WireLimits.MAX_BODY_OCTETS)
        throw FrameClose("body exceeds max_frame_bytes")
    val header = "Content-Length: ${body.size}\r\n\r\n"
        .toByteArray(StandardCharsets.US_ASCII)
    // SPEC 4.5/6.1: a sender MUST NOT rely on a peer accepting a header
    // section longer than the 128-octet figure. The one mandatory line is far
    // inside it; this holds the line if a transport profile ever adds a field.
    check(header.size <= WireLimits.MAX_SEND_HEADER_OCTETS) {
        "header section exceeds max_send_header_bytes"
    }
    return header + body
}
