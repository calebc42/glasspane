// SPDX-License-Identifier: GPL-3.0-or-later
// Process-lifetime bootstrap (SPEC 21, RF-0.5a). The firing service, trigger
// sources, durable recovery, AND the loopback listener come up on process
// start regardless of MainActivity — so triggers fire, throttle survives,
// pending-local occurrences resolve, and Emacs can dial in, even when the
// companion UI was never opened (a cold start from an alarm or a boot
// receiver). Before RF-0.5a the socket was the one process-lifetime concern
// this bootstrap omitted (audit P1-4): the listener was merely *started* from
// MainActivity, so an alarm cold-start revived triggers but left Emacs
// unreachable, and every rotation built a second bridge that lost the bind
// race while the first pushed into a destroyed Activity (audit P2-1).
package com.calebc42.ebp.companion

import android.app.ActivityManager
import android.app.Application
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.JsonObject

class EbpApplication : Application() {

    // Process-owned presentation state: the bridge writes, any Activity
    // observes. An Activity is a pure renderer of these flows — no bridge
    // callback may close over one (RF-0.5a's gate condition).
    private val _currentSpec = MutableStateFlow<Pair<String, JsonObject>?>(null)
    val currentSpec: StateFlow<Pair<String, JsonObject>?> get() = _currentSpec
    private val _currentDialog = MutableStateFlow<Pair<String, JsonObject>?>(null)
    val currentDialog: StateFlow<Pair<String, JsonObject>?> get() = _currentDialog
    // SPEC 18.4: the accepted theme payload ({dark, colors, syntax}) to mirror,
    // or null for the native scheme (dark = follow-system, amendment #36).
    private val _theme = MutableStateFlow<JsonObject?>(null)
    val theme: StateFlow<JsonObject?> get() = _theme
    private val _currentPieMenu = MutableStateFlow<Pair<String, JsonObject>?>(null)
    val currentPieMenu: StateFlow<Pair<String, JsonObject>?> get() = _currentPieMenu
    // SPEC 14.2 companion.settings.open (R4): the Companion's OWN settings
    // sheet — receiver-local presentation state, no wire member anywhere.
    private val _settingsOpen = MutableStateFlow(false)
    val settingsOpen: StateFlow<Boolean> get() = _settingsOpen
    fun dismissSettings() { _settingsOpen.value = false }

    lateinit var bridge: DeviceBridge
        private set

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        // LD-11: size the image cache to this device's per-app memory class.
        // An eighth of the app heap is a conservative retention budget — the
        // Semaphore(3) already bounds concurrent decodes on top of it.
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        com.calebc42.ebp.companion.render.ImageCache.configure(
            am.memoryClass.toLong() * 1024 * 1024 / 8)
        val firing = CompanionStores.firing(this)
        // SPEC 21.2: resolve anything a crash left mid-transaction first.
        firing.recover()
        // Sticky sources seed the current state; then baseline silently so a
        // change that happened while dead does not fire (SPEC 21.5).
        CompanionStores.triggerSources(this).start()
        firing.armAllBaselines()
        // SPEC 18.6/21.5: a cold start (after force-stop or reboot) lost the
        // platform alarms — re-arm reminders + time triggers from durable state.
        Notifications.rearmAllReminders(this)
        TriggerAlarms.reschedule(this)
        // RF-0.5a: the listener last, after durable recovery, so the first
        // session to dial sees recovered state. Toasts ride the main looper
        // with the application context — the bridge's callbacks reference
        // only this process singleton, never an Activity.
        bridge = DeviceBridge(
            this,
            onSurfaceChanged = { surface, spec ->
                _currentSpec.value = if (spec != null) surface to spec else null
            },
            // SPEC 15.1: storage failure and queue exhaustion MUST reach the
            // user as a visible diagnostic.
            onQueueProblem = { message ->
                mainHandler.post {
                    Toast.makeText(this, "EBP queue: $message",
                                   Toast.LENGTH_LONG).show()
                }
            },
            onDialogChanged = { id, spec ->
                // SPEC 18.1: one outstanding dialog presented at a time here.
                _currentDialog.value =
                    if (spec != null && id != null) id to spec else null
            },
            onToast = { text ->
                mainHandler.post {
                    Toast.makeText(this, text, Toast.LENGTH_SHORT).show()
                }
            },
            onTheme = { payload -> _theme.value = payload },
            onPieMenuChanged = { id, spec ->
                _currentPieMenu.value = if (spec != null) id to spec else null
            },
            onOpenSettings = { _settingsOpen.value = true })
        bridge.start()
    }
}
