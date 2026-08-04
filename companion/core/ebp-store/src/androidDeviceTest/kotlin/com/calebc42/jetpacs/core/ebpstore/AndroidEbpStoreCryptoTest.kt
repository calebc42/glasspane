// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.jetpacs.core.ebpstore

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.calebc42.ebp.wire.DurableOutboxPolicy
import com.calebc42.ebp.wire.EventId
import com.calebc42.ebp.wire.PairingId
import java.security.KeyStore
import java.security.SecureRandom
import java.util.Locale
import javax.crypto.AEADBadTagException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidEbpStoreCryptoTest {
    private val aliasesToDelete = mutableSetOf<String>()

    @After
    fun deleteTestKeys() {
        val keyStore = androidKeyStore()
        aliasesToDelete.forEach { alias ->
            if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
        }
    }

    @Test
    fun aliasPolicyIsPureDistinctVersionedAndNotAProvisionedResolver() {
        val pairing = randomPairingId()
        val policy = VersionedAndroidPairingAliasPolicy
        val aliases = track(policy.aliasesFor(pairing))
        val keyStore = androidKeyStore()
        assertFalse(keyStore.containsAlias(aliases.credentialKeyAlias))
        assertFalse(keyStore.containsAlias(aliases.payloadKeyAlias))

        val resolvedAgain = policy.aliasesFor(pairing)

        assertEquals(aliases, resolvedAgain)
        assertNotEquals(aliases.credentialKeyAlias, aliases.payloadKeyAlias)
        assertTrue(aliases.credentialKeyAlias.contains(".v1."))
        assertTrue(aliases.payloadKeyAlias.contains(".v1."))
        assertFalse(
            ProvisionedPairingAliasResolver::class.java.isAssignableFrom(policy.javaClass),
        )
        assertFalse(keyStore.containsAlias(aliases.credentialKeyAlias))
        assertFalse(keyStore.containsAlias(aliases.payloadKeyAlias))
    }

    @Test
    fun payloadProvisioningIsIdempotentAndDoesNotCreateCredentialKey() = runTest {
        val pairing = randomPairingId()
        val aliases = track(VersionedAndroidPairingAliasPolicy.aliasesFor(pairing))
        val provisioner = AndroidKeyStorePayloadKeyProvisioner()
        val first = provisioner.ensureKey(pairing)
        assertEquals(pairing, first.pairingId)
        assertEquals(aliases.payloadKeyAlias, first.alias)
        assertTrue(androidKeyStore().containsAlias(first.alias))
        assertFalse(androidKeyStore().containsAlias(aliases.credentialKeyAlias))
        val codec = AndroidKeyStoreOutboxPayloadEnvelopeCodec()
        val payload = authoritativePayload()
        val metadata = metadata(pairing)
        val sealedBeforeRepeat = codec.encode(payload, metadata, first.alias)

        val second = provisioner.ensureKey(pairing)

        assertEquals(first, second)
        assertEquals(payload, codec.decode(sealedBeforeRepeat, metadata, second.alias))
        assertFalse(androidKeyStore().containsAlias(aliases.credentialKeyAlias))
    }

    @Test
    fun codecRoundTripsAndProviderUsesFreshTwelveByteIvs() = runTest {
        val pairing = randomPairingId()
        val aliases = track(VersionedAndroidPairingAliasPolicy.aliasesFor(pairing))
        val payloadKey = AndroidKeyStorePayloadKeyProvisioner().ensureKey(pairing)
        val codec = AndroidKeyStoreOutboxPayloadEnvelopeCodec()
        val payload = authoritativePayload(extraField = true)
        val metadata = metadata(pairing)

        val first = codec.encode(payload, metadata, payloadKey.alias)
        val second = codec.encode(payload, metadata, payloadKey.alias)
        val firstParsed = OutboxEnvelopeFormat.parse(first)
        val secondParsed = OutboxEnvelopeFormat.parse(second)

        assertEquals(aliases.payloadKeyAlias, payloadKey.alias)
        assertEquals(OutboxEnvelopeFormat.ENVELOPE_VERSION, first[0].toInt())
        assertEquals(OutboxEnvelopeFormat.IV_SIZE_BYTES, firstParsed.iv.size)
        assertEquals(OutboxEnvelopeFormat.IV_SIZE_BYTES, secondParsed.iv.size)
        assertFalse(firstParsed.iv.contentEquals(secondParsed.iv))
        assertEquals(payload, codec.decode(first, metadata, payloadKey.alias))
        assertEquals(payload, codec.decode(second, metadata, payloadKey.alias))
    }

    @Test
    fun codecRejectsIvCiphertextTagAndAadTampering() = runTest {
        val pairing = randomPairingId()
        track(VersionedAndroidPairingAliasPolicy.aliasesFor(pairing))
        val payloadKey = AndroidKeyStorePayloadKeyProvisioner().ensureKey(pairing)
        val codec = AndroidKeyStoreOutboxPayloadEnvelopeCodec()
        val metadata = metadata(pairing)
        val envelope = codec.encode(authoritativePayload(), metadata, payloadKey.alias)

        val ivTampered = envelope.copyOf().also { it[1] = it[1] xor 1 }
        val ciphertextTampered = envelope.copyOf().also {
            val ciphertextOffset = 1 + OutboxEnvelopeFormat.IV_SIZE_BYTES
            it[ciphertextOffset] = it[ciphertextOffset] xor 1
        }
        val tagTampered = envelope.copyOf().also {
            it[it.lastIndex] = it[it.lastIndex] xor 1
        }

        assertSuspendFails<AEADBadTagException> {
            codec.decode(ivTampered, metadata, payloadKey.alias)
        }
        assertSuspendFails<AEADBadTagException> {
            codec.decode(ciphertextTampered, metadata, payloadKey.alias)
        }
        assertSuspendFails<AEADBadTagException> {
            codec.decode(tagTampered, metadata, payloadKey.alias)
        }
        assertSuspendFails<AEADBadTagException> {
            codec.decode(
                envelope,
                metadata.copy(accountedBytes = metadata.accountedBytes + 1),
                payloadKey.alias,
            )
        }
    }

    @Test
    fun codecRejectsWrongAndDeletedAliases() = runTest {
        val pairing = randomPairingId()
        val otherPairing = randomPairingId()
        track(VersionedAndroidPairingAliasPolicy.aliasesFor(pairing))
        track(VersionedAndroidPairingAliasPolicy.aliasesFor(otherPairing))
        val payloadKey = AndroidKeyStorePayloadKeyProvisioner().ensureKey(pairing)
        val otherKey = AndroidKeyStorePayloadKeyProvisioner().ensureKey(otherPairing)
        val codec = AndroidKeyStoreOutboxPayloadEnvelopeCodec()
        val metadata = metadata(pairing)
        val envelope = codec.encode(authoritativePayload(), metadata, payloadKey.alias)

        assertSuspendFails<AEADBadTagException> {
            codec.decode(envelope, metadata, otherKey.alias)
        }
        androidKeyStore().deleteEntry(payloadKey.alias)
        assertSuspendFails<IllegalStateException> {
            codec.decode(envelope, metadata, payloadKey.alias)
        }
    }

    @Test
    fun envelopeRejectsUnknownVersionAndTruncationOnDevice() {
        val valid = OutboxEnvelopeFormat.envelope(
            iv = ByteArray(OutboxEnvelopeFormat.IV_SIZE_BYTES),
            ciphertextAndTag = ByteArray(OutboxEnvelopeFormat.TAG_SIZE_BYTES),
        )
        val unknown = valid.copyOf().also { it[0] = 99 }

        assertThrows(IllegalArgumentException::class.java) {
            OutboxEnvelopeFormat.parse(unknown)
        }
        assertThrows(IllegalArgumentException::class.java) {
            OutboxEnvelopeFormat.parse(valid.copyOf(valid.size - 1 - OutboxEnvelopeFormat.TAG_SIZE_BYTES))
        }
    }

    @Test
    fun generationsAreLowercase128BitAndFresh() = runTest {
        val source = SecureRandomStorageGenerationSource()
        val first = source.next()
        val second = source.next()

        assertTrue(Regex("[0-9a-f]{32}").matches(first))
        assertTrue(Regex("[0-9a-f]{32}").matches(second))
        assertNotEquals(first, second)
    }

    private fun authoritativePayload(extraField: Boolean = false) = buildJsonObject {
        put("event_id", "00000000000000000000000000000002")
        put("occurred_at_ms", 100)
        put("queued_at_ms", 101)
        if (extraField) put("answer", 42)
    }

    private fun metadata(pairingId: PairingId) = OutboxEnvelopeMetadata(
        pairingId = pairingId,
        eventId = EventId("00000000000000000000000000000002"),
        queueSequence = 1,
        storageGeneration = "00000000000000000000000000000003",
        policy = DurableOutboxPolicy.QUEUE,
        occurredAtMs = 100,
        queuedAtMs = 101,
        expiresAtMs = 1_000,
        dedupeKey = null,
        accountedBytes = 256,
        triggerIdentity = null,
    )

    private fun track(aliases: AndroidPairingKeyAliases): AndroidPairingKeyAliases {
        aliasesToDelete += aliases.credentialKeyAlias
        aliasesToDelete += aliases.payloadKeyAlias
        return aliases
    }

    private fun androidKeyStore(): KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun randomPairingId(): PairingId = PairingId(
        ByteArray(16).also(SecureRandom()::nextBytes).joinToString("") { byte ->
            String.format(Locale.ROOT, "%02x", byte.toInt() and 0xff)
        },
    )

    private suspend inline fun <reified T : Throwable> assertSuspendFails(
        crossinline operation: suspend () -> Unit,
    ) {
        try {
            operation()
            fail("Expected " + T::class.java.name)
        } catch (failure: Throwable) {
            if (failure !is T) throw failure
        }
    }

    private infix fun Byte.xor(mask: Int): Byte = (toInt() xor mask).toByte()
}
