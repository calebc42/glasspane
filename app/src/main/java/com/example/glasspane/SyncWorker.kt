package com.example.glasspane

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

class SyncWorker(appContext: Context, workerParams: WorkerParameters) :
    CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val database = GlasspaneDatabase.getDatabase(applicationContext)
        val dao = database.pendingRequestDao()
        val pendingList = dao.getAllPending()

        if (pendingList.isEmpty()) {
            return@withContext Result.success()
        }

        Log.d("SyncWorker", "Attempting to sync ${pendingList.size} cached requests to Emacs...")

        var allSucceeded = true

        for (request in pendingList) {
            try {
                val url = URL(request.urlString)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = request.method
                conn.connectTimeout = 5000

                val code = conn.responseCode

                if (code in 200..299) {
                    // Success! Remove from local cache
                    dao.delete(request)
                    Log.d("SyncWorker", "Successfully synced: ${request.urlString}")
                } else {
                    // Server rejected it (e.g., 500 Error), but we reached the server.
                    // Depending on your logic, you might want to delete it or keep it.
                    // For now, we'll keep it to retry.
                    allSucceeded = false
                    Log.e("SyncWorker", "Server returned $code for ${request.urlString}")
                }
            } catch (e: Exception) {
                // Network failed entirely (still offline)
                allSucceeded = false
                Log.e("SyncWorker", "Network failure, will retry later: ${request.urlString}")
            }
        }

        if (allSucceeded) {
            Result.success()
        } else {
            // Tells Android to try this exact worker again later using exponential backoff
            Result.retry()
        }
    }
}