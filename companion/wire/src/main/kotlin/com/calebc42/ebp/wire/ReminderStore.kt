// SPDX-License-Identifier: GPL-3.0-or-later
// Owner-scoped reminders (SPEC 18.6). Each owner has an independent set,
// atomically replaced; fired receipts key on the (owner, id, at_ms) tuple
// so a reminder presents at most once — replacing an unchanged tuple keeps
// its receipt, changing at_ms or removing the id resets it. Durable through
// an injected ReminderBacking (SPEC 18.6: the accepted set AND the fired
// state persist across process and device restarts); with the default
// in-memory backing it behaves exactly as before. Methods are synchronized:
// the store outlives a connection and is shared between the reader thread
// and platform alarm receivers.
package com.calebc42.ebp.wire

import org.json.JSONObject

class ReminderStore(private val backing: ReminderBacking = MemoryReminderBacking()) {
    // owner -> (reminder id -> reminder object), insertion-ordered.
    private val owners = LinkedHashMap<String, LinkedHashMap<String, JSONObject>>()
    // Fired receipts keyed by (owner, id, at_ms).
    private val fired = HashSet<String>()

    init {
        val state = backing.load()
        for ((owner, list) in state.owners) {
            val map = LinkedHashMap<String, JSONObject>()
            list.forEach { map[it.getString("id")] = it }
            owners[owner] = map
        }
        fired.addAll(state.fired)
    }

    private fun key(owner: String, id: String, atMs: Long) = "$owner $id $atMs"

    private fun snapshot() = ReminderState(
        owners = owners.mapValues { (_, m) -> m.values.toList() },
        fired = fired.toSet())

    @Synchronized fun totalCount(): Int = owners.values.sumOf { it.size }

    @Synchronized fun ownerCount(owner: String): Int = owners[owner]?.size ?: 0

    /** SPEC 18.6: every owner with a live set — the host re-arms each owner's
     * alarms from the durable store after a reboot/force-stop cold start. */
    @Synchronized fun owners(): List<String> = owners.keys.toList()

    @Synchronized fun reminders(owner: String): List<JSONObject> =
        owners[owner]?.values?.toList() ?: emptyList()

    @Synchronized fun reminder(owner: String, id: String): JSONObject? =
        owners[owner]?.get(id)

    /**
     * SPEC 18.6: atomically replace only this owner's set. The caller has
     * validated. Fired receipts survive an unchanged (id, at_ms) tuple and
     * are dropped when the id disappears or its at_ms changes. The new state
     * commits durably before the replace is claimed; a storage failure
     * restores the prior state and rethrows (the caller answers an error,
     * leaving the prior set in force — never a claimed-but-lost accept).
     * Returns the new count for this owner.
     */
    @Synchronized
    fun replace(owner: String, reminders: List<JSONObject>): Int {
        val prevOwner = owners[owner]?.let { LinkedHashMap(it) }
        val prevFired = fired.toSet()
        val next = LinkedHashMap<String, JSONObject>()
        reminders.forEach { next[it.getString("id")] = it }
        val old = owners[owner] ?: emptyMap()
        for ((id, oldR) in old) {
            val newR = next[id]
            if (newR == null || newR.getLong("at_ms") != oldR.getLong("at_ms"))
                fired.remove(key(owner, id, oldR.getLong("at_ms")))
        }
        if (next.isEmpty()) owners.remove(owner) else owners[owner] = next
        try {
            backing.replace(snapshot())
        } catch (e: Exception) {
            if (prevOwner == null) owners.remove(owner) else owners[owner] = prevOwner
            fired.clear(); fired.addAll(prevFired)
            throw e
        }
        return next.size
    }

    /**
     * SPEC 18.6: present at most once per tuple, with the receipt persisted
     * BEFORE presentation. Returns true only when this is the first
     * presentation AND the receipt committed durably; a storage failure
     * withholds presentation (the at-most-once MUST outranks a missed
     * showing) and leaves the tuple eligible for a later retry.
     */
    @Synchronized
    fun markFired(owner: String, id: String): Boolean {
        val r = owners[owner]?.get(id) ?: return false
        val k = key(owner, id, r.getLong("at_ms"))
        if (!fired.add(k)) return false
        return try {
            backing.replace(snapshot()); true
        } catch (e: Exception) {
            fired.remove(k); false
        }
    }

    @Synchronized
    fun isFired(owner: String, id: String): Boolean {
        val r = owners[owner]?.get(id) ?: return false
        return key(owner, id, r.getLong("at_ms")) in fired
    }
}
