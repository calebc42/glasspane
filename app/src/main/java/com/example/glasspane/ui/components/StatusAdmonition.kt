package com.example.glasspane.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

enum class EmacsServerStatus {
    CONNECTED, SYNCING, ERROR, OFFLINE
}

@Composable
fun StatusAdmonition(
    status: EmacsServerStatus,
    message: String,
    modifier: Modifier = Modifier
) {
    val backgroundColor: Color
    val borderColor: Color
    val iconVector: ImageVector

    when (status) {
        EmacsServerStatus.CONNECTED -> {
            backgroundColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
            borderColor = MaterialTheme.colorScheme.primary
            iconVector = Icons.Filled.CloudDone
        }
        EmacsServerStatus.SYNCING -> {
            backgroundColor = MaterialTheme.colorScheme.secondary.copy(alpha = 0.15f)
            borderColor = MaterialTheme.colorScheme.secondary
            iconVector = Icons.Filled.Sync
        }
        EmacsServerStatus.ERROR, EmacsServerStatus.OFFLINE -> {
            backgroundColor = MaterialTheme.colorScheme.error.copy(alpha = 0.15f)
            borderColor = MaterialTheme.colorScheme.error
            iconVector = Icons.Filled.CloudOff
        }
    }

    Surface(
        shape = RoundedCornerShape(8.dp),
        tonalElevation = 2.dp,
        border = BorderStroke(1.dp, borderColor),
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .background(backgroundColor)
                .padding(16.dp)
        ) {
            Icon(
                imageVector = iconVector,
                contentDescription = status.name,
                tint = borderColor,
                modifier = Modifier.padding(end = 12.dp)
            )
            Text(
                text = message,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
    }
}