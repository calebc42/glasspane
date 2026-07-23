// SPDX-License-Identifier: GPL-3.0-or-later
// Process-wide durable stores. This object is the ONLY constructor of the
// file-backed instances, so DeviceBridge and any cold-started manifest
// receiver (alarm, boot, tap) share one in-memory instance per file — two
// instances over one backing file would tear each other's snapshots. All
// accessors are lazy and idempotent; Context is only used for filesDir.
package com.calebc42.ebp.companion

import android.content.Context
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

    /** The current live engine, or null when disconnected. A cold receiver
     * (reminder tap/alarm) routes queue/wake events durably regardless and a
     * drop live only through this slot (SPEC 15.1). Newest-wins (SPEC 5.2). */
    @Volatile var liveSession: LiveSession? = null

    const val MAX_EVENT_BYTES = 262_144L

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
            ).also { svc ->
                svc.stateProvider = { type -> triggerSources(app).currentState(type) }
                svc.notifyListener = { notify -> Notifications.postTrigger(app, notify) }
                firingInstance = svc
            }
        }
    }

    /** SPEC 21: platform trigger sources, feeding the firing service (which the
     * lambda resolves lazily, breaking the source<->service cycle). */
    fun triggerSources(ctx: Context): TriggerSources {
        sourcesInstance?.let { return it }
        val app = ctx.applicationContext
        return synchronized(this) {
            sourcesInstance ?: TriggerSources(app) { type, sample ->
                firing(app).observeSample(type, sample)
            }.also { sourcesInstance = it }
        }
    }
}
