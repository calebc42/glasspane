// SPDX-License-Identifier: GPL-3.0-or-later
package com.calebc42.jetpacs.core.ebpstore

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import com.calebc42.ebp.wire.PairingId
import java.security.InvalidAlgorithmParameterException
import java.security.KeyStore
import java.security.ProviderException
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

private const val ANDROID_KEY_STORE = "AndroidKeyStore"
private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
private const val PAYLOAD_KEY_SIZE_BITS = 256

/**
 * Reserved Android key names, not evidence that either key was provisioned.
 */
data class AndroidPairingKeyAliases(
    val credentialKeyAlias: String,
    val payloadKeyAlias: String,
) {
    init {
        require(credentialKeyAlias.isNotBlank())
        require(payloadKeyAlias.isNotBlank())
        require(credentialKeyAlias != payloadKeyAlias)
    }
}

/** Pure naming policy: implementations must never open AndroidKeyStore. */
fun interface AndroidPairingKeyAliasPolicy {
    fun aliasesFor(pairingId: PairingId): AndroidPairingKeyAliases
}

/**
 * Stable v1, purpose-separated, per-pairing key names. This deliberately does
 * not implement [ProvisionedPairingAliasResolver]: deriving names must never
 * let Room activate a pairing whose credential is not actually provisioned.
 */
object VersionedAndroidPairingAliasPolicy : AndroidPairingKeyAliasPolicy {
    private const val NAMESPACE = "com.calebc42.jetpacs.ebp.pairing.v1"

    override fun aliasesFor(pairingId: PairingId): AndroidPairingKeyAliases =
        AndroidPairingKeyAliases(
            credentialKeyAlias =
                NAMESPACE + "." + pairingId.value + ".credential-hmac-sha256",
            payloadKeyAlias =
                NAMESPACE + "." + pairingId.value + ".payload-aes256-gcm",
        )
}

/** Proof that only the payload half of platform provisioning completed. */
data class ProvisionedAndroidPayloadKey(
    val pairingId: PairingId,
    val alias: String,
) {
    init { require(alias.isNotBlank()) }
}

/**
 * Idempotently provisions the non-exportable, pairing-local payload key.
 *
 * Credential onboarding is intentionally not guessed here. An AndroidKeyStore
 * generated HMAC key could not be exported to Emacs, while importing the real
 * shared credential requires an explicit onboarding/rotation design. Until
 * that next slice exists, callers must not treat [ensureKey] as completion of
 * the pairing credential lifecycle or store a raw credential in Room.
 */
class AndroidKeyStorePayloadKeyProvisioner(
    private val aliasPolicy: AndroidPairingKeyAliasPolicy =
        VersionedAndroidPairingAliasPolicy,
) {
    suspend fun ensureKey(pairingId: PairingId): ProvisionedAndroidPayloadKey =
        withContext(Dispatchers.IO) {
            val alias = aliasPolicy.aliasesFor(pairingId).payloadKeyAlias
            synchronized(PROVISIONING_LOCK) {
                val keyStore = loadAndroidKeyStore()
                if (!keyStore.containsAlias(alias)) {
                    try {
                        generatePayloadKey(alias)
                    } catch (failure: ProviderException) {
                        // A second app process can win between containsAlias and
                        // generateKey. Accept only an alias that now exists and
                        // passes the complete compatibility check below.
                        val reloaded = loadAndroidKeyStore()
                        if (!reloaded.containsAlias(alias)) throw failure
                    }
                }
                val key = requireCompatiblePayloadKey(loadPayloadKey(alias))
                // KeyInfo has no randomized-encryption accessor in API 36.
                requireProviderGeneratedEncryptionIv(key)
            }
            ProvisionedAndroidPayloadKey(pairingId, alias)
        }

    private companion object {
        val PROVISIONING_LOCK = Any()
    }
}

/** Production outbox payload encryption backed directly by AndroidKeyStore. */
class AndroidKeyStoreOutboxPayloadEnvelopeCodec(
    private val json: Json = Json,
) : OutboxPayloadEnvelopeCodec {
    override suspend fun encode(
        payload: JsonObject,
        metadata: OutboxEnvelopeMetadata,
        payloadKeyAlias: String,
    ): ByteArray = withContext(Dispatchers.IO) {
        val key = requireCompatiblePayloadKey(loadPayloadKey(payloadKeyAlias))
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        // No IV is supplied: the provider must generate a fresh randomized IV.
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val iv = checkNotNull(cipher.iv).copyOf()
        check(iv.size == OutboxEnvelopeFormat.IV_SIZE_BYTES) {
            "AndroidKeyStore AES-GCM provider returned a " + iv.size + "-byte IV"
        }
        cipher.updateAAD(OutboxEnvelopeFormat.aad(metadata, payloadKeyAlias))
        val plaintext = json.encodeToString(JsonObject.serializer(), payload).encodeToByteArray()
        try {
            OutboxEnvelopeFormat.envelope(iv, cipher.doFinal(plaintext))
        } finally {
            plaintext.fill(0)
        }
    }

    override suspend fun decode(
        envelope: ByteArray,
        metadata: OutboxEnvelopeMetadata,
        payloadKeyAlias: String,
    ): JsonObject = withContext(Dispatchers.IO) {
        val parsed = OutboxEnvelopeFormat.parse(envelope)
        val key = requireCompatiblePayloadKey(loadPayloadKey(payloadKeyAlias))
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(OutboxEnvelopeFormat.TAG_SIZE_BITS, parsed.iv),
        )
        cipher.updateAAD(OutboxEnvelopeFormat.aad(metadata, payloadKeyAlias))
        val plaintext = cipher.doFinal(parsed.ciphertextAndTag)
        try {
            json.decodeFromString(JsonObject.serializer(), plaintext.decodeToString())
        } finally {
            plaintext.fill(0)
        }
    }
}

/** Generates an unpredictable 128-bit lowercase-hex row generation. */
class SecureRandomStorageGenerationSource : StorageGenerationSource {
    override suspend fun next(): String = withContext(Dispatchers.IO) {
        ByteArray(16).also(PROCESS_SECURE_RANDOM::nextBytes).toLowerHex()
    }

    private companion object {
        // SecureRandom is thread safe; one process-wide instance avoids
        // needless reseeding and construction on each injected source.
        val PROCESS_SECURE_RANDOM = SecureRandom()
    }
}

private fun generatePayloadKey(alias: String) {
    require(alias.isNotBlank()) { "payload key alias must not be blank" }
    val specification = KeyGenParameterSpec.Builder(
        alias,
        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
    )
        .setKeySize(PAYLOAD_KEY_SIZE_BITS)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setRandomizedEncryptionRequired(true)
        .build()
    KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE).apply {
        init(specification)
        generateKey()
    }
}

private fun loadPayloadKey(alias: String): SecretKey {
    require(alias.isNotBlank()) { "payload key alias must not be blank" }
    val key = loadAndroidKeyStore().getKey(alias, null)
        ?: error("AndroidKeyStore payload key does not exist: " + alias)
    check(key is SecretKey) { "AndroidKeyStore alias is not a secret key: " + alias }
    return key
}

private fun requireCompatiblePayloadKey(key: SecretKey): SecretKey {
    check(key.algorithm == KeyProperties.KEY_ALGORITHM_AES) {
        "Outbox payload key must use AES"
    }
    val keyInfo = SecretKeyFactory.getInstance(key.algorithm, ANDROID_KEY_STORE)
        .getKeySpec(key, KeyInfo::class.java) as KeyInfo
    check(keyInfo.keySize == PAYLOAD_KEY_SIZE_BITS) {
        "Outbox payload key must be " + PAYLOAD_KEY_SIZE_BITS + " bits"
    }
    check(
        keyInfo.purposes ==
            (KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT),
    ) { "Outbox payload key has incompatible purposes" }
    check(keyInfo.blockModes.contentEquals(arrayOf(KeyProperties.BLOCK_MODE_GCM))) {
        "Outbox payload key must permit only GCM"
    }
    check(
        keyInfo.encryptionPaddings.contentEquals(
            arrayOf(KeyProperties.ENCRYPTION_PADDING_NONE),
        ),
    ) { "Outbox payload key must permit only NoPadding" }
    check(!keyInfo.isUserAuthenticationRequired) {
        "Outbox payload key must remain usable by background delivery"
    }
    return key
}

/**
 * API 36's KeyInfo does not expose KeyGenParameterSpec's randomized-encryption
 * requirement. Probe the negative capability without encrypting: a compatible
 * AndroidKeyStore key must reject every caller-supplied encryption IV.
 */
private fun requireProviderGeneratedEncryptionIv(key: SecretKey) {
    val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
    try {
        cipher.init(
            Cipher.ENCRYPT_MODE,
            key,
            GCMParameterSpec(
                OutboxEnvelopeFormat.TAG_SIZE_BITS,
                ByteArray(OutboxEnvelopeFormat.IV_SIZE_BYTES),
            ),
        )
    } catch (_: InvalidAlgorithmParameterException) {
        return
    }
    error("Outbox payload key must require provider-generated randomized encryption IVs")
}

private fun loadAndroidKeyStore(): KeyStore =
    KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }

private fun ByteArray.toLowerHex(): String = buildString(size * 2) {
    this@toLowerHex.forEach { byte ->
        val unsigned = byte.toInt() and 0xff
        append(HEX[unsigned ushr 4])
        append(HEX[unsigned and 0x0f])
    }
}

private const val HEX = "0123456789abcdef"
