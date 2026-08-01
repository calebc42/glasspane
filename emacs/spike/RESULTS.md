# spike-elisp results — 2026-07-31

Raw record. The durable finding lives in
[PLAN-refound-2026-07-28.md](../../docs/PLAN-refound-2026-07-28.md); this file dies
with the spike directory.

## Vault measured

Live `~/.emacs.d/vulpea.db` (1.75 MB), read-only: **586 notes across 8 files**
(39 files indexed; 8 contain notes). Vault root `~/pkb/resources/`. Skewed —
`sovereignty-stack.org` alone holds 505 of the 586 notes.

Run: `emacs -Q --batch -l emacs/spike/jetpacs-spike-rows.el -f jetpacs-spike-report`

## The answer

`max_frame_bytes` = **4,194,304** (SPEC 4.5, fixed).

| Projection | Total | % of ONE frame | Rows over a frame | Notes to fill a frame |
|---|---|---|---|---|
| Minimal row (id/title/todo/tags/level) | 105,383 B (103 KiB) | **2.51%** | 0 | ~23,455 |
| Full row (every struct scalar + properties) | 307,737 B (301 KiB) | **7.34%** | 0 | ~8,002 |
| *Bound:* every org file's raw source | 458,191 B (447 KiB) | **10.9%** | — | — |

**The whole vault — metadata projection and every byte of org source together —
is under 20% of a single frame.** Not one row comes near the limit.

## Secondary questions

- **Cost shape.** `json-serialize` is **not** the bottleneck: 1.1 ms of the 8.4 ms
  full-row pass (12.7%). Walking the vulpea structs dominates. The elisp-side
  encoding cost the rung worried about is negligible at this scale.
- **Distribution.** No long tail. Full row: p50 528 B, p95 581 B, max 679 B — a
  1.3× spread from median to max. The total is small because every row is small,
  not because outliers were excluded. A per-note chunking strategy would have
  nothing to chunk.
- **Bracket.** Projection richness costs ~2.9× (179 → 524 B/note) between "what a
  list view needs" and "every scalar the struct carries". Even the rich end leaves
  13.6× headroom.
- **Extrapolation.** A vault needs roughly **8,000 notes** before its full-row
  projection fills one frame — an order of magnitude past this one, and changesets
  are incremental anyway, so the whole-vault figure is the pessimistic case.

## Limits of this measurement — read before citing it

1. **One vault, and a skewed one.** 586 notes, 86% of them in a single file. The
   per-note figures are sound; the whole-vault total is one sample.
2. **vulpea indexes metadata, not content.** The note struct carries no body/text
   field, so the projected rows are title/tags/todo/dates/properties. Body text was
   measured **separately as a bound** (raw file bytes), not projected. If RF-4a's
   schema ever carries body text per row, re-measure — that is the one change that
   could move this answer.
3. **The row shapes are the spike's design, not RF-4a's schema**, which does not
   exist yet. They bracket a plausible range; they are not the contract.
4. Timings are one batch Emacs on one machine, unrepeated. They are reported to
   answer "is encoding the bottleneck" (no), not as a benchmark.
