package com.calebc42.jetpacs.core.data

import com.calebc42.jetpacs.core.model.CachedSurface
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlinx.coroutines.flow.Flow

/** Read-only projections of surfaces already accepted by the EBP store. */
interface SurfaceCacheRepository {
    fun observeSurfaces(pairingId: String): Flow<List<CachedSurface>>

    fun observeSurface(key: SurfaceKey): Flow<CachedSurface?>
}
