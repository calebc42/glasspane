package com.calebc42.jetpacs.core.database

import androidx.room3.Entity

@Entity(
    tableName = "surface_records",
    primaryKeys = ["pairingId", "surfaceId"],
)
data class SurfaceRecordEntity(
    val pairingId: String,
    val surfaceId: String,
    val revision: Long,
    val present: Boolean,
    val specJson: String?,
    val staleSpecJson: String?,
    val staleAfterSeconds: Long?,
    val acceptedAtEpochMs: Long,
    val disconnectedAtEpochMs: Long?,
)
