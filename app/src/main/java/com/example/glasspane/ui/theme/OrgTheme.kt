package com.example.glasspane.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * Shared color mapping for Org-mode concepts (TODO states, priorities).
 *
 * These were previously duplicated across TaskCard, AgendaScreen, and SearchScreen.
 * Centralizing them here ensures consistent styling and a single place to update.
 */
object OrgTheme {

    /**
     * Color for a TODO keyword state.
     * Call this from a @Composable context to access MaterialTheme colors.
     */
    @Composable
    fun todoStateColor(state: String, isDone: Boolean): Color = when {
        isDone -> MaterialTheme.colorScheme.primary
        state == "NEXT" -> MaterialTheme.colorScheme.tertiary
        state == "WAITING" -> MaterialTheme.colorScheme.secondary
        state == "TODO" -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.outline
    }

    /**
     * Color for an Org priority marker ([#A], [#B], [#C]).
     */
    @Composable
    fun priorityColor(priority: String): Color = when (priority) {
        "A" -> Color(0xFFE53935)  // Red
        "C" -> Color(0xFF43A047)  // Green
        else -> MaterialTheme.colorScheme.outline
    }
}
