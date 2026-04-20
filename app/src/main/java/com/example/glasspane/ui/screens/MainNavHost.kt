package com.example.glasspane.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector

// ─── Navigation tabs ─────────────────────────────────────────────────────────

enum class GlasspaneTab(
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector
) {
    AGENDA("Agenda", Icons.Filled.CalendarMonth, Icons.Filled.CalendarMonth),
    TREE("Files", Icons.Filled.AccountTree, Icons.Filled.AccountTree),
    SEARCH("Search", Icons.Filled.Search, Icons.Filled.Search)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainNavHost() {
    var selectedTab by remember { mutableStateOf(GlasspaneTab.AGENDA) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = when (selectedTab) {
                            GlasspaneTab.AGENDA -> "Agenda"
                            GlasspaneTab.TREE -> "Glasspane"
                            GlasspaneTab.SEARCH -> "Search"
                        }
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        },
        bottomBar = {
            NavigationBar {
                GlasspaneTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        icon = {
                            Icon(
                                imageVector = if (selectedTab == tab) tab.selectedIcon else tab.icon,
                                contentDescription = tab.label
                            )
                        },
                        label = { Text(tab.label) }
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(modifier = Modifier.padding(innerPadding)) {
            when (selectedTab) {
                GlasspaneTab.AGENDA -> AgendaScreen()
                GlasspaneTab.TREE -> DashboardScreen()
                GlasspaneTab.SEARCH -> SearchScreen()
            }
        }
    }
}
