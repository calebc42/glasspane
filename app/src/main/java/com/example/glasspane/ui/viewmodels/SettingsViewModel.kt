package com.example.glasspane.ui.viewmodels

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.glasspane.EmacsClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

data class ConfigTemplate(
    val id: String,
    val title: String,
    val file: String,
    val content: String
)

class SettingsViewModel : ViewModel() {

    private val _templates = MutableStateFlow<List<ConfigTemplate>>(emptyList())
    val templates: StateFlow<List<ConfigTemplate>> = _templates.asStateFlow()

    private val _tags = MutableStateFlow<List<String>>(emptyList())
    val tags: StateFlow<List<String>> = _tags.asStateFlow()

    private val _todos = MutableStateFlow<List<String>>(emptyList())
    val todos: StateFlow<List<String>> = _todos.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    init {
        fetchConfig()
    }

    fun fetchConfig() {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val jsonStr = EmacsClient.get("/glasspane-config-get", emptyMap())
                if (jsonStr != null) {
                    val root = JSONObject(jsonStr)
                    val tmplArray = root.optJSONArray("capture_templates") ?: JSONArray()
                    val parsed = mutableListOf<ConfigTemplate>()
                    for (i in 0 until tmplArray.length()) {
                        val obj = tmplArray.getJSONObject(i)
                        parsed.add(
                            ConfigTemplate(
                                id = obj.optString("id"),
                                title = obj.optString("title"),
                                file = obj.optString("file"),
                                content = obj.optString("content")
                            )
                        )
                    }
                    _templates.value = parsed

                    val tagsArray = root.optJSONArray("tags") ?: JSONArray()
                    val parsedTags = mutableListOf<String>()
                    for (i in 0 until tagsArray.length()) parsedTags.add(tagsArray.getString(i))
                    _tags.value = parsedTags

                    val todosArray = root.optJSONArray("todo_keywords") ?: JSONArray()
                    val parsedTodos = mutableListOf<String>()
                    for (i in 0 until todosArray.length()) parsedTodos.add(todosArray.getString(i))
                    _todos.value = parsedTodos
                }
            } catch (e: Exception) {
                Log.e("GlasspaneConfig", "Failed to fetch config", e)
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun saveConfig(newTemplates: List<ConfigTemplate>, newTags: List<String>, newTodos: List<String>) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val array = JSONArray()
                newTemplates.forEach { t ->
                    val obj = JSONObject()
                    obj.put("id", t.id)
                    obj.put("title", t.title)
                    obj.put("file", t.file)
                    obj.put("content", t.content)
                    array.put(obj)
                }

                val tagsArray = JSONArray()
                newTags.forEach { tagsArray.put(it) }

                val todosArray = JSONArray()
                newTodos.forEach { todosArray.put(it) }

                val payload = JSONObject()
                    .put("capture_templates", array)
                    .put("tags", tagsArray)
                    .put("todo_keywords", todosArray)
                    .toString()
                
                EmacsClient.post("/glasspane-config-set", mapOf("payload" to payload))
                
                // Refresh local state to match saved
                _templates.value = newTemplates
                _tags.value = newTags
                _todos.value = newTodos
            } catch (e: Exception) {
                Log.e("GlasspaneConfig", "Failed to save config", e)
            } finally {
                _isLoading.value = false
            }
        }
    }
}
