package com.calebc42.jetpacs.core.testing

import com.calebc42.jetpacs.core.data.SurfaceCacheRepository
import com.calebc42.jetpacs.core.model.CacheWriteResult
import com.calebc42.jetpacs.core.model.CachedSurface
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class FakeSurfaceCacheRepository : SurfaceCacheRepository {
    private val mutex = Mutex()
    private val revisionFloors = mutableMapOf<SurfaceKey, Long>()
    private val records = MutableStateFlow<Map<SurfaceKey, CachedSurface>>(emptyMap())

    override fun observeSurfaces(pairingId: String): Flow<List<CachedSurface>> =
        records
            .map { entries ->
                entries.values
                    .filter { it.key.pairingId == pairingId }
                    .sortedBy { it.key.surfaceId }
            }
            .distinctUntilChanged()

    override fun observeSurface(key: SurfaceKey): Flow<CachedSurface?> =
        records.map { it[key] }.distinctUntilChanged()

    override suspend fun accept(surface: CachedSurface): CacheWriteResult =
        mutate(surface.key, surface.revision) {
            records.value = records.value + (surface.key to surface)
        }

    override suspend fun tombstone(
        key: SurfaceKey,
        revision: Long,
        observedAtEpochMs: Long,
    ): CacheWriteResult {
        require(revision >= 0) { "revision must be non-negative" }
        return mutate(key, revision) {
            records.value = records.value - key
        }
    }

    override suspend fun revokePairing(pairingId: String) {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        mutex.withLock {
            records.value = records.value.filterKeys { it.pairingId != pairingId }
            revisionFloors.keys.removeAll { it.pairingId == pairingId }
        }
    }

    private suspend fun mutate(
        key: SurfaceKey,
        revision: Long,
        apply: () -> Unit,
    ): CacheWriteResult = mutex.withLock {
        val currentRevision = revisionFloors[key]
        if (currentRevision != null && revision <= currentRevision) {
            CacheWriteResult.IgnoredStale(
                revision = revision,
                currentRevision = currentRevision,
            )
        } else {
            apply()
            revisionFloors[key] = revision
            CacheWriteResult.Applied(revision)
        }
    }
}
