// SPDX-License-Identifier: GPL-3.0-or-later
// The device-trigger module (SPEC 21), validation half. A triggers.set
// replace-set is validated in full BEFORE any registration changes (SPEC
// 21.1). Each entry is validated against the closed trigger-type catalog
// (SPEC 21.5), its state-gate predicates (SPEC 21.7), and its on_fire
// structure (SPEC 21.4), then normalized: every documented value default is
// materialized so that SPEC 4.3 equality between two logical registrations
// reduces to a structural compare (the basis for unchanged-id carry-forward).
//
// C3: the normalized entry is BUILT, never mutated — a kotlinx JsonObject is
// immutable, so every accumulation below is a `buildJsonObject`/`buildJsonArray`
// whose value is the result. The accept-time normalization this file already
// practised (read a number however it was spelled, re-emit it as a Long) is
// unchanged and now goes through [integralLongOrNull].
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The device facts a trigger set is validated against (from the report). */
data class TriggerCaps(
    val triggerTypes: Set<String>,
    val stateTypes: Set<String>,
    val trackableStateTypes: Set<String>,
    val triggerCaps: Set<String>,
    val maxResponses: Int,
    /** SPEC 21.4: whether the user approved substituting sensitive-source
     * (sms/call/calendar) data into an on_fire sink. Default deny. */
    val sensitiveSubstitutionApproved: Boolean = false,
)

object TriggerValidator {

    // SPEC 4.4: 1..128 ASCII chars — bounds trigger id/type/dedupe length.
    private val IDENT = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}")
    private val POLICIES = setOf("drop", "queue", "wake")
    private val EDGES = setOf("rise", "fall", "both")
    private val WEEK = listOf("mon", "tue", "wed", "thu", "fri", "sat", "sun")
    // SPEC 21.4: sources whose data reaching a sink needs explicit approval.
    private val SENSITIVE = setOf("sms.received", "call.state", "calendar.event")
    // SPEC 21.5: sms.received/call.state fire payloads MUST be keystore-encrypted
    // at rest if queued. Until that encryption seam exists, a durable policy is
    // refused for them so a sensitive payload can never land plaintext in the
    // durable queue (drop, RECOMMENDED anyway, is the only accepted policy).
    private val ENCRYPTED_IF_QUEUED = setOf("sms.received", "call.state")
    // SPEC 21.4: caps that MUST NOT appear in trigger_caps / on_fire (they are
    // interactive, unbounded, or return non-{} results).
    private val FORBIDDEN_TRIGGER_CAPS = setOf("settings.open", "apps.list",
        "clipboard.read", "shortcut.pin", "shortcuts.set", "trigger.fire")

    // ------------------------------------------------------------- entrypoint

    /**
     * SPEC 21.1: validate the whole replace-set and return the normalized
     * (defaults-materialized) entries in order. Throws ContentInvalid whose
     * path identifies the failing trigger; the caller maps it to 1101.
     */
    fun validateSet(params: JsonObject, caps: TriggerCaps): List<JsonObject> {
        for (k in params.keys) if (k != "triggers")
            throw ContentInvalid(k, "unknown member")
        val arr = params.arrOrNull("triggers")
            ?: throw ContentInvalid("triggers", "must be an array")
        val out = ArrayList<JsonObject>(arr.size)
        val ids = HashSet<String>()
        for (i in arr.indices) {
            val t = arr[i] as? JsonObject
                ?: throw ContentInvalid("triggers[$i]", "not an object")
            val norm = normTrigger(t, "triggers[$i]", caps)
            if (!ids.add(norm.reqString("id")))
                throw ContentInvalid("triggers[$i].id", "duplicate trigger id")
            out.add(norm)
        }
        return out
    }

    // --------------------------------------------------------- one trigger

    private fun normTrigger(t: JsonObject, path: String, caps: TriggerCaps): JsonObject {
        closed(t, path, "id", "type", "params", "when", "policy",
            "ttl_s", "dedupe", "throttle_s", "on_fire")
        val id = ident(t, "$path.id")
        val type = ident(t, "$path.type")
        if (type !in caps.triggerTypes)
            throw ContentInvalid("$path.type", "type not in device.trigger_types")
        // Absent => the documented default. Present but of the wrong kind — an
        // explicit JSON null included — is a content fault, which is exactly
        // what the org.json `opt` + cast read here (JSONObject.NULL is not a
        // JSONObject); JsonNull is not a JsonObject either.
        val rawParams = if ("params" in t)
            t.objOrNull("params") ?: throw ContentInvalid("$path.params", "must be an object")
        else JsonObject(emptyMap())
        val params = normParams(type, rawParams, "$path.params", caps)
        val whenArr = if ("when" in t)
            t.arrOrNull("when") ?: throw ContentInvalid("$path.when", "must be an array")
        else JsonArray(emptyList())
        // A trigger gate may use time.window (a civil-time predicate the
        // Companion always evaluates); other types must be advertised.
        val gate = normPredicates(whenArr, "$path.when", caps.stateTypes, allowTimeWindow = true)
        val policy = if ("policy" in t)
            t.stringOrNull("policy") ?: throw ContentInvalid("$path.policy", "must be a string")
        else "drop"
        if (policy !in POLICIES) throw ContentInvalid("$path.policy", "not a policy")
        val durable = policy == "queue" || policy == "wake"
        if (durable && type in ENCRYPTED_IF_QUEUED)
            throw ContentInvalid("$path.policy", "sensitive type requires policy drop")
        // SPEC 21.1: ttl_s REQUIRED for queue/wake, forbidden for drop.
        val hasTtl = "ttl_s" in t
        if (durable && !hasTtl) throw ContentInvalid("$path.ttl_s", "$policy requires ttl_s")
        if (!durable && hasTtl) throw ContentInvalid("$path.ttl_s", "drop forbids ttl_s")
        val ttl = if (hasTtl) intField(t, "$path.ttl_s", 1, 604_800) else null
        // SPEC 21.1: dedupe valid only for queue/wake.
        val hasDedupe = "dedupe" in t
        if (hasDedupe && !durable) throw ContentInvalid("$path.dedupe", "dedupe needs queue/wake")
        val dedupe = if (hasDedupe) ident(t, "$path.dedupe") else null
        val throttle = if ("throttle_s" in t)
            intField(t, "$path.throttle_s", 1, 604_800) else null
        val onFire = if ("on_fire" in t)
            t.arrOrNull("on_fire") ?: throw ContentInvalid("$path.on_fire", "must be an array")
        else JsonArray(emptyList())
        val normOnFire = normOnFire(onFire, "$path.on_fire", caps)
        // SPEC 21.4 (amendment #42): routing sensitive-source data into a sink
        // needs approval, which is per (source type, sink kind) and default-deny.
        // The current seam is a single conservative boolean (deny unless the
        // host approved), which is safe but coarse — when an approval UI lands,
        // it should carry a set of approved (source, sink) pairs, not a blanket
        // flag. Today's reference never sets it, so sensitive substitution is
        // always rejected.
        if (type in SENSITIVE && !caps.sensitiveSubstitutionApproved &&
            Substitution.referencesData(normOnFire))
            throw ContentInvalid("$path.on_fire", "sensitive substitution requires approval")

        // Canonical normalized entry: fixed members always present, the three
        // conditional members present only when they apply/were supplied. The
        // null guards are load-bearing in a way they were not before: org.json's
        // put(k, null) REMOVED the member, while kotlinx's put(k, null) writes a
        // JSON null — an unguarded put would materialize `"ttl_s": null` and
        // break SPEC 4.3 equality against a bare entry.
        return buildJsonObject {
            put("id", id)
            put("type", type)
            put("params", params)
            put("when", gate)
            put("policy", policy)
            put("on_fire", normOnFire)
            if (ttl != null) put("ttl_s", ttl)
            if (dedupe != null) put("dedupe", dedupe)
            if (throttle != null) put("throttle_s", throttle)
        }
    }

    // --------------------------------------------------- trigger-type params

    private fun normParams(type: String, p: JsonObject, path: String,
                           caps: TriggerCaps): JsonObject = when (type) {
        "time" -> {
            exactlyOne(p, path, "at_ms", "every_s")
            if ("at_ms" in p) { closed(p, path, "at_ms")
                obj("at_ms", intField(p, "$path.at_ms", 0, 9_007_199_254_740_991L)) }
            else { closed(p, path, "every_s")
                obj("every_s", intField(p, "$path.every_s", 60, 9_007_199_254_740_991L)) }
        }
        "power" -> optEnumParam(p, path, "state", setOf("connected", "disconnected"))
        "battery.level" -> {
            exactlyOne(p, path, "above", "below")
            val key = if ("above" in p) "above" else "below"
            closed(p, path, key)
            obj(key, intField(p, "$path.$key", 0, 100))
        }
        "screen" -> optEnumParam(p, path, "state", setOf("on", "off", "unlocked"))
        "headset" -> optEnumParam(p, path, "state", setOf("plugged", "unplugged"))
        "airplane" -> optEnumParam(p, path, "state", setOf("on", "off"))
        "boot", "timezone.changed", "manual" -> { closed(p, path); JsonObject(emptyMap()) }
        "package" -> {
            closed(p, path, "event", "package")
            buildJsonObject {
                optEnum(p, "$path.event", "event", setOf("added", "removed"))?.let { put("event", it) }
                optStr(p, "$path.package", "package")?.let { put("package", it) }
            }
        }
        "state.edge" -> {
            closed(p, path, "when", "edge")
            val w = p.arrOrNull("when")
                ?: throw ContentInvalid("$path.when", "state.edge requires a when array")
            // Edge tracking is over levels only: trackable types, no time.window.
            val gate = normPredicates(w, "$path.when", caps.trackableStateTypes, allowTimeWindow = false)
            if (gate.isEmpty()) throw ContentInvalid("$path.when", "must be non-empty")
            val edge = optEnum(p, "$path.edge", "edge", EDGES) ?: "rise"
            buildJsonObject { put("when", gate); put("edge", edge) }
        }
        "network" -> {
            closed(p, path, "event", "transport")
            buildJsonObject {
                optEnum(p, "$path.event", "event", setOf("available", "lost"))?.let { put("event", it) }
                optEnum(p, "$path.transport", "transport", TRANSPORTS)?.let { put("transport", it) }
            }
        }
        "wifi.enabled", "bluetooth.enabled" -> {
            closed(p, path, "enabled")
            buildJsonObject {
                if ("enabled" in p) put("enabled", boolField(p, "$path.enabled"))
            }
        }
        "calendar.event" -> {
            closed(p, path, "event", "calendar", "title_contains")
            buildJsonObject {
                optEnum(p, "$path.event", "event", setOf("started", "ended"))?.let { put("event", it) }
                optStr(p, "$path.calendar", "calendar")?.let { put("calendar", it) }
                optNonEmpty(p, "$path.title_contains", "title_contains")?.let { put("title_contains", it) }
            }
        }
        "sms.received" -> {
            closed(p, path, "from", "contains", "include_body")
            buildJsonObject {
                optStr(p, "$path.from", "from")?.let { put("from", it) }
                optNonEmpty(p, "$path.contains", "contains")?.let { put("contains", it) }
                put("include_body",
                    if ("include_body" in p) boolField(p, "$path.include_body") else false)
            }
        }
        "call.state" -> {
            closed(p, path, "state", "number", "include_number")
            buildJsonObject {
                optEnum(p, "$path.state", "state", setOf("ringing", "offhook", "idle"))?.let { put("state", it) }
                optStr(p, "$path.number", "number")?.let { put("number", it) }
                put("include_number",
                    if ("include_number" in p) boolField(p, "$path.include_number") else false)
            }
        }
        else -> throw ContentInvalid("$path", "unknown trigger type")
    }

    private val TRANSPORTS = setOf("wifi", "cellular", "ethernet", "vpn", "bluetooth")

    // A trigger param that is a single optional enum filter: absent => no
    // filter (omit from normalized), never an undocumented default.
    private fun optEnumParam(p: JsonObject, path: String, key: String,
                             allowed: Set<String>): JsonObject {
        closed(p, path, key)
        return buildJsonObject {
            optEnum(p, "$path.$key", key, allowed)?.let { put(key, it) }
        }
    }

    // ----------------------------------------------------- state predicates

    private fun normPredicates(arr: JsonArray, path: String,
                               allowedTypes: Set<String>,
                               allowTimeWindow: Boolean): JsonArray =
        buildJsonArray {
            for (i in arr.indices) {
                val p = arr[i] as? JsonObject
                    ?: throw ContentInvalid("$path[$i]", "not an object")
                add(normPredicate(p, "$path[$i]", allowedTypes, allowTimeWindow))
            }
        }

    private fun normPredicate(p: JsonObject, path: String,
                              allowedTypes: Set<String>,
                              allowTimeWindow: Boolean): JsonObject {
        val type = p.stringOrNull("type")
            ?: throw ContentInvalid("$path.type", "must be a string")
        // time.window is a civil-time predicate: valid in a trigger gate,
        // never a tracked level; every other type must be advertised.
        if (type == "time.window") {
            if (!allowTimeWindow) throw ContentInvalid("$path.type", "time.window not valid here")
        } else if (type !in allowedTypes) {
            throw ContentInvalid("$path.type", "predicate type not advertised")
        }
        // The normalized predicate is accumulated in the BUILDER (the only
        // mutable form a kotlinx object has) rather than in a JsonObject.
        return buildJsonObject {
            put("type", type)
            when (type) {
                "power" -> { closed(p, path, "type", "state")
                    put("state", optEnum(p, "$path.state", "state", setOf("connected", "disconnected")) ?: "connected") }
                "battery.level" -> { exactlyOne(p, path, "above", "below")
                    val key = if ("above" in p) "above" else "below"
                    closed(p, path, "type", key); put(key, intField(p, "$path.$key", 0, 100)) }
                "screen" -> { closed(p, path, "type", "state")
                    put("state", optEnum(p, "$path.state", "state", setOf("on", "off", "unlocked")) ?: "on") }
                "airplane" -> { closed(p, path, "type", "state")
                    put("state", optEnum(p, "$path.state", "state", setOf("on", "off")) ?: "on") }
                "network" -> { closed(p, path, "type", "transport")
                    optEnum(p, "$path.transport", "transport", TRANSPORTS)?.let { put("transport", it) } }
                "headset" -> { closed(p, path, "type", "state")
                    put("state", optEnum(p, "$path.state", "state", setOf("plugged", "unplugged")) ?: "plugged") }
                "wifi.enabled" -> { closed(p, path, "type", "enabled")
                    put("enabled", if ("enabled" in p) boolField(p, "$path.enabled") else true) }
                "bluetooth.enabled" -> { closed(p, path, "type", "enabled")
                    put("enabled", if ("enabled" in p) boolField(p, "$path.enabled") else true) }
                "calendar.event" -> { closed(p, path, "type", "calendar", "title_contains")
                    optStr(p, "$path.calendar", "calendar")?.let { put("calendar", it) }
                    optNonEmpty(p, "$path.title_contains", "title_contains")?.let { put("title_contains", it) } }
                "call.state" -> { closed(p, path, "type", "state")
                    put("state", optEnum(p, "$path.state", "state", setOf("ringing", "offhook", "idle")) ?: "offhook") }
                "time.window" -> normTimeWindow(p, path, this)
                else -> throw ContentInvalid("$path.type", "unknown predicate type")
            }
        }
    }

    private fun normTimeWindow(p: JsonObject, path: String, out: JsonObjectBuilder) {
        closed(p, path, "type", "after", "before", "days")
        hhmm(p, "$path.after", "after")?.let { out.put("after", it) }
        hhmm(p, "$path.before", "before")?.let { out.put("before", it) }
        // days defaults to every day; normalize to the canonical week order.
        val days = p["days"]
        if (days == null) {
            out.put("days", week(WEEK))
        } else {
            val a = days as? JsonArray ?: throw ContentInvalid("$path.days", "must be an array")
            val seen = LinkedHashSet<String>()
            for (i in a.indices) {
                // Element-level string read: the same isString guard a member
                // read gets, so a number, a boolean or JSON null is a fault
                // here rather than its own spelling.
                val d = a[i].asStringOrNull()
                    ?: throw ContentInvalid("$path.days[$i]", "must be a string")
                if (d !in WEEK) throw ContentInvalid("$path.days[$i]", "not a weekday")
                if (!seen.add(d)) throw ContentInvalid("$path.days[$i]", "duplicate day")
            }
            out.put("days", week(WEEK.filter { it in seen }))
        }
    }

    private fun week(days: List<String>): JsonArray = JsonArray(days.map { JsonPrimitive(it) })

    private fun hhmm(o: JsonObject, path: String, key: String): String? {
        if (key !in o) return null
        val v = o.stringOrNull(key) ?: throw ContentInvalid(path, "must be HH:MM")
        val m = Regex("^([01][0-9]|2[0-3]):[0-5][0-9]$")
        if (!m.matches(v)) throw ContentInvalid(path, "must be HH:MM")
        return v
    }

    // ------------------------------------------------------------- on_fire

    // SPEC 21.4: each entry is {cap, args?} (cap in trigger_caps) or
    // {notify:{title?, text}}. Full execution + substitution is a later atom;
    // here the structure and cap membership are validated at install time.
    private fun normOnFire(arr: JsonArray, path: String, caps: TriggerCaps): JsonArray {
        if (arr.size > caps.maxResponses)
            throw ContentInvalid(path, "exceeds max_trigger_responses")
        return buildJsonArray {
            for (i in arr.indices) {
                val e = arr[i] as? JsonObject
                    ?: throw ContentInvalid("$path[$i]", "not an object")
                val isNotify = "notify" in e
                val isCap = "cap" in e
                if (isNotify == isCap) throw ContentInvalid("$path[$i]", "exactly one of cap or notify")
                if (isCap) {
                    closed(e, "$path[$i]", "cap", "args")
                    val cap = ident(e, "$path[$i].cap")
                    if (cap in FORBIDDEN_TRIGGER_CAPS)
                        throw ContentInvalid("$path[$i].cap", "cap forbidden in on_fire")
                    if (cap !in caps.triggerCaps)
                        throw ContentInvalid("$path[$i].cap", "cap not in device.trigger_caps")
                    if ("args" in e && e["args"] !is JsonObject)
                        throw ContentInvalid("$path[$i].args", "must be an object")
                    // The entry is carried through verbatim — an immutable tree
                    // is safe to share, so no defensive copy is taken and no
                    // number is respelled (OnFireTest: "number untouched").
                    add(e)
                } else {
                    closed(e, "$path[$i]", "notify")
                    val n = e.objOrNull("notify")
                        ?: throw ContentInvalid("$path[$i].notify", "must be an object")
                    closed(n, "$path[$i].notify", "title", "text")
                    if (n.stringOrNull("text") == null)
                        throw ContentInvalid("$path[$i].notify.text", "text is required")
                    if ("title" in n && n.stringOrNull("title") == null)
                        throw ContentInvalid("$path[$i].notify.title", "must be a string")
                    add(e)
                }
            }
        }
    }

    // ---------------------------------------------------------- primitives

    private fun obj(key: String, value: Long) = buildJsonObject { put(key, value) }

    private fun closed(o: JsonObject, path: String, vararg allowed: String) {
        for (k in o.keys) if (k !in allowed)
            throw ContentInvalid("$path.$k", "unknown member")
    }

    private fun ident(o: JsonObject, path: String): String {
        val v = o.stringOrNull(path.substringAfterLast('.'))
            ?: throw ContentInvalid(path, "must be an identifier")
        if (!IDENT.matches(v)) throw ContentInvalid(path, "must be an identifier")
        return v
    }

    private fun optStr(o: JsonObject, path: String, key: String): String? {
        if (key !in o) return null
        return o.stringOrNull(key) ?: throw ContentInvalid(path, "must be a string")
    }

    private fun optNonEmpty(o: JsonObject, path: String, key: String): String? {
        val s = optStr(o, path, key) ?: return null
        if (s.isEmpty()) throw ContentInvalid(path, "must be non-empty")
        return s
    }

    private fun optEnum(o: JsonObject, path: String, key: String, allowed: Set<String>): String? {
        val s = optStr(o, path, key) ?: return null
        if (s !in allowed) throw ContentInvalid(path, "not a permitted value")
        return s
    }

    private fun boolField(o: JsonObject, path: String): Boolean =
        o.boolOrNull(path.substringAfterLast('.'))
            ?: throw ContentInvalid(path, "must be a boolean")

    /**
     * An integral JSON number in [min, max]. The value is normalized to a Long
     * at ACCEPT time, whatever the sender spelled: `60` and `60.0` are the same
     * ttl_s, and the normalized entry re-emits the integer — so SPEC 4.3
     * equality (and therefore unchanged-id carry-forward) never turns on a
     * respelling. Fractions, strings, booleans and JSON null are refused.
     */
    private fun intField(o: JsonObject, path: String, min: Long, max: Long): Long {
        val n = integralLongOrNull(o[path.substringAfterLast('.')])
            ?: throw ContentInvalid(path, "must be an integer")
        if (n < min || n > max) throw ContentInvalid(path, "out of range $min..$max")
        return n
    }

    private fun exactlyOne(o: JsonObject, path: String, a: String, b: String) {
        if ((a in o) == (b in o)) throw ContentInvalid(path, "exactly one of $a or $b")
    }
}
