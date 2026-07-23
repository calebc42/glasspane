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
import com.calebc42.ebp.wire.ReminderStore
import com.calebc42.ebp.wire.SurfaceStore
import java.io.File

object CompanionStores {

    @Volatile private var queueInstance: DurableQueue? = null
    @Volatile private var surfacesInstance: SurfaceStore? = null
    @Volatile private var remindersInstance: ReminderStore? = null

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
}
