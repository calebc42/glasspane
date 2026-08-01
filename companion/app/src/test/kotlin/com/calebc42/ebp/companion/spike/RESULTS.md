# spike-kotlin results — 2026-07-31

Raw record; the durable finding lives in PLAN-refound's data-spike verdict. This
file dies with the spike directory.

Run: `./gradlew :app:testDebugUnitTest --tests "*TableRowsSpikeTest*"` — 5/5 green.
Real engine, real app advertisement (`NodeSupport.surfaceProfiles()`), real
`DeviceBridge` limits, full frame path. Synthetic rows matching spike-elisp's
measured distribution (586 notes; full row ~524 B mean).

## Answers

| Q | Result |
|---|---|
| Minimal shape (5 cols), one update | **applied** — 2,930 cells, 142,527 B, 2.8 ms |
| Full shape (16 cols), one update | **rejected 1201 `exceeds max_table_cells`** — 9,376 cells (437,872 B never mattered; the *cell* cap fires, not the frame) |
| Boundary | 4,096 aggregate cells **applied**; 4,097 **rejected 1201** — the cap is exact, through the full path |
| Full shape, chunked | floor(4096/16) = **256 rows/update → 3 updates** for 586 notes; 438,135 B total; **7.0 ms total accept** |
| apply-rows | 586/586 extracted from the stored spec, ids unique, **0.72 ms** |

## What this means, next to spike-elisp

The two halves answer different constraints and both are needed:

- **elisp half:** the *frame* is never the binding limit — full vault 7.34% of one
  frame. No bulk carrier (Decision 9 upheld).
- **kotlin half:** the *node-level aggregate caps* are the binding limit —
  `max_table_cells` 4096 (and `max_rich_spans` 4096 in parallel; cells fired first
  here at one span per cell). A rich multi-column projection of even this small
  vault does **not** ride a single `surface.update`; it chunks at
  `floor(4096 / columns)` rows per update. Chunking is cheap: 3 updates, 7 ms
  Companion-side, monotonic revisions on distinct surfaces or one surface
  re-pushed — the spike used distinct surfaces (`app:vault-N`) to keep each
  update independently valid.

**Consequence for RF-4a:** the carrier constraint that matters is not
`max_frame_bytes` but the presentation-node caps — which is itself the argument
that `ebp.data` changesets should NOT be presentation nodes. A `table` node is a
*view* of rows with a view's limits; the module's own changeset schema (RF-4a's
actual work) carries rows as data, subject to frame/event limits only, and this
spike's numbers say those are never binding at this scale.

## Limits

- Synthetic rows (privacy: public repo; vault content stays out). Byte-shape
  matched to the measured distribution; cell/span *counts* are exact by
  construction, which is what the caps care about.
- JVM timings on one machine, unrepeated; they answer "is accept cost material"
  (no — single-digit ms), not benchmarks.
- One span per cell. A rich-text projection (multiple spans per cell) hits
  `max_rich_spans` before `max_table_cells`; the binding cap flips but the
  chunking arithmetic is the same shape.
