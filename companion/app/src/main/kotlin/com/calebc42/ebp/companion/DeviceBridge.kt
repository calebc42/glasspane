// SPDX-License-Identifier: GPL-3.0-or-later
// The android-loopback-tcp binder (SPEC 5.2): 127.0.0.1:8765, one client,
// a new authenticated session supersedes the old. Wraps CompanionEngine;
// the store outlives connections (SPEC 10.4).
//
// W4 SMOKE SCOPE: the pairing is the SPEC 9.3 known-answer credentials so
// the desktop can drive the device before the pairing UI exists (arrives
// with onboarding). Not a secret and not a deployment configuration.
package com.calebc42.ebp.companion

import com.calebc42.ebp.companion.render.ImageCache
import com.calebc42.ebp.companion.render.objOrNull
import com.calebc42.ebp.companion.render.stringOr
import com.calebc42.ebp.wire.CompanionEngine
import com.calebc42.ebp.wire.CompanionConfig
import com.calebc42.ebp.wire.EbpAuth
import com.calebc42.ebp.wire.EditorSession
import com.calebc42.ebp.wire.InputDisplay
import com.calebc42.ebp.wire.ScalarPos
import com.calebc42.ebp.wire.SessionState
import com.calebc42.ebp.wire.Utf16Pos
import com.calebc42.ebp.wire.utf16PosIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.util.concurrent.atomic.AtomicLong
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

/**
 * T2/LD-5: the display's copy of one synchronized editor — the shadow text
 * with the caret in Compose's UTF-16 domain, stamped with the session `seq`
 * and a bridge-local `epoch` (each publication bumps it, so adoption keys on
 * epoch and never replays). Published on every inbound `edit.apply` and on
 * every refused local edit (the snap-back): the shadow is the one text
 * authority, and the field follows it.
 */
data class EditorMirror(
    val text: String,
    val cursorU: Int,
    val selStartU: Int,
    val selEndU: Int,
    val seq: Long,
    val epoch: Long,
)

/** SPEC 19.3: one candidate. `insert` is already defaulted to `label`. */
data class CompletionCandidate(
    val label: String,
    val annotation: String?,
    val insert: String,
)

/**
 * SPEC 19.3 (JC-4b): one answered `edit.complete`, with the editor state it
 * was ISSUED against. Selecting a candidate hands that state back so the
 * engine can refuse a tap whose caret has since moved — validating against
 * the engine's current state instead would compare it with itself.
 */
data class CompletionOffer(
    val prefix: String,
    val candidates: List<CompletionCandidate>,
    val session: String,
    val seq: Long,
    val cursor: Int,
    val epoch: Long,
)

class DeviceBridge(
    private val appContext: android.content.Context,
    /** SPEC 14.4: the shown surface's ID travels with its spec, so an
     * event names the surface the action actually occurred in. */
    private val onSurfaceChanged: (String, JsonObject?) -> Unit,
    /** SPEC 15.1: storage failure and queue exhaustion MUST reach the
     * user as a visible diagnostic. */
    private val onQueueProblem: (String) -> Unit = {},
    /** SPEC 18.1: (dialog_id, spec) to present; (dialog_id, null) to
     * dismiss. */
    private val onDialogChanged: (String?, JsonObject?) -> Unit = { _, _ -> },
    /** SPEC 18.2: best-effort toast text. */
    private val onToast: (String) -> Unit = {},
    /** SPEC 18.4: the accepted theme payload (`{dark, colors, syntax}`) to
     * mirror, or null for the native scheme. Persisted, so a cached theme is
     * delivered once at start before any session. */
    private val onTheme: (JsonObject?) -> Unit = {},
    /** SPEC 18.3: (menu_id, spec) to present; (menu_id, null) to dismiss. */
    private val onPieMenuChanged: (String, JsonObject?) -> Unit = { _, _ -> },
) {

    // SPEC 13.1/15.1/18.6: the durable stores are process-wide singletons
    // (CompanionStores), shared with cold-started manifest receivers.
    // `store` is lazy because SurfaceStore's init reads and revalidates the
    // whole surfaces file, and since RF-0.5a this constructor runs in
    // Application.onCreate on the main thread at every process start —
    // including broadcast-only cold starts that never render a surface.
    // First touch is on a bridge/connection thread (serve(), listeners),
    // the same place the cached-theme read already lives.
    val store by lazy { CompanionStores.surfaces(appContext) }
    val queue = CompanionStores.queue(appContext)
    private val reminders = CompanionStores.reminders(appContext)
    private val triggers = CompanionStores.triggers(appContext)
    // SPEC 21: the device-lifetime firing service (process-wide). This engine
    // attaches to it as the LiveSession in its constructor; the sources feed it
    // directly (EbpApplication), independent of any connection.
    private val firing = CompanionStores.firing(appContext)
    @Volatile private var current: Socket? = null

    private val config = CompanionConfig(
        serverName = "ebp-companion",
        serverVersion = "0.1.0-w4",
        pairings = mapOf(
            "101112131415161718191a1b1c1d1e1f" to
                EbpAuth.decodePairingToken("AAECAwQFBgcICQoLDA0ODw")),
        supportedCapabilities = setOf("theme", "surfaces.dialog", "presentation.toast",
            "presentation.snackbar",
            "presentation.pie-menu", "reminders.owner", "surfaces.notification",
            "editor.sync", "capabilities", "triggers"),
        // SPEC 10.2: what this build's renderer actually honors — derived from
        // the render/NodeSupport registry (the pin test holds the renderer's
        // dispatch to the same sets), never hand-kept here.
        surfaceProfiles = com.calebc42.ebp.companion.render.NodeSupport.surfaceProfiles(),
        // C6: every value below stays INTEGER-spelled. The engine's constructor
        // reads the limits with reqLong, so a `.0` spelling would not merely
        // widen a bound — it would throw at engine construction.
        limits = buildJsonObject {
            put("max_frame_bytes", 4_194_304)
            put("max_queued_events", 256)
            put("max_queued_bytes", 8_388_608)
            put("max_event_bytes", 262_144)
            put("max_surfaces", 64)
            put("max_surface_ids", 4096)
            put("max_field_bytes", 65_536)
            put("max_input_state_bytes", 262_144)
            put("max_capture_fields", 64)
            put("max_dialogs", 4)
            put("max_pie_menus", 1)
            put("max_reminders", 256)
            put("max_editor_sessions", 8)
            put("max_trigger_responses", 8)
            put("max_triggers", 64)
            put("max_device_report_bytes", 8192)
            // SPEC 4.5/17.2: the three image limits are REQUIRED whenever image
            // is advertised — the same constants the loader enforces (no drift).
            put("max_image_bytes",
                com.calebc42.ebp.companion.render.ImageLoader.MAX_IMAGE_BYTES)
            put("max_decoded_image_bytes",
                com.calebc42.ebp.companion.render.ImageLoader.MAX_DECODED_IMAGE_BYTES)
            put("max_image_pixels",
                com.calebc42.ebp.companion.render.ImageLoader.MAX_IMAGE_PIXELS)
            // SPEC 4.5/17.5: REQUIRED whenever chart/canvas are advertised.
            put("max_chart_points", 4096)
            put("max_canvas_ops", 4096)
            // SPEC 4.5: REQUIRED whenever rich_text/table are advertised —
            // aggregate counts across one SurfaceSpec or dialog (LD-22).
            put("max_rich_spans", 4096)
            put("max_table_cells", 4096)
            // SPEC 4.5 (amendment #84): REQUIRED when editor.sync is granted.
            // Declared at the floor: it is what keeps every editor path
            // (shadow rebuild, diff, highlight, relayout) comfortably linear.
            put("max_editor_bytes", 65_536)
        },
        // SPEC 20.1/20.2: advertise the device report and the platform executor.
        deviceReport = AppCapabilities.deviceReport(),
        capabilityHandler = AppCapabilities.handler(appContext, 65_536),
    )

    // SPEC 18.4: the theme survives disconnects and process restarts — like a
    // cached surface, the device keeps looking like your Emacs while it is away.
    private val themeFile = File(appContext.filesDir, "ebp-theme.json")

    // C6: a PERSISTENCE read, so it parses with the plain lenient parser and
    // never with the wire's strict frame parser — an `ebp-theme.json` written
    // by a pre-upgrade (org.json) build must still load. The catch below
    // already covers the new failure kinds (SerializationException,
    // IllegalArgumentException, and the cast's ClassCastException).
    private fun loadTheme(): JsonObject? =
        try {
            if (themeFile.exists())
                Json.parseToJsonElement(themeFile.readText()) as JsonObject
            else null
        } catch (e: Exception) { null }

    private fun saveTheme(payload: JsonObject) {
        try {
            val tmp = File(themeFile.parentFile, "ebp-theme.json.tmp")
            tmp.writeText(payload.toString())
            tmp.renameTo(themeFile) // atomic swap; a torn write never survives
        } catch (e: Exception) { /* best-effort; a lost theme re-syncs next run */ }
    }

    fun start() = thread(name = "ebp-bridge", isDaemon = true) {
        // Deliver the cached theme before any session so a reconnecting device
        // renders in the mirrored palette immediately (§18.4 persistence).
        loadTheme()?.let { onTheme(it) }
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
                // Neither may the CONNECTION thread. `serve` sets up a whole
                // engine before it ever reads, and every line of that setup
                // runs on a socket a newcomer may already have closed; an
                // escape here is a FATAL EXCEPTION on a daemon thread, i.e.
                // the whole Companion dies while merely being reconnected to.
                thread(name = "ebp-conn", isDaemon = true) {
                    runCatching { serve(socket) }
                    socket.runCatching { close() }
                }
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


    // SPEC 14.1 `confirm`: the descriptor asks the Companion to have the user
    // confirm BEFORE the event is created.  Emacs relies on that: an action
    // carrying `confirm` never prompts on its side, because prompting inside
    // the dispatch extent is forbidden — so an unimplemented `confirm` turns
    // a guarded destructive verb into an immediate one.  (The JA-6 device
    // gate found exactly that: the member lived in the vocabulary and the
    // validator, and no chrome ever presented it, so a Delete tap deleted.)
    // The dispatch is PARKED here; `resolveConfirm' releases or drops it.
    data class PendingConfirm(
        val prompt: String, val surface: String, val descriptor: JsonObject,
        val value: JsonElement?, val injected: JsonObject?, val fields: JsonObject?,
        // §14.1: the object form's optional face — a bare-string confirm
        // leaves all four null and the host draws what it always drew.
        val title: String? = null, val icon: String? = null,
        val confirmLabel: String? = null, val dismissLabel: String? = null)

    private val _pendingConfirm = MutableStateFlow<PendingConfirm?>(null)
    val pendingConfirm: StateFlow<PendingConfirm?> get() = _pendingConfirm

    /** Release (RUN true) or drop the parked confirmation. */
    fun resolveConfirm(run: Boolean) {
        val p = _pendingConfirm.value ?: return
        _pendingConfirm.value = null
        if (run) dispatch(p.surface, p.descriptor, p.value, p.injected, p.fields)
    }

    /** Park when DESCRIPTOR carries `confirm`; true when parked. */
    private fun parkIfConfirmed(surface: String, descriptor: JsonObject,
                                value: JsonElement?, injected: JsonObject?,
                                fields: JsonObject?): Boolean {
        // §14.1: `confirm` is a bare string, or the object form
        // {text, title?, icon?, confirm_label?, dismiss_label?}.
        val obj = descriptor.objOrNull("confirm")
        val prompt = obj?.stringOr("text") ?: descriptor.stringOr("confirm")
        if (prompt.isEmpty()) return false
        // One outstanding confirmation: the modal is what the user is
        // looking at, so a second tap cannot reach another descriptor.
        _pendingConfirm.value = PendingConfirm(
            prompt, surface, descriptor, value, injected, fields,
            title = obj?.stringOr("title")?.takeIf { it.isNotEmpty() },
            icon = obj?.stringOr("icon")?.takeIf { it.isNotEmpty() },
            confirmLabel = obj?.stringOr("confirm_label")?.takeIf { it.isNotEmpty() },
            dismissLabel = obj?.stringOr("dismiss_label")?.takeIf { it.isNotEmpty() })
        return true
    }

    private fun dispatch(surface: String, descriptor: JsonObject, value: JsonElement?,
                         injected: JsonObject?, fields: JsonObject?) {
        dispatchExecutor.execute {
            // SPEC 18.1/14.4: a `dialog:` context dispatches in DIALOG
            // context — dialog_id, no surface/revision.  The generic path
            // resolved a revision for the pseudo-surface, got null, and
            // silently dropped every remote descriptor inside a dialog
            // (found by the JA-5 device gate).  Routed HERE so a parked
            // confirmation resumes through the same fork.
            if (surface.startsWith("dialog:"))
                engine?.dispatchDialogAction(
                    surface.removePrefix("dialog:"), descriptor, value,
                    fields) { _, error ->
                    error?.let { onQueueProblem(it.stringOr("message", "queue error")) }
                }
            else engine?.dispatchAction(surface, descriptor, value, injected, fields) { _, error ->
                // SPEC 15.1: surface queue-full/storage failures visibly.
                error?.let { onQueueProblem(it.stringOr("message", "queue error")) }
            }
        }
    }

    /** SPEC 14.1: renderer hook -> remote action through the live engine. */
    fun action(surface: String, descriptor: JsonObject?, value: JsonElement? = null) {
        descriptor ?: return
        if (parkIfConfirmed(surface, descriptor, value, null, null)) return
        dispatch(surface, descriptor, value, null, null)
    }

    /** SPEC 18.1: renderer hook -> remote action from INSIDE a dialog.
     * FIELDS is the capture snapshot read from the dialog's LOCAL field
     * layer at tap time (dialog statefuls never enter the store). */
    fun dialogAction(dialogId: String, descriptor: JsonObject?, value: JsonElement?,
                     fields: JsonObject?) {
        descriptor ?: return
        val surface = "dialog:" + dialogId
        if (parkIfConfirmed(surface, descriptor, value, null, fields)) return
        dispatch(surface, descriptor, value, null, fields)
    }

    /** SPEC 14.3: a multi-member hook (on_reorder from/to/order, on_add_row/
     * col index, swipe direction) injects a member object beside args. */
    fun actionInjecting(surface: String, descriptor: JsonObject?, injected: JsonObject,
                        value: JsonElement? = null) {
        descriptor ?: return
        if (parkIfConfirmed(surface, descriptor, value, injected, null)) return
        dispatch(surface, descriptor, value, injected, null)
    }

    /** SPEC 14.6: a renderer-supplied occurrence-time field value — a
     * text_input password's on_submit, whose secret has no retained draft. */
    fun actionWithFields(surface: String, descriptor: JsonObject?, fields: JsonObject) {
        descriptor ?: return
        if (parkIfConfirmed(surface, descriptor, null, null, fields)) return
        dispatch(surface, descriptor, null, null, fields)
    }

    /** SPEC 14.6: renderer edit -> draft + state.changed publication. */
    fun state(surface: String, id: String, value: JsonElement?,
              caret: Int? = null) {
        dispatchExecutor.execute { engine?.publishState(surface, id, value, caret) }
    }

    // A tiny scope for the fire-and-forget cache bind (SPEC 17.2 identity
    // scoping); the cache owns its own IO scope for the fetches themselves.
    private val cacheScope = kotlinx.coroutines.CoroutineScope(
        kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.Default)

    // T3/LD-2: display generations for stateful nodes, keyed (surface, id).
    // Republished with every accepted snapshot; a widget's remember key
    // carries its epoch, so a value the SNAPSHOT decided reseeds the widget
    // while a value the user is still editing does not.
    private val _inputDisplays =
        MutableStateFlow<Map<Pair<String, String>, InputDisplay>>(emptyMap())
    val inputDisplays: StateFlow<Map<Pair<String, String>, InputDisplay>>
        get() = _inputDisplays

    // T2/LD-5: the editor mirrors, keyed (document, editor_id). RenderEditor
    // collects this and adopts on epoch change; see EditorMirror above.
    private val mirrorEpoch = AtomicLong(0)
    private val _editorMirrors =
        MutableStateFlow<Map<Pair<String, String>, EditorMirror>>(emptyMap())
    val editorMirrors: StateFlow<Map<Pair<String, String>, EditorMirror>>
        get() = _editorMirrors

    /** Publish S as the display's text authority. Caret converts scalar ->
     * UTF-16 against the shadow through the one named conversion pair.
     * Called under the engine monitor (editorListener) or inside a
     * withEditor block — session reads are never torn. */
    private fun publishMirror(s: EditorSession) {
        val text = s.shadow
        val m = EditorMirror(
            text,
            utf16PosIn(text, ScalarPos(s.cursor)).v,
            utf16PosIn(text, ScalarPos(s.selStart)).v,
            utf16PosIn(text, ScalarPos(s.selEnd)).v,
            s.seq, mirrorEpoch.incrementAndGet())
        _editorMirrors.value =
            _editorMirrors.value + ((s.document to s.editorId) to m)
    }

    // SPEC 19.3 (JC-4b): completion offers, keyed (document, editor_id).
    // RenderEditor collects this and shows a dropdown; an offer is REPLACED
    // by the next one and cleared when its editor's text moves, so a stale
    // candidate list can never be tapped.
    private val offerEpoch = AtomicLong(0)
    private val _completionOffers =
        MutableStateFlow<Map<Pair<String, String>, CompletionOffer>>(emptyMap())
    val completionOffers: StateFlow<Map<Pair<String, String>, CompletionOffer>>
        get() = _completionOffers

    /** SPEC 19.3: ask Emacs to complete at the caret. The (session, seq,
     * cursor) the request was issued against ride along so a later selection
     * is validated against THAT state, not against whatever the engine holds
     * when the user finally taps. */
    fun editorComplete(document: String, editorId: String) {
        dispatchExecutor.execute {
            engine?.requestCompletion(document, editorId) {
                prefix, cands, session, seq, cursor ->
                val list = cands.mapNotNull { e ->
                    (e as? JsonObject)?.let { c ->
                        CompletionCandidate(
                            c.stringOr("label"),
                            c.stringOr("annotation").takeIf { it.isNotEmpty() },
                            // SPEC 19.3: `insert` defaults to `label`.
                            c.stringOr("insert").takeIf { it.isNotEmpty() }
                                ?: c.stringOr("label"))
                    }
                }
                _completionOffers.value = _completionOffers.value +
                    ((document to editorId) to CompletionOffer(
                        prefix, list, session, seq, cursor,
                        offerEpoch.incrementAndGet()))
            }
        }
    }

    /** SPEC 19.3: accept a candidate — a local edit replacing the prefix.
     * The engine refuses a selection whose session/seq/cursor have moved,
     * so a stale tap is a no-op rather than a wrong edit (SPEC 19.2). */
    fun editorSelectCompletion(document: String, editorId: String,
                               offer: CompletionOffer, insert: String) {
        clearCompletions(document, editorId)
        dispatchExecutor.execute {
            val e = engine ?: return@execute
            if (!e.selectCompletion(document, editorId, offer.session, offer.seq,
                    offer.cursor, offer.prefix, insert))
                e.withEditor(document, editorId) { publishMirror(it) }
        }
    }

    /** Drop any offer for this editor: the caret moved, or one was taken. */
    fun clearCompletions(document: String, editorId: String) {
        _completionOffers.value = _completionOffers.value - (document to editorId)
    }

    /** SPEC 19.3: a synchronized editor's local edit -> shadow + edit.delta.
     * BASE is the view's pre-edit text: the engine refuses a splice derived
     * from a superseded document (amendment #100), which is what makes a
     * keystroke racing an inbound edit.apply safe. Any refusal — stale base,
     * no OPEN session in READY, or past max_editor_bytes ("as if the editor
     * were read-only", SPEC 19.4) — publishes the unchanged shadow so the
     * field snaps back instead of silently diverging. */
    fun editorEdit(document: String, editorId: String, start: ScalarPos, del: Int,
                   text: String, base: String) {
        dispatchExecutor.execute {
            val e = engine ?: return@execute
            if (!e.localEditorEdit(document, editorId, start, del, text, base))
                e.withEditor(document, editorId) { publishMirror(it) }
        }
    }

    /** SPEC 17.7: a toolbar `command` -> non-durable edit.command
     * event.action. Positions are Compose UTF-16; the engine converts to
     * scalars against the shadow (LD-4). */
    fun editorCommand(surface: String, document: String, editorId: String,
                      command: String, cursor: Int, selStart: Int, selEnd: Int) {
        dispatchExecutor.execute {
            engine?.editorCommand(surface, document, editorId, command,
                Utf16Pos(cursor), Utf16Pos(selStart), Utf16Pos(selEnd))
        }
    }

    /** SPEC 18.1: dialog.submit builtin -> complete the outstanding request. */
    fun dialogSubmit(dialogId: String, value: JsonElement?, fields: JsonObject) {
        dispatchExecutor.execute { engine?.completeDialogSubmit(dialogId, value, fields) }
    }

    /** SPEC 14.1/18.1 (T3/LD-3): the authored values the engine computed for
     * this dialog's stateful nodes, so an untouched field captures its
     * logical value. Read once when the dialog is presented. */
    fun dialogDefaults(dialogId: String): JsonObject? = engine?.dialogDefaults(dialogId)

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
                // C6: the envelope comes from the wire's own SPEC 7.1 builder,
                // which emits `jsonrpc` itself — one spelling of the envelope
                // instead of a second hand-rolled one here.
                e.feed(com.calebc42.ebp.wire.encodeFrame(
                    com.calebc42.ebp.wire.notification("pie_menu.dismiss",
                        buildJsonObject { put("menu_id", menuId) }).toString()))
            }
        }
    }

    // SPEC 20.1.1: the last geometry the Activity reported, for seeding
    // sessions that begin before (or after) a recomposition.
    private var lastWindow: Pair<Int, Int>? = null

    /** SPEC 20.1.1: the Activity reports window geometry here on first
     * composition and every configuration change. The caller is the COMPOSE
     * UI thread and windowChanged may emit a notification — a socket write —
     * so the engine call marshals through the dispatch executor exactly like
     * every other UI-originated engine call (NetworkOnMainThreadException
     * killed the whole process on rotation before it did). */
    fun windowChanged(widthDp: Int, heightDp: Int) {
        lastWindow = widthDp to heightDp
        dispatchExecutor.execute { engine?.windowChanged(widthDp, heightDp) }
    }

    /** SPEC 13.4/14.2: resolve a multi-view spec to the view being shown;
     * a single-view spec passes through. */
    private fun resolveView(surface: String): JsonObject? {
        val spec = store.spec(surface) ?: return null
        val views = spec.objOrNull("views") ?: return spec
        val name = store.currentView(surface) ?: spec.stringOr("initial_view")
        return views.objOrNull(name)
    }

    private fun serve(socket: Socket) {
        val out = socket.getOutputStream()
        val engine = CompanionEngine(config, store, queue, reminders, triggers, firing) { bytes ->
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
        // SPEC 20.1.1: seed the new session with the last-known geometry so
        // the welcome can mirror it before the Activity recomposes.
        lastWindow?.let { (w, h) -> engine.windowChanged(w, h) }
        // SPEC 18.2.1: the event-driven snackbar routes to whichever
        // scaffold host is on screen.
        engine.snackbarListener = { message, action, duration, respond ->
            // The consumer answers from the COMPOSE UI thread when the
            // snackbar leaves the screen; the reply is a socket write, so it
            // marshals through the dispatch executor like every other
            // UI-originated engine call.
            com.calebc42.ebp.companion.render.SnackbarRaises.flow.value =
                com.calebc42.ebp.companion.render.SnackbarRaises.Raise(
                    message, action, duration) { outcome ->
                    dispatchExecutor.execute { respond(outcome) }
                }
        }
        // SPEC 5.2 newest-wins: cold receivers (reminder tap/alarm) reach the
        // current live session through this slot; a drop with no session is lost.
        CompanionStores.setLiveSession(engine)
        engine.surfaceListener = { surface ->
            // SPEC 17.2/9.1: bind the image cache to THIS session's
            // authenticated pairing identity before any image can render.
            // A different identity erases what the previous one fetched —
            // the §9.1 empty state partition, enforced rather than trusted
            // to a revocation call that may never arrive.
            engine.pairingIdentity?.let { id ->
                cacheScope.launch { ImageCache.setIdentity(id) }
            }
            // T3/LD-2: publish display generations before the spec, so the
            // recomposition this push triggers already sees the new epoch.
            _inputDisplays.value = store.inputDisplays()
            when {
                // SPEC 18.5: a notification:* surface is a system notification;
                // its removal (tombstone -> null spec) cancels it.
                surface.startsWith("notification:") -> {
                    val spec = store.spec(surface)
                    if (spec != null) Notifications.postSurface(appContext, surface, spec)
                    else Notifications.cancelSurface(appContext, surface)
                }
                surface.startsWith("app:") ->
                    onSurfaceChanged(surface, resolveView(surface))
            }
        }
        // SPEC 14.2: host-platform builtins. Settings is a stub until the app
        // shell lands (deferred scope) — visible, honest, no silent drop.
        engine.hostBuiltinListener = { builtin, descriptor ->
            when (builtin) {
                "clipboard.copy" -> {
                    val clip = android.content.ClipData.newPlainText(
                        "EBP", descriptor.stringOr("text"))
                    appContext.getSystemService(
                        android.content.ClipboardManager::class.java)
                        .setPrimaryClip(clip)
                    // SPEC 14.2: no additional private copy, no logging.
                }
                "share.send" -> {
                    val send = android.content.Intent(android.content.Intent.ACTION_SEND)
                        .setType("text/plain")
                        .putExtra(android.content.Intent.EXTRA_TEXT,
                            descriptor.stringOr("text"))
                        .also {
                            descriptor.stringOr("title").takeIf { t -> t.isNotEmpty() }
                                ?.let { t -> it.putExtra(
                                    android.content.Intent.EXTRA_TITLE, t) }
                        }
                    appContext.startActivity(
                        android.content.Intent.createChooser(send, null)
                            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                }
                "companion.settings.open" ->
                    onToast("Companion settings arrive with the app shell")
            }
        }
        // SPEC 18.6: reconcile platform alarms with the accepted set (cancel
        // removed, arm new/changed non-fired).
        engine.reminderListener = { owner, newSet, priorSet ->
            Notifications.scheduleReminders(appContext, owner, newSet, priorSet)
        }
        engine.dialogListener = { id, spec -> onDialogChanged(id, spec) }
        // SPEC 19.4 (T2/LD-5): every inbound edit.apply republishes the
        // shadow, so the on-screen text follows it — before this, s.shadow
        // moved and the display did not, and the next keystroke diffed
        // against a stale base. Fires under the engine monitor.
        engine.editorListener = { s -> publishMirror(s) }
        // SPEC 18.1: an oversized submit keeps the dialog up; tell the user to
        // shorten the input (password erasure in the renderer is a follow-on).
        engine.dialogOverflowListener = { onToast("Input too large — please shorten it") }
        engine.toastListener = { text, _ -> onToast(text) }
        // SPEC 18.4: persist the accepted theme and mirror it. currentTheme()
        // is the normalized `{dark, colors, syntax}` payload after the merge.
        engine.themeListener = { _, _, _ ->
            val payload = engine.currentTheme()
            saveTheme(payload)
            onTheme(payload)
        }
        engine.pieMenuListener = { id, spec -> onPieMenuChanged(id, spec) }
        try {
            // INSIDE the try: SPEC 5.2's newest-wins supersession closes this
            // socket from the accept loop the instant a newcomer arrives, and
            // that can land before this thread ever reaches getInputStream().
            // Outside the try it threw SocketException("Socket is closed") out
            // of the thread and killed the process — which is what a retrying
            // `jetpacs-start' produced every time, since its second dial
            // superseded the first mid-setup.
            val input = socket.getInputStream()
            val buffer = ByteArray(8192)
            while (engine.state != SessionState.CLOSED) {
                val n = input.read(buffer)
                if (n < 0) break
                engine.feed(buffer.copyOf(n))
            }
        } catch (_: Exception) {
            // transport loss: SPEC 10.1, any state may close
        } finally {
            // SPEC 15.3: the engine releases its in-flight marker so the
            // next session's replay is never wedged (review P0). LD-18:
            // best-effort — a throw here must not skip clearLiveSession and
            // socket.close(), which would leak the FD and park a dead engine.
            runCatching { engine.close("transport closed") }
            // SPEC 19: transport loss closes every editor session, so no
            // mirror outlives the connection that produced it (also keeps
            // the map bounded — entries are per (document, editor_id)).
            _editorMirrors.value = emptyMap()
            // Atomic compare-and-clear: only if a newer connection has not
            // already superseded this one in the slot (SPEC 5.2 newest-wins).
            CompanionStores.clearLiveSession(engine)
            socket.runCatching { close() }
        }
    }
}
