package com.example.glasspane.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleDialog(
    initialDateStr: String? = null,
    onDismiss: () -> Unit,
    onScheduleSelected: (date: String, repeater: String, isDeadline: Boolean, remove: Boolean) -> Unit
) {
    var isDeadline by remember { mutableStateOf(false) }
    var repeater by remember { mutableStateOf("") }
    
    // Convert current string "2023-10-15" to UTC milliseconds for the DatePicker
    val initialMillis = remember(initialDateStr) {
        if (!initialDateStr.isNullOrEmpty()) {
            try {
                val cleanDate = initialDateStr.replace(Regex("[<>]"), "").substringBefore(" ")
                val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                sdf.timeZone = TimeZone.getTimeZone("UTC")
                sdf.parse(cleanDate)?.time
            } catch (e: Exception) {
                null
            }
        } else {
            null
        }
    }

    val datePickerState = rememberDatePickerState(
        initialSelectedDateMillis = initialMillis ?: System.currentTimeMillis()
    )

    AlertDialog(
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
        modifier = Modifier
            .fillMaxWidth(0.95f)
            .padding(vertical = 24.dp),
        title = {
            Text(text = "Schedule Task")
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center
                ) {
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        SegmentedButton(
                            selected = !isDeadline,
                            onClick = { isDeadline = false },
                            shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                        ) {
                            Text("Scheduled")
                        }
                        SegmentedButton(
                            selected = isDeadline,
                            onClick = { isDeadline = true },
                            shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                        ) {
                            Text("Deadline")
                        }
                    }
                }
                
                Spacer(Modifier.height(16.dp))
                
                DatePicker(
                    state = datePickerState,
                    modifier = Modifier.fillMaxWidth(),
                    showModeToggle = false,
                    title = null,
                    headline = null
                )
                
                Spacer(Modifier.height(16.dp))
                
                OutlinedTextField(
                    value = repeater,
                    onValueChange = { repeater = it },
                    label = { Text("Repeater (e.g. +1w, .+1m)") },
                    placeholder = { Text("Leave blank for one-time") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val millis = datePickerState.selectedDateMillis
                    if (millis != null) {
                        val date = Instant.ofEpochMilli(millis)
                            .atZone(ZoneId.of("UTC"))
                            .format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
                        onScheduleSelected(date, repeater.trim(), isDeadline, false)
                    }
                }
            ) {
                Text("Set Date")
            }
        },
        dismissButton = {
            Row {
                TextButton(
                    onClick = {
                        onScheduleSelected("", "", isDeadline, true)
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) {
                    Text("Clear Date")
                }
                Spacer(Modifier.width(8.dp))
                TextButton(onClick = onDismiss) {
                    Text("Cancel")
                }
            }
        },
        shape = RoundedCornerShape(24.dp)
    )
}
