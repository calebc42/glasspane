package com.example.glasspane.ui.viewmodels

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.glasspane.EmacsClient
import com.example.glasspane.EmacsClient.isError
import com.example.glasspane.EmacsClient.toStringList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

// ─── Search data models ────────────────────────────────────────────────────────

data class SearchResult(
    val id: String,
    val title: String,
    val todo: String,
    val priority: String,
    val tags: List<String>,
    val scheduled: String,
    val deadline: String,
    val file: String,
    val category: String
)

data class SearchUiState(
    val isLoading: Boolean = false,
    val query: String = "",
    val results: List<SearchResult> = emptyList(),
    val errorMessage: String? = null,
    val hasSearched: Boolean = false
)

// ─── ViewModel ─────────────────────────────────────────────────────────────────

class SearchViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(SearchUiState())
    val uiState: StateFlow<SearchUiState> = _uiState.asStateFlow()

    fun updateQuery(query: String) {
        _uiState.value = _uiState.value.copy(query = query)
    }

    fun search() {
        val query = _uiState.value.query.trim()
        if (query.isEmpty()) return

        _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null, hasSearched = true)

        viewModelScope.launch {
            try {
                val result = EmacsClient.get("/glasspane-search", mapOf("q" to query))

                if (result != null) {
                    val json = JSONObject(result)

                    // Check for error response
                    if (json.isError()) {
                        _uiState.value = _uiState.value.copy(
                            isLoading = false,
                            errorMessage = json.optString("message", "Search failed")
                        )
                        return@launch
                    }

                    val resultsArray = json.optJSONArray("results") ?: org.json.JSONArray()
                    val searchResults = mutableListOf<SearchResult>()

                    for (i in 0 until resultsArray.length()) {
                        val item = resultsArray.getJSONObject(i)

                        searchResults.add(
                            SearchResult(
                                id = item.optString("id", ""),
                                title = item.optString("title", ""),
                                todo = item.optString("todo", ""),
                                priority = item.optString("priority", ""),
                                tags = item.optJSONArray("tags").toStringList(),
                                scheduled = item.optString("scheduled", ""),
                                deadline = item.optString("deadline", ""),
                                file = item.optString("file", ""),
                                category = item.optString("category", "")
                            )
                        )
                    }

                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        results = searchResults
                    )
                } else {
                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        errorMessage = "Server returned an error"
                    )
                }
            } catch (e: Exception) {
                Log.e("SearchViewModel", "Search failed", e)
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = "Connection failed: ${e.message}"
                )
            }
        }
    }

    fun cycleTodoState(itemId: String) {
        viewModelScope.launch {
            try {
                val result = EmacsClient.post("/glasspane-set-todo", mapOf("id" to itemId, "state" to "cycle"))
                if (result != null) {
                    // Re-run the search to update results
                    search()
                }
            } catch (e: Exception) {
                Log.e("SearchViewModel", "Failed to cycle TODO state", e)
            }
        }
    }
}
