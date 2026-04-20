package com.example.glasspane.ui.viewmodels

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.glasspane.EmacsClient
import com.example.glasspane.EmacsClient.toStringList
import com.example.glasspane.ui.components.EmacsServerStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

data class OrgTask(
    val id: String,
    val title: String,
    val status: String,
    val isDone: Boolean,
    val hasChildren: Boolean,
    val tags: List<String> = emptyList(),
    val priority: String = "",
    val scheduled: String = "",
    val deadline: String = "",
    val effort: String = "",
    val level: Int = 1,
    val bodyText: String = ""
)

class DashboardViewModel : ViewModel() {

    private val _tasks = MutableStateFlow<List<OrgTask>>(emptyList())
    val tasks: StateFlow<List<OrgTask>> = _tasks.asStateFlow()

    private val _serverStatus = MutableStateFlow(EmacsServerStatus.SYNCING)
    val serverStatus: StateFlow<EmacsServerStatus> = _serverStatus.asStateFlow()

    private val rootTasks = mutableListOf<OrgTask>()
    private val childrenMap = mutableMapOf<String, List<OrgTask>>()
    val expandedStates = MutableStateFlow<Set<String>>(emptySet())

    private val _hoistedNode = MutableStateFlow<OrgTask?>(null)
    val hoistedNode: StateFlow<OrgTask?> = _hoistedNode.asStateFlow()

    // --- Navigation State ---
    private val _currentParentId = MutableStateFlow<String?>(null)
    val currentParentId: StateFlow<String?> = _currentParentId.asStateFlow()

    private val navStack = mutableListOf<Pair<OrgTask?, String?>>() // Pair(hoistedNode, currentParentId)

    init {
        fetchTasks(null)
    }

    /**
     * Rebuild the flattened tree list from rootTasks and childrenMap based on expandedStates.
     */
    private fun updateFlattened() {
        val result = mutableListOf<OrgTask>()
        val currentExpanded = expandedStates.value

        fun traverse(tasksList: List<OrgTask>) {
            for (t in tasksList) {
                result.add(t)
                if (currentExpanded.contains(t.id)) {
                    childrenMap[t.id]?.let { traverse(it) }
                }
            }
        }

        traverse(rootTasks)
        _tasks.value = result
    }

    /**
     * Expand or collapse a node inline (Accordion mode).
     * If children are missing, fetches them silently.
     */
    fun toggleExpand(task: OrgTask) {
        val currentExpanded = expandedStates.value.toMutableSet()
        if (currentExpanded.contains(task.id)) {
            currentExpanded.remove(task.id)
            expandedStates.value = currentExpanded
            updateFlattened()
        } else {
            currentExpanded.add(task.id)
            expandedStates.value = currentExpanded
            
            if (task.hasChildren && !childrenMap.containsKey(task.id)) {
                viewModelScope.launch {
                    try {
                        val json = EmacsClient.get("/glasspane-view", mapOf("id" to task.id))
                        if (json != null) {
                            childrenMap[task.id] = parseGlasspaneView(json)
                            updateFlattened()
                        }
                    } catch (e: Exception) {
                        Log.e("GlasspaneNetwork", "Fetch children failed", e)
                    }
                }
            } else {
                updateFlattened()
            }
        }
    }

    /**
     * Focus (Hoist) a task, pinning it as root and fetching its children.
     */
    fun focusTask(task: OrgTask) {
        navStack.add(Pair(_hoistedNode.value, _currentParentId.value))
        _hoistedNode.value = task
        _currentParentId.value = task.id
        
        viewModelScope.launch {
            _serverStatus.value = EmacsServerStatus.SYNCING
            try {
                val json = EmacsClient.get("/glasspane-view", mapOf("id" to task.id))
                if (json != null) {
                    rootTasks.clear()
                    rootTasks.addAll(parseGlasspaneView(json))
                    expandedStates.value = emptySet()
                    childrenMap.clear()
                    updateFlattened()
                    _serverStatus.value = EmacsServerStatus.CONNECTED
                } else {
                    _serverStatus.value = EmacsServerStatus.ERROR
                }
            } catch (e: Exception) {
                _serverStatus.value = EmacsServerStatus.OFFLINE
            }
        }
    }

    /**
     * Load an arbitrary node (or root if null), usually used on initialization or back press.
     */
    fun fetchTasks(nodeId: String? = null, isBackPress: Boolean = false) {
        if (!isBackPress && nodeId != _currentParentId.value) {
            navStack.add(Pair(_hoistedNode.value, _currentParentId.value))
        }
        _currentParentId.value = nodeId

        viewModelScope.launch {
            _serverStatus.value = EmacsServerStatus.SYNCING

            try {
                val params = if (nodeId != null) mapOf("id" to nodeId) else emptyMap()
                val json = EmacsClient.get("/glasspane-view", params)

                if (json != null) {
                    rootTasks.clear()
                    rootTasks.addAll(parseGlasspaneView(json))
                    expandedStates.value = emptySet()
                    childrenMap.clear()
                    updateFlattened()
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
        viewModelScope.launch {
            try {
                val result = EmacsClient.post("/glasspane-set-todo", mapOf("id" to taskId, "state" to "cycle"))
                if (result != null) {
                    refreshCurrentView()
                }
            } catch (e: Exception) {
                Log.e("GlasspaneNetwork", "Failed to cycle TODO state", e)
            }
        }
    }

    fun setTaskToState(taskId: String, state: String) {
        viewModelScope.launch {
            try {
                val result = EmacsClient.post("/glasspane-set-todo", mapOf("id" to taskId, "state" to state))
                if (result != null) {
                    refreshCurrentView()
                }
            } catch (e: Exception) {
                Log.e("GlasspaneNetwork", "Failed to set TODO state", e)
            }
        }
    }

    fun captureTask(templateId: String, fields: Map<String, String>) {
        viewModelScope.launch {
            try {
                val params = mutableMapOf("id" to templateId)
                params.putAll(fields)
                val result = EmacsClient.post("/glasspane-capture", params)
                if (result != null) {
                    refreshCurrentView()
                }
            } catch (e: Exception) {
                Log.e("GlasspaneNetwork", "Failed to capture", e)
            }
        }
    }

    fun refileTask(sourceId: String, targetId: String) {
        viewModelScope.launch {
            try {
                val result = EmacsClient.post("/glasspane-refile", mapOf("id" to sourceId, "target" to targetId))
                if (result != null) refreshCurrentView()
            } catch (e: Exception) {
                Log.e("GlasspaneNetwork", "Failed to refile", e)
            }
        }
    }

    fun scheduleTask(id: String, date: String, repeater: String, isDeadline: Boolean, remove: Boolean) {
        viewModelScope.launch {
            try {
                val params = mapOf(
                    "id" to id,
                    "date" to date,
                    "repeater" to repeater,
                    "type" to if (isDeadline) "DEADLINE" else "SCHEDULED",
                    "remove" to if (remove) "true" else "false"
                )
                val result = EmacsClient.post("/glasspane-schedule", params)
                if (result != null) refreshCurrentView()
            } catch (e: Exception) {
                Log.e("GlasspaneNetwork", "Failed to schedule", e)
            }
        }
    }

    fun clockInTask(id: String) {
        viewModelScope.launch {
            try {
                val result = EmacsClient.post("/glasspane-clock-in", mapOf("id" to id))
                if (result != null) refreshCurrentView()
            } catch (e: Exception) {
                Log.e("GlasspaneNetwork", "Failed to clock in", e)
            }
        }
    }

    fun deleteTask(id: String) {
        viewModelScope.launch {
            try {
                val result = EmacsClient.post("/glasspane-archive", mapOf("id" to id))
                if (result != null) refreshCurrentView()
            } catch (e: Exception) {
                Log.e("GlasspaneNetwork", "Failed to delete/archive", e)
            }
        }
    }

    fun treeEditTask(id: String, action: String, title: String?) {
        viewModelScope.launch {
            try {
                val params = mutableMapOf("id" to id, "action" to action)
                if (title != null) params["title"] = title
                val result = EmacsClient.post("/glasspane-tree-edit", params)
                if (result != null) refreshCurrentView()
            } catch (e: Exception) {
                Log.e("GlasspaneNetwork", "Failed tree edit", e)
            }
        }
    }

    fun updateTaskTitle(id: String, newTitle: String) {
        viewModelScope.launch {
            try {
                // Optimistically update the title locally
                fun updateInList(list: MutableList<OrgTask>): Boolean {
                    for (i in list.indices) {
                        if (list[i].id == id) {
                            list[i] = list[i].copy(title = newTitle)
                            return true
                        }
                    }
                    return false
                }
                if (!updateInList(rootTasks)) {
                    for (entry in childrenMap) {
                        val ml = entry.value.toMutableList()
                        if (updateInList(ml)) {
                            childrenMap[entry.key] = ml
                            break
                        }
                    }
                }
                updateFlattened()
                
                EmacsClient.post("/glasspane-update-title", mapOf("id" to id, "val" to newTitle))
                refreshCurrentView()
            } catch (e: Exception) {}
        }
    }

    fun setTaskPriority(id: String, priority: String) {
        viewModelScope.launch {
            try {
                EmacsClient.post("/glasspane-set-priority", mapOf("id" to id, "priority" to priority))
                refreshCurrentView()
            } catch (e: Exception) {}
        }
    }

    fun setTaskTags(id: String, tags: String) {
        viewModelScope.launch {
            try {
                EmacsClient.post("/glasspane-set-tags", mapOf("id" to id, "tags" to tags))
                refreshCurrentView()
            } catch (e: Exception) {}
        }
    }

    fun addTaskProperty(id: String, prop: String, value: String) {
        viewModelScope.launch {
            try {
                EmacsClient.post("/glasspane-update", mapOf("id" to id, "prop" to prop, "val" to value))
                refreshCurrentView()
            } catch (e: Exception) {}
        }
    }

    fun updateTaskBody(id: String, newBody: String) {
        viewModelScope.launch {
            try {
                // Optimistically update the body locally before polling
                fun updateInList(list: MutableList<OrgTask>): Boolean {
                    for (i in list.indices) {
                        if (list[i].id == id) {
                            list[i] = list[i].copy(bodyText = newBody)
                            return true
                        }
                    }
                    return false
                }
                
                if (!updateInList(rootTasks)) {
                    for (entry in childrenMap) {
                        val ml = entry.value.toMutableList()
                        if (updateInList(ml)) {
                            childrenMap[entry.key] = ml
                            break
                        }
                    }
                }
                updateFlattened()
                
                if (_hoistedNode.value?.id == id) {
                    _hoistedNode.value = _hoistedNode.value?.copy(bodyText = newBody)
                }
                val result = EmacsClient.post("/glasspane-update-body", mapOf("id" to id, "val" to newBody))
                if (result != null) refreshCurrentView()
            } catch (e: Exception) {
                Log.e("GlasspaneNetwork", "Failed to update body", e)
            }
        }
    }

    /** Re-fetch the current view without mutating the nav stack. Refreshing root and open children. */
    private fun refreshCurrentView() {
        val currentId = _currentParentId.value
        viewModelScope.launch {
            try {
                val params = if (currentId != null) mapOf("id" to currentId) else emptyMap()
                val json = EmacsClient.get("/glasspane-view", params)
                if (json != null) {
                    rootTasks.clear()
                    rootTasks.addAll(parseGlasspaneView(json))
                    
                    // Re-fetch any expanded children to keep tree accurate
                    val expanded = expandedStates.value.toList()
                    childrenMap.clear()
                    updateFlattened() // Hide momentarily while fetching
                    
                    for (id in expanded) {
                        try {
                            val cjson = EmacsClient.get("/glasspane-view", mapOf("id" to id))
                            if (cjson != null) {
                                childrenMap[id] = parseGlasspaneView(cjson)
                            }
                        } catch(e: Exception) {}
                    }
                    updateFlattened()
                    _serverStatus.value = EmacsServerStatus.CONNECTED
                }
            } catch (_: Exception) { }
        }
    }

    // Pop the stack and fetch the previous node
    fun goBack() {
        if (navStack.isNotEmpty()) {
            val prev = navStack.removeLast()
            _hoistedNode.value = prev.first
            fetchTasks(prev.second, isBackPress = true)
        }
    }

    private fun parseGlasspaneView(json: String): List<OrgTask> {
        val parsedTasks = mutableListOf<OrgTask>()
        val root = JSONObject(json)
        val elements = root.optJSONArray("elements") ?: return emptyList()

        for (i in 0 until elements.length()) {
            val node = elements.getJSONObject(i)
            if (node.optString("type") == "Node") {
                val id = node.getString("id")
                val hasChildren = node.optBoolean("has_children", false)
                val level = node.optInt("level", 1)

                val todoState = node.optString("todo", "")
                val priority = node.optString("priority", "")
                val scheduled = node.optString("scheduled", "")
                val deadline = node.optString("deadline", "")
                val effort = node.optString("effort", "")

                val tags = node.optJSONArray("tags").toStringList()

                // Get title from elements array
                val nodeElements = node.optJSONArray("elements")
                var title = "Unknown Node"
                var bodyText = ""
                if (nodeElements != null) {
                    for (j in 0 until nodeElements.length()) {
                        val el = nodeElements.getJSONObject(j)
                        val t = el.optString("type")
                        if (t == "Text" && el.optString("size") == "Title") {
                            title = el.getString("value")
                        } else if (t == "EditableText") {
                            bodyText = el.getString("value")
                        }
                    }
                }

                parsedTasks.add(
                    OrgTask(
                        id = id,
                        title = title,
                        status = todoState.ifEmpty { "No State" },
                        isDone = todoState.equals("DONE", ignoreCase = true),
                        hasChildren = hasChildren,
                        tags = tags,
                        priority = priority,
                        scheduled = scheduled,
                        deadline = deadline,
                        effort = effort,
                        level = level,
                        bodyText = bodyText
                    )
                )
            }
        }
        return parsedTasks
    }
}