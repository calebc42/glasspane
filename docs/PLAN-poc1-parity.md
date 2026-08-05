# POC 1 usability parity plan

Status: accepted 2026-08-04. Order set by the owner: live editing first,
then the command fabric, then app breadth; automation authoring last.

POC 3 (now `slop-fork/main`) carries the conformant wire, the Room store,
the org layer, launcher, clip, and the full M3 catalog. What it does not
carry is the interaction fabric that made POC 1 (`slop-fork/poc-v1`,
worktree `../llm-poc`) the best daily driver. The divergence-map audit
(`../llm-poc/docs/AUDIT-ebp2-divergence-map.md`) already ruled this layer
port-safe: the wire cores had to be rebuilt (done), the app chrome
survives as ports.

Porting rule: POC 1 is the behavior reference, never a merge source. Every
port lands against current SPEC shapes (Section 19 first-class editor
methods, not POC 1's `event.action` legs), with ERT coverage, and modules
that are protocol-generic keep the `ebp-` prefix and zero Jetpacs
dependencies.

## P1 — live editing (in progress)

| POC 1 source | POC 3 target | Notes |
|---|---|---|
| `core/jetpacs-sync.el` (923 lines) | `emacs/ebp-sync.el` (new) + additive `ebp.el` splice hook | The Step 3 recipe in `ARCHITECTURE-POC3.md` is normative: built-in `track-changes.el`, deferred signal, `:disjoint t`, one op contending for `seq + 1`, resync boundaries never guessed. `goldens/editor.golden` pins the splice arithmetic on both endpoints. |
| — diagnostics/fontify/eldoc riders | follow-up after the core loop | The wire frames exist; the flymake/fontify push layer ports once buffer sync is stable. |
| `core/jetpacs-witheditor.el` (197) | NOT a goal (owner decision 2026-08-04) | git and magit are not shipped with Emacs, so magit-commit-from-phone cannot be a Jetpacs goal. No port needed anyway: the generic bridge syncs any buffer, so a user who installs magit gets with-editor buffers on the phone by attaching them — user-land, never named by Jetpacs. |

Exit gate: edit a real buffer from the tablet and from Emacs concurrently;
the golden corpus replays; a forced desync recovers via one `edit.resync`
with no wrong edit. Built-ins-only holds throughout: track-changes,
flymake, font-lock, org, outline — nothing Emacs does not ship.

## P2 — the command fabric

| POC 1 source | POC 3 target | Notes |
|---|---|---|
| `core/jetpacs-minibuffer.el` (919) | port against dialog-as-request (§18.1) | POC 1 predates held-open `dialog.show` requests; prompts become dialogs with `dialog.submit`/`dialog.dismiss` builtins. |
| `core/jetpacs-transient.el` (315) | port | Transient menus as surfaces; check §16.1 presentation-identity rules. |

Exit gate: an arbitrary `M-x` with string/completing-read prompts is
completable from the phone.

## P3 — app breadth

| POC 1 source | POC 3 target | Notes |
|---|---|---|
| `core/jetpacs-apps.el` (378) + `jetpacs-app-store.el`, `jetpacs-hosts.el`, `jetpacs-config.el` | port first in P3 | The registry seam the skins hang off; multi-app isolation (`appid.*` views) is already normative. |
| `core/jetpacs-settings.el` (555) + `jetpacs-customize.el` (359) | port | custom.el stays the backend seam. |
| `core/jetpacs-package-browser.el` (247) | port | Tablist Tier 0.5 renderer already ported. |
| `core/jetpacs-project.el` (357), `core/jetpacs-sql.el` (199) | port | Independent skins, any order. |

## P4 — automation authoring (deferred by owner decision)

`core/jetpacs-automations.el`, `jetpacs-automations-org.el`,
`core/jetpacs-triggers.el` — the Tasker-parity authoring UX. The trigger
wire and runtime already conform in POC 3; only the authoring layer waits.
The §5 weak-language compiler decision (declarative registrations vs
wake-gated handlers) governs the port when it happens.

## Not ported, on purpose

`jetpacs-spec.el`, `jetpacs-lint.el`, `jetpacs-demo.el`,
`jetpacs-source.el`, `jetpacs-devtools.el` — POC 1 workspace tooling;
re-evaluate per-file only when a concrete need appears. `jetpacs-pack.el`
is superseded by the binding layer already in POC 3's lineage.
