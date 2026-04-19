package com.example.glasspane.ui.viewmodels

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.glasspane.ui.components.EmacsServerStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

data class OrgTask(
    val id: String,
    val title: String,
    val status: String,
    val isDone: Boolean,
    val hasChildren: Boolean // Added property
)

class DashboardViewModel : ViewModel() {
    private val EMACS_SERVER_URL = "http://127.0.0.1:8080"

    private val _tasks = MutableStateFlow<List<OrgTask>>(emptyList())
    val tasks: StateFlow<List<OrgTask>> = _tasks.asStateFlow()

    private val _serverStatus = MutableStateFlow(EmacsServerStatus.SYNCING)
    val serverStatus: StateFlow<EmacsServerStatus> = _serverStatus.asStateFlow()

    // --- NEW: Navigation State ---
    private val _currentParentId = MutableStateFlow<String?>(null)
    val currentParentId: StateFlow<String?> = _currentParentId.asStateFlow()

    private val navStack = mutableListOf<String?>() // Keeps track of where we came from

    init {
        fetchTasks(null)
    }

    // Updated to accept a nodeId
    fun fetchTasks(nodeId: String? = null, isBackPress: Boolean = false) {
        if (!isBackPress) {
            navStack.add(_currentParentId.value)
        }
        _currentParentId.value = nodeId

        viewModelScope.launch {
            _serverStatus.value = EmacsServerStatus.SYNCING

            try {
                val resultList = withContext(Dispatchers.IO) {
                    // Append the ID to the URL if we are drilling down
                    val urlString = if (nodeId != null) "$EMACS_SERVER_URL/glasspane-view?id=$nodeId"
                    else "$EMACS_SERVER_URL/glasspane-view"

                    val url = URL(urlString)
                    val connection = url.openConnection() as HttpURLConnection
                    connection.requestMethod = "GET"
                    connection.connectTimeout = 3000
                    connection.readTimeout = 3000

                    if (connection.responseCode == 200) {
                        val jsonString = connection.inputStream.bufferedReader().readText()
                        parseGlasspaneView(jsonString)
                    } else null
                }

                if (resultList != null) {
                    _tasks.value = resultList
                    _serverStatus.value = EmacsServerStatus.CONNECTED
                } else {
                    _serverStatus.value = EmacsServerStatus.ERROR
                }
            } catch (e: Exception) {
                _serverStatus.value = EmacsServerStatus.OFFLINE
            }
        }
    }

    fun toggleTaskStatus(taskId: String, currentStatus: String) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                // Flip TODO to DONE, or DONE to TODO
                val newStatus = if (currentStatus.contains("DONE", ignoreCase = true)) "TODO" else "DONE"

                // Call your Emacs /glasspane-update endpoint
                val urlString = "$EMACS_SERVER_URL/glasspane-update?id=$taskId&prop=STATUS&val=$newStatus"
                val url = URL(urlString)
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.connectTimeout = 3000

                if (connection.responseCode == 200) {
                    // Successfully updated! Re-fetch the current view to update the UI
                    fetchTasks(_currentParentId.value)
                }
            } catch (e: Exception) {
                android.util.Log.e("GlasspaneNetwork", "Failed to update status", e)
            }
        }
    }

    fun captureTask(text: String) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                // URL encode the text safely
                val encodedText = java.net.URLEncoder.encode(text, "UTF-8")

                // Call your Emacs /glasspane-capture endpoint
                // Using "t" which maps to your "Quick Task" template in glasspane.el
                val urlString = "$EMACS_SERVER_URL/glasspane-capture?id=t&Task=$encodedText"
                val url = URL(urlString)
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.connectTimeout = 3000

                if (connection.responseCode == 200) {
                    // Re-fetch the root to show the new task if we are at the root
                    if (_currentParentId.value == null) {
                        fetchTasks(null)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("GlasspaneNetwork", "Failed to capture task", e)
            }
        }
    }

    // NEW: Pop the stack and fetch the previous node
    fun goBack() {
        if (navStack.isNotEmpty()) {
            val previousId = navStack.removeLast()
            fetchTasks(previousId, isBackPress = true)
        }
    }

    private fun parseGlasspaneView(json: String): List<OrgTask> {
        val parsedTasks = mutableListOf<OrgTask>()
        val root = org.json.JSONObject(json)
        val elements = root.optJSONArray("elements") ?: return emptyList()

        for (i in 0 until elements.length()) {
            val node = elements.getJSONObject(i)
            if (node.optString("type") == "Node") {
                val id = node.getString("id")
                // Parse the has_children boolean from your Emacs backend
                val hasChildren = node.optBoolean("has_children", false)

                val nodeElements = node.optJSONArray("elements") ?: continue

                var title = "Unknown Node"
                var statusStr = "TODO"

                for (j in 0 until nodeElements.length()) {
                    val el = nodeElements.getJSONObject(j)
                    if (el.optString("type") == "Text") {
                        if (el.optString("size") == "Title") {
                            title = el.getString("value")
                        } else if (el.optString("size") == "Body") {
                            val fullStatus = el.getString("value")
                            statusStr = fullStatus.replace("Status: ", "")
                        }
                    }
                }

                parsedTasks.add(
                    OrgTask(
                        id = id,
                        title = title,
                        status = statusStr,
                        isDone = statusStr.contains("DONE", ignoreCase = true),
                        hasChildren = hasChildren // Save it to the model
                    )
                )
            }
        }
        return parsedTasks
    }
}