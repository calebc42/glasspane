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
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object ImageLoader {

    data class Limits(val maxBytes: Long, val maxDecodedBytes: Long, val maxPixels: Long)

    private const val MAX_REDIRECTS = 5
    private const val DEADLINE_MS = 15_000L
    private const val CONNECT_TIMEOUT_MS = 8_000
    private const val READ_TIMEOUT_MS = 8_000

    /** Load [url] under [limits], or null on any guard failure. Off the main
     * thread — the caller composes a placeholder while this runs. */
    suspend fun load(url: String, limits: Limits): Bitmap? = withContext(Dispatchers.IO) {
        try {
            when {
                ImageGuards.isHttps(url) -> loadHttps(url, limits)
                url.startsWith("data:", ignoreCase = true) -> loadData(url, limits)
                else -> null // SPEC 17.2: no implicit form
            }
        } catch (e: Exception) {
            null // never surface response content or a crash
        }
    }

    private fun loadData(url: String, limits: Limits): Bitmap? {
        val di = ImageGuards.parseDataImage(url, limits.maxBytes) ?: return null
        return decodeGuarded(di.bytes, limits)
    }

    private fun loadHttps(start: String, limits: Limits): Bitmap? {
        val deadline = System.currentTimeMillis() + DEADLINE_MS
        var current = start
        for (hop in 0..MAX_REDIRECTS) {
            if (System.currentTimeMillis() > deadline) return null
            if (!ImageGuards.isHttps(current)) return null
            val u = URL(current)
            // Before each connection AND after each DNS resolution: reject if
            // ANY resolved address is non-public (defeats a split-horizon
            // resolver that returns one public + one private A record).
            val addrs = runCatching { InetAddress.getAllByName(u.host) }.getOrNull()
            if (addrs.isNullOrEmpty() || addrs.any { ImageGuards.isBlockedAddress(it) }) return null

            val conn = (u.openConnection() as HttpsURLConnection).apply {
                instanceFollowRedirects = false // we follow manually, re-checking each hop
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                useCaches = false
                // No ambient cookies, credentials, client certs, or auth headers.
                setRequestProperty("Cookie", null)
                setRequestProperty("Authorization", null)
                setRequestProperty("Accept", "image/*")
            }
            try {
                conn.connect()
                val code = conn.responseCode
                if (code in 300..399) {
                    val loc = conn.getHeaderField("Location")
                    // SPEC 17.2: a redirect MUST stay https and re-run the
                    // address checks (next loop iteration does the latter).
                    if (!ImageGuards.redirectAllowed(loc)) return null
                    current = loc
                    continue
                }
                if (code != HttpURLConnection.HTTP_OK) return null
                val bytes = conn.inputStream.use { readLimited(it, limits.maxBytes) } ?: return null
                return decodeGuarded(bytes, limits)
            } finally {
                conn.disconnect()
            }
        }
        return null // exceeded the redirect budget
    }

    /** Read at most [max] bytes; null if the stream would exceed it. */
    private fun readLimited(input: InputStream, max: Long): ByteArray? {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(16 * 1024)
        var total = 0L
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            total += n
            if (total > max) return null
            out.write(buf, 0, n)
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
