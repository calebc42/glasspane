# spike-elisp — vulpea → flat rows (throwaway)

**This directory is a measurement instrument, not a feature.** It is scheduled by
[PLAN-refound-2026-07-28.md](../../docs/PLAN-refound-2026-07-28.md)'s data-spike rung
and exists to produce one number. It has no callers in the base, is required by
nothing, and is deleted when the number is recorded.

Written before the first line of code, per the rung's discipline clause — this tree
already carries two "staging, never required by base" arms that outlived their
welcome, and the countermeasure is to write the exit down first.

## The load-bearing question

> What fraction of a real vault's projection exceeds `max_frame_bytes`
> (`ebp/SPEC.md:247` — exactly `4194304`), and what does elisp-side JSON encoding
> actually cost?

That number decides whether RF-4a's reserved bulk carrier is ever specified
(PLAN-refound Decision 9: *do not specify an optimization before measuring the
need*). A vault that fits in one frame with margin means the bulk carrier stays
unspecified and `ebp.data` ships inline changesets only.

## Secondary questions

1. **Cost shape.** Projection time vs `json-serialize` time — is encoding the
   bottleneck, or is walking vulpea?
2. **Row-size distribution.** Is the total dominated by a long tail of large notes
   (which a per-note chunking strategy handles) or spread evenly (which it does not)?
3. **Bracket.** Minimal row (id/title/todo/tags) vs full row — how much does
   projection richness cost, so RF-4a knows what it is buying.
4. **Extrapolation.** At the measured bytes-per-note, how many notes would it take to
   exceed one frame? That is the number a future large-vault user cares about.

## Constraints this must respect (from orgseq's model header)

Verified in `~/pkb/projects/jetpacs-orgseq/orgseq/jetpacs-orgseq-model.el` — note
the path: that file is in a **separate repo**, not this one. Both
`docs/AUDIT-plan-spec-adversarial-2026-07-31.md` and PLAN-refound cite it as
`emacs/jetpacs-orgseq-model.el`, which does not resolve; correcting that is part of
this rung's record.

1. **DB titles are display-formatted**, so "the DB drives search, references, and
   queries; the file drives page rendering". A projection must therefore declare
   DB-vs-file provenance rather than implying its titles are the file's text.
2. **Every mutation runs `save-buffer` + a synchronous `vulpea-db-update-file`**
   (via `vulpea-utils-with-note-sync`). Any future change-capture rides that write
   path; the spike must not assume a quieter one.

## Kill criteria

Stop and record what is known if any of these hold:

- Producing the projection would require editing anything under `ebp/`, any Kotlin,
  or vulpea itself. The rung's boundary is `emacs/` + `test/`; a spike that needs
  more has answered a different question than the one asked.
- The vault cannot be read in batch mode without the user's full interactive config.
  (Then the measurement is about their init, not about the wire.)
- The answer is unambiguous early — e.g. the whole vault is an order of magnitude
  under one frame. **Stop there.** The number's job is a yes/no on the bulk carrier,
  not a benchmark suite.
- One sitting. If it is not measurable in one, record the partial and stop.

## Removal

The spike is deleted in a single named commit once the number is in PLAN-refound:

```
git rm -r emacs/spike
# spike(elisp): remove — measurement recorded in PLAN-refound RF-4a
```

Nothing in `emacs/`, `test/`, `companion/`, or `ebp/` may come to depend on this
directory. If something does, that is the signal that it stopped being a spike and
needs its own rung.

## Scope

- Touches `emacs/spike/` only. Zero Kotlin. Zero `ebp/` (the I1 window is open —
  RF-2b is mid-conversion on branch `rf-2b`).
- Branch: `spike/elisp-vulpea-rows`, cut from `slop-fork/main`.
- Reads the live vault read-only. Writes nothing to the vault or to `vulpea.db`.
