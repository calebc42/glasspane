package com.example.glasspane.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.glasspane.ui.viewmodels.OrgTask

@Composable
fun CreateIoDialog(
    tasks: List<OrgTask>,
    focusedNodeId: String?,
    onDismiss: () -> Unit,
    onSubmit: (type: String, target: String, name: String) -> Unit
) {
    var selectedType by remember { mutableStateOf("heading") } // "heading" or "file"
    var nameInput by remember { mutableStateOf("") }
    
    // Default to the currently focused file if applicable
    val defaultTargetFile = remember(focusedNodeId, tasks) {
        if (focusedNodeId?.startsWith("file:") == true) {
            focusedNodeId.substring(5)
        } else if (focusedNodeId != null) {
            // we are focused on a task; its id doesn't easily map to a file without Emacs, 
            // but the root file might be in the list. Wait, if focused on a task, we cannot easily know its file.
            // Let's just find the first file in `tasks`.
            tasks.firstOrNull { it.id.startsWith("file:") }?.id?.substring(5) ?: "inbox.org"
        } else {
            tasks.firstOrNull { it.id.startsWith("file:") }?.id?.substring(5) ?: "inbox.org"
        }
    }
    
    var targetInput by remember { mutableStateOf(defaultTargetFile) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Create New Component") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                // Type Toggle
                Row(
                    modifier = Modifier.fillMaxWidth().selectableGroup(),
                    horizontalArrangement = Arrangement.Center
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = selectedType == "heading", onClick = { selectedType = "heading" })
                        Text("Heading")
                    }
                    Spacer(Modifier.width(16.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = selectedType == "file", onClick = { selectedType = "file" })
                        Text("File / Folder")
                    }
                }
                
                Spacer(modifier = Modifier.height(16.dp))

                if (selectedType == "heading") {
                    OutlinedTextField(
                        value = nameInput,
                        onValueChange = { nameInput = it },
                        label = { Text("Heading Title") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = targetInput,
                        onValueChange = { targetInput = it },
                        label = { Text("Target File (e.g. inbox.org)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    OutlinedTextField(
                        value = targetInput,
                        onValueChange = { targetInput = it },
                        label = { Text("Path (e.g. projects/web.org)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    if (targetInput.isNotBlank()) {
                        onSubmit(selectedType, targetInput, nameInput)
                        onDismiss()
                    }
                },
                enabled = targetInput.isNotBlank() && (selectedType == "file" || nameInput.isNotBlank())
            ) {
                Text("Create")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}
