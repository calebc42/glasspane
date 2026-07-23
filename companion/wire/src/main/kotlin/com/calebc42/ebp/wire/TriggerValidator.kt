// SPDX-License-Identifier: GPL-3.0-or-later
// The device-trigger module (SPEC 21), validation half. A triggers.set
// replace-set is validated in full BEFORE any registration changes (SPEC
// 21.1). Each entry is validated against the closed trigger-type catalog
// (SPEC 21.5), its state-gate predicates (SPEC 21.7), and its on_fire
// structure (SPEC 21.4), then normalized: every documented value default is
// materialized so that SPEC 4.3 equality between two logical registrations
// reduces to a structural compare (the basis for unchanged-id carry-forward).
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject

/** The device facts a trigger set is validated against (from the report). */
data class TriggerCaps(
    val triggerTypes: Set<String>,
    val stateTypes: Set<String>,
    val trackableStateTypes: Set<String>,
    val triggerCaps: Set<String>,
    val maxResponses: Int,
)

object TriggerValidator {

    private val IDENT = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]*")
    private val POLICIES = setOf("drop", "queue", "wake")
    private val EDGES = setOf("rise", "fall", "both")
    private val WEEK = listOf("mon", "tue", "wed", "thu", "fri", "sat", "sun")

    // ------------------------------------------------------------- entrypoint

    /**
     * SPEC 21.1: validate the whole replace-set and return the normalized
     * (defaults-materialized) entries in order. Throws ContentInvalid whose
     * path identifies the failing trigger; the caller maps it to 1101.
     */
    fun validateSet(params: JSONObject, caps: TriggerCaps): List<JSONObject> {
        for (k in params.keySet()) if (k != "triggers")
            throw ContentInvalid(k, "unknown member")
        val arr = params.opt("triggers") as? JSONArray
            ?: throw ContentInvalid("triggers", "must be an array")
        val out = ArrayList<JSONObject>(arr.length())
        val ids = HashSet<String>()
        for (i in 0 until arr.length()) {
            val t = arr.opt(i) as? JSONObject
                ?: throw ContentInvalid("triggers[$i]", "not an object")
            val norm = normTrigger(t, "triggers[$i]", caps)
            if (!ids.add(norm.getString("id")))
                throw ContentInvalid("triggers[$i].id", "duplicate trigger id")
            out.add(norm)
        }
        return out
    }

    // --------------------------------------------------------- one trigger

    private fun normTrigger(t: JSONObject, path: String, caps: TriggerCaps): JSONObject {
        closed(t, path, "id", "type", "params", "when", "policy",
            "ttl_s", "dedupe", "throttle_s", "on_fire")
        val id = ident(t, "$path.id")
        val type = ident(t, "$path.type")
        if (type !in caps.triggerTypes)
            throw ContentInvalid("$path.type", "type not in device.trigger_types")
        val rawParams = when (val p = t.opt("params")) {
            null -> JSONObject()
            is JSONObject -> p
            else -> throw ContentInvalid("$path.params", "must be an object")
        }
        val params = normParams(type, rawParams, "$path.params", caps)
        val whenArr = when (val w = t.opt("when")) {
            null -> JSONArray()
            is JSONArray -> w
            else -> throw ContentInvalid("$path.when", "must be an array")
        }
        // A trigger gate may use time.window (a civil-time predicate the
        // Companion always evaluates); other types must be advertised.
        val gate = normPredicates(whenArr, "$path.when", caps.stateTypes, allowTimeWindow = true)
        val policy = when (val p = t.opt("policy")) {
            null -> "drop"
            is String -> p
            else -> throw ContentInvalid("$path.policy", "must be a string")
        }
        if (policy !in POLICIES) throw ContentInvalid("$path.policy", "not a policy")
        val durable = policy == "queue" || policy == "wake"
        // SPEC 21.1: ttl_s REQUIRED for queue/wake, forbidden for drop.
        val hasTtl = t.has("ttl_s")
        if (durable && !hasTtl) throw ContentInvalid("$path.ttl_s", "$policy requires ttl_s")
        if (!durable && hasTtl) throw ContentInvalid("$path.ttl_s", "drop forbids ttl_s")
        val ttl = if (hasTtl) intField(t, "$path.ttl_s", 1, 604_800) else null
        // SPEC 21.1: dedupe valid only for queue/wake.
        val hasDedupe = t.has("dedupe")
        if (hasDedupe && !durable) throw ContentInvalid("$path.dedupe", "dedupe needs queue/wake")
        val dedupe = if (hasDedupe) ident(t, "$path.dedupe") else null
        val throttle = if (t.has("throttle_s"))
            intField(t, "$path.throttle_s", 1, 604_800) else null
        val onFire = when (val o = t.opt("on_fire")) {
            null -> JSONArray()
            is JSONArray -> o
            else -> throw ContentInvalid("$path.on_fire", "must be an array")
        }
        val normOnFire = normOnFire(onFire, "$path.on_fire", caps)

        // Canonical normalized entry: fixed members always present, the three
        // conditional members present only when they apply/were supplied.
        val out = JSONObject()
            .put("id", id).put("type", type).put("params", params)
            .put("when", gate).put("policy", policy).put("on_fire", normOnFire)
        if (ttl != null) out.put("ttl_s", ttl)
        if (dedupe != null) out.put("dedupe", dedupe)
        if (throttle != null) out.put("throttle_s", throttle)
        return out
    }

    // --------------------------------------------------- trigger-type params

    private fun normParams(type: String, p: JSONObject, path: String,
                           caps: TriggerCaps): JSONObject = when (type) {
        "time" -> {
            exactlyOne(p, path, "at_ms", "every_s")
            if (p.has("at_ms")) { closed(p, path, "at_ms")
                obj("at_ms", intField(p, "$path.at_ms", 0, 9_007_199_254_740_991L)) }
            else { closed(p, path, "every_s")
                obj("every_s", intField(p, "$path.every_s", 60, 9_007_199_254_740_991L)) }
        }
        "power" -> optEnumParam(p, path, "state", setOf("connected", "disconnected"))
        "battery.level" -> {
            exactlyOne(p, path, "above", "below")
            val key = if (p.has("above")) "above" else "below"
            closed(p, path, key)
            obj(key, intField(p, "$path.$key", 0, 100))
        }
        "screen" -> optEnumParam(p, path, "state", setOf("on", "off", "unlocked"))
        "headset" -> optEnumParam(p, path, "state", setOf("plugged", "unplugged"))
        "airplane" -> optEnumParam(p, path, "state", setOf("on", "off"))
        "boot", "timezone.changed", "manual" -> { closed(p, path); JSONObject() }
        "package" -> {
            closed(p, path, "event", "package")
            val out = JSONObject()
            optEnum(p, "$path.event", "event", setOf("added", "removed"))?.let { out.put("event", it) }
            optStr(p, "$path.package", "package")?.let { out.put("package", it) }
            out
        }
        "state.edge" -> {
            closed(p, path, "when", "edge")
            val w = p.opt("when") as? JSONArray
                ?: throw ContentInvalid("$path.when", "state.edge requires a when array")
            // Edge tracking is over levels only: trackable types, no time.window.
            val gate = normPredicates(w, "$path.when", caps.trackableStateTypes, allowTimeWindow = false)
            if (gate.length() == 0) throw ContentInvalid("$path.when", "must be non-empty")
            val edge = optEnum(p, "$path.edge", "edge", EDGES) ?: "rise"
            JSONObject().put("when", gate).put("edge", edge)
        }
        "network" -> {
            closed(p, path, "event", "transport")
            val out = JSONObject()
            optEnum(p, "$path.event", "event", setOf("available", "lost"))?.let { out.put("event", it) }
            optEnum(p, "$path.transport", "transport", TRANSPORTS)?.let { out.put("transport", it) }
            out
        }
        "wifi.enabled", "bluetooth.enabled" -> {
            closed(p, path, "enabled")
            val out = JSONObject()
            if (p.has("enabled")) out.put("enabled", boolField(p, "$path.enabled"))
            out
        }
        "calendar.event" -> {
            closed(p, path, "event", "calendar", "title_contains")
            val out = JSONObject()
            optEnum(p, "$path.event", "event", setOf("started", "ended"))?.let { out.put("event", it) }
            optStr(p, "$path.calendar", "calendar")?.let { out.put("calendar", it) }
            optNonEmpty(p, "$path.title_contains", "title_contains")?.let { out.put("title_contains", it) }
            out
        }
        "sms.received" -> {
            closed(p, path, "from", "contains", "include_body")
            val out = JSONObject()
            optStr(p, "$path.from", "from")?.let { out.put("from", it) }
            optNonEmpty(p, "$path.contains", "contains")?.let { out.put("contains", it) }
            out.put("include_body", if (p.has("include_body")) boolField(p, "$path.include_body") else false)
        }
        "call.state" -> {
            closed(p, path, "state", "number", "include_number")
            val out = JSONObject()
            optEnum(p, "$path.state", "state", setOf("ringing", "offhook", "idle"))?.let { out.put("state", it) }
            optStr(p, "$path.number", "number")?.let { out.put("number", it) }
            out.put("include_number", if (p.has("include_number")) boolField(p, "$path.include_number") else false)
        }
        else -> throw ContentInvalid("$path", "unknown trigger type")
    }

    private val TRANSPORTS = setOf("wifi", "cellular", "ethernet", "vpn", "bluetooth")

    // A trigger param that is a single optional enum filter: absent => no
    // filter (omit from normalized), never an undocumented default.
    private fun optEnumParam(p: JSONObject, path: String, key: String,
                             allowed: Set<String>): JSONObject {
        closed(p, path, key)
        val out = JSONObject()
        optEnum(p, "$path.$key", key, allowed)?.let { out.put(key, it) }
        return out
    }

    // ----------------------------------------------------- state predicates

    private fun normPredicates(arr: JSONArray, path: String,
                               allowedTypes: Set<String>,
                               allowTimeWindow: Boolean): JSONArray {
        val out = JSONArray()
        for (i in 0 until arr.length()) {
            val p = arr.opt(i) as? JSONObject
                ?: throw ContentInvalid("$path[$i]", "not an object")
            out.put(normPredicate(p, "$path[$i]", allowedTypes, allowTimeWindow))
        }
        return out
    }

    private fun normPredicate(p: JSONObject, path: String,
                              allowedTypes: Set<String>,
                              allowTimeWindow: Boolean): JSONObject {
        val type = p.opt("type") as? String
            ?: throw ContentInvalid("$path.type", "must be a string")
        // time.window is a civil-time predicate: valid in a trigger gate,
        // never a tracked level; every other type must be advertised.
        if (type == "time.window") {
            if (!allowTimeWindow) throw ContentInvalid("$path.type", "time.window not valid here")
        } else if (type !in allowedTypes) {
            throw ContentInvalid("$path.type", "predicate type not advertised")
        }
        val out = JSONObject().put("type", type)
        when (type) {
            "power" -> { closed(p, path, "type", "state")
                out.put("state", optEnum(p, "$path.state", "state", setOf("connected", "disconnected")) ?: "connected") }
            "battery.level" -> { exactlyOne(p, path, "above", "below")
                val key = if (p.has("above")) "above" else "below"
                closed(p, path, "type", key); out.put(key, intField(p, "$path.$key", 0, 100)) }
            "screen" -> { closed(p, path, "type", "state")
                out.put("state", optEnum(p, "$path.state", "state", setOf("on", "off", "unlocked")) ?: "on") }
            "airplane" -> { closed(p, path, "type", "state")
                out.put("state", optEnum(p, "$path.state", "state", setOf("on", "off")) ?: "on") }
            "network" -> { closed(p, path, "type", "transport")
                optEnum(p, "$path.transport", "transport", TRANSPORTS)?.let { out.put("transport", it) } }
            "headset" -> { closed(p, path, "type", "state")
                out.put("state", optEnum(p, "$path.state", "state", setOf("plugged", "unplugged")) ?: "plugged") }
            "wifi.enabled" -> { closed(p, path, "type", "enabled")
                out.put("enabled", if (p.has("enabled")) boolField(p, "$path.enabled") else true) }
            "bluetooth.enabled" -> { closed(p, path, "type", "enabled")
                out.put("enabled", if (p.has("enabled")) boolField(p, "$path.enabled") else true) }
            "calendar.event" -> { closed(p, path, "type", "calendar", "title_contains")
                optStr(p, "$path.calendar", "calendar")?.let { out.put("calendar", it) }
                optNonEmpty(p, "$path.title_contains", "title_contains")?.let { out.put("title_contains", it) } }
            "call.state" -> { closed(p, path, "type", "state")
                out.put("state", optEnum(p, "$path.state", "state", setOf("ringing", "offhook", "idle")) ?: "offhook") }
            "time.window" -> normTimeWindow(p, path, out)
            else -> throw ContentInvalid("$path.type", "unknown predicate type")
        }
        return out
    }

    private fun normTimeWindow(p: JSONObject, path: String, out: JSONObject) {
        closed(p, path, "type", "after", "before", "days")
        hhmm(p, "$path.after", "after")?.let { out.put("after", it) }
        hhmm(p, "$path.before", "before")?.let { out.put("before", it) }
        // days defaults to every day; normalize to the canonical week order.
        val days = p.opt("days")
        if (days == null) {
            out.put("days", JSONArray(WEEK))
        } else {
            val a = days as? JSONArray ?: throw ContentInvalid("$path.days", "must be an array")
            val seen = LinkedHashSet<String>()
            for (i in 0 until a.length()) {
                val d = a.opt(i) as? String ?: throw ContentInvalid("$path.days[$i]", "must be a string")
                if (d !in WEEK) throw ContentInvalid("$path.days[$i]", "not a weekday")
                if (!seen.add(d)) throw ContentInvalid("$path.days[$i]", "duplicate day")
            }
            out.put("days", JSONArray(WEEK.filter { it in seen }))
        }
    }

    private fun hhmm(o: JSONObject, path: String, key: String): String? {
        if (!o.has(key)) return null
        val v = o.opt(key) as? String ?: throw ContentInvalid(path, "must be HH:MM")
        val m = Regex("^([01][0-9]|2[0-3]):[0-5][0-9]$")
        if (!m.matches(v)) throw ContentInvalid(path, "must be HH:MM")
        return v
    }

    // ------------------------------------------------------------- on_fire

    // SPEC 21.4: each entry is {cap, args?} (cap in trigger_caps) or
    // {notify:{title?, text}}. Full execution + substitution is a later atom;
    // here the structure and cap membership are validated at install time.
    private fun normOnFire(arr: JSONArray, path: String, caps: TriggerCaps): JSONArray {
        if (arr.length() > caps.maxResponses)
            throw ContentInvalid(path, "exceeds max_trigger_responses")
        val out = JSONArray()
        for (i in 0 until arr.length()) {
            val e = arr.opt(i) as? JSONObject
                ?: throw ContentInvalid("$path[$i]", "not an object")
            val isNotify = e.has("notify")
            val isCap = e.has("cap")
            if (isNotify == isCap) throw ContentInvalid("$path[$i]", "exactly one of cap or notify")
            if (isCap) {
                closed(e, "$path[$i]", "cap", "args")
                val cap = ident(e, "$path[$i].cap")
                if (cap !in caps.triggerCaps)
                    throw ContentInvalid("$path[$i].cap", "cap not in device.trigger_caps")
                if (e.has("args") && e.opt("args") !is JSONObject)
                    throw ContentInvalid("$path[$i].args", "must be an object")
                out.put(e)
            } else {
                closed(e, "$path[$i]", "notify")
                val n = e.opt("notify") as? JSONObject
                    ?: throw ContentInvalid("$path[$i].notify", "must be an object")
                closed(n, "$path[$i].notify", "title", "text")
                if (n.opt("text") !is String)
                    throw ContentInvalid("$path[$i].notify.text", "text is required")
                if (n.has("title") && n.opt("title") !is String)
                    throw ContentInvalid("$path[$i].notify.title", "must be a string")
                out.put(e)
            }
        }
        return out
    }

    // ---------------------------------------------------------- primitives

    private fun obj(key: String, value: Any) = JSONObject().put(key, value)

    private fun closed(o: JSONObject, path: String, vararg allowed: String) {
        for (k in o.keySet()) if (k !in allowed)
            throw ContentInvalid("$path.$k", "unknown member")
    }

    private fun ident(o: JSONObject, path: String): String {
        val v = o.opt(path.substringAfterLast('.')) as? String
            ?: throw ContentInvalid(path, "must be an identifier")
        if (!IDENT.matches(v)) throw ContentInvalid(path, "must be an identifier")
        return v
    }

    private fun optStr(o: JSONObject, path: String, key: String): String? {
        if (!o.has(key)) return null
        return o.opt(key) as? String ?: throw ContentInvalid(path, "must be a string")
    }

    private fun optNonEmpty(o: JSONObject, path: String, key: String): String? {
        val s = optStr(o, path, key) ?: return null
        if (s.isEmpty()) throw ContentInvalid(path, "must be non-empty")
        return s
    }

    private fun optEnum(o: JSONObject, path: String, key: String, allowed: Set<String>): String? {
        val s = optStr(o, path, key) ?: return null
        if (s !in allowed) throw ContentInvalid(path, "not a permitted value")
        return s
    }

    private fun boolField(o: JSONObject, path: String): Boolean =
        o.opt(path.substringAfterLast('.')) as? Boolean
            ?: throw ContentInvalid(path, "must be a boolean")

    private fun intField(o: JSONObject, path: String, min: Long, max: Long): Long {
        val v = o.opt(path.substringAfterLast('.'))
        if (v !is Number) throw ContentInvalid(path, "must be an integer")
        val d = v.toDouble()
        if (d.isNaN() || d.isInfinite() || d != Math.floor(d))
            throw ContentInvalid(path, "must be an integer")
        val n = v.toLong()
        if (n < min || n > max) throw ContentInvalid(path, "out of range $min..$max")
        return n
    }

    private fun exactlyOne(o: JSONObject, path: String, a: String, b: String) {
        if (o.has(a) == o.has(b)) throw ContentInvalid(path, "exactly one of $a or $b")
    }
}
