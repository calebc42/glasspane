package com.example.glasspane

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import java.net.HttpURLConnection
import java.net.URL

class ClockReceiver : BroadcastReceiver() {
    companion object {
        private const val CHANNEL_ID = "chrono_server_tasks"
        private const val NOTIF_ID = 42
    }

    override fun onReceive(context: Context, intent: Intent) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val action = intent.action
        Log.d("ClockReceiver", "Action received: $action")

        when (action) {
            "com.example.glasspane.CLOCK_IN" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        CHANNEL_ID, "Server Tasks", NotificationManager.IMPORTANCE_LOW
                    )
                    manager.createNotificationChannel(channel)
                }

                val title = intent.getStringExtra("title") ?: "Server Task"
                val text = intent.getStringExtra("text") ?: "Active..."
                val baseTime = intent.getLongExtra("base_time", System.currentTimeMillis())

                val stopIntent = Intent(context, ClockReceiver::class.java).apply {
                    this.action = "com.example.glasspane.HTTP_CLOCK_OUT"
                }
                val stopPendingIntent = PendingIntent.getBroadcast(
                    context, 0, stopIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    android.app.Notification.Builder(context, CHANNEL_ID)
                } else {
                    @Suppress("DEPRECATION")
                    android.app.Notification.Builder(context)
                }

                builder.setContentTitle(title)
                    .setContentText(text)
                    .setSmallIcon(android.R.drawable.ic_media_play)
                    .setUsesChronometer(true)
                    .setWhen(baseTime)
                    .setOngoing(true)
                    .addAction(android.R.drawable.ic_media_pause, "Stop & Log", stopPendingIntent)

                manager.notify(NOTIF_ID, builder.build())
            }

            "com.example.glasspane.CLOCK_OUT" -> {
                manager.cancel(NOTIF_ID)
            }

            "com.example.glasspane.HTTP_CLOCK_OUT" -> {
                // Use goAsync() so the process is kept alive until the HTTP call completes.
                // GlobalScope is unsafe here because Android may kill the process before
                // the coroutine finishes, silently dropping the clock-out request.
                val pendingResult = goAsync()
                val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
                scope.launch {
                    try {
                        val conn = URL("http://127.0.0.1:8080/glasspane-clock-out")
                            .openConnection() as HttpURLConnection
                        conn.requestMethod = "POST"
                        conn.connectTimeout = 5_000
                        conn.readTimeout = 5_000
                        val code = conn.responseCode
                        Log.d("ClockReceiver", "Clock-out response: $code")
                    } catch (e: Exception) {
                        Log.e("ClockReceiver", "Failed to reach Emacs to clock out", e)
                    } finally {
                        // Always release the wake lock — even on failure.
                        pendingResult.finish()
                    }
                }
            }
        }
    }
}