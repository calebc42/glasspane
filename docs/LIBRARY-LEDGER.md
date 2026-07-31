# LIBRARY LEDGER

The enforcement point of the library-adoption standing rule
([PLAN-refound-2026-07-28.md](PLAN-refound-2026-07-28.md) Decision 8, added
2026-07-31): a library is adopted only with a **dated verification citation**, a
**tier** per invariant I4 (materializer / capability-adjacent / infrastructure), and
the **seam** it sits behind — named *before* the gate of the rung that adopts it.
**No entry here, no adoption.** The Room 3 misfit (audit P1-6) went undetected
because adoption was argued from release notes rather than source; entries below
cite what was actually read, where, and when.

An entry is a record, not an endorsement: the rung column says when the adoption is
(or was) due, and a rung's gate may still reject it.

| Library · coordinates | Verification (dated) | Tier (I4) | Seam it sits behind | Rung |
|---|---|---|---|---|
| **kotlinx.serialization** · `org.jetbrains.kotlinx:kotlinx-serialization-json` 1.8.0 | 2026-07-30, PLAN-rf2 §2.1/B0 (commit `2271211`): runtime for Kotlin 2.1.x; tree API only, no compiler plugin, zero `@Serializable` | infrastructure | `EbpJson.parse` stays the only wire-byte parser; kotlinx sees trees via `toJsonElement` + `JsonAccess.kt`; lenient `parseToJsonElement` for persistence reads only | RF-2b (B0 landed 2026-07-30) |
| **kotlinx-datetime** · `org.jetbrains.kotlinx:kotlinx-datetime` 0.6.2 | 2026-07-30, PLAN-rf2 §3.2: JVM implementation delegates to `java.time`, so SPEC §21.7 civil-time behavior is preserved; `DateTimeException` catches retarget to `IllegalTimeZoneException` | infrastructure | Platform time helpers inside `:wire` (`TriggerRuntime`/`TriggerValidator`/`DurableQueue` clock), behind existing interfaces | RF-2c (H5) |
| **Robolectric** · `org.robolectric:robolectric` | 2026-07-31, audit/RF-1b: deferred past C6 deliberately — new dependency stack + SDK-36 shadow-jar risk; reference images are *render snapshots*, never "goldens" | infrastructure (test-only) | `:app` test source set only; never a `main` dependency | RF-1b |
| **androidx.sqlite + sqlite-bundled** · `androidx.sqlite:sqlite`, `androidx.sqlite:sqlite-bundled` | 2026-07-31, local clone @ `d69c96e` — reproducible via `docs/lookup-tables/SQLITE-DRIVER-REFERENCE.org` (generated, SHA-pinned): driver-level `open(fileName, flags)` with public `SQLITE_OPEN_READONLY`/`SQLITE_OPEN_URI` (`BundledSQLiteDriver.kt:84,:95`; `BundledSQLite.kt:26,:35`); bundles SQLite 3.50.1, `SQLITE_THREADSAFE=2`. Web scoping, precisely: the *interface* artifact declares js/wasmJs but splits its source sets — `open`/`prepare` are synchronous only in `nonWebMain`, `suspend` in `webMain` — while **`sqlite-bundled` declares no js/wasmJs at all** (web pairs `webMain` interfaces with `sqlite-web`) | infrastructure | Inside `ebp-sqlite`, behind its declare-schema/apply-changesets interface; costs priced in PLAN-refound RF-4c (`BEGIN IMMEDIATE` helper, thread confinement, no `InvalidationTracker`) | RF-4c |
| **Room 3** · `androidx.room3:room3-runtime` | 2026-07-31, local clone @ `d69c96e`: JS/WasmJS genuinely declared in-source for `room3-runtime`/`room3-common`; driver-backed; Room 2.x in maintenance. **Blockers for a schema-generic layer, verified:** codegen-only `createOpenDelegate` (`RoomDatabase.android.kt:302-306`), identity-hash write (`RoomConnectionManager.kt:113-155`), no-flags open under `ExclusiveMutex` file lock (`:81`, `:70-73`), compile-time migrations — harmless for a Companion-*owned* DB, fatal for a foreign or runtime-declared one (audit P1-6) | materializer (of `jetpacs-vroom3`) | Entirely below `jetpacs-vroom3`'s typed DAO surface; **never** inside `ebp-sqlite`, never in wire vocabulary | post-plan (`jetpacs-vroom3`), per Decision 2 |
| **track-changes.el** · built-in, GNU Emacs 30.1 (v1.2) | 2026-07-31, `emacs-30.1` tag: present in-tree, written for eglot's sync problem | infrastructure (elisp) | Behind RF-4b's change-capture tier and §19's local-edit observation; replaces the 1 s `buffer-chars-modified-tick` poll | RF-5a (prerequisite of RF-4b) |
| **WorkManager** · `androidx.work:work-runtime` | 2026-07-31, audit P2-6: scheduled work does **not** survive force-stop (the rewritten RF-5b gate exists because of this); fits deferrable-guaranteed §15 delivery under Doze; AlarmManager stays for exact-time triggers | infrastructure | Behind the §15 delivery pump's scheduling; `DurableQueue` and its stores unchanged | RF-5b |
| **Coil 3** · `io.coil-kt.coil3:coil` | 2026-07-28, refound audit: replaces hand-rolled fetch/decode/LRU (`render/ImageLoader.kt`, `ImageCache.kt`) | infrastructure | **Behind `wire/ImageGuards.kt`** — the SPEC policy layer (SSRF/redirect/deadline) stays in front; the guards are the product, the plumbing is not | RF-5d |
| **Compose Multiplatform** · `org.jetbrains.compose` (plugin + artifacts) | 2026-07-31: desktop CMP is a JVM target, so RF-2's jvm-only flip already suffices; no new Kotlin target needed | materializer (desktop surface renderer) | The desktop companion UI above the RF-2.6 headless host; the wire core never depends on it | RF-6 |

Standing notes:

- **The JSON-RPC envelope stays hand-rolled** (Decision 4) — recorded here so the
  absence of a jsonrpc library is legible as a decision, not an omission: no
  canonical Kotlin JSON-RPC library exists, and SPEC §7/§8 constrain dispatch past
  what a generic one provides.
- **org.json** is an *exit*, not an adoption: deleted at C6 (`compileOnly` today
  because the Android framework supplies it at runtime).
- **cr-sqlite** is a design reference only (frozen: last push 2024-10, last release
  2024-01, pre-1.0 — audit P3-2). It is not adopted and gets no row; recorded so
  nobody mistakes the citation in RF-4a for an adoption.
