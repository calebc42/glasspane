package com.example.glasspane.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp

@Composable
fun TaskCard(
    title: String,
    isDone: Boolean,
    onToggleStatus: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier
) {
    ElevatedCard(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        shape = MaterialTheme.shapes.small // Harp's standard shape
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp) // Internal padding
        ) {
            // Left Status Icon (TODO vs DONE)
            IconButton(onClick = onToggleStatus) {
                Icon(
                    imageVector = if (isDone) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                    contentDescription = "Toggle Status",
                    tint = if (isDone) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                )
            }

            // Task Title
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                color = if (isDone) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
                textDecoration = if (isDone) TextDecoration.LineThrough else TextDecoration.None,
                modifier = Modifier.padding(start = 4.dp)
            )

            // The spacer weight pushes the delete button to the far right edge
            Spacer(Modifier.weight(1f))

            // Right Action Icon (Delete)
            IconButton(onClick = onDelete) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = "Delete Task",
                    tint = MaterialTheme.colorScheme.error // Semantic error color
                )
            }
        }
    }
}