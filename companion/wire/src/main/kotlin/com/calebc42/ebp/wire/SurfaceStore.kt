// SPDX-License-Identifier: GPL-3.0-or-later
// The Companion's surface state: revisioned snapshots, tombstones that
// survive until pairing revocation, the surface-count limits, and the
// SPEC 13.6 input-draft reconciliation. In-memory at this rung; the
// persistence layer arrives with W6 durability.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject

private val SURFACE_ID = Regex("(app|notification|widget):[A-Za-z0-9][A-Za-z0-9._:/-]*")

data class SurfaceResult(val status: String, val revision: Long, val present: Boolean)

class SurfaceStore(
    private val maxSurfaces: Long,
    private val maxSurfaceIds: Long,
    private val maxCaptureFields: Long = 64,
) {

    private class Record(
        var revision: Long,
        var present: Boolean,
        var spec: JSONObject?,
        var currentView: String?,
        var statefuls: Map<String, JSONObject>,
    )

    private val records = LinkedHashMap<String, Record>()
    private val drafts = HashMap<Pair<String, String>, Any?>()

    fun isValidSurfaceId(id: String): Boolean =
        SURFACE_ID.matches(id) && id.toByteArray(Charsets.UTF_8).size <= 128

    /** The accepted snapshot for a present surface, for rendering. */
    fun spec(surface: String): JSONObject? =
        records[surface]?.takeIf { it.present }?.spec

    /** SPEC 14.4: the accepted revision the user is looking at. */
    fun revisionOf(surface: String): Long? =
        records[surface]?.takeIf { it.present }?.revision

    /** SPEC 14.1: the occurrence-time logical value of a stateful node —
     * the dirty draft when one exists, else the authored value/default. */
    fun currentValue(surface: String, id: String): Any? {
        if (surface to id in drafts) return drafts[surface to id]
        return records[surface]?.statefuls?.get(id)?.let { authoredValue(it) }
    }

    /** SPEC 14.6: password nodes never emit state or retain drafts. */
    fun isPasswordNode(surface: String, id: String): Boolean =
        records[surface]?.statefuls?.get(id)?.optBoolean("password") == true

    /** Whether ID is a stateful node in SURFACE's accepted snapshot. */
    fun isStatefulNode(surface: String, id: String): Boolean =
        records[surface]?.statefuls?.containsKey(id) == true

    fun namespace(id: String): String = id.substringBefore(':')

    // ------------------------------------------------------ update (13.2)

    fun update(surface: String, revision: Long, spec: JSONObject,
               staleSpec: JSONObject?, currentView: String?,
               resetIds: JSONArray?): SurfaceResult {
        // SPEC 13.2: validate the entire request before changing state.
        val statefuls = SpecValidator.validateSurfaceSpec(
            spec, maxCaptureFields = maxCaptureFields)
        val reset = resetIds?.let { SpecValidator.validateResetIds(it, statefuls) }
            ?: emptySet()
        staleSpec?.let { SpecValidator.validateStaleSpec(it, spec.has("views")) }
        val isMultiView = spec.has("views")
        if (currentView != null) {
            if (!isMultiView || !spec.getJSONObject("views").has(currentView))
                throw ContentInvalid("current_view",
                    "valid only for a multi-view app spec naming an existing view")
        }
        val record = records[surface]
        val floor = record?.revision ?: -1L
        if (revision <= floor)
            return SurfaceResult("stale", floor, record?.present ?: false)
        // SPEC 13.1: limits gate anything that would grow a saturated count.
        if (record == null) {
            if (records.size.toLong() >= maxSurfaceIds)
                throw ContentInvalid("surface", "surface-limit")
            if (presentCount() >= maxSurfaces)
                throw ContentInvalid("surface", "surface-limit")
        } else if (!record.present && presentCount() >= maxSurfaces) {
            // Reactivating a tombstone is invalid at max_surfaces.
            throw ContentInvalid("surface", "surface-limit")
        }
        val next = record ?: Record(-1, false, null, null, emptyMap())
        // SPEC 13.4: preserve the user's view unless it vanished, the
        // surface is new, or the request names one.
        next.currentView = when {
            !isMultiView -> null
            currentView != null -> currentView
            next.present && next.currentView != null &&
                spec.getJSONObject("views").has(next.currentView!!) -> next.currentView
            else -> spec.getString("initial_view")
        }
        next.revision = revision
        next.present = true
        next.spec = spec
        next.statefuls = statefuls
        records[surface] = next
        reconcileDrafts(surface, statefuls, reset)
        return SurfaceResult("applied", revision, true)
    }

    // ------------------------------------------------------ remove (13.3)

    fun remove(surface: String, revision: Long): SurfaceResult {
        val record = records[surface]
        val floor = record?.revision ?: -1L
        if (revision <= floor)
            return SurfaceResult("stale", floor, record?.present ?: false)
        if (record == null && records.size.toLong() >= maxSurfaceIds)
            throw ContentInvalid("surface", "surface-limit")
        val next = record ?: Record(-1, false, null, null, emptyMap())
        next.revision = revision
        next.present = false
        next.spec = null
        next.currentView = null
        next.statefuls = emptyMap()
        records[surface] = next
        // SPEC 13.3: tombstoning erases every draft belonging to the surface.
        drafts.keys.removeAll { it.first == surface }
        return SurfaceResult("applied", revision, false)
    }

    private fun presentCount(): Long = records.values.count { it.present }.toLong()

    // -------------------------------------------------- welcome reporting

    /** SPEC 10.2: both present snapshots and tombstones are reported. */
    fun snapshot(): JSONObject {
        val out = JSONObject()
        for ((id, record) in records)
            out.put(id, JSONObject()
                .put("revision", record.revision).put("present", record.present))
        return out
    }

    /** SPEC 10.2 input_state: latest non-password values, present surfaces. */
    fun inputState(): JSONObject {
        val out = JSONObject()
        for ((key, value) in drafts) {
            val (surface, id) = key
            if (records[surface]?.present != true) continue
            if (!out.has(surface)) out.put(surface, JSONObject())
            out.getJSONObject(surface).put(id, value ?: JSONObject.NULL)
        }
        return out
    }

    // ------------------------------------------------------ drafts (13.6)

    fun putDraft(surface: String, id: String, value: Any?) {
        val node = records[surface]?.statefuls?.get(id) ?: return
        if (node.optBoolean("password")) return // SPEC 14.6: never retained
        drafts[surface to id] = value
    }

    fun draft(surface: String, id: String): Any? = drafts[surface to id]

    fun hasDraft(surface: String, id: String): Boolean = (surface to id) in drafts

    private fun reconcileDrafts(surface: String, statefuls: Map<String, JSONObject>,
                                reset: Set<String>) {
        val stale = drafts.keys.filter { (s, id) ->
            s == surface && run {
                val node = statefuls[id]
                val value = drafts[s to id]
                node == null ||                      // ID disappeared
                    id in reset ||                   // explicitly replaced
                    !compatible(node, value) ||      // schema incompatible
                    jsonValueEquals(authoredValue(node), value) // acknowledged
            }
        }
        stale.forEach(drafts::remove)
    }

    /** SPEC 13.6: value-schema compatibility is exact. */
    private fun compatible(node: JSONObject, value: Any?): Boolean =
        when (node.getString("t")) {
            "text_input" -> value is String && !node.optBoolean("password") &&
                (!node.optBoolean("single_line") || '\n' !in value)
            "checkbox", "switch" -> value is Boolean
            "enum_list" -> {
                val options = node.getJSONArray("options")
                val legal = { v: Any? ->
                    (0 until options.length()).any {
                        jsonValueEquals(options.getJSONObject(it).get("value"), v)
                    } || (node.optBoolean("allow_add") && v is String && v.isNotEmpty())
                }
                if (node.optBoolean("multi_select"))
                    value is JSONArray && (0 until value.length()).all { legal(value.get(it)) }
                else value !is JSONArray && legal(value)
            }
            "slider" -> value is Number && run {
                val values = node.optJSONArray("values")
                if (values != null)
                    (0 until values.length()).any {
                        jsonValueEquals(values.get(it), value)
                    }
                else {
                    val min = (node.opt("min") as? Number)?.toDouble() ?: 0.0
                    val max = (node.opt("max") as? Number)?.toDouble() ?: 1.0
                    value.toDouble() in min..max
                }
            }
            "editor" -> value is String && node.optBoolean("publish_state") &&
                !node.has("document")
            else -> false
        }

    private fun authoredValue(node: JSONObject): Any? = when (node.getString("t")) {
        "text_input", "editor" -> node.opt("value") ?: ""
        "checkbox", "switch" -> node.opt("checked") ?: false
        "enum_list" ->
            node.opt("value") ?: if (node.optBoolean("multi_select")) JSONArray() else null
        "slider" -> node.opt("value")
            ?: node.optJSONArray("values")?.get(0) ?: node.opt("min") ?: 0
        else -> null
    }
}
