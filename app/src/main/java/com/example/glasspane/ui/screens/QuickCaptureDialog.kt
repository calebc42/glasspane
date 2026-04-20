package com.example.glasspane.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import com.example.glasspane.EmacsClient

// ─── Data models for capture templates ──────────────────────────────────────

data class CaptureTemplateField(
    val key: String,
    val label: String,
    val hint: String = ""
)

data class CaptureTemplate(
    val id: String,
    val title: String,
    val endpoint: String,
    val fields: List<CaptureTemplateField>
)

// ─── The Capture Dialog ─────────────────────────────────────────────────────

@Composable
fun QuickCaptureDialog(
    onDismiss: () -> Unit,
    onCapture: (templateId: String, fields: Map<String, String>) -> Unit
) {
    // State: loading, template list, selected template, field values
    var isLoading by remember { mutableStateOf(true) }
    var templates by remember { mutableStateOf<List<CaptureTemplate>>(emptyList()) }
    var selectedTemplate by remember { mutableStateOf<CaptureTemplate?>(null) }
    var fieldValues by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    // Fetch templates on first composition
    LaunchedEffect(Unit) {
        try {
            val fetched = EmacsClient.get("/glasspane-capture-templates")?.let {
                parseCaptureTemplates(it)
            }
            if (fetched != null) {
                templates = fetched
                isLoading = false
            } else {
                errorMessage = "Could not fetch templates"
                isLoading = false
            }
        } catch (e: Exception) {
            errorMessage = "Connection failed: ${e.message}"
            isLoading = false
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = if (selectedTemplate != null) selectedTemplate!!.title else "Choose Template",
                style = MaterialTheme.typography.titleLarge
            )
        },
        text = {
            when {
                isLoading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(120.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }

                errorMessage != null -> {
                    Text(
                        text = errorMessage ?: "",
                        color = MaterialTheme.colorScheme.error
                    )
                }

                selectedTemplate == null -> {
                    // ── Template picker ──────────────────────────────────
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 400.dp)
                    ) {
                        items(templates) { template ->
                            Surface(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp)
                                    .clickable {
                                        selectedTemplate = template
                                        // Initialize field values
                                        fieldValues = template.fields.associate { it.key to "" }
                                    },
                                shape = RoundedCornerShape(12.dp),
                                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier.padding(16.dp)
                                ) {
                                    Surface(
                                        shape = RoundedCornerShape(6.dp),
                                        color = MaterialTheme.colorScheme.primaryContainer,
                                        modifier = Modifier.size(36.dp)
                                    ) {
                                        Box(contentAlignment = Alignment.Center) {
                                            Text(
                                                text = template.id.uppercase(),
                                                fontWeight = FontWeight.Bold,
                                                fontSize = 14.sp,
                                                color = MaterialTheme.colorScheme.onPrimaryContainer
                                            )
                                        }
                                    }
                                    Spacer(Modifier.width(12.dp))
                                    Column {
                                        Text(
                                            text = template.title,
                                            style = MaterialTheme.typography.titleSmall
                                        )
                                        Text(
                                            text = "${template.fields.size} field${if (template.fields.size != 1) "s" else ""}",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.outline
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                else -> {
                    // ── Field entry form ─────────────────────────────────
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 400.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        selectedTemplate!!.fields.forEachIndexed { index, field ->
                            OutlinedTextField(
                                value = fieldValues[field.key] ?: "",
                                onValueChange = { newVal ->
                                    fieldValues = fieldValues.toMutableMap().apply {
                                        this[field.key] = newVal
                                    }
                                },
                                label = { Text(field.label) },
                                placeholder = {
                                    if (field.hint.isNotEmpty()) Text(field.hint)
                                },
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(12.dp),
                                singleLine = index > 0,  // First field gets multiline
                                minLines = if (index == 0) 2 else 1,
                                keyboardOptions = KeyboardOptions(
                                    imeAction = if (index == selectedTemplate!!.fields.lastIndex)
                                        ImeAction.Done else ImeAction.Next
                                )
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            if (selectedTemplate != null) {
                Button(
                    onClick = {
                        onCapture(selectedTemplate!!.id, fieldValues)
                    },
                    enabled = fieldValues.values.any { it.isNotBlank() }
                ) {
                    Text("Capture")
                }
            }
        },
        dismissButton = {
            if (selectedTemplate != null) {
                // Show "Back" to return to template picker
                TextButton(onClick = {
                    selectedTemplate = null
                    fieldValues = emptyMap()
                }) {
                    Text("Back")
                }
            }
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
        shape = RoundedCornerShape(24.dp),
        containerColor = MaterialTheme.colorScheme.surface,
        titleContentColor = MaterialTheme.colorScheme.onSurface,
        textContentColor = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

// ─── JSON parser ────────────────────────────────────────────────────────────

private fun parseCaptureTemplates(json: String): List<CaptureTemplate> {
    val result = mutableListOf<CaptureTemplate>()
    val arr = org.json.JSONArray(json)

    for (i in 0 until arr.length()) {
        val obj = arr.getJSONObject(i)
        val fieldsArr = obj.optJSONArray("fields") ?: org.json.JSONArray()
        val fields = mutableListOf<CaptureTemplateField>()

        for (j in 0 until fieldsArr.length()) {
            val fieldObj = fieldsArr.getJSONObject(j)
            fields.add(
                CaptureTemplateField(
                    key = fieldObj.optString("key", ""),
                    label = fieldObj.optString("label", ""),
                    hint = fieldObj.optString("hint", "")
                )
            )
        }

        result.add(
            CaptureTemplate(
                id = obj.optString("id", ""),
                title = obj.optString("title", ""),
                endpoint = obj.optString("endpoint", "/glasspane-capture"),
                fields = fields
            )
        )
    }

    return result
}