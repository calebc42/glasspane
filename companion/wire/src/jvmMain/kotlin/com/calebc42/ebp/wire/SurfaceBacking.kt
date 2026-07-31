// SPDX-License-Identifier: GPL-3.0-or-later
// Durable backing for the SurfaceStore. The surface histories (SPEC 13.1,
// including tombstones that survive until pairing revocation) and the input
// drafts (which ARE the SPEC 10.2 input_state / the SPEC 15.1 reconnection
// snapshot) are one atomic whole-snapshot replace, so a process death leaves
// either the old state or the new state, never a torn one — the same shape
// as the durable queue's QueueStore.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.io.FileOutputStream

/** One retained surface history. `spec`/`currentView` are null for a
 * tombstone (present == false). */
data class PersistedRecord(
    val surface: String,
    val revision: Long,
    val present: Boolean,
    val spec: JsonObject?,
    val currentView: String?,
)

/**
 * One retained input draft; `value` may be null (a JSON null value).
 *
 * R6: this is the module's one documented exception to the "Kotlin null =
 * member ABSENT" convention — at the draft seam Kotlin null IS the JSON null,
 * which is exactly what the `?: JSONObject.NULL` elvis meant pre-swap. A
 * draft's existence is carried by the record existing at all, so there is no
 * absent value left to distinguish. The on-disk spelling is `"value":null` —
 * never an omitted member, never the STRING "null".
 */
data class PersistedDraft(val surface: String, val id: String, val value: JsonElement?)

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
        val records = root?.arrOrNull("records")?.map { element ->
            val o = element.jsonObject
            PersistedRecord(
                surface = o.reqString("surface"),
                revision = o.reqLong("revision"),
                present = o.reqBoolean("present"),
                spec = o.objOrNull("spec"),
                currentView = if ("current_view" in o) o.reqString("current_view") else null,
            )
        } ?: emptyList()
        // Drafts come from the split file. Backward compat: a records file
        // written by the pre-split format carries its own `drafts` array.
        // MIGRATE it immediately rather than reading it lazily — a
        // records-only rewrite (a `view.switch`, say) drops the legacy array,
        // so a lazy fallback loses every migrated draft the moment anything
        // touches records before a draft is written.
        val draftsRoot = readObject(draftsFile) ?: root?.also { legacy ->
            legacy.arrOrNull("drafts")?.let { legacyDrafts ->
                runCatching {
                    writeAtomic(draftsFile, buildJsonObject { put("drafts", legacyDrafts) })
                }
            }
        }
        val drafts = draftsRoot?.arrOrNull("drafts")?.map { element ->
            val o = element.jsonObject
            // `value` must be PRESENT: org.json's throwing `get` is what said
            // so, and a draft record without one is corrupt, not a null draft.
            val raw = o["value"] ?: throw NoSuchElementException("value")
            // R6: the draft seam spells JSON null as Kotlin null — see
            // [PersistedDraft]. This is the load half of that round trip.
            PersistedDraft(o.reqString("surface"), o.reqString("id"),
                if (raw is JsonNull) null else raw)
        } ?: emptyList()
        return SurfaceState(records, drafts)
    }

    override fun replaceRecords(records: List<PersistedRecord>) {
        val arr = JsonArray(records.map { r ->
            buildJsonObject {
                put("surface", r.surface)
                put("revision", r.revision)
                put("present", r.present)
                // Absent, not null: `spec` and `current_view` are read back by
                // presence, and kotlinx's `put(k, null)` WRITES a JSON null
                // where org.json's removed the member.
                r.spec?.let { put("spec", it) }
                r.currentView?.let { put("current_view", it) }
            }
        })
        writeAtomic(file, buildJsonObject { put("records", arr) })
    }

    override fun replaceDrafts(drafts: List<PersistedDraft>) {
        val arr = JsonArray(drafts.map { d ->
            buildJsonObject {
                put("surface", d.surface)
                put("id", d.id)
                // R6: Kotlin null IS the JSON null here, so it is WRITTEN as
                // one — `"value":null`, never an omitted member and never the
                // STRING "null" (the delta a `put(k, v.toString())` port
                // would introduce). Pinned by
                // PersistenceCompatTest.draftNullRoundTripsAsJsonNull.
                put("value", d.value ?: JsonNull)
            }
        })
        writeAtomic(draftsFile, buildJsonObject { put("drafts", arr) })
    }

    private fun readObject(f: File): JsonObject? {
        if (!f.exists()) return null
        val text = f.readText(Charsets.UTF_8)
        // PERSISTED text is read by kotlinx's lenient parser, NEVER by
        // EbpJson.parse: that one is the strict WIRE parser, and SPEC 4.5 caps
        // a frame at 64 nested containers. A stored `spec` may legally nest
        // deeper on disk than any single frame may carry (the record and the
        // {"records":[…]} wrapper alone add levels), so a strict re-parse
        // would turn a perfectly legal store file into a boot crash-loop.
        // Pinned by PersistenceCompatTest.strictParserRejectsWhatTheStoreMustAccept.
        return if (text.isBlank()) null else Json.parseToJsonElement(text).jsonObject
    }

    /** org.json's `getBoolean`, minus its "true"/"false" STRING coercion: a
     * record with no usable `present` still refuses to load rather than
     * silently becoming a tombstone. JsonAccess has no throwing boolean
     * reader; this stays a member so adding one there cannot collide. */
    private fun JsonObject.reqBoolean(k: String): Boolean =
        (this[k] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toBooleanStrictOrNull()
            ?: throw NoSuchElementException(k)

    private fun writeAtomic(target: File, root: JsonObject) {
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
