// SPDX-License-Identifier: GPL-3.0-or-later
// Platform presentation for SPEC 18.5 notification surfaces and SPEC 18.6
// reminders: one notification channel, a poster, and the alarm receiver that
// fires a reminder at its at_ms. This W7 slice presents; routing a
// notification/reminder tap back to Emacs with its offline policy is the
// deeper integration (the shared ReminderStore/queue must outlive a
// connection) noted for a follow-on.
package com.calebc42.ebp.companion

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

object Notifications {
    const val CHANNEL = "ebp"

    fun ensureChannel(ctx: Context) {
        val mgr = ctx.getSystemService(NotificationManager::class.java)
        if (mgr.getNotificationChannel(CHANNEL) == null)
            mgr.createNotificationChannel(NotificationChannel(
                CHANNEL, "EBP", NotificationManager.IMPORTANCE_HIGH))
    }

    fun post(ctx: Context, tag: String, id: Int, title: String, body: String?,
             ongoing: Boolean = false) {
        ensureChannel(ctx)
        val n = Notification.Builder(ctx, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .also { if (!body.isNullOrEmpty()) it.setContentText(body) }
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(tag, id, n)
    }

    /** SPEC 18.6: arm one exact alarm per reminder; the payload rides the
     * intent so the receiver can present without a live connection. */
    private fun alarmReqCode(owner: String, id: String) = "$owner $id".hashCode()

    /**
     * SPEC 18.6: reconcile the owner's platform alarms with the new set —
     * CANCEL alarms for removed ids, and (re)arm only tuples that have not
     * already fired. Skipping fired tuples (with the receiver's own fired-state
     * gate) is what stops a re-push of an unchanged, already-past reminder from
     * re-firing. The payload rides the intent so the receiver can present with
     * no live connection.
     */
    fun scheduleReminders(ctx: Context, owner: String, newSet: JSONArray, priorSet: JSONArray) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val store = CompanionStores.reminders(ctx)
        val newIds = (0 until newSet.length())
            .map { newSet.getJSONObject(it).getString("id") }.toSet()
        for (i in 0 until priorSet.length()) {
            val id = priorSet.getJSONObject(i).getString("id")
            if (id in newIds) continue
            PendingIntent.getBroadcast(ctx, alarmReqCode(owner, id),
                Intent(ctx, ReminderAlarmReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
                ?.let { am.cancel(it); it.cancel() }
        }
        for (i in 0 until newSet.length()) {
            val r = newSet.getJSONObject(i)
            val id = r.getString("id")
            if (store.isFired(owner, id)) continue // already presented — do not re-arm
            val intent = Intent(ctx, ReminderAlarmReceiver::class.java)
                .putExtra("owner", owner).putExtra("rid", id)
                .putExtra("title", r.getString("title"))
                .putExtra("body", r.optString("body", ""))
            val pi = PendingIntent.getBroadcast(ctx, alarmReqCode(owner, id), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, r.getLong("at_ms"), pi)
        }
    }

    /** SPEC 18.6: re-arm every owner's unfired reminders from the durable store.
     * AlarmManager loses alarms across a reboot or a force-stop, so a cold start
     * (and a wall-clock change) must re-establish them. Arm-only (prior empty):
     * nothing is cancelled, and already-fired tuples stay skipped, so this never
     * re-presents a past reminder. */
    fun rearmAllReminders(ctx: Context) {
        val store = CompanionStores.reminders(ctx)
        for (owner in store.owners())
            scheduleReminders(ctx, owner, JSONArray(store.reminders(owner)), JSONArray())
    }

    /** SPEC 18.6: present a reminder with a tap route into the Section 14
     * pipeline via ReminderTapReceiver (works whether or not a session is up). */
    fun postReminder(ctx: Context, owner: String, rid: String, title: String, body: String?) {
        ensureChannel(ctx)
        val tap = Intent(ctx, ReminderTapReceiver::class.java)
            .putExtra("owner", owner).putExtra("rid", rid)
        val contentIntent = PendingIntent.getBroadcast(ctx, "tap $owner $rid".hashCode(),
            tap, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(ctx, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .also { if (!body.isNullOrEmpty()) it.setContentText(body) }
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify("reminder", rid.hashCode(), n)
    }

    /** Present a notification:* surface (SPEC 18.5) — this slice renders the
     * body's text and the meta's ongoing flag; actions with their tap routing
     * are the follow-on integration. */
    fun postSurface(ctx: Context, surface: String, spec: JSONObject) {
        val body = spec.optJSONObject("body")
        val meta = spec.optJSONObject("meta")
        val text = body?.let { collectText(it) } ?: ""
        post(ctx, surface, surface.hashCode(),
            title = surface.substringAfter(':'),
            body = text,
            ongoing = meta?.optBoolean("ongoing") == true)
    }

    fun cancelSurface(ctx: Context, surface: String) {
        ctx.getSystemService(NotificationManager::class.java)
            .cancel(surface, surface.hashCode())
    }

    /** SPEC 21.4: present a trigger on_fire {title?, text} notification. With
     * no title the text becomes the title, matching a simple local alert. */
    fun postTrigger(ctx: Context, notify: JSONObject) {
        val text = notify.optString("text", "")
        val title = notify.optString("title", "").ifEmpty { text }
        val body = if (title == text) null else text
        post(ctx, "trigger", (title + body).hashCode(), title, body)
    }

    private fun collectText(node: JSONObject): String {
        if (node.optString("t") == "text") return node.optString("text")
        val out = StringBuilder()
        node.optJSONArray("children")?.let { kids ->
            for (i in 0 until kids.length()) {
                (kids.opt(i) as? JSONObject)?.let {
                    if (out.isNotEmpty()) out.append('\n')
                    out.append(collectText(it))
                }
            }
        }
        return out.toString()
    }
}

class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val owner = intent.getStringExtra("owner") ?: return
        val title = intent.getStringExtra("title") ?: return
        val rid = intent.getStringExtra("rid") ?: return
        val body = intent.getStringExtra("body")
        val app = ctx.applicationContext
        // SPEC 18.6: markFired persists (file I/O) — off the main thread.
        val pending = goAsync()
        CompanionStores.firingExecutor.execute {
            try {
                // Commit the fired receipt durably BEFORE presenting, so a restart
                // or a re-armed/re-pushed tuple never re-presents. markFired
                // returns false if already fired or the receipt could not be
                // committed — either way, do not present.
                if (CompanionStores.reminders(app).markFired(owner, rid))
                    Notifications.postReminder(app, owner, rid, title, body)
            } finally { pending.finish() }
        }
    }
}

/** SPEC 18.6: a reminder tap enters the Section 14 pipeline with the authored
 * offline policy. Works cold (no live engine): queue/wake taps admit to the
 * shared durable queue and replay on the next connect; a drop delivers live
 * only through the current session. */
class ReminderTapReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val owner = intent.getStringExtra("owner") ?: return
        val rid = intent.getStringExtra("rid") ?: return
        val app = ctx.applicationContext
        // SPEC 14/18.6: the tap admits to the durable queue (file I/O) and may
        // deliver live (socket write) — off the main thread.
        val pending = goAsync()
        CompanionStores.firingExecutor.execute {
            try {
                com.calebc42.ebp.wire.routeReminderTap(
                    CompanionStores.reminders(app), CompanionStores.queue(app),
                    CompanionStores.MAX_EVENT_BYTES, owner, rid, CompanionStores.liveSession)
                app.getSystemService(NotificationManager::class.java)
                    .cancel("reminder", rid.hashCode())
            } finally { pending.finish() }
        }
    }
}
