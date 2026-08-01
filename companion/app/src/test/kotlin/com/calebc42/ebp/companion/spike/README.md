# spike-kotlin — table + apply-rows (throwaway)

**This directory is a measurement instrument, not a feature.** Scheduled by
[PLAN-refound-2026-07-28.md](../../../../../../../../docs/PLAN-refound-2026-07-28.md)'s
data-spike rung (the kotlin half, gated on the RF-2b exit — met at `2871b59`,
merged in PR #3). Deleted when the numbers are recorded.

Written before the first line of code, per the rung's discipline clause.

## The question — reframed, honestly

The ladder row says this spike "produces the measurement that decides RF-4a's
carrier." That was written before spike-elisp ran. **spike-elisp already decided
the carrier** (2026-07-31): a real vault's full-row projection is 7.34% of one
frame — no bulk carrier, Decision 9 upheld. What the kotlin half still owns is the
question the elisp half *couldn't* see:

> The frame fits — but does the vault actually **ride** the declared carrier
> (`surface.update` + `table`) within the *node-level* limits the app advertises,
> and what does the Companion-side accept + apply cost?

Concretely, with the app's real advertised limits (`DeviceBridge.kt`):
`max_table_cells` = 4096 and `max_rich_spans` = 4096, both **aggregate per
SurfaceSpec** (LD-22; counted in `SpecValidator` at `ctx.tableCells += cells.size`).
A 586-note vault at C columns is 586·C cells and ≥586·C spans. The arithmetic says
a 5-column (minimal) projection fits one update at 2,930 cells while a 16-column
(full) projection at 9,376 cells cannot — the spike verifies both empirically
through the real engine and measures the chunked alternative.

## Questions

1. **One-update viability.** Minimal shape (5 cols): accepted in one
   `surface.update`? Full shape (16 cols): rejected, and with exactly what
   taxonomy (which limit fires first, cells or spans; error code and reason)?
2. **The boundary.** 4096 aggregate cells accepted, 4097 rejected — through the
   full frame path with the app's own profiles, not a synthetic validator config.
3. **Chunk math.** Full shape at floor(4096/16) = 256 rows/update → 3 updates for
   586 notes. Total accept time, per-chunk time.
4. **Companion-side cost.** encodeFrame → decode → validate → store apply, ms, for
   the ~300 KiB one-shot and for the chunked sequence.
5. **apply-rows.** Read the accepted spec back out of the `SurfaceStore` into a
   flat `List<Row>` (the consumer motion): time and fidelity (586 of 586).

## Method constraints

- **`:app` only.** The spike lives in the `:app` test source set. It builds the
  engine with `NodeSupport.surfaceProfiles()` — the app's *real* advertisement,
  which is the point — and the same limits block `DeviceBridge` declares. Nothing
  under `:wire`, nothing under `ebp/`, no production code.
- **Synthetic rows, deliberately.** The elisp spike measured the real vault
  (586 notes, mean 524 B full row, p95 581, max 679, no tail). This half generates
  deterministic synthetic rows matching that distribution. Two reasons: the repo is
  public, and vault content (titles, paths) must not be committed; and a JVM test
  cannot run Emacs. The distribution figures are the bridge between the halves.
- Carrier vocabulary only: `surface.update` + `table`. No `jetpacs.*` method
  (§7.3 frozen, I5), no `jetpacs.*` capability (closed `VALIDATED` set).

## Kill criteria

- The answer is unambiguous early → stop and record. (The elisp half stopped this
  way; same rule.)
- The spike would need to modify `:wire`, `ebp/`, or production `:app` code to
  proceed → stop; that is RF-4c's work, not a measurement.
- One sitting.

## Removal

```
git rm -r companion/app/src/test/kotlin/com/calebc42/ebp/companion/spike
# spike(kotlin): remove — measurement recorded in PLAN-refound RF-4a
```

Nothing may come to depend on this directory. The durable numbers go to
PLAN-refound's data-spike verdict; `RESULTS.md` here dies with the directory.
