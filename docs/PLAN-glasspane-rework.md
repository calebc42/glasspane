# PLAN — Glasspane rework: machinery-first rebase onto the org primitives + IA/UX restructure

Repo: `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-3` @ **dec2830** (slop-fork/main).
Written **2026-08-14**, after: org primitives landed in one commit (401a55e — `jetpacs-reader.el`/`jetpacs-editor.el` hosts, org adapters, `jetpacs-org-mode.el` composition root), ALL scaffold seams S1–S7 landed (2625953, a7216c6, 496b001, dec2830), settings relocation §3 complete, D-1/D-3(d)/D-4/D-9/D-10 fixed.

**Authority:** the understand-phase map (glasspane-map-synth + per-module readers, 2026-08-14: 16-row duplication matrix, 5 ownership collisions, 12 upstream candidates, 14 risks). Every claim this plan's rungs stand on was re-verified in-tree at dec2830 while drafting; cites are file:line at HEAD.

**Companion doc:** `docs/PLAN-jetpacs-debt-and-scaffold.md` (ledger register + the S1–S5 seam entries this plan builds on). This doc does NOT edit that one; §11 carries the cross-reference stamp to add there on its next edit.

**Ladder prefix is GR- (Glasspane rework)** — deliberately not R- or G-: three landed ladders already use R2/R4/R6 and one uses G0–G9 (the documented D-6 label-collision hazard). A fresh session resuming "GR-4" from this doc alone cannot land on the wrong ledger.

Full ERT gate everywhere below = `test/run-tests.sh` (46 suites at HEAD **plus every suite this plan adds — the runner is an EXPLICIT list; a suite not named there never runs. That is the K1a merge lesson, and each rung that adds a suite names the wiring step.**)

---

## §0 Ratified inputs (decisions, not options)

**RATIFIED (Caleb, 2026-08-14):**

1. **OWNERSHIP:** jetpacs-org-mode owns BOTH capture and agenda reminders. They migrate to jetpacs-org-mode as org-generic machinery; Glasspane consumes/extends them like any build-within app. The device-verified Glasspane implementations are the ones with hardware coverage — their code/UX moves under the new owner in preference to keeping the ERT-only org-mode versions, absorbing each side's exclusive extras (org-protocol + prefix-template filtering from org-mode; sheet-chain UX + share stash + `org.capture.share` replay alias from Glasspane).
2. **SCOPE:** the rework = rebase onto the reader/editor primitives + full seam adoption AND an IA/UX restructure — hub, navigation, and screen inventory get rethought, not just machinery.
3. **LAYERING (Caleb, 2026-08-16):** dependency direction is strictly **EBP → Jetpacs → Glasspane**. Jetpacs has no knowledge of Glasspane; the app is eventually extracted to its own repository. Native Emacs mechanisms belong to Jetpacs, while product opinions and placement belong to Glasspane. Glasspane consumes Jetpacs and EBP's Kotlin implementation and remains **entirely Elisp** — no Glasspane Kotlin layer. The executable guard is `test/run-tests.sh`'s zero-`glasspane` scan over top-level `emacs/*.el`.
4. **OR-1 RATIFIED (Caleb, 2026-08-16):** the org-clock chronometer and clocking machinery move to Jetpacs at GR-5. Glasspane retains only its opinionated affordance placement (for example, the detail-screen clock-in icon).
5. **OR-2 RATIFIED + EXECUTED (Caleb, 2026-08-17; PA-3d):** ef-themes and the component gallery are org-free Jetpacs facilities.  Ef lives at `emacs/apps/ef-themes/jetpacs-ef-themes.el` under owner `jetpacs.ef`; the gallery lives at `emacs/jetpacs-gallery.el` under owner `jetpacs.demo`.  Glasspane neither loads nor registers nor tears either one down.
6. **OR-4 RATIFIED (Caleb, 2026-08-17):** accept the readable plain-Org fallback instead of funding G4b now.  “Rich bodies degrade” means an app reader may show body text as plain, readable Org syntax when its richer renderer is unavailable; rich rendering remains in use wherever a supported host exists.  This is not a system-wide downgrade and does not remove rich rendering.  The ruling unblocks GR-10/PA-5's table/Babel ownership move.

**PROPOSED, NOT RATIFIED — open rulings for Caleb (flagged at every rung they touch; executing a flagged rung requires the ruling first):**

- **OR-3** the demo org corpus follows the capture/agenda owner; the IDE-tour half is foundation demo material. Rung GR-10.
- **OR-5** GR-8a's final tab list (mechanism is committed; the four names are a one-list edit if Caleb prefers a different split).

## §1 Hard invariants (violating any is a plan defect)

- **I-1 Durable verb names never change.** `org.clock.out`/`.switch`/`.in-last` ride ttl-3600 PendingIntents (glasspane-clock.el:36-96); `org.capture.share` + `share.text` ride offline-queue receipts and the older-Companion replay alias (glasspane-capture.el:282-307). A vanished verb turns queued replays into permanent `rejected` receipt deletions and orphans posted notification actions. §3 is the per-verb contract table.
- **I-2 Reminder cutover ordering.** Device reminder sets are device-lifetime durable; `rearmAllReminders` re-arms orphans from ebp-reminders.json every boot; teardown sweeps LOCAL bookkeeping only (jetpacs-device.el:182-192, by design). The losing owner's set is cleared via `(jetpacs-reminders-clear LOSING-OWNER CALLBACK)` while connected + `reminders.owner` granted, and the clear's **confirmation callback is observed before proceeding** — the session mirror is never trusted to skip a clear (jetpacs-device.el:170-176 says exactly this). Ceremonies in §5.
- **I-3** The live duplicate-alarm defect (both after-push hooks armed at HEAD: jetpacs-org-mode.el:550-551 and glasspane-agenda.el:736-737) gets an **immediate mitigation rung** (GR-0), not just the eventual cutover.
- **I-4 org-crypt:** every surviving mutation funnel gains the editor host's before-save re-encryption discipline — errors deliberately propagate to abort the write (jetpacs-editor.el:136-142). Glasspane's bare `save-buffer` funnel (glasspane-org.el:51-62) is a cleartext-persistence hole today. Closed at GR-6, regression-pinned forever after.
- **I-5 D1:** verbs emitted from surfaces the new owner does not own get exactly one of: S4 guest sanctioning, `:any-surface` with a written rationale, or a forwarding verb — else taps go permanently rejected. Every moved verb in §3 names its choice.
- **I-6 Slot budget:** `jetpacs-chrome-max-screens` is 3; pinned root = 2 live slots; S4 guests contend for host slots. §7's three-tier model is the design answer; GR-8c audits every screen family's stale slot assumption.
- **I-7 Device smoke:** S1–S5, S4 guest lifecycle, and jetpacs-org-mode are ERT-only today. The FIRST hardware exposure of each is a named arm in this plan, **before** anything is rebased onto it (GR-1). Tablet is in PORTRAIT (landscape tap maps stale); force-stop before every smoke; screenshot before every tap (row positions shift with lockfiles/annotation rows).
- **I-8 wants∩supported:** the single current composition root wants the FULL
  Companion-supported profile (the G9 lesson).  The former daily-driver/tablet
  dual-init split cited by the original plan was retired by
  `tools/onboard-tablet.sh`; `emacs/jetpacs-init.el` omitted the supported
  `surfaces.notification` capability and fixes that at GR-0.  It already asks
  for `offline.wake`, but the Companion does not implement or advertise that
  capability, so wants∩supported correctly leaves it ungranted.  The FGS vs
  `offline.wake` vs client-backoff decision remains owned by RF-0.5b; GR-0 must
  not counterfeit support by adding an inert capability string.
- **I-9 dependency direction:** EBP and Jetpacs source may not name, require, declare, or call Glasspane. The app may depend downward on both layers, never the reverse. Native Org capture/reminder/clock machinery lives under Jetpacs; Glasspane owns only its all-Elisp workflow opinions and their presentation sites. A top-level source-name scan makes the boundary executable, and the device's downstream user config explicitly loads Glasspane after Jetpacs.

## §2 Why machinery-first (the ordering argument)

Three defects are LIVE at HEAD, not hypothetical: (a) both reminder hooks arm duplicate per-owner alarm sets for every timed item on the tablet harness; (b) glasspane-org-reader front-claims the Files body/actions hooks the reader host installed into (remove-then-add at glasspane-org-reader.el:795-802), so the host's org action icons ship as dead controls over Glasspane's body; (c) every Glasspane mutation funnel can persist decrypted org-crypt entries as cleartext. An IA restructure on top of colliding machinery re-tests everything twice — so: **collisions → hardware floor → cutover → host adoption → deletions-after-soak → THEN IA → then upstreaming.** Every rung leaves the tree green and the tablet daily-driver functional: capture works, timed items fire exactly one alarm each, .org files open and save safely.

**Rollback doctrine (applies to every rung marked RISKY):** the losing implementation stays in-tree behind a `defvar` flag until its soak closes; one full daily-driver day between a cutover's device gate and demolition of the losing side (GR-9); every ceremony in §5 includes its scripted reverse; a tripwire firing mid-rung means stop, restore flag state, re-run the rung's smoke arms to confirm baseline, record, then diagnose. Rollback anchor: `git tag rework-baseline` at GR-0.

## §3 Verb-name preservation contract

| Verb(s) | Durable carrier | Ruling | D1 story after move (I-5) |
|---|---|---|---|
| `org.clock.out` / `.switch` / `.in-last` | PendingIntents (ttl 3600) + queued receipts on hardware | names EXACT, forever | keep `:any-surface` (durable-replay-during-SYNCING rationale, verbatim) |
| `org.capture.share` | offline-queue receipts + older-Companion replay alias | name EXACT | keep `:any-surface` (Companion-attribution rationale, verbatim) |
| `share.text` | offline-queue receipts (Companion intake UNBUILT, D-12 — still contractual) | name EXACT | keep `:any-surface`; the deferential-registration dance dies with single ownership, recorded as the convention for future PKM apps |
| `org.capture.show` + sheet-chain conclusions | live taps (FAB, hub card) — owner-scoped TODAY (glasspane-capture.el:295-303) | name EXACT | **gains `:any-surface`** with the §6 written rationale; sheet mid-flow events carry no `:surface` (SPEC 14.4) — unaffected |
| `org-mode.capture` | none durable (hub row + M-x) | becomes a thin deprecation alias onto the moved handler, one release of receipt insurance | n/a |
| `org.table.*` / `org.babel.*` | live taps | names EXACT through any GR-10 move (already base-named) | unchanged (screen-local) |
| `detail.save`, `tasks.open`, other Glasspane UX verbs | live taps; `tasks.open` in old receipts | survive; `tasks.open` retargets to the merged Agenda Tasks page (GR-8a) — cheap receipt/back-compat insurance | unchanged (owner-scoped, own surfaces) |
| `glasspane.home` | drawer tap only | **SURVIVES** as the explicit app-reset verb (M-x parity + programmatic `jetpacs-chrome-reset-screens`). Only its drawer emission site retires (GR-8b). Routeless `app.open` is NOT its replacement: that is return-to-APP — a plain `jetpacs-shell-push` resuming the stack top (jetpacs-apps.el:462-465), deliberately not a reset; the hub is one system-back away from any tier | unchanged (owner-scoped, own surfaces) |
| Reminder ids | not verbs; alarm slots key per-owner | sets are rebuilt from scratch under the new owner, so the id scheme moves freely: keep Glasspane's readable `STEM-sha1[8]` shape under the new prefix, `org-mode.rem-STEM-sha1[8]` | n/a — neither side authors `:on_tap` today (verified), nothing to lose; a future reminder-tap deep link rides ownerless `app.open :route` (§10) |

## §4 Rung ladder overview

Each lettered sub-rung is one commit-able unit; every rung ends with a gate (ERT + device arms where hardware behavior changes).

| Rung | Name | Depends on | Size | Device arm? | RISKY |
|---|---|---|---|---|---|
| GR-0 | Live-defect mitigation batch | — | S | YES | no |
| GR-1 | Hardware floor: first device arms for the seams + owed D-2 smoke | GR-0 | M | YES | no |
| GR-2 | Reader seam: front-claim → adapter | GR-1 | M | YES | yes (UX) |
| GR-3 | Reminders ownership cutover (ceremony §5.1) | GR-1 | M | YES, mandatory | YES |
| GR-4 | Capture ownership cutover (ceremony §5.2) | GR-1, GR-3 | L | YES, mandatory | YES |
| GR-5 | Chronometer → jetpacs-org-clock.el (**OR-1 ratified**) | GR-4 | S | YES | YES |
| GR-6 | Editor discipline (a: crypt closure + freshness + refusal, app-side · b: save-policy seam + second adapter, foundation-side) | GR-2 | M | YES | no (additive) |
| GR-7 | a: coupling severance · b: foundation gap funding (:badge, FAB registry, remove-link, dates) | GR-3, GR-4, GR-6 | M | no | no |
| GR-8 | IA/UX restructure (a: pole+triage, b: hub/drawer, c: navigation+slots, d: periphery) | GR-7 | L | YES — the big batch + soak day | YES |
| GR-9 | Demolition + exit checklist (deletions cite their soaks) | GR-8 soak | M | YES (checklist) | no |
| GR-10 | Upstreaming tail (decision-gated) | GR-9 + rulings | L | per item | no |

**Tripwires armed for the whole ladder — §9 is the table with abort actions.** Kotlin quartet items (a)/(c) remain open; reconnect churn during device batches is exactly where (a) bites.

---

## GR-0 — Live-defect mitigation batch (do FIRST; small; no design decisions)

**Goal:** stop the bleeding at HEAD without prejudging structure: one alarm set per timed item, no silent grant degrades, every later flip has its flag.

**Status: GATE CLOSED 2026-08-16.**  The two hook flags, duplicate-era
device-set clear, supported notification want, automated gates, and generated
single-alarm reboot/fire arm are green on the Pixel Tablet.  The durable store
was empty after cleanup.  The device reported `reminders.owner` and
`surfaces.notification` granted and `offline.wake` ungranted, matching the
supported-capability registry and the RF-0.5b ownership recorded in I-8.

**Steps:**
1. **Flag-gate both reminder hooks** (the flags are what make the §5.1 ceremony's clear→code-drop window structurally safe — a push between clear and land cannot re-arm the losing set): new `defvar jetpacs-org-mode-reminders-enabled` **default nil** guarding `jetpacs-org-mode--sync-reminders` (jetpacs-org-mode.el:393-414, hook at :550-551) — it is ERT-only code with zero hardware history; Glasspane's device-verified pipeline keeps running. Symmetric `defvar glasspane-agenda-reminders-enabled` **default t** guarding `glasspane-agenda--sync-reminders` (glasspane-agenda.el:736-737). **This old inline org-mode pipeline's flag stays nil FOREVER**: the pipeline that eventually wins ownership is GR-3's new `jetpacs-org-reminders.el` under its OWN flag — no ceremony ever flips this one, and GR-9 demolishes the inline pipeline still-nil (three pipelines briefly coexist in-tree; the hook-singleton gate arm spans all three).
2. **Clear the duplicate-era set**, connected + `reminders.owner` granted, on the tablet: `(jetpacs-reminders-clear "org-mode" (lambda (count err) (message "CLEAR org-mode: %s %s" count err)))` — **wait for the message; timeout/error aborts (tripwire T-1)**. Without this, `rearmAllReminders` re-arms the org-mode duplicates from ebp-reminders.json every boot regardless of step 1 (I-2).
3. **I-8 fix:** `emacs/jetpacs-init.el` adds
   `"surfaces.notification"` to `:wants`, completing the supported profile in
   the one composition root deployed by current onboarding.  `offline.wake`
   was already requested, but remains absent from Companion support by the
   explicit RF-0.5b decision boundary; an ungranted result is expected until
   that rung implements a real wake mechanism.
4. `git tag rework-baseline` on the deployed tree+APK pair.

**Gate:** full ERT + new arms in `test/jetpacs-mode-app-test.el` and `test/glasspane-test.el` pinning hook-iff-flag on both sides. **Device arm (tablet, PORTRAIT, force-stop first, screenshot before every tap):** seed one timed item today+2h (generated fixture bytes only) → after a push, exactly ONE alarm+notification set, owner "glasspane" (`dumpsys alarm | grep -i jetpacs`); reboot → no org-mode re-arm. **I-8 proof (directly observable on the current single-root install):** after reconnect, `(jetpacs-granted-p "surfaces.notification")` ⇒ t and `(jetpacs-granted-p "offline.wake")` ⇒ nil; the latter must agree with the Companion's supported-capability registry until RF-0.5b builds and advertises a conforming wake mechanism. Chronometer-posts-on-the-daily-driver is a GR-5 arm.

## GR-1 — Hardware floor: the seams get their first device truth (MANDATORY before GR-2+)

**Goal:** never rebase onto ERT-only floor. The cutover ceremonies (GR-3/4) lean on live sync and S4 guest mechanics; the IA rung (GR-8) leans on S1/S2. Discovering a seam defect at the final gate would re-litigate five landed rungs.

**Arms (each names what it proves; one device day):**
- **S1:** host drawer renders Glasspane's `:destinations` nest (glasspane.el:130-138 registry); nested-row tap → `app.open :app "glasspane" :route KEY` lands on the right screen (the path GR-8b rebuilds the hub onto). Stale-route arm: dead route → fallback home, no error card. Routeless `app.open` resumes the app stack top, with home one system-back away — the later GR-8b return-to-app ruling supersedes this arm's original reset wording.
- **S2:** temporarily flip a scratch app to `:chrome 'primary` on the tablet; verify ≤4 tab generation + `:selected` route tracking (jetpacs-apps.el:211-229 — the pole GR-8a adopts).
- **S3:** M-x injected and executing on a Glasspane screen.
- **S4:** push a guest screen (settings satellite from a Glasspane surface); verify `guest-OWNER-ID` prefixing, Companion-local back revokes with no bookkeeping, owner teardown sweeps the guest and repushes the host (the mechanism GR-4's sheet taps and GR-8's satellites ride). Slot-contention arm: guest push at 2-deep stack → record the observed eviction (feeds GR-8c's audit).
- **S5/S6:** snackbar injector reaches the current view on a multi-view surface.
- **D-2 (owed):** concurrent-edit + forced-desync steps added to the files-sync smoke and run — one `edit.resync`, no wrong edit; verifies the D-1 caret fix on hardware. Every reader/editor-host surface leans on live sync.

**Gate:** all arms green, screenshots recorded in the rung notes; full ERT unchanged-green. **Tripwire T-2 armed from here on** (reverse-order `event.action` replies under batch traffic → halt, fund informed-execution R4 per D-6).

> **GR-1 DEVICE GATE COMPLETE 2026-08-16 — Pixel Tablet, Android 17,
> portrait, force-stop-first, screenshot-before-every-tap.** S1's canonical
> host drawer deep-linked to the real Journal screen; a vanished route now
> returned `stale` **and opened Glasspane home** (the gate found and fixed the
> stale-host-screen defect in `jetpacs-apps--action-open`); routeless open
> resumed the stack top and one system back reached home. S2's temporary
> `primary` flip rendered Eval + Files + three Glasspane destinations (five
> total, within the cap), with Journal selected, then restored the registry.
> S3 executed the injected M-x on Glasspane. S4 used the real Glasspane
> Settings satellite: wire id `guest-glasspane-glasspane-settings`, local back
> left only an inert bookkeeping row with delegation false, owner teardown
> swept the guest and repushed Settings home, and re-registration rebuilt a
> healthy Glasspane root. At the three-view cap, Settings revision 30 retained
> `home`, host B, and the guest while evicting oldest non-root host A; cleanup
> revision 31 contained `home` only. S5/S6 revision 56 targeted the injected
> snackbar at current view `glasspane-tasks` on the two-view surface while
> `home.snackbar` remained null; it was visibly rendered on Tasks. Runner
> screenshots are the `tmp/gr1-s1-*`, `gr1-s2-*`, `gr1-s4-*`, `gr1-s5-*`,
> and `gr1-d2-*` sets from this device day.
>
> **D-2 CLOSED IN THE SAME RUN.** `test/smoke-files-sync.el` is now B1–B10:
> D-1 left the reported device caret `61 -> 61` across an Emacs append; the
> deterministic pending-local/device-delta race emitted exactly one
> `edit.resync`, retained the one device keystroke, dropped the losing local
> sentinel, and converged buffer+mirror; a deliberately stale local seq then
> emitted exactly one more resync, minted a fresh seq-0 session, dropped the
> refused sentinel from both copies, and converged again. The arm found a
> second real defect: an accepted resync replaced only ebp.el's mirror and
> never delivered its full-state seed to the attached buffer. The resync
> callback now runs the same edit-open reconciliation hooks, pinned by
> `ebp-sync-resync-result-reseeds-the-attached-buffer`. Final fresh hardware
> run: `smoke-files-sync: 0 failure(s)`; targeted bridge gate: 45/45; full
> `test/run-tests.sh` gate: exit 0. The final 123-file Elisp tree was then
> deployed, Emacs + Companion relaunched to the clean Glasspane home root, and
> the original rotation baseline restored (`free`, accelerometer `1`, user
> rotation `0`).

## GR-2 — Reader seam: front-claim becomes adapter registration

**Goal:** Glasspane's foldable-tree reader rides `jetpacs-reader-register`; no hand-claimed hooks; no dead host controls; stock behavior restored when Glasspane unloads.

**Steps:**
1. In `glasspane-org-reader-register`: DELETE the remove-then-add pairs on `jetpacs-files-editor-body-functions`/`-actions-functions` (glasspane-org-reader.el:795-802). Replace with `(jetpacs-reader-register 'org :predicate #'jetpacs-reader-org-path-p :render #'glasspane-org-reader--adapter-render :actions #'glasspane-org-reader--adapter-actions :transition #'glasspane-org-reader--adapter-transition)`.
2. **Mechanism decision — replace-in-place of id `'org`, justified against its failure mode** (a misregistration would vanish ALL org rendering, where a separate-id scheme would degrade to the foundation render): (i) a separate id is **not expressible** under this host API — `jetpacs-reader-register` APPENDS new ids at the tail (jetpacs-reader.el:70-78, verified), so a later-loading `'glasspane-org` could never precede the stock `'org` without unregistering it anyway — the same single point of failure plus load-order roulette; (ii) the registration site is singular and gate-tested (`glasspane-register`); (iii) `glasspane-org-reader-unregister` restores the stock adapter by calling `jetpacs-reader-org-register`, pinned by an ERT arm both directions; (iv) **degradation guard:** the adapter `:render` wraps the tree builder in `condition-case` and falls back to `jetpacs-reader-org`'s render on signal — a Glasspane-side render bug degrades to the stock presentation instead of a blank Files screen.
3. Adapter `:actions` = Glasspane's set — the ONE-grammar `files.filter` input + clear chip (matrix row 7: the filter owns search for the foldable-tree presentation; org-occur search returns whenever the stock adapter does) — **plus the absorbed decrypt action** from `jetpacs-reader-org` (the visible-PGP-block conditional). Dropping decrypt from the tree presentation would contradict GR-6's own org-crypt work. The host's generic `jetpacs.reader.toggle` now governs rendered/plain for Glasspane too (its gate already transitively delegates to `jetpacs-reader-active-p`, jetpacs-org-render.el:875-878).
4. Per-document state (fold state, filter query/counts) moves onto the host's path-keyed store (`jetpacs-reader-state-get/set`) under `:gp-*` keys, distinct from the stock `:org-*` keys; the private defvars die.
5. Adapter `:transition`: entering 'editor reuses the narrowed-buffer downgrade discipline exactly as the stock adapter does (narrowed buffers cannot use SPEC-19 whole-document coordinates).
6. DELETE the dead JA-6 assumptions (matrix row 8): the `jetpacs.org.view-mode` pass-through/commentary (glasspane-org-reader.el:744-755). The legacy seams are opt-in-off; the flag is NOT flipped.
7. Keep `glasspane-org-reader-subtree` exported (journal's day render) and `glasspane-org-reader--refile-lists` temporarily (severed properly at GR-7a). The host grows NO embeddable subtree/list API this rework (map OQ6 — recorded decision, §10).

**Gate:** ERT (test/glasspane-test.el + test/jetpacs-mode-app-test.el): with both apps loaded, `.org` opens Glasspane's tree via the ADAPTER (hook lists contain only `jetpacs-reader--files-body`); host top bar carries Glasspane's actions and the absorbed decrypt action, **no other stock org action icons**; `glasspane-unregister` → stock adapter renders with its full action set; render-signal fallback arm; toggle round-trip preserves fold state. **Device arm:** open a seeded .org — tree renders, filter works, decrypt affordance visible on a crypt file, toggle to plain and back, no dead icons; force-stop + relaunch resumes.

> **GR-2 DEVICE GATE COMPLETE 2026-08-16 — Pixel Tablet, Android 17,
> portrait, force-stop-first, screenshot-before-every-tap.** The seeded
> three-heading Org file opened through the stable `org` adapter; the
> `todo:TODO` query rendered **1 of 3 headings**, the visible PGP block
> exposed **Decrypt Org Crypt entries**, and rendered → plain → rendered
> returned to the tree. The reader bar carried Refile + conditional decrypt
> beside the generic host controls, with none of the stock Org
> reader-mode/visibility/search icons. Refile and its Reader return both
> dispatched on hardware; decrypt presence and handler reachability are
> pinned without attempting to decrypt the deliberately invalid fixture.
>
> The arm found and closed two integration defects. First, the adapter's
> Glasspane-owned descriptors are emitted from the stable foreign Files
> surface, so D1 rejected all four until `heading.menu`, `files.filter`,
> `files.toggle-refile`, and `heading.reorder` became bounded global verbs;
> their live-path/token/list guards and a real `jetpacs--dispatch` arm now
> pin that boundary. Second, a `reorderable_list` nested in a lazy column
> crashed Compose with infinite vertical constraints; refile mode now gives
> the weighted list the finite remainder of a root column, pinned by a
> structural ERT arm. Companion force-stop/relaunch followed by the
> documented caller-owned `M-x jetpacs-start` reconnect resumed the exact
> Org document from Files while the Emacs process retained its path-keyed
> reader state.
>
> Registration/unregistration, stock-render fallback, stock-action restore,
> stable-id toggle round-trip, `:gp-*` document isolation, and the refile
> layout all ride the suite. Final gates: Glasspane **72/72**; full
> `test/run-tests.sh` **exit 0**. The generated fixture/evidence was removed
> from the tablet, Eval was left clean, and the rotation baseline was
> restored (`free`, accelerometer `1`, user rotation `0`).

## GR-3 — Reminders ownership cutover (RATIFIED ruling 1, reminders half) — RISKY

**Goal:** one pipeline, owner "org-mode", device-verified code surviving, device sets cut over without orphans. Ceremony §5.1 IS the device gate.

**Steps:**
1. **New file `emacs/jetpacs-org-reminders.el`** (owner "org-mode", required + registered by the composition root): Glasspane's device-verified pipeline moves — `--item-hm`, `--upcoming-reminders`, scheduled+deadline same-instant dedupe, `--sync-reminders` on `jetpacs-shell-after-push-hook`, gated on `(jetpacs-connected-p)` + `(jetpacs-granted-p "reminders.owner")` + **its OWN new flag `defvar jetpacs-org-reminders-enabled`, default nil at merge** — deliberately NOT GR-0's `jetpacs-org-mode-reminders-enabled`: sharing that flag would enable BOTH org-mode pipelines at §5.1 step 6 (two after-push hooks issuing replace-sets under the one owner "org-mode" with disjoint id schemes — each send atomically replaces the other's whole set, ReminderStore's per-owner replace drops the vanished ids' fired receipts, and the survivor would be add-hook-order roulette). Reminder ids per §3: `org-mode.rem-STEM-sha1[8]`.
1b. **The old inline pipeline is un-hooked in the SAME commit:** `jetpacs-org-mode-register` stops adding `jetpacs-org-mode--sync-reminders` to the hook (its flag stays nil, its code stays in-tree as the GR-9 corpse) — after GR-3 exactly one org-mode reminder hook can ever be live.
2. **Absorb org-mode's exclusive extra:** the defcustom horizon — `jetpacs-org-reminders-horizon-hours`, default 24 — replaces Glasspane's hard today+tomorrow window.
3. **Agenda-extraction dedup (matrix row 3):** ONE extractor survives in jetpacs-org-mode: org-mode's `--agenda-scope` (line-for-line clone anyway, jetpacs-org-mode.el:284-339) + Glasspane's RICHER item walk (tags/priority/extra/ts-date/date-str + ebp-org ref — its consumers are Glasspane's agenda cards and the GR-8b dashboard, which live on), memoised under `'org-mode`. `glasspane-org.el`'s copy becomes a thin delegating alias for its screen consumers, out of the extraction business.
4. **Execute ceremony §5.1.** The losing hook code (glasspane-agenda's sync section, glasspane-org's reminder helpers) stays in-tree behind its flag until GR-9's soak-cited demolition.
5. New suite `test/jetpacs-org-reminders-test.el` — **wired into `test/run-tests.sh`'s explicit list in the same commit.**

**Gate:** full ERT — horizon defcustom arms, same-instant dedupe, id-shape arm, owner string, **hook-singleton arm spanning ALL THREE pipelines: for every flag combination the ceremonies use (including all-nil), at most one reminder hook is effective, and the old inline hook is effective under none**, diff-vs-last. **Device gate = ceremony §5.1 steps 5–8** (single set under "org-mode" with every id matching `^org-mode\.rem-`, reboot rearm, fire-once, date-only-arms-nothing). Daily-driver arm: a normal day's items fire once each.
**Rollback:** §5.1 reverse ceremony.

> **GR-3 DEVICE GATE COMPLETE 2026-08-16 — Pixel Tablet, Android 17.**
> The forward ceremony first made all three pipelines inert, then observed
> successful callbacks for both durable clears (`glasspane` `(0 nil)`,
> `org-mode` `(0 nil)`) before enabling the new owner. A generated timed row
> produced exactly one confirmed `org-mode.rem-*` mirror entry, an empty
> Glasspane mirror, and one Companion `RTC_WAKEUP`; its date-only control
> produced no alarm. After reboot and the required credential unlock, Android
> rearmed that one alarm before Emacs started. The historical
> `dumpsys alarm | grep -i jetpacs` probe no longer matches the Android tag;
> the observable active tag is
> `com.calebc42.ebp.companion/.ReminderAlarmReceiver`, so the gate counted that
> package/receiver directly.
>
> The fire arm scheduled `GR3 fire-once arm` for 12:47. Before delivery there
> was one active alarm and no fixture notification; after delivery there was
> no active reminder alarm and exactly one notification record. Notification
> Manager reported one enqueue, one post, zero updates, and the shade visibly
> showed the expected title/body. Review also hardened the moved pipeline so
> an agenda scan error preserves the last durable device set instead of
> treating failure as an authoritative empty projection; a dedicated ERT arm
> pins that behavior.
>
> The scripted reverse then made Org inert, observed its clear callback
> `(0 nil)`, enabled only Glasspane, and armed exactly one
> `glasspane.rem-*` row at 15:00 with the Org mirror empty. A second reboot
> rearmed exactly that one alarm before Emacs startup. Final restoration again
> made the loser inert first, observed Glasspane's clear callback `(0 nil)`,
> removed only the generated fixture, and enabled only the canonical Org
> hook. Final state: canonical/legacy/Glasspane flags `(t nil nil)`, only
> `jetpacs-org-reminders--sync-reminders` live, both mirrors empty, no active
> Companion reminder alarm, no fixture notification/file, and rotation at its
> recorded baseline (`free`, accelerometer `1`, user rotation `0`). The agenda
> had no natural timed item during the scheduled window, so generated bytes
> supplied the deterministic fire arm; the full-day soak remains the GR-9
> demolition prerequisite. Evidence is the `tmp/gr3-*` set from this run.
> Automated gates: GR-3 **6/6**, Org app **20/20**, Glasspane **72/72**, and
> full `test/run-tests.sh` **exit 0**.

## GR-4 — Capture ownership cutover (RATIFIED ruling 1, capture half) — RISKY

**Goal:** one capture implementation, org-mode-owned, carrying the device-verified UX; durable names byte-identical. Ceremony §5.2.

**Steps:**
0. **Enforce the newly ratified layer boundary before moving capture:** remove the reminder module's direct legacy-hook reference and the Jetpacs composition root's optional Glasspane `require`; Glasspane now loads its own managed config, and downstream device `user.el` explicitly `(require 'glasspane)` after Jetpacs. Add the zero-name foundation guard. This keeps the rollback implementation downstream without making Jetpacs aware it exists.
1. **New file `emacs/jetpacs-org-capture.el`** (owner "org-mode", registered from the composition root): glasspane-capture.el's sheet chain moves wholesale — picker→form dialogs, deterministic capf field ids (`jetpacs-wire-id`; the G9 obarray-twin rule: `jetpacs--check-capture-fields` interns keyword twins, so field-id generation must stay deterministic across the move), share stash written before the client guard, one-live-sheet/1301 semantics, durable-then-celebrate submit tail.
2. **Absorb org-mode's exclusives:** org-protocol URL decoding (modern + legacy forms, jetpacs-org-mode.el:170-228) as an intake path feeding the same sheet chain (headless `ebp-org-capture-run` when the URL fully specifies); the non-selectable prefix-template filter (:139-145) applied to the picker's enumeration. Behavior change recorded for release notes: users with prefix templates now see the filter.
3. **Registrations under owner "org-mode", names byte-identical (§3):** `org.capture.show` gains **`:any-surface t`** with this written rationale, recorded in the defaction `:doc`/comment: *"Global intake affordance — capture taps originate on any app's screens (Glasspane FAB and hub card today, future apps tomorrow) and on durable descriptors; the sheet chain that follows is dialog-scoped (SPEC 14.4: dialog conclusions carry no surface), so surface scoping protects nothing and D1 would permanently reject every Glasspane FAB tap. Alternatives rejected: S4 guest sanctioning — capture is a dialog, no guest SCREEN exists at tap time to delegate through; a forwarding verb — two live names for one action is worse than one honest `:any-surface`."* `share.text` + `org.capture.share` keep their `:any-surface` Companion-attribution rationale verbatim, now registered unconditionally — org-mode owns the intake; the deferential dance (`--owns-share-action`, eq-guarded teardown) is deleted and recorded in CHROME-VOCABULARY as the convention for a FUTURE app that wants to displace it. `org-mode.capture` becomes a thin deprecation alias onto the same handler.
4. **Cache-invalidation RULING (recorded — answers map OQ10):** capture success keeps the **whole-cache** `(ebp-org-cache-invalidate)` deliberately. A capture writes a file ANY app's memos may cover; scoping to `'org-mode` would lose the `'glasspane` invalidation Glasspane's own capture performs today (glasspane invalidates `'glasspane`, glasspane-org.el:62; org-mode runs the bare invalidate, jetpacs-org-mode.el:248) — agenda cards and the dashboard would show stale data after every capture until TTL. Not hygiene: a regression.
5. **Delete** org-mode's bridged completing-read/read-string capture path — the ONE no-soak deletion in this plan, because it is ERT-only with zero hardware history and its replacement IS the hardware-verified incumbent. `glasspane-capture.el`'s registration flips behind `defvar glasspane-capture-enabled` (default nil post-swap) for the scripted reverse; file deleted at GR-9.
6. **Glasspane keeps:** the FAB emission sites (same verb, unchanged bytes); `glasspane-config-ensure` capture-template seeding (the app's template opinion — the engine reads `org-capture-templates` regardless; recorded non-move); `journal.capture` (raw datetree append, NOT org-capture — stays in glasspane-journal.el permanently).
7. Move capture suites out of test/glasspane-test.el into new `test/jetpacs-org-capture-test.el`; **wire into test/run-tests.sh in the same commit.**

**Gate:** full ERT — sheet-chain conclusion mapping; stash semantics (share-over-open-picker abandon; async-1301 must not clobber a successor's stash); obarray-twin field arm; prefix-template filter; org-protocol both URL forms; whole-cache-invalidate arm; **D1 arm proving a glasspane-surface tap on `org.capture.show` is accepted.** **Device gate = ceremony §5.2:** FAB capture e2e from the Agenda screen under the new owner (picker → form → "Captured ✓" → entry lands); share replay (`org.capture.share` queued offline via injection — Companion ACTION_SEND intake is UNBUILT, D-12; injection is the honest arm) reconnects and is accepted; airplane-mode capture submit → reconnect → accepted receipt (I-1 proof); same-day daily-driver capture.
**Rollback:** §5.2 reverse. **Tripwire T-3 armed:** any D1 `rejected` from a capture-path tap post-cutover → abort rung, re-inventory emission sites against §3.

> **GR-4 DEVICE GATE COMPLETE 2026-08-16 — Pixel Tablet, Android 17,
> portrait-locked, force-stop-first, screenshot-before-every-tap.** The private
> queue was empty before the owner swap (`records=0`, `next_seq=1`). The
> deployed downstream `user.el` explicitly required Glasspane while the
> Jetpacs entry path loaded no Glasspane feature; all canonical capture verbs
> resolved to owner `org-mode` with flags `(t nil)`.
>
> The Agenda FAB opened the moved picker and Note form, then durably wrote the
> unique forward marker exactly once to `/sdcard/org/inbox.org` and closed the
> sheet. A valid injected `org.capture.share` record
> (`a4c42026081613560000000000000001`) replayed after reconnect with summary
> `(delivered 1 rejected 0 expired 0 remaining 0 blocked_by nil)`; its receipt
> survived a clean Emacs restart and the Companion queue returned to empty.
> While Android airplane mode was visibly on, another Agenda capture advanced
> the receipt store **599 → 600** under owner `org-mode`, wrote its marker once,
> and closed the form; the next clean reconnect loaded all 600 receipts.
>
> The scripted reverse persisted flags `(nil t)`, restarted Emacs, transferred
> the three rollback-era durable/live names to owner `glasspane`, and reran the
> same Agenda picker/form smoke: receipt store **603 → 604**, marker exactly
> once, sheet closed. Final restoration persisted `(t nil)`, restarted again,
> and resolved `org.capture.show`, `share.text`, `org.capture.share`, and the
> `org-mode.capture` deprecation alias to `org-mode`. Cleanup removed only the
> three audited generated Org subtrees and the injection/ADB transport files;
> final queue state is `records=0`, `next_seq=2`, airplane mode `0`, Wi-Fi `1`,
> and rotation at its recorded baseline (accelerometer `1`, user rotation `0`).
> The same-day deployed-tablet capture supplies this rung's live-use arm; the
> full-day soak remains the GR-9 demolition prerequisite. Evidence is the
> `tmp/gr4-*` set from this run. Automated gates: capture **8/8**, Org mode
> **17/17**, reminders **6/6**, Glasspane **71/71**, entry **1/1**,
> warning-as-error byte compilation, and full `test/run-tests.sh` **exit 0**.

## GR-5 — Chronometer → `emacs/jetpacs-org-clock.el` (**OR-1 RATIFIED 2026-08-16**) — RISKY

glasspane-clock.el moves near-verbatim under owner "org-mode" (pure org-clock, zero glasspane sibling deps, uses only foundation `ebp-org-defer-save`). **Verb strings and the `notification:org-clock` root name do not change** (§3/I-1); the `:any-surface` durable-replay rationale carries verbatim; grant-gated assert vs never-gated retire, both-directions READY settlement at depth 90, D2 `--soon` deferral, hooks-at-enable all move untouched — **except the GR-6a clock crypt guard, which the move carries (or lands here first if GR-5 runs before GR-6)**. Clocking and chronometer behavior are native Emacs machinery and therefore Jetpacs-owned; `heading.clock-in` stays Glasspane as the opinionated detail-screen affordance.

**Ceremony §5.3 gates the deploy.** Suite moves to new `test/jetpacs-org-clock-test.el`, **wired into test/run-tests.sh in the same commit.**
**Gate:** ERT lifecycle suite green under the new name. **Device arms:** on the TABLET (the only device with a Glasspane detail screen): clock-in from detail → ongoing chronometer with 2 meta actions; clock-out FROM the notification retires it and the CLOCK line closes on disk; offline-queued clock-out replays during SYNCING, accepted. On the DAILY DRIVER (first chronometer code there — jetpacs-org-mode now carries it; GR-0's I-8 fix made the surface eligible): M-x org-clock-in → chronometer posts.

> **GR-5 DEVICE GATE COMPLETE 2026-08-16 — Pixel Tablet, Android 17.**
> The clock-out gate began stopped, with no live
> `notification:org-clock`, an empty private queue, and the notification
> grant present.  The deployed downstream `user.el` explicitly required
> Glasspane while selecting flags `(jetpacs-org-clock-enabled
> glasspane-clock-enabled) = (t nil)`; all three byte-stable durable verbs
> and the notification root resolved to owner `org-mode`.
>
> A physical tap on Glasspane detail's unchanged **Clock in** affordance
> started `GR5_CLOCK_FORWARD_20260816_1503`.  The Android shade showed one
> ongoing elapsed chronometer with exactly **Clock out** and **Switch task**;
> a physical **Clock out** notification tap retired it and left one closed
> CLOCK line and no open line on disk.  For the cold durable arm, event
> `a5c52026081615120000000000000002` was the sole queued record while the
> Companion was stopped; Emacs restored the running generated clock before
> reconnect, then the action replayed during SYNCING with summary
> `(delivered 1 rejected 0 expired 0 remaining 0 blocked_by nil)`.  Its
> durable receipt committed, the clock closed on disk, and the private queue
> returned to `records=0` (`next_seq=5`).
>
> The reverse persisted flags `(nil t)`, restarted Emacs, and transferred
> the unchanged verbs, hooks, root, and two-action chronometer to owner
> `glasspane`; its registered clock-out handler answered `accepted` and
> retired cleanly.  Final restoration persisted `(t nil)`, removed the
> temporary clock-persistence harness, and left only the native Org hooks
> and owner.  A native interactive `org-clock-in` call then posted the
> elapsed chronometer under `org-mode`, supplying the same-day live-use arm
> on the only connected device; the full-day daily-driver soak remains the
> GR-9 demolition prerequisite.
>
> Cleanup removed only the four exact generated Org subtrees and audited
> transport files.  Final state: no active clock/root/notification, queue
> empty, airplane mode `0`, Wi-Fi `1`, and baseline rotation restored
> (accelerometer `1`, user rotation `0`).  Evidence is the `tmp/gr5-*` set
> from this run.  Automated gates: clock **7/7**, Org mode **17/17**,
> Glasspane **67/67**, integration **14/14**, warning-as-error byte
> compilation, zero upstream `glasspane` names, and full
> `test/run-tests.sh` **exit 0**.

## GR-6 — Editor discipline: org-crypt closure + freshness merge + save-policy seam

**Goal:** no Glasspane mutation can persist cleartext (I-4); the two complementary save-guard models become one shared core; app save policy becomes a foundation seam so srs durability survives GR-9's deletions. Two commit-able halves with separate blast radii: GR-6a is app-side hardening, GR-6b is a foundation refactor (its save-policy seam must be cross-repo-verified against vulpea-absent Glasspane).

### GR-6a — app-side hardening (one commit)
1. **Close the cleartext hole at the funnel:** `glasspane-org--save-and-invalidate` (glasspane-org.el:51-62) runs `jetpacs-files-before-buffer-save-hook` (TRUENAME BUFFER, deliberately UNisolated — a signaling `org-encrypt-entries` ABORTS the write, matching jetpacs-editor.el:136-142) before its `save-buffer`. Every caller — detail.save, table cell edits, at-ref mutations, srs engine-form saves — inherits re-encryption for free, because all screen mutations thread this one funnel.
2. **The clock funnel is the exception the sentence above would silently miss — closed here too:** glasspane-clock persists CLOCK-line mutations via `ebp-org-defer-save` (glasspane-clock.el:185,205), whose idle-timer save is a plain `save-buffer` that never runs `jetpacs-files-before-buffer-save-hook` (that hook fires only inside jetpacs-files' own save gate, jetpacs-files.el:1604), and clock buffers never traverse the editor host's Files setup. Fix: before deferring, the clock handlers `(add-hook 'before-save-hook #'org-encrypt-entries nil t)` in the clock buffer (mirroring jetpacs-editor-org--setup) — the buffer-local hook rides the idle save. Carried through GR-5's move (the jetpacs-org-clock.el copy inherits it).
3. **Freshness merge (matrix row 2 — NEITHER side is a superset):** extract a shared core `glasspane-org--fresh-splice` carrying jetpacs-editor-org's gates (disk mtime vs stamp, region bounds, `buffer-chars-modified-tick`, `jetpacs-files-max-bytes` cap, byte-for-byte restore on pre-durability failure — jetpacs-editor-org.el:156-284 is the reference) AND Glasspane's gates (leading-stars shape check, ID-based ref re-anchor). `detail.save` (glasspane-detail.el:1139-1190) adopts it — its last-write-wins over external edits dies; `jetpacs.editor.org.save-narrowed` keeps its own host path unchanged. Both verbs survive: they serve different screens (drill-in token funnel vs Files narrowed editor).
4. **SPEC-19 overlap (risk #13) — concrete v1 behavior, not a note:** the funnel consults `jetpacs-files-current-edit-path` + editor context; when the mutation target IS the live synchronized document, `detail.save` **refuses with a snackbar naming the conflict ("file is open in the synced editor")** rather than splicing under sync's feet. Routing through the sync splice is recorded as a follow-up (§10).

**GR-6a gate:** full ERT, arms in `test/glasspane-test.el`: ciphertext regression (decrypted `:crypt:` entry + funnel save → on-disk bytes remain ciphertext); **clock ciphertext arm** (clock-out on a heading inside a decrypted `:crypt:` entry → idle save fires → on-disk bytes remain ciphertext); mtime-conflict arm (external touch → `detail.save` `'rejected` + snackbar); tick-conflict arm; shape-gate and ID re-anchor arms preserved; synced-document refusal arm. **Device arm:** edit a subtree containing a decrypted org-crypt entry via detail.save → ssh the file off, verify ciphertext; concurrent external edit (Termux `touch`+append) → save rejected on device.

> **GR-6a DEVICE GATE COMPLETE 2026-08-16 — Pixel Tablet, Android 17.**
> A real `org-crypt` fixture was encrypted by GnuPG, decrypted in the live
> Emacs buffer, opened in Glasspane Detail, edited on-device, and saved
> through `detail.save`.  The pulled file retained its complete PGP armor
> and contained neither the original cleartext marker nor the device edit
> marker (`tmp/gr6-crypt-after-detail-save.org`).
>
> A fresh Detail snapshot was then raced with a Termux append+touch.  The
> physical Save tap returned **File changed on disk — not saved**; the
> second pulled file retained both external append headings and its PGP
> block while excluding the rejected device edit
> (`tmp/gr6-crypt-after-conflict.org`, screenshot
> `tmp/gr6-20-conflict-rejected.png`).  Cleanup removed only the disposable
> fixture and scripts from the device, stopped the test GPG agent, and left
> the Companion queue empty with airplane mode `0`, Wi-Fi `1`, and baseline
> rotation `(accelerometer,user)=(1,0)`.
>
> Automated gates: Glasspane **70/70**, Files **61/61**, Org mode/editor
> **17/17**, clock **7/7**, warning-as-error byte compilation, diff check,
> and full elevated `test/run-tests.sh` **exit 0** (including live socket
> integration).

### GR-6b — foundation save-policy seam + second adapter (one commit; cross-repo-verified)
5. **Save-policy seam upstream (matrix rows 11-superset/12):** jetpacs-editor-org's bare after-save (`ebp-org-cache-invalidate` only, jetpacs-editor-org.el:286-288) adopts the full policy as a foundation function `jetpacs-editor-org-save-policy` — synchronous save + `vulpea-db-update-file` (guarded on vulpea presence; cross-repo rule: verify against Glasspane locally where vulpea is absent) + cache invalidation. **Invalidation scope RULING (mirrors GR-4 step 4's logic — a mutation writes a file ANY app's memos may cover):** the policy runs the **whole-cache** `(ebp-org-cache-invalidate)`, not a namespaced one — a namespaced `'glasspane` invalidate would leave the GR-3-consolidated `'org-mode` extraction memo (agenda cards, dashboard, reminder pipeline) stale after every todo swipe/detail.save until TTL, recreating risk #6 by plan. `glasspane-org--save-and-invalidate` becomes a thin wrapper over the policy. The `ebp-org-file-save-function` registration-time rebind (previous-holder restore) moves alongside. srs rate/postpone/suspend/undo durability (the G9 catch) pinned by a test asserting the policy runs INSIDE the engine form.
6. **Second editor adapter (matrix row 13 / seam adoption):** `(jetpacs-editor-register 'glasspane-org …)` matching `.org` with ONLY `:actions` (append semantics — all matching adapters participate, verified jetpacs-editor.el:117-122) carrying the file-properties action, and `:after-save`; body/toolbar/fab stay nil (first-wins slots remain the stock adapter's).

**GR-6b gate:** full ERT — before-save abort arm (encrypt signal → no bytes on disk, buffer restored), save-policy arms (vulpea-present and vulpea-absent), **stale-memo arm (mutate via the funnel → the `'org-mode` extraction memo misses, fresh walk on next read)**, srs engine-form durability arm, editor-adapter actions arm — these land in **NEW `test/jetpacs-editor-org-test.el`, wired into `test/run-tests.sh`'s explicit list in the same commit** (the K1a rule; no editor-org suite exists today).

> **GR-6b GATE COMPLETE 2026-08-16.**
> `jetpacs-editor-org-save-policy` now owns the mandatory pre-write chain,
> synchronous save, optional Vulpea refresh, and whole-cache invalidation;
> a signaling encryption transform restores the buffer before re-signaling.
> The Org adapter owns and lifecycle-restores `ebp-org-file-save-function`.
> Glasspane's save funnel is a thin call into that public policy, while its
> separate `glasspane-org` editor adapter contributes only the file-properties
> action and downstream after-save index refresh — no body, toolbar, FAB, or
> before-save slot.  Refile now sends every modified source/target Org buffer
> through the same policy instead of bypassing it with
> `org-save-all-org-buffers`.
>
> The new explicit `test/jetpacs-editor-org-test.el` gate is **7/7**:
> encryption-abort rollback, Vulpea present/absent, `'org-mode` memo eviction,
> EBP holder restoration, additive adapter composition, and rate/postpone/
> suspend/undo durability inside the SRS engine form.  Affected legacy gates:
> Glasspane **70/70**, Org mode/editor **17/17**, Org dialogs **37/37**, and
> Files **61/61**.  Warning-as-error compilation, zero upstream `glasspane`
> names, diff check, and full elevated `test/run-tests.sh` all pass; the full
> runner exited **0**.  GR-6b adds no device behavior and requires no new
> hardware arm; GR-6a's completed ciphertext/conflict device gate remains the
> rung's hardware evidence.

## GR-7 — Coupling severance + foundation gap funding (unblocks GR-8)

### GR-7a — severance (one commit)
1. **`glasspane-ui--defer-refresh` retirement (matrix row 11):** dialog-origin callers → `jetpacs-settings-refresh` (jetpacs-settings.el:309); remaining surface-or-flow-owner callers → a small mode-neutral foundation `jetpacs-app-defer-refresh` (flow-continue + `jetpacs-shell-push` to the flow's surface). This is the D2 funnel whose replacement unlocks ef/gallery re-homing (GR-8d) and keeps srs app-side but foundation-fed.
2. **Refile-lists coupling:** `glasspane-org-reader--refile-lists` gets a public accessor pair; glasspane-views writes through the public name only.
3. **Shared card/formatter builders** parked in glasspane-detail/glasspane-agenda that detail/agenda/views/journal consume: exported under public names so GR-8 can relocate screen code without breaking three siblings.

> **GR-7a GATE COMPLETE 2026-08-16.**
> `jetpacs-app-defer-refresh` is now the mode-neutral D2 app-surface seam:
> an event surface wins, otherwise the captured flow surface is preserved,
> and presentation failure cannot escape the continuation.  Settings-owned
> agenda editors use `jetpacs-settings-refresh`; every remaining caller uses
> the app seam.  The retired helper has zero source callers, and EF/Gallery
> no longer require `glasspane-ui`.
>
> The reader's refile table remains private behind public lookup/store
> accessors.  Shared agenda/detail builders and every Glasspane sibling API
> actually consumed cross-file now have public names; uncached workers remain
> private.  Executable source gates reject both a return of the retired helper
> and any double-hyphen Glasspane symbol read outside its defining module.
>
> Verification: Glasspane **73/73**, app registry **16/16**, Org editor policy
> **7/7**, reminders **6/6**, and Settings **10/10**; all 16 touched source
> modules pass warning-as-error byte compilation.  Zero upstream `glasspane`
> names, zero generated `.elc` residue, diff check, and the full elevated
> `test/run-tests.sh` all pass; the full runner exited **0**.  This is a
> dependency-severance rung with no rendered behavior change, so the plan's
> no-device-arm ruling applies.

### GR-7b — foundation gaps (one commit)
1. **`:badge` plumbing** — required or the agenda badge dies at the GR-8a pole flip (verified: `jetpacs-apps--destination-tabs` emits only `:label`/`:icon`/`:on-tap`/`:selected`, jetpacs-apps.el:218-229; the D-9 `:badge` rides the hand dock item GR-8a deletes): add a `:badge` member to the destination plist — validated in `jetpacs-apps--check-destination-list` (jetpacs-apps.el:63-93), value a nullary function (memoised count) or string, nil-when-zero — and thread it through `jetpacs-apps--destination-tabs`. The dock-item plist already supports `:badge`; this is registry→generator plumbing only.
2. **App-default FAB registry** (matrix row 15b, FOUNDATION-GAPS #2): `jetpacs-defapp` gains `:fab` (descriptor or (SURFACE)→descriptor fn); `jetpacs-chrome--build` injects it when the screen authors no `:fab` — **keyed on the SCREEN's owner, not the surface's: an S4 guest screen (its id carries the `guest-` prefix / a recorded foreign owner, jetpacs-chrome.el:617-671) NEVER gets the host app's FAB injected onto it.** Single-slot authored-wins for `:fab`; the S5 any-slot rule at jetpacs-chrome.el:440-454 governs the dock join it sits beside (different granularity — do not conflate). Glasspane will declare the capture FAB once at GR-8a, deleting the per-screen hand-authored node (glasspane-ui.el:123-132).
3. **`jetpacs-settings-remove-link`** (matrix row 15a): foundation helper; both hand-rolled `cl-remove` sites (glasspane-ui.el:741-760) drop.
4. **`glasspane-dates.el` → `emacs/jetpacs-dates.el`** (FOUNDATION-GAPS #10): pure util, mechanical rename + prefix grep, callers updated, suite renamed.

**Gate (both):** full ERT — grep gates in the suite (zero `glasspane-ui--defer-refresh` callers, zero double-hyphen cross-module reads); badge validation + tab-generation arms; FAB injection FOUR arms (no-FAB screen gets app default / authored wins / foreign surface gets nothing / **guest screen on the app's own surface gets NO injected FAB**); remove-link pair; dates suite. No device arm (behavior-preserving + GR-8's batch covers the rendered results).

> **GR-7b GATE COMPLETE 2026-08-16.**  Destination badges now validate at
> registration and resolve per navigation-bar build; empty-dot, dynamic,
> nil, malformed-result, and signalling arms are pinned.  `jetpacs-defapp'
> owns the app-default FAB declaration, while chrome resolves it from each
> screen's recorded owner: a native free slot inherits it, authored wins,
> foreign surfaces remain empty, and an S4 guest on the host surface cannot
> inherit either app's default.  The app join precedes S10 globals, so a
> global requesting `fab' falls back to the top bar.
>
> `jetpacs-settings-remove-link' is the sole removal writer and every former
> hand mutation (Glasspane UI, Ef, Gallery, and foundation Org settings) uses
> it.  The pure date utility and its suite moved mechanically to
> `jetpacs-dates'; executable source contains zero old-prefix references.
>
> Verification: app registry **19/19**, chrome **62/62**, Settings **11/11**,
> dates **1/1**, Org settings **9/9**, and Glasspane **72/72**; all 11 touched
> source modules pass warning-as-error byte compilation.  The foundation
> layering grep, old-date-prefix grep, direct-settings-writer grep, diff
> check, package-install gate, and full elevated `test/run-tests.sh` pass;
> the full runner exited **0**.  Per the rung ruling there is no device arm.
>
> No GR-8 placement mechanics landed in GR-7b. At that checkpoint the private
> legacy generator name and its old four-entry cap remained debt for PA-1;
> PA-1 has since closed both with generic Jetpacs seams. The authoritative
> target is exactly five Glasspane destinations — Agenda, Projects, Areas,
> Resources, Review — owning the NavBar/BottomAppBar. Agenda alone has
> Day/Week/Month content tabs. Resources delegates to the native Jetpacs Files
> explorer and replaces its separate bar entry;
> Archive, Eval, and Apps are drawer-only.

## GR-8 — IA/UX restructure (RATIFIED ruling 2) — RISKY; §7 is the design it implements

> **NON-EXECUTABLE FORWARD POINTER (2026-08-16):** this GR-8 was already
> superseded by `PLAN-glasspane-para.md`; Caleb has also corrected PARA's
> placement rule. Glasspane owns exactly five NavBar/BottomAppBar destinations:
> Agenda, Projects, Areas, Resources, Review. Agenda alone has Day/Week/Month
> content tabs. Resources delegates to the native Jetpacs Files explorer and
> replaces its separate bar entry; Archive, Eval,
> and Apps are NavDrawer-only. The rewritten PA-1/PA-3 text in the PARA plan is
> authoritative; the historical GR-8 text below remains non-executable.

Old hub/dock/front-claim-era code stays in-tree behind `defvar glasspane-ui-legacy-ia` through the soak; deletions land at GR-9 citing it.

### GR-8a — pole + destination triage (one commit)
- `glasspane`'s defapp gains `:chrome 'primary` and `:fab` (the capture FAB descriptor, GR-7b seam): core collapses to one Home; destinations become dock tabs via `app.open :route` with `:selected` tracked by `jetpacs-apps--current-route`. The hand dock item (glasspane.el:114-128) retires behind the flag; its agenda `:badge` moves onto the Agenda destination via GR-7b's threading. `'standalone` is rejected for the named build-within exemplar — it would withdraw the core dock (jetpacs-apps.el:245-249, the standalone branch of `jetpacs-apps-dock-items`) AND S3 M-x injection (jetpacs-apps.el:286-294).
- **Boot seed of the current app** (without it the primary pole never engages: `jetpacs-apps--current-route`/current-app are written ONLY by the `app.open` handler, jetpacs-apps.el:419-420, and no init calls it — after every Emacs restart the hub would render the build-within core dock, no tabs, until the user routed through the app grid): new helper `jetpacs-apps-seed-current APP` (the same setter the handler uses, no device event), called at READY by every init that loads Glasspane — device/emacs-init.el today; the defvar's "written only by app.open" doc updates with it.
- **Destination fate table (7 → 5; §7.1 carries the rationale; OR-5 lets Caleb re-split with a one-list edit):** table order in `glasspane-ui-destinations` becomes `agenda journal search views review` — order is load-bearing (`seq-take … 4`, jetpacs-apps.el:229): tabs = **Agenda(badged) / Journal / Search / Views**; **Review stays a first-class destination but not tab-shaped**; **Tasks merges into Agenda**; **capture row deleted** (dialog, not a place — standing rule, glasspane.el:130-138).
- **Tasks merge mechanism:** the agenda screen gains a `jetpacs-tabs` "Tasks" page (body = the todo walk + `tasks.filter` state moved from the tasks screen); `tasks.open` retargets as an alias opening the agenda screen on that page (§3 back-compat); the `glasspane-tasks` screen family is deleted (behind the flag until GR-9). One more per-page token set under the agenda screen — 32/owner budget re-checked at GR-8c.
- **Review reconciliation (recorded):** no prior ratified "Review must be a tab" ruling exists — CHROME-VOCABULARY.md contains no Review clause (verified by grep at HEAD) and the #26 hub entry (PLAN-glasspane-app.md:1091) ratifies the ONE-TABLE invariant, not tab shape. Review stays first-class in that one table — rendered as hub dashboard card + drawer row + host-drawer nest row — and off the tab bar because it is session-shaped and absent-degraded when org-srs is missing: a permanently dead tab is worse IA than a live card. The one-table invariant survives intact: tabs, drawer, and hub all derive from the same registry, so #26 cannot recur.

### GR-8b — hub + drawer rebuilt S1-native (one commit; the debt plan's explicit directive)
- **Host drawer** (foundation-rendered from `:destinations` via `app.open :route`) is the canonical navigation list; Glasspane stops competing with it.
- **Hub (pinned root) becomes a dashboard, not a menu clone:** (a) "Now/Next" agenda preview card — top 3 items from the memoised extraction (now the GR-3 consolidated walk), item tap drills to detail; (b) Review card with memoised due count (install empty-state when org-srs absent — the srs precedent) — **the card IS Review's hub affordance; there is NO destination index on the hub** (it would duplicate, on the hub's own screen, the four tabs rendered right below it — §7.3's no-duplicate-rows claim is kept honest by omission, not exception); (c) journal quick-add input (the existing `journal.capture` datetree append); (d) capture via the registry FAB. **Discipline: dashboard reads are memoised-only** — chrome rebuilds the whole stack per push (the dock-badge rule; the static-subtitles rationale at glasspane-ui.el:180-183 generalizes to memoised-cards-only).
- **App drawer** shrinks to utilities: Settings row (`glasspane.settings.open`, unchanged `:any-surface` opener) + Review row. The duplicate destination table, the Home row (the `glasspane.home` drawer emission — **the verb itself SURVIVES per §3** as the M-x/programmatic reset), and the hand-wrapped `jetpacs-launcher-rows` apps-foot retire behind the flag; `jetpacs-apps-drawer-row` + host nests cover app-switching; routeless `app.open` is **return-to-APP (a plain resume of the stack top, jetpacs-apps.el:462-465 — NOT a reset; the hub is one system-back away)**.
- **jetpacs-org-mode's destination story (map OQ9, decided):** org-mode contributes NO `:destinations` this rework — post-GR-3/4/5 it is machinery (capture engine, reminders, clock: dialogs and alarms, not places). **Its dock item's true fate under the pole (recorded, accepted):** the primary branch keys on the CURRENT app with no surface check (jetpacs-apps.el:251-258), so while Glasspane is current — the tablet's normal state after the boot seed — org-mode's dock item never renders anywhere, and Files screens carry Glasspane's tabs. Accepted because the tablet is Glasspane's device and the daily driver (which never loads Glasspane) keeps org-mode's item everywhere; if that trade sours, Files-surface pole resolution (a surface check in the primary branch) is the recorded follow-up (§10). If org-mode ever grows destinations they coexist as a separate nest; no merge machinery built.

### GR-8c — navigation + slot/token audit (one commit)
- **Three-tier model adopted (§7.2)** with **NEW helper `glasspane-ui-open-destination`** (added this rung in glasspane-ui.el; reset+push peer semantics — nothing by this name exists at HEAD) adopted by all destination verbs and `views.open` (peer semantics: opening a saved view REPLACES views-hub in the destination slot — §7.2).
- **Route honesty for non-`app.open` navigation** (`jetpacs-apps--current-route` is written ONLY by the `app.open` handler, jetpacs-apps.el:55-59,419-420, while the plan's own flows reach destinations by owner verbs — the tag-chip → search jump, `tasks.open`, dashboard card taps — and back-from-destination leaves the stale route selected over the hub): small S2 extension `jetpacs-apps-note-route APP KEY` + clear-on-reset, called by `glasspane-ui-open-destination`; the defvar doc updates.
- **Per-screen-family slot-assumption audit — an explicit checklist with recorded resolutions in the rung notes** (each family's stale assumption + its fix is an auditable artifact): `views.delete` pop-when-on-top (delete is emitted from the view screen itself — still valid under the tier model; recorded); journal keep-day (re-enters via the re-entrant stack-insert truncation semantics, jetpacs-chrome.el:496-527, instead of assuming its origin survived); detail re-entry (constant id → same-id truncate-and-replace; detail→detail never evicts); the GR-1 guest-contention observation folded in.
- **Token budget (risk #11):** re-verify `ebp-org-token-sets-max` 32/owner headroom per screen family after consolidation (agenda's page cap stays; the Tasks page adds one set).
- **mark-pos adoption, scoped:** agenda-item jumps and notes backlink jumps move onto `jetpacs-navigate-thunk`/`jetpacs-navigate-buffer` with scroll-target mark-pos (the `jetpacs.org.follow` mechanism); a detail top action **"Open in file"** lands on the Files screen — rendered by the GR-2 adapter — scrolled to the heading. Migrating ALL group-B drill-in off `heading.tap`→detail is consciously NOT done (every card builder in five files; §10).

### GR-8d — periphery re-homing (**OR-2 executed by PA-3d, 2026-08-17**)
With GR-7a's funnel replacement landed, ef + gallery's last Glasspane couplings were removed.  Ef moved to `emacs/apps/ef-themes/jetpacs-ef-themes.el` (org-free, atop `jetpacs-theme-picker`, owner `jetpacs.ef`, Settings-satellite order 81); gallery moved to the foundation demo tier at `emacs/jetpacs-gallery.el` (owner `jetpacs.demo`, Settings-satellite order 84).  Both are registered by `jetpacs-init.el`, work without Glasspane, and survive `glasspane-unregister`.  SRS stays app-side (first-class Review destination, notes coupling; its funnels are mode-neutral or foundation-fed).

**Residual `:any-surface` audit result:** only the two generic entry openers, `ef.show` and `demo.gallery`, remain `:any-surface`, because their taps can precede creation of a sanctioned guest screen.  Every inner ef/gallery control is owner-scoped and rides S4 guest delegation; a foreign control on a Glasspane/Projects surface is regression-pinned as rejected.  `glasspane.settings.open` keeps the equivalent downstream opener rationale.

**Gate (GR-8, the big batch):** full ERT — tab generation from the new table (4 tabs, order, badge, `:selected` tracking), reset+push semantics (destination B removes destination A; drill preserved only within a destination), **route-honesty arms (reach Search via the tag-chip verb → Search tab `:selected`; back to hub → NO destination tab selected; boot-seed arm: seeded current app → tabs present with no prior `app.open`)**, tasks-page + `tasks.open` alias arms, hub dashboard builds offline from memos, single-source arms (registry feeds tabs+drawer+hub), deleted-verb absence arms, legacy-IA flag arms. **Device batch (PORTRAIT; force-stop; screenshot before EVERY tap):** **boot-state arm: force-stop → relaunch → tabs present on the hub with NO prior navigation (the seed, not the app-grid detour)**; tabs render ≤4 + Home with correct `:selected`; tab-hop Agenda→Journal→Search; back from a destination → hub **with no tab selected**; agenda→detail→tag-chip→search flow **ending with Search `:selected`**; badge on the Agenda tab; host drawer nest deep-links via `app.open :route` from a host surface; stale-route + refused-verb fallback-home on hardware; settings satellite as S4 guest from a Glasspane tab + back revoke; M-x on every tab; FAB injected on agenda/journal, absent on a screen authoring its own **and absent on the guest settings satellite**; "Open in file" scrolled landing; D-14 residual checklist rides along (ripgrep install, async first-count, search-ENTER). **Then: one full daily-driver soak day on the new IA before GR-9.**
**Tripwires:** T-4 (token overflow SIGNAL → halt, audit lifetimes), T-5 (push-cadence growth from the dashboard → D-5 graduates, funded before GR-9).

## GR-9 — Demolition + exit checklist (deletions cite their soaks)

**Steps:**
1. Delete the flag-gated corpses, each commit citing the ceremony + soak that justified it: org-mode's old inline reminder pipeline; glasspane-agenda's sync section + glasspane-org's reminder helpers; glasspane-capture.el; the legacy hub/dock/drawer code + `glasspane--dock-items` + `glasspane-tasks` screen family; the GR-2-superseded front-claim remnants; drop the now-constant flags.
2. **`glasspane.home` SURVIVES** (the §3 row): M-x parity + programmatic reset. Only its drawer emission site retired at GR-8b — routeless `app.open` resumes, it does not reset, so the verb keeps the only reset affordance.
3. Grep gates in the suite: zero references to any deleted symbol; `test/run-tests.sh` explicitly names every suite this plan added or moved (the K1a explicit-list trap, re-verified here).
4. Two-walk revisit: with GR-3 data, either grow the consolidated extractor to fully replace Glasspane's alias layer or record the delegation as accepted — decided from measurements.
5. **Exit device checklist (one consolidated day):** GR-0 single-alarm arm; §5.1 reboot-rearm; capture e2e; chronometer set (if GR-5 ran); GR-8 IA smoke spot-checks; org-crypt pull-and-verify; desync smoke re-run. All green ⇒ `git tag rework-closed`; stamp memory + §11's cross-reference into the debt plan.

**Gate:** full ERT + the checklist above.

## GR-10 — Upstreaming tail (each item decision-gated; none blocks GR-0..9)

| Item | Gate/ruling needed | Shape |
|---|---|---|
| glasspane-table.el → org adapter layer (matrix row 14) | **OR-4 (D-20/OQ2) first** | wholesale move to a `jetpacs-org-table.el` adapter module; verbs already base-named (`org.table.*`, `org.babel.*` — I-1 safe); relocate the `jetpacs-editor-org-save-policy` dep + `glasspane-babel-timeout` defcustom; device arm: cell edit + babel confirm on hardware |
| Per-heading affordances → reader adapter layer | design review | device-local folding, structured headers, quick-ops menu, swipe pair, refile drag with D-4 resolution, long-press sheet (glasspane-org-reader.el:148-524) |
| Heading-mutation verb family + typed property rows + logbook + file-properties dialog (incl. the 30.1 #+CATEGORY workaround) | design review — largest item | primitives expose these only as interactive commands today |
| ONE-grammar cross-file search + vulpea index arm | rides the reader-adapter story | upstream only if the foldable tree is the durable presentation |
| Demo seeder split | **OR-3** | IDE-tour half → foundation fixture infra; org corpus follows the capture owner |
| glasspane_mobile vulpea extractor | map OQ8 | stays a Glasspane opinion — **no rename** (`:worker-lib` resolution breaks for registered extractors) |

---

## §5 Cutover ceremonies (run verbatim; each is its rung's device gate)

### §5.1 Reminders: glasspane → org-mode (rides GR-3)

Precondition: GR-3 code merged and DEPLOYED; `jetpacs-org-reminders-enabled` nil, `jetpacs-org-mode-reminders-enabled` nil (stays nil forever — GR-0/GR-3), `glasspane-agenda-reminders-enabled` t.

**Ordering rule the steps implement: the losing hook goes INERT before its set is cleared** — clearing first would let any push in the clear→flip window re-arm the glasspane set from the still-armed hook (glasspane-agenda.el:81-102 syncs on every push), re-creating the device-lifetime orphan set I-2 exists to prevent.

1. **Schedule** a window with no timed item due within the next hour (already-notified-but-not-yet-past items re-fire once under the new owner unless cleared past `at_ms` — scheduling minimizes the exposure; the single-duplicate worst case is accepted and noted in the smoke script).
2. On the tablet, connected, `(jetpacs-granted-p "reminders.owner")` ⇒ t. Baseline: notification-shade screenshot + `dumpsys alarm | grep -i jetpacs`.
3. **Flip the LOSER off first:** `glasspane-agenda-reminders-enabled` nil, persisted into device/init.el and DEPLOYED (force-stop + relaunch) — from here no push can re-arm a glasspane set. The winner's flag is still nil: the device is reminder-quiet for the width of this ceremony (accepted; the schedule window from step 1 covers it).
4. `(jetpacs-reminders-clear "glasspane" (lambda (count err) (message "CLEAR glasspane: %s %s" count err)))` — **wait for the message. Timeout or error ABORTS the ceremony (T-1): revert step 3, retry another connected session. Never proceed on the session mirror** (jetpacs-device.el:170-176). Then `(jetpacs-reminders-clear "org-mode" …)` the same way, if any residue survived GR-0.
5. **Flip the WINNER on:** `jetpacs-org-reminders-enabled` t; persist into device/init.el; deploy; trigger any push.
6. Verify one set, owner "org-mode": `(jetpacs-reminders "org-mode")` non-nil **with every id matching `^org-mode\.rem-`** (the id-shape check — an `org-rem-*` id means the old inline pipeline ran; abort), `(jetpacs-reminders "glasspane")` nil, `dumpsys alarm` shows one RTC_WAKEUP per timed item. **A non-nil glasspane set here ⇒ re-run step 4; do NOT proceed.**
7. **Reboot arm:** reboot the tablet → `rearmAllReminders` re-arms ONLY `org-mode.rem-*` ids, zero `glasspane.rem-*` orphans (this is the check I-2 exists for).
8. **Fire arm:** seed a timed item ~5 min out (generated fixture bytes only) → fires once, notification once; date-only item arms nothing.

**Reverse ceremony (same loser-inert-before-clear order, mirrored):** flip `jetpacs-org-reminders-enabled` nil + deploy → `(jetpacs-reminders-clear "org-mode" …)` wait-confirmed → flip `glasspane-agenda-reminders-enabled` t + deploy → push → verify the glasspane set (ids `glasspane.rem-*`, org-mode set nil) → reboot arm.

### §5.2 Capture: glasspane → org-mode (rides GR-4)

1. Merge GR-4's tree (both registrations flag-selectable).
2. **Offline-queue drain check:** on the tablet, confirm the queue is empty — or replay it to empty — BEFORE deploying the owner swap, so no durable receipt straddles the owner change (a receipt queued under the old registration replaying across the swap is exactly the durable-state bug I-1 exists to prevent). Ensure downstream `user.el` explicitly requires Glasspane; Jetpacs no longer discovers or loads it by name.
3. Deploy; force-stop; run GR-4's device arms.

**Reverse:** `glasspane-capture-enabled` t / org-mode capture registration off; re-run the capture smoke.

### §5.3 Chronometer (rides GR-5; OR-1 ratified 2026-08-16)

1. Precondition: GR-0's I-8 fix landed and soaked (daily driver wants `surfaces.notification`).
2. **Clock-out gate:** verify no active clock and no live `notification:org-clock` posted (`org-clock-out` if needed) before the deploy — the ttl-3600 PendingIntents keep resolving by I-1, but the notification root's owner claim must not straddle the swap.
3. Deploy; run GR-5's arms (post / tap-out / offline replay during SYNCING).

**Reverse:** flag-flip; the pre-move notification was drained by step 2.

## §6 Capture `:any-surface` rationale (normative text for GR-4 step 3)

Recorded above verbatim in GR-4; it is the I-5 written rationale and pre-answers the review question of why the other two sanctioned mechanisms don't apply: **S4 rejected** because capture is a dialog and no guest screen exists at tap time; **forwarding rejected** because it leaves two live names for one action. Verified correct against the dialog-based sheet chain in glasspane-capture.el:84-243.

## §7 The IA/UX target (first-class design, implemented by GR-8)

### §7.1 Destination fate table (7 → 5)

Current table (glasspane-ui.el:149-171): agenda, tasks, journal, capture, search, views, review.

| Destination | Fate | Why |
|---|---|---|
| Agenda | **Tab 1** (badged) | the daily anchor; carries the memoised count via GR-7b `:badge` |
| Tasks | **merged into Agenda** as a `jetpacs-tabs` page | agenda already folds day/week/month/custom into one screen; Tasks is one more page; removes a screen family from the 2-slot budget; `tasks.open` survives as an alias |
| Journal | **Tab 2** | daily driver; the landing already treats it as a home |
| Search | **Tab 3** | frequent + the `search.by-tag` chip target from three modules |
| Views | **Tab 4** | the power library; deep-linkable, place-shaped |
| Review | **destination, not a tab** | session-shaped; absent-degraded without org-srs — a dead tab is worse than a live hub card; reached via hub card + drawer + host nest (see GR-8a's reconciliation note) |
| Capture | **not a destination** (unchanged) | dialog, not a place; the FAB story |

### §7.2 Three-tier screen model (fits `jetpacs-chrome-max-screens` 3 exactly)

- **Tier 0 — pinned root:** the hub dashboard. Never evicted.
- **Tier 1 — destination slot:** exactly one of agenda(+tasks page)/journal/search/views-hub/view-NAME/review. Destination opens are **peer navigation**: `glasspane-ui-open-destination` (NEW at GR-8c) = reset+push, so switching destination abandons the drill (tabs semantics everywhere in Android); back from any destination → hub. **`views.open` rides the same peer semantics: opening a saved view REPLACES views-hub in this slot** — that is what makes "exactly one of" true; the Views tab re-opens views-hub, one tap away.
- **Tier 2 — drill slot:** `glasspane-detail` (constant id; detail→detail re-enters via same-id truncate-and-replace, jetpacs-chrome.el:496-527 — never evicts). **There is NO sanctioned 3-deep flow and nothing ever evicts:** hub + view + detail = 3 exactly (the view sits in Tier 1 per the line above); back from a view → hub, back from detail → its Tier-1 origin.
- **Satellite one-slot rule (stated):** an S4 guest screen never pushes a second screen — its follow-ups are dialogs (the foundation one-live-dialog slot) — so a guest costs the host at most one slot.

### §7.3 Surface roles — no duplicate rows

Host drawer = canonical navigation (S1 registry). Hub = memoised-cards-only dashboard (agenda-peek/review-due/journal quick-add; NO destination index — the tabs on the same screen already are one). App drawer = utilities (Settings + Review). Tabs = daily loop. All four derive from ONE destination table — the #26 invariant, now enforced by the foundation instead of by hand.

**The two Homes, reconciled:** the dock's "Home" is the SHELL's (core first item — the Eval REPL hub on the daily driver, device/init.el:197-205); the glasspane hub is the APP's home — Tier 0, one system-back from any tier, resumed by routeless `app.open` from the host drawer; `glasspane.home` is the explicit reset (M-x/programmatic). Three affordances, three distinct jobs; none is renamed to pretend otherwise.

## §8 File fates — all 21 glasspane files + the jetpacs-org-mode delta

| File | Fate | Where / notes |
|---|---|---|
| glasspane.el | survives | loses hand dock item + the `glasspane.home` DRAWER emission (GR-8; the verb survives as the M-x/programmatic reset, §3) and clock hook install (GR-5); gains `:chrome 'primary` + `:fab` |
| glasspane-ui.el | survives, heavily rewritten | hub/drawer S1-native (GR-8b); `--defer-refresh` retired (GR-7a); FAB via registry; remove-link via foundation |
| glasspane-config.el | survives | capture-template seeding stays (recorded non-move); the downstream app entry owns its ensure call, with no Jetpacs bootstrap knowledge |
| glasspane-packages.el | survives | unchanged; `glasspane.packages.install` stays under S4 delegation |
| glasspane-capture.el | **dies (moves)** | → `emacs/jetpacs-org-capture.el` owner "org-mode" (GR-4), absorbing org-protocol + template filtering; names byte-identical |
| glasspane-clock.el | **dies (moves)** | → `emacs/jetpacs-org-clock.el` (GR-5, OR-1 ratified); Glasspane keeps only opinionated clock-affordance placement |
| glasspane-org.el | survives, slimmer | reminder helpers die (GR-3/9); extraction delegates to the consolidated org-mode walk; save funnel wraps the foundation save-policy seam + before-save discipline (GR-6); query/search/stamps stay |
| glasspane-org-reader.el | survives as reader adapter | front-claim → `jetpacs-reader-register 'org` replace-in-place with fallback guard (GR-2); dead JA-6 assumptions deleted; subtree entry exported; heading affordances = GR-10 candidate |
| glasspane-detail.el | survives | detail.save gains merged freshness core + before-save + synced-doc refusal (GR-6); builders exported (GR-7a); "Open in file" action (GR-8c); mutation verb family = GR-10 candidate |
| glasspane-table.el | moves (gated on OR-4) | → adapter layer at GR-10; survives in place until then |
| glasspane-dates.el | **dies (moves)** | → `emacs/jetpacs-dates.el` (GR-7b) |
| glasspane-agenda.el | survives | reminder sync section dies (GR-3/9); gains the Tasks page (GR-8a); badge moves to the destination tab; cards stay |
| glasspane-journal.el | survives | `journal.capture` stays (not org-capture); day render keeps the exported subtree entry; keep-day resolved via re-entrant re-entry (GR-8c) |
| glasspane-views.el | survives | refile-lists via public accessor (GR-7a); pop-when-on-top audited + recorded (GR-8c) |
| glasspane-search.el | survives | Tab 3; core unchanged |
| glasspane-notes.el | survives | backlink jumps adopt mark-pos (GR-8c) |
| glasspane-srs.el | survives | stays app-side (decided, GR-8d); durability pinned to the save-policy seam (GR-6); funnels re-pointed (GR-7a) |
| glasspane-ef.el | **dies (moved at PA-3d)** | → `emacs/apps/ef-themes/jetpacs-ef-themes.el`, owner `jetpacs.ef`; Glasspane has no lifecycle dependency |
| glasspane-gallery.el | **dies (moved at PA-3d)** | → `emacs/jetpacs-gallery.el`, owner `jetpacs.demo`; registered by the Jetpacs composition root |
| glasspane-demo.el | splits (gated on OR-3) | IDE-tour half → foundation fixture infra; org corpus follows the capture owner — GR-10 |
| glasspane-vulpea.el | survives | `glasspane_mobile` extractor stays; NO rename (`:worker-lib` resolution) |

**jetpacs-org-mode delta:** GAINS `emacs/jetpacs-org-capture.el`, `emacs/jetpacs-org-reminders.el`, and `emacs/jetpacs-org-clock.el` (OR-1 ratified), required+registered from the composition root; the consolidated rich agenda extractor (GR-3). LOSES the bridged-prompt capture path + share fallback + `--owns-share-action` deference (GR-4), the inline reminder pipeline (GR-3/9); `org-mode.capture` becomes a deprecation alias. CONTRIBUTES no `:destinations` (decided, GR-8b); dock item code-unchanged but **suppressed whenever Glasspane is the current app** (the primary branch has no surface check — GR-8b records the acceptance; on the daily driver, which never loads Glasspane, it renders everywhere as today). Capture success keeps the whole-cache invalidate (the GR-4 step 4 ruling).

## §9 Tripwire table (named observations, named abort actions)

| # | Observation | Abort action |
|---|---|---|
| T-1 | `jetpacs-reminders-clear` callback timeout/error mid-ceremony | abort ceremony, flags unchanged, retry another connected session — never proceed on the session mirror |
| T-2 | reverse-order `event.action` replies under batch traffic | halt the ladder; fund informed-execution R4 (D-6) first |
| T-3 | any D1 `rejected` from a capture-path tap post-GR-4 | abort rung; re-inventory emission sites against §3 before retry |
| T-4 | `ebp-org-token-sets-max` overflow SIGNAL on consolidated screens | halt; audit token-set lifetimes/sweep timing before proceeding |
| T-5 | push-cadence growth from the GR-8 hub dashboard (watch Companion logs during the batch) | D-5 (SurfaceStore.persist amplification) graduates to correctness-risk and is funded before GR-9 demolition |
| T-6 | any daily-driver regression during a soak day | reopen the rung via its rollback; the soak restarts after the fix |

## §10 What this plan deliberately does not do

- Build the Companion ACTION_SEND share intake (D-12) — GR-4 smokes share replay by injection, honestly; intake is the first Companion-side follow-on, unblocked by GR-4's single-owner settlement.
- Flip the legacy JA-6 seams flag (`jetpacs-org-render-install-legacy-files-seams` stays nil; the dead assumptions are deleted instead).
- Adopt a reminder `:on_tap` — neither implementation authors one today; a future reminder-tap deep link rides ownerless `app.open :route`, designed then, not now.
- Grow an embeddable subtree/list API on the reader host (map OQ6) — journal + views stay app-composed via the exported entry points.
- Migrate group-B drill-in cards off `heading.tap`→detail (five files of card builders — recorded follow-up).
- Route detail.save through the SPEC-19 sync splice — GR-6 ships the refusal snackbar; splice routing is the recorded follow-up.
- Rename `config.sync` (zero emission sites; stays the M-x-only allowlist entry) — recorded, matches map OQ11.
- Add a surface check to the S2 primary branch (Files-surface pole resolution) — GR-8b records the acceptance of org-mode's dock item being suppressed while Glasspane is current; this is the follow-up if that trade sours.
- Move Saved Searches, srs, `journal.capture`, or glasspane-config template seeding (standing rulings/recorded non-moves).
- Touch the widget/tile track (D-19 STOP stands).

## §11 Cross-reference stamp for docs/PLAN-jetpacs-debt-and-scaffold.md (apply on that doc's next edit; this plan does not modify it)

> **Glasspane-on-primitives rework: planned 2026-08-14 → docs/PLAN-glasspane-rework.md** (ladder GR-0..GR-10). Executes the ratified capture+reminders ownership cutover to jetpacs-org-mode and the §4 ordering-note directive (hub/drawer/dock rewritten against S1/S2/S3 at GR-8). Arms this ledger's tripwires as GR §9 T-2 (reverse-order replies → fund R4) and T-5 (persist amplification → graduate D-5); closes the S1–S5/S4-guest device-coverage debt at GR-1/GR-8; funds FOUNDATION-GAPS #2 (FAB registry) and #10 (dates util) at GR-7b. D-12 (Companion share intake) remains the first Companion-side follow-on after GR-4.

## §12 Coverage cross-checks (auditable from this doc alone)

**Duplication matrix (16 rows → rungs):** 1 reader front-claim→GR-2 · 2 detail.save/save-narrowed→GR-6 · 3 agenda extraction→GR-3 · 4 reminder pipeline→GR-0+GR-3 · 5 capture UX→GR-4 · 6 share.text race→GR-4 · 7 filter vs in-doc search→GR-2 · 8 view-mode drift→GR-2 · 9 hub/drawer vs S1→GR-8b · 10 dock vs S2 tabs→GR-8a · 11 defer-refresh→GR-7a · 12 save-and-invalidate superset→GR-6 · 13 org-crypt inverse gap→GR-6 · 14 table/babel→GR-10 · 15 remove-link+FAB gaps→GR-7b · 16 chronometer→GR-5.

**Risks (14 → mitigations):** #1 duplicate alarms→GR-0 · #2 durable reminder sets→§5.1/I-2 · #3 durable verb names→§3/I-1 · #4 cleartext+no-mtime→GR-6 · #5 seam-collision UX→GR-2 · #6 cache cross-talk→GR-4 step 4 ruling + GR-6b whole-cache save-policy + GR-3 extractor consolidation · #7 slot pressure→§7.2+GR-8c audit · #8 zero hardware coverage→GR-1 floor + per-rung arms + GR-8 batch · #9 wants∩supported→GR-0 · #10 D1 cross-owner rejection→GR-4 `:any-surface` rationale + T-3 · #11 token budget→GR-8c + T-4 · #12 private coupling→GR-7a · #13 SPEC-19 overlap→GR-6 step 3 · #14 armed tripwires→§9.

**Upstream candidates (12 → disposition):** table.el→GR-10/PA-5 (OR-4 ratified) · save-policy seam→GR-6 · freshness merge→GR-6 · per-heading affordances→GR-10 · mutation verb family→GR-10 · cross-file search→GR-10 · dates util→GR-7b · settings-remove-link→GR-7b · FAB registry→GR-7b · clock→GR-5(OR-1 ratified) · ef/gallery→GR-8d/PA-3d (OR-2 executed) · demo seeder→GR-10(OR-3).
