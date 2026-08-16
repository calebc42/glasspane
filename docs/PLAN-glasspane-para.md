# PLAN — Glasspane PARA: the fresh IA (Agenda-rooted, shared-bar, PARA-shaped)

Repo: `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-3` @ **8965e40** (slop-fork/main; = S9 31c3f1c + S11 ee34b40 + S10 8965e40 — both seams committed while this plan was in review, so the "in-flight" caveat resolved before it landed). Written **2026-08-15**. Line cites were verified against exactly this tree state. PA-3b's S11 dependency is satisfied at the commit level; the APK deploy remains its device-side precondition.

**Authority:** the ratified PARA vision (Caleb, 2026-08-15 — §0 verbatim) + the surviving machinery half of `docs/PLAN-glasspane-rework.md` (GR-0..GR-7, unchanged). Produced by a full planning workflow (3 exploration + 3 design agents, 2026-08-15); every mechanism claim was re-verified in-tree while drafting.

**Companion docs:** `docs/PLAN-glasspane-rework.md` — **this plan supersedes its §7 + GR-8 and re-scopes GR-9/GR-10**; that doc is NOT edited here; §10 carries the stamp for its next edit. `docs/PLAN-jetpacs-debt-and-scaffold.md` — §10 carries its stamp. `docs/CHROME-VOCABULARY.md` — **v4 ratified 2026-08-15 alongside this plan** (the full-bar clause + the S8 root-only drawer-injection sentence; edited in its own commit, not in passing).

**Ladder prefix is PA- (PARA)** — fresh per the D-6 label-collision rule (GR-, G0–G9, R2/R4/R6 taken; grep `\b(PA|GP)-[0-9]` at this tree = zero prior hits). A session resuming "PA-2c" from this doc alone cannot land on another ledger.

> **AUTHORITATIVE NAVIGATION CORRECTION — Caleb, 2026-08-16.**
> This overrides the five-tab/full-bar/core-suppression placement described
> below.  **Agenda, Projects, Areas, Resources, and Review are not tabs.**
> They are peer entries on Jetpacs' persistent navigation surface — the
> compact NavBar/BottomAppBar and its responsive rail form — immediately
> alongside the existing **Eval** and **Files** entries.  Eval and Files stay
> in that bar.  **Apps leaves the bar and is NavDrawer-only.**
>
> The resulting seven peer destinations must all remain reachable from the
> navigation surface; the old 3–5 cap, `seq-take`, or silently relocating
> entries into the drawer is not an acceptable implementation.  In-body
> `jetpacs-tabs` pagers (for example Agenda's day/week/month pages) are a
> separate widget and are unaffected.
>
> GR-0..GR-7 and the PARA data/screen/verb decisions remain valid.  The PA-1
> and PA-3 navigation-placement mechanics, every `:dock-core nil` instruction,
> and later uses of “tab” for these destinations are **non-executable until
> rewritten after GR-7b**.  That rewrite must fund the seven-item responsive
> bar, preserve route selection/badges, and make Apps drawer-only before any
> IA implementation begins.

Full ERT gate everywhere below = `test/run-tests.sh` — **the runner is an EXPLICIT list; a suite not named there never runs (the K1a merge lesson). This whole ladder adds ONE suite, `test/glasspane-para-test.el`, wired into the list in the same commit as PA-1; every later rung only adds arms to it.**

---

## §0 Ratified inputs (Caleb, 2026-08-15 — decisions, not options)

1. **The bar is exactly five destinations: Agenda, Projects, Areas, Resources, Review.** No shell Home row. The core-suppression mechanism extension (§5.1) is sanctioned.
2. **Agenda is home — no hub.** The hub dashboard dies whole. Agenda = day/week/month pages + custom-agenda pages + one new "Saved" page (the views fold, §5.5). System back at the Agenda root exits the app (Android-normal for a nav-bar root).
3. **Projects = anything with a TODO stage.** v1 = the todo walk grouped **by file** with the existing TODO-keyword filter chips as the second axis; heading-level project-entity grouping is the recorded follow-up, not v1.
4. **Areas = org categories.** New backend (nothing exists at HEAD — `org-get-category` is never called and the query grammar has no category term).
5. **Resources = a wrapper around the vault's files.** Row tap is the **hybrid**: org files drill IN-APP through the reader builder; non-org files hand off to the Files app via the public `jetpacs-files-open-path` (D1-clean elisp call, visible surface switch recorded as the cost).
6. **Review v1 = SRS flashcards + stale vulpea files**, plus the cheap Habits LINK row to the existing `jetpacs.org` habits surface. "On this day last year" and habits/metrics aggregation are **noted future work only** (§9).
7. **Drawer:** Eval + Files (the auto-relocated suppressed core, §5.1), Archive (a drawer-only destination), the Apps row, the host Tools/Settings nests. **Journal is deleted. Search moves to the top app bar.** Capture stays the FAB dialog (never a place).
8. **PARA replaces GR-8's IA.** GR-0..GR-7 survive unchanged and remain prerequisites where named; this plan supersedes the rework's §7 + GR-8 and re-scopes GR-9/GR-10 (§2). The rework's OR-5 is resolved by supersession.
9. **CHROME-VOCABULARY v4** (ratified): the APP-PRIMARY sentence gains the full-bar form — *"core collapses to one Home, or, when the app declares the full-bar form, to none: the app's destinations fill the M3 3–5 budget whole, and every core destination remains reachable in the navigation drawer (M-x parity is the floor, not the bar)."* The S8 root-only drawer-injection rule rides the same v4 batch (it was pending ratification in the debt plan's S8 entry).
10. **Back-gesture tab honesty: repush on route change** — one bounded repush per route-changing companion-local back (§5.4); T-5 re-armed over it.
11. `journal.capture` winds down through a **deprecation alias + queue-drain ceremony** (§4 PA-4), never a bare delete — it is a durable queued verb (`:when-offline "queue"`, ttl 86400, glasspane-journal.el:75,178-181).

**PROPOSED, NOT RATIFIED — open rulings for Caleb (executing a rung that touches one requires the ruling first):**

- **PA-OR-1** Areas upgrade path: v1 honors org's three category layers app-side (keyword / inherited `:CATEGORY:` property via `org-get-category` / basename fallback) with **no** query-grammar `category` term. Growing the grammar later is a five-touch-point foundation change (matcher, point-get, wire allowlist, vetter, note-terms kept OFF so vulpea routing degrades correctly). Rule only if saved views/search want area filters.
- **PA-OR-2** Registry merge: `glasspane-org-custom-agendas` (page-shaped) ⇄ `glasspane-saved-views` (rendering-shaped) stay two registries, both presented on the Agenda "Saved" page. A merge is a data-model migration — recorded, deferred.
- **PA-OR-3** Review tab badge (due count via `glasspane-srs--due-count`): **deferred** — the Agenda badge owns the bar's one number first. Revisit after the PA-3 soak.
- **PA-OR-4** ef + gallery re-homing: the rework's OR-2 content unchanged; its decision venue ("the IA restructure decides") is now THIS plan — rule at PA-3d or leave both app-side and green.

## §1 Hard invariants (violating any is a plan defect)

**I-1..I-8 are inherited verbatim from PLAN-glasspane-rework.md §1** (durable verb names; reminder cutover ordering; duplicate-alarm mitigation; org-crypt; D1 surface scoping; slot budget; device-smoke-before-rebase; wants∩supported) — I-6's pointer to "§7's three-tier model" now reads through this plan's §5.3.

- **I-9 ONE-TABLE (#26).** Tabs, the host-drawer destination nest, and every route deep-link derive from the ONE destination table (glasspane-ui.el:149). The hub's verb-inventory gate tests survive the hub's death renamed to a root-reaches-every-opener form — a destination can never be reachable in one surface and missing from another.
- **I-10 The M3 bar contract.** Three to five destinations, places never actions, `:selected` always indicated, the bar persists on every screen (a bar that vanishes on drill is a defect). Search's top-bar seat is the ratified exception to place-shaped-things-go-in-the-bar: it is screen-scope ACTION chrome, not a destination.
- **I-11 M-x parity.** Every new affordance (tabs, drawer rows, top-bar search, Habits link) projects a command reachable without it.
- **I-12 K1a.** `test/run-tests.sh` is an explicit list; this ladder's one suite is wired at PA-1 in the same commit that creates it.
- **I-13 Durable-carrier discipline for dying/moved verbs.** Before any verb registration is deleted or retargeted, its durable carriers are enumerated and a wind-down named (`journal.capture` is the template, §3). A vanished durable verb turns queued replays into permanent `rejected` deletions.
- **I-14 The back contract.** Exactly ONE Glasspane screen — the Agenda root — yields system back to the Activity; every other screen's gesture pops (S11 dispatches the screen's own authored back descriptor). A second back-less Glasspane screen is a defect.

## §2 Relationship to the rework plan (the supersede map)

**SUPERSEDED by this plan:** rework §7 whole (7.1 fate table, 7.2 three-tier as written — the *mechanism* survives re-parameterized in §5.3, 7.3 surface roles incl. "The two Homes"); GR-8a/b/c/d as written (surviving mechanisms are re-hosted in §4/§5); the GR-8 gate; OR-5 (resolved: the ratified tab list is §0.1); GR-9's demolition list (PA-4 carries the successor); rework §8 rows for glasspane-ui / glasspane-agenda / glasspane-journal (flips survives→dies) / glasspane-views / glasspane-search.

**SURVIVES UNTOUCHED:** GR-0..GR-7 whole, in order — they remain the machinery floor this plan stands on (GR-7b's `:badge` threading and `:fab` registry are hard dependencies of PA-3a; GR-2's reader adapter is the soft dependency of PA-2b/2c; GR-3's consolidated extractor is the substrate of PA-2a/2d). Rework §2 ordering argument, §3 verb-contract structure, §5 ceremonies, §6, I-1..I-8, §9 tripwires, §10 (minus the overridden row below).

**AMENDED (one-line stamps on the rework doc's next edit — §10 here carries them):** GR-3 step 3's consumer list ("the GR-8b dashboard" dies; consumers = agenda cards + the Agenda tab badge + reminders); GR-7b's "at GR-8a" phrases → PA-3a; GR-2 step 7's "(journal's day render)" parenthetical → the surviving `glasspane-org-reader-subtree` consumer is glasspane-detail.el:907-914; **the `journal.capture` "stays permanently" non-move (GR-4 step 6, rework §10) is OVERRIDDEN by §0.11**; §3 rows for `tasks.open` (retargets to Projects, not an Agenda page) and `glasspane.home` (resets to the Agenda root, not the hub).

## §3 Verb inventory — the PARA delta (rework §3 discipline; every row I-13-checked)

| Verb | Fate | Durable carrier | Call |
|---|---|---|---|
| `projects.open` `areas.open` `areas.drill` `resources.open` `resources.open-file` `archive.open` `review.habits.open` | NEW, owner-scoped, M-x parity | — | grep-verified no collisions (`jetpacs.org.archive` at jetpacs-org-dialogs.el is the unrelated heading action; coexists) |
| `tasks.open` | survives as alias → `projects.open` | old receipts (rework §3 row) | keep the alias; cheap insurance |
| `views.hub` | survives as alias → Agenda landing on the Saved page | live taps + drawer rows | alias insurance, same pattern |
| `views.open` | survives unchanged; per-view screen becomes a Tier-1 peer (back → Agenda root) | live taps | — |
| `journal.open` `.nav` `.goto` `.today` | DIE | live taps only (verified) | flag-gated at PA-3, deleted at PA-4, no alias |
| **`journal.capture`** | DIES with ceremony | **YES** — queued, ttl 86400 (glasspane-journal.el:75,178-181) | headless datetree-append **deprecation alias ≥ one release** (the `org-mode.capture` precedent); PA-4 queue-drain check (the §5.2-step-2 pattern from the rework) before final delete |
| `heading.schedule` (journal carried-card emission) | verb survives (detail/G4 family); this emission site dies | queued + ttl | swept `journal-carried` tokens answer `'stale` by design — recorded, no action |
| `search.open` | MOVED: destination row dies; verb + screen survive; entry = top-bar icon (§5.6) | live taps | `search.by-tag` chip flows unchanged (three emitting modules) |
| `glasspane.home` | survives, RETARGETED: the reset lands on the Agenda root | drawer/M-x/programmatic | rework §3 row amended per §2 |
| `agenda.open` `review.open` `org.capture.show` | unchanged (`agenda.open` becomes the root's verb) | per rework §3 | — |
| `tasks.filter` | moves with the body to glasspane-projects.el, name unchanged | live taps | screen-local |

## §4 Rung ladder

Each rung ends with a gate; the tree stays green and the tablet daily-driver functional throughout. Rollback doctrine inherited verbatim from rework §2 (losing implementations behind a `defvar` until the soak closes; scripted reverses; tripwire = stop, restore, re-smoke, record, diagnose). Legacy IA lives behind **`glasspane-ui-legacy-ia`** until PA-4.

| Rung | Name | Depends on | Size | Device arm? | RISKY |
|---|---|---|---|---|---|
| PA-0 | Governance: doc lands; v4 lands; stamps queued; S10/S11 fate pinned; `git tag para-baseline` | — | S | no | no |
| PA-1 | Pole mechanics: `:dock-core` + relocation rule + `:tab` key + seed-ROUTE + doc-drift fix + suite wiring | GR-7b | S | no | no |
| PA-2a | Areas backend + screens (`glasspane-areas.el`) | GR-3 | M | no | no |
| PA-2b | Archive backend + screen (rides the Resources walker) | PA-2c; soft GR-2 | S | no | no |
| PA-2c | Resources backend + screens (`glasspane-resources.el`) | soft GR-2 | M | no | no |
| PA-2d | Projects module (`glasspane-projects.el`, tasks body promoted) | GR-3 preferred | S | no | no |
| PA-2e | Review-as-tab (combined empty state + Habits link + session arm) | — | S | no | no |
| PA-3a | Pole + ONE-TABLE flip: `:chrome 'primary :dock-core nil :fab`, the 6-row table, badges, hand dock item retires | PA-1, PA-2* | M | rides batch | yes |
| PA-3b | Root swap: Agenda = pinned root; hub retires behind the flag; Saved page; boot seed; route hooks | PA-3a, **S11 deployed** | M | rides batch | YES |
| PA-3c | Destination screens wired + slot/token audit (GR-8c analog) | PA-2*, PA-3a | M | rides batch | yes |
| PA-3d | Drawer handover + top-bar Search + aliases + PA-OR-4 venue | PA-3b | M | rides batch | yes |
| — | **PA-3 gate: the big device batch + ONE daily-driver soak day** | all PA-3 | — | **YES** | — |
| PA-4 | Demolition + exit checklist (supersedes GR-9's list); `git tag para-closed` | PA-3 soak | M | YES (checklist) | no |
| PA-5 | Upstreaming tail = GR-10 re-hosted (content unchanged, executes after PA-4) | PA-4 + rulings | L | per item | no |

PA-2a..2e are ERT-only and parallelizable with GR-4..GR-7 (none touch reminders/capture/clock). The GR-8 soak-day slot transfers to PA-3.

### PA-0 — Governance (this commit)

This doc + the CHROME-VOCABULARY v4 edit land as two `docs(...)` commits. **S10/S11 fate pinned:** both are in flight uncommitted at drafting time; **S11 (Companion BackHandler) is a hard precondition of PA-3b's device arms** — without it the system gesture exits the Activity from anywhere, making the I-14 arms unrunnable; S10 (globals placement) is an interaction note only (M-x top-bar + Search = 2 icons, inside the top-bar contract; S10's FAB placements yield to the GR-7b capture FAB on Glasspane screens). They commit on their own ladder; this doc's header is re-stamped with the post-resolution commit at PA-1. `git tag para-baseline` on the deployed tree+APK pair when execution starts.

### PA-1 — Pole mechanics (foundation, additive)

1. **`jetpacs-defapp` gains `:dock-core` (default t)** (jetpacs-apps.el:104-142): validated `(memq dock-core '(nil t))`, stored in the registry plist. NOT a third `:chrome` pole — v4 ratifies full-bar as a *parameter of* APP-PRIMARY, and CHROME-VOCABULARY ratified exactly two poles.
2. **The primary dock branch honors it** (jetpacs-apps.el:277-283): `:dock-core nil` on the current entry binds `core` to nil → `room` = 5 → `jetpacs-apps--destination-tabs` fills the whole bar. Default t keeps every existing caller byte-identical.
3. **The relocation rule:** `jetpacs-apps-drawer` (jetpacs-apps.el:356-378) composes the suppressed core items as `jetpacs-chrome-row`s between the destination nests and the host tail (same `:dock-core nil` + primary + current check). Shell destinations never vanish; they relocate — this is how "Eval in the drawer" ships, with zero Glasspane authoring (the hub's core items are Eval `hub.home` + Files, jetpacs-init.el:297-310).
4. **`:tab` destination key** (rides GR-7b's plist extension in `jetpacs-apps--check-destination-list`, jetpacs-apps.el:63): optional; `(:tab nil)` rows are filtered out of `jetpacs-apps--destination-tabs` BEFORE the `seq-take` (which stays as the M3 backstop). Chosen over cap-order because a 5/5 bar cannot distinguish "sixth would-be tab" from "never a tab", and a future mid-table insertion must not silently evict Review.
5. **`jetpacs-apps-seed-current` gains `&optional ROUTE`** (the GR-8a helper re-hosted): the tablet harness init calls `(jetpacs-apps-seed-current "glasspane" "agenda")` at READY — 5 tabs, Agenda selected, before any `app.open`.
6. **Doc-drift fix (discovered drafting this plan):** the primary branch appends the FULL core list while the docstrings (jetpacs-apps.el:121-127, :263-267) and the pre-v4 vocabulary claim "collapses to its first item" — with the hub's 2-item core, primary today would render Eval+Files+3 tabs. Docstrings rewritten to the v4 truth: core items all render; `:dock-core nil` suppresses them into the drawer.
7. **`test/glasspane-para-test.el` created and wired into `test/run-tests.sh`'s explicit list in this commit** (I-12).

**Gate:** full ERT + new arms: `:dock-core` validation; primary+suppressed → 5 tabs, zero core; primary+default → core + room tabs (the drift arm); relocation rows present in the composed drawer exactly when suppressed; `:tab nil` filtered from tabs, present in drawer nests; seed-with-route arm (tabs + `:selected` with no prior `app.open`); daily-driver arm (no current primary app → core items everywhere, bytes unchanged).

### PA-2a — Areas (`emacs/apps/glasspane/glasspane-areas.el`, new)

App-side module (srs/notes shape, register/unregister from glasspane.el's sweep) — NOT glasspane-org.el (GR-3 moves generic extraction to org-mode; category-as-IA is a Glasspane opinion; recorded non-move keeps it out of GR-3's blast radius).

1. **Extractor** `glasspane-areas--index`, memoised `(ebp-org-with-cache 'glasspane '(areas-index) …)`: over `(glasspane-org--agenda-scope)` (never the `org-agenda-files` FUNCTION — P1-7), per file under `ebp-org--with-clamped-io` with per-file `condition-case`-skip (the habits-walk discipline, jetpacs-org-habits.el:93-122): file-level `#+CATEGORY` via `org-collect-keywords` else basename-sans-extension; `org-map-entries "TODO<>\"\""` collecting the standard item alist + `(category . (org-get-category))` so inherited `:CATEGORY:` properties create their own buckets. **30.1 hazard:** stock `org-element.elc` mis-compiles the category cache-miss arm — apply the in-tree workaround (prime `org-element-at-point` at the keyword line, the glasspane-detail.el:1805-1814 recipe); the per-file skip is the backstop. Deliberately the file arm even when vulpea is up (the note index carries explicit drawer props only — an index arm would silently re-bucket the vault; documented at the arm).
2. **Screens/verbs:** `areas.open` → list screen (name + open-TODO count + "N files", sorted); tap → `areas.drill :args (:category NAME)` — **plain string args, zero token sets for the list** (the `tasks.filter` precedent). `areas.drill` → Tier-1 peer screen (id `(jetpacs-wire-id "area" NAME)`; replacing the areas list in the destination slot is the views-open-replaces-views-hub precedent): section 1 = the category's TODO cards via the shared card builders + `glasspane-agenda--tokenize items "areas"` (mints the dialogs-owner twin too, keeping swipe-archive working); section 2 = the category's files, rows tapping the Resources drill verb. Vanished category → empty state, never an error.
3. **Token budget:** +1 set ("areas") + its dialogs-owner twin — the ladder's whole net delta (§7).

**Gate:** arms: bucket layering (keyword / inherited property / basename); rotten-file skip; string-arg drill round trip; empty-category degrade; grep-pin the module never calls `org-agenda-files` (the habits suite's pin pattern); 30.1 CATEGORY workaround arm.

### PA-2b/2c — Resources + Archive (`emacs/apps/glasspane/glasspane-resources.el`, new; one module, two screens)

1. **Walker** `glasspane-resources--files`: `directory-files-recursively` over `org-directory` matching `\.org\'`, excluding `_archive\'`, capped by a defcustom (~500, the `jetpacs-files-scan-cap` precedent), memoised `'glasspane '(resources)`. Per file ONE `file-attributes` (mtime+size); title via vulpea when present (soft probe, never a require); open-TODO chip joined free from the memoised todo walk. `glasspane-org--file-list` stays as-is for its current consumer.
2. **Freshness:** these files sit OUTSIDE the cache stamp (agenda files only, ebp-org.el:304-337) — invalidate the `(resources)`/`(archive-files)` keys from `jetpacs-shell-refresh-hook` (the srs reprobe precedent). Pull-to-refresh is the honest freshness story; no stamp surgery.
3. **Screens/verbs:** `resources.open` → the list (name/title, mtime age caption, TODO chip). Row tap = `resources.open-file :args (:path P)` — path args on the wire (the jetpacs-files precedent); handler validates via `ebp-org--check-file`, signals mapped through `ebp-org-refusal-disposition`. **The ratified hybrid:** org paths → a drill-slot screen whose body is the exported reader builder (`glasspane-org-reader--reader-body`) — in-app, offline, normal back, route untouched (honest `:selected`); after GR-2 the drill consumes the adapter's `:render` name (soft dependency — the builder is screen-callable at HEAD). Non-org paths → `(jetpacs-files-open-path path …)` — public elisp outward call, D1-clean; the visible surface switch is the recorded cost.
4. **Archive** (`archive.open`, drawer-only via `:tab nil`): the same walker parameterized to `_archive\'` files (memo `'(archive-files)`). The default `org-archive-location "%s_archive::"` puts them beside their sources — inside `ebp-org--roots`, so path policy passes for free. Row = source name + mtime; tap = the same drill verb. **Predicate widening (a real defect on the way):** `glasspane-org-reader--org-path-p` requires `.org` — widen to `\.org\(_archive\)?\'` so archives render as org trees; note for GR-2 that the adapter `:predicate` should match.
5. **Leak audit (verified):** `_archive` files do NOT leak into agenda/Projects for directory-style config (`org-agenda-file-regexp` excludes them); the two remaining edges (an explicit agenda-files ENTRY naming an archive; a custom vulpea indexing archives) are covered by PA-2d's display filter.

**Gate:** arms: cap; `_archive` exclusion (Resources) / inclusion (Archive); path-validation status split (refused/unresolved/unavailable); refresh-hook invalidation; org-vs-other routing; predicate widening; roots-policy pass for an archive file; no-unarchive grep pin.

### PA-2d — Projects (`emacs/apps/glasspane/glasspane-projects.el`, new, thin)

The tasks body promoted honestly: keyword chips + shared cards over `glasspane-org--todo-items` (both arms intact — vulpea whole-vault when the index is up, else the agenda-scope map), **grouped by file** (`seq-group-by` + basename section headers — a pure fold; items already carry `file` in both arms; ratified §0.3). `tasks.filter` moves with the body, name unchanged; `tasks.open` becomes the alias (§3). Token set: reuses `"tasks"` — net zero. **Archive display filter:** drop items whose `file` matches `_archive\'` (the leak-edge insurance). Recorded follow-ups, not v1: project-entity grouping (nest under level-1 headings — pure fold, items carry `level`+`pos`); group-by-category (reuse the Areas index).

**Gate:** arms: alias; group-by-file fold over both arms' item shapes; archive display filter; chips-filter regression.

### PA-2e — Review-as-tab (edit `glasspane-srs.el`)

1. **Never-dead guarantee:** org-srs absent → the existing install body already renders a live installer (keep exactly). vulpea absent → stale half absent (keep, while the other half lives). **Both absent** → ONE combined empty state ("Review needs engines — org-srs for flashcards, vulpea for stale notes", install button when available) + the Habits row — the tab is live and useful in every configuration. This answers the rework's dead-tab objection (its §7.1 Review row) now that §0.1 ratifies Review as Tab 5.
2. **Habits link row** (ratified): rendered when `(featurep 'jetpacs-org-habits)`; new verb `review.habits.open` guards `fboundp` and calls the habits push (`jetpacs-org-habits`'s own entry to the `jetpacs.org` surface) — outgoing elisp push, D1-clean; surface-switch cost recorded (same class as the Resources handoff).
3. Session-vs-tab state: unchanged (session defvars + the screen's session/idle body switch); one new arm pins tab-hop-away-and-back resumes.

**Gate:** arms: both-absent combined empty state; habits-row gating; session-resume-across-tab-hop.

### PA-3a — Pole + ONE-TABLE flip

`glasspane`'s defapp gains `:chrome 'primary :dock-core nil :fab <capture descriptor>` (the GR-7b registry; the per-screen hand-authored FAB node retires). **The table** (glasspane-ui.el:149 rewritten; I-9):

| # | :key | :label | :icon | :verb | :badge | :tab |
|---|---|---|---|---|---|---|
| 1 | agenda | Agenda | event | agenda.open | `glasspane-agenda-dock-badge` | t |
| 2 | projects | Projects | task_alt | projects.open | — | t |
| 3 | areas | Areas | category | areas.open | — | t |
| 4 | resources | Resources | topic | resources.open | — | t |
| 5 | review | Review | school | review.open | — (PA-OR-3) | t |
| 6 | archive | Archive | archive | archive.open | — | **nil** |

Deleted rows: tasks (→ projects + alias), journal (deleted), capture (FAB + M-x), search (row dies, §5.6), views (folds, §5.5). The hand dock item (glasspane.el:114-128) retires behind the flag; its agenda `:badge` moves onto the Agenda destination via GR-7b's threading. `'standalone` remains rejected for the build-within exemplar (it would withdraw the core drawer AND M-x).

**Gate:** arms: tab generation from the new table (5 tabs, order, badge, `:selected`); Archive absent from tabs, present in the drawer nest; registry-FAB injection (the GR-7b four arms re-run against the new table); deleted-row absence.

### PA-3b — Root swap (hard dep: S11 committed + deployed)

1. `glasspane.el:150`: `(jetpacs-chrome-define-root glasspane-owner "glasspane-agenda" #'glasspane-agenda-screen)` — the root id deliberately EQUALS the id `agenda.open` pushes, so the Agenda tab tap is a reset-to-root for free via same-id truncate-and-replace (jetpacs-chrome.el's stack-insert). `glasspane-ui-home-screen` unreferenced (flag-gated corpse until PA-4). `glasspane.home` unchanged in name and shape; it now resets to the Agenda root.
2. **The Saved page** (§5.5) joins the agenda pages.
3. **Boot seed** (PA-1's ROUTE form) lands in the tablet harness init.
4. **Route hooks:** `glasspane-ui-open-destination` (GR-8c helper, survives verbatim: reset+push peer semantics) also calls `jetpacs-apps-note-route`; **the ratified back-repush hook** on `jetpacs-shell-view-change-functions` (the journal on-view-change precedent — that hook itself dies): map screen ids → route keys ("glasspane-agenda"→agenda, "glasspane-projects"→projects, areas/area-*→areas, resources→resources, archive→archive, "glasspane-review"→review, view-*→agenda; detail/search/drill-* → no change), note the route, `jetpacs-shell--schedule-repush` ONLY when the route changed (one bounded repush per route-changing back; T-5 watches).
5. Journal's landing hook + `glasspane-journal-landing` defcustom + its Settings row die behind the flag — the Agenda root IS the landing.

**Gate:** arms: root-id-equals-agenda-push (tab tap truncates to root, never stacks); reset semantics (destination B removes destination A; drill preserved only within a destination); route honesty (verb-reached destination → its tab `:selected`; back → origin re-selected after the repush; boot-seed arm); `glasspane.home` resets to the Agenda root.

### PA-3c — Destination screens wired + slot/token audit

Wire the PA-2 screens to the flipped table; run the GR-8c-analog audit with the PARA rows: `area.open` peer-replace in the destination slot; the search-drill eviction chain (§5.6); detail constant-id re-entry; the Resources non-org handoff jump; journal keep-day row deleted from the audit (dies with Journal). **Token budget re-verified:** live `"glasspane"` sets ≈ 23-25 today; the delta is +1 ("areas" + twin) − 1 (`journal-carried` dies) — headroom vs `ebp-org-token-sets-max` 32/owner stays ≥ 6; T-4 stays armed. mark-pos adoption rows (agenda-item jumps, notes backlinks, detail "Open in file") carry over from GR-8c unchanged.

**Gate:** the audit checklist recorded in the rung notes with per-family resolutions (the GR-8c artifact rule); token-count arm.

### PA-3d — Drawer handover + top-bar Search + aliases

1. **Glasspane authors NO drawer** (stronger than GR-8b's shrunk drawer): `glasspane-ui--home-drawer` + `--drawer-app-rows` retire behind the flag; the S8 host drawer composes on the Agenda root — Apps row; the Glasspane nest (ALL 6 rows incl. **Archive** — its primary affordance) + other apps' nests; **the relocated Eval + Files rows** (PA-1's rule); the host tail (Tools nest, divider, Settings nest). The "fewer than three destinations: no drawer" clause governs *authored* app drawers — Glasspane authors none. M-x parity holds row by row.
2. **Top-bar Search** (§5.6): shared helper `glasspane-ui--top-actions` returning the search `icon_button` (`search.open`), passed as `:actions` by the destination screen builders. NOT the S10 global-items seam (shell-scope; the placement defcustom could re-author it into a FAB). Not on the search screen itself; not on detail.
3. **Aliases live:** `tasks.open` → projects; `views.hub` → Agenda Saved page; `journal.capture` → the headless datetree-append deprecation handler. Journal/views destination rows out (behind the flag).
4. **PA-OR-4 venue:** rule ef/gallery here or leave app-side; the rework's residual `:any-surface` audit rides along either way.

**Gate:** arms: composed-drawer contents on the root (nest + relocated rows + tail, exactly once each); no authored `:drawer` anywhere in glasspane; search icon present on destination screens, absent on search/detail; the three aliases answer `accepted` and land correctly; journal-alias queue arm (an injected queued `journal.capture` replays into the datetree).

### PA-3 gate — the big device batch + soak

Tablet, PORTRAIT, force-stop before every smoke, screenshot before every tap (I-7): boot-state arm (force-stop → relaunch → 5 tabs on the Agenda root, Agenda selected, NO prior navigation — the seed, not the app-grid detour); 5 tabs on BOTH form factors (bar compact / rail medium+); tab-hop across all five; **system back from each destination → Agenda with Agenda re-selected after the repush; system back at the Agenda root → Activity finishes; relaunch resumes (the S11/I-14 arms)**; Agenda badge; drawer: Archive row opens the browser, Eval row reaches the REPL, Files row reaches Files — and their surfaces wear Glasspane's tabs (the recorded §5.2 acceptance arm); Areas renders live categories from the real vault → drill → detail → back chain; Resources org drill offline + non-org handoff + back; Review SRS + stale + Habits link tap; search icon → screen → `search.by-tag` chip round trip ending Search-visible with the origin tab still selected; FAB = capture on destinations, absent on the guest settings satellite; M-x on every tab; stale-route fallback lands on the Agenda root (re-verify `app.open`'s fallback-home under no-hub); journal-alias replay arm on hardware. **Then ONE full daily-driver soak day on the new IA before PA-4.**

### PA-4 — Demolition + exit checklist (deletions cite their soaks)

1. Delete the flag-gated corpses, each commit citing the soak: **`glasspane-journal.el`** (after the queue-drain check: confirm the offline queue empty — or replayed to empty — of `journal.capture` receipts before deleting the alias, the rework §5.2-step-2 pattern; the alias itself survives ≥ one release per §0.11 — its deletion may fall to a later ladder and this rung records that); the hub corpse (`glasspane-ui-home-screen`, `--home-body`, `--home-drawer`, `--drawer-app-rows`, `--capture-fab`); the views-hub screen; the `glasspane-tasks` registration remnants; the journal landing defcustom + Settings row; `glasspane-ui-legacy-ia` and now-constant flags.
2. Grep gates in the suite: zero references to any deleted symbol; `test/run-tests.sh` explicit list re-verified.
3. **Exit device checklist (one consolidated day):** the GR-9 list re-targeted — single-alarm arm, reboot-rearm, capture e2e, chronometer (if GR-5 ran), PARA IA spot-checks, org-crypt pull-and-verify, desync re-run, back-contract spot-check (I-14). All green ⇒ `git tag para-closed`; stamps applied (§10); memory updated.

### PA-5 — Upstreaming tail

= the rework's GR-10, re-hosted pointer, content unchanged (table/babel move, per-heading affordances, mutation verb family, cross-file search, demo seeder split, vulpea extractor non-rename). Executes after PA-4; each item decision-gated as written there.

## §5 The IA target (first-class design; PA-3 implements it)

### §5.1 The full-bar primary pole
`:chrome 'primary` + `:dock-core nil` (v4-ratified form): core contributes zero dock items while the app is current; the app's ≤5 `:tab`-eligible destinations fill the bar; the suppressed core items relocate to the composed drawer. Daily driver (never loads Glasspane): the build-within default branch renders Eval/Files everywhere, bytes unchanged.

### §5.2 Foreign surfaces (recorded acceptance, extended)
The primary branch keys on the current app with no surface check — while Glasspane is current, the Files and hub surfaces wear Glasspane's 5 tabs and no Eval/Files items, even standing on the Eval REPL itself. Escape hatches: every root drawer carries the relocated Eval/Files rows + the Apps row + all destination nests; S11 system back; the 5 tabs themselves. This EXTENDS the GR-8b acceptance (org-mode's dock item already suppressed while Glasspane is current); the recorded follow-up "surface check in the primary branch" (rework §10) stays the escape hatch if it sours. The tablet is Glasspane's device — the rationale, verbatim.

### §5.3 Three tiers (max-screens 3, exactly)
- **Tier 0 — pinned root: the Agenda screen.** Day/week/month + ≤8 custom-agenda pages + the Saved page; page switches are device-local tab swipes, zero slot cost.
- **Tier 1 — destination slot:** exactly one of projects / areas-list / area-NAME / resources / archive / review / view-NAME / search-drill. Opens ride `glasspane-ui-open-destination` (reset+push peer semantics — switching destinations abandons the drill); `area.open` and `views.open` replacing their list screens in this slot is the ratified peer pattern.
- **Tier 2 — drill slot:** `glasspane-detail` (constant id; re-entry truncates, never evicts).
- Recorded audit row: detail→search→detail re-push truncates to the existing detail entry, dropping search (existing stack semantics; acceptable).

### §5.4 Route honesty
`jetpacs-apps--current-route` is written by `app.open`, the boot seed, `glasspane-ui-open-destination` (via `jetpacs-apps-note-route`), and the ratified back-repush hook (§4 PA-3b step 4). The bar's `:selected` is therefore honest at boot, on tab taps, on verb-reached destinations, and after every route-changing back gesture — at the cost of one bounded repush per such back (T-5 armed).

### §5.5 The Saved page (the views fold)
The Agenda screen gains a "Saved" page listing BOTH registries: `glasspane-org-custom-agendas` entries (tap = switch to that agenda page) and `glasspane-saved-views` entries (tap = `views.open` → the per-view screen as a Tier-1 peer, back → Agenda root). `views.hub` aliases to Agenda-landing-on-Saved. The two-registry duplication is recorded, not merged (PA-OR-2).

### §5.6 Search
A top-bar search icon on Glasspane's destination screens pushes the existing search screen as a plain drill — back returns to the origin; no route change (the origin tab stays selected — honest: search is transient, not a place). The real `search_bar` node exists but the search screen is a query BUILDER (filter sections + chips + tokenized results), not a suggestion list — forcing the bar-expansion shape is a rewrite with no offline gain; recorded polish: swap the screen's text input for a docked `search_bar` in-screen later. Slot cost audited in §5.3.

### §5.7 Surface roles — no duplicate rows
Host drawer = canonical navigation (Apps + nests + relocated core + tail). Tabs = the PARA loop. Agenda root = the app's home AND its first destination. FAB = capture. Top bar = back/hamburger + Search + M-x + overflow. **The two Homes, re-reconciled:** the shell's home is the Eval REPL hub — reached through the drawer while Glasspane is primary; the APP's home is the Agenda root — one system back from any tier; `glasspane.home` is the explicit reset onto it. Three affordances, three jobs; none renamed to pretend otherwise.

## §6 File fates — the delta vs rework §8 (rows not named here are unchanged there)

| File | Fate |
|---|---|
| glasspane.el | root swap ("glasspane-agenda"); `:chrome 'primary :dock-core nil :fab`; table pass-through; new module wiring; hand dock item retires |
| glasspane-ui.el | hub + authored drawer + capture-FAB node die; keeps shared view state, at-ref funnel, dialogs, settings satellite + verbs, the rewritten table, `glasspane-ui-open-destination`, the back-repush hook, `--top-actions` |
| glasspane-agenda.el | becomes the root; gains the Saved page; loses the tasks body + `tasks.open`/`tasks.filter` registrations (→ glasspane-projects.el); badge re-consumed by the destination `:badge` |
| **glasspane-journal.el** | **DIES** (was "survives"): screens, nav verbs, landing hook + defcustom + Settings row; `journal.capture` → deprecation alias per §0.11; the day-render's subtree export survives via its OTHER consumer (glasspane-detail.el:907-914) |
| glasspane-views.el | views-hub screen dies; `views.open` + renderings survive as Tier-1 peers reached from the Saved page |
| glasspane-search.el | survives whole; destination row dies; reached via top-bar icon + tag chips + M-x |
| glasspane-srs.el | survives; combined empty state; Habits link; (badge deferred, PA-OR-3) |
| **NEW** glasspane-projects.el, glasspane-areas.el, glasspane-resources.el | §4 PA-2 |

## §7 Budgets

Token sets: net ≈ +1 −1 (add "areas"+twin; `journal-carried` dies) — headroom ≥ 6 vs 32/owner; T-4 armed. Push cadence: +1 bounded repush per route-changing back — T-5 armed. Screens: 3-tier fits `jetpacs-chrome-max-screens` 3 exactly (§5.3).

## §8 Tripwires (rework §9 carried whole; deltas)

T-1..T-4, T-6 verbatim. **T-5 re-pointed:** push-cadence growth from the back-repush hook or the Agenda-root cards (watch Companion logs during the PA-3 batch) → D-5 graduates and is funded before PA-4. **T-7 (new):** the Areas whole-scope category walk shows hardware cost (slow first paint on the real vault) → halt, memoise/derive from the GR-3 consolidated walk before proceeding.

## §9 What this plan deliberately does not do

- Build "on this day last year" (noted future: a memoised Review section walking the journal datetree for today−1y + an inactive-timestamp scan over the agenda scope; date-keyed memo; no new machinery) or habits/metrics aggregation (noted future: streaks are already parsed in the habits walk; org-srs stats + org-clock totals as memoised Review cards; in-screen only — the widget/tile track stays under the D-19 STOP).
- Grow a query-grammar `category` term (PA-OR-1), merge the two saved registries (PA-OR-2), or badge the Review tab (PA-OR-3).
- Build unarchive, cross-archive search, or archive-side mutation verbs; honor `#+ARCHIVE` keywords or `::* heading` archive targets (v1 corpus = sibling `_archive` files only; all recorded).
- Adopt `org-agenda-custom-commands` / org-ql / composite agendas.
- Add the primary-branch surface check (§5.2's escape hatch — recorded follow-up if the foreign-surface trade sours).
- Everything in rework §10 except the overridden `journal.capture` row (§0.11).

## §10 Cross-reference stamps (apply on each doc's next edit; this plan does not modify them)

**For `docs/PLAN-glasspane-rework.md`:**

> **PARA supersession (2026-08-15): docs/PLAN-glasspane-para.md replaces this plan's IA half (ladder PA-0..PA-5).** Caleb ratified the PARA IA: 5 tabs Agenda/Projects/Areas/Resources/Review, no shell Home row; Agenda is home — no hub; Journal deleted; Search → top app bar; drawer = Eval + Files + Archive + Settings; capture FAB unchanged. Superseded: §7 whole, GR-8 whole, OR-5 (resolved by the ratified tab list), GR-9's demolition list (PA-4 carries the successor, adding journal + hub + the search destination row), §8's ui/agenda/journal/views/search rows. Surviving unchanged: GR-0..GR-7, §5 ceremonies, I-1..I-8 (I-6 re-points to PARA §5.3), §9 (T-5 re-points to the back-repush hook + Agenda-root cards). §3 amendments: `tasks.open` retargets to the PARA Projects destination; `glasspane.home` resets to the Agenda root. **Overridden non-move:** `journal.capture`'s "stays permanently" (GR-4 step 6, §10) — a queued-durable verb (ttl 86400) that winds down through PA's deprecation alias + queue-drain ceremony, never a bare deletion. GR-10 executes after PA-4 as PA-5. Stale forward references (GR-3's "GR-8b dashboard" consumer, GR-7b's "at GR-8a" phrases, GR-2's journal parenthetical, §12's GR-8 rows) read through this stamp.

**For `docs/PLAN-jetpacs-debt-and-scaffold.md`:**

> **PARA restructure (2026-08-15): docs/PLAN-glasspane-para.md supersedes GR-8** — S8's "until GR-8b shrinks it" and the GR-8b host-drawer directive resolve to PA-3d; S11 is a hard precondition for PA-3b's back arms; S10 interacts (top-bar budget) but is not a dependency. GR-7b remains the :badge/FAB funding rung, unchanged. CHROME-VOCABULARY v4 (2026-08-15) ratified the S8 root-only drawer-injection sentence this ledger's S8 entry left pending.

**For `docs/PLAN-glasspane-app.md`** (optional, low priority): at the #26 hub entry — the ONE-TABLE gate tests survive the hub's death renamed to the root-reaches-every-opener form (PARA I-9).

## §11 Coverage cross-checks (auditable from this doc alone)

**Ratified inputs → where honored:** §0.1→PA-1/PA-3a · §0.2→PA-3b/§5.3 · §0.3→PA-2d · §0.4→PA-2a · §0.5→PA-2c · §0.6→PA-2e/§9 · §0.7→PA-3d/§5.6 · §0.8→§2/§10 · §0.9→PA-0/PA-1 · §0.10→PA-3b/§5.4 · §0.11→§3/PA-4.
**New surfaces → suite arms:** every PA-2 rung names its arms; the one suite is wired at PA-1 (I-12).
**Dying/moved verbs → I-13 rows:** all in §3; the only durable carrier (`journal.capture`) has its ceremony (PA-4).
**Invariants → enforcement:** I-9→PA-3a gate + the renamed inventory tests · I-10→PA-3a/PA-3 batch · I-11→PA-3d gate · I-12→PA-1 · I-13→§3 · I-14→PA-3 batch (S11 arms).
