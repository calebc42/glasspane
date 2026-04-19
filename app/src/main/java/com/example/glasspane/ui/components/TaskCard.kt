package com.example.glasspane.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
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
    hasChildren: Boolean, // NEW
    onCardClick: () -> Unit, // NEW
    onToggleStatus: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier
) {
    ElevatedCard(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .clickable { onCardClick() }, // Make the whole card tappable
        shape = MaterialTheme.shapes.small
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp)
        ) {
            // Left Status Icon (Only show if it doesn't have children, meaning it's a leaf task)
            if (!hasChildren) {
                IconButton(onClick = onToggleStatus) {
                    Icon(
                        imageVector = if (isDone) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                        contentDescription = "Toggle Status",
                        tint = if (isDone) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                    )
                }
            } else {
                // Spacer to keep text aligned if there is no checkbox
                Spacer(Modifier.width(12.dp))
            }

            // Task/File Title
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                color = if (isDone) MaterialTheme.colorScheme.outline else MaterialTheme.colorScheme.onSurface,
                textDecoration = if (isDone) TextDecoration.LineThrough else TextDecoration.None,
                modifier = Modifier.padding(start = 4.dp)
            )

            Spacer(Modifier.weight(1f))

            // Right Action Icon: Show an arrow if we can drill down, otherwise show delete
            if (hasChildren) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = "Open",
                    tint = MaterialTheme.colorScheme.outline,
                    modifier = Modifier.padding(end = 12.dp)
                )
            } else {
                IconButton(onClick = onDelete) {
                    Icon(
                        imageVector = Icons.Filled.Delete,
                        contentDescription = "Delete Task",
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
    }
}