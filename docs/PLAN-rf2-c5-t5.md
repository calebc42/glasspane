# PLAN — RF-2b C5.t5: the 6 editor/queue/golden suites to kotlinx (Opus fleet execution doc)

Split from the C5 execution appendix per the ratified §8 amendment of
[PLAN-rf2-c5-tests.md](PLAN-rf2-c5-tests.md): t4/t5 conversion agents run on Opus;
Fable keeps orchestration, compile stragglers, and everything from t6 onward.
Each conversion agent reads section A plus its own section-B sheet, plus the two
style exemplars (ThemeTest.kt, TriggerTest.kt), then converts its ONE file in place.
Ledger baseline entering t4: 343 compileTestKotlinJvm errors.

## A. COMMON DIRECTIVES FOR EVERY CONVERSION AGENT

You are converting exactly ONE test file from org.json to kotlinx.serialization, in place. Follow these rules with zero discretion. Where this block and your per-file sheet (section B) conflict, the per-file sheet wins.

### A.1 Scope — hard prohibitions
- Edit ONLY your assigned file. Do NOT touch `jvmMain`, `TestSupport.kt`, any other test file, `build.gradle.kts`, or `ebp/`.
- Do NOT run gradle or any build command. The main loop compiles.
- Do NOT delete, rename, merge, or add any `@Test` method. Your sheet states the exact `@Test` count; the converted file must have exactly that count, same names (the one rename in this migration, §3.7, is in batch t6, not yours).
- Do NOT change any expected value, assertion message, comment, or fixture string unless your sheet gives an explicit before → after for that line. Comments mentioning org.json stay as prose.
- Read-only references you may open: `TestSupport.kt`, `jvmMain/.../JsonAccess.kt`, `jvmMain/.../CompanionEngine.kt`, `jvmMain/.../Envelope.kt`, and the style exemplars `ThemeTest.kt` and `TriggerTest.kt` (converted this session — copy their idioms).

### A.2 Imports
- Delete every `import org.json.*` line (`JSONObject`, `JSONArray`, `JSONException`).
- Keep every non-org.json import that is still used (`java.io.File`, `org.junit.Rule`, `org.junit.rules.TemporaryFolder`, etc.).
- Add kotlinx imports as SINGLE-NAME imports, alphabetized, in group order `java.*` → `kotlinx.*` → `org.junit.*` (see `SurfaceStoreTest.kt` header). Never wildcard. The full menu: `kotlinx.serialization.json.Json`, `JsonArray`, `JsonElement`, `JsonNull`, `JsonObject`, `JsonObjectBuilder`, `JsonPrimitive`, `add`, `addJsonObject`, `buildJsonArray`, `buildJsonObject`, `put`, `putJsonArray`, `putJsonObject`. Import only what you use.
- JsonAccess helpers (`reqString/reqLong/reqObj/reqArr/stringOr/stringOrNull/longOr/wireIntOrNull/integralLongOrNull/objOrNull/arrOrNull/boolOr/boolOrNull/asStringOrNull/asDoubleOrNull/with/without/isNullOrAbsent/requestIdKey`), `jsonValueEquals`, and everything in `TestSupport.kt` are same-package `internal` — no import needed.

### A.3 Fixed translation table (the ONLY vocabulary; never re-derive coercion)

| org.json | kotlinx replacement |
|---|---|
| `JSONObject()` empty | `JsonObject(emptyMap())` |
| `JSONArray()` empty | `JsonArray(emptyList())` |
| `JSONObject().put(...)` chain (fresh object) | `buildJsonObject { put(...) }` |
| `.put(k, v)` on an EXISTING object (helper result) | `.with(k, JsonPrimitive(v))` — see A.6 |
| `JSONArray(listOf("a","b"))` (strings) | `JsonArray(listOf("a","b").map(::JsonPrimitive))` |
| `JSONArray(listOf(0,100))` (numbers) | `JsonArray(listOf(0,100).map { JsonPrimitive(it) })` — `::JsonPrimitive` is ambiguity-prone on numbers; always the lambda form |
| `JSONArray().put(x).put(y)` | `buildJsonArray { add(x); add(y) }` (objects via `addJsonObject { ... }`) |
| `.getString(k)` | `.reqString(k)` |
| `.optString(k)` | `.stringOr(k)` (default `""`, same as org.json) |
| `.getInt(k)` / `.getLong(k)` | `.reqLong(k)` |
| `.optInt(k)` (default 0) | `.longOr(k)` — result is used with `L`-suffixed literals (A.4) |
| `.getBoolean(k)` | `.boolOrNull(k)` (keeps absence detectable); `.optBoolean` → `.boolOr(k)` |
| `.getJSONObject(k)` | `.reqObj(k)` |
| `.optJSONObject(k)` | `.objOrNull(k)` |
| `.getJSONArray(k)` | `.reqArr(k)` |
| `.optJSONArray(k)` | `.arrOrNull(k)` |
| `.has(k)` | `k in obj` (negated: `k !in obj`) |
| `.keySet()` | `.keys` |
| `.length()` | `.size` (Int — bare Int literals fine in these comparisons) |
| `arr.getString(i)` | `arr[i].asStringOrNull()!!` |
| `(0 until a.length()).map { a.getString(it) }` | `a.map { it.asStringOrNull()!! }` |
| `arr.getInt(i)` | `integralLongOrNull(arr[i])` — expected literal gets `L` |
| `JSONObject.NULL` | `JsonNull` (see A.10) |
| `it.opt("method") == "x"` | `it.stringOrNull("method") == "x"` |
| `it.opt("id") == "x"` | `it["id"] == JsonPrimitive("x")` (typed equality) |
| `it.opt("id") == 7` | `it["id"] == JsonPrimitive(7)` |
| `JSONObject(text)` (document fixture: contract.json, manifest, goldens) | `Json.parseToJsonElement(text) as JsonObject` |
| `JSONArray(text)` | `Json.parseToJsonElement(text) as JsonArray` |
| `msg.toString()` | `msg.toString()` — UNCHANGED. kotlinx `toString()` IS production `wireSerialize` (`CompanionEngine.kt:2479`) |
| `MutableList<JSONObject>` / `Pair<String, JSONObject?>` etc. | same shape with `JsonObject` |

### A.4 THE L-SUFFIX RULE (the #1 silent-failure trap)
`reqLong`/`longOr`/`wireIntOrNull`/`integralLongOrNull` return `Long`/`Long?`. When the actual side is nullable (`Long?`), `assertEquals(1200, x)` resolves to `assertEquals(Object, Object)` and compares `Integer(1200)` to `Long(1200)` — **it compiles and silently fails**. Rule, applied uniformly with zero thought: **every expected numeric literal asserted against ANY JsonAccess numeric read gets an explicit `L` suffix** (`assertEquals(-32601L, out.errorOf("s1").reqLong("code"))` — exactly as `TriggerTest.kt:125`). The only bare-Int comparisons allowed are against `.size` and against plain Kotlin `Int`/counter properties (`out.size`, `refused`, `presented.size`, `engine.triggers.count(...)`).

### A.5 reqLong vs the nullable readers
For a member the test REQUIRES to exist: `reqLong(k)` (throws on absent/mis-spelled — absence fails loudly). Use `longOr`/`integralLongOrNull` only where the original used `opt*` inside a predicate (absent must mean "no match", not an exception) — your sheet marks each such site. Never use `integralLongOrNull` where the sheet says `reqLong`.

### A.6 `.with()` results MUST be used
`obj.with(k, v)` returns a NEW JsonObject (`JsonAccess.kt:138`); it does not mutate. A dropped result compiles and does nothing — the compiler cannot catch it. Every `.with(...)` you write must be (a) assigned, (b) passed as an argument, or (c) chained into a further call, on the same expression. Every `existing.put(k,v)` in the original is either a `.with(...)` per your sheet or was already an expression whose value was consumed — preserve consumption.

### A.7 Engine-emitted vs pass-through numbers (from fact-sheet 0.5)
The engine copies `args`/`fields`/annotation params **JsonElement-verbatim** from what the fixture authored (`CompanionEngine.kt:425-436, 439-452, 1941`). Therefore:
- **ENGINE-EMITTED** (integer-spelled by construction; read with `reqLong` + `L` literal): error `code`; `remaining`/`delivered`/`rejected`/`expired`; `queued_events`; `revision`/`revision_seen`; `occurred_at_ms`; `queued_at_ms`; `queue_seq`; editor `seq`; `cursor`/`sel_start`/`sel_end`/`start`/`len`; `category_index`/`item_index`; reminder `count`; outbound request `id`.
- **PASS-THROUGH-VERBATIM** (spelling is the fixture's): everything under `args`/`fields` that the fixture authored, capability-handler result members, annotation `seq`. **Every pass-through fixture value must be written as an Int/Long literal** (`put("k", 1)`, never `1.0`) or the strict readers throw. A `.0` or fractional literal is permitted ONLY where the sheet marks binary64 spelling as the test's subject (CapabilityTest 251/262/263/281, ReminderTest 102).

### A.8 Throwing selectors vs assertNull sites (from fact-sheet 0.6)
`TestSupport.replyTo(id)`/`errorOf(id)` THROW when nothing matches (`last {}`), which is wanted — vacuity fails loudly. But any site whose assertion is `assertNull(...)`/`assertNotNull(lastOrNull ...)` MUST keep a `lastOrNull`-based form with typed equality: `out.lastOrNull { it["id"] == JsonPrimitive(id) }`. Your sheet marks each such site; there are exactly three in these batches (DialogTest `responseFor` helper, DialogTest:178, CompanionEngineTest:563). Also: `assertNotNull(x.getLong(k))` was vacuous (boxed primitive); `assertNotNull(x.reqLong(k))` is a real existence check via throw — keep the wrapper, convert the read.

### A.9 Raw-text fixtures are byte-verbatim
Any string literal fed to `encodeFrame(...)`, `EbpJson.parse(...)`, or read from disk (`.bin`, `.golden`, `contract.json`, `manifest.json`) is untouchable — do not reformat, re-quote, re-indent, or re-spell one byte. Document-file reads convert parser only: `Json.parseToJsonElement(file.readText()) as JsonObject`.

### A.10 `JSONObject.NULL` — two meanings
- **Assert-emitted-null**: `assertEquals(JSONObject.NULL, x.get("k"))` → `assertEquals(JsonNull, x["k"])`. In predicates: `it.get("id") == JSONObject.NULL` → `it["id"] == JsonNull`.
- **Build-null-into-fixture**: `put(k, JSONObject.NULL)` → `put(k, JsonNull)` — NEVER omit the member; omission now means absent, which is a different assertion.

### A.11 Banned accessors
kotlinx's coercing accessors are banned exactly like production: `.int`, `.long`, `.float`, `.double`, `.boolean`, `.jsonPrimitive`, `.content`, `.contentOrNull`, `.jsonObject`, `.jsonArray`. Read only through JsonAccess helpers, `as JsonObject` / `as JsonArray` casts, and element equality. (`Json.parseToJsonElement(...) as JsonObject` is the house cast idiom — see A.3.)

### A.12 TestSupport — what exists, and delete-vs-keep
`TestSupport.kt` provides (same package, `internal`): `katToken`/`katPid`/`katCn`/`katSn`; `testLimits(vararg overrides: Pair<String, Number>): JsonObject` (the 9-member core — max_frame_bytes 4_194_304, max_queued_events 256, max_queued_bytes 8_388_608, max_event_bytes 262_144, max_surfaces 16, max_surface_ids 1024, max_field_bytes 65_536, max_input_state_bytes 262_144, max_capture_fields 64 — overrides append or replace); `frame(msg: JsonObject): ByteArray`; `List<JsonObject>.replyTo(id: String)`, `replyTo(id: Long)`, `errorOf(id: String)` (all THROW on no match); `List<JsonObject>.events()` (filters `method == "event.action"`).
Rule: DELETE a local helper only where your sheet says DELETE, replacing every call site with the exact TestSupport call the sheet gives (including exact `testLimits(...)` override args). KEEP everything the sheet says KEEP — especially every `engine()`/`readyEngine()` factory: they differ meaningfully per suite (grants, reports, stores, sink shapes) and must stay local, converted body-for-body. Do not "improve", inline, or generalize a kept helper.

### A.13 Seam signatures (post-C4 jvmMain; your calls must match — all in `CompanionEngine.kt` unless noted)
`sendRequest(method, params: JsonObject, bounded = true, callback: (JsonObject?, JsonObject?) -> Unit)`; `dispatchDialogAction(dialogId, descriptor: JsonObject, hookValue: JsonElement?, fields: JsonObject?, callback: ((String?, JsonObject?) -> Unit)? = null)`; `dispatchAction(surface, descriptor: JsonObject, hookValue: JsonElement?, injected: JsonObject? = null, extraFields: JsonObject? = null, sourceId: String? = null, callback: ((String?, JsonObject?) -> Unit)? = null)`; `publishState(surface, id, value: JsonElement?)` — scalars wrap in `JsonPrimitive(...)`; `dialogDefaults(dialogId): JsonObject?`; `selectPieMenu(menuId, categoryIndex: Int, itemIndex: Int? = null)` — plain Ints; `markReminderFired(owner, reminderId): Boolean`; `dispatchReminderTap(owner, reminderId, callback)`; `openEditor(document, editorId, seed, cursor: ScalarPos = ScalarPos(0))`; `localEditorEdit(document, editorId, start: ScalarPos, del: Int, text, base: String? = null)`; `localEditorCaret(document, editorId, cursor: Utf16Pos, selStart: Utf16Pos? = null, selEnd: Utf16Pos? = null)`; `editorCommand(surface, document, editorId, command, cursor: Utf16Pos, selStart: Utf16Pos, selEnd: Utf16Pos): Boolean`; `requestCompletion(document, editorId, callback: (String, JsonArray, String, Long, Int) -> Unit)`; `selectCompletion(document, editorId, atSession, atSeq: Long, atCursor: Int, prefix, insert)`; `completeDialogSubmit(dialogId, value: JsonElement? = null, fields: JsonObject? = null)`.
Listeners: `surfaceListener: ((String) -> Unit)?`; `hostBuiltinListener: ((String, JsonObject) -> Unit)?`; `pieMenuListener: ((String, JsonObject?) -> Unit)?`; `reminderListener: ((String, JsonArray, JsonArray) -> Unit)?`; `annotationListener: ((String, String, JsonObject) -> Unit)?`; `themeListener: ((Boolean?, JsonObject?, JsonObject?) -> Unit)?`; `dialogListener: ((String, JsonObject?) -> Unit)?`; `dialogOverflowListener: ((String) -> Unit)?`.
Other: `SurfaceStore.update(surface, revision: Long, spec: JsonObject, staleSpec: JsonObject?, currentView: String?, resetIds: JsonArray?)`; `surfaces.draft(s,id): JsonElement?`; `surfaces.inputState(): JsonObject`; `surfaces.snapshot(): JsonObject`; `Envelope.kt`: `request(id: String|JsonElement, method, params: JsonObject)`, `notification(method, params: JsonObject)`, `resultResponse(id: JsonElement, result: JsonObject)` (NO String overload), `errorResponse(id: JsonElement, code: Int, message, kind, data = JsonObject(emptyMap()))`, `isValidRequestId(id: JsonElement?)`; `CapabilityHandler.invoke(cap: String, args: JsonObject)`; `CapabilityOutcome.Ok(result: JsonObject)`; `SpecValidator.validateSurfaceSpec(spec: JsonElement?, path, ...)`; `ContentInvalid(val path, val reason)`.

### A.14 Echo ids: copy the ELEMENT, never re-derive
Every place a test answers an engine-issued request by reading its id: `put("id", event["id"]!!)` — the JsonElement verbatim. NEVER `event.reqLong("id")` re-wrapped. Your sheet lists every echo site.

### A.15 Report format (end of your reply)
State: (1) file converted, (2) `@Test` count before/after (must be equal to the sheet's number), (3) each sheet risk-site line handled, checked off, (4) any uncertainty as `UNCERTAIN: <line> <one sentence>` — do not resolve uncertainties by inventing behavior; flag them.

---


## B. PER-FILE INSTRUCTION SHEETS (batch t5)

### B.10 EditorTest.kt — batch t5 — **26 @Test**, 609 lines

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 18-21 | KAT | DELETE |
| 23-29 | `limits()` | DELETE → `testLimits("max_editor_sessions" to 8, "max_editor_bytes" to 65_536)` |
| 31 | `frame` | DELETE |
| 33-51 | `engine(out, grant: Boolean = true)` | KEEP-and-convert; sink CONSUMER overload `d.feed(bytes) { out.add(it) }` |
| 53 | `List<JSONObject>.method(m)` member extension | KEEP-and-convert: `private fun List<JsonObject>.method(m: String) = filter { it.stringOrNull("method") == m }` (generalized selector — TestSupport only has `events()`) |
| 54 | `response(out, id)` | DELETE → `out.replyTo(id)` (no assertNull sites; string ids only) |
| 119-128 | `applyText(engine, id, session, seq: Long, start: Int, del: Int, text: String, len: Int, document = "doc:1", editorId = "body")` | KEEP-and-convert to buildJsonObject; **the `cursor = start + text.codePointCount(0, text.length)` computation is the LD-4 pin — keep it** |
| 228-231 | nested `annot(method, session, seq: Long)` | KEEP-and-convert; params carry `diagnostics: JsonArray(emptyList())`, `runs: JsonArray(emptyList())`, `text: "d"` in ONE object, reused across three methods — keep byte-shape; `put("seq", seq)` stays a Long put |
| 280-287, 310-316 | nested `diagnostics/diag/runs/run` | KEEP-and-convert (hand-built envelopes `{jsonrpc, method, params}` may stay hand-built via buildJsonObject) |

**Numeric reads — engine-emitted, `reqLong` + `L`**: 104/105 open `seq`/`cursor`; 110/111/113 delta `seq`/`start`/`len`; 138/144/174/399 result `seq`; 210 resync `seq`; 264/337/364/393/487/542/577 error `code`; 524-526 caret `cursor`/`sel_start`/`sel_end`.
**225 — the ONE pass-through**: `engine.annotationListener = { kind, _, p -> seen.add(kind to p.reqLong("seq")) }` with `seen: MutableList<Pair<String, Long>>`; the fixture's `put("seq", seq)` (Long) must stay integer-spelled or the listener throws.
Non-JSON property reads (`s.seq`, `s.cursor`, `s.selStart/selEnd`, `s.scalarLength()`) — leave alone; 339/356/428/454/471/545 already `L`-suffixed, keep.

**Risk sites**
- **593-598 the `bare` limits object — the omission IS the test**: it hand-writes 9 core + `max_editor_sessions` 8 and deliberately OMITS `max_editor_bytes`. Replace with `testLimits("max_editor_sessions" to 8)` (TestSupport adds no editor member — reproduces exactly). Do NOT use the file's converted default limits.
- 599-606 inline `CompanionEngine(CompanionConfig(..., surfaceProfiles = JsonObject(emptyMap()), limits = bare, ...)) { }` inside `runCatching{}.isFailure` — convert as shown.
- **449** `put("start", 4_294_967_296L)` — the 2^32 truncation pin, stays Long-spelled. **468** `put("start", Int.MAX_VALUE)` with `put("del", 1)` — stays.
- 536-548 byte-accounting (`"a".repeat(65_500)` + 100 > 65 536) — port verbatim; `jcsUtf8Bytes` is encoder-independent (`EditorSession.kt:141-170`), plain ASCII, no change.
- 185 `"deadbeef".repeat(4)` fake session — asserts `editor-stale`, NOT a validation error; preserve.
- 294 `assertEquals(4, out.method("log.error").size)` — exact count (Int). 190/429/559/579/586 `out.method(...)` emptiness/size checks unchanged in shape.
- 211 `assertTrue(r.reqString("session") != old)`.
- Emoji/large literals (67, 87, 238, 497, 518, 536/555, 540/558, 575, 584) byte-verbatim.

**Seam calls (plain Kotlin, no JSON wrapping)**: `EditorSession("d","e","sess")`, `s.shadow = ...`, `s.splice(ScalarPos(n), del, text, len)`, `EditorSession.diff(old,new)` destructuring, all `openEditor(..., cursor = ScalarPos(3))` sites, `localEditorEdit(...)` incl. 425-426 `base = viewText` / 431-432 `base = s.shadow`, 189 `closeEditor`, 249 `close`, 521-522 `localEditorCaret("doc:1","body", Utf16Pos(2), Utf16Pos(6), Utf16Pos(2))`, 252 `EditorSession.State.CLOSED`.

**End state**: 0 errors; 26 `@Test`; `bare` reproduced by override-omission; codePointCount arithmetic intact.

---

### B.11 EditorLifecycleTest.kt — batch t5 — **12 @Test**, 325 lines

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 17-20 | KAT | DELETE |
| 22-28 | `limits(maxEditors: Long = 8)` | DELETE, parameterized → `testLimits("max_editor_sessions" to maxEditors, "max_editor_bytes" to 65_536)`; factory keeps `maxEditors: Long = 8` (used with 8 and 1) |
| 30 | `frame` | DELETE |
| 32-54 | `engine(out, maxEditors: Long = 8, toReady: Boolean = true)` | KEEP-and-convert; TWO profiles (`app` + `dialog`, both `["text","column","editor"]`); sink CONSUMER overload; `session.ready` only if `toReady` — preserve the conditional |
| 56-59 | `editorNode(id, document, value: String = "")` | KEEP-and-convert — flatten `.also{}`: `buildJsonObject { put("t","editor"); put("id", id); put("document", document); put("publish_state", false); if (value.isNotEmpty()) put("value", value) }` |
| 61-67 | `push(engine, out, surface, revision: Long, spec): JsonObject` | KEEP-and-convert; request id `"s$revision-${surface.hashCode()}"` computation unchanged (negative hashCodes still match the id grammar); tail → `out.replyTo(rid)` |
| 69 | `List<JSONObject>.method(m)` | KEEP-and-convert (same as B.10) |
| 189-206 | nested `connect(): CompanionEngine` | KEEP-and-convert; shared `SurfaceStore(16,1024)` at 187 stays shared; hello+auth but NO session.ready — preserve |

**The one numeric read is an ECHO (146-147)**: the test answers the Companion's own `edit.complete` request. `engine.feed(frame(buildJsonObject { put("jsonrpc","2.0"); put("id", req["id"]!!); put("result", <converted result object>) }))` — **`req["id"]!!` element copy, never `getInt`** (production correlates via `requestIdKey`).

**Risk sites**
- **141-143**: `var got: Pair<String, JsonArray>? = null`; `engine.requestCompletion("doc:1","body") { prefix, cands, _, _, _ -> got = prefix to cands }` — callback type `(String, JsonArray, String, Long, Int) -> Unit`.
- 149-150 candidates: `buildJsonArray { addJsonObject { put("label","print"); put("insert","print()") } }`.
- 153-154 `selectCompletion("doc:1","body", s.sessionId, s.seq, s.cursor, "pri", "print()")`; 158-159 `selectCompletion("doc:1","body", s.sessionId, 99, 0, "x","y")` — plain scalars, `99` types to Long.
- **295-296**: `editorNode("body","doc:1","seed").with("publish_state", JsonPrimitive(true))` — REPLACES the `false` (`with` keeps key position, `JsonAccess.kt:139`). **316**: `.with("key", JsonPrimitive("k1"))`. **319**: `.with("key", JsonPrimitive("k2"))`. All results consumed as arguments.
- 173-176 editor-shaped object inside `on_tap.args` — keep member order `t`,`id`,`document` exactly (byte-shape matters).
- 300-301 the LOCAL editor (no `document`): `buildJsonObject { put("t","editor"); put("id","note"); put("publish_state", true) }`.
- 297/302 `publishState(..., JsonPrimitive("typed offline"/"kept"))`; 298/303 `hasDraft` unchanged; 211 `first.close("transport closed")`; 214 `out.clear()` position preserved; 220 `localEditorEdit("doc:1","body", ScalarPos(5), 0, "!")`; 255-256 `surface.remove` request; 270-271 `dialog.show` with `spec = editorNode("body","doc:2","hi")`; 280 `completeDialogDismiss("dlg")`.
- 128-129/237/278 `.reqObj("error").reqObj("data").reqString("reason")` — expected `"editor-session-limit"`, `"editor-duplicate"` verbatim; 132-133/283 `.reqObj("result").reqString("status")` = `"applied"`.
- 155/157 `assertEquals("print()", s.shadow)` and `assertEquals(1, s.seq)` — `s.seq` is a Kotlin Long property (not a JSON read); bare `1` binds `long,long`. Leave as-is.

**End state**: 0 errors; 12 `@Test`; echo by element; `toReady` conditional intact.

---

### B.12 EditorCommandTest.kt — batch t5 — **3 @Test**, 124 lines

**Helpers**: 18-21 KAT DELETE; 23-28 `limits()` DELETE → `testLimits("max_editor_bytes" to 65_536)` (note: NO max_editor_sessions in this file); 30 `frame` DELETE; 32-50 `readyEngine(out)` KEEP-and-convert (wants = `listOf("editor.sync")`; sink `forEach(out::add); finish()`).

**Numeric reads — all engine-emitted, `reqLong` + `L`**: 66 `revision_seen` (already `7L` — keep); 72-74 `args.reqLong("cursor"/"sel_start"/"sel_end")` expected `5L/2L/5L`; 97-99 expected `10L/0L/10L`; 106-108 expected `1L/1L/1L`.

**Risk sites**
- 56-58/88-90/115-117 three `surface.update` requests (revisions 7, 1, 1) → buildJsonObject; revision Int-spelled.
- 60-61 `editorCommand("app:main","doc.org","ed1","org-todo", cursor = Utf16Pos(5), selStart = Utf16Pos(2), selEnd = Utf16Pos(5))` — named args preserved.
- 93-94 positional `Utf16Pos(20), Utf16Pos(20), Utf16Pos(0))` — backward drag on purpose; 102-103 `Utf16Pos(3) ×3` mid-surrogate; 119-120 `"nope.org"` returns `false`.
- 91 `"😀".repeat(10)` byte-verbatim.
- 67 `EbpAuth.isValidNonce(ev.reqString("event_id"))`; 76 `args.reqString("session").isNotEmpty()`; **77** `assertTrue("seq" in args)`.
- 118/122 `out.size` no-op check preserved.

**End state**: 0 errors; 3 `@Test`.

---

### B.13 W6QueueTest.kt — batch t5 — **20 @Test**, 568 lines

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 23-24 | `@get:Rule val temp = TemporaryFolder()` | KEEP (and its imports) |
| 26-29 | KAT | DELETE |
| 31-36 | `limits()` | DELETE → `testLimits()` (no extras) |
| 38-45 | `config()` | KEEP-and-convert (bare config, no sink) |
| 47 | `frame` | DELETE |
| 49-54 | `engineOn(queue, store, out)` | KEEP-and-convert; 3-positional constructor `(config(), store, queue)`; sink `d.feed(bytes).forEach(out::add); d.finish()` |
| 56-65 | `CompanionEngine.handshake(toReady: Boolean = true)` member extension | KEEP-and-convert — the `q0` `queue.replay` AND `r1` `session.ready` are both inside the toReady path; preserve |
| 67-70 | `queuedDescriptor(dedupe: String? = null)` | KEEP-and-convert — flatten `.also{}`; **`put("ttl_s", 3600L)` stays integer-spelled** |
| 72-75 | `surfaceWithInput()` | KEEP-and-convert (`SurfaceStore(16,1024).also { it.update("app:main", 1, <spec>, null, null, null) }`) |
| 77-78 | `List<JSONObject>.events()` | DELETE → TestSupport `events()` (identical predicate) |
| 80-83 | `respondTo` | KEEP-and-convert — **the most important echo site in the batch**, exact code below |

**§3.5(a) — `respondTo` exact conversion (called 10×)**:
```kotlin
    private fun respondTo(engine: CompanionEngine, event: JsonObject, status: String) =
        engine.feed(frame(buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", event["id"]!!)
            put("result", buildJsonObject { put("status", status) })
        }))
```
`event["id"]!!` — the element verbatim. `reqLong("id")` would happen to work today and is FORBIDDEN (breaks R2 echo discipline).

**Other echoes**: 171 `put("id", first["id"]!!)` (the 1500-error injection); 212 `put("id", out.events().single()["id"]!!)`.

**JsonNull site — 191**: `assertEquals(JsonNull, summary["blocked_by"])`.

**Numeric reads — engine-emitted, `reqLong` + `L`**: 107 `queued_events`; 114/188/346/401 `delivered`; 115/190/402 `remaining`; 189 `rejected`; 218 `remaining`; 210 code `1600L`; 462 `welcome.reqLong("queued_events")` expected `1L`; 482/505 code `1201L`; 269/282/288/289 `q.head()!!.reqLong("queue_seq")` / `record.reqLong("queue_seq")`.
**466**: `assertNotNull(event.reqLong("queued_at_ms"))` — was vacuous with getLong; reqLong makes it a real existence check. Keep the assertNotNull wrapper.

**Id matching**: 113/187/209/216/345/400/481 string ids → `out.replyTo("q1"/"q2"/"rm")` matching original selection; 74/441 `put("id","title")` are node ids.

**Fixture events fed to `q.admit` — occurred_at_ms MUST be integer-spelled** (`DurableQueue.kt:122` does `reqLong("occurred_at_ms")` internally): every event fixture at 257-258, 276-277, 297-298, 309-310, 317-318 keeps `q.effectiveNow()` / `now` / `900_000L` Long values in `put("occurred_at_ms", ...)`. A Double spelling throws inside `admit`.

**Queue API (unchanged shapes, convert only JSON args)**: `q.admit(event("a"), "queue", "key", 3600)`; 280 `q.admit(ev("x"), "queue", null, 3600, pendingLocal = true)` (named arg preserved); `beginDelivery`/`clearPendingLocal(Long)`/`clearInFlight(Long)`/`it.clock = { now }`/`sweepExpired()`/`effectiveNow()`/`hasInFlight()`/`head()`; 316 `DurableQueue(MemoryQueueStore(), maxEvents = 1, maxBytes = 8_388_608)`; 499 `DurableQueue(MemoryQueueStore(), 256, 8_388_608) { 1000L }` (trailing lambda = clock); 439/454 `SurfaceStore(16, 1024, backing = FileSurfaceBacking(surfaceFile))`; 484 `store.snapshot().size`.

**Mutations**: 361 & 447 `queuedDescriptor().with("capture_fields", JsonArray(listOf("title").map(::JsonPrimitive)))`; 504 `queuedDescriptor().with("args", buildJsonObject { put("pad", pad) })` — all consumed as arguments.

**Byte-accounting overhead fixture (488-508)** — convert the builder, keep every member, order, and spelling; the serialized size is load-bearing and insertion order now equals the engine's write order (`event_id, action, surface, revision_seen, occurred_at_ms, args`):
```kotlin
        val overhead = buildJsonObject {
            put("event_id", "0".repeat(32)); put("action", "demo.tap")
            put("surface", "app:main"); put("revision_seen", 1L)
            put("occurred_at_ms", 1000L)
            put("args", buildJsonObject { put("pad", "") })
        }.toString().toByteArray(Charsets.UTF_8).size
        val pad = "x".repeat(limit - overhead)
```

**§3.5(b) — `byteGateMeasuresWhatItEmits` (528-567), exact treatment** (master-plan-ratified: the re-serializer is `Json.parseToJsonElement`, the SAME serializer as emit — do NOT substitute `EbpJson.parse`, do NOT strengthen to `assertEquals(body, event.toString())`):
- `val tricky = "— “q” €</xtail"` — byte-verbatim (it probes the retired org.json `/`-escaping divergence; the assertion now holds because emit and re-serialize are the same function).
- Dual sink converts as-is: `raw.add(bytes); FrameDecoder().let { d -> d.feed(bytes).forEach(out::add); d.finish() }`; `raw = mutableListOf<ByteArray>()` unchanged.
- `dispatchAction("app:main", buildJsonObject { put("action","a.b"); put("args", buildJsonObject { put("note", tricky) }) }, null)`.
- `val event = out.events().single()`; `val params = event.reqObj("params")`; assertion 1: `assertEquals(tricky, params.reqObj("args").reqString("note"))`.
- The `\r\n\r\n` substring split and `Regex("Content-Length: (\\d+)")` lines: UNTOUCHED.
- Assertion 2: `assertEquals(body.toByteArray(Charsets.UTF_8).size, Json.parseToJsonElement(body).toString().toByteArray(Charsets.UTF_8).size)`.
- Assertion 3: `assertEquals(params.toString().toByteArray(Charsets.UTF_8).size, (Json.parseToJsonElement(body) as JsonObject).reqObj("params").toString().toByteArray(Charsets.UTF_8).size)`.
- Assertion 4 (declared Content-Length): UNTOUCHED.

**Misc**: 358/418/445 `publishState(..., JsonPrimitive("x".repeat(300_000) / "syncing edit" / "offline edit"))`; 420 `out.none { it.stringOrNull("method") == "state.changed" }` (stays `none` — it has the 422-424 positive control right below: `stateIdx in 0 until eventIdx`, ordering preserved); 380 `assertEquals(1, out.count { it.stringOrNull("method") == "log.error" })` exact count; 270-271 `val seqs = listOf(q.head()!!.reqLong("queue_seq")); assertTrue(seqs.all { it >= 1 })` — weak on purpose, keep; 360-362/503-504 dispatch callbacks `{ _, error -> localError = error }` with `var localError: JsonObject?`.

**End state**: 0 errors; 20 `@Test`; respondTo echoes by element; byteGate re-serializer is `Json.parseToJsonElement`.

---

### B.14 WireConformanceTest.kt — batch t5 — **12 @Test**, 296 lines

**No engine, no limits(), no frame() in this file.**

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 22-24 | `ebpDir` / `wireDir` | KEEP verbatim |
| 28-31 | katToken/katPid/katCn/katSn | DELETE (TestSupport). **The two KAT proof hex strings at 36/39 are raw fixtures — KEEP** |
| 54-61 | `chunkings(bytes)` | KEEP unchanged (pure bytes) |
| 63-73 | `runFixture(chunks)` | KEEP-and-convert: return type `Pair<List<JsonObject>?, String?>`; the four catch arms (`FrameClose`→"close", `FrameIncomplete`→"incomplete-frame", `WireParseError`→"parse-error", `InvalidRequest`→"invalid-request") unchanged |
| 176-177 | nested `dup(text)` | KEEP unchanged (`EbpJson.parse` IS the subject — wire-strict) |
| 201-205 | nested `required(method)` | KEEP-and-convert: `methods.reqObj(method).reqObj("params").reqArr("required").map { it.asStringOrNull()!! }.toSet()` |
| 285-295 | `jsonEquals(Any?, Any?)` | **DELETE ENTIRELY** — §3.3, below |

**§3.3(a) — jsonEquals deletion + jsonValueEquals call shape.** Delete the whole walker (its `JSONObject.NULL` structural clause dies with it). The manifest replay loop (100-104) becomes:
```kotlin
                    val expected = fx.reqArr("expect_messages")
                    assertEquals(context, expected.size, messages!!.size)
                    for (i in messages.indices) {
                        assertTrue("$context message $i differs",
                            jsonValueEquals(messages[i], expected[i]))
                    }
```
`jsonValueEquals` is production (`jvmMain/JsonEquality.kt`) — objects unordered, arrays ordered, numbers by binary64 value (`1 == 1.0`, SPEC 4.3), `"1" != 1`. **Never** write `messages[i] == expected[i]` — kotlinx data-class equality compares content strings (`1 != 1.0`) and the manifest is lenient-parsed while messages come from EbpJson: element equality WILL break the replay.

**Manifest/goldens reads (lenient, house cast idiom)**: 77 `val manifest = Json.parseToJsonElement(wireDir.resolve("manifest.json").readText()) as JsonObject`; 78-80 `manifest.reqArr("fixtures")`, `assertTrue("adversarial set truncated?", fixtures.size >= 10)`, per-index `val fx = fixtures[f] as JsonObject`; 89-93 `fx.arrOrNull("roles")?.let { roles -> val named = roles.map { it.asStringOrNull()!! }; ... }` (assertion message unchanged); 94 `wireDir.resolve(fx.reqString("file")).readBytes()`; 98 `fx.reqString("kind") == "positive"`; 107 `fx.reqString("expect_error")`; 199 `val contract = Json.parseToJsonElement(ebpDir.resolve("contract.json").readText()) as JsonObject` + `contract.reqObj("methods")`.

**§3.3(b) — `envelopeClassification` (140-153), every builder call**:
- 143 `request("r1", "session.ready", JsonObject(emptyMap()))` — the String-id overload of `request` still exists; only the params object changes.
- 145 `notification("state.changed", JsonObject(emptyMap()))`.
- 147 `resultResponse(JsonPrimitive("r1"), JsonObject(emptyMap()))` — **there is NO String overload of resultResponse**; the id must be `JsonPrimitive("r1")`.
- 149 `errorResponse(JsonPrimitive("r1"), 1204, "not legal now", "session-state")` — id is `JsonElement`; code stays plain `Int` 1204.
- 151 `assertNull(classifyMessage(buildJsonObject { put("jsonrpc","1.0"); put("method","x") }))`.
- 152-153 `assertNull(classifyMessage(buildJsonObject { put("jsonrpc","2.0"); put("id","r1"); put("result", JsonObject(emptyMap())); put("error", JsonObject(emptyMap())) }))`.

**§3.3(c) — `requestIdGrammar` (155-166), every call wrapped; signature is `isValidRequestId(id: JsonElement?)`**:
```kotlin
        assertTrue(isValidRequestId(JsonPrimitive("r1")))
        assertTrue(isValidRequestId(JsonPrimitive("a".repeat(64))))
        assertFalse(isValidRequestId(JsonPrimitive("a".repeat(65))))
        assertFalse(isValidRequestId(JsonPrimitive("")))
        assertTrue(isValidRequestId(JsonPrimitive(7))) // amendment #34: jsonrpc.el ids
        assertTrue(isValidRequestId(JsonPrimitive(9_007_199_254_740_991L)))
        assertFalse(isValidRequestId(JsonPrimitive(9_007_199_254_740_992L)))
        assertFalse(isValidRequestId(JsonPrimitive(7.5)))
        assertFalse(isValidRequestId(null))
```
The last line is Kotlin `null` (absent id) — do NOT write `JsonNull`; production has a separate `JsonNull → false` branch and `null` is the semantic this line pins. Do not add extra assertions.

**Raw-text fixtures — untouchable**: 36/39 proof hex; 132 `"Content-Length: 2\r\n\r\n{}"` + `encodeFrame("{}")`; 134-135 `"""{"a":"é"}"""` + `"Content-Length: 10\r\n\r\n"`; 178-183 the five duplicate-scan texts; 117 the regex; 243 `"x".repeat(4_000_000)`; 158-159 (now inside requestIdGrammar wraps — the `repeat` expressions stay). The whole `utf8FixtureWitnessesOctetCounting` test (114-125) and byte/chunk loops (236-258, 261-281): TOUCH NOTHING except any `List<JSONObject>` type mention.

**Other conversions**: 206-209 `hello.keys` / `auth.keys`; 210 `auth.reqString("client_proof")`; 151 hand-built envelope covered above; 222 `sessionStep(s, event) ?: fail("illegal: $event from $s").let { return }` — keep verbatim, do NOT clean up; 252/274-275 consumer-overload feeds unchanged; 257/278-279 `out[i].reqObj("params").reqString("m")`; 101 `assertEquals(context, expected.size, messages!!.size)` (Int/Int — safe).

**End state**: 0 errors; 12 `@Test`; `jsonEquals` gone; zero org.json identifiers.

---

### B.15 WidgetsGoldenReplayTest.kt — batch t5 — **2 @Test**, 80 lines

**Nothing moves to TestSupport** (no KAT, no limits, no frame, no engine, no selectors).

**§3.4 — `goldensDir()` rewrite (21-30), exact replacement** (replaces the `user.dir` upward walk; `ebp.dir` is already set on the jvmTest task — matches CompanionEngineTest/WireConformanceTest):
```kotlin
    // The contract repo location comes from the ebp.dir system property
    // (set on the jvmTest task) — no cwd-dependent upward walk.
    private fun goldensDir(): File =
        File(System.getProperty("ebp.dir")
            ?: error("ebp.dir system property not set")).resolve("goldens")
```
Delete the while-loop, the `fail(...)`, and the `throw IllegalStateException()` tail. Call sites (`File(goldensDir(), name)`) unchanged. Keep `import org.junit.Assert.fail` — the two @Test bodies still use `fail`.

**Helpers**: 32-38 `goldenLines(name)` — pure String/IO, KEEP UNTOUCHED. 42-52 `wrapAction` — KEEP-and-convert, exact replacement:
```kotlin
    private fun wrapAction(action: JsonObject): JsonObject = buildJsonObject {
        put("t", "column")
        putJsonArray("children") {
            action.arrOrNull("capture_fields")?.forEach { cf ->
                addJsonObject { put("t", "text_input"); put("id", cf.asStringOrNull()!!) }
            }
            addJsonObject { put("t", "button"); put("label", "x"); put("on_tap", action) }
        }
    }
```
(Signature changes param AND return to `JsonObject`. Passing `action` by reference into `on_tap` is now safe immutable sharing.)

**The two parse shapes — they DIFFER, do not use `.jsonObject` for both**:
- 59 (widgets, one object per line): `val obj = Json.parseToJsonElement(json) as JsonObject`.
- 72 (hypertext, one ARRAY per line): `val doc = buildJsonObject { put("t","column"); put("children", Json.parseToJsonElement(json) as JsonArray) }`.
Golden line text is byte-verbatim by definition — never re-serialize or normalize it (mixed spellings like `"font_weight":700` are preserved in `JsonPrimitive.content`; `isIntegral` still discriminates).

**Other sites**: 60 `if ("action" in obj || "builtin" in obj) wrapAction(obj) else obj`; 62/73 `SpecValidator.validateSurfaceSpec(doc, "widgets:$idx" / "hypertext:$idx")` — positional JsonObject works against the new `JsonElement?` signature, unchanged; 63/74 `catch (e: ContentInvalid)` with `e.reason`/`e.path` unchanged; 57 corpus-floor assert unchanged. Imports to drop: `org.json.JSONArray`, `org.json.JSONObject`; keep `java.io.File`.

**End state**: 0 errors; 2 `@Test`; no `user.dir` reference anywhere in the file.

---


## C. BATCH PROTOCOL FOR THE MAIN LOOP

### C.1 Workflow shape
- **t4**: one Workflow, 9 Opus agents in parallel — one per file: CompanionEngineTest, CapabilityTest, DialogTest, ActionEventTest, ReminderTest, PieMenuTest, BuiltinTest, DispatchFieldsTest, NotificationSurfaceTest (sheets B.1–B.9).
- **t5** (only after t4 is committed): one Workflow, 6 Opus agents — EditorTest, EditorLifecycleTest, EditorCommandTest, W6QueueTest, WireConformanceTest, WidgetsGoldenReplayTest (sheets B.10–B.15).
- Each agent prompt = block A verbatim + its one B sheet verbatim + the absolute target path under `$WT/companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire/` + the A.1 read-only reference list. Agents write the file in place and do not compile.

### C.2 Pre-batch snapshot (main loop, from `$WT/companion`)
```bash
./gradlew :wire:compileTestKotlinJvm --console=plain 2>&1 | grep "^e: " > "$SCRATCH/pre.txt"
wc -l < "$SCRATCH/pre.txt"                                   # t4 baseline: 343
grep -oE '[A-Za-z0-9]+\.kt' "$SCRATCH/pre.txt" | sort | uniq -c > "$SCRATCH/pre-perfile.txt"
```

### C.3 Post-batch compile + acceptance rule
```bash
./gradlew :wire:compileTestKotlinJvm --console=plain 2>&1 | grep "^e: " > "$SCRATCH/post.txt"
wc -l < "$SCRATCH/post.txt"
grep -oE '[A-Za-z0-9]+\.kt' "$SCRATCH/post.txt" | sort | uniq -c > "$SCRATCH/post-perfile.txt"
```
A batch is ACCEPTED only when ALL of:
1. Total error count strictly below the pre-batch count (ledger monotone: 343 → N₄ → N₅; after t5 the only remaining error sources are the three pin files EnvelopeIdTest / PersistenceCompatTest / PreSwapNumberTest, converted at t6).
2. **Every batch file at 0 errors**: no batch filename appears in `post-perfile.txt`.
3. **No movement in non-batch files**: `diff <(grep -vE "$BATCH_RE" "$SCRATCH/pre-perfile.txt") <(grep -vE "$BATCH_RE" "$SCRATCH/post-perfile.txt")` is empty (`BATCH_RE` = alternation of the batch filenames). Any movement elsewhere = regression: stop, revert the offending file, investigate.
4. `git status --porcelain companion/wire/src/jvmTest` lists ONLY the batch files; `git diff 459458e -- companion/wire/src/jvmMain companion/wire/build.gradle.kts` is empty; `git status --short ebp/` empty.
5. Static detectors (C.4) clean or every hit on the exempt list.
6. `@Test` census per batch file equals the sheet's count: `grep -c '@Test' <file>` → t4: 25/12/12/7/6/9/3/2/4; t5: 26/12/3/20/12/2.

**Straggler rule**: a batch file with 1–3 residual errors that are mechanically obvious (missing import, reference to a deleted local helper, missing `L` suffix flagged by the compiler) → main loop fixes directly. Anything else → bounce ONCE to a fresh agent with the same A + B sheet plus the verbatim `e:` lines appended under the heading `COMPILER SAID`; after one bounce, main loop fixes by hand. Never run the batch's tests — `:wire:jvmTest` first runs at t6.

### C.4 Static detectors (from `$WT`; `F=companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire`)
Run tree-wide, compare against a pre-batch run of the same greps; only NEW hits need adjudication.
```bash
grep -rnE '\["[A-Za-z_]+"\] *[=!]= *("|[0-9-]|true|false)' $F/   # JsonElement vs raw literal
grep -rnE 'lastOrNull|firstOrNull|singleOrNull|\.none *\{' $F/    # silent-when-vacuous
grep -rn '\.content' $F/                                          # coercing reads
grep -rn 'parseToJsonElement' $F/                                 # lenient parses
grep -rnE 'put\("[a-z_]+", -?[0-9_]+\.0\b' $F/                    # double-spelled builder members
grep -rn '^import org\.json' $F/                                  # must not regrow
grep -rnE '\.jsonPrimitive|\.contentOrNull|\.jsonObject|\.jsonArray' $F/  # banned accessors (house idiom is `as JsonObject`)
```
Exempt lists (every new hit must be on these; anything else = bounce the file):
- **Detector 1, 3, 6, 7**: zero new hits allowed in batch files (`.content` remains JsonAccessTest-only).
- **Detector 2, new after t4**: DialogTest `responseFor` helper (lastOrNull, ~68) and the rpc.cancel `lastOrNull` (~178); CompanionEngineTest `lastOrNull` (~563) and the depth-64 `none {` (~498). New after t5: W6QueueTest `out.none {` (~420, positive control at 422-424).
- **Detector 4, new after t4**: CompanionEngineTest ×1 (contract.json). New after t5: WireConformanceTest ×2 (manifest.json, contract.json), WidgetsGoldenReplayTest ×2 (widgets/hypertext lines), W6QueueTest ×2 (byteGate assertions 2 and 3 — §3.5 ratified).
- **Detector 5, new after t4**: CapabilityTest `put("pitch", 3.0)` only. New after t5: none.

### C.5 Commit (main loop; only after acceptance)
```bash
cd $WT
git add companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire/{<batch files>}.kt
git commit   # heredoc message per template below
```
**t4 template** (house pattern = `RF-2b(C5.tN): <content> (errors A -> B)` + per-file notables + fleet note + trailer):
```
RF-2b(C5.t4): engine conformance suites to kotlinx (errors 343 -> <N4>)

CompanionEngineTest (malformed-frame vectors + auth KATs byte-verbatim;
the toString-indistinguishability pin unchanged — kotlinx toString IS
wireSerialize; echo ids copied by element; contract.json lenient),
CapabilityTest (60k tree rebuilt bottom-up; the -32603 serializeReply
pin ports unchanged), DialogTest (rpc.cancel integer-id pin via
JsonPrimitive(7) element equality; responseFor stays lastOrNull for its
assertNull sites), ActionEventTest (pass-through args stay Int-spelled;
draft() now JsonElement — expected wrapped in JsonPrimitive),
ReminderTest (the at_ms 1.5 rejection pin keeps its double spelling),
PieMenuTest, BuiltinTest (stringOr "" absence-in-disguise kept),
DispatchFieldsTest (the ==true absent-args guard kept),
NotificationSurfaceTest (no TestSupport — store-only suite).

9-agent fleet under the C5 execution appendix (block A + per-file
sheets); <k> stragglers bounced/fixed; uncertainties: <list or "none">.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```
**t5 template**:
```
RF-2b(C5.t5): editor/queue/goldens to kotlinx (errors <N4> -> <N5>)

EditorTest (the bare-limits omission reproduced via testLimits override;
LD-4 codePointCount kept; annotation seq is pass-through — Long-spelled
fixture), EditorLifecycleTest (edit.complete answered by element-copied
id), EditorCommandTest, W6QueueTest (§3.5: byteGate re-serializes via
Json.parseToJsonElement(body).toString() — the same serializer as emit;
respondTo echoes the id element verbatim; blocked_by JsonNull),
WireConformanceTest (§3.3: the jsonEquals walker deleted — production
jsonValueEquals compares the manifest replay; isValidRequestId args
wrapped in JsonPrimitive, the null case stays Kotlin null;
resultResponse/errorResponse take JsonElement ids), WidgetsGoldenReplayTest
(§3.4: user.dir walk replaced by the ebp.dir property; hypertext lines
parse as JsonArray, widgets as JsonObject).

6-agent fleet under the C5 execution appendix (block A + per-file
sheets); <k> stragglers bounced/fixed; uncertainties: <list or "none">.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

### C.6 After t5
Expected residual: errors only in the three pin files. Hand off to t6 per the master plan (pins convert last, hermetic, then the first `:wire:jvmTest` run and §4 adjudication). Do not run jvmTest, the mutation matrix, or the review fleet from this appendix — those are t6+ steps.

---

### Critical Files for Implementation
- /home/calebc42/pkb/projects/jetpacs/jetpacs/.claude/worktrees/rf2b-c5/companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire/TestSupport.kt (the shared vocabulary every sheet references)
- /home/calebc42/pkb/projects/jetpacs/jetpacs/.claude/worktrees/rf2b-c5/companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/JsonAccess.kt (the only permitted read idioms; `.with` at :138)
- /home/calebc42/pkb/projects/jetpacs/jetpacs/.claude/worktrees/rf2b-c5/companion/wire/src/jvmMain/kotlin/com/calebc42/ebp/wire/CompanionEngine.kt (every seam signature in A.13)
- /home/calebc42/pkb/projects/jetpacs/jetpacs/.claude/worktrees/rf2b-c5/companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire/CompanionEngineTest.kt (largest and highest-risk conversion, B.1)
- /home/calebc42/pkb/projects/jetpacs/jetpacs/.claude/worktrees/rf2b-c5/companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire/WireConformanceTest.kt (the jsonEquals→jsonValueEquals swap, B.14)