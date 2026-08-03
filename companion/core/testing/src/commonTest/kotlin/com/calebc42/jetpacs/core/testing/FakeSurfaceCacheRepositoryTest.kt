package com.calebc42.jetpacs.core.testing

import com.calebc42.jetpacs.core.model.CacheWriteResult
import com.calebc42.jetpacs.core.model.CachedSurface
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull

class FakeSurfaceCacheRepositoryTest {
    private val key = SurfaceKey(
        pairingId = "pairing-1",
        surfaceId = "catalog",
    )

    @Test
    fun staleUpdatesCannotCrossATombstoneRevisionFloor() = runTest {
        val repository = FakeSurfaceCacheRepository()
        val revisionOne = CachedSurface(
            key = key,
            revision = 1,
            specJson = """{"revision":1}""",
            acceptedAtEpochMs = 10,
        )

        assertIs<CacheWriteResult.Applied>(repository.accept(revisionOne))
        assertIs<CacheWriteResult.Applied>(
            repository.tombstone(key, revision = 2, observedAtEpochMs = 20)
        )
        assertIs<CacheWriteResult.IgnoredStale>(repository.accept(revisionOne))
        assertNull(repository.observeSurface(key).first())
    }

    @Test
    fun aNewerSnapshotCanReplaceATombstone() = runTest {
        val repository = FakeSurfaceCacheRepository()
        repository.tombstone(key, revision = 2, observedAtEpochMs = 20)
        val revisionThree = CachedSurface(
            key = key,
            revision = 3,
            specJson = """{"revision":3}""",
            acceptedAtEpochMs = 30,
        )

        assertEquals(CacheWriteResult.Applied(3), repository.accept(revisionThree))
        assertEquals(revisionThree, repository.observeSurface(key).first())
    }

    @Test
    fun revokePairingErasesOnlyItsRecordsAndRevisionFloors() = runTest {
        val repository = FakeSurfaceCacheRepository()
        val retainedKey = SurfaceKey("pairing-2", "catalog")
        val revoked = CachedSurface(key, 5, "{}", acceptedAtEpochMs = 50)
        val retained = CachedSurface(retainedKey, 2, "{}", acceptedAtEpochMs = 20)
        repository.accept(revoked)
        repository.accept(retained)

        repository.revokePairing(key.pairingId)

        assertNull(repository.observeSurface(key).first())
        assertEquals(retained, repository.observeSurface(retainedKey).first())
        assertEquals(CacheWriteResult.Applied(1), repository.accept(revoked.copy(revision = 1)))
    }
}
