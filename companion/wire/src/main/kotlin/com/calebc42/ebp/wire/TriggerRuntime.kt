// SPDX-License-Identifier: GPL-3.0-or-later
// The device-trigger firing runtime (SPEC 21.2/21.3/21.5/21.6). Device
// sources feed observations in; this decides which are *admitted* occurrences
// and drives the SPEC 21.2 order for each: evaluate the state gate and
// throttle, then (on success) commit throttle state and emit trigger.fired
// through the durable event pipeline. Level types are silently baselined so a
// sticky report never fires — only a later crossing/transition/edge does.
// Pure logic: the clock, current state, and event emission are injected, so
// the semantics are testable without any Android source (those arrive in a
// later atom and simply call onSample/onExternal/armBaselines).
package com.calebc42.ebp.wire

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject

class TriggerRuntime(
    private val store: TriggerStore,
    /** Milliseconds; rollback-resistant wall time (queue.effectiveNow). */
    private val now: () -> Long,
    /** Civil-time zone for time.window predicates. */
    private val zone: ZoneId,
    /** Current sample object for a state type, or null if unavailable. */
    private val stateProvider: (String) -> JSONObject?,
    /** Route an admitted trigger.fired for this registration + fire data. */
    private val emit: (TriggerStore.Registration, JSONObject) -> Unit,
) {

    private val WEEK = listOf(DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY,
        DayOfWeek.THURSDAY, DayOfWeek.FRIDAY, DayOfWeek.SATURDAY, DayOfWeek.SUNDAY)
    private val DAY_KEY = mapOf(
        DayOfWeek.MONDAY to "mon", DayOfWeek.TUESDAY to "tue", DayOfWeek.WEDNESDAY to "wed",
        DayOfWeek.THURSDAY to "thu", DayOfWeek.FRIDAY to "fri", DayOfWeek.SATURDAY to "sat",
        DayOfWeek.SUNDAY to "sun")

    // Enum state types whose primary field is a single value; a present filter
    // fires on transition INTO that value, an absent filter on any change.
    private val ENUM_FIELD = mapOf(
        "screen" to "state", "power" to "state", "headset" to "state",
        "airplane" to "state", "call.state" to "state",
        "wifi.enabled" to "enabled", "bluetooth.enabled" to "enabled")

    // ------------------------------------------------------- arming/baseline

    /**
     * SPEC 21.5/21.6: establish the silent baseline for every level and edge
     * registration from the current state, so arming or restoring never fires;
     * a later observed transition is required for the first occurrence. SPEC
     * 21.1: a carried-forward (unchanged) registration already holds its
     * baseline — this only fills a fresh one, never re-baselines it.
     */
    fun armBaselines(identity: String) {
        for (reg in store.registrations(identity)) {
            val type = reg.entry.getString("type")
            when {
                type == "state.edge" ->
                    if (!reg.baselines.containsKey("edge"))
                        reg.baselines["edge"] = edgeHolds(reg)
                type == "battery.level" ->
                    if (!reg.baselines.containsKey("side")) stateProvider(type)?.let {
                        reg.baselines["side"] = batterySide(reg.entry, it) }
                type in ENUM_FIELD -> {
                    val field = ENUM_FIELD.getValue(type)
                    if (reg.entry.getJSONObject("params").has(field)) {
                        if (!reg.baselines.containsKey("side")) stateProvider(type)?.let {
                            reg.baselines["side"] = enumMatch(reg.entry, field, it) }
                    } else if (!reg.baselines.containsKey("value")) stateProvider(type)?.let {
                        reg.baselines["value"] = it.opt(field) }
                }
            }
        }
    }

    // ------------------------------------------------------ observation feed

    /**
     * SPEC 21.5: a level-type observation. Level registrations of this type
     * evaluate a crossing/transition against their baseline; every state.edge
     * re-evaluates because any tracked level may have flipped its conjunction.
     */
    fun onSample(identity: String, type: String, sample: JSONObject) {
        for (reg in store.registrations(identity)) {
            if (reg.entry.getString("type") != type) continue
            when {
                type == "battery.level" -> crossing(reg, batterySide(reg.entry, sample), sample)
                type in ENUM_FIELD -> {
                    val field = ENUM_FIELD.getValue(type)
                    if (reg.entry.getJSONObject("params").has(field))
                        crossing(reg, enumMatch(reg.entry, field, sample), sample)
                    else valueChange(reg, sample.opt(field), sample)
                }
            }
        }
        reEvaluateEdges(identity)
    }

    /**
     * SPEC 21.5: an external occurrence (package, sms.received, boot, time,
     * timezone.changed, manual). These have no sticky baseline — an admitted
     * occurrence is the event itself, subject to the gate and throttle.
     */
    fun onExternal(identity: String, type: String, data: JSONObject) {
        for (reg in store.registrations(identity))
            if (reg.entry.getString("type") == type) tryAdmit(reg, data)
    }

    // -------------------------------------------------------- crossing logic

    // SPEC 21.5: a filtered level fires only when entering the configured side.
    private fun crossing(reg: TriggerStore.Registration, side: Boolean, data: JSONObject) {
        val prev = reg.baselines["side"] as Boolean?
        if (prev == null) { reg.baselines["side"] = side; return } // silent baseline
        if (!prev && side) tryAdmit(reg, data)
        reg.baselines["side"] = side
    }

    // SPEC 21.5: an unfiltered level fires on any change of its primary value.
    private fun valueChange(reg: TriggerStore.Registration, value: Any?, data: JSONObject) {
        val prev = reg.baselines["value"]
        if (!reg.baselines.containsKey("value")) { reg.baselines["value"] = value; return }
        if (prev != value) tryAdmit(reg, data)
        reg.baselines["value"] = value
    }

    private fun batterySide(entry: JSONObject, sample: JSONObject): Boolean {
        val p = entry.getJSONObject("params")
        val level = sample.optInt("level", -1)
        return if (p.has("above")) level > p.getInt("above") else level < p.getInt("below")
    }

    private fun enumMatch(entry: JSONObject, field: String, sample: JSONObject): Boolean =
        sample.opt(field) == entry.getJSONObject("params").opt(field)

    // ------------------------------------------------------------- edges

    private fun reEvaluateEdges(identity: String) {
        for (reg in store.registrations(identity)) {
            if (reg.entry.getString("type") != "state.edge") continue
            val holds = edgeHolds(reg)
            val prev = reg.baselines["edge"] as Boolean?
            if (prev == null) { reg.baselines["edge"] = holds; continue } // silent
            val edge = reg.entry.getJSONObject("params").getString("edge")
            val rise = !prev && holds && (edge == "rise" || edge == "both")
            val fall = prev && !holds && (edge == "fall" || edge == "both")
            reg.baselines["edge"] = holds
            if (rise || fall)
                tryAdmit(reg, JSONObject().put("holds", holds)
                    .put("edge", if (holds) "rise" else "fall"))
        }
    }

    // The tracked conjunction (SPEC 21.6 params.when), distinct from the
    // row-level `when` gate evaluated at admission.
    private fun edgeHolds(reg: TriggerStore.Registration): Boolean =
        allHold(reg.entry.getJSONObject("params").getJSONArray("when"))

    // ----------------------------------------------- admission (SPEC 21.2)

    private fun tryAdmit(reg: TriggerStore.Registration, data: JSONObject) {
        // Step 1: state gate + throttle eligibility. A failure consumes nothing.
        if (!allHold(reg.entry.getJSONArray("when"))) return
        val throttle = reg.entry.optLong("throttle_s", 0)
        if (throttle > 0) {
            val floor = reg.throttleFloorMs
            if (floor != null && now() - floor < throttle * 1000) return
        }
        // Steps 2-3: freeze + commit the throttle floor before emitting.
        reg.throttleFloorMs = now()
        // Step 4 (on_fire) is a later atom. Step 5: remote event eligible.
        emit(reg, data)
    }

    // ---------------------------------------------- gate predicate eval

    private fun allHold(preds: JSONArray): Boolean {
        for (i in 0 until preds.length())
            if (!predicateHolds(preds.getJSONObject(i))) return false
        return true
    }

    // SPEC 21.3/21.7: a predicate that cannot be evaluated does not hold.
    private fun predicateHolds(p: JSONObject): Boolean {
        val type = p.getString("type")
        if (type == "time.window") return timeWindowHolds(p)
        val s = stateProvider(type) ?: return false
        return when (type) {
            "power" -> s.optString("state") == p.optString("state", "connected")
            "battery.level" ->
                if (p.has("above")) s.optInt("level", -1) > p.getInt("above")
                else s.optInt("level", -1) < p.getInt("below")
            "screen" -> {
                val want = p.optString("state", "on"); val cur = s.optString("state")
                if (want == "on") cur == "on" || cur == "unlocked" else cur == want
            }
            "airplane" -> s.optString("state") == p.optString("state", "on")
            "network" -> s.optBoolean("connected") &&
                (!p.has("transport") || transportsHave(s, p.getString("transport")))
            "headset" -> s.optString("state") == p.optString("state", "plugged")
            "wifi.enabled" -> s.optBoolean("enabled") == p.optBoolean("enabled", true)
            "bluetooth.enabled" ->
                s.has("enabled") && s.optBoolean("enabled") == p.optBoolean("enabled", true)
            "calendar.event" -> s.optBoolean("ongoing")
            "call.state" -> s.optString("state") == p.optString("state", "offhook")
            else -> false
        }
    }

    private fun transportsHave(s: JSONObject, transport: String): Boolean {
        val arr = s.optJSONArray("transports") ?: return false
        return (0 until arr.length()).any { arr.opt(it) == transport }
    }

    // SPEC 21.7: local civil time in the half-open window; wraps at midnight
    // when after > before; days selects the civil day the after-portion begins.
    private fun timeWindowHolds(p: JSONObject): Boolean {
        val zdt = Instant.ofEpochMilli(now()).atZone(zone)
        val nowT = zdt.toLocalTime()
        val after = p.optString("after", "").takeIf { it.isNotEmpty() }?.let { LocalTime.parse(it) }
        val before = p.optString("before", "").takeIf { it.isNotEmpty() }?.let { LocalTime.parse(it) }
        val days = p.optJSONArray("days")?.let { a ->
            (0 until a.length()).map { a.getString(it) }.toSet()
        } ?: WEEK.map { DAY_KEY.getValue(it) }.toSet()
        val wraps = after != null && before != null && after > before
        val inTime = when {
            after == null && before == null -> true
            after == null -> nowT < before
            before == null -> nowT >= after
            !wraps -> nowT >= after && nowT < before
            else -> nowT >= after || nowT < before // wrapping
        }
        if (!inTime) return false
        // The civil day: for a wrapping window, the after-portion's day owns
        // the whole window, so 01:00 belongs to the prior day's after side.
        val day = if (wraps && before != null && nowT < before)
            zdt.minusDays(1).dayOfWeek else zdt.dayOfWeek
        return DAY_KEY.getValue(day) in days
    }
}
