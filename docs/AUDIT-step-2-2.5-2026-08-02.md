# Step 2 and 2.5 audit — 2026-08-02

This audit is based on local Jetpacs, EBP, Emacs, AndroidX, architecture-template,
architecture-samples, Compose sample, and Nav 3 source trees. GitHub was not used
as a code authority. Gradle's own checksum registry was used only to authenticate
the selected wrapper distribution and wrapper JAR.

## Room-first architecture correction

The original audit treated Room as a surface projection appended to POC 2's
file-backed stores. That direction is superseded by
[`PLAN-room3-rebuild.md`](PLAN-room3-rebuild.md): POC 3 will be rebuilt from the
local architecture template, and Room 3 will be Jetpacs' sole durable
implementation of POC 2's EBP state. The existing surface cache is a proven
prototype, not the production persistence seam.

Consequently, S2-001 is no longer a post-accept cache callback; it is a generic
suspending EBP transaction SPI plus an optional post-commit domain-change hook.
S2-002 is part of the full Room surface contract. S2-003 is the complete
Room-first rebuild and file-store cutover. Later projection language in this
dated audit is historical; the rebuild plan is canonical.

## Boundary decision

EBP remains Jetpacs-agnostic. `emacs/ebp.el` and the future `kotlin-ebp` library
may define protocol state, validation, accepted-mutation DTOs, and persistence
ports, but they may not depend on Jetpacs, Room, Nav 3, Android, or Compose.

Room 3 is Jetpacs' sole durable implementation of state accepted from Emacs;
`kotlin-ebp` remains the storage-independent semantic authority. Nav 3 owns
Jetpacs destinations and history. Neither choice becomes an EBP field, method,
or requirement. EBP document-local `view.switch` remains distinct from Jetpacs
app navigation.

## Step 2 status

Completed in this branch:

- Rebasing `slop-fork/v3` onto local Jetpacs `slop-fork/main` at `9241bdd`.
- Re-running the Room/cache JVM gates, app unit tests, debug APK, Android lint,
  and release APK after the rebase.
- Verifying the Room contract on a Pixel Tablet running API 37 before Step 2.
- Adding pairing-scoped cache revocation to the DAO, real repository, shared
  fake, and tests. Revocation erases snapshots and tombstone floors only for
  the revoked pairing.
- Aligning the installation floor to Android 16/API 36 in every Android module.
- Aligning Activity Compose `1.13.0` and Compose BOM `2026.05.01` with the local
  architecture template while retaining the deliberate Material 3 expressive
  override.
- Regenerating the Gradle 9.5.1 wrapper. The properties now pin the official
  binary distribution SHA-256 and the wrapper JAR matches Gradle's official
  SHA-256.
- Extending CI with the POC3 core JVM suites, lint, and debug/release assembly.

The complete wire suite compiled and ran 353 tests after the rebase. Nine tests
failed only because the POC3 EBP submodule checkout is not at its gitlink; the
remaining 344 passed. Core/app verification is green independently.

## Step 2 blockers before production Room/Nav wiring

### S2-001 — generic transaction SPI and committed change stream

The current app callback is `(surface, resolvedView?)`. It omits pairing,
revision, tombstone state, the full accepted document, `stale_after_s`, and
`stale_spec`. A `view.switch` can also change the resolved view without a new
surface revision, so the callback is neither a safe cache input nor a durable
transaction boundary.

Do not expand it into a post-accept Room writer. Define a suspending,
storage-independent transaction SPI in `:wire`/future `kotlin-ebp`; Jetpacs'
Room adapter commits through that SPI before returning `applied`. An optional
typed domain-change event may be emitted after commit for platform effects. It
contains no Room type or Jetpacs policy and is not a second persistence path.

### S2-002 — fix existing stale-snapshot persistence

The current wire handler validates `stale_spec` but `SurfaceStore.Record` and
`PersistedRecord` discard it, and `stale_after_s` is not consumed. That is an
existing Section 13.2/13.5 conformance gap and prevents a complete Room store.
Characterize old persisted files, include the fields in the new Room schema and
legacy importer, and test disconnect/process-death behavior before using Room as
the renderer source.

### S2-003 — Room-first durable rebuild and cutover

The JSON backings, one-table Room prototype, and `EbpApplication` flows are
parallel representations today. Replace them with one Room-backed implementation
of the generic EBP transaction SPI:

```text
Emacs -> kotlin-ebp reducer -> generic transaction SPI
      -> Jetpacs Room transaction -> committed Room state
      -> read-only repository Flow -> ViewModel StateFlow
      -> dumb Compose renderer
```

The rebuild includes the pairing partition, surfaces/drafts, queue, reminders,
triggers/runtime, theme, legacy import, and crash-resumable revocation. It uses
one process-lifetime coroutine actor and never dual-writes. The same behavioral
contracts run against memory and Room, and every `applied` response follows the
commit. Section 19 session state remains non-durable. The detailed work packages
and cutover gates are in `PLAN-room3-rebuild.md`.

### S2-004 — lifecycle-aware Nav 3 composition root

Use the local Nav 3 `BasicSamples.kt` pattern: `rememberNavBackStack`,
`NavDisplay`, saveable-state and ViewModel-store entry decorators, and a modular
entry provider. A screen ViewModel must expose immutable state using
`stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ...)`; Compose
must use `collectAsStateWithLifecycle`.

The first stack needs only Pairing, Catalog(pairing, surface), and Settings.
Back-stack restoration is a device test. Multiple stacks, deep links, and
adaptive scenes remain later work. `pane_scaffold` stays renderer-local adaptive
layout rather than Nav state.

### S2-005 — local EBP checkout reproducibility

The rebased gitlink pins `4f8c7ba`. The POC2 EBP worktree has that exact
`slop-fork/main`, while the separate local `/projects/jetpacs/ebp` repository is
still at `4f6f82b` and does not advertise `4f8c7ba`. The failed initialization
left POC3's submodule at `adf9cee` with staged deletions. The current branch must
not claim a green conformance gate until the local authority is reconciled and
the submodule is detached at the gitlink.

## Toolchain and platform gate

| Area | Decision / result |
|---|---|
| Gradle | 9.5.1, verified distribution checksum and official wrapper JAR |
| AGP / Kotlin / KSP | 9.2.1 / 2.3.21 / 2.3.9, matches local template |
| Android | compile/target/min API 36; device verification on API 37 |
| Compose | BOM 2026.05.01; Activity Compose 1.13.0 |
| Room / SQLite | Room 3.0.0-rc01 / SQLite 2.7.0-rc01, matches local AndroidX |
| Nav 3 | 1.1.2; serializable keys compile, app integration still pending |
| Emacs | minimum 30.1; built-in `jsonrpc.el`; `track-changes.el` begins in Step 3 |

Post-change device gate on the Pixel Tablet:

- 3 database and 3 repository tests passed on Android 17/API 37.
- The debug APK installed and cold-launched; the app process remained alive.
- The launched process had no `AndroidRuntime` error in its filtered log.
- Build-tools 36 verified every APK entry and native library at 16 KB alignment.

The tablet kernel reports a 4096-byte page size, so this proves APK/native
alignment but not execution on a 16 KB-page device.

Before closing Step 2, run rotation, background/foreground, process death,
predictive back, notification denial, reboot/timezone receiver, offline cache,
and reconnect scenarios on the device. Add explicit edge-to-edge/system-bar
appearance; `safeDrawingPadding` alone is not the complete policy.

## Step 2.5 hardening backlog

### P0 — before Step 3

- Resolve S2-001 through S2-005.
- Add a public, additive `:edit-delta-function` hook to `ebp.el` so
  `ebp-sync.el` receives the already-validated splice rather than re-diffing the
  whole mirror or calling private internals. Pin callback ordering and Unicode
  eligibility on Emacs 30.1 and current local Emacs.
- Generate and validate contract enum tables in Kotlin and Elisp. The current
  contract validator/generators do not fully enforce `enums`/`field_types`, and
  runtime catalogs remain partly hand maintained.
- Add renderer semantics tests, device screenshot goldens, and one cross-runtime
  fixture from Elisp-authored canonical EBP JSON through Kotlin validation to
  Compose semantics.

### P1 — low-risk hardening

- Promote stable JSON accessors from `wire/JsonAccess.kt` and remove the
  duplicate app `render/NodeAccess.kt` implementation after characterization.
- Extract pure dialog capture construction and the repeated input
  seed/epoch/publish sequence only after behavior tests exist.
- Add one `tools/check` entry point with quick/all/device/changed modes and
  machine-readable output.
- Add module-boundary lint: `core` may not depend on app; `wire`/`kotlin-ebp`
  may not depend on Jetpacs, Room, Nav, Android, or Compose; `ebp*.el` may not
  depend on `jetpacs-*`.
- Generate lookup tables from a manifest with source commit, generator,
  generated-region hash, and `--check` mode. Stop parsing Org tables as runtime
  data and stop hand-maintaining widget/enum catalogs.
- Add `.gitattributes` for LF text and explicit binary/golden handling, plus a
  bootstrap preflight for the EBP pin, Android references, SDK, Emacs, and ADB.
- Fix inherited compiler deprecations: AutoMirrored icons, positional
  `rememberSaveable`, dynamic swipe anchors, and Kotlin 2.4 exhaustiveness.

### P2 — characterized structural work

- Split `CompanionEngine.kt`, `SpecValidator.kt`, `InputNodes.kt`,
  `Renderer.kt`, and `jetpacs-widgets.el` only behind characterization tests.
- Move proven platform-neutral wire code to `commonMain` as `kotlin-ebp`
  extraction proceeds.
- Replace flat scaffold growth with typed nested configuration/child nodes when
  a second demonstrated consumer justifies the vocabulary change.
- Add adaptive scenes, multiple Nav stacks, deep links, macrobenchmarks,
  baseline profiles, accessibility coverage, and release shrinking.

## POC 1 versus POC 2 correction and regression matrix

| Area | Result for POC3 |
|---|---|
| Room | POC1 used Room for queued events and triggers only. POC2 replaced it with richer file-backed queue, surface/tombstone/draft, reminder, and trigger stores. POC3 must preserve those semantics while adopting Room 3 as Jetpacs' cache; it is not a return to POC1's schema. |
| JSON-RPC | Keep current built-in `jsonrpc.el`; do not restore POC1's hand-rolled transport. |
| Sync | Restore POC1 behavior as generic `ebp-sync.el`, but replace whole-buffer prefix/suffix diffing with built-in `track-changes.el`. |
| Reconnect | Restore generic endpoint reconnect policy with built-in timers. |
| Editor command | Kotlin emits semantic `event.action` action `edit.command`, but no current Emacs handler exists. Add Jetpacs policy after generic buffer registration exists; do not put its command allowlist in EBP. |
| Diagnostics/Eldoc/fontification | Restore as optional adapters over generic EBP hooks, with Jetpacs owning file/mode/Eglot policy. |
| Nav | Replace POC1's manual stack with Nav 3 for Jetpacs destinations; keep EBP `view.switch` separate. |
| CI/DX | Current CI and generators are stronger than the historical rewrite review, but need POC3 core/lint/schema/device and unified generation checks. |

## M3 fidelity implications for the DSL

Recent `search_bar`, `navigation_rail`, `pane_scaffold`, `tooltip`, and
`split_button` work repeatedly touched renderer dispatch, profiles, vocabulary,
Elisp catalogs, and generators. Replace parallel registries with a typed
renderer manifest, but do not generate renderer support merely because EBP
knows a node type.

Observed categories:

- Prior hint, badge, spacing, alignment, tonal, and shadow failures were
  renderer defects, not EBP gaps.
- Filled versus outlined icon style is a real generic vocabulary gap.
- Icon-only tabs need an explicit accessible description rather than falling
  back to an icon identifier.
- Navigation-rail selection and one-frame adaptive demonstrations are currently
  catalog harness/state problems, not automatically protocol gaps.
- Authored state, synchronized drafts, and renderer-local ephemeral state need
  explicit traits. Scroll positions and animation frames remain local and must
  not become EBP traffic.

## Step 3 entry criteria

Do not begin the `track-changes.el` engine until the P0 decisions above have
stable tests and the cache/navigation composition root is understandable.
`ebp-sync.el` will own only generic buffer registration, tracker/session/shadow
state, queued applies, validated remote deltas, resync, and teardown. Jetpacs
will own file/buffer selection, Eglot/Flymake/Eldoc policy, `edit.command`, and
application UX.
