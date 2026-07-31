# PLAN — Amendment package for the refound plan + SPEC (2026-07-31)

**Purpose.** Execution plan for three (four-file) deliverables that correct
`PLAN-refound-2026-07-28.md` in place and draft the SPEC amendments its audit surfaced.
A fresh session should read §0, then start at the first non-DONE item.

**Provenance:**

| Source | What it holds |
|---|---|
| Session 2026-07-31 (Opus 5 authoring, Fable 5 verification) | The adversarial review: 3 external verification agents (Emacs 30.1 source @ tag, web ecosystem, room3 clone @ `d69c96e`), 1 SPEC adversary, 1 sequencing adversary |
| `docs/REVIEW-poc-v1-vs-rewrite-2026-07-27.md` §4 | The three orphaned regressions this package puts on a rung |
| `docs/AUDIT-spec-holes-2026-07-24.md` | The prior spec-hole pass; this package must not duplicate it |
| SPEC §25 / `ebp/README.md` | Amendment process — "No entry, no amendment"; ratification is Caleb's |
| `/home/calebc42/pkb/resources/android/androidx/room3` | Local Room 3 / androidx.sqlite clone (Caleb, 2026-07-31) |

**Method note.** Emacs claims judged at the `emacs-30.1` tag. Kotlin claims judged against
the local `androidx` clone, not release notes. Every anchor in this plan was re-verified by
hand on 2026-07-31 (see §0.1) — the package's own thesis is that stated enforcement outruns
actual enforcement, so it does not get to assert unverified anchors.

---

## §0 STATE — execution ledger (update at every checkpoint)

| # | Item | Status |
|---|---|---|
| V | Anchor + claim verification pass | **DONE 2026-07-31** — see §0.1 |
| D1 | `docs/AUDIT-plan-spec-adversarial-2026-07-31.md` | **DONE 2026-07-31** |
| D2 | Amendments to `docs/PLAN-refound-2026-07-28.md` (+ `PLAN-rf2` ledger edits) | **DONE 2026-07-31** |
| D3 | `docs/DRAFT-amendments-140-152.md` | OPEN — blocked on D1 |
| D4 | `docs/LIBRARY-LEDGER.md` | OPEN — the enforcement point for the library-adoption rule |

**Scope wall.** Ratifying amendments into `ebp/SPEC.md` is **out of scope**. `git status
--short ebp/` MUST stay empty for this entire package — the submodule is pinned at
`06fd9cd` and nothing here may move it.

**Baseline at write time (verified):** branch `slop-fork/main`, HEAD `0fab0d5`, working tree
clean except 5 untracked `docs/lookup-tables/*.org`; `ebp` submodule `06fd9cd`, clean;
`SPEC-CHANGES.md` highest amendment **#139**.

### §0.1 Verification pass (Fable 5, 2026-07-31)

Every load-bearing claim re-checked against source. **All verified**, with four corrections:

| Claim | Result |
|---|---|
| PLAN-refound anchors (`:10-14`, `:36-44`, `:51`, `:81`, I1 `:83`, I4 `:93`, I6 `:98`, I8 `:114`, RF-0 `:124`, RF-1 `:140`, gate `:158`, RF-4 `:232`, RF-5 `:310`, 5b `:315`, priority `:319`, non-goals `:338`) | ✅ all resolve; file is 356 lines |
| Generation-swap paragraph to strike | ⚠️ **CORRECTION — it is `:267-276`, not `:266-276`; the fsync/atomic-rename sentence is `:268-270`, not `:270-272`** |
| `SPEC.md:247` `max_frame_bytes` MUST equal `4194304` | ✅ |
| `SPEC.md:383-385` supersession + (per #77) MUST continue to accept connections | ✅ |
| `SPEC.md:427-432` §5.3 `offline.wake` — coalesce, ≤1/60 s, stop after 10 s, "not background-execution privileges" | ✅ |
| `SPEC.md:4287-4290` conformance compares body **semantically**, MUST NOT require member order/escaping | ✅ — this is what makes I1's byte-drift point correct |
| `NodeSupport.kt:34` advertises `table` | ✅ — the spike's carrier is real |
| `CapabilityCatalog.kt:50` `VALIDATED` set; `:58` "A cap outside VALIDATED throws" | ✅ — closed set confirmed; a `jetpacs.*` capability is impossible pre-RF-3 |
| 5 `:wire` jvmTest suites resolve fixtures via `ebp.dir` | ✅ — the wire job is the real cross-repo binding, not the spec job |
| `test/ebp-wire-test.el:331` `ebp-test--start-companion` is elisp-scripted | ✅ — there is no elisp↔Kotlin harness |
| `RoomConnectionManager.kt:81` calls the no-flags `delegate.open(resolvedFileName)` | ✅ |
| `RoomConnectionManager.kt:70-73` `ExclusiveMutex(… useFileLock = …)` | ✅ — file lock confirmed |
| `BundledSQLiteDriver.kt:84` `open(fileName)`, **`:95` `open(fileName, @OpenFlag flags)`** | ✅ |
| `BundledSQLite.kt:26` `SQLITE_OPEN_READONLY`, `:35` `SQLITE_OPEN_URI` | ✅ |
| vulpea delete+reinsert and DB-file deletion | ✅ but ⚠️ **CORRECTION — these live in the ELPA install, not the repo: `/home/calebc42/.emacs.d/elpa/vulpea-20260714.543/vulpea-db-extract.el:1465` and `…/vulpea-db.el:341`. Citations MUST be version-qualified absolute paths** (the checkout at `~/pkb/resources/emacs/vulpea` is outdated and would mislead a reader) |
| `jetpacs-theme.el:471` explicit ungranted branch | ✅ `((not (jetpacs-granted-p "theme")) (message …))` — the new gate must not change this taxonomy |
| `MainActivity.kt:51` builds `DeviceBridge` closing over Activity state (`currentSpec`) and `this` for Toasts; manifest declares no `configChanges` | ✅ — rotation defect confirmed |
| No method→capability table exists in `ebp.el` | ✅ zero matches — the gate needs new structure |
| No upstream on `$POC` or `$POC/ebp`; `origin` exists | ✅ — RF-1 is technically blocked on RF-0 |
| `offline.wake` absent from `supportedCapabilities` | ✅ `DeviceBridge.kt:111-113` lists 9 caps, not it |
| PLAN-rf2 `:5`, `:27`, `:39`, `:57`, `:258` | ✅ all resolve |

**Two further corrections found during verification:**
- ⚠️ The approved plan said "three documents" but also introduces `LIBRARY-LEDGER.md` →
  **four files**. Ledger above corrected.
- ⚠️ `PLAN-rf2-kmp-migration.md:5` carries a **broken relative link** to PLAN-refound
  (`../../pkb/projects/jetpacs/jetpacs/llm-poc-2/docs/…`, which resolves outside the repo).
  Fix it in the D2 commit since that file is being edited anyway.

---

## The thesis (both deliverables carry it)

**Stated enforcement outruns actual enforcement.** Three independent instances: I1 reads
"goldens byte-identical" while no Kotlin test compares serialized bytes and SPEC.md:4287-4290
*mandates* semantic comparison; `check_spec_sync` is described as binding prose↔contract but
covers 2 of 31 contract registries; §9.1's keystore MUST is unconvictable by a
wire-and-golden regime.

**Secondary, for the SPEC half:** amendments that close a symptom and deepen the structure
underneath — #81 → the clock ratchet, #107 → surface-ID exhaustion, #77/#79 → an unbounded
pre-auth surface.

---

## D1 — `docs/AUDIT-plan-spec-adversarial-2026-07-31.md`

Format per `AUDIT-spec-holes-2026-07-24.md` / `AUDIT-ja6-2026-07-28.md`: H1; unheaded
preamble with bold `**Target:**` / `**Run:**` / `**Scope:**`; bold count line; one-line
`Severity:` definition; `## Status & method`; `## The thesis`; tier H2s most-severe-first;
findings as `### P1-1 · Title` + metadata line + *Claim. / Reproduction. / Fix.*;
`## SPEC-amendment candidates (13)`; `## Refuted / re-characterised`;
`## Appendix — unverified tail`; `## What this review did NOT cover`.

Restate the standing house rule in Status & method: **a dead verifier is never counted as a
refutation**, and label every finding hand-verified-in-text vs agent-reported lead.

### Plan-half findings

| # | Sev | Finding | Anchors |
|---|---|---|---|
| 1 | P1 | RF-4a generation-swap unsound: a read-only open does **not** skip locking (only `immutable=1` does); a WAL artifact needs sidecars or `immutable=1`; the artifact must be checkpointed, `journal_mode=DELETE`, sidecar-free | sqlite.org/uri.html, wal.html §5; `PLAN-refound:267-276` |
| 2 | P1 | RF-4a producer gap: Emacs **cannot** durably publish. `sqlite-open` hardcodes `CREATE\|READWRITE`; URI unreachable (`expand-file-name` prepends `default-directory` to `file:…`); no directory-fsync primitive; `write-region-inhibit-fsync` defaults `t`. The paragraph is a spec-shaped promise the only extant producer cannot keep | `emacs-30.1:src/sqlite.c`; `fileio.c:5579,:6844`; `PLAN-refound:268-270` |
| 3 | P1 | RF-4b change capture collides with vulpea: delete-all-rows-per-file + re-INSERT with FK cascades; a schema-epoch bump **deletes the DB file**, annihilating any in-DB changelog | `…/elpa/vulpea-20260714.543/vulpea-db-extract.el:1465`; `…/vulpea-db.el:341,675,176-198`; confirmed at app level in `jetpacs-orgseq-model.el` header |
| 4 | P1 | Three orphaned regressions on no rung. **Sharper form:** `EbpApplication.onCreate` already does process-lifetime bootstrap for triggers/alarms and omits only the socket → triggers survive a cold start from an alarm; the socket does not | manifest (no `<service>`); `DeviceBridge.kt:166,171,179`; `MainActivity.kt:78`; `EbpApplication.kt:14-33`; `ebp.el:1142,1798,1941,1959`; `device/init.el:165-181,209-211` |
| 5 | P1 | **RF-1 is blocked on RF-0 technically** — no upstream on either repo, so Actions has nothing to check out and `actions/checkout` cannot fetch an unpushed submodule SHA | verified: `git rev-parse @{u}` fails on both |
| 6 | P1 | Room 3 cannot serve the *schema-generic* layer (codegen-only `createOpenDelegate`; identity-hash **mutates** any DB handed to it; no-flags open + PRAGMA writes + `ExclusiveMutex`; compile-time migration ladder) — while RF-4c's own prose already says "androidx.sqlite driver-level, zero @Entity" → the module is **misnamed** | `RoomDatabase.android.kt:302-306`; `RoomConnectionManager.kt:81,70-73,113-155` |
| 7 | P1 | **No elisp↔Kotlin loopback harness exists**, yet RF-3's gate (2), RF-4's gate, and a cross-implementation CI job all assume one | `test/ebp-wire-test.el:331`; `PLAN-refound:225,299-302` |
| 8 | P2 | Activity-recreation defect: `DeviceBridge` is built per `onCreate`, closing over Activity state, and no `android:configChanges` is declared → rotation builds a second bridge that loses the bind race while the first still owns the socket and pushes into a destroyed Activity's flows | manifest `:27` (no `configChanges`); `MainActivity.kt:51-60`; `DeviceBridge.kt:172-181` |
| 9 | P2 | Reconnection × §5.2 supersession **livelock**: newest-wins + auto-reconnect on both endpoints and two Emacsen (device + workstation over `adb forward`, a documented configuration) oscillate forever, each cycle running a full §10.3 barrier including `queue.replay`. §5.2 defines **no supersession signal** — the loser sees a bare close, indistinguishable from a crash | `SPEC.md:383-385`; `DeviceBridge.kt:186-187`; `ONBOARDING-device.md` |
| 10 | P2 | `offline.wake` — SPEC §5.3's sanctioned "get Emacs back" mechanism — is declared in `:wire` but **not advertised**; three overlapping mechanisms (FGS / reconnect / wake) exist and the plan names two | `DeviceBridge.kt:111-113`; `SPEC.md:427-432` |
| 11 | P2 | RF-2 ahead of RF-1 contradicts the plan's own rationale; the runbook's ledger records skipped pin tests and skipped sub-step branches — the "demonstrated-once" mode reproduced by the plan that diagnosed it | `PLAN-rf2:39,:57-62` |
| 12 | P2 | I1 reads stronger than enforced, and **contradicts itself across documents**: `PLAN-refound:83` says byte-identical, `PLAN-rf2:27` says explicitly not output-byte identity; SPEC mandates semantic comparison so byte drift is legal and undetected in exactly the step most likely to cause it | `PLAN-refound:83`; `PLAN-rf2:11,:27`; `SPEC.md:4287-4290` |
| 13 | P2 | RF-5b's gate cannot pass: "queue → **force-stop** → delivery" is precisely what WorkManager does not survive | `PLAN-refound:315` |
| 14 | P2 | `ebp.data` needs a canonical string encoding for integers > 2^53 (§4.2 caps at ±(2^53−1) with a hard Parse Error; SQLite `INTEGER` is 64-bit) | `SPEC.md:141` |
| 15 | P3 | `check_spec_sync` covers 2 registries of **31** contract top-level keys. **Correction to record:** it *is* bidirectional and its §11 half compares three fields (existence, sender via `SENDER_MAP`, class) — the finding is coverage, not direction | `validate.py:94-133` |
| 16 | P3 | cr-sqlite dormant (last push 2024-10, last release 2024-01, pre-1.0) — a frozen design reference, not a living upstream | vlcn-io/cr-sqlite |
| 17 | P3 | `sqlite-load-extension`'s allowlist is **filename-based**, not content-based, and the DEFUN is `#if HAVE_LOAD_EXTENSION` (possibly absent on Android builds) — the conclusion holds *harder* than the plan's argument | `emacs-30.1:src/sqlite.c` |

**Verified-positive — record these; negative results matter.** Room 3 exactly as ratified
(`androidx.room3`, JS/WasmJS genuinely declared in-source for room3-runtime/common and
sqlite/sqlite-async, driver-backed, Room 2.x in maintenance); SQLDelight still lacks wasmJs;
**`BundledSQLiteDriver.kt:95 open(fileName, flags)` with public `SQLITE_OPEN_READONLY`/
`SQLITE_OPEN_URI`, bundling SQLite 3.50.1** — the Android *reader* half of the snapshot
design was implementable; full 30.1 sqlite API present; `track-changes.el` present (v1.2,
eglot-driven); JCS-vs-i64 sound at the wire; at-least-once + receiver-dedup windows line up
with margin; §21 trigger durability honestly scoped.

**Re-characterised.** §9.1 keystore (#78→#95) was **not** arbitrary narrowing — #95 narrowed
because Emacs 30.1 exposes no keystore interface from Lisp. Residual finding: the symmetric
secret's weaker copy is unprotected *by construction*, the escape hatch (`SPEC.md:780-781`)
is self-certified and unfalsifiable, its compensating duty has no defined observable, and
nothing in §24.6 can convict it. §9.1-rate-limiter vs §23.5 is **not** a contradiction —
§23.5 is scoped to state keyed by unvalidated *method names*; coverage gap only.

### SPEC-half findings

Hand-verified in text: §15.2 clock ratchet (L1909-1919); §13.1 surface-ID exhaustion
(L1288-1308; no release method exists); §4.5 limits arithmetic (L245-260 vs L295-302 —
64 × 65536 ≫ 262144); §15.3 paused-head dedupe (L1941-1943, L1985; §15.2's in-flight
carve-out at L1927-1928 does not cover a paused head); §14.1/§15.2 dedupe key space (L1542
vs L1925-1927, plus the spec's own contradictory namespaced-vs-bare examples); §16.4 vs
§17.4/§17.2 accessibility defendant (L2084); §9.3/§23.6/§5.2 loopback threat model
(L945-962, L374-378, L386-387).

Appendix leads (agent-reported, not hand-verified): supersession welcome-snapshot mutability
+ no floor absorption on `stale` (L1349); pre-auth bound with no eviction/fairness/aging
rule (L386-387); rate-limit state keyed on peer-chosen pairing IDs (L819); revision-space
exhaustion (L141).

---

## D2 — amendments to `docs/PLAN-refound-2026-07-28.md`

House convention: **edit in place, no changelog section.** Status cells rewritten with an
inline `(ratified <date>)` note and a cross-doc link; new items appended into existing
numbered lists; the rationale lives in the **commit message**; deviations recorded on
**both** sides (child runbook + parent ladder row).

### D2.1 The producer decision — the largest content change

**Adopt: the Companion materializes its own database from inline changesets. Ship inline
changesets only; do not specify a bulk carrier until the spike measures the need.**

- **Strike `:267-276`** (the generation-swap bullet). As written it mandates a mechanism
  Emacs cannot perform.
- This **moots the entire FUSE / immutable / rename / locking analysis** — no cross-process
  file handoff, no cross-UID locking, no journal-mode discipline, no generation retirement,
  no reader-holds-old-generation rule.
- **It also softens finding 6.** Room 3's identity-hash writes, file lock, and no-flags open
  are fatal only for a *foreign* artifact; for a database the Companion creates and
  exclusively owns they are harmless — so `jetpacs-vroom3` can be an ordinary Room 3
  database with `@Entity`/KSP/migrations. **The rename still stands:** the schema-generic,
  wire-declared layer still cannot use Room, because the codegen requirement is
  ownership-independent. The `BundledSQLiteDriver` flags finding stays in the record as
  verified research that is no longer load-bearing.
- **Reserved shape** if a bulk carrier ever returns: not a SQLite file but a dumb
  hash-verified blob (gzipped NDJSON changesets) at a negotiated URI, content hash carried
  inline. The artifact need not be *durable*, only *detectable* — a torn or vanished file
  fails the hash and the consumer falls back to inline changesets.
- **Honest cost to state:** the projection is stored twice on one device. I7's logic accepts
  it — the Companion's copy is a projection, not a second interpreter.

### D2.2 Edits by anchor

- **Provenance table (`:10-14`)** — add a row citing D1. The repo has no docs index;
  citation *is* registration.
- **Rung ladder (`:36-44`)** — replace with §D2.3's ladder.
- **§1 Decisions (`:51-77`)** — rewrite Decision 2 (Room 3 → typed consumer only; generic
  layer = `androidx.sqlite` + `sqlite-bundled`), citing the four blockers. Append two
  decisions: the **library-adoption standing rule** (verification citation + tier + seam,
  named before a gate, recorded in `LIBRARY-LEDGER.md`), and its sibling — *do not specify
  an optimization before measuring the need*.
- **§2 Invariants (`:81-120`)**
  - **I1** restated once, unambiguously: *no file under `ebp/` is modified during RF-2 and
    goldens are never regenerated; wire-byte drift is expected and SPEC-legal per
    §24's semantic-comparison mandate.* Add the CI assertion `git status --short ebp/`
    empty. Generalise into the enforcement-naming rule.
  - **I4** defines only *materializer* but is asked to carry three tiers — define
    **capability** and **infrastructure**, and update examples for the rename (Room 3 =
    materializer of `jetpacs-vroom3`; androidx.sqlite = infrastructure inside `ebp-sqlite`;
    neither appears in wire vocabulary).
  - **I6** gets a start point and a retroactivity clause: binds from RF-1a; RF-2a/B0/B1
    grandfathered under local gates; C2 onward requires CI green. The throwaway spike
    carries no permanent gate but must never be able to redden another rung's.
  - **I8** add: a copy under a *different application's* private storage is a new exposure
    surface requiring explicit onboarding consent.
- **RF-0 (`:124-136`)** — add: push `ebp` **and set upstream**, then the parent, stating
  that CI depends on it; and the `granted`-gating P1. Record that the fix is bigger than two
  call sites: `ebp.el` needs a **method→capability table** (`theme.set`→`theme`,
  `dialog.show`→`surfaces.dialog`) — none exists today (verified) — **pinned against
  `ebp/contract.json`** rather than hand-written, since hand-written mirrors are a named
  v1→v2 regression; but read only fields that already exist, or it collides with I1.
  Specify the gate's failure mode and its interaction with callers that already gate:
  `jetpacs-theme.el:471` has an explicit ungranted branch whose taxonomy must not change.
- **NEW RF-0.5a / RF-0.5b.** The framing correction: the listener is a daemon thread on the
  *application process*, merely *started* from MainActivity — so there are two separable
  defects. **0.5a** hoists the bootstrap into `EbpApplication` (no `<service>`, no
  `FOREGROUND_SERVICE_SPECIAL_USE`, no Play surface) and absorbs the Activity-recreation
  defect by making the bridge process-owned and the Activity a pure observer. **0.5b** is
  the foreground service *plus* the reconnection-policy decision (FGS vs `offline.wake`
  §5.3 vs client backoff) with the supersession-livelock rules: backoff with jitter and a
  cap on a close the endpoint did not initiate; drop the old session's pending callbacks on
  reconnect (a stale response must not conclude a new session's pending id); never shortcut
  the §10.3 barrier; a reconnect that fails at auth/welcome leaves the staleness timer
  running. **Warning to record:** admitting `offline.wake` roughly doubles the rung — §5.3's
  inertness requirements are a security-conformance burden, not a checkbox.
- **RF-1 split (`:140-159`)** — **1a** elisp + spec + wire + app, no new dependencies, plus
  the three-red demonstration; **1b** Robolectric + Compose renderer tests, deferred past
  C6; **1c** the cross-implementation job, after the headless host. Record *why* 1b defers:
  the renderer's protection during C6 is the APK smoke plus the string-literal fixture rule,
  not a framework introduced the week before. Two non-obvious CI facts to write down: the
  **wire** job needs the submodule (five suites resolve fixtures through the `ebp.dir`
  system property and `error()` when unset) — it, not the spec job, is the real cross-repo
  binding; and `local.properties` is gitignored, so `:app` needs `ANDROID_HOME` supplied.
- **NEW data-spike rung, split.** Elisp half **now, parallel with C2–C6** (touches only
  `emacs/` + `test/`, and **must not modify anything under `ebp/`**). Kotlin half **after the
  RF-2b exit gate**, in `:app` only — never `:wire`, or RF-2c's six-file `jvmMain` inventory
  gate breaks. **State the carrier explicitly:** an ordinary `surface.update` carrying a
  `table` node (verified advertised at `NodeSupport.kt:34`) — a `jetpacs.*` method is
  impossible pre-RF-3 (§7.3 unknown-method) and a `jetpacs.*` capability is impossible
  (`CapabilityCatalog.VALIDATED` is closed and throws outside it). Record the spike's
  **written questions, kill criteria, removal commit, and directory** — this tree already
  carries two "staging, never required by base" arms that survived. One question is
  load-bearing: *what fraction of a real vault's projection exceeds `max_frame_bytes`
  (`SPEC.md:247`, exactly 4194304), and what does elisp-side JSON encoding actually cost?* —
  that number decides whether a bulk carrier is ever needed. Record the two constraints
  orgseq's model header states: DB titles are display-formatted (so the projection must
  declare DB-vs-file), and every mutation runs `save-buffer` + a synchronous
  `vulpea-db-update-file`.
- **NEW RF-2.6 — headless JVM loopback host.** `CompanionEngine` + Memory stores +
  `ServerSocket`, in a `:host` module or a `jvmTest` fixture, after RF-2c where `commonMain`
  plus the JVM actuals make it nearly free. Four things depend on it (RF-1c, RF-3, RF-4, and
  it seeds the desktop companion).
- **RF-4 (`:232-308`)** — rename to `ebp-sqlite`; apply D2.1; replace trigger-based change
  capture with the track-changes + content-hash tiers; add the wide-integer encoding
  **sequenced after the RF-2b exit** (it edits `ebp/`, so it cannot land inside the I1
  window); caveat cr-sqlite as frozen. Note the inherited costs of not using Room in the
  generic layer: a `BEGIN IMMEDIATE`/`END`/`ROLLBACK` helper (template at
  `RoomConnectionManager.kt:127-140`), thread-confinement or `SQLITE_OPEN_FULLMUTEX`
  (`SQLITE_THREADSAFE=2`, `hasConnectionPool=false`), and no `InvalidationTracker`.
- **RF-5 (`:310-319`)** — **5a becomes a prerequisite of RF-4b**, contradicting `:43` and
  `:46-47` ("each independent", "parallelizable") and the priority line `:319`; fix all
  three. Rewrite 5b's gate (process-death-by-reaper, not force-stop). Note in 5c that
  auto-reconnect turns every flap into a Keystore operation.
- **Non-goals (`:338-356`)** — replace the Tauri aside with the CMP desktop companion, but
  **split it**: the headless host is a scheduled rung (RF-2.6); the CMP *UI* app stays an
  RF-6 item. Desktop CMP is a JVM target, so RF-2's jvm-only flip already suffices. Record
  that `sqlite-bundled` declares **no** js/wasmJs targets (web uses `sqlite-web`, whose
  `open` is `suspend`).
- **`docs/PLAN-rf2-kmp-migration.md`** — write the still-owed P0 pin tests **before C2**
  (`:39`, `:57-59`); cut the `rf-2b` branch; edit the three ledger entries that now say the
  opposite of this amendment (`PLAN-refound:40`, `PLAN-rf2:5`, `PLAN-rf2:258`) in the same
  commit, or a fresh session reads §0 STATE and skips CI; **fix the broken relative link at
  `PLAN-rf2:5`**. Add the standing instruction for the whole RF-1→C6 window: **every test or
  fixture builds JSON from string literals, never programmatic `JSONObject().put(...)`
  chains** — conversion then becomes a one-line parser swap per fixture. Also: call RF-1b's
  reference images **render snapshots**, never "goldens" (I1's noun is already overloaded).

### D2.3 Final ladder

| Rung | What | Blocked on | Why (where non-obvious) |
|---|---|---|---|
| RF-0 | Push `ebp` **+ set upstream**, then parent; JA-4 P1-6; JA-6's five P1s; **`granted` gating**; device smoke | — | The push is a *technical* prerequisite of CI |
| RF-1a | CI: elisp + spec + wire + app; three-red demo. No new deps | RF-0 | Elisp suite is self-contained; the wire job needs the submodule |
| RF-0.5a | Process-scope the listener in `EbpApplication`; absorb the rotation defect | RF-1a | Structural, not JSON — land before C2 so it does not enlarge C6 and every later smoke is trustworthy |
| P0 | The owed pre-swap pin tests, string-literal fixtures | RF-1a | Enforced from birth, not demonstrated once |
| C2–C6 | The conversion, on branch `rf-2b` | P0, RF-1a | Nothing under `ebp/` may change |
| spike-elisp | vulpea → flat rows | — (parallel now) | Zero Kotlin, zero `ebp/` |
| RF-2c | Hoist to `commonMain` | RF-2b exit | |
| spike-kotlin | table + apply-rows, `:app` only, via `surface.update` + `table` | RF-2b exit | Produces the measurement that decides RF-4a's carrier |
| RF-1b | Robolectric + renderer tests | RF-2b exit | New dependency stack + SDK-36 shadow-jar risk |
| RF-2.6 | Headless JVM loopback host | RF-2c | Nearly free once commonMain exists; four things depend on it |
| RF-1c | Cross-implementation CI job | RF-2.6 | First time elisp↔Kotlin is enforced rather than assumed |
| RF-0.5b | Foreground service + reconnection policy + supersession rules | RF-2b exit, RF-0.5a | New Kotlin — would be converted twice if earlier |
| RF-5a | track-changes.el — **now a prerequisite of RF-4b** | RF-1a | Promote it in the priority line |
| RF-5c | Keystore | RF-1a | Note the reconnect interaction |
| RF-3 | Extension seam + `jetpacs.echo` | RF-2c, RF-2.6 | Gate (2) is unrunnable without the host |
| RF-4a | `ebp.data` spec — inline changesets only | RF-3; informed by spike-kotlin; after I1 closes | Editing `ebp/` is forbidden while RF-2 is in flight |
| RF-4b | `ebp-data.el` | RF-4a, RF-5a | |
| RF-4c | `ebp-sqlite` (renamed) | RF-4a, RF-2.6 | Under the producer decision, Room's constraints stop applying to a Companion-owned DB |
| RF-5b | WorkManager, **rewritten gate** | RF-1a | |
| RF-5d | Coil 3 | RF-1a | |
| RF-6 | Graduation + CMP desktop companion UI | RF-2..RF-4 | JVM target — RF-2's flip already suffices |

---

## D3 — `docs/DRAFT-amendments-140-152.md`

**Numbering settled and re-verified: `SPEC-CHANGES.md` runs #34→#139, so this batch starts
at #140.** Format per `DRAFT-amendments-87-90.md`; H1 with an **en dash**
(`# DRAFT amendments #140–#152`). Preamble: `Drafted 2026-07-31 against ebp/SPEC.md @
06fd9cd (amendments through #139).`, `Source audit:
docs/AUDIT-plan-spec-adversarial-2026-07-31.md`, the bold **"These are drafts for
ratification, not applied edits."**, and a `Ratification order:` line putting the
no-design-decision entries first (**#142, #144, #148, #150, #151**).

Per candidate: (1) `**SPEC-CHANGES row:**` — the pasteable 6-field row in a `>` blockquote,
ratifier column empty; (2) `**SPEC.md edits:**` — bullets naming the exact anchor sentence,
each with replacement prose in a nested `>` blockquote; (3) artifact changes
(contract/goldens/validate). `**⚠ Design decision required:**` with lettered options where
the shape is a judgement call. Close with the `## Roll-up` table
(`| # | Hole | Sections | Needs a decision? | Artifacts |`).

| # | § | Hole | Decision? |
|---|---|---|---|
| 140 | §15.2 | Effective-clock ratchet — an unbounded forward advance mass-expires the queue, then disables expiry until real time catches up; the correct technique is already in-spec at §21.2 | **Yes** |
| 141 | §13.1 | Surface-ID floors are non-reclaimable with no release path; the only remedy destroys all durable state | **Yes** |
| 142 | §4.5 | `max_capture_fields × max_field_bytes` may exceed `max_event_bytes` at the REQUIRED minimums; state the inequality as §4.5 already does for event/frame | No |
| 143 | §15.3/§15.2 | Dedupe may delete the retained-and-paused head, inverting the anti-overtake guarantee; the resulting pause state is undefined | **Yes** |
| 144 | §14.1/§15.2 | Dedupe key space unqualified by action/surface; fix the spec's own contradictory examples | No |
| 145 | §16.4/§17.4/§17.2 | Accessibility duty assigned to the endpoint that has no data to satisfy it | **Yes** |
| 146 | §5.2/§9.2/§23.6 | Listener contention + handshake ordering; re-scope §23.6's "privileged" claim | **Yes** |
| 147 | §5.2/§9.1 | Pre-auth bound has no eviction/fairness/aging rule; rate-limit state keyed on peer-chosen pairing IDs | **Yes** |
| 148 | §13.2/§10.3 | Make `applied`/`stale` normative floor-absorption points; define supersession's pending-inbound disposition | No |
| 149 | §4.2/§13.1 | Revision-space exhaustion: no wrap rule, no exhaustion error, no receiver duty to refuse | **Yes** |
| 150 | §24.4 | State that ordering/atomicity/clock/durability semantics are outside any projection, and that the contract is not a complete gate | No |
| 151 | §25 | **Standing rule:** an amendment touching a monotone resource MUST state exhaustion + reclamation; a claimed enforcement MUST name the tool and scope enforcing it | No |
| 152 | §5.2 | Supersession defines no signal — the loser sees a bare close, indistinguishable from a crash, which makes auto-reconnect livelock-prone. Add `session.superseded` before the close, or a normative minimum backoff | **Yes** |

Anchors located and verified for all: §15.2 L1909-1919; §13.1 L1288-1308;
§4.5 L245-260/L295-302; §15.3 L1941-1943/L1985; §14.1 L1542; §16.4 L2084; §17.2 icon row;
§17.4 `icon_button` row; §9.3 L945-962; §5.2 L374-378, L383-385, L386-387; §9.1 L774-786,
L819; §13.2 L1349; §4.2 L141; §24.4 L4250; §25 L4337-4353.

---

## D4 — `docs/LIBRARY-LEDGER.md`

The enforcement point the library-adoption rule otherwise lacks. One row per adopted
library: **name + coordinates · dated verification citation · tier (materializer /
capability / infrastructure, per I4) · seam it sits behind · rung**. Retro-fit the entries
already implied: kotlinx.serialization, kotlinx-datetime, Robolectric, androidx.sqlite +
sqlite-bundled, Room 3, track-changes.el, WorkManager, Coil 3, Compose Multiplatform.

---

## Verification

Documents only, so verification is citation integrity plus proof that nothing normative moved:

1. **Anchor check** — every `path:line` cited resolves to the quoted text (extract citations,
   `sed -n` each, diff against the quote). Where load-bearing, cite section + quote, not the
   line alone: line numbers shift the moment anything is ratified. §0.1 is the record of the
   pass already run.
2. **Amendment numbering** — `SPEC-CHANGES.md` still tops out at #139 at write time; #140-152
   collide with nothing.
3. **No ratification leakage** — `git status --short ebp/` **empty** and `git submodule
   status` still shows the leading-space in-sync marker at `06fd9cd`. This package must not
   touch `SPEC.md`, `contract.json`, or any golden.
4. **`python3 ebp/validate.py`** green from `$POC` — proves nothing normative changed.
5. **`test/run-tests.sh`** (29 ERT suites) and **`./gradlew :wire:jvmTest`** green — the
   documents-only proof. Note `:wire:jvmTest` resolves fixtures via `ebp.dir`.
6. **Reproduce the two external claims that most affect RF-4**, so a later reader need not
   re-run agents: (a) `git -C ~/pkb/resources/emacs/emacs show emacs-30.1:src/sqlite.c`
   shows `sqlite-open` hardcoding `CREATE|READWRITE` with no read-only path; (b) the room3
   clone shows `BundledSQLiteDriver.kt:95 open(fileName, flags)` while
   `RoomConnectionManager.kt:81` calls the no-flags `open`.
7. **Ledger-contradiction sweep** — after D2, `grep -rn "no CI\|ahead of RF-1\|CI (RF-1, later rung)"`
   over `docs/` returns nothing contradicting the new ordering.
8. **Commit shape** — house style (`docs(audit):`, `docs(plan):`, `docs(spec):`), each with a
   prose body carrying the rationale, since this repo records amendment rationale in commit
   messages rather than a changelog section.
