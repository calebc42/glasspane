# PLAN — RF-2b checkpoint C4: `CompanionEngine.kt` to kotlinx

**Purpose.** Execution plan for the hub checkpoint of the org.json →
kotlinx.serialization conversion. This is the expansion of
[PLAN-rf2-kmp-migration.md](PLAN-rf2-kmp-migration.md) §2.5's one-line "C4 the hub"
entry; §2.3 (translation table), §2.4 (R1–R6) and §0.1 (P0 as executed) remain the
governing references. Branch: `rf-2b`.

## §0 Context — why this checkpoint is different

C2 landed the core four (`EbpJson`, `FrameCodec`, `Envelope`, `JsonEquality`,
commit `a8d5db1`); C3 landed 17 validators and stores (`2ece3b2`). Both gated on
*compilation scope*, and both held exactly: after C3 **all 68 remaining errors are
in `CompanionEngine.kt`**, the only file left in `companion/wire/src/jvmMain`
importing org.json.

C4 converts that file — 2,292 lines — and it is the riskiest step in RF-2b:

1. **Five of the six redesigns converge here.** R1, R2, R3, R4 and R6 all land in
   one file; C3's files each carried one or two. (R5 landed with `JsonEquality` in
   C2.)
2. **The P0 pins are dark.** The test source set stays org.json until C5, so the 23
   pin tests written specifically to catch this conversion's semantic drift cannot
   run for the whole of C4 (recorded in PLAN-rf2 §0.1). The compiler is the only
   automated check this checkpoint has.

Two decisions follow from (2), both ratified 2026-07-31:

- **C4 lands as five staged sub-commits, not one.** Red mid-branch is sanctioned by
  the runbook's ground rules ("the branch is the workspace, the merge is gated"),
  and staged commits give bisect points if C5's pin run surfaces a regression in a
  2,300-line diff.
- **No adversarial review fleet this checkpoint.** C5's pin run is the acceptance
  harness. (C3 used a review fleet and it found five real findings; the tradeoff
  here is deliberate, not an oversight.)

## §1 The five passes

Ordering rule from §2.5: **R2 then R1 first**, so the dispatch path is settled
before the long tail. Each pass ends in a commit that records its error count; the
count must fall monotonically.

### Pass 1 — R2, the id spine

The one true bug site is `:212` — `(msg.opt("id") as? Int)?.let(pending::remove)`.
`requestIdKey()` already exists in `JsonAccess.kt` (isString-guarded, pinned by
`JsonAccessTest`) and is exactly what it becomes.

| Site | Change |
|---|---|
| `:225`, `:226` | `nextOutboundId: Int` → `Long`; `pending: HashMap<Int, (JSONObject?, JSONObject?) -> Unit>` → `HashMap<Long, (JsonObject?, JsonObject?) -> Unit>` |
| `:211-215` | RESPONSE arm → `requestIdKey(msg["id"])?.let(pending::remove)`; result/error via `msg["result"] as? JsonObject` |
| `:505` + 12 handlers (`600, 707, 936, 1162, 1300, 1360, 1555, 1558, 1665, 1893, 2023, 2058`) | `id: Any` → `id: JsonElement` |
| `:2237`, `:2270` | `respondResult`/`respondError` take `id: JsonElement` |
| `:1882` | `dialogs: LinkedHashMap<String, Any>` → `<String, JsonElement>` (written `:1956`, read `:1986`/`:2012`) |
| `:595`, `:598` | `replayId: Any?` → `JsonElement?`; `blockedBy: Any = JSONObject.NULL` → `JsonElement = JsonNull` |
| `:166-173`, `:260-262` | `close()`'s pending drain and `sendRequest`'s synthetic 1401 rebuild as `buildJsonObject` |

**Inbound ids echo verbatim** — a string id stays a string, an integer stays an
integer. Seven `sendRequest` call sites retype their `(result, error)` lambdas:
`:327`, `:351`, `:469`, `:641` (the pump — the only `bounded = false` caller),
`:1133`, `:1539`, and the dense `requestCompletion` callback at `:1705-1734`.

### Pass 2 — R1 and the single `wireSerialize`

- **`serializeReply` (`:2258-2268`) keeps both catch arms.** kotlinx *throws* where
  org.json returned null from `toString()`, and a deep host-supplied result can
  still overflow the stack. SPEC 7.1's "MUST NOT leave the request unanswered" is
  the whole reason this funnel exists.
- `respondResult` (`:2237-2256`) builds via `buildJsonObject`; `respondError`
  delegates to `Envelope.errorResponse`, which already retired the
  `data.put("kind", …)` write-through in C2.
- `emitFramingError` (`:2283`) carries `JsonNull` as its id.
- **One `wireSerialize(JsonElement): String`, used by `emit` (`:2288`) *and* every
  measuring site, in the same commit**: `:325`, `:349`, `:431`, `:1537`, `:1997`
  (the dialog-overflow pre-check), `:2225` and `:2228` (`checkLimits`' prospective
  welcome). This is §2.3's explicit rule and
  `W6QueueTest.byteGateMeasuresWhatItEmits` is its pin.
- `Any?.utf8Len()` (`:2290`) retypes; callers read client name/version at
  `:2036-2037`.

### Pass 3 — R3/R4, accumulation and deep copies

- Delete the three `JSONObject(x.toString())` deep copies (`:306`, `:394`, `:1105`)
  → `descriptor.objOrNull("args") ?: JsonObject(emptyMap())`. Immutable trees share
  safely.
- Args/fields accumulation becomes single `buildJsonObject` merges:
  `dispatchDialogAction` (`:306-322`), `dispatchAction` (`:394-421`),
  `selectPieMenu` (`:1105`).
- The capture snapshot (`:317-322`) writes `JsonNull` deliberately — an uncaptured
  field *is* a JSON null, not an absent member.

### Pass 4 — R6, the `Any?` seams

These are the public signatures `:app` consumes, so this pass defines the C6
boundary: `hookValue: Any?` (`:301`, `:376`), `publishState(value: Any?)` (`:485`),
`completeDialogSubmit(value: Any?)` (`:1984`), `surfaceRevision(value: Any?)`
(`:700`) → `JsonElement?`. Remaining `JSONObject.NULL` → `JsonNull` (`:320`,
`:415`, `:502`, `:571`, `:607`). Kotlin null means JSON null at these seams.

### Pass 5 — the tail, then the imports

Remaining handler-body param reads via the `JsonAccess` helpers; `CompanionConfig`'s
public `surfaceProfiles`/`limits`/`deviceReport` (`:20`, `:22`, `:26`) →
`JsonObject`; delete `import org.json.JSONArray` / `JSONObject` (`:8-9`).

## §2 Hazards to hold

These compile cleanly and are wrong — the class of defect C3's review pass caught
five times:

1. **Dropped immutable result.** A `.with()`/`.without()`/`buildJsonObject` whose
   value is computed and not assigned back is a silent no-op. Grep the diff for
   every `.with(` / `.without(` and confirm each result is used.
2. **`put(k, null)` changed meaning.** org.json *removed* the member; kotlinx writes
   `JsonNull`. The existing `if (hookValue != null)` / `if (value != null)` guards
   must survive **as guards**, not collapse into unconditional null writes.
3. **Dialog id equality stays typed.** `rpc.cancel`'s lookup (`:984`) uses
   `JsonElement` data-class equality so `5` ≠ `"5"`. Do **not** route it through
   `jsonValueEquals` — that layer compares numbers by value, which is right for
   SPEC 4.3 equality and wrong for id matching. `EnvelopeIdTest` pins the
   distinction.
4. **Measure must equal emit** — one `wireSerialize`, migrated with `emit` in the
   same commit.
5. **`isNull` → `isNullOrAbsent`**, preserving org.json's absent-counts-as-null
   reading rather than "fixing" it.

## §3 What C4 deliberately leaves red

- **`:wire` jvmTest** — still org.json; converts at C5, where the 23 P0 pins light
  up and become the acceptance harness.
- **`:app`** — 17 files, roughly 300 org.json references (`render/LayoutNodes.kt`
  68, `render/Renderer.kt` 45, `render/InputNodes.kt` 33, `DeviceBridge.kt` 30);
  converts at C6. `AppCapabilities.kt`'s `args.getLong("ms")` is already flagged in
  the C3 commit: its truncation is what makes
  `PreSwapNumberTest.integralDoubleCapabilityArgReachesTheHandler` pass on the
  device, so it needs `integralLongOrNull`, not a naive port.

## §4 Verification

C4's gate is §2.5's, and it is **compile-scope only** — stated plainly because no
test can run at this checkpoint:

```bash
cd companion && ./gradlew :wire:compileKotlinJvm --console=plain 2>&1 | grep -c "^e: "
```

must be **0**, and org.json must survive in `wire/src/jvmMain` only inside comments
that describe the old mechanism (C2 and C3 left several deliberately):

```bash
grep -rn "^import org.json" companion/wire/src/jvmMain/
```

must be empty.

Per pass: record the error count in the commit message so the descent is legible.
After Pass 5: update PLAN-rf2 §0 STATE with checkpoint C4 and label the final commit
`RF-2b(C4)`. G-spec and G-elisp are unaffected by this work and can be spot-checked;
`:wire:jvmTest` (G-wire) and `:app` (G-app) stay red by design until C5 and C6.
