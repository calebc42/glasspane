// SPDX-License-Identifier: GPL-3.0-or-later
// SurfaceSpec validation (SPEC 16-17 receiver duties): the whole document
// validates before any persistent or visible state changes (SPEC 13.2).
// Rejection carries the failing object path for error.data.path.
//
// What rejects (SPEC 16.1): a malformed node, missing required member,
// invalid action descriptor, duplicate authored ID, an authored password
// seed, or an authored single_line value containing U+000A (SPEC 17.4).
// What does NOT reject: unknown node types (SPEC 16.2 degrade) and unknown
// optional fields (SPEC 16.3) — those are the receiver's tolerance duties.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject

class ContentInvalid(val path: String, val reason: String) :
    Exception("$reason at $path")

private val IDENTIFIER = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]*")

object SpecValidator {

    /** Validate one SurfaceSpec; returns the stateful nodes by ID. */
    fun validateSurfaceSpec(spec: Any?, path: String = "spec"): Map<String, JSONObject> {
        if (spec !is JSONObject) throw ContentInvalid(path, "spec must be an object")
        val seenIds = mutableSetOf<String>()
        val statefuls = mutableMapOf<String, JSONObject>()
        if (spec.has("views")) {
            val views = spec.optJSONObject("views")
                ?: throw ContentInvalid("$path.views", "views must be an object")
            if (views.length() == 0)
                throw ContentInvalid("$path.views", "views must be non-empty")
            val initial = spec.opt("initial_view")
            if (initial !is String || !views.has(initial))
                throw ContentInvalid("$path.initial_view", "must name an existing view")
            for (name in views.keySet())
                walk(views.get(name), "$path.views.$name", seenIds, statefuls)
        } else {
            walk(spec, path, seenIds, statefuls)
        }
        return statefuls
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

    private fun walk(value: Any?, path: String, ids: MutableSet<String>,
                     statefuls: MutableMap<String, JSONObject>) {
        when (value) {
            is JSONArray ->
                for (i in 0 until value.length())
                    walk(value.get(i), "$path[$i]", ids, statefuls)
            is JSONObject -> {
                if (value.has("t")) validateNode(value, path, ids, statefuls)
                for (key in value.keySet()) {
                    val child = value.get(key)
                    if (key in ACTION_HOOK_KEYS && child is JSONObject)
                        validateAction(child, "$path.$key")
                    else if ((key == "swipe_start" || key == "swipe_end") && child is JSONObject)
                        validateSwipeSide(child, "$path.$key")
                    else walk(child, "$path.$key", ids, statefuls)
                }
            }
            else -> Unit // scalars carry no schema
        }
    }

    private fun validateNode(node: JSONObject, path: String, ids: MutableSet<String>,
                             statefuls: MutableMap<String, JSONObject>) {
        val t = node.opt("t") as? String
            ?: throw ContentInvalid(path, "node discriminator t must be a string")
        // SPEC 16.1: every authored node ID is unique across the document.
        (node.opt("id") as? String)?.let { id ->
            if (!IDENTIFIER.matches(id) || id.length > 128)
                throw ContentInvalid("$path.id", "invalid identifier")
            if (!ids.add(id)) throw ContentInvalid("$path.id", "duplicate node ID")
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
                val options = node.getJSONArray("options")
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
                statefuls[id] = node
            }
        }
    }

    private fun validateSwipeSide(side: JSONObject, path: String) {
        if (!side.has("label") || !side.has("on_trigger"))
            throw ContentInvalid(path, "swipe side needs label and on_trigger")
        val trigger = side.optJSONObject("on_trigger")
            ?: throw ContentInvalid("$path.on_trigger", "must be an ActionDescriptor")
        validateAction(trigger, "$path.on_trigger")
    }

    /** SPEC 14.1-14.2: the discriminated ActionDescriptor schema. */
    fun validateAction(obj: JSONObject, path: String) {
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
        } else {
            val name = obj.opt("builtin") as? String
                ?: throw ContentInvalid("$path.builtin", "must be a string")
            // SPEC 14.2: an unknown builtin rejects the containing document.
            row = ACTION_SCHEMA[name]
                ?: throw ContentInvalid("$path.builtin", "unknown builtin $name")
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
