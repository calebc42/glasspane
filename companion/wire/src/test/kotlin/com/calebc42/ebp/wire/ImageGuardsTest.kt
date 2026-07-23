// SPDX-License-Identifier: GPL-3.0-or-later
// W9-j SPEC 17.2 image guards: SSRF destination classification, base64
// data:image validation (media type + size + active-format rejection), and the
// redirect-scheme rule — the pure predicates behind the loader.
package com.calebc42.ebp.wire

import java.net.InetAddress
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageGuardsTest {

    private fun blocked(ip: String) = ImageGuards.isBlockedAddress(InetAddress.getByName(ip))

    @Test
    fun blocksLoopbackPrivateLinkLocalMulticastAndReserved() {
        // Loopback, unspecified, private, CGNAT, link-local, multicast, TEST-NET,
        // reserved — every non-public class the SPEC names.
        for (ip in listOf(
            "127.0.0.1", "127.1.2.3", "0.0.0.0", "10.0.0.5", "172.16.9.9",
            "192.168.1.10", "100.64.0.1", "169.254.1.1", "224.0.0.1",
            "192.0.2.5", "198.51.100.7", "203.0.113.9", "198.18.0.1",
            "240.0.0.1", "255.255.255.255", "::1", "fc00::1", "fe80::1", "ff02::1"))
            assertTrue("$ip should be blocked", blocked(ip))
    }

    @Test
    fun allowsGenuinePublicAddresses() {
        for (ip in listOf("8.8.8.8", "1.1.1.1", "93.184.216.34", "2606:4700:4700::1111"))
            assertFalse("$ip should be allowed", blocked(ip))
    }

    @Test
    fun parseDataImageAcceptsSupportedRasterAndRejectsTheRest() {
        // 1x1 transparent PNG.
        val png = "data:image/png;base64," +
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        val ok = ImageGuards.parseDataImage(png, maxBytes = 4096)
        assertNotNull(ok)
        assertTrue(ok!!.mediaType == "image/png" && ok.bytes.size > 8)
        // SVG is an active format — rejected before any decode.
        assertNull(ImageGuards.parseDataImage("data:image/svg+xml;base64,PHN2Zy8+", 4096))
        // Non-image media type, non-base64, and malformed all reject.
        assertNull(ImageGuards.parseDataImage("data:text/plain;base64,aGk=", 4096))
        assertNull(ImageGuards.parseDataImage("data:image/png,notbase64", 4096))
        assertNull(ImageGuards.parseDataImage("data:image/png;base64,***", 4096))
    }

    @Test
    fun parseDataImageEnforcesTheDecodedByteLimit() {
        val png = "data:image/png;base64," +
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        // A tiny cap rejects the payload.
        assertNull(ImageGuards.parseDataImage(png, maxBytes = 8))
    }

    @Test
    fun redirectMustStayHttps() {
        assertTrue(ImageGuards.redirectAllowed("https://cdn.example.com/x.png"))
        assertFalse(ImageGuards.redirectAllowed("http://example.com/x.png"))
        assertFalse(ImageGuards.redirectAllowed("file:///etc/passwd"))
        assertFalse(ImageGuards.redirectAllowed("gopher://x"))
        assertFalse(ImageGuards.redirectAllowed(null))
    }

    @Test
    fun isValidImageUrlGatesFormAtContentLevel() {
        assertTrue(ImageGuards.isValidImageUrl("https://example.com/a.png"))
        assertTrue(ImageGuards.isValidImageUrl("data:image/jpeg;base64,/9j/4AAQ"))
        assertFalse(ImageGuards.isValidImageUrl("http://example.com/a.png"))
        assertFalse(ImageGuards.isValidImageUrl("file:///etc/passwd"))
        assertFalse(ImageGuards.isValidImageUrl("data:image/svg+xml;base64,PHN2Zy8+"))
        assertFalse(ImageGuards.isValidImageUrl("data:text/html;base64,PGgxPg=="))
    }
}
