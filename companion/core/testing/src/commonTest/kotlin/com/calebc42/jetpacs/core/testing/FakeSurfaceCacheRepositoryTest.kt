package com.calebc42.jetpacs.core.testing

import com.calebc42.jetpacs.core.model.CachedSurface
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest

class FakeSurfaceCacheRepositoryTest {
    private val key = SurfaceKey(
        pairingId = "pairing-1",
        surfaceId = "catalog",
    )

    @Test
    fun projectionsArePairingScopedAndSorted() = runTest {
        val repository = FakeSurfaceCacheRepository(
            listOf(
                surface(SurfaceKey("pairing-1", "settings"), 2),
                surface(key, 1),
                surface(SurfaceKey("pairing-2", "catalog"), 3),
            )
        )

        assertEquals(
            listOf("catalog", "settings"),
            repository.observeSurfaces("pairing-1").first().map { it.key.surfaceId },
        )
    }

    @Test
    fun fixtureControlsReplaceAndClearProjectionsWithoutAcceptingProtocolWrites() = runTest {
        val retained = surface(SurfaceKey("pairing-2", "catalog"), 2)
        val repository = FakeSurfaceCacheRepository(listOf(surface(key, 1), retained))

        repository.setSurfaces(listOf(surface(key, 3), retained))
        assertEquals(3, repository.observeSurface(key).first()?.revision)

        repository.clearPairing(key.pairingId)
        assertNull(repository.observeSurface(key).first())
        assertEquals(retained, repository.observeSurface(retained.key).first())
    }

    @Test
    fun duplicateFixtureKeysFailFast() {
        assertFailsWith<IllegalArgumentException> {
            FakeSurfaceCacheRepository(listOf(surface(key, 1), surface(key, 2)))
        }
    }

    @Test
    fun fixtureProjectionPreservesSurfaceAndRuntimeMetadata() = runTest {
        val expected = surface(key, 4).copy(
            staleSpecJson = "{\"stale\":true}",
            staleAfterSeconds = 30,
            currentView = "details",
            readyDisconnectedAtEpochMs = 50,
        )
        val repository = FakeSurfaceCacheRepository(listOf(expected))

        assertEquals(expected, repository.observeSurface(key).first())
    }

    private fun surface(key: SurfaceKey, revision: Long) = CachedSurface(
        key = key,
        revision = revision,
        specJson = "{\"revision\":$revision}",
        acceptedAtEpochMs = revision,
    )
}
