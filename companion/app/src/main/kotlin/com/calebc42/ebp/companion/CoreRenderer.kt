// SPDX-License-Identifier: GPL-3.0-or-later
// The Core Node Set renderer (SPEC 16.2/24.1): text, row, column, box,
// spacer, divider, button, text_input — plus the 16.2 unknown-node degrade.
// W4 renders; action and state dispatch arrive with W5 (buttons and inputs
// are display-only until then). The full poc-v1 renderer ports at W8.
package com.calebc42.ebp.companion

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun RenderNode(node: JSONObject, surface: String, bridge: DeviceBridge) {
    val padding = Modifier.padding((node.optDouble("padding", 0.0)).dp)
    when (node.optString("t")) {
        "text" -> Text(
            text = node.optString("text"),
            style = when (node.optString("style")) {
                "title" -> MaterialTheme.typography.titleLarge
                "headline" -> MaterialTheme.typography.headlineMedium
                "caption" -> MaterialTheme.typography.bodySmall
                else -> MaterialTheme.typography.bodyLarge
            },
            modifier = padding)
        "row" -> Row(modifier = padding) { RenderChildren(node.optJSONArray("children"), surface, bridge) }
        "column" -> Column(modifier = padding) { RenderChildren(node.optJSONArray("children"), surface, bridge) }
        "box" -> Box(modifier = padding) { RenderChildren(node.optJSONArray("children"), surface, bridge) }
        "spacer" -> Spacer(Modifier
            .width((node.optDouble("width", 0.0)).dp)
            .height((node.optDouble("height", 0.0)).dp))
        "divider" -> HorizontalDivider(modifier = padding)
        "button" -> Button(
            onClick = { // SPEC 14.1: dispatch the authored descriptor
                bridge.action(surface, node.optJSONObject("on_tap"))
            },
            modifier = padding) { Text(node.optString("label")) }
        "text_input" -> {
            // Seeded from the authored value; draft publication is W5.
            var value by rememberSaveable(node.optString("id")) {
                mutableStateOf(node.optString("value"))
            }
            OutlinedTextField(
                value = value,
                onValueChange = {
                    value = it
                    // SPEC 14.6: publish each user edit as state.changed.
                    bridge.state(surface, node.optString("id"), it)
                },
                label = node.optString("label").takeIf { it.isNotEmpty() }
                    ?.let { { Text(it) } },
                singleLine = node.optBoolean("single_line"),
                modifier = padding)
        }
        else ->
            // SPEC 16.2: unknown types render children as a neutral
            // vertical sequence, or nothing.
            node.optJSONArray("children")?.let { children ->
                Column { RenderChildren(children, surface, bridge) }
            }
    }
}

@Composable
private fun RenderChildren(children: JSONArray?, surface: String, bridge: DeviceBridge) {
    if (children == null) return
    for (i in 0 until children.length()) {
        (children.opt(i) as? JSONObject)?.let { RenderNode(it, surface, bridge) }
    }
}
