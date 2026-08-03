package com.calebc42.jetpacs.core.database

import androidx.room3.ConstructedBy
import androidx.room3.Database
import androidx.room3.RoomDatabase
import androidx.room3.RoomDatabaseConstructor

@Database(
    entities = [SurfaceRecordEntity::class],
    version = 1,
    exportSchema = true,
)
@ConstructedBy(JetpacsDatabaseConstructor::class)
abstract class JetpacsDatabase : RoomDatabase() {
    abstract fun surfaceDao(): SurfaceDao
}

@Suppress("NO_ACTUAL_FOR_EXPECT")
expect object JetpacsDatabaseConstructor : RoomDatabaseConstructor<JetpacsDatabase> {
    override fun initialize(): JetpacsDatabase
}
