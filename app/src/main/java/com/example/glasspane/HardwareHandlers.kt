package com.example.glasspane

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.widget.Toast
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.net.HttpURLConnection
import java.net.URL
import android.content.BroadcastReceiver
import android.util.Log

object HardwareHandlers {
    private const val CHANNEL_ID = "glasspane_server_tasks"

    fun handleNotification(context: Context, intent: Intent) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Android 8+ requires a channel
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Glasspane Tasks", NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }

        // 1. Parse the Primitives
        val id = intent.getIntExtra("id", 1)
        val title = intent.getStringExtra("title") ?: "Emacs Alert"
        val content = intent.getStringExtra("content") ?: ""
        val ongoing = intent.getBooleanExtra("ongoing", false)
        val useChronometer = intent.getBooleanExtra("chronometer", false)
        val baseTimeMs = intent.getLongExtra("base_time_ms", 0L)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info) // Replace with your app icon later
            .setContentTitle(title)
            .setContentText(content)
            .setOngoing(ongoing)

        if (useChronometer) {
            builder.setUsesChronometer(true)
            if (baseTimeMs > 0) {
                // Android's Notification Builder natively accepts Epoch time
                // and handles the elapsedRealtime translation automatically!
                builder.setWhen(baseTimeMs)
            }
        }

        // 2. Parse the Action Button Primitives
        val btn1Label = intent.getStringExtra("button1_label")
        val btn1Endpoint = intent.getStringExtra("button1_endpoint")

        if (btn1Label != null && btn1Endpoint != null) {
            val actionIntent = Intent(context, GlasspaneApiReceiver::class.java).apply {
                action = "com.example.glasspane.api.EXECUTE_ENDPOINT"
                putExtra("endpoint", btn1Endpoint)
            }

            // FLAG_IMMUTABLE is strictly required on Android 14 (Pixel Fold)
            val pendingIntent = PendingIntent.getBroadcast(
                context, btn1Endpoint.hashCode(), actionIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(android.R.drawable.ic_media_play, btn1Label, pendingIntent)
        }

        manager.notify(id, builder.build())
    }

    fun handleExecuteEndpoint(intent: Intent, pendingResult: BroadcastReceiver.PendingResult) {
        val endpoint = intent.getStringExtra("endpoint") ?: return pendingResult.finish()

        // This is where Glasspane silently tells Emacs what button was pressed
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope.launch {
            try {
                // Hardcoded for local Termux now, move to GlasspaneConfig later!
                val url = URL("http://127.0.0.1:8080$endpoint")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 5000
                conn.responseCode // execute the call
            } catch (e: Exception) {
                Log.e("GlasspaneAPI", "Failed to execute endpoint: $endpoint", e)
            } finally {
                pendingResult.finish() // Always release the wake lock
            }
        }
    }

    fun handleVibrate(context: Context, intent: Intent) {
        val duration = intent.getIntExtra("duration_ms", 500).toLong()

        // 1. Build the high-priority Audio Attributes
        // This is the "magic key" that tells Android 14 to allow background vibration
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_ALARM) // Treat this as a high-priority alarm
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ (API 31+)
            val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            val vibrator = vibratorManager.defaultVibrator

            // Pass the audio attributes into the vibrate call
            vibrator.vibrate(
                VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE),
                audioAttributes
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Android 8+ (API 26+)
            @Suppress("DEPRECATION")
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator

            vibrator.vibrate(
                VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE),
                audioAttributes
            )
        } else {
            // Legacy Android (Pre-Oreo)
            @Suppress("DEPRECATION")
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            vibrator.vibrate(duration)
        }
    }

    fun handleToast(context: Context, intent: Intent) {
        val text = intent.getStringExtra("text") ?: "Emacs says hello"
        Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
    }
}