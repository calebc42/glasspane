# RF-2 Runbook — `:wire` to KMP (jvm-only) + org.json → kotlinx.serialization

## Context

RF-2 of [docs/PLAN-refound-2026-07-28.md](../../pkb/projects/jetpacs/jetpacs/llm-poc-2/docs/PLAN-refound-2026-07-28.md): make the wire core's platform-freedom compiler-enforced (KMP `commonMain`) and swap org.json for kotlinx.serialization's `JsonElement`. Hand-executed by Caleb; local gates only (no CI — deviation from the refound plan, ratified 2026-07-28); all 34 test files stay in `jvmTest`.

Exploration facts this plan builds on (verified):
- `EbpJson.parse` is already a hand-rolled, KMP-clean strict parser producing a custom `EbpValue` tree. org.json enters only via the projection `toOrgJson` (EbpJson.kt:65-78), which deliberately narrows `EInt`→`Int` so `CompanionEngine.kt:212`'s `(msg.opt("id") as? Int)` response-id lookup matches.
- ~625 org.json sites in `:wire` (21 of 27 files; CompanionEngine 235), ~295 in `:app` (16 files). `:wire`'s public API leaks `JSONObject` into 30+ signatures used by `:app` → **both modules migrate in one pass**.
- **No Kotlin test compares serialized JSON bytes**, and SPEC.md:4287-4290 mandates *semantic* comparison — wire-byte drift from escaping/number-spelling is SPEC-legal. Goldens are static submodule artifacts nothing in Kotlin regenerates.
- Outbound bytes funnel through `CompanionEngine.emit`/`serializeReply` (org.json `toString()`); `toString()` is also a byte-measuring-tape at 10 normative-limit sites and a deep-copy hack at 5 sites.
- First execution step: copy this file into the repo as `llm-poc-2/docs/PLAN-rf2-kmp-migration.md` and commit it (with the untracked PLAN-refound doc).

`$POC` = `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2`. Gradle runs from `$POC/companion`.

## Ground rules

**The four gates** (each step names its subset):

| Gate | Command | Proves |
|---|---|---|
| G-wire | `./gradlew :wire:jvmTest` (pre-RF-2a: `:wire:test`) | 34 suites incl. 17 `.bin` fixtures × 3 chunkings |
| G-app | `./gradlew :app:testDebugUnitTest :app:assembleDebug` | :app compiles against :wire API; APK builds |
| G-spec | `cd $POC && python3 ebp/validate.py` | goldens/contract/spec-sync untouched |
| G-elisp | `cd $POC && test/run-tests.sh` | ~26 ERT suites (elisp side; doesn't exercise Kotlin) |

**I1 restated precisely**: (a) `git status --short $POC/ebp` shows no golden edits — goldens are never touched; (b) G-wire + G-app green; (c) G-spec green. It is *not* "output bytes identical" — byte drift is expected and SPEC-legal.

**Branch/rollback**: one branch per sub-step (`rf-2a`, `rf-2b`, `rf-2c`) from a green tip; commit at every named checkpoint; rollback = `git reset --hard <checkpoint>`. Red commits are fine mid-`rf-2b` — the branch is the workspace, the merge is gated.

**Module-wide null convention** (adopt once, apply everywhere): Kotlin `null` = **absent** member; `JsonNull` = JSON **null**. `JsonObject` is a `Map<String, JsonElement>`, so `obj[k]` is null exactly when absent — cleaner than org.json ever was. Exception: the drafts/`hookValue` `Any?` seams re-type as `JsonElement?` where Kotlin null = JSON null (matches today's `?: JSONObject.NULL` elvis sites exactly — see R-null below).

---

## §0 STATE — execution ledger (update at every checkpoint)

| Checkpoint | What | Status |
|---|---|---|
| P0 | Phase 0.2 pre-swap pin tests | **NOT DONE** — next step; still writable, org.json is still live |
| A | RF-2a KMP flip, sources to `jvmMain` | DONE `7f6bfde` |
| B0 | kotlinx-serialization-json dependency (`api`) | DONE `2271211` |
| B1 | `JsonAccess.kt` + `EbpJson.toJsonElement` (additive) | DONE `94720a5` |
| C2–C6 | the conversion proper | OPEN |
| H1–H7 | RF-2c hoist to `commonMain` | OPEN |

**Executed on `slop-fork/main`, not on per-sub-step branches** (Ground rules'
branch/rollback scheme): every commit so far is a green checkpoint, so the
branch bought nothing. Cut `rf-2b` before C2 — that is where the directed red
period starts and where rollback stops being a one-commit revert.

**Test-count parity number (0.2-9):** `:wire:jvmTest` ran **315** tests in 34
suites at checkpoint A — the post-flip parity figure, taken after the flip
rather than before it, so it proves nothing about the flip itself; the flip's
proof is that `git diff --numstat -M` showed content edits in build files only.
B1 added `JsonAccessTest` (16 tests) → **331**. `:app:testDebugUnitTest` 26.

**Deviations from this runbook so far:** (1) Phase 0.2 was skipped ahead of
Phase 1 — the pin tests are still valid and still pass against org.json, but
write them before C2 or the conversion loses its semantic-delta harness;
(2) B1 shipped `JsonAccessTest` (not called for in 2.2) — the accessors encode
one decision each and were cheaper to pin than to re-derive at 625 call sites;
(3) `isNullOrAbsent` is a named helper rather than the inline `let` of 2.3.

---

## Phase 0 — Baseline + pre-swap pin tests (org.json still in place)

**0.1 Baseline green.** Run all four gates from a clean tree; if anything is red, stop. Commit the two plan docs. `git switch -c rf-2a`.

**0.2 Pre-swap pin tests** — write these NOW, while org.json is live; they pass today and convert every semantic delta into a conscious diff. Priority order:

1. **`PersistenceCompatTest`** (new, `wire/src/test/`): commit org.json-*written* fixture files for all four stores — a queue record with ~62-deep `args` (re-wrapped depth exceeds `MAX_JSON_DEPTH` 64!), the legacy pre-split surfaces file (exercises `SurfaceBacking.kt:84-88` migration), a reminder with integral-double `at_ms`, a triggers file with runtime records. Assert each store loads with full fidelity. **This is the upgrade gate: the migrated read path must be lenient `Json.parseToJsonElement`, NEVER strict `EbpJson.parse` — a strict re-parse of a legal legacy queue file crash-loops the app.**
2. **Integral-double acceptance** (extend `ReminderTest`/`ActionEventTest`/`CapabilityTest`): `"at_ms": 5000.0`, `"ttl_s": 60.0`, `"ms": 100.0` are accepted-and-functional today (org.json `getLong` truncates); a naive `jsonPrimitive.long` port crashes at tap time. Pin acceptance now; during the swap either normalize-to-Long at accept time (like `TriggerValidator.kt:148` already does — preferred) or use integrality-checked `double.toLong()` readers.
3. **`EnvelopeIdTest.responseIdStringNeverMatchesIntegerPending`**: response `"id":"1"` (string) must NOT conclude pending integer id 1; `"id":1` must. The entire durable pump and every callback hangs on this.
4. **`TriggerTest.respellNumberKeepsRuntimeRecords`** + `canonicalEquals` cross-spelling (`{"a":60}` ≡ `{"a":60.0}` — true today, and must stay true): a lost throttle floor double-fires triggers; a lost one-shot completion re-arms it.
5. **`ByteGateConsistencyTest`** (in `W6QueueTest.kt`): dispatch an event whose args contain `"— “q” €</x"` + U+0085; assert the measured size equals the emitted frame-body size and DurableQueue accounts the same bytes. Pins the *invariant* (measure-with-what-you-emit), survives the swap.
6. **Draft null round-trip** (`SurfaceBackingTest`/`SurfaceStoreTest`): putDraft(null) → persist → reload → draft is JSON null (not the string `"null"`, not absent); untouched field captures as JSON null with `hasDraft` false.
7. **`SubstitutionTest.integralDoubleSubstitutesWithoutDecimalPoint`**: `${data.x}` with `2.0` → `"2"` (keep `Substitution.jsonNumber` verbatim).
8. Cheap taxonomy pins: revision `1.0`/`"1"` → −32602; toast `duration_s` `2.0`/`"5"` ignored; `{"method":5}` behavior (today: connection close — flip consciously if desired); `DialogTest.rpcCancelWithIntegerIdConcludesDialog`.
9. **Runbook assertions** (not tests): record the executed-test count (`grep -c "<testcase" wire/build/test-results/test/*.xml` total) for post-flip parity; mark `CapabilityTest.unserializableResultIsAnsweredNotDropped` (deep-tree → −32603) and `JsonEqualityTest` (`1 == 1.0` TRUE, `"1" == 1` FALSE) as MUST-PORT-UNCHANGED.

Gate: G-wire green with the new tests. Commit (checkpoint **P0**).

---

## Phase 1 — RF-2a: the KMP flip (zero behavior change)

**1.1 Catalog + root plugins.** In `gradle/libs.versions.toml` `[plugins]` add
`kotlin-multiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }`.
In `companion/build.gradle.kts` flip line 4: `alias(libs.plugins.kotlin.jvm) apply false` → `alias(libs.plugins.kotlin.multiplatform) apply false` (keeps KGP's `KotlinPlatformType` compatibility rules on the build classpath — this is what lets AGP resolve a jvm-only KMP project). Same plugin artifact, different id — no version skew possible.

**1.2 Move sources with history.**
```bash
cd $POC/companion/wire && git mv src/main src/jvmMain && git mv src/test src/jvmTest
```

**1.3 Rewrite `wire/build.gradle.kts`** (complete new contents):
```kotlin
plugins { alias(libs.plugins.kotlin.multiplatform) }

kotlin {
    jvmToolchain(21)
    jvm()
    sourceSets {
        jvmMain.dependencies { compileOnly(libs.json) }   // framework-supplied on device
        jvmTest.dependencies {
            implementation(libs.json)
            implementation(libs.junit)
        }
    }
}

tasks.named<Test>("jvmTest") {
    useJUnit()
    systemProperty("ebp.dir", rootDir.resolve("../ebp").canonicalPath)
}
// keep the documented gate command working
tasks.register("test") { dependsOn("jvmTest") }
```
WHY: KMP has no `test` task or top-level `dependencies{}`; the `ebp.dir` property must ride `jvmTest` or five conformance suites lose their fixtures (they fail loudly — that's the check). `rootDir` still = `$POC/companion`, so `../ebp` is unchanged; the `user.dir` walk in `WidgetsGoldenReplayTest` also survives.

**1.4 Gate.** G-wire (new task name; **assert test-count parity** vs 0.2's recorded number, now under `test-results/jvmTest/`), G-app, G-spec, and `git diff --stat -M100% HEAD` = renames + build files only.
**Contingency** if `:app:assembleDebug` fails variant matching ("no matching variant of project :wire"): diagnose with `./gradlew :app:dependencyInsight --configuration debugRuntimeClasspath --dependency wire`. If `TargetJvmEnvironment` is the mismatched attribute, add a consumer-side compatibility rule in `:app`; if `org.jetbrains.kotlin.platform.type` fails, verify 1.1's root-classpath flip landed. Hard stop + rollback rather than fight anything else.
Commit (checkpoint **A**); delete the now-unused `kotlin-jvm` alias if `grep -rn "kotlin.jvm" companion --include=*.kts` is clean.

---

## Phase 2 — RF-2b: org.json → JsonElement (both modules, one directed red period)

**Strategy**: core-first, hub-last — `EbpJson`/`FrameCodec`/`Envelope`/`JsonEquality` define the types every signature carries, so each subsequent compiler error is downstream pressure pointing at the next file. The compiler is the worklist:
`./gradlew :wire:compileKotlinJvm 2>&1 | grep "^e: " | cut -d: -f1 | sort | uniq -c | sort -rn | head`.

**2.1 Dependencies** (tree stays green). Catalog:
```toml
[versions] kotlinx-serialization = "1.8.0"        # runtime for Kotlin 2.1.x
[libraries] kotlinx-serialization-json = { group = "org.jetbrains.kotlinx", name = "kotlinx-serialization-json", version.ref = "kotlinx-serialization" }
```
`jvmMain.dependencies`: **`api(libs.kotlinx.serialization.json)`** — `api` because `JsonElement` appears in `:wire`'s public signatures consumed by `:app`. **No serialization compiler plugin** — tree API only, zero `@Serializable`. Gate: G-wire + `:app:assembleDebug`. Commit (**B0**).

**2.2 Add `JsonAccess.kt` + `toJsonElement`** alongside the old code (green). New file `wire/src/jvmMain/.../JsonAccess.kt` — commonMain-clean by construction; encodes every translation decision once:
```kotlin
// Convention: Kotlin null = ABSENT; JsonNull = JSON null.
internal fun JsonObject.objOrNull(k: String): JsonObject? = this[k] as? JsonObject
internal fun JsonObject.arrOrNull(k: String): JsonArray? = this[k] as? JsonArray
internal fun JsonObject.stringOrNull(k: String): String? =
    (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content        // JsonNull: isString=false → safe
internal fun JsonObject.stringOr(k: String, d: String = ""): String = stringOrNull(k) ?: d
// wireInt recovers today's `is Int || is Long` predicate exactly: EInt content never has '.'/'e'
internal fun JsonObject.wireIntOrNull(k: String): Long? =
    (this[k] as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }?.content?.toLongOrNull()
internal fun JsonObject.longOr(k: String, d: Long = 0L): Long = wireIntOrNull(k) ?: d
internal fun JsonObject.boolOr(k: String, d: Boolean = false): Boolean =
    (this[k] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toBooleanStrictOrNull() ?: d
// throwing (get-style) accessors keep the crash-vs-reply behavior:
internal fun JsonObject.reqString(k: String): String = stringOrNull(k) ?: throw NoSuchElementException(k)
internal fun JsonObject.reqLong(k: String): Long = wireIntOrNull(k) ?: throw NoSuchElementException(k)
internal fun JsonObject.reqObj(k: String): JsonObject = objOrNull(k) ?: throw NoSuchElementException(k)
internal fun JsonObject.reqArr(k: String): JsonArray = arrOrNull(k) ?: throw NoSuchElementException(k)
// persistent "mutation":
internal fun JsonObject.with(k: String, v: JsonElement): JsonObject = JsonObject(this + (k to v))
internal fun JsonObject.without(k: String): JsonObject = JsonObject(this - k)
// SPEC 4.2 integer-vs-binary64 discrimination for validators:
internal val JsonPrimitive.isIntegral: Boolean get() = !isString && content.toLongOrNull() != null
// outbound-response correlation (Companion ids are integers, SPEC 7.2):
internal fun requestIdKey(e: JsonElement?): Long? =
    (e as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toLongOrNull()
```
In `EbpJson.kt` add `toJsonElement(v: EbpValue): JsonElement` — `EInt → JsonPrimitive(v.v)` (**Long always; the Int narrowing dies** — its only customer was the id map, redesigned below). Gate: G-wire. Commit (**B1**). Everything after rolls back to B1.

**2.3 Desk-reference translation table** (semantic deltas bolded):

| org.json | kotlinx | Delta |
|---|---|---|
| `JSONObject().put(k,v)…` ×429 | `buildJsonObject { put(k, v) }` | **`put(k, null)` removed the member; `put(k, JsonNull)` writes null** — audit every put whose value can be Kotlin-null |
| `.opt(k)` ×218 | `obj[k]` | absent=null, null=JsonNull — the distinction org.json blurred |
| `.has(k)` ×145 | `k in obj` | — |
| `.length()` ×93 | `.size` | — |
| `.optJSONObject/.optJSONArray` | `objOrNull/arrOrNull` | — |
| `.getString/.getLong/.get*` | `reqString/reqLong/…` | throws `NoSuchElementException` not `JSONException`; **string-coercion dies** (org.json parsed `"42"` as 42 — all sites are validator-gated, stricter is correct; a tripping test = real latent laxity) |
| `.optString(k,d)/.optLong/.optBoolean` | `stringOr/longOr/boolOr` | **org.json folded explicit-null to the default AND coerced types; helpers do the fold, drop coercion** |
| `.keySet()` ×33 | `.keys` | insertion-ordered now (was HashMap-random) — benign; scanSyncedEditors duplicate-identity resolution becomes deterministic |
| `.toString()` wire/measure/persist ×31 | `elem.toString()` | **byte drift, SPEC-legal**; keep ONE `wireSerialize()` used by BOTH every measuring site and every emit site, swapped in the same commit |
| `.remove(k)` ×20 | `obj.without(k)` — **returns new; assign it back** | a copy-and-forget compiles and stalls the pump |
| `.isNull(k)` | `obj[k].let { it == null \|\| it is JsonNull }` | org.json's isNull was true for absent too — preserve, don't "fix" |
| `JSONObject.NULL` (~10 sites) | `JsonNull`; `=== NULL` → `is JsonNull` | — |
| `JSONObject(x.toString())` deep copy ×5 | delete — immutable trees share safely | **removes the org.json bug where copied `2.0` became `2`** (SPEC 17.4 fix; drift is legal) |
| `value is JSONObject` (validators) | `is JsonObject`; integer checks via `isIntegral` | — |
| parsing text (tests/stores) | `Json.parseToJsonElement(text)` | **wire path stays `EbpJson.parse` + `toJsonElement` — kotlinx must never parse wire bytes** (duplicate-keys/2^53 taxonomy is nonconforming) |

Grep-ban after conversion: `.content` outside `JsonAccess.kt` (raw content coerces strings and stringifies JsonNull to `"null"`).

**2.4 Six structural redesigns** (land as you reach their files):
- **R1 `serializeReply`** (CompanionEngine.kt:2261): `try { msg.toString() } catch (t: Throwable) { null }` — the one deliberate catch-all funnel behind SPEC 7.1's "never leave a request unanswered"; kotlinx throws where org.json returned null, and deep host results can still overflow. Port the deep-tree CapabilityTest unchanged (build the 60k-deep tree bottom-up: `repeat(60_000) { cur = JsonObject(mapOf("n" to cur)) }`).
- **R2 id matching** (CompanionEngine.kt:212,226,265): `nextOutboundId: Long`; `pending: HashMap<Long, cb>`; RESPONSE arm uses `requestIdKey(msg["id"])` (isString-guarded — pinned by test 0.2-3). Inbound ids (peer requests, dialog deferred replies): store and echo the **original `JsonElement`** verbatim; `respondResult/respondError(id: JsonElement, …)`. `isValidRequestId(id: JsonElement?)`: string branch checks content length/regex (ASCII, so length = octets); numeric branch `!isString && content.toLongOrNull() in ±2^53−1`. `rpc.cancel`'s `dialogs` map compares JsonElement-to-JsonElement (data-class equality distinguishes `5` from `"5"`).
- **R3 mutation sites**: `DurableQueue.kt:134` build the final record *before* capacity math (`record.with("queue_seq", …)`); `:211` `records[i] = records[i].without("pending_local")` — then persist; `Envelope.errorResponse:65` stops mutating the caller's `data` (`data.with(…)`); CompanionEngine args/fields accumulation (`:306,394,400,421,1105`) + ContextlessEvents (`:109,147`) become single `buildJsonObject { … }` merges — shorter than the copy-then-mutate originals.
- **R4 deep copies**: `descriptor.objOrNull("args") ?: JsonObject(emptyMap())` — immutability makes sharing safe; R3's builders already produce fresh objects.
- **R5 `JsonEquality` + `TriggerStore.canonicalEquals`**: do NOT use `JsonPrimitive.equals` (content-string: `1 ≠ 1.0`, violates SPEC 4.3). Reimplement the LD-20 type-tag gate: strings by isString+content, booleans by content, **numbers by `content.toDouble()` value** (exact under the 2^53 bound), JsonNull only equals JsonNull, absent (Kotlin null) only absent. Port `JsonEqualityTest` with meanings unchanged.
- **R6 org.json-shaped `Any?` → `JsonElement?` module-wide** (drafts, `InputDisplay.value`, `authoredValueOf`, `hookValue`, `publishState`, renderer callbacks): Kotlin null = JSON null at these seams (matches today's `?: JSONObject.NULL` elvises — they only ever fired for absent, and JsonNull is non-null so they still never fire). `Renderer.kt:97`'s sentinel becomes `it !is JsonNull`. `authoredValueOf` migrates as `node["value"] ?: JsonPrimitive("")` — same absent-vs-null structure, don't "clean it up".

**2.5 Execution order** (checkpoints = commits; red allowed):
- **C2 core** (red starts): `EbpJson.kt` (delete `toOrgJson` + org.json imports), `FrameCodec.kt:192` (`toJsonElement(value) as JsonObject` — same cast enforces top-level-object; leave ByteBuffer internals for RF-2c), `Envelope.kt` (builders → `buildJsonObject`; `classifyMessage` checks `jsonrpc` is a *string* primitive `"2.0"` — numeric 2.0 stays invalid; require `method` to be a string primitive and route non-string method to the −32600 path — a deliberate, commented taxonomy change from today's connection-close), `JsonEquality.kt` (R5).
- **C3 validators + stores**: `Auth.kt`, `SpecValidator.kt` (78; `isIntegral` carries integer checks), `TriggerValidator.kt` (54), `Substitution.kt` (keep `jsonNumber` floor-collapse verbatim), `CapabilityCatalog.kt`, `QueueStore.kt` + `DurableQueue.kt` (R3; **persistence reads = `Json.parseToJsonElement`, with a comment saying why not EbpJson**), `SurfaceBacking.kt`/`SurfaceStore.kt` (R6), `ReminderBacking/Store`, `TriggerBacking/Store` (R5), `TriggerRuntime.kt`, `TriggerFiringService.kt` (keep filter-not-fail in `jsonStringSet`), `ContextlessEvents.kt`.
- **C4 the hub**: `CompanionEngine.kt` (235 sites; R1-R4, R6 converge — do R2 then R1 first so dispatch tests guide the rest; migrate the measure/emit sites in the SAME commit per the wireSerialize rule). Gate: `:wire:compileKotlinJvm` green + `grep -rn "org.json" wire/src/jvmMain/` empty.
- **C5 `:wire` tests** (33 files ~7.6k LOC, mechanical): fixtures via `Json.parseToJsonElement("""…""")`; port MUST-PORT-UNCHANGED tests faithfully. Gate: **G-wire + G-spec + goldens-untouched** (= I1). Commit.
- **C6 `:app`** (16 files ~295 sites: LayoutNodes 68, Renderer 45, InputNodes 33, DeviceBridge 30): same table; add a small `NodeAccess.kt` in `render/` with `dimInt(k,d) = doubleOrNull?.toInt() ?: d` — dimension members are legally fractional (SpecValidator gates them as Number) and are truncated today; raw `intOrNull` would silently drop them to defaults. Then delete org.json everywhere: remove `compileOnly`/`testImplementation(libs.json)` from both modules + the catalog entry once `grep -rn "org.json" companion/{wire,app}/src` is empty. Gate: **G-app**. Commit.

**RF-2b exit gate**: all four gates + both greps + goldens-untouched. Device note: legacy on-device store files parse fine under the lenient reader (pinned by PersistenceCompatTest), but do a **clean install** for the APK smoke anyway.

---

## Phase 3 — RF-2c: hoist to commonMain

**3.1 Decisions.** Stays `jvmMain` permanently: the four `File*` store impls (split each file: interface + Memory impl → commonMain; File impl → new jvmMain file) and `ImageGuards.kt` (`InetAddress` API). `@Volatile` ×4 → `kotlin.concurrent.Volatile`. **`@Synchronized` ×59 → `WireLock` expect/actual** (no wait/notify anywhere in `:wire`; monitors are pure mutual exclusion; JVM actual `synchronized(monitor)` preserves reentrancy, which matters — dispatchAction→executeBuiltin nest). Pattern: `private val lock = WireLock()`; body wraps in `lock.withLock { … }`. **Discipline: `grep -c "@Synchronized"` per file before, count conversions off — a miss is a silent race, not a compile error.**

**3.2 expect/actual + pure-common rewrites.**
```kotlin
// commonMain Platform.kt                          // jvmMain Platform.jvm.kt actuals
internal expect fun secureRandomBytes(n: Int): ByteArray          // SecureRandom (one instance)
internal expect fun hmacSha256(key: ByteArray, msg: ByteArray): ByteArray  // Mac/SecretKeySpec
internal expect fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean // MessageDigest.isEqual
internal expect fun base64UrlDecode(text: String): ByteArray      // java.util.Base64
internal expect class WireLock() { fun <T> withLock(block: () -> T): T }
```
Pure-common (no expect needed): hex via `joinToString` bit-trick (replaces `"%02x".format`); **strict UTF-8 = `ByteArray.decodeToString(throwOnInvalidSequence = true)`** (common stdlib; rejects exactly what `CodingErrorAction.REPORT` rejected — the 17×3 fixture matrix is the acceptance harness) and `String.encodeToByteArray()`; `ByteBuffer`/`System.arraycopy` → `ByteArray`/`copyInto`; codepoint helpers in new `TextUnits.kt` (`codePointAtCompat`/`codePointCountCompat`/`offsetByCodePointsCompat` — `Char.isHighSurrogate` IS common; **add a jvmTest property-checking each against the `java.lang` originals** over ASCII/BMP/astral/lone-surrogate corpora); time via **kotlinx-datetime 0.6.2** (`api` in commonMain; `Instant.fromEpochMilliseconds`, `TimeZone.of`/`currentSystemDefault`, `LocalTime`, `DayOfWeek` — JVM impl delegates to java.time so SPEC 21.7 behavior is preserved; retarget `DateTimeException` catches to `IllegalTimeZoneException`); DurableQueue's default clock → `Clock.System.now().toEpochMilliseconds()`. Caveat: `encodeToByteArray()` writes U+FFFD (3 bytes) for lone surrogates where `toByteArray(UTF_8)` wrote `?` (1 byte) — wire strings are surrogate-clean by parser construction, but host-supplied strings (clipboard) should keep a jvm-actual byte counter if any gate measures them.

**3.3 Hoist order** (each step ends G-wire green; G-app at H4/H7):
H1 moves-only (already pure): `JsonAccess.kt`, `JsonEquality.kt`, `Envelope.kt`, `Vocabulary.kt`, `MethodRegistry.kt`, `ToolbarEdits.kt`, `Session.kt`. H2: `TextUnits.kt` + `EbpJson.kt` + `EditorSession.kt`. H3: `FrameCodec.kt` (ByteArray rewrite; carries `WireLimits`). H4: `Platform.kt`/`Platform.jvm.kt` + `Auth.kt`. H5: kotlinx-datetime + `TriggerRuntime/Validator/FiringService` (AtomicReference → `@Volatile var` if writes are lock-guarded — verify at hoist). H6: `WireLock` + `DurableQueue`, store interfaces/Memory impls (File impls split to jvmMain), `SurfaceStore`, `ReminderStore`, `TriggerStore`, `Substitution`, `SpecValidator`, `CapabilityCatalog`, `ContextlessEvents`. H7: `CompanionEngine.kt` (bulk of the WireLock sweep).
End state jvmMain: `Platform.jvm.kt`, `ImageGuards.kt`, `FileQueueStore.kt`, `FileSurfaceBacking.kt`, `FileReminderBacking.kt`, `FileTriggerBacking.kt`.

**3.4 Final `wire/build.gradle.kts`**: commonMain deps = `api(kotlinx-serialization-json)` + `api(kotlinx-datetime)`; jvmTest = junit; same `jvmTest` task config.

**3.5 Purity gate — two parts** (subtlety: with a single jvm() target, commonMain compiles WITH the JVM classpath, so `java.*` silently resolves; "commonMain compiles" is not yet the proof):
1. Every checkpoint: `! grep -rnE '(^import (java|javax|android)\.)|[^.[:alnum:]](java|javax|android)\.[a-z]' wire/src/commonMain/`
2. RF-2c exit, one-time scratch edit (do not commit): add `linuxX64()` to the kotlin block, run `./gradlew :wire:compileKotlinLinuxX64` (downloads K/N toolchain once; serialization 1.8.0 + datetime 0.6.2 both publish linuxX64 klibs), then `git checkout -- wire/build.gradle.kts`. This compiles commonMain under a non-JVM frontend — `java.*` genuinely unresolvable, expect/actual fully checked. When a real second target lands, this becomes a permanent gate for free.

**RF-2c exit**: purity (both parts) + all four gates + jvmMain contains only the six intended files.

---

## Final verification

```bash
cd $POC/companion && ./gradlew clean :wire:jvmTest :app:testDebugUnitTest :app:assembleDebug
cd $POC && python3 ebp/validate.py && test/run-tests.sh
git status --short ebp/                                   # empty — goldens never edited
grep -rn "org.json" companion/ --include=*.kt --include=*.kts   # empty
```
APK smoke (manual, clean install): pair, one surface round-trip, one dialog, one queued-offline action — exercising emit/serializeReply/DurableQueue, the three redesigned funnels. Plus one float-authored action arg end-to-end (the SPEC 17.4 echo fix).

## Effort honesty — the three hardest steps

1. **C4 `CompanionEngine.kt`** — 235 sites, all six redesigns converge in a 2,300-line file. Budget 1-2 focused days; land R2 (id map) and R1 (serializeReply) first so dispatch tests guide the rest.
2. **C5 test conversion** — 33 files / 7.6k LOC mechanical-but-relentless; this is where real semantic regressions surface (the stricter accessor deltas).
3. **H6-H7 `@Synchronized`→`WireLock`** — 59 sites where a miss is a silent race; use per-file grep counts. Close fourth: H3 FrameCodec ByteArray rewrite (bounded by the 17×3 fixture matrix).

## Out of scope (explicit)

CI (RF-1, later rung), kotlin.test/commonTest port (when a second target lands), RF-3 (module seam) and RF-4 (`ebp.data`) — separate plans. JA-4/JA-6 P1 batches: Claude executes next, independent of this runbook.
