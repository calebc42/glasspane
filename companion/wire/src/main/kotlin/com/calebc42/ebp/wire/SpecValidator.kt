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
    private class Ctx(val maxCaptureFields: Long) {
        val ids = mutableSetOf<String>()
        val statefuls = mutableMapOf<String, JSONObject>()
        val captureRefs = mutableListOf<Pair<String, List<String>>>()
        var nodeCount = 0
    }

    /** Validate one SurfaceSpec; returns the stateful nodes by ID. */
    fun validateSurfaceSpec(
        spec: Any?,
        path: String = "spec",
        maxCaptureFields: Long = 64,
    ): Map<String, JSONObject> {
        if (spec !is JSONObject) throw ContentInvalid(path, "spec must be an object")
        val ctx = Ctx(maxCaptureFields)
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
    fun validateStaleSpec(staleSpec: Any?, primaryIsMultiView: Boolean) {
        val statefuls = validateSurfaceSpec(staleSpec, "stale_spec")
        if (statefuls.isNotEmpty())
            throw ContentInvalid("stale_spec", "stateful nodes are prohibited in stale_spec")
        if ((staleSpec as JSONObject).has("views") != primaryIsMultiView)
            throw ContentInvalid("stale_spec", "must use the same variant as spec")
        if (containsEditor(staleSpec))
            throw ContentInvalid("stale_spec", "editor nodes are prohibited in stale_spec")
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
        val known = NODE_SCHEMA.containsKey(node.optString("t"))
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
        val row = NODE_SCHEMA[t] ?: return // SPEC 16.2: unknown types degrade
        for (req in row.required)
            if (!node.has(req))
                throw ContentInvalid(path, "$t missing required $req")
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
                } else {
                    val min = (node.opt("min") as? Number)?.toDouble() ?: 0.0
                    val max = (node.opt("max") as? Number)?.toDouble() ?: 1.0
                    if (min >= max)
                        throw ContentInvalid(path, "slider min must be less than max")
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
            }
        }
        if (t in STATEFUL_NODE_TYPES) {
            val isStateful = t != "editor" || node.optBoolean("publish_state")
            if (isStateful) {
                val id = node.opt("id") as? String
                    ?: throw ContentInvalid(path, "$t requires an id")
                ctx.statefuls[id] = node
            }
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
