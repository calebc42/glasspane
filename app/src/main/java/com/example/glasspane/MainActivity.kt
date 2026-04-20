package com.example.glasspane

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import java.util.TimeZone
import java.util.Date
import java.text.SimpleDateFormat
import com.example.glasspane.ui.theme.GlasspaneTheme
import com.example.glasspane.ui.screens.MainNavHost

val okHttpClient = OkHttpClient()

// ─── Data model for a Capture Template field ────────────────────────────────
data class CaptureField(val key: String, val label: String, val hint: String = "")

// ─── Data model for a Capture Template ──────────────────────────────────────
data class CaptureTemplate(
    val id: String,
    val title: String,
    val endpoint: String,
    val fields: List<CaptureField>
)

// ─── Active clock state ───────────────────────────────────────────────────────
// activeClockId == null  → nothing is clocked in
// activeClockId == "xyz" → the org-id of the currently clocked-in node
data class ClockState(val activeClockId: String?)

// ─── Navigation back-stack entry ─────────────────────────────────────────────
typealias NodeId = String?

class MainActivity : ComponentActivity() {
    // Android 13+ requires POST_NOTIFICATIONS to be requested at runtime.
    // We register the launcher unconditionally; it only fires on API 33+.
    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            // Permission granted or denied — either way we proceed.
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Phase 4.1: Edge-to-Edge support
        enableEdgeToEdge()

        // Ask for notification permission on first launch (API 33+ only).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        // Force a background sync every time the app is opened
        val syncRequest = OneTimeWorkRequestBuilder<SyncWorker>()
            .setConstraints(
                androidx.work.Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .build()

        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            "glasspane_sync",
            ExistingWorkPolicy.REPLACE,
            syncRequest
        )

        setContent {
            GlasspaneTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    MainNavHost()
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlasspaneApp() {
    val navStack: SnapshotStateList<NodeId> = remember { mutableStateListOf(null) }
    val currentNodeId: NodeId by remember { derivedStateOf { navStack.last() } }
    var viewRefreshTrigger by remember { mutableIntStateOf(0) }

    val onDrillDown: (String) -> Unit = { id -> navStack.add(id) }
    val onNavigateUp: () -> Unit = { if (navStack.size > 1) navStack.removeLastOrNull() }

    // ── Capture template state ────────────────────────────────────────────────
    var captureTemplates by remember { mutableStateOf<List<CaptureTemplate>>(emptyList()) }
    var showTemplateChooser by remember { mutableStateOf(false) }
    var activeTemplate by remember { mutableStateOf<CaptureTemplate?>(null) }

    // ── Active clock state — shared across the whole composable tree ──────────
    var clockState by remember { mutableStateOf(ClockState(null)) }
    val coroutineScope = rememberCoroutineScope()

    // Fetch the current clock state from Emacs (called on launch and after clock actions)
    suspend fun fetchClockState() {
        withContext(Dispatchers.IO) {
            try {
                val request = Request.Builder().url("http://127.0.0.1:8080/glasspane-clock-status").build()
                val response = okHttpClient.newCall(request).execute()
                val jsonStr = response.body?.string() ?: "{}"
                val json = JSONObject(jsonStr)
                val id = json.optString("active_id").takeIf { it.isNotEmpty() }
                clockState = ClockState(id)
            } catch (_: Exception) {
                // Server unreachable — leave clock state unchanged
            }
        }
    }

    val snackbarHostState = remember { SnackbarHostState() }

    val showSnackbar: (String) -> Unit = { message ->
        coroutineScope.launch { snackbarHostState.showSnackbar(message) }
    }

    // Callback passed down so child composables can refresh clock state after an action
    val onClockAction: () -> Unit = {
        coroutineScope.launch { fetchClockState() }
    }

    // ── Fetch capture templates + initial clock state once ───────────────────
    LaunchedEffect(Unit) {
        // Run both in parallel
        launch {
            withContext(Dispatchers.IO) {
                try {
                    val request = Request.Builder().url("http://127.0.0.1:8080/glasspane-capture-templates").build()
                    val response = okHttpClient.newCall(request).execute()
                    val json = response.body?.string() ?: "[]"
                    val arr = JSONArray(json)
                    captureTemplates = (0 until arr.length()).map { i ->
                        val obj = arr.getJSONObject(i)
                        val fieldsArr = obj.optJSONArray("fields") ?: JSONArray()
                        val fields = (0 until fieldsArr.length()).map { j ->
                            val f = fieldsArr.getJSONObject(j)
                            CaptureField(
                                key = f.optString("key"),
                                label = f.optString("label"),
                                hint = f.optString("hint", "")
                            )
                        }
                        CaptureTemplate(
                            id = obj.optString("id"),
                            title = obj.optString("title"),
                            endpoint = obj.optString("endpoint"),
                            fields = fields
                        )
                    }
                } catch (e: Exception) {
                    captureTemplates = listOf(
                        CaptureTemplate(
                            id = "debug",
                            title = "Quick Note (offline fallback)",
                            endpoint = "/glasspane-capture",
                            fields = listOf(
                                CaptureField("heading", "Heading", "What's on your mind?"),
                                CaptureField("body", "Body", "Details…")
                            )
                        )
                    )
                }
            }
        }
        fetchClockState()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
        topBar = {
            TopAppBar(
                navigationIcon = {
                    if (navStack.size > 1) {
                        IconButton(onClick = onNavigateUp) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "Navigate up"
                            )
                        }
                    }
                },
                title = {
                    Column {
                        Text(if (navStack.size <= 1) "Project Glasspane" else "Glasspane")
                        // Show a subtle "● Clocked in" indicator in the top bar whenever active
                        if (clockState.activeClockId != null) {
                            Text(
                                text = "● Clocked in",
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            )
        },
        floatingActionButton = {
            if (captureTemplates.isNotEmpty()) {
                FloatingActionButton(onClick = {
                    if (captureTemplates.size == 1) {
                        activeTemplate = captureTemplates.first()
                    } else {
                        showTemplateChooser = true
                    }
                }) {
                    Icon(Icons.Filled.Add, contentDescription = "New capture")
                }
            }
        }
    ) { paddingValues ->
        Box(modifier = Modifier.padding(paddingValues)) {
            key(currentNodeId) {
                RenderView(
                    nodeId = currentNodeId,
                    refreshTrigger = viewRefreshTrigger,
                    clockState = clockState,
                    onDrillDown = onDrillDown,
                    onSnackbar = showSnackbar,
                    onClockAction = onClockAction
                )
            }
        }
    }

    if (showTemplateChooser) {
        AlertDialog(
            onDismissRequest = { showTemplateChooser = false },
            title = { Text("Choose capture type") },
            text = {
                Column {
                    captureTemplates.forEach { template ->
                        TextButton(
                            onClick = {
                                showTemplateChooser = false
                                activeTemplate = template
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(template.title, modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showTemplateChooser = false }) { Text("Cancel") }
            }
        )
    }

    activeTemplate?.let { template ->
        CaptureDialog(
            template = template,
            onDismiss = { activeTemplate = null },
            onSubmit = { fieldValues ->
                activeTemplate = null
                coroutineScope.launch {
                    val result = withContext(Dispatchers.IO) {
                        try {
                            val formBuilder = FormBody.Builder()
                            formBuilder.add("id", template.id)
                            fieldValues.forEach { (k, v) -> formBuilder.add(k, v) }
                            val request = Request.Builder()
                                .url("http://127.0.0.1:8080${template.endpoint}")
                                .post(formBuilder.build())
                                .build()
                            val response = okHttpClient.newCall(request).execute()
                            val code = response.code
                            if (code in 200..299) "success" else "http_error:$code"
                        } catch (e: Exception) {
                            "error:${e.message}"
                        }
                    }
                    when {
                        result == "success" -> {
                            showSnackbar("Capture saved ✓")
                            viewRefreshTrigger++
                        }
                        result.startsWith("http_error") ->
                            showSnackbar("Emacs returned ${result.substringAfter(":")} — check your handler")
                        else ->
                            showSnackbar("Connection refused — is the daemon running?")
                    }
                }
            }
        )
    }
}

// ─── View loader ──────────────────────────────────────────────────────────────
@Composable
fun RenderView(
    nodeId: NodeId,
    refreshTrigger: Int = 0,
    clockState: ClockState,
    onDrillDown: (String) -> Unit,
    onSnackbar: (String) -> Unit,
    onClockAction: () -> Unit
) {
    var viewJson by remember { mutableStateOf<JSONObject?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var internalRefresh by remember { mutableIntStateOf(0) }

    LaunchedEffect(refreshTrigger, internalRefresh) {
        viewJson = null
        errorMessage = null
        withContext(Dispatchers.IO) {
            try {
                val urlBuilder = "http://127.0.0.1:8080/glasspane-view".toHttpUrlOrNull()?.newBuilder()
                if (!nodeId.isNullOrEmpty()) {
                    urlBuilder?.addQueryParameter("id", nodeId)
                }
                val request = Request.Builder().url(urlBuilder?.build() ?: throw Exception("Invalid URL")).build()
                val response = okHttpClient.newCall(request).execute()
                viewJson = JSONObject(response.body?.string() ?: "{}")
            } catch (e: Exception) {
                errorMessage = "Connection failed: ${e.message}"
            }
        }
    }

    when {
        errorMessage != null ->
            Text(
                text = errorMessage!!,
                modifier = Modifier.padding(16.dp),
                color = MaterialTheme.colorScheme.error
            )

        viewJson != null -> {
            val json = viewJson!!
            val viewTitle = json.optString("view_title", "")
            val elements: JSONArray = json.optJSONArray("elements") ?: JSONArray()

            LazyColumn(
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .fillMaxSize(),
                contentPadding = PaddingValues(vertical = 16.dp)
            ) {
                if (viewTitle.isNotBlank()) {
                    item {
                        Text(
                            text = viewTitle,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                    }
                }

                items(elements.length()) { i ->
                    val element = elements.getJSONObject(i)
                    when (element.optString("type")) {
                        "Node" -> RenderNode(
                            element = element,
                            clockState = clockState,
                            onDrillDown = onDrillDown,
                            onRefresh = { internalRefresh++ },
                            onSnackbar = onSnackbar,
                            onClockAction = onClockAction
                        )
                        else -> RenderElement(
                            element = element,
                            clockState = clockState,
                            onRefresh = { internalRefresh++ },
                            onSnackbar = onSnackbar,
                            onClockAction = onClockAction
                        )
                    }
                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 4.dp),
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                    )
                }
            }
        }

        else ->
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
    }
}

// ─── Capture form dialog ──────────────────────────────────────────────────────
@Composable
fun CaptureDialog(
    template: CaptureTemplate,
    onDismiss: () -> Unit,
    onSubmit: (Map<String, String>) -> Unit
) {
    val fieldValues = remember {
        mutableStateMapOf<String, String>().apply {
            template.fields.forEach { put(it.key, "") }
        }
    }
    var isSubmitting by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = { if (!isSubmitting) onDismiss() },
        title = { Text(template.title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                template.fields.forEach { field ->
                    OutlinedTextField(
                        value = fieldValues[field.key] ?: "",
                        onValueChange = { fieldValues[field.key] = it },
                        label = { Text(field.label) },
                        placeholder = if (field.hint.isNotBlank()) ({ Text(field.hint) }) else null,
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !isSubmitting
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    isSubmitting = true
                    onSubmit(fieldValues.toMap())
                },
                enabled = !isSubmitting
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                } else {
                    Text("Save")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isSubmitting) { Text("Cancel") }
        }
    )
}

// ─── Node renderer ────────────────────────────────────────────────────────────
@Composable
fun RenderNode(
    element: JSONObject,
    clockState: ClockState,
    onRefresh: () -> Unit,
    onSnackbar: (String) -> Unit,
    onDrillDown: (String) -> Unit,
    onClockAction: () -> Unit
) {
    val id = element.optString("id")
    val hasChildren = element.optBoolean("has_children", false)
    val childElements = element.optJSONArray("elements") ?: JSONArray()
    val isActiveClock = clockState.activeClockId == id

    val todo = element.optString("todo")
    val priority = element.optString("priority")
    val tags = element.optJSONArray("tags")
    val currentTitle = remember(childElements) {
        var t = ""
        for (i in 0 until childElements.length()) {
            val el = childElements.getJSONObject(i)
            if (el.optString("type") == "Text" && el.optString("size") == "Title") {
                t = el.optString("value")
                break
            }
        }
        t
    }

    var showAddDialog by remember { mutableStateOf<String?>(null) }
    var showEditTitleDialog by remember { mutableStateOf(false) }
    var showSetPriorityDialog by remember { mutableStateOf(false) }
    var showSetTagsDialog by remember { mutableStateOf(false) }
    var showAddPropertyDialog by remember { mutableStateOf(false) }

    var titleInput by remember { mutableStateOf("") }
    var priorityInput by remember { mutableStateOf("") }
    var tagsInput by remember { mutableStateOf("") }
    var propKeyInput by remember { mutableStateOf("") }
    var propValInput by remember { mutableStateOf("") }

    val coroutineScope = rememberCoroutineScope()
    
    val executeTreeAction: (String, String?) -> Unit = { action, title ->
        coroutineScope.launch {
            val formBuilder = FormBody.Builder()
            formBuilder.add("id", id)
            formBuilder.add("action", action)
            if (title != null) formBuilder.add("title", title)
            val request = Request.Builder()
                .url("http://127.0.0.1:8080/glasspane-tree-edit")
                .post(formBuilder.build())
                .build()
            withContext(Dispatchers.IO) {
                try {
                    okHttpClient.newCall(request).execute()
                } catch (e: Exception) {}
            }
            onRefresh()
            onSnackbar("Action: $action")
        }
    }

    val executeNetworkEdit: (String, Map<String, String>) -> Unit = { endpoint, params ->
        coroutineScope.launch {
            val formBuilder = FormBody.Builder().add("id", id)
            params.forEach { (k, v) -> formBuilder.add(k, v) }
            val request = Request.Builder()
                .url("http://127.0.0.1:8080$endpoint")
                .post(formBuilder.build())
                .build()
            withContext(Dispatchers.IO) {
                try {
                    okHttpClient.newCall(request).execute()
                } catch (e: Exception) {}
            }
            onRefresh()
            onSnackbar("Updated successfully")
        }
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .clickable(enabled = id.isNotEmpty()) { onDrillDown(id) },
        colors = CardDefaults.cardColors(
            // Highlight the card green when this node is currently clocked in
            containerColor = if (isActiveClock)
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
            else
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                // Active-clock badge shown above the node title
                if (isActiveClock) {
                    Text(
                        text = "● Clocked in",
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(bottom = 4.dp)
                    )
                }

                // Inline Chips
                if (todo.isNotEmpty() || priority.isNotEmpty() || (tags != null && tags.length() > 0)) {
                    Row(
                        modifier = Modifier.padding(bottom = 6.dp).horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        if (todo.isNotEmpty()) {
                            Surface(color = MaterialTheme.colorScheme.errorContainer, shape = MaterialTheme.shapes.small) {
                                Text(todo, color = MaterialTheme.colorScheme.onErrorContainer, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                            }
                        }
                        if (priority.isNotEmpty()) {
                            Surface(color = MaterialTheme.colorScheme.tertiaryContainer, shape = MaterialTheme.shapes.small) {
                                Text("[$priority]", color = MaterialTheme.colorScheme.onTertiaryContainer, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                            }
                        }
                        if (tags != null && tags.length() > 0) {
                            for (i in 0 until tags.length()) {
                                Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = MaterialTheme.shapes.small) {
                                    Text(":${tags.getString(i)}:", color = MaterialTheme.colorScheme.onSecondaryContainer, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp))
                                }
                            }
                        }
                    }
                }

                for (i in 0 until childElements.length()) {
                    // Pass onClockAction down; stop click propagation inside RenderElement
                    // by wrapping buttons in a non-propagating container (handled in RenderElement).
                    RenderElement(
                        element = childElements.getJSONObject(i),
                        clockState = clockState,
                        onRefresh = onRefresh,
                        onSnackbar = onSnackbar,
                        onClockAction = onClockAction,
                        nodeId = id
                    )
                    if (i < childElements.length() - 1) {
                        Spacer(modifier = Modifier.height(8.dp))
                    }
                }
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                if (hasChildren) {
                    Icon(
                        imageVector = Icons.Filled.ChevronRight,
                        contentDescription = "Has children",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                var expanded by remember { mutableStateOf(false) }
                Box {
                    IconButton(onClick = { expanded = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "Options")
                    }
                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                        DropdownMenuItem(text = { Text("Edit Title") }, onClick = { expanded = false; titleInput = currentTitle; showEditTitleDialog = true })
                        DropdownMenuItem(text = { Text("Set Priority") }, onClick = { expanded = false; priorityInput = priority; showSetPriorityDialog = true })
                        DropdownMenuItem(text = { Text("Set Tags") }, onClick = { 
                            expanded = false
                            val tagsList = mutableListOf<String>()
                            if (tags != null) for (i in 0 until tags.length()) tagsList.add(tags.getString(i))
                            tagsInput = if(tagsList.isEmpty()) "" else ":" + tagsList.joinToString(":") + ":"
                            showSetTagsDialog = true 
                        })
                        DropdownMenuItem(text = { Text("Add Property") }, onClick = { expanded = false; propKeyInput = ""; propValInput = ""; showAddPropertyDialog = true })
                        HorizontalDivider()
                        DropdownMenuItem(text = { Text("Add Child") }, onClick = { expanded = false; titleInput = ""; showAddDialog = "insert-child" })
                        DropdownMenuItem(text = { Text("Add Sibling") }, onClick = { expanded = false; titleInput = ""; showAddDialog = "insert-sibling" })
                        DropdownMenuItem(text = { Text("Move Up") }, onClick = { expanded = false; executeTreeAction("move-up", null) })
                        DropdownMenuItem(text = { Text("Move Down") }, onClick = { expanded = false; executeTreeAction("move-down", null) })
                        DropdownMenuItem(text = { Text("Promote") }, onClick = { expanded = false; executeTreeAction("promote", null) })
                        DropdownMenuItem(text = { Text("Demote") }, onClick = { expanded = false; executeTreeAction("demote", null) })
                    }
                }
            }
        }
    }

    if (showAddDialog != null) {
        AlertDialog(
            onDismissRequest = { showAddDialog = null },
            title = { Text(if (showAddDialog == "insert-child") "Add Child Node" else "Add Sibling Node") },
            text = {
                OutlinedTextField(
                    value = titleInput,
                    onValueChange = { titleInput = it },
                    label = { Text("Heading Title") },
                    singleLine = true
                )
            },
            confirmButton = {
                Button(onClick = {
                    val action = showAddDialog!!
                    showAddDialog = null
                    executeTreeAction(action, titleInput)
                    titleInput = ""
                }) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { showAddDialog = null }) { Text("Cancel") }
            }
        )
    }

    if (showEditTitleDialog) {
        AlertDialog(
            onDismissRequest = { showEditTitleDialog = false },
            title = { Text("Edit Title") },
            text = { OutlinedTextField(value = titleInput, onValueChange = { titleInput = it }, singleLine = true) },
            confirmButton = {
                Button(onClick = {
                    showEditTitleDialog = false
                    executeNetworkEdit("/glasspane-update-title", mapOf("val" to titleInput))
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { showEditTitleDialog = false }) { Text("Cancel") } }
        )
    }

    if (showSetPriorityDialog) {
        AlertDialog(
            onDismissRequest = { showSetPriorityDialog = false },
            title = { Text("Set Priority") },
            text = { OutlinedTextField(value = priorityInput, onValueChange = { priorityInput = it }, label = { Text("A, B, C, or Space") }, singleLine = true) },
            confirmButton = {
                Button(onClick = {
                    showSetPriorityDialog = false
                    executeNetworkEdit("/glasspane-set-priority", mapOf("priority" to priorityInput))
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { showSetPriorityDialog = false }) { Text("Cancel") } }
        )
    }

    if (showSetTagsDialog) {
        AlertDialog(
            onDismissRequest = { showSetTagsDialog = false },
            title = { Text("Set Tags") },
            text = { OutlinedTextField(value = tagsInput, onValueChange = { tagsInput = it }, label = { Text(":tag1:tag2:") }, singleLine = true) },
            confirmButton = {
                Button(onClick = {
                    showSetTagsDialog = false
                    executeNetworkEdit("/glasspane-set-tags", mapOf("tags" to tagsInput))
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { showSetTagsDialog = false }) { Text("Cancel") } }
        )
    }

    if (showAddPropertyDialog) {
        AlertDialog(
            onDismissRequest = { showAddPropertyDialog = false },
            title = { Text("Add Property") },
            text = {
                Column {
                    OutlinedTextField(value = propKeyInput, onValueChange = { propKeyInput = it }, label = { Text("Property Key") }, singleLine = true)
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(value = propValInput, onValueChange = { propValInput = it }, label = { Text("Value") }, singleLine = true)
                }
            },
            confirmButton = {
                Button(onClick = {
                    showAddPropertyDialog = false
                    executeNetworkEdit("/glasspane-update", mapOf("prop" to propKeyInput, "val" to propValInput))
                }) { Text("Add") }
            },
            dismissButton = { TextButton(onClick = { showAddPropertyDialog = false }) { Text("Cancel") } }
        )
    }
}

// ─── Element renderer ─────────────────────────────────────────────────────────
@Composable
fun RenderElement(
    element: JSONObject,
    clockState: ClockState,
    onRefresh: () -> Unit,
    onSnackbar: (String) -> Unit,
    onClockAction: () -> Unit,
    // nodeId is passed in when we are rendering inside a RenderNode card, so the
    // Clock In/Out button can know whether *this* node is the active one.
    nodeId: String? = null
) {
    val type = element.optString("type")
    val action = element.optJSONObject("action")
    var isLoading by remember { mutableStateOf(false) }
    var showDialog by remember { mutableStateOf(false) }
    var inputText by remember { mutableStateOf("") }
    val coroutineScope = rememberCoroutineScope()

    val executeNetworkAction: (String?) -> Unit = { inputValue ->
        isLoading = true
        coroutineScope.launch {
            val endpoint = action?.optString("endpoint")
            val id = action?.optString("id")
            val prop = action?.optString("prop")

            val result = withContext(Dispatchers.IO) {
                try {
                    if (endpoint != null && id != null) {
                        val formBuilder = FormBody.Builder()
                        formBuilder.add("id", id)
                        if (!prop.isNullOrEmpty()) formBuilder.add("prop", prop)
                        if (!inputValue.isNullOrEmpty()) formBuilder.add("val", inputValue)
                        
                        val request = Request.Builder()
                            .url("http://127.0.0.1:8080$endpoint")
                            .post(formBuilder.build())
                            .build()
                        val response = okHttpClient.newCall(request).execute()
                        val code = response.code
                        if (code in 200..299) "success" else "http_error:$code"
                    } else {
                        "error:missing action params"
                    }
                } catch (e: Exception) {
                    "error:${e.message}"
                }
            }

            isLoading = false
            showDialog = false

            when {
                result == "success" -> {
                    onSnackbar("Success ✓")
                    onRefresh()
                    // If this was a clock action, also refresh the global clock state
                    val ep = action?.optString("endpoint") ?: ""
                    if (ep.contains("clock")) onClockAction()
                }
                result.startsWith("http_error") ->
                    onSnackbar("Server error ${result.substringAfter(":")}")
                else ->
                    onSnackbar("Connection refused — is the daemon running?")
            }
        }
    }

    when (type) {
        "Text" -> {
            val value = element.optString("value")
            val size = element.optString("size")
            if (size == "Title") {
                Text(text = value, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            } else {
                Text(text = value, fontSize = 16.sp)
            }
        }

        "EditableText" -> {
            val value = element.optString("value")
            var isEditing by remember { mutableStateOf(false) }
            var text by remember { mutableStateOf(value) }

            if (isEditing) {
                androidx.compose.ui.window.Dialog(
                    onDismissRequest = { if (!isLoading) isEditing = false },
                    properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)
                ) {
                    Scaffold(
                        topBar = {
                            @OptIn(ExperimentalMaterial3Api::class)
                            TopAppBar(
                                title = { Text("Edit Body") },
                                navigationIcon = {
                                    IconButton(onClick = { if (!isLoading) isEditing = false }) {
                                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Close")
                                    }
                                },
                                actions = {
                                    if (isLoading) {
                                        CircularProgressIndicator(modifier = Modifier.size(24.dp).padding(end = 16.dp))
                                    } else {
                                        Button(
                                            onClick = {
                                                executeNetworkAction(text)
                                                isEditing = false
                                            },
                                            modifier = Modifier.padding(end = 8.dp)
                                        ) {
                                            Text("Save")
                                        }
                                    }
                                }
                            )
                        }
                    ) { padding ->
                        OutlinedTextField(
                            value = text,
                            onValueChange = { text = it },
                            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
                            enabled = !isLoading,
                            placeholder = { Text("Enter notes here...") }
                        )
                    }
                }
            } else {
                if (value.isEmpty()) {
                    Text(
                        text = "Tap to add notes...",
                        fontSize = 16.sp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { isEditing = true }
                            .padding(vertical = 4.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    val lines = value.split("\n")
                    Column {
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
                                            val newText = value.replaceFirst(line, "${indent}- [$newState] $content")
                                            executeNetworkAction(newText)
                                        },
                                        modifier = Modifier.size(24.dp).padding(end = 8.dp, top = 2.dp)
                                    )
                                    Text(
                                        text = content, 
                                        fontSize = 16.sp, 
                                        modifier = Modifier.padding(top = 2.dp).fillMaxWidth().clickable { isEditing = true }
                                    )
                                }
                            } else {
                                Text(
                                    line, 
                                    fontSize = 16.sp, 
                                    modifier = Modifier.fillMaxWidth().clickable { isEditing = true }.padding(vertical = 2.dp)
                                )
                            }
                        }
                    }
                }
            }
        }

        "PropertyDrawer" -> {
            val props = element.optJSONArray("properties") ?: JSONArray()
            val actionType = element.optJSONObject("action")

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f), shape = MaterialTheme.shapes.small)
                    .padding(8.dp)
            ) {
                Text(
                    text = "PROPERTIES",
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(bottom = 4.dp)
                )
                for (i in 0 until props.length()) {
                    val propObj = props.getJSONObject(i)
                    val key = propObj.optString("key")
                    val value = propObj.optString("value")

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                actionType?.put("prop", key)
                                actionType?.put("input_prompt", "Edit $key")
                                inputText = value
                                showDialog = true
                            }
                            .padding(vertical = 4.dp)
                    ) {
                        Text(":$key:", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(value, fontSize = 14.sp)
                    }
                }
            }
        }

        "Button" -> {
            val rawLabel = element.optString("label")
            val endpoint = action?.optString("endpoint") ?: ""

            // For Clock In buttons, flip the label and endpoint based on current clock state.
            // We must also stop click propagation so tapping this button doesn't also
            // trigger the parent card's drill-down clickable.
            val isClockInButton = endpoint.contains("clock-in")
            val thisNodeIsActive = nodeId != null && clockState.activeClockId == nodeId
            val label = if (isClockInButton && thisNodeIsActive) "Clock Out" else rawLabel
            val effectiveEndpoint = if (isClockInButton && thisNodeIsActive)
                "/glasspane-clock-out" else endpoint

            // Build a modified action object when we need to redirect to clock-out
            val effectiveAction: JSONObject? = if (isClockInButton && thisNodeIsActive) {
                JSONObject().apply {
                    put("method", "POST")
                    put("endpoint", effectiveEndpoint)
                    // clock-out doesn't need an id param on our server
                    put("id", action?.optString("id") ?: "")
                    put("require_input", false)
                }
            } else {
                action
            }

            // Box with clickable(false) prevents touches on the button area from
            // bubbling up to the parent Card's drill-down handler.
            Box(modifier = Modifier.clickable(enabled = false) {}) {
                Button(
                    onClick = {
                        if (effectiveAction?.optBoolean("require_input") == true) {
                            inputText = ""
                            showDialog = true
                        } else {
                            // Re-run with the potentially overridden endpoint
                            isLoading = true
                            coroutineScope.launch {
                                val id = effectiveAction?.optString("id")
                                val ep = effectiveAction?.optString("endpoint")
                                val result = withContext(Dispatchers.IO) {
                                    try {
                                        if (ep != null) {
                                            val formBuilder = FormBody.Builder()
                                            if (!id.isNullOrEmpty()) formBuilder.add("id", id)
                                            val request = Request.Builder()
                                                .url("http://127.0.0.1:8080$ep")
                                                .post(formBuilder.build())
                                                .build()
                                            val response = okHttpClient.newCall(request).execute()
                                            val code = response.code
                                            if (code in 200..299) "success" else "http_error:$code"
                                        } else "error:missing endpoint"
                                    } catch (e: Exception) {
                                        "error:${e.message}"
                                    }
                                }
                                isLoading = false
                                when {
                                    result == "success" -> {
                                        onSnackbar("Success ✓")
                                        onRefresh()
                                        onClockAction()
                                    }
                                    result.startsWith("http_error") ->
                                        onSnackbar("Server error ${result.substringAfter(":")}")
                                    else ->
                                        onSnackbar("Connection refused — is the daemon running?")
                                }
                            }
                        }
                    },
                    enabled = !isLoading,
                    // Tint the button when this node is actively clocked in
                    colors = if (isClockInButton && thisNodeIsActive)
                        ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                    else
                        ButtonDefaults.buttonColors()
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text(text = label)
                }
            }

            if (showDialog) {
                AlertDialog(
                    onDismissRequest = { if (!isLoading) showDialog = false },
                    title = { Text(action?.optString("input_prompt") ?: "Input Required") },
                    text = {
                        OutlinedTextField(
                            value = inputText,
                            onValueChange = { inputText = it },
                            singleLine = true,
                            enabled = !isLoading
                        )
                    },
                    confirmButton = {
                        Button(
                            onClick = { executeNetworkAction(inputText) },
                            enabled = !isLoading
                        ) {
                            if (isLoading) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(18.dp),
                                    strokeWidth = 2.dp,
                                    color = MaterialTheme.colorScheme.onPrimary
                                )
                            } else {
                                Text("Submit")
                            }
                        }
                    },
                    dismissButton = {
                        TextButton(
                            onClick = { showDialog = false },
                            enabled = !isLoading
                        ) { Text("Cancel") }
                    }
                )
            }
        }

        "Checkbox" -> {
            val label = element.optString("label")
            val initialChecked = element.optBoolean("checked", false)
            var isChecked by remember { mutableStateOf(initialChecked) }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Checkbox(
                    checked = isChecked,
                    onCheckedChange = { newlyChecked ->
                        isChecked = newlyChecked
                        executeNetworkAction(if (newlyChecked) "DONE" else "TODO")
                    },
                    enabled = !isLoading
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(text = label, fontSize = 16.sp)

                if (isLoading) {
                    Spacer(modifier = Modifier.width(8.dp))
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                }
            }
        }

        "DatePicker" -> {
            val label = element.optString("label")
            val currentValue = element.optString("current_value", "None")
            var showDatePicker by remember { mutableStateOf(false) }

            @OptIn(ExperimentalMaterial3Api::class)
            val datePickerState = rememberDatePickerState()

            OutlinedButton(
                onClick = { showDatePicker = true },
                modifier = Modifier.fillMaxWidth(),
                enabled = !isLoading
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text("$label: $currentValue")
            }

            @OptIn(ExperimentalMaterial3Api::class)
            if (showDatePicker) {
                DatePickerDialog(
                    onDismissRequest = { showDatePicker = false },
                    confirmButton = {
                        TextButton(onClick = {
                            showDatePicker = false
                            datePickerState.selectedDateMillis?.let { millis ->
                                val sdf = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
                                sdf.timeZone = java.util.TimeZone.getTimeZone("UTC")
                                val formattedDate = sdf.format(java.util.Date(millis))
                                executeNetworkAction("<$formattedDate>")
                            }
                        }) { Text("OK") }
                    },
                    dismissButton = {
                        TextButton(onClick = { showDatePicker = false }) { Text("Cancel") }
                    }
                ) {
                    DatePicker(state = datePickerState)
                }
            }
        }
    }
}

suspend fun fetchGlasspaneView(id: String? = null): List<JSONObject> = withContext(Dispatchers.IO) {
    try {
        val urlBuilder = "http://127.0.0.1:8080/glasspane-view".toHttpUrlOrNull()?.newBuilder()
        if (id != null) {
            urlBuilder?.addQueryParameter("id", id)
        }
        val request = Request.Builder().url(urlBuilder?.build() ?: throw Exception("Invalid URL")).build()
        val response = okHttpClient.newCall(request).execute()

        if (response.isSuccessful) {
            val responseText = response.body?.string() ?: ""
            val jsonResponse = JSONObject(responseText)
            val elementsArray = jsonResponse.optJSONArray("elements") ?: JSONArray()

            val resultList = mutableListOf<JSONObject>()
            for (i in 0 until elementsArray.length()) {
                resultList.add(elementsArray.getJSONObject(i))
            }
            return@withContext resultList
        }
    } catch (e: Exception) {
        android.util.Log.e("GlasspaneNetwork", "Failed to fetch view", e)
    }
    return@withContext emptyList()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OrgNode(node: JSONObject, depth: Int = 0) {
    val nodeId = node.optString("id")
    val hasChildren = node.optBoolean("has_children", false)
    val elements = node.optJSONArray("elements") ?: JSONArray()

    var isExpanded by remember { mutableStateOf(false) }
    var children by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var isLoadingChildren by remember { mutableStateOf(false) }

    // 1. The Orgzly Swipe-to-Dismiss Wrapper
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { dismissValue ->
            if (dismissValue == SwipeToDismissBoxValue.StartToEnd) {
                // TODO: Plunder the WorkManager to send a /glasspane-update POST here
                // e.g., Update STATUS to "DONE"
                android.util.Log.d("Swipe", "Swiped node $nodeId to the right!")
                false // Return false to bounce the card back after the action triggers
            } else {
                false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            // The green background that shows when swiping (Orgzly style)
            val color = if (dismissState.targetValue == SwipeToDismissBoxValue.StartToEnd) {
                MaterialTheme.colorScheme.primaryContainer
            } else MaterialTheme.colorScheme.surface

            Box(Modifier.fillMaxSize().background(color).padding(16.dp), contentAlignment = Alignment.CenterStart) {
                Text("MARK DONE", color = MaterialTheme.colorScheme.onPrimaryContainer, fontWeight = FontWeight.Bold)
            }
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                // Multiply padding by depth for the nested Outline feel!
                .padding(start = (depth * 16).dp, top = 8.dp, bottom = 8.dp, end = 8.dp)
        ) {
            Row(verticalAlignment = Alignment.Top) {
                // Expand/Collapse Chevron
                if (hasChildren) {
                    IconButton(
                        onClick = {
                            isExpanded = !isExpanded
                            if (isExpanded && children.isEmpty()) {
                                isLoadingChildren = true
                            }
                        },
                        modifier = Modifier.size(24.dp).padding(end = 4.dp)
                    ) {
                        Icon(
                            imageVector = if (isExpanded) Icons.Default.ExpandMore else Icons.Default.ChevronRight,
                            contentDescription = "Expand"
                        )
                    }
                } else {
                    Spacer(modifier = Modifier.width(24.dp)) // Maintain alignment if no children
                }

                // Render the SDUI Elements provided by Emacs
                Column(modifier = Modifier.weight(1f)) {
                    for (i in 0 until elements.length()) {
                        val element = elements.optJSONObject(i) ?: continue
                        when (element.optString("type")) {
                            "Text" -> {
                                val textVal = element.optString("value")
                                val isTitle = element.optString("size") == "Title"
                                Text(
                                    text = textVal,
                                    style = if (isTitle) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium,
                                    fontWeight = if (isTitle) FontWeight.Bold else FontWeight.Normal,
                                    color = if (isTitle) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            "Button" -> {
                                OutlinedButton(
                                    onClick = { /* TODO: Execute HTTP Action endpoint */ },
                                    modifier = Modifier.padding(top = 4.dp)
                                ) {
                                    Text(element.optString("label"))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 2. The Recursive Loading
    // If the node is expanded, fetch the children from Emacs and draw them!
    if (isExpanded) {
        LaunchedEffect(nodeId) {
            if (children.isEmpty()) {
                children = fetchGlasspaneView(nodeId)
                isLoadingChildren = false
            }
        }

        if (isLoadingChildren) {
            CircularProgressIndicator(modifier = Modifier.padding(start = ((depth + 1) * 16).dp, top = 4.dp).size(16.dp), strokeWidth = 2.dp)
        } else {
            // Recursion: The Node calls itself for every child
            children.forEach { childNode ->
                OrgNode(node = childNode, depth = depth + 1)
            }
        }
    }
}

@Composable
fun MainOutlineScreen() {
    var rootNodes by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        // Fetch the root directory (no ID passed)
        rootNodes = fetchGlasspaneView(null)
        isLoading = false
    }

    Scaffold(
        topBar = {
            @OptIn(ExperimentalMaterial3Api::class)
            TopAppBar(title = { Text("Glasspane Outline") })
        }
    ) { paddingValues ->
        if (isLoading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(modifier = Modifier.padding(paddingValues)) {
                items(rootNodes) { node ->
                    // Kick off the recursive drawing starting at depth 0
                    OrgNode(node = node, depth = 0)
                    Divider(color = MaterialTheme.colorScheme.surfaceVariant)
                }
            }
        }
    }
}