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

import kotlinx.serialization.json.JsonObject

class ReminderStore(private val backing: ReminderBacking = MemoryReminderBacking()) {
    // owner -> (reminder id -> reminder object), insertion-ordered.
    private val owners = LinkedHashMap<String, LinkedHashMap<String, JsonObject>>()
    // Fired receipts keyed by (owner, id, at_ms).
    private val fired = HashSet<String>()

    init {
        val state = backing.load()
        for ((owner, list) in state.owners) {
            val map = LinkedHashMap<String, JsonObject>()
            list.forEach { map[it.reqString("id")] = it }
            owners[owner] = map
        }
        fired.addAll(state.fired)
    }

    /**
     * `at_ms` as a Long across every NUMERIC spelling — the fired receipt key
     * is built from this, so the reader keeps org.json `getLong`'s tolerance
     * for integer and integral-double literals. It does NOT keep that method's
     * JSON-STRING coercion (`"5000"` no longer reads as 5000): dropping the
     * coercion is the module-wide policy stated in JsonAccess.kt, and
     * acceptance already refuses a non-numeric `at_ms`, so only a hand-edited
     * store file could hold one.
     *
     * Deliberately NOT [wireIntOrNull]: an integral double IS an accepted at_ms
     * (acceptance checks integrality by VALUE), so `5000.0` reaches this store
     * as a binary64 and a legacy file may hold one. A reader that refused it,
     * or that keyed on the literal "5000.0", would compute a DIFFERENT key than
     * the pre-swap build did for the same reminder and re-present one that had
     * already fired — SPEC 18.6's at-most-once, broken by a respelling. Pinned
     * by PersistenceCompatTest.reminderWithIntegralDoubleAtMsLoadsAsLong.
     *
     * The fractional fallback keeps org.json's truncation toward zero. Such a
     * value can only reach the store past validation (`at_ms: 1.5` is refused
     * at accept), but a store file that holds one must keep keying the way it
     * used to, not start throwing out of a platform alarm receiver.
     */
    private fun JsonObject.atMs(): Long =
        integralLongOrNull(this["at_ms"])
            ?: this["at_ms"]?.asDoubleOrNull()?.toLong()
            ?: throw NoSuchElementException("at_ms")

    private fun key(owner: String, id: String, atMs: Long) = "$owner $id $atMs"

    private fun snapshot() = ReminderState(
        owners = owners.mapValues { (_, m) -> m.values.toList() },
        fired = fired.toSet())

    @Synchronized fun totalCount(): Int = owners.values.sumOf { it.size }

    @Synchronized fun ownerCount(owner: String): Int = owners[owner]?.size ?: 0

    /** SPEC 18.6: every owner with a live set — the host re-arms each owner's
     * alarms from the durable store after a reboot/force-stop cold start. */
    @Synchronized fun owners(): List<String> = owners.keys.toList()

    @Synchronized fun reminders(owner: String): List<JsonObject> =
        owners[owner]?.values?.toList() ?: emptyList()

    @Synchronized fun reminder(owner: String, id: String): JsonObject? =
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
    fun replace(owner: String, reminders: List<JsonObject>): Int {
        val prevOwner = owners[owner]?.let { LinkedHashMap(it) }
        val prevFired = fired.toSet()
        val next = LinkedHashMap<String, JsonObject>()
        reminders.forEach { next[it.reqString("id")] = it }
        val old = owners[owner] ?: emptyMap()
        for ((id, oldR) in old) {
            val newR = next[id]
            if (newR == null || newR.atMs() != oldR.atMs())
                fired.remove(key(owner, id, oldR.atMs()))
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
        val k = key(owner, id, r.atMs())
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
        return key(owner, id, r.atMs()) in fired
    }
}
