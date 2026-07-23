// SPDX-License-Identifier: GPL-3.0-or-later
// Process-lifetime bootstrap (SPEC 21). The firing service, trigger sources,
// and durable recovery come up on process start regardless of MainActivity —
// so triggers fire, throttle survives, and pending-local occurrences resolve
// even when the companion UI was never opened (a cold start from an alarm or a
// boot receiver).
package com.calebc42.ebp.companion

import android.app.Application

class EbpApplication : Application() {
    override fun onCreate() {
        super.onCreate()
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
