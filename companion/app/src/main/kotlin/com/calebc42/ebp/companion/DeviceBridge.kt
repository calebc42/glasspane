// SPDX-License-Identifier: GPL-3.0-or-later
// The android-loopback-tcp binder (SPEC 5.2): 127.0.0.1:8765, one client,
// a new authenticated session supersedes the old. Wraps CompanionEngine;
// the store outlives connections (SPEC 10.4).
//
// W4 SMOKE SCOPE: the pairing is the SPEC 9.3 known-answer credentials so
// the desktop can drive the device before the pairing UI exists (arrives
// with onboarding). Not a secret and not a deployment configuration.
package com.calebc42.ebp.companion

import com.calebc42.ebp.wire.CompanionEngine
import com.calebc42.ebp.wire.CompanionConfig
import com.calebc42.ebp.wire.DurableQueue
import com.calebc42.ebp.wire.EbpAuth
import com.calebc42.ebp.wire.FileQueueStore
import com.calebc42.ebp.wire.FileSurfaceBacking
import com.calebc42.ebp.wire.SessionState
import com.calebc42.ebp.wire.SurfaceStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

class DeviceBridge(
    private val appContext: android.content.Context,
    queueFile: File,
    surfaceFile: File,
    private val onSurfaceChanged: (JSONObject?) -> Unit,
    /** SPEC 15.1: storage failure and queue exhaustion MUST reach the
     * user as a visible diagnostic. */
    private val onQueueProblem: (String) -> Unit = {},
    /** SPEC 18.1: (dialog_id, spec) to present; (dialog_id, null) to
     * dismiss. */
    private val onDialogChanged: (String?, JSONObject?) -> Unit = { _, _ -> },
    /** SPEC 18.2: best-effort toast text. */
    private val onToast: (String) -> Unit = {},
    /** SPEC 18.4: theme polarity — true/false forced, null follow-system. */
    private val onTheme: (Boolean?) -> Unit = {},
    /** SPEC 18.3: (menu_id, spec) to present; (menu_id, null) to dismiss. */
    private val onPieMenuChanged: (String, JSONObject?) -> Unit = { _, _ -> },
) {

    // SPEC 13.1/15.1: surface histories, tombstones, and input_state drafts
    // survive process and device restarts, like the durable queue.
    val store = SurfaceStore(64, 4096, backing = FileSurfaceBacking(surfaceFile))

    /** SPEC 15: the durable queue survives process and device restarts. */
    val queue = DurableQueue(FileQueueStore(queueFile), 256, 8_388_608)
    @Volatile private var current: Socket? = null

    private val config = CompanionConfig(
        serverName = "ebp-companion",
        serverVersion = "0.1.0-w4",
        pairings = mapOf(
            "101112131415161718191a1b1c1d1e1f" to
                EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")),
        supportedCapabilities = setOf("theme", "surfaces.dialog", "presentation.toast",
            "presentation.pie-menu", "reminders.owner", "surfaces.notification"),
        surfaceProfiles = JSONObject()
            .put("app", JSONObject()
                .put("node_types", JSONArray(listOf(
                    "text", "row", "column", "box", "spacer", "divider",
                    "button", "text_input", "scaffold")))
                .put("builtins", JSONArray(listOf(
                    "view.switch", "companion.settings.open")))
                .put("features", JSONArray()))
            .put("dialog", JSONObject()
                .put("node_types", JSONArray(listOf(
                    "text", "row", "column", "box", "spacer", "divider",
                    "button", "text_input")))
                .put("builtins", JSONArray(listOf("dialog.submit", "dialog.dismiss")))
                .put("features", JSONArray()))
            .put("notification", JSONObject()
                .put("node_types", JSONArray(listOf(
                    "text", "row", "column", "box", "spacer", "divider")))
                .put("builtins", JSONArray())
                .put("features", JSONArray())),
        limits = JSONObject()
            .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
            .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
            .put("max_surfaces", 64).put("max_surface_ids", 4096)
            .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
            .put("max_capture_fields", 64).put("max_dialogs", 4)
            .put("max_pie_menus", 1).put("max_reminders", 256),
    )

    fun start() = thread(name = "ebp-bridge", isDaemon = true) {
        try {
            val server = ServerSocket()
            server.reuseAddress = true
            // SPEC 5.2: bind only a loopback interface. A restart can race
            // the previous process's socket release (EADDRINUSE); retry
            // rather than crash the app.
            var bound = false
            for (attempt in 0 until 20) {
                try {
                    server.bind(InetSocketAddress("127.0.0.1", 8765))
                    bound = true; break
                } catch (e: java.net.BindException) { Thread.sleep(500) }
            }
            if (!bound) return@thread
            while (true) {
                val socket = server.accept()
                // SPEC 5.2: one session at a time; the newcomer supersedes.
                current?.runCatching { close() }
                current = socket
                thread(name = "ebp-conn", isDaemon = true) { serve(socket) }
            }
        } catch (_: Exception) {
            // The listener thread must never take down the host app.
        }
    }

    @Volatile private var engine: CompanionEngine? = null

    // Renderer hooks arrive on the Compose main thread; socket writes are
    // prohibited there (NetworkOnMainThreadException). One dispatch thread
    // also preserves SPEC 14.6 state-before-action ordering by itself.
    private val dispatchExecutor =
        java.util.concurrent.Executors.newSingleThreadExecutor { r ->
            Thread(r, "ebp-dispatch").apply { isDaemon = true }
        }

    /** SPEC 14.1: renderer hook -> remote action through the live engine. */
    fun action(surface: String, descriptor: JSONObject?, value: Any? = null) {
        descriptor ?: return
        dispatchExecutor.execute {
            engine?.dispatchAction(surface, descriptor, value) { _, error ->
                // SPEC 15.1: surface queue-full/storage failures visibly.
                error?.let { onQueueProblem(it.optString("message", "queue error")) }
            }
        }
    }

    /** SPEC 14.6: renderer edit -> draft + state.changed publication. */
    fun state(surface: String, id: String, value: Any?) {
        dispatchExecutor.execute { engine?.publishState(surface, id, value) }
    }

    /** SPEC 18.1: dialog.submit builtin -> complete the outstanding request. */
    fun dialogSubmit(dialogId: String, value: Any?, fields: JSONObject) {
        dispatchExecutor.execute { engine?.completeDialogSubmit(dialogId, value, fields) }
    }

    /** SPEC 18.1: dialog.dismiss builtin / platform dismissal. */
    fun dialogDismiss(dialogId: String) {
        dispatchExecutor.execute { engine?.completeDialogDismiss(dialogId) }
    }

    /** SPEC 18.3: a radial selection with its zero-based indices. */
    fun pieMenuSelect(menuId: String, categoryIndex: Int, itemIndex: Int?) {
        dispatchExecutor.execute { engine?.selectPieMenu(menuId, categoryIndex, itemIndex) }
    }

    /** SPEC 18.3: dismiss the pie menu on an outside tap. */
    fun pieMenuDismiss(menuId: String) {
        dispatchExecutor.execute {
            engine?.let { e ->
                e.feed(com.calebc42.ebp.wire.encodeFrame(JSONObject()
                    .put("jsonrpc", "2.0").put("method", "pie_menu.dismiss")
                    .put("params", JSONObject().put("menu_id", menuId)).toString()))
            }
        }
    }

    private fun serve(socket: Socket) {
        val out = socket.getOutputStream()
        val engine = CompanionEngine(config, store, queue) { bytes ->
            // The sink runs on whatever thread emits — the reader, the pump,
            // or the UI dispatch executor. A peer that went away mid-write
            // MUST NOT crash that thread (and with it the app): close the
            // socket so the reader loop unwinds through engine.close().
            try {
                out.write(bytes); out.flush()
            } catch (_: java.io.IOException) {
                socket.runCatching { close() }
            }
        }
        this.engine = engine
        engine.surfaceListener = { surface ->
            when {
                // SPEC 18.5: a notification:* surface is a system notification;
                // its removal (tombstone -> null spec) cancels it.
                surface.startsWith("notification:") -> {
                    val spec = store.spec(surface)
                    if (spec != null) Notifications.postSurface(appContext, surface, spec)
                    else Notifications.cancelSurface(appContext, surface)
                }
                surface.startsWith("app:") -> onSurfaceChanged(store.spec(surface))
            }
        }
        // SPEC 18.6: an accepted reminder set arms exact alarms.
        engine.reminderListener = { owner, reminders ->
            Notifications.scheduleReminders(appContext, owner, reminders)
        }
        engine.dialogListener = { id, spec -> onDialogChanged(id, spec) }
        engine.toastListener = { text, _ -> onToast(text) }
        engine.themeListener = { dark, _, _ -> onTheme(dark) }
        engine.pieMenuListener = { id, spec -> onPieMenuChanged(id, spec) }
        val input = socket.getInputStream()
        val buffer = ByteArray(8192)
        try {
            while (engine.state != SessionState.CLOSED) {
                val n = input.read(buffer)
                if (n < 0) break
                engine.feed(buffer.copyOf(n))
            }
        } catch (_: Exception) {
            // transport loss: SPEC 10.1, any state may close
        } finally {
            // SPEC 15.3: the engine releases its in-flight marker so the
            // next session's replay is never wedged (review P0).
            engine.close("transport closed")
            socket.runCatching { close() }
        }
    }
}
