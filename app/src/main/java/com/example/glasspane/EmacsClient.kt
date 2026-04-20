package com.example.glasspane

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Centralized HTTP client for communicating with the Emacs simple-httpd server.
 *
 * Consolidates the server URL, connection management, and common JSON utilities
 * that were previously duplicated across every ViewModel and dialog.
 */
object EmacsClient {

    /** Base URL for the Emacs HTTP server running inside Termux. */
    const val SERVER_URL = "http://127.0.0.1:8080"

    // ─── HTTP primitives ────────────────────────────────────────────────────

    /**
     * Execute a GET request and return the response body as a String,
     * or null if the request failed.
     *
     * @param path   The endpoint path (e.g. "/glasspane-view")
     * @param params Optional query parameters as key-value pairs
     */
    suspend fun get(path: String, params: Map<String, String> = emptyMap()): String? =
        request("GET", path, params)

    /**
     * Execute a POST request and return the response body as a String,
     * or null if the request failed.
     */
    suspend fun post(path: String, params: Map<String, String> = emptyMap()): String? =
        request("POST", path, params)

    private suspend fun request(
        method: String,
        path: String,
        params: Map<String, String>
    ): String? = withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        try {
            val queryString = if (params.isNotEmpty()) {
                "?" + params.entries.joinToString("&") { (k, v) ->
                    "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
                }
            } else ""

            val url = URL("$SERVER_URL$path$queryString")
            connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = method
            connection.connectTimeout = 5000
            connection.readTimeout = 5000

            if (connection.responseCode == 200) {
                connection.inputStream.bufferedReader().readText()
            } else null
        } catch (_: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }

    // ─── JSON helpers ───────────────────────────────────────────────────────

    /**
     * Parse a JSONArray into a List<String>.
     * Returns an empty list if the array is null.
     */
    fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).map { getString(it) }
    }

    /**
     * Check whether a JSON response object represents an error.
     */
    fun JSONObject.isError(): Boolean =
        has("status") && optString("status") == "error"

    /**
     * Extract the error message from a JSON error response.
     */
    fun JSONObject.errorMessage(): String =
        optString("message", "Unknown error")
}
