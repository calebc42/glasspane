# PLAN — executing the JA-1/JA-2 audit remainder

Source: `AUDIT-ja1-ja2-2026-07-26.md`.  This plan supersedes that doc's §7 fix
order: it folds in what has already landed, the R1/R2/R3 ratifications, and an
explicit home for every P2 and P3 so nothing dangles.  Detail lives in the
audit; this doc is the ledger and the ladder.

## 0. State

**DONE** (2026-07-26, each mutation-verified, suite green at each step):

| Commit | What | Landed |
|---|---|---|
| audit §7 commit 1 | P1-1 pump (pending-slot + in-flight claim + close/signal paths) | d331c4d |
| audit §7 commit 2 | P1-4/P1-5 grants: floor `jetpacs--gate-descriptor-policy`, `surfaces.dialog` in bridge-p, advertised-p fail-closed **narrowed to capability-gated targets** | 37e9cd9 |
| audit §7 commit 3 (most) | P1-2/P1-3: GATE 5, idempotent budget, chrome wraps once, cap-spans zero clause + `(max 1 left)` dropped | 5479b71 |
| audit §7 commits H/I naming | P1-6: `jetpacs.clip`/`jetpacs.theme` rename, `jetpacs-reserved-owner-prefix`, claim-site discrimination | dcaf9c4 |

**Ratified** (PLAN-jetpacs-apps.md §8): R1 `jetpacs.*` reserved; R2 clip AND
theme stay base ("vanilla Emacs optimized for mobile use"); R3 amendment #126
option B (delete the Kotlin `meta`/`paren` reads).  **No remaining decision
gates any commit below.**

**Commit-3 residue** (deliberately deferred, land in E1): the node counter on
the budget cons; the chrome stack depth bound.

**Suite baseline: 427 tests / 17 suites** (2026-07-27, after E4 +9 and T +5).  Trust
no mutation result from a harness reporting fewer (the teardown suite runs
only under its selector — audit §3(h) baseline note).  The 358 figure this
line carried until E4 was stale by 55 tests: it predated work that landed
without updating it, so re-measure rather than trusting the number here.

## 1. Shape of the remainder

Six elisp commits (E1–E6), then four cross-artifact commits (K, C, T, S), then
one device gate (D).  E1→E2 is the only hard elisp dependency chain; E3–E6 are
independent of it and of each other.  K blocks the last step of E6 and the
golden half of C.  Every commit ends with: byte-compile clean under
`byte-compile-error-on-warn`, full suite green, and a mutation check on each
new guard — **assert WHICH error fires, not that one fires** (the GATE 5
lesson: a bare `should-error` on a stub client passes for the wrong reason).

```
E1 chrome ──► E2 routing        E3 W10   E4 redaction   E5 clip   E6 theme
                                                                    │(:meta del)
K kotlin ──────────────────────────────────────────────────────────┘
K ──► C contract/validator      T tests       S spec        D device gate (last)
```

## 2. The commits

### E1 — chrome correctness (audit commit 4 + commit-3 residue) — P2(a)

The multi-view machinery still holds N documents with one document's habits.

- [ ] `push-screen`/`pop-screen`/`reset-screens`: **defer the push** out of the
      mutate-then-signal shape (the drill at `jetpacs-chrome--drill` already
      documents and dodges this exact trap — give the three public verbs its
      shape, or roll back the stack mutation on signal).  The poisoned-entry
      aggravation makes this the worst P2: today one bad screen makes the
      surface unpushable for the process lifetime.
- [ ] Per-entry `condition-case` in `jetpacs-chrome--build`: a broken screen
      costs its own view (error card), never the whole multi_view.
- [ ] Namespace per-screen node ids (prefix subtree ids with the screen id at
      composition, or a document-wide id table across `--build`); add the
      obligation to the drill-seam docstring in navigate.
- [ ] `current_view` on refused pushes: record the view into the map at
      revision-claim time in `jetpacs-shell-push`; remember a refused
      `current_view` in the B8 callback and re-assert it on the requeue.
      (The audit verified `jetpacs-shell-current-view` lies after every
      Emacs-driven navigation — the record-at-push-time fix cures that too.)
- [ ] Pass the surface list to `jetpacs-teardown-functions` (compute once at
      the top of `jetpacs-teardown-owner`) — fixes chrome's stale-stack read.
- [ ] Commit-3 residue: node counter on the budget cons; stack depth bound
      (default 8 rendered screens, evict from the bottom).
- [ ] P3 rider: correct `jetpacs-chrome-push-screen`'s false W10-nil docstring
      (the surface path claims the revision before the ceiling can refuse).

### E2 — D1 routing (audit commit 5) — P2(b) — depends on E1

- [ ] **First**: bind `jetpacs-current-owner` in `jetpacs--dispatch` from
      `jetpacs--owner-of` — the root cause; every owner-derived default inside
      a handler starts working, exactly where SPEC 14.4 omits surface context.
- [ ] `jetpacs-owned-surface-p` over `jetpacs-shell--owner-surfaces`; clamp
      `jetpacs.clip.refresh`'s wire-named surface with it and document the
      clamp as THE D1 idiom (replaces the bare `(plist-get params :surface)`).
- [ ] Navigate: with the owner bound, the default resolves; when
      `jetpacs-in-action-p` and no explicit surface and no flow surface —
      **refuse** (snackbar + nil), never guess `app:main`.
- [ ] Drill-host hardening: `condition-case` around the funcall (the seam
      promises "never signals"); `jetpacs-chrome--drill` returns nil on a
      stackless surface; per-surface drill-host registry with the global as
      fallback; default-sentinel guards on both `with-eval-after-load`
      seizures (chrome + navigate) so a Tier-1's own host survives require
      order.
- [ ] Key the one-slot snackbar by surface.
- [ ] P3 riders: isolate `view.switched` subscribers (same isolation
      `jetpacs-teardown-owner` already uses); constrain
      `jetpacs-navigate-thunk`'s docstring to UI-only thunks.

### E3 — W10 / refusal hygiene (audit commit 6) — P2(c) — independent

- [ ] Tag ebp's synthetic local refusal `:ebp-local t` (callback-only, never
      serialized); require it in `jetpacs-refused-p` — a peer 1401 is
      byte-identical today and 1401 is a MANDATORY response code (dialogs).
- [ ] Cap + exponentially back off the B8 refusal-driven repush per surface
      (reproduced today: unbounded, backoff-free loop).
- [ ] On refusal: requeue the snackbar, skip `jetpacs-shell-after-push-hook`
      (the audit reproduced the user's durable confirmation being lost).
- [ ] `jetpacs-shell--send-remove` discriminates: requeue ONLY refusals/
      transport loss; a permanent `-32601`/`1201` is dropped loudly.
- [ ] Make `jetpacs-teardown-owner` idempotent (guard re-fires forever today;
      measured 3 calls = 3 sends).
- [ ] P3 riders (ebp.el): `integerp` on `retry_after_s` (audit commit 1 item,
      still open); `ebp-client--receipt-commit` must not answer `t` with no
      durable write (no db, no file) — signal or warn loudly.
- [ ] P3 riders (device): move the reminders grant check above the `cl-incf`
      gen bump; stop `remhash`ing the gen counter on teardown (monotonic, not
      per-set); `:at_ms` ceiling via `jetpacs--check-integer`.

### E4 — redaction + exposure (audit commit 7) — P2(d) — **DONE 2026-07-27**

- [x] `advice-add 'jsonrpc--warn :around`: fixed redacted string unless
      `ebp-log-events` (30.1's jsonrpc writes the raw frame body to
      *Warnings* — reproduced with a secret).  Ship with the §24.6 item 12
      test.  `ebp--jsonrpc-warn-redact`, scoped by `ebp--in-filter` so other
      jsonrpc.el consumers in the session (eglot) keep their diagnostics —
      a second test pins that scoping.  Redacting at `jsonrpc--warn` covers
      BOTH sinks: it calls `jsonrpc--message` (→ *Messages*) before
      `display-warning` (→ *Warnings*).
- [x] Obarray isolation: bind a throwaway `obarray` around the decode in the
      existing process-filter wrapper, remap dispatch names after (SPEC 23.5 /
      amendment A2; measured 20k interned symbols surviving GC).  §24.6 item 4
      test.  Shape: `(let ((obarray (obarray-make))) …)` around the rented
      filter, then `ebp--isolate-parsed-messages` at the wrapper's exit
      re-homes each parsed message onto the global obarray via `intern-soft`
      (a name interned nowhere else is peer-invented and is DELIBERATELY left
      on the dying throwaway) and swaps an unregistered method name for
      `ebp--unknown-method-sentinel`, so jsonrpc.el's pre-dispatch `intern`
      of it never reaches the global pool.  Timers cannot fire inside the
      filter's synchronous extent, so the queue is stable when we walk it.
      Known residue, accepted + commented: jsonrpc.el's bug#60088 re-entry
      reschedule would re-run the filter outside the wrapper, but that path
      needs `accept-process-output` inside our own filter extent, which no
      ebp code performs.
- [x] Commit buffer exposure records only after the node survives both
      budgets (today a discarded node's bindings stay armed and unshimmed).
      Implemented as *suppress-then-re-derive*: `jetpacs-buffer--defer-exposure`
      silences `jetpacs-buffer-expose` during the line build, and
      `jetpacs-buffer--expose-node-taps` reads the SHIPPED spans of the
      committed node.  This also closes the span-cap half the audit did not
      name — a tap the SPEC 4.5 ellipsis replaced is no longer authorized —
      and it leaves the public `jetpacs-buffer-line-spans` exposure-for-free
      contract intact for skins calling it outside the walk.
- [x] Scope the exposure table per document (surface + render generation),
      not per buffer render — chrome makes one document hold N renders.
      `jetpacs-buffer--exposure-document` is bound by
      `jetpacs-buffer-with-budget` (which already delimits exactly one
      SurfaceSpec and is already idempotent under nesting), and the NAMED
      `jetpacs-buffer-forget-exposed` supersedes a buffer only the first time
      per document.  The no-arg form stays an unconditional reset — it is the
      teardown/test verb, never a render step.
- [x] P3 rider: length-bound `jetpacs-toast` TEXT (the one uncapped text path).
      `jetpacs-toast-max-chars` (300) + a reusable `jetpacs-truncate-text`
      following the `jetpacs-buffer-cap-spans` rule (the ellipsis REPLACES the
      tail, so the result never exceeds the bound).

**Mutation-verified** (each guard reverted individually, test must fail):
redaction advice removed → item-12 test fails; throwaway obarray removed →
growth test fails; `--defer-exposure` forced nil → both exposure tests fail;
document scoping disabled → scope test fails; toast cap unwired → bound test
fails.  Two tests did NOT bite on the first attempt and were rewritten — the
GATE 5 lesson recurring: the document test first used two DIFFERENT buffers
(`forget-exposed` is per-buffer, so they never collided) and the budget test
counted nodes (the trailing `… output truncated` caption inflates the count by
one, masking exactly the one leaked line).  Both now assert SET EQUALITY of
authorized vs shipped `(pos . action)` pairs, which is immune to both.

### E5 — clip privacy (audit commit 8, shaped by R2: stays base) — P2(d)

The kill ring is the most sensitive data stream in Emacs and the snapshot is
device-persisted (SPEC 13.5).  R2 keeps the app in base; these fixes are what
make that defensible.

- [ ] **No push at registration** — the `require`-time
      `jetpacs-shell--schedule-repush` is the defect that defeats every other
      mitigation.  First `jetpacs-clip-show` (or first kill with auto-refresh
      on a claimed view) is the arming step.
- [ ] Arm the `kill-new` advice only while the view is claimed.
- [ ] `jetpacs-clip-exclude-functions`, consulted per ENTRY (the preview leaks
      too, not just the copy button), seeded: `auth-source`/`epa`/
      `.authinfo*`/`.gpg`-sourced kills.
- [ ] `jetpacs-clip-max-age` — never ship pre-pairing kills retroactively.
- [ ] Tombstone the surface when backgrounded; teardown hook; a retraction
      path (clearing `kill-ring` must be able to clear the device).
- [ ] KEEP `jetpacs-clip-auto-refresh` default t — the P3 note + D-12
      deprioritize the multi-app scenario; the load-time push above was the
      real defect.  (Flip to nil only if Caleb asks.)
- [ ] P3 riders: entry `:key` suffixed with RING POSITION (not kill text —
      duplicates are legal and sibling keys are MUST-unique); Core-Node-Set
      fallback for the card (chrome kit too).
- [ ] Tests: byte-cap asserted on the NODE (10k-char kill → `string-bytes` of
      the descriptor ≤ 4096); the debounce counter test (20-kill storm → 1
      push — deleting the `cancel-timer` pair is green today).

### E6 — theme seams (audit commit 9, reframed by R2) — P2(f)

Not a split — the seams let a Tier-1 build on modus 5.0's public API without
fighting base for the palette.

- [ ] `off` in the `jetpacs-theme-mode` enum (today loading the file seizes
      `theme.set`: default `system` CLEARS a Tier-1's persisted palette 0.2s
      after every READY).
- [ ] `jetpacs-theme-payload-function` — an explicit payload wins over the
      mirror.
- [ ] Split the `jetpacs-modus-*` queries into a hook-free module (they are
      the documented public substrate; requiring them must not arm hooks).
- [ ] First READY frame synchronous (or delete the false ordering comment) —
      the 0.2s debounce exists for `load-theme`'s disable+enable pair, not
      for READY; today first pairing flashes the wrong palette.
- [ ] Teardown hook; the three wiring assertions (ready hook, enable/disable
      theme hooks — both deletable green today); the debounce inner-re-gate
      test (arm granted, then mutate grant/state before draining).
- [ ] **AFTER K lands**: delete the `:meta` duplicate at both emit sites, the
      pin-test carve-out `(unless (eq k :meta) …)`, and the vacuous
      `(equal nil nil)` meta assertion.

### K — Kotlin (R3 = option B) — **DONE** (session C, APK rebuilt+installed)

- [x] Delete the `meta` and `paren` reads in `SyntaxHighlight.kt`; add a `tag`
      field to `SyntaxColors` + `emacsSyntaxColors` and use it for org tags at
      `styleOrgLine` (today a `:work:` tag renders in the preprocessor pink,
      not its lavender); read `preprocessor` directly.
- [x] Correct the false "the contract fixes no syntax_roles" comment.
- [x] `validateReminder` rejects `capture_fields` (verified 2026-07-27 at
      `CompanionEngine.kt:1165`, citing #133) (#133's receiver half).

### C — contract + validator (amendments #127, #135) — **DONE** (session C, submodule d48075d)

- [x] `syntax_style` schema (`fg bg font_weight italic underline`); `fg` into
      `field_types`; the app multi-view variant into `surface_spec_variants`.
- [x] `validate.py` walks `theme_roles`/`syntax_roles`/`SyntaxStyle` and the
      variants — **the highest-leverage item in this plan**: these are the
      only contract sections the validator ignores, and that blindness is
      mechanically why the `meta` drift survived three rungs.
- [x] Regenerate the `theme.set` golden with the full role set + ≥3 syntax
      roles.

### Filed during E1 (new, not in the audit)

- **dialog.show is knowingly ungated for size** — `jetpacs-shell--gate-size`
  is reusable as-is (client + spec), but neither `jetpacs-dialog--ask` nor
  `jetpacs-sections--show-menu` calls it, and `jetpacs-dialog--gate-spec`
  recurses through `:children` only (the E1f gate walks every non-opaque
  member).  Land with the first dialog-touching commit.
- **Two-pass top-first chrome render** — the E1f depth-bound default is 3, not
  the audit's 8, because bottom-first rendering starves the TOP screen of the
  shared budget; the two-pass fix inverts `jetpacs-claim-node-id` claim order
  (root-literal-first is what the E1c seed semantics pin), so it needs its own
  design pass.
- **`jetpacs-shell--build`'s error spec ships `error-message-string`** —
  prescribed by SPEC-JC-0-floor.md:193; E4/S doc+code amendment.

### T — tests (audit §3(h) + §6 test P3s not landed in E1–E6) — **DONE 2026-07-27**

- [x] The navigate×chrome integration file in `run-tests.sh`: assert the live
      seam wiring `(eq jetpacs-navigate-drill-function #'jetpacs-chrome--drill)`
      and the stackless-surface nil — today the entire drill feature can die
      with green CI.  Landed as `test/jetpacs-integration-test.el`, deliberately
      scoped WIDER than the drill seam: it is the one process that requires the
      application layer TOGETHER, which is the structural fix for §3(h) rather
      than a patch for its one visible symptom.  Requires chrome BEFORE
      navigate on purpose — that exercises the `with-eval-after-load` backfill
      branch no other suite reaches.
- [x] Mutation-resistant replacements.  Three of the five were **already
      landed** in E1–E6 and were verified rather than rewritten: the wire-id
      prefix-length term (`jetpacs-widgets/wire-id-ceiling-and-bad-prefix`
      errors on a 101-char prefix), the POSITIVE snackbar assertion in
      `jetpacs-navigate-thunk-error-redaction`, and teardown's
      `(= (length removed) 1)`.  The two real gaps are now closed in the
      integration file: `jetpacs-teardown-functions` coverage for device
      (confirmed by mutation that deleting the `add-hook` was green across
      device/teardown/phase-a), and a stub-free W10 ceiling test — the device
      suite's version stubs `ebp-client--request` wholesale and feeds the
      callback a hand-written 1401, so it asserts that `jetpacs-reminders-set`
      READS a refusal, never that ebp PRODUCES one.  The new one drives a real
      loopback companion that simply never answers `reminders.set`, so
      outstanding accumulates over a real socket and the ceiling does its own
      work; it also pins the `:ebp-local` discriminator and that the refused
      request never reached the wire.

**Mutation-verified**: deleting chrome's `with-eval-after-load` fails the seam
test; deleting device's `add-hook` fails both teardown tests; dropping the
`:ebp-local` tag fails the ceiling test.  Suite now **427 / 17**.

### S — SPEC prose (#127–#136 as ratified; #126 needs no text under option B)

- [ ] #127 syntax-style pinning; #128 variant transition; #129 welcome
      current view; #130 the 1401 discriminator (write ebp's `:ebp-local`
      invention into the spec — E3 implements it); #131 durability
      discriminator; #132 pie-menu observability; #133 capture_fields; #134
      the R1 reservation text; #135 multi-view variant; #136 warning sinks
      (E4 implements it).
- [ ] B9 riders: the password-event no-retry paragraph; the note that an
      unhandled handler signal is silently a permanent `rejected` (E3/E2
      soften this with `jetpacs-commit-or-retry` at the floor, quit → 1500).

### D — device gate (last, after K's APK)

- [ ] Re-run smoke-ja2 + theme-mirror + clip smokes against the new APK.
      Note the owner rename: the tablet holds orphaned `app:clip`/`app:theme`
      snapshots from JA-1 — remove them via Companion settings or reinstall.
- [ ] The P1-1 rider from audit commit 1: a SECOND "Retry me" tap in
      smoke-ja2 P6 (the drained-then-retry cycle on real hardware).
- [ ] New smoke moments: drill to depth 3+ under a small `max_rich_spans`
      (E1); a refused push re-asserting `current_view` (E1/E3); org tag color
      on device (K).

### E5 demotion (Caleb, 2026-07-26)

E5 (clip privacy) moves to the TAIL of the plan, after S and before the
device gate.  Rationale: on Android the KEYBOARD (Gboard et al.) already
carries its own device-wide clipboard history, so much of the
kill-ring-privacy hardening duplicates exposure the platform has
anyway.  When E5 does land, the load-bearing piece is
**no-push-at-registration** — that one is a correctness defect
independent of privacy (a bare `require` during a live session ships
the whole kill ring and seizes the tablet screen), and the cheap
non-privacy riders (`:key` on entries, the byte-cap-on-the-NODE test,
the debounce test) ride along.

## 3. Session batching (usage-limit aware)

Each elisp commit is sized to land inside one session comfortably; nothing
shares state across commits except E1→E2 and K→(E6 tail, C).

- **Session A**: E1 then E2. DONE 2026-07-26.
- **Session B**: E3 DONE; **E4 DONE 2026-07-27** — all elisp commits are now
  landed.  Still owed for E4: the ONE connect-smoke device re-run below (it
  wraps the process filter), and the S-commit prose for amendment #136.
- **Session C**: E6 DONE; K DONE (APK rebuilt+installed); C DONE (submodule
  d48075d, both rail halves verified to bite).  **T and S remain.**
- **Session D**: **DEVICE GATE PASSED 2026-07-26** on the new APK:
  smoke-theme-mirror 6/6 (synchronous READY paint, renamed toggle through the
  :any-surface gate) and smoke-ja2 16/16 — including "delivered three times
  (1500 x2 then accepted)", the P1-1 pump cycle on hardware.  E5 (demoted)
  remains.  After E4 lands, ONE connect-smoke re-run (it wraps the process
  filter); no full gate needed.

If a session must shrink: land E1 alone (the unpushable-surface trap is the
worst live defect remaining), then E3 (the lost-confirmation reproduction).

## 4. Explicitly not planned

The audit's 14 refuted findings (§8) stay closed.  P3 "latent" items with no
reachable trigger today and no host commit above (the magit denylist — already
on D-10's rescope list; `jetpacs-dialog--gate-spec`'s builtin/feature thirds —
unreachable until a Tier-1 authors a dialog image, rider on the first commit
that touches dialog gating) are recorded here as accepted debt, not lost.
