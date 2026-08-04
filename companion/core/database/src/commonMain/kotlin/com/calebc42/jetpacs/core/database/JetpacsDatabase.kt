package com.calebc42.jetpacs.core.database

import androidx.room3.ConstructedBy
import androidx.room3.Database
import androidx.room3.RoomDatabase
import androidx.room3.RoomDatabaseConstructor

@Database(
    entities = [
        PairingPartitionEntity::class,
        PairingRuntimeEntity::class,
        PairingRevocationEntity::class,
        RevocationArtifactEntity::class,
        SurfaceRecordEntity::class,
        SurfaceDraftEntity::class,
        QueueEventEntity::class,
        IssuedEventIdEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
@ConstructedBy(JetpacsDatabaseConstructor::class)
abstract class JetpacsDatabase : RoomDatabase() {
    abstract fun pairingDao(): PairingDao

    abstract fun revocationDao(): RevocationDao

    abstract fun surfaceDao(): SurfaceDao

    abstract fun queueEventDao(): QueueEventDao

    abstract fun issuedEventIdDao(): IssuedEventIdDao
}

@Suppress("NO_ACTUAL_FOR_EXPECT")
expect object JetpacsDatabaseConstructor : RoomDatabaseConstructor<JetpacsDatabase> {
    override fun initialize(): JetpacsDatabase
}
