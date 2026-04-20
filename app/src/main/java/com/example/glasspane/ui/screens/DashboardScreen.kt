package com.example.glasspane.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.glasspane.ui.components.CreateIoDialog
import com.example.glasspane.ui.components.EmacsServerStatus
import com.example.glasspane.ui.components.NodeAction
import com.example.glasspane.ui.components.TaskCard
import com.example.glasspane.ui.components.TransientSheet
import com.example.glasspane.ui.viewmodels.DashboardViewModel
import com.example.glasspane.ui.viewmodels.OrgTask
import com.example.glasspane.ui.viewmodels.SettingsViewModel
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    viewModel: DashboardViewModel = viewModel(),
    settingsViewModel: SettingsViewModel = viewModel(),
    onOpenSettings: () -> Unit = {}
) {
    // Observe state from the ViewModel
    val serverStatus by viewModel.serverStatus.collectAsState()
    val tasks by viewModel.tasks.collectAsState()
    val currentParentId by viewModel.currentParentId.collectAsState()
    val hoistedNode by viewModel.hoistedNode.collectAsState()
    val expandedStates by viewModel.expandedStates.collectAsState()
    val isStructureMode by viewModel.isStructureMode.collectAsState()

    var showCaptureDialog by remember { mutableStateOf(false) }
    var showIoDialog by remember { mutableStateOf(false) }
    var taskToRefile by remember { mutableStateOf<String?>(null) }
    var taskToSchedule by remember { mutableStateOf<String?>(null) }
    var taskDateInitial by remember { mutableStateOf<String?>(null) }
    var treeEditTarget by remember { mutableStateOf<Pair<String, String>?>(null) } // Pair(nodeId, action)
    var treeEditTitle by remember { mutableStateOf("") }

    var taskToEditTitle by remember { mutableStateOf<OrgTask?>(null) }
    var taskToSetPriority by remember { mutableStateOf<OrgTask?>(null) }
    var taskToSetTags by remember { mutableStateOf<OrgTask?>(null) }
    var taskToPickTodo by remember { mutableStateOf<OrgTask?>(null) }
    var taskToAddProperty by remember { mutableStateOf<OrgTask?>(null) }
    var taskToEditBody by remember { mutableStateOf<OrgTask?>(null) }
    
    // Transient Action Sheet Target
    var transientTarget by remember { mutableStateOf<OrgTask?>(null) }
    var showStructureBanner by remember { mutableStateOf(false) }

    // For dialog states
    var dialogInputData by remember { mutableStateOf("") }
    var propKeyInput by remember { mutableStateOf("") }
    var propValInput by remember { mutableStateOf("") }

    val configTags by settingsViewModel.tags.collectAsState()
    val availableTags = remember(tasks, configTags) {
        val tagsFromTasks = tasks.flatMap { it.tags }.map { it.trim(':') }.filter { it.isNotEmpty() }
        (configTags + tagsFromTasks).toSet().sorted()
    }

    val todoSequence by settingsViewModel.todos.collectAsState()

    val haptics = LocalHapticFeedback.current

    // Action Dispatcher
    val onNodeAction: (NodeAction) -> Unit = { action ->
        when (action) {
            // Structure
            is NodeAction.MoveUp -> viewModel.treeEditTask(action.nodeId, "move-up", null)
            is NodeAction.MoveDown -> viewModel.treeEditTask(action.nodeId, "move-down", null)
            is NodeAction.Promote -> viewModel.treeEditTask(action.nodeId, "promote", null)
            is NodeAction.Demote -> viewModel.treeEditTask(action.nodeId, "demote", null)
            is NodeAction.InsertChild -> treeEditTarget = Pair(action.nodeId, "insert-child")
            is NodeAction.InsertBelow -> treeEditTarget = Pair(action.nodeId, "insert-sibling")
            is NodeAction.Refile -> taskToRefile = action.nodeId
            is NodeAction.Focus -> viewModel.focusTask(action.task)
            is NodeAction.Delete -> {
                viewModel.deleteTask(action.nodeId)
                if (hoistedNode?.id == action.nodeId) viewModel.goBack() 
            }
            
            // Metadata
            is NodeAction.EditTitle -> { dialogInputData = action.task.title; taskToEditTitle = action.task }
            is NodeAction.CycleTodo -> viewModel.toggleTaskStatus(action.nodeId, action.currentState)
            is NodeAction.PickTodo -> taskToPickTodo = action.task
            is NodeAction.SetPriority -> { dialogInputData = action.task.priority; taskToSetPriority = action.task }
            is NodeAction.SetTags -> taskToSetTags = action.task
            is NodeAction.AddProperty -> { propKeyInput = ""; propValInput = ""; taskToAddProperty = action.task }
            
            // Planning
            is NodeAction.Schedule -> { taskToSchedule = action.nodeId; taskDateInitial = action.initialDate }
            is NodeAction.ClockIn -> viewModel.clockInTask(action.nodeId)
            
            // Body
            is NodeAction.EditBodyFullScreen -> { dialogInputData = action.task.bodyText; taskToEditBody = action.task }
            is NodeAction.InlineUpdateBody -> viewModel.updateTaskBody(action.nodeId, action.newBody)
        }
    }

    LaunchedEffect(isStructureMode) {
        if (isStructureMode) {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            showStructureBanner = true
            delay(3000)
            showStructureBanner = false
        } else {
            showStructureBanner = false
        }
    }

    // Handle system back button when navigated into the tree
    BackHandler(enabled = currentParentId != null) {
        viewModel.goBack()
    }

    Scaffold(
        floatingActionButton = {
            if (!isStructureMode) {
                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    SmallFloatingActionButton(
                        onClick = { showIoDialog = true },
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer
                    ) {
                        Icon(Icons.Filled.AccountTree, contentDescription = "Create IO")
                    }
                    ExtendedFloatingActionButton(
                        onClick = { showCaptureDialog = true },
                        icon = { Icon(Icons.Filled.Add, contentDescription = "Capture") },
                        text = { Text("Capture") },
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }
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

                // Structure Mode Toggle
                IconButton(onClick = { viewModel.toggleStructureMode() }, modifier = Modifier.size(32.dp)) {
                    Icon(
                        imageVector = if (isStructureMode) Icons.Filled.Close else Icons.Filled.AccountTree,
                        contentDescription = "Structure Mode",
                        tint = if (isStructureMode) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                    )
                }

                Spacer(Modifier.width(8.dp))

                // Refresh Button
                IconButton(onClick = { viewModel.fetchTasks() }, modifier = Modifier.size(32.dp)) {
                    Icon(
                        imageVector = Icons.Filled.Refresh,
                        contentDescription = "Force Sync",
                        tint = MaterialTheme.colorScheme.outline
                    )
                }

                Spacer(Modifier.width(8.dp))
                
                // Settings Button
                IconButton(onClick = onOpenSettings, modifier = Modifier.size(32.dp)) {
                    Icon(
                        imageVector = Icons.Filled.Settings,
                        contentDescription = "Settings",
                        tint = MaterialTheme.colorScheme.outline
                    )
                }
            }

            AnimatedVisibility(visible = showStructureBanner) {
                Surface(
                    color = MaterialTheme.colorScheme.primaryContainer,
                    shape = RoundedCornerShape(8.dp),
                    modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)
                ) {
                    Text(
                        "Structure Mode — arrows to re-level or move up/down",
                        modifier = Modifier.padding(12.dp),
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        style = MaterialTheme.typography.bodyMedium
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
                            task = hoisted.copy(level = 1),
                            isExpanded = true, // Hoisted parents are always expanded to show their body
                            isDocument = hoisted.id.startsWith("file:"),
                            isStructureMode = isStructureMode,
                            onCardClick = { viewModel.toggleExpand(hoisted) },
                            onLongPress = { transientTarget = hoisted },
                            onAction = onNodeAction
                        )
                    }
                }

                Spacer(Modifier.height(8.dp))

                LazyColumn(
                    modifier = Modifier.weight(1f).fillMaxWidth()
                ) {
                    items(tasks, key = { it.id }) { task ->
                        TaskCard(
                            task = task,
                            isExpanded = expandedStates.contains(task.id),
                            isDocument = task.id.startsWith("file:"),
                            isDirectory = task.id.startsWith("dir:"),
                            isStructureMode = isStructureMode,
                            onCardClick = { viewModel.toggleExpand(task) },
                            onLongPress = { transientTarget = task },
                            onAction = onNodeAction
                        )
                    }
                }
            }
        }
    }

    // --- Bottom Sheets & Dialogs ---

    transientTarget?.let { task ->
        TransientSheet(
            task = task,
            onDismiss = { transientTarget = null },
            onAction = onNodeAction
        )
    }

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

    if (showIoDialog) {
        CreateIoDialog(
            tasks = tasks,
            focusedNodeId = currentParentId,
            onDismiss = { showIoDialog = false },
            onSubmit = { type, target, name ->
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                viewModel.createIO(type, target, name)
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
            title = { Text(if (action == "insert-child") "Add Child Node" else "Add Below") },
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

    taskToEditTitle?.let { task ->
        AlertDialog(
            onDismissRequest = { taskToEditTitle = null },
            title = { Text("Edit Title") },
            text = { OutlinedTextField(value = dialogInputData, onValueChange = { dialogInputData = it }, singleLine = true) },
            confirmButton = {
                Button(onClick = {
                    viewModel.updateTaskTitle(task.id, dialogInputData)
                    taskToEditTitle = null
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { taskToEditTitle = null }) { Text("Cancel") } }
        )
    }

    taskToSetPriority?.let { task ->
        AlertDialog(
            onDismissRequest = { taskToSetPriority = null },
            title = { Text("Set Priority") },
            text = { OutlinedTextField(value = dialogInputData, onValueChange = { dialogInputData = it }, label = { Text("A, B, C, or Space") }, singleLine = true) },
            confirmButton = {
                Button(onClick = {
                    viewModel.setTaskPriority(task.id, dialogInputData)
                    taskToSetPriority = null
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { taskToSetPriority = null }) { Text("Cancel") } }
        )
    }

    taskToSetTags?.let { task ->
        // Track selected tags as a mutable set, seeded from task's current tags
        var selectedTags by remember(task.id) {
            mutableStateOf(task.tags.map { it.trim(':') }.toSet())
        }
        var customTag by remember { mutableStateOf("") }

        AlertDialog(
            onDismissRequest = { taskToSetTags = null },
            title = { Text("Set Tags") },
            text = {
                Column {
                    if (availableTags.isNotEmpty()) {
                        Text("Tap to toggle:", style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.outline)
                        Spacer(Modifier.height(8.dp))
                        @OptIn(ExperimentalLayoutApi::class)
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            availableTags.forEach { tag ->
                                val isSelected = selectedTags.contains(tag)
                                FilterChip(
                                    selected = isSelected,
                                    onClick = {
                                        selectedTags = if (isSelected) selectedTags - tag else selectedTags + tag
                                    },
                                    label = { Text(tag) }
                                )
                            }
                        }
                        Spacer(Modifier.height(12.dp))
                    }
                    OutlinedTextField(
                        value = customTag,
                        onValueChange = { customTag = it },
                        label = { Text("Add custom tag") },
                        singleLine = true,
                        trailingIcon = {
                            if (customTag.isNotBlank()) {
                                IconButton(onClick = {
                                    selectedTags = selectedTags + customTag.trim()
                                    customTag = ""
                                }) { Icon(Icons.Filled.Add, "Add") }
                            }
                        }
                    )
                    if (selectedTags.isNotEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        Text("Selected: ${selectedTags.joinToString(", ")}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary)
                    }
                }
            },
            confirmButton = {
                Button(onClick = {
                    val tagStr = if (selectedTags.isEmpty()) "" else ":${selectedTags.joinToString(":")}:"
                    viewModel.setTaskTags(task.id, tagStr)
                    taskToSetTags = null
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { taskToSetTags = null }) { Text("Cancel") } }
        )
    }

    taskToPickTodo?.let { task ->
        val activeStates = todoSequence.filter { it != "|" }
        AlertDialog(
            onDismissRequest = { taskToPickTodo = null },
            title = { Text("Set TODO State") },
            text = {
                Column {
                    activeStates.forEach { state ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 2.dp)
                        ) {
                            RadioButton(
                                selected = task.status == state,
                                onClick = {
                                    viewModel.setTaskToState(task.id, state)
                                    taskToPickTodo = null
                                }
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(state, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 2.dp)
                    ) {
                        RadioButton(
                            selected = task.status == "No State" || task.status.isEmpty(),
                            onClick = {
                                viewModel.setTaskToState(task.id, "")
                                taskToPickTodo = null
                            }
                        )
                        Spacer(Modifier.width(8.dp))
                        Text("(No State)", style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.outline)
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { taskToPickTodo = null }) { Text("Close") } }
        )
    }

    taskToAddProperty?.let { task ->
        AlertDialog(
            onDismissRequest = { taskToAddProperty = null },
            title = { Text("Add Property") },
            text = {
                Column {
                    OutlinedTextField(value = propKeyInput, onValueChange = { propKeyInput = it }, label = { Text("Property Key") }, singleLine = true)
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(value = propValInput, onValueChange = { propValInput = it }, label = { Text("Value") }, singleLine = true)
                }
            },
            confirmButton = {
                Button(onClick = {
                    viewModel.addTaskProperty(task.id, propKeyInput, propValInput)
                    taskToAddProperty = null
                }) { Text("Add") }
            },
            dismissButton = { TextButton(onClick = { taskToAddProperty = null }) { Text("Cancel") } }
        )
    }

    taskToEditBody?.let { task ->
        androidx.compose.ui.window.Dialog(
            onDismissRequest = { taskToEditBody = null },
            properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Scaffold(
                topBar = {
                    @OptIn(ExperimentalMaterial3Api::class)
                    TopAppBar(
                        title = { Text("Edit Body") },
                        navigationIcon = {
                            IconButton(onClick = { taskToEditBody = null }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Close")
                            }
                        },
                        actions = {
                            Button(
                                onClick = {
                                    viewModel.updateTaskBody(task.id, dialogInputData)
                                    taskToEditBody = null
                                },
                                modifier = Modifier.padding(end = 8.dp)
                            ) {
                                Text("Save")
                            }
                        }
                    )
                }
            ) { padding ->
                OutlinedTextField(
                    value = dialogInputData,
                    onValueChange = { dialogInputData = it },
                    modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
                    placeholder = { Text("Enter notes here...") }
                )
            }
        }
    }
}