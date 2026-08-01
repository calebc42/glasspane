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
import com.calebc42.ebp.companion.render.arrOrNull
import com.calebc42.ebp.companion.render.longByValue
import com.calebc42.ebp.wire.CapabilityHandler
import com.calebc42.ebp.wire.CapabilityOutcome
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * The caps this build actually executes on Android. Every entry is in
 * CapabilityCatalog.VALIDATED, so the wire library validates its Args before
 * this handler ever runs. `vibrate` needs no runtime consent; `clipboard.read`
 * works while the Companion UI holds focus.
 */
object AppCapabilities {

    private val CAPS = listOf("vibrate", "clipboard.read")
    // SPEC 21/20.1: advertise ONLY what a source actually feeds. battery.level
    // (TriggerSources) plus the W8-e scheduled/external sources: boot and
    // timezone.changed (BootReceiver) and time (TriggerAlarms + TimeAlarmReceiver).
    // screen/power/etc. attach the same way and get advertised as they land.
    // trigger_caps is the unattended subset runnable inside on_fire.
    private val TRIGGER_TYPES = listOf("battery.level", "boot", "time", "timezone.changed")
    private val STATE_TYPES = listOf("battery.level")

    /** SPEC 20.1: the device report echoed in the welcome (capabilities and
     * triggers share one report). Every advertised entry stays a JSON STRING:
     * the engine gates a cap with `caps.none { it.asStringOrNull() == cap }`
     * and jsonStringSet() drops non-strings outright. The serialized size is
     * budget-checked (CompanionEngine max device_report bytes), so this builder
     * carries exactly these seven members — no more. */
    fun deviceReport(): JsonObject = buildJsonObject {
        put("caps", JsonArray(CAPS.map(::JsonPrimitive)))
        put("trigger_caps", JsonArray(listOf(JsonPrimitive("vibrate"))))
        put("permissions", JsonObject(emptyMap()))
        // SPEC 20.1: REQUIRED once triggers is granted.
        put("trigger_types", JsonArray(TRIGGER_TYPES.map(::JsonPrimitive)))
        put("state_types", JsonArray(STATE_TYPES.map(::JsonPrimitive)))
        put("trackable_state_types", JsonArray(STATE_TYPES.map(::JsonPrimitive)))
        put("trigger_unavailable", JsonObject(emptyMap()))
    }

    /**
     * SPEC 20.2: the executor. `maxFieldBytes` bounds clipboard text per the
     * catalog. Runs on the ebp-dispatch thread, never the socket reader.
     */
    fun handler(context: Context, maxFieldBytes: Int) = CapabilityHandler { cap, args ->
        try {
            when (cap) {
                "vibrate" -> { vibrate(context, args); CapabilityOutcome.Ok(JsonObject(emptyMap())) }
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
    private fun vibrate(context: Context, args: JsonObject) {
        val vibrator = (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                as VibratorManager).defaultVibrator
        // C6: `ms` and EVERY `pattern` element are read BY VALUE. The engine
        // hands this handler the original, un-normalized args; CapabilityCatalog
        // normalizes only for validation, and it does so with integralLongOrNull
        // — so an older peer's {"ms": 100.0} (or "pattern": [100.0, 200.0]) is
        // accepted, working traffic that org.json's getLong simply truncated. A
        // strict reader would yield nothing here, the blanket catch above would
        // turn that into a plausible-looking 1003 "platform-error", and the
        // device would stop buzzing with no other symptom.
        if ("ms" in args) {
            vibrator.vibrate(VibrationEffect.createOneShot(
                longByValue(args["ms"]) ?: return, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            val arr = args.arrOrNull("pattern") ?: return
            val pattern = arr.map { longByValue(it) ?: return }.toLongArray()
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
        return CapabilityOutcome.Ok(buildJsonObject { put("text", text) })
    }
}
