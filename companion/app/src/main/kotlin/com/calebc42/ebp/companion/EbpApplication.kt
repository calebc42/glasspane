// SPDX-License-Identifier: GPL-3.0-or-later
// Process-lifetime bootstrap (SPEC 21). The firing service, trigger sources,
// and durable recovery come up on process start regardless of MainActivity —
// so triggers fire, throttle survives, and pending-local occurrences resolve
// even when the companion UI was never opened (a cold start from an alarm or a
// boot receiver).
package com.calebc42.ebp.companion

import android.app.ActivityManager
import android.app.Application
import android.content.Context

class EbpApplication : Application() {
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
    }
}
