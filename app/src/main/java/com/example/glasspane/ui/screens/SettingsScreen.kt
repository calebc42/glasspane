package com.example.glasspane.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.glasspane.ui.viewmodels.ConfigTemplate
import com.example.glasspane.ui.viewmodels.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel(),
    onNavigateBack: (() -> Unit)? = null
) {
    val templates by viewModel.templates.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    
    // We maintain a local editable copy of templates so the user can modify them before batch saving.
    var editableTemplates by remember { mutableStateOf<List<ConfigTemplate>>(emptyList()) }
    var editableTags by remember { mutableStateOf<List<String>>(emptyList()) }
    var editableTodos by remember { mutableStateOf<List<String>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    
    val tags by viewModel.tags.collectAsState()
    val todos by viewModel.todos.collectAsState()

    var selectedTab by remember { mutableStateOf(0) }
    val tabs = listOf("Templates", "Tags", "TODO States")

    LaunchedEffect(templates, tags, todos) {
        if (!loaded && templates.isNotEmpty()) {
            editableTemplates = templates.toList()
            editableTags = tags.toList()
            editableTodos = todos.toList()
            loaded = true
        }
    }

    Scaffold(
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { viewModel.saveConfig(editableTemplates, editableTags, editableTodos) },
                icon = { Icon(Icons.Filled.Save, "Save Configuration") },
                text = { Text("Sync Config") }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(vertical = 16.dp)
            ) {
                if (onNavigateBack != null) {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Back")
                    }
                    Spacer(Modifier.width(8.dp))
                }
                Text(
                    text = "Configurations",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(Modifier.weight(1f))
                if (isLoading) {
                    CircularProgressIndicator(modifier = Modifier.size(24.dp))
                } else {
                    IconButton(onClick = {
                        when (selectedTab) {
                            0 -> editableTemplates = editableTemplates + ConfigTemplate("", "", "", "")
                            1 -> editableTags = editableTags + ""
                            2 -> editableTodos = editableTodos + ""
                        }
                    }) {
                        Icon(Icons.Filled.Add, "Add Item")
                    }
                }
            }

            TabRow(selectedTabIndex = selectedTab) {
                tabs.forEachIndexed { index, title ->
                    Tab(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        text = { Text(title) }
                    )
                }
            }
            Spacer(Modifier.height(16.dp))

            when (selectedTab) {
                0 -> {
                    if (editableTemplates.isEmpty() && !isLoading) {
                        Text("No templates found.", color = MaterialTheme.colorScheme.outline)
                    } else {
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(bottom = 80.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    itemsIndexed(editableTemplates) { index, tmpl ->
                        Card(
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha=0.5f))
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    OutlinedTextField(
                                        value = tmpl.id,
                                        onValueChange = { newVal ->
                                            val mt = editableTemplates.toMutableList()
                                            mt[index] = tmpl.copy(id = newVal)
                                            editableTemplates = mt
                                        },
                                        label = { Text("Key (e.g. 't')") },
                                        modifier = Modifier.weight(1f).padding(end = 8.dp),
                                        singleLine = true
                                    )
                                    IconButton(onClick = {
                                        val mt = editableTemplates.toMutableList()
                                        mt.removeAt(index)
                                        editableTemplates = mt
                                    }) {
                                        Icon(Icons.Filled.Delete, "Delete", tint = MaterialTheme.colorScheme.error)
                                    }
                                }

                                Spacer(Modifier.height(8.dp))
                                OutlinedTextField(
                                    value = tmpl.title,
                                    onValueChange = { newVal ->
                                        val mt = editableTemplates.toMutableList()
                                        mt[index] = tmpl.copy(title = newVal)
                                        editableTemplates = mt
                                    },
                                    label = { Text("Title (e.g. 'Quick Task')") },
                                    modifier = Modifier.fillMaxWidth(),
                                    singleLine = true
                                )

                                Spacer(Modifier.height(8.dp))
                                OutlinedTextField(
                                    value = tmpl.file,
                                    onValueChange = { newVal ->
                                        val mt = editableTemplates.toMutableList()
                                        mt[index] = tmpl.copy(file = newVal)
                                        editableTemplates = mt
                                    },
                                    label = { Text("Target File (e.g. '~/inbox.org')") },
                                    modifier = Modifier.fillMaxWidth(),
                                    singleLine = true
                                )

                                Spacer(Modifier.height(8.dp))
                                OutlinedTextField(
                                    value = tmpl.content,
                                    onValueChange = { newVal ->
                                        val mt = editableTemplates.toMutableList()
                                        mt[index] = tmpl.copy(content = newVal)
                                        editableTemplates = mt
                                    },
                                    label = { Text("Template Content (* TODO %^{Task})") },
                                    modifier = Modifier.fillMaxWidth(),
                                    minLines = 3
                                )
                            }
                        }
                    }
                }
            }
        }
                1 -> {
                    LazyColumn(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        itemsIndexed(editableTags) { index, tag ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                OutlinedTextField(
                                    value = tag,
                                    onValueChange = { newVal ->
                                        val mt = editableTags.toMutableList()
                                        mt[index] = newVal
                                        editableTags = mt
                                    },
                                    label = { Text("Tag name (without ':')") },
                                    modifier = Modifier.weight(1f),
                                    singleLine = true
                                )
                                IconButton(onClick = {
                                    val mt = editableTags.toMutableList()
                                    mt.removeAt(index)
                                    editableTags = mt
                                }) { Icon(Icons.Filled.Delete, "Delete", tint = MaterialTheme.colorScheme.error) }
                            }
                        }
                    }
                }
                2 -> {
                    LazyColumn(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        item { Text("Order matters. Use '|' to separate active workflows vs closed (e.g. TODO, WAITING, |, DONE)", style = MaterialTheme.typography.bodySmall) }
                        itemsIndexed(editableTodos) { index, td ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                OutlinedTextField(
                                    value = td,
                                    onValueChange = { newVal ->
                                        val mt = editableTodos.toMutableList()
                                        mt[index] = newVal
                                        editableTodos = mt
                                    },
                                    label = { Text("TODO state (e.g. 'NEXT')") },
                                    modifier = Modifier.weight(1f),
                                    singleLine = true
                                )
                                IconButton(onClick = {
                                    val mt = editableTodos.toMutableList()
                                    mt.removeAt(index)
                                    editableTodos = mt
                                }) { Icon(Icons.Filled.Delete, "Delete", tint = MaterialTheme.colorScheme.error) }
                            }
                        }
                    }
                }
            }
        }
    }
}
