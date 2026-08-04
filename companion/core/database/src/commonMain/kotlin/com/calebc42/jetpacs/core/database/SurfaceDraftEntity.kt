package com.calebc42.jetpacs.core.database

import androidx.room3.ColumnInfo
import androidx.room3.Entity
import androidx.room3.ForeignKey
import androidx.room3.Index

@Entity(
    tableName = "surface_drafts",
    primaryKeys = ["pairing_id", "surface_id", "node_id"],
    foreignKeys = [
        ForeignKey(
            entity = SurfaceRecordEntity::class,
            parentColumns = ["pairing_id", "surface_id"],
            childColumns = ["pairing_id", "surface_id"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index(
            name = "index_surface_drafts_pairing_surface",
            value = ["pairing_id", "surface_id"],
        ),
    ],
)
data class SurfaceDraftEntity(
    @ColumnInfo(name = "pairing_id")
    val pairingId: String,
    @ColumnInfo(name = "surface_id")
    val surfaceId: String,
    @ColumnInfo(name = "node_id")
    val nodeId: String,
    @ColumnInfo(name = "value_json")
    val valueJson: String,
) {
    init {
        require(pairingId.isNotBlank()) { "pairingId must not be blank" }
        require(surfaceId.isNotBlank()) { "surfaceId must not be blank" }
        require(nodeId.isNotBlank()) { "nodeId must not be blank" }
    }
}
