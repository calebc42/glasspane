# PLAN — RF-2b checkpoint C5: `wire/src/jvmTest` to kotlinx (the pins light up)

Expansion of PLAN-rf2-kmp-migration.md §2.5's "C5 `:wire` tests" entry; §2.3 (translation
table) and §0.1 (P0 as executed) govern. First execution step: commit this plan into the
repo as `docs/PLAN-rf2-c5-tests.md` (C4 precedent).

## Context

C4 (`459458e`) finished the production half of the org.json → kotlinx conversion:
`wire/src/jvmMain` is fully kotlinx and compiles clean. The price, recorded in PLAN-rf2
§0.1, is that the 23 P0 pin tests — written pre-swap specifically to catch semantic drift
in that conversion — have been dark since C2. C5 converts `wire/src/jvmTest`
(38 files / 8,508 lines / 354 `@Test`; 36 files import org.json; the set is untouched
since P0 `a85623f`, so working-tree = ground truth) so `./gradlew :wire:jvmTest` runs for
the first time since C2. **The first green-compile run adjudicates everything C2–C4 did.**
Gate per §2.5: **G-wire + G-spec + goldens-untouched (= I1)**.

## Environment (changed since C4 — do not skip)

The llm-poc-2 worktree is now on the user's active spike branch
(`spike/elisp-vulpea-rows`, untracked `emacs/spike/` present). `rf-2b` = `459458e` exists
but is checked out **nowhere**. C5 executes in a dedicated worktree; the spike checkout is
never touched:

```bash
git -C /home/calebc42/pkb/projects/jetpacs/jetpacs worktree add .claude/worktrees/rf2b-c5 rf-2b
cd /home/calebc42/pkb/projects/jetpacs/jetpacs/.claude/worktrees/rf2b-c5
git submodule update --init --reference /home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-2/ebp ebp
# (drop --reference if the local ebp objects don't resolve; submodule pin: ebp @ 83d6e08)
```

All commands below run from that worktree (`$WT`); Gradle from `$WT/companion`. `:app` is
irrelevant to C5 (no ANDROID_HOME needed). When done: leave the worktree for C6 or
`git worktree remove` after merge — the user switches llm-poc-2 back to rf-2b whenever the
spike concludes.

## Ratified decisions (2026-07-31, this session)

1. **Staged batch commits like C4** — `compileTestKotlinJvm` error count per commit,
   monotone descent. Caveat adopted from design review: batch commits are a *progress*
   ledger only (no test can run mid-port); the bisect value lives in the separate
   adjudication commits (`C5.tN` test fixes / `C5.fN` production fixes).
2. **PersistenceCompatTest upgrade-gate fixtures frozen as raw org.json-SPELLED text**
   (§3.8 variant ii) — the legacy-file gate keeps testing yesterday's files under
   tomorrow's parser.
3. **Shared `TestSupport.kt` first** (batch t0), with two carve-outs from design review:
   it carries only the byte-identical duplicates (KAT constants ×20 files, `limits()` ×17,
   `frame()` ×17, `List<JsonObject>` selector helpers ×6) — **not** the 16 `engine()`/
   `readyEngine()` factories (they differ meaningfully in grants/reports/stores; one blended
   factory is how a grant leaks into a dispatch test and flips a −32601/1204 taxonomy) —
   and **the three pin files keep fully local helpers** (PLAN-rf2 §0.1 hermeticity:
   "a single file to keep green" is worth 60 duplicated lines).
4. **Adversarial review fleet after green** (§6), plus mutation spot-checks M1–M5 (§5).

Recorded deviations from the runbook letter: (a) `wire/build.gradle.kts`'s two dead
org.json dependency lines are deleted at C5, not C6 — with zero org.json imports in the
module, a live jar on the test classpath is exactly how a stray import compiles again
silently; the catalog entry and `:app`'s dep stay for C6. (b) One test is deleted, not
ported (§3.1), so parity becomes **353**.

## §1 Translation guide (desk reference; model file = `JsonAccessTest.kt`)

jvmTest is a friend compilation of jvmMain: all `internal` JsonAccess helpers
(`stringOrNull/wireIntOrNull/longOr/integralLongOrNull/objOrNull/arrOrNull/reqString/
reqLong/reqObj/reqArr/with/isIntegral/isNullOrAbsent/asStringOrNull/asDoubleOrNull/
boolOrNull/requestIdKey`) and `jsonValueEquals` are directly usable. Use them; never
re-derive coercion per file.

- **Builders**: `JSONObject().put(…)` chains → `buildJsonObject { put(…) }`;
  nested → `putJsonObject("app") { … }` / `putJsonArray("children") { add(x) }`;
  `JSONObject()` (empty) → `JsonObject(emptyMap())`;
  `JSONArray(listOf("a","b"))` → `JsonArray(listOf("a","b").map(::JsonPrimitive))`;
  receiver-lambda `trig(id, type, block: JSONObject.() -> Unit)` (5 trigger files) →
  `block: JsonObjectBuilder.() -> Unit` inside `buildJsonObject`;
  vararg `Pair<String, Any?>` builders (`node()` in SpecValidatorCompletenessTest,
  `toast()` in ToastTest) → `Pair<String, JsonElement>` (compiler turns call sites into
  the worklist).
- **THE INT-LITERAL RULE** (the one semantic hazard in builders): org.json re-spelled
  `put("x", 5000.0)` to `5000` on serialization; kotlinx writes `5000.0`. Every member a
  strict integer-spelled reader consumes (`revision`, `duration_s`, `protocol`, `ttl_s`,
  `at_ms`, `throttle_s`, ids, every `limits()` member) MUST be an Int/Long literal in a
  builder. A `.0` literal is permitted only where binary64 spelling IS the subject:
  SubstitutionTest (2.0/−7.0/0.0), TriggerTest canonicalEquals (60.0, 1.0, 2.0),
  JsonEqualityTest / EnvelopeIdTest equality pins (1.0), JsonAccessTest. Those pins GAIN
  teeth under kotlinx (org.json erased the spelling before it reached the code under
  test) — port the doubles verbatim. Reviewer grep:
  `grep -nE 'put\("[a-z_]+", -?[0-9_]+\.0\b'` — every hit must be on the exempt list.
- **Raw-text fixtures stay raw text, byte-verbatim**: all `feedRaw` bodies
  (PreSwapNumberTest), malformed-frame vectors (CompanionEngineTest:447-497,
  `"{ not json"`, `[]`, dup-keys, depth-65 probe), every `EbpJson.parse("""…""")`.
  Document fixtures parse leniently: `JSONObject(file.readText())` →
  `Json.parseToJsonElement(file.readText()) as JsonObject` (contract.json, manifest.json,
  golden lines). `EbpJson.parse` survives in tests ONLY where wire-strictness is the
  subject (EbpJsonTest, WireConformanceTest duplicate scan,
  PersistenceCompatTest.strictParserRejectsWhatTheStoreMustAccept).
- **`frame(msg)` = `encodeFrame(msg.toString())` survives** (kotlinx `toString()` IS
  production `wireSerialize`) — parameter type change only.
- **Typed id matching** (R2): `out.last { it.opt("id") == id }` →
  `out.last { it["id"] == JsonPrimitive(id) }`. `JsonPrimitive(7) == JsonPrimitive(7L)`
  holds; `JsonPrimitive("7")` differs (that distinction is itself under test).
  **Echo ids by element, never re-derive**: `respondTo`-style helpers replace
  `event.getInt("id")` with `put("id", event.getValue("id"))`. String-spelling of an
  integer id (EnvelopeIdTest): `JsonPrimitive(requestIdKey(event["id"])!!.toString())`.
  **Selector helpers throw when nothing matches** (`last {}`/`single {}`, never
  `lastOrNull`) — vacuity must be loud.
- **Reads** (reviewer rule of thumb):
  * engine-EMITTED members (error codes, counts, result revisions, ids it issued) →
    `reqObj/reqArr/reqString/reqLong` (expected literals gain `L`: `1201L`) or
    `wireIntOrNull`;
  * values passed THROUGH verbatim (capability args, store reloads, host objects) →
    `integralLongOrNull(obj[k])` — spelling is the fixture's business, the VALUE is the
    assertion's;
  * exact-echo identity → `JsonPrimitive`/`JsonNull` element equality;
  * `opt(k)` → `obj[k]`; `has` → `in`; `length()` → `.size`; `keySet()` → `.keys`;
    `(0 until a.length()).map { a.getString(it) }` → `a.map { it.asStringOrNull()!! }`;
    `getDouble` → `asDoubleOrNull()!!`; `getBoolean` → `boolOrNull(k)!!`.
- **`JSONObject.NULL` (22 sites), two meanings**: assert-emitted-null →
  `assertEquals(JsonNull, replay["blocked_by"])`; build-null-into-fixture →
  `put("value", JsonNull)` (never omit — omission now means absent).
- **Engine seams**: `dispatchAction(descriptor: JsonObject, hookValue: JsonElement?)`,
  `publishState(value: JsonElement?)` — scalars wrap in `JsonPrimitive(…)`; Substitution
  helper: `Substitution.apply(JsonPrimitive(s), …)!!.asStringOrNull()!!`.
- **Test-side `.content` policy** (= production grep-ban): tests read only through
  JsonAccess helpers, element casts + `.isString`, and element equality. kotlinx's
  coercing accessors (`.int`, `.long`, `.jsonPrimitive`, `.contentOrNull`) are banned —
  same hazard in a stdlib hat. Sole exemption: `JsonAccessTest.kt` (it pins the accessors
  themselves).
- Exception drift is benign: `req*` throw `NoSuchElementException` where `get*` threw
  `JSONException`; no test catches `JSONException` (verified).

## §2 Batches (staged commits; error ledger = `./gradlew :wire:compileTestKotlinJvm --console=plain 2>&1 | grep -c "^e: "`)

Per-file error sets are disjoint (all helpers file-private): a batch must zero exactly its
files' errors; movement elsewhere = regression, stop. Record baseline N before t0.

| Commit | Content | Est. |
|---|---|---|
| `C5.t0` | `TestSupport.kt` (KAT constants, `limits(vararg overrides)`, `frame()`, throwing selector helpers `replyTo/errorOf/events`) — new file, compiles green standalone | 0.5h |
| `C5.t1` | Unit files, idiom rehearsal: JsonEqualityTest, EbpJsonTest (incl. §3.1 deletion), SubstitutionTest, NodeTypeGateTest, ImageGuardsTest, NotificationActionTest (~590 ln) | 1h |
| `C5.t2` | Validator/store: SpecValidatorCompletenessTest, SpecLimitsTest, SurfaceStoreTest(+VocabularyDriftTest), ReminderBackingTest, TriggerBackingTest, ThemeTest, ToastTest (~1,650 ln) | 3.5h |
| `C5.t3` | Trigger family (the 5 `trig()` receiver-lambda files): TriggerTest, TriggerRuntimeTest, TriggerScheduleTest, FiringServiceTest, OnFireTest (~1,110 ln) | 2h |
| `C5.t4` | Engine conformance: CompanionEngineTest, CapabilityTest (§3.2), DialogTest, ActionEventTest, ReminderTest, PieMenuTest, BuiltinTest, DispatchFieldsTest, NotificationSurfaceTest (~2,220 ln) | 4h |
| `C5.t5` | Editor/queue/goldens: EditorTest, EditorLifecycleTest, EditorCommandTest, W6QueueTest (§3.5), WireConformanceTest (§3.3), WidgetsGoldenReplayTest (§3.4) (~2,000 ln) | 3h |
| `C5.t6` | **The pin files, last**: EnvelopeIdTest, PreSwapNumberTest, PersistenceCompatTest (~583 ln) — error count reaches 0 here; message records the FIRST `:wire:jvmTest` run's verbatim failure list with each failure's adjudicated class (§4) | 2h |
| `C5.tN`/`C5.fN` | Adjudication commits per finding (§4) — test-only vs jvmMain-only, never mixed | — |
| `RF-2b(C5)` | Build-file deletion, STATE ledger, mutation matrix + parity + scorecard record | 0.5h |

Pins go LAST deliberately: the idiom vocabulary is rehearsed across ~7,900 lines before
the highest-stakes 583; the pin diff is one small line-by-line-reviewable commit; when a
pin fails, bisection has exactly two suspects (the pin-conversion commit or C2–C4), not an
8,500-line blur. ToolbarEditsTest and JsonAccessTest: verify-only, no conversion.

## §3 Special items — exact treatment

1. **DELETE `EbpJsonTest.orgJsonProjectionPreservesTypesAndIds`** (EbpJsonTest.kt:119-129
   + the org.json import): its subject `EbpJson.toOrgJson` died at C2; equivalent-and-
   stronger coverage exists at JsonAccessTest.kt:132-165. Parity 354 → **353**; record in
   the t1 message.
2. **CapabilityTest.unserializableResultIsAnsweredNotDropped**: 60k-deep tree builds
   bottom-up (immutable trees): `var deep = JsonObject(emptyMap()); repeat(60_000) { deep =
   JsonObject(mapOf("n" to deep)) }`. The −32603/`internal-error` assertions are
   MUST-PORT-UNCHANGED (they pin R1's serializeReply StackOverflowError arm).
3. **WireConformanceTest**: delete the private `jsonEquals(Any?,Any?)` walker; compare via
   production `jsonValueEquals(messages[i], expected[i])` (kills a drifting test-local twin
   of SPEC 4.3 equality). `isValidRequestId` calls wrap args in `JsonPrimitive(…)`.
   Byte-exact encoder assertions (`encodeFrame(text)` vs committed `.bin`) stay — input is
   text, serializer-independent.
4. **WidgetsGoldenReplayTest**: replace the `user.dir` upward walk with the `ebp.dir`
   system property (already on the jvmTest task) — stops depending on JVM cwd.
5. **W6QueueTest.byteGateMeasuresWhatItEmits**: the re-serialization side becomes
   `Json.parseToJsonElement(body).toString()` — the SAME serializer as emit, or the
   size-agreement assertion loses its meaning. Byte-COUNT assertion shapes port verbatim.
6. **Three read-by-VALUE sites — `integralLongOrNull`, never `reqLong`** (a mechanical
   port here fails correct production code): PreSwapNumberTest:97 (stored `at_ms` 5000.0),
   PreSwapNumberTest:136 (pass-through capability arg `ms` 100.0),
   PersistenceCompatTest:183 (reloaded `at_ms`). Adjacent :195 `getDouble` →
   `asDoubleOrNull()!!`.
7. **The ONE pin whose meaning flips** — rewrite + rename
   `nonStringMethodClosesTheConnection` → `nonStringMethodIsInvalidRequestNotSilentClose`:
   feed `{"jsonrpc":"2.0","id":"m5","method":5,"params":{}}`; assert exactly one new
   frame, `error.code == -32600L`, id echoed as string `"m5"`, `data.kind ==
   "invalid-request"`, `engine.state == READY`. Expected values come from C2's recorded
   Envelope decision (Envelope.kt:55-63 comment), NOT from observing the code — that is
   what separates a re-pin from an update-to-pass. Template: CompanionEngineTest:450-458.
8. **PersistenceCompatTest (freeze variant, ratified)**: the four legacy-file pins
   (`queueRecordWithDeepArgsSurvivesRoundTrip`, `legacyPreSplitSurfacesFileMigratesItsDrafts`,
   `reminderWithIntegralDoubleAtMsLoadsAsLong`, `reminderWithFractionalAtMsIsPreservedVerbatim`)
   write hand-frozen org.json-SPELLED raw text via `file.writeText(…)` — integral doubles
   as integers (`"at_ms":5000`), fractional preserved (`1.5`), explicit `"value":null` —
   so the gate tests yesterday's file under tomorrow's parser. Deep queue fixture as text:
   `"""{"records":[{"event_id":"e1","queue_seq":7,…,"args":""" + """{"n":""".repeat(61) +
   `"""{"leaf":"bottom"}""" + "}".repeat(61) + …` (keys per FileQueueStore:
   records/next_seq/clock_high_water). `strictParserRejectsWhatTheStoreMustAccept` shares
   the frozen text (its `EbpJson.parse` rejection try-block MUST stay strict). Refinement:
   the queue test also does `replace()` + reload after the frozen load, keeping write-path
   deep-args coverage. `jsonDepth` recurses over `JsonElement`; `deepArgs` builds bottom-up.
   Raw-byte assertions (`raw.contains("\"value\":null")`, not `"\"null\""`) stay verbatim.
9. **In-suite pins, meaning-unchanged** (they gain teeth): SubstitutionTest keeps its
   doubles; TriggerTest.canonicalEqualsIgnoresNumberSpelling keeps `60` vs `60.0` spellings
   (a port that normalizes both sides tests nothing); DialogTest rpc.cancel pin matches ids
   by element equality (`JsonPrimitive(7)`), never via `jsonValueEquals` (C4-hub hazard 3);
   EnvelopeIdTest type assertions translate, not drop: `intId is Int || is Long` →
   `assertNotNull(requestIdKey(event["id"]))`; echo-type via
   `(reply["id"] as JsonPrimitive).isString` / negation;
   `jsonValueEquals(1, 1.0)` → `jsonValueEquals(JsonPrimitive(1), JsonPrimitive(1.0))`.

## §4 First pin run + adjudication protocol

Precondition: error count 0 AND `git diff 459458e -- companion/wire/src/jvmMain/` empty.

```bash
./gradlew :wire:jvmTest --console=plain --continue --rerun-tasks
```

Per failure, classify IN ORDER (no fix before classification):
- **Q1 — the one deliberate flip?** Only §3.7 qualifies. Any OTHER test "fixed" by
  changing expected values is never Q1.
- **Q2 — test-port defect?** Diff against `git show 459458e:<path>`. Known shapes:
  vacuous selector predicates (`it["id"] == "p1"` compares JsonElement to String — always
  false), dropped type-identity assertions, normalized fixture spellings, exception-type
  drift. Fix in a test-only `C5.tN` commit.
- **Q3 — real production regression from C2–C4?** The pins' whole purpose. Fix jvmMain in
  its own `C5.fN` commit citing pin + originating commit
  (`RF-2b(C5.f1): <symptom> — regression from C4.p2 (7e2aa01); pin W6QueueTest.byteGate…`).
  First resort is the scope map: id-spine/dialog-id pins → C4.p1 `1523a2b`; byte-gate/
  serializeReply → C4.p2 `7e2aa01` (+p3 `f93fa14` for event-build measures); accumulation/
  capture → C4.p3; draft/publishState null seams → C4.p4 `7ec98dc`; handler-body
  ttl_s/at_ms reads → C4.p5 `459458e`; persistence/stores → C3 `2ece3b2`; equality/envelope
  taxonomy → C2 `a8d5db1`. When the map doesn't resolve: overlay-bisect —
  `git worktree add ../c5-bisect <suspect>`, `git checkout <C5-tip> -- companion/wire/src/jvmTest`,
  run the one failing test; a compile failure there means the API predates the final shape
  → treat as `bisect skip` and close the gap by reading `git log -L :<function>:<file>
  1523a2b..459458e`. Remove the bisect worktree after.
- **Ambiguity rule**: if both Q2 and Q3, split — fix the test first so it fails for the
  production reason alone, then land the production fix. Never one commit touching both
  source sets.

## §5 Vacuous-pass detection (mandatory before declaring green)

Static detectors (tree-wide over jvmTest):
```bash
grep -rnE '\["[A-Za-z_]+"\] *[=!]= *("|[0-9-]|true|false)' companion/wire/src/jvmTest/  # JsonElement vs raw literal
grep -rnE 'lastOrNull|firstOrNull|singleOrNull|\.none *\{' companion/wire/src/jvmTest/   # silent-when-vacuous; each hit needs a positive control
grep -rn '\.content' companion/wire/src/jvmTest/        # only JsonAccessTest may hit
grep -rn 'parseToJsonElement' companion/wire/src/jvmTest/  # fixtures/persistence only, never strictness stand-ins
```

Mutation matrix — working-tree-only reverts of known C2–C4 semantics; each must go
red-then-green (`git restore` between; final `git diff 459458e -- …jvmMain/` shows only
`C5.fN` fixes, no residue). Run all five:

| # | Mutation | Must go red |
|---|---|---|
| M1 | JsonAccess `requestIdKey`: drop `!it.isString &&` | EnvelopeIdTest.responseIdString…, JsonAccessTest |
| M2 | CompanionEngine ttl_s (:496) and at_ms (:1317): `integralLongOrNull` → `wireIntOrNull` | PreSwapNumberTest ttl_s + at_ms pins |
| M3 | Envelope.classifyMessage: drop the non-string-method null return | the re-pinned §3.7 test |
| M4 | CompanionEngine emit: `wireSerialize(msg) + " "` (emit diverges from measure by one octet) | W6QueueTest.byteGateMeasuresWhatItEmits |
| M5 | JsonEquality number arm: compare `content` strings instead of by double value | JsonEqualityTest, TriggerTest.canonicalEquals…, EnvelopeIdTest.idEquality… |

A mutation that stays green = a vacuous port: stop, fix the test, re-run.

## §6 Adversarial review fleet (after green)

One defect class, verbatim to reviewers: **"the ported test asserts less than the
original."** Ground truth: `git show 459458e:companion/wire/src/jvmTest/…/<file>`.
Allowances: exactly one flip (§3.7) and one deletion (§3.1); anything else that changed an
expected value, dropped an assert line, or relaxed a reader is a finding.

- **Full adversarial reads (9 files)**: PersistenceCompatTest, PreSwapNumberTest,
  EnvelopeIdTest, SubstitutionTest, TriggerTest, W6QueueTest (whole byte-accounting suite),
  DialogTest, JsonEqualityTest, CapabilityTest. Per-file checklist: (a) every old assertion
  line has a counterpart or written justification; (b) every negative assertion keeps its
  positive control, same order; (c) every fixture number keeps its SPELLING; (d) every
  strict/lenient reader choice matches the original's teeth; (e) selector helpers throw.
- **Sampled reads (other 29)**, mechanically prioritized first:
  `git diff --numstat 459458e..HEAD -- …jvmTest/` (net-shrink files = dropped-line
  candidates); assertion census per file old-vs-new
  (`git show 459458e:$f | grep -cE 'assert|fail\('` vs current — may not drop except
  EbpJsonTest −5); `@Test` census (only EbpJsonTest 8→7). Flagged files get full reads;
  others 3 sampled tests biased toward id/null/number/type/bytes names.
- **Completeness critic** (tree-wide): `grep -rn "^import org\.json" companion/wire/src`
  empty (both source sets); `grep -rnE 'JSONObject|JSONArray|JSONException'` hits are
  comment-only (pin files legitimately keep org.json PROSE — their headers explain the old
  spelling behavior); the §5 static detectors; the kotlinx coercing-accessor import ban
  (`import kotlinx.serialization.json.(int|long|jsonPrimitive|contentOrNull…)` — none).
- Disposition: findings re-enter §4's tree (mostly Q2 → `C5.tN`). A Q3 found HERE means a
  pin was vacuous AND the mutation matrix missed it — record loudly. The finding count is
  the second half of the C4-fleet-skip scorecard (C4 skipped its fleet because this run is
  the acceptance; the ledger records what the pins caught vs what the review caught).

## §7 Parity, build change, exit checklist, ledger

**Parity**: expected **39 suites / 353 tests** (354 at P0 − the §3.1 deletion). Below 353 =
something silently dropped; above = unplanned addition; either way stop and account.
Command (output goes in the final commit message):
```bash
./gradlew :wire:jvmTest --console=plain --rerun-tasks && \
  echo "$(ls wire/build/test-results/jvmTest/TEST-*.xml | wc -l) suites / \
$(grep -ho '<testcase' wire/build/test-results/jvmTest/TEST-*.xml | wc -l) tests"
```

**Build change (final commit)**: delete `compileOnly(libs.json)` (jvmMain, dead since C4)
and `implementation(libs.json)` (jvmTest) from `wire/build.gradle.kts` + the stale
org.json comment block. Catalog entry + `:app`'s dep stay until C6.

**Exit checklist**:
1. `:wire:jvmTest` green — **G-wire, first time since C2**; parity 39/353 recorded.
2. `python3 ebp/validate.py` green (G-spec); `git status --short ebp/` empty (I1).
3. Import/identifier/content/accessor greps per §6 critic — clean.
4. Mutation matrix M1–M5 red-then-green; no mutation residue in jvmMain diff.
5. Review fleet complete; findings adjudicated and landed.
6. G-elisp spot-check green (unaffected); **G-app still red by design until C6** — record,
   don't gate.
7. Optional (user action — pushes are the user's): push rf-2b + open/refresh a draft PR so
   CI's wire job runs green on the tip (rf-2b isn't `slop-fork/**`, so push CI won't fire
   otherwise); the PR's red app job is sanctioned until C6.
8. STATE ledger: replace PLAN-rf2 §0's `C5–C6` row (on rf-2b's copy) with a C5 DONE row
   recording: parity 39/353 (−1 documented), the one flipped pin, the frozen upgrade-gate
   fixtures, first-pin-run failure count adjudicated as ⟨k⟩ Q2 / ⟨m⟩ Q3 / 1 Q1, the
   mutation matrix result, the review finding count, and the **C4-fleet-skip scorecard**
   ("the pins caught ⟨m⟩ real regressions; the review caught ⟨j⟩ the pins missed") — fill
   every ⟨⟩ with measured numbers, zeros included. Then `C6 | :app | OPEN`.
   Final commit labeled `RF-2b(C5)`.

## Verification (end-to-end)

The checkpoint is self-verifying by construction: the 23 pins + 331 legacy tests ARE the
verification of C2–C4, and §5's mutation matrix verifies the pins themselves still bite.
Full sequence: error-ledger descent t0→t6 → first pin run + adjudication (§4) → mutation
matrix (§5) → review fleet (§6) → exit checklist (§7). Every gate command is listed above
and runs from `$WT/companion` (Gradle) or `$WT` (validate.py, run-tests.sh).

## Critical files

- `companion/wire/src/jvmTest/kotlin/com/calebc42/ebp/wire/` — all 38 files (36 converted,
  2 verify-only); new `TestSupport.kt`
- `companion/wire/src/jvmMain/…/JsonAccess.kt` — reader idioms + mutation targets M1
- `companion/wire/src/jvmMain/…/CompanionEngine.kt` (:496 ttl_s, :1317 at_ms, :2474 emit,
  :2479 wireSerialize) — mutation targets M2/M4 and the Q3 fix surface
- `companion/wire/src/jvmMain/…/Envelope.kt` — M3; the C2 flip rationale quoted in §3.7
- `companion/wire/build.gradle.kts` — dependency deletion
- `docs/PLAN-rf2-kmp-migration.md` — §0 STATE ledger row (rf-2b copy)
- Reference (read-only): `JsonAccessTest.kt` (style model), PLAN-rf2-c4-hub.md (hazard
  list), the five C4 commits `1523a2b`/`7e2aa01`/`f93fa14`/`7ec98dc`/`459458e` (Q3 scope map)
