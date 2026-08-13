# The wire growth model: cosmetic × constraining, open × closed

Status: design rationale, informative. Ratified as the working growth
algorithm 2026-08-13 (Caleb, during the #169 ratification dialog).
Slop-line text — facts and ideas may cross into the hand-written spec;
sentences may not (the quarantine-the-quarry rule).

## The root question

Every growing protocol must answer: what does a receiver do with
vocabulary it does not understand? There are only two postures —
IGNORE-unknowns (open: process what you recognize, drop the rest) and
REJECT-unknowns (closed: refuse the whole construct) — and neither is
universally correct. Which one is safe depends on the semantic role of
the unknown member.

## The member taxonomy

A COSMETIC member decorates the base behavior without changing what
happens (`annotation`, an icon hint, candidate `kind`). Ignoring it
costs polish; the same action occurs.

A CONSTRAINING member narrows or guards the base behavior (`when:
battery < 20%` on a notify; `confirm` on a delete; a `ttl_s` bound; a
trigger predicate). Ignoring it makes the receiver do MORE than the
sender authorized: "notify below 20%" becomes "notify always" (the
when-strip hazard); "delete with confirmation" becomes "delete now" —
which happened live on hardware (the JA-6 device gate: the Companion
accepted `confirm` and never presented it; the first trash tap
destroyed the file).

## The failure asymmetry

|  | Cosmetic member unknown | Constraining member unknown |
|---|---|---|
| Ignore-unknowns | fine (plainer UI) | OVER-ACCEPT: silent, invisible, harmful — the guard evaporates |
| Reject-unknowns | OVER-REJECT: whole frame refused over a decoration | fine (loud `1201`, sender learns, nothing runs unguarded) |

Over-accept is the catastrophic direction because it is invisible.
Over-reject is the annoying direction but loud and recoverable. This
asymmetry is invariant 7 ("safe under partial understanding") made
operational: a receiver that does not fully understand must end up
doing LESS, never more. Rejecting does less. Stripping a guard does
more.

## The mechanism map

Because a receiver cannot tell cosmetic from constraining by looking
at an unknown member NAME, EBP's default posture for object SHAPE is
closed — candidates, trigger params, and descriptors reject unknown
members (§19.3, §21, §14.1), which also keeps the deliberately weak
languages finite and auditable (invariant 6). Selected VALUE spaces
stay open-with-degrade where the degrade is provably harmless: an
unknown icon name renders a placeholder (§17.2), an unknown `features`
entry is ignored (§22.4), an unknown snippet token stays literal
(§17.7).

§22.4's feature registry exists for the case neither default handles:
vocabulary the sender MUST NOT emit until the receiver has advertised
it. The receiver-side rule skip-don't-strip (if you cannot honor the
guard, do not do the guarded thing) and the sender-side rule (do not
send the guarded thing to a receiver that cannot honor it) are two
halves of one law; the registry is the sender half's mechanism.

## The 2×2 and its precedents

Member role × object posture:

1. **Cosmetic on an open value space** → degrade rules. Precedent:
   #41 (pinned safe fallback), #145 (accessible-label derivation
   floor), §17.2 icon placeholder.
2. **Constraining anywhere** → §22.4 negotiation + sender-omit.
   Precedent: the registry's founding rows; #88 (registry as the
   designated home, appended never inserted).
3. **Load-bearing growth of a closed object** → amendment updating
   both ends together. Precedent: #168 (`confirm` object form), #135.
   Honest caveat: this cell's precedents never actually negotiated —
   they shipped both endpoints simultaneously, a luxury that ends when
   second implementations exist (the publication goal).
4. **Cosmetic member on a CLOSED object** → the closedness converts
   "harmless to ignore" into "fatal to send", so a cosmetic member
   needs the same sender-withholds machinery as a constraining one —
   for the opposite reason (loud over-reject instead of silent
   over-accept). First instance: #169 candidate `kind`, which widens
   §22.4's lead sentence to name both genres.

## The growth algorithm

For any proposed wire vocabulary: classify the member (cosmetic /
constraining), check the hosting object's posture (open / closed), and
the 2×2 names the mechanism. If the answer requires a NEW mechanism,
stop — that is the rewrite-criterion smell ("a load-bearing seam is
wrong"), and so far every case has landed in an existing cell.

Corroboration from the ecosystem: LSP handles its own
CompletionItemKind growth identically — closed base set (1–25 frozen),
client advertisement (`valueSet`), and a graceful-degrade guarantee
for values outside it (LSP 3.18, completion.md ClientCompletionItemOptionsKind)
— independent convergence on cell-4 mechanics.

## Enforcement duties that ride every cell

- #127: a rail the validator does not walk is drift that survives —
  every new member/value lands in contract.json AND validate.py in the
  same change.
- #150/#151: name the enforcing tool and its exact scope; state the
  monotonic-resource posture.
- The dispatch-audit lesson (6× recurred): "the validator accepts it"
  never means "the chrome dispatches/draws it" — every new member's
  implementation rung carries a does-the-chrome-USE-it device check.
