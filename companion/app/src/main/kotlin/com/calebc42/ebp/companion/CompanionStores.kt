// SPDX-License-Identifier: GPL-3.0-or-later
// Process-wide durable stores. This object is the ONLY constructor of the
// file-backed instances, so DeviceBridge and any cold-started manifest
// receiver (alarm, boot, tap) share one in-memory instance per file — two
// instances over one backing file would tear each other's snapshots. All
// accessors are lazy and idempotent; Context is only used for filesDir.
package com.calebc42.ebp.companion

import android.content.Context
import android.provider.Settings
import com.calebc42.ebp.wire.DurableQueue
import com.calebc42.ebp.wire.FileQueueStore
import com.calebc42.ebp.wire.FileReminderBacking
import com.calebc42.ebp.wire.FileSurfaceBacking
import com.calebc42.ebp.wire.FileTriggerBacking
import com.calebc42.ebp.wire.LiveSession
import com.calebc42.ebp.wire.ReminderStore
import com.calebc42.ebp.wire.SurfaceStore
import com.calebc42.ebp.wire.TriggerFiringService
import com.calebc42.ebp.wire.TriggerStore
import com.calebc42.ebp.wire.jsonStringSet
import java.io.File

object CompanionStores {

    @Volatile private var queueInstance: DurableQueue? = null
    @Volatile private var surfacesInstance: SurfaceStore? = null
    @Volatile private var remindersInstance: ReminderStore? = null
    @Volatile private var triggersInstance: TriggerStore? = null
    @Volatile private var firingInstance: TriggerFiringService? = null
    @Volatile private var sourcesInstance: TriggerSources? = null

    private val liveSessionRef = java.util.concurrent.atomic.AtomicReference<LiveSession?>()

    /** The current live engine, or null when disconnected. A cold receiver
     * (reminder tap/alarm) routes queue/wake events durably regardless and a
     * drop live only through this slot (SPEC 15.1). Newest-wins (SPEC 5.2). */
    val liveSession: LiveSession? get() = liveSessionRef.get()

    /** SPEC 5.2: a connection publishes itself as the live session. */
    fun setLiveSession(s: LiveSession) { liveSessionRef.set(s) }

    /** Clear only if still this exact session — a superseded connection's
     * teardown must not null out the newer session (the lost-update race).
     * Returns whether THIS call cleared it: the same verdict gates the
     * teardown's wipe of the shared display maps (R5 review). */
    fun clearLiveSession(s: LiveSession): Boolean =
        liveSessionRef.compareAndSet(s, null)

    const val MAX_EVENT_BYTES = 262_144L
    // SPEC 14.1: matches DeviceBridge's advertised max_field_bytes.
    const val MAX_FIELD_BYTES = 65_536L

    /** SPEC 21.2: every firing + cold-event route runs on this single background
     * thread, NEVER the Android main thread — an admitted occurrence may deliver
     * live (a loopback socket write, which throws NetworkOnMainThreadException on
     * the main thread) and persists records / runs on_fire (file + platform I/O).
     * A single thread also serializes all firing behind one writer. */
    val firingExecutor: java.util.concurrent.ExecutorService by lazy {
        java.util.concurrent.Executors.newSingleThreadExecutor { r ->
            Thread(r, "ebp-firing").apply { isDaemon = true }
        }
    }

    /** SPEC 15: the durable queue survives process and device restarts. */
    fun queue(ctx: Context): DurableQueue =
        queueInstance ?: synchronized(this) {
            queueInstance ?: DurableQueue(
                FileQueueStore(File(ctx.filesDir, "ebp-queue.json")),
                256, 8_388_608).also { queueInstance = it }
        }

    /** SPEC 13.1/15.1: surface histories + tombstones + drafts survive. */
    fun surfaces(ctx: Context): SurfaceStore =
        surfacesInstance ?: synchronized(this) {
            surfacesInstance ?: SurfaceStore(64, 4096,
                maxCaptureFields = 64,
                // SPEC 4.5/17.5: enforced at validation when chart/canvas are
                // advertised — must match DeviceBridge's advertised limits.
                maxChartPoints = 4096, maxCanvasOps = 4096,
                // SPEC 17.1: gate each target to exactly what it advertises, so
                // an app-only type in a dialog/notification degrades (§16.2).
                appNodeTypes = com.calebc42.ebp.companion.render.NodeSupport.APP_NODE_TYPES,
                notificationNodeTypes =
                    com.calebc42.ebp.companion.render.NodeSupport.NOTIFICATION_NODE_TYPES,
                backing = FileSurfaceBacking(File(ctx.filesDir, "ebp-surfaces.json"))
            ).also { surfacesInstance = it }
        }

    /** SPEC 18.6: reminder sets + fired receipts survive. */
    fun reminders(ctx: Context): ReminderStore =
        remindersInstance ?: synchronized(this) {
            remindersInstance ?: ReminderStore(
                FileReminderBacking(File(ctx.filesDir, "ebp-reminders.json"))
            ).also { remindersInstance = it }
        }

    /** SPEC 21.1: trigger registrations + runtime records survive. */
    fun triggers(ctx: Context): TriggerStore =
        triggersInstance ?: synchronized(this) {
            triggersInstance ?: TriggerStore(
                FileTriggerBacking(File(ctx.filesDir, "ebp-triggers.json"))
            ).also { triggersInstance = it }
        }

    /** SPEC 21: the device-lifetime firing service over the durable stores.
     * Fires regardless of a live socket; a live engine attaches as its
     * LiveSession. Wired with the platform state provider + on_fire executors. */
    fun firing(ctx: Context): TriggerFiringService {
        firingInstance?.let { return it }
        val app = ctx.applicationContext
        return synchronized(this) {
            firingInstance ?: TriggerFiringService(
                triggers(app), queue(app), MAX_EVENT_BYTES,
                triggerCaps = jsonStringSet(AppCapabilities.deviceReport(), "trigger_caps"),
                capabilityHandler = AppCapabilities.handler(app, 65_536),
                bootGeneration = { bootGeneration(app) },
            ).also { svc ->
                svc.stateProvider = { type -> triggerSources(app).currentState(type) }
                svc.notifyListener = { notify -> Notifications.postTrigger(app, notify) }
                // SPEC 21.5: a triggers.set that changed time.* entries re-arms
                // the platform alarms for the new schedule.
                svc.onTimeScheduleChanged = { TriggerAlarms.reschedule(app) }
                firingInstance = svc
            }
        }
    }

    /** SPEC 21.5: the current device boot generation. Settings.Global.BOOT_COUNT
     * increments once per boot; a `boot` trigger fires at most once per value.
     * Null (unavailable) leaves boot ungated — the receiver is the sole guard. */
    private fun bootGeneration(ctx: Context): String? = runCatching {
        Settings.Global.getString(ctx.contentResolver, Settings.Global.BOOT_COUNT)
    }.getOrNull()

    /** SPEC 21: platform trigger sources, feeding the firing service (which the
     * lambda resolves lazily, breaking the source<->service cycle). */
    fun triggerSources(ctx: Context): TriggerSources {
        sourcesInstance?.let { return it }
        val app = ctx.applicationContext
        return synchronized(this) {
            sourcesInstance ?: TriggerSources(app) { type, sample ->
                // SPEC 21.2: never fire on the main thread (the battery receiver's
                // onReceive) — a live delivery would socket-write there.
                firingExecutor.execute { firing(app).observeSample(type, sample) }
            }.also { sourcesInstance = it }
        }
    }
}
