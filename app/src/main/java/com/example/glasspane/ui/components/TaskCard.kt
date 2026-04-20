package com.example.glasspane.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
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
import com.example.glasspane.ui.theme.OrgTheme

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TaskCard(
    title: String,
    isDone: Boolean,
    hasChildren: Boolean,
    onCardClick: () -> Unit,
    onToggleStatus: () -> Unit,
    onCycleTodo: () -> Unit = {},
    onPickTodo: () -> Unit = {},
    onDelete: () -> Unit,
    onRefile: () -> Unit = {},
    onSchedule: () -> Unit = {},
    onClockIn: () -> Unit = {},
    onTreeEdit: (String) -> Unit = {},
    onFocus: () -> Unit = {},
    onEditTitle: () -> Unit = {},
    onSetPriority: () -> Unit = {},
    onSetTags: () -> Unit = {},
    onAddProperty: () -> Unit = {},
    onEditBodyFullScreen: () -> Unit = {},
    modifier: Modifier = Modifier,
    todoState: String = "",
    priority: String = "",
    tags: List<String> = emptyList(),
    scheduled: String = "",
    deadline: String = "",
    effort: String = "",
    level: Int = 1,
    isExpanded: Boolean = false,
    isDocument: Boolean = false,
    bodyText: String = "",
    onUpdateBody: (String) -> Unit = {}
) {
    var showMenu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = { onCardClick() },
                onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    showMenu = true
                }
            ),
        color = Color.Transparent
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = ((level - 1) * 16).dp) // Dynamic Left Indentation for Outline Hierarchy!
                .padding(top = 8.dp, bottom = 8.dp, end = 12.dp)
        ) {
            // Top row: status icon + title + menu
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                // Expanding Chevron if children OR if body text exist
                if (hasChildren || bodyText.isNotEmpty()) {
                    IconButton(
                        onClick = onCardClick,
                        modifier = Modifier.size(36.dp).padding(end = 4.dp)
                    ) {
                        Icon(
                            imageVector = if (isExpanded) Icons.Filled.KeyboardArrowDown else Icons.Filled.KeyboardArrowRight,
                            contentDescription = "Expand",
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                } else {
                    Spacer(Modifier.width(12.dp))
                }

                // Status / Type Icon
                if (isDocument) {
                    Icon(
                        imageVector = Icons.Filled.Description,
                        contentDescription = "File",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(24.dp).padding(end = 6.dp)
                    )
                } else if (!hasChildren) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .combinedClickable(
                                onClick = {
                                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    onCycleTodo()
                                },
                                onLongClick = {
                                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                    onPickTodo()
                                }
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = if (isDone) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                            contentDescription = "Cycle TODO State (tap) / Pick State (hold)",
                            tint = if (isDone) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                        )
                    }
                } else if (todoState.isEmpty()) {
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

                // TODO state badge
                if (todoState.isNotEmpty() && todoState != "No State") {
                    val stateColor = OrgTheme.todoStateColor(todoState, isDone)
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = stateColor.copy(alpha = 0.15f),
                        modifier = Modifier
                            .padding(end = 8.dp)
                            .combinedClickable(
                                onClick = {
                                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    onCycleTodo()
                                },
                                onLongClick = {
                                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                    onPickTodo()
                                }
                            )
                    ) {
                        Text(
                            text = todoState,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = stateColor,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                }

                // Priority badge
                if (priority.isNotEmpty() && priority != "B") {
                    val priColor = OrgTheme.priorityColor(priority)
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = priColor.copy(alpha = 0.15f),
                        modifier = Modifier.padding(end = 8.dp)
                    ) {
                        Text(
                            text = "#$priority",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = priColor,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                }

                // Task/File Title
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    color = if (isDone) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
                    textDecoration = if (isDone) TextDecoration.LineThrough else TextDecoration.None,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 4.dp)
                )

                // Right Action: Overflow Menu
                Box {
                    IconButton(
                        onClick = { showMenu = true },
                        modifier = Modifier.size(36.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.MoreVert,
                            contentDescription = "Options",
                            tint = MaterialTheme.colorScheme.outline
                        )
                    }
                    
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Refile") },
                            leadingIcon = { Icon(Icons.AutoMirrored.Filled.ArrowForward, "Refile") },
                            onClick = {
                                showMenu = false
                                onRefile()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Schedule / Deadline") },
                            leadingIcon = { Icon(Icons.Filled.Schedule, "Schedule") },
                            onClick = {
                                showMenu = false
                                onSchedule()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Focus") },
                            leadingIcon = { Icon(Icons.Filled.RemoveRedEye, "Focus") },
                            onClick = {
                                showMenu = false
                                onFocus()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Clock In") },
                            leadingIcon = { Icon(Icons.Filled.Timer, "Clock") },
                            onClick = {
                                showMenu = false
                                onClockIn()
                            }
                        )
                        HorizontalDivider()
                        DropdownMenuItem(text = { Text("Edit Title") }, onClick = { showMenu = false; onEditTitle() })
                        DropdownMenuItem(text = { Text("Set Priority") }, onClick = { showMenu = false; onSetPriority() })
                        DropdownMenuItem(text = { Text("Set Tags") }, onClick = { showMenu = false; onSetTags() })
                        DropdownMenuItem(text = { Text("Add Property") }, onClick = { showMenu = false; onAddProperty() })
                        HorizontalDivider()
                        DropdownMenuItem(text = { Text("Move Up") }, onClick = { showMenu = false; onTreeEdit("move-up") })
                        DropdownMenuItem(text = { Text("Move Down") }, onClick = { showMenu = false; onTreeEdit("move-down") })
                        DropdownMenuItem(text = { Text("Promote") }, onClick = { showMenu = false; onTreeEdit("promote") })
                        DropdownMenuItem(text = { Text("Demote") }, onClick = { showMenu = false; onTreeEdit("demote") })
                        DropdownMenuItem(text = { Text("Add Child") }, onClick = { showMenu = false; onTreeEdit("insert-child") })
                        DropdownMenuItem(text = { Text("Add Sibling") }, onClick = { showMenu = false; onTreeEdit("insert-sibling") })
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(Icons.Filled.Delete, "Delete", tint = MaterialTheme.colorScheme.error) },
                            onClick = {
                                showMenu = false
                                onDelete()
                            }
                        )
                    }
                }
            }

            // Bottom row: tags + timestamps
            val hasMetadata = tags.isNotEmpty() || scheduled.isNotEmpty() || deadline.isNotEmpty() || effort.isNotEmpty()
            if (hasMetadata) {
                Spacer(Modifier.height(6.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 40.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    tags.forEach { tag ->
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

                    if (scheduled.isNotEmpty()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Filled.Schedule,
                                contentDescription = "Scheduled",
                                modifier = Modifier.size(12.dp),
                                tint = MaterialTheme.colorScheme.outline
                            )
                            Spacer(Modifier.width(2.dp))
                            Text(
                                text = scheduled.replace(Regex("[<>]"), ""),
                                fontSize = 10.sp,
                                color = MaterialTheme.colorScheme.outline
                            )
                        }
                    }

                    if (deadline.isNotEmpty()) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Filled.Warning,
                                contentDescription = "Deadline",
                                modifier = Modifier.size(12.dp),
                                tint = MaterialTheme.colorScheme.error
                            )
                            Spacer(Modifier.width(2.dp))
                            Text(
                                text = deadline.replace(Regex("[<>]"), ""),
                                fontSize = 10.sp,
                                color = MaterialTheme.colorScheme.error.copy(alpha = 0.8f)
                            )
                        }
                    }

                    if (effort.isNotEmpty()) {
                        Text(
                            text = "⏱ $effort",
                            fontSize = 10.sp,
                            color = MaterialTheme.colorScheme.outline
                        )
                    }
                }
            }

            // Expanded Body Text
            if (isExpanded && bodyText.isNotEmpty()) {
                val lines = bodyText.split("\n")
                // Truncate to 10 lines if explicitly required by user logic, but they wanted drill-down. 
                // We'll show all of it when expanded, but it's hidden normally!
                Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp).combinedClickable(onClick = { onEditBodyFullScreen() }, onLongClick = {showMenu = true})) {
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
                                        val newText = bodyText.replaceFirst(line, "${indent}- [$newState] $content")
                                        onUpdateBody(newText)
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
        }
        HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
    }
}