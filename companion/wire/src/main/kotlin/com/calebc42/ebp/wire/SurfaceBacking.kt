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
    /** LD-14: records and drafts persist SEPARATELY. A keystroke touches only
     * drafts, so it re-serializes no spec and no tombstone — the dominant
     * cost was rebuilding every present spec plus up to `max_surface_ids`
     * (4096) tombstones on every draft write. Each is its own atomic,
     * durable replace; throws on failure. */
    fun replaceRecords(records: List<PersistedRecord>)
    fun replaceDrafts(drafts: List<PersistedDraft>)
}

class MemorySurfaceBacking : SurfaceBacking {
    private var records = emptyList<PersistedRecord>()
    private var drafts = emptyList<PersistedDraft>()
    override fun load(): SurfaceState = SurfaceState(records, drafts)
    override fun replaceRecords(records: List<PersistedRecord>) { this.records = records }
    override fun replaceDrafts(drafts: List<PersistedDraft>) { this.drafts = drafts }
}

/**
 * Two JSON files, each with write-to-temp, fsync, atomic-rename replacement —
 * the kill-matrix witness for surfaces and input_state, exactly as
 * [FileQueueStore] is for the durable queue. LD-14: records (specs +
 * tombstones) and drafts live in SEPARATE files so a keystroke re-serializes
 * only the drafts. [draftsFile] defaults to a `-drafts` sibling of the
 * records file, so existing callers pass one path and get the split.
 */
class FileSurfaceBacking(
    private val file: File,
    private val draftsFile: File =
        File(file.parentFile, file.nameWithoutExtension + "-drafts." +
            (file.extension.ifEmpty { "json" })),
) : SurfaceBacking {

    override fun load(): SurfaceState {
        val root = readObject(file)
        val records = root?.optJSONArray("records")?.let { a ->
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
        } ?: emptyList()
        // Drafts come from the split file. Backward compat: a records file
        // written by the pre-split format carries its own `drafts` array.
        // MIGRATE it immediately rather than reading it lazily — a
        // records-only rewrite (a `view.switch`, say) drops the legacy array,
        // so a lazy fallback loses every migrated draft the moment anything
        // touches records before a draft is written.
        val draftsRoot = readObject(draftsFile) ?: root?.also { legacy ->
            if (legacy.optJSONArray("drafts") != null)
                runCatching { writeAtomic(draftsFile, JSONObject()
                    .put("drafts", legacy.getJSONArray("drafts"))) }
        }
        val drafts = draftsRoot?.optJSONArray("drafts")?.let { a ->
            (0 until a.length()).map { i ->
                val o = a.getJSONObject(i)
                val raw = o.get("value")
                PersistedDraft(o.getString("surface"), o.getString("id"),
                    if (raw == JSONObject.NULL) null else raw)
            }
        } ?: emptyList()
        return SurfaceState(records, drafts)
    }

    override fun replaceRecords(records: List<PersistedRecord>) {
        val arr = JSONArray()
        for (r in records) {
            val o = JSONObject().put("surface", r.surface)
                .put("revision", r.revision).put("present", r.present)
            if (r.spec != null) o.put("spec", r.spec)
            if (r.currentView != null) o.put("current_view", r.currentView)
            arr.put(o)
        }
        writeAtomic(file, JSONObject().put("records", arr))
    }

    override fun replaceDrafts(drafts: List<PersistedDraft>) {
        val arr = JSONArray()
        for (d in drafts)
            arr.put(JSONObject().put("surface", d.surface).put("id", d.id)
                .put("value", d.value ?: JSONObject.NULL))
        writeAtomic(draftsFile, JSONObject().put("drafts", arr))
    }

    private fun readObject(f: File): JSONObject? {
        if (!f.exists()) return null
        val text = f.readText(Charsets.UTF_8)
        return if (text.isBlank()) null else JSONObject(text)
    }

    private fun writeAtomic(target: File, root: JSONObject) {
        val temp = File(target.parentFile, target.name + ".tmp")
        FileOutputStream(temp).use { out ->
            out.write(root.toString().toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        if (!temp.renameTo(target)) {
            temp.delete()
            throw java.io.IOException("atomic replace failed for $target")
        }
        // Directory fsync for the rename's own durability (best-effort; the
        // JVM cannot demand it portably), as in FileQueueStore.
        runCatching {
            java.nio.channels.FileChannel.open(
                target.parentFile.toPath(),
                java.nio.file.StandardOpenOption.READ).use { it.force(true) }
        }
    }
}
