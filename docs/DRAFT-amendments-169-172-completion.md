# DRAFT amendments #169–#172 — the completion ladder's wire half

Status: DRAFT, awaiting ratification. Nothing here touches SPEC.md,
contract.json, validate.py, or a golden until ratified.

Numbering: the ebp ledger on this line tops out at #168, whose own row
records that #153–#167 are reserved by sibling lines — these four take
#169–#172 under the same rule: renumber freely at ratification.

Provenance: these are the SPEC-amendment rungs of
`docs/PLAN-glasspane-completion.md` (R3 = #169, R4 = #170+#171,
R5 = #172), plus the exact fix for the R2 adversarial review's
provenance-forgery finding (#170). The no-SPEC rungs R0/R1/R2/R6 are
landed (7de24df, 0b4aa0a, 08ff61d, 2683690); everything below is the
part that needs wire vocabulary. Each amendment names its enforcing
tools and scopes (#150/#151 duty) and states its monotonic-resource
posture (#151 duty). All four are within protocol major 2.

Ratification order matters once: #170 before #171 (#171's relaxation
is safe *because* of #170's marker).

---

## #169 — §19.3 candidate `kind` (+ §22.4 feature `editor.candidate_kind`)

### Proposed ledger row

> **The candidate learns what it is.** §19.3's candidate is a closed
> object `{label, annotation?, insert?}` — closed is why the poc's
> `kind` member was dropped at the rewrite rather than carried, and the
> R3 rung needs it back: the device dropdown cannot draw a
> function/variable/keyword icon it is never told about, and every
> LSP-backed capf already knows. The candidate MAY now carry `kind`, a
> string from the closed 25-name vocabulary below. Because the
> candidate object is CLOSED, an older Companion must never see the
> member: `kind` is feature-gated as §22.4 `editor.candidate_kind`,
> sender rule when absent: omit the member from every candidate. The
> value vocabulary is closed at the SENDER (Emacs MUST send only
> registered names) while the RECEIVER degrades an unrecognized value
> to no icon and MUST NOT reject the reply — the #41/#145 pinned-safe-
> fallback shape, which is what lets the vocabulary grow additively
> later. Growth class 2 (cosmetic member), forced into feature-gating
> by candidate closedness.

### Normative text (§19.3, after the candidate-members sentence)

Current text amended:

> Each candidate MUST contain a non-empty string `label` and MAY
> contain string `annotation` and string `insert`; `insert` defaults
> to `label` and MAY be empty.

grows:

> When the target's profile advertises the `editor.candidate_kind`
> feature (Section 22.4), a candidate MAY additionally contain `kind`,
> a string naming the candidate's category from this closed sender
> vocabulary: `text`, `method`, `function`, `constructor`, `field`,
> `variable`, `class`, `interface`, `module`, `property`, `unit`,
> `value`, `enum`, `keyword`, `snippet`, `color`, `file`, `reference`,
> `folder`, `enum-member`, `constant`, `struct`, `event`, `operator`,
> `type-parameter`. Emacs MUST NOT send any other value and MUST omit
> the member entirely when the feature is absent. A Companion
> receiving a `kind` it does not recognize MUST present the candidate
> with no category decoration and MUST NOT reject the reply — the
> vocabulary grows additively, and an unrecognized value is a
> presentation gap, never an error.

Vocabulary provenance (informative, for the record): these are LSP
`CompletionItemKind` 1–25 in Emacs's own company-kind spelling —
verified at emacs-30.1 eglot.el:598-605 (`eglot--kind-names`) and
:3314-3317, where `EnumMember` and `TypeParameter` are special-cased
to `enum-member` and `type-parameter` and everything else downcases.
Emacs's harvest reads capf `:company-kind`, so LSP and non-LSP
backends alike produce exactly these symbols; the wire spelling equals
what the ecosystem already emits, and the projection from any LSP
server is lossless. The reference stays informative and the values
stay enumerated here (RATIFIED 2026-08-13): a version-pointer would
import external change control while the contract must enumerate the
values anyway to be validatable (#127), and external drift is ABSORBED
rather than tracked — a future LSP kind arrives as an absent `kind`
(eglot's own table is frozen at 1–25), renders undecorated, and joins
this vocabulary only through a one-row amendment under §25. LSP itself
grows this space the same way (closed set + `valueSet` advertisement +
graceful degrade).

### §22.4 feature row

| Feature | Constrains | Sender rule when absent |
|---|---|---|
| `editor.candidate_kind` | a §19.3 completion candidate carrying `kind` | omit the `kind` member from every candidate |

§22.4's lead sentence today scopes the registry to "constraining
features" (a construct an ignoring receiver would over-accept). `kind`
is not constraining — it is a cosmetic member an older CLOSED-object
receiver would REJECT. Two options:

- **Option A (RATIFIED 2026-08-13, Caleb):** widen §22.4's lead
  sentence by one clause — the registry also carries features that
  gate "a member an existing closed object cannot accept from an older
  receiver", with the same sender-omit discipline. One sentence, and
  the registry stays the single negotiation namespace (#88's
  reasoning: appended registry, never a new mechanism). The two
  registry genres and the growth model behind them are recorded in
  `docs/DECISIONS-wire-growth-model.md`.
- **Option B:** a §19.3-local negotiation sentence instead. REJECTED
  at ratification: it mints a second negotiation mechanism for one
  member, and every future compatibility-gated member would face
  copy-the-local-flag (proliferation) or use-§22.4-anyway
  (inconsistency).

### Duties, enforcement, deferrals

- Contract: `contract.json` candidate member registry += `kind` with
  the 25-value enum; `features` += `editor.candidate_kind`.
- validate.py (named tool, scope): walks the candidate enum — a reply
  fixture carrying an unregistered kind value MUST fail the corpus
  (the #127 lesson: a rail the validator does not walk is drift that
  survives three rungs).
- Goldens: one `edit.complete` reply frame carrying `kind` joins the
  editor golden (coverage floor).
- Kotlin: SpecValidator accepts the member + enum; **the dropdown icon
  render is DEFERRED to the R3 implementation rung and named here** —
  "a wire member is not implemented because the validator accepts it"
  is this project's six-times-recurred defect, so the rung's device
  gate MUST include a does-the-chrome-DRAW-it check, not a validator
  check.
- Emacs: the harvester emits from `:company-kind` only when the
  feature is advertised (welcome-gated, the sender-omit rule); pin
  test on the omit path.
- Monotonic resources (#151): none introduced; the vocabulary is a
  fixed closed set whose growth path is a future amendment.

---

## #170 — §19.3 `edit.delta` provenance member `accept`

### Proposed ledger row

> **The tap says it was a tap.** §19.3 makes a candidate selection an
> ordinary local edit — the wire deliberately carries no provenance —
> and the R2 adversarial review demonstrated what that costs now that
> Emacs finishes completions (exit functions, auto-import): the accept
> must be INFERRED from splice shape, and the shape is forgeable.
> Paste, glide typing, voice input, and IME word commits each replace
> the composing text in one splice; an empty-prefix offer (legal LSP
> member completion) degrades the shape to a bare insertion that
> anything can produce. The landed Emacs-side mitigation
> (provenance-by-shape: the deleted prefix and inserted text must
> share an end scalar, which the Companion's minimal diff could never
> emit) closes the forgery classes at the cost of missing rare
> flex-matched taps and ALL empty-prefix taps. The exact fix is one
> optional boolean: the `edit.delta` a Companion sends for a §19.3
> candidate selection MUST carry `accept: true`; a delta for any other
> local edit MUST NOT carry the member (omitted, never `false`). This
> is provenance, not coordinate authority — the splice applies
> identically with or without it, and Emacs MAY still shape-check as
> defense in depth. Presence-only is ratified on its surviving legs
> (2026-08-13): a required boolean would ride EVERY keystroke delta —
> the wire's hottest frame — to encode a rare event, and a tri-state
> mints two spellings of "not a tap" that validators must equate; that
> an older Emacs also happens to ignore the member is a corollary, not
> the goal (backward compatibility is not a PoC goal — recorded).
> Growth class 2 (optional member on an existing notification's
> params, which are not a closed object).

### Normative text (§19.3, the selection paragraph)

Current text:

> If they do, it MUST replace that prefix with `insert` as one local
> edit, advance the sequence, and send the corresponding `edit.delta`.

becomes:

> If they do, it MUST replace that prefix with `insert` as one local
> edit, advance the sequence, and send the corresponding `edit.delta`,
> which MUST carry `accept: true`. An `edit.delta` for any local edit
> that is not a §19.3 candidate selection MUST NOT carry the `accept`
> member — omitted, never `false`, so the member's presence IS the
> assertion. Emacs MAY use the assertion to run completion-finishing
> side effects and MAY additionally verify the splice has the
> selection's replacement shape; it MUST apply the splice itself
> identically whether or not the member is present.

### Duties, enforcement, deferrals

- Contract: `edit.delta` params += `accept` (boolean, optional).
- validate.py (named tool, scope): accepts the member on `edit.delta`
  and rejects it on every other method's params (a provenance member
  that leaks onto `edit.apply` would invert its meaning).
- Goldens: one accept-carrying `edit.delta` joins the editor golden.
- Kotlin: `selectCompletion` is the SINGLE emitter (verified in the R2
  review: CompanionEngine.kt:1919-1932 vs the Renderer diff path) —
  it stamps the member; the typed path cannot, by construction.
  **THE FUNNEL RULE (ratification condition, 2026-08-13):** every
  accept emission MUST flow through this one funnel forever — a future
  accept gesture (Enter-accepts-top, a pie accept) calls it, never
  re-implements the splice-and-stamp. The one-call-site thesis is this
  project's most-recurred defect (6×), and the funnel is the seam that
  prevents its recurrence here. Wire tests PIN both directions: the
  tap path carries the member; a typed-path delta never does — so a
  second unstamped emitter fails a named test instead of shipping.
  Deferred to the implementation rung, named.
- Emacs: `ebp-sync--maybe-finish-completion` prefers the marker when
  present and KEEPS the shape check — the last seam: even a future
  unstamped accept degrades to today's inference, never to silent
  nothing.
- Monotonic resources (#151): none.

---

## #171 — §19.3 selection survives a typed prefix extension

### Proposed ledger row

> **The offer survives typing.** §19.3's selection gate — session,
> sequence, cursor, and prefix "still match", else "MUST discard" —
> means every keystroke clears the dropdown, because a keystroke
> advances the sequence. POC 1's strongest UX ingredient was exactly
> the opposite: the list stayed up and narrowed locally while the user
> typed, and a tap landed against the extended prefix, hiding the
> round-trip entirely. That behavior is nonconformant under the
> current gate. The gate now admits one precisely-bounded divergence:
> selection MAY proceed when every sequence step since the offer was a
> LOCAL insertion at the caret extending the offered prefix (each
> intervening splice: `del` 0, at the then-current cursor), the
> extended prefix is a Unicode-scalar prefix of the candidate's
> `label` or of its `insert`, and the selection then replaces the
> EXTENDED prefix with `insert` — in one local edit, sequence
> advanced, `accept: true` (#170). Any other divergence — a remote
> splice, a deletion, an edit away from the caret — still discards.
> This relaxes a receiver-side MUST within major 2 (the #89 genre:
> pinning apply semantics both readings left divergent), and the
> no-harm argument is exact: Emacs receives an ordinary marked delta
> whose splice replaces a prefix that really is on its mirror —
> indistinguishable from a fast tap under today's rules. Requires
> #170; without the marker, widening the legal accept shapes would
> widen Emacs's inference surface, which is the R2 review's finding in
> reverse.

### Normative text (§19.3, replacing the discard sentence)

Current text:

> If they do not, it MUST discard the result without changing text and
> MAY issue a new completion request.

becomes:

> If they do not, it MUST discard the result without changing text and
> MAY issue a new completion request — with one exception. Selection
> MAY proceed against a PREFIX EXTENSION: when every sequence advance
> since the reply was a local insertion at the caret extending the
> returned prefix, and the extended prefix is a Unicode-scalar prefix
> of the candidate's `label` or of its `insert`, the Companion MAY
> treat the selection as valid, replacing the extended prefix with
> `insert` as one local edit, advancing the sequence, and sending the
> corresponding `edit.delta` with `accept: true`. Every other
> divergence — an applied remote splice, a deletion, any local edit
> not at the caret — MUST still discard. A Companion narrowing its
> presented candidates against the extension (dropping candidates the
> extension no longer prefixes) is presentation and needs no rule.

### Open sub-decision for the owner

POC 1 narrowed by `startsWith` on the label but by `contains` on
insert-carrying candidates. The draft proposes **strict prefix only**
(label or insert): substring matching would let a tap rewrite text
that no longer visibly relates to what the user typed, and a missed
flex-narrowing tap costs one extra round trip, not correctness. Say
the word if v1's contains-behavior should be kept instead.

### Duties, enforcement, deferrals

- Contract/validator: no shape change (the relaxation is receiver
  prose; the resulting delta is #170's shape). validate.py scope
  unchanged, stated per #150.
- Kotlin: the Renderer keeps the offer across qualifying keystrokes
  and narrows locally; `selectCompletion` validates the extension rule
  before emitting. Deferred to the R4 implementation rung with its
  device gate (latency feel is the point; only hardware shows it).
- Emacs: no change required — #170's marker plus the existing splice
  handling already accept the resulting delta. The R2 shape-check
  fallback intentionally does NOT recognize extension-accepts from
  pre-#170 Companions; that combination cannot occur (both land
  together on the Companion).
- Monotonic resources (#151): none.

---

## #172 — `edit.candidate.doc`: lazy per-candidate documentation

### Proposed ledger row

> **Documentation for the highlighted candidate, on demand.** Neither
> POC carried per-candidate docs, and eager docs would be the wrong
> shape: N doc strings per reply on a phone screen that shows one at a
> time, against the §4.5 frame budget. LSP's own answer is lazy
> (`completionItem/resolve` enriches only the item the user is
> looking at — mirrored deliberately). A new Companion-sender request
> `edit.candidate.doc` `{document, editor_id, session, seq, index}`
> returns `{doc}`: plain text (§16.4 discipline — never markup, never
> an executable format), possibly empty, for the `index`-th candidate
> (0-based) of the most recent `edit.complete` reply of that session
> and sequence. A session/sequence mismatch is `1201` `editor-stale`
> exactly as `edit.complete`; an index outside the last reply is
> `1201` `content-invalid`. Emacs SHOULD cap `doc` at 16384 UTF-8
> octets; a Companion SHOULD keep at most one `edit.candidate.doc`
> outstanding per session — the highlighted row changed, the old
> answer is moot. `READY` only, gated on `editor.sync` like the rest
> of §19. Growth class 2 (new optional core method); a Companion that
> never sends it and an Emacs that answers empty are both fully
> conformant.

### §11 registry row

| Method | Sender | Class | State | Capability | Section |
|---|---|---|---|---|---|
| `edit.candidate.doc` | Companion | request | `R` | `editor.sync` | 19 |

### Normative text (§19.3, after the selection paragraph)

> `edit.candidate.doc` is a request containing `document`,
> `editor_id`, `session`, `seq`, and `index`. It asks for
> documentation of the `index`-th candidate (0-based) of the most
> recent `edit.complete` result Emacs produced for that session and
> sequence. Its result is `{"doc": string}` — plain text under §16.4's
> presentation discipline, and MAY be empty when no documentation
> exists. Emacs MUST answer only when the session and sequence match
> (`1201` with `data.reason: "editor-stale"` otherwise, exactly as
> `edit.complete`) and MUST answer `1201 content-invalid` for an
> `index` outside that result. Emacs SHOULD cap `doc` at 16384 UTF-8
> octets; a cap MUST truncate at a Unicode-scalar boundary at or below
> the limit — an octet cut mid-scalar is not a string. A Companion
> SHOULD keep at most one such request outstanding per session and
> SHOULD request documentation only for a candidate it is presently
> highlighting — the method exists to be lazy. (Informative: volume
> needs no pagination here. A longer rendering, if ever wanted, is an
> additive `offset` param under §25 — or, better, a full document is
> what `surface.update` and the buffer machinery already exist to
> show; the peek method never becomes a transport for manuals.)

### Duties, enforcement, deferrals

- Contract: `methods` += `edit.candidate.doc` (full-schema duty:
  params and result, both typed).
- validate.py (named tool, scope): per-method coverage floor requires
  one `edit.candidate.doc` frame in `frames.golden` (the #152
  mechanism); the result schema is walked.
- Kotlin: `MethodRegistry` += row (the cross-implementation pin);
  the doc-panel render and the highlight-driven request are DEFERRED
  to the R5 implementation rung, named here — the panel is chrome, and
  the dispatch-audit lesson applies to it as to every wire member.
- Emacs: answers from the retained last-reply state that the R2 offer
  machinery already holds (candidate strings with their text
  properties — eglot's doc comes from `:company-doc-buffer` or a
  resolve against the propertized item). Harvest errors degrade to
  `{"doc": ""}`, never `-32603` — the `edit.complete` discipline.
  §23.3: doc text derives from user/server content; it goes on the
  wire as a result body and MUST NOT be logged, same as every body.
- Monotonic resources (#151): none — `index` addresses only the most
  recent reply, whose retention lifetime the offer machinery already
  bounds (superseded by the next request, claimed by any session
  event); no new identifier space, no new retention window.

---

## Open questions for ratification

1. ~~**#169 option A vs B**~~ — **RATIFIED 2026-08-13: Option A**,
   with the vocabulary enumerated in-document (no version pointer) and
   the LSP reference informative. #169 is fully ratified.
1b. **#170 RATIFIED 2026-08-13** with the funnel condition: presence-
   only boolean on its surviving rationale (hot-path cost + no dead
   states; compat demoted to corollary), all accept emissions through
   the single `selectCompletion` funnel, pins in both directions,
   Emacs shape check retained as the last seam.
2. **#171 matching policy** — strict prefix (drafted) vs POC 1's
   contains-on-insert?
3. **#172 doc cap** — 16384 octets is proposed; any preference?
4. **Numbering** — #169–#172 assumed; renumber freely.
5. **Sequencing** — ratify #170 alone first if R2's forgery fix should
   ship ahead of the UX rungs; #169 and #172 are independent of each
   other and of #170/#171.
