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

import org.json.JSONArray
import org.json.JSONObject

class ContentInvalid(val path: String, val reason: String) :
    Exception("$reason at $path")

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
    "on_point_tap" to setOf("value"),
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
        val statefuls = mutableMapOf<String, JSONObject>()
        val captureRefs = mutableListOf<Pair<String, List<String>>>()
        var nodeCount = 0
        // SPEC 4.5: max_rich_spans / max_table_cells are AGGREGATE counts
        // across one SurfaceSpec or dialog document, like max_chart_points.
        var richSpans = 0L
        var tableCells = 0L
    }

    /** Validate one SurfaceSpec; returns the stateful nodes by ID. The chart/
     * canvas count limits default high so unit tests and the golden corpus
     * pass; the engine passes the profile's real §4.5 values. */
    fun validateSurfaceSpec(
        spec: Any?,
        path: String = "spec",
        maxCaptureFields: Long = 64,
        maxChartPoints: Long = Long.MAX_VALUE,
        maxCanvasOps: Long = Long.MAX_VALUE,
        maxRichSpans: Long = Long.MAX_VALUE,
        maxTableCells: Long = Long.MAX_VALUE,
        advertisedTypes: Set<String>? = null,
        advertisedBuiltins: Set<String>? = null,
    ): Map<String, JSONObject> {
        if (spec !is JSONObject) throw ContentInvalid(path, "spec must be an object")
        val ctx = Ctx(maxCaptureFields, maxChartPoints, maxCanvasOps,
            maxRichSpans, maxTableCells, advertisedTypes, advertisedBuiltins)
        if (spec.has("views")) {
            val views = spec.optJSONObject("views")
                ?: throw ContentInvalid("$path.views", "views must be an object")
            if (views.length() == 0)
                throw ContentInvalid("$path.views", "views must be non-empty")
            val initial = spec.opt("initial_view")
            if (initial !is String || !views.has(initial))
                throw ContentInvalid("$path.initial_view", "must name an existing view")
            for (name in views.keySet()) {
                val view = views.get(name)
                if (view !is JSONObject || view.opt("t") !is String)
                    throw ContentInvalid("$path.views.$name", "each view must be a node")
                walkNode(view, "$path.views.$name", ctx)
            }
        } else {
            // SPEC 16.1: a single-view surface root is itself a node.
            if (spec.opt("t") !is String)
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
    fun validateResetIds(resetIds: JSONArray, statefuls: Map<String, JSONObject>): Set<String> {
        val out = mutableSetOf<String>()
        for (i in 0 until resetIds.length()) {
            val id = resetIds.opt(i) as? String
                ?: throw ContentInvalid("reset_input_ids[$i]", "must be a widget ID")
            if (!out.add(id))
                throw ContentInvalid("reset_input_ids[$i]", "duplicate ID")
            val node = statefuls[id]
                ?: throw ContentInvalid("reset_input_ids[$i]", "not a stateful node in spec")
            if (node.optBoolean("password"))
                throw ContentInvalid("reset_input_ids[$i]", "password nodes cannot be reset")
            if (node.getString("t") == "editor" && node.has("document"))
                throw ContentInvalid("reset_input_ids[$i]",
                    "synchronized editor text changes only through Section 19")
        }
        return out
    }

    /** SPEC 13.5: `stale_spec` carries no stateful node and no editor. */
    fun validateStaleSpec(staleSpec: Any?, primaryIsMultiView: Boolean,
                          maxCaptureFields: Long = 64,
                          maxChartPoints: Long = Long.MAX_VALUE,
                          maxCanvasOps: Long = Long.MAX_VALUE,
                          maxRichSpans: Long = Long.MAX_VALUE,
                          maxTableCells: Long = Long.MAX_VALUE) {
        val statefuls = validateSurfaceSpec(staleSpec, "stale_spec",
            maxCaptureFields, maxChartPoints, maxCanvasOps,
            maxRichSpans, maxTableCells)
        if (statefuls.isNotEmpty())
            throw ContentInvalid("stale_spec", "stateful nodes are prohibited in stale_spec")
        if ((staleSpec as JSONObject).has("views") != primaryIsMultiView)
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
    fun validateNotificationSpec(spec: Any?, path: String = "spec",
                                 maxCaptureFields: Long = 64,
                                 advertisedTypes: Set<String>? = null,
                                 advertisedBuiltins: Set<String>? = null,
                                 maxChartPoints: Long = Long.MAX_VALUE,
                                 maxCanvasOps: Long = Long.MAX_VALUE,
                                 maxRichSpans: Long = Long.MAX_VALUE,
                                 maxTableCells: Long = Long.MAX_VALUE) {
        if (spec !is JSONObject) throw ContentInvalid(path, "must be an object")
        if (spec.has("views")) throw ContentInvalid(path, "multi-view prohibited")
        for (k in spec.keySet()) if (k != "body" && k != "meta")
            throw ContentInvalid("$path.$k", "unknown notification member")
        val body = spec.opt("body")
        if (body !is JSONObject || body.opt("t") !is String)
            throw ContentInvalid("$path.body", "must be a node")
        // SPEC 17.1: gate the body to the notification profile's node_types.
        validateSurfaceSpec(body, "$path.body", maxCaptureFields,
            maxChartPoints = maxChartPoints, maxCanvasOps = maxCanvasOps,
            maxRichSpans = maxRichSpans, maxTableCells = maxTableCells,
            advertisedTypes = advertisedTypes, advertisedBuiltins = advertisedBuiltins)
        if (spec.has("meta")) {
            val meta = spec.opt("meta") as? JSONObject
                ?: throw ContentInvalid("$path.meta", "must be an object")
            validateNotificationMeta(meta, "$path.meta")
        }
    }

    private val PRIORITIES = setOf("min", "low", "default", "high", "max")

    private fun validateNotificationMeta(meta: JSONObject, path: String) {
        val allowed = setOf("channel", "ongoing", "category", "priority",
            "chronometer", "actions")
        for (k in meta.keySet()) if (k !in allowed)
            throw ContentInvalid("$path.$k", "unknown meta member")
        (meta.opt("channel"))?.takeIf { meta.has("channel") }?.let {
            if (it !is String || !IDENTIFIER.matches(it))
                throw ContentInvalid("$path.channel", "must be an identifier")
        }
        (meta.opt("category"))?.takeIf { meta.has("category") }?.let {
            if (it !is String || !IDENTIFIER.matches(it))
                throw ContentInvalid("$path.category", "must be an identifier")
        }
        if (meta.has("ongoing") && meta.opt("ongoing") !is Boolean)
            throw ContentInvalid("$path.ongoing", "must be a boolean")
        if (meta.has("priority") && meta.opt("priority") !in PRIORITIES)
            throw ContentInvalid("$path.priority", "min|low|default|high|max")
        meta.optJSONObject("chronometer")?.let { chrono ->
            // SPEC 4.3/18.5: base_ms is a non-negative epoch-millis INTEGER,
            // not any Number (a fractional or negative timestamp is invalid).
            val base = (chrono.opt("base_ms") as? Number)?.toDouble()
            if (base == null || base != Math.floor(base) || base < 0)
                throw ContentInvalid("$path.chronometer.base_ms",
                    "must be a non-negative epoch-millis integer")
            if (chrono.has("count_down") && chrono.opt("count_down") !is Boolean)
                throw ContentInvalid("$path.chronometer.count_down", "must be a boolean")
        }
        meta.optJSONArray("actions")?.let { actions ->
            for (i in 0 until actions.length()) {
                val a = actions.optJSONObject(i)
                    ?: throw ContentInvalid("$path.actions[$i]", "must be an object")
                validateNotificationAction(a, "$path.actions[$i]")
            }
        }
    }

    private fun validateNotificationAction(a: JSONObject, path: String) {
        val allowed = setOf("label", "on_tap", "icon", "dismiss", "input")
        for (k in a.keySet()) if (k !in allowed)
            throw ContentInvalid("$path.$k", "unknown action member")
        if (a.opt("label") !is String || (a.opt("label") as String).isEmpty())
            throw ContentInvalid("$path.label", "non-empty string required")
        val onTap = a.optJSONObject("on_tap")
            ?: throw ContentInvalid("$path.on_tap", "required")
        // SPEC 14.2/18.5: a notification action's on_tap MUST be a remote
        // ActionDescriptor — the notification profile advertises no builtins and
        // there is no context-less builtin execution path, so a builtin on_tap
        // would validate but throw at tap time.
        if (onTap.has("builtin"))
            throw ContentInvalid("$path.on_tap", "notification action must be a remote action, not a builtin")
        // LD-19: identifiers carry the SPEC 4.4/4.5 128-octet bound, not
        // just the grammar — this is the node-id check applied to the two
        // sites that missed it (icon here, input.key below).
        if (a.has("icon") && (a.opt("icon") !is String ||
                !IDENTIFIER.matches(a.getString("icon")) ||
                a.getString("icon").toByteArray(Charsets.UTF_8).size >
                    WireLimits.MAX_IDENTIFIER_OCTETS))
            throw ContentInvalid("$path.icon", "must be an identifier")
        val dismiss = a.opt("dismiss")
        if (a.has("dismiss") && dismiss !is Boolean)
            throw ContentInvalid("$path.dismiss", "must be a boolean")
        val hasInput = a.has("input")
        if (hasInput) {
            val input = a.optJSONObject("input")
                ?: throw ContentInvalid("$path.input", "must be an object")
            for (k in input.keySet()) if (k != "hint" && k != "key")
                throw ContentInvalid("$path.input.$k", "unknown input member")
            if (input.has("hint") && input.opt("hint") !is String)
                throw ContentInvalid("$path.input.hint", "must be a string")
            if (input.has("key") && (input.opt("key") !is String ||
                    !IDENTIFIER.matches(input.getString("key")) ||
                    input.getString("key").toByteArray(Charsets.UTF_8).size >
                        WireLimits.MAX_IDENTIFIER_OCTETS))
                throw ContentInvalid("$path.input.key", "must be an identifier")
        }
        // SPEC 18.5: when input or dismiss:true is present, on_tap MUST be
        // a remote ActionDescriptor; an inline reply MUST NOT capture_fields.
        val requiresRemote = hasInput || dismiss == true
        val isRemote = onTap.has("action") && !onTap.has("builtin")
        if (requiresRemote && !isRemote)
            throw ContentInvalid("$path.on_tap", "must be a remote action for input/dismiss")
        if (hasInput && onTap.has("capture_fields"))
            throw ContentInvalid("$path.on_tap", "an inline reply must not capture_fields")
        // SPEC 14.1/14.2: validate the descriptor itself with the SAME rules
        // the surface path uses — exactly-one action/builtin, a dotted action
        // name, a known offline policy, ttl_s only for queue/wake and in
        // 1..604800, no ttl_s/dedupe on drop, and a globally-known builtin.
        if (onTap.has("action") == onTap.has("builtin"))
            throw ContentInvalid("$path.on_tap", "exactly one of action/builtin")
        if (onTap.has("action")) {
            val name = onTap.opt("action") as? String
                ?: throw ContentInvalid("$path.on_tap.action", "must be a string")
            if ('.' !in name)
                throw ContentInvalid("$path.on_tap.action", "action names contain a dot")
            val policy = onTap.optString("when_offline", OFFLINE_DEFAULT)
            if (policy !in OFFLINE_POLICIES)
                throw ContentInvalid("$path.on_tap.when_offline", "unknown offline policy")
            if (policy in setOf("queue", "wake") && !onTap.has("ttl_s"))
                throw ContentInvalid("$path.on_tap", "$policy requires ttl_s")
            if (policy == "drop" && (onTap.has("ttl_s") || onTap.has("dedupe")))
                throw ContentInvalid("$path.on_tap", "ttl_s/dedupe are invalid for drop")
            if (onTap.has("ttl_s")) {
                val ttl = onTap.opt("ttl_s") as? Number
                    ?: throw ContentInvalid("$path.on_tap.ttl_s", "must be an integer 1..604800")
                val d = ttl.toDouble()
                if (d != Math.floor(d) || d.isInfinite() || d < 1.0 || d > 604800.0)
                    throw ContentInvalid("$path.on_tap.ttl_s", "must be an integer 1..604800")
            }
        } else {
            val name = onTap.opt("builtin") as? String
                ?: throw ContentInvalid("$path.on_tap.builtin", "must be a string")
            if (name !in ACTION_SCHEMA)
                throw ContentInvalid("$path.on_tap.builtin", "unknown builtin $name")
        }
    }

    private fun containsEditor(value: Any?): Boolean = when (value) {
        is JSONObject -> value.opt("t") == "editor" ||
            value.keySet().any { containsEditor(value.get(it)) }
        is JSONArray -> (0 until value.length()).any { containsEditor(value.get(it)) }
        else -> false
    }

    // ------------------------------------------------------------ walking

    /**
     * Generic descent for a value that is not itself a schema-declared node
     * position: descends arbitrary structure to validate nested nodes and
     * the action descriptors on container items (menu/tab/table entries).
     * The strict node-position rules live in [walkNode].
     */
    private fun walkValue(value: Any?, path: String, ctx: Ctx) {
        when (value) {
            is JSONArray ->
                for (i in 0 until value.length())
                    walkValue(value.get(i), "$path[$i]", ctx)
            is JSONObject ->
                if (value.opt("t") is String) {
                    walkNode(value, path, ctx)
                } else {
                    for (key in value.keySet()) {
                        val child = value.get(key)
                        if (key in ACTION_HOOK_KEYS && child is JSONObject)
                            validateAction(child, "$path.$key", key, ctx)
                        else if ((key == "swipe_start" || key == "swipe_end") && child is JSONObject)
                            validateSwipeSide(child, "$path.$key", key, ctx)
                        else walkValue(child, "$path.$key", ctx)
                    }
                }
            else -> Unit // scalars carry no schema
        }
    }

    private fun walkNode(node: JSONObject, path: String, ctx: Ctx) {
        // SPEC 4.5: at most 10,000 nodes in one surface snapshot; count
        // before descending so an over-limit tree rejects, not renders.
        if (++ctx.nodeCount > WireLimits.MAX_NODES_PER_SNAPSHOT)
            throw ContentInvalid(path, "exceeds max_nodes_per_snapshot")
        validateNode(node, path, ctx)
        // SPEC 16.2: unknown node types degrade — their subtrees are scanned
        // for nested known nodes but not held to per-type structural rules.
        val t = node.optString("t")
        // SPEC 17.1/16.2: a known type absent from the target profile degrades
        // exactly like an unknown type — its subtree is scanned but its per-type
        // hooks/schema are not applied and it dispatches nothing.
        val known = NODE_SCHEMA.containsKey(t) &&
            (ctx.advertisedTypes == null || t in ctx.advertisedTypes)
        for (key in node.keySet()) {
            val child = node.get(key)
            when {
                known && key in ACTION_HOOK_KEYS -> {
                    // SPEC 17.1: an `on_*` member is an ActionDescriptor.
                    if (child !is JSONObject)
                        throw ContentInvalid("$path.$key", "action descriptor must be an object")
                    validateAction(child, "$path.$key", key, ctx)
                }
                known && (key == "swipe_start" || key == "swipe_end") -> {
                    if (child !is JSONObject)
                        throw ContentInvalid("$path.$key", "swipe side must be an object")
                    validateSwipeSide(child, "$path.$key", key, ctx)
                }
                known && key == "children" -> {
                    // SPEC 17.1: `children` is an array of Nodes. SPEC 4.5:
                    // at most 10,000 children of one node.
                    val arr = child as? JSONArray
                        ?: throw ContentInvalid("$path.children", "children must be an array of nodes")
                    if (arr.length() > WireLimits.MAX_CHILDREN_PER_NODE)
                        throw ContentInvalid("$path.children", "exceeds max_children_per_node")
                    for (i in 0 until arr.length()) {
                        val el = arr.opt(i) as? JSONObject
                            ?: throw ContentInvalid("$path.children[$i]", "child must be a node object")
                        if (el.opt("t") !is String)
                            throw ContentInvalid("$path.children[$i]", "child node missing discriminator t")
                        walkNode(el, "$path.children[$i]", ctx)
                    }
                }
                else -> walkValue(child, "$path.$key", ctx)
            }
        }
    }

    private fun isInt(v: Any?): Long? {
        val n = (v as? Number)?.toDouble() ?: return null
        return if (n == Math.floor(n) && !n.isInfinite()) n.toLong() else null
    }

    /** LD-10: enforce the contract FIELD_TYPES for the scalar categories.
     * Complex types (node/array/object/enum/varies-per-node) return without
     * a check — their dedicated validators run separately. */
    private fun checkScalarFieldType(t: String, member: String, v: Any?, path: String) {
        val p = "$path.$member"
        fun bad(want: String): Nothing = throw ContentInvalid(p, "$member must be $want")
        when (FIELD_TYPES[member]) {
            "boolean" -> if (v !is Boolean) bad("a boolean")
            "string", "yyyy-mm" -> if (v !is String) bad("a string")
            "identifier" -> if (v !is String || !IDENTIFIER.matches(v) ||
                    v.toByteArray(Charsets.UTF_8).size > WireLimits.MAX_IDENTIFIER_OCTETS)
                bad("an identifier")
            "color" -> if (v !is String) bad("a color string")
            "string-or-number" -> if (v !is String && v !is Number) bad("a string or number")
            "dp", "number" -> if (v !is Number || (v).toDouble().isInfinite() ||
                    (v).toDouble().isNaN()) bad("a finite number")
            "non-negative-integer" -> if ((isInt(v) ?: -1) < 0) bad("a non-negative integer")
            "positive-integer" -> if ((isInt(v) ?: 0) < 1) bad("a positive integer")
            "integer-1-12" -> if (isInt(v).let { it == null || it < 1 || it > 12 })
                bad("an integer 1..12")
            "integer-1-31" -> if (isInt(v).let { it == null || it < 1 || it > 31 })
                bad("an integer 1..31")
            else -> Unit // enum, font-weight, varies-per-node, and complex types
        }
    }

    private fun validateNode(node: JSONObject, path: String, ctx: Ctx) {
        val t = node.opt("t") as? String
            ?: throw ContentInvalid(path, "node discriminator t must be a string")
        // SPEC 16.1: every authored node ID is unique across the document.
        (node.opt("id") as? String)?.let { id ->
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
            if (!node.has(req))
                throw ContentInvalid(path, "$t missing required $req")
        // LD-10: type-check each type-specific member against the contract's
        // FIELD_TYPES, for the coercion-prone SCALAR categories. The org.json
        // accessors coerce silently — `optBoolean("enabled", true)` returned
        // the DEFAULT for `enabled: 0`, rendering a disabled node enabled;
        // `optString("title", "")` turned `title: {...}` into a heading of
        // the object's JSON text; `optBoolean("password", ...)` accepted the
        // string "true". Scoped to members this node's schema lists (so
        // richer-grammar universal attrs are untouched) and to scalar types
        // (enum has §16.3 fallback semantics, and node/array/object/
        // varies-per-node members have dedicated validators below).
        for (member in row.required + row.optional)
            if (node.has(member)) checkScalarFieldType(t, member, node.get(member), path)
        when (t) {
            "text_input" -> {
                val value = node.opt("value")
                if (value != null && value !is String)
                    throw ContentInvalid("$path.value", "text_input value must be a string")
                // SPEC 17.4: single_line prohibits U+000A in authored values.
                if (node.optBoolean("single_line") && value is String && '\n' in value)
                    throw ContentInvalid("$path.value", "single_line value contains U+000A")
                // SPEC 17.4: a snapshot must not seed a password.
                if (node.optBoolean("password") &&
                    (value is String && value.isNotEmpty() || node.has("on_change")))
                    throw ContentInvalid(path, "password nodes cannot seed values or publish state")
                validateLineCounts(node, path)
            }
            "slider" -> {
                val values = node.optJSONArray("values")
                if (values != null) {
                    if (node.has("min") || node.has("max"))
                        throw ContentInvalid(path, "discrete slider must omit min and max")
                    if (values.length() < 2)
                        throw ContentInvalid("$path.values", "at least two discrete values")
                    var prev = Double.NEGATIVE_INFINITY
                    for (i in 0 until values.length()) {
                        val n = values.opt(i) as? Number
                            ?: throw ContentInvalid("$path.values[$i]", "must be a number")
                        if (n.toDouble() <= prev)
                            throw ContentInvalid("$path.values", "must be strictly increasing")
                        prev = n.toDouble()
                    }
                    // SPEC 17.4: a discrete value must equal one listed number
                    // (Section 4.3 numeric equality); default is the first.
                    if (node.has("value")) {
                        val v = node.opt("value") as? Number
                            ?: throw ContentInvalid("$path.value", "must be a number")
                        val listed = (0 until values.length())
                            .any { jsonValueEquals(values.get(it), v) }
                        if (!listed)
                            throw ContentInvalid("$path.value", "must equal a listed discrete value")
                    }
                } else {
                    val min = (node.opt("min") as? Number)?.toDouble() ?: 0.0
                    val max = (node.opt("max") as? Number)?.toDouble() ?: 1.0
                    if (min >= max)
                        throw ContentInvalid(path, "slider min must be less than max")
                    // SPEC 17.4: a continuous value lies in the closed range.
                    if (node.has("value")) {
                        val v = (node.opt("value") as? Number)?.toDouble()
                            ?: throw ContentInvalid("$path.value", "must be a number")
                        if (v.isNaN() || v < min || v > max)
                            throw ContentInvalid("$path.value", "must be within min..max")
                    }
                }
            }
            "enum_list" -> {
                // SPEC 16.1: a wrong-typed required member rejects (1201),
                // it never crashes the session — so opt, not the throwing get.
                val options = node.optJSONArray("options")
                    ?: throw ContentInvalid("$path.options", "options must be an array")
                val seen = mutableListOf<Any>()
                for (i in 0 until options.length()) {
                    val opt = options.optJSONObject(i)
                        ?: throw ContentInvalid("$path.options[$i]", "must be an object")
                    if (!opt.has("label") || !opt.has("value"))
                        throw ContentInvalid("$path.options[$i]", "needs label and value")
                    if (seen.any { jsonValueEquals(it, opt.get("value")) })
                        throw ContentInvalid("$path.options[$i]", "duplicate option value")
                    seen.add(opt.get("value"))
                }
                // SPEC 17.4: unless allow_add, every selected value appears in
                // options; multi_select values are an array of distinct values.
                if (node.has("value") && !node.isNull("value")) {
                    val allowAdd = node.optBoolean("allow_add")
                    fun checkMember(v: Any, p: String) {
                        if (!allowAdd && seen.none { jsonValueEquals(it, v) })
                            throw ContentInvalid(p, "selected value not in options")
                    }
                    if (node.optBoolean("multi_select")) {
                        val arr = node.opt("value") as? JSONArray
                            ?: throw ContentInvalid("$path.value", "multi-select value must be an array")
                        val chosen = mutableListOf<Any>()
                        for (i in 0 until arr.length()) {
                            val v = arr.get(i)
                            if (chosen.any { jsonValueEquals(it, v) })
                                throw ContentInvalid("$path.value[$i]", "duplicate selected value")
                            chosen.add(v)
                            checkMember(v, "$path.value[$i]")
                        }
                    } else {
                        if (node.opt("value") is JSONArray)
                            throw ContentInvalid("$path.value", "single-select value must be scalar")
                        checkMember(node.get("value"), "$path.value")
                    }
                }
            }
            "text" -> validatePositiveInt(node, "max_lines", path)
            "rich_text" -> validateSpans(node.opt("spans"), "$path.spans", ctx)
            "empty_state" ->
                // SPEC 17.2: action_label and on_tap together or both absent.
                if (node.has("action_label") != node.has("on_tap"))
                    throw ContentInvalid(path,
                        "action_label and on_tap must appear together or both be absent")
            "progress" ->
                if (node.has("value")) {
                    val v = (node.opt("value") as? Number)?.toDouble()
                        ?: throw ContentInvalid("$path.value", "must be a number 0..1")
                    if (v.isNaN() || v < 0.0 || v > 1.0)
                        throw ContentInvalid("$path.value", "must be a number 0..1")
                }
            "date_stamp" -> {
                validateIntRange(node, "day", 1, 31, path)
                validateIntRange(node, "month_index", 1, 12, path)
                if (node.has("year")) {
                    val y = (node.opt("year") as? Number)?.toDouble()
                    if (y == null || y != Math.floor(y) || y < 0)
                        throw ContentInvalid("$path.year", "must be a non-negative integer")
                }
            }
            "reorderable_list" -> {
                // SPEC 17.3: every item has a unique key or id — else invalid.
                val items = node.optJSONArray("items")
                    ?: throw ContentInvalid("$path.items", "items must be an array")
                val keys = mutableSetOf<String>()
                for (i in 0 until items.length()) {
                    val item = items.optJSONObject(i)
                        ?: throw ContentInvalid("$path.items[$i]", "must be a node")
                    val k = (item.opt("key") as? String) ?: (item.opt("id") as? String)
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
                if (!ImageGuards.isValidImageUrl(node.optString("url")))
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
                val hasDocument = node.has("document")
                // SPEC 17.4: complete:true requires document.
                if (node.optBoolean("complete") && !hasDocument)
                    throw ContentInvalid(path, "complete requires document")
                if (node.has("toolbar"))
                    validateToolbar(node.opt("toolbar"), "$path.toolbar", hasDocument)
            }
        }
        if (t in STATEFUL_NODE_TYPES) {
            // SPEC 13.6: "a local `editor` draft requires publish_state: true
            // and no `document` in both snapshots. A synchronized editor never
            // participates in draft reconciliation." Registering a
            // synchronized editor as stateful let publishState write a
            // DURABLE draft for it (persisted, and reportable in the next
            // welcome's input_state) — the offline draft §19 forbids.
            val isStateful = t != "editor" ||
                (node.optBoolean("publish_state") && !node.has("document"))
            if (isStateful) {
                val id = node.opt("id") as? String
                    ?: throw ContentInvalid(path, "$t requires an id")
                ctx.statefuls[id] = node
            }
        }
    }

    // ------------------------------------------- per-type deep rules (17.x)

    /** SPEC 17.4: min_lines/max_lines are positive integers, min ≤ max, and
     * single_line:true requires both to equal 1. */
    private fun validateLineCounts(node: JSONObject, path: String) {
        validatePositiveInt(node, "min_lines", path)
        validatePositiveInt(node, "max_lines", path)
        val min = (node.opt("min_lines") as? Number)?.toInt()
        val max = (node.opt("max_lines") as? Number)?.toInt()
        if (min != null && max != null && min > max)
            throw ContentInvalid(path, "min_lines must not exceed max_lines")
        if (node.optBoolean("single_line") &&
            ((min ?: 1) != 1 || (max ?: 1) != 1))
            throw ContentInvalid(path, "single_line requires line counts of 1")
    }

    private fun validatePositiveInt(node: JSONObject, member: String, path: String) {
        if (!node.has(member)) return
        val n = (node.opt(member) as? Number)?.toDouble()
        if (n == null || n != Math.floor(n) || n < 1)
            throw ContentInvalid("$path.$member", "must be a positive integer")
    }

    private fun validateIntRange(node: JSONObject, member: String, lo: Int, hi: Int, path: String) {
        if (!node.has(member)) return
        val n = (node.opt(member) as? Number)?.toDouble()
        if (n == null || n != Math.floor(n) || n < lo || n > hi)
            throw ContentInvalid("$path.$member", "must be an integer $lo..$hi")
    }

    /** SPEC 17.2: a RichSpan MUST contain text: string. Every RichSpan in the
     * document — rich_text spans and table-cell spans alike — spends the
     * SPEC 4.5 aggregate max_rich_spans allowance. */
    private fun validateSpans(spans: Any?, path: String, ctx: Ctx) {
        val arr = spans as? JSONArray
            ?: throw ContentInvalid(path, "must be an array of spans")
        ctx.richSpans += arr.length()
        if (ctx.richSpans > ctx.maxRichSpans)
            throw ContentInvalid(path, "exceeds max_rich_spans")
        for (i in 0 until arr.length()) {
            val span = arr.optJSONObject(i)
                ?: throw ContentInvalid("$path[$i]", "must be a span object")
            if (span.opt("text") !is String)
                throw ContentInvalid("$path[$i].text", "span text must be a string")
        }
    }

    /** SPEC 17.3: tabs arrays pair 1:1 and are non-empty; TabItem needs a
     * label; initial indexes the common count. */
    private fun validateTabs(node: JSONObject, path: String) {
        val items = node.optJSONArray("items")
            ?: throw ContentInvalid("$path.items", "items must be an array")
        val children = node.optJSONArray("children")
            ?: throw ContentInvalid("$path.children", "children must be an array")
        if (items.length() == 0 || items.length() != children.length())
            throw ContentInvalid(path, "items and children must have equal non-zero length")
        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i)
                ?: throw ContentInvalid("$path.items[$i]", "must be a TabItem object")
            if (item.opt("label") !is String)
                throw ContentInvalid("$path.items[$i].label", "TabItem label must be a string")
        }
        if (node.has("initial")) {
            val init = (node.opt("initial") as? Number)?.toDouble()
            if (init == null || init != Math.floor(init) ||
                init < 0 || init >= items.length())
                throw ContentInvalid("$path.initial", "must index the item count")
        }
    }

    /** SPEC 17.3: an unknown TableRow kind is invalid; data/header cells MUST
     * contain spans (RichSpan[]); aligns entries are start|center|end. */
    private fun validateTable(node: JSONObject, path: String, ctx: Ctx) {
        val rows = node.optJSONArray("rows")
            ?: throw ContentInvalid("$path.rows", "rows must be an array")
        for (i in 0 until rows.length()) {
            val row = rows.optJSONObject(i)
                ?: throw ContentInvalid("$path.rows[$i]", "must be a TableRow object")
            when (row.opt("kind")) {
                "rule" -> Unit
                "data", "header" -> {
                    val cells = row.optJSONArray("cells")
                        ?: throw ContentInvalid("$path.rows[$i].cells", "must be an array")
                    // SPEC 4.5: max_table_cells is an aggregate count across
                    // the document, spent by data and header cells.
                    ctx.tableCells += cells.length()
                    if (ctx.tableCells > ctx.maxTableCells)
                        throw ContentInvalid("$path.rows[$i].cells", "exceeds max_table_cells")
                    for (j in 0 until cells.length()) {
                        val cell = cells.optJSONObject(j)
                            ?: throw ContentInvalid("$path.rows[$i].cells[$j]", "must be a cell object")
                        validateSpans(cell.opt("spans"), "$path.rows[$i].cells[$j].spans", ctx)
                    }
                }
                else -> throw ContentInvalid("$path.rows[$i].kind", "unknown table row kind")
            }
        }
        node.optJSONArray("aligns")?.let { aligns ->
            for (i in 0 until aligns.length())
                if (aligns.opt(i) !in setOf("start", "center", "end"))
                    throw ContentInvalid("$path.aligns[$i]", "must be start|center|end")
        }
    }

    /** SPEC 17.5: every ChartPoint is finite numeric x/y; y_range is a
     * two-number [min,max] with min < max; height is positive. */
    private fun validateChart(node: JSONObject, path: String, ctx: Ctx) {
        val series = node.optJSONArray("series")
            ?: throw ContentInvalid("$path.series", "series must be an array")
        var totalPoints = 0L
        for (i in 0 until series.length()) {
            val s = series.optJSONObject(i)
                ?: throw ContentInvalid("$path.series[$i]", "must be a series object")
            val points = s.optJSONArray("points")
                ?: throw ContentInvalid("$path.series[$i].points", "points must be an array")
            // SPEC 4.5: max_chart_points bounds the total across all series.
            totalPoints += points.length()
            if (totalPoints > ctx.maxChartPoints)
                throw ContentInvalid("$path.series", "exceeds max_chart_points")
            for (j in 0 until points.length()) {
                val p = points.optJSONObject(j)
                    ?: throw ContentInvalid("$path.series[$i].points[$j]", "must be a point object")
                for (coord in listOf("x", "y")) {
                    val v = (p.opt(coord) as? Number)?.toDouble()
                    if (v == null || v.isNaN() || v.isInfinite())
                        throw ContentInvalid("$path.series[$i].points[$j].$coord",
                            "must be a finite number")
                }
            }
        }
        node.optJSONArray("y_range")?.let { r ->
            val lo = (r.opt(0) as? Number)?.toDouble()
            val hi = (r.opt(1) as? Number)?.toDouble()
            if (r.length() != 2 || lo == null || hi == null || !(lo < hi))
                throw ContentInvalid("$path.y_range", "must be [min, max] with min < max")
        }
        if (node.has("height")) {
            val h = (node.opt("height") as? Number)?.toDouble()
            if (h == null || h.isNaN() || h <= 0)
                throw ContentInvalid("$path.height", "must be positive")
        }
    }

    /** SPEC 17.5: canvas dims are positive; KNOWN ops carry their closed
     * shape's required finite members (an unknown op is skipped at render,
     * never rejected); path points are exactly {x, y}. */
    private fun validateCanvas(node: JSONObject, path: String, ctx: Ctx) {
        for (dim in listOf("width", "height")) {
            val v = (node.opt(dim) as? Number)?.toDouble()
            if (v == null || v.isNaN() || v <= 0)
                throw ContentInvalid("$path.$dim", "must be positive")
        }
        val ops = node.optJSONArray("ops")
            ?: throw ContentInvalid("$path.ops", "ops must be an array")
        // SPEC 4.5: max_canvas_ops bounds the op count (unknown ops still count).
        if (ops.length().toLong() > ctx.maxCanvasOps)
            throw ContentInvalid("$path.ops", "exceeds max_canvas_ops")
        for (i in 0 until ops.length()) {
            val op = ops.optJSONObject(i)
                ?: throw ContentInvalid("$path.ops[$i]", "must be an op object")
            val kind = op.opt("op") as? String
                ?: throw ContentInvalid("$path.ops[$i].op", "op discriminator required")
            val required = CANVAS_OPS[kind] ?: continue // unknown op: render-skip
            for (m in required) {
                if (!op.has(m))
                    throw ContentInvalid("$path.ops[$i]", "$kind missing required $m")
                if (m != "points" && m != "text") {
                    val v = (op.opt(m) as? Number)?.toDouble()
                    if (v == null || v.isNaN() || v.isInfinite())
                        throw ContentInvalid("$path.ops[$i].$m", "must be a finite number")
                }
            }
            if (kind == "path") {
                val pts = op.optJSONArray("points")
                    ?: throw ContentInvalid("$path.ops[$i].points", "must be an array")
                for (j in 0 until pts.length()) {
                    val p = pts.optJSONObject(j)
                        ?: throw ContentInvalid("$path.ops[$i].points[$j]", "must be {x, y}")
                    for (coord in listOf("x", "y")) {
                        val v = (p.opt(coord) as? Number)?.toDouble()
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
                if (op.has(m)) {
                    val v = (op.opt(m) as? Number)?.toDouble()
                    if (v == null || v.isNaN() || v < 0)
                        throw ContentInvalid("$path.ops[$i].$m", "must be non-negative")
                }
            }
        }
    }

    /** SPEC 17.5: month formats, dots 0..3, min_month ≤ max_month. */
    private fun validateMonthGrid(node: JSONObject, path: String) {
        val month = node.opt("month") as? String
        if (month == null || !YYYY_MM.matches(month))
            throw ContentInvalid("$path.month", "must be YYYY-MM")
        for (m in listOf("min_month", "max_month")) {
            (node.opt(m))?.takeIf { node.has(m) }?.let {
                if (it !is String || !YYYY_MM.matches(it))
                    throw ContentInvalid("$path.$m", "must be YYYY-MM")
            }
        }
        val lo = node.opt("min_month") as? String
        val hi = node.opt("max_month") as? String
        if (lo != null && hi != null && lo > hi)
            throw ContentInvalid(path, "min_month must not follow max_month")
        (node.opt("selected"))?.takeIf { node.has("selected") }?.let {
            if (it !is String || !YYYY_MM_DD.matches(it))
                throw ContentInvalid("$path.selected", "must be YYYY-MM-DD")
        }
        node.optJSONObject("marks")?.let { marks ->
            for (key in marks.keySet()) {
                if (!YYYY_MM_DD.matches(key))
                    throw ContentInvalid("$path.marks.$key", "keys must be YYYY-MM-DD")
                val mark = marks.optJSONObject(key)
                    ?: throw ContentInvalid("$path.marks.$key", "must be an object")
                val dots = (mark.opt("dots") as? Number)?.toDouble()
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
    private fun validateToolbar(toolbar: Any?, path: String, hasDocument: Boolean) {
        if (toolbar is String) {
            if (!IDENTIFIER.matches(toolbar))
                throw ContentInvalid(path, "must be a toolbar identifier or item array")
            return
        }
        val items = toolbar as? JSONArray
            ?: throw ContentInvalid(path, "must be a toolbar identifier or item array")
        for (i in 0 until items.length())
            validateToolbarItem(items.optJSONObject(i)
                ?: throw ContentInvalid("$path[$i]", "must be a ToolbarItem object"),
                "$path[$i]", hasDocument, allowMenu = true)
    }

    private fun validateToolbarItem(item: JSONObject, path: String,
                                    hasDocument: Boolean, allowMenu: Boolean) {
        if (!item.has("label") && !item.has("icon"))
            throw ContentInvalid(path, "ToolbarItem needs label or icon")
        val ops = TOOLBAR_OPS.filter { item.has(it) }
        if (ops.size != 1)
            throw ContentInvalid(path, "exactly one primary operation required")
        val op = ops.single()
        if (op == "menu" && !allowMenu)
            throw ContentInvalid(path, "menu items must carry non-menu operations")
        when (op) {
            "menu" -> {
                val sub = item.optJSONArray("menu")
                    ?: throw ContentInvalid("$path.menu", "must be an array of items")
                for (j in 0 until sub.length())
                    validateToolbarItem(sub.optJSONObject(j)
                        ?: throw ContentInvalid("$path.menu[$j]", "must be a ToolbarItem"),
                        "$path.menu[$j]", hasDocument, allowMenu = false)
            }
            "command" -> {
                val c = item.opt("command")
                if (c !is String || !IDENTIFIER.matches(c))
                    throw ContentInvalid("$path.command", "must be an identifier")
                // SPEC 17.4: a toolbar command requires document.
                if (!hasDocument)
                    throw ContentInvalid("$path.command", "command requires document")
            }
            "snippet" -> {
                val snippet = item.opt("snippet") as? String
                    ?: throw ContentInvalid("$path.snippet", "must be a string")
                // SPEC 17.7 (amendment #61): at most one ${input:...} token.
                if (INPUT_TOKEN.findAll(snippet).count() > 1)
                    throw ContentInvalid("$path.snippet",
                        "at most one \${input:...} token per snippet")
            }
            "line" -> if (item.opt("line") !is String)
                throw ContentInvalid("$path.line", "must be a string")
            // on_tap descriptors are validated by the generic walk.
        }
        if (item.has("placement") && item.opt("placement") !in TOOLBAR_PLACEMENTS)
            throw ContentInvalid("$path.placement", "must be cursor|line-start|block")
        if (item.has("long_press")) {
            val lp = item.optJSONObject("long_press")
                ?: throw ContentInvalid("$path.long_press", "must be an object")
            validateToolbarItem(lp, "$path.long_press", hasDocument, allowMenu = false)
        }
    }

    private fun validateSwipeSide(side: JSONObject, path: String, sideKey: String, ctx: Ctx) {
        if (!side.has("label") || !side.has("on_trigger"))
            throw ContentInvalid(path, "swipe side needs label and on_trigger")
        val trigger = side.optJSONObject("on_trigger")
            ?: throw ContentInvalid("$path.on_trigger", "must be an ActionDescriptor")
        validateAction(trigger, "$path.on_trigger", "$sideKey.on_trigger", ctx)
    }

    /** SPEC 14.1-14.3: the discriminated ActionDescriptor schema. */
    private fun validateAction(obj: JSONObject, path: String, hook: String, ctx: Ctx) {
        val hasAction = obj.has("action")
        val hasBuiltin = obj.has("builtin")
        if (hasAction == hasBuiltin)
            throw ContentInvalid(path, "exactly one of action/builtin")
        val row: ActionRow
        if (hasAction) {
            row = ACTION_SCHEMA.getValue("remote")
            val name = obj.opt("action") as? String
                ?: throw ContentInvalid("$path.action", "must be a string")
            if ('.' !in name)
                throw ContentInvalid("$path.action", "action names contain a dot")
            val policy = obj.opt("when_offline") ?: OFFLINE_DEFAULT
            if (policy !in OFFLINE_POLICIES)
                throw ContentInvalid("$path.when_offline", "unknown offline policy")
            if (policy in setOf("queue", "wake") && !obj.has("ttl_s"))
                throw ContentInvalid(path, "$policy requires ttl_s")
            if (policy == "drop" && (obj.has("ttl_s") || obj.has("dedupe")))
                throw ContentInvalid(path, "ttl_s/dedupe are invalid for drop")
            // SPEC 14.1: ttl_s is an integer 1..604800. Validating it here
            // makes the queue-admission getLong at dispatch time total.
            if (obj.has("ttl_s")) {
                val ttl = obj.opt("ttl_s") as? Number
                    ?: throw ContentInvalid("$path.ttl_s", "must be an integer 1..604800")
                val d = ttl.toDouble()
                if (d != Math.floor(d) || d.isInfinite() || d < 1.0 || d > 604800.0)
                    throw ContentInvalid("$path.ttl_s", "must be an integer 1..604800")
            }
            // SPEC 14.1: confirm is a non-empty string when present.
            if (obj.has("confirm")) {
                val c = obj.opt("confirm")
                if (c !is String || c.isEmpty())
                    throw ContentInvalid("$path.confirm", "must be a non-empty string")
            }
            // SPEC 14.3: a remote descriptor on a value-producing hook MUST
            // NOT author the member the Companion injects.
            INJECTED_MEMBERS[hook]?.let { injected ->
                obj.optJSONObject("args")?.let { args ->
                    for (m in injected)
                        if (args.has(m))
                            throw ContentInvalid("$path.args.$m",
                                "conflicts with the value injected by $hook")
                }
            }
        } else {
            val name = obj.opt("builtin") as? String
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
        if (obj.has("capture_fields")) {
            val cf = obj.optJSONArray("capture_fields")
                ?: throw ContentInvalid("$path.capture_fields", "must be an array")
            if (cf.length().toLong() > ctx.maxCaptureFields)
                throw ContentInvalid("$path.capture_fields", "exceeds max_capture_fields")
            val names = mutableListOf<String>()
            val seen = mutableSetOf<String>()
            for (i in 0 until cf.length()) {
                val nm = cf.opt(i) as? String
                    ?: throw ContentInvalid("$path.capture_fields[$i]", "must be a widget ID")
                if (!seen.add(nm))
                    throw ContentInvalid("$path.capture_fields[$i]", "duplicate capture field")
                names.add(nm)
            }
            ctx.captureRefs.add(path to names)
        }
        for (req in row.required)
            if (req != "builtin" && !obj.has(req))
                throw ContentInvalid(path, "action missing required $req")
        for (key in obj.keySet())
            if (key !in row.required && key !in row.optional && key != "builtin"
                && key != "action")
                throw ContentInvalid("$path.$key", "unknown action member")
    }
}
