// SPDX-License-Identifier: GPL-3.0-or-later
// The device-capability module (SPEC 20), Android host half. This is the
// CapabilityHandler the wire library delegates to after it has validated the
// closed Args: it performs the bounded platform operation and returns the
// exact catalog Result, or a typed refusal. The wire library owns the
// contract; this file owns only the platform touch.
package com.calebc42.ebp.companion

import android.content.ClipboardManager
import android.content.Context
import android.os.VibrationEffect
import android.os.VibratorManager
import com.calebc42.ebp.wire.CapabilityHandler
import com.calebc42.ebp.wire.CapabilityOutcome
import org.json.JSONArray
import org.json.JSONObject

/**
 * The caps this build actually executes on Android. Every entry is in
 * CapabilityCatalog.VALIDATED, so the wire library validates its Args before
 * this handler ever runs. `vibrate` needs no runtime consent; `clipboard.read`
 * works while the Companion UI holds focus.
 */
object AppCapabilities {

    private val CAPS = listOf("vibrate", "clipboard.read")

    /** SPEC 20.1: the device report echoed in the welcome. */
    fun deviceReport(): JSONObject = JSONObject()
        .put("caps", JSONArray(CAPS))
        .put("trigger_caps", JSONArray()) // no trigger module yet
        .put("permissions", JSONObject())

    /**
     * SPEC 20.2: the executor. `maxFieldBytes` bounds clipboard text per the
     * catalog. Runs on the ebp-dispatch thread, never the socket reader.
     */
    fun handler(context: Context, maxFieldBytes: Int) = CapabilityHandler { cap, args ->
        try {
            when (cap) {
                "vibrate" -> { vibrate(context, args); CapabilityOutcome.Ok(JSONObject()) }
                "clipboard.read" -> readClipboard(context, maxFieldBytes)
                else -> CapabilityOutcome.Fail(1003, "unimplemented")
            }
        } catch (e: SecurityException) {
            CapabilityOutcome.Fail(1002, "permission-denied")
        } catch (e: Exception) {
            CapabilityOutcome.Fail(1003, "platform-error")
        }
    }

    // minSdk 34: VibratorManager is always present.
    private fun vibrate(context: Context, args: JSONObject) {
        val vibrator = (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                as VibratorManager).defaultVibrator
        if (args.has("ms")) {
            vibrator.vibrate(VibrationEffect.createOneShot(
                args.getLong("ms"), VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            val arr = args.getJSONArray("pattern")
            val pattern = LongArray(arr.length()) { arr.getLong(it) }
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        }
    }

    private fun readClipboard(context: Context, maxFieldBytes: Int): CapabilityOutcome {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = cm.primaryClip
        val text = if (clip != null && clip.itemCount > 0)
            clip.getItemAt(0).coerceToText(context).toString() else ""
        // SPEC 20.3: the encoded text MUST NOT exceed max_field_bytes and MUST
        // NOT be truncated — an oversize clip is a typed failure.
        if (text.toByteArray(Charsets.UTF_8).size > maxFieldBytes)
            return CapabilityOutcome.Fail(1003, "clipboard-too-large")
        return CapabilityOutcome.Ok(JSONObject().put("text", text))
    }
}
