package com.example.glasspane.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Code // Placeholder for logo
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.glasspane.ui.components.EmacsServerStatus
import com.example.glasspane.ui.components.StatusAdmonition
import com.example.glasspane.ui.components.TaskCard

// A temporary mock data class for our UI
data class OrgTask(val id: String, val title: String, val isDone: Boolean)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen() {
    // UI State (You will eventually wire this up to a ViewModel reading from your Emacs backend)
    var serverStatus by remember { mutableStateOf(EmacsServerStatus.CONNECTED) }
    var tasks by remember {
        mutableStateOf(
            listOf(
                OrgTask("1", "Review PR for Glasspane", false),
                OrgTask("2", "Buy groceries", true),
                OrgTask("3", "Write Emacs Lisp hook", false)
            )
        )
    }
    var showCaptureDialog by remember { mutableStateOf(false) }

    Scaffold(
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { showCaptureDialog = true },
                icon = { Icon(Icons.Filled.Add, contentDescription = "Capture") },
                text = { Text("Capture") },
                containerColor = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp) // Standard safe padding
        ) {
            Spacer(Modifier.height(16.dp))

            // --- 1. Dashboard Header (Inspired by HarpTitle.kt) ---
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                // Replace with painterResource(R.drawable.your_logo) later
                Icon(
                    imageVector = Icons.Filled.Code,
                    contentDescription = "Glasspane Logo",
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.primary
                )

                Text(
                    text = "Glasspane",
                    style = MaterialTheme.typography.displayMedium, // From our custom Typography
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(start = 12.dp)
                )

                Spacer(Modifier.weight(1f))

                IconButton(onClick = { /* Navigate to Settings */ }) {
                    Icon(
                        imageVector = Icons.Filled.Settings,
                        contentDescription = "Settings",
                        tint = MaterialTheme.colorScheme.outline
                    )
                }
            }

            Spacer(Modifier.height(16.dp))

            // --- 2. Server Status Notification ---
            StatusAdmonition(
                status = serverStatus,
                message = if (serverStatus == EmacsServerStatus.CONNECTED) "Connected to org-server" else "Server Offline"
            )

            Spacer(Modifier.height(16.dp))

            // --- 3. Task List Header ---
            Text(
                text = "Recent Tasks",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.outline
            )

            Spacer(Modifier.height(8.dp))

            // --- 4. The Data List or Empty State ---
            if (tasks.isEmpty()) {
                // Empty State
                Box(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "Inbox Zero!",
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.outline
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f).fillMaxWidth()
                ) {
                    items(tasks, key = { it.id }) { task ->
                        TaskCard(
                            title = task.title,
                            isDone = task.isDone,
                            onToggleStatus = {
                                tasks = tasks.map { if (it.id == task.id) it.copy(isDone = !it.isDone) else it }
                            },
                            onDelete = {
                                tasks = tasks.filter { it.id != task.id }
                            }
                        )
                    }
                }
            }
        }
    }

    // --- 5. Quick Capture Dialog Trigger ---
    if (showCaptureDialog) {
        QuickCaptureDialog(
            onDismiss = { showCaptureDialog = false },
            onSave = { newTaskTitle ->
                // Add the new task to our list (Wired to your Emacs backend later)
                tasks = tasks + OrgTask(id = System.currentTimeMillis().toString(), title = newTaskTitle, isDone = false)
                showCaptureDialog = false
            }
        )
    }
}