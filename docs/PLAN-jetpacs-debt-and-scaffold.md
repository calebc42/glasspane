# Jetpacs debt ledger + scaffold direction - 2026-08-14

Repo: `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-3` @ `3bc080c` (slop-fork/main). Written the day after the G9 device gate closed (f131130) and the m3-catalog Playground merge landed (3bc080c, K1a fix ce5619c), before the major Glasspane changes begin. Every item below was adversarially re-verified against the tree at HEAD; refuted candidates were removed (none survived to list — see §5 for confirmed wontfixes). Line numbers are the corrected ones, not the plan docs' stale copies.

---

## 1. Executive summary

**State:** the ladders are green — G9 closed on hardware, R0–R6 landed, P1–P3 closed, Playground merged. The debt is real but almost entirely *known and recorded*; the danger is not hidden rot, it is that the coming Glasspane rework compounds five specific items and buries three cheap ones. Nothing here blocks starting; four things should land first.

**Recommended execution order:**

0. **Push (minutes, today).** 11 commits unpushed — the Playground/K1a merge only; the G9 baseline f131130 is *already* on GitHub (D-8). While at it, `git add docs/PLAN-paging3-decision-2026-08-13.md` — the whole paging non-adoption record is currently **untracked**, one `git clean` from gone (D-13).
1. **Settings relocation (RATIFIED — first work item, §3).** Steps 1–3 land before the rework; step 4 is an owner ruling. ~2–3 days incl. a device batch.
2. **Pre-rework correctness batch (~1–2 days):** edit.apply caret arithmetic (D-1), dock `:badge` thread-through (D-9), EditorSession.diff two-ended scan (D-10), file the punch-#18 foundation advisory (D-4). All small, all sit directly under the rework's feet.
3. **Scaffold seams before surface polish (§4):** S7 (ratify the two-pole vocabulary) first, then S1/S2/S3 (+ the S5 rail-injection fix as a correctness patch). Do **not** rewrite the hub screen, drawer IA, or dock item until these land — they get rewritten against the new seams. S4 rides the settings-satellite migration.
4. **Doc-hygiene batch (an hour, batchable any time):** stamp the pylsp "still owed" sentence (D-15), stamp PLAN-rf5a superseded-with-remainders (D-16), stamp PLAN-m3-catalog-verification closed (D-17), note the stale JA-7/8 stamps (D-18).
> **COORDINATION HOLD (owner, 2026-08-14): a second agent is building the Org Mode app in this same branch** — mode-neutral reader/editor HOSTS (`jetpacs-reader.el`/`jetpacs-editor.el`), Org adapters, and a composition root (`jetpacs-org-mode.el`) replacing the direct jetpacs-org-render wiring. Seam work PAUSES after S1 until its changes land. **The Glasspane rework gains a prerequisite: it rebuilds ON those primitives** (owner directive) — its reader/detail/editing surfaces ride the hosts, not private forks. Open ruling for the rework plan: the capture + agenda-reminder ownership boundary — the Org Mode app's composition root claims both "belong to the Org app as a whole," and Glasspane currently owns both.

> **RESOLVED + PLANNED (2026-08-14): the hold lifted, the seams all landed, and the ownership ruling arrived — jetpacs-org-mode owns BOTH capture and agenda reminders (Caleb). Glasspane-on-primitives rework: planned → docs/PLAN-glasspane-rework.md** (ladder GR-0..GR-10, adversarially verified: 57 checks, 17 defects found and fixed in the doc). Executes the ratified capture+reminders ownership cutover to jetpacs-org-mode and this doc's §4 ordering-note directive (hub/drawer/dock rewritten against S1/S2/S3 at GR-8). Arms this ledger's tripwires as GR §9 T-2 (reverse-order replies → fund R4) and T-5 (persist amplification → graduate D-5); closes the S1–S5/S4-guest device-coverage debt at GR-1/GR-8; funds FOUNDATION-GAPS #2 (FAB registry) and #10 (dates util) at GR-7b. D-12 (Companion share intake) remains the first Companion-side follow-on after GR-4.

5. **Then the major Glasspane changes**, with two tripwires armed: reverse-order `event.action` replies during heavy wire traffic → fund R4 (D-6); hub/push cadence growth → SurfaceStore.persist amplification graduates to correctness-risk (D-5).
6. **Parked, trigger- or decision-gated (§2 tier 4):** widget/tile, rich reader/G4b, share intake, R7, SPEC prose backfill, spec-hole audit resume, JA-9/P4/JA-11 leftovers. Each returns by decision, not drift.

---

## 2. Debt ledger — ranked by (risk × how much the rework compounds it)

| # | Item | Kind | Effort | Rework coupling |
|---|------|------|--------|-----------------|
| D-1 | edit.apply yanks the device caret | correctness-risk | M | **direct** — every live-sync keystroke |
| D-2 | P1 desync/concurrency smoke ERT-only | missing-coverage | M | **direct** — editor-sync corner |
| D-3 | Kotlin quartet (SurfaceStore, ImageCache, LD-14, same-id dialog) | correctness-risk | M | high — dialogs + surface churn |
| D-4 | Punch #18: foundation `rendered-p` private, advisory never filed | process-trap | S | high — reader seams |
| D-5 | SurfaceStore.persist amplification + paging §7 governance debris | doc-drift → risk | M | high if push cadence grows |
| D-6 | R2/R4 informed-execution ladder deferred until H3 bites | deferred-feature | M | watch-trigger during heavy traffic |
| D-7 | E5 clip privacy tail + require-time repush defect | correctness-risk | M | medium |
| D-8 | Push debt: 11 commits (Playground/K1a merge) unpushed | process-trap | S | do first |
| D-9 | Dock `:badge` thread-through never landed (gap #5) | deferred-feature | S | cheap win, pre-rework |
| D-10 | EditorSession.diff double int[] per keystroke | perf (filed correctness-risk) | S | cheap win |
| D-11 | Strike span SPEC 17.2 amendment PARKED (gap #7, OQ3) | deferred-feature | S | rider on next amendment batch |
| D-12 | Companion share-sheet intake UNBUILT | deferred-feature | M | collides if capture is touched |
| D-13 | Paging §2 spike unrun; §4 ledger note unratified; **plan doc untracked** | deferred + hazard | M | commit the doc NOW |
| D-14 | G9 device-truth residuals (ripgrep, auto-revert, async first-count, +search-ENTER) | device-residual | S | next device session checklist |
| D-15 | pylsp smoke "still owed" sentence stale (it ran 2026-08-13) | doc-drift | S | misleads next session |
| D-16 | PLAN-rf5a never stamped superseded | doc-drift | S | dead-runbook trap |
| D-17 | PLAN-m3-catalog-verification ledger stale (sprint closed 265/279) | doc-drift | S | dead-runbook trap |
| D-18 | PLAN-jetpacs-apps rung stamps stale (JA-7/8 since resolved) | doc-drift | S | invites re-litigating |
| D-19 | Widget + QS tile: nodes + Companion renderer unbuilt (gap #1 STOP, OQ1) | deferred-feature | L | decision-gated |
| D-20 | Rich org reader bodies degraded; table node dead code (gap #6, OQ2, G4b) | deferred-feature | L | decision-gated |
| D-21 | Completion-ladder R7 (tabstops, inlay hints, active-parameter) | deferred-feature | L | trigger: a real Glasspane workflow |
| D-22 | SPEC.md prose missing for 12–13 contract-only node types | doc-drift | L | amendment batch owed |
| D-23 | AUDIT-spec-holes tail: ~178 P2 + ~98 P3 unverified; resume script absent from tree | missing-coverage | L | backlog |
| D-24 | Remaining scope deferrals: JA-9, P4, JA-11 leftovers | deferred-feature | L | none prerequisite |

### D-1 — edit.apply still yanks the device caret (worse than the plan recorded)

**Evidence:** PLAN-emacs-informed-execution-2026-07-25.md:254-258 (T2-queued ebp.el follow-up); `emacs/ebp.el` — `ebp-client-edit-apply` (1892-1947) sends `:cursor (+ start (length text))` at :1923, no sel members, no caller override; only `edit-move` (1949-1972) carries sel. **Blast radius grew since the plan:** `emacs/ebp-sync.el` (the §19 bridge, df8910c) routes *every* live-sync splice through it (:260, :552), and the Companion honors the wire cursor unconditionally by design (EditorSession.kt:126-134, comment :118-122 defers the choice to ebp.el). No resolving commit exists (f4f3c4c..0f793f1 never touches the arithmetic).
**Consequence:** every Emacs-initiated remote apply dictates end-of-its-own-splice as the device caret — a caret yank per keystroke-driven apply during concurrent editing.
**Fix shape:** three-case marker arithmetic in `ebp-client-edit-apply` — adjust the device's *last-known* caret (before-splice unchanged; inside-splice clamp; after-splice shift by `(length text) − del`). sel_start/sel_end omission stays recorded-fine (SPEC paired-or-omitted). **Effort M. Do before the rework leans harder on live sync.**

> **LANDED c038a9b (2026-08-14):** the arithmetic plus two base-freshness refinements — the applied cursor is adopted into the mirror (a burst of applies chains instead of drifting) and a device delta parks the estimate at its own splice end pending its best-effort report. Non-integer stored carets (never-reported or hostile float) fall back to end-of-splice. Nine test arms; the 43-suite gate had nothing pinning the old value — which is how the defect survived. On-hardware verification rides the D-2 smoke.

### D-2 — P1 desync/concurrency exit-gate sub-clauses never ran on hardware

**Evidence:** PLAN-glasspane-completion.md:294-297 ("Still owed: … P1's desync/concurrency smoke sub-clauses"); gate wording PLAN-poc1-parity.md:28-30 ("edit … concurrently; … forced desync recovers via one edit.resync with no wrong edit"); `test/smoke-files-sync.el` (repo-root `test/`, 182 lines) has zero desync/concurrent/resync steps — B1-B7 are sequential; ERT coverage only (`test/ebp-wire-test.el` :1256/:1636/:2114, `test/ebp-sync-test.el`). No commit a7e235b..3bc080c adds smoke steps.
**Consequence:** any Glasspane change leaning on editor sync inherits an untested-on-hardware corner — and D-1's fix will need exactly this choreography to verify.
**Fix shape:** add concurrent-edit + forced-desync steps to the device smoke and run them in the same batch that verifies D-1. **Effort M.** (Note: the *other* clause in that PLAN sentence — Termux/pylsp — is resolved; see D-15.)

### D-3 — the deliberately-open Kotlin quartet

**Evidence:** PLAN-emacs-informed-execution-2026-07-25.md:102-107 ("Known and deliberately open"); all four verified current: (a) `SurfaceStore.kt:28` — no synchronization anywhere in the file, while the store is process-wide (CompanionStores.kt:76) and engines are per-connection (DeviceBridge.kt:852) → overlap window during connection supersession; (b) zero `ImageCache.clear()` callers repo-wide (only the internal identity flush, ImageCache.kt:77) — the revocation seam awaits a forget-pairing path that doesn't exist; (c) LD-14: `putDraft` still calls `persistDrafts()` synchronously per keystroke (SurfaceStore.kt:379-388), no idle-timer seam; (d) `RenderDialogRoot` (Renderer.kt:304-310) keys `fields` *and* `defaults` on `remember(dialogId)` alone → a same-id dialog within one frame inherits its predecessor's fields (§18.1). The sibling serve()-finally ghost was fixed by R5 (PLAN-glasspane-completion.md:506-511).
**Rework coupling:** (d) is live ammunition for any dialog-heavy work — including the settings relocation's dialog moves (§3 step 2). (a) bites exactly during the reconnect churn heavy device testing produces.
**Fix shape:** (d) FIXED 3bfa990 (show-epoch keying via EbpApplication.DialogShow); (a) a Mutex or `@Synchronized` on the mutating paths; (b) wire clear() when a forget-pairing path exists (else stays parked); (c) debounce seam. Recorded, none silently dropped — but none fixed. **Effort M for the set; (d) alone is S and worth taking with §3 step 2.**

### D-4 — punch #18: the foundation-side advisory was never filed

**Evidence:** PLAN-glasspane-app.md:1075 (WONTFIX-as-app-edit, owed follow-up verbatim: "Correct home: a foundation-side advisory in the base repo's own review, verified against Glasspane per the cross-repo procedure."). `glasspane-org-reader.el:730,751` (lines shifted from the plan's 723/744 by the f8c090a punch sweep) — both the body and actions seams key off `jetpacs-org-render--files-rendered-p`, the double-hyphen private at `emacs/jetpacs-org-render.el:765`. No public accessor exists anywhere in history (`git log --all -S` empty); no REVIEW doc or FOUNDATION-GAPS entry covers it.
**Consequence:** a base-repo rename of the rendered-p internals silently breaks the Glasspane reader with no compile-time or test tripwire. If the rework touches reader seams, this coupling snaps first.
**Fix shape:** file the advisory now — public `jetpacs-org-render-rendered-p` accessor + test seam, verified against Glasspane per the cross-repo procedure. **Effort S.**

> **LANDED 348feb8 (2026-08-14):** the in-tree ruling collapses the advisory into the fix — the accessor is public, the reader migrated, the old private spelling is an alias pinned to the public fn by the mode suite.

### D-5 — SurfaceStore.persist amplification + the paging §7 governance debris (one sub-claim struck)

**Evidence:** PLAN-paging3-decision-2026-08-13.md:291-311 (§7). Verified current: (1) Nav 3 1.1.2 / material3 1.5.0-alpha16 / coroutines 1.11.0 wired (libs.versions.toml:7-8,21; app/build.gradle.kts:27,33-34) with **no LIBRARY-LEDGER rows**; (2) ledger Rung column speaks superseded RF names vs ARCHITECTURE-POC3's canonical Phases 0–9; (3) Room 3 seam column stale vs the live `RoomEbpDurableStore`; (4) "capability-adjacent" vs "capability" naming drift; (5) **the real per-push cost:** `SurfaceStore.persist()` (SurfaceStore.kt:155-158, persistRecords :138-144) rewrites *every* surface's full spec via whole-file atomic rewrite (SurfaceBacking.kt:118-132) on every accepted update (:305) and remove (:327). **STRUCK:** the §7 restatement of "hub lazy_column outside byte accounting" — fixed 2026-07-27 in eec7787 (`jetpacs-emacs-ui--charge-rows`, jetpacs-emacs-ui.el:127-156, budget-bound in jetpacs-chrome--build); §7 restating it on 2026-08-13 is itself doc-drift. A residual sliver survives as envelope-vs-2048-octet-headroom asymmetry (jetpacs-buffer.el:82). Replacing it as the sixth sub-item, and verified current: lazy_grid + 7 siblings exist contract-only with zero SPEC prose (→ D-22).
**Fix shape:** ledger backfill rows + column refresh (doc, S); persist() → per-surface dirty-record write or debounce (code, M) — **graduates to correctness-risk if the rework grows the hub or push cadence; arm it as a tripwire.**

### D-6 — informed-execution R2/R4 deferred until H3 bites (keep the trigger in view)

**Evidence:** PLAN-emacs-informed-execution-2026-07-25.md:242-244 (verbatim trigger: "take them up only if H3's reverse-order replies bite in practice"); ladder defined in RESEARCH-A8-2026-07-25.md:162 (H3 = jsonrpc.el replies leave in reverse receive order under §1.4 LIFO nesting, violating §7.4; not fixable without R4), :179-180 (R2 = notification-only deferral guard — **not** an H3 fix; R4 = own outbound queue, "the only thing that would fix H3"), :629, :184 (prerequisite: settle on-device socket buffer sizes before R4). Verified: no outbound queue in ebp.el (the :around at :535 is the W10 pause guard, not a queue).
**Label-collision hazard:** THREE other landed R2/R4 ladders exist (completion-ladder, RF-2b KMP, RF-2c — whose "H3" is FrameCodec, unrelated). This item is the *informed-execution* ladder only.
**Fix shape:** none now. **Tripwire for the rework:** heavy Glasspane wire traffic is the first realistic chance to observe reverse-order `event.action` replies — if seen, fund R4 (socket-buffer measurement first). Effort M when triggered.

### D-7 — E5 clip privacy tail, including a live require-time defect

**Evidence:** PLAN-audit-fixes.md:179-204 (all 8 boxes unchecked), :357-368 (Caleb's 2026-07-26 demotion), :384-385 ("E5 (demoted) remains."). Everything else in that plan stamped DONE/PASSED. Verified current: `emacs/jetpacs-clip.el` has no `jetpacs-clip-exclude-functions`, no max-age, no tombstone/retraction; `(advice-add 'kill-new …)` armed unconditionally at top level (:206). **The load-bearing sub-item is a live defect:** jetpacs-clip.el:186-187 registers its root at require time and `jetpacs-shell-define-root` still schedules a repush on a live session — a bare mid-session `require` ships the kill ring and claims the screen. §4 (:391-397) parks the magit denylist + dialog-gate thirds as accepted debt (§5 below). Also outside E5's scope: three unstamped "Filed during E1" items (:249-262) and two deferred sub-items (:330-332).
**Fix shape:** at minimum, take the no-push-at-registration piece (S) out of the demoted tail — it's a correctness defect, not privacy polish. The privacy riders (auth-source/epa exclusion, pre-pairing max-age, tombstone, retraction) remain the demoted M batch. Kill ring is device-persisted (SPEC 13.5).

### D-8 — push debt (corrected: smaller than memory says)

**Evidence:** `git branch -vv` → `slop-fork/main 3bc080c [ahead 11]`; **but** `git ls-remote` shows GitHub slop-fork/main = **f131130** — the G9 close and everything under it pushed today 12:19. The 11 unpushed commits are exactly the Playground/K1a merge (3bc080c + bb7606a..ce5619c incl. the K1a wire fix ce5619c). ebp submodule fully cleared: pin 2cd7387 = local hub = GitHub calebc42/ebp; no dangling pin. The "K1a fix on unmerged branch" memory is stale — merged locally as 3bc080c.
**Fix shape:** `git push`. **Effort minutes. Do first.**

### D-9 — dock `:badge` thread-through (gap #5, never landed, cheap)

**Evidence:** docs/PLAN-glasspane-app.md:907-913 ("a one-key :badge thread-through in jetpacs-chrome--dock-tab/rail is the right base change, scheduled any time before G5"); `git log --all -S':badge' -- emacs/jetpacs-chrome.el` empty — never landed on any branch; dock-item plist still `:label/:icon/:on-tap/[:selected]` (jetpacs-chrome.el:77-89, --dock-tab :177). Both consumers shipped the in-screen fallback *and cite the gap by name in-tree* (glasspane-agenda.el:20-22,582-583; glasspane-srs.el:30,570). `jetpacs-icon` already supports a badge (jetpacs-widgets.el:679, passed at :689 — the plan's :669 is stale drift).
**Fix shape:** one-key plist thread-through + the two consumers drop their fallbacks. **Effort S — take it before/during the rework; it ruled "right base change" and then silently never happened.**

> **LANDED 26e3963 (2026-08-14):** :badge rides the bar tab's icon and the rail item (both arms test-pinned incl. the bare-dot form); Glasspane's dock item wears today's memoised agenda count, nil-when-zero. The SRS due count stays in-screen deliberately — two numbers on one icon is mud; recorded at the old gap citations.

### D-10 — EditorSession.diff materializes two `codePoints().toArray()` int[] per keystroke

**Evidence:** PLAN-emacs-informed-execution-2026-07-25.md:691 (Tier-3 table: two-ended char scan, "~15 lines, same asymptotics, zero allocation. (Measured: diff is 22 ms of the 29 ms per-keystroke cost at the 4 MiB ceiling)"); current at EditorSession.kt:184-186 (the plan row's ":57-67" pointer is stale after the jvmMain move); on the keystroke path via Renderer.kt:809. No commit applied the rewrite (80728cd/2ece3b2/7f6bfde only moved the file / swapped JSON libs).
**Fix shape:** the ~15-line two-ended scan, the one actionable Tier-3 row (the rest — typed IR, content-hash reuse, jit-lock chunking, TextFieldState — stay behind their named thresholds). **Effort S.**

> **LANDED 8a0576c (2026-08-14):** char indices walk the UTF-16 forms, scalar counts ride alongside, only the deleted middle re-counts; EditorGoldenReplayTest pins the arithmetic unchanged.

### D-11 — strike span amendment PARKED (gap #7, open question 3)

**Evidence:** PLAN-glasspane-app.md:922-926, :1026-1030. Never ratified: zero "strike" in ebp/SPEC.md, SPEC-CHANGES.md (through #88), contract.json; `jetpacs-span` (:653 — the plan's :643-661 pointer drifted) has no `:strike`; color degrade live in all three consumers (glasspane-views.el:168-175; glasspane-org-reader.el:157,237-253, `#66BB6A`). Do not conflate with PLAN-glasspane-completion.md:183's *different* parked amendment (accept:true tap-provenance).
**Fix shape:** one-member SPEC 17.2 amendment, natural rider on whatever amendment batch the rework produces (likely alongside D-22's prose backfill). **Effort S; needs the parking decision made, not defaulted.**

### D-12 — Companion share-sheet intake UNBUILT

**Evidence:** PLAN-glasspane-app.md:821-824 (G9 catch 5, #20 resolved-as-absent); `companion/app/src/main/AndroidManifest.xml:26-58` — MainActivity carries only MAIN/LAUNCHER, remaining filters receiver-only, no ACTION_SEND anywhere. The sole ACTION_SEND in companion/ is DeviceBridge.kt:920 — the *outbound* share.send chooser (outbound half built, inbound absent). Emacs side ready: glasspane-capture.el:304-307 registers `share.text`/`org.capture.share` with `:any-surface t`, comment anticipating the Companion-stamped foreign surface string.
**Fix shape:** ACTION_SEND intent-filter + intake emitting `share.text` into the SPEC 14 pipeline, then answer the banked device question (what surface string the Companion stamps: absent / launcher's / foreign). **Effort M. First Companion-side collision if the rework touches capture.**

### D-13 — paging decision: spike unrun, ledger note unratified, **plan doc untracked**

**Evidence:** PLAN-paging3-decision-2026-08-13.md §2 (:88-138; exit criteria :120-133 all unmet — no probe code, no results doc, §4 draft at :195 still bracketed T1/T2/T3 slots) and §4 (:175-179 "no entry lands without ratification"); `grep -i paging docs/LIBRARY-LEDGER.md` empty. §3's three no-wire fixes DID land (a1ef26c, 74f00ef, aa663f8) — the memory's "§3 pending" is stale. **Deepening fact: the plan doc is untracked (`?? docs/PLAN-paging3-decision-2026-08-13.md`)** — the decision record and drafted note exist only in the working tree.
**Fix shape:** three steps, not two: (1) commit the doc **today** (rides D-8's push); (2) the ~3-day §2 spike pins T1/T2/T3 as integers; (3) Caleb ratifies and the note lands in LIBRARY-LEDGER.md. Until then the ledger reads as omission rather than decision — the exact failure it exists to prevent. **Effort M (spike); the commit is minutes.**

### D-14 — G9 device-truth residuals (next device session checklist)

**Evidence:** docs/PLAN-glasspane-app.md:846-852 (banked in the G9-close commit f131130): (a) external edits to open org files invisible — no auto-revert; seed NEW files or edit through the app; (b) unlinked mentions degrade to "ripgrep unavailable" — `pkg install ripgrep` in Termux lights the third mentions section, and **neither onboarding script installs it** (tools/onboard-tablet.sh installs openssh/rsync/python only), so even a re-provision leaves it dark; (c) vulpea full scan is async — first notes count reads 0. Plus the fourth banked truth at :829-831: the Search BUTTON echoes the build-time mirror — first query must go through the field's ENTER.
**Fix shape:** (b) one Termux command (consider adding ripgrep to onboard-tablet.sh's package list); (a)/(c)/(d) session practice. **Effort S; ride the first post-rework device batch checklist.**

### D-15 / D-16 / D-17 / D-18 — the doc-drift batch (an hour total)

> **ALL FOUR STAMPED (2026-08-14):** the pylsp clause amended with the desync half preserved (D-15), PLAN-rf5a superseded-with-remainders — poll replacement + :app hardening pointed at future cadence work, the #156/#157 reuse collision recorded (D-16), PLAN-m3-catalog-verification closed at 265/279 with the registry-not-grep counting rule and the archived-checkout warning (D-17), JA-7/JA-8 part-landed/part-retired resolutions on their rungs (D-18).

- **D-15:** PLAN-glasspane-completion.md:294-297 still says the Termux/pylsp smoke is owed — it **ran on hardware 2026-08-13** (proof in-tree: device/emacs-init.el Stage 3b's measured Pixel-Tablet cold-pylsp timings; harness at tools/onboard-tablet.sh, device/py/live.py; commits 6b7bbfd, 02e4087, f131130). Amend only that clause — the desync/concurrency half of the same sentence is still genuinely owed (D-2) and must survive the edit.
- **D-16:** PLAN-rf5a-editor-cadence.md:3 sits at "DRAFT … Nothing below §0 has executed" with 11 pending checkpoints, but the ebp-sync.el route (df8910c) + completion ladder superseded it. Stamp it — **not a blanket "superseded":** RF-5a's deliverable 3 (replacing the 1 s poll — jetpacs-emacs-ui.el:530-578 still runs the chars-modified-tick `run-at-time` poll) and the Companion :app hardening are live remainders to point somewhere; also its S1 amendment numbers #156/#157 were since reused by the m3-tier1 draft — executing it as written now collides.
- **D-17:** PLAN-m3-catalog-verification.md (:3-5, :14-16, :54, :70; resume commands even cd into archived llm-poc-2) presents itself as live resume state; the sprint since closed at 265/279 with 14 real `:unsupported` (registry counts, not grep — 20 raw hits include 6 infrastructure in jetpacs-m3-core.el). Stamp closed.
- **D-18:** PLAN-jetpacs-apps.md stamps (:707, :729) predate the parity track: JA-7 is part-landed (jetpacs-transient.el, af47d48) + part-retired by owner ruling (with-editor NOT a goal, PLAN-poc1-parity.md:26); JA-8 likewise (jetpacs-project.el/jetpacs-sql.el bde3bec; hosts not-ported-on-purpose, :71-76). Note the resolutions on the plan so a future inventory doesn't re-litigate.

### D-19 — home-screen widget + QS tile (gap #1, the only STOP; open question 1 unanswered)

**Evidence:** PLAN-glasspane-app.md:869-886 (STOP at :883), :1011-1018 (OQ1, recommendation "ship without", no recorded answer). Spec side done (tile amendment #87, ebp/SPEC-CHANGES.md:54; `surface_spec_variants.tile` contract.json:2730-2743); Emacs seam done (`jetpacs-widget-surface` widgets.el:2850; widget:/tile: classification shell.el:170-178; gate :720-729). Missing halves verified absent: no widget_item/widget_divider/tile in the 52-type list (jetpacs-vocabulary.el:34-85); zero AppWidgetProvider/Glance/TileService in companion/; **bonus: CompanionEngine.kt:796-803's capability gate maps only notification and widget — `tile:` falls to else→null, so Companion-side tile gating is also unbuilt.** Phase 9 (PLAN-poc3-rebuild.md:345-353) reserves the Glance/TileService projections.
**Fix shape:** a future track needs only node vocabulary + a Companion renderer. **Effort L; decision-gated — get OQ1 formally answered (recommendation on record: ship 1.0 without).**

### D-20 — app-reader rich bodies degraded; table node has no render host (gap #6, OQ2, G4b unfunded)

**Evidence:** PLAN-glasspane-app.md:914-921, :1019-1025, :1091 (punch #26 "NOT closed here" residue). Live in code: glasspane-org-reader.el:144 ships bodies as plain `(jetpacs-text body :syntax "org")`; `glasspane-table-node` (glasspane-table.el:420) has zero production callers — dead code (sole ref: test :3602). Tier-0 buffer skin unaffected. OQ2 (accept vs fund G4b) is recommended-accept but **unratified** — the "ALL RESOLVED" block at PLAN-glasspane-completion.md:597 is that doc's own decision points, not this one.
**Fix shape:** ratify OQ2 one way; if accept, either delete or explicitly park the table node. **Effort L only if G4b is funded; the decision itself is S.**

### D-21 — completion-ladder R7 (tabstops, inlay hints, eldoc active-parameter)

**Evidence:** PLAN-glasspane-completion.md:680-685, verbatim trigger: "Take only when a concrete Glasspane workflow demands them." Zero implementation anywhere (grep + `git log --all` clean incl. the Playground branch). All §25 class-2/3 additive with precedent.
**Fix shape:** none until triggered — **but the coming rework may supply the trigger** if it grows programming-mode surfaces; this is the pre-approved next rung shape. Effort L.

### D-22 — SPEC prose missing for the contract-only node types (undercounted: 12–13, not 11)

**Evidence:** PLAN-paging3-decision-2026-08-13.md:304-307; ebp/SPEC.md:50-60 (§2.2: prose↔contract mismatch = defect); SPEC-CHANGES row numbering skips #153-#167 (row #168's artifact column reserves them; the m3-tier1 batch is **#156-#167**, #153-#155 belong to the rf-4a sibling line); types 42-52 landed as contract-only commits (07752d8..6219637). Word-boundary scan: tooltip, split_button, pane_scaffold, navigation_rail, search_bar, segmented_button, app_bar_row/column, carousel, fab_menu, button_group, lazy_grid entirely absent from SPEC.md; dropdown only incidental (caret prose :1899-1907). A validator generated from prose and one from contract now disagree about ~13 types.
**Fix shape:** prose-backfill amendment batch — scope in tooltip and split_button; natural companion to D-11's rider. **Effort L.**

### D-23 — spec-hole audit tail: ~276 candidates unverified; resume state not in this tree

**Evidence:** docs/AUDIT-spec-holes-2026-07-24.md L9-26 (306 verifiers died at spend limit; ~178 P2 + ~98 P3 unverified), L402-405 (resume wf_0260ae90-308). The 20 hand-verified holes ARE closed (P1s→#80-#86, P2s→#67-#79, tile→#87). Currency affirmatively proven by AUDIT-plan-spec-adversarial-2026-07-31.md:552-568 ("its unverified tail remains unverified"; appendix machine verification never ran). **Caveats:** (a) the resume script (workflows/scripts/…) does NOT exist in llm-poc-3 — no workflows/ dir; recover the cache/journal from the llm-poc-2-era location first (per the verifier-failure-trap memory: absence of a machine verdict is not refutation; the cache replays). (b) Two appendix leads since incidentally closed: pre-auth DoS (bounded by #147) and occurred_at_ms clock (#81). The remainder (image.https DNS-rebinding, chart.kind fallback, session.ready failure cell, unpinned §18.6 clocks, zero-permitting at-most-ones, password-in-durable-work-item, the §12-rule-6 vocabulary sweeps) is unmined.
**Fix shape:** recover workflow state, re-run Verify+Skeptic. **Effort L; backlog, not pre-rework.**

### D-24 — remaining scope deferrals (narrowed after correction)

Genuinely open: **JA-9** (triggers UI — PLAN-jetpacs-apps.md:746, no authoring code exists), **P4** (automation authoring — PLAN-poc1-parity.md:81-88; trigger wire/runtime already conform; governed by the §5 weak-language compiler decision when taken), **JA-11 leftovers** (tools-hub view + opaque-member linter; the devtools core — profiler + flight recorder — already exists, 16c54ac). JA-7/JA-8 are **off this list** (resolved/retired — see D-18). None is prerequisite to the Glasspane work; listed so breadth returning is a decision, not drift.

---

## 3. Settings relocation — RATIFIED, first work item

The owner has ratified moving Glasspane's emacs-native settings surfaces to the foundation. Full inventory verified; the sequencing principle: **land all of this before the major Glasspane changes — every moved surface is a surface the rebuild then doesn't have to carry.** Precedent to build on: device/init.el:73-97 already registers curated foundation-defcustom sections at boot.

**New foundation module: `emacs/jetpacs-org-settings.el`** (jetpacs- prefix correct under the 2026-08-06 naming rule — it renders companion widgets and writes floor registries), required from device/init.el next to the existing curated block.

> **STEPS 1 + 4 LANDED a0a9d3b (2026-08-14; step-4 ruling: YES).** `emacs/jetpacs-org-settings.el` carries the six sections (babel timeout stays app-side), the foundation whole-table after-set, the two previously unsurfaced rows, and the guarded interactive-only seeding; line-numbers folded into the host Appearance section, its node and verb deleted; org-defaults.el survives as a managed stub so config.sync overwrites stale device copies. Gate 44 suites green. Steps 2 (editors + dialog slot) and 3 (theme-picker) remain.

### Step 1 — schema-section moves (S, ~half a day incl. tests)

Pure data relocation, no dependencies:
- The five sections from `glasspane-table--settings-sections` (glasspane-table.el:475-514) verbatim minus `glasspane-babel-timeout`: Org Workflow, Org Agenda, Org Editing & Display, User Defaults, Calendar & Location. Registered at load (the "registered at boot so a queued toggle replays" rule).
- The "Reader" section (glasspane-org-reader.el:792-799): the two `ebp-org-outline-show-*` foundation defcustoms (ebp-org.el:1687-1691).
- **The one seam that must be redesigned:** `:after-set` becomes foundation-owned — `(ebp-org-cache-invalidate)` with NO namespace (drops the whole memo table; slightly broader than today's `'glasspane`, benign, correct for any future app). Delete `glasspane-ui-org-after-set` (ui:928-934).
- `jetpacs-line-numbers` as a PLAIN schema entry folded into device/init.el's existing "Appearance" section — its choice-of-consts custom-type renders an equivalent enum; delete `glasspane-ui--line-numbers-node` (ui:420-438) and the `settings.line-numbers` verb outright.
- Consider adding `ebp-org-roots` and `org-default-notes-file` rows while there (both currently unsurfaced).
- Tests: test/glasspane-test.el:876-1013 asserts section/link registration + the line-numbers node; moved coverage lands in test/jetpacs-settings-test.el or a new jetpacs-org-settings test.

> **STEP 2 LANDED 7b7529a + STEP 3 LANDED 9ac25cb/7c2a983 (2026-08-14); D-3(d) fixed 3bfa990 in the same batch as planned.** The editors are jetpacs-org-settings.el's ownerless jetpacs.org.* family behind the foundation "Org workflow" satellite (order 50); the one-live-dialog slot is jetpacs-settings-show-dialog/close/params; the :any-surface dance for the moved verbs dissolved (asserted absent from the set); the three app sections consolidated into ONE "Glasspane" block; the theme-picker scaffold is emacs/jetpacs-theme-picker.el (gap #8 reversed). DEVICE-SMOKED on the tablet: satellite renders, sequence edit dialog → save persists to the customize block ("TODO" → "TODO, DOING"), card re-renders + snackbar, reopen seeds fresh (the D-3(d) epoch plumbing live), new APK + tree deployed. Gate 45 suites. §3 is COMPLETE — steps 1–4 all landed.

### Step 2 — TODO-sequence + tags editors + dialog slot to foundation (M-L, 1–2 days incl. device batch)

Depends on step 1 only for the after-set home. Moves wholesale:
- Pure helpers (ui:359-394 + agenda.el:689-695), `todo-keywords-apply` incl. the `customize-save-variable` + `org-mode-restart` sweep (agenda.el:697-707), dialog builder (ui:609-663), card renderer (ui:463-504).
- Tags editor: `--tag-options`/`--tags-enum` (ui:398-418) + `--on-tags` (ui:773-794).
- Verbs renamed into foundation namespace (`jetpacs.org.todo.edit/.save/.delete`, `jetpacs.org.tags`), registered ownerless at load like `settings.set`/`settings.reset` (jetpacs-settings.el:353-354) — **which dissolves the entire `:any-surface` dance** (ui:1000-1009).
- The one-live-dialog slot machinery (ui:556-607 + agenda.el:709-718) — the move **eliminates the existing cross-module reach** (agenda.el:715 reads glasspane-ui's dialog slot). Origin-params refresh shrinks to plain `jetpacs-settings-refresh` (jetpacs-settings.el:309-313) instead of the app's origin-tracking `--defer-refresh`.
- Surfacing: a foundation satellite screen ("Org workflow" via `jetpacs-settings-add-link` near the foundation orders) matches current UX.
- **Behavioral notes:** (i) verb renames mean an offline-queued `settings.todo.save` from an older session answers `rejected` post-upgrade — benign by design, record it; (ii) **dialog flows must be smoked ON DEVICE** — the S3 dialog + captured-fields path is exactly the class the device-smoke practice exists for, and exactly where the D-3(d) same-id dialog defect lives: take that Kotlin fix in the same batch.
- Glasspane shrinks to thin references: settings screen = Saved Searches alone; subtitles (ui:249, ui:549) → "Saved searches"; `--verbs` tables drop the moved verbs; **opportunity:** consolidate babel timeout + Journal landing + Packages auto-install into ONE "Glasspane" app section, collapsing three single-entry sections.

### Step 3 — theme-picker scaffold promotion (S, ~an hour)

Rename glasspane-theme-picker.el → emacs/jetpacs-theme-picker.el (reverses gap #8; the scaffold requires only cl-lib/jetpacs-widgets/jetpacs-theme, zero glasspane symbols); glasspane-ef.el stays app-side requiring the new name (ef-themes is in the app's package set). Independent, mechanical, plus a prefix grep in tests/docs.

### Step 4 — glasspane-config.el content: OWNER RULING, not a silent move

The org-defaults.el content (inbox seeding, agenda-files fallback, log-into-drawer, babel languages — config.el:51-105) is emacs-native and phone-generic, but the subtree machinery is governed by the standing **FOUNDATION-GAPS #4 DEFER** ("promoted to the store only if a second app wants it", config.el:23-35) and the store-adoption consent model (config.el:168-182). If the ratified directive extends here, the cheap shape: org-defaults content → jetpacs-org-settings.el as soft seeding at load (same only-while-stock guards); capture templates stay Glasspane's opinion. **Flag it; execution afterwards is XS-S.**

### Recorded non-moves

Saved Searches (`glasspane-org-custom-agendas` — Jetpacs-side query grammar, sole consumer glasspane-agenda; if it ever moves, its home is the ebp-org layer, not jetpacs-settings); Review/org-srs limits (availability-gated on an app-installed package — moving gives the foundation an org-srs probe dependency); Journal landing; Packages auto-install; gallery link; the unsurfaced app defcustoms. **Companion side: ZERO work in this batch** — every surface rides existing wire vocabulary (settings.set/reset, enum_list, dialog.show).

---

## 4. Scaffold direction — the two poles and the seams

**Frame:** two legitimate poles for a Jetpacs app. **Deep integration** (Glasspane as the exemplar: feels like Jetpacs *tabs*, not a guest) and **full rejection** (the orgseq/orgzly-native pole: standalone chrome, own IA, shell stays out of the way). Today Glasspane "feels like a different app" not because the architecture is missing but because the composition seams are: the shell dock already persists into every app (jetpacs-chrome--build:345 injects unless authored), defapp/registry/drawer-rows/theming/resume all work, and cross-owner guest screens *already work ad hoc* (glasspane.settings.open pushes onto whatever surface was tapped, ui:743-756). On the rejection side, raw-scaffold builders, owner-scoped verb isolation (the D1 gate, jetpacs-surfaces.el:770), and notification:/widget:/tile: presence already exist.

### Seams to build (sized), in order

- **S7 — ratify the two-pole contract in docs/CHROME-VOCABULARY.md** (S). **Do FIRST** — it names the vocabulary every other seam implements. Currently line 9 ("Tier-1 apps may deviate") is the only hook; the legal-but-undocumented escape hatch (raw scaffold keeps back/error-isolation/budget while rejecting chrome) gets stated here.

  > **LANDED (2026-08-14): CHROME-VOCABULARY.md v3 carries "The two integration poles"** — build-within (the default; S1 destinations from poc-1 `:views`, S2 app-primary dock, S3 global actions, S4 sanctioned guests) and standalone (`:chrome 'standalone`, S5) with the four non-rejectable invariants (back, error isolation, push budget, M-x parity) and the honest Companion-tier limits (one activity, session-global theme, last-push-wins, no per-app identity). The S5 injection rule is now ratified WORDING the fix implements: authoring any dock slot opts out on every slot.
- **[LANDED a7216c6 + review fixes]** **S1 — destination/route registry + central deep-link verb** (M, jetpacs-apps.el). `glasspane-ui-destinations` (ui:147) is exactly the right shape but private to its hub, and its verbs are owner-scoped so a host-drawer row would be refused by the foreign-surface gate. A `:destinations`/`:routes` key on jetpacs-defapp + `app.open` extended with `:route` solves the gate problem **once, centrally**, instead of `:any-surface` proliferation. The registry must live in base (jetpacs-apps) with device/init.el's hub as a consumer — the hub is currently host-authored and can't portably receive app contributions. Biggest single step toward the exemplar. **Owner note (2026-08-14): this existed in poc 1 — S1 is restoration, not invention. Verified: v1's `jetpacs-defapp` (llm-poc/emacs/core/jetpacs-apps.el:88, `:views` key) had apps CLAIM named views and the SHELL compose them — "one app's tabs in the bottom bar at a time," `app.open` switching, unclaimed core views showing in every app, launcher machinery appearing only with a second app, and owner-scoped registration spanning views/actions/settings-links/drawer-items/top-actions (S1+S2+S3 in one mechanism). v3 lost the composition when apps became whole-surface owners. Mine that file's contract comments before designing; the v3 shape should port the claimed-views composition onto surfaces/chrome-screens deliberately.**
- **[LANDED 496b001]** **S2 — dock composition policy** (S, pure jetpacs-apps-dock-items logic + tests). Today's compose is core(2) + app(1) + Apps(1) = 4 of the M3 3–5 budget with no negotiation. An "app-primary" mode (core collapses to one Home; app contributes ~3 tabs; Apps folds into drawer) is what makes Agenda/Journal/Search feel like Jetpacs tabs.
- **[LANDED 496b001]** **S3 — global top-bar actions seam** (S). M-x is a global verb (jetpacs-emacs-ui.el:791) but only the hub authors the button; a chrome-level global-actions injection (symmetric to the dock seam, opt-out flag shared with S5) makes shell globals persist into apps.
- **[LANDED 2026-08-14]** **S4 — guest-screen sanctioning** (M — dispatch gate + chrome stack + teardown). The actual debt of the working ad hoc pattern: six Glasspane verbs went `:any-surface` solely because their emission site is a foreign stack (ui:1000-1027); screen ids on a shared stack are unnamespaced; teardown sweeps only the owner's OWN surfaces, so a stranded guest screen survives its app's unload as a rebuilt error card. Needed: scoped delegation ("owner X may receive events from surface Y while stacked there"), guest id prefixing, foreign-stack teardown sweep. **The settings-satellite migration (§3) rides this and deletes the six `:any-surface` declarations.** This is the seam with pre-existing debt compounding — every new satellite screen adds more.

  > **LANDED (2026-08-14):** `jetpacs-guest-delegation-function` seam in the D1 gate (surfaces stays kit-agnostic; chrome installs `jetpacs-chrome--guest-delegate-p`); `jetpacs-chrome-push-screen` prefixes a foreign-stack push's id (`guest-OWNER-ID`) and records it in `jetpacs-chrome--guests`; validity derives from the LIVE stack, so a Companion-local back revokes with no bookkeeping; `jetpacs-chrome-sweep-guests` rides `jetpacs-teardown-functions` AND owner-form `jetpacs-chrome-remove`, scheduling a repush on each touched host surface. **Test-caught foundation defect fixed in the same change: the presenting push used to CLAIM the host's surface for the guest** (`jetpacs-shell-push` claims under the bound owner) — an unscoped D1 grant, unprefixed re-pushes, and the host's root swept by the guest's teardown; the guest push now binds the owner of record around the send. Glasspane drops: `settings.agenda.edit`/`.delete` + `glasspane.packages.install` lost `:any-surface` (covered by delegation from the guest settings/ef/srs screens); the openers (`glasspane.settings.open`, `ef.show`, gallery/clock/capture verbs) keep it — their taps arrive before any guest screen exists or ride durable notifications.
- **[LANDED 496b001]** **S5 — standalone chrome exemption + rail-injection fix** (S). An app cannot subtract core dock items today; the per-screen `:bottom_bar` workaround **leaks on medium/expanded windows** — the plist-member guard (jetpacs-chrome.el:386) tests only the slot the dock chose, so an authored bottom bar does not suppress the injected `:rail`. `jetpacs-defapp :chrome 'standalone` consulted by both jetpacs-apps-dock-items and --dock-slot, plus the rail fix — **the rail fix is a correctness patch regardless of pole.**
- **[RESOLVED — was doc-drift]** **S6 — snackbar into current view** (M, known deferred shell work). jetpacs-shell-notify degrades to toast on any multi-view surface (H10 note, jetpacs-chrome.el:28-32) and every chrome app IS multi-view.

  > **RESOLVED (2026-08-14): the behavior had already landed 2026-08-02 (1ad6bde)** — `jetpacs-shell--inject-snackbar` reaches into the CURRENT view's scaffold on a multi_view spec (VIEW arg, else `initial_view`), copy-on-write, degrading to a toast only when that view's root is no scaffold. This ledger entry was drift off the stale H10 note, which is now rewritten in place (jetpacs-chrome.el:28-32). What was genuinely missing was COVERAGE: the injector had zero tests — `jetpacs-chrome-snackbar-injector-reaches-current-view` now pins all three arms.

**Ordering note:** S1/S2/S3 are independent of the planned Glasspane changes and *shape* them — the hub screen, drawer IA, and dock item all get rewritten against the new seams; do not polish those surfaces first. One interaction to watch: `jetpacs-chrome-max-screens` is 3 and guest screens contend for a host stack's slots (S4). **Out of Emacs-side reach (spec/Companion tier, note only):** per-app theme (theme.set is session-global — corollary: glasspane-ef's picker restyles the whole shell today, which is build-within behavior whether intended or not), per-app Android identity (task/launcher shortcut/share intake — D-12), immunity from last-push-wins screen theft (the clip auto-refresh precedent, device/init.el:99-102, and the D-7 require-time repush are both instances). A standalone-feeling orgseq still shares one activity, one theme, one screen.

---

## 5. Not debt / wontfix confirmed

Checked and deliberately NOT on the ledger:

- **Refuted candidates:** none survived to list — every submitted item confirmed (some corrected in scope; corrections are inline above).
- **Saved Searches manager stays app-side** — Jetpacs-grammar config for Glasspane's agenda screen, not org's native notion (`org-agenda-custom-commands` untouched anywhere in the repo).
- **Review/org-srs section stays app-side** — availability-gated on an app-installed package; moving it gives the foundation a probe dependency.
- **glasspane-config.el subtree machinery** — governed by the standing FOUNDATION-GAPS #4 DEFER; step 4 of §3 is a ruling request, not debt.
- **sel_start/sel_end omission in edit.apply** — recorded-fine per SPEC paired-or-omitted (until selection-carrying applies matter; distinct from the caret bug D-1).
- **Punch #18 as an app edit** — WONTFIX stands; the debt is the unfiled foundation advisory (D-4), not the app coupling itself.
- **§4 accepted-debt P3s in PLAN-audit-fixes** (magit denylist, dialog-gate thirds) — parked by explicit ruling, not lost.
- **JA-7 git-from-tablet / JA-8 hosts** — resolved/retired by owner decisions 2026-08-04 (transient landed af47d48; with-editor NOT a goal; project/sql landed bde3bec; hosts superseded by EBP pairing). Only the doc stamps are debt (D-18).
- **Hub lazy_column byte accounting** — fixed eec7787 (2026-07-27); the paging plan's §7 restatement is drift, struck from D-5. Residual sliver: envelope-vs-2048-octet headroom asymmetry, noted there.
- **androidx.paging adoption** — NOT adopted, unanimous 2026-08-13; the debt is recording the decision (D-13), not revisiting it.
- **Tier-3 deferred rows** (typed UiNode IR, content-hash reuse, jit-lock chunking, TextFieldState migration) — stay behind their named thresholds (~1,000 non-lazy nodes / >256 KiB documents); only the diff rewrite (D-10) is actionable now.
- **ebp submodule push state** — fully clear: pin 2cd7387 = local hub = GitHub on both local HEAD and pushed tip; the memory's "ebp first" half is discharged.