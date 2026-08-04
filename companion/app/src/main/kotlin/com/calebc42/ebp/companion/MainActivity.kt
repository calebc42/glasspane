// SPDX-License-Identifier: GPL-3.0-or-later
// W4 host, RF-0.5a shape: a PURE OBSERVER of the process-owned bridge.
// EbpApplication constructs and starts the bridge and owns every
// presentation flow; this Activity only renders them. Rotation recreates
// the Activity freely — the bridge, its socket, and the accepted state
// never notice. Chrome, apps, and the shell arrive with later rungs.
package com.calebc42.ebp.companion

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.platform.LocalConfiguration
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
import kotlinx.serialization.json.JsonObject

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // SPEC 18.5/18.6: request notification presentation permission —
        // the one duty that genuinely needs an Activity, so it stays.
        if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
            != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 0)
        }
        // RF-0.5a: the bridge and every presentation flow are process-owned
        // (EbpApplication). SPEC 14.4's surface-ID-travels-with-spec pairing
        // and 18.1's one-outstanding-dialog rule live where the state does.
        val app = application as EbpApplication
        val bridge = app.bridge
        setContent {
            // SPEC 18.4: mirror the pushed palette (colors/dark), or the native
            // scheme following the system when no theme is set.
            val themePayload by app.theme.collectAsState()
            EbpTheme(themePayload) {
                // The Surface paints edge-to-edge (the theme reaches under
                // the system bars) but CONTENT stays inside the safe-drawing
                // insets: without this the first row of any surface — a nav
                // toolbar, a status row — lands under the status bar, where
                // it is half-hidden and taps race the notification shade.
                Surface(Modifier.fillMaxSize()) {
                    androidx.compose.foundation.layout.Box(
                        Modifier.safeDrawingPadding()) {
                    // Each overlay reads its own flow inside its own composable,
                    // so opening a dialog or pie menu recomposes only that host
                    // — not the surface tree. Reading all three here put them in
                    // one recompose scope, and because every render composable
                    // takes an (unstable) JsonObject, a dialog opening
                    // re-executed the entire surface render.
                    SurfaceHost(app.currentSpec, bridge)
                    PieMenuHost(app.currentPieMenu, bridge)
                    DialogHost(app.currentDialog, bridge)
                    ConfirmHost(bridge)
                    }
                }
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun SurfaceHost(
    flow: kotlinx.coroutines.flow.StateFlow<Pair<String, JsonObject>?>,
    bridge: DeviceBridge,
) {
    val shown by flow.collectAsState()
    when (val s = shown) {
        null -> Text(
            "EBP Companion — waiting for Emacs on 127.0.0.1:8765",
            Modifier.padding(24.dp))
        else -> RenderNode(s.second, s.first, bridge)
    }
}

/**
 * SPEC 14.1 `confirm`: the user confirms BEFORE the event is created.
 * Its own host for the same reason the others have theirs — a parked
 * confirmation must not recompose the surface tree.  A dismissal (scrim
 * or back) is a REFUSAL: the event is never created, which is the whole
 * point of a guarded destructive verb.
 */
@androidx.compose.runtime.Composable
private fun ConfirmHost(bridge: DeviceBridge) {
    val pending by bridge.pendingConfirm.collectAsState()
    pending?.let { p ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { bridge.resolveConfirm(false) },
            // §14.1 object form: the face is authored; a bare string keeps
            // exactly the dialog this host always drew.
            icon = p.icon?.let {
                {
                    androidx.compose.material3.Icon(
                        com.calebc42.ebp.companion.render.IconMap.get(it),
                        contentDescription = null)
                }
            },
            title = p.title?.let { { Text(it) } },
            text = { Text(p.prompt) },
            confirmButton = {
                androidx.compose.material3.TextButton(
                    onClick = { bridge.resolveConfirm(true) }) {
                    Text(p.confirmLabel ?: "OK")
                }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(
                    onClick = { bridge.resolveConfirm(false) }) {
                    Text(p.dismissLabel ?: "Cancel")
                }
            })
    }
}

@androidx.compose.runtime.Composable
private fun PieMenuHost(
    flow: kotlinx.coroutines.flow.StateFlow<Pair<String, JsonObject>?>,
    bridge: DeviceBridge,
) {
    val pie by flow.collectAsState()
    pie?.let { (id, spec) -> RenderPieMenu(id, spec, bridge) }
}

@androidx.compose.runtime.Composable
private fun DialogHost(
    flow: kotlinx.coroutines.flow.StateFlow<Pair<String, JsonObject>?>,
    bridge: DeviceBridge,
) {
    val dialog by flow.collectAsState()
    dialog?.let { (id, dspec) ->
        androidx.compose.ui.window.Dialog(
            // SPEC 18.1: a platform dismissal is a dismiss.
            onDismissRequest = { bridge.dialogDismiss(id) }) {
            Surface(shape = MaterialTheme.shapes.large, tonalElevation = 6.dp) {
                // The HOST container scrolls. SPEC 18.1 forbids lazy_column
                // NODES in a dialog spec, not the window scrolling — and
                // without this, any dialog taller than the window (a long
                // enum_list picker, stacked context cards) has UNREACHABLE
                // content below the fold. JC-4 prerequisite.
                //
                // heightIn is what makes verticalScroll work AT ALL here:
                // a Dialog measures its content with UNBOUNDED height, so a
                // scrolling column believes it has infinite room, never
                // scrolls, and the window is simply clipped by the screen.
                // Capping the height gives the scroll something to overflow.
                // A cap rather than fillMaxHeight so a short dialog still
                // wraps its content instead of always filling the screen.
                val maxDialogHeight =
                    (LocalConfiguration.current.screenHeightDp * 0.8f).dp
                androidx.compose.foundation.layout.Column(
                    Modifier
                        .heightIn(max = maxDialogHeight)
                        .verticalScroll(rememberScrollState())
                        .padding(24.dp)) {
                    RenderDialogRoot(id, dspec, bridge)
                }
            }
        }
    }
}
