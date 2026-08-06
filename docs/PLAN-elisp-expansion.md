# PLAN: the elisp expansion — package-skin survey + hypertext substrate

STATUS (2026-07-13): PLANNED — nothing landed yet. Authored from two full repo audits
(jetpacs + Glasspane/composer), the committed substrate doctrine, and a source-verified
stage design. Part III Stage 0 is the first executable increment.

## Context

This began as a thought experiment: *if jetpacs / jetpacs-composer / Glasspane are an
LLM-generated "worse is better" PoC, what would a clean-room rewrite "the correct way"
be — Rust+Slint? Flutter? Java/JNI?* Part I records the answer (short version: no stack
change; correctness belongs at the interface, and the GNU-alignment lever is moving more
behavior into elisp). The headline of this plan is that lever: **survey Emacs packages
(built-in / GNU ELPA / NonGNU ELPA / MELPA) as contenders for abstractions/skins**, with
the magit-section family expanded toward server management over TRAMP (including Guix
hosts). Scope decisions: all four pillars in scope; deliverable = survey + build plan for
the top pick; Spec-1.0/conformance work kept as a compressed parallel track (Part V).

## Part I — The stack memo (settled)

**Verdict: keep elisp (the brain) + Kotlin/Compose (the pane); a language swap fails every
stated motive.** The audited numbers: the elisp brain is 12,654 LOC (stack-agnostic, reused
verbatim under *any* client stack; only ~933 LOC is protocol) and Glasspane adds 8,073 LOC
of pure elisp. Of ~12k Kotlin LOC, only the 5.5k renderer is replaceable — the ~3.7k
platform moat (RemoteViews widgets, QS tiles, exact-alarm reminders, TriggerHost,
`specialUse` FGS, boot re-arm, 18-capability effector hub) stays Kotlin/Java under
**every** alternative, reached via JNI/channels. All three repos are **already GPLv3**, so
"FOSS ⇒ Java and C" dissolves (Kotlin/Compose are Apache-2.0 upstream; the GNU-purist
Java+C Android artifact already ships in this system — the GNU Emacs Android port itself).
Rust+Slint: Android backend Rust-only, IME/safe-area only landed in Slint 1.15 (2026) —
immature exactly where this app lives. Flutter: BSD buys no copyleft, second render
pipeline, its payoff (iOS) is a non-motive. Java/JNI: keeps the moat but discards Compose —
pure downside. The audit also undercut the "worse is better PoC" premise: SPEC.md has a
real Conformance section, contract.json is generated + byte-pinned, two golden layers +
~190 ERT tests exist. What's genuinely NJ-grade: 227 LOC of Kotlin tests, no per-node
schemas, no session fixtures, sparse SPDX. Hence Part V.

## Part II — The elisp expansion: package survey (the headline)

### Criteria (the repo's committed doctrine, applied)

1. **Tier-0 renders free by default** (jetpacs-buffer.el:3-16) — a skin is an opt-in
   override "only where it's worth it"; skip anything that already reads fine.
2. **Substrates over one-offs** (tablist/comint/results precedent) — one renderer per
   buffer *framework* covers every derivative.
3. **"Earns a curated primitive"** (PLAN-platform-hardening.md:436) — high-frequency ×
   interaction-sensitive × small closed parameterization.
4. **Phone-fit** — reading, chat, glance-and-act, capture; not IDE work (standing scope
   decision).
5. **Deps/battery** — pure elisp > Termux binary (fine: shared signature) > resident
   daemon (avoid); build-feature probes for libxml/sqlite (positive knowledge).
6. **Archive tier** (GNU-alignment): built-in > GNU ELPA > NonGNU ELPA (default-enabled
   since 28.1) > MELPA-only.

### Already free — never build these (zero new code)

Every tabulated-list derivative (**daemons.el** systemd — incl. remote over TRAMP, proced,
**bui.el = Emacs-Guix package/generation lists**, docker.el list modes, kubel); every
comint derivative (REPLs incl. **geiser/Guix REPL**, shells — incl. over TRAMP);
occur/compilation/**grep**/xref (results substrate); **every transient UI** (the whole
casual suite, magit/forge popups) via the transient bridge; **every minibuffer read** incl.
`read-passwd` — **TRAMP ssh password prompts are already phone dialogs**; widget.el/
Customize forms; dired (cards skin); with-editor/git-commit. Any third-party package built
on these frameworks arrives pre-skinned.

### Ranked build candidates

| # | Bet | Family unlocked | Archive tier | Why this rank |
|---|-----|-----------------|--------------|---------------|
| **1** | **Hypertext substrate** (top pick — Part III) | eww, help, Info, man + every shr consumer: elfeed-show, nov.el (EPUB), devdocs, elpher; **prerequisite for mail message views** | built-in core; elfeed NonGNU, devdocs GNU | Committed verdict already (Phase H Task 23); biggest delta over free baseline (images→placeholder, tables→flat, layout linearized today — while the *wire already has* image/table/span nodes); reading is THE phone activity; zero new wire vocabulary |
| **2** | **magit-section substrate + server/TRAMP pillar** (runner-up — Part IV) | magit status, forge, kubernetes.el, taxy-magit-section riders (**ement room list, org-ql views → feeds Glasspane saved views**) | magit NonGNU; taxy-magit-section GNU | High leverage, but current baseline is "acceptable not degraded" (sections already fold/tap + keymap pie), so delta is smaller than #1's; the TRAMP/Guix arc is mostly *composition* of existing substrates (see Part IV) |
| 3 | **Comms** — gptel micro-skin first; ement.el; ERC; then mail (notmuch or mu4e) | gptel (NonGNU, chat buffer ≈ org text + composer bar = cheapest high-wow win); ement (GNU ELPA — room list rides #2, message bodies rendered by shr ride #1); mail search = adapter, message view = #1, compose = existing with-editor/editor bridges | mixed | Structurally honest: no shared chat framework (ewoc vs erc-insert vs plain text) — it's one *presentation pattern* (timeline + composer) with thin per-package adapters; sequenced after #1 because ement/mail bodies are shr |
| 4 | **Life-admin Tier 1s** — ledger/hledger capture+reports; EBDB contacts; EMMS | ledger: capture template + report tables (native table node exists; binary via Termux; strong PKM-conversion adjacency). EBDB (GNU ELPA) custom formatting = medium adapter. EMMS (GNU ELPA): playlist adapter + `media.key` exists — a lock-screen MediaSession would be a new *negotiated* Kotlin capability | GNU ELPA heavy | App-shaped, not substrate-shaped; pick per demo needs — ledger-capture first among them |

**Skip / defer (doctrine reasons):** telega (tdlib C daemon — battery/build), pdf-tools
(epdfinfo C; phone PDFs → `intent.start` to a native viewer), EXWM (graphical), calc/SES
(defer — carried over from the built-ins verdict), treemacs/neotree (imenu+dired cover),
vterm (C module; comint path preferred), dashboards (launcher exists). **eshell**: not
comint-derived so it misses the substrate; plain Tier 0 today; no committed record of prior
deferral — file as a small future adapter, not now.

**Execution note:** the survey itself gets committed as **`docs/AUDIT-package-skins.md`** —
it also becomes the durable home of the 2026-07-12 built-ins verdicts, which currently
exist nowhere on disk except the Task 23 line.

## Part III — Build plan: hypertext substrate (6–8 evenings; mechanics verified against source)

**Locked design decisions.** One new file `emacs/core/jetpacs-hypertext.el` (Tier 0.5,
results/comint file shape; inserted into `emacs/build-bundle.el`'s ordered list after
results + bundle regen). **Two-phase render**: adapters scan a buffer into a neutral
*document model* (segment plists: heading/para/pre/quote/image/table/rule), one emitter
maps the model onto the existing vocabulary (`section_header`, `rich_text` spans,
`surface`, `jetpacs-image`, `jetpacs-table`, `divider`) — that's what keeps adapters thin.
In-document links = spans tapping the existing `jetpacs.buffer.act` (same-buffer navigation
+ refresh re-push; **no new dispatch**). Toolbar nav (back/forward/prev/next/up — no buffer
position to tap) = one new additive allowlisted action `hypertext.nav` with a hardcoded
per-mode op→command alist. Fidelity floor: unrecognized runs degrade to plain paragraph
spans — worst case equals Tier 0, never worse. **No new wire node types, no Kotlin changes**
(the lint=golden=`SDUI_NODE_TYPES` equality test enforces it).

- **Stage 0 — Build-feature probe (= hardening Task 23 verbatim) (S).**
  `jetpacs-build-features` defconst + `jetpacs-feature-p` in `emacs/core/jetpacs.el`
  (fboundp-guarded predicates, libxml among them); additive `features` field in the hello
  client object (~jetpacs.el:473); api 1.6.0→**1.7.0** + machine-checked API-STABILITY.md
  entry; Bridge-settings doctor row (jetpacs-shell.el ~524); SPEC §3 additive note; bundle
  regen. Verified: `frames.golden` doesn't pin the client object, so no golden regen
  expected. Accept: new ERT on the constant + hello round-trip; suite + core-load green.
- **Stage 1 — Follow-seam hardening + card-grammar core (M).** Extract the results shim
  (jetpacs-results.el:225–256) into shared `jetpacs-buffer-call-shimmed` (window-excursion
  + display shims + `last-input-event`/`last-nonmenu-event` nil + condition-case); results
  becomes a thin wrapper; **also bind the nil-event guard inside
  `jetpacs-buffer-invoke-at`** (jetpacs-buffer.el:583–612 — the 71de875 bug class at the
  seam every link tap rides). New file with the segment model + `jetpacs-hypertext--emit`
  (image/table emit placeholders until Stage 4 so the model shape is final now). Accept:
  **the missing 71de875 regression test** (push a fake input event, assert position-driven
  jump), existing results tests green unchanged, grammar goldens via a new
  `test/hypertext.golden` + regen fn (mirroring `jetpacs-tests-regen-widget-golden`).
- **Stage 2 — Adapter 1: shr-property reader, registered for `eww-mode` (M).** Scan
  char-property runs: `shr-h1..h6` faces → heading levels, `shr-url` → link spans, existing
  face→span resolution for emphasis; image/pre/table runs → segment kinds. **All shr
  prop/face names isolated in one "props contract" function** — the drift firewall. Fixture
  `test/fixtures/hypertext-basic.html` rendered through the *running* Emacs's libxml+shr in
  ERT; every shr test `(skip-unless (jetpacs-feature-p 'libxml))`. Valve: heading faces
  unreliable → descope to links+paragraphs (still above Tier 0).
- **Stage 3 — Adapters 2+3: help-mode + Info-mode + document-nav toolbar (M/L, splittable
  3a/3b; libxml-free, can swap ahead of Stage 2).** `hypertext.nav` action: per-mode
  allowlist (eww back/forward/reload; Info prev/next/up/toc/history; help back/forward;
  `goto` for TOC section nav) invoked via the shared shim, toolbar emitted in-body offering
  only live directions (results toolbar precedent). Help adapter: button.el xrefs → link
  spans (same-buffer rewrite works via act+refresh); Info adapter: breadcrumb header card,
  menu/xref runs → links, underline-pair headings → `section_header`. Accept: help tests
  run everywhere (no libxml); Info tests against a small committed `.info` fixture (never
  system manuals); junk op/mode rejected. Valves: Info body descopes to header+nav over
  Tier 0 body; that alone is a win.
- **Stage 4 — Images + native tables, this substrate's render path ONLY (M/L; images
  must-have, tables descope-first).** Image resolution: display-spec `:file` → `file://`
  passthrough (covers nov.el, which extracts EPUB resources to disk); http(s) source → URL
  passthrough (**device fetches — battery-friendliest**); `:data`-only → write-once cache
  under `jetpacs-root` (content-sha1 filenames, idempotent, defcustom byte cap ~20MB +
  mtime sweep + manual clear), alt text → content description. **Generic Tier 0 untouched —
  the Task 10 deferral stands** (cross-reference added, no code). Tables eww-first:
  re-parse `eww-data :source` via libxml, DOM `<table>` → `jetpacs-table` matched to
  rendered regions by document order; ambiguous stays monospace (zero regression). Accept:
  extractor unit tests on hand-propertized buffers (batch Emacs is non-graphic — test the
  extractor, not shr's image production); cache idempotency/sweep tests; DOM-table golden.
- **Stage 5 — Rider proof + docs + closeout (S/M).** Public
  `jetpacs-hypertext-register-shr-mode` + soft registrations via `with-eval-after-load`
  (worked example: `elfeed-show-mode`; nov/devdocs as one-liners — they derive from
  `special-mode`, so explicit registration required, and never register `special-mode`
  itself). Docs per current-state rule: BUILDING-TIER1/ARCHITECTURE tier table gain the
  substrate + rider recipe; Task 23 status flip; API-STABILITY entries. Accept:
  throwaway-mode ERT through the public register fn; `git grep` proves no
  `(require 'elfeed/nov/devdocs` in core; core-load-test green.

**Dependency spine:** 0 → 1 → 2 → 4, Stage 3 hangs off 1 (2↔3 swappable), 5 last.
**Top risks + mitigations:** shr prop drift across 30.x → props-contract fn + contract ERT
against the running shr (drift = named test failure); `:data` images → passthrough-first,
cache valve; Info's prop-less structure → heuristics tested on a committed fixture, descope
valve; input-event hijack → fixed once at the shared seam and finally pinned by a
regression test.

## Part IV — Runner-up sketch: magit-section substrate + server/TRAMP/Guix pillar

- **Substrate:** map the magit-section tree → collapsible cards; per-section keymaps →
  context actions (the keymap→actions extraction already proven by the pie seam). Unlocks
  real card UIs for magit status, forge topics, kubernetes.el, and **taxy-magit-section**
  riders (ement room list, org-ql dynamic views — the latter feeds straight back into
  Glasspane).
- **The pillar is composition, not construction:** TRAMP makes existing skins remote —
  dired cards, comint shells, compile/grep results, magit, daemons.el — and `read-passwd`
  bridging already covers ssh prompts. **Guix host story:** package/generation management =
  bui lists (tablist, free), `guix` REPL = comint (free), system ops = daemons.el + shells.
  New code needed: one small Tier-1 **host/connection picker** (bookmarked TRAMP endpoints
  → open dired/shell/magit/daemons *on that host*), plus latency/battery guardrails (TRAMP
  ops are synchronous — expose glance-and-act operations, not long pipelines).
- Sequenced second; starts after Part III or interleaved evenings if Part III stalls on a
  gate.

## Part V — Parallel track: Spec 1.0 + conformance (compressed; independently landable)

S0 freeze bookkeeping: SPEC status `1.0-rc` + `docs/SPEC-CHANGES.md` amendment log +
version-coherence ERT (S) · S1 per-node/per-kind schema registry in jetpacs-lint tables →
`contract_format: 2` via build-contract.el (M–L) · S2 Kotlin golden-replay conformance
suite — needs real `org.json` test dep (M; **MVP line**) · S3 wire-transcript recorder
(nil-default sink) + ERT session replay, 2-evening canonicalization timebox → synthetic
fallback (M–L + one phone evening) · S4 Kotlin transcript validation (S–M) · S5 declare
Frozen 1.0 + `docs/PROVENANCE.md` (artifact-attached provenance: human-reviewed spec,
dual-consumed fixtures, rewrite-must-pass-kit) (S–M) · S6 SPDX/REUSE pass across all three
repos (3×S, fully parallel) · S7 deploy-script dedup (S, cut first). No wire changes
anywhere; everything except S0 defers cleanly during alpha crunch.

## Non-goals & kill criteria

- No renderer rewrite / language change / template DSL (standing decisions). No
  wire-protocol changes; any new node attr is additive + negotiated. No full
  elfeed/nov/mail apps in this round — the substrate plus one thin rider proof. No
  telega/pdf-tools/EXWM.
- Part III Stage 0 gate: if the libxml probe fails on the device Emacs build, the shr
  adapter descopes to help/Info adapters first (they don't need libxml) while the device
  build question routes to Phase H.
- Alpha pressure valve: survey doc (Part II) is one evening and safe anytime; Part III
  stages are evening-sized and individually landable; Part V S0 alone stops spec drift.

## Verification

- Every stage: `wsl -d Debian -- test/run-tests.sh` (headless ERT, `</dev/null` + timeout)
  green; ~190 existing tests stay green; new substrate tests skip-unless the build-feature
  probe.
- Hypertext substrate acceptance: golden-style card-grammar fixtures (LF-only .html
  fixtures); on-device checks — eww article with images + a table, `C-h f` help page, an
  Info node with menu nav, one shr rider (elfeed-show or nov) — links follow via the mode's
  own command under the shim (no input-event hijack regressions), images render as real
  `jetpacs-image` nodes from the temp-file cache.
- Part V per-stage gates: seeded-failure tests prove the validators bite, byte-pinned
  contract regen, transcript determinism check.
- External facts verified 2026-07-13: Slint 1.5/1.15 Android status (slint.dev);
  elfeed/gptel/magit on NonGNU ELPA; taxy-magit-section on GNU ELPA.
