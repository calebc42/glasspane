# EBP Specification — Amendment Audit (holes, edge-cases, non-normative gaps)

**Target:** `ebp/SPEC.md` @ `d76d53a` (amendments through **#66** applied).
**Run:** 2026-07-24. Workflow `wf_0260ae90-308` (33 finders → dedup → verify).
**Scope:** defects in the SPEC TEXT that require an amendment — not implementation bugs.

---

## Status & method

A fan-out audit produced **412 raw findings → 312 after dedup** (33 auditors: 24
section sweeps, 7 cross-cutting lenses — normative-language, state-machine,
limits/vocabulary, threat-model, contract-drift, and two downstream-consumer
lenses reading the Kotlin companion and the elisp side — plus 2 harvesters that
re-extracted the 78 SPEC findings from the halted `AUDIT-full-spec-RAW.md`).

The **adversarial verification phase was cut off by a monthly spend limit**: 306
of the verifier subagents died mid-run. Only the first ~40 findings (the §1–§9
pipeline head) were machine-verified, yielding the 4 editorial P3s in Tier 3.

**Everything in Tiers 1 and 2 below was therefore re-verified by hand** against
the current spec text (section reads + contract.json checks are cited inline).
The unverified remainder — **~178 P2 + ~98 P3 candidates** — is summarized in
the Appendix by genre, not individually confirmed. Per the known verifier trap,
absence of a machine verdict is *not* refutation.

Severity: **P1** = interop failure, data loss, or security divergence between two
*conformant* implementations. **P2** = observable divergence or an unconvictable
MUST. **P3** = non-normative language / editorial.

Recurrence note: the majority of Tier-1/2 holes are the **same genres already
ratified in amendments #34–66** — a closed vocabulary with no fallback, a clock
left unpinned, an "at most one" that permits zero, a data-protection boundary
left undefined, cross-artifact drift, a ratified amendment that didn't
propagate. The spec's own amendment history predicts where the remaining holes
are.

---

## Tier 1 — Verified P1 (interop failure / data loss / security divergence)

### 1. Amendment #34 residue: §4.2 and §7.5 still mandate string-only request IDs
**§4.2 (L142), §7.5 (L535)** — contradicting **§7.2 (L487–494)**

Amendment #34 rewrote §7.2 to allow "a JSON string **or a JSON integer**" so that
"core Emacs `jsonrpc.el` … conforms without adaptation." Two sentences were never
updated:
- §4.2 L142: *"EBP request IDs are strings; Section 7.2 prohibits numeric request IDs."* — now a **false** cross-reference.
- §7.5 L535: rpc.cancel params carry *"the exact **string** request ID being cancelled."*

**Divergence.** A jsonrpc.el Emacs (the blessed path) sends `session.hello` with
`id:1`. A Companion enforcing §4.2's sentence rejects the integer ID → pairing
never completes. And integer-ID cancellation is unconstructable: `{"id":5}`
fails §7.5's "string" letter, `{"id":"5"}` never matches under §4.1's
no-coercion rule → `rpc.cancel` silently never works for the reference endpoint.

**Amendment.** Rewrite §4.2 to "IDs are strings or safe integers per §7.2";
rewrite §7.5 to "the exact request-ID value (string or integer), matched by §4.3
equality." (Two independent finders, s24-conformance + x-consumer-emacs.)

### 2. Any well-formed JSON-RPC error wedges the durable queue forever
**§15.3 (L1616–1617)** with **§7.3 (L513)** and **§14.4 (L1399–1414)**

§15.3: *"Any well-formed JSON-RPC error response … MUST stop replay and retain
that event and every later event."* But §7.3 **mandates** `-32602` for
structurally invalid params, and amendment #34 blessed jsonrpc.el's dispatch
tolerances — a stock dispatcher answers a malformed `event.action` with `-32602`,
not a §14.4 status. §14.4's four statuses route a permanent failure to
`rejected` (**delete record, advance**); a JSON-RPC error routes to **retain head
+ all later events**. Opposite dispositions, no stated winner.

**Divergence.** One durably-committed malformed event that permanently draws
`-32602` pins the head; every later valid event expires behind it (they may not
overtake, §15.3 L1637) → **silent data loss**. A Companion that treats permanent
errors as `rejected` drains but discards retained intent. Both defensible.

**Amendment.** State that a *permanent* validation failure of `event.action` MUST
be answered on the result channel as `rejected`/`stale`, never as a JSON-RPC
error; partition §15.3 errors into transient (retain) vs permanent (delete +
count rejected + continue); add a bounded-attempt poison-message escape.

### 3. `tile:*` surface namespace has no SurfaceSpec variant anywhere
**§13.4 (L1093–1101)** — orphaned by amendment #39

Amendment #39 registered `tile:<name>` as a capability-gated namespace (§13.1
L997, gated on `surfaces.tile`; contract.json capability present at L910) and
§10.2 names a `tile` profile target. But §13.4's variant table lists only
`app:*`, `notification:*`, `widget:*`, and L1091 makes that table the **sole**
authority ("The namespace determines the exact SurfaceSpec variant"). No `tile`
row exists in the spec or contract.

**Divergence.** Emacs granted `surfaces.tile` sends
`surface.update{surface:"tile:vpn", spec:…}`. What shape is `spec`? Undefined:
Companion A accepts a bare root Node, B expects a `{label,icon,…}` wrapper and
1201-rejects a bare Node, C rejects every tile update (no schema row). **A
granted capability is unusable interoperably.**

**Amendment.** Add a `tile:*` row to §13.4 (label/icon/active-state wrapper or a
constrained root Node, multi-view prohibited) and project it into contract.json.

### 4. Synchronized-editor documents are unboundable — no `max_editor_bytes`
**§4.5 (L223–244), §19.4 (L2622), §19 preamble (L2450)**

`edit.open.text` and the `edit.resync` result MUST carry the **complete** text in
one frame. §4.5 caps `max_frame_bytes = 4194304` and defines `max_editor_sessions`
but **no per-document byte limit** (confirmed: no `max_editor*bytes` in
contract.json). Deltas grow a document incrementally within per-frame caps, so
two conformant endpoints can reach a document whose mandatory full-state carrier
exceeds `max_frame_bytes`.

**Divergence.** A 5 MiB org buffer goes stale; `edit.resync` must "return its
current full state" but the body exceeds the frame cap → §6 forces close; on
reconnect the node is present in READY so the Companion MUST send `edit.open`
with the full seed — an unsendable frame → **permanent connect/close loop**.
Implementations diverge between violating the cap, refusing to open (violating a
MUST), and truncating (data corruption).

**Amendment.** Add a negotiated `limits.max_editor_bytes` (REQUIRED when
`editor.sync` granted, bounded so seed/resync fit `max_frame_bytes`); Emacs MUST
NOT advertise an editor whose document exceeds it; define a typed rejection when
a splice would exceed it. (Same genre as amendment #40's `max_device_report_bytes`.)

### 5. `selected` is boolean in §17.1/contract but a date string on `month_grid`
**§17.1 (L1783), §17.5 (L2094), contract.json `field_types.selected` (L274)**

§17.5 L2094: *"`selected` is one `YYYY-MM-DD` date"* for `month_grid`. But §17.1's
by-name common-type rule leaves `selected` a boolean (the `chip` case), and
`contract.json field_types.selected = "boolean"` (verified L274) commits the
projection. A date string is not a "narrower rule" of boolean, so §17.1's
row-narrowing escape does not resolve it.

**Divergence.** `{"t":"month_grid","selected":"2026-07-24"}` — a validator keyed
on `field_types` rejects it as a type error and per §16.1 rejects the **entire
surface** with 1201, while a §17.5-driven Companion highlights the day.

**Amendment.** Exactly the fix amendment #66 applied to `fill`: qualify §17.1 as
"boolean-valued `selected`" and set `field_types.selected` to `"varies-per-node"`.

### 6. §10.3 READY-flush rewrites `revision_seen`, which §14.6 forbids
**§10.3 (L890–892)** vs **§14.6 (L1486–1488)**

§10.3's on-READY flush emits `state.changed` for every divergent value changed
"after the welcome snapshot or during `SYNCING`, **using the accepted revision
currently shown**." §14.6 requires `revision_seen` to equal *"the revision of the
accepted snapshot presented to the user when the edit was made"* and *"MUST NOT
rewrite a pending notification's `revision_seen` after accepting a newer
snapshot."* These collide whenever §10.3-step-3 pushes a newer revision during
SYNCING before the flush.

**Divergence.** Value edited at shown revision 41; SYNCING pushes 42. One
Companion flushes `revision_seen:42` (currently shown), another `41` (when
edited). Emacs's §14.6 adoption test is keyed on `revision_seen`, so the user's
offline draft is silently kept on one pair and dropped on the other. §10.3 also
lacks §14.6's `reset_input_ids` discard carve-out, so a draft Emacs deliberately
reset can be resurrected. (Two finders: harvest-a + x-statemachine.)

**Amendment.** Amend §10.3 to require §14.6's revision (presented-when-edited /
welcome revision for a disconnected edit) and its `reset_input_ids` discard;
cross-reference §14.5/§14.6. Also resolve that `state.changed` is legal only in
READY (§11) yet edits occur during SYNCING (§10.3) — either legalize the flush's
timing or scope the §13.2/§14.6 barrier to READY explicitly.

### 7. `occurred_at_ms` stamping clock unpinned — rollback expires fresh events at birth
**§15.2 (L1572–1577)** with **§14.4 (L1377)**

Expiry compares the rollback-protected **effective** clock against
`occurred_at_ms`, but §14.4 defines `occurred_at_ms` only as "Creation time" and
§4.2 only as epoch ms — the stamping clock is never pinned. Amendment #47 pinned
`time.at_ms` to the effective clock; the queue's own creation stamp was missed.

**Divergence.** Clock rolled back 2h; user taps a `ttl_s=3600` queued action.
Stamped from the raw wall clock, `occurred_at_ms < high-water − ttl` → the event
satisfies the expiry predicate **at admission** and is deleted before any
delivery. Stamped from the effective clock, it lives its full hour. Both
conformant → silent data loss on one.

**Amendment.** Require `occurred_at_ms`/`queued_at_ms` for durable events to be
stamped from the §15.2 effective clock, or equivalently guarantee a newly
admitted event the full `ttl_s` of effective-clock lifetime from admission.

---

## Tier 2 — Verified P2 (observable divergence / unconvictable MUST / hardening)

### 8. Reminder presentation is at-most-once only; never-firing is conformant
**§18.6 (L2422)** — the only obligation is *"MUST present … **at most once**"* — an
upper bound trivially met by **zero** presentations. No at-least-once floor
exists; the "or the surviving registrations will never fire" consequence lives
only in the **non-normative** note (L2417–2420). Exact amendment-#46 genre ("at
most one" permitting zero where exactly-one is intended), unfixed for reminders.
*Fix:* an accepted unfired reminder MUST present exactly once, promptly at/after
`at_ms` including at restore/re-arm; define behavior on notification-permission
withdrawal.

### 9. No receiver rule for a present-but-invalid *optional* member
**§16.1 (L1682–1684)** — the reject list names "invalid **required** field"; §16.3
covers unknown fields; §17 preamble covers **omitted** optionals. A present
out-of-domain optional (`alpha:1.5`, `max_lines:0`, `padding:-3`) matches no
rule, and §17 rows are inconsistent (some say "otherwise the node is invalid",
`progress.value MUST be 0..1` states no consequence). Reject-whole-update vs
ignore-member divergence on the same surface. *Fix:* one uniform duty — any
present member violating its type/domain makes the node malformed → 1201, with
explicitly listed per-field fallbacks (e.g. `text.style → body`) as the only
exceptions.

### 10. Delivery pump start-condition misses SYNCING-admitted / non-head backlog
**§15.3 (L1591–1596)** — the pump starts on *"admission of a **new head event**"*
while READY. An event admitted during SYNCING, or into a non-empty queue, is not
"a new head event"; §10.3 only says the Companion **MAY** release events after
the flush, and Emacs's `queue.replay` retry is gated on `remaining > 0` (reported
0). A `queue`-policy tap during SYNCING can then sit until ttl expiry. *Fix:*
replace the trigger with an invariant — whenever READY ∧ queue non-empty ∧ no
durable request in flight ∧ not error-paused, the pump MUST run; entering READY
(after the §10.3 flush) MUST start it.

### 11. Dirty-draft data loss: "merely because refreshed" + `publish_state:false` editor
**§13.6 (L1159–1167), §17.4 draft rules (§13.6 L1179)** — §13.6 forbids overwriting
a dirty value *"merely because the snapshot was refreshed"*; a snapshot with a
**changed** authored value is arguably not a mere refresh, and the four-item
clear-list is never stated exhaustive → keep-vs-overwrite divergence destroys
half-typed input on one impl. Separately, §13.6 L1179 scopes local-editor draft
protection to `publish_state:true`; a `publish_state:false` editor (user types,
`on_save` captures) is protected by no rule — §13.2's atomic replace vs §16.1's
rendering-state retention are unresolved, so a same-identity refresh may wipe
live text. *Fix:* state that the clear-list + `reset_input_ids` are the ONLY
ways to clear a compatible draft, and that authored `value` seeds a *new*
identity only, for every stateful node regardless of `publish_state`.

### 12. Editor reconnect: seed diverging from the Emacs document has no reconciliation rule
**§19 preamble (L2444–2450)** pins the Companion's seed exactly
(`edit.open.text MUST equal that selected seed`) but defines **no Emacs duty**
when the seed differs from its document. Divergence is guaranteed: deltas are
notifications, so a transport cut can lose an applied edit (seed newer than
document); process death falls back to the cached authored value even when Emacs
accepted later deltas (seed older). Emacs may then silently whole-document
`edit.apply` over the user's visible text, or adopt a stale seed discarding its
own accepted edits — both silent data loss, no rule violated. *Fix:* require
Emacs to compare `edit.open.text` to its document, forbid silently overwriting a
seed newer than its last accepted delta, and define a diff/conflict path.

### 13. Revocation atomicity & crash-durability undefined; fenced identity keeps firing
**§9.1 (L607–613)** — *"Revocation MUST **atomically** fence the identity … erase
its token, queued payloads, … reminders, triggers, …"* "atomically" attaches to
the fence, but the erasure spans stores that cannot be one platform transaction,
and nothing requires it to be durable/resumable. §21.1/§18.6 make trigger firing
and reminder presentation **device-lifetime** obligations driven by the persisted
registration itself — so a crash after fencing but before erasing
reminders/triggers leaves a fenced identity whose registrations **keep firing**
and whose keystore-encrypted SMS/call payloads (§21.5) survive on disk
indefinitely (the fenced identity is never revisited). *Fix:* revocation MUST be
recorded durably before/with the fence; erasure MUST complete (resume after
restart) until every listed category is gone.

### 14. Intent allowlist: absent plural members and "when present" flip allow/deny
**§20.3 (L2851–2859)** — "including matching absence" is stated only for
`action`/`mode`/`package`/`class_name`. For `schemes`/`authorities`/`mime_types`/
`extra_keys` the semantics of an **absent** member is undefined, and *"when
present, a listed authority"* is ambiguous between "authority present in the URI"
and "the `authorities` member present in the entry." *Divergence:* entry
`{action:VIEW, mode:activity, schemes:[https]}` (no `authorities`) + request
`data:"https://evil.example/x"` → one Companion launches (absent = unconstrained),
another denies (absent = empty allowlist). **Allow-vs-deny on the module's
security boundary.** *Fix:* state per-member deny-by-default absence semantics and
disambiguate "when present."

### 15. Redaction floor omits `calendar.event` data and the SMS sender
**§23.3 (L3370–3372)** — the MUST-NOT-log list names "SMS **bodies**, call
numbers" but not calendar event titles/times, nor the SMS `from` field, though
§21.4 groups `calendar.event` with sms/call as a sensitive source and the §21.5
`calendar.event` row carries no "MUST NOT be logged" clause. Those values fall to
the *SHOULD* only → a genuinely sensitive value ("Divorce lawyer 3pm", a sender
number) leaves the device in a crash report from one conformant impl and is
redacted by another. *Fix:* add calendar titles/times, SMS sender identifiers,
and captured fire-data of any §21.4 sensitive source to the MUST-NOT list, or
reference §21.4's set so it stays in sync.

### 16. `time.window` predicate vs `device.state_types`: every time-window gate may be unauthorable
**§21.3 (L3005–3007)** vs **§21.7 (L3238–3239)** — §21.3 requires *"every predicate
type appears in `device.state_types`"* for Emacs to include a gate; §21.7 makes
`time.window` a valid gate predicate but **excludes** it from sampleable state
types (`state.get.types` is "other than `time.window`") and never says whether it
appears in `device.state_types`. Literal reading → a time-window-gated trigger is
unauthorable (Emacs MUST omit it); the alternate reading admits `state.edge` over
civil time with undefined level semantics. *Fix:* name `time.window` as
predicate-only in §21.7 (always available in gates, never in `state_types`) and
except predicate-only types in §21.3.

### 17. Permission-blocked-but-supported trigger type: accept-unarmed vs reject undefined
**§21.1 (L2906), §21.4, §21.8** — a type in `device.trigger_types` but currently
permission-blocked has no acceptance rule; three signals point opposite ways
(§21.1 "validate every required permission descriptor" — itself undefined; §21.4's
MAY-leave-unarmed; §21.8's stored registrations). Because rejection is atomic,
`triggers.set [battery-low, sms-watch]` with SMS off → Companion A stores
sms-watch dormant and returns `{count:2}` (total success); Companion B 1101-rejects
the whole set (battery-low not installed either — total failure). *Fix:* permission
state MUST NOT be a rejection cause for a shape-valid entry whose type is in
`device.trigger_types`; accept, store, leave unarmed. Define "required permission
descriptor."

### 18. Accepting a second connection is never required; supersession is trivially avoidable
**§5.2 (L335–339)** — the supersession MUST fires only *"when a new session
authenticates successfully,"* but no rule obliges the Companion to **accept** a
second loopback connection while one is open (§22.3 bounds queues, never
connection count). A single-connection Companion is conformant. *Divergence:*
Emacs is OS-frozen with a READY connection still open (no FIN); the user restarts
Emacs and dials — Companion A accepts, authenticates, supersedes the zombie;
Companion B refuses until it restarts → **total connectivity loss**. *Fix:* under
this profile the Companion MUST keep accepting new loopback connections and let
them attempt the handshake while a session exists (supersession depends on it),
and MUST bound concurrent pre-auth connections.

### 19. Pairing token has weaker at-rest protection than the SMS payloads it authorizes
**§9.1 (L602)** requires only *"storage private to each endpoint"* for the 128-bit
master token; §23.3 + amendment #48 mandate **keystore** encryption for sensitive
queued trigger data. The spec thus protects a single SMS body more strongly than
the secret gating **all** authentication, capability invocation, and trigger
arming. A forensic/rooted image (post-first-unlock FBE) yields the plaintext
token → an attacker completes the §9.3 HMAC handshake as a fully authorized
Emacs. *Fix:* require the token (and recoverable HMAC key material) to be
keystore-wrapped wherever a keystore exists, on the same terms as §21.5 sensitive
data, and fail-safe where none exists.

### 20. Unknown pairing ID: failure stage & work unpinned, defeating the non-revelation MUST
**§9.1 (L621) / §9.2 (L649–651) / §9.3 (L709)** — §9.1 requires "MUST NOT reveal
whether an unknown pairing ID or an incorrect proof caused failure," but §9.2
defines hello outcomes only for protocol mismatch (1202) and invalid field
(-32602), and the constant-time rule covers only *"well-formed proofs."* Nothing
mandates challenge-anyway + equal-work (dummy-HMAC) on the unknown-ID path, so an
impl can leak the cause via failure **stage** (1203 at hello vs at auth.response)
or **timing** (skipped HMAC) while satisfying the letter. *Fix:* require a
well-formed hello with an unknown ID to receive a normal fresh challenge, and the
subsequent `auth.response` to be verified with work equivalent to the known-ID
path, so neither stage, code, nor timing distinguishes the causes.

---

## Tier 3 — Verified P3 (editorial / governance; machine-confirmed)

- **§1 scope MUSTs are unconvictable.** *"It MUST NOT carry executable
  host-language code"* has no defendant and is literally falsified by §19 editor
  sync (Elisp buffer text crosses the wire as inert data); the real rule is
  receiver-side (§3 invariant 4). *"Invent application behavior"* is never
  defined. *Fix:* rephrase as a receiver-side no-evaluation duty; define or delete
  "invent application behavior."
- **§25 governance has no actor, no required record, no ratifier.** The
  classification MUST names no one; the amendment record is only SHOULD; nothing
  defines who may ratify a publication. *Fix:* name the maintainer, make the
  amendment record REQUIRED, state ratification authority.
- **§2.3 client/server word-ban has undefined scope** and the spec's own wire
  uses those words as persistent identifiers (`client` in hello L632/644,
  `server` in welcome L770/817, "EBP/2 client:" proof label L672). *Fix:* scope
  the ban to prose; exempt the fixed wire names.
- **§26 omits FIPS 180-4 / RFC 6234 (SHA-256)** on which the mandatory
  HMAC-SHA256 (§4.4, §9.3) depends — RFC2104 defines HMAC generically only. *Fix:*
  add the SHA-256 reference (and the Unicode Standard for §4.1 scalar values).

---

## Appendix — Unverified candidate tail (NOT machine-verified)

The verification pass never reached these; they are dedup'd finder output,
strongest-per-section. Treat as leads. They cluster into the **ratified genres**,
which is why they are high-probability:

- **Closed vocabularies with no unknown-value fallback-or-reject rule (§12 rule 6
  applied to itself):** `chart.kind` (§17.5), theme map values (§18.4),
  annotation `severity` (§19.5), `when_offline` values (§14.1), Color parse
  failure vs unknown-role fallback boundary (§16.6), toast `duration_s`
  out-of-range (§18.2). §12 itself notes "the spec's own vocabularies violate"
  rule 6 — a systemic sweep is warranted.
- **Clocks/time left unpinned (the #47 genre):** staleness clock (§13.5), `at_ms`
  clock for reminders (§18.6), `every_s` timebase under live clock change (§21.5),
  high-water-mark advancement cadence (§15.2), Emacs dedupe-retention start
  instant (§14.4).
- **Receiver duty undefined for malformed-but-well-formed input:** explicit
  `null` on a non-null member (§4.1), BOM-prefixed body (§4.1), unpaired
  surrogate error path (§4.1), duplicate-member response code/id (§4.1/§6.2),
  invalid Content-Length value (§6.2), schema-violating welcome (§10.2),
  response with unknown id / id:null (§7.3).
- **"At most one"/MAY permitting zero (the #46 genre):** §22.2 "at most one unsent
  snapshot" permits dropping newest state; §21.8 triple-MAY on post-revocation
  disposition; §21.6 edge-firing obligation is non-normative only.
- **Unbounded/unconvictable MUSTs:** failed-proof rate-limit has no bound (§9.1);
  "MUST rate-limit `log.error`" has no rate though other sections cite it as
  defined (§22.3); "decoded safely" for icon PNGs (§20.3); "reject excessive
  content" names no number (§23.5).
- **State-machine dead cells / races:** `session.ready` failure outcome (§10.3);
  SYNCING-entry instant vs supersession fence ordering (§10.1); dialog outstanding
  across supersession (§18.1); editor Companion-side staleness unrecoverable
  (§19.2–19.4); dialog-document node cap missing — the 10k limit is scoped to
  surface snapshots (§4.5/§18.1).
- **Security/privacy leads:** `image.https` not pinned to the connected IP
  (DNS-rebinding TOCTOU, §17.2); Emacs may persist a captured password in a
  durable work item — nothing forbids it (§14.4/§14.6/§23.3); §23.3 keystore rule
  read alone permits plaintext-and-advertise when no keystore exists (drifts from
  §21.5's do-not-advertise, the #48 fix); no bound on pre-auth connections →
  local DoS (§10.1/§22.3).
- **Further cross-artifact drift (the #63–66 genre):** `field_types.month` is
  `"yyyy-mm"` but `date_stamp.month` is a display string (§17.2); per-method
  `errors` arrays in contract.json have no spec semantics (§24.4).

**To finish the audit:** re-run the workflow's Verify+Skeptic phases once the
spend limit resets — resume with `wf_0260ae90-308`
(`workflows/scripts/ebp-spec-hole-audit-wf_0260ae90-308.js`); the 312 deduped
findings replay from cache and only the verification agents re-run.
