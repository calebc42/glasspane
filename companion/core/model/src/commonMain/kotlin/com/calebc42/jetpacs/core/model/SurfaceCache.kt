package com.calebc42.jetpacs.core.model

data class SurfaceKey(
    val pairingId: String,
    val surfaceId: String,
) {
    init {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(surfaceId.isNotBlank()) { "surfaceId must not be blank" }
    }
}

data class CachedSurface(
    val key: SurfaceKey,
    val revision: Long,
    val specJson: String,
    val staleSpecJson: String? = null,
    val staleAfterSeconds: Long? = null,
    val acceptedAtEpochMs: Long,
    val disconnectedAtEpochMs: Long? = null,
) {
    init {
        require(revision >= 0) { "revision must be non-negative" }
        require(staleAfterSeconds == null || staleAfterSeconds >= 0) {
            "staleAfterSeconds must be non-negative"
        }
    }
}

sealed interface CacheWriteResult {
    val revision: Long

    data class Applied(
        override val revision: Long,
    ) : CacheWriteResult

    data class IgnoredStale(
        override val revision: Long,
        val currentRevision: Long,
    ) : CacheWriteResult
}
