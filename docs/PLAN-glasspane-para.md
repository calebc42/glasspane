# PLAN — Glasspane PARA: the fresh IA (Agenda-rooted, shared-bar, PARA-shaped)

Repo: `/home/calebc42/pkb/projects/jetpacs/jetpacs/llm-poc-3` @ **29b0297** (PA-2e execution base on slop-fork/main; PA-1/PA-2a/PA-2b/PA-2c/PA-2d complete). Written **2026-08-15**, navigation amended and PA-1/PA-2a/PA-2b/PA-2c/PA-2d/PA-2e executed **2026-08-16**. Original line cites were verified at 8965e40; PA-2e mechanisms and gates were re-verified at the execution base. PA-3b's S11 dependency is satisfied at the commit level; the APK deploy remains its device-side precondition.

**Authority:** the ratified PARA vision (Caleb, 2026-08-15 — §0 verbatim) + the surviving machinery half of `docs/PLAN-glasspane-rework.md` (GR-0..GR-7, unchanged). Produced by a full planning workflow (3 exploration + 3 design agents, 2026-08-15); every mechanism claim was re-verified in-tree while drafting.

**Companion docs:** `docs/PLAN-glasspane-rework.md` — **this plan supersedes its §7 + GR-8 and re-scopes GR-9/GR-10**; that doc is NOT edited here; §10 carries the stamp for its next edit. `docs/PLAN-jetpacs-debt-and-scaffold.md` — §10 carries its stamp. `docs/CHROME-VOCABULARY.md` — **v4 ratified 2026-08-15 alongside this plan** (the full-bar clause + the S8 root-only drawer-injection sentence; edited in its own commit, not in passing).

**Ladder prefix is PA- (PARA)** — fresh per the D-6 label-collision rule (GR-, G0–G9, R2/R4/R6 taken; grep `\b(PA|GP)-[0-9]` at this tree = zero prior hits). A session resuming "PA-2c" from this doc alone cannot land on another ledger.

> **AUTHORITATIVE NAVIGATION CORRECTION — Caleb, 2026-08-16.**
> The persistent NavBar/BottomAppBar has exactly five peer destinations:
> **Agenda, Projects, Areas, Resources, Review**.  They are destinations, not
> tabs.  Agenda alone contains the POC-1-style **Day / Week / Month** content
> tabs.  Projects succeeds the POC-1 Tasks screen.  Resources wraps and
> subsumes the Files explorer, so there is no separate Files bar or drawer
> entry while Glasspane owns the primary bar.
>
> The NavDrawer carries **Archive, Eval, and Apps/the app switcher**, followed
> by the surviving host Tools/Settings content.  Archive is a drawer-only
> Glasspane destination.  Eval is a selectively relocated Jetpacs core
> destination.  Apps is drawer-only everywhere; it never consumes a bar slot.
>
> GR-0..GR-7 and the PARA data/screen/verb decisions remain valid.  PA-1 and
> PA-3 below are rewritten around this exact map: Jetpacs supplies generic
> primary-bar, selective-core-relocation, and drawer-only-destination seams;
> Glasspane alone declares the PARA choices.  Jetpacs has no Glasspane
> knowledge.

Full ERT gate everywhere below = `test/run-tests.sh` — **the runner is an EXPLICIT list; a suite not named there never runs (the K1a merge lesson). This whole ladder adds ONE suite, `test/glasspane-para-test.el`, wired into the list in the same commit as the first app-specific rung, PA-2a; every later rung only adds arms to it. PA-1's generic foundation arms live in the already-wired app/home suites.**

---

## §0 Ratified inputs (Caleb, 2026-08-15 — decisions, not options)

1. **The bar is exactly five persistent destinations: Agenda, Projects, Areas, Resources, Review.** No shell Home, Eval, Files, or Apps row. The generic core-suppression and selective-relocation mechanism (§5.1) is sanctioned.
2. **Agenda is home — no hub.** The hub dashboard dies whole. Agenda = Day/Week/Month content tabs + custom-agenda pages + one new "Saved" page (the views fold, §5.5). System back at the Agenda root exits the app (Android-normal for a navigation root).
3. **Projects = anything with a TODO stage.** v1 = the todo walk grouped **by file** with the existing TODO-keyword filter chips as the second axis; heading-level project-entity grouping is the recorded follow-up, not v1.
4. **Areas = org categories.** New backend (nothing exists at HEAD — `org-get-category` is never called and the query grammar has no category term).
5. **Resources = the Glasspane-named entry into Jetpacs' native Files explorer, rooted at the vault.** It replaces the separate Files navigation entry while Glasspane is primary, but it does not reimplement a file browser. `resources.open` passes `org-directory` to the public `jetpacs-files-open-path` on the canonical Files surface; Jetpacs continues to own listing, search, creation, file operations, editing, and reader-adapter selection for both Org and non-Org files. Glasspane owns only the PARA label, placement, starting scope, and selected route.
6. **Review v1 = SRS flashcards + stale vulpea files**, plus the cheap Habits LINK row to the existing `jetpacs.org` habits surface. "On this day last year" and habits/metrics aggregation are **noted future work only** (§9).
7. **Drawer:** Archive (drawer-only destination), Eval (the only selectively relocated core destination, §5.1), the Apps/app-switcher row, and the host Tools/Settings nests. Files is not duplicated here because Resources subsumes it. **Journal is deleted. Search moves to the top app bar.** Capture stays the FAB dialog (never a place).
8. **PARA replaces GR-8's IA.** GR-0..GR-7 survive unchanged and remain prerequisites where named; this plan supersedes the rework's §7 + GR-8 and re-scopes GR-9/GR-10 (§2). The rework's OR-5 is resolved by supersession.
9. **CHROME-VOCABULARY v4** (amended by the 2026-08-16 correction): APP-PRIMARY may let an app fill the M3 3–5 budget whole. The app explicitly selects any suppressed core destinations that relocate to the drawer and accounts for the others through an app destination that subsumes them. Glasspane relocates Eval and replaces Files with Resources. The S8 root-only drawer-injection rule remains unchanged.
10. **Back-gesture route honesty: repush on route change** — one bounded repush per route-changing companion-local back (§5.4); T-5 re-armed over it.
11. `journal.capture` winds down through a **deprecation alias + queue-drain ceremony** (§4 PA-4), never a bare delete — it is a durable queued verb (`:when-offline "queue"`, ttl 86400, glasspane-journal.el:75,178-181).

**PROPOSED, NOT RATIFIED — open rulings for Caleb (executing a rung that touches one requires the ruling first):**

- **PA-OR-1** Areas upgrade path: v1 honors org's three category layers app-side (keyword / inherited `:CATEGORY:` property via `org-get-category` / basename fallback) with **no** query-grammar `category` term. Growing the grammar later is a five-touch-point foundation change (matcher, point-get, wire allowlist, vetter, note-terms kept OFF so vulpea routing degrades correctly). Rule only if saved views/search want area filters.
- **PA-OR-2** Registry merge: `glasspane-org-custom-agendas` (page-shaped) ⇄ `glasspane-saved-views` (rendering-shaped) stay two registries, both presented on the Agenda "Saved" page. A merge is a data-model migration — recorded, deferred.
- **PA-OR-3** Review destination badge (due count via `glasspane-srs--due-count`): **deferred** — the Agenda badge owns the bar's one number first. Revisit after the PA-3 soak.
- **PA-OR-4** ef + gallery re-homing: the rework's OR-2 content unchanged; its decision venue ("the IA restructure decides") is now THIS plan — rule at PA-3d or leave both app-side and green.

## §1 Hard invariants (violating any is a plan defect)

**I-1..I-8 are inherited verbatim from PLAN-glasspane-rework.md §1** (durable verb names; reminder cutover ordering; duplicate-alarm mitigation; org-crypt; D1 surface scoping; slot budget; device-smoke-before-rebase; wants∩supported) — I-6's pointer to "§7's three-tier model" now reads through this plan's §5.3.

- **I-9 ONE-TABLE (#26).** Bar entries, the host-drawer destination nest, and every route deep-link derive from the ONE destination table (glasspane-ui.el:149). Agenda's Day/Week/Month tabs are its screen-local page model, not rows in that table. The hub's verb-inventory gate tests survive the hub's death renamed to a root-reaches-every-opener form — a destination can never be reachable in one surface and missing from another unless it is explicitly marked drawer-only.
- **I-10 The M3 bar contract.** Three to five destinations, places never actions, `:selected` always indicated, the bar persists on every screen (a bar that vanishes on drill is a defect). Search's top-bar seat is the ratified exception to place-shaped-things-go-in-the-bar: it is screen-scope ACTION chrome, not a destination.
- **I-11 M-x parity.** Every new affordance (bar entries, Agenda tabs, drawer rows, top-bar search, Habits link) projects a command reachable without it.
- **I-12 K1a.** `test/run-tests.sh` is an explicit list; this ladder's one new suite is wired at PA-2a in the same commit that creates it. PA-1 extends already-wired foundation suites.
- **I-13 Durable-carrier discipline for dying/moved verbs.** Before any verb registration is deleted or retargeted, its durable carriers are enumerated and a wind-down named (`journal.capture` is the template, §3). A vanished durable verb turns queued replays into permanent `rejected` deletions.
- **I-14 The back contract.** Exactly ONE Glasspane screen — the Agenda root — yields system back to the Activity; every other screen's gesture pops (S11 dispatches the screen's own authored back descriptor). A second back-less Glasspane screen is a defect.

## §2 Relationship to the rework plan (the supersede map)

**SUPERSEDED by this plan:** rework §7 whole (7.1 fate table, 7.2 three-tier as written — the *mechanism* survives re-parameterized in §5.3, 7.3 surface roles incl. "The two Homes"); GR-8a/b/c/d as written (surviving mechanisms are re-hosted in §4/§5); the GR-8 gate; OR-5 (resolved: the ratified destination list is §0.1); GR-9's demolition list (PA-4 carries the successor); rework §8 rows for glasspane-ui / glasspane-agenda / glasspane-journal (flips survives→dies) / glasspane-views / glasspane-search.

**SURVIVES UNTOUCHED:** GR-0..GR-7 whole, in order — they remain the machinery floor this plan stands on (GR-7b's `:badge` threading and `:fab` registry are hard dependencies of PA-3a; GR-2's reader adapter is the soft dependency of PA-2b/2c; GR-3's consolidated extractor is the substrate of PA-2a/2d). Rework §2 ordering argument, §3 verb-contract structure, §5 ceremonies, §6, I-1..I-8, §9 tripwires, §10 (minus the overridden row below).

**AMENDED (one-line stamps on the rework doc's next edit — §10 here carries them):** GR-3 step 3's consumer list ("the GR-8b dashboard" dies; consumers = agenda cards + the Agenda destination badge + reminders); GR-7b's "at GR-8a" phrases → PA-3a; GR-2 step 7's "(journal's day render)" parenthetical → the surviving `glasspane-org-reader-subtree` consumer is glasspane-detail.el:907-914; **the `journal.capture` "stays permanently" non-move (GR-4 step 6, rework §10) is OVERRIDDEN by §0.11**; §3 rows for `tasks.open` (retargets to Projects, not an Agenda page) and `glasspane.home` (resets to the Agenda root, not the hub).

## §3 Verb inventory — the PARA delta (rework §3 discipline; every row I-13-checked)

| Verb | Fate | Durable carrier | Call |
|---|---|---|---|
| `projects.open` `areas.open` `areas.drill` `resources.open` `resources.open-file` `archive.open` `review.habits.open` | NEW, owner-scoped, M-x parity | — | `resources.open`/`.open-file` are thin downstream delegates to the public Files seam; grep-verified no collisions (`jetpacs.org.archive` at jetpacs-org-dialogs.el is the unrelated heading action; coexists) |
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
| PA-1 | Foundation navigation composition: full primary bar + selective core relocation + `:bar` eligibility + drawer-only Apps | GR-7b | S | no | no |
| PA-2a | Areas backend + screens (`glasspane-areas.el`) | GR-3 | M | no | no |
| PA-2b | Archive index + drawer-only screen | PA-2c; soft GR-2 | S | no | no |
| PA-2c | Resources wrapper over native Jetpacs Files (`glasspane-resources.el`) | Jetpacs Files; soft GR-2 | S | no | no |
| PA-2d | Projects module (`glasspane-projects.el`, tasks body promoted) | GR-3 preferred | S | no | no |
| PA-2e | Review destination (combined empty state + Habits link + session arm) | — | S | no | no |
| PA-3a | Pole + ONE-TABLE flip: full app bar, selective Eval relocation, the 6-row table, badges, hand dock item retires | PA-1, PA-2* | M | rides batch | yes |
| PA-3b | Root swap: Agenda = pinned root; hub retires behind the flag; Saved page; boot seed; route hooks | PA-3a, **S11 deployed** | M | rides batch | YES |
| PA-3c | Destination screens wired + slot/token audit (GR-8c analog) | PA-2*, PA-3a | M | rides batch | yes |
| PA-3d | Drawer handover + top-bar Search + aliases + PA-OR-4 venue | PA-3b | M | rides batch | yes |
| — | **PA-3 gate: the big device batch + ONE daily-driver soak day** | all PA-3 | — | **YES** | — |
| PA-4 | Demolition + exit checklist (supersedes GR-9's list); `git tag para-closed` | PA-3 soak | M | YES (checklist) | no |
| PA-5 | Upstreaming tail = GR-10 re-hosted (content unchanged, executes after PA-4) | PA-4 + rulings | L | per item | no |

PA-2a..2e are ERT-only and parallelizable with GR-4..GR-7 (none touch reminders/capture/clock). The GR-8 soak-day slot transfers to PA-3.

### PA-0 — Governance (this commit)

This doc + the CHROME-VOCABULARY v4 edit landed as two `docs(...)` commits. **S10/S11 fate pinned:** both were in flight at drafting time and are now committed. **S11 (Companion BackHandler) is a hard precondition of PA-3b's device arms** — without its deployed APK the system gesture exits the Activity from anywhere, making the I-14 arms unrunnable; S10 (globals placement) is an interaction note only (M-x top-bar + Search = 2 icons, inside the top-bar contract; S10's FAB placements yield to the GR-7b capture FAB on Glasspane screens). The header is re-stamped with PA-1's GR-7b-complete execution base. `git tag para-baseline` belongs on the deployed tree+APK pair when device-side PARA execution starts.

### PA-1 — Foundation navigation composition (additive)

This rung is entirely Jetpacs-generic. It contains no Glasspane names or
PARA assumptions; Glasspane consumes the seams at PA-3.

1. **`jetpacs-defapp` gains `:dock-core` (default t) and `:drawer-core` (default nil).** `:dock-core nil` lets a current APP-PRIMARY app own the full M3 bar. `:drawer-core` is a list of stable core-item keys to relocate when core is suppressed. This is not a third `:chrome` pole: it is declarative composition within APP-PRIMARY.
2. **Core dock rows gain stable keys.** The host's Eval and Files items are keyed `"eval"` and `"files"`. Jetpacs can therefore relocate an app-selected subset without knowing why. Glasspane will later request only `("eval")`; its Resources destination accounts for Files.
3. **Destination plists gain optional `:bar` eligibility** (default t). `:bar nil` omits a destination before the M3 cap but retains it in the drawer nest and verb/deep-link table. The private generator is renamed from `jetpacs-apps--destination-tabs` to `jetpacs-apps--destination-bar-items` so foundation vocabulary no longer calls persistent destinations tabs.
4. **The primary bar honors full ownership.** With `:dock-core nil`, no core rows consume slots and up to five `:bar`-eligible app destinations fill the bar. With the default t, current behavior remains core plus the remaining app destinations up to five.
5. **Selective relocation is composed by the host drawer.** Only core rows named by the current primary app's `:drawer-core` become `jetpacs-chrome-row`s, between app destination nests and the host tail. Unknown keys are ignored safely. No Glasspane-authored drawer is required.
6. **Apps becomes drawer-only globally.** The default build-within branch no longer appends an Apps bottom-bar item when multiple apps are registered. The existing Apps drawer row remains the sole app-switcher affordance.
7. **`jetpacs-apps-seed-current` accepts optional ROUTE.** The tablet harness will call `(jetpacs-apps-seed-current "glasspane" "agenda")` at PA-3 — five destinations with Agenda selected before any `app.open`.
8. **Test ownership:** generic behavior lands in the already-explicit app/home suites. `test/glasspane-para-test.el` is created and wired when the first Glasspane-specific PARA behavior lands at PA-2a (I-12).

**Gate:** full ERT + new arms: option validation; primary+suppressed → five app bar entries and zero core; primary+default → core plus remaining app entries; `:bar nil` absent from the bar and present in the drawer nest; only selected core keys relocate; Eval-only relocation does not duplicate Files; Apps absent from every bottom bar and present in the drawer; seed-with-route selects Agenda without prior `app.open`; daily-driver default still renders Eval/Files.

> **PA-1 GATE COMPLETE 2026-08-16.** Jetpacs now exposes only generic
> composition metadata: `:dock-core`, `:drawer-core`, and destination `:bar`.
> Core rows have stable app-agnostic keys; the renamed bar generator filters
> drawer-only destinations before the five-item cap; READY-time route seeding
> changes selection without navigation. Apps is drawer-only in zero-, one-,
> and multi-app composition. No foundation source names Glasspane or PARA.
>
> The full-primary arm renders exactly five app entries, Archive only in the
> destination nest, Eval exactly once in the drawer, and Files zero times when
> only Eval is selected for relocation. The default pole still renders native
> Eval/Files. Verification: app registry **22/22**, host home **3/3**, and M3
> catalog **38/38**; warning-as-error compilation, foundation-layering grep,
> package install, diff check, and the full elevated `test/run-tests.sh` all
> pass; the full runner exited **0**. This foundation-only rung changes no
> Glasspane declaration and has no device arm.

### PA-2a — Areas (`emacs/apps/glasspane/glasspane-areas.el`, new)

App-side module (srs/notes shape, register/unregister from glasspane.el's sweep) — NOT glasspane-org.el (GR-3 moves generic extraction to org-mode; category-as-IA is a Glasspane opinion; recorded non-move keeps it out of GR-3's blast radius).

1. **Extractor** `glasspane-areas--index`, memoised `(ebp-org-with-cache 'glasspane '(areas-index) …)`: over the public `glasspane-org-agenda-scope` alias to Jetpacs' canonical local scope (never a raw agenda-form call — P1-7), per file under `ebp-org--with-clamped-io` with per-file `condition-case`-skip (the habits-walk discipline, jetpacs-org-habits.el:93-122): file-level `#+CATEGORY` via `org-collect-keywords` else basename-sans-extension; `org-map-entries "TODO<>\"\""` collecting the standard item alist + `(category . (org-get-category))` so inherited `:CATEGORY:` properties create their own buckets. **30.1 hazard:** stock `org-element.elc` mis-compiles the category cache-miss arm — apply the in-tree workaround (prime `org-element-at-point` at the keyword line, the glasspane-detail.el:1805-1814 recipe); the per-file skip is the backstop. Deliberately the file arm even when vulpea is up (the note index carries explicit drawer props only — an index arm would silently re-bucket the vault; documented at the arm).
2. **Screens/verbs:** `areas.open` → list screen (name + open-TODO count + "N files", sorted); tap → `areas.drill :args (:category NAME)` — **plain string args, zero token sets for the list** (the `tasks.filter` precedent). `areas.drill` → Tier-1 peer screen (id `(jetpacs-wire-id "area" NAME)`; replacing the areas list in the destination slot is the views-open-replaces-views-hub precedent): section 1 = the category's TODO cards via the shared card builders + public `glasspane-agenda-tokenize` over set `"areas"` (mints the dialogs-owner twin too, keeping swipe-archive working); section 2 = the category's files, rows tapping `resources.open-file`, which delegates to the public Jetpacs Files host. Vanished category → empty state, never an error.
3. **Token budget:** +1 set ("areas") + its dialogs-owner twin — the ladder's whole net delta (§7).

**Gate:** arms: bucket layering (keyword / inherited property / basename); rotten-file skip; string-arg drill round trip; empty-category degrade; grep-pin the module never calls `org-agenda-files` (the habits suite's pin pattern); 30.1 CATEGORY workaround arm.

> **PA-2a GATE COMPLETE 2026-08-16.** The new app-side Areas module
> indexes all three native Org category layers, preserves file-only areas,
> counts only open TODO headings, skips malformed files locally, and memoises
> the canonical local agenda scope. List routes use plain category strings;
> drill cards use the public Agenda tokenizer, and file rows stage the public
> `resources.open-file` contract for PA-2c. Public scope/tokenizer aliases keep
> the implementation free of cross-module private calls. The staged
> `areas.open` destination is deliberately absent from the legacy hub until
> PA-3 performs the one-table navigation flip.
>
> Evidence: the explicit PARA suite is wired into the runner and passes
> **8/8**; the legacy Glasspane suite passes **72/72**; the shared reminder /
> scope suite passes **6/6**. The Emacs 30.1 category-cache arm, rotten-file
> isolation, memoisation, serialization, vanished-category token sweep,
> lifecycle, source-boundary, and layering pins all pass. Warning-as-error
> compilation, package installation, diff hygiene, and the full elevated
> `test/run-tests.sh` pass; the runner exited **0**. PA-2a has no device arm.

### PA-2b/2c — Resources + Archive (`emacs/apps/glasspane/glasspane-resources.el`, new; one wrapper action, one screen)

1. **Resources is delegation, not duplication.** `resources.open` resolves the canonical Files surface with `(jetpacs-shell-surface-for jetpacs-files-owner)` and calls `(jetpacs-files-open-path org-directory FILES-SURFACE)`. Direct path entries from Areas and Archive use `resources.open-file :args (:path P)`, whose entire accepted path is the same public call. No Glasspane code calls `jetpacs-files--body`/`--screen`, walks a Resources file tree, or reproduces Files rows/actions.
2. **Ownership boundary:** Glasspane chooses the PARA name, the `org-directory` landing directory, and the Resources route. Jetpacs validates against its effective Files roots and owns the canonical guest surface, dired-backed listing, bounded content search, create/rename/copy/move/delete, editor/reader hosts, and Org adapter. The surface switch is deliberate: embedding the private Files body on a Glasspane-owned surface would break D1 ownership for every `jetpacs.files.*` action. While the guest surface is visible, the APP-PRIMARY bar persists and Resources remains selected.
3. **Archive alone needs an opinionated index.** `glasspane-resources--archive-files` walks `org-directory` for `_archive\'` files, capped by a defcustom (~500, the `jetpacs-files-scan-cap` precedent), memoised `'glasspane '(archive-files)`, with one `file-attributes` call per file. The files sit outside the agenda cache stamp, so `jetpacs-shell-refresh-hook` invalidates that key; pull-to-refresh is the freshness story. `glasspane-org--file-list` stays as-is for its current consumer.
4. **Archive screen:** `archive.open` is drawer-only via `:bar nil`; rows show source name + mtime and tap `resources.open-file`, entering the same canonical Files host. The default `org-archive-location "%s_archive::"` puts archive files beside their sources and therefore inside `ebp-org--roots`/the configured Files roots.
5. **Archive recognition is native Org behavior and therefore a Jetpacs fix.** Widen the shared `jetpacs-reader-org-path-p` (and the legacy `jetpacs-org-render--org-path-p` compatibility predicate) from `.org` only to `\.org\(_archive\)?\'`. Glasspane's replacement adapter continues to consume the public predicate; it does not grow its own file-type rule.
6. **Leak audit (verified):** `_archive` files do NOT leak into agenda/Projects for directory-style config (`org-agenda-file-regexp` excludes them); the two remaining edges (an explicit agenda-files ENTRY naming an archive; a custom vulpea indexing archives) are covered by PA-2d's display filter.

**Gate:** arms: Resources delegates `org-directory` to the canonical Files surface; direct-file delegation for Org and non-Org paths; no private `jetpacs-files--*` calls; no Resources walker/screen; Files root refusal propagates as a rejected result; Resources stays selected on the guest surface; Archive cap + refresh invalidation; `_archive` inclusion; shared predicate widening in both native paths; roots-policy pass for an archive file; no-unarchive grep pin.

> **PA-2c GATE COMPLETE 2026-08-16 (Resources half; PA-2b completed
> below).** `glasspane-resources.el` is a downstream-only adapter:
> `resources.open` hands `org-directory` to the public Files opener and
> `resources.open-file` hands it the supplied path, both on the canonical
> `jetpacs.files` surface. It creates no screen, walks no files, and calls no
> private Files symbol. Native Files root refusal returns `rejected`
> unchanged. The existing `app.open` route state keeps Resources selected
> after the guest-surface handoff. Both verbs are lifecycle-owned by
> Glasspane; the destination opener stays explicitly staged until PA-3.
>
> Evidence: five PA-2c arms extend the explicit PARA suite from **8/8** to
> **13/13**, covering vault/Org/non-Org delegation, real Files-root refusal,
> guest-surface selection, lifecycle/schema/staging, and source-boundary
> pins. The legacy Glasspane suite remains **72/72**. Warning-as-error
> compilation, package installation, EBP/Jetpacs/Glasspane layering, shell
> and diff hygiene, and the full elevated `test/run-tests.sh` pass; the
> runner exited **0**. PA-2c has no device arm.

> **PA-2b GATE COMPLETE 2026-08-16 (Archive half; combined PA-2b/2c
> rung complete).** The downstream Archive index performs a bounded local
> walk of `org-directory`, does not follow symlinked directories, isolates an
> unreadable directory, and records one explicit mtime read per matching
> `_archive` file. Its result is memoised under the Glasspane EBP cache key;
> the module-owned shell refresh hook invalidates membership independently of
> the agenda stamp. The staged Archive screen shows source names and mtimes,
> and every row delegates its path to `resources.open-file` on native Files.
> `archive.open` is lifecycle-owned but remains absent from the legacy hub
> until PA-3 installs it as a drawer-only destination.
>
> Jetpacs now recognizes `.org_archive` (case-insensitively) through both the
> shared reader predicate and its legacy rendering compatibility predicate;
> Glasspane adds no private file-type rule. Real EBP and Files root policies
> accept a sibling archive under the vault, and a source pin confirms this
> rung introduces no unarchive operation. Evidence: the explicit PARA suite
> passes **18/18**, the native mode/app suite **18/18**, the native rendering
> suite **39/39**, and the legacy Glasspane suite remains **72/72**.
> Warning-as-error compilation, package installation, dependency layering,
> diff hygiene, and the full elevated `test/run-tests.sh` pass; the runner
> exited **0**. PA-2b has no device arm.

### PA-2d — Projects (`emacs/apps/glasspane/glasspane-projects.el`, new, thin)

The tasks body promoted honestly: keyword chips + shared cards over `glasspane-org-todo-items` (both arms intact — vulpea whole-vault when the index is up, else the agenda-scope map), **grouped by file** (`seq-group-by` + basename section headers — a pure fold; items already carry `file` in both arms; ratified §0.3). `tasks.filter` moves with the body, name unchanged; `tasks.open` becomes the alias (§3). Token set: reuses `"tasks"` — net zero. **Archive display filter:** drop items whose `file` matches `_archive\'` (the leak-edge insurance). Recorded follow-ups, not v1: project-entity grouping (nest under level-1 headings — pure fold, items carry `level`+`pos`); group-by-category (reuse the Areas index).

**Gate:** arms: alias; group-by-file fold over both arms' item shapes; archive display filter; chips-filter regression.

> **PA-2d GATE COMPLETE 2026-08-16.** The Tasks body, filter state,
> handlers, and lifecycle ownership now live whole in the new downstream
> Projects module. Its extractor retains both public TODO-item arms: the
> Vulpea whole-vault index when available and the agenda-scope fallback.
> Items are grouped by their full file path, groups are ordered
> deterministically by path, basename headers label each section, and the
> existing shared Agenda cards preserve item order within a file.
>
> Explicit-scope and custom-index archive leaks are both stopped before
> token minting by a case-insensitive `_archive` file filter. The native TODO
> keyword chips and `tasks.filter` contract are unchanged, and the existing
> `"tasks"` token set is reused for a net-zero token-set delta.
> `projects.open` is staged for the PA-3 one-table flip; `tasks.open` is a
> durable deprecated alias registered to the exact same handler. The legacy
> hub therefore continues to reach Projects through `tasks.open` without
> exposing the new destination early.
>
> Evidence: the explicit PARA suite passes **23/23** and the legacy
> Glasspane suite passes **72/72**. Both extractor arms, pre-token archive
> exclusion, grouping, chips, alias identity, lifecycle, staging, and source
> boundaries are pinned. Warning-as-error compilation, package
> installation, dependency layering, diff hygiene, and the full elevated
> `test/run-tests.sh` pass; the runner exited **0**. PA-2d has no device arm.

### PA-2e — Review destination (edit `glasspane-srs.el`)

1. **Never-dead guarantee:** org-srs absent → the existing install body already renders a live installer (keep exactly). vulpea absent → stale half absent (keep, while the other half lives). **Both absent** → ONE combined empty state ("Review needs engines — org-srs for flashcards, vulpea for stale notes", install button when available) + the Habits row — the destination is live and useful in every configuration. This answers the rework's dead-destination objection now that §0.1 ratifies Review as the fifth persistent entry.
2. **Habits link row** (ratified): rendered when `(featurep 'jetpacs-org-habits)`; new verb `review.habits.open` guards `fboundp` and calls the habits push (`jetpacs-org-habits`'s own entry to the `jetpacs.org` surface) — outgoing elisp push, D1-clean; surface-switch cost recorded (same class as the Resources handoff).
3. Session-vs-destination state: unchanged (session defvars + the screen's session/idle body switch); one new arm pins navigation-away-and-back resumes.

**Gate:** arms: both-absent combined empty state; habits-row gating; session-resume-across-destination-hop.

> **PA-2e GATE COMPLETE 2026-08-16.** Review now stays useful across
> every engine combination. With org-srs alone it keeps the due/session
> half; with Vulpea alone it keeps the existing org-srs installer beside
> stale files; with both it keeps both sections. When neither engine is
> available, those dead halves collapse to one combined “Review needs
> engines” empty state whose install action appears only while the package
> verb is live.
>
> The Habits link is a downstream Glasspane placement opinion over the
> public native `jetpacs-org-habits` entrypoint. Its row appears only when
> that Jetpacs feature is loaded; `review.habits.open` guards the function,
> defers the outgoing native-surface push, and is owned by the SRS module's
> existing register/unregister sweep. Glasspane loads no Habits module and
> duplicates none of its collection, graph, mutation, or surface logic.
> Active session state remains separate from destination navigation: a
> Review → Projects → Review hop resumes the same card, reveal flag, and
> undo stack.
>
> Evidence: the explicit PARA suite passes **26/26** and the legacy
> Glasspane suite passes **72/72**. Combined-empty capability gating,
> Habits feature/function gating and public handoff, lifecycle inventory,
> and session resumption are pinned. Warning-as-error compilation, clean
> package installation, dependency layering, icon lint, diff hygiene, and
> the full elevated `test/run-tests.sh` pass; the runner exited **0**.
> PA-2e changes only downstream Glasspane Elisp and has no device arm.

### PA-3a — Pole + ONE-TABLE flip

`glasspane`'s defapp gains `:chrome 'primary :dock-core nil :drawer-core '("eval") :fab <capture descriptor>` (the GR-7b registry plus PA-1 composition seams; the per-screen hand-authored FAB node retires). **The table** (glasspane-ui.el:149 rewritten; I-9):

| # | :key | :label | :icon | :verb | :badge | :bar |
|---|---|---|---|---|---|---|
| 1 | agenda | Agenda | event | agenda.open | `glasspane-agenda-dock-badge` | t |
| 2 | projects | Projects | task_alt | projects.open | — | t |
| 3 | areas | Areas | category | areas.open | — | t |
| 4 | resources | Resources | topic | resources.open | — | t |
| 5 | review | Review | school | review.open | — (PA-OR-3) | t |
| 6 | archive | Archive | archive | archive.open | — | **nil** |

Deleted rows: tasks (→ projects + alias), journal (deleted), capture (FAB + M-x), search (row dies, §5.6), views (folds, §5.5). The hand dock item (glasspane.el:114-128) retires behind the flag; its agenda `:badge` moves onto the Agenda destination via GR-7b's threading. `'standalone` remains rejected for the build-within exemplar (it would withdraw the core drawer AND M-x).

**Gate:** arms: bar generation from the new table (five entries, order, badge, `:selected`); Archive absent from the bar, present in the drawer nest; Eval relocated exactly once; Files absent because Resources replaces it; registry-FAB injection (the GR-7b four arms re-run against the new table); deleted-row absence.

> **PA-3a GATE COMPLETE 2026-08-16.** Glasspane now declares the
> APP-PRIMARY pole with a full five-slot bar, suppresses native core bar
> entries, selectively relocates only Eval, and contributes Capture through
> Jetpacs' typed app-FAB registry. The per-screen FAB slots are absent in the
> new composition; their historical authored nodes, the hand dock item, and
> the old destination table remain reachable only through
> `glasspane-ui-legacy-ia` plus re-registration for the PA-3 soak rollback.
>
> The authoritative table is exactly Agenda, Projects, Areas, Resources,
> Review, then Archive. The first five are bar-eligible in that order;
> Archive is drawer/deep-link-only. Agenda carries the live count as the
> string-valued destination badge. Tasks, Journal, Capture, Search, and Saved
> views are absent from the active table, while their still-required verbs
> remain explicitly classified as compatibility contracts. The temporary
> hub remains the root for PA-3b, and the authored-drawer handover remains
> reserved for PA-3d.
>
> Evidence: the explicit PARA suite passes **30/30** and the legacy
> Glasspane suite passes **72/72**. Exact table shape, bar ordering, badge,
> selected route, Archive exclusion, Apps/Archive/Eval drawer presence,
> Files absence, all four registry-FAB ownership/precedence arms, deleted
> rows, and the rollback restoration are pinned. Warning-as-error
> compilation, clean package installation, dependency layering, icon lint,
> diff hygiene, and the full elevated `test/run-tests.sh` pass; the runner
> exited **0**. PA-3a rides the batch gate and has no separate device arm.

### PA-3b — Root swap (hard dep: S11 committed + deployed)

1. `glasspane.el:150`: `(jetpacs-chrome-define-root glasspane-owner "glasspane-agenda" #'glasspane-agenda-screen)` — the root id deliberately EQUALS the id `agenda.open` pushes, so tapping the Agenda bar entry resets to root for free via same-id truncate-and-replace (jetpacs-chrome.el's stack-insert). `glasspane-ui-home-screen` unreferenced (flag-gated corpse until PA-4). `glasspane.home` unchanged in name and shape; it now resets to the Agenda root.
2. **The Saved page** (§5.5) joins the agenda pages.
3. **Boot seed** (PA-1's ROUTE form) lands in the tablet harness init.
4. **Route hooks:** `glasspane-ui-open-destination` (GR-8c helper, survives verbatim: reset+push peer semantics) also calls `jetpacs-apps-note-route`; **the ratified back-repush hook** on `jetpacs-shell-view-change-functions` (the journal on-view-change precedent — that hook itself dies): map screen ids → route keys ("glasspane-agenda"→agenda, "glasspane-projects"→projects, areas/area-*→areas, archive→archive, "glasspane-review"→review, view-*→agenda; detail/search/drill-* → no change), note the route, `jetpacs-shell--schedule-repush` ONLY when the route changed (one bounded repush per route-changing back; T-5 watches). Resources has no Glasspane screen id: `app.open` selects that route before its deliberate handoff to the Files surface.
5. Journal's landing hook + `glasspane-journal-landing` defcustom + its Settings row die behind the flag — the Agenda root IS the landing.

**Gate:** arms: root-id-equals-agenda-push (bar tap truncates to root, never stacks); reset semantics (destination B removes destination A; drill preserved only within a destination); route honesty (verb-reached destination → its bar entry `:selected`; back → origin re-selected after the repush; boot-seed arm); `glasspane.home` resets to the Agenda root.

### PA-3c — Destination screens wired + slot/token audit

Wire the PA-2 screens and Resources delegate to the flipped table; run the GR-8c-analog audit with the PARA rows: `area.open` peer-replace in the destination slot; the search-drill eviction chain (§5.6); detail constant-id re-entry; the Resources whole-surface Files handoff and return; journal keep-day row deleted from the audit (dies with Journal). **Token budget re-verified:** live `"glasspane"` sets ≈ 23-25 today; the delta is +1 ("areas" + twin) − 1 (`journal-carried` dies) — headroom vs `ebp-org-token-sets-max` 32/owner stays ≥ 6; T-4 stays armed. mark-pos adoption rows (agenda-item jumps, notes backlinks, detail "Open in file") carry over from GR-8c unchanged.

**Gate:** the audit checklist recorded in the rung notes with per-family resolutions (the GR-8c artifact rule); token-count arm.

### PA-3d — Drawer handover + top-bar Search + aliases

1. **Glasspane authors NO drawer** (stronger than GR-8b's shrunk drawer): `glasspane-ui--home-drawer` + `--drawer-app-rows` retire behind the flag; the S8 host drawer composes on the Agenda root — Apps row; the Glasspane nest (ALL 6 rows incl. **Archive** — its primary affordance) + other apps' nests; **the relocated Eval row** (PA-1's selective rule); the host tail (Tools nest, divider, Settings nest). Files is intentionally absent: Resources is its Glasspane navigation wrapper. The "fewer than three destinations: no drawer" clause governs *authored* app drawers — Glasspane authors none. M-x parity holds row by row.
2. **Top-bar Search** (§5.6): shared helper `glasspane-ui--top-actions` returning the search `icon_button` (`search.open`), passed as `:actions` by the destination screen builders. NOT the S10 global-items seam (shell-scope; the placement defcustom could re-author it into a FAB). Not on the search screen itself; not on detail.
3. **Aliases live:** `tasks.open` → projects; `views.hub` → Agenda Saved page; `journal.capture` → the headless datetree-append deprecation handler. Journal/views destination rows out (behind the flag).
4. **PA-OR-4 venue:** rule ef/gallery here or leave app-side; the rework's residual `:any-surface` audit rides along either way.

**Gate:** arms: composed-drawer contents on the root (nest + relocated rows + tail, exactly once each); no authored `:drawer` anywhere in glasspane; search icon present on destination screens, absent on search/detail; the three aliases answer `accepted` and land correctly; journal-alias queue arm (an injected queued `journal.capture` replays into the datetree).

### PA-3 gate — the big device batch + soak

Tablet, PORTRAIT, force-stop before every smoke, screenshot before every tap (I-7): boot-state arm (force-stop → relaunch → five entries on the Agenda root, Agenda selected, NO prior navigation — the seed, not the app-grid detour); five entries on BOTH form factors (bar compact / rail medium+); destination-hop across all five; Agenda opens its Day/Week/Month tabs; **system back from each destination → Agenda with Agenda re-selected after the repush; system back at the Agenda root → Activity finishes; relaunch resumes (the S11/I-14 arms)**; Agenda badge; drawer: Archive opens its filtered list, Eval reaches the REPL, Apps opens the switcher, and no Files duplicate appears; Eval and Files guest surfaces retain Glasspane's five-entry bar (the recorded §5.2 acceptance arm); Areas renders live categories from the real vault → drill → detail → back chain; Resources opens the native Files explorer rooted at `org-directory`, remains selected while browsing, exercises search/create plus Org and non-Org opens, and returns cleanly; Archive row → native Files reader + back; Review SRS + stale + Habits link tap; search icon → screen → `search.by-tag` chip round trip ending Search-visible with the origin destination still selected; FAB = capture on destinations, absent on the guest settings satellite; M-x on every destination; stale-route fallback lands on the Agenda root (re-verify `app.open`'s fallback-home under no-hub); journal-alias replay arm on hardware. **Then ONE full daily-driver soak day on the new IA before PA-4.**

### PA-4 — Demolition + exit checklist (deletions cite their soaks)

1. Delete the flag-gated corpses, each commit citing the soak: **`glasspane-journal.el`** (after the queue-drain check: confirm the offline queue empty — or replayed to empty — of `journal.capture` receipts before deleting the alias, the rework §5.2-step-2 pattern; the alias itself survives ≥ one release per §0.11 — its deletion may fall to a later ladder and this rung records that); the hub corpse (`glasspane-ui-home-screen`, `--home-body`, `--home-drawer`, `--drawer-app-rows`, `--capture-fab`); the views-hub screen; the `glasspane-tasks` registration remnants; the journal landing defcustom + Settings row; `glasspane-ui-legacy-ia` and now-constant flags.
2. Grep gates in the suite: zero references to any deleted symbol; `test/run-tests.sh` explicit list re-verified.
3. **Exit device checklist (one consolidated day):** the GR-9 list re-targeted — single-alarm arm, reboot-rearm, capture e2e, chronometer (if GR-5 ran), PARA IA spot-checks, org-crypt pull-and-verify, desync re-run, back-contract spot-check (I-14). All green ⇒ `git tag para-closed`; stamps applied (§10); memory updated.

### PA-5 — Upstreaming tail

= the rework's GR-10, re-hosted pointer, content unchanged (table/babel move, per-heading affordances, mutation verb family, cross-file search, demo seeder split, vulpea extractor non-rename). Executes after PA-4; each item decision-gated as written there.

## §5 The IA target (first-class design; PA-3 implements it)

### §5.1 The full-bar primary pole
`:chrome 'primary :dock-core nil :drawer-core '("eval")` (v4-amended form): core contributes zero bar items while Glasspane is current; the app's five `:bar`-eligible destinations fill the bar; only Eval relocates to the composed drawer. Resources subsumes Files, so Files is deliberately neither a Glasspane bar entry nor a drawer duplicate. Daily driver (never loads Glasspane): the build-within default branch still renders Eval/Files; Apps remains drawer-only.

### §5.2 Foreign surfaces (recorded acceptance, extended)
The primary branch keys on the current app with no surface check — while Glasspane is current, Files and hub surfaces wear Glasspane's five destination entries and no Eval/Files entries, even while standing on the Eval REPL itself. Escape hatches: every root drawer carries Eval, Apps, and all destination nests; S11 system back; the five persistent destinations themselves. This EXTENDS the GR-8b acceptance (org-mode's dock item already suppressed while Glasspane is current); the recorded follow-up "surface check in the primary branch" (rework §10) stays the escape hatch if it sours. The tablet is Glasspane's device — the rationale, verbatim.

### §5.3 Three tiers (max-screens 3, exactly)
- **Tier 0 — pinned root: the Agenda screen.** Day/week/month + ≤8 custom-agenda pages + the Saved page; page switches are device-local tab swipes, zero slot cost.
- **Tier 1 — destination slot:** exactly one of projects / areas-list / area-NAME / archive / review / view-NAME / search-drill. Opens ride `glasspane-ui-open-destination` (reset+push peer semantics — switching destinations abandons the drill); `area.open` and `views.open` replacing their list screens in this slot is the ratified peer pattern. Resources is the deliberate exception: it delegates to the canonical Files guest surface and creates no Glasspane screen or slot.
- **Tier 2 — drill slot:** `glasspane-detail` (constant id; re-entry truncates, never evicts).
- Recorded audit row: detail→search→detail re-push truncates to the existing detail entry, dropping search (existing stack semantics; acceptable).

### §5.4 Route honesty
`jetpacs-apps--current-route` is written by `app.open`, the boot seed, `glasspane-ui-open-destination` (via `jetpacs-apps-note-route`), and the ratified back-repush hook (§4 PA-3b step 4). The bar's `:selected` is therefore honest at boot, on bar taps, on verb-reached destinations, and after every route-changing back gesture — at the cost of one bounded repush per such back (T-5 armed).

### §5.5 The Saved page (the views fold)
The Agenda screen gains a "Saved" page listing BOTH registries: `glasspane-org-custom-agendas` entries (tap = switch to that agenda page) and `glasspane-saved-views` entries (tap = `views.open` → the per-view screen as a Tier-1 peer, back → Agenda root). `views.hub` aliases to Agenda-landing-on-Saved. The two-registry duplication is recorded, not merged (PA-OR-2).

### §5.6 Search
A top-bar search icon on Glasspane's destination screens pushes the existing search screen as a plain drill — back returns to the origin; no route change (the origin destination stays selected — honest: search is transient, not a place). The real `search_bar` node exists but the search screen is a query BUILDER (filter sections + chips + tokenized results), not a suggestion list — forcing the bar-expansion shape is a rewrite with no offline gain; recorded polish: swap the screen's text input for a docked `search_bar` in-screen later. Slot cost audited in §5.3.

### §5.7 Surface roles — no duplicate rows
Host drawer = canonical extended navigation (Apps + nests + selected relocated core + tail). The five-entry bar = the PARA loop; Agenda's Day/Week/Month controls are its content tabs. Agenda root = the app's home AND its first destination. FAB = capture. Top bar = back/hamburger + Search + M-x + overflow. **The two Homes, re-reconciled:** the shell's home is the Eval REPL hub — reached through the drawer while Glasspane is primary; the APP's home is the Agenda root — one system back from any tier; `glasspane.home` is the explicit reset onto it. Three affordances, three jobs; none renamed to pretend otherwise.

## §6 File fates — the delta vs rework §8 (rows not named here are unchanged there)

| File | Fate |
|---|---|
| glasspane.el | root swap ("glasspane-agenda"); `:chrome 'primary :dock-core nil :drawer-core '("eval") :fab`; table pass-through; new module wiring; hand dock item retires |
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
- Grow a query-grammar `category` term (PA-OR-1), merge the two saved registries (PA-OR-2), or badge the Review destination (PA-OR-3).
- Build unarchive, cross-archive search, or archive-side mutation verbs; honor `#+ARCHIVE` keywords or `::* heading` archive targets (v1 corpus = sibling `_archive` files only; all recorded).
- Adopt `org-agenda-custom-commands` / org-ql / composite agendas.
- Add the primary-branch surface check (§5.2's escape hatch — recorded follow-up if the foreign-surface trade sours).
- Everything in rework §10 except the overridden `journal.capture` row (§0.11).

## §10 Cross-reference stamps (apply on each doc's next edit; this plan does not modify them)

**For `docs/PLAN-glasspane-rework.md`:**

> **PARA supersession (2026-08-15; navigation amended 2026-08-16): docs/PLAN-glasspane-para.md replaces this plan's IA half (ladder PA-0..PA-5).** Caleb ratified exactly five persistent destinations — Agenda/Projects/Areas/Resources/Review — with only Agenda containing Day/Week/Month content tabs; no shell Home row; Agenda is home — no hub; Projects succeeds Tasks; Resources wraps Files; Journal deleted; Search → top app bar; drawer = Archive + Eval + Apps + host tail; capture FAB unchanged. Superseded: §7 whole, GR-8 whole, OR-5 (resolved by the ratified destination list), GR-9's demolition list (PA-4 carries the successor, adding journal + hub + the search destination row), §8's ui/agenda/journal/views/search rows. Surviving unchanged: GR-0..GR-7, §5 ceremonies, I-1..I-8 (I-6 re-points to PARA §5.3), §9 (T-5 re-points to the back-repush hook + Agenda-root cards). §3 amendments: `tasks.open` retargets to the PARA Projects destination; `glasspane.home` resets to the Agenda root. **Overridden non-move:** `journal.capture`'s "stays permanently" (GR-4 step 6, §10) — a queued-durable verb (ttl 86400) that winds down through PA's deprecation alias + queue-drain ceremony, never a bare deletion. GR-10 executes after PA-4 as PA-5. Historical GR-8 tab references read only through this supersession stamp.

**For `docs/PLAN-jetpacs-debt-and-scaffold.md`:**

> **PARA restructure (2026-08-15): docs/PLAN-glasspane-para.md supersedes GR-8** — S8's "until GR-8b shrinks it" and the GR-8b host-drawer directive resolve to PA-3d; S11 is a hard precondition for PA-3b's back arms; S10 interacts (top-bar budget) but is not a dependency. GR-7b remains the :badge/FAB funding rung, unchanged. CHROME-VOCABULARY v4 (2026-08-15) ratified the S8 root-only drawer-injection sentence this ledger's S8 entry left pending.

**For `docs/PLAN-glasspane-app.md`** (optional, low priority): at the #26 hub entry — the ONE-TABLE gate tests survive the hub's death renamed to the root-reaches-every-opener form (PARA I-9).

## §11 Coverage cross-checks (auditable from this doc alone)

**Ratified inputs → where honored:** §0.1→PA-1/PA-3a · §0.2→PA-3b/§5.3 · §0.3→PA-2d · §0.4→PA-2a · §0.5→PA-2c · §0.6→PA-2e/§9 · §0.7→PA-3d/§5.6 · §0.8→§2/§10 · §0.9→PA-0/PA-1 · §0.10→PA-3b/§5.4 · §0.11→§3/PA-4.
**New surfaces → suite arms:** every PA-2 rung names its arms; the one new suite is wired at PA-2a (I-12).
**Dying/moved verbs → I-13 rows:** all in §3; the only durable carrier (`journal.capture`) has its ceremony (PA-4).
**Invariants → enforcement:** I-9→PA-3a gate + the renamed inventory tests · I-10→PA-3a/PA-3 batch · I-11→PA-3d gate · I-12→PA-2a · I-13→§3 · I-14→PA-3 batch (S11 arms).
