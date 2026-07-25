# EBP audit — Opus verification pass (complete)

**Run:** 2026-07-24, resume of `wf_0260ae90-308` on Opus. **355 agents, 0 errors,
every finding verified** (the Fable run had died on a spend limit with 305
unverified). Verified against the **post-amendment** spec (amendments #67–#79
applied), so findings the new amendments close are retired here.

## Totals

| | count |
|---|---:|
| deduped findings | 312 |
| **confirmed** | **132** (P1 5, P2 101, P3 26) |
| contested (verify CONFIRMED, skeptic REFUTED) | 3 |
| refuted / covered | 177 — of which **REFUTED 117, ALREADY_SPECIFIED 40, DUP_AMENDMENT 20** |
| unverified | 0 |

## The applied P2 amendments (#67–#79) are validated

**20 findings were retired as `DUP_AMENDMENT` citing the just-applied amendments,
and every one of #67–#79 was cited at least once** (#68 five times, #69/#70/#76/#77
twice each, the rest once). Another 40 were `ALREADY_SPECIFIED` (the Fable finders
over-reported holes existing text already closed) and 117 were genuinely refuted.
Residual confirmed holes remain in some amended sections (e.g. §18.6 still has
`at_ms` clock semantics, two-`reminders.set` ordering, and "cancel removed
reminders" scope) — but these are **separate adjacent holes**, not failures of the
applied fix.

## The P1 picture, reconciled against the seven P1 drafts

Opus's skeptic pass is stricter than the hand-verification. **Five P1s confirmed
(all skeptic-upheld); two of the seven drafts were knocked down.**

| Draft P1 | Verdict | Disposition |
|---|---|---|
| integer-ID residue (§4.2/§7.5) | **CONTESTED → editorial** | Stale text is real, but §7.2 (blesses jsonrpc.el integers) + §7.5 "exact ID" + §4.3 equality make behavior correct. A Companion rejecting an integer ID is *non-conformant*, so no two-conformant divergence. Worth an **editorial (P3)** fix, not P1. |
| queue-disposition wedge (§14.4/§15.3) | **CONTESTED → refuted (non-hole)** | The partition already exists: §7.3 routes *structural* invalidity to `-32602` (before the handler); §14.4 routes *semantic* invalidity of a schema-valid event to `rejected`/`stale`. Disjoint and exhaustive. My proposed "always `rejected`, never JSON-RPC error" would *contradict* §7.3. **Discard.** Deferring #68 was the right call. |
| tile:* variant (§13.4) | **CONFIRMED P1** | Deferred for the QS-tile implementation (near). Still open. |
| editor doc unboundable (§19.4) | **CONFIRMED P1** | Ready to apply as-drafted. |
| `selected` boolean-vs-date (§17.1/§17.5) | **CONFIRMED, downgraded to P2** | Real, but severity P2 (a validator wrongly rejecting a `month_grid`), not P1. Draft still valid. |
| §10.3 flush `revision_seen` (§10.3) | **CONFIRMED, downgraded to P3** | Editorial contradiction only; the deeper §14.6 SYNCING-corruption concern (id 269) was **refuted** — three guards (§13.6 reset-clear, etc.) forbid the resurrection. |
| `occurred_at_ms` clock (§15.2) | **CONFIRMED P1** | Ready to apply as-drafted. |

**Two NEW P1s Opus confirmed that were never drafted:**

1. **§14.1 — wake authored without the `offline.wake` grant has no receiver rule.**
   Sender-only ban; §5.3 gates the wake *signal* on persistent per-pairing target
   config, not the session grant — so a Companion with a configured target from a
   prior session could durably admit and OS-signal a wake the current session never
   negotiated. Security-relevant. *Fix:* a `wake` descriptor without the current
   grant MUST be rejected with its document, or treated exactly as `queue` with no
   signal; gate the signal on the grant, not just target config.

2. **§17.2 — fetched image bytes: cache license, offline use, revocation erasure
   undefined.** §9.1's revocation-erasure list doesn't naturally include a
   URL-keyed image disk cache, so a Companion can retain personal photos after
   revocation while another wipes them — the exact data-protection-boundary genre
   of amendments #48/#49/#72/#78, unaddressed for images. *Fix:* state whether
   fetched image content may persist, scope it to the pairing identity, add it to
   §9.1's erasure list, and say whether a cached image satisfies §13.5 offline
   rendering.

**Current confirmed-P1 set (5):** tile (deferred), editor-bytes (ready),
occurred_at_ms (ready), wake-without-grant (new), image-cache (new).

## The 101 confirmed P2 — the next backlog

Heaviest: **§17 (21)**, **§21 (15)**, **§18 (11)**, §4/§10/§13/§14 (6–7 each). The
recurring genres dominate: unknown-value fallbacks (chart.kind, theme values,
annotation severity), unpinned clocks (staleness, at_ms, every_s, throttle),
undefined gestures/affordances (on_submit trigger, collapsible toggle, swipe
completion), coordinate/rendering spaces (canvas origin/clipping, on_point_tap),
and cross-artifact drift (`month` yyyy-mm vs display string). Full list in the
run journal.

## Critic — audit blind spots worth a follow-up round

- **Hub tables §8 / §11 / §24 got ZERO findings** — no cross-reference-integrity
  lens traversed hub-to-callsite links (does §24.1's method list equal §11's
  registry? does every §8 code have a call site? is the 1201-vs-`-32602` boundary
  applied consistently?). This is the single most actionable gap.
- **§19 editor** lowest density despite a full session state machine; **§9/§23**
  (highest-stakes crypto/security) had no dedicated threat-model lens.
- The audit read SPEC.md largely in isolation; a spec-vs-artifact reconciliation
  (contract.json, goldens, reference impl) would catch more drift.

## Recommended next steps

1. **Apply the two ready P1 drafts** (editor-bytes §19.4, occurred_at_ms §15.2) and
   **draft the two new P1s** (wake §14.1, image §17.2).
2. **Downgrade-and-apply** `selected` (P2) and `revision_seen` (P3 editorial);
   **rewrite** integer-ID as an editorial (P3) amendment; **discard** the
   queue-disposition draft.
3. **Batch the 101 P2s** the way #67–#79 were batched — most are one-line prose in
   the ratified genres.
4. **Run a targeted follow-up** on §8/§11/§24 cross-reference integrity and a
   dedicated §9/§19/§23 lens (the critic's gaps).
