// SPDX-License-Identifier: GPL-3.0-or-later
// W4 host: start the loopback bridge, render the latest accepted app:*
// snapshot. Chrome, apps, and the shell arrive with later rungs.
package com.calebc42.ebp.companion

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject

class MainActivity : ComponentActivity() {

    private val currentSpec = MutableStateFlow<JSONObject?>(null)
    private val currentDialog = MutableStateFlow<Pair<String, JSONObject>?>(null)
    // SPEC 18.4: null = follow-system (amendment #36).
    private val forcedDark = MutableStateFlow<Boolean?>(null)
    private lateinit var bridge: DeviceBridge

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        bridge = DeviceBridge(
            java.io.File(filesDir, "ebp-queue.json"),
            java.io.File(filesDir, "ebp-surfaces.json"),
            onSurfaceChanged = { spec -> currentSpec.value = spec },
            onQueueProblem = { message ->
                runOnUiThread {
                    android.widget.Toast.makeText(
                        this, "EBP queue: $message",
                        android.widget.Toast.LENGTH_LONG).show()
                }
            },
            onDialogChanged = { id, spec ->
                // SPEC 18.1: one outstanding dialog presented at a time here.
                currentDialog.value = if (spec != null && id != null) id to spec
                    else null
            },
            onToast = { text ->
                runOnUiThread {
                    android.widget.Toast.makeText(
                        this, text, android.widget.Toast.LENGTH_SHORT).show()
                }
            },
            onTheme = { dark -> forcedDark.value = dark })
        bridge.start()
        setContent {
            val dark by forcedDark.collectAsState()
            // SPEC 18.4: forced polarity, or the system setting when null.
            val useDark = dark ?: isSystemInDarkTheme()
            MaterialTheme(colorScheme = if (useDark) darkColorScheme()
                else lightColorScheme()) {
                Surface(Modifier.fillMaxSize()) {
                    val spec by currentSpec.collectAsState()
                    when (val s = spec) {
                        null -> Text(
                            "EBP Companion — waiting for Emacs on 127.0.0.1:8765",
                            Modifier.padding(24.dp))
                        else -> RenderNode(s, "app:main", bridge)
                    }
                    val dialog by currentDialog.collectAsState()
                    dialog?.let { (id, dspec) ->
                        androidx.compose.ui.window.Dialog(
                            // SPEC 18.1: a platform dismissal is a dismiss.
                            onDismissRequest = { bridge.dialogDismiss(id) }) {
                            Surface(
                                shape = MaterialTheme.shapes.large,
                                tonalElevation = 6.dp) {
                                androidx.compose.foundation.layout.Column(
                                    Modifier.padding(24.dp)) {
                                    RenderDialogRoot(id, dspec, bridge)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
