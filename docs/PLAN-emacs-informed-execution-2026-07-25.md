# PLAN — Emacs-informed execution (2026-07-25)

**Purpose.** Execution plan from two source-grounded reviews run 2026-07-25. A fresh session should
read §0, then start at §4.

**Provenance:**

| Doc | What it holds |
|---|---|
| `docs/REVIEW-emacs-30.1-vs-spec-2026-07-25.md` | Review 1: EBP SPEC vs Emacs 30.1 source. 21 amendment entries, 5 P1. Full amendment text lives there. |
| This doc, Track B | Review 2: companion Kotlin core vs Emacs C core. 10 pairings, 30 recommendations survived an anti-cargo-cult filter, 2 rejected outright, plus 4 gaps from a completeness critic. |

**Method note.** Every Emacs citation was read at the **`emacs-30.1` tag**, never the master working
tree:

```bash
git -C ~/pkb/resources/emacs/emacs show emacs-30.1:src/insdel.c
```

The checkout sits on master. A master-only line quoted as 30.1 invalidates a finding — this trap was
hit and corrected during review. Behavioral claims were reproduced on live GNU Emacs 30.1; Kotlin
claims were probed against the pinned `org.json:json:20240303` jar.

---

## §0 STATE

**Version floor:** EBP targets **Emacs 30.1+**, because the primary use case is Android-native
companion apps and Android-native Emacs arrived in Emacs 30. Judge everything against *Emacs 30.1
built for and running on Android*, dialing loopback TCP to the companion on the same device.

**Two tracks, independent, parallelizable across people.**

**Decisions taken (Caleb, 2026-07-25):** the constants in §5.1 and the `SurfaceStore` durability
posture in §5.2 may be relaxed/adopted where the analysis shows they improve the implementation. Both
are now recorded as **decided** with the supporting determination stated. §5.3 remains open.

### Execution ledger (2026-07-25, session 2 — build-order steps 1–3 + 5 DONE)

Landed on `llm-poc-2 slop-fork/main` (submodule `ebp` at `3c73d75`, amendments through **#105**):

| Step | What | Commits |
|---|---|---|
| §4-1 | **A0** — §6.2 delegation clause bounded (amendment #91) | ebp `6efbbc9` |
| §4-2 | **LD-15 + LD-7 + LD-22** — `max_editor_bytes` at the 65536 floor advertised + enforced (JCS sizing matches ebp.el/`json_out_string` exactly); 20k highlight cap deleted; `max_rich_spans`/`max_table_cells` aggregate enforcement (cell spans spend the rich-span allowance); conditional limits required in `checkLimits` | `3c16fbb` |
| slip-ins | **LD-1** (dialog hang; T3c override chain in `RenderCtx.action`), **LD-12** crash-closers (Semaphore(3) + `Throwable`), **LD-13 half** (close() drains `pending`), **LD-16**, **LD-18**, **LD-19** (+ IconMap caches only resolved vectors), **LD-21** (O(n²) decoder → stateful incremental) | `967ab1e` |
| §4-3 | **T1** — `EbpJson`/`EbpValue` strict one-pass parser replaces org.json at the boundary; both compensating scans deleted; **LD-8, LD-9** closed; **LD-20** `JsonEquality` type-tag gate, no `else` | `dceb22a` |
| §4-5 | **A1–A5** = amendments **#92–96** (+ astral `edit.delta` golden row 36, contract `max_method_bytes: 128`); **A7** = **#97** (§24.2 floor). Companion #93 conformance: method-name gate before registry | ebp `30857a5`, `74a09d8` |
| §4-4a | **T2** — ScalarPos/Utf16Pos through EditorSession + the four engine entry points, ONE surrogate-safe conversion pair; editorCommand/localEditorCaret convert+order (LD-4); `editorListener` wired → EditorMirror StateFlow → RenderEditor adopts on epoch + refused-edit snap-back (LD-5); edit.apply atomic + form-strict, cursor REQUIRED, peer caret validated pre-splice. Note: insdel's three-case adjust has no live slot (peer-dictated cursor, B2); the sender-side cursor choice is an **ebp.el follow-up** | `271c3df` |
| audit | **T1/T2 audited against §4/§6/§19** — 9 defects fixed (Unicode-lax hex escapes, move-only `seq` unchecked, local edit from a superseded base, `toInt()` position truncation, `start+del` overflow closing the transport, frames stranded behind a fault, unvalidated `edit.complete` results, `ebp.el`'s line-anchored `Content-Length`, `validate.py`'s lone surrogates + missing unterminated-header cap); amendments **#98–#103**; 11 pre-existing defects confirmed + scheduled. Report: `docs/AUDIT-T1-T2-2026-07-25.md` | `7ed0f82`, `26b635f` |

Baselines: **293 wire / 24 app Kotlin; 203 elisp across 8 suites; validate.py green (37 frames,
17 wire fixtures)**. Spec through **amendment #105**.

**Audit backlog CLEARED** (`691b052`, spec `3c73d75`, amendments **#104-#105**): all 11 §3
items resolved except the one P3 ordering nit (§3.10), each with a regression test. The editor
lifecycle is now: node-position-only collection gated on the target profile, sessions keyed by
§16.1 presentation identity, a READY sweep over the SurfaceStore that fixes reconnect and
SYNCING-removal together, `(document, identity)` exclusivity, no drafts for synchronized editors,
dialog editors counted/opened/closed, and validated annotation batches.

**T3 DONE** (`d95e402`) — (a) the epoch: SurfaceStore stamps a per-`(surface, id)` generation in
ONE place inside `update()`, by comparing what the display shows before and after the snapshot, so
an erased draft or a moved authored value reseeds the widget while an in-progress edit (and an
acknowledged draft) does not; published on the bridge, collected at the render root, folded into
every stateful widget's remember key (LD-2). (b) the defaults layer: the engine keeps the dialog
statefuls it validated and `DialogContext` resolves user-then-authored through a **containment
test**, so a deliberately-cleared field is not restored and an untouched `checkbox` ships boolean
`true` rather than the string `""` (LD-3); extracted as pure `captureValue()`, with
`authoredValueOf` now the single definition shared by both layers. The override chain (c) landed
in `967ab1e`. **All three Tier-1 architectural items (T1, T2, T3) are complete.**

**Tier 2 DONE** (`029f990`, `a06d77c`, `0a63fe6`, `f3314df`): LD-13 bound half (kbd_buffer
hysteresis: hold at 512 outstanding, resume below 128, refusals fail locally with 1401); the two
serialize-to-compare fixes + the MainActivity recompose-scope split (SurfaceHost/PieMenuHost/
DialogHost); LD-14 records/drafts file split (a keystroke re-serializes no spec or tombstone —
the load-bearing §5.2 half; the idle-timer amortization is deferred, see below); LD-11 image cache
(LRU byte budget from memoryClass + in-flight coalescing + clear() revocation seam, completing
LD-12's retained-bytes bound); LD-10 contract-driven scalar type checks (FIELD_TYPES projected from
contract.json, boolean/string/identifier/dp coercion closed) + LD-17 builtin-context gate
(builtinsFromProfiles). Baselines **298 wire / 24 app / 203 elisp**.

**Deferred, small, noted:** (a) LD-14's idle-timer draft amortization — needs a scheduler seam in
the pure wire library and §15.1-barrier integration, and per the review buys nothing for an
on_change field; the tombstone-re-serialization cost (the dominant one) is already gone. (b) The
image-cache `clear()` awaits an app-side forget-pairing path, which is not wired yet.

**NEXT:** **A6** — the P2/P3 amendment batch (incl. §5.1's `max_node_depth`/`max_send_header_bytes`
constants, both §25 restricting rows), then **A8**'s research items.

**Deferred to device time:** LD-4's astral on-device check (unit-covered in `271c3df`; the
checklist wants it on hardware too), an inbound-`edit.apply`-while-the-editor-is-shown smoke (the
new mirror adoption + snap-back), a dialog-`text_input` Done-key smoke (LD-1), and the standing
outward handoff — Caleb pushes the CONTRACT repo history (now `30857a5`, still local to the
submodule clone) to GitHub before llm-poc-2, or the recorded pin won't resolve from a fresh clone.
The `ebp/llm-poc` worktree is a stale sibling at `4f6f82b` (#62); the submodule checkout is the
live spec authority.

**ebp.el follow-ups queued by T2 (elisp track):** (1) the sender-side caret choice on
`edit.apply` — ebp.el dictates `(+ start (length text))` (end of its own splice), which yanks the
device caret on every remote apply; the three-case marker arithmetic belongs THERE, adjusting the
device's last-known caret instead; (2) `ebp-client-edit-apply` never sends `sel_start`/`sel_end` —
fine (paired-or-omitted), recorded for when selection-carrying applies matter.

---

## §1 TRACK A — SPEC amendments

### A0. The keystone — first, alone

**Bound §6.2's delegation clause (SPEC.md:462–470).** Root cause of **13 of 31** Review-1 findings.
It relaxes receiver obligations for Emacs on the grounds it "MAY delegate framing and message
decoding to a host-platform JSON-RPC library … accepting that library's tolerances," disclaiming
relaxation only for "Section 6.1." Three axes left open:

1. Silent on the delegate's **diagnostics** → P1-1 (secrets logged).
2. Silent on **resources committed before validation** → P1-2 (interning).
3. **"Tolerances" cannot cover non-termination** → P2-1 (permanent header stall). A tolerance is "I
   accepted what I could have rejected." A silent infinite wedge is not that.

Three sentences, no `contract.json` change, no golden change:

> No sender obligation **in this document** is relaxed by this paragraph. A role excused by this
> paragraph from a strictness obligation still owes a bounded terminal reaction: it MUST NOT accept
> the message as valid, and it MUST reach close, discard, or a documented tolerance within Section
> 22.3's bounds; an unbounded stall is not a conforming alternative. This paragraph does not relax
> any obligation of Section 23, and in particular does not extend to a host library's diagnostics or
> to resources it allocates before validation.

**Why first:** every P1 and most P2 amendments become local elaborations of a coherent rule.

### A1–A5. The P1s

Full text in the Review 1 doc.

| ID | Change | Sections | Artifacts |
|---|---|---|---|
| A1 | Delegation does not extend to a host library's diagnostics — disable/redact raw-frame logging before the first frame | §23.3, xref §8 | §24.6 item 12 widened to auth proofs |
| A2 | Decoding MUST NOT grow an unbounded process-lifetime table from peer names; + method-name grammar and 128-octet bound | §23.5, §4.5, §11, §7.3 | `contract.json`: `limits.fixed.max_method_bytes: 128`; §24.6 item 4 |
| A3 | The wake signal MUST be inert — no startup args, command line, or code/file to load | §5.3, xref §21.1 | none (prose) |
| A4 | Rewrite §9.1's keystore rule to give the Emacs endpoint a defined storage floor | §9.1 | revises amendment #78 |
| A5 | Emacs MUST NOT present a synchronized editor whose text is not Unicode scalar values; no lossy substitution | §19 preamble | `frames.golden`: astral `edit.delta` row |

**A3 caveat — state this accurately.** The argv exposure is a **pre-existing property of Emacs on
Android**: any app can already start the exported `EmacsActivity` with startup arguments
(`java/AndroidManifest.xml.in:226` `android:exported="true"`; `EmacsActivity.java:269`
`getStringArrayExtra`, no caller check; `EmacsThread.java:58-68` spliced into `initEmacs`). The
amendment does not fix Emacs. It stops a *conforming Companion* being the vehicle.

**A5 is the easiest to get subtly wrong.** The failure is not "Emacs sends bad bytes" — §4.1 bars
that. It is that the natural defensive fix (U+FFFD substitution, 1 char → 1 char) **preserves scalar
length**, so every §19.3 length gate keeps passing while the documents silently differ.

### A6. The P2/P3 batch

Eleven P2 and five P3, itemized in the review doc. Largely independent; land after A0. Constants are
now decided — see §5.1.

### A7. Version floor statement → **§24.2**, not §1, not §4

§24.2 is already the Emacs-specific conformance section, so a floor there does not breach the
implementation-agnostic rule. The clause needing it is §4.5's amendment-#35 carve-out, which assumes
"a host JSON-RPC library that bounds recursion by its own means" — true only from Emacs 30 on:
`json.o` is unconditional in 30.1's `src/Makefile.in` but gated behind `JSON_OBJ = @JSON_OBJ@` in
29.1's, and without it `jsonrpc.el` degrades to `json.el`'s **recursive** `json-read`.

**Do not add floor language to §9.** `gnutls-hash-mac` is `#ifdef HAVE_GNUTLS3` and GnuTLS is an
Android packager add-on, but `secure-hash` is unconditional core and returns 32 raw octets under
BINARY (`src/fns.c:6395`, `:6411-6413`), so RFC 2104 HMAC-SHA-256 is constructible in pure Lisp on
every 30.1 build.

### A8. Next-round candidates — research, not drafting

1. **`src/process.c:6820-6851`** — `send_process` blocks in a spin that runs timers, so inbound
   frames dispatch *re-entrantly inside an outbound send*. Bears on §22.3 backpressure and §7.4
   ordering. `jsonrpc.el:786-788` already flags it, citing bug#60088.
2. **Unbounded number literal → quadratic mini-gmp.** `json.c:1310-1325` caps no digit count; the
   default Android build has no libgmp, so `lib/mini-gmp.c:1390-1402` is quadratic with no
   `maybe_quit`. A 4-million-digit integer is inside every §4.5 limit. A2's text does not cover it.
3. **Transport coding system unpinned and locale-dependent.** `jsonrpc.el` never calls
   `set-process-coding-system`; default resolves to `undecided-unix` under `LANG=C`. The in-tree
   consumer that gets it right is `eglot.el:1590` (`:coding 'utf-8-emacs-unix`).

---

## §2 TRACK B — companion Kotlin core

### B-lesson. The deepest lesson (read this before touching anything)

**Every P1 defect in this review is the same defect: two authorities for one fact, and no structure
that makes one of them wrong.**

`org.json`'s value model vs SPEC §4.1's. Compose's `TextFieldValue` vs `EditorSession.shadow`.
Compose `remember` vs `SurfaceStore.drafts`. `DialogContext.fields` vs the authored defaults the
engine computed and discarded. A UTF-16 `Int` vs a scalar `Int`. The advertised builtin profile vs
three hand-written `when`s. `pendingEditors` vs `editors`. In not one case did anyone write the wrong
logic — in every case someone wrote *correct* logic against a copy that a second, equally correct
piece of logic had already moved past.

The naive response is discipline: audit the call sites, add the missing subscription. The companion
is already doing this — `LaunchedEffect(optSig)` with the comment "audit I7", `hasDuplicateMembers`
bolted onto a parser that will not enforce the rule, `NodeSupportPinTest`'s source scan. All correct,
all cheap, all *per-instance*. They fix the case that was found and do nothing about the case that
was not.

Emacs's C core is organized around the opposite response, and it is **not** "one global source of
truth" — Emacs is full of derived copies. It is: *every derived copy carries, in its own structure,
the identity of what it was derived from, and the deriving code is the only code that can write it.*
`blv->where` records which buffer a binding came from and every read checks it. `store_in_keymap`
flushes `where_is_cache` as its first statement. `filter_image_spec` records what a decode was keyed
on. `CHECK_STRING` at the DEFUN boundary vs `XSTRING`'s bare `eassert` inside records *where* the
type was established, making "already validated" a greppable global property. And where Emacs cannot
make a derived copy safe it deletes the second authority: text lives in one buffer, and everything
pointing into it is registered with that buffer.

**The actionable instruction: when you find a second copy of a fact, do not add a synchronization
step — add a stamp and a chokepoint.** A stamp is T3's epoch, `blv->where`, the seq already on §19.5
annotations (which the companion gets *right*, and which is why marker machinery is unnecessary
there). A chokepoint is `EbpJson.parse`, `RenderCtx.action`, `EditorSession.splice`, `SpecValidator`.
The three Tier-1 items are each one stamp and one chokepoint.

**Review rule for new code here:** *whenever a value is read in two places, ask which one the wire
sees. If the answer is "the other one," that is a defect, whether or not anyone has hit it yet.*

### B0. Live defects

#### P1 — silent wrong data or a user-visible break

- **LD-1. A dialog `text_input` submitting via `dialog.submit` hangs Emacs forever.** The dialog
  rebinding lives only in `Renderer.kt:525-548 onButton`, reached from 5 button-shaped sites.
  `text_input`'s Done key goes to `ctx.action(onSubmit, v)` (`Renderer.kt:257`) →
  `dispatchAction` → `:255 if (descriptor.has("builtin")) return executeBuiltin(...)` → the `when`
  at `:208` has no `dialog.submit` arm and falls off the end (comment at `:237-239` admits it). The
  outstanding `dialog.show` is never answered. Wider than `on_submit`: `on_tap` inside a dialog
  (`LayoutNodes.kt:197`), `empty_state` (`ContentNodes.kt:319`), `section_header` trailing
  (`LayoutNodes.kt:589-594`) are all conformant and equally dead. *Fixed free by T3.*
- **LD-2. The value on screen and the value sent to Emacs are different values.** *(converged: two
  pairings independently)* `SurfaceStore.drafts` is authoritative for `capture_fields`
  (`CompanionEngine.kt:277-278`) and §15.1 `input_state`; every widget keeps a private Compose copy
  keyed only on `(surface, id)` (`Renderer.kt:236-238`; `InputNodes.kt:185, 205, 251-253, 363, 379`)
  — invariant across revisions, so the seeding lambda runs once and no snapshot reseeds. Repro: rev 1
  `text_input id="title"`; user types "reject me"; Emacs pushes rev 2 with `value:"Untitled"` and
  `reset_input_ids:["title"]`; `reconcileDrafts` erases the draft per §13.6; the field still reads
  "reject me". A `capture_fields:["title"]` button submits "Untitled" while the user looks at
  "reject me". Mirror image on restart: drafts are durable, Compose state is not. `grep
  reset_input_ids` → 0 hits in `app/`.
- **LD-3. Dialog capture invents `""` — the wrong JSON *type*.** `fields.put(fieldId,
  dialog.fields[fieldId] ?: "")` (`Renderer.kt:537`, sole capture site). A `checkbox` authored
  `checked: true` and untouched ships the **string** `""` where SPEC.md:2315-2317 requires the
  logical value, i.e. boolean `true`. The defaults already exist and are discarded:
  `handleDialogShow` calls `validateSurfaceSpec(...)` as a bare statement
  (`CompanionEngine.kt:1414-1421`) and throws away the returned `statefuls`.
- **LD-4. Editor caret/selection go on the wire as UTF-16, unordered.** `Renderer.kt:363-364` passes
  Compose's `value.selection.start/.end` through two pass-throughs into
  `CompanionEngine.editorCommand:1185-1186`, serialized with no conversion, no clamp, no ordering
  check. Two MUST violations on one line: SPEC.md:2590 (convert before sending) and SPEC.md:2640
  (`sel_start <= sel_end`). Repro: ten emoji, caret at end → `cursor: 20` against a 10-scalar
  document. Backward drag → `sel_start > sel_end`. Contrast one line away: the *text* path
  (`Renderer.kt:341` → `EditorSession.diff`) is scalar-correct, and `setCaret`
  (`EditorSession.kt:72-85`) does validate ordering. `editorCommand` is the one path bypassing
  `EditorSession`.
- **LD-5. The editor shadow has no owner, so §19.4's apply gate is *uncheckable*.**
  `CompanionEngine.editorListener` (`:1106`) is declared and invoked (`:1229`, `:1248`) and
  **assigned nowhere outside `EditorTest.kt`** (`DeviceBridge.kt:254-314` subscribes eight listeners,
  not this one). After any inbound `edit.apply`, `s.shadow` moves and the on-screen text does not;
  the next keystroke diffs against a stale base. Compounding: `EditorSession.splice()` ends with three
  unconditional assignments (`EditorSession.kt:41-43`) that *overwrite* rather than adjust the caret
  and destroy any selection — correct for a local keystroke (Emacs's `SET_PT`), wrong for an inbound
  apply (`adjust_point`), same function both callers (`:1141`, `:1241`). And `handleEditApply` treats
  §19.4's **required** `cursor` as optional (`:1244-1247`), discards `setCaret`'s `false`, and
  responds `{status:"applied"}` regardless (`:1249`).
- **LD-6. Deferred editor opens are never pruned.** `pendingEditors` (`:614`) is only added to
  (`:649`), cleared wholesale (`:149`, `:434`), drained (`:433`). Both removal paths
  (`closeEditor:1195`, `closeSurfaceEditors:658`) operate on `editors`, which pending entries were
  never inserted into — silent no-ops. Repro A: rev 1 puts editor `e` on `d1`; rev 2 moves it to
  `d2`; on `session.ready` **both** open; the `d1` session is unreachable by every close path, leaks
  for the connection's life, is invisible to the `max_editor_sessions` count (`:583-590` sums
  `surfaceEditors`, not `editors.size`), and `handleEditApply` will still resolve and mutate it.
  Repro B: `surface.remove` during SYNCING → `edit.open` for a surface that no longer exists.
- **LD-7. Syntax highlighting silently stops at 20,000 characters.** `maxChars: Int = 20_000`
  (`SyntaxHighlight.kt:116`); every tokenizer does `minOf(src.length, maxChars)` (`:176`, `:294`,
  `:355`). `highlightOrg`'s own 40,000 default is dead code because `:120` forwards the outer 20,000.
  All three call sites take the default. At §4.5's 65536 floor roughly two thirds of a document
  renders unstyled, permanently, with no signal — the exact failure `jit-lock` was written to prevent
  (`lisp/jit-lock.el:190-194`). Note what Emacs did *not* do: it capped the **chunk**, never the
  document. **One-line fix**; keep the `runCatching` fallback at `:117`. Do **not** build the chunk
  cache (§B2).

#### P2 — conformance and cost

- **LD-8. Lone surrogates admitted, then silently rewritten to `?`.** `handleEditApply` takes splice
  text with a bare cast (`:1235`); `splice` concatenates it into `shadow`; `edit.resync` puts it back
  on the wire (`:1270`). Verified: `{"s":"A\ud800B"}` re-encodes to `{"s":"A?B"}`. SPEC.md:122 is an
  explicit MUST; `grep -rn surrogate` over the companion → 0 hits. Scalar counts stay aligned and
  `edit.resync` recovers, so this is silent *content* divergence, not unrecoverable desync. Fix in
  the parser (T1), not the callsite.
- **LD-9. The wire boundary accepts a superset of JSON and coerces types.** `FrameCodec.parseBody`
  hands `JSONTokener.nextValue()` straight through plus two hand-rolled full-text scans
  (`exceedsDepthLimit:162`, `hasDuplicateMembers:198`) — a valid 4 MiB body is walked three times.
  Probed on the pinned jar: `{n:1}`, `{'n':'v'}`, `[1,2,]`, `+1`, `007`, `0x10` all accepted; bare
  `NaN`/`Infinity` become the **strings** `"NaN"`/`"Infinity"`; out-of-range integers return
  `BigInteger`; neither `JSONObject` nor `JSONArray` declares `equals`/`hashCode`. The codebase
  already documents this class of divergence at `FrameCodec.kt:142-146`.
- **LD-10. Node attributes are never type-checked; accessors coerce.** The required-member loop
  (`SpecValidator.kt:403-406`) is presence-only. Probed: `{"content_padding":"5"}` → `optDouble` 5.0;
  `{"enabled":0}` → `optBoolean("enabled", true)` returns the **default** `true`, so a disabled node
  renders enabled; `{"password":"true"}` → `true`, inside the validator itself (`:416`).
  `{"t":"section_header","title":{"secret":"internal"}}` → `optString` coerces the object to its
  literal JSON text and renders it as a heading. Meanwhile `contract.json` carries 93 `field_types`
  and 19 `enums` rows that **no Kotlin reads**, while `SpecValidator.kt:32`/`:192` hand-duplicate two.
- **LD-11. There is no image cache at all.** `produceState<Bitmap?>(null, url)`
  (`ContentNodes.kt:71-73`) is the only decode entry point; leaving composition discards the bitmap
  and cancels the load. `RenderLazyColumn` disposes off-screen items (`LayoutNodes.kt:243-256`), so
  scrolling re-runs the full `loadHttps` path — fresh DNS, TLS, up to 8 MiB re-downloaded, full
  decode. Same on `view.switch`, backgrounding, and relaunch of a durably-present surface. Ten
  identical avatars are ten concurrent sockets.
- **LD-12. Aggregate decoded-image memory is unbounded, and an OOM kills the process.**
  `decodeGuarded` enforces caps *per image* (`ImageLoader.kt:236-238`); nothing bounds the sum. Eight
  maximal 4096×4096 images pass individually (`4096*4096*4 == 67_108_864` is *not* `>` the limit) and
  ask for ~512 MiB. And `ImageLoader.load`'s guard is `catch (e: Exception)` (`:46`) —
  `OutOfMemoryError` is an `Error`, so it escapes the loader, escapes the coroutine, and takes the
  process.
- **LD-13. The outstanding-request map is unbounded and never failed on close.** `private val pending
  = HashMap<Int, …>` (`:182`), written at `:189` with no cap and no deadline. `close()` (`:121-151`)
  clears queue marker, dialogs, pie menus, editors, `surfaceEditors`, `pendingEditors`, detaches
  `firing` — and never touches `pending`, so §22.3's "Outstanding requests fail locally" is unmet.
  §22.3 names outstanding-request count as a MUST-bound resource. Inbound side is fine:
  `DeviceBridge.kt:316-322` is a blocking 8 KiB read feeding `feed` synchronously, so TCP window is
  the backpressure.
- **LD-14. `persist()` writes and fsyncs all state on every keystroke.** `putDraft` calls `persist()`
  unconditionally (`:255`), rebuilding every present surface's full spec plus every tombstone (up to
  `max_surface_ids` = 4096, `:207`) plus every draft; `FileSurfaceBacking.replace` serializes,
  `fd.sync()`, renames, `force()`s the directory — **two fsyncs per typed character**.
  `SurfaceStore.kt:64-67` documents this as deliberate §15.1 conservatism, so it is a design
  question, not a bug. Runs on `ebp-dispatch`, so typing does not jank; harms are flash write
  amplification at ~10 Hz and every subsequent action queued behind it. Dominant scaling term is
  tombstone accumulation.
- **LD-15. `max_editor_bytes` is neither advertised nor enforced.** *(converged: three pairings)*
  `grep max_editor_bytes` over all Kotlin → **0 hits**. REQUIRED in the welcome whenever
  `editor.sync` is granted (SPEC.md:238), and `editor.sync` *is* advertised (`DeviceBridge.kt:64`);
  the sibling `max_field_bytes` is already pinned at the floor (`:73`). SPEC.md:2779's
  `editor-too-large` refusal is unimplemented. **Consequence: the effective editor ceiling today is
  `max_frame_bytes` = 4 MiB, which is what makes every editor performance number look bad. Declaring
  it at the 65536 floor is the single cheapest way to make six Tier-3 performance items permanently
  unnecessary.**
- **LD-16. A trigger set is committed durably, then reported as a storage failure.**
  `TriggerFiringService.replaceSet:137-143` commits and arms inside `synchronized`, *then* calls
  `onTimeScheduleChanged?.invoke()` → `TriggerAlarms.reschedule` (`TriggerAlarms.kt:32-40`). A throw
  there is caught by `handleTriggersSet`'s `-32603 "Storage failed"` (`:1044-1050`) and
  `triggerListener` is skipped, so Emacs believes the prior set is armed (SPEC.md:3043-3049) while
  the new one is live. The sibling `handleRemindersSet:901-906` gets this right. Fix hoists one line.
- **LD-17. Builtin context legality is unvalidated; per-target builtins advertised, never read back.**
  `surface_profiles.<target>.builtins` is emitted (`NodeSupport.kt:56-80`) with no
  `builtinsFromProfiles` to match `nodeTypesFromProfiles`; `validateAction`'s builtin branch checks
  only `ACTION_SCHEMA` membership (`:923-928`). SPEC.md:1361's "invalid context MUST reject the
  containing document" is unimplemented. Calibration: *advertisement* is a sender duty, so this never
  breaks a conformant Emacs — hence P2 while LD-1 is P1.
- **LD-20. `JsonEquality` is asymmetric and conflates JSON `null` with an absent member.** *(critic
  gap 1)* `JsonEquality.kt`'s last clause is `else -> a == b`, delegating the terminal case to
  org.json. Probed: `NULL.equals(null) = true`, so `jsonValueEquals(JSONObject.NULL, null)` is `true`
  while the reverse is `false` (Kotlin `==` dispatches on the left operand) — against SPEC.md:131
  verbatim ("An absent member and a member whose value is `null` are distinct"), and Kotlin `null` is
  exactly what `authoredValue` returns for an absent member (`SurfaceStore.kt:316-324`). Called at 12
  non-test sites: three are validator MUST-rejects (`SpecValidator.kt:471`, `:480`, `:489`), three
  decide whether a user's draft is silently erased (`SurfaceStore.kt:276`, `:292`, `:303`). Emacs's
  decisive line is the type-tag gate `JsonEquality` lacks — `if (XTYPE (o1) != XTYPE (o2)) return
  false;` (`fns.c:2864-2872`) — so no cross-type equality is reachable at all, and `same_float`
  (`:1880-1889`) refuses C's `==` outright. Same lesson as T1: when the language's default equality
  is not your spec's, do not layer a `when` on top — make the borrowed one unreachable. **~6 lines**
  (a total `when` over the seven EBP types with **no `else`**), and it falls out of T1's sealed
  hierarchy as a compile error. *Dependency:* the number clause `a.toDouble() == b.toDouble()` is
  conformant per SPEC.md:160 **only once T1 rejects >2^53 integers** — today org.json returns `Long`
  for `9007199254740993` and `9007199254740992` and they compare equal.
- **LD-21. `FrameDecoder.feed` is O(n²) — measured, not speculated.** *(critic gap 2)*
  `FrameCodec.kt:57-73` does `buffer += bytes` (realloc + copy all pending), then
  `indexOfTerminator(buffer)` **from index 0 every time**, and at `:69` returns without consuming the
  header — so the next read re-scans the whole accumulated buffer *and* re-runs `parseHeader`.
  `DeviceBridge.kt:317` reads 8192 bytes at a time. Simulated on the exact loop:

  | body | reads | wallclock | memcpy | scanned |
  |---:|---:|---:|---:|---:|
  | 262,144 | 33 | 1 ms | 4.6 MB | 4.6 MB |
  | 1,048,576 | 129 | 21 ms | 68.7 MB | 68.7 MB |
  | 4,194,304 | 513 | 229 ms | 1.08 GB | 1.08 GB |

  229 ms and 1.08 GB of memory traffic on a **desktop** for one spec-legal frame, before a byte is
  parsed. On a phone, seconds. Emacs's answer is two-part: in C, `read_process_output` reads into a
  **fixed** buffer sized once per read (`process.c:6183`, `read-process-output-max` default 65536)
  and carries over only the decoder's partial-multibyte remainder, never the accumulated message; in
  Lisp, `jsonrpc--process-filter` stores `expected-bytes` **on the connection** so the header regexp
  runs once (`jsonrpc.el:739-745`) and consumes with `delete-region` (`:782`). The naive version is
  exactly the companion's: re-derive parse state from the whole buffer on every chunk. **~30 lines,
  no new types:** give `FrameDecoder` a `bodyStart`/`expected: Int?` pair and a `scanned: Int`
  watermark, accumulate into a grown `ByteArray` with a read offset, resume `indexOfTerminator` at
  `scanned - 3`, parse the header once. **Threshold already crossed** — LD-15 caps *editors* at 64
  KiB but does nothing about `surface.update` snapshots, bounded only by 10,000 nodes / 4 MiB.
- **LD-22. Two more unenforced advertised limits.** *(critic gap 3)* Sweeping every row of
  SPEC.md:236-245 against non-test Kotlin: `max_rich_spans` → **0 hits**, `max_table_cells` → **0
  hits**, both triggered (`rich_text` and `table` are in `NodeSupport.kt:19`/`:34`, rendered at
  `Renderer.kt:135`/`:152`). SPEC.md:259-261 makes these **"aggregate counts across one SurfaceSpec
  or dialog document"** — precisely LD-12's shape (per-item bounded, sum unbounded), generalized by
  the spec one line away. `max_chart_points`/`max_canvas_ops` already show the correct pattern
  (advertise in `DeviceBridge`, thread through `CompanionEngine.kt:43-44`/`:1416-1417`, enforce in
  `SpecValidator`), so all three missing limits are the same ~10-line copy.

#### P3 — hygiene

- **LD-18.** `close()` (`:121-152`) is unprotected and calls host listeners at `:136`/`:142` *before*
  `firing.detach(this)` at `:151`, which removes the dead engine from a device-lifetime
  `AtomicReference`. `close()` is called bare in `DeviceBridge.serve()`'s `finally` (`:326-332`), so a
  throw there also skips `clearLiveSession` and `socket.close()` — leaked FD plus a dead engine
  parked globally. No current listener can throw, so this guards the next one. Two edits:
  `runCatching { engine.close(...) }`, and hoist `firing.detach` above the callouts.
- **LD-19.** `IconMap.cache` is an unbounded `ConcurrentHashMap` keyed on a wire string
  (`IconMap.kt:17, 89-100`), and `icon.name` has no `"icon"` case in `validateNode`. *Critic
  correction:* `MAX_IDENTIFIER_OCTETS` **is** applied — at `SpecValidator.kt:394`, to every node `id`
  — but not at `icon` (`:244`) or `input.key` (`:259`). That makes the fix a one-line copy of an
  existing check rather than new policy. LRU optional.

### B1. Architectural recommendations

#### Tier 1 — do these three

**T1. Replace org.json at the frame boundary with a strict RFC8259 parser producing a sealed
`EbpValue`.** *Closes LD-9, LD-8, LD-10's substrate, LD-20.*

Emacs is the precedent, and recently: it shipped libjansson for 27–29, concluded a general-purpose
JSON library was the wrong thing at the wire boundary, and in 30.1 replaced it with 1,866 hand-written
lines (`etc/NEWS:34` — "Native JSON support is now always available; libjansson is no longer used").
Lone surrogates die at `json.c:1160-1181`; the whole number grammar is gated by one line at `:1291`
(`if (c < '0' || c > '9') json_signal_error (...)`) which kills `+1`, `NaN`, `Infinity`, `0x10` at the
first character; out-of-range is `Qjson_number_out_of_range` (`:1267`), not a silently widened
representation. **Why Emacs needed it:** the library's laxity, number mapping, duplicate-key and
surrogate policy were not Emacs's policy, and none are correctable from the caller's side — you can
only re-scan afterward, which is exactly what `FrameCodec` does twice.

*Kotlin shape:* one file in `wire/`, ~250–350 lines. `sealed interface EbpValue` with
`EObj/EArr/EStr/ENum/EInt/EBool/ENull`, plus `object EbpJson { fun parse(text: String): EbpValue }`.
Strict grammar; enforce **in-parse, one pass**: duplicate member names, depth ≤ 64, unpaired
surrogate escapes, integers outside ±(2^53−1), non-finite literals. Deletes both compensating scans.

**T2. Editor ownership and typed positions.** *Closes LD-4, LD-5.*

Emacs never let charpos and bytepos be the same type — `buffer.h:988-995` states the discipline,
`insdel.c:93-95` machine-checks it (`eassert (charpos == BYTE_TO_CHAR (bytepos) && …)`), conversion is
always a named call. *Kotlin:* `@JvmInline value class ScalarPos(val v: Int)` / `Utf16Pos(val v: Int)`
— both erase to `Int`, zero allocation — pushed through `EditorSession` and the four `CompanionEngine`
editor entry points; everything Compose-facing takes `Utf16Pos`; exactly one conversion pair as named
methods. **Wire `editorListener` first** — it is what makes §19.4's shadow-equality gate expressible
at all; everything else in T2 is arithmetic. Take the three-case adjustment arithmetic from
`insdel.c:263-272` as a private function. **Do not build a Marker registry** (§B2).

**T3. One reconciliation point: the epoch stamp and the defaults layer.** *Closes LD-1, LD-2, LD-3.*

Emacs's `make_current` (`dispnew.c:2770-2797`) is the moment a desired row *becomes* the current one,
in exactly one function. Emacs's `swap_in_symval_forwarding` (`data.c:1546-1567`) falls back to
`blv->defcell` with `blv->found` as the explicit override bit (`lisp.h:3142-3144`), and
`Fbuffer_local_value` **signals** rather than inventing a value when neither layer has one.

*Three pieces:* (a) `SurfaceStore` gains a per-`(surface, id)` epoch bumped whenever the displayed
value was decided by a snapshot rather than the user; thread it through `surfaceListener` so every
widget's remember key becomes `(surface, id, epoch)`. (b) `DialogContext` gains the `defaults` layer
`handleDialogShow` already computes and discards — **the lookup must be a containment test, not
`?:`**, or a deliberately-cleared field (empty string, `false`, `0`) is indistinguishable from an
absent one; that is exactly LD-3. (c) Move the dialog builtin rebinding from `onButton` into
`RenderCtx.action` as an ordered override chain (~10 lines); the five button sites collapse to plain
`ctx.action(...)` and the fifteen bypassing sites become correct with no edit. Emacs's shape is
`command_remapping` (`keymap.c:1224-1250`) — an override is an ordinary binding resolved through the
ordinary chain, so precedence falls out.

#### Tier 2 — cheap, next

- **Bound `pending` and fail it on close** (LD-13). `kbd_buffer` is a fixed 4096-slot ring
  (`keyboard.h:374`) holding off its source at half full (`keyboard.c:3801-3811`) and resuming at a
  quarter (`:3989-3996`) — keep the hysteresis, a single cap thrashes. **The ten-line half — invoking
  every pending callback with a synthetic local error in `close()` — is a standalone conformance fix;
  do it first.** ~30 lines total.
- **Fix the frame decoder** (LD-21). ~30 lines. Belongs here, not Tier 3.
- **Fix `JsonEquality`** (LD-20). ~6 lines; depends on T1 for the integer rule.
- **Split the persist file, then amortize** (LD-14). Emacs auto-saves on a 300-keystroke counter
  gated by *both* the count and `!detect_input_pending_run_timers (0)` (`keyboard.c:2855-2861`), with
  `force_auto_save_soon` (`:778-782`), and an explicit scale term — `delay_level` is "4 for files
  under around 50k … 15 at 1 meg": *the bigger the write, the less often.* **Order matters:** (1)
  split the backing into `records.json` and `drafts.json` so a draft write re-serializes no spec and
  no tombstone — the load-bearing half; (2) then `markDirty()`/`flush()` with a ~500 ms reschedulable
  idle timer plus a hard dirty cap, and unconditional `flushNow()` at the §15.1 barriers. **(2) alone
  buys nothing for a field with `on_change`** — the barrier forces a flush per keystroke anyway.
- **Image cache with an aggregate byte budget** (LD-11, LD-12). `lookup_image` never re-decodes a
  seen spec (`image.c:3508-3512`), touches `img->timestamp` on every hit (`:3607`), and — the
  transferable subtlety — keys on `filter_image_spec` not the whole spec, because "Some
  animation-related data doesn't affect display, but breaks the image cache" (`:2241-2264`): keying
  too widely degenerates to decode-every-time. Kotlin: `object ImageCache` in `app/` (it holds
  `Bitmap`s — keep it out of `wire/`), LRU + Mutex + a `Map<Key, Deferred<Bitmap?>>` of in-flight
  loads so N nodes on one URL make one fetch. Key on `url` + `limits` **only**; unlike Emacs, a
  `theme.set` MUST NOT invalidate it. Budget from `ActivityManager.memoryClass`. **Land the two
  crash-closers first and independently: a `Semaphore(3)` around fetch/decode, and catching
  `Throwable` at `ImageLoader.kt:46` — ~20 lines, no cache required.**
- **Push attribute types into the validator from `contract.json`** (LD-10, LD-17, LD-22). Project
  `field_types`/`enums` into `Vocabulary.kt`; drive the required-member loop off `FIELD_TYPES`,
  skipping rows valued `varies-per-node` (amendment #71 sets `selected` to exactly that); delete the
  two hand-duplicated enums. Add `builtinsFromProfiles` beside `nodeTypesFromProfiles`. Add the three
  missing limits (LD-22) using the `max_chart_points` pattern. Extend `VocabularyDriftTest` beyond the
  action key *set* (`SurfaceStoreTest.kt:454`).
- **Split the pie-menu and dialog `collectAsState` reads out of the surface restart scope**
  (`MainActivity.kt:88/95/97`). All three read in one recompose scope today, so opening a dialog
  re-executes the entire surface tree — and because every render composable takes a `JSONObject`
  (unstable, no `equals`), *nothing in the render path is skippable*. Two `PieMenuHost`/`DialogHost`
  composables, ~15 lines. **This is the cheap 90% of the IR argument.**
- **Fix the two serialize-to-compare sites**: `remember(itemsJson.toString())` (`LayoutNodes.kt:630`)
  and `options.toString()` (`InputNodes.kt:258`). Use `val sig = remember(itemsJson) {
  itemsJson.toString() }` then `remember(sig) { … }` — *not* `remember(itemsJson)`, since `JSONArray`
  has no `equals` and identity would reset the user's reorder on every re-push.
- **Server-computed fontification** (§19.5, LD-6's sibling). `handleAnnotation` decodes and calls
  `annotationListener`, assigned only in `EditorTest.kt:221`. **Not a live defect** — `grep fontify
  llm-poc-2/emacs/*.el` finds no sender either, so it is an unimplemented two-sided feature. Still the
  right architecture, and it dissolves LD-7 from the other direction. Emacs's split is `xdisp.c:4527-4529`
  — the display engine knows how to *read* a face, never how to *choose* one, which is why a mode
  written in 2025 fontifies correctly through a redisplay loop written in 1991. **Do the companion
  half first and unconditionally:** `EditorAnnotations` in `wire/` keyed by `(document, editorId)`,
  `handleAnnotation` rejecting the **entire batch** (never partially applying) when any run is
  unsorted, overlapping, or past `s.scalarLength()` — SPEC.md:2792-2794 requires it and a
  1-based/0-based peer bug otherwise reaches `AnnotatedString` and throws at layout. **Also require
  the converted endpoint not to split a surrogate pair** (critic §6). ~150 lines.
- **LD-16, LD-18, LD-19.** Four small edits.

#### Tier 3 — deferred, with thresholds

| Item | Threshold | Status |
|---|---|---|
| Typed `UiNode` IR, Compose-stable | ~1,000 nodes in a *non-lazy* tree; `lazy_column` already bounds composition | Deferred — the Tier-2 scope split removes the dominant trigger. ~2,500-LOC refactor, not 40 lines. |
| Cached content hash + instance reuse | Requires the IR; pays above ~1,000 nodes | Deferred — take the two `toString()` fixes now. |
| jit-lock chunk cache | Only if the editor moves to a windowed text surface | Deferred — today Compose's O(doc) `MultiParagraph` relayout dominates the tokenizer, and chunking would *lose* cross-chunk string/comment correctness. Take the one-line cap removal only. |
| `StringBuilder` shadow | ~1 MB documents; at the floor the rebuild is 0.017–0.071 ms off the UI thread | Do as a byproduct of T2, not its own change. `shadow` must become private with a setter first. |
| Delta-maintained counters | Only if `max_editor_bytes` is declared above the floor | Superseded by declaring it at the floor. |
| Landmark cache for scalar↔UTF-16 | Past ~256 KiB | Skip — take the identity fast path only. |
| `TextFieldState`/`ChangeList` migration | Above ~256 KiB | Deferred. Instead rewrite `EditorSession.diff` (`:57-67`) to scan chars from both ends rather than materializing two `int[]` via `codePoints().toArray()`, backing off one index at a surrogate boundary — ~15 lines, same asymptotics, zero allocation. (Measured: `diff` is 22 ms of the 29 ms per-keystroke cost at the 4 MiB ceiling.) |

### B2. What we deliberately are NOT taking from Emacs

Each was proposed, investigated against both trees, and rejected. **Re-proposing one requires
refuting the reason.**

**Data structures whose problem EBP designed away**

- **An interval tree (`src/itree.c`).** Its two reasons to exist are the augmented LIMIT field for
  overlap queries and the OFFSET/otick lazy-shift machinery (`itree.c:99-128`). §19.5 requires runs
  "sorted, MUST NOT overlap" (SPEC.md:2792-2794), so a sorted `IntArray` + binary search gives the
  same O(log n + k); and "MUST discard an annotation whose session or sequence does not match" means
  annotations **never survive an edit**, deleting OFFSET's entire purpose. Emacs needs the tree
  because overlays are unbounded — its own comment cites "300KB and 30K overlays" as still a
  bottleneck (`marker.c:159-160`). *This is not "not yet" — the spec designed it away.*
- **A gap buffer or rope.** `StringBuilder` is the useful half and ships in the JDK.
- **A Marker registry with `insertion_type`.** §19.4 makes `cursor` REQUIRED on every text-changing
  apply, so the caret's post-splice value is dictated by the peer, not derived. A `class Marker` is
  ceremony around three `Int`s the wire overwrites on the common path. Take the arithmetic, leave the
  registry.
- **Marker adjustment for §19.5 annotation ranges or §19.3 completion positions.** These are
  seq-stamped and MUST be discarded on mismatch; the companion already does this correctly
  (`CompanionEngine.kt:1307`, `:1326`). **Retrofitting adjustment here would be a spec violation, not
  an improvement.**
- **A symbol interner / obarray for member names.** Emacs interns because symbols are compared in the
  evaluator's innermost loop *and* carry mutable per-name state shared by identity. EBP member names
  carry no state; comparison targets are class-file literals the JVM already interned. Doing this
  would also import Review 1's P1-2 deliberately.

**Designs Emacs itself abandoned**

- **Preemptible rendering.** `redisplay-dont-pause` defaults to `true` (`dispnew.c:3252`, `:6912`) and
  the variable is obsolete (`etc/NEWS.24:24`). The comment says why: "Contrary to expectations, a
  value of \"false\" can be detrimental to responsiveness since aborting a redisplay throws away some
  of the work already performed." The companion already has the replacement — `MutableStateFlow`
  (`MainActivity.kt:31`) conflates superseded snapshots by construction. **Do not add a pending-input
  check, cancellation token, chunked composition pass, or `withFrameNanos` yield loop.**
- **`nimages > 40` eviction shrink (`image.c:2371-2372`).** A proxy for memory pressure Emacs's
  time-only policy cannot measure. A byte budget measures it directly.

**Already provided by Kotlin, Compose, or the existing structure**

- **A specpdl / unwind stack.** Traced every state machine: the replay pump's flags are idempotent or
  released in `close()`; dialog and pie-menu teardown already consume the entry before running its
  effect (`:133-143`) — `unbind_to`'s discipline, hand-written and correct; `SurfaceStore.update()` is
  validate-then-mutate; and the two places needing compensating rollback already write
  `record_unwind_protect` longhand (`DurableQueue.admit:139-155`,
  `TriggerFiringService.admit:169-181`). Nested `try/finally` gives C's missing lexical unwind for free.
- **`safe_funcall` around host listeners.** It is a redisplay-specific muzzle by its own comment;
  Emacs lets `run-hooks` signal freely elsewhere. The dispatch loop already fails closed (`:96-104`),
  all 18 callout sites are last-statement-in-handler, and listeners are first-party. Muting trades a
  loud failure for a silently wrong UI.
- **A `Scoped<T>` primitive.** §18.4 makes `theme.set` a single global replacement; Compose's
  `CompositionLocal` already *is* default-plus-override with a defined lookup order.
- **A realized-style cache.** Emacs realizes faces because realization means *font selection* —
  matching against every font on the system (`xfaces.c:126-133`), milliseconds. The companion's
  equivalent is a `when` over ~24 interned strings. The one genuinely expensive realization,
  tokenization, is already memoized correctly (`ContentNodes.kt:144`).
- **A refcount on cache entries.** Emacs needs `img->refcount` because `free_image` releases the
  pixmap while glyph matrices hold the id — a dangling-reference problem C has and Kotlin does not.
- **Compose's diffing.** The problem is not that Compose's diffing is inadequate — it is that passing
  `JSONObject` parameters switches it off. Fix the inputs.

**Net-negative here**

- **Cooperative quit (`maybe_quit`) or a work budget in `SpecValidator.walkNode`.**
  `exceedsDepthLimit` already implements the primitive that matters — a constant-stack pre-parse
  depth scan bounding recursion to 64 frames — with the body capped at 4 MiB and the walk at 10,000
  nodes, on the socket reader thread which never touches the UI thread. `ensureActive()` would be
  pure ceremony.
- **A `while-no-input` abandon of a superseded `surface.update`.** Every update owes a response;
  revisions are monotonic so stale updates only appear on replay; skipping validation would change
  which of 1201-vs-stale wins.
- **Generating the renderer's `when` from `contract.json`.** It cannot know which of the 39 types
  *this build* implements or which Composable to call — that is what positive-knowledge profiles
  express. `NodeSupportPinTest` fails loudly on set inequality. Already correct.

---

## §3 WHERE THE TRACKS TOUCH

1. **Scalar-value text.** A5 (spec) and T2/LD-4 (client) are two ends of one problem. Land A5 first
   so the companion's bounds-checking has a normative rule to cite.
2. **Strict decoding.** A0/A2 and T1 are the same discipline on the two endpoints. Note the asymmetry
   A0 preserves: strictness is **REQUIRED for the Companion**, RECOMMENDED for Emacs. T1 is therefore
   not optional for conformance — the companion is the strict side.
3. **`max_editor_bytes`.** LD-15 is a companion gap, but declaring it interacts with A5 and with §4.5
   reporting duties. Decide the number once, in the welcome, and let both tracks cite it.

---

## §4 BUILD ORDER

1. **A0** — bound §6.2. One paragraph, cheapest item in either track, and everything else in Track A
   reads better afterward.
2. **LD-15 + LD-7 + LD-22** — declare and enforce `max_editor_bytes` at the 65536 floor, delete the
   20,000-char highlight cap, add the two missing aggregate limits. Small edits in
   `DeviceBridge.kt:80`, `CompanionEngine.localEditorEdit`/`handleEditApply`, `SyntaxHighlight.kt:116`,
   plus three ~10-line limit copies. **This goes first among code changes because it decides the
   shape of everything after it:** with the ceiling at the floor, six Tier-3 performance items become
   permanently unnecessary and the one user-visible editor rendering bug disappears. Leaving the
   ceiling implicitly at 4 MiB is what makes the editor look like it needs a rope.
3. **T1 — the strict parser and `EbpValue`.** A leaf change with no dependents; closes LD-9 and LD-8
   outright, deletes two full-body scans, makes LD-20 a compile error, and is the only item that
   converts an entire *class* of future bug into a parse error. Do it before the Tier-2 attribute-type
   work so that work has a typed value to check against.
4. **T2 (editor ownership + typed positions), then T3 (epoch + defaults + override chain).** T2 first
   because the editor is currently *non-functional* for inbound edits — LD-5 means every `edit.apply`
   silently desynchronizes the display — whereas T3's failures, though worse in consequence, need a
   specific push sequence. Inside T2, wire `editorListener` first.
5. **A1–A5**, A5 before further editor work.
6. **The rest of Tier 2**, then **A6**, then **A8**.

**Slip these in ahead of anything above if the calendar allows** — each is ~10–30 lines and closes a
crash, hang, or conformance hole standalone: the `pending` drain in `close()` (LD-13 half), the
`RenderCtx.action` override chain (T3c, closes LD-1), `Semaphore(3)` + `catch (Throwable)` in
`ImageLoader` (LD-12 crash-closer), and the `FrameDecoder` fix (LD-21).

---

## §5 DECISIONS

### 5.1 Constants — **DECIDED** (Caleb, 2026-07-25): adopt

Authorization: *"we can relax the constraints if we have determined they will improve the
implementation."* The determination supports all three:

- **`max_node_depth` = 20.** `json-serialize` hard-caps at 50 containers (`src/json.c:566`, enforced
  at `:404-408`, still 50 on master — no post-30.1 escape). Budget: 2 envelope + 2×20 + leaf +
  wrapper = 44 ≤ 50, leaving margin. Without it, a legal deep snapshot is unemittable by an Emacs
  endpoint and fails as an unhandled local error with no frame and no error code.
- **`max_send_header_bytes` = 128.** `jsonrpc.el`'s header search is bounded to 100 characters
  (`lisp/jsonrpc.el:740-744`, identical at 29.1/30.1/30.2/master). Without it, a conforming Companion
  emitting extra headers wedges the Emacs endpoint permanently and silently.
- **`max_editor_bytes` = 65536 (the §4.5 floor).** The most consequential number here: it is what
  makes six Tier-3 performance items permanently unnecessary. Flagged explicitly because it
  *restricts* rather than relaxes — the editor ceiling drops from an implicit 4 MiB to 64 KiB.

Both spec-side constants are §25 "restricts previously valid content" changes and need SPEC-CHANGES
rows.

### 5.2 `SurfaceStore` durability — **DECIDED** (Caleb, 2026-07-25): relax

Authorization as above. The determination: `SurfaceStore.kt:64-67` documents per-keystroke fsync as
deliberate §15.1 conservatism, but §15.1's actual requirement is that a draft be durable *before any
later durable event* — which an unconditional `flushNow()` at the barriers satisfies exactly, without
two fsyncs per character. Emacs's calibration is the precedent (300-keystroke counter *and* an idle
gate, with `force_auto_save_soon` for barriers, and *less* frequent writes as the file grows).

**Do it in the stated order:** split `records.json` / `drafts.json` first — that is the load-bearing
half and is a pure win requiring no policy change; the amortization is second, and buys nothing on
its own for a field with `on_change`.

### 5.3 §19.5 annotations scope — **OPEN**

An unimplemented two-sided feature (no producer in `emacs/*.el`, no consumer in `app/`). The
companion half (~150 lines) is worth doing regardless — its bounds-checking is the defense against a
peer bug reaching `AnnotatedString` — but the payoff needs the Emacs-side emitter, which is unscoped
work on a third track.

---

## §6 VERIFICATION CHECKLIST

- [ ] Every SPEC change has a `SPEC-CHANGES.md` row. No entry, no amendment.
- [ ] `validate.py` passes. **Two known gaps it does not catch:** `decode_stream` only checks the
      header cap *after* finding `\r\n\r\n` (an unterminated header section loops rather than being
      rejected), and there is no node-depth walk.
- [ ] Goldens regenerated per amendment — A2 (`max_method_bytes`), A5 (astral `edit.delta`), P2-1
      (extra-header positive + unterminated-header negative), P2-2 (**a positive fixture at maximum
      nesting** — today nothing exercises the boundary, so an encoder that can only reach 50
      containers passes every wire golden).
- [ ] New tests reproduce each LD before its fix. Specifically: an astral-character `edit.command`
      (LD-4), a rev-2 `reset_input_ids` push (LD-2), an untouched dialog `checkbox` (LD-3), a 4 MiB
      frame arriving in 8 KiB chunks (LD-21), `jsonValueEquals(null, JSONObject.NULL)` both
      directions (LD-20).
- [ ] LD-4 verified on-device with a real astral character, not only a unit test.
- [ ] Per device-smoke practice: force-stop before smokes, screenshot before tapping.

---

## §7 SCOPE NOT COVERED

- **Review 1 left uncovered:** §2.1, §2.3, §5.1, §10.1, §10.4, §13.1–13.3, §13.5, §13.7, §14.1–14.5,
  §15.4, §16.2–16.4, §17.1, §17.3, §17.6, §18.2, §18.3, §18.5, §18.6, §19.5, §21.3, §21.4, §21.6,
  §21.7, §22.1, §22.2, §22.4, §24.3. Most are Companion-side render/policy, correctly out of scope for
  an Emacs-floor review. Three warrant a second pass: **§22.2** (traffic classes — folds into A8's
  blocking-send question), **§19.5** (Emacs-authored; check against `jit-lock.el`, since a buffer in
  no window has no faces unless the endpoint forces `font-lock-ensure`, and overlay-supplied faces
  *do* overlap unlike text-property runs), and **§13.2/§24.2** (persistent monotonic per-surface
  revisions across process death on a platform that kills without notice).
- **Review 2 coverage was good:** of ~2,700 LOC of uncovered companion main code, the critic
  spot-checked the likely hiding places and found **only `JsonEquality.kt`** concealing a live defect
  (now LD-20). Judged clean and recorded so nobody re-opens them: `Auth.kt` (uses
  `MessageDigest.isEqual` — SPEC.md:738 constant-time compare satisfied), `Substitution.kt`,
  `ToolbarEdits.kt` (UTF-16 **by design** — it feeds a `TextFieldValue`; do not "fix" it),
  `VisualizationNodes.kt` (bounded by `max_chart_points`/`max_canvas_ops`), `Notifications.kt` (tap
  routing is a declared follow-on).
- **Emacs subsystems checked and judged not worth opening:** `src/coding.c` (framing is byte-length
  based and `parseBody` decodes only a complete body with `CodingErrorAction.REPORT`, so a split
  UTF-8 sequence cannot occur; `encodeFrame:186-191` correctly computes `Content-Length` from
  `toByteArray(UTF_8).size`), `src/keyboard.c` (already mined; `DurableQueue.kt:63`'s
  `effectiveNow() = maxOf(clock(), highWater)` already implements the monotonic-clock guarantee),
  `src/composite.c`/`src/bidi.c` (Compose owns grapheme and bidi; one residual folded into the
  fontification item), `src/undo.c`/`src/window.c`/`src/search.c` (no companion analogue).
- **The elisp side (`llm-poc-2/emacs/*.el`) was not reviewed as an implementation.** Several findings
  imply work there (A5's withdrawal mechanism, §19.5's producer). That is a third track, unscoped.
