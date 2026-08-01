// SPDX-License-Identifier: GPL-3.0-or-later
// W9-j SPEC 17.2 image guards: SSRF destination classification, base64
// data:image validation (media type + size + active-format rejection), and the
// redirect-scheme rule — the pure predicates behind the loader.
package com.calebc42.ebp.wire

import java.io.File
import java.net.InetAddress
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
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
    fun blocksIPv4MappedAndNat64EmbeddingPrivateV4() {
        // ::ffff:169.254.169.254 (IPv4-mapped cloud-metadata) and ::ffff:10.0.0.5.
        assertTrue(blocked("::ffff:169.254.169.254"))
        assertTrue(blocked("::ffff:10.0.0.5"))
        // 64:ff9b::/96 NAT64 embedding a private/loopback v4 must be blocked.
        assertTrue(blocked("64:ff9b::a00:5"))       // -> 10.0.0.5
        assertTrue(blocked("64:ff9b::7f00:1"))      // -> 127.0.0.1
        // NAT64 embedding a genuinely public v4 is allowed.
        assertFalse(blocked("64:ff9b::808:808"))    // -> 8.8.8.8
    }

    @Test
    fun firstAllowedAddressFailsClosedOnAnyBlockedMember() {
        val pub = InetAddress.getByName("8.8.8.8")
        val priv = InetAddress.getByName("10.0.0.5")
        // A clean public set returns the first address.
        assertEquals(pub, ImageGuards.firstAllowedAddress(arrayOf(pub)))
        // Split-horizon (one public + one private) fails CLOSED.
        assertNull(ImageGuards.firstAllowedAddress(arrayOf(pub, priv)))
        assertNull(ImageGuards.firstAllowedAddress(arrayOf<InetAddress>()))
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

    @Test
    fun base64ProfileIsTheContractsAndIsNeverSanitized() {
        // SPEC 17.2 (amendment #114) pins the encoding in
        // contract.limits.image_data_encoding: standard RFC 4648 alphabet,
        // padding required, whitespace forbidden.
        val contract = Json.parseToJsonElement(
            File(System.getProperty("ebp.dir")
                ?: error("ebp.dir system property not set"), "contract.json")
                .readText()) as JsonObject
        val enc = contract.reqObj("image_data_encoding")
        assertEquals("rfc4648-standard", enc.reqString("alphabet"))
        assertEquals("required", enc.reqString("padding"))
        assertEquals("forbidden", enc.reqString("whitespace"))

        assertTrue(ImageGuards.isStrictBase64("aGVsbG8h"))     // 8 chars, no pad
        assertTrue(ImageGuards.isStrictBase64("aGk="))          // one pad char
        assertTrue(ImageGuards.isStrictBase64("YQ=="))          // two pad chars
        // Padding is REQUIRED: java.util.Base64's basic decoder would take
        // this happily, which is exactly why the profile is checked first.
        assertFalse(ImageGuards.isStrictBase64("YQ"))
        assertFalse(ImageGuards.isStrictBase64("aGk"))
        // base64url is a different alphabet, not a tolerated variant.
        assertFalse(ImageGuards.isStrictBase64("a-b_cdef"))
        // Whitespace anywhere is a rejection, never something to strip:
        // leading, trailing, interior, and the 76-column wrap that Emacs's
        // `base64-encode-string' emits unless its NO-LINE-BREAK arg is set.
        assertFalse(ImageGuards.isStrictBase64(" aGVsbG8h"))
        assertFalse(ImageGuards.isStrictBase64("aGVsbG8h "))
        assertFalse(ImageGuards.isStrictBase64("aGVs bG8h"))
        assertFalse(ImageGuards.isStrictBase64("aGVs\nbG8h"))
        assertFalse(ImageGuards.isStrictBase64("aGVsbG8h\n"))
        assertFalse(ImageGuards.isStrictBase64(""))
        assertFalse(ImageGuards.isStrictBase64("===="))
        // '=' outside the final quantum is not padding.
        assertFalse(ImageGuards.isStrictBase64("aG=k"))
    }

    @Test
    fun dataUrlWhitespaceIsRejectedNotTrimmed() {
        // The decoder used to call .trim(), so a payload with surrounding
        // whitespace decoded to bytes the sender never authorized and the
        // accepted length differed from the transmitted one — SPEC 17.2's
        // "MUST NOT strip or normalize whitespace in place of rejection".
        val body =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        assertNotNull(ImageGuards.parseDataImage("data:image/png;base64,$body", 4096))
        assertNull(ImageGuards.parseDataImage("data:image/png;base64, $body", 4096))
        assertNull(ImageGuards.parseDataImage("data:image/png;base64,$body\n", 4096))
        assertNull(ImageGuards.parseDataImage(
            "data:image/png;base64," + body.chunked(76).joinToString("\n"), 4096))
    }

    @Test
    fun acceptTimeGateInspectsThePayloadNotJustTheHeader() {
        // SPEC 17.2: the payload is part of the URI form, so a data: URL that
        // could never decode is content-invalid at surface.update — not a
        // silent blank at render time, after Emacs was told "applied" and the
        // revision floor advanced past a spec that does not work.
        assertTrue(ImageGuards.isValidImageUrl("data:image/png;base64,iVBORw0K"))
        assertFalse(ImageGuards.isValidImageUrl("data:image/png;base64,***"))
        assertFalse(ImageGuards.isValidImageUrl("data:image/png;base64,"))
        assertFalse(ImageGuards.isValidImageUrl("data:image/png;base64,iVBO Rw0K"))
        assertFalse(ImageGuards.isValidImageUrl("data:image/png;base64,iVBORw0"))

        // And it lands as ContentInvalid through the validator, at the path.
        val spec = Json.parseToJsonElement(
            """{"t":"image","url":"data:image/png;base64,**"}""")
        val err = try {
            SpecValidator.validateSurfaceSpec(spec); null
        } catch (e: ContentInvalid) { e }
        assertNotNull(err)
        assertEquals("spec.url", err!!.path)
    }
}
