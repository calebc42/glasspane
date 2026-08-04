package com.calebc42.jetpacs.core.navigation

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlinx.serialization.json.Json

class JetpacsNavKeyTest {
    private val json = Json

    @Test
    fun everyNavigationKeyRoundTripsThroughSerialization() {
        val keys = listOf<JetpacsNavKey>(
            JetpacsNavKey.Pairing,
            JetpacsNavKey.Catalog(pairingId = "pairing-1"),
            JetpacsNavKey.Surface(pairingId = "pairing-1", surfaceId = "surface-1"),
            JetpacsNavKey.Settings,
        )

        keys.forEach { key ->
            val encoded = json.encodeToString(JetpacsNavKey.serializer(), key)
            assertEquals(key, json.decodeFromString(JetpacsNavKey.serializer(), encoded))
        }
    }

    @Test
    fun catalogIdentityIsScopedToPairing() {
        assertEquals(
            JetpacsNavKey.Catalog(pairingId = "pairing-1"),
            JetpacsNavKey.Catalog(pairingId = "pairing-1"),
        )
        assertNotEquals(
            JetpacsNavKey.Catalog(pairingId = "pairing-1"),
            JetpacsNavKey.Catalog(pairingId = "pairing-2"),
        )
    }

    @Test
    fun surfaceIdentityIncludesPairingAndSurface() {
        val key = JetpacsNavKey.Surface(pairingId = "pairing-1", surfaceId = "surface-1")

        assertEquals(
            key,
            JetpacsNavKey.Surface(pairingId = "pairing-1", surfaceId = "surface-1"),
        )
        assertNotEquals(
            key,
            JetpacsNavKey.Surface(pairingId = "pairing-1", surfaceId = "surface-2"),
        )
        assertNotEquals(
            key,
            JetpacsNavKey.Surface(pairingId = "pairing-2", surfaceId = "surface-1"),
        )
    }
}
