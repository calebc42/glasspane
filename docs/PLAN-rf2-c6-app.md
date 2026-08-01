# PLAN — RF-2b C6: `:app` to kotlinx (Opus fleet execution doc)

Companion to [PLAN-rf2-c5-tests.md](PLAN-rf2-c5-tests.md) (§8 amendment: Opus converts,
Fable orchestrates/recovers green). Ledger metric: `./gradlew :app:compileDebugKotlin`
error count, baseline **77**. Gate: `./gradlew :app:testDebugUnitTest :app:assembleDebug`
(G-app; 26-test parity floor). EVERY grep over app sources runs with `-a`
(Notifications.kt carries a NUL byte and is otherwise grep-invisible — §0.1 below).

## §A COMMON DIRECTIVES FOR EVERY CONVERSION AGENT

You convert exactly ONE file, in place, with zero discretion; your per-file sheet
(§B.x / §T.x below) pre-makes every judgment call and WINS over this section on
conflict. Do not touch any other file, `:wire`, gradle files, or `NodeAccess.kt`.
Do not run gradle. Preserve every function, every assertion, every comment (prose
naming org.json stays; two comments are re-worded per their sheets). Style exemplars:
`companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/ContextlessEvents.kt` (builders/readers)
and `companion/app/src/main/kotlin/com/calebc42/ebp/companion/render/NodeAccess.kt` (the app reader roster).

1. READERS — use `NodeAccess.kt` (package `com.calebc42.ebp.companion.render`,
   internal to :app): `stringOrNull/stringOr/boolOrNull/boolOr/objOrNull/arrOrNull/
   doubleOr/dimInt/intByValue/longByValue/numOrNull/strOrNull`. `:app` CANNOT see
   :wire's internal JsonAccess. Public :wire helpers you MAY use: `jsonValueEquals`,
   `jsonStringSet`, `notification/request/resultResponse/errorResponse/isValidRequestId`,
   `encodeFrame`, `SurfaceStore.authoredValueOf`.
2. BUILDERS: `JSONObject().put(...)` chains -> `buildJsonObject { put(...) }`;
   `putJsonObject/putJsonArray` for nesting; `JSONObject()` -> `JsonObject(emptyMap())`;
   `JSONArray()` -> `JsonArray(emptyList())`; `JSONArray(listOfStrings)` ->
   `JsonArray(list.map(::JsonPrimitive))`; `JSONArray(List<JsonObject>)` -> `JsonArray(list)`.
   INT-SPELLED members stay Int/Long literals (limits, index/from/to, level, ids) —
   the engine reads limits with reqLong and a `.0` throws at construction.
3. THE ALWAYS-NULL CAST TRAP (app's #1): after a seam retypes to `JsonElement?`,
   `as? String`/`as? Boolean`/`as? Number` compiles and is ALWAYS null. Every such
   site gets an explicit primitive read per its sheet. After converting, grep your
   file for `as\? (String|Boolean|Number)` — required zero.
4. JSONObject.NULL: assert/read sentinel -> `it !is JsonNull` (Renderer:97 shape);
   build-into-fields -> `?: JsonNull` (NEVER omit; NEVER Kotlin null at
   InputNodes:277 — the seeding elvis depends on JsonNull being non-null).
5. NUMBERS: dimension (dp/number) reads -> `dimInt`/`numOrNull` (fractional legal,
   truncate); integer-by-value spec members (initial/max_lines/day/year/month_index/
   dots) -> `intByValue`; pass-through-verbatim (at_ms, base_ms, capability ms,
   pattern[i]) -> `longByValue` (P0-pinned integral doubles are working traffic);
   1-arg `optDouble` NaN-default sites keep skip-on-absent via `node[k]?.numOrNull()?.let{...}`
   — NEVER `?: 0.0`.
6. ARRAYS: `.length()` -> `.size`; `.opt(i)/.optJSONObject(i)` -> `getOrNull(i) as? JsonObject`
   where the index is not provably in range (PieMenu especially); bounded loops may
   use `arr[i]`. `arr.optString(i)` -> `arr[i].strOrNull().orEmpty()` (bounded) /
   `getOrNull(i)?.strOrNull()`.
7. PERSISTENCE/IPC text (`ebp-theme.json`, PendingIntent on_tap extras) parses with
   `Json.parseToJsonElement(text) as JsonObject` inside the existing catch(Exception)
   — NEVER EbpJson.parse. Serialization stays `.toString()`.
8. TESTS: expected values asserted against a `JsonElement?`-returning API MUST wrap
   in `JsonPrimitive(...)` (the app analogue of the L-suffix rule — a bare literal
   compiles and silently fails). Raw string-literal fixtures stay byte-verbatim;
   fully-qualified `org.json.*` uses (NodeSupportPinTest) convert to
   `Json.parseToJsonElement(...) as JsonObject/JsonArray`.
9. BANNED: kotlinx `.content/.jsonPrimitive/.int/.long/.intOrNull/.contentOrNull/
   .double/.boolean` accessors (read through NodeAccess or explicit
   `as? JsonPrimitive` + isString guards); wire-internal helper names that do not
   exist in NodeAccess.
10. POST-C6 TARGET SIGNATURES: every re-typed signature is listed in your sheet and
    §5's seam table — code against those exactly; RenderCtx's new shapes are in §B.1.
11. Do NOT simplify the `remember(json.toString())` identity dances, the Compose
    host structure, or NodeSupportPinTest's source-scanned `when (type) {` formatting.
    Convert body-for-body; flag simplifications in your report notes.

Return the structured report; never weaken silently — record concerns as uncertainties.

---

# C6 CONVERSION FACT SHEETS — `:app` org.json → kotlinx.serialization

Worktree: `/home/calebc42/pkb/projects/jetpacs/jetpacs/.claude/worktrees/rf2b-c5` (branch `rf-2b`, HEAD `1453fe2` "RF-2b(C5): the pins lit up green", tree clean). All paths below are absolute-relative to that root as `companion/app/src/...`.

---

## 0. TWO CORRECTIONS TO THE RUNBOOK, FOUND BY MEASURING

**0.1 `Notifications.kt` is invisible to grep and was omitted from the runbook's count.**
`/home/calebc42/pkb/projects/jetpacs/jetpacs/.claude/worktrees/rf2b-c5/companion/app/src/main/kotlin/com/calebc42/ebp/companion/Notifications.kt:54` contains a **raw NUL byte (0x00) inside a Kotlin string literal**:

```
od -c line 54: . d i g e s t ( " $ o w n e r \0 $ i d " . toByteArray(Charsets.UTF_8))
```

so `reminderKey` hashes `"$owner\u0000$id"` (a deliberate-looking unambiguous separator, undocumented). Consequence: GNU grep classifies the file as **binary** and `grep -rn "org.json"`, `grep -c`, `grep -oE | wc -l` all report **nothing** for it. My first inventory pass scored it 0 org.json sites; with `grep -a` it has **31**. This file is a 362-line, 31-site conversion with three live wire seams.

- **Gate integrity:** the RF-2b exit check `grep -rn "org.json" companion/ --include=*.kt` (runbook "Final verification") and `grep -rn "org.json" companion/{wire,app}/src` (§2.5 C6) **will pass while Notifications.kt still imports org.json**. Every C6 grep must be `grep -ra` / `grep -rn --binary-files=text`.
- No other `.kt` under `app/src` or `wire/src` contains control bytes (checked all).

**0.2 Counts.** Runbook says "16 files ~295 sites" with LayoutNodes 68 / Renderer 45 / InputNodes 33 / DeviceBridge 30. Measured: **18 main files, 347 sites** (LayoutNodes 68 ✓, Renderer 47, InputNodes 34, DeviceBridge 34, **Notifications 31**, VisualizationNodes 29). Test source set: 4 files, 26 sites, **26 @Test = the P0 parity floor exactly**.

---

## 1. INVENTORY

### 1.1 main (`app/src/main/kotlin/com/calebc42/ebp/companion/`) — 23 files

| lines | org.json sites | `^import org.json` | file |
|---|---|---|---|
| 733 | **68** | 2 | `render/LayoutNodes.kt` |
| 763 | **47** | 2 | `render/Renderer.kt` |
| 590 | **34** | 2 | `DeviceBridge.kt` |
| 493 | **34** | 2 | `render/InputNodes.kt` |
| 362 | **31** | 2 | `Notifications.kt` ← grep-invisible (§0.1) |
| 392 | **29** | 2 | `render/VisualizationNodes.kt` |
| 401 | **19** | 2 | `render/ContentNodes.kt` |
| 90 | **15** | 2 | `AppCapabilities.kt` |
| 199 | **13** | 2 | `render/EditorToolbar.kt` |
| 160 | **10** | 2 | `render/Attributes.kt` |
| 97 | **9** | 1 | `EbpApplication.kt` |
| 88 | **8** | 2 | `render/NodeSupport.kt` |
| 142 | **7** | 1 | `render/ThemeModel.kt` |
| 57 | **6** | 1 | `render/PieMenu.kt` |
| 162 | **5** | 1 | `MainActivity.kt` |
| 48 | **5** | 1 | `TriggerSources.kt` |
| 409 | **4** | 1 | `render/SyntaxHighlight.kt` |
| 93 | **3** | 1 | `TriggerAlarms.kt` |
| | | | **total 347 sites / 18 files** |

**Zero org.json — NO WORK (do not open, do not touch):** `CompanionStores.kt` (146), `render/ColorModel.kt` (84), `render/IconMap.kt` (114), `render/ImageCache.kt` (136), `render/ImageLoader.kt` (255).
Caveat: `CompanionStores.kt:112,116,117` and `:139-142` wire *lambdas whose types change* (`stateProvider: (String) -> JsonObject?`, `notifyListener: ((JsonObject) -> Unit)?`, `TriggerSources(app){type,sample->}`) — it compiles unchanged **only if** `AppCapabilities.deviceReport()` and `TriggerSources`/`Notifications.postTrigger` are converted correctly. It is a zero-edit file with three type dependencies.

### 1.2 test (`app/src/test/kotlin/com/calebc42/ebp/companion/render/`) — 4 files, 26 @Test

| lines | sites | @Test | file | note |
|---|---|---|---|---|
| 163 | 4 | **9** | `NodeSupportPinTest.kt` | **no org.json import** — uses fully-qualified `org.json.JSONArray(...)`/`org.json.JSONObject(...)` at 143/156/159/161 (the ReminderTest:117 trap, app-side) |
| 111 | 11 | **8** | `SyntaxHighlightTest.kt` | `JSONObject().put(...)` payload chains |
| 69 | 7 | **4** | `DialogCaptureTest.kt` | local `defaults{}` builder; `JSONObject.NULL`; `is JSONArray` |
| 85 | 4 | **5** | `ThemeModelTest.kt` | `JSONObject().put(...)` colors chains |

No `androidTest` source set. Task = `:app:testDebugUnitTest`.

---

## 2. PER-FILE FACT SHEETS

### B.1 `render/Renderer.kt` — 763 lines, 47 sites — THE HUB (R6 lands here)

**Signatures that re-type (every caller in :app follows):**

| line | today | post-C6 |
|---|---|---|
| 67 | `fields: SnapshotStateMap<String, Any?>` | `SnapshotStateMap<String, JsonElement?>` |
| 71 | `defaults: JSONObject? = null` | `JsonObject?` (from `bridge.dialogDefaults`) |
| 90 | `fun capture(id): Any?` | `JsonElement?` |
| 95 | `fun captureValue(id, fields: Map<String,Any?>, defaults: JSONObject?): Any?` | `Map<String, JsonElement?>`, `JsonObject?`, `JsonElement?` — **public, pinned by DialogCaptureTest** |
| 119 | `child(node: JSONObject?, index)` | `JsonObject?` |
| 147 | `storeValue(id): Any?` | `JsonElement?` |
| 149 | `action(descriptor: JSONObject?, value: Any? = null)` | `JsonObject?`, `JsonElement?` |
| 203 | `actionInjecting(descriptor: JSONObject?, injected: JSONObject, value: Any?=null)` | `JsonObject?`, `JsonObject`, `JsonElement?` |
| 210 | `actionWithFields(descriptor: JSONObject?, fields: JSONObject)` | `JsonObject?`, `JsonObject` |
| 215 | `state(id, value: Any?)` | `value: JsonElement?` |
| 228/239/250 | `RenderNode(node: JSONObject, …)`, `RenderDialogRoot(dialogId, spec: JSONObject, …)` | `JsonObject` |
| 317/330/340 | `RenderChildren/RowChildren/ColumnChildren(children: JSONArray?, …)` | `JsonArray?` |
| 760 | `onButton(onTap: JSONObject?, ctx)` | `JsonObject?` |

**JSONObject.NULL sites (3, all "build-null-into-fixture" except 97):**
- **97 — THE R6 SENTINEL** (runbook item 4, verbatim today):
  ```kotlin
  defaults?.has(id) == true -> defaults.get(id).takeIf { it != JSONObject.NULL }
  ```
  → `id in defaults -> defaults[id]?.takeIf { it !is JsonNull }`. **Must not be "cleaned up" to `defaults[id]`**: `CompanionEngine.kt:2120` writes `put(nodeId, SurfaceStore.authoredValueOf(node) ?: JsonNull)` — the member is **present and JsonNull** for a stateful node with no authored value, and the containment-vs-elvis distinction documented at 78-88 is the whole point of the function.
- **169** `fields.put(fieldId, d.capture(fieldId) ?: JSONObject.NULL)` → inside a `buildJsonObject { put(fieldId, d.capture(fieldId) ?: JsonNull) }`. Never omit — omission means absent, a different §14.1 capture.
- **193** same shape in the remote-descriptor-in-dialog arm.

**Mutation building → buildJsonObject (5):** 163-171 (`fields` accumulated in a loop over `capture_fields`), 189-195 (same), 387 `JSONObject().put(id, v)` (password fields). All become `buildJsonObject { … }`; the two loops become `buildJsonObject { for (i in capture.indices) put(capture[i].asStringOrNull()!!, …) }`-shaped.

**Numeric reads:** 288/289 `optDouble("width"/"height", 0.0)` (spacer, **dp/number — fractional legal**, already double-based → `?.asDoubleOrNull()`), 327 `weightOf: optDouble("weight", 0.0).toFloat()` (dp-class; note `weight` is not in FIELD_TYPES → unvalidated numeric, keep double).

**Silent-failure casts (the app's #1 trap — compiles with at most a warning, then always-null):**
- **368** `ctx.storeValue(id) as? String ?: node.optString("value")` (text_input seed)
- **454** `ctx.storeValue(id) as? String ?: node.optString("value")` (editor seed)
  After retype `storeValue: JsonElement?`, `as? String` **can never succeed** → every widget silently reverts to the authored value while the store still holds the user's draft = **exactly the LD-2 divergence the 133-146 comment says must not happen**, by a route no test covers. Replacement: `(ctx.storeValue(id) as? JsonPrimitive)?.takeIf { it.isString }?.content ?: node.stringOr("value")`.
- **320/333/343** `children.opt(i) as? JSONObject` → `children[i] as? JsonObject` (array index, `.opt(i)` had no throw; kotlinx `[i]` throws past the end — the loops are bounded by `.size`, safe).

**Value-injection call sites that must wrap (each is an `Any?` → `JsonElement?` param):** 388 `ctx.action(onSubmit, v)` (String); 406 `ctx.action(it, next)`; 424 (LayoutNodes' caller) — see B.2; 499 `ctx.state(id, new.text)`; 405/408 `ctx.state(id, next)`; 567 `ctx.action(onSave, value.text)`; 173 `descriptor.opt("value")` → `descriptor["value"]` (already an element, do **not** re-wrap).

**Keep-verbatim:** 251 `node.optString("t")` → `stringOr("t")`; 255-260 the unsupported-type degrade path; **263 `when (type) {` and every case label's exact indentation and quoting — `NodeSupportPinTest` SOURCE-SCANS this file** (`NodeSupportPinTest.kt:41` looks for the literal `when (type) {`, `:43` regex `^(\s+)"[a-z_]+"(\s*,\s*"[a-z_]+")*\s*->` and takes only the shallowest matching indent). Reformatting the dispatch, splitting a case, or adding a same-indent `"foo" ->` inside a nested when breaks 1 of the 26 tests.

**Seams into wire (see §5):** 172 `bridge.dialogSubmit`, 178 `dialogDismiss`, 196 `dialogAction`, 199 `bridge.action`, 205/211 injecting/withFields, 223 `bridge.editorCommand`, 233 `bridge.inputDisplays`, 244 `bridge.dialogDefaults`, 463 `ctx.bridge.editorMirrors`, 497 `bridge.editorEdit`, 504 `clearCompletions`, 516 `completionOffers`, 522 `editorComplete`, 584 `editorSelectCompletion`, 493 `EditorSession.diff` (pure, unchanged), 529 `node.optJSONArray("toolbar")` → `arrOrNull` feeding `EditorToolbar(items: JsonArray)`.

---

### B.2 `render/LayoutNodes.kt` — 733 lines, 68 sites (largest)

**Dimension reads — all already `optDouble`, all "dp" in FIELD_TYPES, fractional legal:** 104/115 `spacing`, 175 `run_spacing`, 220 `elevation`, 248 `content_padding`, 250 `spacing`. Port shape: `safeDp(node["spacing"]?.asDoubleOrNull() ?: 0.0)`.

**The ONE integer read: 396 `node.optInt("initial", 0).coerceIn(0, pageCount-1)`** — `initial` is `non-negative-integer` but `SpecValidator.kt:795-800` validates it with `asDoubleOrNull() + Math.floor` → **`"initial": 2.0` is ACCEPTED**, and org.json's `optInt` truncated it. A `wireIntOrNull`-shaped port returns null → default 0 → **tabs silently open on page 0**. Use the integral-tolerant read (§3a).

**Building/mutation (4 vararg-free builders):**
- 281-282 `ctx.actionInjecting(it, JSONObject().put("direction", …))` → `buildJsonObject { put("direction", …) }`
- 505 `JSONObject().put("index", ncols)`, 509 `…put("index", nrows)` → `buildJsonObject { put("index", ncols) }` — **Int-spelled** (`index` is engine-injected, integer-spelled; keep `put(k, Int)`).
- 626/627 `JSONObject().put("key", key)` / `.put("id", …)` — the §14.3 identity objects.
- **710-715 the reorder payload**: `JSONArray()` + `ids.put(itemIdentity(it))` loop then `JSONObject().put("from",…).put("to",…).put("order", ids)` → `buildJsonObject { put("from", dragStartPos); put("to", to); put("order", buildJsonArray { order.forEach { add(itemIdentity(it)) } }) }`. `from`/`to` stay **Int**.

**Value injection:** **424 `ctx.action(it, pagerState.settledPage)`** — an `Int` into `value: JsonElement?` → `JsonPrimitive(pagerState.settledPage)`; a mechanical port leaves a type error (compiler catches, good).

**Array iteration (`.length()` + `optJSONObject(i)`) — 12 loops:** 233-237 (scroll_here scan), 251 `items(count = children.length())` → `.size`, 252, 431 `minOf(items.length(), pageCount)`, 432, 451, 472-486 (table rows/cells), 479-480, 492 **`a.optString(i)`** (aligns array — element-level string: `a[i].asStringOrNull().orEmpty()`), 617/624/650, 638 `(0 until itemsJson.length()).toList()`, 648.

**Ordering / identity-dependent (do not "improve"):**
- **629-637** the deliberate two-step `val itemsSig = remember(itemsJson) { itemsJson.toString() }` + `remember(itemsSig)`. The comment says "JSONArray has no equals, so keying the state on the instance would reset the user's reorder on every re-push". **kotlinx `JsonArray`/`JsonObject` DO have structural equals/hashCode** (they delegate to the backing List/Map) → the second step becomes redundant and the `toString()` cost is now avoidable. It is still *correct* as written. Convert body-for-body; flag the simplification, do not perform it (behavior change class: `remember` key equality).
- 401 `key(ctx.path)`, 407-417 the retained-index reset, 419-426 settle reporting — preserve statement order.
- 271-285 `confirmValueChange` returning `false` (never settle dismissed) and the at-most-once `on_trigger` dispatch.
- 462-463 `data class CellsSpec(val cells: List<JSONObject>, …)` → `List<JsonObject>`; 536-577 the pure Layout math untouched.

**Type-dispatch:** none. **JSONObject.NULL:** none. **JSONException catches:** none.

---

### B.3 `DeviceBridge.kt` — 590 lines, 34 sites

**Constructor callback types (EbpApplication follows):** 76 `onSurfaceChanged: (String, JSONObject?) -> Unit`, 82 `onDialogChanged: (String?, JSONObject?)`, 88 `onTheme: (JSONObject?)`, 90 `onPieMenuChanged: (String, JSONObject?)` → all `JsonObject?`.

**The limits builder — 124-149, a 26-member `.put` chain**: → one `buildJsonObject { … }`. Every value must stay **integer-spelled** (`put("max_frame_bytes", 4_194_304)`); `ImageLoader.MAX_IMAGE_BYTES/…PIXELS` are `Long` consts (`ImageLoader.kt:30-32`) → `put(k, Long)` resolves to the Number overload, integer-spelled. `CompanionEngine`'s constructor reads these with **`reqLong`** (`CompanionEngine.kt:47-48, 61-62`, `config.limits.reqLong("max_surfaces")` etc.) — a `.0` spelling here throws at engine construction.

**Persistence (theme) — the lenient-read rule:** 159-162 `JSONObject(themeFile.readText())` → **`Json.parseToJsonElement(text) as JsonObject`**, never `EbpJson.parse` (same rule as the stores; a pre-upgrade `ebp-theme.json` must load). 164-170 `payload.toString()` → unchanged (kotlinx `toString()` *is* `wireSerialize`, `CompanionEngine.kt:2479`). The `catch (e: Exception)` at 162/169 already covers `SerializationException`/`IllegalArgumentException` — keep as-is (there is no `JSONException` catch anywhere in :app).

**Hand-built frame — 452-458:**
```kotlin
e.feed(encodeFrame(JSONObject().put("jsonrpc","2.0").put("method","pie_menu.dismiss")
    .put("params", JSONObject().put("menu_id", menuId)).toString()))
```
→ `encodeFrame(notification("pie_menu.dismiss", buildJsonObject { put("menu_id", menuId) }).toString())`. `notification` is **public** (`Envelope.kt:105`) and emits `jsonrpc` itself — preferred over re-hand-rolling the envelope.

**`Any?` seams:** 223 `PendingConfirm(… value: Any?, injected: JSONObject?, fields: JSONObject?)` → `JsonElement?`/`JsonObject?`; 236-246 `parkIfConfirmed`; 248 `dispatch`; 271/280/290/299 the four public action entries; 306 `state(surface, id, value: Any?)` → `JsonElement?`; 431 `dialogSubmit(dialogId, value: Any?, fields: JSONObject)` → `JsonElement?`, `JsonObject`.

**Error reads:** 261 and 265 `it.optString("message", "queue error")` — org.json's 2-arg `optString` folds absent **and explicit null** into the default; port as `stringOr("message", "queue error")` (same fold, coercion dropped). These are the only two `optString(k, d)` sites in this file.

**Completion callback — 364-379:** `requestCompletion(document, editorId) { prefix, cands, session, seq, cursor -> … }`; post-C4 `cands: JsonArray` (`CompanionEngine.kt:1838-1839`, callback `(String, JsonArray, String, Long, Int) -> Unit`). Body: `(0 until cands.length()).mapNotNull { cands.optJSONObject(i) }` → `cands.mapNotNull { it as? JsonObject }`; three `optString` reads → `stringOr`; **372-373 `insert` defaults to `label`** — keep the `takeIf { it.isNotEmpty() } ?: label` shape exactly (SPEC 19.3).

**View resolution — 463-468:** `spec.optJSONObject("views") ?: return spec`; `store.currentView(surface) ?: spec.optString("initial_view")`; `views.optJSONObject(name)` → `objOrNull`. `store.spec()` already returns `JsonObject?` post-C3.

**Listener attachments (types now fixed by wire; see §5) — 487-563**, plus `engine.pairingIdentity` (String?, unchanged), `engine.currentTheme(): JsonObject` (559), `engine.state`/`SessionState` (567), `engine.feed(ByteArray)`, `engine.close(String)`, `engine.withEditor(document,id){}`.

**Ordering-dependent:** 497-498 `_inputDisplays.value = store.inputDisplays()` **before** the spec push (T3/LD-2 comment); 574-587 the `finally` block order (`close` → clear mirrors → `clearLiveSession` → socket close).

---

### B.4 `render/InputNodes.kt` — 493 lines, 34 sites

**JSONObject.NULL — 277:** `else values.firstOrNull() ?: JSONObject.NULL` in `currentValue()`. → **`?: JsonNull`, NOT Kotlin null.** Reason chain: `ctx.state(id, v)` → `publishState` → `surfaces.putDraft(surface,id,value)` stores the *Kotlin-level* value (`SurfaceStore.kt:379-388`), and `InputDisplay.value` feeds back into **246** `ctx.storeValue(id) ?: node.opt("value")`. `JsonNull` is non-null and stops the elvis (today's behavior: no selection stays no selection); Kotlin null would fall through to the authored value and **re-seed a selection the user cleared**. On the wire both spell `null` (`CompanionEngine.kt:560` `put("value", value ?: JsonNull)`), so only the local seeding path reveals the bug.

**The three always-null casts (same class as Renderer 368/454):**
- **187, 208** `ctx.storeValue(id) as? Boolean ?: node.optBoolean("checked", false)` → `(ctx.storeValue(id) as? JsonPrimitive)?.takeIf{!it.isString}?.content?.toBooleanStrictOrNull() ?: node.boolOr("checked")`
- **366** `(ctx.storeValue(id) ?: node.opt("value")) as? Number ?: return 0` → JsonPrimitive numeric read (`is Number` on `JsonElement?` is a hard compile error — the compiler catches this one)
- **389** `(ctx.storeValue(id) as? Number)?.toFloat() ?: node.optDouble("value", min.toDouble()).toFloat()`

**Type-dispatch:** 247 `if (v is JSONArray)` → `is JsonArray`; 248 `(0 until v.length()).map { v.get(it) }` → `v.toList()`.

**`jsonValueEquals` seam (public, `JsonEquality.kt:32`, now `(JsonElement?, JsonElement?) -> Boolean`):** 249, 268, 272, 299, 368. Every argument must already be a `JsonElement` — compiler-caught. Keep `jsonValueEquals`, never `==`: SPEC 4.3 needs `1 == 1.0` true, and kotlinx `JsonPrimitive.equals` is content-string equality (R5).

**Collections:** 240 `optionValues: List<Any>` → `List<JsonElement>` via `options.mapNotNull { (it as? JsonObject)?.get("value") }`; 243 `seedValues(): List<Any>` → `List<JsonElement>`; **276 `JSONArray(values)`** where `values = selectedValues + selectedAdded.toList()` mixes elements and **Strings** → `JsonArray(selectedValues + selectedAdded.map(::JsonPrimitive))`; 238 `?: JSONArray()` → `?: JsonArray(emptyList())`.

**Discrete slider — 376:** `val exact = values.get(index) // the authored number, exactly` → `values[index]`, then `ctx.state(id, exact)` / `ctx.action(onChange, exact)` pass the **element verbatim** (this is the SPEC 17.4 "EXACT authored number" pin — never `.toDouble()` it, that would respell `3` as `3.0`).
**Continuous slider — 396-397:** `ctx.state(id, pos.toDouble())` → `JsonPrimitive(pos.toDouble())` (a genuine binary64 — keep the double).

**Dimension/numeric reads:** 385 `min` / 386 `max` / 390 `value` — all `optDouble`, FIELD_TYPES `"number"`, fractional legal → `asDoubleOrNull`.

**14 × `optBoolean("enabled", true)`** (73,100,121,135,153,163,184,205,234,360,414,443) + `checked` (187,208) → `boolOr(k, true)` / `boolOr("checked")`. org.json's `optBoolean(k,d)` coerced the strings `"true"`/`"false"`; `boolOr` does not — validator-gated (`SpecValidator.kt:471` requires `boolOrNull != null` for every `"boolean"` member), stricter is correct.
**154 `optString("icon","more_vert")`** → `stringOr("icon","more_vert")`.

**Menu loop — 158-174:** `items.length()`/`optJSONObject(i)`/`optBoolean("enabled", true)`; **169** the disabled-item guard (`if (itemEnabled) item.optJSONObject("on_tap")?.let{…}`) must keep both the guard and the `open = false` before it.

**`options.toString()` at 266** — same `remember(options)` identity-vs-value note as LayoutNodes:635; convert, don't simplify.

**Pure, untouched:** 467-493 `parseHm`, `parseIsoDateUtc`, `isoDateFromUtcMillis` (no JSON).

---

### B.5 `Notifications.kt` — 362 lines, 31 sites (the runbook-missed file)

**Wire seam that TYPE-MISMATCHES today — 67:**
```kotlin
fun scheduleReminders(ctx: Context, owner: String, newSet: JSONArray, priorSet: JSONArray)
```
called from `DeviceBridge.kt:543-545` where post-C4 `engine.reminderListener: ((String, JsonArray, JsonArray) -> Unit)?` (`CompanionEngine.kt:1247`) → both params become `JsonArray`.

**DEVICE-CRITICAL numeric read — 90 (a second `getLong` truncation the runbook does not list):**
```kotlin
am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, r.getLong("at_ms"), pi)
```
Reminder objects reach here **verbatim** from `ReminderStore.reminders(owner): List<JsonObject>`; acceptance checks `at_ms` integrality **by value**, so `"at_ms": 5000.0` is legal accepted traffic (P0 pin) and org.json's `getLong` truncated it. Wire's own reader is deliberately lenient — `ReminderStore.kt:53-56`:
```kotlin
private fun JsonObject.atMs(): Long =
    integralLongOrNull(this["at_ms"]) ?: this["at_ms"]?.asDoubleOrNull()?.toLong()
        ?: throw NoSuchElementException("at_ms")
```
but it is **`private`** and in another module. A `reqLong`-shaped port here throws `NoSuchElementException` **inside the engine's `reminderListener` callback** (called from the accept path) for every integral-double reminder → no alarm is ever armed and the accept path faults. `Notifications.kt` must carry its own integral-tolerant `atMs` reader with the same two-step + truncating fallback and the same reasoning comment.

**Other numeric read — 178:** `chrono.optLong("base_ms", 0L)`. `SpecValidator.kt:258-263` validates `base_ms` with `asDoubleOrNull() + Math.floor` → **`1784700000000.0` is accepted**; `optLong` truncated it. Integral-tolerant read required, else the chronometer silently disappears (guarded by `if (baseMs > 0L)`).

**Throwing array/object reads — 70-90:** `newSet.getJSONObject(it).getString("id")` (71), `priorSet.getJSONObject(i).getString("id")` (73), `newSet.getJSONObject(i)` (81), `r.getString("id")` (82), `r.getString("title")` (86), `r.optString("body","")` (87) → `(newSet[i] as JsonObject).reqString-equivalent` / `stringOr("body")`. These are inside a platform-alarm reconciliation with no error reply — a throw here is a lost alarm, so prefer the same tolerant shape wire uses (`as? JsonObject ?: continue`) only where today's code already tolerated absence; **`getString` threw before, so a throwing port preserves semantics** — decide once and comment.

**Constructions:** 102 `JSONArray(store.reminders(owner))`, `JSONArray()` → `JsonArray(store.reminders(owner))` (works directly: `reminders()` returns `List<JsonObject>`) and `JsonArray(emptyList())`. 147 `?: JSONObject()`, 196 `?: JSONObject()` → `JsonObject(emptyMap())`.

**IPC serialize/parse pair (a persistence-class read):** **201** `putExtra("on_tap", onTap.toString())` and **314** `val onTap = try { JSONObject(onTapStr) } catch (e: Exception) { return }` → `Json.parseToJsonElement(onTapStr) as JsonObject` inside the same `try`. A `PendingIntent` created by the *pre-upgrade* build can still be sitting in the platform with org.json-spelled JSON; the lenient parser is mandatory (never `EbpJson.parse`), and the `catch (Exception)` covers the new exception types. `as JsonObject` can throw `ClassCastException` — inside the try, fine.

**Tree walk:** 156-168 `visit` lambda `(JSONObject) -> Unit`; 165 `body.optString("t") in setOf("row","column","box")`; 166/250-259 `forEachLeaf(children: JSONArray?, …)`; 261-273 `collectText` (**private and only self-recursive — dead code**; convert or delete deliberately, don't leave it half-typed); 266 `kids.opt(i) as? JSONObject`.

**Meta reads:** 148 `optString("priority","default")`, 149 `optString("channel")`, 172/173 `optBoolean("ongoing", false)` (called twice — the value must be read the same way both times), 176 `optString("category")`, 181 `optBoolean("count_down", false)`, 185-189 `optJSONArray("actions")` loop, 195-215 `buildAction` (`optString("label")`, `optJSONObject("on_tap")`, `optJSONObject("input")`, `input.optString("key").ifEmpty{"reply"}`, `optBoolean("dismiss", false)`, `optString("icon")`, `input?.optString("hint")`), 242-246 `postTrigger(notify: JSONObject)` (`optString("text","")`, `optString("title","")`).

**Wire seams:** 318-321 `routeNotificationAction(queue, MAX_EVENT_BYTES, onTap: JsonObject, replyKey, replyText, liveSession, maxFieldBytes){status,error->}` (`ContextlessEvents.kt:158-164`); 348-350 `routeReminderTap(reminders, queue, MAX_EVENT_BYTES, owner, rid, liveSession){…}` (`:130-136`); `store.isFired/markFired/owners/reminders` unchanged shapes.

**Do not touch:** the NUL byte at 54 (§0.1) — it is inside a hash input; changing it changes every reminder's alarm request code, PendingIntent identity and notification id, i.e. orphans every already-armed alarm on an upgraded device.

---

### B.6 `render/VisualizationNodes.kt` — 392 lines, 29 sites

**Dimension reads with `optInt` — 3 sites, all fractional-legal (§3a):**
- **79** `node.optInt("height", 160)` — chart `height`, FIELD_TYPES `"number"`, validator `SpecValidator.kt:872-876` only requires positive-finite → `12.5` legal.
- **191** `node.optInt("width", 100)`, **192** `node.optInt("height", 100)` — canvas dims, validator `:883-887` positive-finite.
**Integer-by-value read — 359** `mark?.optInt("dots", 0)`: validator `:967-969` uses `asDoubleOrNull + Math.floor` → `2.0` accepted.

**Double reads (correct today, port to `asDoubleOrNull`) — 17 sites:** 94 `y`, 105 `y_range[0]/[1]` (**`it.optDouble(0, yMin)` — an ARRAY-index optDouble with a default; kotlinx `arr[i]` throws past the end, so keep the `it.length()==2` guard at 105 and use `getOrNull(i)?.asDoubleOrNull() ?: yMin`**), 211 `stroke_width`, 216 `width`, 218-219 `x,y,width,height`, 224-225 `cx,cy,radius`, 235 path `x,y`, 246 `size`, 250 text `x,y`.

**Constructions:** 136 `JSONObject().put("index", idx)` → `buildJsonObject { put("index", idx) }` (**Int-spelled**); 77/88/193/230 `?: JSONArray()` → `?: JsonArray(emptyList())`; 92 `?: JSONObject()` → `JsonObject(emptyMap())`.

**Value injection — 137:** `ctx.actionInjecting(onPointTap, {index}, s0.points.getOrNull(idx))` — the third arg is the **COMPLETE authored point object** (amendment #114). `JsonObject` *is* a `JsonElement`, so this passes through with no wrapping; do not "flatten" it.
**279/343** `ctx.action(it, next)` / `ctx.action(it, date)` — Strings → `JsonPrimitive(...)`.

**Types:** 72 `class ChartSeriesData(val points: List<JSONObject>, …)` → `List<JsonObject>`; 356 `mark: JSONObject?` → `JsonObject?`.

**`node.toString()` at 113 and 120** (`remember(node.toString())`, `pointerInput(node.toString())`) — the chart re-animates/re-binds on content change. kotlinx `toString()` is the serializer; keep (or note that `remember(node)` now works by value — do not change it in a mechanical pass).

**Untouched:** 262-267 month/selected/min_month/max_month string reads; 282-291 the Calendar math; 387-392 `monthAdd`.

---

### B.7 `render/ContentNodes.kt` — 401 lines, 19 sites

**§3a dimension read — 84 (the highest-value one in this file):**
```kotlin
node.has("width") && node.has("height") -> Modifier.size(node.optInt("width").dp, node.optInt("height").dp)
```
`width`/`height` are UNIVERSAL_NODE_ATTRIBUTES typed `"number"` (`Vocabulary.kt:113,173`) and validated finite-only (`SpecValidator.kt:482`) → `"width": 120.5` is legal and org.json truncated to 120. Note `optInt(k)` with **no default** returned 0 → today a non-numeric width yields a 0.dp image; `dimInt("width", 0)` reproduces that.
**Integer-by-value reads:** 139 `optInt("max_lines", Int.MAX_VALUE)` (validator `validatePositiveInt` = floor check → `3.0` accepted); 359 `optInt("day")`, 361 `optInt("year")`, 363 `optInt("month_index", 0)` (validators `integer-1-31` / `non-negative-integer` / `integer-1-12` all go through `integralLongOrNull`/floor → integral doubles accepted).

**Type dispatch — 126-133 `fontWeightOf(value: Any?)`:**
```kotlin
is Number -> value.toInt().takeIf { it in 1..1000 }?.let { FontWeight(it) }
"bold" -> …  "medium" -> …  "normal" -> …  "light" -> …
```
→ `fontWeightOf(value: JsonElement?)` with an explicit primitive split: numeric branch via `(value as? JsonPrimitive)?.takeIf{!it.isString}?.content?.toDoubleOrNull()?.toInt()`, string branch via `asStringOrNull()`-equivalent then the four names. Both current branches are compile errors after retype (good). Callers: 157 `node.opt("font_weight")` → `node["font_weight"]`, 187 `s.opt("font_weight")` → `s["font_weight"]`. FIELD_TYPES has `font_weight` → `"font-weight"`, which `SpecValidator.kt:495` leaves as `else -> Unit` (**unvalidated**) — so a hostile `"font_weight": "9"` reaches here; the isString guard is what keeps it out of the numeric branch (org.json's `is Number` did the same).

**Other:** 87 `optDouble("aspect_ratio", 1.0)`; 227 `optDouble("size", 0.0)` (dp); 330 `optDouble("value", 0.0)` guarded by `has("value")` (329); 175-180 `buildSpanString(spans: JSONArray?, …, dispatch: (JSONObject) -> Unit)` → `JsonArray?`/`(JsonObject) -> Unit` (**also called from LayoutNodes.kt:587-589**); 182-183 `spans.length()`/`optJSONObject(i)`; 196 `s.optJSONObject("on_tap")`; 252 `optJSONArray("children")`; 292 `optJSONObject("trailing")`; 298 `optJSONObject("on_tap")`; 305 `optString("icon","inbox")`.

---

### B.8 `AppCapabilities.kt` — 90 lines, 15 sites — **runbook item 3b lives here**

Full text of the flagged function (66-77):
```kotlin
    // minSdk 34: VibratorManager is always present.
    private fun vibrate(context: Context, args: JSONObject) {
        val vibrator = (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                as VibratorManager).defaultVibrator
        if (args.has("ms")) {
            vibrator.vibrate(VibrationEffect.createOneShot(
                args.getLong("ms"), VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            val arr = args.getJSONArray("pattern")
            val pattern = LongArray(arr.length()) { arr.getLong(it) }
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        }
    }
```
and its exception funnel (51-63): the whole `when(cap)` is wrapped in `try { … } catch (SecurityException) → 1002 … catch (Exception) → 1003 "platform-error"`.

**Why a naive port breaks the device, precisely:** `CompanionEngine.kt:1483-1487` validates with `CapabilityCatalog.validateArgs(cap, args)` and then `:1493` calls `handler.invoke(cap, args)` with the **original, un-normalized** `args`. `CapabilityCatalog.validateVibrate` → `intArg(args,"ms",1,60_000)` → `integer()` → **`integralLongOrNull`** (`CapabilityCatalog.kt:128-139`, whose comment says in as many words: *"The value is normalized at accept time, so an older peer's `{"ms": 100.0}` is the same 100 ms it was under org.json (whose getLong truncated a Double) — pinned by PreSwapNumberTest"*). The normalization is **local to the validator**; nothing rewrites `args`. So the handler still sees `100.0`. `getLong` truncated → 100 ms buzz today. A `reqLong`/`wireIntOrNull` port returns null/throws → caught by the `catch (e: Exception)` at line 60 → the peer gets **1003 "platform-error"** instead of a vibration: a silent capability regression with a plausible-looking error.
**Fix:** a by-value integral read, e.g. `integralOf(args["ms"]) ?: return` — `p.content.toLongOrNull() ?: p.content.toDoubleOrNull()?.takeIf{it==floor(it)}?.toLong()`.
**The twin the C3 flag omits — line 74 `arr.getLong(it)`:** every `pattern` element goes through `CapabilityCatalog.kt:103 integer(p[i], …)` = the same lenient `integralLongOrNull`, so `"pattern": [100.0, 200.0]` is accepted-and-working today. **Both** reads need the integral-tolerant path; converting only `"ms"` leaves half the capability broken.

**deviceReport() — 37-45, a 7-member `.put` chain with 5 `JSONArray(List<String>)`:**
```kotlin
JSONObject().put("caps", JSONArray(CAPS)).put("trigger_caps", JSONArray(listOf("vibrate")))
  .put("permissions", JSONObject()).put("trigger_types", JSONArray(TRIGGER_TYPES))
  .put("state_types", …).put("trackable_state_types", …).put("trigger_unavailable", JSONObject())
```
→ `buildJsonObject { put("caps", JsonArray(CAPS.map(::JsonPrimitive))); … put("permissions", JsonObject(emptyMap())); … }`. Consumers: `CompanionEngine.kt:1479` `config.deviceReport.arrOrNull("caps")` + `caps.none { it.asStringOrNull() == cap }` (a non-string entry never matches — keep them strings), `jsonStringSet(deviceReport, "trigger_caps"/"trigger_types"/"state_types"/"trackable_state_types")` (`TriggerFiringService.kt:26`, public), and `CompanionEngine.kt:2401` `require(wireSerialize(config.deviceReport).utf8Len() <= deviceBudget)` — the byte budget is measured on this object, so **do not add members**.

**Results:** 54 `CapabilityOutcome.Ok(JSONObject())` → `Ok(JsonObject(emptyMap()))`; 88 `Ok(JSONObject().put("text", text))` → `Ok(buildJsonObject { put("text", text) })`. `CapabilityOutcome.Ok(result: JsonObject)` (`CapabilityCatalog.kt:16`), `CapabilityHandler.invoke(cap: String, args: JsonObject)` (`:29-31`). 51 `CapabilityHandler { cap, args -> … }` — `args` infers to `JsonObject`; 66 the explicit `args: JSONObject` annotation must change.
**Untouched:** 79-89 `readClipboard` byte-budget refusal ("clipboard-too-large") — the `toByteArray(UTF_8).size` measure stays.

---

### B.9 `render/EditorToolbar.kt` — 199 lines, 13 sites

Signature: 53 `items: JSONArray` → `JsonArray`; 56 `dispatch: (JSONObject) -> Unit` → `(JsonObject) -> Unit`; 63 `var pendingInput by remember { mutableStateOf<JSONObject?>(null) }` → `JsonObject?`; 73 `runOp: (JSONObject) -> Unit`; 119 `ToolbarItem(item: JSONObject, runOp: (JSONObject) -> Unit)`.

**Ordering-dependent dispatch — 78-92:** the `when { tap != null -> … ; line.isNotEmpty() -> … ; op.has("snippet") -> … ; op.has("command") -> … }` chain is a **priority order** (SPEC 17.7: exactly one operation per item). Convert `has` → `in`, keep branch order and the `isNotEmpty()`/`has` asymmetry (`line` uses emptiness, `snippet`/`command` use presence — a `snippet: ""` must still park/apply, a `command: ""` must not dispatch: 91 `takeIf { it.isNotEmpty() }`).

Reads: 76 `optJSONObject("on_tap")`, 77/88/106/112 `optString("line"/"snippet"/"placement")`, 101 `items.length()`/`optJSONObject(i)`, 120-123 `optString("icon"/"label")`, `optJSONArray("menu")`, `optJSONObject("long_press")`, 130-133 `menu.length()`/`optJSONObject(i)`/`sub.optString("label").ifEmpty{sub.optString("icon")}`.
**Wire seam:** `ToolbarEdit(text, selStart, selEnd)` / `ToolbarEdits.applySnippet/lineOp/needsInput/inputPrompt` are pure String/Int APIs (`ToolbarEdits.kt:12,82,91,98,170`) — **unchanged by the swap**.

---

### B.10 `render/Attributes.kt` — 160 lines, 10 sites (the universal-attribute reader)

**The NaN-default idiom — 6 sites, easy to get wrong:** 129 `optDouble("width")`, 130 `optDouble("height")`, 131/132 `min_width`/`max_width`, 135/136 `min_height`/`max_height`, 140 `fill_fraction`, 142 `aspect_ratio`, 158 `alpha`. org.json's **1-arg `optDouble` defaults to `NaN`**, and `safeDp`/`safeFraction`/`safeAspect`/`safeAlpha` (39-49) reject non-finite → *the modifier is SKIPPED, never applied at 0*. The correct port is `node["width"]?.asDoubleOrNull()?.let { safeDp(it) }` — **not** `?: 0.0`, which would apply `0.dp` width and collapse the node. Each site is already gated by `node.has(k)` (129-142), so the only reachable NaN case is a non-numeric member on a nonconforming sender — precisely what the file header's "skip, never throw" philosophy exists for.

**Type dispatch — 91-103 `cornerShape`:**
```kotlin
val c = node.opt("corner") ?: return RectangleShape
when (c) { is Number -> safeDp(c.toDouble())…; is JSONObject -> { fun side(k) = safeDp(c.optDouble(k, 0.0))?.dp ?: 0.dp; … }; else -> RectangleShape }
```
→ `node["corner"]`, then `is JsonPrimitive`+`!isString`+`content.toDoubleOrNull()` for the scalar arm and `is JsonObject` for the per-corner arm; `else -> RectangleShape` keeps a string/bool corner harmless. FIELD_TYPES has **no `corner` entry** → `SpecValidator` does not type it → the `else` arm is load-bearing.
**Per-side padding — 113-127:** `pad.has(specific) → pad.optDouble(specific,0.0)` / `pad.has(axis) → …` / else `node.optDouble("padding",0.0)`; the three-level fallback ("per-side wins over its axis shorthand") must survive intact. 125-126 the `else if (node.has("padding"))` arm.
**Border — 152-157:** `optJSONObject("border")`, `b.optDouble("width", 1.0)` (**default 1.0, not 0**), `b.optString("color")`.
**148** `node.optBoolean("clip")`; **149** `node.optString("bg")`.
**Pure helpers pinned by NodeSupportPinTest:116-125:** `safeDp/safeFraction/safeAspect/safeAlpha` take `Double` — **keep the `Double` parameter type** (the test calls `safeDp(-1.0)`, `safeDp(Double.NaN)`, `safeFraction(1.5)`…). Do not "improve" them to take `JsonElement?`.
**58-73 `lazyChildKeys(children: JSONArray)`** → `JsonArray`, `children.length()`→`.size`, `optJSONObject(i)`, `optString("key"/"id")`. **Pinned by NodeSupportPinTest:142-152** (exact expected list `["k:a","id:field","i:2","k:a#1"]`).
**77-85 `identityPath(parentPath, node: JSONObject?, i)`** → `JsonObject?`; **pinned by NodeSupportPinTest:154-162**.

---

### B.11 `render/NodeSupport.kt` — 88 lines, 8 sites (the advertised profiles)

76-87 is the whole conversion:
```kotlin
private fun profile(nodes, builtins, features) = JSONObject()
    .put("node_types", JSONArray(nodes.toList())) .put("builtins", …) .put("features", …)
fun surfaceProfiles(): JSONObject = JSONObject().put("app", profile(…)).put("dialog", …).put("notification", profile(NOTIFICATION_NODE_TYPES, sortedSetOf(), …))
```
→ `buildJsonObject { put("node_types", JsonArray(nodes.map(::JsonPrimitive))); … }` and `buildJsonObject { put("app", profile(…)); … }`. Consumers are strict: `nodeTypesFromProfiles(config.surfaceProfiles, "app"/"dialog"/"notification")` and `builtinsFromProfiles` (`CompanionEngine.kt:54-57, 912, 2068-2072, 2348-2349`), plus `put("surface_profiles", config.surfaceProfiles)` verbatim into the welcome (`:2276, :2385`). **`sortedSetOf()` ordering is observable** in the advertised welcome — keep `.toList()` on the sorted sets so the emitted arrays stay sorted (JsonArray preserves list order; the sets are `sortedSetOf`, so no change if the `.toList()` survives).
All the `Set<String>` declarations (18-74) are pure Kotlin — untouched. `APP_NODE_TYPES` etc. are read by `NodeSupportPinTest` and `CompanionStores.kt:80-82`.

---

### B.12 `render/ThemeModel.kt` — 142 lines, 7 sites

**45-47 the role reader:**
```kotlin
private fun JSONObject.role(key: String): Color? =
    optString(key).takeIf { it.isNotEmpty() }?.let { parseHexColor(it)?.let(::Color) }
```
→ `JsonObject.role` with `stringOr(key)` (or `stringOrNull`) — keep the empty-string gate: a `null` or non-string role must yield `null`, not `Color(0)`.
**59 `buildColorScheme(colors: JSONObject?, base)`**, **104 `buildExtendedColors(colors: JSONObject?, dark)`**, **124 `EbpTheme(payload: JSONObject?, …)`** → `JsonObject?`. `buildColorScheme`/`buildExtendedColors` are **public and pinned by ThemeModelTest** (5 tests).
**111/113 `c.has("success")` / `c.has("warning")`** → `"success" in c` — the presence test is what decides "derive a legible on-color" vs "keep the default"; a `?:`-style rewrite loses it.
**Type dispatch — 125-128 (compile error after retype, good):**
```kotlin
val dark = when (val d = payload?.opt("dark")) { is Boolean -> d; else -> isSystemInDarkTheme() }
```
→ read the boolean by primitive: `payload?.get("dark")?.let { (it as? JsonPrimitive)?.takeIf{!it.isString}?.content?.toBooleanStrictOrNull() } ?: isSystemInDarkTheme()`. Semantics to preserve exactly (amendment #36): **absent OR `null` OR non-boolean → follow the system**; only a real JSON boolean forces polarity. `boolOr(k, isSystemInDarkTheme())` is the compact equivalent — but note it must be evaluated inside a `@Composable` scope, so keep the `when`/`?:` shape rather than eagerly computing the default.
**129/135** `payload?.optJSONObject("colors")` / `("syntax")` → `objOrNull` (post-C4 `engine.currentTheme()` writes `put("colors", JsonNull)` for a clear — `objOrNull` correctly yields `null` for JsonNull, matching `optJSONObject`).

---

### B.13 `render/PieMenu.kt` — 57 lines, 6 sites (highest throw-risk per line)

```kotlin
30  fun RenderPieMenu(menuId: String, spec: JSONObject, bridge: DeviceBridge)
31  val categories = spec.optJSONArray("categories") ?: return
35  spec.optString("center_label").takeIf { it.isNotEmpty() }
39-40 val ring = if (active == null) categories else categories.getJSONObject(active).optJSONArray("items")
41  val n = ring?.length() ?: 0
43  val entry = ring!!.getJSONObject(k)
47  if (active == null && entry.has("items")) expanded = k
53  Text(entry.optString("label"))
```
`getJSONObject(i)` threw `JSONException` on a non-object; kotlinx `ring[k] as JsonObject` throws `ClassCastException`, and `ring[k]` itself throws `IndexOutOfBoundsException` past the end. **Nothing catches** — a throw inside this composable blanks the dialog. `expanded` is a remembered index into a list that a re-push can shrink (**`active` is validated only by `getJSONObject(active)` throwing**): the safest faithful port is `(categories.getOrNull(active) as? JsonObject)?.arrOrNull("items")` and `(ring.getOrNull(k) as? JsonObject) ?: return@Box`-style guards — a deliberate improvement, so record it as a deviation rather than sneaking it in. Seams: `bridge.pieMenuDismiss(menuId)`, `bridge.pieMenuSelect(menuId, k, null)` / `(menuId, active, k)` → engine `selectPieMenu(menuId, categoryIndex: Int, itemIndex: Int? = null)` — **plain Kotlin Ints, no JsonPrimitive** (`CompanionEngine.kt:1185`).

---

### B.14 `render/SyntaxHighlight.kt` — 409 lines, 4 sites

**84-92, the only JSON in the file:**
```kotlin
private fun JSONObject.syntaxFg(role: String): Color? {
    val v = opt(role) ?: return null
    val hex = when (v) { is JSONObject -> v.optString("fg").takeIf{it.isNotEmpty()}
                         is String -> v.takeIf{it.isNotEmpty()}; else -> null } ?: return null
    return parseHexColor(hex)?.let(::Color) }
```
→ `JsonObject.syntaxFg`: `is JsonObject -> v.stringOr("fg")…`, and the `is String` arm (**compile error after retype**) becomes `(v as? JsonPrimitive)?.takeIf{it.isString}?.content`. The lenient bare-string form is **pinned by SyntaxHighlightTest:60** (`.put("string","#00ff00")` → `merged.string == Color(0xFF00FF00)`), and `else -> null` must keep swallowing numbers/booleans/JsonNull.
**98 `emacsSyntaxColors(syntax: JSONObject?, fallback)`** → `JsonObject?` (public; called from `ThemeModel.kt:134` and 4 tests). 100-115 unchanged logic; **102** the single-`heading`-recolours-the-rainbow rule and **111/115** the "registered roles only" set (`meta`/`paren` deliberately ignored) are pinned by 3 tests.
The tokenizers (118-409) are pure String work — zero JSON.

---

### B.15 `EbpApplication.kt` — 97 lines, 9 sites

Four `MutableStateFlow` types + their public `StateFlow` getters: 29-30 `Pair<String, JSONObject>?` (currentSpec), 31-32 (currentDialog), 35-36 `JSONObject?` (theme), 37-38 (currentPieMenu) → `JsonObject`. Then the four `DeviceBridge` callback lambdas (70-94) infer. No reads, no builds, no numerics. **Ordering-dependent (RF-0.5a):** 53-64 `firing.recover()` → `triggerSources().start()` → `armAllBaselines()` → `rearmAllReminders` → `TriggerAlarms.reschedule` → *then* `bridge.start()` (95). Preserve exactly.

---

### B.16 `MainActivity.kt` — 162 lines, 5 sites

`import org.json.JSONObject` (30) + four flow parameter types: 80 `SurfaceHost(flow: StateFlow<Pair<String, JSONObject>?>, …)`, 119 `PieMenuHost`, 128 `DialogHost`. Pure re-typing.
**Comment at 61-66** ("because every render composable takes an (unstable) JSONObject, a dialog opening re-executed the entire surface render") — prose that names org.json. The *reasoning survives verbatim*: kotlinx `JsonObject` is also unstable to the Compose compiler (a plain class implementing `Map`, no `@Immutable`), so the per-overlay hosts are still required. Update the noun, keep the structure; do **not** collapse the three hosts.

---

### B.17 `TriggerSources.kt` — 48 lines, 5 sites

21 `onSample: (String, JSONObject) -> Unit`, 23 `ConcurrentHashMap<String, JSONObject>`, 26 `currentState(type): JSONObject?`, 33 `JSONObject().put("level", level * 100 / scale)` → `buildJsonObject { put("level", level * 100 / scale) }` — **integer division, integer-spelled**; `TriggerRuntime` compares this against authored `level` thresholds via SPEC 4.3 numeric equality, so keeping it an Int literal is required (a `.toDouble()` would respell `50` as `50.0`). Consumers: `TriggerFiringService.stateProvider: (String) -> JsonObject?` (`:46`) and `observeSample(type, sample: JsonObject)` (`:86`), wired at `CompanionStores.kt:116, 142`.

### B.18 `TriggerAlarms.kt` — 93 lines, 3 sites

84 `firing.observeExternal("boot", JSONObject())` → `JsonObject(emptyMap())`; 86-88 `observeExternal("timezone.changed", JSONObject().put("tz", ZoneId.systemDefault().id))` → `buildJsonObject { put("tz", …) }`. `observeExternal(type: String, data: JsonObject)` (`TriggerFiringService.kt:90`). Everything else (`timeSchedule()`, `fireScheduled`, AlarmManager) is JSON-free.

---

### T.1 `test/render/DialogCaptureTest.kt` — 4 @Test, 7 sites — **the app's silent-assert trap**

| line | today | after |
|---|---|---|
| 15 | `private fun defaults(build: JSONObject.() -> Unit) = JSONObject().apply(build)` | **KEEP as a local helper**, re-shaped: `private fun defaults(build: JsonObjectBuilder.() -> Unit) = buildJsonObject(build)`. App tests **cannot see wire's `TestSupport.kt`** (different module, `internal`, and a different package `com.calebc42.ebp.wire`), so nothing here moves out; the file duplicates only `buildJsonObject`-shaped construction, which is stdlib. |
| 23-27, 39-43, 51, 64 | `put("agree", true)`, `put("count", 3)`, `put("choice", JSONObject.NULL)` | `put("agree", true)`, **`put("count", 3)` Int-spelled**, `put("choice", JsonNull)` |
| 28-30, 44-46, 52-53 | `assertEquals(true, captureValue(...))`, `assertEquals(3, ...)`, `assertEquals("Untitled", ...)` | **every expected value must become `JsonPrimitive(...)`** — this is the app's version of the L-suffix rule: `captureValue` returns `JsonElement?`, so `assertEquals(3, actual)` resolves to `assertEquals(Object,Object)`, **compiles, and silently fails**. Six such sites: 28, 29, 30, 44, 45, 46, 52, 53. |
| 44-46 | `mapOf("agree" to false)`, `mapOf("name" to "")`, `mapOf("count" to 0)` | the fields map is now `Map<String, JsonElement?>` → `mapOf("agree" to JsonPrimitive(false))`, `JsonPrimitive("")`, `JsonPrimitive(0)`. The **"deliberately cleared" semantics is the test's subject** — `""`, `false`, `0` must stay those exact values. |
| 55-56 | `val arr = JSONArray().put("a").put("b")`; `assertTrue(captureValue("tags", mapOf("tags" to arr), d) is JSONArray)` | `JsonArray(listOf("a","b").map(::JsonPrimitive))`; `… is JsonArray` |
| 65-67 | `assertNull(captureValue("choice", emptyMap(), d))` etc. | unchanged — and **these three are the R6 sentinel's acceptance test**: `put("choice", JsonNull)` present-but-null must still resolve to Kotlin `null`. If Renderer.kt:97 drops `takeIf { it !is JsonNull }`, line 65 fails. Keep them. |

### T.2 `test/render/NodeSupportPinTest.kt` — 9 @Test, 4 sites

**No `import org.json` line** — the three org.json uses are **fully qualified** at 143 (`org.json.JSONArray("""[…]""")`), 156, 159, 161 (`org.json.JSONObject("""{…}""")`). A converter that works by deleting imports and following compile errors will still find them (they're type errors), but a grep-driven pass keyed on imports misses this file.
- 143-150 → `Json.parseToJsonElement("""[…]""") as JsonArray`; the raw fixture text and the expected `listOf("k:a","id:field","i:2","k:a#1")` are byte-verbatim.
- 156-161 → `Json.parseToJsonElement("""{"t":"text","key":"k","id":"i"}""") as JsonObject`, ×3, expectations `"/k:k"`, `"/id:i"`, `"/3:text"` unchanged.
- 22-35 `rendererSource()` (the `user.dir` upward walk for `Renderer.kt`) and 37-67 `dispatchTypes()` (the source scanner) are **pure String/File work — do not touch**, and see B.1: the scanner constrains how `Renderer.kt`'s `when (type)` may be formatted.
- 116-125 `pureHelpersClampNotThrow` pins `safeDp(Double)` etc. — see B.10.
- 76-82 uses `NODE_SCHEMA.keys` and 84-89 `CORE_NODE_SET` from `:wire` (public `Vocabulary.kt:13,26`) — unchanged by the swap.

### T.3 `test/render/SyntaxHighlightTest.kt` — 8 @Test, 11 sites
All 11 are payload construction: 58-60, 74, 84-86, 101-103 `JSONObject().put(role, JSONObject().put("fg", "#…").put("italic", true))` → `buildJsonObject { putJsonObject("keyword") { put("fg","#ff0000"); put("italic", true) } ; put("string","#00ff00") }`. Every hex string is byte-verbatim (they are compared against exact `Color(0xFF…)` values). `put("string","#00ff00")` at 60 is the **bare-string leniency** pin (B.14). 9 `import org.json.JSONObject` → kotlinx. No numerics, no NULL, no ordering issues. Expected values are `Color`/`SyntaxColors`, not JSON → **no JsonPrimitive-wrapping trap here**.

### T.4 `test/render/ThemeModelTest.kt` — 5 @Test, 4 sites
22-25, 45, 66 `JSONObject().put("primary","#ff0000")…` → `buildJsonObject { put("primary","#ff0000"); put("surface","#101010"); put("surface_variant","#303030") }`. 56 `buildColorScheme(null, base)` (the null-map arm) unchanged. All expectations are `Color`/`ColorScheme` — no wrapping trap. 36 `scheme.surfaceContainer.red < scheme.surfaceVariant.red` and 47/70/71 the legible-on-color values are the subjects; do not touch.

---

## 3. THE TWO RUNBOOK-FLAGGED ITEMS

### 3a. Dimension-member reads → `render/NodeAccess.kt` (runbook §2.5 C6)

**CONFIRMED: `:app` CANNOT see wire's `asDoubleOrNull`.** `JsonAccess.kt` declares **20 `internal`** members including `asDoubleOrNull` (`:103`), `integralLongOrNull` (`:83`), `wireIntOrNull`, `reqLong`, `stringOr`, `objOrNull`, `with`… Kotlin `internal` = same **compilation module**; `:wire`'s `jvmMain` and `:app` are separate Gradle modules with no `associate`/friend-path relation (only `:wire`'s own `jvmTest` gets friend access). Therefore **`render/NodeAccess.kt` must be entirely self-contained** — re-derive the readers from `JsonObject`/`JsonPrimitive` primitives, and copy the isString/JsonNull guard discipline verbatim (a `.content` read without the guard stringifies JsonNull to `"null"` and coerces `"42"`).
Public wire helpers `:app` *may* use: `jsonValueEquals(JsonElement?, JsonElement?)` (`JsonEquality.kt:32`), `jsonStringSet(JsonObject, String)` (`TriggerFiringService.kt:26`), `Envelope`'s `request/notification/resultResponse/errorResponse/isValidRequestId`, `encodeFrame(String)`, `SurfaceStore.authoredValueOf(JsonObject)`.

**Evidence that dimension members are legally fractional** (so a `wireIntOrNull`-shaped port silently defaults them):
`Vocabulary.kt:81-175 FIELD_TYPES` — `"dp"`: `content_padding, elevation, padding, run_spacing, size, spacing, thickness`; `"number"`: `width, height, min, max`. `SpecValidator.kt:482`:
```kotlin
"dp", "number" -> node[member]?.asDoubleOrNull().let {
    if (it == null || it.isInfinite() || it.isNaN()) bad("a finite number") }
```
— finiteness only, **no integrality gate**.
And the *integer*-typed members are validated integral **by value**, not by spelling: `:484-494` (`non-negative-integer`/`positive-integer`/`integer-1-12`/`integer-1-31` all via `integralLongOrNull`), `:751-757 validatePositiveInt` and `:758-763 validateIntRange` (`asDoubleOrNull` + `Math.floor`), `:795-800` (tabs `initial`), `:967-969` (`marks.dots`), `:872-876`/`:883-887` (chart/canvas dims). **So `2.0` is accepted for `initial`, `max_lines`, `day`, `year`, `month_index`, `dots` too** — every one of these needs the *by-value* read, not just the dp/number ones.

**Complete enumeration of the at-risk integer reads (14 sites, 5 files):**

| file:line | member | class | today | required |
|---|---|---|---|---|
| `render/ContentNodes.kt:84` | image `width`, `height` | **DIMENSION** (`number`, universal attr) | `optInt(k)` → truncate, default 0 | `dimInt(k, 0)` |
| `render/VisualizationNodes.kt:79` | chart `height` | **DIMENSION** (`number`) | `optInt("height",160)` | `dimInt("height",160)` |
| `render/VisualizationNodes.kt:191` | canvas `width` | **DIMENSION** | `optInt("width",100)` | `dimInt("width",100)` |
| `render/VisualizationNodes.kt:192` | canvas `height` | **DIMENSION** | `optInt("height",100)` | `dimInt("height",100)` |
| `render/LayoutNodes.kt:396` | tabs `initial` | AUTHORED-SPEC-MEMBER (integral-by-value) | `optInt("initial",0)` | integral-tolerant |
| `render/ContentNodes.kt:139` | `max_lines` | AUTHORED-SPEC-MEMBER | `optInt("max_lines", Int.MAX_VALUE)` | integral-tolerant |
| `render/ContentNodes.kt:359` | `day` | AUTHORED-SPEC-MEMBER | `optInt("day")` | integral-tolerant |
| `render/ContentNodes.kt:361` | `year` | AUTHORED-SPEC-MEMBER | `optInt("year")` | integral-tolerant |
| `render/ContentNodes.kt:363` | `month_index` | AUTHORED-SPEC-MEMBER | `optInt("month_index",0)` | integral-tolerant |
| `render/VisualizationNodes.kt:359` | `marks.<date>.dots` | AUTHORED-SPEC-MEMBER | `optInt("dots",0)` | integral-tolerant |
| `Notifications.kt:178` | `meta.chronometer.base_ms` | AUTHORED-SPEC-MEMBER (floor-validated `:258-263`) | `optLong("base_ms",0L)` | integral-tolerant |
| **`Notifications.kt:90`** | reminder `at_ms` | **PASS-THROUGH-VERBATIM** (P0-pinned integral double) | `getLong("at_ms")` | integral-tolerant **+ truncating fallback** (mirror `ReminderStore.kt:53-56`) |
| **`AppCapabilities.kt:71`** | capability arg `ms` | **PASS-THROUGH-VERBATIM** | `getLong("ms")` | integral-tolerant (§3b) |
| **`AppCapabilities.kt:74`** | `pattern[i]` | **PASS-THROUGH-VERBATIM** | `arr.getLong(it)` | integral-tolerant (§3b) |

**Already-safe (already double-based; port to `asDoubleOrNull` + keep the NaN-skip):** 43 `optDouble` sites listed per-file in §2 — `LayoutNodes` 104,115,175,220,248,250; `InputNodes` 385,386,390; `Attributes` 119,126,129,130,131,132,135,136,140,142,153,158; `Renderer` 288,289,327; `VisualizationNodes` 94,105(×2),211,216,218(×2),219(×2),224(×2),225,235(×2),246,250(×2); `ContentNodes` 87,227,330.

**Suggested `render/NodeAccess.kt` (self-contained, `internal` to `:app`):**
```kotlin
internal fun JsonElement.numOrNull(): Double? =
    (this as? JsonPrimitive)?.takeIf { !it.isString && it !is JsonNull }?.content?.toDoubleOrNull()
/** Dimension members are legally fractional (SpecValidator gates dp/number as finite
 *  numbers); org.json's optInt TRUNCATED. */
internal fun JsonObject.dimInt(k: String, d: Int): Int = this[k]?.numOrNull()?.toInt() ?: d
/** Integer-typed members validated integral BY VALUE: "2.0" is accepted upstream. */
internal fun JsonObject.intByValue(k: String, d: Int): Int =
    this[k]?.numOrNull()?.takeIf { it == floor(it) }?.toInt() ?: d
```
Note `dimInt` must **truncate, not round** (`toInt()`), to reproduce org.json exactly; and it must return the default for a *non-numeric* member (matching `optInt`'s fold), not throw.

### 3b. `AppCapabilities.kt:71` — quoted in full in **B.8** above, with the un-flagged twin at `:74` and the exact reason (`CompanionEngine.kt:1483-1493` hands the handler **un-normalized** args; `CapabilityCatalog.kt:128-139` normalizes only for validation) and the failure mode (`catch (e: Exception)` at `AppCapabilities.kt:60` converts the throw into a plausible `1003 "platform-error"`).

---

## 4. `Renderer.kt:97` SENTINEL AND SIBLINGS (runbook R6)

**The site, verbatim (`Renderer.kt:95-103`):**
```kotlin
fun captureValue(id: String, fields: Map<String, Any?>, defaults: JSONObject?): Any? = when {
    fields.containsKey(id) -> fields[id]
    defaults?.has(id) == true -> defaults.get(id).takeIf { it != JSONObject.NULL }
    // Neither layer has it. §14.1 makes an unresolvable capture a
    // document-level error the Companion already refused at validation, so
    // reaching here means the spec and this map disagree — surface null
    // rather than inventing a value of the wrong type.
    else -> null
}
```
→ `id in defaults -> defaults[id]?.takeIf { it !is JsonNull }` (R6's `it !is JsonNull`). Both halves are load-bearing: `in` (not `?:`) keeps the two-layer `found`-bit semantics documented at 76-89, and the `!is JsonNull` filter is what turns the engine's explicit `put(nodeId, authoredValueOf(node) ?: JsonNull)` (`CompanionEngine.kt:2120`) into "no authored value". Acceptance: `DialogCaptureTest.kt:64-65`.

**Sibling sentinel sites (2, both *build*-null, opposite direction):** `Renderer.kt:169` and `:193` — `fields.put(fieldId, d.capture(fieldId) ?: JSONObject.NULL)` → `put(fieldId, d.capture(fieldId) ?: JsonNull)`. Never omit the member: an absent `fields.<id>` is a different §14.6 capture than a null one.
**Third sibling, different file:** `InputNodes.kt:277` `values.firstOrNull() ?: JSONObject.NULL` → **`?: JsonNull`** (not Kotlin null) — full reasoning in B.4.

**`authoredValueOf`:** `:app` never calls it. It is `SurfaceStore.authoredValueOf(node: JsonObject): JsonElement?` (`SurfaceStore.kt:509-521`, public companion member) and already migrated per R6 (`"text_input","editor" -> node["value"] ?: JsonPrimitive("")`, `"checkbox","switch" -> node["checked"] ?: JsonPrimitive(false)`, enum_list/slider fallbacks). `:app` consumes its output **only indirectly**, through two seams whose JsonNull-vs-absent behavior therefore matters:
1. `bridge.dialogDefaults(dialogId): JsonObject?` → `Renderer.kt:97`;
2. `InputDisplay.value: JsonElement?` (`SurfaceStore.kt:26`) → `RenderCtx.storeValue` → the four seeding sites (`Renderer.kt:368,454`; `InputNodes.kt:187,208,246,366,389`).

---

## 5. WIRE-API SEAMS — every `:wire` symbol `:app` touches, with its post-C4 signature

Read from `companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/`.

**`CompanionEngine.kt` — constructor & config**
- `CompanionConfig(serverName, serverVersion, pairings: Map<String,ByteArray>, supportedCapabilities: Set<String>, surfaceProfiles: JsonObject, limits: JsonObject, deviceReport: JsonObject = JsonObject(emptyMap()), capabilityHandler: CapabilityHandler? = null, sensitiveSubstitutionApproved: Boolean = false, nonceSource: () -> String)` — `:19-42`. **3 params change type** for `DeviceBridge.kt:111-153`.
- `CompanionEngine(config, surfaces: SurfaceStore, queue: DurableQueue, reminders: ReminderStore, triggers: TriggerStore, firing: TriggerFiringService, sink: (ByteArray) -> Unit)` — `:44-77`; positional call at `DeviceBridge.kt:472` unchanged. Limits are read with **`reqLong`** at `:47-48,61-62,74` → integer-spelled limits mandatory.

**Methods `:app` calls**
| call site | signature (post-C4) |
|---|---|
| `DeviceBridge.kt:263` | `dispatchAction(surface: String, descriptor: JsonObject, hookValue: JsonElement?, injected: JsonObject? = null, extraFields: JsonObject? = null, sourceId: String? = null, callback: ((String?, JsonObject?) -> Unit)? = null)` — `:405-412`. App passes 5 positional + trailing lambda; **`sourceId` sits after `extraFields`** — alignment matters. |
| `:258-260` | `dispatchDialogAction(dialogId, descriptor: JsonObject, hookValue: JsonElement?, fields: JsonObject?, callback: ((String?, JsonObject?) -> Unit)? = null)` — `:319-321` |
| `:307` | `publishState(surface, id, value: JsonElement?)` — `:541`; internally `put("value", value ?: JsonNull)` at `:560` |
| `:364` | `requestCompletion(document, editorId, callback: (String, JsonArray, String, Long, Int) -> Unit)` — `:1838-1839` |
| `:392` | `selectCompletion(document, editorId, atSession: String, atSeq: Long, atCursor: Int, prefix: String, insert: String): Boolean` — `:1888-1889` |
| `:394,415` | `withEditor(document, editorId) { EditorSession -> }` |
| `:414` | `localEditorEdit(document, editorId, start: ScalarPos, del: Int, text: String, base: String? = null): Boolean` — `:1548-1550` |
| `:425` | `editorCommand(surface, document, editorId, command, cursor: Utf16Pos, selStart: Utf16Pos, selEnd: Utf16Pos): Boolean` — `:1637-1639` |
| `:432` | `completeDialogSubmit(dialogId, value: JsonElement? = null, fields: JsonObject? = null)` — `:2138-2139` |
| `:442` | `completeDialogDismiss(dialogId)` — `:2174` |
| `:438` | `dialogDefaults(dialogId): JsonObject?` — `:879` |
| `:447` | `selectPieMenu(menuId, categoryIndex: Int, itemIndex: Int? = null)` — `:1185` (**plain Ints**) |
| `:454,570` | `feed(bytes: ByteArray)` — `:112`; `close(reason: String)` — `:157` |
| `:493` | `pairingIdentity: String?` — `:98` |
| `:559` | `currentTheme(): JsonObject` — `:2003` |
| `:567` | `state: SessionState` — `:78` |

**Listeners `:app` assigns** (all in `CompanionEngine.kt`)
`surfaceListener: ((String) -> Unit)?` `:87` · `hostBuiltinListener: ((String, JsonObject) -> Unit)?` `:294` · `pieMenuListener: ((String, JsonObject?) -> Unit)?` `:1085` · **`reminderListener: ((String, JsonArray, JsonArray) -> Unit)?` `:1247`** (→ `Notifications.scheduleReminders`, §B.5) · `editorListener: ((EditorSession) -> Unit)?` `:1508` · `themeListener: ((dark: Boolean?, colors: JsonObject?, syntax: JsonObject?) -> Unit)?` `:1980` · `toastListener: ((String, Long?) -> Unit)?` `:2009` · `dialogListener: ((String, JsonObject?) -> Unit)?` `:2035` · `dialogOverflowListener: ((String) -> Unit)?` `:2039`.
(`:app` does **not** use `annotationListener` `:1510`, `markReminderFired` `:1341`, `dispatchReminderTap` `:1348` — the last two are reached via `ContextlessEvents.routeReminderTap`.)

**Stores / other**
- `SurfaceStore`: `spec(surface): JsonObject?` `:164` · `currentView(surface): String?` `:172` · `inputDisplays(): Map<Pair<String,String>, InputDisplay>` `:434` · `draft(surface,id): JsonElement?` `:390` · `putDraft(surface,id,value: JsonElement?)` `:379` · `inputState(): JsonObject` `:362` · `update(surface, revision: Long, spec: JsonObject, …)` `:206` · ctor `(maxSurfaces: Long, maxSurfaceIds: Long, maxCaptureFields, maxChartPoints, maxCanvasOps, maxRichSpans, maxTableCells, appNodeTypes, notificationNodeTypes, …, backing)` `:28+` (called with named args from `CompanionStores.kt:73-84`, unchanged) · `authoredValueOf(node: JsonObject): JsonElement?` `:509` (companion).
- **`data class InputDisplay(val epoch: Long, val value: JsonElement?)`** — `SurfaceStore.kt:26`. `RenderCtx.epochOf`/`storeValue` read it.
- `ReminderStore`: `owners(): List<String>` `:70`, **`reminders(owner): List<JsonObject>`** `:72`, `markFired`/`isFired` `:118,130`.
- `DurableQueue`, `FileQueueStore`, `FileSurfaceBacking`, `FileReminderBacking`, `FileTriggerBacking`, `TriggerStore` — constructor shapes unchanged (`CompanionStores.kt`).
- `TriggerFiringService`: `stateProvider: (String) -> JsonObject?` `:46` · `notifyListener: ((JsonObject) -> Unit)?` `:48` · `onTimeScheduleChanged: (() -> Unit)?` `:52` · `observeSample(type, sample: JsonObject)` `:86` · `observeExternal(type, data: JsonObject)` `:90` · `armAllBaselines()` `:136` · `recover()` `:251` · `timeSchedule()` / `fireScheduled(identity, tid)`.
- `LiveSession { deliverLiveDrop(params: JsonObject, cb); onDurableAdmitted(policy) }` — `ContextlessEvents.kt:44-47`; `CompanionEngine : LiveSession`.
- `routeReminderTap(reminders, queue, maxEventBytes: Long, owner, reminderId, live: LiveSession?, callback)` `:130-136`; `routeNotificationAction(queue, maxEventBytes, onTap: JsonObject, replyKey: String?, replyText: String?, live: LiveSession?, maxFieldBytes, callback)` `:158-164`.
- `CapabilityHandler { fun invoke(cap: String, args: JsonObject): CapabilityOutcome }` `CapabilityCatalog.kt:29-31`; `CapabilityOutcome.Ok(result: JsonObject)` `:16`, `Fail(code: Int, reason: String)` `:19`.
- `EbpAuth.decodePairingToken(display): ByteArray` `Auth.kt:31` (unchanged) · `encodeFrame(jsonText: String): ByteArray` `FrameCodec.kt:199` · `Envelope`: `notification(method, params: JsonObject): JsonObject` `:105`, `request(id, method, params)` `:82/:95`, `resultResponse/errorResponse/isValidRequestId` `:112/:125/:26` — all **public**.
- `jsonValueEquals(a: JsonElement?, b: JsonElement?): Boolean` `JsonEquality.kt:32` · `jsonStringSet(o: JsonObject, key: String): Set<String>` `TriggerFiringService.kt:26` · `CORE_NODE_SET`, `NODE_SCHEMA` `Vocabulary.kt:13,26` · `ToolbarEdit`/`ToolbarEdits` (pure) · `EditorSession` (`shadow/cursor/selStart/selEnd/seq/document/editorId`, `diff`), `ScalarPos`/`Utf16Pos` value classes, `utf16PosIn(text, ScalarPos): Utf16Pos` `EditorSession.kt:19,23,39` · `SessionState` · `ContentInvalid(path, reason)` (not caught in `:app`).

---

## 6. BUILD / TOOLING

### 6.1 `companion/app/build.gradle.kts` (full dependencies block, lines 25-36)
```kotlin
dependencies {
    implementation(projects.wire) // org.json comes from the framework      // :26
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material.icons)
    // JVM unit tests (the NodeSupport pin test): the framework isn't present,
    // so tests supply the reference org.json jar exactly as :wire does.
    testImplementation(libs.junit)                                          // :34
    testImplementation(libs.json)                                           // :35
}
```
**`:app` main declares NO org.json dependency at all** — not `compileOnly`, not `implementation`. Main-source org.json resolves from the **Android framework** (`android.jar` bundles `org.json`), which the comment on `:26` records. So the C6-exit deletion in this file is exactly **one line: `:35 testImplementation(libs.json)`**. kotlinx-serialization arrives transitively: `:wire`'s `jvmMain.dependencies { api(libs.kotlinx.serialization.json) }` (`wire/build.gradle.kts:18`) — `api`, so `:app` needs no explicit dependency (nothing to add at C6). Also note the compose-BOM has no bearing.
Rest of the file: `plugins { alias(libs.plugins.android.application); alias(libs.plugins.kotlin.compose) }`; `android { namespace "com.calebc42.ebp.companion"; compileSdk 36; minSdk 34; targetSdk 36; buildFeatures { compose = true }; compileOptions Java 21 }` — untouched by C6.

### 6.2 Everything else to delete at C6 exit
- `companion/wire/build.gradle.kts:24` `compileOnly(libs.json)` (jvmMain) and `:27` `implementation(libs.json)` (jvmTest) — the jvmMain comment already says "(Deleted by RF-2b.)".
- `companion/gradle/libs.versions.toml`: `[versions] json = "20240303"` (line 6) and `[libraries] json = { group = "org.json", name = "json", version.ref = "json" }`. `kotlinx-serialization = "1.8.0"` + `kotlinx-serialization-json` stay.
- Order: the deletions must come **after** `grep -ra "org.json" companion/{wire,app}/src` is empty — with **`-a`** (§0.1).

### 6.3 SDK / `local.properties`
- **`ANDROID_HOME=/home/calebc42/android-sdk`** IS set in this environment (`ANDROID_SDK_ROOT` is empty). The SDK has `platforms/{android-34,35,36,36.1}`, `build-tools/{34,35,36}.0.0`, `platform-tools`, `licenses` — compileSdk 36 + AGP 9.1.1 satisfied.
- **This worktree has NO `local.properties`**: neither `.../worktrees/rf2b-c5/local.properties` nor `.../worktrees/rf2b-c5/companion/local.properties` exists. (`companion/app/build` also does not exist — `:app` has never been built here.)
- **The other checkout's copy, ready to copy:** `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2/companion/local.properties`, contents exactly:
  ```
  sdk.dir=/home/calebc42/android-sdk
  ```
  Gradle's root for this build is `companion/` (`settings.gradle.kts` there), so the file belongs at `<worktree>/companion/local.properties`, **not** the repo root.
- **Trap:** `/home/calebc42/pkb/projects/jetpacs/jetpacs/local.properties` also exists and contains a **Windows path** — `sdk.dir=C\:\\Users\\caleb\\AppData\\Local\\Android\\Sdk` (and no trailing newline). It is a leftover from the Windows-side checkout and is outside the Gradle root, so it is inert — but do not copy *that* one.
- Gradle user home `~/.gradle` exists (warm caches). `settings.gradle.kts` uses `enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")` (hence `projects.wire`), `include(":wire")`, `include(":app")`, repos `google()`/`mavenCentral()`.
- C6 gate, from `<worktree>/companion`: `./gradlew :app:testDebugUnitTest :app:assembleDebug`. It is currently **RED before any edit** (C4 changed 30+ `:wire` signatures), which is the expected starting ledger; the first useful worklist is `./gradlew :app:compileDebugKotlin --console=plain 2>&1 | grep "^e: " | cut -d: -f1 | sort | uniq -c | sort -rn`.

---

## 7. WHAT A MECHANICAL CONVERTER GETS WRONG (ranked)

1. **`grep` silently skips `Notifications.kt`** (NUL byte, §0.1). Both the worklist and the exit gate must use `grep -a`. 31 sites, 3 wire seams, and one device-critical `at_ms` read hide behind this.
2. **`as? String` / `as? Boolean` / `as? Number` on a re-typed `JsonElement?` compiles (warning at most) and is ALWAYS null.** Seven sites: `Renderer.kt:368,454`; `InputNodes.kt:187,208,389` (+`366` and `246` in the same expressions). Result: every stateful widget silently reverts to the authored value while the store holds the user's draft — the LD-2 divergence, undetectable by any epoch, and no `:app` test covers seeding. Grep for `as\? (String|Boolean|Number)` after conversion and require zero hits.
3. **`assertEquals(<literal>, <JsonElement>)`** in `DialogCaptureTest` — 8 sites (28,29,30,44,45,46,52,53). Resolves to `assertEquals(Object,Object)`, compiles, **fails silently or passes vacuously**. The app's analogue of the t4 L-suffix rule: *every* expected value asserted against `captureValue` gets `JsonPrimitive(...)`.
4. **`JSONObject.NULL` → Kotlin `null` instead of `JsonNull`** at `InputNodes.kt:277` and `Renderer.kt:169,193`. On the wire the two are identical (`publishState` does `value ?: JsonNull`), so the bug is invisible in emitted bytes and shows up only as a re-seeded selection (draft `JsonNull` vs absent at `InputNodes.kt:246`) or as an *absent* `fields.<id>` member in a §14.6 capture.
5. **`optDouble(k)` (one-arg) defaults to NaN, and NaN means "skip the modifier".** `Attributes.kt:129-142,158` (9 sites). Porting to `?: 0.0` applies `0.dp` width/height/alpha and collapses or hides nodes.
6. **Truncating vs by-value integer reads** — the 14 sites in §3a; `AppCapabilities.kt:71` **and `:74`**; `Notifications.kt:90` and `:178`. Two of these (`ms`, `at_ms`) are P0-pinned working device traffic; both failure modes are *silent* (a 1003 "platform-error" reply; an alarm that never arms).
7. **`NodeSupportPinTest` source-scans `Renderer.kt`.** Reformatting the `when (type) {` line, re-indenting a case label, or adding a same-indent `"foo" ->` in a nested `when` fails `dispatchMatchesAdvertisedAppNodeTypes` — a test failure that looks nothing like a JSON conversion bug.
8. **Fully-qualified `org.json.*` with no import** — `NodeSupportPinTest.kt:143,156,159,161`. The exit grep catches it only with `-a` + a pattern that isn't `^import`.
9. **kotlinx `JsonObject`/`JsonArray` have structural `equals`; org.json had none.** This *changes `remember(key)` semantics* at `LayoutNodes.kt:243,636`, `InputNodes.kt:255-259,266`, `VisualizationNodes.kt:113,120`, `Renderer.kt:374,479`. The direction is benign (fewer resets), and the deliberate two-step identity/value dance at `LayoutNodes.kt:629-637` and `InputNodes.kt:265-267` becomes redundant — **convert body-for-body and flag; do not simplify in the same pass.** Compose *stability* does not change (JsonObject is as unstable as JSONObject was), so `MainActivity`'s per-overlay hosts stay necessary.
10. **Array indexing changed its failure mode.** `.opt(i)`/`.optJSONObject(i)` returned null past the end; `arr[i]` **throws** `IndexOutOfBoundsException`, and `as JsonObject` throws `ClassCastException`. Sites where the index is not provably in range: `PieMenu.kt:40,43` (a remembered `expanded` index into a possibly-shrunk re-push, **nothing catches** → blank dialog), `VisualizationNodes.kt:105` (`it.optDouble(0/1, …)` guarded by `length()==2` — keep the guard), `Notifications.kt:71-90`. Prefer `getOrNull(i) as? JsonObject`, and record it as a deviation.
11. **`try { JSONObject(text) }` sites are *persistence/IPC* reads → `Json.parseToJsonElement`, never `EbpJson.parse`.** `DeviceBridge.kt:161` (`ebp-theme.json`, written by a pre-upgrade build) and `Notifications.kt:314` (an `on_tap` string inside a live `PendingIntent` created by a pre-upgrade build). Both are already wrapped in `catch (e: Exception)`, which covers `SerializationException`/`IllegalArgumentException`/`ClassCastException` — **there are zero `JSONException` catches in `:app`**, so no catch-clause rewrites are needed anywhere.
12. **`optString(k, d)` folds explicit null into the default; `optBoolean(k, d)` also coerced the strings `"true"`/`"false"`.** Nine `optString(k,d)` and 23 `optBoolean(k,d)` sites (enumerated in §2). `stringOr`/`boolOr`-shaped helpers keep the fold, drop the coercion — correct, because `SpecValidator.kt:471,483` gate those members; note it once in `NodeAccess.kt` rather than re-deriving 32 times.
13. **Chained `.put` builders that must stay integer-spelled.** `DeviceBridge.kt:124-149` (26 limits members — the engine reads them with `reqLong`, a `.0` throws at construction), `AppCapabilities.kt:37-45` (`deviceReport`, byte-budgeted at `CompanionEngine.kt:2401`), `TriggerSources.kt:33` (`level` — compared by SPEC 4.3 equality), `LayoutNodes.kt:505,509,712-715` (`index`/`from`/`to`), `VisualizationNodes.kt:136` (`index`).
14. **`.with()`-style copy-and-forget** does not appear in `:app` today (no `remove`/in-place-mutate-a-helper-result patterns) — the only mutation-building is fresh-object `.put` chains and the two `fields` accumulation loops (`Renderer.kt:163-171,189-195`). Nothing here needs `with`; if a converter reaches for it, that is a sign it mis-modelled the site.
15. **Vararg/collection array constructors**: `JSONArray(List<String>)` at `AppCapabilities.kt:38,39,42,43,44` and `NodeSupport.kt:78-80` → `JsonArray(list.map(::JsonPrimitive))`; `JSONArray(List<JsonObject>)` at `Notifications.kt:102` → `JsonArray(list)` directly; `JSONArray(List<Any>)` at `InputNodes.kt:276` → **mixed** (elements + Strings), needs a per-element map.
16. `AppCapabilities.kt:60`'s blanket `catch (e: Exception) → Fail(1003,"platform-error")` will happily swallow every new-reader exception in that file. Any strict read added under it becomes a silent capability failure — read leniently *and* consider whether the catch should narrow.
17. **Dead code:** `Notifications.collectText` (`:261-273`) is private with only a recursive self-call. Convert or delete deliberately; leaving it half-typed is a compile error, deleting it silently is an undocumented behavior-neutral change.
18. **Prose that names org.json stays prose**, but two comments now describe kotlinx facts and should be re-worded rather than deleted: `MainActivity.kt:61-66` ("(unstable) JSONObject" — still true of `JsonObject`) and `LayoutNodes.kt:629-637` ("JSONArray has no equals" — no longer true; the code above it is still correct).