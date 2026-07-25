# APPLIED amendments #67–#79 — the thirteen verified P2 spec holes

> **APPLIED 2026-07-24** to `ebp/SPEC.md` and `ebp/SPEC-CHANGES.md` as amendments
> **#67–#79** (renumbered from the provisional #74–#86 because the P1 batch #67–#73
> was deferred, so P2 took the next contiguous numbers). Mapping: 74→67, 75→68,
> 76→69, 77→70, 78→71, 79→72, 80→73, 81→74, 82→75, 83→76, 84→77, 85→78, 86→79.
> `validate.py` stays green. The per-entry headings below keep their draft numbers;
> the authoritative applied numbers are the mapping above and `SPEC-CHANGES.md`.

## (draft numbering — the thirteen verified P2 spec holes)

Drafted 2026-07-24 against `ebp/SPEC.md` @ `d76d53a` (amendments through #66).
Source audit: `docs/AUDIT-spec-holes-2026-07-24.md` Tier 2 (findings 8–20).
Companion to `DRAFT-amendments-67-73.md` (the P1 batch).

**Drafts for ratification, not applied edits.** Numbers are provisional and
contiguous after the P1 batch (#67–#73); actual numbers are assigned at
ratification, so if a P1 draft is dropped these shift down. Each entry gives the
`SPEC-CHANGES.md` row, the exact `SPEC.md` edits, and any artifact change.

**All thirteen were hand-verified against the current spec text during the
audit** (re-reads cited in the audit report). Two carry a small behavioral choice,
flagged inline: **#77** (preserve-vs-reseed for a `publish_state:false` editor)
and **#85** (keystore-or-fail-safe for the pairing token).

**Interaction note:** #76 edits the same §15.3 paragraph neighborhood as the
deferred P1 #68 — if both land they must be merged (noted in #76).

Difficulty tiers (for ratification ordering):
- **Pure prose, no design:** 74, 78, 79, 80, 81, 82, 83, 84, 86
- **Prose + a behavioral choice:** 77, 85
- **Prose touching §15.3 (merge with #68 if that lands):** 76
- **Enumeration edit:** 75

---

## #74 — Reminder presentation is at-least-once, not only at-most-once (§18.6)

**SPEC-CHANGES row:**

> | 74 | 2026-07-24 | §18.6 | **Reminder presentation gains its lower bound.** §18.6's only presentation obligation was "MUST present the reminder *at most once*" — an upper bound trivially met by zero presentations, so a Companion that never fires any reminder satisfied every MUST, and the "or the surviving registrations will never fire" consequence lived only in the non-normative note from amendment #43. This is amendment #46's genre ("at most one" permitting zero where exactly-one is intended) left unfixed for reminders. §18.6 now requires an accepted, unfired reminder to be presented *at least once* — promptly at or after `at_ms`, including promptly at restore or re-arm when `at_ms` passed while the process or device was down — and *at most once* per accepted `(owner, id, at_ms)` tuple, unless the tuple is removed or replaced before presentation or the platform notification permission is withdrawn (in which case the obligation resumes on the next opportunity after permission is restored if the tuple has not fired). Clarifying prose that makes the intended firing mandatory and convictable; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §18.6, lines 2422–2424 — replace:
  > At or after `at_ms`, the Companion MUST present the reminder at most once for
  > that accepted `(owner, id, at_ms)` tuple and MUST persist fired state before or
  > atomically with presentation so a restart does not deliberately re-fire it.

  with:
  > At or after `at_ms`, the Companion MUST present the reminder for that accepted
  > `(owner, id, at_ms)` tuple **at least once** — promptly at or after `at_ms`,
  > including promptly at restore or re-arm when `at_ms` passed while the process or
  > device was down — and **at most once**, and MUST persist fired state before or
  > atomically with presentation so a restart does not deliberately re-fire it or
  > drop it. The at-least-once obligation lapses only while the tuple is removed or
  > replaced before presentation, or while the platform notification permission is
  > withdrawn; in the latter case the Companion MUST present on the next opportunity
  > after permission is restored if `at_ms` has passed and the tuple has not fired.

**Artifacts:** none (prose; the non-normative boot re-arm note from #43 remains as
the mechanism).

---

## #75 — Present-but-invalid optional member has a uniform receiver rule (§16.1)

**SPEC-CHANGES row:**

> | 75 | 2026-07-24 | §16.1 (cross-ref §16.3, §17.1, §12) | **An optional member present with an invalid value is a malformed node.** §16.1's whole-update rejection list named only "invalid *required* field"; §16.3 covers *unknown* fields (ignore) and §17's preamble covers *omitted* optionals (default), so a known optional member present with a value outside its declared type or domain — `alpha: 1.5`, `max_lines: 0`, `padding: -3`, a non-boolean `clip` — matched no rule, and §17 rows are inconsistent (some say "otherwise the node is invalid", `progress.value MUST be 0..1` states no consequence). §17.1's no-coercion rule forbids clamping but did not choose between ignore-member and reject-update. §16.1 now states that an optional member present with a value outside its declared type or domain makes the node malformed and rejects the whole update with `1201 content-invalid`, consistent with the no-coercion rule — except where a specific member defines a safe fallback for an unrecognized value under §12 rule 6 (`text.style` to `body`, `dialog.style` to `dialog`), which is applied instead of rejection. Clarifying prose closing an enumeration gap; no contract or golden change (existing per-member fallbacks are unchanged). | none (prose) | |

**SPEC.md edits:**

- §16.1, lines 1682–1684 — replace:
  > A malformed node, invalid required field, invalid action descriptor, duplicate
  > stateful-node ID, or resource-limit violation MUST reject the entire update with
  > `1201 content-invalid`.

  with:
  > A malformed node, invalid required field, an optional member present with a
  > value outside its declared type or domain, invalid action descriptor, duplicate
  > stateful-node ID, or resource-limit violation MUST reject the entire update with
  > `1201 content-invalid` — except a member that defines a safe fallback for an
  > unrecognized value under Section 12 rule 6 (such as `text.style` falling back to
  > `body` or `dialog.style` to `dialog`), which is applied instead of rejection.
  > A receiver MUST NOT coerce, clamp, or silently drop an out-of-domain member in
  > place of this rejection.

**Artifacts:** none. (A conformance-golden with an out-of-domain optional expecting
`1201` MAY be added under §24.6.)

---

## #76 — Delivery-pump run condition is an invariant, not "new head event" (§15.3)

**SPEC-CHANGES row:**

> | 76 | 2026-07-24 | §15.3 | **The delivery pump runs on an invariant, closing the SYNCING-backlog gap.** §15.3 started the pump only on "admission of a *new head event*" while `READY`, but an event admitted during `SYNCING` (or into a non-empty queue) is not a new head event, and §10.3 only says the Companion *MAY* release events after the flush while Emacs's `queue.replay` retry is gated on a nonzero `remaining` (reported `0`) — so a `queue`-policy tap taken during `SYNCING` with an exhausted barrier replay could sit undelivered until `ttl` expiry silently deleted it, data loss between two conformant implementations. §15.3 now states the pump MUST run whenever the session is `READY`, the queue is non-empty, no durable `event.action` request is in flight, and the pump is not paused by a prior transient error — regardless of whether the head was admitted while `READY` or during `SYNCING` — and entering `READY` after the §10.3 flush MUST start it. Clarifying prose replacing an under-inclusive trigger; no contract or golden change. | none (prose; a SYNCING-admit-then-READY delivery golden MAY be added) | |

**SPEC.md edits:**

- §15.3, lines 1591–1596 — replace:
  > While `READY`, admission of a new head event MUST start or wake that pump unless
  > it is paused by a prior transient error. A permanent result deletes the head and
  > advances the pump; a JSON-RPC error retains the head and pauses it. Admission of
  > a later event MUST NOT clear that pause or bypass the head. During `SYNCING`,
  > only the explicit replay request starts the pump.

  with:
  > The pump MUST run whenever the session is `READY`, the queue is non-empty, no
  > durable `event.action` request is in flight, and the pump is not paused by a
  > prior transient error — regardless of whether the head was admitted while
  > `READY` or during `SYNCING`. Entering `READY`, after the Section 10.3 flush, MUST
  > start it. A permanent result deletes the head and advances the pump; a JSON-RPC
  > error retains the head and pauses it. Admission of a later event MUST NOT clear
  > that pause or bypass the head. During `SYNCING`, only the explicit replay request
  > starts the pump.

> **Merge note:** if P1 **#68** is ratified, its rewrite of the "permanent result …
> JSON-RPC error retains the head" sentences supersedes the two-sentence disposition
> clause here; keep #68's error-partition wording and #76's run-condition invariant.

**Artifacts:** none.

---

## #77 — Dirty draft survives a changed authored value; local-editor text is preserved (§13.6)

**⚠ One behavioral choice** (second bullet): a `publish_state:false` editor's live
text on a same-identity refresh — *preserve* (drafted) vs *reseed from the
authored value*. Preserve is drafted because Emacs never receives that editor's
text (it emits no `state.changed`), so reseed silently destroys unrecoverable user
input. Flip if a `publish_state:false` editor is meant to be display-only.

**SPEC-CHANGES row:**

> | 77 | 2026-07-24 | §13.6 (cross-ref §13.2, §16.1, §17.4) | **A dirty draft is cleared only by the enumerated conditions, and local-editor text survives a refresh.** §13.6 forbade overwriting a dirty value "merely because the snapshot was refreshed", but a snapshot carrying a *changed* authored value is arguably not a mere refresh and the four-item clear-list was never stated exhaustive, so two conformant Companions could keep or overwrite a half-typed input on the same push — data loss. Separately, §13.6 scoped local-editor draft protection to `publish_state: true`, leaving a `publish_state: false` editor (user types, `on_save` captures) protected by no rule, with §13.2's atomic replace and §16.1's rendering-state retention unresolved. §13.6 now states the four clear conditions plus `reset_input_ids` are the *only* circumstances in which a compatible dirty value is cleared — a changed authored value alone does not overwrite a draft — and that a local `editor` node's live text is preserved across a same-presentation-identity snapshot regardless of `publish_state`, the authored `value` seeding only a new presentation identity. Clarifying prose making the draft-wins-unless-reset design normative; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §13.6, lines 1159–1160 — replace:
  > A new surface snapshot MUST NOT overwrite that dirty value merely because the
  > snapshot was refreshed.

  with:
  > A new surface snapshot MUST NOT overwrite that dirty value except in the
  > conditions enumerated below; in particular a snapshot that carries a different
  > authored `value` for the node does not by itself overwrite the draft.

- §13.6, after the clear-list (after line 1167) — add:
  > These four conditions and an ID named in `reset_input_ids` are the only
  > circumstances in which a compatible dirty value is cleared.

- §13.6, at the local-`editor` bullet (lines 1179–1181) — append:
  > A local `editor` node's live text is preserved across a same-presentation-identity
  > snapshot regardless of `publish_state`: the authored `value` seeds only a new
  > presentation identity, and a `publish_state: false` editor — which cannot be
  > named in `reset_input_ids` — reseeds only on a presentation-identity change.

**Artifacts:** none.

---

## #78 — Emacs reconciliation duty for a divergent editor seed (§19.3)

**SPEC-CHANGES row:**

> | 78 | 2026-07-24 | §19.3 (cross-ref §19 preamble) | **Emacs must reconcile an `edit.open` seed that differs from its document.** §19 pins the Companion's seed text exactly (`edit.open.text` equals the selected volatile-or-cached seed) but defined no Emacs duty when that seed differs from Emacs's own document — and divergence is guaranteed: deltas are notifications, so a delta applied to the shadow can be lost at transport cut (seed newer than the document), and process death falls back to the cached authored `value` even when Emacs accepted later deltas (seed older). Emacs could then silently issue a whole-document `edit.apply` over the user's visible text, or adopt a stale seed discarding its own accepted edits — both silent data loss with no rule violated. §19.3 now requires Emacs, on receiving `edit.open`, to compare `edit.open.text` against its current document for that `document` and, where they diverge, to reconcile explicitly (adopt the seed, issue a reconciling `edit.apply`, or surface a conflict); Emacs MUST NOT silently overwrite a seed newer than the last delta it accepted, and MUST NOT issue a blind whole-document replacement that discards the user's visible text. Clarifying prose adding the missing receiver duty; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §19.3, at the definition of the Companion-to-Emacs `edit.open` (insert after the
  `edit.open` shape) — add:
  > On receiving `edit.open`, Emacs MUST compare `edit.open.text` against its current
  > document for that `document`. Where they diverge, Emacs MUST reconcile
  > explicitly — adopting the seed, issuing a reconciling `edit.apply`, or surfacing
  > a conflict to the user — and MUST NOT silently overwrite a seed that is newer
  > than the last delta it accepted, nor issue a blind whole-document `edit.apply`
  > that discards the user's visible text.

**Artifacts:** none. (Place the sentence at the `edit.open` subsection of §19.3;
exact line depends on the surrounding text.)

---

## #79 — Revocation must be durable and resumable, not only atomically fenced (§9.1)

**SPEC-CHANGES row:**

> | 79 | 2026-07-24 | §9.1 (cross-ref §21.1, §18.6) | **Revocation erasure is durable and resumable; "atomically" names the fence.** §9.1 required revocation to "atomically fence the identity … erase its token, queued payloads, … reminders, triggers, …", but "atomically" grammatically attaches to the fence while the erasure spans stores that cannot be one platform transaction, and nothing required the erasure to be durable or resumable. Because §21.1 and §18.6 make trigger firing and reminder presentation device-lifetime obligations driven by the persisted registration itself, a crash after fencing but before erasing reminders and triggers leaves a fenced identity whose registrations keep firing and whose keystore-encrypted SMS and call payloads (§21.5) survive on disk indefinitely, since the fenced identity is never revisited. §9.1 now requires revocation to be recorded durably before or atomically with the fence, and the erasure of every listed category to be completed — resumed after any process or device restart — until it is gone; a crash mid-erasure MUST NOT leave a fenced identity whose triggers or reminders still fire or whose sensitive queued payloads survive. Clarifying prose closing a crash-durability gap; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §9.1, after the revocation sentence (after line 613, "Re-pairing creates a new
  pairing ID and an empty state partition.") — add:
  > Revocation MUST be recorded durably before or atomically with the fence, and the
  > erasure of every listed category MUST be completed — resumed after any process
  > or device restart — until it is gone. "Atomically" names the fence: a crash
  > after fencing but before erasure completes MUST NOT leave a fenced identity whose
  > triggers or reminders still fire (Sections 21.1, 18.6) or whose sensitive queued
  > payloads survive on disk.

**Artifacts:** none.

---

## #80 — Intent-allowlist absence is an empty allowlist, deny-by-default (§20.3)

**SPEC-CHANGES row:**

> | 80 | 2026-07-24 | §20.3 | **Absent intent-allowlist plural members deny by default; "when present" disambiguated.** §20.3 stated exact-match "including matching absence" only for `action`, `mode`, `package`, and `class_name`; for the plural members it left the semantics of an *absent* member undefined and "when present, a listed authority" ambiguous between "authority present in the URI" and "the `authorities` member present in the entry". An entry with `schemes` but no `authorities` matched a request whose data URI carried an authority under one reading (absent = unconstrained → launch) and failed it under the other (absent = empty allowlist → deny) — an allow-versus-deny divergence on the module's security boundary. §20.3 now states an absent `schemes`, `authorities`, `mime_types`, or `extra_keys` member is an empty allowlist, not an unimposed constraint: a request carrying a data URI, a URI authority component, a MIME type, or an extras key that the corresponding member does not list MUST NOT match, defaulting to deny, consistent with the positive-knowledge posture; and "a listed authority" is gated on the URI carrying an authority component. Clarifying prose pinning the security boundary; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §20.3, lines 2855–2859 — replace:
  > A request matches only when `action`, effective `mode`, `package`, and
  > `class_name` exactly equal the entry, including matching absence; any data URI
  > has a listed scheme and, when present, a listed authority; any MIME type is
  > listed; and every extras key is listed.

  with:
  > A request matches only when `action`, effective `mode`, `package`, and
  > `class_name` exactly equal the entry, including matching absence; any data URI
  > has a listed scheme and, if the URI carries an authority component, a listed
  > authority; any MIME type is listed; and every extras key is listed. An absent
  > `schemes`, `authorities`, `mime_types`, or `extra_keys` member is an empty
  > allowlist, not an unimposed constraint: a request carrying a data URI, a URI
  > authority component, a MIME type, or an extras key that the corresponding member
  > does not list MUST NOT match and MUST be denied.

**Artifacts:** none. (A `1003`/`intent-denied` golden for an absent-`authorities`
entry MAY be added.)

---

## #81 — Redaction floor covers calendar data and the SMS sender (§23.3)

**SPEC-CHANGES row:**

> | 81 | 2026-07-24 | §23.3 (cross-ref §21.4) | **The MUST-NOT-log floor is aligned with §21.4's sensitive-source set.** §23.3's hard "MUST NOT appear in normal logs … or crash reports" list named "SMS bodies, call numbers" but not calendar event titles or times, nor the SMS *sender* identifier, though §21.4 groups `calendar.event` with `sms.received` and `call.state` as a sensitive source requiring source-to-sink approval and the §21.5 `calendar.event` row carries no redaction clause — so calendar titles and SMS sender numbers fell only to the next sentence's SHOULD, and a genuinely sensitive value could leave the device in a crash report from one conformant implementation and be redacted by another. §23.3 now adds calendar event titles and times, SMS sender identifiers, and the captured fire data of any privacy-sensitive trigger source named in §21.4 to the hard MUST-NOT enumeration, referencing §21.4 so the two stay in sync. Clarifying prose extending an existing floor; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §23.3, lines 3370–3372 — replace:
  > Pairing tokens, authentication proofs, password values, clipboard contents, SMS
  > bodies, call numbers, and private editor content MUST NOT appear in normal logs,
  > metrics, diagnostics, Goldens, or crash reports.

  with:
  > Pairing tokens, authentication proofs, password values, clipboard contents, SMS
  > bodies and sender identifiers, call numbers, calendar event titles and times,
  > private editor content, and the captured fire data of any privacy-sensitive
  > trigger source named in Section 21.4 MUST NOT appear in normal logs, metrics,
  > diagnostics, Goldens, or crash reports.

**Artifacts:** none.

---

## #82 — `time.window` is a predicate-only state type (§21.3, §21.7, §20.1)

**Note:** confirmed contract-vs-prose drift — `contract.json` already projects
`predicate_only_state_types: ["time.window"]` and omits it from `state_types`,
but no prose defines the category or excepts it from §21.3's rule. This is the
reverse of the #63–66 drift (contract ahead of prose); the amendment lands the
prose the contract already assumes, so **no contract change is needed**.

**SPEC-CHANGES row:**

> | 82 | 2026-07-24 | §21.3, §21.7, §20.1 (contract) | **`time.window` named as the predicate-only state type the contract already projects.** §21.3 required "every predicate type appears in `device.state_types`" for Emacs to include a gate, but §21.7 makes `time.window` a valid `when` predicate while excluding it from sampleable state types, and never said whether it appears in `device.state_types` — so a literal reading made every time-window-gated trigger unauthorable (Emacs MUST omit it), while `contract.json` already carries `predicate_only_state_types: ["time.window"]` and omits it from `state_types`, a projection no prose defined. §21.7 now names `time.window` the sole predicate-only state type — a valid gate predicate that never appears in `device.state_types`, `device.trackable_state_types`, `state.get.types`, or a `state.edge` — and §21.3 excepts predicate-only types from its `device.state_types` requirement (a predicate-only type is available in a gate whenever `triggers` or `state.get` is granted). §20.1 notes `device.state_types` excludes predicate-only types. Clarifying prose aligning the spec with the existing `predicate_only_state_types` projection; no contract or golden change. | none (prose; contract `predicate_only_state_types` already present) | |

**SPEC.md edits:**

- §21.3, lines 3005–3007 — replace:
  > Emacs MUST include a gate only when every predicate type appears in
  > `device.state_types`. If any type is absent, Emacs MUST omit the entire trigger;
  > it MUST NOT remove the unsupported predicate and install a weaker trigger.

  with:
  > Emacs MUST include a gate only when every predicate type that is not
  > predicate-only appears in `device.state_types`. A predicate-only type (Section
  > 21.7) is available in a gate whenever `triggers` or `state.get` is granted and
  > never appears in `device.state_types`. If a non-predicate-only type is absent,
  > Emacs MUST omit the entire trigger; it MUST NOT remove the unsupported predicate
  > and install a weaker trigger.

- §21.7, at the `time.window` handling (near lines 3238–3239) — add:
  > `time.window` is the sole *predicate-only* state type: it is a valid `when`
  > predicate but never a sampleable or trackable state type, so it never appears in
  > `device.state_types`, `device.trackable_state_types`, `state.get.types`, or a
  > `state.edge`. `contract.json` projects the predicate-only set as
  > `predicate_only_state_types`.

- §20.1, at the `device.state_types` definition — add: `device.state_types`
  excludes predicate-only types (Section 21.7).

**Artifacts:** none — `contract.json` already correct.

---

## #83 — A permission-blocked but supported trigger type is accepted unarmed (§21.1)

**SPEC-CHANGES row:**

> | 83 | 2026-07-24 | §21.1 (cross-ref §21.4, §21.8) | **Permission grant state is not a trigger-acceptance gate, and "required permission descriptor" is defined.** §21.1 required validating "every … required permission descriptor" before changing registrations but never defined the phrase, inviting a reading where a currently-withdrawn permission rejects the whole atomic replace-set — yet §21.8 says blocked registrations "MAY remain stored and MAY arm after permission is restored" and §21.4 says "an unavailable permission MAY leave the trigger registered but unarmed", so `triggers.set [battery-low, sms-watch]` with SMS off yielded total success on one Companion (store sms-watch dormant, `{count:2}`) and total failure on another (`1101`, and because rejection is atomic, battery-low uninstalled too). §21.1 now defines a "required permission descriptor" as the OS permission(s) a trigger's `type` (per the §21.5 catalog) and its `on_fire` capabilities need, and states that a shape-valid entry whose `type` appears in `device.trigger_types` MUST be accepted and stored even when a needed permission is currently withdrawn — stored unarmed per §21.8 and armed when permission is restored; permission grant state MUST NOT be a `1101` rejection cause and MUST NOT fail the atomic replace-set. Validation of the descriptor is that the permissions are identifiable, not that they are granted. Clarifying prose resolving an accept-versus-reject divergence; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §21.1, lines 2915–2921 — after "…required permission descriptor, before changing
  registrations." add:
  > A trigger's *required permission descriptor* is the set of OS permission(s) its
  > `type` (per the Section 21.5 catalog) and its `on_fire` capabilities need;
  > validating it means those permissions are identifiable, not that they are
  > currently granted. A shape-valid entry whose `type` appears in
  > `device.trigger_types` MUST be accepted and stored even when a required
  > permission is currently withdrawn: the Companion stores it unarmed (Section 21.8)
  > and arms it when permission is restored. Permission grant state MUST NOT be a
  > `1101 triggers-rejected` cause and MUST NOT fail the atomic replace-set.

**Artifacts:** none.

---

## #84 — The Companion must accept a second connection for supersession (§5.2)

**SPEC-CHANGES row:**

> | 84 | 2026-07-24 | §5.2 (cross-ref §22.3) | **Accepting a new loopback connection is required, so supersession is reachable.** §5.2's supersession MUST fired only "when a new session authenticates successfully", but no rule obliged the Companion to *accept* a second TCP connection while one is open, and §22.3 bounds queues and requests but never connection count — so a single-connection Companion that refuses a second dial while a session is open satisfied the MUST vacuously, and when Emacs is OS-frozen with a `READY` connection still open (no FIN), the user's restarted Emacs could never reconnect until the Companion itself restarted: total connectivity loss between two conformant implementations. §5.2 now states the Companion MUST continue to accept new loopback connections and allow each to attempt the handshake while an authenticated session exists — supersession depends on it — and MUST bound the number of concurrent pre-authentication connections; a listener that refuses a second dial while a possibly-zombie session is open is non-conformant. Clarifying prose making the acceptance precondition explicit; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §5.2, after line 339 ("…before the new session enters `SYNCING`.") — add:
  > The Companion MUST continue to accept new loopback connections and allow each to
  > attempt the Section 9 handshake while an authenticated session exists —
  > supersession depends on it — and MUST bound the number of concurrent
  > pre-authentication connections. A listener that refuses or ignores a second dial
  > while a session (possibly a zombie whose transport has not yet closed) is open is
  > non-conformant.

**Artifacts:** none. (A concurrent-pre-auth-connection bound could be projected as a
`limits.fixed` value in a later batch if a number is wanted; the prose bound
suffices for conformance.)

---

## #85 — The pairing token gets keystore protection at rest (§9.1)

**⚠ One behavioral choice:** on a platform *lacking* a keystore facility, the
drafted rule is *fail-safe* (refuse to persist a pairing). If you prefer to allow
plaintext storage there with an explicit user warning, soften the last sentence to
a SHOULD + a MUST-warn.

**SPEC-CHANGES row:**

> | 85 | 2026-07-24 | §9.1 (cross-ref §23.3, §21.5) | **The pairing token is protected at rest at least as strongly as the data it authorizes.** §9.1 required only "storage private to each endpoint" for the 128-bit pairing token, while §23.3 and amendment #48 mandate keystore-backed encryption for sensitive queued trigger data — so the master secret gating all authentication, capability invocation, and trigger arming had weaker at-rest protection than a single SMS body, and a forensic or rooted image (post-first-unlock file-based encryption) could yield the plaintext token and complete the §9.3 handshake as a fully authorized Emacs. §9.1 now requires the pairing token and any recoverable HMAC key material to use platform keystore-backed storage wherever one exists, on the same unconditional terms as §21.5's sensitive queued data, and never to be held in plaintext application storage weaker than §23.3's protection for the SMS and call data the token's authority can reach; a Companion on a platform with no keystore facility MUST make that limitation explicit and MUST NOT persist a pairing under weaker protection. Clarifying prose raising the at-rest floor; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §9.1, lines 602–603 — replace:
  > The token MUST be stored in storage private to each endpoint, MUST NOT cross the
  > EBP wire, and MUST NOT appear in logs, errors, Goldens, or crash reports.

  with:
  > The token MUST be stored in storage private to each endpoint, MUST NOT cross the
  > EBP wire, and MUST NOT appear in logs, errors, Goldens, or crash reports. Where a
  > platform provides keystore-backed encrypted storage, the pairing token and any
  > recoverable HMAC key material MUST use it, on the same unconditional terms as
  > Section 21.5's sensitive queued data, and MUST NOT be held in plaintext
  > application storage weaker than the protection Section 23.3 requires for the SMS
  > and call data the token's authority can reach. A Companion on a platform with no
  > such facility MUST make that limitation explicit and MUST NOT persist a pairing
  > under weaker protection.

**Artifacts:** none.

---

## #86 — Unknown pairing ID gets an equal-work, indistinguishable rejection (§9.2)

**SPEC-CHANGES row:**

> | 86 | 2026-07-24 | §9.2 (cross-ref §9.1, §9.3) | **A hello with an unknown pairing ID is challenged and rejected with equal work.** §9.1 required not revealing whether an unknown pairing ID or an incorrect proof caused authentication failure, but §9.2 defined hello outcomes only for a protocol mismatch (`1202`) and an invalid field (`-32602`), and §9.3's constant-time rule covered only comparison of "well-formed proofs" — with no stored token there is no expected proof, so nothing required challenge-anyway or equal-work verification on the unknown-ID path, letting an implementation leak the cause through the failure stage (`1203` at hello versus at `auth.response`) or through response timing (a skipped HMAC) while satisfying the letter. §9.2 now requires a well-formed `session.hello` whose `pairing_id` matches no stored pairing to receive a normal fresh `server_nonce` challenge, indistinguishable from a known ID, and the subsequent `auth.response` to be verified with work equivalent to the known-ID path — an HMAC against a fixed dummy key plus a constant-time comparison — and rejected with `1203`, so neither the failure stage, the error code, nor response timing distinguishes an unknown pairing ID from an incorrect proof. Clarifying prose supplying the mechanism §9.1's non-revelation MUST needs; no contract or golden change. | none (prose) | |

**SPEC.md edits:**

- §9.2, after line 651 ("…another invalid hello field MUST receive `-32602`.") — add:
  > A well-formed `session.hello` whose `pairing_id` matches no stored pairing MUST
  > receive a normal fresh `server_nonce` challenge, indistinguishable from a known
  > ID; the Companion MUST NOT answer the hello itself with `1203` or any signal that
  > the ID is unknown. The subsequent `auth.response` MUST be verified with work
  > equivalent to the known-ID path — an HMAC-SHA256 computation against a fixed
  > dummy key and a constant-time comparison — and rejected with `1203 auth-failed`,
  > so neither the failure stage, the error code, nor response timing distinguishes
  > an unknown pairing ID from an incorrect proof (Section 9.1).

**Artifacts:** none.

---

## Roll-up

| # | Hole | Section(s) | Kind | Artifacts |
|---|---|---|---|---|
| 74 | Reminder never-fires conformant | §18.6 | prose | none |
| 75 | Invalid optional member unruled | §16.1 | enum edit | none |
| 76 | Pump-start misses SYNCING backlog | §15.3 | prose (merge #68) | none |
| 77 | Draft loss on refresh / local editor | §13.6 | prose + 1 choice | none |
| 78 | Editor seed divergence unreconciled | §19.3 | prose | none |
| 79 | Revocation not crash-durable | §9.1 | prose | none |
| 80 | Intent allowlist absence ambiguity | §20.3 | prose | none |
| 81 | Redaction floor omits calendar/sender | §23.3 | prose | none |
| 82 | `time.window` predicate-only undefined | §21.3/§21.7/§20.1 | prose (contract already right) | none |
| 83 | Permission-blocked trigger accept/reject | §21.1 | prose | none |
| 84 | Second connection not required | §5.2 | prose | none |
| 85 | Pairing token weak at rest | §9.1 | prose + 1 choice | none |
| 86 | Unknown pairing ID timing leak | §9.2 | prose | none |

**All thirteen are prose or projection-alignment — none change the wire format or a
contract vocabulary** (except #82, which the contract already anticipates). Twelve
have no artifact change at all. This is the P2 dividend of the audit's central
finding: the holes are the same genres already ratified in #34–66, and their fixes
are the same kind of clarifying prose.

Deferred / open from the P1 batch: **#68** (queue-disposition backstop constant)
and **#69** (tile spec shape — circle back at QS-tile implementation). The
unverified P2 tail (~165 remaining candidates) needs the workflow's verify phase
re-run once the spend limit resets (resume `wf_0260ae90-308`).
