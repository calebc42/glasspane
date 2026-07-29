// SPDX-License-Identifier: GPL-3.0-or-later
// Durable backing for the SPEC 15 queue. Every mutation is one atomic
// whole-snapshot replace: the SPEC 15.1/15.2 "one durable transaction"
// requirements fall out of that shape by construction. The file store is
// the kill-matrix witness — a process death is "re-open the same file".
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/** One durable state of the queue: records plus the two counters that
 * must survive restart (SPEC 15.1 queue_seq; SPEC 15.2 clock mark). */
data class QueueSnapshot(
    val records: List<JSONObject>,
    val nextSeq: Long,
    val clockHighWater: Long,
)

interface QueueStore {
    fun load(): QueueSnapshot
    /** Atomically and durably replace the whole state; throws on failure. */
    fun replace(snapshot: QueueSnapshot)
}

class MemoryQueueStore : QueueStore {
    private var snapshot = QueueSnapshot(emptyList(), 1, 0)
    override fun load(): QueueSnapshot = snapshot
    override fun replace(snapshot: QueueSnapshot) { this.snapshot = snapshot }
}

/**
 * JSON file with write-to-temp, fsync, atomic-rename replacement, so a
 * crash leaves either the old state or the new state, never a torn one.
 */
class FileQueueStore(private val file: File) : QueueStore {

    override fun load(): QueueSnapshot {
        if (!file.exists()) return QueueSnapshot(emptyList(), 1, 0)
        val text = file.readText(Charsets.UTF_8)
        if (text.isBlank()) return QueueSnapshot(emptyList(), 1, 0)
        val root = JSONObject(text)
        val array = root.getJSONArray("records")
        return QueueSnapshot(
            records = (0 until array.length()).map { array.getJSONObject(it) },
            nextSeq = root.getLong("next_seq"),
            clockHighWater = root.getLong("clock_high_water"),
        )
    }

    override fun replace(snapshot: QueueSnapshot) {
        val root = JSONObject()
            .put("records", JSONArray(snapshot.records))
            .put("next_seq", snapshot.nextSeq)
            .put("clock_high_water", snapshot.clockHighWater)
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
