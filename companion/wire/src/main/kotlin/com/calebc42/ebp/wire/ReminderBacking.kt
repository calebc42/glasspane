// SPDX-License-Identifier: GPL-3.0-or-later
// Durable backing for SPEC 18.6 reminders. The accepted per-owner sets and
// the fired receipts MUST both survive process and device restarts ("persist
// the accepted set across process and device restarts"; "persist fired state
// before or atomically with presentation so a restart does not deliberately
// re-fire it"). Every mutation is one atomic whole-snapshot replace, the
// same shape as QueueStore/SurfaceBacking.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/** One durable state: owner -> ordered reminder list, plus the fired
 * receipts keyed "owner id at_ms" (the SPEC 18.6 at-most-once tuple). */
data class ReminderState(
    val owners: Map<String, List<JSONObject>>,
    val fired: Set<String>,
)

interface ReminderBacking {
    fun load(): ReminderState
    /** Atomically and durably replace the whole state; throws on failure. */
    fun replace(state: ReminderState)
}

class MemoryReminderBacking : ReminderBacking {
    private var state = ReminderState(emptyMap(), emptySet())
    override fun load(): ReminderState = state
    override fun replace(state: ReminderState) { this.state = state }
}

/**
 * JSON file with write-to-temp, fsync, atomic-rename replacement, so a
 * crash leaves either the old state or the new state, never a torn one.
 */
class FileReminderBacking(private val file: File) : ReminderBacking {

    override fun load(): ReminderState {
        if (!file.exists()) return ReminderState(emptyMap(), emptySet())
        val text = file.readText(Charsets.UTF_8)
        if (text.isBlank()) return ReminderState(emptyMap(), emptySet())
        val root = JSONObject(text)
        val ownersJson = root.getJSONObject("owners")
        val owners = LinkedHashMap<String, List<JSONObject>>()
        for (owner in ownersJson.keySet()) {
            val arr = ownersJson.getJSONArray(owner)
            owners[owner] = (0 until arr.length()).map { arr.getJSONObject(it) }
        }
        val firedArr = root.getJSONArray("fired")
        return ReminderState(
            owners = owners,
            fired = (0 until firedArr.length()).map { firedArr.getString(it) }.toSet(),
        )
    }

    override fun replace(state: ReminderState) {
        val ownersJson = JSONObject()
        for ((owner, list) in state.owners) ownersJson.put(owner, JSONArray(list))
        val root = JSONObject()
            .put("owners", ownersJson)
            .put("fired", JSONArray(state.fired.toList()))
        val temp = File(file.parentFile, file.name + ".tmp")
        FileOutputStream(temp).use { out ->
            out.write(root.toString().toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        if (!temp.renameTo(file)) {
            temp.delete()
            throw java.io.IOException("atomic replace failed for $file")
        }
        // Durability of the rename itself needs a directory fsync on
        // POSIX; best-effort — the JVM cannot demand it portably.
        runCatching {
            java.nio.channels.FileChannel.open(
                file.parentFile.toPath(),
                java.nio.file.StandardOpenOption.READ).use { it.force(true) }
        }
    }
}
