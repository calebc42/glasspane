package com.calebc42.jetpacs.core.testing

import com.calebc42.jetpacs.core.data.SurfaceCacheRepository
import com.calebc42.jetpacs.core.model.CachedSurface
import com.calebc42.jetpacs.core.model.SurfaceKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update

/**
 * Read-only repository fake with explicit test-fixture controls.
 *
 * Revision acceptance belongs to the EBP store contract, not this UI projection.
 */
class FakeSurfaceCacheRepository(
    initialSurfaces: List<CachedSurface> = emptyList(),
) : SurfaceCacheRepository {
    private val records = MutableStateFlow(index(initialSurfaces))

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

    fun setSurfaces(surfaces: List<CachedSurface>) {
        records.value = index(surfaces)
    }

    fun clearPairing(pairingId: String) {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        records.update { entries -> entries.filterKeys { it.pairingId != pairingId } }
    }

    private companion object {
        fun index(surfaces: List<CachedSurface>): Map<SurfaceKey, CachedSurface> {
            val indexed = surfaces.associateBy(CachedSurface::key)
            require(indexed.size == surfaces.size) { "surface keys must be unique" }
            return indexed
        }
    }
}
