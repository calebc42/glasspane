package com.example.glasspane

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.NetworkType
import androidx.work.Constraints
import androidx.work.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.withContext

class ShareActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Intercept Android's native share data
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
        val sharedSubject = intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: ""

        setContent {
            MaterialTheme {
                ShareToEmacsDialog(sharedSubject, sharedText)
            }
        }
    }

    @Composable
    fun ShareToEmacsDialog(initialTitle: String, initialDetails: String) {
        var taskTitle by remember { mutableStateOf(initialTitle) }
        var taskDetails by remember { mutableStateOf(initialDetails) }

        AlertDialog(
            onDismissRequest = { finish() },
            title = { Text("Capture to Emacs") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = taskTitle,
                        onValueChange = { taskTitle = it },
                        label = { Text("Task (Title)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = taskDetails,
                        onValueChange = { taskDetails = it },
                        label = { Text("Details (URL/Text)") },
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { captureToEmacsAndFinish(taskTitle, taskDetails) }) {
                    Text("Save to Inbox")
                }
            },
            dismissButton = {
                TextButton(onClick = { finish() }) { Text("Cancel") }
            }
        )
    }

    private fun captureToEmacsAndFinish(task: String, details: String) {
        // 1. Use an independent scope so the DB write survives the Activity being destroyed
        CoroutineScope(Dispatchers.IO + SupervisorJob()).launch {
            val encTask = URLEncoder.encode(task, "UTF-8")
            val encDetails = URLEncoder.encode(details, "UTF-8")
            val urlString = "http://127.0.0.1:8080/glasspane-capture?id=t&Task=$encTask&Details=$encDetails"

            try {
                val url = URL(urlString)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 2000 // Fast fail (2 seconds)

                if (conn.responseCode in 200..299) {
                    Log.d("ShareActivity", "Sent straight to Emacs!")
                } else {
                    throw Exception("Server rejected payload")
                }
            } catch (e: Exception) {
                Log.w("ShareActivity", "Emacs offline. Caching payload locally.", e)

                // Save to Room DB
                val db = GlasspaneDatabase.getDatabase(applicationContext)
                db.pendingRequestDao().insert(PendingRequest(urlString = urlString))

                // 2. Build an aggressive retry policy (Try every 15 seconds instead of 10 minutes)
                val syncRequest = OneTimeWorkRequestBuilder<SyncWorker>()
                    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                    .setBackoffCriteria(
                        BackoffPolicy.LINEAR,
                        15, // 15 seconds
                        java.util.concurrent.TimeUnit.SECONDS
                    )
                    .build()

                // 3. Enqueue Unique Work (prevents spamming the queue if you save 5 things while offline)
                WorkManager.getInstance(applicationContext).enqueueUniqueWork(
                    "glasspane_sync",
                    ExistingWorkPolicy.REPLACE,
                    syncRequest
                )
            } finally {
                // Must switch to Main thread to safely finish UI components
                withContext(Dispatchers.Main) {
                    finish()
                }
            }
        }
    }
}