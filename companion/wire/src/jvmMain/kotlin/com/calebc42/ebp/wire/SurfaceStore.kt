// SPDX-License-Identifier: GPL-3.0-or-later
// The Companion's surface state: revisioned snapshots, tombstones that
// survive until pairing revocation, the surface-count limits, and the
// SPEC 13.6 input-draft reconciliation. In-memory at this rung; the
// persistence layer arrives with W6 durability.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

private val SURFACE_ID = Regex("(app|notification|widget):[A-Za-z0-9][A-Za-z0-9._:/-]*")

data class SurfaceResult(val status: String, val revision: Long, val present: Boolean)

/** T3/LD-2: the value a stateful node's widget should display, and the
 * generation that value belongs to. See [SurfaceStore.inputDisplays].
 *
 * R6: `value` follows the draft seam — Kotlin null is the JSON null, not an
 * absent member (see [PersistedDraft]). */
data class InputDisplay(val epoch: Long, val value: JsonElement?)

class SurfaceStore(
    private val maxSurfaces: Long,
    private val maxSurfaceIds: Long,
    private val maxCaptureFields: Long = 64,
    // SPEC 4.5: chart/canvas/span/cell count caps enforced at validation when
    // the corresponding node type is advertised. Spans and cells are AGGREGATE
    // counts across one SurfaceSpec, like chart points across all series.
    private val maxChartPoints: Long = Long.MAX_VALUE,
    private val maxCanvasOps: Long = Long.MAX_VALUE,
    private val maxRichSpans: Long = Long.MAX_VALUE,
    private val maxTableCells: Long = Long.MAX_VALUE,
    // SPEC 17.1: the app / notification profiles' advertised node_types, so an
    // unadvertised-but-known type degrades. null = allow all (in-memory tests).
    private val appNodeTypes: Set<String>? = null,
    private val notificationNodeTypes: Set<String>? = null,
    // SPEC 14.2 (LD-17): the advertised builtins per target, for the
    // invalid-context gate. null = allow all.
    private val appBuiltins: Set<String>? = null,
    private val notificationBuiltins: Set<String>? = null,
    /** SPEC 13.1/15.1: durable surface histories + input_state. In-memory
     * by default; DeviceBridge wires a file so both survive process death. */
    private val backing: SurfaceBacking = MemorySurfaceBacking(),
) {

    private class Record(
        var revision: Long,
        var present: Boolean,
        var spec: JsonObject?,
        var currentView: String?,
        var statefuls: Map<String, JsonObject>,
    )

    private val records = LinkedHashMap<String, Record>()
    // R6: a present key IS the draft; its value follows the draft seam, where
    // Kotlin null is the JSON null (see [PersistedDraft]).
    private val drafts = HashMap<Pair<String, String>, JsonElement?>()
    // T3/LD-2: display generations — see [inputEpoch]. Deliberately NOT
    // persisted: a process restart rebuilds every widget from the durable
    // draft or authored value anyway, so there is nothing stale to supersede.
    private val epochs = HashMap<Pair<String, String>, Long>()
    private var epochClock = 0L

    init {
        // SPEC 10.4/13.1: the store outlives connections AND process death.
        // Statefuls are recomputed from the durable spec; a record whose
        // spec no longer validates is dropped rather than crashing startup.
        val state = backing.load()
        for (r in state.records) {
            var present = r.present
            var spec = r.spec
            var currentView = r.currentView
            val statefuls = if (r.present && r.spec != null) {
                // SPEC 13.4: the namespace decides the variant, on RELOAD too.
                // Re-validating a notification spec ({body, meta?}) with the
                // app-surface validator failed every time, so every present
                // notification was dropped on every restart.
                val revalidated = runCatching {
                    if (namespace(r.surface) == "notification") {
                        SpecValidator.validateNotificationSpec(r.spec,
                            maxCaptureFields = maxCaptureFields,
                            advertisedTypes = notificationNodeTypes,
                            advertisedBuiltins = notificationBuiltins,
                            maxChartPoints = maxChartPoints, maxCanvasOps = maxCanvasOps,
                            maxRichSpans = maxRichSpans, maxTableCells = maxTableCells)
                        emptyMap()
                    } else {
                        SpecValidator.validateSurfaceSpec(r.spec,
                            maxCaptureFields = maxCaptureFields,
                            maxChartPoints = maxChartPoints, maxCanvasOps = maxCanvasOps,
                            maxRichSpans = maxRichSpans, maxTableCells = maxTableCells,
                            advertisedTypes = appNodeTypes,
                            advertisedBuiltins = appBuiltins)
                    }
                }.getOrNull()
                if (revalidated == null) {
                    // SPEC 13.1: "MUST retain each tombstone revision floor
                    // until pairing revocation and MUST NOT reclaim it." A
                    // spec this build can no longer validate — because the
                    // validator legitimately tightened between versions —
                    // MUST NOT be rendered or dispatched, but DROPPING the
                    // record reclaimed its floor, so a delayed older
                    // `surface.update` would then be answered `applied`
                    // instead of `stale`. Retain the history as a tombstone:
                    // not present, floor intact, and Emacs re-pushes.
                    present = false
                    spec = null
                    currentView = null
                    emptyMap()
                } else revalidated
            } else emptyMap()
            records[r.surface] = Record(r.revision, present, spec, currentView, statefuls)
        }
        // SPEC 10.2/13.6: a draft belongs to a stateful node of a PRESENT
        // surface. The two files persist independently, so a reload can carry
        // a draft whose node the loaded spec does not have; keeping it would
        // publish a phantom in the welcome `input_state`.
        for (d in state.drafts) {
            val rec = records[d.surface] ?: continue
            if (!rec.present || !rec.statefuls.containsKey(d.id)) continue
            drafts[d.surface to d.id] = d.value
        }
    }

    /**
     * SPEC 15.1: commit the surface histories and the input_state snapshot
     * durably. Best-effort like the queue's expiry sweep — a persist failure
     * leaves the last durable state, and Emacs re-pushes surfaces on
     * reconnect regardless. Called on every accepted mutation, so a draft
     * is durable before any later durable event (SPEC 15.1 ordering).
     */
    private fun persistRecords() {
        runCatching {
            backing.replaceRecords(records.map { (surface, r) ->
                PersistedRecord(surface, r.revision, r.present, r.spec, r.currentView)
            })
        }
    }

    private fun persistDrafts() {
        runCatching {
            backing.replaceDrafts(drafts.map { (k, v) -> PersistedDraft(k.first, k.second, v) })
        }
    }

    /** LD-14: an update or remove touches both files. The order is
     * drafts-then-records so a §15.1 reader that saw the new records also
     * sees the reconciled drafts, never a draft the new spec has dropped. */
    private fun persist() {
        persistDrafts()
        persistRecords()
    }

    fun isValidSurfaceId(id: String): Boolean =
        SURFACE_ID.matches(id) && id.toByteArray(Charsets.UTF_8).size <= 128

    /** The accepted snapshot for a present surface, for rendering. */
    fun spec(surface: String): JsonObject? =
        records[surface]?.takeIf { it.present }?.spec

    /** SPEC 14.4: the accepted revision the user is looking at. */
    fun revisionOf(surface: String): Long? =
        records[surface]?.takeIf { it.present }?.revision

    /** SPEC 13.4/14.2: the view a present multi-view surface shows. */
    fun currentView(surface: String): String? =
        records[surface]?.takeIf { it.present }?.currentView

    /** SPEC 14.2 view.switch: valid only inside a present multi-view surface
     * whose snapshot names `view`; the local choice persists like any other
     * presentation state. Returns whether the switch happened. */
    fun switchView(surface: String, view: String): Boolean {
        val r = records[surface]?.takeIf { it.present } ?: return false
        val views = r.spec?.objOrNull("views") ?: return false
        if (view !in views) return false
        r.currentView = view
        persistRecords() // view choice is record state, no draft touched
        return true
    }

    /** SPEC 14.1: the occurrence-time logical value of a stateful node —
     * the dirty draft when one exists, else the authored value/default. */
    fun currentValue(surface: String, id: String): JsonElement? {
        if (surface to id in drafts) return drafts[surface to id]
        return records[surface]?.statefuls?.get(id)?.let { authoredValue(it) }
    }

    /** SPEC 14.6: password nodes never emit state or retain drafts. */
    fun isPasswordNode(surface: String, id: String): Boolean =
        records[surface]?.statefuls?.get(id)?.boolOr("password") == true

    /** Whether ID is a stateful node in SURFACE's accepted snapshot. */
    fun isStatefulNode(surface: String, id: String): Boolean =
        records[surface]?.statefuls?.containsKey(id) == true

    fun namespace(id: String): String = id.substringBefore(':')

    // ------------------------------------------------------ update (13.2)

    fun update(surface: String, revision: Long, spec: JsonObject,
               staleSpec: JsonObject?, currentView: String?,
               resetIds: JsonArray?): SurfaceResult {
        // SPEC 13.2: validate the entire request before changing state.
        // SPEC 13.4: the namespace decides the SurfaceSpec variant.
        val statefuls: Map<String, JsonObject>
        val reset: Set<String>
        val isMultiView: Boolean
        if (namespace(surface) == "notification") {
            // SPEC 13.4/18.5: {body: Node, meta?}, no views, no drafts.
            SpecValidator.validateNotificationSpec(spec, maxCaptureFields = maxCaptureFields,
                advertisedTypes = notificationNodeTypes,
                advertisedBuiltins = notificationBuiltins,
                maxChartPoints = maxChartPoints, maxCanvasOps = maxCanvasOps,
                maxRichSpans = maxRichSpans, maxTableCells = maxTableCells)
            if (currentView != null)
                throw ContentInvalid("current_view", "not valid for a notification surface")
            if (resetIds != null && resetIds.size > 0)
                throw ContentInvalid("reset_input_ids", "a notification surface has no drafts")
            staleSpec?.let {
                SpecValidator.validateNotificationSpec(it, "stale_spec", maxCaptureFields,
                    advertisedTypes = notificationNodeTypes,
                    advertisedBuiltins = notificationBuiltins,
                    maxChartPoints = maxChartPoints, maxCanvasOps = maxCanvasOps,
                    maxRichSpans = maxRichSpans, maxTableCells = maxTableCells)
            }
            statefuls = emptyMap()
            reset = emptySet()
            isMultiView = false
        } else {
            statefuls = SpecValidator.validateSurfaceSpec(
                spec, maxCaptureFields = maxCaptureFields,
                maxChartPoints = maxChartPoints, maxCanvasOps = maxCanvasOps,
                maxRichSpans = maxRichSpans, maxTableCells = maxTableCells,
                advertisedTypes = appNodeTypes, advertisedBuiltins = appBuiltins)
            reset = resetIds?.let { SpecValidator.validateResetIds(it, statefuls) }
                ?: emptySet()
            // SPEC 13.5/14.2/17.1: a stale_spec is RENDERED while
            // disconnected, so it is held to the same per-target gates as the
            // live spec — an unadvertised builtin inside it is the same
            // invalid context, and an unadvertised node type must degrade
            // rather than be held to its per-type schema.
            staleSpec?.let { SpecValidator.validateStaleSpec(it, "views" in spec,
                maxCaptureFields, maxChartPoints, maxCanvasOps,
                maxRichSpans, maxTableCells, appNodeTypes, appBuiltins) }
            isMultiView = "views" in spec
            if (currentView != null) {
                if (!isMultiView || currentView !in spec.reqObj("views"))
                    throw ContentInvalid("current_view",
                        "valid only for a multi-view app spec naming an existing view")
            }
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
                next.currentView!! in spec.reqObj("views") -> next.currentView
            else -> spec.reqString("initial_view")
        }
        // SPEC 13.6: the pre-update node types decide draft compatibility.
        val oldStatefuls = next.statefuls
        // T3/LD-2: what the display is showing right now, before this
        // snapshot is applied — the draft when the user has one, else the
        // authored value.
        val shownBefore = (oldStatefuls.keys + statefuls.keys)
            .associateWith { currentValue(surface, it) }
        next.revision = revision
        next.present = true
        next.spec = spec
        next.statefuls = statefuls
        records[surface] = next
        reconcileDrafts(surface, oldStatefuls, statefuls, reset)
        // T3/LD-2: THE stamping point. A node whose displayed value is not
        // what it was, when the user did not change it, has been decided by
        // this snapshot — its widget must reseed. This catches both shapes at
        // once: an erased draft (the authored value now governs) and a moved
        // authored value with no draft standing. A surviving draft compares
        // equal to itself, so a user's in-progress edit never reseeds.
        for ((id, before) in shownBefore) {
            if (!jsonValueEquals(before, currentValue(surface, id)))
                epochs[surface to id] = ++epochClock
        }
        persist()
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
        persist()
        return SurfaceResult("applied", revision, false)
    }

    private fun presentCount(): Long = records.values.count { it.present }.toLong()

    /** SPEC 13.5/19: the present surfaces, in acceptance order. The store
     * outlives a connection, so this is what a fresh session must reconcile
     * against — a reconnect that receives no `surface.update` still has
     * present snapshots, and their synchronized editors still need sessions. */
    fun presentSurfaces(): List<String> =
        records.entries.filter { it.value.present }.map { it.key }

    // -------------------------------------------------- welcome reporting

    /** SPEC 10.2: both present snapshots and tombstones are reported. */
    fun snapshot(): JsonObject = buildJsonObject {
        for ((id, record) in records) {
            put(id, buildJsonObject {
                put("revision", record.revision)
                put("present", record.present)
                // SPEC 10.2 (amendment #129): a present multi-view app surface
                // also reports the view the user is actually on.
                // `view.switched` is when_offline "drop", so a navigation
                // performed while Emacs was disconnected is otherwise
                // unrecoverable at the 10.3 barrier. currentView is null for a
                // single-root snapshot (#128 clears it), so this is present
                // exactly when the spec requires it.
                if (record.present && id.startsWith("app:"))
                    record.currentView?.let { put("current_view", it) }
            })
        }
    }

    /** SPEC 10.2 input_state: latest non-password values, present surfaces. */
    fun inputState(): JsonObject {
        // Immutable trees: accumulate per surface and build once. The old
        // `out.getJSONObject(surface).put(...)` reached into a nested object
        // and mutated it in place — an operation that no longer exists.
        val out = LinkedHashMap<String, MutableMap<String, JsonElement>>()
        for ((key, value) in drafts) {
            val (surface, id) = key
            if (records[surface]?.present != true) continue
            // R6: a draft's Kotlin null IS the JSON null, and input_state
            // reports it as one (the old `?: JSONObject.NULL`).
            out.getOrPut(surface) { LinkedHashMap() }[id] = value ?: JsonNull
        }
        return JsonObject(out.mapValues { (_, members) -> JsonObject(members) })
    }

    // ------------------------------------------------------ drafts (13.6)

    fun putDraft(surface: String, id: String, value: JsonElement?) {
        val node = records[surface]?.statefuls?.get(id) ?: return
        if (node.boolOr("password")) return // SPEC 14.6: never retained
        drafts[surface to id] = value
        // SPEC 15.1: the input_state snapshot is durable no later than any
        // event created from this interaction. LD-14: only drafts.json is
        // rewritten — a keystroke no longer re-serializes every spec and
        // every tombstone.
        persistDrafts()
    }

    fun draft(surface: String, id: String): JsonElement? = drafts[surface to id]

    fun hasDraft(surface: String, id: String): Boolean = (surface to id) in drafts

    /**
     * T3/LD-2: the generation of the value a stateful node's DISPLAY should be
     * showing. It changes only when a snapshot — not the user — decided that
     * value: a draft the user typed was erased under §13.6 (`reset_input_ids`,
     * an incompatible or acknowledged value, a reused ID), or the authored
     * value moved while no draft stood.
     *
     * This exists because the store is authoritative for `capture_fields`
     * (§14.1) and the welcome `input_state` (§15.1) while the editing widget
     * keeps its own copy. Keyed on `(surface, id)` alone, that copy is
     * invariant across revisions: its seeding lambda runs once and no later
     * snapshot ever reseeds it. So Emacs could push `value: "Untitled"` with
     * `reset_input_ids: ["title"]`, the store would erase the draft, and the
     * field would still read what the user typed — while a `capture_fields`
     * button submitted "Untitled". The value on screen and the value on the
     * wire were two different values, with nothing to reconcile them.
     *
     * The epoch is that reconciliation point, and like Emacs's `make_current`
     * it is stamped in exactly ONE place: [update], below.
     */
    fun inputEpoch(surface: String, id: String): Long = epochs[surface to id] ?: 0L

    /** Every `(surface, id)` whose epoch is non-zero, for the host's snapshot
     * of display generations. */
    fun inputEpochs(): Map<Pair<String, String>, Long> = epochs.toMap()

    /**
     * T3/LD-2: what every stateful node of every PRESENT surface should be
     * displaying, and which generation that is.
     *
     * The epoch alone is not enough. A widget that seeds from the node's
     * AUTHORED value shows the wrong thing whenever it is disposed and
     * recomposed while a draft stands — a view switch, a `collapsible`
     * folding, a `lazy_column` recycling the row — because no snapshot
     * changed, so no epoch moves, and the widget silently reverts to the
     * authored value while the store (and therefore `capture_fields` and
     * `input_state`) still holds the user's. Publishing the value makes the
     * store the seed authority in every case, and the epoch says only WHEN
     * to re-seed.
     */
    fun inputDisplays(): Map<Pair<String, String>, InputDisplay> {
        val out = HashMap<Pair<String, String>, InputDisplay>()
        for ((surface, r) in records) {
            if (!r.present) continue
            for (id in r.statefuls.keys) {
                val key = surface to id
                out[key] = InputDisplay(epochs[key] ?: 0L, currentValue(surface, id))
            }
        }
        return out
    }

    private fun reconcileDrafts(surface: String, oldStatefuls: Map<String, JsonObject>,
                                newStatefuls: Map<String, JsonObject>, reset: Set<String>) {
        val stale = drafts.keys.filter { (s, id) ->
            s == surface && run {
                val node = newStatefuls[id]
                val value = drafts[s to id]
                val oldNode = oldStatefuls[id]
                node == null ||                      // ID disappeared
                    id in reset ||                   // explicitly replaced
                    // SPEC 13.6/16.1: reusing an ID for a different node type
                    // is a new identity — erase even when the value schema is
                    // still compatible (checkbox<->switch, text_input->editor).
                    (oldNode != null && oldNode.reqString("t") != node.reqString("t")) ||
                    !compatible(node, value) ||      // schema incompatible
                    jsonValueEquals(authoredValue(node), value) // acknowledged
            }
        }
        stale.forEach(drafts::remove)
    }

    /** SPEC 13.6: value-schema compatibility is exact. */
    private fun compatible(node: JsonObject, value: JsonElement?): Boolean =
        when (node.reqString("t")) {
            "text_input" -> value is JsonPrimitive && value.isString &&
                !node.boolOr("password") &&
                (!node.boolOr("single_line") || '\n' !in value.content)
            // §13.6: `state` present makes the value schema the enum STRING,
            // not a boolean — a retained boolean draft is incompatible and is
            // erased, which is why tri-state is a distinct member rather than
            // a widened `checked`.
            "checkbox" ->
                if ("state" in node)
                    value is JsonPrimitive && value.isString &&
                        value.content in TRI_STATES
                else isJsonBoolean(value)
            "switch" -> isJsonBoolean(value)
            "button", "icon_button" -> "checked" in node && isJsonBoolean(value)
            "search_bar" -> value is JsonPrimitive && value.isString
            // §17.4 dropdown: the editable form's value is the TEXT (any
            // string, like text_input); the plain form's is an option value,
            // like enum_list single-select.
            "dropdown" ->
                if (node.boolOr("editable"))
                    value is JsonPrimitive && value.isString
                else {
                    val options = node.reqArr("options")
                    value !is JsonArray &&
                        options.any { jsonValueEquals(it.jsonObject["value"], value) }
                }
            // §17.4: segmented_button's value schema mirrors enum_list exactly
            // (one option value, or an array of them under multi_select),
            // minus allow_add, which it does not carry.
            "enum_list", "segmented_button" -> {
                val options = node.reqArr("options")
                val legal = { v: JsonElement? ->
                    options.any { jsonValueEquals(it.jsonObject["value"], v) } ||
                        (node.boolOr("allow_add") &&
                            v is JsonPrimitive && v.isString && v.content.isNotEmpty())
                }
                if (node.boolOr("multi_select"))
                    value is JsonArray && value.all { legal(it) }
                else value !is JsonArray && legal(value)
            }
            // §13.6: `value_end` present makes the value schema a TWO-NUMBER
            // array (both thumbs), so a scalar draft from before the member
            // was authored is incompatible and erased — and vice versa.
            "slider" ->
                if ("value_end" in node) {
                    val min = jsonNumberOrNull(node["min"]) ?: 0.0
                    val max = jsonNumberOrNull(node["max"]) ?: 1.0
                    val pair = (value as? JsonArray)?.takeIf { it.size == 2 }
                        ?.mapNotNull { jsonNumberOrNull(it) }
                    pair != null && pair.size == 2 && pair[0] <= pair[1] &&
                        pair.all { it in min..max }
                } else jsonNumberOrNull(value)?.let { num ->
                    val values = node.arrOrNull("values")
                    if (values != null)
                        values.any { jsonValueEquals(it, value) }
                    else {
                        val min = jsonNumberOrNull(node["min"]) ?: 0.0
                        val max = jsonNumberOrNull(node["max"]) ?: 1.0
                        num in min..max
                    }
                } ?: false
            "editor" -> value is JsonPrimitive && value.isString &&
                node.boolOr("publish_state") && "document" !in node
            else -> false
        }

    companion object {
        /** SPEC 14.1: the authored/default logical value of a stateful node —
         * the value in force before the user touches it. Shared with the
         * dialog defaults layer (T3/LD-3), which has no draft store of its
         * own, so both layers resolve a default the same way.
         *
         * The elvises test for an ABSENT member, exactly as `opt` did: an
         * authored `"value": null` reads back as JsonNull (non-null, like
         * org.json's NULL), so it still overrides the default rather than
         * being replaced by it. */
        fun authoredValueOf(node: JsonObject): JsonElement? = when (node.reqString("t")) {
            "text_input", "editor" -> node["value"] ?: JsonPrimitive("")
            "checkbox" ->
                if ("state" in node) node["state"] ?: JsonPrimitive("off")
                else node["checked"] ?: JsonPrimitive(false)
            "switch" -> node["checked"] ?: JsonPrimitive(false)
            // null when absent: a plain button has no authored value at all.
            "button", "icon_button" -> node["checked"]
            "search_bar" -> node["value"] ?: JsonPrimitive("")
            "dropdown" ->
                if (node.boolOr("editable")) node["value"] ?: JsonPrimitive("")
                else node["value"]
            "enum_list", "segmented_button" -> node["value"]
                ?: if (node.boolOr("multi_select")) JsonArray(emptyList()) else null
            "slider" ->
                if ("value_end" in node) {
                    val floor = node["value"] ?: node["min"] ?: JsonPrimitive(0)
                    JsonArray(listOf(floor, node["value_end"] ?: floor))
                } else node["value"]
                    ?: node.arrOrNull("values")?.get(0) ?: node["min"] ?: JsonPrimitive(0)
            else -> null
        }

        /** The legal checkbox `state` strings (§17.4 tri-state). */
        val TRI_STATES: Set<String> = setOf("off", "on", "indeterminate")

        /** The two SPEC 4.2 kind tests org.json used to get from Kotlin's
         * `is Boolean` / `is Number`. Both refuse a JSON STRING that merely
         * spells one (`"true"`, `"5"`) — the coercion that dies with the swap.
         * Local to this file on purpose: JsonAccess has no boolean/binary64
         * PREDICATE (its `boolOr`/`wireIntOrNull` are keyed readers), and a
         * private member cannot collide with one being added there. */
        private fun isJsonBoolean(v: JsonElement?): Boolean =
            v is JsonPrimitive && !v.isString && v.content.toBooleanStrictOrNull() != null

        private fun jsonNumberOrNull(v: JsonElement?): Double? =
            (v as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toDoubleOrNull()
    }

    private fun authoredValue(node: JsonObject): JsonElement? = authoredValueOf(node)
}
