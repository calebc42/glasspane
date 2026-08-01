# PLAN — RF-2b C5.t4: the 9 engine-conformance suites to kotlinx (Opus fleet execution doc)

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


## B. PER-FILE INSTRUCTION SHEETS (batch t4)

### B.1 CompanionEngineTest.kt — batch t4 — **25 @Test**, 680 lines

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 19-20 | `ebpDir = File(System.getProperty("ebp.dir") ?: error("ebp.dir system property not set"))` | KEEP verbatim |
| 22-25 | katToken/katPid/katCn/katSn | DELETE (TestSupport) |
| 27-32 | `limits()` (9 core, no extras) | DELETE → every plain `limits()` call → `testLimits()` |
| 34-39 | `profiles()` | KEEP-and-convert to `buildJsonObject`. node_types stays the HAND-WRITTEN list `["text","row","column","box","spacer","divider","button","text_input"]` — do NOT replace with `NODE_SCHEMA.keys` |
| 41-55 | `engine(sink: MutableList<JsonObject>, supported: Set<String> = setOf("theme"), nonce: String = katSn)` | KEEP-and-convert. Sink body unchanged: `FrameDecoder().let { d -> d.feed(bytes).forEach(sink::add); d.finish() }` |
| 57-67 | `engineWithLimits(limits: JsonObject)` | KEEP-and-convert; empty sink `{ }` stays |
| 69 | `frame(msg)` | DELETE (TestSupport) |
| 71-73, 75-76 | `hello()`, `auth()` | KEEP — bodies unchanged (EbpAuth returns JsonObject) |
| 253-257 | `authedEngine(out)` | KEEP |
| 412-414 | `arrayParamsRequest(id, method)` | KEEP-and-convert → `buildJsonObject { put("jsonrpc","2.0"); put("id", id); put("method", method); put("params", buildJsonArray { add(1) }) }` — the positional-array params IS the point |

**testLimits overrides**: line 302 `limits().put("max_input_state_bytes", 4_194_000)` → `testLimits("max_input_state_bytes" to 4_194_000)`; line 506 `limits().put("max_surfaces",30000).put("max_surface_ids",30000)` → `testLimits("max_surfaces" to 30000, "max_surface_ids" to 30000)`.

**Raw-text fixtures — byte-verbatim, do not touch**: 290 `"X-No-Length: 1\r\n\r\n".toByteArray(Charsets.US_ASCII)`; 447 `encodeFrame("{ not json")`; 452 `encodeFrame("[]")`; 456 `encodeFrame("""{"a":1,"a":2}""")`; 474 `encodeFrame("{bad")`; 490/497 the depth-65/64 probes `"{\"a\":".repeat(65) + "1" + "}".repeat(65)` (and 64); 556 `encodeFrame("[1,2]")`; 528/537/531 the 200-char/`"bad name!"` method names; 145/160/161/209/222 the auth KAT strings.

**JSONObject.NULL sites** (all assert-emitted-null): 105 `assertEquals(JsonNull, replay["blocked_by"])`; 448, 453, 491 `assertEquals(JsonNull, out.last()["id"])`; 479 (predicate) `it["id"] == JsonNull`; 560 (predicate) `it["id"] == JsonNull`.

**Numeric reads — engine-emitted, all `.reqObj("error").reqLong("code")` with `L` literals**: lines 125, 135, 148, 183, 197, 212, 228, 239, 248, 266, 269, 272, 275, 351, 357, 423, 426, 433, 449, 454, 457, 492, 530, 533 (e.g. `assertEquals(-32700L, out.last().reqObj("error").reqLong("code"))`). Also: 104 `remaining` → `reqLong("remaining")` + `L`; 347 / 382 `revision` → `reqLong("revision")` + `L`.
Special numeric sites:
- 240: `assertEquals(2L, integralLongOrNull(err.reqObj("data").reqArr("supported")[0]))`
- 480: `it["id"] == JsonNull && it.objOrNull("error")?.reqLong("code") == -32700L`
- 498: `out.drop(base).none { it.objOrNull("error")?.let { e -> integralLongOrNull(e["code"]) } == -32700L }`
- 560-561: `out.any { it["id"] == JsonNull && it.objOrNull("error")?.let { e -> integralLongOrNull(e["code"]) } == -32600L }`
- 578: `if (err?.let { integralLongOrNull(it["code"]) } == 1401L) refused++`

**Id matching / echo**
- 110 `assertEquals(JsonPrimitive("r1"), out.last()["id"])`; 461 same shape with `"q1"`.
- 477 `it["id"] == JsonPrimitive("q1")` (inside `any {}` — stays a predicate).
- 529, 532 `out.last { it.opt("id") == "m1"/"m2" }` → `out.replyTo("m1")` / `out.replyTo("m2")`.
- 563 **must stay nullable**: `assertNotNull(out.lastOrNull { it["id"] == JsonPrimitive("q1") })`.
- 278 `put("id", 7)` — keep integer-spelled. 280: `assertEquals(JsonPrimitive(7), out.last()["id"])` (typed equality; `JsonPrimitive(7) == JsonPrimitive(7L)`).
- **ECHO 585-586**: `val firstId = out.events().first()["id"]!!` then in the response envelope `put("id", firstId)`. **ECHO 591-593**: `for (m in out.events().drop(1).take(400))` ... `put("id", m["id"]!!)`. **ECHO 626-628**: `val delivered = out.events().last()` ... `put("id", delivered["id"]!!)`. All three hand-built envelopes become `frame(buildJsonObject { put("jsonrpc","2.0"); put("id", <element>); put("result", ...) })`. Never `getInt`.

**`.also{}` nested mutations — rebuild, kotlinx has no in-place nested put**
- 144-146: `auth().also { it.getJSONObject("params").put("client_proof", "0".repeat(64)) }` → `request("h2","auth.response", EbpAuth.authParams(katPid, katCn, katSn, katToken).with("client_proof", JsonPrimitive("0".repeat(64))))`
- 236: `hello().also { it.getJSONObject("params").put("protocol", 1) }` → `request("h1","session.hello", EbpAuth.helloParams("test-client","0.0.1",katPid,katCn,listOf("theme")).with("protocol", JsonPrimitive(1)))`

**toString indistinguishability (170-190)**: the `assertEquals(unknownOut.first().toString(), wrongOut.first().toString())` / `.last().toString()` lines stay LITERALLY unchanged. Only 183's code read converts (`reqObj("error").reqLong("code")`, expected `1203L`).

**Contract-drift test (390-408)**: `val contract = Json.parseToJsonElement(ebpDir.resolve("contract.json").readText()) as JsonObject`; `contract.reqObj("methods")`; `methods.keys`; `row.reqString("sender")`, `row.reqString("class")`; `row.reqArr("states").map { it.asStringOrNull()!! }.toSet()`. Loop shape and assertion messages unchanged.

**Seam calls**: 577/615/650 `sendRequest("event.action", JsonObject(emptyMap())) { ... }` (650's params: `buildJsonObject { put("k","v") }`); 654 `got!!.reqObj("data").reqString("kind")`; 618-620/630-632 `dispatchAction("app:main", buildJsonObject { put("action","demo.act"/"demo.act2"); put("when_offline","queue"); put("ttl_s", 3600) }, null)` — `ttl_s` stays Int-spelled `3600`; 668-670 `dialogListener` lambda unchanged (types infer); 304-308/321/331-338/369-377 inline `CompanionEngine(CompanionConfig(...))` constructions all convert (profiles/limits args per above).

**Misc**: 97 `m in welcome`; 99-100 `welcome.reqArr("granted").map { it.asStringOrNull() }`; 111 `.reqObj("result").size` (bare `0` fine); 281 `"result" in out.last()`; 358 `"path" in contentError.reqObj("data")`; 462 `assertNotNull(out.last().reqObj("result"))` (keep the wrapper); 348-363 do NOT add a `revision` member where absent (the −32602-vs-1201 taxonomy depends on it); 342 `spec` reuse across four requests stays (now safe immutable sharing); 580/615 `repeat(512)` loops and 591 drain-order preserved exactly.

**End state**: 0 compile errors attributable to this file; 25 `@Test`; no org.json identifiers outside comments; `ebpDir` and all raw fixtures byte-identical.

---

### B.2 CapabilityTest.kt — batch t4 — **12 @Test** (one is `@Test(expected = IllegalArgumentException::class)` at 94 — keep the annotation), 293 lines

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 17-20 | KAT | DELETE |
| 22-28 | `limits()` | DELETE → `testLimits("max_device_report_bytes" to 8192, "max_rich_spans" to 4096, "max_table_cells" to 4096)` |
| 30 | `frame` | DELETE |
| 31 | `response(out,id)` | DELETE → `out.replyTo(id)` (throwing is identical; no assertNull sites in this file) |
| 32 | `errorOf(out,id)` | DELETE → `out.errorOf(id)` |
| 34-37 | `report(vararg caps)` | KEEP-and-convert: `buildJsonObject { put("caps", JsonArray(caps.toList().map(::JsonPrimitive))); put("trigger_caps", JsonArray(emptyList())); put("permissions", JsonObject(emptyMap())) }` |
| 41 | `calls` recorder | KEEP → `mutableListOf<Pair<String, JsonObject>>()` |
| 43-72 | `engine(...)` factory | KEEP-and-convert (below) |
| 74-78 | `invoke(engine, id, cap, args: JsonObject? = null)` | KEEP-and-convert → `buildJsonObject { put("cap", cap); if (args != null) put("args", args) }` (flatten the in-place mutation) |
| 236-238 | `ok(cap, args)` | KEEP-and-convert; `args: JsonObject`; try/catch `ContentInvalid` unchanged |

**engine() factory conversion** (43-72): keep the default-argument handler closing over `calls`; convert its bodies: `"clipboard.read" -> CapabilityOutcome.Ok(buildJsonObject { put("text", "hi") })`; `"volume.set" -> CapabilityOutcome.Ok(buildJsonObject { put("max", 15) })` — **`15` stays an Int literal** (pass-through, read back at 130); `else -> CapabilityOutcome.Ok(JsonObject(emptyMap()))`. `surfaceProfiles = buildJsonObject { putJsonObject("app") { put("node_types", JsonArray(NODE_SCHEMA.keys.map(::JsonPrimitive))); put("builtins", JsonArray(emptyList())); put("features", JsonArray(emptyList())) } }`. Sink keeps the CONSUMER overload, no finish(): `FrameDecoder().let { d -> d.feed(bytes) { out.add(it) } }`. Handshake stays full (hello/auth/`request("r1","session.ready", JsonObject(emptyMap()))`).

**Numeric reads**
- 130 (pass-through): `assertEquals(15L, out.replyTo("c2").reqObj("result").reqLong("max"))`.
- 155, 170, 180, 194, 197, 201, 217, 220, 230 (engine-emitted): `assertEquals(<code>L, out.errorOf(<id>).reqLong("code"))`.
- 155 region (was `errorOf(out,"c1").getInt("code")` = −32603) — see deep-tree block below: `assertEquals(-32603L, out.errorOf("c1").reqLong("code"))` and `assertEquals("internal-error", out.errorOf("c1").reqObj("data").reqString("kind"))`.

**Mutations of helper results (`.with`, result must be consumed — all are argument positions, so consumption is inherent)**
- 98-99: `report("vibrate").with("permissions", buildJsonObject { put("blob", "y".repeat(9000)) })` — REPLACES the line-37 member.
- 109-113: four chained `.with(...)`: `report("vibrate").with("trigger_caps", <JsonArray>).with("trigger_types", <JsonArray>).with("trackable_state_types", <JsonArray>).with("state_types", <JsonArray>)` — string arrays via `JsonArray(listOf(...).map(::JsonPrimitive))`, preserving the original element lists exactly.

**§3.2 special — the 60k deep tree (143-149), exact replacement code**:
```kotlin
        var deep = JsonObject(emptyMap())
        repeat(60_000) { deep = JsonObject(mapOf("n" to deep)) }
```
(Immutable trees make the old top-down `cur.put("n", next)` impossible; bottom-up preserves 60,000 nesting levels. Delete the `cur`/`next` variables.) The handler override stays `engine(out, handler = CapabilityHandler { _, _ -> CapabilityOutcome.Ok(deep) })` (closing over the `var` is legal — the loop completes first). `invoke(engine, "c1", "clipboard.read", JsonObject(emptyMap()))`. The −32603/`internal-error` assertions are MUST-PORT-UNCHANGED — they pin `serializeReply`'s StackOverflowError arm (`CompanionEngine.kt:2441-2447` catches it; the test still passes post-swap).

**Double spellings — the SUBJECT of these lines, keep exactly**: 251 `JsonArray(listOf(JsonPrimitive(1.5)))`; 262 `put("pitch", 1.5); put("rate", 0.8)`; 263 `put("pitch", 3.0)` — must serialize as `3.0`, and `JsonPrimitive(3.0)` does; 281 `put("level", 1.5)`.
**Numeric arrays (Int-spelled, lambda form)**: 193 `JsonArray(listOf(0,100).map { JsonPrimitive(it) })`; 244 `listOf(0,100,0,100)`; 248 `listOf(0)`; 249 `listOf<Int>()` → `JsonArray(emptyList())`; 250 `listOf(60_000,60_000)`.

**Misc**: 91 `"device" !in ...reqObj("result")`; 116-118 `.reqArr(k).size` (bare Int fine); 199-200 `put("extra", 1)` stays Int; 291 `assertFalse(ok("state.get", JsonObject(emptyMap())))` — asserts the unimplemented row still throws, do not "fix"; `calls.isEmpty()` asserts at 171/182/202 unchanged; 152-153/212-215 inline `CapabilityHandler { cap, args -> ... }` — `args` is `JsonObject`; 228 `handler = null` unchanged; 237 `CapabilityCatalog.validateArgs(cap, args)` unchanged.

**End state**: 0 errors; 12 `@Test`; the deep-tree test bottom-up; all double-literals preserved.

---

### B.3 DialogTest.kt — batch t4 — **12 @Test**, 283 lines

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 18-21 | KAT | DELETE |
| 23-28 | `limits()` | DELETE → `testLimits("max_dialogs" to 2)` |
| 30 | `frame` | DELETE |
| 32-59 | `readyEngine(out, presented)` | KEEP-and-convert. `presented: MutableList<Pair<String, JsonObject?>>`. Two profiles convert to nested `putJsonObject("app"){...}` / `putJsonObject("dialog"){...}` with their exact node_types/builtins lists; sink `d.feed(bytes).forEach(out::add); d.finish()`; `dialogListener` set at 51; full handshake; READY assert at 57 stays |
| 61-62 | `dialogSpec()` | KEEP-and-convert: `buildJsonObject { put("t","column"); putJsonArray("children") { addJsonObject { put("t","text_input"); put("id","name") } } }` |
| 64-66 | `show(engine, reqId, dialogId)` | KEEP-and-convert |
| 68-69 | `responseFor(out, reqId)` | **KEEP-and-convert — MUST NOT become replyTo** (assertNull sites 104/129/194/209/210/236): `private fun responseFor(out: List<JsonObject>, reqId: String) = out.lastOrNull { it["id"] == JsonPrimitive(reqId) }` |
| 239 | local `assertNotNull(v: Any?)` | KEEP verbatim (it shadows JUnit's, which is not imported) |

**Numeric reads (engine-emitted)**: 157 `assertEquals(1301L, ...)`, 182 `1301L`, 208 `1401L`, 220 `1201L` — all via `.reqObj("error").reqLong("code")` or `out.errorOf(id).reqLong("code")` matching the original read shape.

**The typed-id pin (161-183) — keep the string/integer asymmetry EXACT**:
- 172 `put("id", 7)` — integer request id, stays Int.
- 176 `put("id", "7")` — STRING spelling, must conclude nothing — stays a string.
- 178 `out.lastOrNull { it["id"] == JsonPrimitive(7) }` — **stays lastOrNull** (its assertion is nullability).
- 180 `put("id", 7)`.
- 181 `out.last { it.opt("id") == 7 }` → `out.replyTo(7L)` (TestSupport's Long overload).
- 156/176/180 `notification("rpc.cancel", buildJsonObject { put("id", ...) })` — payload id spelling preserved per line above.

**dialogDefaults block (87-91)**: `val d = engine.dialogDefaults("rename")!!` (returns `JsonObject?`); 89 `d.reqString("name")`; 90 `assertEquals(true, d.boolOrNull("agree"))`; 91 `assertEquals(false, d.boolOrNull("off"))` — **`boolOrNull`, not `boolOr`**: the point (comment on 91) is that the engine WROTE `false`; `boolOr` would pass on absence.

**Seam calls**: 108-109 `completeDialogSubmit("rename", JsonPrimitive("ok"), buildJsonObject { put("name","typed") })`; 127-128/132 oversize submit — value wraps in `JsonPrimitive(...)`, the `"x".repeat(4_300_000)` blob unchanged; 146 `completeDialogSubmit("rename", JsonPrimitive("late"))`; 235 `completeDialogSubmit("a", JsonPrimitive("x"))`; 276 `completeDialogSubmit("a", JsonPrimitive("done"))`; 93/142/196 `completeDialogDismiss(...)` unchanged; 123 `dialogOverflowListener = { overflowed.add(it) }` unchanged; 230 `close(...)` unchanged; 257 `dispatchDialogAction("a", descriptor, null, fields)` — 4 positional, fields is `JsonObject`; 278-279 `dispatchDialogAction("a", buildJsonObject { put("action","jetpacs.org.archive") }, null, null)`.

**Structures**: 79-84 nested spec → `buildJsonObject { put("t","column"); putJsonArray("children") { addJsonObject{...}; addJsonObject{...}; addJsonObject{...} } }` — the three children keep their exact members incl. node ids `"name"`/`"agree"`/`"off"` (node ids, not request ids); 252-255 descriptor with `put("capture_fields", JsonArray(listOf("name").map(::JsonPrimitive)))`; 259 `it.stringOrNull("method") == "event.action"` (or `out.events()` — use `out.events().last()` if the original selected last); 262/263 `"surface" !in event` / `"revision_seen" !in event`; 191-192 `.reqObj("error").reqObj("data").reqString("kind")`.

**Misc**: 129 `assertNull(responseFor(out,"d1"))` — depends on the serialize-first guard; the 4_300_000 plain-`x` blob has no escape growth, safe — port verbatim; 105-106 `presented.single().second` uses the LOCAL assertNotNull — keep.

**End state**: 0 errors; 12 `@Test`; `responseFor` still `lastOrNull`; integer/string id spellings intact.

---

### B.4 ActionEventTest.kt — batch t4 — **7 @Test**, 212 lines

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 18-21 | KAT | DELETE |
| 23-29 | `limits()` | DELETE → `testLimits("max_rich_spans" to 4096, "max_table_cells" to 4096)` |
| **42** | **nested `fun frame(msg)` INSIDE `readyEngine`** — easy to miss, it is not a class member | DELETE → TestSupport `frame` |
| 31-54 | `readyEngine(out)` | KEEP-and-convert. Handshake `wants = emptyList()`; the 47-50 `surface.update` push (rev 5, spec `{t:"text_input", id:"title", value:"authored"}`) converts to `buildJsonObject`; `revision` stays Int-spelled `5` |
| 56-62 | `descriptor(vararg capture)` | KEEP-and-convert — flatten the `.also{}`: `buildJsonObject { put("action","demo.tap"); putJsonObject("args") { put("k", 1) }; if (capture.isNotEmpty()) put("capture_fields", JsonArray(capture.toList().map(::JsonPrimitive))) }` — **`put("k", 1)` stays an Int literal (pass-through)** |

**Numeric reads**
- ENGINE-EMITTED: 78/86 `revision_seen` → `reqLong("revision_seen")`, expected `5L`; 87 `params.reqLong("occurred_at_ms") > 0` (Long comparison — fine).
- **PASS-THROUGH (fixtures must stay Int-literal)**: 90 `assertEquals(1L, args.reqLong("k"))`; 111 `assertEquals(2L, args.reqLong("from"))`; 112 `assertEquals(0L, args.reqLong("to"))`; 114 `assertEquals(1L, args.reqLong("k"))`. Their fixtures: 58 `put("k", 1)`, 106 `put("from", 2)`, `put("to", 0)`.

**Echo sites (element copy, never getInt)**: 95 `put("id", event["id"]!!)`; 179 `put("id", events[1]["id"]!!)`; 182 `put("id", events[0]["id"]!!)`. 187 `put("id", 999)` — deliberately unknown id, stays Int-spelled. The `encodeFrame(<obj>.toString())` call shapes at 94-96, 178-183, 186-188, 199-202 all convert to `frame(buildJsonObject { ... })`.

**Seam calls**: 69 `publishState("app:main","title", JsonPrimitive("typed"))`; 70-72 `dispatchAction("app:main", descriptor("title"), JsonPrimitive("clicked")) { s, _ -> status = s }`; 89 `args.reqString("value")` reads that hookValue back — correct as-is; 108 `dispatchAction("app:main", descriptor(), null, injected)`; 121/124 `publishState(..., JsonPrimitive("first"/"second"))`; 122/135 `dispatchAction(..., null)`; 156-158 `engine.surfaces.update("app:main", 5, <JsonObject spec>, null, null, null)`; 159-160 `dispatchAction("app:main", buildJsonObject { put("action","demo.tap") }, null)`; 161 `publishState(..., JsonPrimitive("offline draft"))`; 173/174 `dispatchAction(..., null) { s, _ -> statuses.add(s) }`; 204/209 `publishState(..., JsonPrimitive("hunter2"/"x"))`.
- **165 — the trap that compiles and FAILS if missed**: `draft` now returns `JsonElement?` → `assertEquals(JsonPrimitive("offline draft"), engine.surfaces.draft("app:main","title"))`. A bare String expected compiles and fails.
- 206 `assertNull(engine.surfaces.draft("app:pw","secret"))` — unchanged.
- 207 `assertFalse("app:pw" in engine.surfaces.inputState())`.

**Structures**: 106-107 `injected = buildJsonObject { put("from", 2); put("to", 0); put("order", JsonArray(listOf("c","a","b").map(::JsonPrimitive))) }`; 113 `args.reqArr("order")[0].asStringOrNull()`; 74-76 ordering-dependent `indexOfFirst { it.stringOrNull("method") == "state.changed" }` vs `"event.action"` + `assertTrue(stateIdx in 0 until eventIdx)` — preserve exactly; 175-184 the response-reordering block (answer events[1] before events[0], expect `listOf("rejected","accepted")`) — correctness rides on the echo sites; 144-153 the second inline `CompanionEngine(...)` (no nonceSource, `NODE_SCHEMA.keys` profile) converts like B.2's factory; 83 `EbpAuth.isValidNonce(params.reqString("event_id"))`.

**End state**: 0 errors; 7 `@Test`; all pass-through fixtures Int-spelled; the 165 JsonPrimitive wrap present.

---

### B.5 ReminderTest.kt — batch t4 — **6 @Test**, 193 lines

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 17-20 | KAT | DELETE |
| 22-27 | `limits(maxReminders: Long = 256)` | DELETE, **parameter threading kept**: every `limits(maxReminders)` call site → `testLimits("max_reminders" to maxReminders)`; the `engine(...)` factory keeps its `maxReminders: Long = 256` parameter (used with `3` at 123) |
| 29 | `frame` | DELETE |
| 31-50 | `engine(out, maxReminders: Long = 256, grant: Boolean = true)` | KEEP-and-convert. Sink keeps the CONSUMER overload `d.feed(bytes) { out.add(it) }` (no finish) |
| 52-54 | `reminder(id, atMs: Long, onTap: JsonObject? = null)` | KEEP-and-convert — flatten `.also{}`: `buildJsonObject { put("id", id); put("title", "T $id"); put("at_ms", atMs); if (onTap != null) put("on_tap", onTap) }` |
| 56 | `var reqN = 0` | KEEP |
| 57-63 | `set(engine, out, owner, vararg rs): JsonObject` | KEEP-and-convert; params body: `buildJsonObject { put("owner", owner); put("reminders", JsonArray(rs.toList())) }`; tail `out.last { it.opt("id") == rid }` → `out.replyTo(rid)` |
| 87-90 | nested `reason(vararg rs)` | KEEP-and-convert: `val r = set(engine, out, "org.a", *rs); return r.reqObj("error").reqObj("data").reqString("reason")` |

**Numeric reads**: 71/74/78/127 `count` (engine-emitted): `assertEquals(2L, <resp>.reqObj("result").reqLong("count"))` — explicit `L` on every one (78 asserts `0L` for the zero-vararg clear — keep the zero-vararg call). **170 PASS-THROUGH**: `assertEquals(1L, args.reqLong("k"))`, fixture 162 `put("k", 1)` stays Int. 191 `assertEquals(-32601L, ....reqLong("code"))`. 75/76/79/80/132 `ownerCount/totalCount` are Kotlin Ints — leave literal spellings alone.

**Risk sites**
- **102 — SPEC 4.3 pin, double stays double**: `put("at_ms", 1.5)` — must serialize as `1.5` (non-integer at_ms rejected, not truncated). Exempt from the Int rule.
- **117 — fully-qualified `org.json.JSONArray().put("note")`** (not covered by the file's imports — easy to miss): → `JsonArray(listOf(JsonPrimitive("note")))`.
- 105 `reminder("x",1).with("extra", JsonPrimitive(true))` (unknown member, must be rejected); 144 `reminder("x",1000).with("body", JsonPrimitive("changed"))` — both results consumed as arguments.
- 108-109 injection-conflict fixture `args:{owner:"sneaky"}` and 111-112 queue-without-ttl fixture — convert to buildJsonObject, values verbatim.
- 92-117: the eight `reason(...)` expected strings are exact validator outputs — port character-verbatim.
- 53/96/99/102 `put("id", ...)` are REMINDER ids, not request ids — plain strings.

**Seam calls**: 141/142/149 `markReminderFired` unchanged; 145/148/153 `reminders.isFired` unchanged; 164 `out.events().last()`; 166 `assertFalse("surface" in ev)` / `assertFalse("revision_seen" in ev)` (match original polarity); 174-176 `dispatchReminderTap("org.a","y") { s, _ -> status = s }`; 178 `queue.count()`; 182 `dispatchReminderTap("org.a","z")`.

**End state**: 0 errors; 6 `@Test`; `maxReminders` still threaded; 1.5 and all reason strings byte-identical.

---

### B.6 PieMenuTest.kt — batch t4 — **9 @Test**, 223 lines

**Helpers**
| Lines | Helper | Verdict |
|---|---|---|
| 17-20 | KAT | DELETE |
| 22-27 | `limits(maxPie: Long = 1)` | DELETE, parameterized → `testLimits("max_pie_menus" to maxPie)`; factory keeps `maxPie: Long = 1` (used with 1 and 4) |
| 29 | `frame` | DELETE |
| 31-52 | `engine(out, presented: MutableList<Pair<String, JsonObject?>>, maxPie: Long = 1, grant: Boolean = true)` | KEEP-and-convert; sink `d.feed(bytes).forEach(out::add); d.finish()`; `pieMenuListener = { id, spec -> presented.add(id to spec) }` |
| 54-55 | `leaf(action)` | KEEP-and-convert: `buildJsonObject { put("label","cat"); putJsonObject("on_tap") { put("action", action) } }` |
| 57-62 | `nested(vararg itemActions)` | KEEP-and-convert: `buildJsonObject { put("label","parent"); putJsonArray("items") { itemActions.forEachIndexed { j, a -> addJsonObject { put("label","i$j"); putJsonObject("on_tap") { put("action", a) } } } } }` |
| 64-68 | `show(engine, menuId, categories: JsonArray, centerLabel: String? = null)` | KEEP-and-convert — flatten `.also{}`: `buildJsonObject { put("menu_id", menuId); put("categories", categories); if (centerLabel != null) put("center_label", centerLabel) }` inside `notification("pie_menu.show", ...)` |

**Numeric reads (all engine-emitted)**: 115 `assertEquals(1L, args.reqLong("category_index"))`; 127 `assertEquals(0L, args.reqLong("category_index"))`; 128 `assertEquals(1L, args.reqLong("item_index"))`; 164 `assertEquals(1201L, params.reqLong("code"))` (match the original read chain).

**No id matching anywhere** — all selection by `method`.

**Seam calls**: 108 `selectPieMenu("m", 1)`; 124/131 `selectPieMenu("m", 0, 1)` — plain Kotlin Ints, NO JsonPrimitive wrapping; 210 `close("transport closed")`; 79-80/84-85 `notification("pie_menu.dismiss", buildJsonObject { put("menu_id", ...) })`.

**Risk sites**
- 141: `leaf("x").with("items", JsonArray(emptyList()))` — a category with BOTH `items` and `on_tap`, must be rejected; result is consumed as an argument.
- 151-153: `val many = buildJsonArray { repeat(11) { add(leaf("x")) } }`.
- Every `JSONArray().put(...)` category list (75, 95-99, 107, 123, 141-153, 175, 191-198, 208-209, 220) → `buildJsonArray { add(...) }`.
- 157-161 and 177-181 the log.error predicate: `out.filter { it.stringOrNull("method") == "log.error" && it.objOrNull("params")?.objOrNull("data")?.stringOrNull("reason") == "pie-menu-invalid" }` (equivalent to optString: both absent-forms `!= "pie-menu-invalid"`).
- 162 `assertEquals(4, invalid.size)` — exact count, bare Int fine.
- 112 `"surface" !in event && "revision_seen" !in event`; 116 `"item_index" !in args`.
- 95-96/175 invalid menu-id literals (`"not a menu id"`, `"m".repeat(129)`, `"has space"`) byte-verbatim.
- 130-132 ordering-dependent `out.size` snapshot around `selectPieMenu` — preserve; 194/200 `presented.size` counts preserve.

**End state**: 0 errors; 9 `@Test`; `presented` typed `Pair<String, JsonObject?>`.

---

### B.7 BuiltinTest.kt — batch t4 — **3 @Test**, 129 lines

**Helpers**: 17-20 KAT DELETE; 22-27 `limits()` DELETE → `testLimits()` (no extras); 29 `frame` DELETE; 31-51 `readyEngine(out)` KEEP-and-convert (profile builtins list `["view.switch","companion.settings.open","clipboard.copy"]` verbatim; handshake `wants = emptyList()`; sink `forEach(out::add); finish()`); 53-57 `multiViewSpec()` KEEP-and-convert: `buildJsonObject { put("initial_view","main"); putJsonObject("views") { putJsonObject("main") { put("t","text"); put("text","m") }; putJsonObject("detail") { put("t","text"); put("text","d") } } }`.

**Risk sites**
- 66-68 / 91 / 101 **listener-attach ORDER is load-bearing**: `surfaceListener` attached AFTER the `surface.update` feed, and 101's `changed.clear()` — preserve statement order exactly.
- 70-71/93-94/103-104: `dispatchAction("app:main", buildJsonObject { put("builtin","view.switch"); put("view","detail"/"nope") }, null)`.
- **117-119**: `engine.hostBuiltinListener = { name, d -> seen.add(name to d.stringOr("text")) }` — **`stringOr`, NOT `stringOrNull`**: 124-125 asserts `listOf("clipboard.copy" to "hello", "companion.settings.open" to "")` — the `""` is stringOr's default, an absence assertion in disguise; `stringOrNull` changes the Pair type and `""` no longer matches `null`.
- 79 `EbpAuth.isValidNonce(event.reqString("event_id"))`.
- 127 `assertTrue(out.events().isEmpty())` (replaces `out.none { it.opt("method") == "event.action" }`).
- 74/92/96/106 `out.size` counts — bare Int, unchanged.

**End state**: 0 errors; 3 `@Test`.

---

### B.8 DispatchFieldsTest.kt — batch t4 — **2 @Test**, 89 lines

**Helpers**: 16-19 KAT DELETE; 21-26 `limits()` DELETE → `testLimits()`; 28 `frame` DELETE; 30-48 `readyEngine(out)` KEEP-and-convert (wants = emptyList(); sink `forEach(out::add); finish()`).

**Risk sites**
- **60-61 and 82 — 5-positional `dispatchAction`, do not drop the two nulls**: `engine.dispatchAction("app:main", onSubmit, null, null, buildJsonObject { put("pw","s3cret") })` (and `"x"` at 82). Positions: hookValue=null, injected=null, extraFields=the object; next param is `sourceId: String?` so alignment matters.
- 59 `onSubmit = buildJsonObject { put("action","auth.login"); put("when_offline","drop") }`; 80-81 `desc = buildJsonObject { put("action","form.save"); put("when_offline","drop"); put("capture_fields", buildJsonArray { add("name") }) }`; 78-79 nested column/children spec → buildJsonObject/putJsonArray.
- **66-67 — the `== true` is load-bearing**: `assertFalse("secret must not appear in args", ev.objOrNull("args")?.containsKey("value") == true)`. Do NOT "simplify" to `!ev.reqObj("args").containsKey("value")` — `args` IS absent here (the engine omits an empty args object, `CompanionEngine.kt:461`) and reqObj would throw.
- 65/85/86 `fields.reqString("pw"/"name")`; **87** `assertTrue(fields.size == 2)` (Int).
- 57/79 `put("id", ...)` are node ids — plain strings.

**End state**: 0 errors; 2 `@Test`.

---

### B.9 NotificationSurfaceTest.kt — batch t4 — **4 @Test**, 122 lines

**No engine, no KAT, no limits(), no frame() — NOTHING moves to TestSupport.** All helpers stay local.

**Helpers**: 18 `store() = SurfaceStore(16, 1024)` KEEP verbatim (Int literals type to the Long params); 20 `body()` KEEP-and-convert (`buildJsonObject { put("t","text"); put("text","Meeting at 3") }`); 22-23 `notif(spec: JsonObject, store: SurfaceStore = store(), rev: Long = 1)` KEEP-and-convert; 25-26 `spec(meta: JsonObject? = null)` KEEP-and-convert — flatten `.also{}`: `buildJsonObject { put("body", body()); if (meta != null) put("meta", meta) }`; 41-47 `rejects(spec, fragment)` KEEP unchanged (`ContentInvalid` catch, `e.reason.contains(fragment) || e.path.contains(fragment)`); 68 nested `action(a: JsonObject) = spec(buildJsonObject { put("actions", JsonArray(listOf(a))) })` — match the original shape exactly.

**Risk sites**
- **33**: `put("base_ms", 1784700000000L)` — Long literal stays (chronometer validator reads it integer-spelled).
- **110**: `s.update("notification:a", 1, spec(), null, "v", null)` — currentView positional, unchanged shape.
- **114-115**: last param is now `JsonArray?` → `s.update("notification:a", 1, spec(), null, null, buildJsonArray { add("x") })`.
- **120**: `assertEquals(0, s.inputState().size)` (Int).
- 59 `put("mystery", 1)` stays Int.
- 61 expected fragment `"min|low|default|high|max"` is a literal pipe string — untouchable.
- 38 named-args-out-of-order call `notif(spec(), rev = 2, store = store())` — legal, preserve.
- 36/38/87/100 `.status` reads unchanged; 112/117 `e.path.contains(...)` unchanged.

**End state**: 0 errors; 4 `@Test`; zero TestSupport references.

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