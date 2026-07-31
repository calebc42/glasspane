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
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class TriggerRuntime(
    private val store: TriggerStore,
    /** Milliseconds; rollback-resistant wall time (queue.effectiveNow). */
    private val now: () -> Long,
    /** Civil-time zone for time.window predicates — a supplier read fresh at
     * each evaluation, so a device timezone change takes effect immediately
     * (the systemDefault() default) rather than being frozen at construction. */
    private val zone: () -> ZoneId,
    /** Current sample object for a state type, or null if unavailable. */
    private val stateProvider: (String) -> JsonObject?,
    /**
     * SPEC 21.2: perform the durable commit for an admitted occurrence and,
     * only if it succeeds, invoke `commit` (which consumes throttle + runs
     * on_fire) BEFORE making the remote trigger.fired eligible. For queue/wake
     * this means committing the event record first and skipping `commit`
     * entirely on QueueFull/StorageFailed; for drop it means committing
     * throttle+on_fire even with no live session, delivering live only in READY.
     */
    private val emit: (TriggerStore.Registration, JsonObject, commit: () -> Unit) -> Unit,
    /** SPEC 21.4: execute one substituted on_fire entry ({cap,args?}|{notify}).
     * Called in authored order at admission; a throw is isolated per entry. */
    private val onFire: (JsonObject) -> Unit = {},
    /** SPEC 21.2 step 3: durably commit the throttle floor / one-shot / boot
     * records BEFORE on_fire runs. A no-op with the default in-memory store. */
    private val persistRecords: () -> Unit = {},
    /** SPEC 21.5: the current device boot generation (Settings.Global.BOOT_COUNT
     * on Android), or null if unknown. A `boot` registration is admitted at most
     * once per generation; the JVM default leaves boot triggers ungated. */
    private val bootGeneration: () -> String? = { null },
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
        // SPEC 21.1: the every_s anchor and boot generation recorded below are
        // durable records (unlike the silent level/edge baselines, which are
        // re-established from live state) — a fresh recording must be persisted
        // so it survives restart.
        var recorded = false
        for (reg in store.registrations(identity)) {
            val type = reg.entry.reqString("type")
            when {
                type == "state.edge" ->
                    if (!reg.baselines.containsKey("edge"))
                        reg.baselines["edge"] = edgeHolds(reg)
                type == "battery.level" ->
                    if (!reg.baselines.containsKey("side")) stateProvider(type)?.let {
                        reg.baselines["side"] = batterySide(reg.entry, it) }
                type in ENUM_FIELD -> {
                    val field = ENUM_FIELD.getValue(type)
                    if (field in reg.entry.reqObj("params")) {
                        if (!reg.baselines.containsKey("side")) stateProvider(type)?.let {
                            reg.baselines["side"] = enumMatch(reg.entry, field, it) }
                    } else if (!reg.baselines.containsKey("value")) stateProvider(type)?.let {
                        // C3: the baseline holds a JsonElement? — absent reads as
                        // Kotlin null and JSON null as JsonNull, the same two-way
                        // split org.json's opt() gave (null vs JSONObject.NULL),
                        // so the containsKey-vs-value distinction below is intact.
                        reg.baselines["value"] = it[field] }
                }
                // SPEC 21.5: a repeating time.every_s registration anchors its
                // cadence at the acceptance that first introduced it. A fresh
                // Registration has no anchor; a carried-forward one keeps the
                // anchor it was accepted with, so arming never resets the phase.
                type == "time" && "every_s" in reg.entry.reqObj("params") ->
                    if (reg.scheduleAnchorMs == null) { reg.scheduleAnchorMs = now(); recorded = true }
                // SPEC 21.5: installing a new/changed boot registration silently
                // records the CURRENT generation and arms for the NEXT boot — it
                // must not fire for the boot it was installed during. A carried-
                // forward or persisted receipt keeps its generation, so a process
                // restart in the same boot creates no occurrence. Recorded only
                // when the platform generation is known; null stays ungated.
                type == "boot" ->
                    if (reg.bootGeneration == null) bootGeneration()?.let {
                        reg.bootGeneration = it; recorded = true }
            }
        }
        // Best-effort (SPEC 21.5 re-establishes silently on the next arm if this
        // is lost): never fail a triggers.set because a baseline persist hiccups.
        if (recorded) runCatching { persistRecords() }
    }

    // ------------------------------------------------------ observation feed

    /**
     * SPEC 21.5: a level-type observation. Level registrations of this type
     * evaluate a crossing/transition against their baseline; every state.edge
     * re-evaluates because any tracked level may have flipped its conjunction.
     */
    fun onSample(identity: String, type: String, sample: JsonObject) {
        for (reg in store.registrations(identity)) {
            if (reg.entry.reqString("type") != type) continue
            when {
                type == "battery.level" -> crossing(reg, batterySide(reg.entry, sample), sample)
                type in ENUM_FIELD -> {
                    val field = ENUM_FIELD.getValue(type)
                    if (field in reg.entry.reqObj("params"))
                        crossing(reg, enumMatch(reg.entry, field, sample), sample)
                    else valueChange(reg, sample[field], sample)
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
    fun onExternal(identity: String, type: String, data: JsonObject) {
        for (reg in store.registrations(identity))
            if (reg.entry.reqString("type") == type) tryAdmit(reg, data)
    }

    /**
     * SPEC 21.5 (manual): fire exactly the named `manual` registration (via the
     * builtin or trigger.fire), NOT every manual trigger. Unknown or non-manual
     * ids are a no-op.
     */
    fun fireManual(identity: String, triggerId: String, data: JsonObject) {
        val reg = store.registration(identity, triggerId) ?: return
        if (reg.entry.reqString("type") == "manual") tryAdmit(reg, data)
    }

    /**
     * SPEC 21.5 (time): admit exactly the named time.* registration whose host
     * alarm just elapsed — NOT every time trigger, because each has its own due
     * time (unlike a fan-out `boot`). The one-shot/gate/throttle eligibility in
     * tryAdmit still applies. Unknown or non-time ids are a no-op.
     */
    fun fireScheduled(identity: String, triggerId: String, data: JsonObject) {
        val reg = store.registration(identity, triggerId) ?: return
        if (reg.entry.reqString("type") != "time") return
        tryAdmit(reg, data)
        // SPEC 21.5: a repeating every_s advances its schedule cursor to the
        // current boundary on EVERY elapsed alarm, even when the gate/throttle/
        // queue blocked admission — otherwise the host recomputes the SAME
        // past-due boundary and re-arms it, and the alarm spins (an RTC_WAKEUP
        // storm) until the blocking condition clears. On a successful admit the
        // commit already floored lastFireFloorMs to now, so this is a no-op.
        val params = reg.entry.objOrNull("params")
        if (params != null && "every_s" in params &&
            (reg.lastFireFloorMs ?: Long.MIN_VALUE) < now()) {
            reg.lastFireFloorMs = now()
            runCatching { persistRecords() }
        }
    }

    // -------------------------------------------------------- crossing logic

    // SPEC 21.5: a filtered level fires only when entering the configured side.
    private fun crossing(reg: TriggerStore.Registration, side: Boolean, data: JsonObject) {
        val prev = reg.baselines["side"] as Boolean?
        if (prev == null) { reg.baselines["side"] = side; return } // silent baseline
        if (!prev && side) tryAdmit(reg, data)
        reg.baselines["side"] = side
    }

    // SPEC 21.5: an unfiltered level fires on any change of its primary value.
    // C3: `value` is a JsonElement? (absent = Kotlin null, JSON null =
    // JsonNull) and the comparison stays the host language's `!=` — a
    // JsonPrimitive is a data class over (isString, content), so the type
    // strictness of the old boxed-value compare survives: the string "on" is
    // still not the number 1, and a respelled number is still a change.
    private fun valueChange(reg: TriggerStore.Registration, value: JsonElement?, data: JsonObject) {
        val prev = reg.baselines["value"]
        if (!reg.baselines.containsKey("value")) { reg.baselines["value"] = value; return }
        if (prev != value) tryAdmit(reg, data)
        reg.baselines["value"] = value
    }

    private fun batterySide(entry: JsonObject, sample: JsonObject): Boolean {
        val p = entry.reqObj("params")
        // C3: the level is read as an INTEGER member (TriggerValidator stores
        // above/below as integers and the device source reports whole
        // percents). A sample spelling it `19.0` no longer coerces — it reads
        // as the -1 "unavailable" sentinel, exactly as a missing member does.
        val level = sample.longOr("level", -1)
        return if ("above" in p) level > p.reqLong("above") else level < p.reqLong("below")
    }

    private fun enumMatch(entry: JsonObject, field: String, sample: JsonObject): Boolean =
        sample[field] == entry.reqObj("params")[field]

    // ------------------------------------------------------------- edges

    private fun reEvaluateEdges(identity: String) {
        for (reg in store.registrations(identity)) {
            if (reg.entry.reqString("type") != "state.edge") continue
            val holds = edgeHolds(reg)
            val prev = reg.baselines["edge"] as Boolean?
            if (prev == null) { reg.baselines["edge"] = holds; continue } // silent
            val edge = reg.entry.reqObj("params").reqString("edge")
            val rise = !prev && holds && (edge == "rise" || edge == "both")
            val fall = prev && !holds && (edge == "fall" || edge == "both")
            reg.baselines["edge"] = holds
            if (rise || fall)
                tryAdmit(reg, buildJsonObject {
                    put("holds", holds)
                    put("edge", if (holds) "rise" else "fall")
                })
        }
    }

    // The tracked conjunction (SPEC 21.6 params.when), distinct from the
    // row-level `when` gate evaluated at admission.
    private fun edgeHolds(reg: TriggerStore.Registration): Boolean =
        allHold(reg.entry.reqObj("params").reqArr("when"))

    // ----------------------------------------------- admission (SPEC 21.2)

    private fun tryAdmit(reg: TriggerStore.Registration, data: JsonObject) {
        // SPEC 21.2 step 1: state gate + throttle eligibility. A failed check
        // consumes NOTHING — no throttle, no local response, no event.
        if (!allHold(reg.entry.reqArr("when"))) return
        val throttle = reg.entry.longOr("throttle_s", 0)
        if (throttle > 0) {
            val floor = reg.throttleFloorMs
            if (floor != null && now() - floor < throttle * 1000) return
        }
        // SPEC 21.5 eligibility (a skip consumes nothing): a completed one-shot
        // time.at_ms never fires again, and a boot registration fires at most
        // once per known device boot generation. An unknown generation (null)
        // leaves boot ungated — the receiver already feeds it once per boot.
        if (reg.oneShotCompleted) return
        if (reg.entry.reqString("type") == "boot") {
            val gen = bootGeneration()
            if (gen != null && gen == reg.bootGeneration) return
        }
        // SPEC 21.2 steps 2-5, ordered by emit: the durable commit happens
        // FIRST; only if it succeeds does emit invoke this `commit` closure,
        // which consumes the throttle floor (step 3) and runs on_fire in
        // authored order (step 4). Remote FIFO eligibility / live delivery
        // (step 5) follows inside emit. A failed durable transaction
        // (QueueFull/StorageFailed) never calls commit — so no throttle is
        // consumed and no local response runs (SPEC 21.2).
        emit(reg, data) {
            // Step 3: consume the throttle floor and advance the time/boot
            // records (SPEC 21.5), then durably persist them BEFORE any local
            // response: a one-shot time.at_ms is done for good, a repeating
            // time.every_s floors its last fire so missed intervals coalesce and
            // the cadence resumes, and a boot occurrence records its generation.
            val priorThrottle = reg.throttleFloorMs
            val priorOneShot = reg.oneShotCompleted
            val priorLastFire = reg.lastFireFloorMs
            val priorBoot = reg.bootGeneration
            reg.throttleFloorMs = now()
            val type = reg.entry.reqString("type")
            val params = reg.entry.objOrNull("params")
            when {
                type == "time" && params != null && "at_ms" in params ->
                    reg.oneShotCompleted = true
                type == "time" && params != null && "every_s" in params ->
                    reg.lastFireFloorMs = now()
                type == "boot" -> reg.bootGeneration = bootGeneration()
            }
            // SPEC 21.2: if the record write (transaction B) fails, RESTORE the
            // in-memory records and rethrow so `emit` rolls back the event
            // (transaction A) — a failed transaction consumes nothing.
            try {
                persistRecords()
            } catch (e: Exception) {
                reg.throttleFloorMs = priorThrottle
                reg.oneShotCompleted = priorOneShot
                reg.lastFireFloorMs = priorLastFire
                reg.bootGeneration = priorBoot
                throw e
            }
            // Step 4: on_fire in authored order, substituted, failure-isolated.
            val id = reg.entry.reqString("id")
            val list = reg.entry.reqArr("on_fire")
            for (item in list) {
                try {
                    onFire(Substitution.apply(item, id, type, data) as JsonObject)
                } catch (_: Exception) { /* isolated per entry; SPEC 21.4 */ }
            }
        }
    }

    // ---------------------------------------------- gate predicate eval

    private fun allHold(preds: JsonArray): Boolean {
        for (pred in preds)
            if (!predicateHolds(pred as JsonObject)) return false
        return true
    }

    // SPEC 21.3/21.7: a predicate that cannot be evaluated does not hold.
    private fun predicateHolds(p: JsonObject): Boolean {
        val type = p.reqString("type")
        if (type == "time.window") return timeWindowHolds(p)
        val s = stateProvider(type) ?: return false
        return when (type) {
            "power" -> s.stringOr("state") == p.stringOr("state", "connected")
            "battery.level" ->
                if ("above" in p) s.longOr("level", -1) > p.reqLong("above")
                else s.longOr("level", -1) < p.reqLong("below")
            "screen" -> {
                val want = p.stringOr("state", "on"); val cur = s.stringOr("state")
                if (want == "on") cur == "on" || cur == "unlocked" else cur == want
            }
            "airplane" -> s.stringOr("state") == p.stringOr("state", "on")
            "network" -> s.boolOr("connected") &&
                ("transport" !in p || transportsHave(s, p.reqString("transport")))
            "headset" -> s.stringOr("state") == p.stringOr("state", "plugged")
            "wifi.enabled" -> s.boolOr("enabled") == p.boolOr("enabled", true)
            "bluetooth.enabled" ->
                "enabled" in s && s.boolOr("enabled") == p.boolOr("enabled", true)
            "calendar.event" -> s.boolOr("ongoing")
            "call.state" -> s.stringOr("state") == p.stringOr("state", "offhook")
            else -> false
        }
    }

    private fun transportsHave(s: JsonObject, transport: String): Boolean {
        val arr = s.arrOrNull("transports") ?: return false
        // C3: element-to-element comparison against the JSON STRING spelling —
        // JsonPrimitive equality is over (isString, content), so a number or a
        // nested container entry can never match a transport name, which is
        // what the old `arr.opt(i) == transport` (String equality) meant.
        return arr.any { it == JsonPrimitive(transport) }
    }

    // SPEC 21.7: local civil time in the half-open window; wraps at midnight
    // when after > before; days selects the civil day the after-portion begins.
    private fun timeWindowHolds(p: JsonObject): Boolean {
        val zdt = Instant.ofEpochMilli(now()).atZone(zone())
        val nowT = zdt.toLocalTime()
        val after = p.stringOr("after").takeIf { it.isNotEmpty() }?.let { LocalTime.parse(it) }
        val before = p.stringOr("before").takeIf { it.isNotEmpty() }?.let { LocalTime.parse(it) }
        // A non-string day throws, as the org.json `getString(i)` did: the
        // validator normalizes `days` to weekday strings, so an entry that is
        // anything else is a corrupt store, not a predicate that "does not hold".
        val days = p.arrOrNull("days")?.let { a ->
            a.map { it.asStringOrNull() ?: throw NoSuchElementException("days") }.toSet()
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

    companion object {
        /**
         * SPEC 21.5: the next scheduled occurrence of a repeating time.every_s
         * registration — the first `anchor + k·interval` boundary (k ≥ 1)
         * strictly after its last-fire floor, or the acceptance anchor itself if
         * it has never fired. A returned value in the past means the interval(s)
         * elapsed while the Companion was dead: the host arms the alarm for it,
         * it fires once, and the commit floors the last fire past `now` — so the
         * NEXT call resumes the cadence with no catch-up burst (missed intervals
         * coalesce into that single occurrence). Null for a non-repeating or
         * not-yet-anchored entry (nothing to schedule).
         */
        fun nextRepeatDueMs(reg: TriggerStore.Registration): Long? {
            val params = reg.entry.objOrNull("params") ?: return null
            if ("every_s" !in params) return null
            val interval = params.reqLong("every_s") * 1000
            if (interval <= 0) return null
            val anchor = reg.scheduleAnchorMs ?: return null
            val elapsed = (reg.lastFireFloorMs ?: anchor) - anchor
            val k = (if (elapsed < 0) 0L else elapsed / interval) + 1
            return anchor + k * interval
        }
    }
}
