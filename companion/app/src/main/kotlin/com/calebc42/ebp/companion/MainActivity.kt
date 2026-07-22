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
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject

class MainActivity : ComponentActivity() {

    private val currentSpec = MutableStateFlow<JSONObject?>(null)
    private val bridge = DeviceBridge { spec -> currentSpec.value = spec }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        bridge.start()
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    val spec by currentSpec.collectAsState()
                    when (val s = spec) {
                        null -> Text(
                            "EBP Companion — waiting for Emacs on 127.0.0.1:8765",
                            Modifier.padding(24.dp))
                        else -> RenderNode(s)
                    }
                }
            }
        }
    }
}
