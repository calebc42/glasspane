# Completion excellence ladder (Glasspane rebuild track)

UPDATE 2026-08-13: amendments #169–#172 are RATIFIED AND APPLIED (ebp
submodule 2cd7387, pin 41c7b46; the ratification/verification record
is docs/DRAFT-amendments-169-172-completion.md). R3, R4, and R5 are
now pure implementation rungs — their wire vocabulary exists, the
validator rails bite, and the per-rung Companion/Emacs duties are
named in the ledger rows (#169/#171/#172) and the draft doc.

Status: R0 LANDED. Ratified 2026-08-12 alongside the Glasspane rebuild
decision: v1-quality completion/eldoc/eglot support is the focus, and
the architectural rulings are settled — EBP and LSP are different
layers that already coexist (eglot terminates LSP inside Emacs and fans
results into the built-in middleware the ebp-sync riders and
ebp-complete harvest); the Companion is never an LSP client; the SPEC
never requires LSP; the Glasspane app layer treats an eglot-managed
real buffer as the *expected* completion source for programming modes,
degrading silently when no server exists.

No SPEC loosening anywhere below except R4's narrow selection-gate
prose relaxation, which grants receiver behavior, not interpretation.

## R0 — attach-aware completion routing (LANDED)

The headline v3 gap: `edit.complete` was answered client-wide by the
SHADOW harvester, so an eglot-managed buffer's capf never ran even
though jetpacs-files attaches that exact buffer for the riders.

- ebp.el: `edit-complete-overrides` on the client struct — per-document
  completion sources consulted before the client-wide
  `:edit-complete-function`. The single-mutable-slot defect (a dialog
  picker borrowing the slot answered every other document empty) dies
  at the layer that owned it.
- ebp-sync.el: `ebp-sync-attached-buffer` (DOCUMENT EDITOR-ID) — the
  clientless routing lookup, sound under the JC-0 single-client floor.
- ebp-complete.el: the live-buffer arm. When the attached buffer's
  (widened) text equals the mirror TEXT, harvest THERE — eglot and
  every buffer-local capf answer; on divergence (mid-flush), timeout
  (`ebp-complete-live-timeout`, a thinking LSP server), or no attach,
  the shadow answers exactly as before. A live harvest that finds
  nothing IS the answer (the shadow runs a subset of the same sources).
- jetpacs-dialog.el: the picker registers its own document in the
  override table instead of borrowing the client-wide slot.

Hazards bounded, not eliminated (recorded in `ebp-complete--live-harvest`):
`with-timeout` cannot interrupt a capf spinning in C without yielding
(the #137 shape), and the ebp process filter may dispatch an inbound
`edit.delta` under a waiting harvest — costing at worst a garbage offer
the Companion's SPEC 19.3 selection gate discards.

Adversarial review (13 raw findings, 4 confirmed, all fixed same day):

- An empty live harvest FALLS THROUGH to the shadow — nil-as-final
  silenced `ebp-complete-shadow-setup-hook` sources (the module's own
  extension point, which attached buffers never run) for every
  attached document.
- `ebp-complete--live-harvest-active` latch: `with-timeout` mints its
  catch tag at MACROEXPANSION time, so two stacked live harvests share
  one tag and the inner catch steals the outer timer's throw. The
  latch routes a nested `edit.complete` to the shadow, so harvests
  never stack.
- The same flag defers `jetpacs-flow-continue` continuations
  (reschedule at 0.05s) while a harvest is on the stack: a
  continuation may WAIT (a bridged prompt, hub.eval), and the timeout
  throw unwinding through one would abandon the prompt mid-round-trip
  with no rpc.cancel.
- The picker's quit path (dismiss → keyboard-quit) is pinned: the
  override-table remhash is an unwind-protect obligation, and the
  moved-remhash mutant previously survived the whole suite.

Companion-side hardening noted for a later Kotlin pass (NOT blocking):
`requestCompletion`'s reply callback checks only sessionId, not seq
(CompanionEngine.kt:1891), so a slow reply for an old seq can clobber a
fresher offer in DeviceBridge's latest-write-wins map; taps on it are
refused by selectCompletion's seq gate, so it self-heals on the next
keystroke.

## R1 — eglot lifecycle port (the v1 crown jewels) (LANDED)

Ported from poc-v1 `core/jetpacs-sync.el` into ebp-sync.el's new
"language tooling arm" section, with four deliberate deltas from the
reference:

- v1's two-arm buffer strategy (real buffers for eglot modes, shadows
  otherwise) is NOT ported — v3 binds real buffers universally, so
  only the lifecycle logic was missing. `ebp-sync--ensure-eglot` runs
  at every attach: direct async `eglot--connect` (the `eglot-ensure`
  `post-command-hook` deferral never fires headless — verified at
  emacs-30.1 eglot.el:1455-1476), 30s buffer-local throttle that both
  prevents double-connect races and spaces the reopen attempts that
  revive an OS-reaped server. Gated by `ebp-sync-eglot` +
  `ebp-sync-eglot-modes` (elisp/org excluded on purpose).
- The gate got a `file-remote-p`-before-`file-exists-p` guard v1
  lacked — the house remote-before-stat invariant.
- The in-process elisp flymake backend (paren scan + temp-copy
  byte-compile, no `emacs -batch`) is swapped in at attach and
  RESTORED at detach: v1 swapped inside jetpacs-owned shadows, but v3
  binds the USER's buffer, so the swap is session-scoped.
  `ebp-sync-elisp-repl` carries the REPL lexical-binding-cookie
  variant for a future REPL attacher (the hub editor is not attached
  yet).
- The `flymake-start` kick per arm (headless idle timers unreliable)
  is gated on real backends. Test lesson: `flymake-mode`'s own enable
  calls `flymake-start` internally — a kick test must reset its
  counter after attach or it counts stock behavior.

Adversarial review (14 raw findings, 6 distinct confirmed, all fixed
same day):

- **The throttle is PROJECT-keyed** (`ebp-sync--eglot-attempts`), not
  buffer-local: with `eglot-sync-connect` nil the server reaches
  `eglot-current-server` only after the async initialize handshake, so
  a buffer-local stamp let a second file of the same project spawn a
  second server during cold init — leaked process, project silently
  split across two servers. (A faithfully-ported v1 bug.)
- The in-process backend **widens** — the stock backend it replaces
  widens too, and the wire ships whole-document offsets; unwidened, a
  narrowed buffer shipped spurious paren errors and misplaced
  squiggles.
- The `flymake-start` kick moved **off the dispatch path onto the
  settle timer** (`ebp-sync--push-diagnostics`), and the flymake
  enable is start-suppressed — a synchronous whole-buffer compile per
  keystroke inside the jsonrpc callback was the hot-path finding; a
  plain `run-at-time` timer fires fine headless, which was the whole
  rationale.
- The swap is **platform-gated** (`ebp-sync-elisp-inprocess`, default
  Android-only): in-process compilation runs macro expansion in the
  LIVE session and a pathological form can wedge a headless Emacs, so
  stock's subprocess isolation stays wherever spawning works.
- The in-process compile **mirrors stock's 30.1 `trusted-content-p`
  gate** (macro expansion IS evaluation), degrading to paren diags +
  one :note instead of stock's user-error.
- The paren pre-scan **no longer suppresses compile diagnostics** (an
  unescaped `?(` char literal false-positives it); the truly-unbalanced
  case drops the compile's duplicate end-of-file error.

Stated, accepted deltas (in the backend docstring): sibling `require`s
unresolved (no "-L ." equivalent), and compile-time evaluation runs
live on the Android path — both are why the gate defaults off
everywhere else.

After R0+R1: LSP completion + diagnostics + hover on device = v1
parity for programming modes, pending the desktop-uds/device smoke.

## R2 — exit-function + additionalTextEdits (LANDED)

The wire deliberately does not mark a completion accept (SPEC 19.3: a
tap is an ordinary local edit), so Emacs INFERS it: the live harvest
mints `ebp-complete-live-offer` when the winning capf supplied an
`:exit-function` (keeping the PROPERTIZED candidate strings — eglot's
LSP item rides text properties the wire strip would destroy), and
`ebp-sync`'s splice watch recognizes the splice that replaces exactly
the offered prefix at the offered cursor with an offered insert. Any
other splice for that document clears the offer.

The exit function runs DEFERRED off the jsonrpc dispatch (it may block
— eglot resolves against its server), revalidated at fire time,
latched non-reentrant (the R0 `with-timeout` tag lesson), bounded at
1s. Whatever it edits — snippet-fallback text, `additionalTextEdits`
auto-imports — flows back through the ordinary track-changes →
`edit.apply` loop: NO special wire traffic, which is why R2 needs no
SPEC change. The Companion never learns Range/TextEdit — coordinate
authority stays withheld.

Also landed: the `publishDiagnostics` push-latency hook (an
`eglot-handle-notification :after` method: URI → attached buffer →
collect at 0.5s instead of waiting out the 3s settle) and the
`eglot-managed-mode-hook` arm (a server that comes up after attach
ships its first diagnostics without waiting for an edit).

Adversarial review (10 raw, 5 confirmed, all fixed same day):

- **Provenance by shape.** The accept inference can be forged: paste,
  swipe-typing, and IME word commits produce accept-shaped splices.
  The Companion's typed path emits MINIMAL diffs while the tap path
  emits the untrimmed prefix-replace, so the watch now additionally
  requires the deleted prefix and inserted text to share their first
  or last scalar — a shape the minimal diff could never emit, hence
  provably a tap. Ambiguous shapes and the empty-prefix shape (del 0,
  indistinguishable from insertion) never fire; missing a rare
  flex-tap is the safe direction. The exact fix is a one-member wire
  provenance marker (`accept: true` on the tap's delta) — a SPEC
  amendment PARKED with R3-R5.
- The offer is claimed at EVERY session lifecycle boundary
  (`ebp-sync--claim-offer`): every splice for its document including
  the resync branch, reseed, resync, detach.
- The runner's blocking extent is covered by BOTH R0 guards: it binds
  `ebp-complete--live-harvest-active` (nested `edit.complete` takes
  the shadow — no request handler parks on the throw path) and
  `jetpacs-flow-continue` also postpones on `ebp-sync--exit-fn-running`.
- A latched second accept RE-ARMS (20 × 0.05s, revalidation makes a
  stale run self-cancel) instead of silently dropping its auto-import.

## R3 — candidate `kind` (SPEC amendment) + icon render (LANDED)

Optional `kind` string on the §19.3 candidate: the LSP
CompletionItemKind 25-name vocabulary as lowercase strings (eglot emits
exactly these via `eglot--kind-names` / `:company-kind`), §22.4
feature-gated because the candidate object is closed. Companion renders
leading icons. Queues behind a device gate + push.

## R4 — survive-typing offers (SPEC amendment) + local narrowing (LANDED)

Relax §19.3's selection MUST-discard: MAY-apply when the only
divergence since the request is a typed prefix-extension matching the
candidate (replaced range = extended prefix). Companion narrows the
list locally instead of clearing on keystroke — v1's perceived-zero-
latency ingredient. Wire shapes unchanged; Emacs sees an ordinary delta.

The adversarial review returned nine confirmed findings (none
refuted), all fixed in the follow-up commit: explicit-empty `insert`
conflated with absent at both parse sites (a §19.2 wrong edit on
accept); reply-time cursor equality in the arm gate (the SPEC's caret
is never the comparand — seq alone proves text identity); the
narrowing predicate applied to PRISTINE offers (the base path is an
unconditional MUST, and Emacs tables are not prefix engines);
edit.resync not claiming the Companion tracker (an accept could cross
a session boundary — seq restarting at 0 is indistinguishable from an
offer armed at seq 0); the Kotlin/elisp divergence on the degenerate
del-0 empty-text splice (qualifies on both sides now); and the
display plumbing rebuilt as OBSERVED state (`DeviceBridge.offerViews`)
published after each tracker mutation — no more per-keystroke
@Synchronized engine reads on the main thread (the monitor is held
across blocking socket writes), no pre-splice reconcile race, and a
reply the arm gate refused is never handed to the display.

## R5 — lazy candidate docs (amendment #172 implementation) + doc panel (LANDED)

LANDED 2026-08-13. All six decision points executed on their recommended
arms (Caleb's continue-and-execute ratification): long-press gesture,
range-1201 with NO data.reason, cell outlives the offer claim, the
dynamic-var provider seam, the serve()-finally ghost fix riding R5, and
an empty doc showing NO panel. Two deltas from the plan text, both
additive: the slot class carries a TICKET per flight (a conclusion must
name the exact flight it ends — after a retire, a stale conclusion could
otherwise free or re-arm a slot a fresh offer's flight now owns), and
the renderer's three-condition show gate is extracted as a THIRD pure
helper (`candidateDocVisible`) because no Compose test rig exists, which
is what made the epoch/narrowed-set/empty-doc mutants killable. The
elisp collect now builds ONE stripped→first-raw map in the strip pass
and the R3 kind lookup plus the R2 mint-offer pairing were repointed at
it (the F2 fix subsumed both older cl-find-if probes). Everything else
below shipped as written; the section is kept as the design record.

POST-LAND ADVERSARIAL REVIEW (same day, 4 lenses → 14 raw findings →
12 verified by 3 skeptics each, all 40 verifier agents live): 10
CONFIRMED unanimously, 2 refuted, plus 2 uncapped test-pin gaps
hand-verified. All fixed in the follow-up commit. The two P2s: (1)
per-instance slot tickets restart at 1 and the conclusion lambda
re-resolved the slot BY KEY, so after an offer death replaced the
instance, a slow reply's stale conclusion matched the fresh instance's
first flight and disowned it mid-air — fixed by concluding on the
INSTANCE the flight was issued from, with retire now IN PLACE (drops
only the desired pair; the outstanding flight keeps occupying, so a
fresh offer's long-press queues instead of double-issuing — which also
closed the transient one-outstanding violation); (2) the F11 epoch
admission was untestable bridge glue — extracted as the pure
`offerEpochCurrent`, used at gesture/publish/reissue alike. Notable
overturn: the plan's closed-key loop on candidate.doc's RESULT was an
over-reject MUST violation — SPEC 12 rule 1 defaults receivers to
IGNORE unknown optional members and §19.3 declares closed objects only
for edit.complete's result, so the engine now ignores them (the
growth-model asymmetry, cited by the review). Also fixed: the retained
cell stores the NORMALIZED seq (a float-seeded mirror would eql-refuse
every fetch); the serialize gate runs BEFORE the cap (garbage past
16384 octets must answer "", not ship an innocent-looking prefix);
ebp-sync--run-exit-fn postpones on the HARVEST latch too (its timer
can fire inside the doc provider's throw-armed wait — the R0 trap
shape); serve()'s finally wipes the shared display maps only when its
own connection was still the live one (clearLiveSession now returns
the CAS verdict — the pre-existing mirrors/annotations wipes had the
same supersession hole); and the doc panel's scroll state is keyed on
the documented row. Test deltas: the empty-arm mint asserted directly
against the hash (range-1201 vs stale-1201 are wire-indistinguishable),
the out-of-order test pins that the outer reply still goes out, a
float-seeded-mirror test, a garbage-past-the-cap degrade case, and the
rearm test covers the harvest-latch postpone.

DEVICE BATCH (same day, Pixel Tablet, commit after the review fixes):
smoke-r5-docs.el SMOKE PASS — three kind icons drawn (R3), long-press
doc panel with §16.4-verbatim text, empty-doc no-panel, accept:true on
the tap and absent on the keystroke; the R4 settings row was BUILT
(companion.settings.open's toast stub replaced by an app-owned dialog)
and verified through the prefs file both ways; smoke-files-sync.el
re-ran green (B1-B7 — the P1 save fix train is finally
device-verified); smoke-eglot-lsp.el (desktop, real
typescript-language-server) proved headless eglot connect at attach,
server members through the live harvest, kind + exit-function armed,
real squiggles through the rider, and the server's JSDoc through
edit.candidate.doc — the review-P1 scenario against real eglot. The
batch also CAUGHT one pre-existing display defect (fixed same commit):
a successful tap-accept never republished the mirror, so the field
kept the pre-tap text until the next keystroke bounced off the #100
gate and snapped back, swallowing that keystroke. Still owed: P1's
desync/concurrency smoke sub-clauses (the D-2 ledger row).  (The
on-device Android-Emacs + Termux pylsp smoke RAN 2026-08-13 — the
measured cold-pylsp timings live in device/emacs-init.el Stage 3b and
the harness at tools/onboard-tablet.sh + device/py/live.py; 6b7bbfd,
02e4087, f131130.)

Amendment #172 is fully applied: SPEC §19.3 normative text
(SPEC.md:3328-3345), the §11 registry row, contract.json's method
entry (params {document, editor_id, session, seq, index}, result
{doc}, errors [1201]), frames.golden's request/reply pair (lines
47-48), validate.py's generic `check_result` walk, and Kotlin
MethodRegistry all landed with the amendment adoption. R5 owes ONLY
the two implementations the amendment's artifacts column deferred:
the Emacs retention cell + handler, and the Companion doc panel +
highlight-driven request.

### The comparand, stated once

The request names the session and seq **of the retained edit.complete
reply** — never the live mirror. Mid-#171-extension the mirror's seq
has legitimately advanced past the reply's; validating against the
mirror would refuse exactly the requests the method exists for
(edit.complete's own handler at ebp.el:1749-1750 compares the LIVE
mirror — correct there, a conformance bug if copied here). On the
Companion the frozen pair lives ONLY in the app-side
`CompletionOffer.session/.seq` (DeviceBridge.kt:101-102): the engine
tracker has no session field and its `expectedSeq` mutates per
qualifying splice, and the engine's issue-time pair dies with the
requestCompletion closure. So the engine method takes session/seq as
CALLER parameters and the bridge supplies them from the offer it is
displaying.

### Retention-cell lifetime (a ratification point)

The cell is superseded by the next edit.complete answer for its
(document, editor_id) and cleared at the four session events ebp.el
already owns — edit.open's reseed puthash, edit.close's remhash, the
edit.resync callback's replace, and forget-pairing's clrhash. It is
NOT cleared by splices (deltas advancing seq are precisely the
#171-extension window the retained comparand exists to survive) and
NOT cleared when the accept claims the completion OFFER: the applied
goldens pin this — frames.golden line 46 is the accept delta at seq
5, and lines 47-48 are a doc request at the retained seq 4 answered
with a doc. Reading of the amendment's "reclaimed by the same session
events that claim the offer": the SESSION events among the offer's
claim events (reseed, resync, close, detach-side effects), not every
claim. The stale comparand makes a leftover cell unanswerable after
any session change regardless — clearing is the #151 memory bound,
not a correctness need.

### Emacs side

- **The seam:** a new defvar in ebp.el, `ebp-edit-complete-doc-provider`
  (nil default). `ebp-client--handle-edit-complete` let-binds it nil
  around the completion-fn funcall; a completion source MAY setq it
  during its run to a closure `(lambda (index) DOC-STRING-or-nil)`.
  After the funcall the handler snapshots it into the retention cell.
  This keeps the (doc eid text cursor) fn contract intact (the picker
  override and every test fixture keep working), keeps ebp.el ignorant
  of capf, and gives any future completion source the same hook.
- **The cell:** new ebp-client struct hash `candidate-replies`, keyed
  (document . editor-id), value `(:session S :seq Q :count N
  :provider FN-or-nil)` — minted on EVERY edit.complete answer
  including the no-fn empty arm (count 0, provider nil). Cleared at
  the four ebp.el session-event sites named above. **Retention is
  gated on the answer still being current** (review F9): a nested
  edit.complete dispatched under a blocking live harvest answers
  FIRST, so the outer (older) answer would otherwise overwrite the
  newer cell and leave the Companion's displayed offer pointing at a
  reply Emacs no longer retains — every doc request then 1201s in
  exactly the slow-LSP-plus-typing window R5 exists for. Mint only
  when the live mirror's session/seq still equal the request's; the
  reply still goes out either way, only retention is skipped.
- **The handler:** `ebp-client--handle-candidate-doc`, registered in
  `ebp-client-create` beside edit.complete (registration also exempts
  the method from the unknown-method sentinel). **Type-check the whole
  envelope up front** — stringp document/editor_id/session, integral
  seq, integral index — into ONE `-32602` arm, the event.action
  precedent at ebp.el:1550-1560 (review F5: mirroring
  handle-edit-complete's bare `=` on seq lets a string seq signal
  `wrong-type-argument`, which jsonrpc converts to -32603, breaking
  both SPEC.md:693's structural-params MUST and this plan's own
  never--32603 invariant; compare with `equal`/`eql` afterwards so no
  comparison can signal). "Integral" is the `integralLongOrNull` twin
  — an integer OR an integral float, `5.0` accepted and `5.5` refused
  — because the Kotlin side deliberately reads numbers by VALUE
  (JsonAccess.kt:83-90) and a plain `integerp` would be precisely the
  cross-implementation divergence genre the R4 review already caught
  once (review F19). Then: cell present + session/seq equal → else
  `(ebp-client--error client 1201 "Editor stale" "content-invalid"
  :reason "editor-stale")` (signals; non-local exit); index outside
  [0, count) → bare `1201 content-invalid` with NO data.reason —
  exactly what the ratified text specifies (reason is named only for
  the stale arm; no reason registry exists anywhere to extend).
  Result: `(:doc STRING)` — provider nil, index unanswerable, or any
  provider failure all degrade to `""` (the MAY-be-empty arm). The
  handler owns the SHOULD-cap: a binary-search scalar-boundary
  truncation helper to ≤ 16384 UTF-8 octets. **Emacs chars are not
  all scalars** (review F4): raw bytes live at #x3FFF80-#x3FFFFF and
  json.c refuses them (plus lone surrogates) at serialize time — i.e.
  AFTER the handler returns, inside `ebp-client--serializable`, which
  answers -32603. So the last link in the degradation chain is a
  pre-flight `(ebp--json-serialize doc)` under condition-case; a
  string json.c will not take answers `""` like every other failure.
  Pre-flight rather than a hand-rolled predicate: json.c's refusal set
  is wider than `ebp-sync--scalar-clean-p`'s arithmetic, and ebp.el
  cannot require ebp-sync anyway.
- **The provider (ebp-complete) — THREE ingredients, not two.** The
  P1 the review caught: **the closure must capture the HARVEST BUFFER
  and funcall doc-fn inside it.** jsonrpc.el dispatches every inbound
  message inside `(with-temp-buffer (jsonrpc-connection-receive ...))`
  (emacs-30.1 jsonrpc.el:807-809), so the handler runs in a
  fundamental-mode temp buffer; `eglot-current-server` resolves from
  buffer-local state behind an explicit `(not (eq major-mode
  'fundamental-mode))` guard (eglot.el:2108-2120, gh#1330), returns
  nil there, and `eglot--current-server-or-lose` SIGNALS — which this
  plan's condition-case would have degraded to `""` on every single
  eglot fetch, leaving R5's headline deliverable silently dead and
  every listed test green (a fixture doc-fn is buffer-agnostic). So:
  capture `(current-buffer)` at `--collect` time (the attached buffer
  on the live arm, the shadow buffer otherwise) and run under
  `(when (buffer-live-p buf) (with-current-buffer buf ...))`, dead
  buffer → `""`. This is R2's `ebp-sync--run-exit-fn` discipline
  (ebp-sync.el:474) applied to the doc path.
  The other two ingredients: the capf props' `:company-doc-buffer`
  function (read at the props extraction — it is read NOWHERE today)
  and an index-aligned originals vector. **Build the pairing in the
  strip pass the collect already pays** (review F2), not with a
  `cl-find-if` per wire candidate: the existing `mapcar
  #'substring-no-properties` at ebp-complete.el:300 already computes
  every stripped twin, so one O(n) stripped→first-raw map there costs
  nothing, where per-candidate probing costs 30 × |raw| compares with
  a fresh allocation each — and |raw| is obarray-scale for elisp,
  whose capfs ALL carry `:company-doc-buffer` (elisp-mode.el:727,
  744, 760, 811, 818), on the per-keystroke path whose latency is
  R4's whole point. Retaining only the ≤30 matched originals also
  keeps #172's ratified #151 bound ("bounded by the candidate cap").
  The closure funcalls doc-fn on the PROPERTIZED original — eglot's
  doc-buffer reads the `eglot--lsp-item` text property and is useless
  on stripped text — accepts the convention's BUFFER or
  (BUFFER . POINT) return, extracts `buffer-string`, strips properties
  (eglot's markup render returns fontified text).
- **Arming discipline — ONE program point** (review F3/F13). The
  provider var is SET at the finalization of the run whose list
  actually ships (inside the `when cands` block, after `seq-take`),
  and set UNCONDITIONALLY there — nil unless this run minted a vector
  — mirroring the extras snapshot's `(and cands ...)` shape at
  ebp-complete.el:289-292. "Word-fallback and no-capf arms set no
  provider" must NOT be read as "leave the var alone": the live arm
  can arm and then return nil (the sole-candidate delete at
  ebp-complete.el:305 empties the list), fall through to the shadow
  (ebp-complete.el:494), and have the word fallback answer — a
  don't-touch reading then serves the LIVE arm's docs against the
  SHADOW's candidate list, i.e. wrong docs for a fully valid
  (session, seq, index), with no exotic timing at all.
- **Blocking discipline (the R0/R2 lessons verbatim):** the answer is
  computed inside the jsonrpc dispatch extent (no deferred serving
  exists). eglot's doc-buffer performs a SYNCHRONOUS
  completionItem/resolve — 10s default jsonrpc timeout, waiting in
  sit-for, during which the ebp filter dispatches nested frames; with
  `:cancel-on-input t` any user input aborts it to nil. The provider
  therefore: answers nil immediately when
  `ebp-complete--live-harvest-active` is already up (no stacked
  bounded waits — the with-timeout shared-tag trap), else binds the
  latch (routing any nested edit.complete to the shadow arm and
  keeping flow continuations off the unwind path, the run-exit-fn
  precedent) and runs doc-fn under
  `(with-timeout (ebp-complete-doc-timeout) nil)` — new defcustom,
  default 1.0 — inside condition-case. Every failure mode is `""` on
  the wire, never -32603 — an invariant that holds BECAUSE of the
  handler's pre-flight serialize gate above, not despite it.

### Companion side

- **Engine:** `requestCandidateDoc(document, editorId, session, seq,
  index, callback): Boolean` — @Synchronized, OPEN+READY gate, sends
  the five params verbatim (session/seq are the caller's retained
  pair). Reply validation mirrors requestCompletion's discard-whole
  style — `stringOrNull("doc")` non-null (explicit `""` is a valid
  empty doc), closed-key loop `{doc}` — but **conclusion is split
  from publication** (review F8/F12): the callback fires on EVERY
  reply conclusion with a nullable doc (null = error, malformed, or
  discarded), and the Boolean return says whether anything was sent
  at all, because requestCompletion's precedent refuses with a bare
  `return` and no callback (CompanionEngine.kt:1892). Without both,
  a single 1201 / -32601 / gate refusal leaves the bridge's slot
  marked in-flight forever and docs die for that editor for the
  process's life. A 1201 (editor-stale or out-of-range) or -32601
  (pre-R5 Emacs) is a silent no-op for the DISPLAY; the request still
  concludes, so §22.2's transmitted-request duty is met without ever
  emitting rpc.cancel.
- **Bridge:** `editorCandidateDoc(document, editorId, index, epoch)` —
  **the epoch of the offer the row was composed from is a PARAMETER**
  (review F11): offer publication happens on the reader thread under
  the engine monitor, so between the long-press and the executor read
  a fresh reply can land, and the bridge would then pair the NEW
  offer's session/seq with the OLD index — every staleness gate on
  both endpoints passes and the panel documents a candidate the user
  never highlighted. The executor task drops the request when the
  published offer's epoch no longer matches. The frozen pair itself
  comes from that offer's `.session`/`.seq` (DeviceBridge.kt:101-102),
  never from live engine state.
  One-outstanding SHOULD via a latest-wins slot: at most one in flight
  per editor; a new highlight while one is outstanding overwrites the
  desired (epoch, index); on conclusion the slot publishes into a new
  `_candidateDocs` StateFlow<Map<(doc,eid), CandidateDoc(index, text,
  epoch)>> — **re-checking offer aliveness at publish time, not just
  slot identity** — else issues the desired request. **The slot is
  extracted as a pure class with its own unit tests** (review F18):
  DeviceBridge is constructor-coupled to android.content.Context and
  has no test today, so every slot-state mutant (stale publish,
  reissue dropped, slot never freed) would otherwise be unkillable.
  Docs AND the slot retire wherever the offer dies: publishOfferView's
  dead branch, clearCompletions, forgetEditor, a fresh offer's
  publish, and serve()'s transport-loss finally — **which today fails
  to clear _completionOffers/_offerViews at all (a stale-dropdown
  display ghost); R5 sweeps all three into that finally as a named
  pre-existing-gap fix.**
- **Renderer:** the narrowing pipeline moves to
  `offer.candidates.withIndex()` so a row that survives filter +
  take(12) keeps its ORIGINAL wire index (list position == wire
  position holds because the engine discards invalid replies whole —
  pinned with a comment). Rows become combinedClickable: tap accepts
  as today; LONG-PRESS (haptic, the EditorToolbar/LayoutNodes
  precedent) requests documentation for that row — with
  `onLongClickLabel` set and the function-level
  `@OptIn(ExperimentalFoundationApi::class)` Renderer.kt does not
  carry yet (review F15: a long-press-ONLY affordance with no visual
  cue makes that label its entire TalkBack surface; scroll and
  long-press coexist because a drag cancels the press). The panel is
  local chrome in the eldoc-row idiom (never a floating popup — the
  dropdown's own dialog-host rationale): a bounded plain-text block
  under the candidate rows (bodySmall, ~8-line max height, vertical
  scroll within), rendered verbatim per §16.4 — raw markdown
  punctuation from a markdown-mode-less device Emacs displays as
  typed, never interpreted. **THREE show conditions**, all required:
  the published doc's (epoch, index) matches; the offer is alive; and
  the documented row is still IN the narrowed set (review F14 — an
  offer survives a qualifying extension without bumping its epoch, so
  without this the panel documents a row the narrowing just filtered
  off screen, the same "lie of presentation" R4's narrowing rationale
  forbids; the index-preserving helper already computes the set).
  Whether an EMPTY doc shows anything is decision point 6 below.
  No new §22.4 feature — the method rides editor.sync.

### Tests + mutants (the gate)

**Elisp.** Cell minted on all three arms. THE comparand pin, BOTH
halves: (a) a qualifying delta advances the mirror — a request at the
RETAINED seq answers, one at the LIVE seq is 1201 editor-stale; (b) a
LIVE cell presented with a request whose SESSION differs while seq
matches is 1201 (review F16 — every other session test asserts through
a CLEARED cell, a state a seq-only comparand also produces, and after
a resync seq restarts at 0 and can re-reach the retained value, so the
session half is genuinely reachable and otherwise unpinned).
Supersession; **out-of-order supersession** (nested shadow answer at
seq N+1 then the outer live answer at seq N leaves the cell at N+1).
Index arms: -1, count, fractional 5.5 → 1201 / 1201 / -32602, plus
5.0 ANSWERS (the integral-float twin). Post-accept answer (the
goldens' lifetime pin); session-event clears (close, reseed, resync).
Doc-fn context: a fixture whose doc-fn asserts `(current-buffer)` is
the harvest buffer — **and returns a value DERIVED from the candidate's
text property as the doc, with the test asserting that exact content**
(review F22: `ert-test-failed` derives from `error`, so a bare `should`
inside the closure is swallowed by the provider's own condition-case
and surfaces only as `""`; the assertion has to ride the wire result).
Cross-arm leak: live capf answering only the typed token + shadow
word-fallback answer → provider nil. Degrades: provider absent, doc-fn
error, doc-fn slower than `ebp-complete-doc-timeout`, nested request
while the latch is up, raw-byte/lone-surrogate doc → all `""`. Cap
boundaries: a doc of exactly 16384 octets comes back UNTRUNCATED, and
a multibyte doc truncates to exactly 16384 at a scalar boundary
(review F20 — the single "≤ 16384" assertion cannot catch a
converge-one-short binary search). **One real-connection round trip**
through the wire-test server harness asserting the stale reply carries
`data.reason "editor-stale"` and the range reply carries `data.kind`
with NO reason (review F17: `ebp-client--error` stashes extras on the
CONNECTION, so the connectionless fixture idiom every listed test uses
drops them and both arms look like bare 1201s — decision point 2 is
otherwise unpinnable).

**Kotlin wire.** Request carries the caller's frozen session/seq
mid-extension; explicit-empty doc accepted; unknown result member /
wrong-typed doc discarded; error reply publishes nothing but DOES
conclude (a later highlight still issues — the wedge test); the
OPEN+READY gate: SYNCING and CLOSED-editor cases emit no frame
(review F21 — contract states are ["READY"] and no existing wire test
covers requestCompletion's identical gate either).

**App.** Two pure extractions with unit tests: the index-preserving
narrowing helper (wire indices survive filter+take) and the
one-outstanding slot class (desired/outstanding/published transitions
keyed by epoch+index).

**Mutants, each killed by a named test:** live-mirror comparand swap;
session comparand dropped; off-by-one index bound; cap boundary
off-by-one; serialize gate dropped; stripped-original passed to
doc-fn; `with-current-buffer` dropped from the provider; provider
armed at the extras snapshot instead of finalization; withIndex
dropped for filtered position; closed-key check dropped; engine gate
dropped; callback-on-error dropped (wedged slot); epoch parameter
dropped; empty-doc panel guard dropped; narrowed-set show condition
dropped.

### Decision points for ratification (ALL RESOLVED on the recommended arms, 2026-08-13)

1. **Highlight gesture = long-press** (recommended: zero new chrome,
   existing haptic precedent, tap-to-accept untouched) vs an info
   icon per row (discoverable but permanent clutter at 12 rows).
2. **Index-out-of-range 1201 carries NO data.reason** (the ratified
   text's literal shape; recommended) vs minting an advisory reason
   string (legal under SPEC 8 extras, normative home nowhere).
3. **Cell outlives the offer claim** (goldens-backed reading above;
   recommended) vs claim-with-offer (would need ebp.el↔ebp-sync
   coupling AND contradicts the applied goldens).
4. **The dynamic-var provider seam** (recommended: fn contract
   untouched, ebp.el stays capf-ignorant) vs widening the completion
   fn's return contract (every fixture and the picker override churn).
5. Scope rider: the serve()-finally display-ghost fix rides R5
   (recommended) vs a separate commit.
6. **An empty doc shows NO panel** (recommended: the eldoc row this
   idiom comes from already guards with `takeIf { it.isNotEmpty() }`,
   Renderer.kt:910) vs a muted "No documentation" line. This matters
   more than it looks (review F6): `""` is not the rare case but the
   universal degradation arm — every picker candidate, every
   word-fallback candidate, every timeout, every latch collision, and
   every failure answers `""`, so under the "show nothing" choice a
   real regression is indistinguishable from "no docs here" at every
   layer including device smoke. The muted line makes long-press
   feedback unambiguous at the cost of one string and a permanent
   affordance ambiguity.

### Review provenance

Drafted, then reviewed by a 4-lens adversarial pass (SPEC conformance,
Emacs runtime, Kotlin threading/display, test completeness): 22
findings, 4 verified before the pass exhausted its budget, the other
18 hand-verified against the sources. Everything above is folded in.
The P1 was found independently by three of the four lenses: the
provider had no buffer context, which would have made every eglot doc
fetch answer `""` forever while the whole planned test list stayed
green. No finding was refuted.

## R6 — edit.command revival (LANDED)

The reverse direction of the delta stream, ported from POC 1
(jetpacs-sync.el:717-920). A toolbar `command` op (SPEC 17.7) arrives
as the `edit.command` event.action carrying the device's exact point
and selection; the command runs in the ATTACHED buffer with real
point/mark, and its result rides the ordinary sync loop back — this is
also the carrier for LSP code actions, rename, and formatting (Emacs
computes, eglot executes, the loop ships), with zero wire additions.

- `edit.command` handler in jetpacs-emacs-ui.el (a GLOBAL VERB — the
  op rides whatever surface hosts the editor): the dispatch validates
  shape + mirror freshness only (D2), the command runs from the flow
  continuation. The registration IS SPEC 17.7's required outer
  allowlist; `jetpacs-emacs-ui-command-predicate` (default `commandp`)
  is the nested one for the command name — interned softly, gated,
  never handed to an evaluator.
- The command runs WIDENED (device coordinates are document offsets)
  with the desktop restriction restored after; region placed from the
  device's selection under a let-bound `transient-mark-mode`. A text
  change flushes eagerly (`ebp-sync-flush`) so it contends for seq+1
  ahead of the next keystroke; a move-only result reports the new
  `ebp-client-edit-move` (SPEC 19.4 move-only form: no
  start/del/text/len, unchanged seq — stale simply loses the move).
- The flow re-gates on the mirror at fire time: a seq that moved
  between dispatch and continuation drops the run quietly (the raced
  caret's rule). Only the M-x arm (empty command) gates on the dialog
  bridge — an explicit command asks nothing and runs on a grant-less
  session.
- `jetpacs-files.el`'s toolbar `:command` dead-letter ban is lifted.

Equivalent-mutant deletion: POC 1's explicit `activate-mark` after
`set-mark` was dead code (`set-mark` activates the mark itself at
emacs-30.1 simple.el) — caught by a surviving mutant and removed, the
JA-6 F4 precedent.

Adversarial review (3 raw, 1 confirmed P3, 2 refuted): the default
predicate was bare `commandp` while the docstring claimed "same
posture as the M-x surface" — but the M-x button filters
`jetpacs-command-visible-p` (drops `jetpacs-suppressed-commands` like
`suspend-frame`, and `jetpacs-unsupported` commands). Fixed by making
the default actually `jetpacs-command-visible-p`, so the code matches
the claim and `edit.command` is no wider than the palette.

## R7 — deferred

Snippet tabstops (candidate flag reusing §17.7's finite placeholder
grammar), inlay hints (a fourth §19.5 sibling), eldoc active-parameter
runs. All §25 class-2/3 additive with precedent; none blocks the eglot
goal. Take only when a concrete Glasspane workflow demands them.
