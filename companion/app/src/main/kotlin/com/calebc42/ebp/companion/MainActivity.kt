// SPDX-License-Identifier: GPL-3.0-or-later
// W4 host: start the loopback bridge, render the latest accepted app:*
// snapshot. Chrome, apps, and the shell arrive with later rungs.
package com.calebc42.ebp.companion

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.calebc42.ebp.companion.render.EbpTheme
import com.calebc42.ebp.companion.render.RenderDialogRoot
import com.calebc42.ebp.companion.render.RenderNode
import com.calebc42.ebp.companion.render.RenderPieMenu
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject

class MainActivity : ComponentActivity() {

    private val currentSpec = MutableStateFlow<JSONObject?>(null)
    private val currentDialog = MutableStateFlow<Pair<String, JSONObject>?>(null)
    // SPEC 18.4: the accepted theme payload ({dark, colors, syntax}) to mirror,
    // or null for the native scheme (dark = follow-system, amendment #36).
    private val theme = MutableStateFlow<JSONObject?>(null)
    private val currentPieMenu = MutableStateFlow<Pair<String, JSONObject>?>(null)
    private lateinit var bridge: DeviceBridge

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // SPEC 18.5/18.6: request notification presentation permission.
        if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
            != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 0)
        }
        bridge = DeviceBridge(
            applicationContext,
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
            onTheme = { payload -> theme.value = payload },
            onPieMenuChanged = { id, spec ->
                currentPieMenu.value = if (spec != null) id to spec else null
            })
        bridge.start()
        setContent {
            // SPEC 18.4: mirror the pushed palette (colors/dark), or the native
            // scheme following the system when no theme is set.
            val themePayload by theme.collectAsState()
            EbpTheme(themePayload) {
                Surface(Modifier.fillMaxSize()) {
                    val spec by currentSpec.collectAsState()
                    when (val s = spec) {
                        null -> Text(
                            "EBP Companion — waiting for Emacs on 127.0.0.1:8765",
                            Modifier.padding(24.dp))
                        else -> RenderNode(s, "app:main", bridge)
                    }
                    val pie by currentPieMenu.collectAsState()
                    pie?.let { (id, spec) -> RenderPieMenu(id, spec, bridge) }
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
