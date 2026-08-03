// SPDX-License-Identifier: GPL-3.0-or-later
// SurfaceSpec validation (SPEC 16-17 receiver duties): the whole document
// validates before any persistent or visible state changes (SPEC 13.2).
// Rejection carries the failing object path for error.data.path.
//
// What rejects (SPEC 16.1): a malformed node, missing or wrong-typed
// required member, invalid action descriptor, duplicate authored ID, an
// authored password seed, an authored single_line value containing U+000A
// (SPEC 17.4), or a resource-limit violation (SPEC 4.5: node count,
// per-node children, capture_fields). What does NOT reject: unknown node
// types (SPEC 16.2 degrade) and unknown optional fields (SPEC 16.3) —
// those are the receiver's tolerance duties.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

class ContentInvalid(val path: String, val reason: String) :
    Exception("$reason at $path")

/**
 * org.json's `opt(k) !in SET_OF_STRINGS` membership test, which decided that
 * a non-string value was simply not a member. Preserved: a number, an object,
 * or JSON null in an enum position is not one of the listed spellings.
 * (JsonAccess carries the readers; this is a validator idiom over them.)
 */
private fun JsonElement?.isOneOf(allowed: Set<String>): Boolean {
    val s = this?.asStringOrNull()
    return s != null && s in allowed
}

private val IDENTIFIER = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]*")

// SPEC 17.5: month_grid calendar formats (zero-padded, so string order is
// chronological order for the min/max bound check).
private val YYYY_MM = Regex("\\d{4}-(0[1-9]|1[0-2])")
private val YYYY_MM_DD = Regex("\\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\\d|3[01])")

// SPEC 17.7: a ToolbarItem carries exactly one primary operation.
private val TOOLBAR_OPS = setOf("snippet", "on_tap", "menu", "command", "line")
// SPEC 17.7 (amendment #61): the ${input:...} placeholder — at most one per snippet.
private val INPUT_TOKEN = Regex("""\$\{input:""")
private val TOOLBAR_PLACEMENTS = setOf("cursor", "line-start", "block")

// SPEC 17.5: the closed canvas-op shapes — required members per known op.
// An UNKNOWN op is skipped at render, never rejected (SPEC 17.5).
private val CANVAS_OPS: Map<String, List<String>> = mapOf(
    "line" to listOf("x1", "y1", "x2", "y2"),
    "rect" to listOf("x", "y", "width", "height"),
    "circle" to listOf("cx", "cy", "radius"),
    "path" to listOf("points"),
    "text" to listOf("x", "y", "text"),
)

// SPEC 14.3: the members each value-producing hook injects into a copy of
// `args`. A remote descriptor on such a hook MUST NOT author a conflicting
// member — that makes the containing surface invalid.
private val INJECTED_MEMBERS: Map<String, Set<String>> = mapOf(
    "on_change" to setOf("value"),
    "on_submit" to setOf("value"),
    "on_save" to setOf("value"),
    "on_enter" to setOf("value"),
    "on_pick" to setOf("value"),
    "on_day_tap" to setOf("value"),
    "on_month_change" to setOf("value"),
    "on_point_tap" to setOf("value", "index"),
    "on_reorder" to setOf("from", "to", "order"),
    "on_add_row" to setOf("index"),
    "on_add_col" to setOf("index"),
    "swipe_start.on_trigger" to setOf("direction"),
    "swipe_end.on_trigger" to setOf("direction"),
)

object SpecValidator {

    /**
     * One traversal's mutable state. `captureRefs` defers `capture_fields`
     * resolution until the whole document is walked, because a named node
     * may appear after the descriptor that captures it (SPEC 14.1).
     */
    private class Ctx(
        val maxCaptureFields: Long,
        val maxChartPoints: Long,
        val maxCanvasOps: Long,
        val maxRichSpans: Long,
        val maxTableCells: Long,
        // SPEC 17.1: a node type absent from the TARGET profile's advertised
        // node_types is treated as unsupported (§16.2 degrade), even though it
        // is a known contract type. null = allow all (unit tests / golden corpus).
        val advertisedTypes: Set<String>?,
        // SPEC 14.2 (LD-17): a builtin absent from the target's advertised
        // builtins is an INVALID CONTEXT — unlike a node type it does not
        // degrade, it rejects the containing document. null = allow all.
        val advertisedBuiltins: Set<String>? = null,
    ) {
        val ids = mutableSetOf<String>()
        val statefuls = mutableMapOf<String, JsonObject>()
        val captureRefs = mutableListOf<Pair<String, List<String>>>()
        var nodeCount = 0
        // SPEC 4.5: max_rich_spans / max_table_cells are AGGREGATE counts
        // across one SurfaceSpec or dialog document, like max_chart_points.
        var richSpans = 0L
        var tableCells = 0L
        // SPEC 4.5/16.1 (amendment #108): node nesting depth.
        var nodeDepth = 0
    }

    /** Validate one SurfaceSpec; returns the stateful nodes by ID. The chart/
     * canvas count limits default high so unit tests and the golden corpus
     * pass; the engine passes the profile's real §4.5 values. */
    fun validateSurfaceSpec(
        spec: JsonElement?,
        path: String = "spec",
        maxCaptureFields: Long = 64,
        maxChartPoints: Long = Long.MAX_VALUE,
        maxCanvasOps: Long = Long.MAX_VALUE,
        maxRichSpans: Long = Long.MAX_VALUE,
        maxTableCells: Long = Long.MAX_VALUE,
        advertisedTypes: Set<String>? = null,
        advertisedBuiltins: Set<String>? = null,
    ): Map<String, JsonObject> {
        if (spec !is JsonObject) throw ContentInvalid(path, "spec must be an object")
        val ctx = Ctx(maxCaptureFields, maxChartPoints, maxCanvasOps,
            maxRichSpans, maxTableCells, advertisedTypes, advertisedBuiltins)
        if ("views" in spec) {
            val views = spec.objOrNull("views")
                ?: throw ContentInvalid("$path.views", "views must be an object")
            if (views.size == 0)
                throw ContentInvalid("$path.views", "views must be non-empty")
            val initial = spec.stringOrNull("initial_view")
            if (initial == null || initial !in views)
                throw ContentInvalid("$path.initial_view", "must name an existing view")
            for ((name, view) in views) {
                if (view !is JsonObject || view.stringOrNull("t") == null)
                    throw ContentInvalid("$path.views.$name", "each view must be a node")
                walkNode(view, "$path.views.$name", ctx)
            }
        } else {
            // SPEC 16.1: a single-view surface root is itself a node.
            if (spec.stringOrNull("t") == null)
                throw ContentInvalid(path, "surface root must be a node or a multi-view object")
            walkNode(spec, path, ctx)
        }
        // SPEC 14.1: each capture name resolves to exactly one stateful node
        // in the document. IDs are unique across the document (SPEC 16.1),
        // so membership in `statefuls` is the exact resolution test.
        for ((refPath, names) in ctx.captureRefs)
            for ((i, name) in names.withIndex())
                if (!ctx.statefuls.containsKey(name))
                    throw ContentInvalid("$refPath.capture_fields[$i]",
                        "must name a stateful node in the document")
        return ctx.statefuls
    }

    /**
     * SPEC 13.2 `reset_input_ids`: distinct, naming non-password stateful
     * nodes in the submitted spec; a synchronized editor never appears.
     */
    fun validateResetIds(resetIds: JsonArray, statefuls: Map<String, JsonObject>): Set<String> {
        val out = mutableSetOf<String>()
        for (i in resetIds.indices) {
            val id = resetIds[i].asStringOrNull()
                ?: throw ContentInvalid("reset_input_ids[$i]", "must be a widget ID")
            if (!out.add(id))
                throw ContentInvalid("reset_input_ids[$i]", "duplicate ID")
            val node = statefuls[id]
                ?: throw ContentInvalid("reset_input_ids[$i]", "not a stateful node in spec")
            if (node.boolOr("password"))
                throw ContentInvalid("reset_input_ids[$i]", "password nodes cannot be reset")
            if (node.reqString("t") == "editor" && "document" in node)
                throw ContentInvalid("reset_input_ids[$i]",
                    "synchronized editor text changes only through Section 19")
        }
        return out
    }

    /** SPEC 13.5: `stale_spec` carries no stateful node and no editor. */
    fun validateStaleSpec(staleSpec: JsonElement?, primaryIsMultiView: Boolean,
                          maxCaptureFields: Long = 64,
                          maxChartPoints: Long = Long.MAX_VALUE,
                          maxCanvasOps: Long = Long.MAX_VALUE,
                          maxRichSpans: Long = Long.MAX_VALUE,
                          maxTableCells: Long = Long.MAX_VALUE,
                          advertisedTypes: Set<String>? = null,
                          advertisedBuiltins: Set<String>? = null) {
        val statefuls = validateSurfaceSpec(staleSpec, "stale_spec",
            maxCaptureFields, maxChartPoints, maxCanvasOps,
            maxRichSpans, maxTableCells, advertisedTypes, advertisedBuiltins)
        if (statefuls.isNotEmpty())
            throw ContentInvalid("stale_spec", "stateful nodes are prohibited in stale_spec")
        if (("views" in (staleSpec as JsonObject)) != primaryIsMultiView)
            throw ContentInvalid("stale_spec", "must use the same variant as spec")
        if (containsEditor(staleSpec))
            throw ContentInvalid("stale_spec", "editor nodes are prohibited in stale_spec")
    }

    /**
     * SPEC 13.4/18.5: a notification surface spec is `{body: Node, meta?}`,
     * never a multi-view object. The body is a node tree; meta is the
     * optional §18.5 metadata (channel, ongoing, category, priority,
     * chronometer, actions). Notification surfaces have no input drafts,
     * so nothing is returned.
     */
    fun validateNotificationSpec(spec: JsonElement?, path: String = "spec",
                                 maxCaptureFields: Long = 64,
                                 advertisedTypes: Set<String>? = null,
                                 advertisedBuiltins: Set<String>? = null,
                                 maxChartPoints: Long = Long.MAX_VALUE,
                                 maxCanvasOps: Long = Long.MAX_VALUE,
                                 maxRichSpans: Long = Long.MAX_VALUE,
                                 maxTableCells: Long = Long.MAX_VALUE) {
        if (spec !is JsonObject) throw ContentInvalid(path, "must be an object")
        if ("views" in spec) throw ContentInvalid(path, "multi-view prohibited")
        for (k in spec.keys) if (k != "body" && k != "meta")
            throw ContentInvalid("$path.$k", "unknown notification member")
        val body = spec["body"]
        if (body !is JsonObject || body.stringOrNull("t") == null)
            throw ContentInvalid("$path.body", "must be a node")
        // SPEC 17.1: gate the body to the notification profile's node_types.
        validateSurfaceSpec(body, "$path.body", maxCaptureFields,
            maxChartPoints = maxChartPoints, maxCanvasOps = maxCanvasOps,
            maxRichSpans = maxRichSpans, maxTableCells = maxTableCells,
            advertisedTypes = advertisedTypes, advertisedBuiltins = advertisedBuiltins)
        if ("meta" in spec) {
            val meta = spec.objOrNull("meta")
                ?: throw ContentInvalid("$path.meta", "must be an object")
            validateNotificationMeta(meta, "$path.meta")
        }
    }

    private val PRIORITIES = setOf("min", "low", "default", "high", "max")

    private fun validateNotificationMeta(meta: JsonObject, path: String) {
        val allowed = setOf("channel", "ongoing", "category", "priority",
            "chronometer", "actions")
        for (k in meta.keys) if (k !in allowed)
            throw ContentInvalid("$path.$k", "unknown meta member")
        // A non-null map read IS the presence test now, so the old
        // `opt(k)?.takeIf { has(k) }` pairing collapses into one lookup. An
        // explicit JSON null still REJECTS — org.json's opt handed back its
        // NULL sentinel, which failed the `is String` test, and JsonNull
        // fails the string reader the same way.
        meta["channel"]?.let {
            val s = it.asStringOrNull()
            if (s == null || !IDENTIFIER.matches(s))
                throw ContentInvalid("$path.channel", "must be an identifier")
        }
        meta["category"]?.let {
            val s = it.asStringOrNull()
            if (s == null || !IDENTIFIER.matches(s))
                throw ContentInvalid("$path.category", "must be an identifier")
        }
        if ("ongoing" in meta && meta.boolOrNull("ongoing") == null)
            throw ContentInvalid("$path.ongoing", "must be a boolean")
        if ("priority" in meta && !meta["priority"].isOneOf(PRIORITIES))
            throw ContentInvalid("$path.priority", "min|low|default|high|max")
        meta.objOrNull("chronometer")?.let { chrono ->
            // SPEC 4.3/18.5: base_ms is a non-negative epoch-millis INTEGER,
            // not any Number (a fractional or negative timestamp is invalid).
            val base = chrono["base_ms"]?.asDoubleOrNull()
            if (base == null || base != Math.floor(base) || base < 0)
                throw ContentInvalid("$path.chronometer.base_ms",
                    "must be a non-negative epoch-millis integer")
            if ("count_down" in chrono && chrono.boolOrNull("count_down") == null)
                throw ContentInvalid("$path.chronometer.count_down", "must be a boolean")
        }
        meta.arrOrNull("actions")?.let { actions ->
            for (i in actions.indices) {
                val a = actions[i] as? JsonObject
                    ?: throw ContentInvalid("$path.actions[$i]", "must be an object")
                validateNotificationAction(a, "$path.actions[$i]")
            }
        }
    }

    private fun validateNotificationAction(a: JsonObject, path: String) {
        val allowed = setOf("label", "on_tap", "icon", "dismiss", "input")
        for (k in a.keys) if (k !in allowed)
            throw ContentInvalid("$path.$k", "unknown action member")
        val label = a.stringOrNull("label")
        if (label == null || label.isEmpty())
            throw ContentInvalid("$path.label", "non-empty string required")
        val onTap = a.objOrNull("on_tap")
            ?: throw ContentInvalid("$path.on_tap", "required")
        // SPEC 14.2/18.5: a notification action's on_tap MUST be a remote
        // ActionDescriptor — the notification profile advertises no builtins and
        // there is no context-less builtin execution path, so a builtin on_tap
        // would validate but throw at tap time.
        if ("builtin" in onTap)
            throw ContentInvalid("$path.on_tap", "notification action must be a remote action, not a builtin")
        // LD-19: identifiers carry the SPEC 4.4/4.5 128-octet bound, not
        // just the grammar — this is the node-id check applied to the two
        // sites that missed it (icon here, input.key below).
        if ("icon" in a) {
            val icon = a.stringOrNull("icon")
            if (icon == null || !IDENTIFIER.matches(icon) ||
                icon.toByteArray(Charsets.UTF_8).size > WireLimits.MAX_IDENTIFIER_OCTETS)
                throw ContentInvalid("$path.icon", "must be an identifier")
        }
        val dismiss = a.boolOrNull("dismiss")
        if ("dismiss" in a && dismiss == null)
            throw ContentInvalid("$path.dismiss", "must be a boolean")
        val hasInput = "input" in a
        if (hasInput) {
            val input = a.objOrNull("input")
                ?: throw ContentInvalid("$path.input", "must be an object")
            for (k in input.keys) if (k != "hint" && k != "key")
                throw ContentInvalid("$path.input.$k", "unknown input member")
            if ("hint" in input && input.stringOrNull("hint") == null)
                throw ContentInvalid("$path.input.hint", "must be a string")
            if ("key" in input) {
                val key = input.stringOrNull("key")
                if (key == null || !IDENTIFIER.matches(key) ||
                    key.toByteArray(Charsets.UTF_8).size > WireLimits.MAX_IDENTIFIER_OCTETS)
                    throw ContentInvalid("$path.input.key", "must be an identifier")
            }
        }
        // SPEC 18.5: when input or dismiss:true is present, on_tap MUST be
        // a remote ActionDescriptor; an inline reply MUST NOT capture_fields.
        val requiresRemote = hasInput || dismiss == true
        val isRemote = "action" in onTap && "builtin" !in onTap
        if (requiresRemote && !isRemote)
            throw ContentInvalid("$path.on_tap", "must be a remote action for input/dismiss")
        if (hasInput && "capture_fields" in onTap)
            throw ContentInvalid("$path.on_tap", "an inline reply must not capture_fields")
        // SPEC 14.1/14.2: validate the descriptor itself with the SAME rules
        // the surface path uses — exactly-one action/builtin, a dotted action
        // name, a known offline policy, ttl_s only for queue/wake and in
        // 1..604800, no ttl_s/dedupe on drop, and a globally-known builtin.
        if (("action" in onTap) == ("builtin" in onTap))
            throw ContentInvalid("$path.on_tap", "exactly one of action/builtin")
        if ("action" in onTap) {
            val name = onTap.stringOrNull("action")
                ?: throw ContentInvalid("$path.on_tap.action", "must be a string")
            if ('.' !in name)
                throw ContentInvalid("$path.on_tap.action", "action names contain a dot")
            // org.json's `optString(k, d)` folded ABSENT and explicit JSON null
            // into the default but STRINGIFIED anything else BEFORE the
            // whitelist test, so `when_offline: 5` read as "5" and rejected.
            // `stringOr` would fold that 5 into the default and let it pass —
            // looser, not stricter — so the read is spelled out here: the fold
            // for null/absent, a refusal for a present non-string.
            val policy = if (onTap.isNullOrAbsent("when_offline")) OFFLINE_DEFAULT
                         else onTap.stringOrNull("when_offline")
            if (policy == null || policy !in OFFLINE_POLICIES)
                throw ContentInvalid("$path.on_tap.when_offline", "unknown offline policy")
            if (policy in setOf("queue", "wake") && "ttl_s" !in onTap)
                throw ContentInvalid("$path.on_tap", "$policy requires ttl_s")
            if (policy == "drop" && ("ttl_s" in onTap || "dedupe" in onTap))
                throw ContentInvalid("$path.on_tap", "ttl_s/dedupe are invalid for drop")
            if ("ttl_s" in onTap) {
                // Read as binary64, not as an integer: `ttl_s: 60.0` from an
                // older peer is accepted traffic (PreSwapNumberTest pins it),
                // and the integrality rule is the floor test below.
                val d = onTap["ttl_s"]?.asDoubleOrNull()
                    ?: throw ContentInvalid("$path.on_tap.ttl_s", "must be an integer 1..604800")
                if (d != Math.floor(d) || d.isInfinite() || d < 1.0 || d > 604800.0)
                    throw ContentInvalid("$path.on_tap.ttl_s", "must be an integer 1..604800")
            }
        } else {
            val name = onTap.stringOrNull("builtin")
                ?: throw ContentInvalid("$path.on_tap.builtin", "must be a string")
            if (name !in ACTION_SCHEMA)
                throw ContentInvalid("$path.on_tap.builtin", "unknown builtin $name")
        }
    }

    private fun containsEditor(value: JsonElement?): Boolean = when (value) {
        is JsonObject -> value["t"]?.asStringOrNull() == "editor" ||
            value.values.any { containsEditor(it) }
        is JsonArray -> value.any { containsEditor(it) }
        else -> false
    }

    // ------------------------------------------------------------ walking

    /**
     * Generic descent for a value that is not itself a schema-declared node
     * position: descends arbitrary structure to validate nested nodes and
     * the action descriptors on container items (menu/tab/table entries).
     * The strict node-position rules live in [walkNode].
     */
    private fun walkValue(value: JsonElement, path: String, ctx: Ctx) {
        when (value) {
            is JsonArray ->
                for (i in value.indices)
                    walkValue(value[i], "$path[$i]", ctx)
            is JsonObject ->
                if (value.stringOrNull("t") != null) {
                    walkNode(value, path, ctx)
                } else {
                    for ((key, child) in value) {
                        if (key in ACTION_HOOK_KEYS && child is JsonObject)
                            validateAction(child, "$path.$key", key, ctx)
                        else if ((key == "swipe_start" || key == "swipe_end") && child is JsonObject)
                            validateSwipeSide(child, "$path.$key", key, ctx)
                        else walkValue(child, "$path.$key", ctx)
                    }
                }
            else -> Unit // scalars carry no schema
        }
    }

    private fun walkNode(node: JsonObject, path: String, ctx: Ctx) {
        // SPEC 4.5: at most 10,000 nodes in one surface snapshot; count
        // before descending so an over-limit tree rejects, not renders.
        if (++ctx.nodeCount > WireLimits.MAX_NODES_PER_SNAPSHOT)
            throw ContentInvalid(path, "exceeds max_nodes_per_snapshot")
        // SPEC 4.5/16.1 (amendment #108): and at most 20 levels deep — the
        // receiver's JSON-container limit is not a budget a sender can spend,
        // because host encoders cap well below it.
        if (++ctx.nodeDepth > WireLimits.MAX_NODE_DEPTH) {
            ctx.nodeDepth--
            throw ContentInvalid(path, "node-depth")
        }
        try {
        validateNode(node, path, ctx)
        // SPEC 16.2: unknown node types degrade — their subtrees are scanned
        // for nested known nodes but not held to per-type structural rules.
        val t = node.stringOr("t")
        // SPEC 17.1/16.2: a known type absent from the target profile degrades
        // exactly like an unknown type — its subtree is scanned but its per-type
        // hooks/schema are not applied and it dispatches nothing.
        val known = NODE_SCHEMA.containsKey(t) &&
            (ctx.advertisedTypes == null || t in ctx.advertisedTypes)
        for ((key, child) in node) {
            when {
                known && key in ACTION_HOOK_KEYS -> {
                    // SPEC 17.1: an `on_*` member is an ActionDescriptor.
                    if (child !is JsonObject)
                        throw ContentInvalid("$path.$key", "action descriptor must be an object")
                    validateAction(child, "$path.$key", key, ctx)
                }
                known && (key == "swipe_start" || key == "swipe_end") -> {
                    if (child !is JsonObject)
                        throw ContentInvalid("$path.$key", "swipe side must be an object")
                    validateSwipeSide(child, "$path.$key", key, ctx)
                }
                known && key == "children" -> {
                    // SPEC 17.1: `children` is an array of Nodes. SPEC 4.5:
                    // at most 10,000 children of one node.
                    val arr = child as? JsonArray
                        ?: throw ContentInvalid("$path.children", "children must be an array of nodes")
                    if (arr.size > WireLimits.MAX_CHILDREN_PER_NODE)
                        throw ContentInvalid("$path.children", "exceeds max_children_per_node")
                    for (i in arr.indices) {
                        val el = arr[i] as? JsonObject
                            ?: throw ContentInvalid("$path.children[$i]", "child must be a node object")
                        if (el.stringOrNull("t") == null)
                            throw ContentInvalid("$path.children[$i]", "child node missing discriminator t")
                        walkNode(el, "$path.children[$i]", ctx)
                    }
                }
                else -> walkValue(child, "$path.$key", ctx)
            }
        }
        } finally { ctx.nodeDepth-- }
    }

    /** LD-10: enforce the contract FIELD_TYPES for the scalar categories.
     * Complex types (node/array/object/enum/varies-per-node) return without
     * a check — their dedicated validators run separately.
     *
     * The caller has already established that MEMBER is present, so the keyed
     * JsonAccess readers are exactly the old `opt(member) as? T` casts. */
    private fun checkScalarFieldType(t: String, member: String, node: JsonObject, path: String) {
        val p = "$path.$member"
        fun bad(want: String): Nothing = throw ContentInvalid(p, "$member must be $want")
        when (FIELD_TYPES[member]) {
            "boolean" -> if (node.boolOrNull(member) == null) bad("a boolean")
            "string", "yyyy-mm" -> if (node.stringOrNull(member) == null) bad("a string")
            "identifier" -> node.stringOrNull(member).let {
                if (it == null || !IDENTIFIER.matches(it) ||
                    it.toByteArray(Charsets.UTF_8).size > WireLimits.MAX_IDENTIFIER_OCTETS)
                    bad("an identifier")
            }
            "color" -> if (node.stringOrNull(member) == null) bad("a color string")
            "string-or-number" ->
                if (node.stringOrNull(member) == null &&
                    node[member]?.asDoubleOrNull() == null) bad("a string or number")
            "dp", "number" -> node[member]?.asDoubleOrNull().let {
                if (it == null || it.isInfinite() || it.isNaN()) bad("a finite number")
            }
            "non-negative-integer" ->
                if ((integralLongOrNull(node[member]) ?: -1) < 0) bad("a non-negative integer")
            "positive-integer" ->
                if ((integralLongOrNull(node[member]) ?: 0) < 1) bad("a positive integer")
            "integer-1-12" -> if (integralLongOrNull(node[member])
                    .let { it == null || it < 1 || it > 12 })
                bad("an integer 1..12")
            "integer-1-31" -> if (integralLongOrNull(node[member])
                    .let { it == null || it < 1 || it > 31 })
                bad("an integer 1..31")
            else -> Unit // enum, font-weight, varies-per-node, and complex types
        }
    }

    private fun validateNode(node: JsonObject, path: String, ctx: Ctx) {
        val t = node.stringOrNull("t")
            ?: throw ContentInvalid(path, "node discriminator t must be a string")
        // SPEC 16.1: every authored node ID is unique across the document.
        node.stringOrNull("id")?.let { id ->
            if (!IDENTIFIER.matches(id) ||
                id.toByteArray(Charsets.UTF_8).size > WireLimits.MAX_IDENTIFIER_OCTETS)
                throw ContentInvalid("$path.id", "invalid identifier")
            if (!ctx.ids.add(id))
                throw ContentInvalid("$path.id", "duplicate node ID")
        }
        // SPEC 17.1: a type absent from the target profile is unsupported —
        // degrade like an unknown type (skip required members, per-type schema,
        // and stateful registration; the renderer renders its children only).
        if (ctx.advertisedTypes != null && t !in ctx.advertisedTypes) return
        val row = NODE_SCHEMA[t] ?: return // SPEC 16.2: unknown types degrade
        for (req in row.required)
            if (req !in node)
                throw ContentInvalid(path, "$t missing required $req")
        // LD-10: type-check each type-specific member against the contract's
        // FIELD_TYPES, for the coercion-prone SCALAR categories. A DEFAULTING
        // reader still cannot make this distinction after the swap:
        // `boolOr("enabled", true)` returns the DEFAULT for `enabled: 0`,
        // rendering a disabled node enabled, and `stringOr("title", "")`
        // turns `title: {...}` into an empty heading. (Half of the old hazard
        // did die with org.json — a defaulting read no longer stringifies the
        // object INTO the heading, and `boolOr("password", …)` no longer
        // accepts the string "true" — but the read is silent either way,
        // which is what this check exists to stop.) Scoped to members this
        // node's schema lists (so richer-grammar universal attrs are
        // untouched) and to scalar types (enum has §16.3 fallback semantics,
        // and node/array/object/varies-per-node members have dedicated
        // validators below).
        //
        // C3 scope caveat, recorded rather than papered over: because this
        // check is schema-scoped, it does NOT back-stop the two `boolOr`
        // reads on members absent from the node's own schema row —
        // `password` read off a non-text_input stateful (validateResetIds)
        // and `single_line` read off an `editor` (validateLineCounts). At
        // exactly those two sites the dropped string coercion is a LOOSENING,
        // not a tightening: `password: "true"` on a slider used to block a
        // reset and no longer does. Both inputs are spec-invalid extra
        // members that §16.3 tells a receiver to ignore anyway, so the
        // practical blast radius is nil — but the "already type-checked
        // first" justification does not cover them, and a future reader
        // should not assume it does.
        for (member in row.required + row.optional)
            if (member in node) checkScalarFieldType(t, member, node, path)
        when (t) {
            "text_input" -> {
                val value = node["value"]
                if (value != null && value.asStringOrNull() == null)
                    throw ContentInvalid("$path.value", "text_input value must be a string")
                val text = value?.asStringOrNull()
                // SPEC 17.4: single_line prohibits U+000A in authored values.
                if (node.boolOr("single_line") && text != null && '\n' in text)
                    throw ContentInvalid("$path.value", "single_line value contains U+000A")
                // SPEC 17.4: a snapshot must not seed a password.
                if (node.boolOr("password") &&
                    (text != null && text.isNotEmpty() || "on_change" in node))
                    throw ContentInvalid(path, "password nodes cannot seed values or publish state")
                validateLineCounts(node, path)
            }
            "slider" -> {
                val values = node.arrOrNull("values")
                if (values != null) {
                    if ("min" in node || "max" in node)
                        throw ContentInvalid(path, "discrete slider must omit min and max")
                    if (values.size < 2)
                        throw ContentInvalid("$path.values", "at least two discrete values")
                    var prev = Double.NEGATIVE_INFINITY
                    for (i in values.indices) {
                        val n = values[i].asDoubleOrNull()
                            ?: throw ContentInvalid("$path.values[$i]", "must be a number")
                        if (n <= prev)
                            throw ContentInvalid("$path.values", "must be strictly increasing")
                        prev = n
                    }
                    // SPEC 17.4: a discrete value must equal one listed number
                    // (Section 4.3 numeric equality); default is the first.
                    if ("value" in node) {
                        val v = node.getValue("value")
                        if (v.asDoubleOrNull() == null)
                            throw ContentInvalid("$path.value", "must be a number")
                        // The element itself goes to jsonValueEquals now — the
                        // §4.3 comparison is over JSON values, and it compares
                        // numbers BY VALUE, so `2` still matches a listed `2.0`.
                        val listed = values.any { jsonValueEquals(it, v) }
                        if (!listed)
                            throw ContentInvalid("$path.value", "must equal a listed discrete value")
                    }
                    if ("value_end" in node) {
                        val v = node.getValue("value_end")
                        if (v.asDoubleOrNull() == null)
                            throw ContentInvalid("$path.value_end", "must be a number")
                        if (values.none { jsonValueEquals(it, v) })
                            throw ContentInvalid("$path.value_end", "must equal a listed discrete value")
                    }
                } else {
                    val min = node["min"]?.asDoubleOrNull() ?: 0.0
                    val max = node["max"]?.asDoubleOrNull() ?: 1.0
                    if (min >= max)
                        throw ContentInvalid(path, "slider min must be less than max")
                    // SPEC 17.4: a continuous value lies in the closed range.
                    if ("value" in node) {
                        val v = node["value"]?.asDoubleOrNull()
                            ?: throw ContentInvalid("$path.value", "must be a number")
                        if (v.isNaN() || v < min || v > max)
                            throw ContentInvalid("$path.value", "must be within min..max")
                    }
                    if ("value_end" in node) {
                        val v = node["value_end"]?.asDoubleOrNull()
                            ?: throw ContentInvalid("$path.value_end", "must be a number")
                        if (v.isNaN() || v < min || v > max)
                            throw ContentInvalid("$path.value_end", "must be within min..max")
                    }
                }
                // SPEC 17.4: both thumbs of a range keep their order.
                val start = node["value"]?.asDoubleOrNull()
                val end = node["value_end"]?.asDoubleOrNull()
                if (start != null && end != null && start > end)
                    throw ContentInvalid(path, "slider value must not exceed value_end")
            }
            "checkbox" -> {
                // SPEC 17.4/13.6: `state` and `checked` carry DIFFERENT value
                // schemas for the same id, so a node carrying both is content-
                // invalid rather than one silently outranking the other.
                if ("state" in node && "checked" in node)
                    throw ContentInvalid(path, "checkbox state and checked are mutually exclusive")
            }
            "split_button" -> {
                // SPEC 17.4: the leading half is a label, an icon, or both —
                // never neither (label left the required set for the icon-only
                // LeadingButton form, not for an empty one).
                if (node.stringOr("label").isEmpty() && node.stringOr("icon").isEmpty())
                    throw ContentInvalid(path, "split_button needs a label, an icon, or both")
            }
            "enum_list" -> {
                // SPEC 16.1: a wrong-typed required member rejects (1201),
                // it never crashes the session — so arrOrNull, not reqArr.
                val options = node.arrOrNull("options")
                    ?: throw ContentInvalid("$path.options", "options must be an array")
                val seen = mutableListOf<JsonElement>()
                for (i in options.indices) {
                    val opt = options[i] as? JsonObject
                        ?: throw ContentInvalid("$path.options[$i]", "must be an object")
                    if ("label" !in opt || "value" !in opt)
                        throw ContentInvalid("$path.options[$i]", "needs label and value")
                    if (seen.any { jsonValueEquals(it, opt.getValue("value")) })
                        throw ContentInvalid("$path.options[$i]", "duplicate option value")
                    seen.add(opt.getValue("value"))
                }
                // SPEC 17.4: unless allow_add, every selected value appears in
                // options; multi_select values are an array of distinct values.
                if ("value" in node && !node.isNullOrAbsent("value")) {
                    val allowAdd = node.boolOr("allow_add")
                    fun checkMember(v: JsonElement, p: String) {
                        if (!allowAdd && seen.none { jsonValueEquals(it, v) })
                            throw ContentInvalid(p, "selected value not in options")
                    }
                    if (node.boolOr("multi_select")) {
                        val arr = node["value"] as? JsonArray
                            ?: throw ContentInvalid("$path.value", "multi-select value must be an array")
                        val chosen = mutableListOf<JsonElement>()
                        for (i in arr.indices) {
                            val v = arr[i]
                            if (chosen.any { jsonValueEquals(it, v) })
                                throw ContentInvalid("$path.value[$i]", "duplicate selected value")
                            chosen.add(v)
                            checkMember(v, "$path.value[$i]")
                        }
                    } else {
                        if (node["value"] is JsonArray)
                            throw ContentInvalid("$path.value", "single-select value must be scalar")
                        checkMember(node.getValue("value"), "$path.value")
                    }
                }
            }
            "text" -> validatePositiveInt(node, "max_lines", path)
            "rich_text" -> validateSpans(node["spans"], "$path.spans", ctx)
            "empty_state" ->
                // SPEC 17.2: action_label and on_tap together or both absent.
                if (("action_label" in node) != ("on_tap" in node))
                    throw ContentInvalid(path,
                        "action_label and on_tap must appear together or both be absent")
            "progress" ->
                if ("value" in node) {
                    val v = node["value"]?.asDoubleOrNull()
                        ?: throw ContentInvalid("$path.value", "must be a number 0..1")
                    if (v.isNaN() || v < 0.0 || v > 1.0)
                        throw ContentInvalid("$path.value", "must be a number 0..1")
                }
            "date_stamp" -> {
                validateIntRange(node, "day", 1, 31, path)
                validateIntRange(node, "month_index", 1, 12, path)
                if ("year" in node) {
                    val y = node["year"]?.asDoubleOrNull()
                    if (y == null || y != Math.floor(y) || y < 0)
                        throw ContentInvalid("$path.year", "must be a non-negative integer")
                }
            }
            "reorderable_list" -> {
                // SPEC 17.3: every item has a unique key or id — else invalid.
                val items = node.arrOrNull("items")
                    ?: throw ContentInvalid("$path.items", "items must be an array")
                val keys = mutableSetOf<String>()
                for (i in items.indices) {
                    val item = items[i] as? JsonObject
                        ?: throw ContentInvalid("$path.items[$i]", "must be a node")
                    val k = item.stringOrNull("key") ?: item.stringOrNull("id")
                        ?: throw ContentInvalid("$path.items[$i]", "item needs a key or id")
                    if (!keys.add(k))
                        throw ContentInvalid("$path.items[$i]", "duplicate item key")
                }
            }
            "image" -> {
                // SPEC 17.2: no URI form is implicit — the url MUST be https or
                // a well-formed base64 data:image of a supported (non-active)
                // media type. Anything else (http, file, javascript:, svg,
                // malformed data:) is content-invalid. The per-form
                // advertisement gate and the SSRF/limit stack are runtime.
                if (!ImageGuards.isValidImageUrl(node.stringOr("url")))
                    throw ContentInvalid("$path.url",
                        "image url must be https or a supported base64 data:image")
            }
            "tabs" -> validateTabs(node, path)
            "table" -> validateTable(node, path, ctx)
            "chart" -> validateChart(node, path, ctx)
            "canvas" -> validateCanvas(node, path, ctx)
            "month_grid" -> validateMonthGrid(node, path)
            "editor" -> {
                validateLineCounts(node, path)
                val hasDocument = "document" in node
                // SPEC 17.4: complete:true requires document.
                if (node.boolOr("complete") && !hasDocument)
                    throw ContentInvalid(path, "complete requires document")
                if ("toolbar" in node)
                    validateToolbar(node["toolbar"], "$path.toolbar", hasDocument)
            }
        }
        if (t in STATEFUL_NODE_TYPES) {
            // SPEC 13.6: "a local `editor` draft requires publish_state: true
            // and no `document` in both snapshots. A synchronized editor never
            // participates in draft reconciliation." Registering a
            // synchronized editor as stateful let publishState write a
            // DURABLE draft for it (persisted, and reportable in the next
            // welcome's input_state) — the offline draft §19 forbids.
            // A `button`/`icon_button` is stateful only when it carries
            // `checked`: the toggle holds device state keyed on its id, while
            // a plain button holds none and MUST NOT be forced to carry an id
            // — every button already on the wire has none.
            val isStateful = when (t) {
                "editor" -> node.boolOr("publish_state") && "document" !in node
                "button", "icon_button" -> "checked" in node
                else -> true
            }
            if (isStateful) {
                val id = node.stringOrNull("id")
                    ?: throw ContentInvalid(path, "$t requires an id")
                ctx.statefuls[id] = node
            }
        }
    }

    // ------------------------------------------- per-type deep rules (17.x)

    /** SPEC 17.4: min_lines/max_lines are positive integers, min ≤ max, and
     * single_line:true requires both to equal 1. */
    private fun validateLineCounts(node: JsonObject, path: String) {
        validatePositiveInt(node, "min_lines", path)
        validatePositiveInt(node, "max_lines", path)
        // Compared as Long, never narrowed to Int. Pre-swap these read as
        // org.json Numbers and `toInt()` TRUNCATED the low 32 bits, so a
        // max_lines of 2^32 wrapped to 0 and made every min > max; routing the
        // same value through a Double instead would CLAMP to Int.MAX_VALUE and
        // invert that answer. Both are narrowing artifacts, not the rule —
        // §17.4 says min <= max — so the comparison is done at the width the
        // wire actually carries (the T1 parser bounds integers at 2^53-1).
        // C3 records this as a deliberate outcome change on absurd input:
        // values above 2^31 were previously judged by wraparound.
        val min = integralLongOrNull(node["min_lines"])
        val max = integralLongOrNull(node["max_lines"])
        if (min != null && max != null && min > max)
            throw ContentInvalid(path, "min_lines must not exceed max_lines")
        if (node.boolOr("single_line") &&
            ((min ?: 1L) != 1L || (max ?: 1L) != 1L))
            throw ContentInvalid(path, "single_line requires line counts of 1")
    }

    private fun validatePositiveInt(node: JsonObject, member: String, path: String) {
        if (member !in node) return
        val n = node[member]?.asDoubleOrNull()
        if (n == null || n != Math.floor(n) || n < 1)
            throw ContentInvalid("$path.$member", "must be a positive integer")
    }

    private fun validateIntRange(node: JsonObject, member: String, lo: Int, hi: Int, path: String) {
        if (member !in node) return
        val n = node[member]?.asDoubleOrNull()
        if (n == null || n != Math.floor(n) || n < lo || n > hi)
            throw ContentInvalid("$path.$member", "must be an integer $lo..$hi")
    }

    /** SPEC 17.2: a RichSpan MUST contain text: string. Every RichSpan in the
     * document — rich_text spans and table-cell spans alike — spends the
     * SPEC 4.5 aggregate max_rich_spans allowance. */
    private fun validateSpans(spans: JsonElement?, path: String, ctx: Ctx) {
        val arr = spans as? JsonArray
            ?: throw ContentInvalid(path, "must be an array of spans")
        ctx.richSpans += arr.size
        if (ctx.richSpans > ctx.maxRichSpans)
            throw ContentInvalid(path, "exceeds max_rich_spans")
        for (i in arr.indices) {
            val span = arr[i] as? JsonObject
                ?: throw ContentInvalid("$path[$i]", "must be a span object")
            if (span.stringOrNull("text") == null)
                throw ContentInvalid("$path[$i].text", "span text must be a string")
        }
    }

    /** SPEC 17.3: tabs arrays pair 1:1 and are non-empty; TabItem needs a
     * label; initial indexes the common count. */
    private fun validateTabs(node: JsonObject, path: String) {
        val items = node.arrOrNull("items")
            ?: throw ContentInvalid("$path.items", "items must be an array")
        val children = node.arrOrNull("children")
            ?: throw ContentInvalid("$path.children", "children must be an array")
        if (items.size == 0 || items.size != children.size)
            throw ContentInvalid(path, "items and children must have equal non-zero length")
        for (i in items.indices) {
            val item = items[i] as? JsonObject
                ?: throw ContentInvalid("$path.items[$i]", "must be a TabItem object")
            if (item.stringOrNull("label") == null)
                throw ContentInvalid("$path.items[$i].label", "TabItem label must be a string")
        }
        if ("initial" in node) {
            val init = node["initial"]?.asDoubleOrNull()
            if (init == null || init != Math.floor(init) ||
                init < 0 || init >= items.size)
                throw ContentInvalid("$path.initial", "must index the item count")
        }
    }

    /** SPEC 17.3: an unknown TableRow kind is invalid; data/header cells MUST
     * contain spans (RichSpan[]); aligns entries are start|center|end. */
    private fun validateTable(node: JsonObject, path: String, ctx: Ctx) {
        val rows = node.arrOrNull("rows")
            ?: throw ContentInvalid("$path.rows", "rows must be an array")
        for (i in rows.indices) {
            val row = rows[i] as? JsonObject
                ?: throw ContentInvalid("$path.rows[$i]", "must be a TableRow object")
            when (row["kind"]?.asStringOrNull()) {
                "rule" -> Unit
                "data", "header" -> {
                    val cells = row.arrOrNull("cells")
                        ?: throw ContentInvalid("$path.rows[$i].cells", "must be an array")
                    // SPEC 4.5: max_table_cells is an aggregate count across
                    // the document, spent by data and header cells.
                    ctx.tableCells += cells.size
                    if (ctx.tableCells > ctx.maxTableCells)
                        throw ContentInvalid("$path.rows[$i].cells", "exceeds max_table_cells")
                    for (j in cells.indices) {
                        val cell = cells[j] as? JsonObject
                            ?: throw ContentInvalid("$path.rows[$i].cells[$j]", "must be a cell object")
                        validateSpans(cell["spans"], "$path.rows[$i].cells[$j].spans", ctx)
                    }
                }
                else -> throw ContentInvalid("$path.rows[$i].kind", "unknown table row kind")
            }
        }
        node.arrOrNull("aligns")?.let { aligns ->
            for (i in aligns.indices)
                if (!aligns[i].isOneOf(setOf("start", "center", "end")))
                    throw ContentInvalid("$path.aligns[$i]", "must be start|center|end")
        }
    }

    /** SPEC 17.5: every ChartPoint is finite numeric x/y; y_range is a
     * two-number [min,max] with min < max; height is positive. */
    private fun validateChart(node: JsonObject, path: String, ctx: Ctx) {
        val series = node.arrOrNull("series")
            ?: throw ContentInvalid("$path.series", "series must be an array")
        var totalPoints = 0L
        for (i in series.indices) {
            val s = series[i] as? JsonObject
                ?: throw ContentInvalid("$path.series[$i]", "must be a series object")
            val points = s.arrOrNull("points")
                ?: throw ContentInvalid("$path.series[$i].points", "points must be an array")
            // SPEC 4.5: max_chart_points bounds the total across all series.
            totalPoints += points.size
            if (totalPoints > ctx.maxChartPoints)
                throw ContentInvalid("$path.series", "exceeds max_chart_points")
            for (j in points.indices) {
                val p = points[j] as? JsonObject
                    ?: throw ContentInvalid("$path.series[$i].points[$j]", "must be a point object")
                for (coord in listOf("x", "y")) {
                    val v = p[coord]?.asDoubleOrNull()
                    if (v == null || v.isNaN() || v.isInfinite())
                        throw ContentInvalid("$path.series[$i].points[$j].$coord",
                            "must be a finite number")
                }
            }
        }
        node.arrOrNull("y_range")?.let { r ->
            // getOrNull, not [0]: org.json's opt(i) answered null past the end
            // of the array, where a JsonArray index throws. The length check
            // below still runs on the same short arrays it did before.
            val lo = r.getOrNull(0)?.asDoubleOrNull()
            val hi = r.getOrNull(1)?.asDoubleOrNull()
            if (r.size != 2 || lo == null || hi == null || !(lo < hi))
                throw ContentInvalid("$path.y_range", "must be [min, max] with min < max")
        }
        if ("height" in node) {
            val h = node["height"]?.asDoubleOrNull()
            if (h == null || h.isNaN() || h <= 0)
                throw ContentInvalid("$path.height", "must be positive")
        }
    }

    /** SPEC 17.5: canvas dims are positive; KNOWN ops carry their closed
     * shape's required finite members (an unknown op is skipped at render,
     * never rejected); path points are exactly {x, y}. */
    private fun validateCanvas(node: JsonObject, path: String, ctx: Ctx) {
        for (dim in listOf("width", "height")) {
            val v = node[dim]?.asDoubleOrNull()
            if (v == null || v.isNaN() || v <= 0)
                throw ContentInvalid("$path.$dim", "must be positive")
        }
        val ops = node.arrOrNull("ops")
            ?: throw ContentInvalid("$path.ops", "ops must be an array")
        // SPEC 4.5: max_canvas_ops bounds the op count (unknown ops still count).
        if (ops.size.toLong() > ctx.maxCanvasOps)
            throw ContentInvalid("$path.ops", "exceeds max_canvas_ops")
        for (i in ops.indices) {
            val op = ops[i] as? JsonObject
                ?: throw ContentInvalid("$path.ops[$i]", "must be an op object")
            val kind = op.stringOrNull("op")
                ?: throw ContentInvalid("$path.ops[$i].op", "op discriminator required")
            val required = CANVAS_OPS[kind] ?: continue // unknown op: render-skip
            for (m in required) {
                if (m !in op)
                    throw ContentInvalid("$path.ops[$i]", "$kind missing required $m")
                if (m != "points" && m != "text") {
                    val v = op[m]?.asDoubleOrNull()
                    if (v == null || v.isNaN() || v.isInfinite())
                        throw ContentInvalid("$path.ops[$i].$m", "must be a finite number")
                }
            }
            if (kind == "path") {
                val pts = op.arrOrNull("points")
                    ?: throw ContentInvalid("$path.ops[$i].points", "must be an array")
                for (j in pts.indices) {
                    val p = pts[j] as? JsonObject
                        ?: throw ContentInvalid("$path.ops[$i].points[$j]", "must be {x, y}")
                    for (coord in listOf("x", "y")) {
                        val v = p[coord]?.asDoubleOrNull()
                        if (v == null || v.isNaN() || v.isInfinite())
                            throw ContentInvalid("$path.ops[$i].points[$j].$coord",
                                "must be a finite number")
                    }
                }
            }
            // SPEC 17.5: rect widths/heights, circle radii, stroke widths, and
            // a line op's width are non-negative.
            val nonNegative = when (kind) {
                "rect" -> listOf("width", "height", "stroke_width")
                "circle" -> listOf("radius", "stroke_width")
                "line" -> listOf("width")
                else -> listOf("stroke_width")
            }
            for (m in nonNegative) {
                if (m in op) {
                    val v = op[m]?.asDoubleOrNull()
                    if (v == null || v.isNaN() || v < 0)
                        throw ContentInvalid("$path.ops[$i].$m", "must be non-negative")
                }
            }
        }
    }

    /** SPEC 17.5: month formats, dots 0..3, min_month ≤ max_month. */
    private fun validateMonthGrid(node: JsonObject, path: String) {
        val month = node.stringOrNull("month")
        if (month == null || !YYYY_MM.matches(month))
            throw ContentInvalid("$path.month", "must be YYYY-MM")
        for (m in listOf("min_month", "max_month")) {
            node[m]?.let {
                val s = it.asStringOrNull()
                if (s == null || !YYYY_MM.matches(s))
                    throw ContentInvalid("$path.$m", "must be YYYY-MM")
            }
        }
        val lo = node.stringOrNull("min_month")
        val hi = node.stringOrNull("max_month")
        if (lo != null && hi != null && lo > hi)
            throw ContentInvalid(path, "min_month must not follow max_month")
        node["selected"]?.let {
            val s = it.asStringOrNull()
            if (s == null || !YYYY_MM_DD.matches(s))
                throw ContentInvalid("$path.selected", "must be YYYY-MM-DD")
        }
        node.objOrNull("marks")?.let { marks ->
            for ((key, value) in marks) {
                if (!YYYY_MM_DD.matches(key))
                    throw ContentInvalid("$path.marks.$key", "keys must be YYYY-MM-DD")
                val mark = value as? JsonObject
                    ?: throw ContentInvalid("$path.marks.$key", "must be an object")
                val dots = mark["dots"]?.asDoubleOrNull()
                if (dots == null || dots != Math.floor(dots) || dots < 0 || dots > 3)
                    throw ContentInvalid("$path.marks.$key.dots", "must be an integer 0..3")
            }
        }
    }

    /**
     * SPEC 17.7: editor.toolbar is a registered identifier (profile-features
     * gating happens at the engine's profile check) or an array of
     * ToolbarItems: label or icon, exactly one primary operation, `menu` of
     * non-menu items, `long_press` exactly one non-menu operation, placement
     * from the closed set. An unrecognized `line` VALUE is a render no-op,
     * never a reject. A `command` op requires a synchronized editor
     * (document present).
     */
    private fun validateToolbar(toolbar: JsonElement?, path: String, hasDocument: Boolean) {
        val named = toolbar?.asStringOrNull()
        if (named != null) {
            if (!IDENTIFIER.matches(named))
                throw ContentInvalid(path, "must be a toolbar identifier or item array")
            return
        }
        val items = toolbar as? JsonArray
            ?: throw ContentInvalid(path, "must be a toolbar identifier or item array")
        for (i in items.indices)
            validateToolbarItem(items[i] as? JsonObject
                ?: throw ContentInvalid("$path[$i]", "must be a ToolbarItem object"),
                "$path[$i]", hasDocument, allowMenu = true)
    }

    private fun validateToolbarItem(item: JsonObject, path: String,
                                    hasDocument: Boolean, allowMenu: Boolean,
                                    // SPEC 17.7: `long_press` is "exactly one
                                    // non-menu OPERATION" — an op plist, not a
                                    // nested item, so it carries no label/icon.
                                    // Requiring one here rejected every toolbar
                                    // whose long-press was authored to spec
                                    // (found by the JA-5 device gate: the org
                                    // toolbar's [%] and <${date}> variants).
                                    isLongPress: Boolean = false) {
        if (!isLongPress && "label" !in item && "icon" !in item)
            throw ContentInvalid(path, "ToolbarItem needs label or icon")
        val ops = TOOLBAR_OPS.filter { it in item }
        if (ops.size != 1)
            throw ContentInvalid(path, "exactly one primary operation required")
        val op = ops.single()
        if (op == "menu" && !allowMenu)
            throw ContentInvalid(path, "menu items must carry non-menu operations")
        when (op) {
            "menu" -> {
                val sub = item.arrOrNull("menu")
                    ?: throw ContentInvalid("$path.menu", "must be an array of items")
                for (j in sub.indices)
                    validateToolbarItem(sub[j] as? JsonObject
                        ?: throw ContentInvalid("$path.menu[$j]", "must be a ToolbarItem"),
                        "$path.menu[$j]", hasDocument, allowMenu = false)
            }
            "command" -> {
                val c = item.stringOrNull("command")
                if (c == null || !IDENTIFIER.matches(c))
                    throw ContentInvalid("$path.command", "must be an identifier")
                // SPEC 17.4: a toolbar command requires document.
                if (!hasDocument)
                    throw ContentInvalid("$path.command", "command requires document")
            }
            "snippet" -> {
                val snippet = item.stringOrNull("snippet")
                    ?: throw ContentInvalid("$path.snippet", "must be a string")
                // SPEC 17.7 (amendment #61): at most one ${input:...} token.
                if (INPUT_TOKEN.findAll(snippet).count() > 1)
                    throw ContentInvalid("$path.snippet",
                        "at most one \${input:...} token per snippet")
            }
            "line" -> if (item.stringOrNull("line") == null)
                throw ContentInvalid("$path.line", "must be a string")
            // on_tap descriptors are validated by the generic walk.
        }
        if ("placement" in item && !item["placement"].isOneOf(TOOLBAR_PLACEMENTS))
            throw ContentInvalid("$path.placement", "must be cursor|line-start|block")
        if ("long_press" in item) {
            val lp = item.objOrNull("long_press")
                ?: throw ContentInvalid("$path.long_press", "must be an object")
            validateToolbarItem(lp, "$path.long_press", hasDocument,
                allowMenu = false, isLongPress = true)
        }
    }

    private fun validateSwipeSide(side: JsonObject, path: String, sideKey: String, ctx: Ctx) {
        if ("label" !in side || "on_trigger" !in side)
            throw ContentInvalid(path, "swipe side needs label and on_trigger")
        val trigger = side.objOrNull("on_trigger")
            ?: throw ContentInvalid("$path.on_trigger", "must be an ActionDescriptor")
        validateAction(trigger, "$path.on_trigger", "$sideKey.on_trigger", ctx)
    }

    /** SPEC 14.1-14.3: the discriminated ActionDescriptor schema. */
    private fun validateAction(obj: JsonObject, path: String, hook: String, ctx: Ctx) {
        val hasAction = "action" in obj
        val hasBuiltin = "builtin" in obj
        if (hasAction == hasBuiltin)
            throw ContentInvalid(path, "exactly one of action/builtin")
        val row: ActionRow
        if (hasAction) {
            row = ACTION_SCHEMA.getValue("remote")
            val name = obj.stringOrNull("action")
                ?: throw ContentInvalid("$path.action", "must be a string")
            if ('.' !in name)
                throw ContentInvalid("$path.action", "action names contain a dot")
            // `opt(k) ?: DEFAULT`: only an ABSENT member took the default —
            // org.json's opt handed back its NULL sentinel for an explicit
            // JSON null, which then failed the whitelist. Preserved, and note
            // it differs from validateNotificationAction above, whose
            // optString read folded null INTO the default. A present
            // non-string still fails either way.
            val policy = if ("when_offline" in obj) obj.stringOrNull("when_offline")
                         else OFFLINE_DEFAULT
            if (policy == null || policy !in OFFLINE_POLICIES)
                throw ContentInvalid("$path.when_offline", "unknown offline policy")
            if (policy in setOf("queue", "wake") && "ttl_s" !in obj)
                throw ContentInvalid(path, "$policy requires ttl_s")
            if (policy == "drop" && ("ttl_s" in obj || "dedupe" in obj))
                throw ContentInvalid(path, "ttl_s/dedupe are invalid for drop")
            // SPEC 14.1: ttl_s is an integer 1..604800. Validating it here
            // makes the queue-admission integer read at dispatch time total.
            // Read as binary64: `ttl_s: 60.0` is accepted traffic today
            // (PreSwapNumberTest), and the floor test IS the integrality rule.
            if ("ttl_s" in obj) {
                val d = obj["ttl_s"]?.asDoubleOrNull()
                    ?: throw ContentInvalid("$path.ttl_s", "must be an integer 1..604800")
                if (d != Math.floor(d) || d.isInfinite() || d < 1.0 || d > 604800.0)
                    throw ContentInvalid("$path.ttl_s", "must be an integer 1..604800")
            }
            // SPEC 14.1: confirm is a non-empty string when present.
            if ("confirm" in obj) {
                val c = obj.stringOrNull("confirm")
                if (c == null || c.isEmpty())
                    throw ContentInvalid("$path.confirm", "must be a non-empty string")
            }
            // SPEC 14.3: a remote descriptor on a value-producing hook MUST
            // NOT author the member the Companion injects.
            INJECTED_MEMBERS[hook]?.let { injected ->
                obj.objOrNull("args")?.let { args ->
                    for (m in injected)
                        if (m in args)
                            throw ContentInvalid("$path.args.$m",
                                "conflicts with the value injected by $hook")
                }
            }
        } else {
            val name = obj.stringOrNull("builtin")
                ?: throw ContentInvalid("$path.builtin", "must be a string")
            // SPEC 14.2: an unknown builtin rejects the containing document.
            row = ACTION_SCHEMA[name]
                ?: throw ContentInvalid("$path.builtin", "unknown builtin $name")
            // SPEC 14.2 (LD-17): a builtin not advertised for THIS target is an
            // invalid context and rejects the document — a builtin does not
            // degrade the way an unadvertised node type does. Emacs MUST NOT
            // emit one absent from surface_profiles.<target>.builtins.
            if (ctx.advertisedBuiltins != null && name !in ctx.advertisedBuiltins)
                throw ContentInvalid("$path.builtin", "builtin $name not valid in this context")
        }
        // SPEC 14.1: capture_fields is an array of distinct widget IDs no
        // longer than max_capture_fields; each is resolved against the
        // document's stateful nodes after the whole walk (see captureRefs).
        if ("capture_fields" in obj) {
            val cf = obj.arrOrNull("capture_fields")
                ?: throw ContentInvalid("$path.capture_fields", "must be an array")
            if (cf.size.toLong() > ctx.maxCaptureFields)
                throw ContentInvalid("$path.capture_fields", "exceeds max_capture_fields")
            val names = mutableListOf<String>()
            val seen = mutableSetOf<String>()
            for (i in cf.indices) {
                val nm = cf[i].asStringOrNull()
                    ?: throw ContentInvalid("$path.capture_fields[$i]", "must be a widget ID")
                if (!seen.add(nm))
                    throw ContentInvalid("$path.capture_fields[$i]", "duplicate capture field")
                names.add(nm)
            }
            ctx.captureRefs.add(path to names)
        }
        for (req in row.required)
            if (req != "builtin" && req !in obj)
                throw ContentInvalid(path, "action missing required $req")
        for (key in obj.keys)
            if (key !in row.required && key !in row.optional && key != "builtin"
                && key != "action")
                throw ContentInvalid("$path.$key", "unknown action member")
    }
}
