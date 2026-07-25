// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 17.2 image loader: the guarded fetch/decode behind an `image` node. It
// enforces HTTPS-only, no ambient credentials, a redirect budget, a 15s total
// deadline, the SSRF address checks (before each connection AND after every
// redirect/DNS resolution), and the three image limits — leaning on the
// JVM-tested ImageGuards for every policy decision. On any failure it returns
// null; the renderer then shows content_description or a neutral placeholder
// and never treats the response as an executable format.
package com.calebc42.ebp.companion.render

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.calebc42.ebp.wire.ImageGuards
import java.io.InputStream
import java.net.InetAddress
import java.net.URL
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

object ImageLoader {

    data class Limits(val maxBytes: Long, val maxDecodedBytes: Long, val maxPixels: Long)

    // SPEC 4.5/17.2: the single source for the three image limits — DeviceBridge
    // advertises exactly these and RenderImage enforces them, so the advertised
    // and enforced values cannot drift.
    const val MAX_IMAGE_BYTES = 8_388_608L          // 8 MiB encoded
    const val MAX_DECODED_IMAGE_BYTES = 67_108_864L // 64 MiB decoded (ARGB)
    const val MAX_IMAGE_PIXELS = 16_777_216L        // 4096x4096
    val DEFAULT_LIMITS = Limits(MAX_IMAGE_BYTES, MAX_DECODED_IMAGE_BYTES, MAX_IMAGE_PIXELS)

    private const val MAX_REDIRECTS = 5
    private const val DEADLINE_MS = 15_000L
    private const val CONNECT_TIMEOUT_MS = 8_000
    private const val READ_TIMEOUT_MS = 8_000

    /** LD-12 crash-closer: at most three concurrent fetch/decodes, so N
     * individually-legal images cannot ask for N × 64 MiB of decoded memory
     * at once (each is per-image capped; nothing bounded the sum). */
    private val gate = Semaphore(permits = 3)

    /** Load [url] under [limits], or null on any guard failure. Off the main
     * thread — the caller composes a placeholder while this runs. */
    suspend fun load(url: String, limits: Limits): Bitmap? = withContext(Dispatchers.IO) {
        gate.withPermit {
            try {
                when {
                    ImageGuards.isHttps(url) -> loadHttps(url, limits)
                    url.startsWith("data:", ignoreCase = true) -> loadData(url, limits)
                    else -> null // SPEC 17.2: no implicit form
                }
            } catch (ce: CancellationException) {
                throw ce // leaving composition cancels the load; propagate
            } catch (t: Throwable) {
                // LD-12: OutOfMemoryError is an Error — `catch (Exception)`
                // let a decode OOM escape the loader and kill the process.
                null // never surface response content or a crash
            }
        }
    }

    private fun loadData(url: String, limits: Limits): Bitmap? {
        val di = ImageGuards.parseDataImage(url, limits.maxBytes) ?: return null
        return decodeGuarded(di.bytes, limits)
    }

    /**
     * SPEC 17.2 HTTPS fetch. A manual pinned-socket client — NOT
     * HttpsURLConnection, which re-resolves DNS internally and would defeat the
     * SSRF check (a DNS-rebinding TOCTOU). We resolve once, pin the socket to a
     * VALIDATED address, and keep SNI + hostname verification for the real host.
     * The 15s total deadline is enforced on every read; the manual request
     * attaches ZERO ambient credentials (no cookies/auth/client-certs).
     */
    private fun loadHttps(start: String, limits: Limits): Bitmap? {
        val deadline = System.currentTimeMillis() + DEADLINE_MS
        var current = start
        for (hop in 0..MAX_REDIRECTS) {
            if (System.currentTimeMillis() >= deadline) return null
            if (!ImageGuards.isHttps(current)) return null
            val u = URL(current)
            val host = u.host
            val port = if (u.port == -1) 443 else u.port
            val path = (u.path.ifEmpty { "/" }) + (u.query?.let { "?$it" } ?: "")
            // Resolve ONCE and pin: fail closed if empty or any address is
            // non-public (the split-horizon defense). The socket connects to
            // exactly this address — the check and the connect cannot diverge.
            val addrs = runCatching { InetAddress.getAllByName(host) }.getOrNull() ?: return null
            val pinned = ImageGuards.firstAllowedAddress(addrs) ?: return null
            val hop = fetchOnce(pinned, host, port, path, limits, deadline) ?: return null
            when (hop) {
                is Hop.Body -> return decodeGuarded(hop.bytes, limits)
                is Hop.Redirect -> {
                    // SPEC 17.2: resolve a relative Location against the current
                    // URL, require https, and re-validate the address next loop.
                    val next = runCatching { URL(u, hop.location).toString() }.getOrNull() ?: return null
                    if (!ImageGuards.isHttps(next)) return null
                    current = next
                }
            }
        }
        return null // exceeded the redirect budget
    }

    private sealed interface Hop {
        class Body(val bytes: ByteArray) : Hop
        class Redirect(val location: String) : Hop
    }

    /** One HTTPS request against a PINNED address, host used only for SNI +
     * cert hostname verification. Returns a body (200) or a redirect (3xx);
     * null on any failure. Enforces [deadline] on every blocking read. */
    private fun fetchOnce(
        pinned: InetAddress, host: String, port: Int, path: String,
        limits: Limits, deadline: Long,
    ): Hop? {
        fun remaining() = (deadline - System.currentTimeMillis()).toInt()
        if (remaining() <= 0) return null
        val raw = java.net.Socket()
        try {
            raw.connect(java.net.InetSocketAddress(pinned, port),
                minOf(CONNECT_TIMEOUT_MS, remaining()))
            val ssl = (javax.net.ssl.SSLSocketFactory.getDefault() as javax.net.ssl.SSLSocketFactory)
                .createSocket(raw, host, port, true) as javax.net.ssl.SSLSocket
            // SNI = the real host; "HTTPS" endpoint identification makes the
            // handshake verify the cert against `host` (not the pinned IP).
            ssl.sslParameters = ssl.sslParameters.apply {
                serverNames = listOf(javax.net.ssl.SNIHostName(host))
                endpointIdentificationAlgorithm = "HTTPS"
            }
            ssl.use { s ->
                s.soTimeout = minOf(READ_TIMEOUT_MS, remaining().coerceAtLeast(1))
                s.startHandshake()
                // Minimal request; Connection: close ends the body at EOF. No
                // Cookie/Authorization/ambient anything.
                val req = "GET $path HTTP/1.1\r\nHost: $host\r\n" +
                    "Accept: image/*\r\nConnection: close\r\nUser-Agent: ebp-companion\r\n\r\n"
                s.outputStream.write(req.toByteArray(Charsets.US_ASCII))
                s.outputStream.flush()
                val input = s.inputStream
                val (code, headers) = readStatusAndHeaders(input, deadline) ?: return null
                if (code in 300..399) {
                    val loc = headers["location"] ?: return null
                    return Hop.Redirect(loc)
                }
                if (code != 200) return null
                s.soTimeout = minOf(READ_TIMEOUT_MS, remaining().coerceAtLeast(1))
                val body = if (headers["transfer-encoding"]?.contains("chunked", true) == true)
                    readChunked(input, limits.maxBytes, deadline)
                else readToLimit(input, limits.maxBytes, deadline,
                    headers["content-length"]?.toLongOrNull())
                return body?.let { Hop.Body(it) }
            }
        } catch (e: Exception) {
            return null
        } finally {
            runCatching { raw.close() }
        }
    }

    /** Read the status line + headers up to the blank line. Returns (code, lower-
     * cased header map); null on malformed input or deadline. */
    private fun readStatusAndHeaders(input: InputStream, deadline: Long): Pair<Int, Map<String, String>>? {
        val statusLine = readLine(input, deadline) ?: return null
        // "HTTP/1.1 200 OK"
        val parts = statusLine.split(' ', limit = 3)
        val code = parts.getOrNull(1)?.toIntOrNull() ?: return null
        val headers = HashMap<String, String>()
        while (true) {
            if (System.currentTimeMillis() >= deadline) return null
            val line = readLine(input, deadline) ?: return null
            if (line.isEmpty()) break
            val c = line.indexOf(':')
            if (c > 0) headers[line.substring(0, c).trim().lowercase()] = line.substring(c + 1).trim()
        }
        return code to headers
    }

    /** Read one CRLF-terminated line (header line cap 8 KiB). */
    private fun readLine(input: InputStream, deadline: Long): String? {
        val sb = StringBuilder()
        while (true) {
            if (System.currentTimeMillis() >= deadline) return null
            val b = input.read()
            if (b < 0) return if (sb.isEmpty()) null else sb.toString()
            if (b == '\n'.code) return sb.removeSuffix("\r").toString()
            sb.append(b.toChar())
            if (sb.length > 8192) return null // runaway header line
        }
    }

    private fun StringBuilder.removeSuffix(s: String): StringBuilder {
        if (endsWith(s)) setLength(length - s.length)
        return this
    }

    /** Read to EOF or [contentLength], capped at [max]; deadline on every read. */
    private fun readToLimit(input: InputStream, max: Long, deadline: Long, contentLength: Long?): ByteArray? {
        if (contentLength != null && contentLength > max) return null
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(16 * 1024)
        var total = 0L
        while (true) {
            if (System.currentTimeMillis() >= deadline) return null
            val n = try { input.read(buf) } catch (e: java.net.SocketTimeoutException) { return null }
            if (n < 0) break
            total += n
            if (total > max) return null
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    /** Decode HTTP chunked transfer-encoding, capped at [max]; deadline-checked. */
    private fun readChunked(input: InputStream, max: Long, deadline: Long): ByteArray? {
        val out = java.io.ByteArrayOutputStream()
        var total = 0L
        while (true) {
            if (System.currentTimeMillis() >= deadline) return null
            val sizeLine = readLine(input, deadline) ?: return null
            val size = sizeLine.substringBefore(';').trim().toIntOrNull(16) ?: return null
            if (size == 0) break // last chunk
            total += size
            if (total > max) return null
            val chunk = ByteArray(size)
            var off = 0
            while (off < size) {
                if (System.currentTimeMillis() >= deadline) return null
                val n = try { input.read(chunk, off, size - off) } catch (e: java.net.SocketTimeoutException) { return null }
                if (n < 0) return null
                off += n
            }
            out.write(chunk)
            readLine(input, deadline) // trailing CRLF after the chunk data
        }
        return out.toByteArray()
    }

    /** Bounds-decode to enforce the pixel + decoded-byte limits before the full
     * decode; reject an undecodable or over-limit image. */
    private fun decodeGuarded(bytes: ByteArray, limits: Limits): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val w = bounds.outWidth
        val h = bounds.outHeight
        if (w <= 0 || h <= 0) return null // not a decodable raster
        val pixels = w.toLong() * h.toLong()
        if (pixels > limits.maxPixels) return null
        if (pixels * 4 > limits.maxDecodedBytes) return null // ARGB_8888
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }
}
