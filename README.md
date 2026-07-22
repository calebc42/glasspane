# jetpacs llm-poc-2 — the conformant rewrite

A from-scratch rewrite of the Jetpacs reference implementation against the
normalized EBP spec: **`ebp/SPEC.md`** (protocol 2, document 2.0.0-draft,
contract format 6), pinned by the `ebp` submodule. The wire core is written
new, conformance-first; the organs of the first PoC (renderers, capability
effectors, the org layer, app chrome) are ported behind it once their rung
is green.

## Lineage and walls

- **`slop-fork/poc-v1`** (worktree `../llm-poc`) — the first PoC, closed by
  its divergence-map audit
  (`../llm-poc/docs/AUDIT-ebp2-divergence-map.md`). It is guidance and organ
  donor: read it, port from it, do not merge it.
- **`slop-fork/main`** (this tree) — the rewrite. Fresh history, no
  ancestry with poc-v1.
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
| `companion/` | The Kotlin companion (arrives with its K-track rungs) |
| `test/` | ERT suites; every wire test is driven by `ebp/goldens/` |
| `docs/REWRITE-PLAN.md` | Rung ladder, gates, port manifest |
