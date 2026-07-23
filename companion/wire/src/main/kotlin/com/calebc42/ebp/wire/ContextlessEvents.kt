// SPDX-License-Identifier: GPL-3.0-or-later
// Context-less event.action dispatch (SPEC 14.4: pie-menu, reminder, and
// reminder-tap events omit surface/revision_seen/dialog_id). Extracted from
// CompanionEngine so a COLD manifest receiver (a reminder tap that fires with
// no live socket) can admit a queue/wake occurrence to the shared durable
// queue for later replay, using exactly the same code path the engine uses.
package com.calebc42.ebp.wire

import org.json.JSONObject

/**
 * The live-session duties a context-less event needs only when a connection
 * exists: deliver a `drop` event live, and wake + advance the pump after a
 * durable admit. Implemented by CompanionEngine and held by the firing
 * service / CompanionStores as a newest-wins slot. A cold sender passes null:
 * queue/wake still admit durably; a `drop` with no session is simply lost
 * (SPEC 15.1).
 */
interface LiveSession {
    fun deliverLiveDrop(params: JSONObject, callback: ((String?, JSONObject?) -> Unit)?)
    fun onDurableAdmitted(policy: String)
}

/**
 * SPEC 14.4/15.1: build a context-less event.action and route it by the
 * descriptor's offline policy against the shared durable queue. Callable off
 * any thread and without a live engine. `queue.admit` is the serialization
 * point; the `live` callbacks run only for their respective policy.
 */
fun dispatchContextless(
    queue: DurableQueue,
    maxEventBytes: Long,
    descriptor: JSONObject,
    args: JSONObject,
    live: LiveSession?,
    callback: ((String?, JSONObject?) -> Unit)? = null,
) {
    val params = JSONObject()
        .put("event_id", EbpAuth.generateNonce())
        .put("action", descriptor.getString("action"))
        .put("occurred_at_ms", queue.effectiveNow())
    if (args.length() > 0) params.put("args", args)
    val policy = descriptor.optString("when_offline", OFFLINE_DEFAULT)
    if (policy == "queue" || policy == "wake")
        params.put("queued_at_ms", queue.effectiveNow())
    if (params.toString().toByteArray(Charsets.UTF_8).size > maxEventBytes) {
        callback?.invoke(null, JSONObject().put("code", 1201)
            .put("message", "Event exceeds max_event_bytes")
            .put("data", JSONObject().put("kind", "content-invalid")
                .put("reason", "event-too-large")))
        return
    }
    when (policy) {
        "queue", "wake" -> when (queue.admit(params, policy,
                descriptor.optString("dedupe").takeIf { it.isNotEmpty() },
                descriptor.getLong("ttl_s"))) {
            is AdmitResult.Admitted -> {
                live?.onDurableAdmitted(policy)
                callback?.invoke("queued", null)
            }
            AdmitResult.QueueFull -> callback?.invoke(null, JSONObject()
                .put("code", 1601).put("message", "Queue full")
                .put("data", JSONObject().put("kind", "queue-full")))
            AdmitResult.StorageFailed -> callback?.invoke(null, JSONObject()
                .put("code", -32603).put("message", "Storage failed")
                .put("data", JSONObject().put("kind", "internal-error")))
        }
        // SPEC 15.1: a drop event delivers live or is lost; no session = lost.
        else -> live?.deliverLiveDrop(params, callback)
    }
}

/**
 * SPEC 18.6: route a reminder tap into the Section 14 pipeline with the
 * reminder's authored offline policy and injected owner/reminder_id. Reads the
 * on_tap from the shared store, so a cold tap receiver (no live engine) routes
 * queue/wake taps into the durable queue exactly as the engine would. A
 * reminder with no on_tap dispatches nothing (dismissal is not a tap).
 */
fun routeReminderTap(
    reminders: ReminderStore,
    queue: DurableQueue,
    maxEventBytes: Long,
    owner: String,
    reminderId: String,
    live: LiveSession?,
    callback: ((String?, JSONObject?) -> Unit)? = null,
) {
    val onTap = reminders.reminder(owner, reminderId)?.optJSONObject("on_tap") ?: return
    val args = JSONObject(onTap.optJSONObject("args")?.toString() ?: "{}")
        .put("owner", owner).put("reminder_id", reminderId)
    dispatchContextless(queue, maxEventBytes, onTap, args, live, callback)
}
