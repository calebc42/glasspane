# W10 — overload: the Emacs half of SPEC 22.3

REWRITE-PLAN row: "§22 traffic classes, bounded processing, `log.error`
protocol"; exit gate §24.6 item 14 (bounded overload per traffic class).
The Companion discharged its half in Tier-2 (LD-13: hold 512 / resume 128,
local synthetic `1401`, #106 pump exemption; inbound bounded by the blocking
single-reader loop, where the TCP window is the backpressure).  ebp.el
discharges none of it — RESEARCH-A8 §7: no outstanding-request ceiling, no
inbound bound, no `1401`; all three §22.3 queues delegated to jsonrpc.el
unbounded.  This plan is the design record for closing that; the A8 report
(§1, §2, §7) is the fact base and is not restated here.

## The constraint that shapes everything (A8 §1.5)

Emacs's re-entrant dispatch inside its own blocking `process-send-string`
is the DEADLOCK-AVOIDANCE mechanism: the Companion's single reader thread
writes from the thread that reads, so if Emacs stops reading while the
Companion is blocked writing to it, and Emacs then blocks in a send of its
own, the cycle closes and neither side ever moves.  Therefore:

**The invariant.** *Reading may pause only while nothing of ours is in
flight: every send path resumes reading first, and a pause is never taken
from inside a send.*  Under it the cycle cannot close — whenever we are
blocked in a send we are reading (the A8-1 mechanism, now load-bearing by
design), and whenever we are paused the Companion's blocked write is pure
backpressure with no send of ours waiting on it.

## The three bounds (all four §22.3 queues accounted)

| §22.3 queue | Bound |
|---|---|
| inbound frame queue | per-frame §4.5 limits (already enforced) + the pause below |
| parsed-message queue | pause reading at HIGH backlog; resume at LOW |
| outstanding request count | W10-a sender ceiling, twin of LD-13 |
| module work queues | shell repush queue is per-surface (bounded by `max_surfaces`); no others |

**W10-a — sender ceiling** (`ebp-client--request`): hold at 512
outstanding, resume at ≤ 128 (sticky hysteresis, mirroring
`CompanionEngine.PENDING_HOLD/RESUME`); a refused request concludes
LOCALLY and synchronously with `1401 {kind: overloaded}`, callback exactly
once.  `queue.replay` is exempt, for #106's reason exactly: the §15.3
replay is single-flight, so it can never be the resource the ceiling
protects, while refusing it would stall durable delivery on our own load.
On close, jsonrpc.el's sentinel already fails every continuation locally
(`Server died`, jsonrpc.el:696-698 at emacs-30.1) — §22.3's "outstanding
requests fail locally" rides that, and the ceiling's decrement rides the
exactly-once callback.

**W10-b — inbound bound.**  Mechanics, all public API, jsonrpc.el rented
unmodified:

- *Backlog metric*: jsonrpc.el's filter drains its `jsonrpc-mqueue`
  process property into 0-delay timers at the end of every invocation
  (jsonrpc.el:770-812), so the parsed-message queue LIVES in `timer-list`.
  Backlog = count of timers whose `timer--args` car is OUR connection
  object — unambiguous (the eq test is against our own object), O(n) at
  filter granularity, no jsonrpc internals touched.
- *Admission point*: `add-function :around` on `(process-filter proc)` —
  OUR process (ebp.el creates it); the wrapper acts only at the outermost
  filter exit (own dynamic depth flag, not jsonrpc's internal one).
- *Pause*: backlog ≥ 512 → `stop-process`, unless inside a send (the
  invariant) or already paused.  Paused, the kernel socket buffer fills,
  the TCP window closes: transport backpressure per §22.3, and the parsed
  backlog only drains from there.
- *Resume*: every drain point (both dispatchers + every wrapped
  continuation) when paused and backlog ≤ 128 → `continue-process`; and
  unconditionally BEFORE any outbound write, via
  `cl-defmethod jsonrpc-connection-send :around (ebp--connection)` — the
  generic every request, notification, AND reply funnels through.  That
  method also binds the in-send flag the pause consults.
- *Exhaustion*: re-entrant dispatch depth > 32 at dispatcher entry (the
  resource amendment #124 adds to §22.3), or backlog ≥ 2048 at filter exit
  (reachable only by growth during sends, where pausing is forbidden) →
  one `log.error 1401 {kind: overloaded}` and close (§22.3's MUST; the
  once-per-connection latch IS the rate limit, since close follows).

Constants: `ebp-overload-hold` 512 / `ebp-overload-resume` 128 (both
sides of the wire now share the same figures), `ebp-overload-exhaust`
2048, `ebp-max-dispatch-depth` 32.  Defconsts, not defcustoms: §22.3
bounds are conformance behavior, not user preference.

**R1-for-H2** (rides along, same hazard family): `ebp-client-edit-apply`'s
callback currently adopts `new`/`seq` read BEFORE the send; a re-entrant
`edit.open`/`edit.close`/`edit.delta` during the send invalidates them.
The callback now re-fetches the mirror entry and adopts only if it is the
same live object, same session, seq unmoved since the send; anything else
is `ebp-client-edit-resync` — the standard stale recovery.

## SPEC amendments (contract repo)

- **#124 (R3)**: §22.2 — the conflation boundary is the HANDOFF to the
  transport, not completion; a message can be *in transmission* (handed
  off, not fully written) and is already un-discardable there.  §7.4 — a
  note that a send is not atomic w.r.t. the sender's own state; the
  ordering rules govern the wire, not the sender's call stack.  §22.3 —
  re-entrant dispatch depth joins the bounded resources.
- **#125 (7-a)**: §22.3 gains the §23.5-parallel sentence: the bounding
  obligations are not relaxed by §6.2 — an unbounded delegate queue is the
  endpoint's own unbounded queue.

## Gates

§24.6 item 14 per class, in the wire suite over the real loopback harness:
latest-wins (flood of `state.changed` notifications: bounded, all
delivered or conflated per class rules, pause observed at HIGH, resume at
LOW, none lost after resume); ordered streams (editor deltas flood: all
dispatched in order, no conflation); intent (`event.action` requests
answered under load).  Sender ceiling: refusal shape at HOLD, hysteresis
at RESUME, exactly-once, `queue.replay` exemption, close-fails-locally.
Depth exhaustion: `log.error` observed then closed.  No device smoke: the
overload seam is Emacs-side and the Companion cannot be made to flood on
cue from hardware; the loopback flood IS the §24.6 vector, and the
Companion's half was device-proven in its own tier (RA-1).
