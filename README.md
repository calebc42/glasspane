# jetpacs llm-poc-3 — the durable rebuild worktree

POC 3 rebuilds the conformant rewrite around explicit KMP boundaries, a Room 3
outbox/cache owned by Jetpacs, an independent SQLite inbox owned by Emacs, and
Navigation 3. The in-tree `:ebp-kmp` module contains the storage-neutral KMP
durable-store SPI, reducers, and memory reference implementation. `:wire`
retains transport, framing, and protocol code and depends on `:ebp-kmp`;
Jetpacs-specific policy lives outside both. Start with
`docs/PLAN-poc3-rebuild.md`, then use
`docs/ARCHITECTURE-POC3.md`, `docs/PLAN-room3-rebuild.md`, and
`docs/PLATFORM-RENTAL-REGISTER.md` for the detailed boundaries and local-source
implementation references.

## Lineage and walls

- **`slop-fork/poc-v1`** (worktree `../llm-poc`) — the first PoC, closed by
  its divergence-map audit
  (`../llm-poc/docs/AUDIT-ebp2-divergence-map.md`). It is guidance and organ
  donor: read it, port from it, do not merge it.
- **`slop-fork/v2`** (worktree `../llm-poc-2`) — the POC 2 line, closed at
  the end of the M3 catalog sprint and cherry-picked commit-for-commit into
  this branch. Like poc-v1 it is now reference, not a merge source.
- **`slop-fork/main`** (this tree/worktree) — the POC 3 rebuild: the
  Room-first architecture carrying the ported POC 2 sprint.
- **`main`** — the clean-room hand-rebuild track. Sealed from both
  slop-fork lines; nothing here is merged there and nothing there is read
  from here.

## Rules of construction

1. **The spec remains the cross-platform contract.** First prove required
   behavior in implementation and backend contracts against the current spec.
   Then audit any mismatch: repair the implementation when the spec already
   covers it, or expand the spec only in language- and platform-agnostic terms.
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
| `companion/` | Storage-neutral `:ebp-kmp`, protocol `:wire`, and Jetpacs KMP app/core modules |
| `test/` | ERT suites; every wire test is driven by `ebp/goldens/` |
| `docs/PLAN-poc3-rebuild.md` | Cross-platform execution phases and exit gates |
| `docs/PLATFORM-RENTAL-REGISTER.md` | Built-ins/libraries that POC 3 must rent instead of reimplementing |
| `docs/REWRITE-PLAN.md` | Rung ladder, gates, port manifest |
| `docs/ARCHITECTURE-POC3.md` | Local references, module boundaries, Room/Nav/track-changes plan |
