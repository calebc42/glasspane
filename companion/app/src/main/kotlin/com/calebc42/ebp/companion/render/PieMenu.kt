// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC 18.3: a radial pie menu. Categories are placed on a circle; a leaf
// dispatches its selection, a nested category expands to its items. This is
// the functional radial overlay; poc-v1's RadialMenu gesture UI optionally
// ports at W9-l.
package com.calebc42.ebp.companion.render

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.calebc42.ebp.companion.DeviceBridge
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import org.json.JSONObject

@Composable
fun RenderPieMenu(menuId: String, spec: JSONObject, bridge: DeviceBridge) {
    val categories = spec.optJSONArray("categories") ?: return
    var expanded by remember(menuId) { mutableStateOf<Int?>(null) }
    Dialog(onDismissRequest = { bridge.pieMenuDismiss(menuId) }) {
        Box(Modifier.size(320.dp), contentAlignment = Alignment.Center) {
            spec.optString("center_label").takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.titleMedium)
            }
            val active = expanded
            val ring = if (active == null) categories
                else categories.getJSONObject(active).optJSONArray("items")
            val n = ring?.length() ?: 0
            for (k in 0 until n) {
                val entry = ring!!.getJSONObject(k)
                val angle = 2 * PI * k / n - PI / 2
                Button(
                    onClick = {
                        if (active == null && entry.has("items")) expanded = k
                        else if (active == null) bridge.pieMenuSelect(menuId, k, null)
                        else bridge.pieMenuSelect(menuId, active, k)
                    },
                    modifier = Modifier.offset(
                        x = (120 * cos(angle)).dp, y = (120 * sin(angle)).dp),
                ) { Text(entry.optString("label")) }
            }
        }
    }
}
