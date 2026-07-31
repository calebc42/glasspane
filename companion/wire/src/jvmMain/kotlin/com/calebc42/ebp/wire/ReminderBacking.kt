// SPDX-License-Identifier: GPL-3.0-or-later
// Durable backing for SPEC 18.6 reminders. The accepted per-owner sets and
// the fired receipts MUST both survive process and device restarts ("persist
// the accepted set across process and device restarts"; "persist fired state
// before or atomically with presentation so a restart does not deliberately
// re-fire it"). Every mutation is one atomic whole-snapshot replace, the
// same shape as QueueStore/SurfaceBacking.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import java.io.File
import java.io.FileOutputStream

/** One durable state: owner -> ordered reminder list, plus the fired
 * receipts keyed "owner id at_ms" (the SPEC 18.6 at-most-once tuple). */
data class ReminderState(
    val owners: Map<String, List<JsonObject>>,
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
        // PERSISTED text is read by kotlinx's lenient parser, NEVER by
        // EbpJson.parse: that one is the strict WIRE parser, and its frame
        // rules (SPEC 4.5's 64-container depth cap above all) are not the
        // store's rules — a reminder's `on_tap.args` sits deeper on disk than
        // it did in the frame that delivered it, because the file's own
        // {"owners":{…:[…]}} wrapper adds levels. A strict re-parse would turn
        // a perfectly legal store file into a boot crash-loop. Pinned by
        // PersistenceCompatTest.strictParserRejectsWhatTheStoreMustAccept.
        val root = Json.parseToJsonElement(text).jsonObject
        val ownersJson = root.reqObj("owners")
        val owners = LinkedHashMap<String, List<JsonObject>>()
        for (owner in ownersJson.keys) {
            val arr = ownersJson.reqArr(owner)
            owners[owner] = arr.map { it.jsonObject }
        }
        val firedArr = root.reqArr("fired")
        return ReminderState(
            owners = owners,
            // Receipt keys are JSON strings and nothing else: org.json's
            // getString coerced nothing here either.
            fired = firedArr.map { it.asStringOrNull() ?: throw NoSuchElementException("fired") }
                .toSet(),
        )
    }

    override fun replace(state: ReminderState) {
        val root = buildJsonObject {
            put("owners", JsonObject(state.owners.mapValues { (_, list) -> JsonArray(list) }))
            put("fired", JsonArray(state.fired.map { JsonPrimitive(it) }))
        }
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
