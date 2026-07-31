# DRAFT amendments #140–#152

Drafted 2026-07-31 against `ebp/SPEC.md` @ `06fd9cd` (amendments through **#139**).
Source audit: `docs/AUDIT-plan-spec-adversarial-2026-07-31.md` (SPEC-half findings and
appendix leads; anchors hand-verified in text).

**These are drafts for ratification, not applied edits.** Each gives the
`SPEC-CHANGES.md` row, the exact `SPEC.md` edits, and artifact changes.

Ratification order: **#142, #144, #148, #150, #151** (no design decision), then the
eight that need a shape call — suggested order **#152, #143, #147, #140, #141, #149,
#145, #146** (wire-visible divergences first, honest re-scopes last).

---

## #140 — the effective-clock ratchet is unbounded forward (§15.2)

**⚠ Design decision required: how far to trust a single forward wall-clock step.**
Two candidates; A is drafted, B is the deeper alternative.

**SPEC-CHANGES row (option A):**

> | 140 | 2026-07-3X | §15.2 (cross-ref §21.2, precedent #47, #81) | **The effective clock's forward ratchet is bounded and corroborated.** §15.2's effective wall clock — the greater of the current wall clock and a durable per-pairing high-water mark, with "the Companion MUST advance that mark when time moves forward" — protects expiry against rollback (#81's fix) but trusts every forward reading absolutely. A transient forward glitch (a bad NITZ/NTP sample, a user experiment with the clock) ratchets the mark irrevocably: at the glitch instant every queued event whose remaining `ttl_s` does not reach the false future is deleted before delivery, silently; after the user corrects the clock, the effective clock is pinned at the false future, so no surviving or newly admitted event ages at all until real time catches up — expiry is first mass-triggered, then disabled, both without a diagnostic. The correct technique is already in-spec: §21.2's throttle rule distrusts wall-clock movement in both directions ("monotonic elapsed time while running and conservative persisted wall time across restart"). The mark now advances beyond genuinely elapsed time only after the new reading is corroborated — it persists across 60 seconds of monotonic elapsed time — and MUST NOT lead the current wall clock by more than 604800 seconds (the maximum legal `ttl_s`), clamping on first observation past that bound. Restricting for a Companion that ratcheted instantly on any reading; rollback protection is unchanged. | none (prose) | |

**SPEC.md edits (option A):**

- §15.2, replace:
  > The Companion MUST advance that mark when time moves forward; clock rollback
  > MUST NOT extend an event's lifetime.

  with:
  > The Companion MUST advance that mark as time genuinely passes; clock rollback
  > MUST NOT extend an event's lifetime. A forward wall-clock step beyond the
  > monotonic time elapsed since the previous reading is a *claim*, not a fact:
  > the Companion MUST NOT advance the mark past genuinely elapsed time until the
  > stepped reading has persisted for 60 seconds of monotonic elapsed time, and
  > MUST NOT let the stored mark lead the current wall clock by more than 604800
  > seconds — on observing a lead beyond that bound it MUST clamp the mark to the
  > current wall clock plus 604800 seconds. This is Section 21.2's throttle
  > discipline applied to the queue's clock: wall-clock movement in either
  > direction is never trusted beyond what monotonic elapsed time corroborates.

**Option B (deeper):** account each event's remaining lifetime directly in monotonic
elapsed time while running plus conservatively persisted wall time across restart
(§21.2 wholesale), demoting the effective clock to a cross-restart floor. Subsumes A
and also fixes multi-restart glitch accumulation, but restructures §15.2's expiry
predicate and the #81 stamping rule rather than bounding them.

**Recommendation: option A.** Minimal edit, convictable ("60 seconds", "604800
seconds" are testable), preserves #81's machinery verbatim. B is the shape a future
major revision should adopt.

---

## #141 — surface-ID floors are non-reclaimable, and the only remedy destroys everything (§13.1)

**⚠ Design decision required: the release mechanism's grain.** Two candidates; A is
drafted.

**SPEC-CHANGES row (option A):**

> | 141 | 2026-07-3X | §13.1, §11, §22.1 (cross-ref §9.1, §24.6 item 7, precedent #107) | **`surface.release` — an explicit floor-retirement path.** §13.1 makes every distinct surface ID a permanent charge against `max_surface_ids`: floors are retained "until pairing revocation", #107 extended that survival through re-validation failure, and no release mechanism exists anywhere — so the ID space is a monotone resource whose only reclamation (§9.1 revocation) also destroys the durable queue, reminders, triggers, and the pairing itself. An Emacs that churns IDs — a bug, or an application pattern such as per-document surfaces — permanently exhausts the pairing's surface capacity, after which every new ID draws `1201 surface-limit` forever. A new Emacs-sender request `surface.release {surface}` retires a *tombstoned* surface's history and floor: the Companion deletes the tombstone and its floor and returns `{released: true}`; releasing a *present* surface is invalid (remove first — release is deliberate, two-step). Emacs MUST NOT reuse a released ID expecting stale-protection: by releasing, Emacs asserts it has no outstanding update for that ID, and a later reuse starts a new history at floor −1 — the Section 24.6 item 7 race is Emacs's to avoid for exactly that ID, which is why release is an explicit request and never implicit reclamation (the #107 rule stands for everything not explicitly released). Additive: a new optional method, discoverable via the method registry; no previously valid message changes meaning. | contract §11 registry entry + method schema; goldens: release round-trip + release-of-present rejection; validate.py method-registry sync | |

**SPEC.md edits (option A):**

- §13.1, after "…MUST NOT reclaim it merely to admit a reused or new ID." — append:
  > The only reclamation is explicit: `surface.release` (below). A Companion MUST
  > NOT reclaim a floor on any other trigger.

- §13.1, new sub-heading `surface.release` (schema + the rules from the row above);
  §11 registry gains the row `| surface.release | Emacs | request |` with legal
  states `READY`.

**Option B (coarse):** `surfaces.reset` — one request atomically discards *all*
floors, tombstones, and present surfaces (Emacs re-pushes everything, as after a
fresh pairing, but queue/reminders/triggers/pairing survive). Simpler to specify and
to test, but it turns one leaked ID into a full re-push and cannot be used while any
surface must stay live.

**Recommendation: option A.** The race #107 guards against is per-ID and
Emacs-authored; a per-ID, Emacs-initiated release matches the authority that holds
the information. B remains a reasonable additional escape hatch for a later batch.

---

## #142 — the capture arithmetic can exceed the event budget at the REQUIRED minimums (§4.5)

**SPEC-CHANGES row:**

> | 142 | 2026-07-3X | §4.5 (cross-ref §14.1, §15.1) | **The capture budget inequality, stated.** §4.5's REQUIRED minimums allow `max_capture_fields` (64) × `max_field_bytes` (65536) = 4194304 bytes of captured input — sixteen times `max_event_bytes`' floor (262144) and equal to the whole frame cap — and no rule says what happens when a legal ActionDescriptor's capture assembles an `event.action.params` that exceeds `max_event_bytes`. §4.5 already states exactly this kind of inequality for event-vs-frame ("An `event.action` sender MUST encode the fixed envelope outside `params` in no more than 256 UTF-8 octets. Together with the upper bound above, this guarantees that an allowed event also fits `max_frame_bytes`"); the capture dimension was left out. The section now states that the per-dimension caps do not compose into an admission guarantee: `max_event_bytes` is the binding budget at capture time, and a capture whose assembled params would exceed it MUST NOT create the event, MUST NOT truncate any captured value, and MUST present a visible diagnostic exactly as §15.1 requires for queue-capacity exhaustion. Clarifying prose resolving an undefined receiver duty; no limit value changes. | none (prose) | |

**SPEC.md edits:**

- §4.5, after "Together with the upper bound above, this guarantees that an allowed
  event also fits `max_frame_bytes`." — insert:
  > The capture dimensions carry no such guarantee: `max_capture_fields` ×
  > `max_field_bytes` may exceed `max_event_bytes` at the REQUIRED minimums. These
  > are per-dimension caps, not a composed admission promise; the binding budget
  > for an assembled `event.action.params` is `max_event_bytes`. A capture whose
  > assembled params would exceed it MUST NOT create the event, MUST NOT truncate
  > or drop individual captured values to fit, and MUST present a visible
  > diagnostic, exactly as Section 15.1 requires when queue capacity is exhausted.

---

## #143 — dedupe can delete the retained-and-paused head (§15.2, §15.3)

**⚠ Design decision required: protect the paused head, or transfer the pause.** A is
drafted.

**SPEC-CHANGES row (option A):**

> | 143 | 2026-07-3X | §15.2, §15.3 | **A paused head is protected from dedupe replacement.** §15.2 forbids dedupe from removing an event "whose `event.action` request is in flight without a permanent result" — but a head *retained by an error pause* (§15.3: "a JSON-RPC error retains the head and pauses it") is not in flight, so a same-key admission atomically deletes the retained head. The pause then refers to a deleted event, a state no sentence defines; the anti-overtake guarantee inverts (the replacement takes the next `queue_seq` at the tail, so the retained intent's ordering evaporates); and §15.3's instruction to retain "that event and every later event" is silently subverted by the very mechanism §15.2 calls mere queue compaction. The dedupe rule now protects the paused head exactly as it protects an in-flight event: the new event is admitted behind it in normal FIFO order, and replacement applies only to non-head, non-in-flight records. The cost — replaceable intent accumulating behind a poisoned head, bounded by the queue caps — is the posture §15.3 already chose for every non-dedupe event. Restricting for a Companion that replaced paused heads; any such Companion was already in undefined territory. | none (prose) | |

**SPEC.md edits (option A):**

- §15.2, replace:
  > It MUST NOT remove or replace an event whose `event.action` request is in
  > flight without a permanent result.

  with:
  > It MUST NOT remove or replace an event whose `event.action` request is in
  > flight without a permanent result, nor a head event retained by a Section 15.3
  > error pause — the new event is admitted behind the retained head in normal
  > FIFO order. Dedupe replacement applies only to queued events that are neither
  > in flight nor a retained head.

**Option B:** allow the replacement but transfer both head position and pause state
to the replacement (it inherits the head's `queue_seq` rather than taking a new
one). Preserves compaction under a poisoned head, but re-opens `queue_seq`
immutability and makes the retained head's identity unstable across the exact
diagnostic window where an operator is looking at it.

**Recommendation: option A.**

---

## #144 — the dedupe key space is flat, and the spec's own examples disagree about it (§14.1, §15.2, §21.1)

**SPEC-CHANGES row:**

> | 144 | 2026-07-3X | §15.2 (cross-ref §14.1, §21.1, §21.2) | **The dedupe key space, stated: flat per pairing identity.** §14.1 types `dedupe` as an identifier "scoped to the pairing identity" and §15.2 replaces on "the same key and pairing identity" — a flat space, unqualified by action, surface, or origin. Trigger firings with a `queue`/`wake` policy enter the same durable queue and the same dedupe rule (§21.2's pipeline invokes "the durable-queue `dedupe` rule before delivery"), so an action's key and a trigger's key collide and silently annihilate each other's intent. The spec's own examples then disagree about whose job collision avoidance is: §14.1's example encodes the replaced intent's identity in the key (`heading:123:todo`) while §21.1's is bare (`battery-low`), and no sentence tells an author that a bare key is a pairing-global replacement channel. §15.2 now states the flatness explicitly — the space is shared across every action name, surface, and trigger of the pairing identity — and requires a sender that does not intend cross-intent replacement to author keys encoding the replaced intent's identity; §21.1's example key becomes `battery.level:low` to match §14.1's discipline. Clarifying prose; the operative replacement rule is unchanged, so no previously valid frame changes meaning — including `frames.golden`/`widgets.golden`, which carry `"dedupe":"battery-low"` and stay conformant (the new MUST is sender-intent discipline, not a validity rule). | none (prose; goldens keep their bare key legally — verified at draft time) | |

**SPEC.md edits:**

- §15.2, after "Dedupe is queue compaction; it is not delivery acknowledgement or
  receiver idempotence." — append:
  > The key space is flat per pairing identity: it is shared across every action
  > name, every surface, and every trigger firing that enters the durable queue.
  > Two events with equal keys replace each other regardless of origin. A sender
  > that does not intend cross-intent replacement MUST author keys that encode
  > the replaced intent's identity, as the Section 14.1 example does
  > (`heading:123:todo`).

- §21.1, in the trigger-set example, replace:
  > "dedupe":"battery-low",

  with:
  > "dedupe":"battery.level:low",

**Artifacts:** none. Noted for the ratifier: `frames.golden` and `widgets.golden`
carry `"dedupe":"battery-low"`. Those frames remain conformant — bare keys stay
valid wire; the new MUST constrains sender *intent*, not message validity — so no
golden changes, and the prose example's divergence from the golden's key is
deliberate (the example teaches the discipline; the golden pins the wire).

---

## #145 — the accessibility duty is assigned to the endpoint with no data (§16.4, §17.2, §17.4)

**⚠ Design decision required: derivation floor vs required member.** A is drafted.

**SPEC-CHANGES row (option A):**

> | 145 | 2026-07-3X | §16.4 (cross-ref §17.2, §17.4) | **The accessible-label duty gets a dischargeable floor.** §16.4's "Interactive nodes MUST expose an accessible label" binds the Companion, but the Companion renders only what Emacs sent, and for icon-only interactive nodes the wire may carry no text at all: `icon_button`'s `content_description` is optional (§17.4) and `icon`'s own rule (§17.2) requires `content_description` only when the icon is "the sole carrier of load-bearing meaning" — a sender-side judgement the Companion cannot audit. The MUST was therefore unconvictable against the defendant it named and undischargeable in the worst case. §16.4 now defines the derivation floor that makes it dischargeable: the accessible label is the first present of `content_description`, a textual `label`, the icon identifier's name, and the node type — and a Companion MUST NOT reject a node for lacking an accessibility member (no new invalidity, so nothing previously valid is invalidated and no protocol-major is triggered). Emacs SHOULD supply `content_description` on every icon-only interactive node; an icon identifier is a fallback of last resort, not a good label. | none (prose) | |

**SPEC.md edits (option A):**

- §16.4, replace:
  > Interactive nodes MUST expose an accessible label.

  with:
  > Interactive nodes MUST expose an accessible label, derived as the first
  > present of: `content_description`, a textual `label` member, the icon
  > identifier's name, and the node type. A Companion MUST NOT reject a node for
  > lacking an accessibility member. Emacs SHOULD supply `content_description` on
  > every interactive node whose only visual content is an icon; the icon
  > identifier is a fallback of last resort, not a substitute.

**Option B:** make `content_description` REQUIRED on `icon_button` (and icon-only
`chip`). Honest, but it invalidates previously valid core messages — a protocol-major
increment under §25's first classification bullet — for a gap a derivation floor
closes at zero cost.

**Recommendation: option A.**

---

## #146 — the loopback threat model excludes an attacker that needs no privilege (§9.3, §23.6, §5.2)

**⚠ Design decision required: honest re-scope vs a real integrity layer.** A is
drafted.

**SPEC-CHANGES row (option A):**

> | 146 | 2026-07-3X | §9.3, §23.6 (cross-ref §5.2) | **The excluded local attacker is named accurately: interposition needs no privilege.** §9.3 excludes "an active privileged local man-in-the-middle" and §23.6 says loopback "does not provide confidentiality or per-message integrity against a privileged local attacker" — but binding a loopback TCP port requires no privilege at all. An ordinary co-installed app that binds the configured port first, or wins the rebind race after a Companion crash (the reference Companion itself retries `EADDRINUSE` for ten seconds — the contention window is real and observed), becomes an active man-in-the-middle by pure proxying: the §9 handshake authenticates the *endpoints* end-to-end and passes through the proxy intact, and because later traffic carries no per-message integrity, the proxy then owns the session. The word "privileged" was false comfort. Both sections now name the class accurately — any local process able to interpose on the loopback path, including an unprivileged one that binds or races the configured port — and gain the operational duties that narrow the window: the Companion MUST treat a persistent failure to bind its configured port as possible squatting and surface it in the pairing UI, and MUST NOT silently fall back to a different port than the pairing UI displays (§5.2 already makes the port a pairing-UI parameter). The threat-model boundary itself is unchanged: in-scope resistance to an interposed local process requires an encrypted, per-message-authenticated profile, exactly as both sections already conclude. | none (prose) | |

**SPEC.md edits (option A):**

- §9.3, replace:
  > It does not encrypt later traffic or
  > authenticate each individual message against an active privileged local
  > man-in-the-middle. That attacker is outside the threat model of
  > `android-loopback-tcp`; a deployment that includes it MUST use a stronger
  > transport profile.

  with:
  > It does not encrypt later traffic or authenticate each individual message
  > against an active local man-in-the-middle — and interposing on a loopback
  > path requires no privilege: an ordinary local process that binds or races
  > the configured port and proxies bytes passes this handshake through intact
  > and then controls the session. That attacker is outside the threat model of
  > `android-loopback-tcp`; a deployment that includes it MUST use a stronger
  > transport profile.

- §23.6, replace:
  > It does not
  > provide confidentiality or per-message integrity against a privileged local
  > attacker.

  with:
  > It does not provide confidentiality or per-message integrity against a local
  > attacker able to interpose on the loopback path — which includes an
  > unprivileged process that binds or races the configured port, not only a
  > privileged one.

- §23.6, append to the paragraph:
  > A Companion MUST treat persistent failure to bind its configured port as
  > possible squatting and surface it in the pairing UI, and MUST NOT listen on
  > a port other than the one that UI displays.

**Option B:** derive per-session traffic keys from the token + nonces and MAC every
frame — a genuine integrity layer. That is a new transport profile in all but name,
contradicts §9.3's stated posture, and belongs in the "stronger transport profile"
both sections already point to.

**Recommendation: option A.** Honesty now; the integrity layer is a profile, not a
patch.

---

## #147 — the pre-auth surface is obligatory but has no eviction, aging, or fairness rule (§5.2, §9.1)

**⚠ Design decision required: eviction discipline and rate-limit keying.** A is
drafted.

**SPEC-CHANGES row (option A):**

> | 147 | 2026-07-3X | §5.2, §9.1 (precedent #77, #79) | **Pre-authentication connections age, evict newest-wins, and rate-limit state is bounded.** #77 made accepting new loopback connections mandatory while a session exists and required bounding concurrent pre-auth connections — but defined no behavior at the bound: a local flooder holding `bound` idle sockets forces the Companion to refuse the next dial, which is precisely the non-conformance #77 forbids ("a listener that refuses or ignores a second dial … is non-conformant"), turning the bound into a supersession-denial lever. And §9.1's "rate-limit failed proofs per pairing ID and source process or connection" keys limiter state on a peer-chosen value: an attacker rotates invented pairing IDs to escape any per-ID bucket and to grow limiter state without bound — the §23.5 genre, one key space over. §5.2 now gives the bound a discipline: a pre-auth connection that has not completed the handshake within 10 seconds MUST be closed, and when the bound is reached a new dial MUST evict the oldest pre-auth connection rather than be refused — newest-wins at pre-auth, mirroring supersession, so the guaranteed-dial property survives saturation. §9.1 now bounds the limiter: state MUST be bounded in total; failed proofs for *unknown* pairing IDs MUST be counted against one shared bucket (per #79 they are indistinguishable to the caller anyway) plus the per-source dimension; per-ID buckets exist only for stored pairings, of which this profile has one. Restricting for implementations that refused at the bound or kept per-unknown-ID state; both were already losing to a trivial local attacker. | none (prose) | |

**SPEC.md edits (option A):**

- §5.2, replace:
  > and MUST bound the
  > number of concurrent pre-authentication connections.

  with:
  > and MUST bound the number of concurrent pre-authentication connections. The
  > bound MUST NOT become a refusal: a pre-authentication connection that has not
  > completed the Section 9 handshake within 10 seconds MUST be closed, and when
  > the bound is reached, a new dial MUST evict the oldest pre-authentication
  > connection rather than be refused — newest-wins, mirroring supersession, so
  > that a legitimate dial always gets a handshake attempt even under local
  > flooding.

- §9.1, replace:
  > The Companion MUST rate-limit failed proofs per pairing ID and source process
  > or connection.

  with:
  > The Companion MUST rate-limit failed proofs per stored pairing ID and per
  > source process or connection, MUST count failed proofs for unknown pairing
  > IDs against a single shared bucket rather than per presented ID (Section 9.2
  > makes the cases indistinguishable to the caller), and MUST bound the total
  > state the rate limiter retains.

**Option B:** per-source token buckets only. Simpler, but loses the per-pairing
dimension on platforms where source attribution is weak, and #79's shared-bucket
observation does the same work more cheaply.

**Recommendation: option A.**

---

## #148 — `applied`/`stale` are not floor-absorption points, and supersession's pending-inbound disposition is undefined (§13.2, §5.2)

**SPEC-CHANGES row:**

> | 148 | 2026-07-3X | §13.2, §5.2 (cross-ref §10.3, §24.2) | **Mid-session results absorb like welcome floors; a terminated session's requests conclude before the welcome is built.** Emacs's duty to absorb Companion revision floors exists only at the synchronization barrier (§10.3 step 1; §24.2's "absorption of Companion revision/tombstone floors") — yet every `applied`/`stale` result also reports "the Companion's current revision floor" (§13.2), and no rule made Emacs adopt it. An Emacs whose revision store regressed (a restored backup, a lost file) can then author below the floor indefinitely: every update draws `stale`, nothing requires the sender to learn, and the surface is silently frozen until the next reconnect. §13.2 now makes any result carrying a revision a normative absorption point — Emacs MUST treat it exactly as a welcome floor: persist it and never author that surface at or below it. Separately, §5.2 orders termination before the new session enters `SYNCING` but never says what happens to the old session's requests still being processed while the welcome snapshot is assembled — leaving welcome-snapshot mutability open: a terminated session's `surface.update`, applied after the snapshot was built, makes the welcome lie. §5.2 now requires the Companion to conclude every pending inbound request of the terminated session — fully applied with its response committed to the old transport, or discarded without effect — before assembling the new session's welcome, and forbids a terminated session's request from altering any state the welcome reports. Clarifying prose pinning duties both endpoints' reference implementations already satisfy in the common path. | none (prose) | |

**SPEC.md edits:**

- §13.2, after "The result revision and `present` MUST describe the Companion's
  current revision floor and snapshot/tombstone state for that surface." — append:
  > A result carrying a revision is a floor-absorption point: Emacs MUST treat
  > the reported revision exactly as it treats a welcome floor (Section 10.3
  > step 1) — persist it and never subsequently author that surface at a
  > revision less than or equal to it. A reported floor above Emacs's own next
  > revision is evidence of store divergence; Emacs MUST continue above it, not
  > resend below it.

- §5.2, after "…the Companion MUST terminate the older session before the new
  session enters `SYNCING`." — append:
  > Before assembling the new session's welcome, the Companion MUST conclude
  > every pending inbound request of the terminated session: each is either
  > fully applied with its response committed to the old transport, or discarded
  > without effect. A terminated session's request MUST NOT alter any state the
  > new session's welcome reports.

---

## #149 — revision-space exhaustion has no wrap rule, no error, and no recovery (§4.2, §13.1)

**⚠ Design decision required: terminal rejection + re-key vs an epoch member.** A is
drafted.

**SPEC-CHANGES row (option A):**

> | 149 | 2026-07-3X | §13.1 (cross-ref §4.2, #141) | **Revision exhaustion: unreachable by construction, terminal by rule.** Revisions "MUST NOT wrap" (§13.1) and MUST NOT exceed 2^53−1 (§4.2) — and nothing says what happens at the boundary: no exhaustion error, no receiver duty to refuse, no recovery path. The space is genuinely reachable: a microsecond-epoch-derived revision scheme sits within one order of magnitude of the cap today, and nothing forbids large strides. §13.1 now states the discipline and the terminal rule: Emacs SHOULD allocate revisions densely (a stride never larger than needed for monotonicity), SHOULD NOT derive them from sub-millisecond clocks; a `surface.update` whose revision equals the §4.2 maximum MUST be rejected `1201 content-invalid` with `data.reason: "revision-exhausted"`, the stored floor unchanged — the surface's history is full, exactly as a saturated `max_surface_ids` is full. Recovery is re-keying to a fresh surface ID (which consumes a floor — #141's release path is the pressure valve) or pairing revocation. Additive in practice: no realistic dense allocator reaches the cap, and any sender that does was already in undefined territory. | none (prose; `data.reason` strings are not contract-projected) | |

**SPEC.md edits (option A):**

- §13.1, after "Gaps are allowed. Revisions MUST NOT wrap." — append:
  > Emacs SHOULD allocate revisions densely — a stride no larger than
  > monotonicity requires — and SHOULD NOT derive them from clocks finer than
  > milliseconds; the space is finite and floors make it non-renewable. A
  > `surface.update` whose `revision` equals the Section 4.2 maximum
  > (`9007199254740991`) MUST be rejected `1201 content-invalid` with
  > `data.reason: "revision-exhausted"` and MUST leave the stored floor
  > unchanged: that surface's history is full. Recovery is re-keying to a fresh
  > Surface ID or pairing revocation.

**Option B:** a revision-epoch member on `surface.update` and the welcome, resetting
the space under a bumped epoch. Solves exhaustion completely, but adds a wire member,
touches the welcome schema, contract, and goldens — over-machinery for a boundary
dense allocation never reaches.

**Recommendation: option A**, ratified together with (or after) #141 so the re-key
path has its pressure valve.

---

## #150 — the contract projection is a necessary gate, not a complete one (§24.4)

**SPEC-CHANGES row:**

> | 150 | 2026-07-3X | §24.4 (cross-ref §25) | **What the projection cannot express, stated — and enforcement claims made falsifiable.** §24.4 defines the contract projection's required contents and already warns that "a property-name inventory without JSON types is not a sufficient contract projection" — but never states the converse limit: ordering, atomicity, clock, durability, and session-state semantics are outside any schema projection's expressive range, so contract conformance alone gates only shapes, never behavior. The gap is not hypothetical: this repository's own sync tool covers two of the contract's thirty-one top-level registries while being cited as "binding prose↔contract", the exact stated-vs-actual-enforcement failure the source audit documents three times over. §24.4 now states the limit and imposes the falsifiability duty: a claim that a tool or artifact enforces part of this document MUST name the tool and the exact scope it checks; a conformance claim broader than its named scope is a process defect under §25. This is the documentation-side half of #151's standing rule. Clarifying prose. | none (prose) | |

**SPEC.md edits:**

- §24.4, after "The projection format MAY evolve independently, but changing its
  format MUST NOT change the EBP wire contract implicitly." — append:
  > A projection gates shapes, never behavior: ordering, atomicity, clock,
  > durability, and session-state semantics are outside any schema's expressive
  > range and are testable only against Sections 24.5–24.6 and this document's
  > prose. A claim that a tool or artifact enforces part of this document MUST
  > name the tool and the exact scope it checks; a conformance claim broader
  > than its named scope is a process defect (Section 25).

---

## #151 — the standing rule: monotone resources state exhaustion; enforcement claims name their tool (§25)

**SPEC-CHANGES row:**

> | 151 | 2026-07-3X | §25 (cross-ref §24.4; precedent #81→#140, #107→#141, #149) | **Two standing amendment duties.** Three times in this spec's history an amendment closed a symptom and deepened the structure underneath: #81 pinned the queue's stamping clock and left the ratchet's forward direction unbounded (#140); #107 hardened floor retention and left the floor space non-reclaimable (#141); plain revision monotonicity left the revision space exhaustible with no rule (#149). Each survivor is the same genre: a monotonically consumed resource whose exhaustion nobody was made to state. §25 now imposes the duty at the door: an amendment that introduces or modifies a monotonically consumed resource — an identifier space, a revision or sequence space, a retained floor, a nonce or dedupe-retention window, a counter — MUST state that resource's exhaustion behavior and reclamation path, or state explicitly that none exists and why that is acceptable. And its sibling, the enforcement-naming duty: an amendment that claims a property is enforced MUST name the enforcing tool and the scope of its enforcement (§24.4 imposes the same on conformance claims generally). Process prose; changes no wire behavior. | none (prose) | |

**SPEC.md edits:**

- §25, after the three classification bullets — append:
  > An amendment that introduces or modifies a monotonically consumed resource —
  > an identifier space, a revision or sequence space, a retained floor, a nonce
  > or dedupe-retention window, a counter — MUST state that resource's
  > exhaustion behavior and its reclamation path, or state explicitly that none
  > exists and why that is acceptable.
  >
  > An amendment that claims a property is enforced MUST name the enforcing tool
  > and the scope of its enforcement (compare Section 24.4's duty for
  > conformance claims).

---

## #152 — supersession has no signal: the loser cannot distinguish it from a crash (§5.2, §11)

**⚠ Design decision required: a wire signal vs a backoff-only rule.** A is drafted.

**SPEC-CHANGES row (option A):**

> | 152 | 2026-07-3X | §5.2, §11, §10.1 (cross-ref #77) | **`session.superseded` — the loser learns why the door closed.** §5.2's newest-wins supersession terminates the older session with a bare transport close: nothing distinguishes "you were replaced, stand down" from "the Companion crashed, redial now." With auto-reconnect on both endpoints — and two Emacsen against one Companion is a documented configuration (device Emacs + workstation over `adb forward`) — the distinction is the whole game: two auto-reconnecting Emacsen supersede each other forever, each cycle a full §10.3 barrier including a `queue.replay` round trip per retained event, indefinitely and silently. A new Companion-sender notification `session.superseded {}` is sent on the *old* session's transport, best-effort, immediately before its termination close. An endpoint that receives it MUST NOT automatically redial for at least 60 seconds and SHOULD require explicit user intent where a user is present — being superseded means another authorized session is live, so automatic contention is never correct. Because the notification is best-effort (the old transport may already be dead), an endpoint MUST additionally treat any close it did not initiate as possibly-supersession and apply jittered backoff to automatic redials; the signal removes doubt when it arrives, the backoff bounds the damage when it does not. Additive: a new notification in the §11 registry; a receiver that does not know it ignores an unknown notification under existing rules and keeps today's behavior. | contract §11 registry entry + method schema; golden: superseded-then-close sequence; validate.py method-registry sync | |

**SPEC.md edits (option A):**

- §5.2, replace:
  > When a new session
  > authenticates successfully, the Companion MUST terminate the older session
  > before the new session enters `SYNCING`.

  with:
  > When a new session authenticates successfully, the Companion MUST send
  > `session.superseded` (Section 11) on the older session's transport,
  > best-effort, and then MUST terminate the older session before the new
  > session enters `SYNCING`. An endpoint receiving `session.superseded` MUST
  > NOT automatically redial for at least 60 seconds and SHOULD require explicit
  > user intent where a user is present. Because the notification is
  > best-effort, an endpoint MUST treat any transport close it did not initiate
  > as possible supersession and apply jittered backoff to automatic redials.

- §11 registry — add the row `| session.superseded | Companion | notification |`,
  legal in any authenticated state, params `{}`.

**Option B (no wire change):** the backoff rule alone — any close the endpoint did
not initiate gets jittered exponential backoff with a stated floor and cap. Dampens
the oscillation but never ends it, and punishes recovery from genuine crashes with
the same delay forever.

**Recommendation: option A** — it contains B's backoff as its best-effort fallback,
and the client-side discipline is independently planned (PLAN-refound RF-0.5b)
whichever way this ratifies.

---

## Roll-up

| # | Hole | Sections | Needs a decision? | Artifacts |
|---|---|---|---|---|
| 140 | effective-clock ratchet unbounded forward | §15.2 | **yes — corroboration bound vs monotonic accounting** | none |
| 141 | surface-ID floors non-reclaimable | §13.1, §11, §22.1 | **yes — release grain (per-ID vs reset-all)** | contract + goldens |
| 142 | capture arithmetic exceeds event budget | §4.5 | no | none |
| 143 | dedupe deletes the paused head | §15.2, §15.3 | **yes — protect head vs transfer pause** | none |
| 144 | dedupe key space flat, examples disagree | §15.2, §14.1, §21.1 | no | none |
| 145 | accessibility duty has no data | §16.4, §17.2, §17.4 | **yes — derivation floor vs required member** | none |
| 146 | "privileged" mis-scopes the local MITM | §9.3, §23.6, §5.2 | **yes — re-scope vs integrity layer** | none |
| 147 | pre-auth surface: no eviction/aging; limiter keyed on peer IDs | §5.2, §9.1 | **yes — eviction discipline + keying** | none |
| 148 | results don't absorb floors; supersession pending-inbound undefined | §13.2, §5.2 | no | none |
| 149 | revision-space exhaustion undefined | §13.1, §4.2 | **yes — terminal rejection vs epochs** | none |
| 150 | contract projection: incomplete gate, unstated | §24.4 | no | none |
| 151 | standing rule: monotone resources + enforcement naming | §25 | no | none |
| 152 | supersession has no signal | §5.2, §11 | **yes — notification vs backoff-only** | contract + goldens |
