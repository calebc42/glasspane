package com.example.glasspane

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class DialogActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Parse Primitives from Emacs
        val method = intent.getStringExtra("input_method") ?: "text"
        val title = intent.getStringExtra("input_title") ?: "Input Required"
        val hint = intent.getStringExtra("input_hint") ?: ""
        val valuesRaw = intent.getStringExtra("input_values") ?: ""
        val endpoint = intent.getStringExtra("endpoint")

        val valuesList = if (valuesRaw.isNotEmpty()) valuesRaw.split(",") else emptyList()

        setContent {
            MaterialTheme {
                when (method) {
                    "text" -> TextInputDialog(title, hint, endpoint)
                    "confirm" -> ConfirmInputDialog(title, hint, endpoint)
                    "radio" -> RadioInputDialog(title, valuesList, endpoint)
                    // You can easily add "checkbox", "spinner", etc. here later
                    else -> {
                        Log.e("DialogActivity", "Unknown method: $method")
                        finish()
                    }
                }
            }
        }
    }

    // --- 1. TEXT INPUT ---
    @Composable
    fun TextInputDialog(title: String, hint: String, endpoint: String?) {
        var textValue by remember { mutableStateOf("") }

        AlertDialog(
            onDismissRequest = { finish() },
            title = { Text(title) },
            text = {
                OutlinedTextField(
                    value = textValue,
                    onValueChange = { textValue = it },
                    label = { Text(hint) },
                    singleLine = false
                )
            },
            confirmButton = {
                TextButton(onClick = { sendResultAndFinish(endpoint, textValue) }) {
                    Text("OK")
                }
            },
            dismissButton = {
                TextButton(onClick = { finish() }) { Text("Cancel") }
            }
        )
    }

    // --- 2. CONFIRM INPUT ---
    @Composable
    fun ConfirmInputDialog(title: String, hint: String, endpoint: String?) {
        AlertDialog(
            onDismissRequest = { finish() },
            title = { Text(title) },
            text = { Text(hint) },
            confirmButton = {
                TextButton(onClick = { sendResultAndFinish(endpoint, "yes") }) {
                    Text("Yes")
                }
            },
            dismissButton = {
                TextButton(onClick = { sendResultAndFinish(endpoint, "no") }) {
                    Text("No")
                }
            }
        )
    }

    // --- 3. RADIO INPUT ---
    @Composable
    fun RadioInputDialog(title: String, options: List<String>, endpoint: String?) {
        var selectedOption by remember { mutableStateOf(options.firstOrNull() ?: "") }

        AlertDialog(
            onDismissRequest = { finish() },
            title = { Text(title) },
            text = {
                Column {
                    options.forEach { option ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { selectedOption = option }
                                .padding(vertical = 8.dp)
                        ) {
                            RadioButton(
                                selected = (option == selectedOption),
                                onClick = { selectedOption = option }
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(text = option)
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { sendResultAndFinish(endpoint, selectedOption) }) {
                    Text("OK")
                }
            },
            dismissButton = {
                TextButton(onClick = { finish() }) { Text("Cancel") }
            }
        )
    }

    // --- NETWORK BRIDGE ---
    private fun sendResultAndFinish(endpoint: String?, result: String) {
        if (endpoint == null) {
            finish()
            return
        }

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                // Hardcoded local server; move to GlasspaneConfig later!
                val url = URL("http://127.0.0.1:8080$endpoint")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true

                val json = JSONObject().apply {
                    put("result", result)
                }

                conn.outputStream.use { os ->
                    val input = json.toString().toByteArray(Charsets.UTF_8)
                    os.write(input, 0, input.size)
                }

                conn.responseCode // Execute
            } catch (e: Exception) {
                Log.e("DialogActivity", "Failed to send dialog result", e)
            } finally {
                finish() // Always destroy the transparent activity when done
            }
        }
    }
}