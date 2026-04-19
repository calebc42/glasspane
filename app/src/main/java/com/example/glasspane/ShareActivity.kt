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
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                // Encode the strings so they survive the HTTP URL translation
                val encTask = URLEncoder.encode(task, "UTF-8")
                val encDetails = URLEncoder.encode(details, "UTF-8")

                // Map exactly to your init.el Quick Task template ("id=t")
                // ("t" "Quick Task" entry (file "~/inbox.org") "* TODO %^{Task}\n%^{Details}\n%U")
                val urlString = "http://127.0.0.1:8080/glasspane-capture?id=t&Task=$encTask&Details=$encDetails"

                val url = URL(urlString)
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 5000
                conn.responseCode // Execute the request
            } catch (e: Exception) {
                Log.e("ShareActivity", "Failed to capture to Emacs", e)
            } finally {
                finish() // Close the transparent dialog, returning control to Chrome
            }
        }
    }
}