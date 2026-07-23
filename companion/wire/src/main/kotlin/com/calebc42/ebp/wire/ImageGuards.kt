// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 17.2 image guard predicates: the pure, JVM-testable core of the loader's
// SSRF and data-URL defenses. The app-layer loader (ImageLoader) does the
// network/decode I/O; every policy decision it makes routes through here so the
// rules can be exercised without a socket. poc-v1 used a bare image library
// with NONE of this — the whole stack is new.
package com.calebc42.ebp.wire

import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress

object ImageGuards {

    /** SPEC 17.2 `image.data`: the raster media types the Companion decodes.
     * SVG and any active/scriptable format are deliberately excluded. */
    val SUPPORTED_MEDIA_TYPES = setOf(
        "image/png", "image/jpeg", "image/gif", "image/webp",
        "image/bmp", "image/heic", "image/heif")

    /**
     * SPEC 17.2: reject loopback, private, link-local, multicast, unspecified,
     * and every other non-public destination — checked before each connection
     * AND after every redirect/DNS resolution. Returns true when [addr] MUST be
     * rejected. Covers the InetAddress-classified ranges plus IPv4 CGNAT/
     * reserved/TEST-NET and IPv6 ULA that the stock predicates miss.
     */
    fun isBlockedAddress(addr: InetAddress): Boolean {
        if (addr.isLoopbackAddress || addr.isAnyLocalAddress ||
            addr.isLinkLocalAddress || addr.isMulticastAddress ||
            addr.isSiteLocalAddress) return true
        val b = addr.address
        when (addr) {
            is Inet4Address -> if (isBlockedV4(b)) return true
            is Inet6Address -> {
                if ((b[0].toInt() and 0xFE) == 0xFC) return true // fc00::/7 ULA
                if (addr.isIPv4CompatibleAddress) return true    // ::/96 compat
                // ::ffff:a.b.c.d IPv4-mapped: some resolvers hand back an
                // Inet6Address; re-check the embedded IPv4 explicitly rather
                // than relying on JVM normalization to Inet4Address.
                if (isV4Mapped(b) && isBlockedV4(b.copyOfRange(12, 16))) return true
                // 64:ff9b::/96 NAT64 (RFC 6052): the last 32 bits embed an IPv4
                // that the far side translates to — re-check it, so a NAT64
                // literal can't smuggle a private/loopback v4 destination.
                if (isNat64(b) && isBlockedV4(b.copyOfRange(12, 16))) return true
            }
        }
        return false
    }

    private fun isBlockedV4(b: ByteArray): Boolean {
        val o0 = b[0].toInt() and 0xFF
        val o1 = b[1].toInt() and 0xFF
        if (o0 == 0) return true                        // 0.0.0.0/8
        if (o0 == 10) return true                        // 10/8 (isSiteLocal misses a raw v4 here)
        if (o0 == 127) return true                       // 127/8 loopback
        if (o0 == 100 && o1 in 64..127) return true      // 100.64/10 CGNAT
        if (o0 == 169 && o1 == 254) return true          // 169.254/16 link-local
        if (o0 == 172 && o1 in 16..31) return true       // 172.16/12 private
        if (o0 == 192 && o1 == 168) return true          // 192.168/16 private
        if (o0 == 192 && o1 == 0) return true            // 192.0.0/24 + TEST-NET-1
        if (o0 == 198 && (o1 == 18 || o1 == 19)) return true // 198.18/15 bench
        if (o0 == 198 && o1 == 51) return true           // 198.51.100/24 TEST-NET-2
        if (o0 == 203 && o1 == 0) return true            // 203.0.113/24 TEST-NET-3
        if (o0 >= 224) return true                        // 224/4 multicast + 240/4 reserved + broadcast
        return false
    }

    private fun isV4Mapped(b: ByteArray): Boolean =
        b.size == 16 && (0..9).all { b[it].toInt() == 0 } &&
            (b[10].toInt() and 0xFF) == 0xFF && (b[11].toInt() and 0xFF) == 0xFF

    private fun isNat64(b: ByteArray): Boolean =
        b.size == 16 && (b[0].toInt() and 0xFF) == 0x00 && (b[1].toInt() and 0xFF) == 0x64 &&
            (b[2].toInt() and 0xFF) == 0xFF && (b[3].toInt() and 0xFF) == 0x9B &&
            (4..11).all { b[it].toInt() == 0 }

    /** SPEC 17.2: pick a resolved address safe to connect to. Fails CLOSED —
     * returns null if the set is empty OR any address is non-public (defeats a
     * split-horizon resolver returning one public + one private A record).
     * The returned address is the exact one the caller MUST pin the socket to. */
    fun firstAllowedAddress(addrs: Array<InetAddress>): InetAddress? {
        if (addrs.isEmpty()) return null
        if (addrs.any { isBlockedAddress(it) }) return null
        return addrs.first()
    }

    /** SPEC 17.2: a redirect MUST NOT change the URI scheme away from https. */
    fun redirectAllowed(location: String?): Boolean =
        location != null && location.trim().lowercase().startsWith("https://")

    /** Whether [url] is an HTTPS URL (the only remote form). */
    fun isHttps(url: String): Boolean = url.lowercase().startsWith("https://")

    /** A validated data:image payload: its media type and decoded bytes. */
    data class DataImage(val mediaType: String, val bytes: ByteArray)

    /**
     * SPEC 17.2 `image.data`: parse and validate a base64 `data:image/...` URL.
     * Returns null unless it is `data:<supported-image-type>;base64,<b64>`, the
     * base64 decodes, and the decoded size is within [maxBytes]. The media type
     * must be one of [SUPPORTED_MEDIA_TYPES] — active/unsupported formats
     * (notably image/svg+xml) are rejected here, before any decode.
     */
    fun parseDataImage(url: String, maxBytes: Long): DataImage? {
        if (!url.startsWith("data:", ignoreCase = true)) return null
        val comma = url.indexOf(',')
        if (comma < 0) return null
        val header = url.substring(5, comma).lowercase() // after "data:"
        // Must be "<media-type>;base64" (base64 is REQUIRED; text data URLs are
        // not images). Parameters other than base64 are not accepted.
        val parts = header.split(';')
        if (parts.size != 2 || parts[1] != "base64") return null
        val mediaType = parts[0]
        if (mediaType !in SUPPORTED_MEDIA_TYPES) return null
        val b64 = url.substring(comma + 1)
        // A cheap upper bound before allocating: base64 is 4 chars per 3 bytes.
        if (b64.length.toLong() / 4 * 3 > maxBytes + 3) return null
        val bytes = try {
            java.util.Base64.getDecoder().decode(b64.trim())
        } catch (e: IllegalArgumentException) { return null }
        if (bytes.size.toLong() > maxBytes) return null
        return DataImage(mediaType, bytes)
    }

    /** SPEC 17.2: whether [url] is a valid image URI form at all — the only
     * implicit forms are none, so it MUST be https or a well-formed data:image.
     * Content-level validation (advertisement gating is a profile concern). */
    fun isValidImageUrl(url: String): Boolean {
        if (isHttps(url)) return true
        if (!url.startsWith("data:", ignoreCase = true)) return false
        val comma = url.indexOf(',')
        if (comma < 0) return false
        val header = url.substring(5, comma).lowercase()
        val parts = header.split(';')
        return parts.size == 2 && parts[1] == "base64" && parts[0] in SUPPORTED_MEDIA_TYPES
    }
}
