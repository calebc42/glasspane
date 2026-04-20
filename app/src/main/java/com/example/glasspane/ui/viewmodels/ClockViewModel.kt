package com.example.glasspane.ui.viewmodels

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.glasspane.EmacsClient
import com.example.glasspane.EmacsClient.isError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import kotlin.math.roundToInt

data class ClockEntry(
    val id: String,
    val title: String,
    val minutes: Int
)

data class ClockReportUiState(
    val isLoading: Boolean = true,
    val span: String = "today",
    val totalMinutes: Int = 0,
    val entries: List<ClockEntry> = emptyList(),
    val errorMessage: String? = null
)

class ClockViewModel : ViewModel() {
    private val _uiState = MutableStateFlow(ClockReportUiState())
    val uiState: StateFlow<ClockReportUiState> = _uiState.asStateFlow()

    init {
        fetchReport("today")
    }

    fun fetchReport(span: String) {
        _uiState.value = _uiState.value.copy(isLoading = true, span = span, errorMessage = null)
        
        viewModelScope.launch {
            try {
                val result = EmacsClient.get("/glasspane-clock-report", mapOf("span" to span))
                if (result != null) {
                    val json = JSONObject(result)
                    
                    if (json.isError()) {
                        _uiState.value = _uiState.value.copy(
                            isLoading = false, 
                            errorMessage = json.optString("message", "Error fetching clock data")
                        )
                        return@launch
                    }

                    val totalStr = json.optString("total_time", "0:00")
                    val totalMinutes = parseTimeStringToMinutes(totalStr)
                    
                    val entriesArr = json.optJSONArray("entries") ?: org.json.JSONArray()
                    val entries = mutableListOf<ClockEntry>()
                    
                    for (i in 0 until entriesArr.length()) {
                        val item = entriesArr.getJSONObject(i)
                        entries.add(
                            ClockEntry(
                                id = item.optString("id", ""),
                                title = item.optString("title", "Unknown Task"),
                                minutes = parseTimeStringToMinutes(item.optString("time", "0:00"))
                            )
                        )
                    }

                    _uiState.value = _uiState.value.copy(
                        isLoading = false,
                        totalMinutes = totalMinutes,
                        entries = entries.sortedByDescending { it.minutes }
                    )
                } else {
                    _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = "Failed to connect to Emacs")
                }
            } catch (e: Exception) {
                Log.e("ClockViewModel", "Failed to fetch clock report", e)
                _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = e.message)
            }
        }
    }

    private fun parseTimeStringToMinutes(timeStr: String): Int {
        if (timeStr.isBlank()) return 0
        try {
            val parts = timeStr.split(":")
            if (parts.size == 2) {
                return (parts[0].toInt() * 60) + parts[1].toInt()
            }
        } catch (e: Exception) {
            // ignore
        }
        return 0
    }
}
