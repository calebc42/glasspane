package com.example.glasspane.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.glasspane.ui.components.EmacsServerStatus
import com.example.glasspane.ui.components.StatusAdmonition
import com.example.glasspane.ui.components.TaskCard
import com.example.glasspane.ui.viewmodels.DashboardViewModel
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    viewModel: DashboardViewModel = viewModel()
) {
    // Observe state from the ViewModel
    val serverStatus by viewModel.serverStatus.collectAsState()
    val tasks by viewModel.tasks.collectAsState()
    val currentParentId by viewModel.currentParentId.collectAsState()

    var showCaptureDialog by remember { mutableStateOf(false) }

    val haptics = LocalHapticFeedback.current

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
                .padding(horizontal = 16.dp)
        ) {
            Spacer(Modifier.height(16.dp))

            // --- Dashboard Header ---
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (currentParentId != null) {
                    IconButton(onClick = { viewModel.goBack() }) {
                        Icon(
                            imageVector = androidx.compose.material.icons.Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Go Back",
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                } else {
                    Icon(
                        imageVector = Icons.Filled.Code,
                        contentDescription = "Glasspane Logo",
                        modifier = Modifier.size(32.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }

                Text(
                    text = if (currentParentId != null) "Navigating..." else "Glasspane",
                    style = MaterialTheme.typography.displayMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(start = 12.dp)
                )

                Spacer(Modifier.weight(1f))

                // Refresh Button
                IconButton(onClick = { viewModel.fetchTasks() }) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = "Force Sync",
                        tint = MaterialTheme.colorScheme.outline
                    )
                }

                IconButton(onClick = { /* Navigate to Settings */ }) {
                    Icon(
                        imageVector = Icons.Filled.Settings,
                        contentDescription = "Settings",
                        tint = MaterialTheme.colorScheme.outline
                    )
                }
            }

            Spacer(Modifier.height(16.dp))

            // --- Server Status ---
            StatusAdmonition(
                status = serverStatus,
                message = when(serverStatus) {
                    EmacsServerStatus.CONNECTED -> "Connected to org-server"
                    EmacsServerStatus.SYNCING -> "Syncing data..."
                    else -> "Server Offline"
                }
            )

            Spacer(Modifier.height(16.dp))

            Text(
                text = "Emacs Org Nodes",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.outline
            )

            Spacer(Modifier.height(8.dp))

            // --- The Dynamic List ---
            if (tasks.isEmpty() && serverStatus == EmacsServerStatus.CONNECTED) {
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
                            hasChildren = task.hasChildren,
                            onCardClick = {
                                if (task.hasChildren) {
                                    viewModel.fetchTasks(task.id)
                                }
                            },
                            onToggleStatus = {
                                // Trigger a satisfying physical click!
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                // Tell Emacs to update the Org file
                                viewModel.toggleTaskStatus(task.id, task.status)
                            },
                            onDelete = { /* Optional */ }
                        )
                    }
                }
            }
        }
    }

    // --- Quick Capture ---
    if (showCaptureDialog) {
        QuickCaptureDialog(
            onDismiss = { showCaptureDialog = false },
            onSave = { newTaskTitle ->
                // Trigger a light click confirming the save
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)

                // Send the capture to Emacs
                viewModel.captureTask(newTaskTitle)

                showCaptureDialog = false
            }
        )
    }
}