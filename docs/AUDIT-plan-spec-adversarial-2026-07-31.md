# AUDIT — The refound plan + SPEC, adversarial review (2026-07-31)

**Target:** `docs/PLAN-refound-2026-07-28.md` @ `0fab0d5` and `ebp/SPEC.md` @ `06fd9cd`
(amendments through **#139**), with `docs/PLAN-rf2-kmp-migration.md` as the executing
runbook.
**Run:** 2026-07-31. Opus 5 authoring, Fable 5 verification. Five adversarial agents:
three external verifiers (Emacs source at the `emacs-30.1` tag; the web ecosystem; the
local Room 3 / androidx.sqlite clone `~/pkb/resources/android/androidx/room3` @
`d69c96e`), one SPEC adversary, one sequencing adversary.
**Scope:** defects in the refound plan's TEXT and SEQUENCING, plus the SPEC holes its
execution would inherit — not implementation bugs, except where the plan's claim *about*
the implementation is itself the defect. The prior spec-hole pass
(`AUDIT-spec-holes-2026-07-24.md`) is not duplicated; every candidate below is new
against #139.

**17 plan-half findings (7 P1, 7 P2, 3 P3) + 7 hand-verified SPEC-half holes + 4
appendix leads → 13 SPEC-amendment candidates; 2 prior findings re-characterised.**

Severity: **P1** = executing the plan as written fails or destroys something (a
mechanism its only producer cannot perform, a gate that cannot pass, an unstated hard
dependency); **P2** = an observable defect or unowned decision the plan inherits or
reproduces; **P3** = the record is wrong or weaker than the truth, without blocking
anything.

---

## Status & method

The agents produced leads; **every load-bearing claim was then re-verified by hand
against source on 2026-07-31** (the pass is recorded as §0.1 of
`PLAN-amendment-package-2026-07-31.md`; the reproduction lines below cite what was
read). Emacs claims are judged at the `emacs-30.1` tag, never master. Kotlin claims are
judged against the local `androidx` clone, not release notes — the package's own thesis
is that stated enforcement outruns actual enforcement, so it does not get to assert
unverified anchors.

The standing house rule is restated here because this project has hit the trap twice:
**a dead verifier is never counted as a refutation.** Every finding below is labeled
**hand-verified** (the cited text was read in source during this pass) or
**agent-reported** (the anchors were located, but the reasoning is the agent's and was
not independently reproduced).

Hand-verification surfaced four corrections to the package's own claims, recorded where
they bite: the RF-4a strike range is `:267-276`, not `:266-276`; the vulpea citations
live in the ELPA install (`~/.emacs.d/elpa/vulpea-20260714.543/`), not the outdated
repo checkout, so they MUST be version-qualified absolute paths; the package is four
files, not the announced three; `PLAN-rf2-kmp-migration.md:5` carries a broken relative
link to PLAN-refound.

---

## The thesis

**Stated enforcement outruns actual enforcement.** Three independent instances, none
sharing a mechanism:

1. **I1** reads "goldens are byte-identical through RF-2" while no Kotlin test compares
   serialized JSON bytes and `SPEC.md:4287-4290` *mandates* semantic comparison — byte
   drift is SPEC-legal and undetected in exactly the step (RF-2b) most likely to cause
   it. The runbook already says the opposite of the plan (P2-5).
2. **`check_spec_sync`** is described by RF-4's gate as binding prose↔contract, but it
   covers 2 of the 31 contract top-level registries (P3-1).
3. **§9.1's keystore MUST** is unconvictable by a wire-and-golden conformance regime —
   nothing observable on the wire distinguishes a keystore-held token from a plaintext
   one (re-characterised below; candidates 150/151 are the structural response).

**Secondary thesis, for the SPEC half:** amendments that close a symptom and deepen the
structure underneath. #81 stamped `occurred_at_ms` from the effective clock and left the
ratchet's *forward* direction unbounded (candidate 140). #107 made a revision floor
survive an unvalidatable snapshot and left the floor space non-reclaimable with no
release path (candidate 141). #77/#79 mandated accepting-while-open plus equal-work
challenges, creating a pre-auth surface that is now obligatory but has no eviction,
fairness, or aging rule (candidate 147).

---

## Tier 1 — P1 (the plan as written fails)

### P1-1 · RF-4a's generation-swap is unsound on the reader side — read-only does not skip locking

**"Immutable generations mean no cross-process locking ever" is false for a read-only SQLite open; only `immutable=1` skips locking, and a WAL artifact needs sidecars**
`PLAN-refound-2026-07-28.md:267-276` · sqlite.org/uri.html, sqlite.org/wal.html §5 · hand-verified (plan text) + agent-reported (SQLite semantics, from the published documentation)

*Claim.* The bullet asserts the Companion "opens it **read-only**" and that "Immutable
generations mean **no cross-process locking ever**". A read-only open does *not* skip
locking — SQLite still takes shared locks on a read-only connection; only the
`immutable=1` URI parameter (which requires a URI-style open) omits file locking
entirely, and it is the application's promise, not something SQLite verifies. A
WAL-mode artifact additionally cannot be read without its `-wal`/`-shm` sidecars unless
opened immutable. For the mechanism to be safe the published artifact must be fully
checkpointed, `journal_mode=DELETE`, and sidecar-free — none of which the paragraph
states.

*Reproduction.* `PLAN-refound:267-276` read in full; the quoted sentences are at
`:268-270` and `:272-273`. SQLite semantics per sqlite.org/uri.html (`immutable`
parameter) and wal.html §5 (read-only WAL requires the shared-memory file or
`immutable`).

*Fix.* Superseded by the producer decision (D2.1 of the amendment package): strike
`:267-276`; the Companion materializes its own database from inline changesets. If a
bulk carrier ever returns, it is a hash-verified dumb blob, never a SQLite file.

### P1-2 · RF-4a's producer gap — Emacs cannot durably publish the artifact at all

**`sqlite-open` hardcodes `CREATE|READWRITE`, URI filenames are unreachable, no directory-fsync primitive exists, and `write-region-inhibit-fsync` defaults `t` — the paragraph is a spec-shaped promise the only extant producer cannot keep**
`emacs-30.1:src/sqlite.c`; `emacs-30.1:src/fileio.c:5579,:6844`; `PLAN-refound-2026-07-28.md:268-270` · hand-verified

*Claim.* The struck paragraph mandates that Emacs "builds `<name>.<generation>.db`
under a temp name, fsyncs, atomically renames". Emacs 30.1 can perform no leg of this:
`sqlite-open` passes hardcoded `SQLITE_OPEN_CREATE|SQLITE_OPEN_READWRITE` flags with no
caller control, so a read-only or URI-parameterized open is unreachable from Lisp; a
`file:` URI is doubly unreachable because `expand-file-name` prepends
`default-directory` to it before the C layer sees it; Lisp has no directory-fsync
primitive, so the atomic-rename durability step cannot be completed; and
`write-region-inhibit-fsync` defaults to `t`, so even the data fsync is off by default.

*Reproduction.* `git -C ~/pkb/resources/emacs/emacs show emacs-30.1:src/sqlite.c` —
the `sqlite-open` DEFUN's `sqlite3_open_v2` call with fixed flags; `fileio.c:5579` and
`:6844` for the fsync default and the absence of any directory-sync path.

*Fix.* The producer decision (D2.1): strike the paragraph; ship inline changesets only;
do not specify a bulk carrier until the spike measures the need.

### P1-3 · RF-4b's trigger-based change capture collides with vulpea's write pattern

**vulpea updates are delete-all-rows-per-file + re-INSERT with FK cascades, and a schema-epoch bump deletes the DB file — an in-DB changelog records churn, then gets annihilated**
`~/.emacs.d/elpa/vulpea-20260714.543/vulpea-db-extract.el:1465`; `…/vulpea-db.el:341,675,176-198`; `~/pkb/projects/jetpacs-orgseq/orgseq/jetpacs-orgseq-model.el` header *(path corrected 2026-07-31 by spike-elisp: originally cited as `emacs/jetpacs-orgseq-model.el`, which resolves to nothing — that file is in a **separate repo**. Same defect class as this pass's own vulpea-ELPA correction, missed on the same pass; the header's content is verbatim as quoted)* · hand-verified

*Claim.* RF-4b specifies "change capture = triggers → changelog table". The projection's
actual producer, vulpea, updates a file by deleting every row for that file and
re-inserting (with foreign-key cascades), so row-level triggers record a mass
delete+insert storm per save, not logical changes. Worse, a schema-epoch bump deletes
the database *file* (`vulpea-db.el:341`), annihilating any changelog stored inside it.
The app-level model (`jetpacs-orgseq-model.el` header) confirms the same pattern: every
mutation runs `save-buffer` plus a synchronous `vulpea-db-update-file`.

*Reproduction.* ELPA sources read at the version-qualified paths above. The repo
checkout at `~/pkb/resources/emacs/vulpea` is **outdated and would mislead** — cite the
ELPA install only.

*Fix.* Replace trigger-based capture with the track-changes + content-hash tiers (D2's
RF-4 edit); RF-5a becomes a prerequisite of RF-4b.

### P1-4 · Three orphaned regressions sit on no rung — and the socket is the only bootstrap `EbpApplication` omits

**Availability, reconnection, and `granted` gating — the review's three carried gaps — appear on no rung; the sharper form: process-lifetime bootstrap already exists and covers triggers/alarms but not the listener**
`REVIEW-poc-v1-vs-rewrite-2026-07-27.md` §4; manifest (no `<service>`); `EbpApplication.kt:14-33`; `MainActivity.kt:78`; `DeviceBridge.kt:166,171,179`; `ebp.el:1142,1798,1941,1959`; `device/init.el:165-181,209-211` · hand-verified

*Claim.* The v1-vs-v2 review closed §4 with "availability, reconnection, and `granted`
gating are not on any rung — those three are the open gaps a reader should carry". The
refound plan schedules none of them. The sharper form the agents missed and
hand-verification found: `EbpApplication.onCreate` *already does* process-lifetime
bootstrap — firing recovery, trigger-source start, baseline arming, reminder and alarm
re-arm — and omits exactly one thing: the socket. So a cold start from an alarm revives
triggers but not the listener; the listener is a daemon thread on the application
process merely *started* from `MainActivity.onCreate` (`MainActivity.kt:78`
`bridge.start()`). The fix is a hoist, not a new architecture.

*Reproduction.* `EbpApplication.kt:14-33` read in full (no socket start);
`AndroidManifest.xml` has no `<service>` element; `DeviceBridge.kt:166` `fun start() =
thread(name = "ebp-bridge", isDaemon = true)`.

*Fix.* New rungs RF-0.5a (hoist the bridge to `EbpApplication`, Activity becomes a pure
observer) and RF-0.5b (foreground service + the reconnection-policy decision);
`granted` gating joins RF-0 (D2).

### P1-5 · RF-1 is blocked on RF-0 *technically*, not just morally

**No upstream exists on either repo, so a GitHub Actions workflow has nothing to check out, and `actions/checkout` cannot fetch an unpushed submodule SHA**
`git rev-parse @{u}` fails in both `$POC` and `$POC/ebp` · hand-verified

*Claim.* The plan sequences RF-1 (CI) after RF-0 (pushes) on debt-hygiene grounds
("a re-founding does not start on unpushed ground") and marks strictness only "where
blocked-on says so" — inviting a reader to parallelize them. They cannot be
parallelized: neither repo has an upstream, so there is no remote for Actions to run
against, and even after the parent pushes, a workflow checking out the `ebp` submodule
pin fails unless the submodule's SHA is reachable on *its* remote first.

*Reproduction.* `git rev-parse --abbrev-ref @{u}` errors in both repos; `origin`
exists, nothing is pushed.

*Fix.* RF-0 gains "push `ebp` **and set upstream**, then the parent, stating that CI
depends on it" (D2); the ladder row for RF-1a names RF-0 as a hard dependency.

### P1-6 · Room 3 cannot serve the schema-generic layer — `ebp-room3` is misnamed

**Room's open path is codegen-only, it writes an identity hash into any DB handed to it, opens with no flags under an `ExclusiveMutex` file lock, and its migration ladder is compile-time — a wire-declared runtime schema cannot use it, as the plan's own prose already admits**
`room3:RoomDatabase.android.kt:302-306`; `RoomConnectionManager.kt:81,70-73,113-155` · hand-verified (room3 clone @ `d69c96e`)

*Claim.* RF-4c's own text says the generic layer is "`androidx.sqlite` driver-level …
Zero `@Entity`" — yet the module is named `ebp-room3` and Decision 2 frames Room 3 as
its foundation. Four blockers, each independently fatal for a *schema-generic* layer:
`createOpenDelegate` is implemented only by generated code, so opening without KSP
codegen is impossible; the connection manager *writes* a schema identity hash into any
database it opens (mutating a foreign artifact); it calls the no-flags
`delegate.open(resolvedFileName)` and takes PRAGMA writes plus an
`ExclusiveMutex(useFileLock=…)`; and the migration ladder is compile-time. The rename
is not cosmetic: the name asserts a dependency the layer must not have.

*Reproduction.* `RoomConnectionManager.kt:81` calls no-flags `open`; `:70-73`
constructs the mutex with a file lock; `:113-155` is the identity-hash
write/validation; `RoomDatabase.android.kt:302-306` is the codegen-only delegate.
Contrast `BundledSQLiteDriver.kt:84` `open(fileName)` with `:95`
`open(fileName, @OpenFlag flags)` and public `SQLITE_OPEN_READONLY`/`SQLITE_OPEN_URI`
(`BundledSQLite.kt:26,:35`) — the *driver* level has everything the generic layer
needs.

*Fix.* Rename to `ebp-sqlite`; rewrite Decision 2 (Room 3 = typed consumer only). Under
the producer decision this finding **softens but the rename stands**: for a database
the Companion creates and exclusively owns, Room's identity hash, file lock, and
no-flags open are harmless — so `jetpacs-vroom3` can be an ordinary Room 3 database
with `@Entity`/KSP/migrations. The codegen requirement is ownership-independent, which
is why the generic layer still cannot use Room.

### P1-7 · No elisp↔Kotlin loopback harness exists, yet three gates assume one

**The live-loopback ERT suite's companion is elisp-scripted; RF-3's gate (2), RF-4's gate, and the cross-implementation CI job all assume a harness that exists nowhere and is scheduled nowhere**
`test/ebp-wire-test.el:331`; `PLAN-refound-2026-07-28.md:225,299-302` · hand-verified

*Claim.* `ebp-test--start-companion` scripts the companion side in elisp — the
"live-loopback" suite proves ebp.el against a fake, never against the Kotlin engine.
RF-3's gate (2) ("tenant round-trips elisp↔Kotlin over live loopback"), RF-4's gate
("elisp↔Kotlin loopback: declare schema → push changesets → kill Companion …"), and
RF-1's ambition of a cross-implementation job all require a real Kotlin process an ERT
suite can dial. No rung builds one.

*Reproduction.* `test/ebp-wire-test.el:331`; grep for any harness that launches a JVM
from ERT — zero matches.

*Fix.* New rung RF-2.6 — a headless JVM loopback host (`CompanionEngine` + Memory
stores + `ServerSocket`), nearly free after RF-2c; RF-1c (the cross-implementation CI
job) sequences after it. Four things depend on the host: RF-1c, RF-3, RF-4, and the
desktop companion seed.

---

## Tier 2 — P2 (inherited defects and unowned decisions)

### P2-1 · Activity-recreation defect: rotation builds a second bridge that loses the bind race

**`DeviceBridge` is built per `onCreate` closing over Activity state, no `configChanges` is declared, so rotation constructs a second bridge while the first still owns the socket and pushes into a destroyed Activity's flows**
`AndroidManifest.xml:27` (no `configChanges`); `MainActivity.kt:51-60`; `DeviceBridge.kt:172-181` · hand-verified

*Claim.* `MainActivity.kt:51` constructs `DeviceBridge` with callbacks closing over
`currentSpec` and `this` (Toasts); the manifest declares no `android:configChanges`, so
rotation destroys and recreates the Activity, constructing a second bridge whose
`start()` loses the bind retry race (`DeviceBridge.kt:172-181` retries `EADDRINUSE` 20
times) while the first bridge keeps serving into flows nothing observes.

*Reproduction.* Anchors read; the closure list is `MainActivity.kt:51-77`.

*Fix.* Absorbed by RF-0.5a: the bridge becomes process-owned, the Activity a pure
observer. Recorded here so the defect has a finding, not just a rung.

### P2-2 · Reconnection × §5.2 supersession is a livelock, and the loser cannot even tell

**Newest-wins + auto-reconnect on both endpoints and two Emacsen (device + workstation over `adb forward` — a documented configuration) oscillate forever, each cycle running a full §10.3 barrier including `queue.replay`; §5.2 defines no supersession signal, so the loser sees a bare close indistinguishable from a crash**
`SPEC.md:383-385`; `DeviceBridge.kt:186-187`; `ONBOARDING-device.md` · hand-verified

*Claim.* §5.2 mandates newest-wins and (per #77) accepting new connections while a
session exists. If both Emacsen auto-reconnect — the exact policy RF-5's reconnection
item would add — each supersession triggers the loser's reconnect, which supersedes the
winner, forever; every cycle is a full synchronization barrier including a
`queue.replay` round trip per retained event. Nothing distinguishes "you were
superseded, back off" from "the Companion crashed, retry now": the loser sees a bare
TCP close (`DeviceBridge.kt:186-187` `current?.runCatching { close() }`).

*Reproduction.* SPEC text at `:383-385`; the two-Emacsen configuration is documented in
`ONBOARDING-device.md`.

*Fix.* RF-0.5b carries the policy rules (backoff with jitter and a cap on a close the
endpoint did not initiate; drop the superseded session's pending callbacks; never
shortcut the §10.3 barrier; a reconnect failing at auth/welcome leaves the staleness
timer running). SPEC-side: candidate 152 (`session.superseded` or a normative minimum
backoff).

### P2-3 · `offline.wake` is declared in `:wire`, advertised nowhere, and the plan names two of three overlapping mechanisms

**SPEC §5.3's sanctioned "get Emacs back" mechanism is absent from `supportedCapabilities`; FGS, auto-reconnect, and `offline.wake` overlap and no rung owns the choice**
`DeviceBridge.kt:111-113`; `SPEC.md:427-432` · hand-verified

*Claim.* `supportedCapabilities` lists 9 capabilities; `offline.wake` is not among
them, though `:wire` validates it. The plan discusses the foreground service
(regression ledger) and reconnection (RF-5 aside) but never §5.3 — three mechanisms
that all answer "Emacs is gone, get it back", with no decision about which combination
ships. **Warning recorded for the rung that admits it:** §5.3's inertness requirements
(coalesce, ≤1/60 s, stop after 10 s, "not background-execution privileges") are a
security-conformance burden that roughly doubles RF-0.5b, not a checkbox.

*Reproduction.* `DeviceBridge.kt:111-113`; `SPEC.md:427-432` quoted in §0.1 of the
package plan.

*Fix.* RF-0.5b owns the FGS vs `offline.wake` vs client-backoff decision explicitly.

### P2-4 · RF-2 running ahead of RF-1 reproduces the demonstrated-once mode the plan was written to end

**The runbook's own ledger records the skipped P0 pin tests and the skipped sub-step branches — the plan that diagnosed "every green number is demonstrated-once" is being executed in that exact mode**
`PLAN-rf2-kmp-migration.md:39,:57-62`; `PLAN-refound-2026-07-28.md:140-144` · hand-verified

*Claim.* RF-1's rationale reads "CI precedes the migration so every later rung is
enforced." RF-2 then ran first on local gates (ratified, but the ratification is
recorded only in a status cell), skipped Phase 0.2's pin tests ahead of the phase that
needed them, and skipped the branch scheme. Each deviation is individually defensible
and honestly ledgered — which is precisely how demonstrated-once regimes persist.

*Reproduction.* `PLAN-rf2:39` ("P0 … **NOT DONE**"), `:57-62` (three deviations
recorded).

*Fix.* P0 lands before C2; cut the `rf-2b` branch; I6 gains a start point and a
retroactivity clause so "ratified deviation" has a boundary (D2).

### P2-5 · I1 reads stronger than anything enforces, and contradicts itself across documents

**`PLAN-refound:83` says "byte-identical"; `PLAN-rf2:27` says explicitly *not* byte identity; SPEC.md:4287-4290 mandates semantic comparison — so byte drift is legal, expected, and undetected in the step most likely to cause it**
`PLAN-refound-2026-07-28.md:83`; `PLAN-rf2-kmp-migration.md:10,:27`; `SPEC.md:4287-4290` · hand-verified

*Claim.* No Kotlin test compares serialized bytes (`PLAN-rf2:10` records this,
verified); the conformance regime *forbids* requiring member order or escaping choices;
yet the plan's headline invariant says "Goldens are byte-identical through RF-2". A
reader of the plan expects an enforcement that neither exists nor is legal to add
without a canonical-JSON amendment. The runbook already restates I1 correctly — the two
documents disagree about the plan's most-cited invariant.

*Reproduction.* All three anchors quoted; `SPEC.md:4287-4290`: "compare the parsed JSON
body **semantically**. It MUST NOT require arbitrary JSON object-member order or
escaping choices".

*Fix.* Restate I1 once, unambiguously, in terms of what is enforced (`ebp/` untouched,
goldens never regenerated, wire-byte drift expected and SPEC-legal), add the CI
assertion `git status --short ebp/` empty, and generalise into the enforcement-naming
rule: *a stated invariant names the tool and scope that enforce it* (D2).

### P2-6 · RF-5b's gate cannot pass: "force-stop" is the one thing WorkManager does not survive

**"queue → force-stop → constraint met → delivery without app open" specifies precisely the behavior Android removes: a force-stopped app's scheduled work does not run until the user relaunches it**
`PLAN-refound-2026-07-28.md:315` · hand-verified (plan text) + agent-reported (platform behavior)

*Claim.* Force-stop puts the app into the stopped state; the platform cancels its jobs
and delivers nothing until an explicit user launch. WorkManager reschedules on next
process start — which force-stop by definition prevents. The gate as written red-bars
forever, or worse, gets "passed" by a tester who launched the app to check.

*Reproduction.* Plan text at `:315`; platform behavior per Android documentation on
stopped state (agent-reported; consistent with the device-smoke practice already in
RF-0, which force-stops *before* smoking precisely because state does not survive it).

*Fix.* Rewrite the gate: process-death-by-reaper (`adb shell am kill`, or OOM), not
force-stop (D2).

### P2-7 · `ebp.data` needs a canonical wide-integer encoding, and it cannot land during the I1 window

**§4.2 hard-caps integers at ±(2^53−1) with a Parse Error; SQLite `INTEGER` is 64-bit; a projection of real rows can carry values the wire must reject — and fixing it edits `ebp/`, forbidden while RF-2 is in flight**
`SPEC.md:141`; SQLite datatype documentation · hand-verified

*Claim.* "Revisions, sequence numbers, timestamps, and counts MUST NOT exceed this
range" (`SPEC.md:138-141`) and the parser hard-errors beyond ±(2^53−1). A vault
projection includes 64-bit rowids/values; `ebp.data`'s spec must define a canonical
string encoding for wide integers before the first changeset flows. Because the
encoding is spec text plus goldens, it edits `ebp/` — so it must sequence after the
RF-2b exit gate closes the I1 window.

*Reproduction.* `SPEC.md:138-145` quoted above.

*Fix.* D2's RF-4 edit adds the wide-integer encoding, sequenced after RF-2b exit.

---

## Tier 3 — P3 (the record is weaker than the truth)

### P3-1 · `check_spec_sync` covers 2 of 31 contract registries — the finding is coverage, not direction

**Correction recorded: the check *is* bidirectional, and its §11 half compares three fields (existence, sender via `SENDER_MAP`, class); everything else in the contract is unchecked prose-side**
`ebp/validate.py:94-133` · hand-verified

*Claim.* RF-4's gate says "`check_spec_sync` binds prose↔contract both directions."
Read in source, it cross-checks exactly two registries — the §8 error table and the §11
method registry — both directions, three fields for methods. The contract has 31
top-level keys; capabilities, node schemas, field types, trigger types, limits, and
every other registry are bound by nothing. An `ebp.data` contract entry would land
outside its coverage entirely unless the tool is extended. The earlier agent report
("one-directional") was wrong; the coverage number survives.

*Reproduction.* `validate.py:94-133` read in full; `python3 -c` count of contract
top-level keys = 31.

*Fix.* The enforcement-naming rule (name the tool *and its scope*); candidates 150/151
make the same demand of the SPEC's own conformance claims.

### P3-2 · cr-sqlite is dormant — a frozen design reference, not a living upstream

**Last push 2024-10, last release 2024-01, pre-1.0**
vlcn-io/cr-sqlite · agent-reported (web)

*Claim.* RF-4a cites cr-sqlite's column-clock scheme as "the design document" for the
future CRDT capability. As a frozen paper design that is fine; as an upstream to track
it is not. The plan should say which it means.

*Reproduction.* Repository activity per the web verifier; not independently reproduced
(no local clone).

*Fix.* Caveat recorded in RF-4's amendment (D2): design reference, explicitly frozen.

### P3-3 · `sqlite-load-extension`'s allowlist is filename-based, and the DEFUN itself is conditional

**The conclusion (no third-party extensions from Emacs Lisp) holds harder than the plan's argument: the allowlist matches module filenames, not content, and the whole DEFUN sits under `#if HAVE_LOAD_EXTENSION` — possibly absent on an Android build**
`emacs-30.1:src/sqlite.c` · hand-verified

*Claim.* The plan says the "hardcoded allowlist … bars third-party extensions forever".
True, and understated: the allowlist is a filename comparison (no content check — a
malicious library *named* like an allowed one would load, which is why relying on it as
a security boundary would be wrong in the other direction), and on builds without
`HAVE_LOAD_EXTENSION` the function does not exist at all. Either way, the session
extension's binary changeset format stays unreachable from Lisp; RF-4a's
canonical-JSON-changesets decision is over-determined.

*Reproduction.* `git -C ~/pkb/resources/emacs/emacs show emacs-30.1:src/sqlite.c` —
the `#if` guard and the filename loop.

*Fix.* None required in the plan beyond keeping the conclusion; recorded so the sharper
mechanism is on file.

---

**Verified positive — negative results, recorded.** Room 3 is exactly as ratified:
the artifact line is `androidx.room3`, JS/WasmJS targets are genuinely declared
in-source for `room3-runtime`/`room3-common` and `sqlite`/`sqlite-async`, the runtime is
driver-backed, Room 2.x is in maintenance. SQLDelight still lacks a wasmJs target.
`BundledSQLiteDriver.kt:95` has `open(fileName, flags)` with public
`SQLITE_OPEN_READONLY`/`SQLITE_OPEN_URI` (`BundledSQLite.kt:26,:35`), bundling SQLite
3.50.1 — the Android *reader* half of the snapshot design was implementable; the design
died on the producer half (P1-2), not this one. The full Emacs 30.1 sqlite API is
present; `track-changes.el` is present at the tag (v1.2, written for eglot's sync
problem). JCS-vs-i64 is sound at the wire. At-least-once delivery + receiver dedupe
windows line up with margin. §21's trigger durability is honestly scoped. These were
attack surfaces that held; recording them is what makes the failed attacks above
meaningful.

---

## SPEC-amendment candidates (13)

Drafted in full as `docs/DRAFT-amendments-140-152.md` (#140–#152 — `SPEC-CHANGES.md`
tops out at #139 at write time). Summary, most-severe-first within each half.
Candidates 140–146 arise from **hand-verified** holes; 147–149 are drafted from the
appendix leads below (anchors verified in text; the failure reasoning is the SPEC
adversary's, re-checked during drafting); 150–152 are the thesis made normative.

1. **#140 §15.2 — the effective-clock ratchet is unbounded forward.** The high-water
   mark ratchets on any forward jump; a transient glitch mass-expires the queue at the
   jump and then freezes event aging until real time catches up. The correct technique
   is already in-spec at §21.2 (monotonic elapsed while running, conservative persisted
   wall time across restart). Hand-verified at L1909-1919. *Design decision.*
2. **#141 §13.1 — surface-ID floors are non-reclaimable with no release path.** #107
   made floors survive re-validation; L1288-1308 forbids reclaiming; the only remedy
   that exists is pairing revocation, which destroys all durable state. Hand-verified;
   no release method exists anywhere in §13. *Design decision.*
3. **#142 §4.5 — limits arithmetic.** `max_capture_fields` (≥64) × `max_field_bytes`
   (≥65536) = 4 MiB ≫ `max_event_bytes` (≥262144) at the REQUIRED minimums — a
   conformant descriptor can demand an unsendable capture. §4.5 already states exactly
   this kind of inequality for event/frame (L295-302); state it for capture.
   Hand-verified at L245-260. *No decision.*
4. **#143 §15.3/§15.2 — dedupe may delete the retained-and-paused head.** The
   protection at L1927-1928 covers only an *in-flight* request; a head retained by an
   error pause is not in flight, so a same-key admission deletes it, leaving the pause
   pointing at nothing and inverting the anti-overtake guarantee (L1985).
   Hand-verified. *Design decision.*
5. **#144 §14.1/§15.2 — the dedupe key space is flat and the spec's examples disagree
   about it.** L1542 scopes the key to the pairing identity; trigger firings enter the
   same queue; §14.1's example namespaces by hand (`heading:123:todo`) while §21.1's is
   bare (`battery-low`). Hand-verified. *No decision.*
6. **#145 §16.4 vs §17.4/§17.2 — the accessibility duty is assigned to the endpoint
   with no data.** "Interactive nodes MUST expose an accessible label" (L2084) binds
   the Companion, but `icon_button`'s `content_description` is optional — for an
   icon-only node the Companion has nothing to expose. Hand-verified. *Design
   decision.*
7. **#146 §5.2/§9.2/§23.6 — the loopback threat model excludes an attacker that needs
   no privilege.** §9.3 (L959-962) excludes the "active *privileged* local
   man-in-the-middle", but an unprivileged local app can squat or race the loopback
   port and proxy the handshake — the handshake authenticates endpoints, not the
   channel. §23.6's "The HMAC handshake supplies that authentication" over-promises.
   Hand-verified. *Design decision.*
8. **#147 §5.2/§9.1 — the pre-auth surface has no eviction/fairness/aging rule, and
   rate-limit state is keyed on peer-chosen IDs.** #77 made accepting obligatory and
   bounding mandatory (L386-387) but an attacker holding `bound` idle connections makes
   supersession unreachable — the exact non-conformance #77 forbids; and "rate-limit
   failed proofs per pairing ID" (L819) lets an attacker rotate invented IDs to evade
   the limit or exhaust its state. Appendix leads, anchors verified. *Design decision.*
9. **#148 §13.2/§10.3 — `applied`/`stale` are not normative floor-absorption points,
   and supersession's pending-inbound disposition is undefined.** §10.3 step 1 and
   §24.2 make Emacs absorb floors from the *welcome*; a mid-session `stale` result
   reporting a higher floor (L1349-1351) carries no absorption duty, so Emacs can
   author below the floor indefinitely; and no rule says when the Companion concludes
   the old session's in-flight requests relative to the new session's welcome
   snapshot. Appendix lead + hand-verified anchors. *No decision.*
10. **#149 §4.2/§13.1 — revision-space exhaustion.** Revisions MUST NOT wrap (L1286)
    and MUST NOT exceed 2^53−1 (L141); no exhaustion error, no receiver duty, no
    recovery path is defined. Reachable by a timestamp-derived revision scheme.
    Appendix lead, anchors verified. *Design decision.*
11. **#150 §24.4 — state what the contract projection cannot gate.** Ordering,
    atomicity, clock, and durability semantics are outside any projection; the
    contract is a necessary gate, not a complete one. The thesis, normative.
    Hand-verified at L4245-4254. *No decision.*
12. **#151 §25 — the standing rule.** An amendment touching a monotone resource MUST
    state exhaustion + reclamation; a claimed enforcement MUST name the tool and scope
    enforcing it. Hand-verified at L4337-4353. *No decision.*
13. **#152 §5.2 — supersession defines no signal.** The superseded endpoint sees a
    bare close indistinguishable from a crash, which makes any auto-reconnect policy
    livelock-prone (P2-2 is the plan-half of this hole). Add `session.superseded`
    before the close, or a normative minimum backoff. Hand-verified at L383-385.
    *Design decision.*

---

## Refuted / re-characterised

- **§9.1 keystore narrowing (#78→#95) was NOT arbitrary.** The adversary's lead read
  #95 as weakening #78. Re-characterised: #95 narrowed the subject because Emacs 30.1
  exposes no keystore interface from Lisp — the narrowing tracks reality. The
  *residual* finding stands and is smaller: the symmetric secret's weaker copy is
  unprotected *by construction*; the §9.1 escape hatch (`SPEC.md:780-781` — a platform
  facility "exposes no interface to it from the endpoint's implementation environment")
  is self-certified and unfalsifiable; its compensating duty has no defined observable;
  and nothing in §24.6 can convict any of it. That residue feeds candidates 150/151,
  not a keystore amendment.
- **§9.1's rate-limiter vs §23.5 is NOT a contradiction.** The lead claimed the
  mandatory failed-proof rate limit violates §23.5's bounded-state rule. Re-read: §23.5
  is scoped to state keyed by unvalidated *method names*; pairing IDs are a different
  key space. What remains is a coverage gap — rate-limit state keyed on peer-chosen
  pairing IDs has no bound of its own — which is candidate 147's second half, not a
  contradiction.

---

## Appendix — unverified tail

Agent-reported leads whose anchors were located but whose reasoning was not
hand-reproduced. Per the standing rule, absence of a verdict is not refutation; three
of the four are drafted as candidates with the reasoning re-checked at drafting time:

- **Supersession welcome-snapshot mutability + no floor absorption on `stale`**
  (`SPEC.md:1349`) → candidate 148.
- **Pre-auth bound with no eviction/fairness/aging rule** (`SPEC.md:386-387`) →
  candidate 147.
- **Rate-limit state keyed on peer-chosen pairing IDs** (`SPEC.md:819`) → candidate
  147.
- **Revision-space exhaustion** (`SPEC.md:141`) → candidate 149.

---

## What this review did NOT cover

- **The prior spec-hole pass's territory.** `AUDIT-spec-holes-2026-07-24.md` (Tier 1/2
  + its appendix genres) was treated as settled input; nothing was re-litigated, and
  its unverified tail remains unverified.
- **Implementation audits.** No lens swept `:wire`, `:app`, or the elisp modules for
  new bugs; code was read only where a plan claim cited it. The JA-series P1 ledger is
  RF-0's business.
- **The RF-2 runbook's translation table.** `PLAN-rf2`'s org.json→kotlinx deltas
  (§2.3-2.5) were not re-derived; only its ledger, gates, and I1 restatement were in
  scope.
- **Web claims beyond the cited ones.** Room 3 target declarations and
  `BundledSQLiteDriver` flags were re-verified against the local clone; release-note
  claims (Room 2.x maintenance status, SQLDelight wasmJs absence, cr-sqlite dormancy)
  rest on the web verifier and are labeled agent-reported where load-bearing.
- **Machine verification of the appendix tail** — four leads, drafted or not, carry
  their labels; none was fed to a verifier fleet.
- **§16–§21 vocabulary sweeps** (the #34–#66 genres) — out of scope; the prior audit's
  appendix already inventories them.
