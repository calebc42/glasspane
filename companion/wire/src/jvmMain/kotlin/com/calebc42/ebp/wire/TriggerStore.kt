// SPDX-License-Identifier: GPL-3.0-or-later
// Trigger registrations (SPEC 21), scoped to a pairing identity and replaced
// atomically. A registration pairs the normalized (defaults-materialized)
// trigger entry with the runtime records SPEC 21.1 requires be carried
// forward UNCHANGED when a replace-set leaves that id's complete entry equal
// under SPEC 4.3 — its throttle floor, one-shot/boot receipts, schedule
// anchor, and silent baselines. A changed or removed id discards them.
// Durable through an injected TriggerBacking (SPEC 21.1: registrations + their
// runtime records persist across process/device restarts); with the default
// in-memory backing it behaves as before. Baselines are re-established
// silently on arm (SPEC 21.5), never persisted. Methods are synchronized: the
// store outlives a connection and is shared with the device-lifetime firing
// service.
package com.calebc42.ebp.wire

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

class TriggerStore(private val backing: TriggerBacking = MemoryTriggerBacking()) {

    /** One armed registration: its normalized entry plus mutable runtime
     * records that outlive an unchanged replace (SPEC 21.1) and persist across
     * restart (all but the baselines, which SPEC 21.5 re-establishes silently). */
    class Registration(val entry: JsonObject) {
        var identity: String? = null         // owning pairing (for recover attribution)
        var throttleFloorMs: Long? = null    // last admitted occurrence (21.2)
        var oneShotCompleted = false         // time.at_ms completed marker (21.5)
        var scheduleAnchorMs: Long? = null   // time.every_s acceptance anchor
        var lastFireFloorMs: Long? = null     // repeating last-fire floor
        var bootGeneration: String? = null   // boot receipt (21.5)
        // Silent baselines / edge levels (NOT persisted). Deliberately still
        // `Any?` after C3: this bag is heterogeneous — the edge/side slots hold
        // a Kotlin Boolean, the unfiltered-level slot holds a raw JSON value
        // (a JsonElement?) — so it is not one of the "some JSON value" seams
        // that re-type to JsonElement?.
        val baselines = HashMap<String, Any?>()
    }

    // pairing identity -> (trigger id -> registration), insertion-ordered.
    private val byIdentity = LinkedHashMap<String, LinkedHashMap<String, Registration>>()

    init {
        for ((identity, regs) in backing.load().identities) {
            val map = LinkedHashMap<String, Registration>()
            for (p in regs) {
                val r = Registration(p.entry)
                r.identity = identity
                r.throttleFloorMs = p.throttleFloorMs
                r.oneShotCompleted = p.oneShotCompleted
                r.scheduleAnchorMs = p.scheduleAnchorMs
                r.lastFireFloorMs = p.lastFireFloorMs
                r.bootGeneration = p.bootGeneration
                map[p.entry.reqString("id")] = r  // baselines stay empty (21.5)
            }
            byIdentity[identity] = map
        }
    }

    private fun persist(r: Registration) = PersistedRegistration(
        r.entry, r.throttleFloorMs, r.oneShotCompleted,
        r.scheduleAnchorMs, r.lastFireFloorMs, r.bootGeneration)

    private fun snapshot() = TriggerState(
        byIdentity.mapValues { (_, m) -> m.values.map { persist(it) } })

    @Synchronized fun count(identity: String): Int = byIdentity[identity]?.size ?: 0

    @Synchronized fun identities(): List<String> = byIdentity.keys.toList()

    @Synchronized fun registrations(identity: String): List<Registration> =
        byIdentity[identity]?.values?.toList() ?: emptyList()

    @Synchronized fun registration(identity: String, id: String): Registration? =
        byIdentity[identity]?.get(id)

    /** SPEC 21.2: durably persist the current runtime records (throttle floor,
     * one-shot/boot receipts, schedule anchor). Called by the firing service
     * inside the admitted-occurrence transaction. Throws on storage failure. */
    @Synchronized fun persistRecords() = backing.replace(snapshot())

    /**
     * SPEC 21.1: atomically replace this identity's whole set with the
     * validated, normalized `entries`. An id whose normalized entry equals the
     * prior one (SPEC 4.3) carries its Registration forward with every runtime
     * record intact; a new or changed id gets a fresh Registration. The new
     * state commits durably before the replace is claimed; a storage failure
     * restores the prior set and rethrows. An empty list clears the identity.
     * Returns the accepted count.
     */
    @Synchronized
    fun replace(identity: String, entries: List<JsonObject>): Int {
        val prev = byIdentity[identity]?.let { LinkedHashMap(it) }
        val old = byIdentity[identity] ?: LinkedHashMap()
        val next = LinkedHashMap<String, Registration>()
        for (e in entries) {
            val id = e.reqString("id")
            val prior = old[id]
            next[id] = if (prior != null && canonicalEquals(prior.entry, e))
                prior                       // unchanged: keep records (21.1)
            else Registration(e).also { it.identity = identity } // new/changed: fresh
        }
        if (next.isEmpty()) byIdentity.remove(identity) else byIdentity[identity] = next
        try {
            backing.replace(snapshot())
        } catch (ex: Exception) {
            if (prev == null) byIdentity.remove(identity) else byIdentity[identity] = prev
            throw ex
        }
        return next.size
    }

    companion object {
        /**
         * SPEC 4.3 structural equality for two normalized entries. Both sides
         * are already defaults-materialized, so this is an order-independent
         * deep compare: objects match key-set and value-wise, arrays match
         * element-wise, numbers match by value, JSON null matches JSON null.
         *
         * C3 (R5): that is exactly [jsonValueEquals] — the same LD-20 type-tag
         * gate, reimplemented over kotlinx's tree — so the clause-by-clause
         * copy that used to live here is gone, not re-derived. What it must NOT
         * become is kotlinx's own `JsonElement.equals`, which compares the
         * literal content STRING: `60` and `60.0` would come out unequal, this
         * function decides whether a re-`triggers.set` is the SAME
         * registration, and so a merely respelled number would silently drop
         * the throttle floor (the trigger double-fires) and the one-shot
         * completion (a completed one-shot re-arms). Pinned by
         * TriggerTest.canonicalEqualsIgnoresNumberSpelling.
         */
        fun canonicalEquals(a: JsonElement?, b: JsonElement?): Boolean = jsonValueEquals(a, b)
    }
}
