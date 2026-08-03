package com.calebc42.jetpacs.core.data

import com.calebc42.jetpacs.core.model.CacheWriteResult
import com.calebc42.jetpacs.core.model.CachedSurface
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlinx.coroutines.flow.Flow

interface SurfaceCacheRepository {
    fun observeSurfaces(pairingId: String): Flow<List<CachedSurface>>

    fun observeSurface(key: SurfaceKey): Flow<CachedSurface?>

    suspend fun accept(surface: CachedSurface): CacheWriteResult

    suspend fun tombstone(
        key: SurfaceKey,
        revision: Long,
        observedAtEpochMs: Long,
    ): CacheWriteResult
}
