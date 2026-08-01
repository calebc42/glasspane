// SPDX-License-Identifier: GPL-3.0-or-later
// Platform scheduling for SPEC 21.5 time/boot triggers. AlarmManager loses all
// alarms across a device reboot or an app force-stop, and the wall clock can be
// moved, so time triggers are (re)armed from the firing service's schedule at
// every relevant moment: a triggers.set that changed them, a fire that advanced
// a repeat, process start (EbpApplication), reboot, and a time/timezone change.
// Boot triggers fire from BootReceiver once per boot generation (SPEC 21.5).
package com.calebc42.ebp.companion

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

object TriggerAlarms {

    private fun reqCode(identity: String, triggerId: String) =
        "time $identity $triggerId".hashCode()

    /**
     * SPEC 21.5: arm one exact alarm per time.* registration at its next due
     * wall-clock ms (timeSchedule() already drops a completed one-shot and
     * coalesces a repeat's missed intervals into one past-due occurrence, which
     * AlarmManager fires immediately). Idempotent: a stable per-trigger request
     * code with FLAG_UPDATE_CURRENT replaces an entry's prior alarm, so a
     * changed cadence re-arms cleanly. A fully removed trigger's stale alarm is
     * left to fire once — fireScheduled is a no-op for an absent registration,
     * and it is not re-armed, so it self-heals after one harmless wake.
     */
    fun reschedule(ctx: Context) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        for (alarm in CompanionStores.firing(ctx).timeSchedule()) {
            val intent = Intent(ctx, TimeAlarmReceiver::class.java)
                .putExtra("identity", alarm.identity).putExtra("tid", alarm.triggerId)
            val pi = PendingIntent.getBroadcast(ctx, reqCode(alarm.identity, alarm.triggerId),
                intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, alarm.dueMs, pi)
        }
    }
}

/** SPEC 21.5: a time.* trigger's alarm elapsed — fire exactly that registration
 * (each has its own due time), then re-arm the schedule (a repeat's next
 * occurrence; a fired one-shot drops out). Works cold, with no live session. */
class TimeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val identity = intent.getStringExtra("identity") ?: return
        val tid = intent.getStringExtra("tid") ?: return
        val app = ctx.applicationContext
        // SPEC 21.2: firing may deliver live (socket write) — never on the main
        // thread. goAsync keeps the receiver alive across the background hop.
        val pending = goAsync()
        CompanionStores.firingExecutor.execute {
            try {
                CompanionStores.firing(app).fireScheduled(identity, tid)
                TriggerAlarms.reschedule(app)
            } finally { pending.finish() }
        }
    }
}

/**
 * SPEC 21.5: a reboot clears alarms and increments the boot generation; a
 * time/timezone change moves the wall clock. Re-establish reminders + time
 * alarms from the durable stores (idempotent with EbpApplication's own cold-
 * start re-arm), and on boot fire the `boot` triggers once (generation-gated in
 * the runtime), on a timezone change the `timezone.changed` triggers.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val app = ctx.applicationContext
        val action = intent.action
        // SPEC 21.2/18.6: re-arm + fire off the main thread (goAsync keeps the
        // cold-started receiver alive across the background hop).
        val pending = goAsync()
        CompanionStores.firingExecutor.execute {
            try {
                Notifications.rearmAllReminders(app)
                TriggerAlarms.reschedule(app)
                val firing = CompanionStores.firing(app)
                when (action) {
                    Intent.ACTION_BOOT_COMPLETED ->
                        firing.observeExternal("boot", JsonObject(emptyMap()))
                    // SPEC 21.5 fire-data: timezone.changed carries the new tz.
                    Intent.ACTION_TIMEZONE_CHANGED -> firing.observeExternal(
                        "timezone.changed",
                        buildJsonObject { put("tz", java.time.ZoneId.systemDefault().id) })
                }
            } finally { pending.finish() }
        }
    }
}
