package com.example.glasspane

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

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
            // Permission granted or denied — either way we proceed. The
            // notification will simply not appear if the user denies it.
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Ask for notification permission on first launch (API 33+ only).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        // Force a background sync every time the app is opened
        val syncRequest = OneTimeWorkRequestBuilder<SyncWorker>().build()
        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            "glasspane_sync",
            ExistingWorkPolicy.REPLACE,
            syncRequest
        )

        setContent {
            MaterialTheme {
                MainOutlineScreen()
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
                val json = JSONObject(URL("http://127.0.0.1:8080/glasspane-clock-status").readText())
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
                    val json = URL("http://127.0.0.1:8080/glasspane-capture-templates").readText()
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
                            val params = fieldValues.entries.joinToString("&") { (k, v) ->
                                "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
                            }
                            val urlString =
                                "http://127.0.0.1:8080${template.endpoint}?id=${template.id}&$params"
                            val conn = URL(urlString).openConnection() as HttpURLConnection
                            conn.requestMethod = "POST"
                            val code = conn.responseCode
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
                val url = if (nodeId.isNullOrEmpty()) {
                    "http://127.0.0.1:8080/glasspane-view"
                } else {
                    val encoded = URLEncoder.encode(nodeId, "UTF-8")
                    "http://127.0.0.1:8080/glasspane-view?id=$encoded"
                }
                viewJson = JSONObject(URL(url).readText())
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

            if (hasChildren) {
                Icon(
                    imageVector = Icons.Filled.ChevronRight,
                    contentDescription = "Has children",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
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
                        var urlString = "http://127.0.0.1:8080$endpoint?id=$id"
                        if (!prop.isNullOrEmpty()) urlString += "&prop=$prop"
                        if (!inputValue.isNullOrEmpty()) {
                            urlString += "&val=${URLEncoder.encode(inputValue, "UTF-8")}"
                        }
                        val conn = URL(urlString).openConnection() as HttpURLConnection
                        conn.requestMethod = "POST"
                        val code = conn.responseCode
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
                                            val urlString = if (!id.isNullOrEmpty())
                                                "http://127.0.0.1:8080$ep?id=$id"
                                            else
                                                "http://127.0.0.1:8080$ep"
                                            val conn = URL(urlString).openConnection() as HttpURLConnection
                                            conn.requestMethod = "POST"
                                            val code = conn.responseCode
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
                                val sdf = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
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
        val urlString = if (id == null) {
            "http://127.0.0.1:8080/glasspane-view"
        } else {
            "http://127.0.0.1:8080/glasspane-view?id=${java.net.URLEncoder.encode(id, "UTF-8")}"
        }

        val url = URL(urlString)
        val conn = url.openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 3000

        if (conn.responseCode in 200..299) {
            val response = conn.inputStream.bufferedReader().readText()
            val jsonResponse = JSONObject(response)
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