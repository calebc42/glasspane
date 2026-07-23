// SPDX-License-Identifier: GPL-3.0-or-later
// Trigger registrations (SPEC 21), scoped to a pairing identity and replaced
// atomically. A registration pairs the normalized (defaults-materialized)
// trigger entry with the runtime records SPEC 21.1 requires be carried
// forward UNCHANGED when a replace-set leaves that id's complete entry equal
// under SPEC 4.3 — its throttle floor, one-shot/boot receipts, schedule
// anchor, and silent baselines. A changed or removed id discards them.
// In-memory here; durable backing (SPEC 21.1 persistence) lands with the
// firing runtime, mirroring how ReminderStore grew its backing.
package com.calebc42.ebp.wire

import org.json.JSONArray
import org.json.JSONObject

class TriggerStore {

    /** One armed registration: its normalized entry plus mutable runtime
     * records that outlive an unchanged replace (SPEC 21.1). The firing
     * runtime populates the records; this atom only preserves or discards them. */
    class Registration(val entry: JSONObject) {
        var throttleFloorMs: Long? = null    // last admitted occurrence (21.2)
        var oneShotCompleted = false         // time.at_ms completed marker (21.5)
        var scheduleAnchorMs: Long? = null   // time.every_s acceptance anchor
        var lastFireFloorMs: Long? = null     // repeating last-fire floor
        var bootGeneration: String? = null   // boot receipt (21.5)
        val baselines = HashMap<String, Any?>() // silent baselines / edge levels (21.5/21.6)
    }

    // pairing identity -> (trigger id -> registration), insertion-ordered.
    private val byIdentity = LinkedHashMap<String, LinkedHashMap<String, Registration>>()

    fun count(identity: String): Int = byIdentity[identity]?.size ?: 0

    fun registrations(identity: String): List<Registration> =
        byIdentity[identity]?.values?.toList() ?: emptyList()

    fun registration(identity: String, id: String): Registration? =
        byIdentity[identity]?.get(id)

    /**
     * SPEC 21.1: atomically replace this identity's whole set with the
     * validated, normalized `entries`. An id whose normalized entry equals the
     * prior one (SPEC 4.3) carries its Registration forward with every runtime
     * record intact; a new or changed id gets a fresh Registration. An empty
     * list clears the identity. Returns the accepted count.
     */
    fun replace(identity: String, entries: List<JSONObject>): Int {
        val old = byIdentity[identity] ?: LinkedHashMap()
        val next = LinkedHashMap<String, Registration>()
        for (e in entries) {
            val id = e.getString("id")
            val prior = old[id]
            next[id] = if (prior != null && canonicalEquals(prior.entry, e))
                prior                       // unchanged: keep records (21.1)
            else Registration(e)            // new or changed: fresh records
        }
        if (next.isEmpty()) byIdentity.remove(identity) else byIdentity[identity] = next
        return next.size
    }

    companion object {
        /**
         * SPEC 4.3 structural equality for two normalized entries. Both sides
         * are already defaults-materialized, so this is an order-independent
         * deep compare: objects match key-set and value-wise, arrays match
         * element-wise, numbers match by value, JSON null matches JSON null.
         */
        fun canonicalEquals(a: Any?, b: Any?): Boolean = when {
            a is JSONObject && b is JSONObject -> {
                a.keySet() == b.keySet() &&
                    a.keySet().all { canonicalEquals(a.opt(it), b.opt(it)) }
            }
            a is JSONArray && b is JSONArray -> {
                a.length() == b.length() &&
                    (0 until a.length()).all { canonicalEquals(a.opt(it), b.opt(it)) }
            }
            a is Number && b is Number -> a.toDouble() == b.toDouble()
            a == JSONObject.NULL || b == JSONObject.NULL -> a == b
            else -> a == b
        }
    }
}
