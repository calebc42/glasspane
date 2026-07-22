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
import com.calebc42.ebp.wire.EbpAuth
import com.calebc42.ebp.wire.SessionState
import com.calebc42.ebp.wire.SurfaceStore
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

class DeviceBridge(private val onSurfaceChanged: (JSONObject?) -> Unit) {

    val store = SurfaceStore(64, 4096)
    @Volatile private var current: Socket? = null

    private val config = CompanionConfig(
        serverName = "ebp-companion",
        serverVersion = "0.1.0-w4",
        pairings = mapOf(
            "101112131415161718191a1b1c1d1e1f" to
                EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")),
        supportedCapabilities = setOf("theme"),
        surfaceProfiles = JSONObject().put("app", JSONObject()
            .put("node_types", JSONArray(listOf(
                "text", "row", "column", "box", "spacer", "divider",
                "button", "text_input")))
            .put("builtins", JSONArray(listOf(
                "view.switch", "companion.settings.open")))
            .put("features", JSONArray())),
        limits = JSONObject()
            .put("max_frame_bytes", 4_194_304).put("max_queued_events", 256)
            .put("max_queued_bytes", 8_388_608).put("max_event_bytes", 262_144)
            .put("max_surfaces", 64).put("max_surface_ids", 4096)
            .put("max_field_bytes", 65_536).put("max_input_state_bytes", 262_144)
            .put("max_capture_fields", 64),
    )

    fun start() = thread(name = "ebp-bridge", isDaemon = true) {
        val server = ServerSocket()
        server.reuseAddress = true
        // SPEC 5.2: bind only a loopback interface.
        server.bind(InetSocketAddress("127.0.0.1", 8765))
        while (true) {
            val socket = server.accept()
            // SPEC 5.2: one session at a time; the newcomer supersedes.
            current?.runCatching { close() }
            current = socket
            thread(name = "ebp-conn", isDaemon = true) { serve(socket) }
        }
    }

    private fun serve(socket: Socket) {
        val out = socket.getOutputStream()
        val engine = CompanionEngine(config, store) { bytes ->
            out.write(bytes); out.flush()
        }
        engine.surfaceListener = { surface ->
            if (surface.startsWith("app:")) onSurfaceChanged(store.spec(surface))
        }
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
            socket.runCatching { close() }
        }
    }
}
