// SPDX-License-Identifier: GPL-3.0-or-later
// Durable backing for SPEC 21 trigger registrations. Persists each identity's
// normalized entries AND the runtime records SPEC 21.2 requires survive a
// restart (throttle floor, one-shot completed marker, boot generation
// receipt, repeating schedule anchor / last-fire floor). Silent baselines and
// edge levels are DELIBERATELY NOT persisted: SPEC 21.5 requires them to be
// re-established silently from the CURRENT state after a restart, so a change
// that happened while the process was dead must not fire. Same atomic
// whole-snapshot replace shape as QueueStore/ReminderBacking.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

data class PersistedRegistration(
    val entry: JSONObject,
    val throttleFloorMs: Long?,
    val oneShotCompleted: Boolean,
    val scheduleAnchorMs: Long?,
    val lastFireFloorMs: Long?,
    val bootGeneration: String?,
)

/** identity -> its ordered registrations. */
data class TriggerState(val identities: Map<String, List<PersistedRegistration>>)

interface TriggerBacking {
    fun load(): TriggerState
    /** Atomically and durably replace the whole state; throws on failure. */
    fun replace(state: TriggerState)
}

class MemoryTriggerBacking : TriggerBacking {
    private var state = TriggerState(emptyMap())
    override fun load(): TriggerState = state
    override fun replace(state: TriggerState) { this.state = state }
}

class FileTriggerBacking(private val file: File) : TriggerBacking {

    override fun load(): TriggerState {
        if (!file.exists()) return TriggerState(emptyMap())
        val text = file.readText(Charsets.UTF_8)
        if (text.isBlank()) return TriggerState(emptyMap())
        val root = JSONObject(text)
        val idsJson = root.getJSONObject("identities")
        val identities = LinkedHashMap<String, List<PersistedRegistration>>()
        for (identity in idsJson.keySet()) {
            val arr = idsJson.getJSONArray(identity)
            identities[identity] = (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                PersistedRegistration(
                    entry = o.getJSONObject("entry"),
                    throttleFloorMs = o.optLongOrNull("throttle_floor_ms"),
                    oneShotCompleted = o.optBoolean("one_shot_completed"),
                    scheduleAnchorMs = o.optLongOrNull("schedule_anchor_ms"),
                    lastFireFloorMs = o.optLongOrNull("last_fire_floor_ms"),
                    bootGeneration = if (o.has("boot_generation")) o.getString("boot_generation") else null,
                )
            }
        }
        return TriggerState(identities)
    }

    override fun replace(state: TriggerState) {
        val idsJson = JSONObject()
        for ((identity, regs) in state.identities) {
            val arr = JSONArray()
            for (r in regs) {
                val o = JSONObject()
                    .put("entry", r.entry)
                    .put("one_shot_completed", r.oneShotCompleted)
                r.throttleFloorMs?.let { o.put("throttle_floor_ms", it) }
                r.scheduleAnchorMs?.let { o.put("schedule_anchor_ms", it) }
                r.lastFireFloorMs?.let { o.put("last_fire_floor_ms", it) }
                r.bootGeneration?.let { o.put("boot_generation", it) }
                arr.put(o)
            }
            idsJson.put(identity, arr)
        }
        val root = JSONObject().put("identities", idsJson)
        val temp = File(file.parentFile, file.name + ".tmp")
        FileOutputStream(temp).use { out ->
            out.write(root.toString().toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        if (!temp.renameTo(file)) {
            temp.delete()
            throw java.io.IOException("atomic replace failed for $file")
        }
        runCatching {
            java.nio.channels.FileChannel.open(
                file.parentFile.toPath(),
                java.nio.file.StandardOpenOption.READ).use { it.force(true) }
        }
    }
}

private fun JSONObject.optLongOrNull(key: String): Long? =
    if (has(key)) getLong(key) else null
