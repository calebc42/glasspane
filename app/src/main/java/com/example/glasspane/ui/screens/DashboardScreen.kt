package com.example.glasspane.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
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
    val hoistedNode by viewModel.hoistedNode.collectAsState()
    val expandedStates by viewModel.expandedStates.collectAsState()

    var showCaptureDialog by remember { mutableStateOf(false) }
    var taskToRefile by remember { mutableStateOf<String?>(null) }
    var taskToSchedule by remember { mutableStateOf<String?>(null) }
    var taskDateInitial by remember { mutableStateOf<String?>(null) }
    var treeEditTarget by remember { mutableStateOf<Pair<String, String>?>(null) } // Pair(nodeId, action)
    var treeEditTitle by remember { mutableStateOf("") }

    val haptics = LocalHapticFeedback.current

    // Handle system back button when navigated into the tree
    BackHandler(enabled = currentParentId != null) {
        viewModel.goBack()
    }

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
            Spacer(Modifier.height(4.dp)) // Drastically reduced padding

            // --- Compact Dashboard Header ---
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)
            ) {
                if (currentParentId != null) {
                    IconButton(onClick = { viewModel.goBack() }) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Go Back",
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                }

                Text(
                    text = if (currentParentId != null) "In Focus" else "Files",
                    style = MaterialTheme.typography.titleLarge, // Changed from giant displayMedium
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(start = if (currentParentId != null) 4.dp else 12.dp)
                )

                Spacer(Modifier.weight(1f))

                // Small Server Status Icon
                val statusIcon = when(serverStatus) {
                    EmacsServerStatus.CONNECTED -> Icons.Filled.Code
                    EmacsServerStatus.SYNCING -> Icons.Filled.Refresh
                    else -> Icons.Filled.Warning
                }
                val statusColor = when(serverStatus) {
                    EmacsServerStatus.CONNECTED -> MaterialTheme.colorScheme.primary.copy(alpha=0.6f)
                    EmacsServerStatus.SYNCING -> MaterialTheme.colorScheme.secondary
                    else -> MaterialTheme.colorScheme.error
                }
                
                Icon(
                    imageVector = statusIcon,
                    contentDescription = "Status",
                    modifier = Modifier.size(16.dp).padding(end = 8.dp),
                    tint = statusColor
                )

                // Refresh Button
                IconButton(onClick = { viewModel.fetchTasks() }, modifier = Modifier.size(32.dp)) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = "Force Sync",
                        tint = MaterialTheme.colorScheme.outline
                    )
                }
            }

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
                // Focus Mode (Pinned Header)
                hoistedNode?.let { hoisted ->
                    Spacer(Modifier.height(8.dp))
                    Text(
                        text = "Focused Node",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 12.dp, bottom = 4.dp)
                    )
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.2f),
                        shape = MaterialTheme.shapes.medium
                    ) {
                        TaskCard(
                            title = hoisted.title,
                            isDone = hoisted.isDone,
                            hasChildren = hoisted.hasChildren,
                            todoState = hoisted.status,
                            priority = hoisted.priority,
                            tags = hoisted.tags,
                            scheduled = hoisted.scheduled,
                            deadline = hoisted.deadline,
                            effort = hoisted.effort,
                            level = 1,
                            isExpanded = true, // Hoisted parents are always expanded to show their body
                            bodyText = hoisted.bodyText,
                            onUpdateBody = { newBody -> viewModel.updateTaskBody(hoisted.id, newBody) },
                            onCardClick = { viewModel.toggleExpand(hoisted) },
                            onToggleStatus = {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                viewModel.toggleTaskStatus(hoisted.id, hoisted.status)
                            },
                            onDelete = { viewModel.deleteTask(hoisted.id); viewModel.goBack() },
                            onRefile = { taskToRefile = hoisted.id },
                            onSchedule = {
                                taskToSchedule = hoisted.id
                                taskDateInitial = hoisted.scheduled.ifEmpty { hoisted.deadline }
                            },
                            onClockIn = { viewModel.clockInTask(hoisted.id) },
                            onTreeEdit = { action ->
                                if (action == "insert-child" || action == "insert-sibling") {
                                    treeEditTarget = Pair(hoisted.id, action)
                                } else {
                                    viewModel.treeEditTask(hoisted.id, action, null)
                                }
                            },
                            onFocus = {} // Cannot focus an already focused node
                        )
                    }
                }

                Spacer(Modifier.height(8.dp))

                LazyColumn(
                    modifier = Modifier.weight(1f).fillMaxWidth()
                ) {
                    items(tasks, key = { it.id }) { task ->
                        TaskCard(
                            title = task.title,
                            isDone = task.isDone,
                            hasChildren = task.hasChildren,
                            todoState = task.status,
                            priority = task.priority,
                            tags = task.tags,
                            scheduled = task.scheduled,
                            deadline = task.deadline,
                            effort = task.effort,
                            level = task.level,
                            isExpanded = expandedStates.contains(task.id),
                            isDocument = task.id.startsWith("file:"),
                            bodyText = task.bodyText,
                            onUpdateBody = { newBody -> viewModel.updateTaskBody(task.id, newBody) },
                            onCardClick = { viewModel.toggleExpand(task) },
                            onToggleStatus = {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                viewModel.toggleTaskStatus(task.id, task.status)
                            },
                            onDelete = { viewModel.deleteTask(task.id) },
                            onRefile = { taskToRefile = task.id },
                            onSchedule = {
                                taskToSchedule = task.id
                                // Prefer picking scheduled time if available, else try deadline
                                taskDateInitial = task.scheduled.ifEmpty { task.deadline }
                            },
                            onClockIn = { viewModel.clockInTask(task.id) },
                            onTreeEdit = { action ->
                                if (action == "insert-child" || action == "insert-sibling") {
                                    treeEditTarget = Pair(task.id, action)
                                } else {
                                    viewModel.treeEditTask(task.id, action, null)
                                }
                            },
                            onFocus = { viewModel.focusTask(task) }
                        )
                    }
                }
            }
        }
    }

    // --- Dialogs ---

    if (showCaptureDialog) {
        QuickCaptureDialog(
            onDismiss = { showCaptureDialog = false },
            onCapture = { templateId, fields ->
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                viewModel.captureTask(templateId, fields)
                showCaptureDialog = false
            }
        )
    }

    taskToRefile?.let { sourceId ->
        RefileDialog(
            sourceNodeId = sourceId,
            onDismiss = { taskToRefile = null },
            onRefile = { targetId ->
                viewModel.refileTask(sourceId, targetId)
                taskToRefile = null
            }
        )
    }

    taskToSchedule?.let { taskId ->
        ScheduleDialog(
            initialDateStr = taskDateInitial,
            onDismiss = { taskToSchedule = null },
            onScheduleSelected = { date, repeater, isDeadline, remove ->
                viewModel.scheduleTask(taskId, date, repeater, isDeadline, remove)
                taskToSchedule = null
            }
        )
    }

    treeEditTarget?.let { (taskId, action) ->
        AlertDialog(
            onDismissRequest = { treeEditTarget = null },
            title = { Text(if (action == "insert-child") "Add Child Node" else "Add Sibling Node") },
            text = {
                OutlinedTextField(
                    value = treeEditTitle,
                    onValueChange = { treeEditTitle = it },
                    label = { Text("Heading Title") },
                    singleLine = true
                )
            },
            confirmButton = {
                Button(onClick = {
                    val finalTitle = treeEditTitle
                    treeEditTitle = ""
                    treeEditTarget = null
                    viewModel.treeEditTask(taskId, action, finalTitle)
                }) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { treeEditTarget = null }) { Text("Cancel") }
            }
        )
    }
}