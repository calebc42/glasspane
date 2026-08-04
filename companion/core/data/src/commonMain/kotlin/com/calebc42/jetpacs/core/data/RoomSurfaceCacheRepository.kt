package com.calebc42.jetpacs.core.data

import com.calebc42.jetpacs.core.database.JetpacsDatabase
import com.calebc42.jetpacs.core.database.SurfaceRecordEntity
import com.calebc42.jetpacs.core.model.CachedSurface
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine

class RoomSurfaceCacheRepository(
    private val database: JetpacsDatabase,
) : SurfaceCacheRepository {
    private val surfaceDao = database.surfaceDao()
    private val pairingDao = database.pairingDao()

    override fun observeSurfaces(pairingId: String): Flow<List<CachedSurface>> =
        combine(
            surfaceDao.observePresent(pairingId),
            pairingDao.observeRuntime(pairingId),
        ) { records, runtime ->
            records.map { it.toModel(runtime?.readyDisconnectedAtEpochMs) }
        }

    override fun observeSurface(key: SurfaceKey): Flow<CachedSurface?> =
        combine(
            surfaceDao.observePresent(key.pairingId, key.surfaceId),
            pairingDao.observeRuntime(key.pairingId),
        ) { record, runtime ->
            record?.toModel(runtime?.readyDisconnectedAtEpochMs)
        }
}

private fun SurfaceRecordEntity.toModel(readyDisconnectedAtEpochMs: Long?): CachedSurface {
    check(present) { "Only present records can be mapped to CachedSurface" }
    val presentSpecJson = requireNotNull(specJson) { "A present record must have spec JSON" }
    return CachedSurface(
        key = SurfaceKey(pairingId, surfaceId),
        revision = revision,
        specJson = presentSpecJson,
        staleSpecJson = staleSpecJson,
        staleAfterSeconds = staleAfterSeconds,
        currentView = currentView,
        acceptedAtEpochMs = acceptedAtEpochMs,
        readyDisconnectedAtEpochMs = readyDisconnectedAtEpochMs,
    )
}
