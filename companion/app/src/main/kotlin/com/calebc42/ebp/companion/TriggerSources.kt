// SPDX-License-Identifier: GPL-3.0-or-later
// Android trigger sources (SPEC 21), host half. Each source watches a platform
// signal and feeds observations into the firing runtime, and keeps the latest
// sample so the runtime can evaluate state gates. This slice wires
// battery.level (a sticky broadcast, so registering seeds the baseline
// immediately); screen/power/etc. attach identically — register a receiver,
// update `current`, and forward the sample. The runtime decides admission.
package com.calebc42.ebp.companion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

class TriggerSources(
    private val context: Context,
    /** Forward a level-type sample to the live engine's runtime. */
    private val onSample: (String, JSONObject) -> Unit,
) {
    private val current = ConcurrentHashMap<String, JSONObject>()

    /** SPEC 21.3/21.7: the latest sample for a state type, for gate evaluation. */
    fun currentState(type: String): JSONObject? = current[type]

    private val battery = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
            if (level < 0 || scale <= 0) return
            val sample = JSONObject().put("level", level * 100 / scale)
            current["battery.level"] = sample
            onSample("battery.level", sample)
        }
    }

    fun start() {
        // ACTION_BATTERY_CHANGED is sticky: registering delivers the current
        // level at once, so the baseline is set before any triggers.set.
        context.registerReceiver(battery, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    }

    fun stop() {
        runCatching { context.unregisterReceiver(battery) }
    }
}
