# PLAN — the deferred downstream consumers (the elisp application layer)

The renderers and dialog/completion layers that CALL `jetpacs-widgets.el` to turn
Emacs content into EBP surfaces. Deferred out of `PLAN-jetpacs-widgets.md` ("Port
after the vocabulary API settles"); the vocabulary is now settled (JW-0..JW-7),
so these can land. Port sources are poc-v1 `jetpacs/llm-poc/emacs/core/*.el`;
targets live beside `emacs/ebp.el` + `emacs/jetpacs-widgets.el` in `llm-poc-2`.

Same boundary as the builders: `jetpacs-` namespace, `(require 'ebp)` +
`(require 'jetpacs-widgets)` (never the reverse — the delineation guard stays
clean), Emacs 30.1 floor, `setopt`, core libs only, org-free (verified: buffer /
results / sections / hypertext / comint have **no** org/org-ql/vulpea deps).

---

## 0. The one structural finding that drives everything

**The consumers do not call `ebp-client-*` today.** They call a poc-v1
*application-framework* that sits between them and the wire and does not exist in
`llm-poc-2`:

- `jetpacs-surfaces.el` — `jetpacs-defaction` (action registry), ownership
  (`jetpacs--claim` / `jetpacs-current-owner` / `with-jetpacs-owner`, multi-app
  view claiming), `jetpacs--in-action-handler` / `jetpacs-in-action-p`, the state
  registry (`jetpacs-on-state-change` / `jetpacs--ui-state`), `jetpacs-connected-p`.
- `jetpacs-shell.el` — `jetpacs-shell-push` (surface push + ownership-scoped ids),
  `jetpacs-shell-after-push-hook`, refresh, and the nav/tab chrome the spec layer needs.
- `jetpacs-async.el` — async task infra (cl-lib only) that `shell` rides.

So there is a **dependency floor**: a slim app-framework, ported onto `ebp.el`,
must land FIRST. It is the thing that translates the seams the renderers expect:

| poc-v1 seam | maps to (`ebp.el`) |
|---|---|
| `jetpacs-defaction NAME FN` (FN `(args payload)`, no return) | `ebp-client-register-action client ACTION FN` (FN `(client params)`, MUST return `accepted`/`stale`/`rejected`; EventId receipt committed by ebp) |
| `jetpacs-shell-push SURFACE SPEC` | `ebp-client-surface-update client surface spec …` |
| prompt → dialog | `ebp-client-dialog-show client dialog-id spec &key style callback` |
| `jetpacs-on-state-change` | the `:state-changed-function` client hook |
| `jetpacs-connected-p` | ebp client state |
| inbound handler args (poc read `(alist-get 'k args)`) | jsonrpc plist decode → `(plist-get (plist-get params :args) :k)` |

This floor is a **rebuild-lite**, not a clean port: `jetpacs.el` transport/auth
and `jetpacs-sync.el` are must-rebuild (replaced BY `ebp.el`), so `surfaces`/
`shell`/`async` port their *registry/ownership* logic but **re-wire** their
transport seams onto `ebp-client-*`.

---

## 1. Dependency DAG (require edges; ★ = must land first, not yet ported)

```
ebp.el ✅ ── jetpacs-widgets.el ✅
  └─★ JC-0 floor:  async → surfaces (defaction, ownership, state seam, connected-p)
                          → shell (shell-push over ebp-client-surface-update, refresh)
        ├─ JC-1 buffer      (dispatch registry + --line-spans + -render Tier-0 + -call-shimmed + -refresh)
        │     ├─ JC-2 results ─ tablist          (need buffer + surfaces + tabulated-list)
        │     │        └─ JC-3a sections         (needs results)
        │     ├─ JC-3b hypertext                 (needs buffer only; image-resolver rebuild)
        │     └─ JC-3c comint                    (needs buffer)
        ├─ JC-4 dialog  (REBUILD of minibuffer)  (ebp-client-dialog-show)
        ├─ JC-5 completion (REBUILD direction, PORT harvester)
        └─ JC-6 declarative view (OPTIONAL): lint(format-6) → source → spec (needs shell)
~~config (jetpacs-root; image cache) — small prereq for JC-3b hypertext~~
  RESOLVED at JC-3b: the disk cache existed solely to mint `file://` URIs, which
  format 6 forbids outright — so it is DELETED, not ported, and `jetpacs-config.el`
  drops out of the DAG entirely (its remaining contents are deployment-only,
  deferred until an app ships).
build-contract.el → RETIRE;   build-bundle.el → defer to a U-phase deploy step
```

---

## 2. Per-module verdict

| Module (poc-v1) | Verdict | Why |
|---|---|---|
| `jetpacs-async` | **port** | cl-lib only; async task infra |
| `jetpacs-surfaces` | **rebuild-lite** | ownership/registry ports; re-wire transport seams to `ebp-client-*` |
| `jetpacs-shell` (slim) | **rebuild-lite** | `shell-push`→`ebp-client-surface-update`; ownership-scoped surface ids |
| `jetpacs-buffer` | **port** | Tier-0 renderer; format-6 span drift; org-free |
| `jetpacs-results` / `-tablist` | **port** | mechanical drift; `tablist` needs `tabulated-list` |
| `jetpacs-sections` | **port** | span-surgery alist→plist; needs results |
| `jetpacs-hypertext` | **port + 1 rebuild** | mechanical, EXCEPT the image resolver (`file://`→`data:image`) |
| `jetpacs-comint` | **port** | mechanical drift |
| `jetpacs-minibuffer` → `jetpacs-dialog` | **REBUILD (~90% new)** | dialog contract inverted (see JC-4) |
| `jetpacs-complete` | **rebuild direction, port harvester (~60% ported)** | `:edit-complete-function` hook; harvester ports |
| `jetpacs-source` / `-spec` (+`lint` fmt-6) | **port (optional track)** | declarative-view layer; needs `lint`+`shell` |
| `build-contract.el` | **RETIRE** | superseded by authored `contract.json` + `validate.py` + catalog-sync ERT |
| `build-bundle.el` | **defer** | deployment concatenator; drop the contract-embed step |

---

## 2.5 Spec-compliance runtime requirements (audited)

A spec-conformance audit of this plan (6 areas, adversarially verified) found **no
plan-bugs and no needed SPEC amendments** — the vocabulary and endpoint already
provide every primitive, and the dialog's non-reactive one-shot model is
intentional (§18.1), not a gap. But several **runtime MUSTs** must be honored by
the consumer/framework layer; the widgets builders + the ERT gates do NOT enforce
them. Each is owned by the rung noted:

1. **§16.2 push-time node-type gate (JC-0, critical).** `jetpacs-shell-push` MUST,
   before `ebp-client-surface-update` fires, run `jetpacs-check-node-types` on the
   fully-built spec against the **live welcome** advertised set for the target —
   `(plist-get (plist-get (ebp-client-profiles client) :app) :node_types)` (and
   `:notification`/`:widget`) — NOT the reference `jetpacs-check-profile` defconst
   (the maximal 39-type union, which passes everything the builders can construct).
   "Emacs MUST NOT emit an unadvertised type" (§16.2) is a **sender** MUST; the
   renderers are data-driven (buffer content decides which optional types — image,
   table, chart… — appear), so an under-advertising companion silently 1201s the
   whole surface. The gate belongs on the runtime push path; the ERT uses a
   deliberately under-advertised fixture (the reference defconst can't witness this).

2. **`event.action` handler status derivation (JC-0).** The `jetpacs-defaction`
   shim MUST hand the handler the **full `params`** (surface, `revision_seen`,
   `dialog_id`, `fields` — all alist→plist, not just `:args`), and each ported
   handler MUST return `rejected` on invalid/unregistered args (§14.1/§14.4) and
   `stale` when the `revision_seen`/surface context makes the action unsafe
   (§14.5), returning `accepted` only after the effect is durable. A no-return poc
   handler blanket-wrapped as `accepted` would durably accept replay-unsafe/invalid
   events. Handlers MUST NOT return `duplicate` (ebp synthesizes it from the receipt
   store). Exit gate covers the `stale` and `rejected` branches, not just `accepted`.

3. **Drop the poc client-side `confirm` gate (JC-0).** Confirmation is
   Companion-enforced (§14.1 — the Companion presents `confirm` before creating the
   event); the event reaches the handler only post-confirmation, so the shim MUST
   NOT re-prompt with a bridged `y-or-n-p`.

4. **§13.4 variant + capability discipline is the consumer's (JC-0/JC-6).** ebp.el
   passes `current_view`/`stale_spec`/namespace through unvalidated, so the push
   path owns: pass `:current-view` only for a multi-view `app:*` spec; build
   `stale_spec` as the SAME variant as `spec` and strip every stateful node +
   `editor` (§13.5); gate a `notification:`/`widget:` push on the granted
   `surfaces.notification`/`surfaces.widget` capability (`ebp-client-granted`).

5. **Bound buffer emission by span/frame limits, not just lines (JC-1).** The
   500-line cap respects §4.5 node/child limits (500 ≪ 10,000) but NOT the welcome
   `max_rich_spans` (per `rich_text`) or `max_frame_bytes` (whole surface). Extend
   the line cap into a span/byte budget (truncation note, or paginate via
   `lazy_column`).

6. **Image: advertise-form gate + size limits (JC-3b).** Emit an `image` URI form
   only when the connection advertises it in the target `features`
   (`image.data`/`image.https`; an unadvertised form is content-invalid, §17.2) —
   `jetpacs--check-image-url`/`check-profile` do NOT enforce per-target features, so
   the hypertext rung owns it. Bind the inline-`data:image` budget to the welcome
   `max_image_bytes`/`max_decoded_image_bytes`/`max_image_pixels` **and** remaining
   frame headroom (base64 ≈ 1.33× raw); downscale/re-encode or degrade to `caption`
   rather than emit an oversized data-URI that voids the surface.

**Confirmed non-issue (recorded so it isn't re-litigated):** a filterable
large-collection `completing-read` dialog has no reactive realization — dialogs are
one-shot and dialog nodes emit no `state.changed` **by design** (§18.1). That is
intentional, not a spec gap; `completing-read`→`enum_list` + the JC-4 design point
(paginate vs. capf) is the correct response. And "the dialog profile forbids layout"
(JC-4) is the **reference** companion's advertised 26-type set, not a SPEC rule
(§10.2 mandates only `dialog.submit`/`dialog.dismiss` there) — always gate on the
connection's advertised dialog set.

---

## 3. The rung ladder

Each rung is a PR-sized unit landing with its exit gate green (byte-compile
warnings-as-errors + ERT via `test/run-tests.sh`, plus a device smoke). New ERT
files slot in as `-l test/…-test.el` lines exactly like the widget suite.

### JC-0 — the application-framework floor **(the crux; highest risk)**
Port `jetpacs-async.el`. Build a **slim `jetpacs-surfaces.el`** on `ebp.el`:
ownership (`jetpacs--claim`/`current-owner`/`with-jetpacs-owner`), the
`jetpacs-defaction` macro as a **shim over `ebp-client-register-action`** that
reconciles the signature (`(client params)` ← poc `(args payload)`), decodes
inbound `:args` from the params plist, and returns `accepted`/`stale`/`rejected`;
`jetpacs--in-action-handler`/`in-action-p`; `jetpacs-on-state-change` wired to the
client `:state-changed-function`; `jetpacs-connected-p`; a client-handle accessor.
Build a **slim `jetpacs-shell.el`**: `jetpacs-shell-push`→`ebp-client-surface-update`
with ownership-scoped surface ids, the refresh seam, and (if JC-6 is in scope) the
nav/tab chrome helpers. Prefer slim; grow as later rungs demand.
This rung also lands the cross-cutting runtime gates §2.5(1–4): the push-time
§16.2 node-type gate against the live welcome (in `jetpacs-shell-push`), the
`defaction` full-params + status-derivation contract, dropping the poc client-side
`confirm`, and the §13.4/capability push discipline.
*Exit gate:* a client connects; a `jetpacs-defaction` handler registers and an
`event.action` round-trips to `accepted` — **and** a stubbed handler round-trips to
`stale` and to `rejected` (§2.5-2); a surface pushes via `jetpacs-shell-push` to
`applied` (live smoke); a spec carrying an unadvertised node type is refused
against an **under-advertised** fixture before push (§2.5-1); ERT with a stubbed
client for the shim's arg-decode + status-return contract.

### JC-1 — `jetpacs-buffer.el` (the renderer linchpin)
Port the Tier-0 generic *Emacs-buffer → node-tree* renderer (`jetpacs-buffer-render`
/ `-render-region` / `-render-tail` / `jetpacs-render-buffer` dispatch +
`jetpacs-render-buffer-register` + `jetpacs-buffer-call-shimmed` + `-refresh-function`).
**Format-6 span drift** in `jetpacs-buffer--span-style`: `:bold t`→`:font-weight "bold"`;
**drop** `:strike`; **delete** `jetpacs-buffer--raise-baseline` + both call sites
(no `baseline`); fold `:code`→`:mono`; keep italic/underline/color/bg/mono.
`jetpacs-scroll-here`→`(jetpacs-with-attrs node :scroll_here t)`. Faces still
resolve to absolute `#rrggbb` (not role tokens) — leave `--color-hex` as is.
Register its two actions via the JC-0 shim. Bound emission against the welcome
`max_rich_spans`/`max_frame_bytes`, not just the 500-line cap (§2.5-5).
*Exit gate:* render-a-known-buffer ERT (a fontified fixture → node tree, byte-asserted
via `jetpacs-node->canonical-json` against a new `test/goldens/renderers.golden`);
`(jetpacs-check-profile tree 'app)` passes; a span/byte-budget-exceeding fixture
truncates rather than over-emits (§2.5-5); live "applied" smoke.

### JC-2 — `jetpacs-results.el` + `jetpacs-tablist.el`
Port both (mechanical drift: positional `jetpacs-text` style→`:style`;
`jetpacs-box :weight`→`(jetpacs-with-attrs … :weight)`; `:args` alist→keyword-plist
on the build side + `plist-get` on the handler side; `jetpacs-defaction`→JC-0 shim).
`tablist` additionally needs `tabulated-list`. Visit/step substrate (locus parsing,
shimmed replay, region framing, nav state machine) ports verbatim.
*Exit gate:* pure-helper ERT (locus parse); render structural ERT (cards +
`results.visit` `:args` plist + cap note); action round-trip against a stubbed
visit seam (armed stepper, boundary clamps); live smoke on `occur`/`grep`.

### JC-3 — `jetpacs-sections` + `jetpacs-hypertext` + `jetpacs-comint`
- **sections** (needs results): PORT. Rewrite the span-surgery trio
  (`--strip-taps`/`--retarget-taps`/header-body) alist→plist
  (`assq-delete-all 'on_tap` → fresh plist minus `:on_tap`; `alist-get`→`plist-get`;
  `setf (alist-get …)`→`plist-put`). Three action `:args` alist→plist.
  `jetpacs-collapsible` is signature-compatible.
- **hypertext** (needs buffer only — the `config` image cache is deleted, see the
  DAG note; DONE 2026-07-25, `emacs/jetpacs-hypertext.el` + 21-test exit gate; the
  resolver settled the design decision as a cascade — https passthrough under
  `image.https`, data-URI inline under `image.data` bounded by the three per-image
  limits + frame headroom with PNG/JPEG header-sniffed pixel counts, caption
  otherwise; the "wrap in `(apply #'jetpacs-hypertext …)`" line below is WRONG —
  the renderer seam wants a LIST, a vector nests as one malformed child): PORT the two-phase
  scan→model→emit substrate + DOM-table pass + nav allowlist verbatim; rewrite the
  emitter's builder calls; `jetpacs-markup`→`(jetpacs-text … :style "mono" :syntax S)`
  with `S` a string; `jetpacs-surface :padding`→`with-attrs`; `jetpacs-table-row`
  new `(KIND &rest cells)` shape; wrap the final list in `(apply #'jetpacs-hypertext …)`.
  **The one real rebuild: the image resolver.** `jetpacs--check-image-url` accepts
  only `https://` / `data:image/*` and rejects `svg`; poc-v1 emits `file://` + bare
  `http://`. Rework: emit `data:image/<png|jpeg>;base64,…` inline, or degrade to the
  `caption` fallback; upgrade/degrade `http`. This is a design decision (inline
  data-URI budget vs. caption-degrade) to settle in this rung. Per §2.5-6: emit a
  URI form only when the target `features` advertise it (`image.data`/`image.https`)
  — the checker does NOT enforce per-target features — and bind the inline budget to
  the welcome `max_image_bytes`/`max_decoded_image_bytes`/`max_image_pixels` + frame
  headroom (downscale/re-encode or degrade to `caption`).
- **comint** (needs buffer): PORT (scroll-here→`:scroll_here`; box `:weight`→with-attrs;
  positional text style→`:style`; `:args` plist).
*Exit gate:* render-a-known-buffer ERT per renderer (shr/help/Info fixture;
synthetic magit-section eieio tree; a comint tail) + profile check + live smoke;
explicit hypertext image cases (data-URI / unreadable→caption / http→degrade /
form-not-advertised→caption / over-budget→downscale-or-caption, §2.5-6).

### JC-4 — the dialog rebuild: `jetpacs-dialog.el` (replaces `jetpacs-minibuffer.el`)
**REBUILD** (~90% new). Re-advise the ~18 core prompt functions
(`y-or-n-p`/`read-string`/`read-passwd`/`completing-read`/`completing-read-multiple`/
`read-char-choice`/…), but each now pushes via `ebp-client-dialog-show` and reads
the answer from the callback `(status result error)` (`result` → `:value` + `:fields`).
Four structural changes force the rebuild: (1) notification→request inversion —
`prompt.reply`/`.dismiss`/`.toggle` custom actions **cease to exist**; (2) dialog
nodes emit no `state.changed` — the **live-filtering picker is gone**, values return
only at submit via `capture_fields`; (3) same-`dialog_id` repaint is now `1201`; (4)
the **dialog profile forbids `lazy_column`/`card`/`flow_row`** — so `completing-read`
becomes a native **`enum_list`** (options `{label,value}`; multi → `:multi-select`;
free-text add → `:allow-add`) inside a `column`, submit via
`(jetpacs-dialog-submit :capture-fields '("pick"))`. Bridge sync-return-over-async
with an `accept-process-output` pump keyed off the callback. Gate every spec through
`(jetpacs-check-node-types spec advertised "dialog")`.
**Design decisions — DECIDED (Caleb, 2026-07-25):**
1. **Large/dynamic collections: the capf/editor picker.** Live per-keystroke narrowing
   via a dialog-hosted synchronized editor + `edit.complete`, NOT sequential
   narrowing dialogs. Fact base at decision time: the wire side already exists in
   full — `edit.complete` is a registered Companion→Emacs request with an engine
   send path (`CompanionEngine.kt:1631`), dialog editors are engine-legal, counted
   against `max_editor_sessions`, opened/closed on dialog lifecycle, and gated on
   `editor.sync` (`:1861,:751-772`), and ebp.el answers from
   `:edit-complete-function` with session/seq staleness (`ebp.el:1249`). What JC-4b
   builds: (a) `editor` added to `DIALOG_NODE_TYPES` + pin test + render-in-Dialog
   verification (advertisement change, no spec amendment — profiles are per-target
   Companion advertisements under §10.2); (b) the Compose completion dropdown over
   the existing engine seam (debounced per keystroke, top-N, tap inserts via the
   normal local-edit delta path); (c) the per-prompt completion source in
   jetpacs-dialog.el — during a picker prompt, `:edit-complete-function` resolves
   from the COLLECTION via `completion-boundaries`/`all-completions` (the JC-5
   buffer harvester is NOT a prerequisite; it later plugs into the same dropdown
   for real editors). Conclusion path: editor + OK (`dialog.submit`); a
   synchronized editor is never a stateful field, so Emacs reads the chosen value
   from the MIRROR at conclusion, with RET-picks-top resolved Emacs-side.
2. **Context-buffer cards: budgeted `rich_text` inside the dialog.** Keep the poc's
   recording seams (`display-buffer` advice + `temp-buffer-show-hook`, gated on the
   device-flow marker), render as `section_header` + `rich_text` through the Tier-0
   span builder under a byte budget — both types ARE in the dialog profile, so v2
   improves on the poc's 4000-char plain-text cards.

**Rung split (consequence of decision 1):**
**JC-4a DONE + DEVICE-VERIFIED** (`f3feced`, `660e34d`, 2026-07-26): `jetpacs-dialog.el` (11 advised
prompts), the floor's `jetpacs-flow-continue`/`jetpacs-device-flow-p` marker, ebp.el's
`ebp-client-abandon` + request-id return (C-g out of a bridged prompt now cancels the dialog per
SPEC 7.5/18.1), and the DialogHost scroll prerequisite. 17-test exit gate + 4 device phases
(yn/string/enum/scroll). **The prerequisite needed more than `verticalScroll`:** a Compose Dialog
measures content with UNBOUNDED height, so the scroll never engaged and the window was clipped —
`heightIn(max = 80% screen)` is what makes it work, and only the device could show that. Baselines
228 elisp / 9 suites.

- **JC-4a — the prompt floor, no picker:** `jetpacs-dialog.el` with the advised
  simple prompts (`y-or-n-p`/`yes-or-no-p`/`read-string`/`read-from-minibuffer`/
  `read-passwd`/`read-char`/`read-char-choice`/…), the sync-over-async pump, the
  device-flow marker that survives `run-at-time` continuations (D2 makes the poc's
  `jetpacs--in-action-handler` gate always-false at prompt time), context cards per
  decision 2, and small closed collections as native `enum_list` (multi →
  `:multi-select`, non-require-match → `:allow-add`).
- **JC-4b — the capf picker: CODE DONE (`83d0892`), DEVICE GATE PENDING (`bf2fe89`).**
  All three items landed: (a) `editor` in `DIALOG_NODE_TYPES` (+pin test);
  (b) the completion dropdown in `RenderEditor` — 180 ms settle so a typing burst
  costs one round trip per pause, plain clickable rows rather than a floating
  menu (a popup anchored inside a scrolling dialog drifts off its field), gated
  on §17.4's `complete` flag; (c) the per-prompt collection-backed completion
  source in `jetpacs-dialog.el`, with the JC-4a stopgap kept as the fallback for
  a Companion that cannot host a dialog editor. `requestCompletion` now hands the
  (session, seq, cursor) it issued against back to `selectCompletion`, because
  re-reading them at tap time compares the engine's state with itself and always
  passes. 6 picker tests drive ebp's real `edit.complete` handler; 234 elisp + both
  Kotlin suites green. **DEVICE-VERIFIED** (`4bfcb18`): both phases green — typing produced one
  `edit.complete`, Emacs answered from the collection, the device rendered the
  candidates, and the tap returned the candidate through the MIRROR. The device
  caught a bug five green unit tests missed: SPEC 18.1 closes a dialog's editor
  sessions BEFORE the submit response, and ebp fires `edit-change-functions` on
  that close with the session gone, so the shadow was wiped to nil exactly when
  the picker read it (`stringp nil`, answer already typed). The watch now takes
  strings only; the regression drives ebp's real close handler. Also caught a
  VACUOUS pass: the astral phase's 5 candidates fell under the enum threshold and
  never used the picker at all — only the "Emacs answered edit.complete" counter
  exposed it. **JC-4 (a+b) COMPLETE.**
- **Prerequisite (device half, either rung):** `DialogHost` wraps dialog content in
  a plain `Column` with no `verticalScroll` (`MainActivity.kt:139`) — content below
  the fold is unreachable. One-line fix + smoke; §18.1 forbids `lazy_column` NODES
  in dialog specs, not the host container scrolling.
*Exit gate:* dialog-builder goldens (byte-match + `check-profile 'dialog`); round-trip
ERT with a stubbed `ebp-client-dialog-show` (`y-or-n-p`→t/nil, `read-string`→`fields.in`,
`completing-read`→`fields.pick`, dismissed→`keyboard-quit`, timeout); assert no
`prompt.*` actions register; live device smoke.

### JC-5 — the completion rebuild
**REBUILD the direction, PORT the harvester.** Register the ported harvester
(`--collect`/`--capf-data`/`--word-fallback`/`--annotate`/`--shadow-buffer`, all pure
Emacs) as the `ebp-client-create :edit-complete-function` hook
(`(doc editor-id text cursor) → (PREFIX . CANDS)`), each CAND a plist
`(:label :annotation? :insert?)` — **drop `kind`**, `insert` defaults to `label`.
Delete the `jetpacs-defaction "edit.complete"` + `completions.show` + `request_id`
and the whole jetpacs-sync coupling (ebp.el owns the document mirror + staleness).
*Exit gate:* direct ERT (`(doc text cursor)` → `(:prefix … :candidates …)`; the
obarray-blowout guard; word fallback; session/seq-mismatch → ebp `1201`); live
editor-completion smoke via the `:edit-complete-function` seam.

### JC-6 — declarative-view layer (OPTIONAL sub-track)
`jetpacs-lint.el` re-pointed at format-6 — but keep only what the builders don't
already subsume: the arbitrary-tree walk (`jetpacs-lint-spec`) for trees assembled
from external data, and the test helpers `jetpacs-test-visible-text` /
`jetpacs-test-view-ok` / `jetpacs-render-to-json` (re-home these for the consumer
ERT suites). Then `jetpacs-source.el` (query registry; needs lint field-types) and
`jetpacs-spec.el` (declarative view → node tree: `jetpacs-scroll-row`→`(jetpacs-row … :scroll t)`;
`jetpacs-box :padding`→with-attrs; carry the `jetpacs-month-abbrev` helper; needs
`source`+`shell`+`lint`). `spec` is table-driven → the best **golden-testable** of
the set (deterministic item-list → deterministic tree).
*Exit gate:* golden ERT on `spec` compilation (list/calendar/board layouts) + a
`source` cache/schema ERT + `check-profile 'app`.

---

## 4. Format-6 drift — the call-site checklist (applies across JC-1..JC-6)

The builder NAMES survive, so most call sites compile, but these shapes changed
(the 15-delta node drift is already absorbed *inside* the builders):

- `jetpacs-text` style is now `:style` (a string), not a positional symbol.
- `:weight`/`:padding` on `box`/`surface` are **universal §16.5 attrs** → wrap with
  `(jetpacs-with-attrs node :weight N :padding M)`; the containers silently drop them otherwise.
- `jetpacs-scroll-here` is **gone** → `(jetpacs-with-attrs node :scroll_here t)`.
- `jetpacs-scroll-row` is **gone** → `(jetpacs-row … :scroll t)`.
- `jetpacs-markup` is **gone** → `(jetpacs-text … :style "mono" :syntax S)` (`S` a string).
- `jetpacs-action :args` MUST be a **keyword member-plist** (`(:buffer X)`), not an
  alist; the action name MUST contain a dot; **offline default is `drop`** (was
  `queue`) — pass `:when-offline 'queue :ttl-s N` if queueing is wanted.
- Handler side: inbound args arrive as plists → `(plist-get (plist-get params :args) :k)`.
- `jetpacs-table-row` is `(KIND &rest cells)` with `KIND` `"data"`/`"header"`.
- span members: `code`→`mono`, `bold`→`font_weight`, no `strike`/`tag`/`baseline`
  (lands in `jetpacs-buffer`'s span builder — consumed spans arrive correct once JC-1 lands).
- `image` URL forms: only `https://` / `data:image/*`; **no `file://`, no `http`, no svg**.

## 5. Testing strategy (no goldens cover renderers)

Three tiers, reusing the existing harness (`jetpacs-node->canonical-json`,
`jetpacs-check-profile`, `test/run-tests.sh`'s delineation→byte-compile→ERT gates):

- **A. Render-a-known-buffer ERT (new `renderers.golden`).** Build a fixture buffer
  in a known mode (shr/help/Info/magit-section/occur/comint or a fontified text
  buffer), call the renderer, serialize the returned tree, `string=` against a
  checked-in golden line. Anchor fixtures on stable inputs (no timestamps/paths).
- **B. Profile-conformance assertion.** Wrap every renderer's output in
  `(jetpacs-check-profile … 'app)` (dialog trees `'dialog`, notification bodies
  `'notification`) inside the ERT — the buffer-consumer analogue of the W9
  `NodeSupportPinTest`. Assert every tappable region round-trips a registered action.
  This asserts the builder emits only real vocabulary against the **reference** union;
  it is NOT the runtime §16.2 gate. That gate (§2.5-1) runs `jetpacs-check-node-types`
  against the **live welcome** set on the push path and gets its own JC-0 ERT with a
  deliberately under-advertised fixture (the reference defconst cannot witness an
  under-advertising companion).
- **C. Live "applied" smoke.** `ebp-connect 127.0.0.1:8765` (KAT pairing), render a
  real buffer on `:ready-function`, `ebp-client-surface-update … :callback`, assert
  `status "applied"`. Add `smoke-dialog.el` (push via `ebp-client-dialog-show`, tap
  OK/Cancel, assert submitted + captured `fields`) and a completion smoke exercising
  `:edit-complete-function`. Smokes run manually / via the adb harness, not in `run-tests.sh`.

Dialog/completion rebuilds additionally use **stubbed-endpoint ERT** (stub
`ebp-client-dialog-show` / feed `:edit-complete-function` directly).

## 6. Retired / deferred (not ported)

- **`build-contract.el` — RETIRE.** The projector inverted: `contract.json` is now
  authored in the ebp repo and self-checked by `validate.py`; the elisp catalogs are
  pinned by the catalog-sync ERT (`test/jetpacs-widgets-test.el`). A format-6 projector
  would be a near-total rewrite whose output nothing consumes. Optional tiny residual:
  an elisp-catalog↔SPEC-prose ERT (the one check neither `validate.py` nor catalog-sync
  covers). No dependency on it for any renderer.
- **`build-bundle.el` — defer to a U-phase deploy step.** A source concatenator; when
  re-added, drop the `jetpacs-lint--contract-embedded` embed (moot — catalogs read the
  contract only at test time). Not on the critical path.

## 7. Decisions for you

1. **Scope / tiers.** Core renderers (JC-0..JC-3) is the minimum useful cut — it lands
   the whole "render any Emacs buffer on the device" capability. +JC-4/JC-5 adds
   dialogs and editor completion. JC-6 (declarative views: lint/source/spec) is the
   most optional and most dependency-heavy; execute it only if the app needs
   data-driven views. Recommend: **JC-0 → JC-1 → JC-2 → JC-3**, then decide on 4/5/6.
2. **The JC-0 floor: slim shim vs. full port.** Recommend a **slim** surfaces+shell
   (ownership + `defaction` shim + `shell-push` + state seam) and grow it per rung,
   over porting the full ~90 KB poc-v1 surfaces/shell up front.
3. **Naming.** The dialog rebuild is a new `jetpacs-dialog.el` (not `-minibuffer`);
   confirm the file name.
4. **Two design points inside rungs** (settle when you reach them): the hypertext
   image resolver (inline `data:image` vs. caption-degrade), and the dialog
   large/dynamic-collection strategy (paginate a new `dialog_id` vs. serve via capf).

## 8. References
- Port sources: `llm-poc/emacs/core/jetpacs-{buffer,hypertext,sections,results,tablist,comint,minibuffer,complete,source,spec}.el`, `llm-poc/emacs/core/jetpacs-{surfaces,shell,async,config,lint}.el`, `llm-poc/emacs/build-{contract,bundle}.el`.
- Targets/seam: `emacs/ebp.el` (`ebp-client-surface-update` 1115, `ebp-client-dialog-show` 1245, `ebp-client-register-action` 803, `ebp-client--handle-edit-complete` 1026 + `:edit-complete-function`, `:state-changed-function`); `emacs/jetpacs-widgets.el` (the full builder + `jetpacs-with-attrs`, `jetpacs-check-profile`, `jetpacs-hypertext`, dialog builtins, `jetpacs-dialog-node-types`).
- Governance: `docs/REWRITE-PLAN.md` (port manifest L37-47, boundary L61-84); `docs/PLAN-jetpacs-widgets.md` (the vocabulary layer this builds on; format-6 drift §6).
