// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.jetpacs.core.ebpstore

import com.calebc42.ebp.wire.DurableOutboxPolicy

/**
 * Storage-only binary formats for the Jetpacs Android outbox envelope.
 *
 * AAD fields use a stable one-byte tag followed by a four-byte, big-endian
 * length and the field bytes. The domain and format version are fields too,
 * so concatenation, nullable values, and use in another crypto protocol are
 * unambiguous. Numeric values use eight-byte, big-endian encodings; enum
 * ordinals are deliberately never persisted.
 */
internal object OutboxEnvelopeFormat {
    const val ENVELOPE_VERSION: Int = 1
    const val IV_SIZE_BYTES: Int = 12
    const val TAG_SIZE_BITS: Int = 128
    const val TAG_SIZE_BYTES: Int = TAG_SIZE_BITS / 8

    private const val AAD_VERSION: Int = 1
    private const val AAD_DOMAIN = "jetpacs.ebp.outbox-payload/aad"

    fun aad(
        metadata: OutboxEnvelopeMetadata,
        payloadKeyAlias: String,
    ): ByteArray = CanonicalFields().apply {
        require(payloadKeyAlias.isNotBlank()) { "payload key alias must not be blank" }
        field(0, AAD_DOMAIN.encodeToByteArray())
        field(1, byteArrayOf(AAD_VERSION.toByte()))
        field(2, metadata.pairingId.value.encodeToByteArray())
        field(3, metadata.eventId.value.encodeToByteArray())
        field(4, metadata.queueSequence.toBigEndianBytes())
        field(5, metadata.storageGeneration.encodeToByteArray())
        field(
            6,
            when (metadata.policy) {
                DurableOutboxPolicy.QUEUE -> "queue"
                DurableOutboxPolicy.WAKE -> "wake"
            }.encodeToByteArray(),
        )
        field(7, metadata.occurredAtMs.toBigEndianBytes())
        field(8, metadata.queuedAtMs.toBigEndianBytes())
        field(9, metadata.expiresAtMs.toBigEndianBytes())
        field(10, metadata.dedupeKey.toNullableBytes())
        field(11, metadata.accountedBytes.toBigEndianBytes())
        field(12, metadata.triggerIdentity.toNullableBytes())
        field(13, payloadKeyAlias.encodeToByteArray())
    }.encode()

    fun envelope(iv: ByteArray, ciphertextAndTag: ByteArray): ByteArray {
        require(iv.size == IV_SIZE_BYTES) { "AES-GCM IV must be exactly $IV_SIZE_BYTES bytes" }
        require(ciphertextAndTag.size >= TAG_SIZE_BYTES) {
            "AES-GCM output must include a $TAG_SIZE_BITS-bit authentication tag"
        }
        return ByteArray(1 + iv.size + ciphertextAndTag.size).also { result ->
            result[0] = ENVELOPE_VERSION.toByte()
            iv.copyInto(result, destinationOffset = 1)
            ciphertextAndTag.copyInto(result, destinationOffset = 1 + iv.size)
        }
    }

    fun parse(envelope: ByteArray): ParsedEnvelope {
        require(envelope.size >= 1 + IV_SIZE_BYTES + TAG_SIZE_BYTES) {
            "Outbox payload envelope is truncated"
        }
        val version = envelope[0].toInt() and 0xff
        require(version == ENVELOPE_VERSION) {
            "Unsupported outbox payload envelope version $version"
        }
        return ParsedEnvelope(
            iv = envelope.copyOfRange(1, 1 + IV_SIZE_BYTES),
            ciphertextAndTag = envelope.copyOfRange(1 + IV_SIZE_BYTES, envelope.size),
        )
    }
}

internal data class ParsedEnvelope(
    val iv: ByteArray,
    val ciphertextAndTag: ByteArray,
)

private class CanonicalFields {
    private val encodedFields = mutableListOf<ByteArray>()
    private var encodedSize: Int = 0
    private var previousTag: Int = -1

    fun field(tag: Int, value: ByteArray) {
        require(tag in 0..255)
        require(tag > previousTag) { "Canonical AAD field tags must be strictly increasing" }
        require(value.size <= Int.MAX_VALUE - 5)
        val encoded = ByteArray(5 + value.size)
        encoded[0] = tag.toByte()
        writeIntBigEndian(value.size, encoded, 1)
        value.copyInto(encoded, destinationOffset = 5)
        require(encodedSize <= Int.MAX_VALUE - encoded.size) { "Canonical AAD is too large" }
        encodedSize += encoded.size
        encodedFields += encoded
        previousTag = tag
    }

    fun encode(): ByteArray = ByteArray(encodedSize).also { result ->
        var offset = 0
        encodedFields.forEach { field ->
            field.copyInto(result, destinationOffset = offset)
            offset += field.size
        }
    }
}

private fun String?.toNullableBytes(): ByteArray {
    if (this == null) return byteArrayOf(0)
    val encoded = encodeToByteArray()
    return ByteArray(1 + encoded.size).also { result ->
        result[0] = 1
        encoded.copyInto(result, destinationOffset = 1)
    }
}

private fun Long.toBigEndianBytes(): ByteArray = ByteArray(Long.SIZE_BYTES) { index ->
    (this ushr ((Long.SIZE_BYTES - 1 - index) * Byte.SIZE_BITS)).toByte()
}

private fun writeIntBigEndian(value: Int, destination: ByteArray, offset: Int) {
    for (index in 0 until Int.SIZE_BYTES) {
        destination[offset + index] =
            (value ushr ((Int.SIZE_BYTES - 1 - index) * Byte.SIZE_BITS)).toByte()
    }
}
