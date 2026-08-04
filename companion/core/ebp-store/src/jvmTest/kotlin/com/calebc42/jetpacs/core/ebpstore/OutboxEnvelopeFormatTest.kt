// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.jetpacs.core.ebpstore

import com.calebc42.ebp.wire.DurableOutboxPolicy
import com.calebc42.ebp.wire.EventId
import com.calebc42.ebp.wire.PairingId
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class OutboxEnvelopeFormatTest {
    @Test
    fun aadIsDeterministicTaggedLengthPrefixedAndDomainSeparated() {
        val first = OutboxEnvelopeFormat.aad(metadata(), PAYLOAD_ALIAS)
        val second = OutboxEnvelopeFormat.aad(metadata(), PAYLOAD_ALIAS)

        assertArrayEquals(first, second)
        val fields = decodeFields(first)
        assertEquals((0..13).toList(), fields.map { it.first })
        assertEquals("jetpacs.ebp.outbox-payload/aad", fields[0].second.decodeToString())
        assertArrayEquals(byteArrayOf(1), fields[1].second)
        assertEquals("00000000000000000000000000000001", fields[2].second.decodeToString())
        assertEquals("00000000000000000000000000000002", fields[3].second.decodeToString())
        assertEquals("queue", fields[6].second.decodeToString())
        assertArrayEquals(byteArrayOf(0), fields[10].second)
        assertArrayEquals(byteArrayOf(0), fields[12].second)
        assertEquals(PAYLOAD_ALIAS, fields[13].second.decodeToString())
    }

    @Test
    fun everyImmutableMetadataFieldChangesAad() {
        val base = metadata()
        val baseAad = OutboxEnvelopeFormat.aad(base, PAYLOAD_ALIAS)
        val variants = listOf(
            base.copy(pairingId = PairingId("10000000000000000000000000000001")),
            base.copy(eventId = EventId("20000000000000000000000000000002")),
            base.copy(queueSequence = 8),
            base.copy(storageGeneration = "30000000000000000000000000000003"),
            base.copy(policy = DurableOutboxPolicy.WAKE),
            base.copy(occurredAtMs = 99),
            base.copy(queuedAtMs = 102),
            base.copy(expiresAtMs = 104),
            base.copy(dedupeKey = "dedupe"),
            base.copy(accountedBytes = 513),
            base.copy(triggerIdentity = "trigger-1"),
        )

        variants.forEach { variant ->
            assertFalse(baseAad.contentEquals(OutboxEnvelopeFormat.aad(variant, PAYLOAD_ALIAS)))
        }
        assertFalse(baseAad.contentEquals(OutboxEnvelopeFormat.aad(base, "another-payload-key")))
    }

    @Test
    fun envelopeRoundTripsVersionIvAndAuthenticatedBytes() {
        val iv = ByteArray(OutboxEnvelopeFormat.IV_SIZE_BYTES) { it.toByte() }
        val ciphertextAndTag =
            ByteArray(OutboxEnvelopeFormat.TAG_SIZE_BYTES + 5) { (it + 20).toByte() }

        val encoded = OutboxEnvelopeFormat.envelope(iv, ciphertextAndTag)
        val parsed = OutboxEnvelopeFormat.parse(encoded)

        assertEquals(OutboxEnvelopeFormat.ENVELOPE_VERSION, encoded[0].toInt())
        assertArrayEquals(iv, parsed.iv)
        assertArrayEquals(ciphertextAndTag, parsed.ciphertextAndTag)
    }

    @Test
    fun envelopeRejectsWrongIvShortTagTruncationAndUnknownVersion() {
        assertThrows(IllegalArgumentException::class.java) {
            OutboxEnvelopeFormat.envelope(
                ByteArray(OutboxEnvelopeFormat.IV_SIZE_BYTES - 1),
                ByteArray(OutboxEnvelopeFormat.TAG_SIZE_BYTES),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            OutboxEnvelopeFormat.envelope(
                ByteArray(OutboxEnvelopeFormat.IV_SIZE_BYTES),
                ByteArray(OutboxEnvelopeFormat.TAG_SIZE_BYTES - 1),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            OutboxEnvelopeFormat.parse(ByteArray(4))
        }
        val unknownVersion = OutboxEnvelopeFormat.envelope(
            ByteArray(OutboxEnvelopeFormat.IV_SIZE_BYTES),
            ByteArray(OutboxEnvelopeFormat.TAG_SIZE_BYTES),
        ).also { it[0] = 99 }
        assertThrows(IllegalArgumentException::class.java) {
            OutboxEnvelopeFormat.parse(unknownVersion)
        }
    }

    private fun metadata() = OutboxEnvelopeMetadata(
        pairingId = PairingId("00000000000000000000000000000001"),
        eventId = EventId("00000000000000000000000000000002"),
        queueSequence = 7,
        storageGeneration = "00000000000000000000000000000003",
        policy = DurableOutboxPolicy.QUEUE,
        occurredAtMs = 100,
        queuedAtMs = 101,
        expiresAtMs = 103,
        dedupeKey = null,
        accountedBytes = 512,
        triggerIdentity = null,
    )

    private fun decodeFields(encoded: ByteArray): List<Pair<Int, ByteArray>> {
        val result = mutableListOf<Pair<Int, ByteArray>>()
        var offset = 0
        while (offset < encoded.size) {
            val tag = encoded[offset].toInt() and 0xff
            val length = readIntBigEndian(encoded, offset + 1)
            val valueStart = offset + 5
            val valueEnd = valueStart + length
            require(valueEnd <= encoded.size)
            result += tag to encoded.copyOfRange(valueStart, valueEnd)
            offset = valueEnd
        }
        return result
    }

    private fun readIntBigEndian(bytes: ByteArray, offset: Int): Int {
        var result = 0
        repeat(Int.SIZE_BYTES) { index ->
            result = (result shl Byte.SIZE_BITS) or (bytes[offset + index].toInt() and 0xff)
        }
        return result
    }

    private companion object {
        const val PAYLOAD_ALIAS = "jetpacs.test.payload-key.v1"
    }
}
