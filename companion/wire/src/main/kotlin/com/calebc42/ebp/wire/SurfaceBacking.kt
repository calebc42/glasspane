// SPDX-License-Identifier: GPL-3.0-or-later
// Durable backing for the SurfaceStore. The surface histories (SPEC 13.1,
// including tombstones that survive until pairing revocation) and the input
// drafts (which ARE the SPEC 10.2 input_state / the SPEC 15.1 reconnection
// snapshot) are one atomic whole-snapshot replace, so a process death leaves
// either the old state or the new state, never a torn one — the same shape
// as the durable queue's QueueStore.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/** One retained surface history. `spec`/`currentView` are null for a
 * tombstone (present == false). */
data class PersistedRecord(
    val surface: String,
    val revision: Long,
    val present: Boolean,
    val spec: JSONObject?,
    val currentView: String?,
)

/** One retained input draft; `value` may be null (a JSON null value). */
data class PersistedDraft(val surface: String, val id: String, val value: Any?)

data class SurfaceState(val records: List<PersistedRecord>, val drafts: List<PersistedDraft>)

interface SurfaceBacking {
    fun load(): SurfaceState
    /** Atomically and durably replace the whole state; throws on failure. */
    fun replace(state: SurfaceState)
}

class MemorySurfaceBacking : SurfaceBacking {
    private var state = SurfaceState(emptyList(), emptyList())
    override fun load(): SurfaceState = state
    override fun replace(state: SurfaceState) { this.state = state }
}

/**
 * JSON file with write-to-temp, fsync, atomic-rename replacement — the
 * kill-matrix witness for surfaces and input_state, exactly as
 * [FileQueueStore] is for the durable queue.
 */
class FileSurfaceBacking(private val file: File) : SurfaceBacking {

    override fun load(): SurfaceState {
        if (!file.exists()) return SurfaceState(emptyList(), emptyList())
        val text = file.readText(Charsets.UTF_8)
        if (text.isBlank()) return SurfaceState(emptyList(), emptyList())
        val root = JSONObject(text)
        val records = root.getJSONArray("records").let { a ->
            (0 until a.length()).map { i ->
                val o = a.getJSONObject(i)
                PersistedRecord(
                    surface = o.getString("surface"),
                    revision = o.getLong("revision"),
                    present = o.getBoolean("present"),
                    spec = o.optJSONObject("spec"),
                    currentView = if (o.has("current_view")) o.getString("current_view") else null,
                )
            }
        }
        val drafts = root.getJSONArray("drafts").let { a ->
            (0 until a.length()).map { i ->
                val o = a.getJSONObject(i)
                val raw = o.get("value")
                PersistedDraft(o.getString("surface"), o.getString("id"),
                    if (raw == JSONObject.NULL) null else raw)
            }
        }
        return SurfaceState(records, drafts)
    }

    override fun replace(state: SurfaceState) {
        val records = JSONArray()
        for (r in state.records) {
            val o = JSONObject().put("surface", r.surface)
                .put("revision", r.revision).put("present", r.present)
            if (r.spec != null) o.put("spec", r.spec)
            if (r.currentView != null) o.put("current_view", r.currentView)
            records.put(o)
        }
        val drafts = JSONArray()
        for (d in state.drafts)
            drafts.put(JSONObject().put("surface", d.surface).put("id", d.id)
                .put("value", d.value ?: JSONObject.NULL))
        val root = JSONObject().put("records", records).put("drafts", drafts)
        val temp = File(file.parentFile, file.name + ".tmp")
        FileOutputStream(temp).use { out ->
            out.write(root.toString().toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        if (!temp.renameTo(file)) {
            temp.delete()
            throw java.io.IOException("atomic replace failed for $file")
        }
        // Directory fsync for the rename's own durability (best-effort; the
        // JVM cannot demand it portably), as in FileQueueStore.
        runCatching {
            java.nio.channels.FileChannel.open(
                file.parentFile.toPath(),
                java.nio.file.StandardOpenOption.READ).use { it.force(true) }
        }
    }
}
