package com.example.glasspane.ui.viewmodels

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.glasspane.EmacsClient
import com.example.glasspane.EmacsClient.toStringList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

// ─── Agenda data models ────────────────────────────────────────────────────────

data class AgendaItem(
    val id: String,
    val title: String,
    val todo: String,
    val priority: String,
    val tags: List<String>,
    val scheduled: String,
    val deadline: String,
    val effort: String,
    val category: String,
    val file: String,
    val effectiveDate: String,
    val itemType: String  // "scheduled", "deadline", "timestamp"
)

data class AgendaGroup(
    val date: String,
    val items: List<AgendaItem>
)

data class TodoKeywordState(
    val state: String,
    val type: String   // "active" or "done"
)

data class AgendaUiState(
    val isLoading: Boolean = true,
    val groups: List<AgendaGroup> = emptyList(),
    val todoKeywords: List<List<TodoKeywordState>> = emptyList(),
    val span: String = "week",
    val errorMessage: String? = null
)

// ─── ViewModel ─────────────────────────────────────────────────────────────────

class AgendaViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(AgendaUiState())
    val uiState: StateFlow<AgendaUiState> = _uiState.asStateFlow()

    init {
        fetchAgenda("week")
    }

    fun fetchAgenda(span: String = "week") {
        _uiState.value = _uiState.value.copy(isLoading = true, span = span, errorMessage = null)

        viewModelScope.launch {
            try {
                val result = EmacsClient.get("/glasspane-agenda", mapOf("span" to span))

                if (result != null) {
                    val json = JSONObject(result)
                    val groups = parseAgendaGroups(json)
                    val keywords = parseTodoKeywords(json)
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        groups = groups,
                        todoKeywords = keywords
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        errorMessage = "Server returned an error"
                    )
                }
            } catch (e: Exception) {
                Log.e("AgendaViewModel", "Failed to fetch agenda", e)
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = "Could not connect to Emacs: ${e.message}"
                )
            }
        }
    }

    fun cycleTodoState(itemId: String) {
        viewModelScope.launch {
            try {
                val result = EmacsClient.post("/glasspane-set-todo", mapOf("id" to itemId, "state" to "cycle"))
                if (result != null) {
                    // Re-fetch the agenda to reflect the change
                    fetchAgenda(_uiState.value.span)
                }
            } catch (e: Exception) {
                Log.e("AgendaViewModel", "Failed to cycle TODO state", e)
            }
        }
    }

    private fun parseAgendaGroups(json: JSONObject): List<AgendaGroup> {
        val groupsArray = json.optJSONArray("groups") ?: return emptyList()
        val result = mutableListOf<AgendaGroup>()

        for (i in 0 until groupsArray.length()) {
            val groupObj = groupsArray.getJSONObject(i)
            val date = groupObj.optString("date", "")
            val itemsArray = groupObj.optJSONArray("items") ?: continue

            val items = mutableListOf<AgendaItem>()
            for (j in 0 until itemsArray.length()) {
                val item = itemsArray.getJSONObject(j)

                items.add(
                    AgendaItem(
                        id = item.optString("id", ""),
                        title = item.optString("title", ""),
                        todo = item.optString("todo", ""),
                        priority = item.optString("priority", ""),
                        tags = item.optJSONArray("tags").toStringList(),
                        scheduled = item.optString("scheduled", ""),
                        deadline = item.optString("deadline", ""),
                        effort = item.optString("effort", ""),
                        category = item.optString("category", ""),
                        file = item.optString("file", ""),
                        effectiveDate = item.optString("effective_date", ""),
                        itemType = item.optString("item_type", "")
                    )
                )
            }

            result.add(AgendaGroup(date = date, items = items))
        }

        return result
    }

    private fun parseTodoKeywords(json: JSONObject): List<List<TodoKeywordState>> {
        val kwArray = json.optJSONArray("todo_keywords") ?: return emptyList()
        val result = mutableListOf<List<TodoKeywordState>>()

        for (i in 0 until kwArray.length()) {
            val seqObj = kwArray.getJSONObject(i)
            val statesArray = seqObj.optJSONArray("sequence") ?: continue
            val states = mutableListOf<TodoKeywordState>()

            for (j in 0 until statesArray.length()) {
                val stateObj = statesArray.getJSONObject(j)
                states.add(
                    TodoKeywordState(
                        state = stateObj.optString("state", ""),
                        type = stateObj.optString("type", "active")
                    )
                )
            }

            result.add(states)
        }

        return result
    }
}
