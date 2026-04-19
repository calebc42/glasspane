package com.example.glasspane

import android.content.BroadcastReceiver
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.util.Log

class GlasspaneApiReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d("GlasspaneAPI", "Received API Action: $action")

        // We use goAsync() so network calls from notification buttons don't get killed
        val pendingResult = goAsync()

        when (action) {
            "com.example.glasspane.api.VIBRATE" -> HardwareHandlers.handleVibrate(context, intent)
            "com.example.glasspane.api.TOAST" -> HardwareHandlers.handleToast(context, intent)

            // 1. Create the notification
            "com.example.glasspane.api.NOTIFICATION" -> {
                HardwareHandlers.handleNotification(context, intent)
                pendingResult.finish()
            }

            // 2. Handle a button click from the notification
            "com.example.glasspane.api.EXECUTE_ENDPOINT" -> {
                HardwareHandlers.handleExecuteEndpoint(intent, pendingResult)
            }

            // 3. Cancel a notification
            "com.example.glasspane.api.CANCEL_NOTIFICATION" -> {
                val id = intent.getIntExtra("id", 0)
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.cancel(id)
                pendingResult.finish()
            }
            else -> {
                Log.w("GlasspaneAPI", "Unknown action: $action")
                pendingResult.finish()
            }
        }
    }
}