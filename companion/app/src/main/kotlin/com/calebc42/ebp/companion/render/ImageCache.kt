// SPDX-License-Identifier: GPL-3.0-or-later
// LD-11: a decoded-image cache with an aggregate byte budget and in-flight
// coalescing. RenderImage used produceState(null, url), so leaving composition
// discarded the bitmap and cancelled the load; RenderLazyColumn disposes
// off-screen items, so scrolling re-ran the whole loadHttps path — fresh DNS,
// TLS, up to 8 MiB re-downloaded, full decode — and ten identical avatars were
// ten concurrent sockets. This cache holds decoded Bitmaps (so it lives in
// app/, not wire/), keyed on url + limits ONLY — unlike Emacs's image cache a
// theme.set MUST NOT invalidate it — under an LRU byte budget, and coalesces
// concurrent requests for one URL into a single fetch.
//
// It completes LD-12 too: ImageLoader.Semaphore(3) bounds concurrent DECODES;
// this budget bounds RETAINED decoded bytes, so the two together bound image
// memory. Eviction drops the cache's reference only — it never recycle()s, so
// a bitmap still held by an on-screen Image is freed by GC when that Image
// leaves, never mid-draw.
package com.calebc42.ebp.companion.render

import android.graphics.Bitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object ImageCache {

    private data class Key(val url: String, val limits: ImageLoader.Limits)

    private val mutex = Mutex()
    // Access-order LinkedHashMap = LRU: get() moves an entry to the front.
    private val lru = object : LinkedHashMap<Key, Bitmap>(16, 0.75f, true) {}
    private val inFlight = HashMap<Key, Deferred<Bitmap?>>()
    private var usedBytes = 0L

    // Default until configure() runs; overwritten from ActivityManager's
    // per-app memory class. A soft budget on what the cache RETAINS.
    @Volatile private var budgetBytes = 32L * 1024 * 1024

    // The cache OWNS the fetch, so one caller leaving composition cancels only
    // its own await(), never the shared load the other callers still want.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Set the retention budget, e.g. `memoryClass MiB / 8`. */
    fun configure(budgetBytes: Long) {
        this.budgetBytes = budgetBytes.coerceAtLeast(4L * 1024 * 1024)
    }

    /** The decoded bitmap for [url], from cache or a coalesced fetch; null on
     * any guard failure (the caller shows a placeholder). */
    suspend fun get(url: String, limits: ImageLoader.Limits): Bitmap? {
        val key = Key(url, limits)
        mutex.withLock { lru[key] }?.let { return it }
        val deferred = mutex.withLock {
            lru[key]?.let { return it }              // recheck under the lock
            inFlight[key] ?: scope.async { ImageLoader.load(url, limits) }
                .also { inFlight[key] = it }
        }
        val bitmap = try {
            deferred.await()
        } finally {
            mutex.withLock { if (inFlight[key] === deferred) inFlight.remove(key) }
        }
        if (bitmap != null) mutex.withLock { admit(key, bitmap) }
        return bitmap
    }

    /** SPEC 9.1/17.2 (amendment #86): fetched image content is inside the
     * revocation-erasure boundary. Call on forget-pairing. */
    suspend fun clear() = mutex.withLock {
        lru.clear()
        usedBytes = 0
    }

    private fun admit(key: Key, bitmap: Bitmap) {
        if (lru.containsKey(key)) return
        val size = bitmap.allocationByteCount.toLong()
        // Evict least-recently-used until the newcomer fits (but never evict
        // so far that a single over-budget image loops forever).
        val it = lru.entries.iterator()
        while (usedBytes + size > budgetBytes && it.hasNext()) {
            val e = it.next()
            usedBytes -= e.value.allocationByteCount.toLong()
            it.remove()
        }
        lru[key] = bitmap
        usedBytes += size
    }
}
