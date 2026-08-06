# PLAN: the ebp-org split — the org engine leaves the floor

Status: accepted 2026-08-06 (Caleb). The naming rule is RATIFIED, not open:

> `jetpacs-` names what cannot exist without Kotlin, Android, and Compose;
> `ebp-` names what only ever touches the wire and Emacs.

(bed8ef4, `refactor(complete): ebp-complete - the capf bridge is wire and
Emacs only` — the rule's first executed rung, and this plan's precedent.)

The boundary test for any module: does its contract reference the node/surface
vocabulary (Compose-shaped → `jetpacs-`), or only wire methods and Emacs state
(→ `ebp-`)? The org engine passes: org is built-in Emacs, the ref-token and
refusal-disposition vocabulary is SPEC 14.4/14.5 wire, and nothing in it needs
a node. The prefix is not a label but an ENFORCED claim — G1 extends the
delineation guard to every `ebp*.el` file, glob-derived (the hand-kept-list
failure mode is the guard's own recorded lesson).

## §0 STATE

| Checkpoint | SHA | Status |
|---|---|---|
| G1 guard generalized | — | pending |
| G2 doctrine into ARCHITECTURE | — | pending |
| G3 ebp-path.el | — | pending |
| G4 token scope explicit | — | pending |
| G5 teardown-owner public | — | pending |
| G6 ebp-org.el phase 1 | — | pending |
| G7 ebp-org.el phase 2 + shim | — | pending |
| G8 adapter suite | — | pending |
| G9 ledger closed | — | pending |

## The measured shape (all numbers verified twice: design + adversarial pass)

`emacs/jetpacs-org.el` is 1777 lines. Exactly SIX floor couplings across ten
source lines; by enclosing form, 132 lines (7.4%) are floor-coupled and 1645
(92.6%) are engine-pure. The couplings: the `jetpacs-surfaces` require (:78),
`:group 'jetpacs` (:82), `jetpacs-local-paths` (:143), `jetpacs-check-path` +
`jetpacs-path-refused` (:186-187), `jetpacs-current-owner` (:551, :603), and
the `jetpacs-teardown-functions` add/remove pair (:619, :1772). Everything
else — `jetpacs-error-label`, `with-jetpacs-owner`, `jetpacs-retry-later` —
is doc-text only. None of this week's seam symbols appear.

Two findings shape the whole plan:

1. **The ambient owner is dead in tree.** Every production and test caller of
   `jetpacs-org-ref-tokens` / `jetpacs-org-token-ref` passes `:owner`
   explicitly; the `(or owner jetpacs-current-owner)` fallbacks are exercised
   by nothing. Owner is an opaque equality-compared scope key in exactly three
   roles (mint cap-key, lookup match, teardown sweep) — never resolved, never
   validated against the floor. Deleting the fallback is a two-line diff, plus
   one NEW guard: `jetpacs-org-token-ref` has no stringp check today, so its
   ambient path would fail SILENT (answers stale) — it gains
   `(unless (stringp owner) (error "..."))` after the token stringp, so a bad
   token still answers stale while a missing owner errors loudly.
2. **`jetpacs-check-path` must not come back.** It was promoted OUT of
   jetpacs-org at JA-6 because jetpacs-files grew a second caller ("A guard
   that exists twice is a guard that is correct once"). It moves to a third
   pure file, `ebp-path.el`, that engine and application both require.

Consumer churn, measured (no aliases needed; house hard-rename): dialogs
19 symbols / 38 lines, habits 9/14, vulpea 3/5, outline 3/4, render 3/4,
surfaces 1/2 — 67 production lines. Error-condition arms: 9 production lines
(+~7 in tests/smokes). ebp-path blast radius: 20 production lines + ~30 test
lines (files.el has 14 `jetpacs-path-refused` condition-case arms plus a
`signal` at :902; files-test also at :719 and :1074, and the /sdcard-probe
test at :264-270 moves with the F1 family since it asserts the non-signal).

## Assignment rulings

- **jetpacs-org.el residual = a ~40-line REGISTRATION SHIM.** It exports no
  callable symbols; it exists for its load effect — the
  `(add-hook 'jetpacs-teardown-functions #'ebp-org-teardown-owner)` pair and
  the requires. Documented as such.
- **Tokens: ENGINE, entirely** (both hashes, both caps, nonce, counter, the
  atomic three-pass mint, `ebp-org-token-ref`, `ebp-org-teardown-owner`).
  D-4 holds: refs never cross the wire, tokens do — that is wire vocabulary.
- **Error conditions rename**: `ebp-org-refused` / `-unresolved` /
  `-unavailable`, and `ebp-org-refusal-disposition`. Handler-position names
  are invisible to the byte-compiler — the exit gate is grep-ZERO on the old
  strings, not "tests pass".
- **`ebp-org-file-save-function`**: engine. It is LIVE (dialogs:1018 calls
  it; the AUDIT-ja4 claim that nothing calls it is stale — corrected in G9).
- **defgroup**: `(defgroup ebp-org nil ... :group 'org :prefix "ebp-org-")` —
  parented to the standard `org` group. Five defcustoms ride along.
- **jetpacs-error-label**: nothing to sever — doc-only. The engine's contract
  instead states: every condition it signals carries no payload beyond the
  head symbol's own data discipline.
- **Vulpea arm**: requires `ebp-org` alone; the FILE keeps its staging name
  and its `jetpacs-org-vulpea-*` symbols, but its two protocol entry points
  rename with the engine: `ebp-org-note-matches-p`,
  `ebp-org-note-query-supported-p`. (Staging doctrine unchanged: never
  required by base, migrates to the app repo with its Tier-1 rung.)
- **Outline**: `jetpacs-org-outline.el` (the Tier-1 VIEW) keeps name and
  tier; it calls `ebp-org-file-toplevel-records` / `ebp-org-outline-cap`.
  The split dissolves the model/view naming collision.
- **Load-graph consequence, deliberate**: after the split,
  `(require 'jetpacs-org-render)` no longer transitively registers the org
  teardown sweep (render requires only ebp-org); registration arrives via the
  shim, which dialogs/habits require. G8 pins the property that matters:
  after `(require 'jetpacs-org-render)` in the device require set,
  `ebp-org-teardown-owner` is a member of `jetpacs-teardown-functions`.
- **The fboundp reset bridge is a SILENT hazard**: surfaces.el:1297 probes
  `jetpacs-org-reset`; renaming without editing it just stops resets running.
  Six sites total: surfaces.el:1300-1301 + five test fixtures (org-test:32,
  habits-test:35/:187, dialogs-test:77, render-test:53). All move in G7.
- **Outline no-base-require pin**: its `directory-files` regexp widens to
  ``"\\`\\(jetpacs\\|ebp\\)-.*\\.el\\'"`` in G7 or the scan set silently
  narrows to half the tree.

## The ladder

- **G1** `test(guard): every ebp file loads alone - and errors, groups and faces count`
  run-tests.sh:6-21 becomes a POSIX per-file loop over the `emacs/ebp*.el`
  GLOB (one `emacs -Q --batch` process each; coverage is glob-derived, count
  asserted ≥ 5, never a name list). Widened offender predicate:
  `(or (fboundp s) (boundp s) (facep s) (get s 'error-conditions)
  (get s 'group-documentation) (get s 'custom-group) (memq s features))` over
  `jetpacs`-prefixed symbols — `custom-group` is what actually catches a
  `:group 'jetpacs` parent link. Exit gate: all five current files green; two
  throwaway probes demonstrated red (a general offender; a file whose ONLY
  offence is `:group 'jetpacs`) then deleted.
- **G2** `docs(architecture): what earns the ebp prefix - the ratified boundary`
  ARCHITECTURE-POC3.md's non-negotiable boundaries gain the ratified sentence
  verbatim with the bed8ef4 SHA plus the enforcement paragraph (bare-Emacs
  load, require closure = vanilla + other ebp files, the guard proves it).
  Fix two stale strings: install.sh's comment ("globally unique `jetpacs-'
  file name") and ci.yml:118's suite count.
- **G3** `refactor(floor): ebp-path.el - the sandbox is nobody's application`
  New ~55-line pure file: `ebp-path-refused`, `ebp-local-paths`,
  `ebp-check-path`, moved (hard, no copy) out of jetpacs-surfaces.el:249-330
  with the JA-6 promotion paragraph extended. surfaces requires it and keeps
  no path code. All callers re-pointed: org (:143/:186-187), files (:216 +
  14 arms + signal :902), project (:288); tests incl. files-test :719/:1074
  and the /sdcard probe. Exit gate: gate green + grep-zero on the three old
  RAW STRINGS + the new file passes the G1 guard by glob.
- **G4** `refactor(org): tokens take their scope - the ambient owner was never read`
  Both fallback deletions; the new token-ref stringp guard; error strings
  name the parameter, not `with-jetpacs-owner`. Exit gate: gate green with
  ZERO call-site edits (proves the fallback was dead); both entry points
  error loudly ownerless.
- **G5** `refactor(org): jetpacs-org-teardown-owner - the sweep is the engine's, the hook is the floor's`
  `jetpacs-org--on-teardown` → public `jetpacs-org-teardown-owner`, body
  byte-identical; add/remove-hook updated; the two direct test calls move to
  the public name. (Renamed again to `ebp-org-` in G7 with everything else —
  this commit isolates the visibility change from the move.)
- **G6** `refactor(org): ebp-org.el - the grammar and the primitives load without the floor`
  Phase 1: the ~840 lines depending on neither `--check-file` nor the
  cache/mutation blocks (errors + refusal-disposition, D2 clamp, typed
  extraction, query parser/vetter, the interpreter `ebp-org-matches-p`,
  ts/logbook/clock/table primitives) move to new `emacs/ebp-org.el` under
  `ebp-org-` names, with the eager-load require block verbatim and the new
  defgroup. jetpacs-org.el requires ebp-org and keeps phase-2 code working.
  Exit gate: gate green; ebp-org passes the G1 guard.
- **G7** `refactor(org): ebp-org.el takes the rest - jetpacs-org.el is the registration`
  Phase 2: roots/agenda-files/--check-file (on ebp-path) + the public
  `ebp-org-file-allowed-p`, cache, refs + tokens + teardown-owner, mutations
  + save timer, high-level query, file-save seam, outline model, reset,
  unload. jetpacs-org.el shrinks to the shim. All 67 consumer lines move to
  `ebp-org-` names; error-condition arms renamed (grep-zero gate); the six
  reset sites; the outline-pin regexp; suite moves wholesale to
  `test/ebp-org-test.el` in run-tests.sh's Jetpacs-free block (after
  ebp-sync, plain runner) — placement rule per the ebp-complete precedent
  comment: a suite lives in the pure block iff its process loads no
  application layer. Exit gate: gate green; the ebp-org suite's process
  loads no jetpacs feature (asserted in-suite); grep-zero on `jetpacs-org--`
  outside the shim/adapter set.
- **G8** `test(org): the adapter's registration, finally covered`
  New slim `test/jetpacs-org-test.el` (application block): teardown driven
  END TO END through `jetpacs-teardown-functions` (today's tests call the
  private directly — the registration itself has zero coverage); the
  fboundp reset bridge asserted positively; the render→teardown chain
  property from the rulings above.
- **G9** `docs(org): the ledger closed and the stale claims corrected`
  §0 SHAs filled; AUDIT-ja4:407 file-save claim struck (one live caller);
  PLAN-rf5a E2 discharge noted; the corrections table (census :215/:459/
  :472/:578/:1740; churn numbers; locate-library limitation stated).

## Sequencing and non-goals

Independent of the P1 wiring (ebp-sync-attach remains unwired; either order
works); precedes the addons/apps repo reorg, which has no plan doc yet and is
not gated on this. NOT in scope: renaming jetpacs-org-vulpea.el/jetpacs-org-
outline.el files (staging doctrine), jetpacs-hypertext (its shr work emits
nodes — jetpacs by the boundary test), further ebp candidates beyond those
named in bed8ef4's lineage.

## Risks (the three silent classes)

1. Condition-name arms are invisible to the byte-compiler — every rename gate
   here is grep-ZERO on raw strings, never "tests pass".
2. fboundp bridges fail silent — every one gets a positive membership/effect
   assertion (G8).
3. Test files are never byte-compiled — the suite moves carry manual sweeps,
   and smokes are grep-swept (they are run by nothing).
