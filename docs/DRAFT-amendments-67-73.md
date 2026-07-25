# DRAFT amendments #67–#73 — the seven P1 spec holes

> **APPLIED / DISPOSITION (2026-07-24, after Opus verification):**
> - **Applied** to SPEC.md + SPEC-CHANGES.md: integer-ID (§4.2/§7.5) as editorial **#80**; occurred_at_ms (§15.2) **#81**; selected (§17.1/§17.5) **#82**; revision_seen (§10.3) **#83**; editor-bytes (§4.5/§19) **#84**. (Draft #67/#73/#71/#72/#70 respectively.)
> - **DISCARDED — #68 (queue-disposition):** Opus refuted it as a non-hole — the §7.3-structural vs §14.4-semantic partition already exists; the drafted fix would have contradicted §7.3. Do not apply.
> - **DEFERRED — #69 (tile):** confirmed P1, but its SurfaceSpec shape is a design decision tied to the near-term QS-tile implementation. Still open.
> - **Two NEW P1s** Opus confirmed (not drafted in this doc) were drafted inline and applied as **#85** (§14.1 wake-without-`offline.wake`-grant, security) and **#86** (§17.2 fetched-image cache/revocation-erasure, privacy). See SPEC-CHANGES.md.
>
> The per-entry edits below are the original drafts; the authoritative applied text is SPEC.md + SPEC-CHANGES.md.

Drafted 2026-07-24 against `ebp/SPEC.md` @ `d76d53a` (amendments through #66).
Source audit: `docs/AUDIT-spec-holes-2026-07-24.md`.

**These are drafts for ratification, not applied edits.** Each entry gives (a) the
`SPEC-CHANGES.md` row ready to paste, (b) the precise normative `SPEC.md` edits,
and (c) the artifact (contract/golden/validate) changes. The `Ratified` column is
left blank for the maintainer. **One design decision is flagged in #69** (the tile
spec shape) — everything else is determined by the existing text.

Suggested ratification order: **71, 67, 72, 73** (pure corrections, no design) →
**70, 68** (new limit / disposition logic) → **69** (needs the tile-shape
decision).

---

## #67 — Amendment #34 residue: integer request IDs in §4.2 and §7.5

**SPEC-CHANGES row:**

> | 67 | 2026-07-24 | §4.2, §7.5 (cross-ref §7.2, §4.3) | **Amendment #34 residue swept from §4.2 and §7.5.** #34 rewrote §7.2 to allow a JSON string *or a safe integer* request ID so core `jsonrpc.el` conforms without adaptation, but two contradicting sentences survived and were never reconciled. §4.2's "EBP request IDs are strings; Section 7.2 prohibits numeric request IDs" was a now-false cross-reference by which a §4.2-literal validator rejects every integer ID a conforming Emacs sends — including `session.hello` itself — so pairing never completes. §7.5 defined `rpc.cancel` params as "the exact *string* request ID", leaving cancellation of an integer-ID request unconstructable: `{"id":5}` fails the string letter and `{"id":"5"}` matches nothing under §4.1's no-coercion rule, so cancellation silently never takes effect on the blessed path. §4.2 now reads "strings or safe integers as Section 7.2 defines"; §7.5 now cancels "the exact request ID (a JSON string or a safe integer), matched against the outstanding request's `id` by Section 4.3 equality". Not wire-breaking: integer IDs were already legal under #34 and this only deletes text that contradicted them. | goldens/frames.golden gains one integer-id `rpc.cancel` frame; validate.py id/cancel check (already integer-tolerant from #34) | |

**SPEC.md edits:**

- §4.2, line 142 — replace:
  > EBP request IDs are strings; Section 7.2 prohibits numeric request IDs.

  with:
  > EBP request IDs are strings or safe integers as Section 7.2 defines.

- §7.5, lines 535–536 — replace:
  > Its params MUST be `{id}` where `id` is the exact string request ID being cancelled.

  with:
  > Its params MUST be `{id}` where `id` is the exact request ID being cancelled — a JSON string or a safe integer — matched against the outstanding request's `id` by Section 4.3 equality.

**Artifacts:** no contract change (`limits.fixed.max_request_id_bytes` and the §7.2
grammar already cover both forms). Optional golden: append an integer-id
`rpc.cancel` frame to `goldens/frames.golden` as a witness.

---

## #68 — Durable-queue poison-message wedge (§14.4 result channel vs §15.3 retain rule)

**SPEC-CHANGES row:**

> | 68 | 2026-07-24 | §14.4, §15.3 (cross-ref §7.3, §8) | **Durable-queue poison-message wedge closed.** §15.3 gave *every* well-formed JSON-RPC error one disposition — "stop replay and retain that event and every later event" — while §7.3 mandates `-32602` for structurally invalid params and #34 blessed a host dispatcher (jsonrpc.el) whose reflex is exactly that answer, and §14.4's four-status rule (`rejected` deletes and advances) pointed the opposite way with no stated winner. A durably-committed event that permanently drew `-32602` therefore pinned the queue head forever and starved every later event to `ttl` expiry — silent data loss. Two corrections. (1) §14.4: a *permanent* validation failure of an `event.action` — a failure of the allowlist, argument, surface-context, revision, or durable-ID checks it already enumerates — MUST be answered `rejected` (or `stale`), never as a JSON-RPC error; a JSON-RPC error from Emacs is reserved for transient inability (`1500`), cancellation (`1301`), and a frame so malformed it cannot dispatch as an `event.action` at all. (2) §15.3 partitions replay error responses: `1500`, `1301`, `1401`, `-32603`, and transport faults are transient (retain the head and pause, unchanged); `-32600`, `-32601`, `-32602`, and `1204` can never succeed on redelivery of the identical frame and are permanent (delete the head, count it in `rejected`, advance); and a head that draws any non-permanent error more than `max_delivery_attempts` (a fixed backstop of 8) MUST then be treated as `rejected`, so no head can wedge the queue indefinitely. Behavior-corrective, not wire-breaking: no frame format changes and every wire golden's disposition holds; the retain-forever path removed was reachable only through the §14.4 violation now forbidden. | contract limits.fixed += `max_delivery_attempts` (8); goldens/wire poison-durable-event vector (permanent error ⇒ head deleted, later event delivered); validate.py replay-disposition check | |

**SPEC.md edits:**

- §14.4 — after the four-status table and the "safely admitted" paragraph
  (insert after line 1414), add:
  > A permanent failure of any validation this section requires — the action
  > allowlist, arguments, surface context, revision (Section 14.5), or durable ID —
  > MUST be reported on the result channel as `rejected`, or as `stale` when the
  > context is only too old. Emacs MUST NOT answer a well-formed `event.action`
  > with a JSON-RPC error to signal permanent invalidity; a JSON-RPC error is
  > reserved for transient inability (`1500`), cancellation (`1301`), and a frame
  > that is not a well-formed `event.action` and so cannot dispatch (`-32602`).

- §15.3 — replace the paragraph at lines 1616–1621:
  > Any well-formed JSON-RPC error response, including `1500 event-retry` and
  > `1301 request-cancelled`, MUST stop replay and retain that event and every later
  > event. …

  with:
  > A well-formed JSON-RPC error response is classed transient or permanent. `1500
  > event-retry`, `1301 request-cancelled`, `1401 overloaded`, `-32603
  > internal-error`, and a transport-level fault are transient: replay MUST stop and
  > retain that event and every later event, and the pump pauses. `-32600`,
  > `-32601`, `-32602`, and `1204 session-state` cannot succeed on redelivery of the
  > identical frame and are permanent: the Companion MUST delete the head, count it
  > in `rejected`, and advance the pump. A head that draws a transient error more
  > than `max_delivery_attempts` times MUST then be treated as a permanent
  > `rejected` result, so no single event can wedge the queue indefinitely; that
  > terminal disposition MUST be surfaced through the replay summary's `blocked_by`
  > before the head is dropped. A result with an unknown status or invalid result
  > shape remains a protocol violation: the Companion MUST retain the event, send at
  > most one safe `log.error`, and close the connection. If the connection closes,
  > all events without a permanent result MUST remain queued.

**Artifacts:** `contract.json` `limits.fixed.max_delivery_attempts = 8`
(drift-checked against the §15.3 prose). Golden: a wire vector where a durable
`event.action` draws `-32602`, the head is deleted and counted `rejected`, and a
later valid event is delivered. `validate.py` gains the transient/permanent
partition in its replay-disposition reference.

> **Note for review:** `max_delivery_attempts = 8` is the one tunable constant here.
> The permanent/transient partition alone closes the `-32602` wedge; the attempt
> cap is the backstop for a *transient* code that never clears (a buggy peer). If
> you prefer no fixed backstop, drop the sentence and rely on `blocked_by`
> surfacing the stuck head to the user instead.

---

## #69 — `tile:*` SurfaceSpec variant (§13.4)

**⚠ Requires one design decision:** amendment #39 registered the `tile:<name>`
namespace and the `surfaces.tile` capability but never defined its `spec` shape,
and nothing in the reference companion or `ebp.el` implements it — so the shape is
genuinely open. The row below proposes a **flat Quick-Settings metadata object**
(no Node tree), which matches the Android QS tile model (label, icon, subtitle,
active state, tap) and sidesteps the renderer questions a Node body would raise.
Swap the shape here if you intend tiles to render a widget-like Node body instead.

**SPEC-CHANGES row (proposed shape):**

> | 69 | 2026-07-24 | §13.4, §13.7 (cross-ref §13.1, §18.5) | **The `tile:*` SurfaceSpec variant, defined.** Amendment #39 registered `tile:<name>` as a capability-gated namespace (§13.1) and `surfaces.tile` (§22.1), and §10.2 names a `tile` profile target, but §13.4 — whose sentence "The namespace determines the exact SurfaceSpec variant" makes its table the sole authority — was never given a `tile` row, so a Companion granted `surfaces.tile` had no schema to validate a `surface.update` against and the capability was unusable interoperably. §13.4 now defines the `tile:*` variant as a flat Quick-Settings metadata object `{label: string, icon?: identifier, subtitle?: string, active?: boolean, on_tap?: remote ActionDescriptor}` — no Node body and no stateful node, mirroring the platform's fixed tile slot; multi-view is prohibited, `current_view` and a Node `spec` are invalid, and `on_tap` follows §14's remote-action pipeline without a surface or revision context (like a shortcut). All of §13's revision, tombstone, limit, update, and remove rules apply unchanged. Additive: no tile `spec` was previously definable, so no previously-valid frame is invalidated; the three existing variants are untouched. | contract `surface_spec_variants.tile` (new projection, parallel to notification/widget); goldens/wire tile `surface.update` + `event.action` from a tile `on_tap`; validate.py tile-variant check | |

**SPEC.md edits:**

- §13.4, lines 1093–1098 — add a fourth row to the variant table:
  > | `tile:*` | `{label: string, icon?: identifier, subtitle?: string, active?: boolean, on_tap?: ActionDescriptor}`; no Node body, no stateful node; multi-view prohibited |

- §13.4, after line 1101 — add:
  > A `tile:*` `spec` MUST NOT carry a Node, a `views` object, a `current_view`, or
  > a stateful node; a Companion MUST reject any of these with `1201
  > content-invalid`. `on_tap`, when present, enters the Section 14 remote-action
  > pipeline with no surface, dialog, or revision context; the Companion MUST inject
  > the tile's Surface ID name into a copy of `on_tap.args` and MUST reject an
  > authored conflicting member, parallel to Section 20.3 shortcuts.

- §13.7 — add a sentence noting the tile wrapper carries no `header_action` and
  no `empty` Node (those are notification/widget concepts).

**Artifacts:** `contract.json` gains a `surface_spec_variants.tile` projection
(the existing app/notification/widget variants are prose-only today; #69 is the
occasion to project all four if drift-checking is wanted, or just tile). Goldens:
a `tile:vpn` `surface.update` and an `event.action` from its `on_tap`.

---

## #70 — Synchronized editor documents need a byte bound: `max_editor_bytes` (§4.5, §19)

**SPEC-CHANGES row:**

> | 70 | 2026-07-24 | §4.5, §19 preamble, §19.4 (cross-ref §23.5) | **A numeric bound on the synchronized editor document.** `edit.open.text` and the `edit.resync` result MUST carry the *complete* document in one frame, but §4.5 bounded `max_frame_bytes` and `max_editor_sessions` with no limit on document length, and deltas grow a document incrementally within per-frame caps — so two conformant endpoints can reach a document whose mandatory full-state carrier cannot be framed at all, forcing a §6 close, and on reconnect the node is present in `READY` so the Companion "MUST create a fresh session and send `edit.open`" with an unsendable seed: a permanent connect/close loop, with implementations diverging between violating the frame cap, refusing to open (violating a MUST), and truncating (data corruption). A new `max_editor_bytes` limit (REQUIRED when `editor.sync` is granted, bounded so seed and resync frames always fit `max_frame_bytes`) closes it: Emacs MUST NOT present a synchronized editor whose document text exceeds it, and a text-changing `edit.apply` from either endpoint whose result would exceed it MUST be refused. This mirrors amendment #40's `max_device_report_bytes` — making an "always frames within `max_frame_bytes`" guarantee provable at the wire. Additive: an over-limit document was previously undefined and unframeable, so no previously-conformant editor is invalidated. | contract limits.welcome += `max_editor_bytes`; goldens/wire over-limit `edit.apply` expect_error `1201 content-invalid` reason `editor-too-large`; validate.py green | |

**SPEC.md edits:**

- §4.5 limits table (after the `max_editor_sessions` row, line 237) — add:
  > | `max_editor_bytes` | REQUIRED when `editor.sync` is granted; maximum encoded bytes (UTF-8 length of the JCS-serialized document text) of one synchronized editor document; at least `65536` and no greater than `max_frame_bytes - 4096` |

  (The `- 4096` headroom covers the JSON-RPC envelope and the other
  `edit.open`/`edit.resync` members — `document`, `editor_id`, `session`, `seq`,
  `cursor`, `sel_start`, `sel_end`.)

- §19 preamble (after line 2450, the `edit.open.text` seed rule) — add:
  > Emacs MUST NOT present a synchronized `editor` whose document text exceeds
  > `max_editor_bytes`; `edit.open.text` and the `edit.resync` result text MUST fit
  > it, so both full-state carriers frame within `max_frame_bytes`.

- §19.4 apply-gate list (lines 2656–2661) — add a fourth gate condition:
  > - the resulting text length does not exceed `max_editor_bytes`;

  and after the `{status:"applied"}`/`{status:"stale"}` sentence (line 2664) add:
  > A text-changing operation that would carry the document past `max_editor_bytes`
  > MUST NOT be applied: an inbound `edit.apply` that would exceed it MUST receive
  > `1201 content-invalid` with `data.reason: "editor-too-large"` and MUST NOT change
  > text, Emacs MUST NOT emit such a splice, and a Companion-local edit that would
  > exceed the limit MUST be refused as if the editor were read-only.

**Artifacts:** `contract.json` `limits.welcome.max_editor_bytes`. Golden: an
`edit.apply` overflowing the limit, `expect_error` `1201`/`editor-too-large`.
`validate.py` unchanged logic (limits are not spec-synced beyond presence).

---

## #71 — `selected` is context-dependent: contract projection corrected (§17.1, §17.5)

**SPEC-CHANGES row:**

> | 71 | 2026-07-24 | §17.1, §17.5 (contract) | **`selected` is context-dependent — the by-name projection is corrected.** This is amendment #66 applied to a second field it missed. §17.1's by-name common-type list makes `selected` a plain boolean (the `chip` case), and `contract.json` `field_types.selected` was `"boolean"`, but §17.5 states "`selected` is one `YYYY-MM-DD` date" for `month_grid` — a date string is not a "narrower rule" of boolean, so the row-narrowing escape does not resolve it, and a validator keyed on the global map rejects a valid `month_grid` value as a type error and per §16.1 rejects the *entire surface* with `1201`. §17.1 now qualifies the field as "boolean-valued `selected`" (exactly as #66 qualified `fill`), and `field_types.selected` becomes `"varies-per-node"` (boolean on `chip`, `YYYY-MM-DD` string on `month_grid`); the per-node meaning already lives in §17.4 and §17.5. Additive and corrective: a valid `month_grid` surface that a contract-literal validator wrongly rejected is now accepted; no member or enum changes. | contract `field_types.selected` "boolean" → "varies-per-node"; validate.py green | |

**SPEC.md edits:**

- §17.1, line 1794 — replace:
  > and `scroll`, `selectable`, `selected`, and boolean-valued `fill` are booleans.

  with:
  > and `scroll`, `selectable`, boolean-valued `selected`, and boolean-valued `fill` are booleans.

**Artifacts:** `contract.json` `field_types.selected`: `"boolean"` →
`"varies-per-node"` (line 274). No golden change.

---

## #72 — §10.3 READY-flush must carry §14.6's `revision_seen`, not the current revision

**SPEC-CHANGES row:**

> | 72 | 2026-07-24 | §10.3 (cross-ref §14.5, §14.6) | **The on-`READY` flush stamps the revision §14.6 requires, not the current one.** §10.3's flush emits `state.changed` for every divergent value changed after the welcome snapshot or during `SYNCING` "using the accepted revision currently shown", but §14.6 requires `revision_seen` to equal "the revision of the accepted snapshot presented to the user when the edit was made" and forbids rewriting it after accepting a newer snapshot — so for a value edited at revision 41 while `SYNCING` pushed 42, the two rules stamp different revisions, and Emacs's §14.6 draft-adoption test (keyed on `revision_seen`) keeps the user's offline draft on one Companion and drops it on another; §10.3 also omitted §14.6's `reset_input_ids` discard, letting a draft Emacs deliberately reset be resurrected. §10.3 now requires each flushed notification to carry the §14.6 `revision_seen` (the revision presented when that value was changed; for a value changed while disconnected, the welcome-reported revision), never the current revision, and to discard unsent any value whose ID an accepted snapshot at a higher revision named in `reset_input_ids`; and it records that this flush is the sole path by which a value changed during `SYNCING` reaches Emacs, since `state.changed` is legal only in `READY`. Clarifying prose that aligns §10.3 with the already-normative §14.6; a Companion implementing §14.6 for the live case now applies it to the reconnect flush. No contract or golden change. | none (prose; a reconnect-flush golden MAY be added as a witness) | |

**SPEC.md edits:**

- §10.3, lines 889–893 — replace:
  > The Companion MUST then clear the surface-disconnection staleness timer and MUST
  > immediately flush as ordered `state.changed` notifications every divergent
  > non-password value changed after the welcome snapshot or during `SYNCING`,
  > using the accepted revision currently shown, even when no event is pending.

  with:
  > The Companion MUST then clear the surface-disconnection staleness timer and MUST
  > immediately flush as ordered `state.changed` notifications every divergent
  > non-password value changed after the welcome snapshot or during `SYNCING`, even
  > when no event is pending. Each flushed notification carries the `revision_seen`
  > Section 14.6 requires — the revision of the accepted snapshot presented to the
  > user when that value was changed, and for a value changed while disconnected the
  > welcome-reported revision — never the revision currently shown; and a value
  > whose ID an accepted snapshot at a higher revision named in `reset_input_ids`
  > MUST be discarded unsent, as Section 14.6 requires. This on-`READY` flush is the
  > sole path by which a value changed during `SYNCING` reaches Emacs, because
  > `state.changed` is legal only in `READY`.

**Artifacts:** none required. Optional golden: a reconnect flush stamping the
presented-when-edited revision.

---

## #73 — Durable-event creation stamp is the effective clock (§15.2)

**SPEC-CHANGES row:**

> | 73 | 2026-07-24 | §15.2 (cross-ref §14.4, §15.1) | **`occurred_at_ms` is stamped from the effective wall clock.** §15.2 compares the rollback-protected *effective* wall clock (the greater of the current wall clock and the durable per-pairing high-water mark) against `occurred_at_ms`, but §14.4 defines `occurred_at_ms` only as "Creation time" and §4.2 only as epoch milliseconds, so the *stamping* clock was never pinned — and a raw device-clock stamp taken after a backward clock change larger than `ttl_s` yields `occurred_at_ms < high-water − ttl`, satisfying the expiry predicate at the instant of admission, so the event is deleted before any delivery and the user's intent is silently lost. §15.2 now requires `occurred_at_ms` and `queued_at_ms` for a durable event to be read from the effective wall clock (equivalently, the stored expiration MUST grant the event its full `ttl_s` of effective-clock lifetime from admission), so a rollback at or before admission cannot expire a fresh event against its own creation stamp. This mirrors amendment #47's pinning of `time.at_ms` to the same effective clock. Clarifying prose; the stamp source was undefined, so no previously-valid behavior is invalidated. No contract or golden change. | none (prose; an admit-under-rollback golden MAY be added) | |

**SPEC.md edits:**

- §15.2 — after the expiry paragraph (line 1577), add:
  > A durable (`queue` or `wake`) event's `occurred_at_ms` and `queued_at_ms` MUST
  > be read from this effective wall clock, not the raw device clock. Equivalently,
  > a newly admitted event's stored expiration time MUST grant it the full `ttl_s`
  > of effective-clock lifetime measured from admission, so a backward clock change
  > at or before admission cannot satisfy the expiry predicate against the event's
  > own creation stamp. This matches amendment #47's pinning of `time.at_ms` to the
  > effective clock.

**Artifacts:** none required. Optional golden: admit an event immediately after a
`> ttl_s` rollback and assert it is delivered, not expired.

---

## Roll-up: artifact changes across all seven

| Amendment | SPEC.md | contract.json | goldens | validate.py |
|---|---|---|---|---|
| #67 integer IDs | §4.2, §7.5 | — | +1 rpc.cancel int-id (opt) | id/cancel check |
| #68 queue disposition | §14.4, §15.3 | limits.fixed += `max_delivery_attempts` | +1 poison-event vector | replay partition |
| #69 tile variant | §13.4, §13.7 | +`surface_spec_variants.tile` | +tile update + on_tap | tile check |
| #70 editor bytes | §4.5, §19, §19.4 | limits.welcome += `max_editor_bytes` | +1 over-limit apply | — |
| #71 selected | §17.1 | `field_types.selected` → varies-per-node | — | green |
| #72 flush revision | §10.3 | — | +reconnect flush (opt) | — |
| #73 occurred_at_ms | §15.2 | — | +rollback admit (opt) | — |

Every amendment records itself in the §197–201 append-only Amendments table of
`SPEC.org` as well, per §25 / the SPEC.org convention.
