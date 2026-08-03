package com.calebc42.jetpacs.core.data

import androidx.room3.withWriteTransaction
import com.calebc42.jetpacs.core.database.JetpacsDatabase
import com.calebc42.jetpacs.core.database.SurfaceRecordEntity
import com.calebc42.jetpacs.core.model.CacheWriteResult
import com.calebc42.jetpacs.core.model.CachedSurface
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class RoomSurfaceCacheRepository(
    private val database: JetpacsDatabase,
) : SurfaceCacheRepository {
    private val dao = database.surfaceDao()

    override fun observeSurfaces(pairingId: String): Flow<List<CachedSurface>> =
        dao.observePresent(pairingId).map { records -> records.map(SurfaceRecordEntity::toModel) }

    override fun observeSurface(key: SurfaceKey): Flow<CachedSurface?> =
        dao.observePresent(key.pairingId, key.surfaceId).map { it?.toModel() }

    override suspend fun accept(surface: CachedSurface): CacheWriteResult =
        replaceIfNewer(surface.toRecord())

    override suspend fun tombstone(
        key: SurfaceKey,
        revision: Long,
        observedAtEpochMs: Long,
    ): CacheWriteResult {
        require(revision >= 0) { "revision must be non-negative" }
        return replaceIfNewer(
            SurfaceRecordEntity(
                pairingId = key.pairingId,
                surfaceId = key.surfaceId,
                revision = revision,
                present = false,
                specJson = null,
                staleSpecJson = null,
                staleAfterSeconds = null,
                acceptedAtEpochMs = observedAtEpochMs,
                disconnectedAtEpochMs = observedAtEpochMs,
            )
        )
    }

    private suspend fun replaceIfNewer(record: SurfaceRecordEntity): CacheWriteResult =
        database.withWriteTransaction {
            val currentRevision =
                dao.getRecord(record.pairingId, record.surfaceId)?.revision
            if (currentRevision != null && record.revision <= currentRevision) {
                CacheWriteResult.IgnoredStale(
                    revision = record.revision,
                    currentRevision = currentRevision,
                )
            } else {
                dao.upsert(record)
                CacheWriteResult.Applied(record.revision)
            }
        }
}

private fun CachedSurface.toRecord() = SurfaceRecordEntity(
    pairingId = key.pairingId,
    surfaceId = key.surfaceId,
    revision = revision,
    present = true,
    specJson = specJson,
    staleSpecJson = staleSpecJson,
    staleAfterSeconds = staleAfterSeconds,
    acceptedAtEpochMs = acceptedAtEpochMs,
    disconnectedAtEpochMs = disconnectedAtEpochMs,
)

private fun SurfaceRecordEntity.toModel(): CachedSurface {
    check(present) { "Only present records can be mapped to CachedSurface" }
    val presentSpecJson = requireNotNull(specJson) { "A present record must have spec JSON" }
    return CachedSurface(
        key = SurfaceKey(pairingId, surfaceId),
        revision = revision,
        specJson = presentSpecJson,
        staleSpecJson = staleSpecJson,
        staleAfterSeconds = staleAfterSeconds,
        acceptedAtEpochMs = acceptedAtEpochMs,
        disconnectedAtEpochMs = disconnectedAtEpochMs,
    )
}
