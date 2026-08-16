# AndroidX Paging 3 — the decision, the spike, and the escalation ladder (2026-08-13)

*Source: workflow `wf_da22e953-0f7`, 15 agents, 2026-08-13 — six source readers
(render path, wire, data layer, Emacs producers, governance, androidx clone),
three rival designs, three judge lenses, one adversarial verification pass.
The verification pass re-derived every load-bearing claim from source: zero
refutations; the nuances it surfaced are folded in below (§6). The androidx
clone was re-verified at `d69c96e6bc402016899904d66646816a62ebff4d` before any
citation was accepted — the same SHA every existing LIBRARY-LEDGER row cites.*

---

## §0 Verdict

**Do not adopt androidx.paging now.** All three judge lenses
(architecture-conformance, pragmatics/YAGNI, technical-risk) independently
ranked the same way: **C (no-paging) > B (vroom3-only) > A (wire-windowed)** —
and converged on the same composite:

1. **Now:** record a source-verified **non-adoption standing note** in
   LIBRARY-LEDGER.md (draft in §4, in the ledger's established jsonrpc/cr-sqlite
   form), land **three cheap no-wire fixes** (§3), and run the **3-day
   measurement spike** (§2) that converts today's judgment-chosen caps into
   recorded numeric thresholds.
2. **Trigger-gated:** the note names **room3-paging below `jetpacs-vroom3`'s
   typed DAO surface** as the *sole* pre-approved future home for the library
   (materializer tier, same rung cell as Room 3's row) — activated only if a
   Companion-owned dataset crosses the spike's recorded crossover *and* a
   vroom3 rung is actually scheduled. Its own 2-day toolchain spike runs then,
   not now (§5.1).
3. **Reserved, unspecified:** the wire escalation (`windowed_list` node + a
   Companion→Emacs `list.window` request in the `edit.complete` shape) is
   recorded as the pre-shaped C1 genre — deliberately **not** drafted, per
   Decision 9 — with one clause the tech-risk lens added: any future draft MUST
   include a restart-re-sync rule (§5.2).

Why this is not a close call: Paging 3 optimizes the one layer that is already
lazy. `lazy_column` composition is O(visible) today (SPEC.md:2380 — "The
Companion MAY compose only visible children"; LayoutNodes.kt:354 keys a plain
LazyColumn). Every cost the system actually pays sits where Paging cannot
reach: Emacs-side O(all-items) collection, a 4 MiB whole-snapshot wire with no
patch op, the full-tree validator walk, and all-surface persist amplification.
And the demand side is absent: no dataset within two orders of magnitude of
paging scale exists on the device, the wire's own caps make a 10k-item list
unshippable regardless, and the house has a ratified "narrow, don't page"
idiom — re-ratified *today* (amendment #172: "pagination deliberately absent").

## §1 The five facts that decide it

| # | Fact | Evidence |
|---|---|---|
| 1 | **A big list is unshippable before it is slow.** `max_frame_bytes` = 4,194,304 exactly; 10,000 nodes/snapshot, 10,000 children/node, depth 20 — and `MAX_NODES_PER_SNAPSHOT` counts parents, so realistic 3–10-node items cap a list at ~1,000–3,000 items. The binding constraint is the wire/validator, not rendering. | SPEC.md:207-217, :247; FrameCodec.kt:14-33; SpecValidator.kt:412-414 |
| 2 | **The wire has no windowing and no patch.** `surface.update` atomically replaces one complete snapshot; no partial-tree op exists; no scroll/viewport/end-reached event flows device→Emacs (scroll is spec'd device-owned presentation identity); `lazy_column` is `children` + `spacing` + `content_padding`, nothing else. The spec even *advises* "flatten or paginate" (SPEC.md:285-293) while providing no vocabulary for it. | SPEC.md:1361-1369, :1214-1247, :2138, :2380; Vocabulary.kt:46 |
| 3 | **There is no device-resident dataset to page.** All 8 JetpacsDatabase tables are protocol-capped EBP durability state (outbox ≤256 events/8 MiB, surfaces ≤4096 ids); surface content is one `spec_json` blob per row — no row-per-item table. `jetpacs-vroom3` is code-zero (plan non-goal, post-RF-4). The measured vault: 586 notes = 7.34% of one frame; ~8,000 notes to fill one. `:app` doesn't even depend on the core ring yet (app/build.gradle.kts:26). | JetpacsDatabase.kt:3-33; DeviceBridge.kt:158-162; PLAN-refound:44,:745-747; spike RESULTS.md:8-9 |
| 4 | **Every producer already bounds itself, as written policy.** Caps: tablist 100, customize 50, project find-file 200, files 300 render/2000 scan-stop, hub 100, org outline 400, sections 300, buffer 500 lines, complete 30, picker 12. Three docstrings state the doctrine verbatim ("narrow with a filter … rather than paging"); the M-x palette never ships the list at all (query-driven picker, ≤12/state); the M3 catalog narrows by navigation (never >~21 rows co-shipped). | jetpacs-tablist.el:45-49; jetpacs-customize.el:36-40; jetpacs-project.el:38-42; jetpacs-files.el:117-127; ebp-org.el:1680-1683; jetpacs-dialog.el:528 |
| 5 | **Governance points the same direction.** Decision 9: "Do not specify an optimization before measuring the need" — upheld twice by the 2026-07-31 spikes. `apps.list pagination` sits as a DEFERRED, unadvertised §20 capability row. Amendment #172 (ratified 2026-08-13) made "pagination deliberately absent" normative for candidate docs. The ledger records non-adoptions as standing notes precisely so absence reads as decision, not omission. | PLAN-refound:113-118; AUDIT-w7-conformance.md:434; DRAFT-amendments-169-172:408-412,:453-456; LIBRARY-LEDGER.md:27-37 |

What Paging 3 actually is, at the pinned clone (`d69c96e`, committed
2026-07-31) — recorded because it is *better* than expected, which is exactly
why the misfit finding is trustworthy:

- `paging-common` and `paging-compose` are full KMP (mac/linux/ios/watchos/tvos/
  js/wasmJs/mingw/desktop-JVM/android); commonMain deps are only
  kotlinx-coroutines + annotation (+ compose *runtime* for -compose)
  (paging-common/build.gradle:34-54; paging-compose/build.gradle:34-55).
- paging-compose ships **no `items{}` DSL** — the public surface is
  `collectAsLazyPagingItems` + `itemKey`/`itemContentType`, and the caller
  writes `items(count, key)` itself (LazyFoundationExtensions.kt:40-81). A
  generic node-tree renderer *could* drive it; nothing structural forbids it.
- `Pager` has public manual `append()/prepend()/refresh()/retry()` at tip
  (Pager.kt:119-185) — loads can be driven by wire signals, not just scroll.
- `paging-runtime` (RecyclerView/LiveData) is Android-only and not needed.
- Room integration exists **only as `room3-paging`** (namespace
  `androidx.room3.paging`; there is no room/ directory in the clone at all);
  it is KMP, pins RELEASED `androidx.paging:paging-common:3.4.2`
  (room3-paging/build.gradle:31-51), and its `LimitOffsetPagingSource`
  self-invalidates via a local InvalidationTracker flow with a
  post-load staleness double-check (LimitOffsetPagingSource.kt:82-176).

The misfit is not quality; it is **placement**. Paging solves presenter-side
windowing of a *device-resident* data stream. This system has no device-resident
list data (fact 3), forbids the demand signal that would feed a wire-backed
source (fact 2), and answers volume by narrowing (fact 4). An Emacs-backed
`PagingSource` type-checks (suspend `load()` can hold a JSON-RPC round trip)
but every Emacs-side edit becomes `invalidate()` → new generation → REFRESH
round trip over the wire — where Room's equivalent is entirely local.

## §2 The measurement spike (run now, ~3 days)

Design C's spike, adopted as-is by all three judges. It is the measurement
Decision 9 requires before *any* windowing can ever be specified, and it
replaces judgment-chosen caps with numbers.

**Goal:** pin the pain thresholds as integers; falsify or confirm that no pain
exists today. If pain is already present, the spike's own output is the C1
amendment trigger.

Steps:

1. **Kotlin probes** (debug build): timestamps at `FrameCodec.decode`,
   `SpecValidator.validateSurfaceSpec`, `SurfaceStore.persist`, and
   first-frame-after-spec; plus a one-line log probe on whether the StateFlow
   equal-value skip actually absorbs a byte-identical re-push (open question —
   `resolveView` returns a fresh subtree instance per push).
2. **Emacs probes:** timer around builder + `json-serialize` for the org
   outline, tablist, and hub producers.
3. **Workload A (real):** org outline over the largest real vault file and over
   the benchmark `large.org` (15,950 headline lines / 2,750 top-level — see
   §6.3) — collection time at cap 400 as-is, then with the §3.1 early-exit fix.
4. **Workload B (cap-scale synthetic):** Tier-1 test app pushes `lazy_column`
   of N ∈ {250, 500, 1000, 2000, 3000} three-node items; record bytes, parse,
   validate, persist, push-to-paint p50/p95 per N; confirm the validator
   rejection boundary near 10k nodes empirically.
5. **Workload C (mutation):** one-item change re-push at N=1000 — the
   full-resend cost windowing would amortize — plus the byte-identical re-push.
6. **Device checks:** scroll survives keyed re-push at N=1000; does *not* for
   keyless `lazy_grid` (before/after the §3.3 fix). Force-stop before smokes,
   per device-smoke practice.

Exit criteria (all binary or numeric, no qualitative language):

- Per-stage timing/bytes table for all N, p50/p95, on hardware.
- Org-outline collection measured with and without early-exit; fix merged if it wins.
- Thresholds recorded as integers in the ledger note. Proposed (spike pins
  final values): **T1** a real screen needs >1,000 multi-node items *after*
  filter/search/navigation narrowing; **T2** producer collection >150 ms or
  push-to-paint p95 >250 ms at current caps; **T3** a real push >2 MiB (50% of
  `max_frame_bytes`).
- A recorded verdict: "no threshold tripped — non-adoption stands, re-measure
  triggers named" **or** "threshold tripped at N=X / stage=Y — C1 amendment
  draft opened".
- StateFlow identical-re-push absorption confirmed or refuted.
- No wire vocabulary changed by the spike itself.

Re-measure triggers to name alongside the thresholds: any dataset genre
carrying body text per row (PLAN-refound:624-626's own trigger), orgseq block
vaults at scale, any proposal to raise `MAX_NODES_PER_SNAPSHOT`, any screen
that cannot narrow.

## §3 Three no-wire fixes (land regardless)

**LANDED 2026-08-13** — `a1ef26c` (bounded collection), `74f00ef` (trailing
note), `aa663f8` (lazy_grid keys + animateItem). Adversarial review
(`wf_41cdd03f-41f`, 3 reviewers) surfaced and the commits carry two extra
corrections: the pre-build level filter must reject star-only lines (they
match `org-heading-regexp` but not `org-outline-regexp` — admitting one
builds a ghost record from the previous real heading), and the note's
denominator must follow the branch that produced the records (an `items-fn`
returning nil falls through to the file path and must still note). Suites
green: ebp-org 74/74, outline view 3/3, strict byte-compile, `:app` compiles.

These resolve every pain the readers actually verified in source, with no
library, no amendment, no doctrine contact:

1. **Bounded org-outline collection** (Emacs). `ebp-org.el:1737-1795` builds a
   full record (components, tags, DEADLINE, properties, body substring) for
   EVERY headline before `seq-take`-ing 400 — in direct violation of the
   repo's own recorded bounded-scan lesson (jetpacs-files.el:124-127: "a cap
   that only truncates at render time still paid to collect and stat
   everything"). Early-exit at `ebp-org-outline-cap` during collection.
   *Regression care:* the level-1 filter currently runs after collection;
   an early exit must count only what the filter keeps, or it drops different
   headings than today (verifier-flagged).
2. **The missing truncation note** (Emacs). The 400-heading cap is the only
   silent cap in the codebase — `jetpacs-org-outline.el:78-93` appends no
   "Showing N of M" note, unlike every other capped module. Add the house
   trailing note.
3. **`lazy_grid` keys** (Kotlin, one line). `LayoutNodes.kt:1202` is
   `items(children.size)` with no `key` parameter, despite the doc comment
   claiming parity with `lazy_column` — grid re-sends lose key-based scroll
   re-anchoring and item identity. Give it `lazyChildKeys`, same as :354.
   (Note in passing: `lazy_grid` also has zero SPEC.md prose — it lives only
   in contract.json, a §2.2 defect independent of this decision.)

## §4 Draft LIBRARY-LEDGER standing note (pending ratification)

Ready to paste into the Standing notes section of LIBRARY-LEDGER.md once Caleb
ratifies; spike numbers fill the bracketed slots. Per Decision 8 discipline
this is drafted here, not applied — no entry lands without ratification.

> - **androidx.paging is not adopted** (2026-08-13, clone @ `d69c96e`, workflow
>   `wf_da22e953-0f7`) — recorded so the absence is legible as a decision, not
>   an omission. The library itself verified renderer-friendly at source:
>   paging-common/-compose are KMP with commonMain deps of only
>   coroutines+annotation(+compose-runtime) (paging-common/build.gradle:34-54,
>   paging-compose/build.gradle:34-55), and paging-compose ships no `items{}`
>   DSL — the caller keeps the items block (LazyFoundationExtensions.kt:40-81).
>   Not adopted because it windows device-resident data and jetpacs has none:
>   `lazy_column` children arrive inline under `MAX_NODES_PER_SNAPSHOT` = 10,000
>   (FrameCodec.kt:18) on an atomic whole-snapshot wire (SPEC.md:1363) with no
>   viewport signal (SPEC.md:1214-1247), composition is already O(visible)
>   (SPEC.md:2380), every producer caps at the source under the ratified
>   narrow-don't-page idiom (jetpacs-tablist.el:48 et al.), and no Companion
>   dataset exceeds [spike T1] items (measured [spike date]). Thresholds:
>   T1=[...], T2=[...], T3=[...]; re-measure on body-text-per-row datasets,
>   orgseq vaults at scale, any `MAX_NODES_PER_SNAPSHOT` raise, any
>   screen that cannot narrow. **Sole pre-approved future home** if a
>   Companion-owned dataset crosses T1 at a scheduled vroom3 rung:
>   `androidx.room3:room3-paging` (namespace `androidx.room3.paging`; KMP;
>   pins released paging-common 3.4.2 — room3-paging/build.gradle:31-51;
>   local self-invalidation, LimitOffsetPagingSource.kt:82-176) as
>   **materializer** below `jetpacs-vroom3`'s typed DAO surface, co-tenant
>   with Room 3's row; never inside ebp-sqlite, never in wire vocabulary,
>   never an Emacs-backed PagingSource (invalidate-per-edit = REFRESH round
>   trip per change, against §7.4 send non-atomicity). Adoption-candidate
>   coordinate at that time: evaluate the released **3.5.0** line first
>   (docs-public/build.gradle:302-308 publishes paging-common/-compose 3.5.0;
>   the in-tree tip is 3.6.0-alpha01 and describes tip, not artifacts;
>   room3-paging transitively pins 3.4.2). Wire escalation past a tripped
>   threshold is the reserved `list.window` genre (§20's deferred
>   'apps.list pagination' slot) — see PLAN-paging3-decision-2026-08-13.md §5.2;
>   unspecified per Decision 9.

## §5 The escalation ladder (neither step taken today)

### §5.1 Trigger-gated: room3-paging below vroom3 (Design B, deferred)

Runs only when (a) a vroom3 rung is actually scheduled in the live line AND
(b) the spike's T1 crossover is exceeded by a real Companion-owned dataset.
Then Design B's 2-day toolchain spike executes first: scratch module cloned
from core:database's build shape (jvm()+android, kspJvm/kspAndroid),
`PagingSource<Int, NoteRow>` DAO, three scales (586 / 8,000 / 16,000 rows),
TestPager-driven, measuring the Flow<List<T>>-vs-paged crossover integer and
the invalidations-per-256-row-ingest-chunk count (batched-transaction ingest
must yield exactly 1 — this constrains the ebp.data apply path). Its ledger row
then cites the coordinates actually resolved, not tip build files.

Known frictions, priced in advance: `PagingSource<Int,T>` in DAO signatures is
a heavier seam than `Flow<List<T>>`; `LazyPagingItems` hardcodes an internal
`expect uiDispatcher` (UiDispatcher.kt:21) that may force direct
`PagingDataPresenter` consumption under the renderer's threading; rc-line drift
until room3 stabilizes.

### §5.2 Reserved: the `list.window` wire genre (Design A's shape, unspecified)

If a threshold trips on an *Emacs-owned* list, the pre-shaped escalation is:
a new optional `windowed_list` node (never a reinterpretation of
`lazy_column`) + a Companion→Emacs `list.window` request
`{surface, list_id, generation, start, count}` in the `edit.complete` shape —
device-initiated, small bounded answer — so scroll position itself never
crosses the wire (the demand-for-data ≠ presentation-state argument;
`edit.complete` already ships full text + cursor). Two §25 amendments, one in
the heaviest genre (full §11 registry row). Key discipline moves to Emacs
(windowed loads can't run `lazyChildKeys`' whole-array dedup). Whether the
device half then rents Paging 3 (as infrastructure behind a `render/window/`
seam — note the ledger-header "capability-adjacent" vs I4 "capability" naming
drift when tiering it) or stays hand-rolled is decided by Design A's 4-day
spike at that time, not now.

**Mandatory clause the tech-risk lens added:** SPEC.md:3065 guarantees
reconnection over cached snapshots receives no `surface.update` — a persisted
`windowed_list` would strand a restarted-Emacs session on a dead generation
with unresolvable placeholders. Any future draft MUST include restart re-sync:
stale-generation answer on a cached snapshot falls back to `initial_window`,
and Emacs MUST re-push windowed surfaces at session establishment. Also to be
priced then: §22.3 behavior under ranged-load bursts, and invalidation-storm
cadence under real (not scripted) editing.

## §6 Verification corrections (nuances that survived, worth keeping)

1. **Coordinate picture corrected:** the designs framed the choice as
   "released 3.4.2 vs in-tree 3.6.0-alpha01". Refuted in part: the tree's own
   docs-public/build.gradle:302-308 publishes a **released 3.5.0 line**
   (including KMP paging-compose 3.5.0). Any future adoption evaluates 3.5.0
   first; room3-paging still transitively pins 3.4.2.
2. **Key re-anchoring is window-limited, not global:** `findIndexByKey`
   resolves through a nearest-range sliding map (~30 + 100 items around the
   current index — LazyListScrollPosition.kt:119-122,
   LazyLayoutItemProvider.kt:94-109). A first-visible item whose key moved
   beyond that window silently loses anchor. Bounds both today's re-push
   behavior at large N and any future windowed design's invalidation story.
3. **Headline arithmetic corrected:** `grep -c '^\*'` counts every level.
   `large.org` = 15,950 headline *lines* / **2,750 top-level**; the org manual
   424 / 27; the measured personal file 587 / 6. This *weakens* the
   silent-400-cap pain (it rarely bites on real files) and *strengthens* the
   collection-cost pain (full-record cost over all 15,950 lines to keep ≤400
   of 2,750). The §3.1 fix targets the part that is real.
4. **§22.3 close is conditioned:** receiver-overload close applies only when
   the endpoint cannot apply a method's defined safe conflation — surface
   snapshots have §22.2 latest-wins conflation, so list re-pushes can be
   absorbed rather than closing. (The sender ceiling also exempts single-flight
   mechanisms.)
5. **"Complete inbound set" overstated:** `log.error` and `rpc.cancel` are
   sender-Either. The paging-relevant negative stands — nothing carries
   scroll/viewport/data-demand — but cite the §11 registry rows, not the
   enumeration.
6. **Manual `append()/prepend()` on `Pager` is verified at tip only** — not
   confirmed present in the released 3.4.2/3.5.0 artifacts. If §5.2 ever rents
   Paging as its engine, verify against the adopted artifact.

## §7 Governance debris this decision surfaced (for Caleb, separate from paging)

- Nav 3, material3 1.5.0-alpha16, and coroutines entered the poc3 baseline
  with **no LIBRARY-LEDGER rows** — backfill or record as deliberate
  grandfathering before the next adoption argues from precedent.
- The ledger's Rung column speaks superseded RF names while
  ARCHITECTURE-POC3.md declares PLAN-poc3-rebuild's Phases 0-9 canonical — a
  new row today would not know which rung vocabulary to cite.
- Room 3's seam column ("below jetpacs-vroom3's typed DAO surface") is stale
  against its actual live use (RoomEbpDurableStore behind the portable
  EbpDurableStore seam, core:ebp-store — in code today).
- Ledger header says "capability-adjacent"; I4 and Decision 8 say
  "capability" (LIBRARY-LEDGER.md:6 vs PLAN-refound:106,:158-167).
- `lazy_grid` (+ carousel, fab_menu, button_group, pane_scaffold,
  navigation_rail, segmented_button, search_bar) exist only in contract.json
  with zero SPEC.md prose — §2.2 classifies that as a defect requiring
  correction.
- Hub `lazy_column` is built outside byte accounting (AUDIT-ja3:203) and
  `persist()` rewrites every surface's spec on every accepted update
  (SurfaceStore.kt:138-157) — both are real per-push costs, both orthogonal to
  paging, neither addressed by this plan.
