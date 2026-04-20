package com.example.glasspane.ui.components

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.draw.drawBehind
import com.example.glasspane.ui.theme.OrgTheme
import com.example.glasspane.ui.viewmodels.OrgTask

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TaskCard(
    task: OrgTask,
    isExpanded: Boolean = false,
    isDocument: Boolean = false,
    isDirectory: Boolean = false,
    isStructureMode: Boolean = false,
    onCardClick: () -> Unit,
    onLongPress: () -> Unit,
    onAction: (NodeAction) -> Unit,
    modifier: Modifier = Modifier
) {
    val haptics = LocalHapticFeedback.current
    var showMenu by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = { onCardClick() },
                onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    val isFileSystemNode = isDocument || isDirectory
                    if (isStructureMode && !isFileSystemNode) {
                        onAction(NodeAction.Delete(task.id))
                    } else if (isFileSystemNode) {
                        showMenu = true
                    } else {
                        onLongPress()
                    }
                }
            ),
        color = Color.Transparent
    ) {
        val structureAccentColor = MaterialTheme.colorScheme.primary
        Box(
            modifier = Modifier.fillMaxWidth().drawBehind {
                if (isStructureMode) {
                    drawRect(color = structureAccentColor, size = androidx.compose.ui.geometry.Size(3.dp.toPx(), size.height))
                }
            }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = ((task.level - 1) * 16).dp) // Dynamic Left Indentation for Outline Hierarchy!
                    .padding(top = 8.dp, bottom = 8.dp, end = 12.dp)
                    .padding(start = if (isStructureMode) 10.dp else 0.dp) // Add internal indent for the left border
                    .animateContentSize()
            ) {
                // Top row: status icon + title + right actions
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    // Expanding Chevron if children OR if body text exist
                    if (task.hasChildren || task.bodyText.isNotEmpty()) {
                        IconButton(
                            onClick = onCardClick,
                            modifier = Modifier.size(36.dp).padding(end = 4.dp)
                        ) {
                            Icon(
                                imageVector = if (isExpanded) Icons.Filled.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                contentDescription = "Expand",
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    } else {
                        Spacer(Modifier.width(12.dp))
                    }

                    // Status / Type Icon
                    if (isStructureMode) {
                        Icon(
                            imageVector = Icons.Filled.DragHandle,
                            contentDescription = "Drag Handle",
                            tint = MaterialTheme.colorScheme.outline,
                            modifier = Modifier.size(36.dp).padding(end = 6.dp)
                        )
                    } else if (isDocument) {
                        Icon(
                            imageVector = Icons.Filled.Description,
                            contentDescription = "File",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(24.dp).padding(end = 6.dp)
                        )
                    } else if (isDirectory) {
                        Icon(
                            imageVector = Icons.Filled.Folder,
                            contentDescription = "Folder",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(24.dp).padding(end = 6.dp)
                        )
                    } else if (!task.hasChildren) {
                        Box(
                            modifier = Modifier
                                .size(36.dp)
                                .combinedClickable(
                                    onClick = {
                                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                        onAction(NodeAction.CycleTodo(task.id, task.status))
                                    },
                                    onLongClick = {
                                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                        onAction(NodeAction.PickTodo(task))
                                    }
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = if (task.isDone) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                                contentDescription = "Cycle TODO State (tap) / Pick State (hold)",
                                tint = if (task.isDone) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                            )
                        }
                    } else if (task.status.isEmpty()) {
                        // It's a heading with children and NO todo state!
                        Icon(
                            imageVector = Icons.Filled.Folder,
                            contentDescription = "Folder",
                            tint = MaterialTheme.colorScheme.secondary,
                            modifier = Modifier.size(24.dp).padding(end = 6.dp)
                        )
                    } else {
                        Spacer(Modifier.width(12.dp))
                    }

                    if (!isStructureMode) {
                        // TODO state badge
                        if (task.status.isNotEmpty() && task.status != "No State") {
                            val stateColor = OrgTheme.todoStateColor(task.status, task.isDone)
                            Surface(
                                shape = RoundedCornerShape(4.dp),
                                color = stateColor.copy(alpha = 0.15f),
                                modifier = Modifier
                                    .padding(end = 8.dp)
                                    .combinedClickable(
                                        onClick = {
                                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                            onAction(NodeAction.CycleTodo(task.id, task.status))
                                        },
                                        onLongClick = {
                                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                            onAction(NodeAction.PickTodo(task))
                                        }
                                    )
                            ) {
                                Text(
                                    text = task.status,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = stateColor,
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                )
                            }
                        }

                        // Priority badge
                        if (task.priority.isNotEmpty() && task.priority != "B") {
                            val priColor = OrgTheme.priorityColor(task.priority)
                            Surface(
                                shape = RoundedCornerShape(4.dp),
                                color = priColor.copy(alpha = 0.15f),
                                modifier = Modifier.padding(end = 8.dp)
                            ) {
                                Text(
                                    text = "#${task.priority}",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = priColor,
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                )
                            }
                        }
                    }

                    // Task/File Title
                    Text(
                        text = task.title,
                        style = MaterialTheme.typography.titleMedium,
                        color = if (task.isDone) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
                        textDecoration = if (task.isDone) TextDecoration.LineThrough else TextDecoration.None,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .weight(1f)
                            .padding(start = 4.dp)
                    )

                    // Right Actions
                    val isFileSystemNode = isDocument || isDirectory
                    if (isStructureMode) {
                        if (!isFileSystemNode) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                IconButton(onClick = { onAction(NodeAction.MoveUp(task.id)) }, modifier = Modifier.size(32.dp)) {
                                    Icon(Icons.Filled.ArrowUpward, "Move Up", tint = MaterialTheme.colorScheme.primary)
                                }
                                IconButton(onClick = { onAction(NodeAction.MoveDown(task.id)) }, modifier = Modifier.size(32.dp)) {
                                    Icon(Icons.Filled.ArrowDownward, "Move Down", tint = MaterialTheme.colorScheme.primary)
                                }
                                IconButton(onClick = { onAction(NodeAction.Promote(task.id)) }, modifier = Modifier.size(32.dp)) {
                                    Icon(Icons.AutoMirrored.Filled.ArrowBack, "Promote", tint = MaterialTheme.colorScheme.primary)
                                }
                                IconButton(onClick = { onAction(NodeAction.Demote(task.id)) }, modifier = Modifier.size(32.dp)) {
                                    Icon(Icons.AutoMirrored.Filled.ArrowForward, "Demote", tint = MaterialTheme.colorScheme.primary)
                                }
                            }
                        }
                    } else {
                        Box {
                            IconButton(onClick = { showMenu = true }, modifier = Modifier.size(36.dp)) {
                                Icon(Icons.Filled.MoreVert, "Options", tint = MaterialTheme.colorScheme.outline)
                            }
                            DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                                if (!isFileSystemNode) {
                                    DropdownMenuItem(
                                        text = { Text("Schedule / Deadline") },
                                        leadingIcon = { Icon(Icons.Filled.Schedule, "Schedule") },
                                        onClick = { showMenu = false; onAction(NodeAction.Schedule(task.id, task.scheduled.ifEmpty { task.deadline })) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Clock In") },
                                        leadingIcon = { Icon(Icons.Filled.Timer, "Clock In") },
                                        onClick = { showMenu = false; onAction(NodeAction.ClockIn(task.id)) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Focus") },
                                        leadingIcon = { Icon(Icons.Filled.RemoveRedEye, "Focus") },
                                        onClick = { showMenu = false; onAction(NodeAction.Focus(task)) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Refile") },
                                        leadingIcon = { Icon(Icons.AutoMirrored.Filled.ArrowForward, "Refile") },
                                        onClick = { showMenu = false; onAction(NodeAction.Refile(task.id)) }
                                    )
                                    HorizontalDivider()
                                    DropdownMenuItem(
                                        text = { Text("Add Child") },
                                        leadingIcon = { Icon(Icons.Filled.SubdirectoryArrowRight, "Child") },
                                        onClick = { showMenu = false; onAction(NodeAction.InsertChild(task.id)) }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Add Below") },
                                        leadingIcon = { Icon(Icons.Filled.PlaylistAdd, "Below") },
                                        onClick = { showMenu = false; onAction(NodeAction.InsertBelow(task.id)) }
                                    )
                                    HorizontalDivider()
                                }
                                DropdownMenuItem(
                                    text = { Text("Delete / Archive", color = MaterialTheme.colorScheme.error) },
                                    leadingIcon = { Icon(Icons.Filled.Delete, "Delete", tint = MaterialTheme.colorScheme.error) },
                                    onClick = { showMenu = false; onAction(NodeAction.Delete(task.id)) }
                                )
                            }
                        }
                    }
                }

                if (!isStructureMode) {
                    // Bottom row: tags + timestamps
                    val hasMetadata = task.tags.isNotEmpty() || task.scheduled.isNotEmpty() || task.deadline.isNotEmpty() || task.effort.isNotEmpty()
                    if (hasMetadata) {
                        Spacer(Modifier.height(6.dp))
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 40.dp),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            task.tags.forEach { tag ->
                                Surface(
                                    shape = RoundedCornerShape(4.dp),
                                    color = MaterialTheme.colorScheme.secondaryContainer
                                ) {
                                    Text(
                                        text = tag.trim(':'),
                                        fontSize = 10.sp,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp)
                                    )
                                }
                            }

                            if (task.scheduled.isNotEmpty()) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        imageVector = Icons.Filled.Schedule,
                                        contentDescription = "Scheduled",
                                        modifier = Modifier.size(12.dp),
                                        tint = MaterialTheme.colorScheme.outline
                                    )
                                    Spacer(Modifier.width(2.dp))
                                    Text(
                                        text = task.scheduled.replace(Regex("[<>]"), ""),
                                        fontSize = 10.sp,
                                        color = MaterialTheme.colorScheme.outline
                                    )
                                }
                            }

                            if (task.deadline.isNotEmpty()) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        imageVector = Icons.Filled.Warning,
                                        contentDescription = "Deadline",
                                        modifier = Modifier.size(12.dp),
                                        tint = MaterialTheme.colorScheme.error
                                    )
                                    Spacer(Modifier.width(2.dp))
                                    Text(
                                        text = task.deadline.replace(Regex("[<>]"), ""),
                                        fontSize = 10.sp,
                                        color = MaterialTheme.colorScheme.error.copy(alpha = 0.8f)
                                    )
                                }
                            }

                            if (task.effort.isNotEmpty()) {
                                Text(
                                    text = "⏱ ${task.effort}",
                                    fontSize = 10.sp,
                                    color = MaterialTheme.colorScheme.outline
                                )
                            }
                        }
                    }

                    // Expanded Body Text
                    if (isExpanded && task.bodyText.isNotEmpty()) {
                        val lines = task.bodyText.split("\n")
                        Column(modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 4.dp, vertical = 4.dp)
                            .combinedClickable(
                                onClick = { onAction(NodeAction.EditBodyFullScreen(task)) },
                                onLongClick = { onLongPress() }
                            )
                        ) {
                            for (line in lines) {
                                val checkboxMatch = Regex("^(\\s*)- \\[( |X|\\-)\\] (.*)$").find(line)
                                if (checkboxMatch != null) {
                                    val indent = checkboxMatch.groupValues[1]
                                    val state = checkboxMatch.groupValues[2]
                                    val content = checkboxMatch.groupValues[3]
                                    Row(
                                        verticalAlignment = Alignment.Top,
                                        modifier = Modifier.padding(start = (indent.length * 8).dp, top = 2.dp)
                                    ) {
                                        Checkbox(
                                            checked = state == "X",
                                            onCheckedChange = { isChecked ->
                                                val newState = if (isChecked) "X" else " "
                                                val newText = task.bodyText.replaceFirst(line, "${indent}- [$newState] $content")
                                                onAction(NodeAction.InlineUpdateBody(task.id, newText))
                                            },
                                            modifier = Modifier.size(24.dp).padding(end = 8.dp, top = 2.dp)
                                        )
                                        Text(
                                            text = content, 
                                            fontSize = 14.sp,
                                            modifier = Modifier.padding(top = 2.dp)
                                        )
                                    }
                                } else {
                                    Text(
                                        text = line, 
                                        fontSize = 14.sp, 
                                        modifier = Modifier.padding(vertical = 2.dp),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                } // end if (!isStructureMode)
            }
        }
        HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
    }
}