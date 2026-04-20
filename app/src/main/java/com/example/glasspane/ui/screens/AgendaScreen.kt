package com.example.glasspane.ui.screens

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.glasspane.ui.theme.OrgTheme
import com.example.glasspane.ui.viewmodels.AgendaItem
import com.example.glasspane.ui.viewmodels.AgendaViewModel
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgendaScreen(
    viewModel: AgendaViewModel = viewModel(),
    onNavigateToTask: (String) -> Unit = {},
    onOpenSettings: () -> Unit = {}
) {
    val uiState by viewModel.uiState.collectAsState()
    val haptics = LocalHapticFeedback.current

    val todayStr = remember {
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // ── Span Selector Chips ───────────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            listOf("day" to "Today", "week" to "Week", "month" to "Month").forEach { (span, label) ->
                FilterChip(
                    selected = uiState.span == span,
                    onClick = { viewModel.fetchAgenda(span) },
                    label = { Text(label) },
                    leadingIcon = if (uiState.span == span) {
                        { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
                    } else null
                )
            }

            Spacer(Modifier.weight(1f))

            IconButton(onClick = { viewModel.fetchAgenda(uiState.span) }) {
                Icon(
                    imageVector = Icons.Filled.Refresh,
                    contentDescription = "Refresh Agenda",
                    tint = MaterialTheme.colorScheme.outline
                )
            }

            IconButton(onClick = onOpenSettings) {
                Icon(
                    imageVector = Icons.Filled.Settings,
                    contentDescription = "Agenda Settings",
                    tint = MaterialTheme.colorScheme.outline
                )
            }
        }

        // ── Content ───────────────────────────────────────────────────────────
        when {
            uiState.isLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            }

            uiState.errorMessage != null -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = Icons.Filled.CloudOff,
                            contentDescription = "Error",
                            modifier = Modifier.size(48.dp),
                            tint = MaterialTheme.colorScheme.error
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = uiState.errorMessage ?: "Unknown error",
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyLarge
                        )
                        Spacer(Modifier.height(16.dp))
                        OutlinedButton(onClick = { viewModel.fetchAgenda(uiState.span) }) {
                            Text("Retry")
                        }
                    }
                }
            }

            uiState.groups.isEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = Icons.Filled.EventAvailable,
                            contentDescription = "No items",
                            modifier = Modifier.size(48.dp),
                            tint = MaterialTheme.colorScheme.outline
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "Agenda is clear!",
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.outline
                        )
                    }
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                    contentPadding = PaddingValues(bottom = 80.dp)
                ) {
                    uiState.groups.forEach { group ->
                        // Date header
                        item(key = "header_${group.date}") {
                            AgendaDateHeader(
                                date = group.date,
                                isToday = group.date == todayStr
                            )
                        }

                        // Items for this date
                        items(
                            items = group.items,
                            key = { "${group.date}_${it.id}" }
                        ) { item ->
                            AgendaItemCard(
                                item = item,
                                todayStr = todayStr,
                                onClick = { onNavigateToTask(item.id) },
                                onToggleTodo = {
                                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                    viewModel.cycleTodoState(item.id)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AgendaDateHeader(date: String, isToday: Boolean) {
    val displayDate = remember(date) {
        try {
            val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val parsed = sdf.parse(date)
            val dayFmt = SimpleDateFormat("EEEE, MMM d", Locale.US)
            if (parsed != null) dayFmt.format(parsed) else date
        } catch (e: Exception) {
            date
        }
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 16.dp, bottom = 8.dp)
    ) {
        if (isToday) {
            Surface(
                shape = RoundedCornerShape(6.dp),
                color = MaterialTheme.colorScheme.primary
            ) {
                Text(
                    text = "TODAY",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
                )
            }
            Spacer(Modifier.width(8.dp))
        }
        Text(
            text = displayDate,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = if (isToday)
                MaterialTheme.colorScheme.primary
            else
                MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun AgendaItemCard(
    item: AgendaItem,
    todayStr: String,
    onClick: () -> Unit = {},
    onToggleTodo: () -> Unit
) {
    val isDone = item.todo.equals("DONE", ignoreCase = true) ||
                 item.todo.equals("CANCELLED", ignoreCase = true)

    val isOverdue = !isDone && item.effectiveDate.isNotEmpty() && item.effectiveDate < todayStr
    val isDeadline = item.itemType == "deadline"

    val cardColor by animateColorAsState(
        targetValue = when {
            isDone -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
            isOverdue -> MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.4f)
            isDeadline -> MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.2f)
            else -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)
        },
        label = "cardColor"
    )

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .clickable { onClick() },
        colors = CardDefaults.cardColors(containerColor = cardColor),
        shape = RoundedCornerShape(8.dp),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Type indicator strip
            Box(
                modifier = Modifier
                    .width(3.dp)
                    .height(40.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(
                        when {
                            isOverdue -> MaterialTheme.colorScheme.error
                            isDeadline -> MaterialTheme.colorScheme.tertiary
                            item.itemType == "scheduled" -> MaterialTheme.colorScheme.primary
                            else -> MaterialTheme.colorScheme.outline
                        }
                    )
            )

            Spacer(Modifier.width(12.dp))

            // TODO state toggle
            IconButton(
                onClick = onToggleTodo,
                modifier = Modifier.size(32.dp)
            ) {
                Icon(
                    imageVector = if (isDone) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                    contentDescription = "Toggle state",
                    tint = when {
                        isDone -> MaterialTheme.colorScheme.primary
                        isOverdue -> MaterialTheme.colorScheme.error
                        item.todo == "NEXT" -> MaterialTheme.colorScheme.tertiary
                        item.todo == "WAITING" -> MaterialTheme.colorScheme.secondary
                        else -> MaterialTheme.colorScheme.outline
                    },
                    modifier = Modifier.size(20.dp)
                )
            }

            Spacer(Modifier.width(8.dp))

            // Title + metadata
            Column(modifier = Modifier.weight(1f)) {
                // TODO state badge + title row
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (item.todo.isNotEmpty()) {
                        val stateColor = OrgTheme.todoStateColor(item.todo, isDone)
                        Text(
                            text = item.todo,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isOverdue && !isDone) MaterialTheme.colorScheme.error else stateColor,
                            modifier = Modifier.padding(end = 6.dp)
                        )
                    }

                    // Priority
                    if (item.priority.isNotEmpty() && item.priority != "B") {
                        val priColor = OrgTheme.priorityColor(item.priority)
                        Text(
                            text = "[#${item.priority}]",
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = priColor,
                            modifier = Modifier.padding(end = 6.dp)
                        )
                    }

                    Text(
                        text = item.title,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textDecoration = if (isDone) TextDecoration.LineThrough else TextDecoration.None,
                        color = when {
                            isDone -> MaterialTheme.colorScheme.outline
                            isOverdue -> MaterialTheme.colorScheme.onErrorContainer
                            else -> MaterialTheme.colorScheme.onSurface
                        }
                    )
                }

                // Metadata row
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(top = 2.dp)
                ) {
                    // Category
                    if (item.category.isNotEmpty()) {
                        Text(
                            text = item.category,
                            fontSize = 10.sp,
                            color = MaterialTheme.colorScheme.outline
                        )
                    }

                    // Tags
                    item.tags.forEach { tag ->
                        Surface(
                            shape = RoundedCornerShape(3.dp),
                            color = MaterialTheme.colorScheme.secondaryContainer
                        ) {
                            Text(
                                text = tag,
                                fontSize = 9.sp,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                                modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
                            )
                        }
                    }

                    // Effort
                    if (item.effort.isNotEmpty()) {
                        Text(
                            text = "⏱ ${item.effort}",
                            fontSize = 10.sp,
                            color = MaterialTheme.colorScheme.outline
                        )
                    }
                }
            }

            // Deadline/Scheduled indicator icon
            if (isOverdue) {
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = "Overdue",
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(16.dp)
                )
            } else if (isDeadline) {
                Icon(
                    imageVector = Icons.Filled.Event,
                    contentDescription = "Deadline",
                    tint = MaterialTheme.colorScheme.tertiary,
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
}
