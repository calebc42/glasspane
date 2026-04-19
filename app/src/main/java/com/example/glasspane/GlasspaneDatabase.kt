package com.example.glasspane

import android.content.Context
import androidx.room.*

// 1. The Table Structure
@Entity(tableName = "pending_requests")
data class PendingRequest(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val urlString: String,
    val method: String = "POST",
    val timestamp: Long = System.currentTimeMillis()
)

// 2. The Queries
@Dao
interface PendingRequestDao {
    @Insert
    suspend fun insert(request: PendingRequest)

    @Query("SELECT * FROM pending_requests ORDER BY timestamp ASC")
    suspend fun getAllPending(): List<PendingRequest>

    @Delete
    suspend fun delete(request: PendingRequest)
}

// 3. The Database Singleton
@Database(entities = [PendingRequest::class], version = 1, exportSchema = false)
abstract class GlasspaneDatabase : RoomDatabase() {
    abstract fun pendingRequestDao(): PendingRequestDao

    companion object {
        @Volatile
        private var INSTANCE: GlasspaneDatabase? = null

        fun getDatabase(context: Context): GlasspaneDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    GlasspaneDatabase::class.java,
                    "glasspane_cache.db"
                ).build()
                INSTANCE = instance
                instance
            }
        }
    }
}