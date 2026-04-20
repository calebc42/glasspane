package com.example.glasspane.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.glasspane.ui.viewmodels.DashboardViewModel
import com.example.glasspane.ui.viewmodels.OrgTask

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RefileDialog(
    sourceNodeId: String,
    onDismiss: () -> Unit,
    onRefile: (targetId: String) -> Unit,
    viewModel: DashboardViewModel = viewModel()
) {
    val tasks by viewModel.tasks.collectAsState()
    val currentParentId by viewModel.currentParentId.collectAsState()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (currentParentId != null) {
                    IconButton(onClick = { viewModel.goBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    text = if (currentParentId == null) "Select Refile Target" else "Select Child Node",
                    style = MaterialTheme.typography.titleLarge
                )
            }
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 400.dp)
            ) {
                LazyColumn {
                    items(tasks, key = { it.id }) { task ->
                        NodePickerItem(
                            task = task,
                            onDrillDown = { viewModel.fetchTasks(task.id) },
                            onSelect = { onRefile(task.id) },
                            isSourceNode = task.id == sourceNodeId
                        )
                    }
                }
            }
        },
        confirmButton = {
            if (currentParentId != null) {
                Button(onClick = { onRefile(currentParentId!!) }) {
                    Text("Refile Here")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
        shape = RoundedCornerShape(24.dp)
    )
}

@Composable
fun NodePickerItem(
    task: OrgTask,
    onDrillDown: () -> Unit,
    onSelect: () -> Unit,
    isSourceNode: Boolean
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        shape = RoundedCornerShape(8.dp),
        color = if (isSourceNode) MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f) else MaterialTheme.colorScheme.surface,
        onClick = if (task.hasChildren) onDrillDown else onSelect,
        enabled = !isSourceNode
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = task.title,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (isSourceNode) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface
                )
                if (isSourceNode) {
                    Text(
                        text = "Cannot refile to itself",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
            if (task.hasChildren && !isSourceNode) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedButton(
                        onClick = onSelect,
                        modifier = Modifier.padding(end = 8.dp),
                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text("Select")
                    }
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = "Drill Down",
                        tint = MaterialTheme.colorScheme.outline
                    )
                }
            }
        }
    }
}
