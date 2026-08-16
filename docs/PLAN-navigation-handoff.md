# Navigation program — closing ledger and handoff

**Status: the navigation-consistency program is COMPLETE on the elisp/JVM
side (2026-08-15).** Four rungs landed and adversarially verified in one
day; this doc is the closing ledger, the invariants the program minted,
and the ordered handoff of what remains. It plans nothing new — the
forward IA program is docs/PLAN-glasspane-para.md (ratified), riding
docs/PLAN-glasspane-rework.md GR-0..GR-7 and the S-ledger in
docs/PLAN-jetpacs-debt-and-scaffold.md §4.

## 1. What landed (slop-fork/main, in order)

| Commit | Rung | One line |
|---|---|---|
| fa1fbf6 | — | checkpoint: 46 loose onboarding/packaging files secured (jetpacs.el + jetpacs-init.el were untracked) |
| a218eaa | S8 | drawer persistence seam — the composed host drawer injects on every build-within root, stack-bottom only |
| 31c3f1c | S9 | single enumeration + conformance sweep — defapp registry is THE identity source; launcher/clip/sql/project brought into chrome |
| ee34b40 | S11 | Companion BackHandler — system back runs the presented screen's own arrow, companion-local, offline included |
| 8965e40 | S10 | global-actions placement — where M-x rides ('top-bar/'fab/'fab-menu) is a phone-settable defcustom |
| 81556eb | — | CHROME-VOCABULARY v4 ratified (the S8 root-only drawer rule + full-bar form are contract text now) |
| c63935d | — | PLAN-glasspane-para.md — the ratified IA redesign (PA-0..PA-5), supersedes rework §7 + GR-8 |

The original complaint — drawer sometimes there, sometimes not, contents
different per screen; M-x appearing out of nowhere — traced to one
asymmetry: the dock and the global actions had injection seams in
`jetpacs-chrome--build`, the drawer had none, and three different lists
(dock, drawer nests, launcher) each enumerated "apps" their own way.
S8+S9 closed that. S10 made the remaining hand-authoring (M-x placement)
declarative and phone-configurable. S11 gave the platform back-contract
its missing half. Nav3 was correctly diagnosed as irrelevant to chrome
consistency and stays deferred (deps + JetpacsNavKey staged, unused).

## 2. Verification record

Every rung: implemented, then adversarially reviewed (multi-lens
finder/verifier agents), every CONFIRMED finding fixed before its
commit, full ERT gate green at each commit (47 suites; 1081 → 1091
tests across the program) plus `:app:testDebugUnitTest` +
`:app:compileDebugKotlin` for the Kotlin rung. Notable review catches,
all fixed in-line: three D2 inline-push violations (S9), the
multi-surface identity erasure (Org Mode would have relabeled the Files
surface), the stateless drawer-sheet overloads installing no back
handler (S11 — an open drawer would have had the stack switched under
it), the authored-`:fab` reach loss (S10 — M-x vanishing from glasspane
home), and the substring dedup (`...mxyz` swallowing `...mx`).

## 3. Invariants this program minted (bake into every future rung)

- **D2, sharpened:** an action handler NEVER pushes inside the dispatch
  extent — resets included; defer through `jetpacs-flow-continue`
  (three regressions caught the day the rule was leaned on).
- **Authored-wins costs the SLOT, never the REACH** (S10): injection
  seams yield the slot to a screen's own chrome but must re-home the
  affordance, not drop it.
- **Drawer is root-only** (S8, v4-ratified): SPEC 16.1 document-wide id
  uniqueness is why; the dock sidesteps only because its tabs carry no
  literal keys.
- **System back = the authored arrow, nothing else** (S11): the
  extractor matches the top bar's leading spine only — a drawer row or
  body button carrying `view.switch` must never claim the gesture.
- **Function-valued seams stay defvars** (S10): `jetpacs-settings--decode`
  falls through to `read` for undecodable types, so a phone-settable
  function value is an eval surface; only closed choice-of-consts
  tokens get defcustom promotion.
- **Registry scans, not first-claim filters** (S9): a secondary surface
  claim must not shadow another app's home.

## 4. Handoff — in execution order

1. **Device smoke of S8–S11** (the one open verification debt: all of
   it is ERT/JVM-proven only). Folds into GR-1's hardware floor and the
   PA-3 device batch. Minimum arms: drawer present on every app root
   (hub, Files, Settings, app-store, SQL, Project, Org Mode, Habits,
   catalog, launcher, Clipboard) with identical canonical contents;
   back arrows on the sql picker / project find+switch working with the
   socket down; system back pops the stack, closes an open drawer
   first, and still exits from a root; M-x placement flipped from the
   phone's Appearance settings, including the authored-FAB fallback
   screens (glasspane home, Buffers) and the three self-authoring bars.
2. **The PARA ladder** (docs/PLAN-glasspane-para.md, ratified) is the
   forward IA program. S11 was PA-3b's hard precondition — satisfied at
   commit level; APK deploy is still pending.
3. **GR-0..GR-7 survive** (docs/PLAN-glasspane-rework.md). GR-7b's
   `:badge` + per-app FAB registry feeds PA-3a — and must OUTRANK the
   S10 globals in the `:fab` slot (comment already at the join,
   jetpacs-chrome.el `--join-global-fab`).
4. **Open ratifications** for Caleb: the S10 fab-placement deviation
   from the FAB contract sentence (opt-in only; the default honors v4
   exactly), and the S9 OR on Customize's tree-up back riding the
   arrow slot (the one back arrow that dies offline).
5. **docs/PLAN-glasspane-reimagined.md sits UNTRACKED and UNVERIFIED**:
   a parallel planning workflow was stopped mid-verification once the
   PARA plan was ratified — its OR-1 (supersede vs coexist) is already
   answered by PARA. Do NOT land it as a competing doc; mine it for
   salvage into the PA ladder if anything looks valuable, else delete.
6. **Nothing is pushed to any remote** (standing discipline: ebp
   first, then the stack).

## 5. Where things live

- The S-ledger with all [LANDED] stamps: PLAN-jetpacs-debt-and-scaffold.md §4.
- The chrome contracts: CHROME-VOCABULARY.md (v4).
- The session-persistent program memory: the assistant's
  jetpacs-navigation-program note carries the same state.
