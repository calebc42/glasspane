# REVIEW — poc-v1 vs the rewrite: what actually improved (2026-07-27)

**Question:** objectively, what improved from `llm-poc` (poc-v1, branch
`slop-fork/poc-v1`) to `llm-poc-2` (the rewrite, branch `slop-fork/main`) —
and what regressed?

**Method:** 4 comparison lenses (architecture, conformance, verification,
losses) produced 78 evidence-cited findings; an adversarial critic re-checked
the load-bearing ones on disk and ruled 56 KEEP / 16 REPHRASE / 6 CUT —
cutting boosterism, double-counts (CI-absence was reported four times;
counted once), and anachronistic blame.  The three most surprising claims
(the ebp.el LOC inversion, the reconnect regression, the v1 foreground
service) were then re-verified by hand.  Both trees read at their 2026-07-27
HEADs.

---

## 1. Hard metrics

| | v1 | v2 |
|---|---|---|
| elisp source LOC | 23,714 | 12,867 |
| elisp test LOC (files) | 8,984 (3) | 9,620 (16) + 3,583 smoke (42) |
| Kotlin source LOC | 14,143 | 13,632 |
| Kotlin test LOC (files) | 1,893 (19) | 7,958 (38) |
| Kotlin test:source ratio | 0.13 | 0.58 |
| SPEC citations in source | 158 | 1,362 |
| citation density | 1 per 244 lines | 1 per 19 lines |
| markdown docs | 39 (~209 KB user-facing) | 28 (~9 KB user-facing) |

Reading the LOC rows honestly: the elisp halving comes from the *unrebuilt
application layer*, not from economy in the wire core — see §5.  The Kotlin
test rows are the real story.

## 2. The verdict in one paragraph

The rebuild's central claim is true and measurable: v2 drew a protocol seam
v1 never had, and everything real in the improvement column descends from one
constructor change — v1's engine took an Android `Context` + a live
`Socket`; v2's takes config + `sink: (ByteArray) -> Unit`.  But the ledger
runs both ways: v2 currently regresses on availability, reconnection, inbound
robustness, device breadth, and everything a second person would need (docs,
CI, install path).  And every green number in v2 is demonstrated-once, not
enforced — there is no CI, so nothing runs unless someone types it.

## 3. What genuinely improved

- **The protocol seam.** `:wire`: zero `android` occurrences across 61
  files; imports only `java.*`/`javax.crypto`/`org.json`; `kotlin.jvm`
  plugin only.  v1's `:jetpacs` "library": 42 of 49 sources import
  `android.*` (684 import lines) and it re-exports Room/Compose/Coil as
  `api` dependencies.  `CompanionEngine(config, ..., sink)` +
  `feed(bytes)` vs `JetpacsConnection(context, socket, ...)` spawning its
  own reader thread.
- **Testability, as a direct consequence.** v1 has no test at all for
  `JetpacsConnection` or `JetpacsServer` — its two largest protocol classes
  were unconstructable off-device.  v2's engine test alone is 680 LOC; 34
  plain-JVM wire test files, 7,530 LOC.
- **Golden method coverage** (re-derived, not trusted): v1's
  `frames.golden` exercised 3 of its own contract's 24 methods; v2's
  exercises 28 of 28, and `validate.py:757` makes that floor
  machine-enforced.
- **Editor sync entered the contract.** v1 emitted six `edit.*` methods its
  own contract.json never declared — the most position-math-sensitive wire
  surface was machine-unchecked.  All six are in v2's contract.
- **Byte-level adversarial conformance:** 17 `.bin` fixtures with typed
  outcomes, replayed at whole/1-octet/7-octet chunkings.  v1's
  cross-implementation test (`WireGoldenConformanceTest`) is the ancestor;
  the byte and chunking dimensions are new.
- **Prose-to-machine binding:** `check_spec_sync` fails on any row present
  in SPEC.md §8/§11 but missing from contract.json, in either direction.
  v1 had no equivalent.
- **Negative-path testing:** `should-error` assertions 17 → 192, with
  boundary-exact pairs (64 containers pass / 65 signal).
- **Real transport in the elisp tests.** v1's suite had zero
  `make-network-process` — framing, auth, and session lifecycle were never
  executed by any v1 test, only stubbed (~200 `symbol-function` sites).
  v2 drives a live TCP loopback companion through the full handshake.
- **The byte-compile-error-on-warn guard**, demonstrated empirically: the
  unescaped-docstring-quote bug class compiles clean under plain
  `batch-byte-compile` and fails hard under v2's guard.
- **The self-audit practice.** Nine severity-classified audits with
  file:line citations; AUDIT-ja1-ja2 ran mutation-style checks against the
  test suite and every named blind spot re-checked has since been closed.

## 4. What genuinely regressed

- **CI, entirely.** v1 ran the isolation guard, both ERT suites, a
  bundle-currency check, a package-vc install test, and Android
  tests/lint/assemble on every push.  v2 tracks no workflow file.  This is
  the load-bearing regression: it converts every improvement above from
  "enforced" to "ran once".
- **Availability.** v1's accept loop lived in a foreground service
  (`jetpacs/src/main/AndroidManifest.xml:99`,
  `FOREGROUND_SERVICE_SPECIAL_USE` + the Play-justification property).
  v2 binds the socket in `MainActivity.onCreate`; no `<service>`, no FGS
  permission — ironic against the manifesto's listener-survivability
  argument.
- **Automatic reconnection.** v1: in-transport, 5s→60s backoff, on by
  default (`jetpacs-reconnect`).  v2: deferred to the caller; no caller
  implements it (`device/init.el` retries only the initial connect, 45 s).
  REWRITE-PLAN lists reconnection under W3 — a rung claimed landed.
- **Inbound robustness — the rental's price.** jsonrpc.el enforces no
  Content-Length ceiling (v1 discarded oversized bodies byte-exactly,
  without buffering, answering `1400 frame-too-large`) and bounds its
  header-section search at ~100 chars where SPEC 6.2 declares 8,192.
  v2's own bounded decoder (`ebp--parse-body`) is reachable only from
  tests, not the live path.
- **Device surface breadth.** Home-screen widgets and QS tiles gone with
  no rung scheduling them; capabilities 17 → 2; trigger types 15 → 4;
  sampleable state predicates 11 → 1; the `wake` offline policy declared
  in `:wire` but never assigned in `:app`.
- **The elisp contract binding.** v1's `jetpacs-lint.el` derived
  node/method/error vocabulary from contract.json at load, with
  `build-contract.el` as a lossless round-trip witness.  v2 hand-writes
  mirrors pinned by equality tests — weaker in kind, not just coverage.
- **Onboarding.** User-facing docs ~209 KB → ~9 KB; zero written build
  instructions (no markdown in v2 mentions `gradlew`); no tutorial, no
  architecture doc, no package install path; no `Version:` header on any
  of the 19 elisp modules.
- **Pairing.** An 80-bit SecureRandom token behind an 826-line wizard →
  the SPEC's own published known-answer vector hardcoded on both ends
  (`DeviceBridge.kt:110`).
- **`granted` unenforced in ebp.el** — absorbed from welcome, never
  consulted; `theme.set`/`dialog.show` emit unconditionally.  Gating
  exists only in the jetpacs layer above, so a consumer using ebp.el as
  the reference endpoint (its stated purpose) is ungated.  v2's own open
  P1.

Of these, the module-level absences are ladder-deferred and marked so;
**availability, reconnection, and `granted` gating are not on any rung** —
those three are the open gaps a reader should carry.

## 5. Merely different (neither better nor worse)

- alist + `:null`/`:false` sentinels → jsonrpc.el plists (the rental's
  idiom; 301 `alist-get` sites → 359 `plist-get` sites).
- 2 → 19 batch test processes: isolation gained; cross-module loading lost
  (mechanically the cause of the audit's headline blind spot).
- Golden snapshotting relocated from inside `ebp/goldens/` (v1 regenerated
  contract fixtures from its own code — the wrong place) to
  `test/goldens/` one layer up.  The technique survived; the authority
  moved.
- minSdk 24 → 34: ten API levels of reach for a class of removed compat
  branching — a trade, on a single-tablet project.
- Distribution: a CI-verified 1.1 MB single-file bundle + an 89-line
  deploy.sh (Termux ssh + Windows paths) vs an 11-line adb push of 19
  files.  v2's is simpler and works; v1's reached places v2's does not.
- The `rich_text` span vocabulary narrowed (strike/code/tag/baseline
  removed) — a format-6 contract decision binding both ends equally.

## 6. The two caveats to hold

**The conformance delta partly measures the arrival of a spec, not rebuild
quality.**  "v1 had no spec" is false — the ebp repo's initial commit is
2026-07-15; v1 ran 2026-06-30 to 2026-07-22 and acquired the spec on day 16
of 23; the authority inversion landed one day before v1 ended.  Findings
scoring v1's citation count against v2's are largely measuring build order.
The contract is also authored by the implementation's author — it is a
discipline, not an independent authority.  (Provenance nit found on the way:
amendments #31–#33 are absent from both checked-out SPEC-CHANGES logs.)

**The ebp.el LOC inversion.**  v2 deleted ~464 lines of hand-rolled
transport by renting jsonrpc.el — but `emacs/ebp.el` is 1,923 lines against
v1 `jetpacs.el`'s 867, while renting jsonrpc.el's 1,180 on top.  The
endpoint file more than doubled; the rewrite's elisp economy lives in the
unrebuilt app layer, not the wire core.  (What grew is largely spec surface:
receipts, overload, the reference decoder, session verify/absorb — but the
"leaner" narrative should not be repeated without this footnote.)

## 7. Bottom line

The seam is real, the conformance machinery is real, and the verification
culture transformed (test:source 0.13 → 0.58, 42 device smokes, 9 audits).
The price so far: availability, reconnection, inbound bounds, breadth, and
shareability.  The single highest-leverage act available is already queued:
push both repos and land CI, which flips every demonstrated-once claim to
continuously enforced.
