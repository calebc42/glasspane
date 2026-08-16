// SPDX-License-Identifier: GPL-3.0-or-later
// W4 host, RF-0.5a shape: a PURE OBSERVER of the process-owned bridge.
// EbpApplication constructs and starts the bridge and owns every
// presentation flow; this Activity only renders them. Rotation recreates
// the Activity freely — the bridge, its socket, and the accepted state
// never notice. Chrome, apps, and the shell arrive with later rungs.
package com.calebc42.ebp.companion

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.calebc42.ebp.companion.render.EbpTheme
import com.calebc42.ebp.companion.render.chromeBackDescriptor
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
            // SPEC 20.1.1: report the window geometry on first composition
            // and every configuration change (rotation, fold, resize).
            val config = androidx.compose.ui.platform.LocalConfiguration.current
            androidx.compose.runtime.LaunchedEffect(
                config.screenWidthDp, config.screenHeightDp) {
                bridge.windowChanged(config.screenWidthDp, config.screenHeightDp)
            }
            EbpTheme(themePayload) {
                val context = androidx.compose.ui.platform.LocalContext.current
                var onboardingRequired by androidx.compose.runtime.remember {
                    androidx.compose.runtime.mutableStateOf(
                        !isCurrentOnboardingComplete(context),
                    )
                }
                var onboardingOpen by androidx.compose.runtime.remember {
                    androidx.compose.runtime.mutableStateOf(false)
                }
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
                    SurfaceHost(
                        app.currentSpec,
                        bridge,
                        // S11: every other overlay composes into its OWN
                        // window (a ComponentDialog owns the back key while
                        // it is up), but onboarding is drawn IN THIS ONE over
                        // the surface — while it stands, back must not move
                        // the screen stack under it.
                        ownsBack = !(onboardingRequired || onboardingOpen),
                        onRepair = { onboardingOpen = true },
                    )
                    PieMenuHost(app.currentPieMenu, bridge)
                    DialogHost(app.currentDialog, bridge)
                    ConfirmHost(bridge)
                    SettingsHost(
                        app,
                        bridge,
                        onOpenOnboarding = {
                            app.dismissSettings()
                            onboardingOpen = true
                        },
                    )
                    if (onboardingRequired || onboardingOpen) {
                        Surface(Modifier.fillMaxSize()) {
                            OnboardingFlow(
                                onDone = {
                                    markCurrentOnboardingComplete(this@MainActivity)
                                    onboardingRequired = false
                                    onboardingOpen = false
                                },
                                onCancel = if (onboardingRequired) null else {
                                    { onboardingOpen = false }
                                },
                            )
                        }
                    }
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
    ownsBack: Boolean,
    onRepair: () -> Unit,
) {
    val shown by flow.collectAsState()
    when (val s = shown) {
        null -> WaitingForEmacs(onRepair)
        else -> {
            // S11: system back runs the presented screen's OWN back arrow —
            // bridge.action is the terminal call RenderCtx.action makes for a
            // surface descriptor, so the companion-local view switch and its
            // `view.switched` report are indistinguishable from a tap on the
            // arrow (drop-mode offline, exactly like the tap). Enabled only
            // while this screen authors one; otherwise the system default
            // proceeds and the Activity finishes, as it always has.
            //
            // Registered BEFORE the tree composes, so every handler the tree
            // installs — an open modal drawer's predictive back, an expanded
            // search bar — is added later and outranks this one (the back
            // dispatcher runs its callbacks newest-first).
            val back = chromeBackDescriptor(s.second)
            BackHandler(enabled = ownsBack && back != null) {
                back?.let { bridge.action(s.first, it) }
            }
            RenderNode(s.second, s.first, bridge)
        }
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

/**
 * SPEC 14.2 `companion.settings.open` (R4): the Companion's own settings.
 * Its own host for the house reason — opening it must not recompose the
 * surface tree.  First tenant: the amendment-#171 completion-narrowing
 * predicate, receiver-local presentation the user may set (strict is the
 * reference default); the choice persists through DeviceBridge's
 * prefs-backed property and emits nothing on the wire.
 */
@androidx.compose.runtime.Composable
private fun SettingsHost(
    app: EbpApplication,
    bridge: DeviceBridge,
    onOpenOnboarding: () -> Unit,
) {
    val open by app.settingsOpen.collectAsState()
    if (!open) return
    var narrowing by androidx.compose.runtime.remember {
        androidx.compose.runtime.mutableStateOf(bridge.completionNarrowing)
    }
    androidx.compose.material3.AlertDialog(
        onDismissRequest = { app.dismissSettings() },
        title = { Text("Companion settings") },
        text = {
            androidx.compose.foundation.layout.Column {
                Text("Completion narrowing",
                    style = MaterialTheme.typography.titleSmall)
                Text(
                    "How typing filters an open completion list.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                listOf(
                    com.calebc42.ebp.wire.CompletionNarrowing.STRICT
                        to "Strict — candidates start with what you typed",
                    com.calebc42.ebp.wire.CompletionNarrowing.CONTAINS
                        to "Contains — candidates match anywhere",
                ).forEach { (mode, label) ->
                    androidx.compose.foundation.layout.Row(
                        verticalAlignment =
                            androidx.compose.ui.Alignment.CenterVertically,
                        modifier = Modifier.padding(top = 8.dp)) {
                        androidx.compose.material3.RadioButton(
                            selected = narrowing == mode,
                            onClick = {
                                bridge.completionNarrowing = mode
                                narrowing = mode
                            })
                        Text(label,
                            style = MaterialTheme.typography.bodyMedium)
                    }
                }
                androidx.compose.material3.HorizontalDivider(
                    Modifier.padding(vertical = 12.dp))
                Text("Installation", style = MaterialTheme.typography.titleSmall)
                androidx.compose.material3.TextButton(onClick = onOpenOnboarding) {
                    Text("Set up or repair Jetpacs")
                }
            }
        },
        confirmButton = {
            androidx.compose.material3.TextButton(
                onClick = { app.dismissSettings() }) { Text("Done") }
        })
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
    flow: kotlinx.coroutines.flow.StateFlow<EbpApplication.DialogShow?>,
    bridge: DeviceBridge,
) {
    val dialog by flow.collectAsState()
    dialog?.let { (id, dspec, epoch) ->
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
                    RenderDialogRoot(id, dspec, bridge, epoch)
                }
            }
        }
    }
}
