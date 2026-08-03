# jetpacs llm-poc-3 — the KMP architecture scaffold

POC 3 extends the conformant rewrite with KMP architecture boundaries, a Room 3
cache, and Navigation 3. The in-tree `:wire` module remains the incubator for a
future standalone, Jetpacs-agnostic `kotlin-ebp` library; Jetpacs-specific
policy lives in `companion/core`. See `docs/ARCHITECTURE-POC3.md` for the local
reference review and implementation sequence.

## Lineage and walls

- **`slop-fork/poc-v1`** (worktree `../llm-poc`) — the first PoC, closed by
  its divergence-map audit
  (`../llm-poc/docs/AUDIT-ebp2-divergence-map.md`). It is guidance and organ
  donor: read it, port from it, do not merge it.
- **`slop-fork/main`** — the current local rewrite and eventual rebase target.
- **`slop-fork/v3`** (this tree/worktree) — the POC 3 architecture scaffold,
  kept separate for this checkpoint and rebased onto local `slop-fork/main` next.
- **`main`** — the clean-room hand-rebuild track. Sealed from both
  slop-fork lines; nothing here is merged there and nothing there is read
  from here.

## Rules of construction

1. **The spec is law.** Every behavior traces to a SPEC.md section. A
   needed behavior with no section is a spec bug: it goes to
   `ebp/SPEC-CHANGES.md` as an amendment first (the W-register in the
   poc-v1 audit seeds this), never silently into code.
2. **Conformance before features.** A rung lands only with its `ebp`
   fixtures green: the wire Goldens (`ebp/goldens/wire/` incl. the §9.3
   known-answer vector), the frame/widget/hypertext corpora, and the §24.6
   adversarial vectors that apply to the rung.
3. **Port, don't rewrite, above the boundary.** Modules classified
   port-safe in the divergence map come across as ports with vocabulary
   updates only. Rewriting them is scope creep.
4. **The contract is authored in `ebp/`.** This repo generates its wire
   vocabulary from `ebp/contract.json` and byte-compares its projection
   back (the poc-v1 drift machinery pattern is kept).

## Layout

| Path | What |
|---|---|
| `ebp/` | Submodule: the governing spec, contract, goldens, validate.py |
| `emacs/` | The elisp client, spec-first (`ebp.el` wire core, then modules) |
| `companion/` | Kotlin app, future `kotlin-ebp` incubator, and Jetpacs KMP core modules |
| `test/` | ERT suites; every wire test is driven by `ebp/goldens/` |
| `docs/REWRITE-PLAN.md` | Rung ladder, gates, port manifest |
| `docs/ARCHITECTURE-POC3.md` | Local references, module boundaries, Room/Nav/track-changes plan |
