# JC-0 — the application-framework floor: implementation specification

*Merged from seven parallel extractions; every load-bearing claim re-verified against the real sources on 2026-07-24. Deviations from the analysts are flagged inline as **[corrected]**; anything I could not verify is flagged **[unverified]**.*

**Verification notes.**
- ✅ Verified in-source: `ebp-client-register-action` / `--handle-event-action` / `--handle-state-changed` / `--surface-request` / `-surface-update` / `-dialog-show` / `-create` config / `--on-welcome` (`:before-replay-function` fires pre-`queue.replay`, `:ready-function` post-`session.ready`); `jetpacs-check-node-types` / `--collect-node-types` / `--opaque-members` / `jetpacs-multi-view` / `-notification-surface` / `-widget-surface` / `-scaffold`; poc-v1 `jetpacs-async.el` (225 L, verbatim), `jetpacs-surfaces.el` L255-470 + L546-578, `jetpacs-shell.el` L455-632.
- ✅ Verified by execution in Emacs 30.1: `(member "text" ["text"])` → `(wrong-type-argument listp ["text"])`; `(jsonrpc--json-encode '(:a nil :b 1))` → `{"a":null,"b":1}`; jsonrpc decode yields `(:node_types ["text"] :present :json-false)`.
- ✅ Verified against SPEC.md: §16.2 sender gate, §10.2 (nodes **and builtins and features**, "MUST NOT interpret a missing profile or list as support for everything"), §13.5 stale_spec, §14.1 wake.
- **[corrected]** The `DRAFT-amendments-*.md` files use *draft* numbering that was renumbered on ratification. The authoritative mapping is `ebp/SPEC-CHANGES.md` rows 34-53; §6 below uses that. (The `sender-duties` analyst used ratified numbers and is correct; the `DRAFT-` docs are stale.)
- **[unverified]** poc `test/jetpacs-tests.el` line numbers cited by analysts (the file exists at `llm-poc/test/jetpacs-tests.el`, async tests confirmed present at L2101+; other cited offsets not individually checked).

---

## 0. Ratified decisions (2026-07-24, Caleb)

Two of §8's open questions are settled by decision; the rest take §8's recommendation.
**Read §2.3 and §5 through D1 — they were drafted against the option that was *not* chosen.**

### D1 — Q2: per-owner surfaces (§8 option **b**)

Each owner gets its own surface, id **`app:<owner>`**; every app therefore has its own
snapshot, revision line, and back stack. Consequences that MUST land in the build:

- `jetpacs-shell-surface-id` derives `app:<owner>` from `jetpacs-current-owner`;
  `jetpacs-shell-define-root` is keyed by owner; the reconnect-restore set becomes
  "every claimed owner with a live root", not one surface.
- **Owner strings become wire identifiers.** `jetpacs--claim` MUST validate the owner as
  a §4.4 Surface-ID name component (non-empty; ASCII letters, digits, `.` `_` `-` `:` `/`)
  and MUST keep the complete `app:<owner>` inside the §4.4 128-octet cap. An illegal owner
  is a *registration-time* error, never a push-time `1201`.
- **§13.1 limits now bind app count, not view count.** `max_surfaces` (REQUIRED ≥ 16) counts
  only *currently present* snapshots, so more than 16 simultaneously-present apps earns
  `1201` with `data.reason: "surface-limit"` — JC-0 MUST `surface.remove` (tombstone) an
  owner's surface on teardown rather than leave it present. `max_surface_ids` (≥ 1024) counts
  every distinct id with a retained snapshot **or tombstone**, held until pairing revocation,
  so owner names MUST be stable and MUST NOT be generated per session (§13.1: "MUST NOT churn
  Surface IDs as a substitute for revisions").
- **The `jetpacs-async` push seam changes arity.** poc `jetpacs-async--flush-push` calls
  `(jetpacs-shell-push)` with **zero arguments** (`jetpacs-async.el:76-77`) — unambiguous only
  under one global surface. Under D1 the debounce must repush *the owners whose entries
  settled*. Each `jetpacs-async--entry` already carries `:owner`, so: accumulate a pending-owner
  set in `jetpacs-async--settle`, and have `--flush-push` repush each owner in it, skipping
  owners with no live root. This keeps `jetpacs-async` shell-agnostic — it passes owners
  through, it never learns a surface id.

### D2 — Q6: blocking inside an action handler is FORBIDDEN (§8 option **a**)

A handler returns its status immediately; any prompt is driven from a `run-at-time 0`
continuation. Consequences: the `accepted`-means-durable contract stays honest; no
`accept-process-output` pump is permitted inside the jsonrpc dispatch extent;
`jetpacs--in-action-handler` survives only as an advisory flag; and **Q8 dissolves** — with no
nested pump there is no `jetpacs-async` re-entrancy hazard. poc `jetpacs-files.el`'s
`files.grep` violates this and MUST be rewritten when it is ported (record against the files rung).

### Taken from §8 without further input

Q1 single-client floor (`jetpacs-attach` errors on a second client) · Q3 non-status return →
`rejected` + `display-warning :error` · Q4 `jetpacs-event-stale-p` opt-in per handler, never
automatic · Q5 bare-id state keying · Q7 add `:after-replay-function` to `ebp-client-create`
(~6 lines in `ebp.el`) rather than reimplementing replay above the boundary.

---

## 1. Scope

### Delivers

Three files under `llm-poc-2/emacs/`, requiring `ebp` + `jetpacs-widgets`, never the reverse. Emacs 30.1 floor, `setopt` for user options, core libraries only, org-free.

1. **`jetpacs-async.el`** — near-verbatim port of the 225-line poc module (keyed async-loader cache, generation sweep on the push cycle, owner-scoped teardown). Only two docstring lines and one hook-registration form change.
2. **`jetpacs-surfaces.el`** — *rebuild-lite*, ~60% of the poc file dropped. Keeps: ownership registry (`jetpacs--claim` / `jetpacs-current-owner` / `with-jetpacs-owner`), the `jetpacs-defaction` shim over `ebp-client-register-action`, the in-action flag, the state-change registry wired to `:state-changed-function`, `jetpacs-connected-p`, and the **client-handle accessor + attach path** (new; no poc analogue).
3. **`jetpacs-shell.el`** — *rebuild-lite*, ~75% cut. Keeps: `jetpacs-shell-push` over `ebp-client-surface-update`, the four §2.5 runtime gates, degrade-in-place build, `jetpacs-shell-after-push-hook`, the refresh seam, the one-slot snackbar, the live-coding repush debounce.

Plus the cross-cutting runtime gates **§2.5(1)-(4)**, and (added here, verified against §10.2) the **builtins** half of the profile gate, plus the two new sender gates from ratified amendments **#84** (`max_editor_bytes`) and **#85** (`wake` without `offline.wake`).

### Explicitly defers

| Deferred | To | Why |
|---|---|---|
| View registry, tabs, route params, overlays, nav chrome (poc shell L46-246, L268-455 — 388 L) | JC-6 / a chrome rung | format-6 has **no** `drawer`/`drawer_item`/`top_bar`/`bottom_bar`/`nav_item`/`list_item` node types; these are rebuilds as generic compositions in `jetpacs-scaffold`'s §17.6 slots, not ports. **Verified:** no JC-1..JC-3 renderer source references `jetpacs-shell-*` at all — they reach the host only through their own seam defvars. |
| The whole form subsystem (poc surfaces L492-756, 265 L) | later rung | Nothing in the JC-0..JC-6 port set consumes it; it depends on `jetpacs-ui-state-put`, which the ebp-owned input store deliberately does not offer. |
| Stock Settings screen (131 L), after-save refresh (41 L), `jetpacs-lint-views`, devtools recording | unported / JC-6 | Depend on `jetpacs-settings` / `jetpacs-apps` / `jetpacs-devtools`, none in the port manifest. |
| Sender-side conflation outbox + `revision_seen` lag gauge (poc surfaces L117-216) | **ebp.el gap, not jetpacs** | §5 backpressure is a §24.2 endpoint duty. Rebuilding it above the boundary would violate the architecture. Record and push unconflated. |
| Revision counter, disk persistence, welcome snapshot absorb | ebp.el (already done) | `ebp-client--surface-floor` / `--absorb-floor` / `--on-welcome`. |
| Action catalog (`:args`/`:doc` on defaction) | RETIRE | **Verified:** zero of the 158 poc `jetpacs-defaction` call sites pass either; only consumer is out-of-scope `jetpacs-pack.el`. |
| Client-side `confirm` gate | **DROP permanently** | §14.1 / §2.5-3. llm-poc-2 widgets ships no confirm index. |
| `jetpacs--ui-state` store, `jetpacs-ui-state-put/-clear` | DROP | Second source of truth vs `ebp-client-input-values`. §14.6 clearing is `:reset-input-ids`. |
| §2.5-5 span/byte budget, §2.5-6 image feature gate | JC-1 / JC-3b | Per plan. |
| §19 editor-seed reconciliation (#71) | new rung after JC-0 | Needs Emacs's real buffer; ebp's `(doc . id)` text mirror is not that. |

---

## 2. Files and complete public API

### 2.1 `emacs/jetpacs-async.el` (~235 L; port-verbatim + ~10 L seam)

`(require 'cl-lib)` only. **No `require` of `ebp`, `jetpacs-widgets`, or any framework file** — it emits no wire vocabulary and must stay that way. Three forward-declared framework names.

| Name | Arglist | Contract |
|---|---|---|
| `jetpacs-async` | `(cl-defun jetpacs-async (key loader &key owner))` | Return `(STATUS . PAYLOAD)` for KEY (`equal`); start LOADER once on first sight, cache the result. **First call always returns the literal `'(pending)`**, even for a synchronous resolve. LOADER is `(lambda (RESOLVE REJECT) …)` and may return a cleanup thunk stored as the entry's cancel. OWNER defaults to `(bound-and-true-p jetpacs-current-owner)`. |
| `jetpacs-async-clear-owner` | `(owner)` | Drop every entry scoped to OWNER, running each cancel. App-teardown leak guard. **No caller at JC-0** — must be covered by ERT or it reads as dead code. |
| `jetpacs-async-reset` | `()` | Drop all state, run every cancel, zero the generation, cancel the debounce timer. Teardown + test fixture. **New under ebp:** must also be called on client detach (`jetpacs-detach`). |
| `jetpacs-async--after-push` | `()` | Double-dash but **effectively public**: the shell-integration point. Sweep entries stamped below the current generation (running cancels), then `cl-incf` the generation. Registered on `jetpacs-shell-after-push-hook`. |
| `jetpacs-async--flush-push` | `()` | Test seam; the debounce timer's target. Runs the coalesced push now. |
| `jetpacs-async--cache` / `--generation` / `--push-timer` | defvars | Read directly by the ported ERTs. **Every one of these names must survive the port unrenamed** — the poc suite `cl-letf`s `jetpacs-shell-push` and pokes all four internals; renaming turns a near-free port into a rewrite. |

Internals ported verbatim: `jetpacs-async--entry` (cl-defstruct: `status value gen owner cancel`), `--schedule-push`, `--settle`, `--start`, `--read`, `--message`, `--run-cancel`.

Two correctness guarantees in `--settle` worth preserving verbatim: a completion for a **swept** entry never pushes (`eq` identity check against the live cache entry), and only the **first** of competing resolve/reject wins (`pending` check).

**Three changes from poc:**
1. Docstring example line `(jetpacs-error e)` → `(jetpacs-text e :color "error")`. **Verified:** `jetpacs-error` does not exist in llm-poc-2 widgets; `"error"` is a valid §16.5 color role. (`(jetpacs-progress)` survives unchanged — the builder is now `(cl-defun jetpacs-progress (&key variant value))`, so the zero-arg call is still valid.)
2. Header comment + `--after-push` docstring: "after each successful shell push" → "after each pushed frame, once the `surface.update` revision is minted — **not** gated on the Companion's `applied`". This documents seam S2 in the file itself.
3. Delete the trailing `(with-eval-after-load 'jetpacs-shell (add-hook …))`; the slim shell adds the hook at its own load time, so the dependency points one way only.

Drop the `;;;###autoload` cookie (inert — the tree has no loaddefs generation; `jetpacs-widgets.el` carries zero cookies) and the `(fboundp 'jetpacs-shell-push)` guard in `--flush-push` (the slim shell is now a hard sibling). Note the `'(pending)` return is a **shared quoted literal** returned from two sites — document it read-only.

### 2.2 `emacs/jetpacs-surfaces.el` (~330 L, from 786)

```elisp
(require 'cl-lib) (require 'subr-x) (require 'seq) (require 'ebp)
```
**Not** `jetpacs-widgets` — a slim surfaces needs no builder. New: `(defgroup jetpacs nil "…" :group 'ebp)` (llm-poc-2 has no `jetpacs` customize group today; `jetpacs-strict-namespaces` is a defcustom that references one).

**Ownership (port-verbatim from L262-316)**

| Name | Arglist | Contract |
|---|---|---|
| `jetpacs-current-owner` | defvar, nil | The app/module id currently registering. nil = anonymous core. |
| `jetpacs-strict-namespaces` | defcustom, nil | Non-nil: a cross-owner collision `error`s instead of `display-warning`. |
| `with-jetpacs-owner` | `(id &rest body)` macro | `(declare (indent 1) (debug (form body)))`; let-binds `jetpacs-current-owner`. The only defmacro in the file. |
| `jetpacs--claim` | `(kind name)` | Attribute `KIND:NAME`; warn (or error) on a different-owner clash; same-owner is silent; no-op when owner is nil. Returns NAME. |
| `jetpacs--owner-of` | `(kind name)` | Owner id or nil. |
| `jetpacs--owned-names` | `(kind owner)` | The teardown enumerator — the registry's only read path. Keep or the registry is write-only. |
| `jetpacs--unclaim` | `(kind name)` | Drop the record. |

**Client handle (all NEW — no poc analogue)**

| Name | Arglist | Contract |
|---|---|---|
| `jetpacs--client` | defvar, nil | The single live `ebp-client`. **JC-0 is explicitly single-client** (decision D1). |
| `jetpacs-client` | `()` | The live client or nil. Every jetpacs-* layer reaches ebp through this. |
| `jetpacs-client-or-error` | `()` | The client, or `(error "jetpacs: no client attached")`. |
| `jetpacs-connected-p` | `()` | `(and (jetpacs-client) (eq (ebp-client-state (jetpacs-client)) 'ready))`. `ready` is the only state past the §10.3 barrier (states: `connected` `awaiting-nonce` `challenged` `awaiting-welcome` `syncing` `ready` `closed`). **There is no public predicate in ebp.el** — `ebp-client--authenticated-p` is private. |
| `jetpacs-attach` | `(client)` | Store CLIENT in `jetpacs--client`, then **replay every entry of `jetpacs-action-handlers` into `ebp-client-register-action`**. Returns CLIENT. Must be called synchronously, with no intervening blocking call, before the welcome lands. |
| `jetpacs-detach` | `(&optional client)` | Clear the handle, `(jetpacs-async-reset)`, clear `jetpacs--state-handlers`. Wire to disconnect/teardown. |
| `jetpacs-connect` | `(host port &rest config)` | Thin wrapper: injects `:state-changed-function #'jetpacs--on-state-changed`, `:before-replay-function #'jetpacs-shell--before-replay`, and pushes any caller `:ready-function`; calls `ebp-connect`, then `jetpacs-attach` on the returned client, then returns it. |

**Actions**

| Name | Arglist | Contract |
|---|---|---|
| `jetpacs-action-handlers` | defvar, `equal` hash | Global action-name → `(ARGS PARAMS)` handler. **Must survive** as a load-time staging table: every poc `jetpacs-defaction` runs at top level, long before a client exists; ebp's allowlist is per-client. |
| `jetpacs-defaction` | `(name fn)` | See §4. Registers globally **and** into the live client if one is attached. Returns NAME. `:args`/`:doc` dropped. |
| `jetpacs-undefaction` | `(name)` | `remhash` from both the global table and `(ebp-client-actions client)` — ebp has **no** `ebp-client-unregister-action`. `jetpacs--unclaim`s the name. |
| `jetpacs--dispatch` | `(client params fn)` | The wrapper installed per action name. See §4. |
| `jetpacs--in-action-handler` | defvar | Non-nil in a handler's dynamic extent. 16 consumers in the JC-4 rebuild. |
| `jetpacs-in-action-p` | `()` | Public reader. Nil in an async continuation. |
| `jetpacs-event-stale-p` | `(params)` | Non-nil when `(:revision_seen params)` is strictly below `(gethash surface (ebp-client-revisions client) -1)`. **Always nil for a dialog event** (§14.4: dialog events carry `:dialog_id` and MUST omit `:surface`/`:revision_seen`, so `stale` is not derivable). A helper handlers opt into, **not** an automatic gate — see open question Q4. |

**State**

| Name | Arglist | Contract |
|---|---|---|
| `jetpacs--state-handlers` | defvar, `equal` hash | Widget id → callback. |
| `jetpacs-on-state-change` | `(id fn)` | FN called with the new value. Bare-id keying retained (app ids are namespaced) — see open question Q5. |
| `jetpacs-on-state-change-clear` | `(prefix)` | Remove every subscription whose id starts with PREFIX. |
| `jetpacs--on-state-changed` | `(client surface revision id value)` | The `:state-changed-function` hook body. **Does NOT store the value** — ebp already wrote `ebp-client-input-values` and applied the §14.6 + P1#2 reset reconciliation before calling. Fans out to `jetpacs--state-handlers` inside a `condition-case` so one bad callback cannot break the connection. |
| `jetpacs-ui-state` | `(id &optional surface)` | **Read-through only**: `(ebp-client-input-value (jetpacs-client-or-error) (or surface jetpacs-shell-surface-id) id)`. No writer exists by design. |
| `jetpacs-ui-state-list` | `(id &optional surface)` | Port-verbatim coercion (vector / list / string / JSON-array string → list of strings, malformed discarded) over the read-through. |
| `jetpacs-test-reset-state` | `()` | Fixture seam. Slimmed: clears `jetpacs--state-handlers`, then `fboundp`/`boundp`-guarded `jetpacs-async-reset` and the shell's snackbar. Keep the guard idiom. |

### 2.3 `emacs/jetpacs-shell.el` (~280 L, from 853)

```elisp
(require 'cl-lib) (require 'ebp) (require 'jetpacs-widgets)
(require 'jetpacs-surfaces) (require 'jetpacs-async)
```
Dropped requires: `jetpacs` (the replaced transport), `jetpacs-devtools`, `jetpacs-spec`. `(require 'jetpacs-buffer)` becomes `(with-eval-after-load 'jetpacs-buffer …)` so the floor lands before JC-1. **[corrected]** poc declared `(require 'jetpacs-async)` but never referenced it; here the require is real (the shell adds the sweep hook itself).

| Name | Arglist | Contract |
|---|---|---|
| `jetpacs-shell-surface-id` | defvar, `"app:main"` | Default surface for a zero-arg push. §13.4 namespace-prefixed. **[corrected]** poc used `"app:dashboard"`; `app:main` matches the ebp smokes and the SPEC §10.2 example. |
| `jetpacs-shell--roots` | defvar, alist | `SURFACE → (:builder FN :owner ID :required BOOL :stale-after-s N :stale-builder FN)`. Replaces the dropped view registry; a single-root surface per entry. |
| `jetpacs-shell-define-root` | `(cl-defun … (surface builder &key required stale-after-s stale-builder))` | Register/replace BUILDER (nullary → a root Node or a SurfaceSpec) for SURFACE; `jetpacs--claim "surface"`; schedule a repush. REQUIRED means "re-push on reconnect, before `queue.replay`". Returns SURFACE. |
| `jetpacs-shell-remove-root` | `(surface)` | Unregister, `jetpacs--unclaim`, and `ebp-client-surface-remove` when connected. |
| `jetpacs-shell-push` | `(cl-defun … (&optional surface &key spec current-view stale-after-s stale-spec reset-input-ids callback))` | See §5. **MUST remain zero-arg callable** — `jetpacs-buffer-refresh-function` funcalls it nullary and `jetpacs-async--flush-push` calls `(jetpacs-shell-push)`. Returns the claimed revision, or nil when nothing was pushed. |
| `jetpacs-shell-after-push-hook` | defvar, nil | Normal hook, run **synchronously after `ebp-client-surface-update` returns its revision**, on the success path only. Not from the `:callback`. Sole in-manifest member: `jetpacs-async--after-push`. |
| `jetpacs-shell-refresh-hook` | defvar, nil | Normal hook run before a cache-bypassing push; apps drop memo caches here. |
| `jetpacs-shell-refresh` | `(&rest _)` | `(run-hooks 'jetpacs-shell-refresh-hook)` then push. `&rest _` so it is hook-safe. |
| `jetpacs-shell-notify` | `(text)` | Queue TEXT as the snackbar for the next push. One slot, latest wins. The Companion re-shows a snackbar only when the text **changes**. |
| `jetpacs-shell--build` | `(surface plist)` | Call the builder inside `condition-case`; a crash degrades **in place** to a visible error view: `(jetpacs-column (jetpacs-text (format "Error building %s" surface) :style "title") (jetpacs-text (error-message-string err) :style "body"))`. A broken builder costs its own screen, not the whole push — the live-coding contract. **[corrected]** poc used positional `'title`/`'body`; format-6 `:style` takes a **string**. |
| `jetpacs-shell--gate-spec` | `(client surface spec what)` | The §16.2 + §10.2 gate. See §5 step 5. Signals; never sanitizes. |
| `jetpacs-shell--surface-target` | `(surface)` | Prefix → `:app` / `:notification` / `:widget` / `:tile` (§10.2). Unknown prefix → error. |
| `jetpacs-shell--before-replay` | `(client)` | The §10.3 step-3 seam: push every `:required` root **before** `queue.replay`. Installed by `jetpacs-connect`. |
| `jetpacs-shell--schedule-repush` | `()` | 0.5 s idle debounce after a registry mutation on a live session; no-op while disconnected (the reconnect push carries the registrations). |

Load-time seam installs (all `with-eval-after-load`, so the floor stands alone):
```elisp
(add-hook 'jetpacs-shell-after-push-hook #'jetpacs-async--after-push)
(with-eval-after-load 'jetpacs-buffer
  (setq jetpacs-buffer-refresh-function #'jetpacs-shell-push))
```

---

## 3. The seam table

| # | poc-v1 call | ebp.el replacement — exact signature | Notes |
|---|---|---|---|
| S1 | `(jetpacs-surface-push SURFACE SPEC &optional TTL-S STALE-SPEC CURRENT-VIEW)` (surfaces:241) | `(cl-defun ebp-client-surface-update (client surface spec &key stale-after-s stale-spec current-view reset-input-ids callback))` — ebp.el:1115 | Positional→keyword; `ttl_s`→`stale_after_s`; new `:reset-input-ids`. **Returns the integer revision synchronously**, claimed as `1+ floor` at send time; the wire request is async and `:callback` gets `(STATUS ERROR)`, STATUS `"applied"` or `"stale"` — **both success** (§13.2 stale is benign; retrying on stale is a push loop). A push that errors or times out still **burns** its revision. |
| S2 | `(run-hooks 'jetpacs-shell-after-push-hook)` at the tail of poc `jetpacs-shell-push`, inside the condition-case, success only (shell:603) | same hook, run **immediately after S1 returns**, synchronously, **not** in `:callback` | **The one real design decision in this port.** The generation contract requires only that the *build* finished (stamping happens during the build), not that the Companion applied the frame. Deferring to the callback means a 1201 / content-invalid / offline push never advances the generation — entries accumulate forever, cancel thunks never run, processes and timers leak. |
| S3 | `(jetpacs-surface-remove SURFACE)` | `(cl-defun ebp-client-surface-remove (client surface &key callback))` — ebp.el:1135 | Now a revisioned tombstone request; the poc trick of yanking a queued update out of the outbox first is moot. |
| S4 | `(jetpacs-register-handler "event.action" #'jetpacs--on-action)` + one global lookup | `(ebp-client-register-action client ACTION FN)` — ebp.el:803, FN `(CLIENT PARAMS)` → `accepted`/`stale`/`rejected` | **Inversion of control.** ebp owns the server and does the lookup itself in `ebp-client--handle-event-action` (ebp.el:884), in the §14.4 order: envelope → duplicate → allowlist → handler. JC-0 **must not** re-register `"event.action"` — doing so silently displaces the receipt/reconciliation machinery. |
| S5 | `(jetpacs-register-handler "state.changed" #'jetpacs--on-state-changed)`, `(alist-get 'id payload)` | `:state-changed-function` on `ebp-client-create`; hook `(CLIENT SURFACE REVISION ID VALUE)` — ebp.el:953 | ebp stores the value and applies §14.6/P1#2 reconciliation **before** the hook; a superseded report never reaches it. jetpacs must not re-store. |
| S6 | `jetpacs--next-revision`, `jetpacs-revision-file`, `--revision-load/-persist`, `--absorb-revision-snapshot` | **nothing — delete** | `ebp-client--surface-request` claims `1+ floor` at send; `ebp-client--absorb-floor` raises it from the welcome, from `applied`, and from `stale`. `(ebp-client-revisions client)` is **read-only** to jetpacs. |
| S7 | outbox / `--flush-outbox` / `--note-lag` / `--sent-revisions` / `--lag-streak` / `jetpacs-surface-conflate-max-delay` | **nothing — do NOT port** | §5 backpressure is a §24.2 endpoint duty; ebp.el has no equivalent and exposes no per-event lag hook. Record as an **ebp.el gap**. |
| S8 | `(jetpacs-connected-p)` reading `jetpacs--process` + `jetpacs--session` (jetpacs.el:851) | `(eq (ebp-client-state client) 'ready)` | Note: inbound `event.action` dispatches in **both** `syncing` and `ready` (replay delivers events before `session.ready`), so a handler can fire before ready — but **sends** must be gated on `ready`. |
| S9 | `(add-hook 'jetpacs-connected-hook #'jetpacs--absorb-revision-snapshot -50)` / `… --reset-conflation -49` / `… shell-push 10` | `:before-replay-function` (§10.3 step 3, required pushes) and `:ready-function` (post-barrier) on `ebp-client-create` | Depth ordering **collapses** — ebp absorbs floors during welcome processing, before either hook. `test/ebp-wire-test.el:789` asserts the wire order `session.hello, auth.response, surface.update, queue.replay, session.ready`. **Pushing in `:ready-function` violates the barrier** (the existing smokes do it because they have no reconnect story — do not copy them). |
| S10 | `(jetpacs-node-supported-p TYPE)` reading `(alist-get 'node_types jetpacs--session)`, permissive when absent | `(jetpacs-check-node-types SPEC (append (plist-get (plist-get (ebp-client-profiles client) :app) :node_types) nil) "app")` | Per-target, **fail-closed**, whole-tree scan. `jetpacs-check-profile` **cannot** be used — its `app` branch is the maximal 39-type union and passes everything the builders construct. |
| S11 | `(jetpacs-granted-p CAP)` reading `(alist-get 'granted jetpacs--session)` | `(ebp-client-granted client)` — a **VECTOR** of strings | Use `seq-contains-p` or `(member cap (append … nil))`; bare `member` on the vector errors. |
| S12 | `(jetpacs-lint-on-push … jetpacs-lint-sanitize-spec)` inside `jetpacs-surface-update` (surfaces:225-233) | `jetpacs-shell--gate-spec` → **refuse** | Semantics **invert**: poc sanitized a bad subtree into a visible error node and pushed anyway; §16.2 makes emitting an unadvertised type a sender MUST-NOT. |
| S13 | `(jetpacs--claim "surface" SURFACE)` inside `jetpacs-surface-push` | keep `jetpacs--claim` in surfaces; call it from `jetpacs-shell-define-root` / `jetpacs-shell-push` | ebp.el has no ownership concept and must not gain one. |
| S14 | `(add-hook 'jetpacs-queue-drained-hook #'jetpacs-shell-refresh)` (shell:811) | **no ebp analogue** | ebp does §15.3 replay (`--on-welcome` / `--schedule-replay-retry`, `replay-summary`) but exposes **no** replay-complete seam. Drop the post-replay refresh in JC-0, or request a hook from ebp.el. Do not reimplement replay above the boundary. |
| S15 | `(y-or-n-p confirm)` in the dispatcher, prompt from `jetpacs--confirm-index` | **nothing — pass `:confirm` on the descriptor** | §14.1 / §2.5-3. `jetpacs-widgets.el:450` validates `:confirm` as a non-empty string; the whole confirm index is already gone. Re-prompting is a **double** prompt. |
| S16 | `(jetpacs-async-reset)` from `jetpacs-test-reset-state` | keep the `fboundp`-guarded fixture seam **and** call it from `jetpacs-detach` | New under ebp: poc's session was process-global, so a cache outliving a connection was invisible. Each `ebp-connect` mints a fresh client; without this, ready values and in-flight loaders from a dead session bleed into the new one. |
| S17 | poc spec shape `((views . ALIST-of-symbol) (initial_view . STR))` | `(jetpacs-multi-view VIEWS INITIAL-VIEW)` → `(:views HASH-TABLE :initial_view "id")`; single-root = **the root node itself** | View values must satisfy `jetpacs--root-node-p` (a `:t`-headed plist) — delete the `((children . [scaffold]))` wrapper. `:views` is an **`equal` hash-table**, not a plist: the variant test is `(plist-member spec :views)`, the accessor is `gethash`. |

---

## 4. The `jetpacs-defaction` shim

### 4.0 It is a function, not a macro

**[corrected]** The plan's JC-0 text says "the `jetpacs-defaction` macro". poc-v1 is `(cl-defun jetpacs-defaction (name fn &key args doc))` — there is no expansion. All ~158 call sites pass a **lambda as a value**: `(jetpacs-defaction "files.open" (lambda (args _) …))`. Keeping it a defun preserves call-site compatibility across the ~20 in-port-set sites for free; making it a macro would require rewriting every one. **Spec: `jetpacs-defaction` is a `defun`.** Do not let the `def*` name imply a macro contract (a docstring cannot be attached the way `defun` call sites expect) — say so in its docstring.

### 4.1 What the user writes

```elisp
(with-jetpacs-owner "grocy"
  (jetpacs-defaction "grocy.consume" (lambda (args params) … 'accepted)))
```

- `NAME` — a string. **Must contain a dot** (§4.4 + `jetpacs-action` build-time check). `jetpacs-defaction` re-validates it with `jetpacs--check-identifier` and errors early, so a name that would fail at descriptor-build time fails at registration time instead.
- `FN` — a function of **two** positional arguments `(ARGS PARAMS)`. This is deliberately the same arity as poc's `(args payload)`, so ported bodies compile unchanged; only the `alist-get` reads become `plist-get` and an explicit status return is added.
  - `ARGS` = `(plist-get params :args)` — a keyword plist, or nil.
  - `PARAMS` = the **full** event.action params plist (satisfies §2.5-2).
- Return value: exactly one of `accepted`, `stale`, `rejected`.

### 4.2 What it does

```
jetpacs-defaction NAME FN
  1. (jetpacs--check-identifier NAME "action") and require a "." in NAME
  2. (jetpacs--claim "action" NAME)                  ; ownership bookkeeping
  3. (puthash NAME FN jetpacs-action-handlers)       ; the load-time staging table
  4. when a client is attached:
       (ebp-client-register-action (jetpacs-client) NAME
                                   (jetpacs--action-shim NAME))
  5. return NAME
```

`jetpacs--action-shim` returns a closure of `(CLIENT PARAMS)` that looks FN up in `jetpacs-action-handlers` **at dispatch time**, not at registration time — so a live-coded re-`defaction` takes effect without re-registering with ebp.

`jetpacs-attach` replays step 4 for every entry in `jetpacs-action-handlers`. **This is the structural mismatch most likely to be missed:** every poc registration is a top-level form evaluated at load; ebp's allowlist is a per-client hash created by `ebp-client-create`. Without the replay, an `ebp-connect` after the modules load registers **zero** actions, and every inbound event answers `{status: rejected, message: "action not allowlisted"}` — a silent, total failure that a stubbed-client ERT will not catch unless it exercises the attach path.

### 4.3 The dispatch wrapper

```elisp
(defun jetpacs--dispatch (client params fn)
  "Run FN for one event.action and derive its SPEC 14.4 status."
  (let ((args (plist-get params :args))
        ;; §2.5-3: NO confirm gate.  The Companion presented `confirm'
        ;; before creating the event; a client-side re-prompt is a double
        ;; prompt AND would block the jsonrpc dispatch extent.
        (jetpacs--in-action-handler t)
        ;; Pin completion redirection back to the built-ins: ivy/counsel/
        ;; consult reroute prompts BEFORE the advised primitives run and
        ;; would otherwise reach a keyboard UI the phone cannot drive.
        (completing-read-function #'completing-read-default)
        (read-file-name-function  #'read-file-name-default)
        (read-buffer-function     nil)
        (disabled-command-function nil))
    (condition-case err
        (pcase (funcall fn args params)
          ((and status (or 'accepted 'stale 'rejected)) status)
          (other
           (display-warning
            'jetpacs
            (format "action %s returned %S, not accepted/stale/rejected \
(SPEC 14.4); answering rejected"
                    (plist-get params :action) other)
            :error)
           'rejected))
      ;; Cancelling a bridged prompt raises `quit', which `error' does not
      ;; catch; poc let it unwind through the process filter.  Both map to
      ;; `rejected' -- an escaped elisp error becomes a bare -32603 with no
      ;; data.kind, which is a SPEC 8 violation (ebp's typed-error helper
      ;; `ebp-client--error' is private, so the shim must catch first).
      (quit  'rejected)
      (error
       (message "jetpacs: action %s failed: %s"
                (plist-get params :action) (error-message-string err))
       'rejected))))
```

Note what is **absent** and why: no `jetpacs-surfaces--note-lag` (S7), no confirm gate (S15), no `jetpacs--last-action-time` (sole reader is out-of-scope `jetpacs-witheditor.el`), and **no logging of `PARAMS`** — ratified amendment #74 puts calendar titles/times, SMS sender identifiers and call numbers into `trigger.fired` args, and they MUST NOT reach normal logs. The failure `message` above carries only the action name.

### 4.4 How inbound params reach the handler

jsonrpc.el decodes with `:object-type 'plist :array-type 'array :null-object nil :false-object :json-false` (verified in `/usr/share/emacs/30.1/lisp/jsonrpc.el.gz:630-634). Therefore:

| Wire | In PARAMS | Poc read | New read |
|---|---|---|---|
| `event_id` (32 lowercase hex) | `:event_id` | — | `(plist-get params :event_id)` |
| `action` | `:action` | `(alist-get 'action payload)` | `(plist-get params :action)` |
| `args` object | `:args` (plist, or absent) | `(alist-get 'file args)` | `(plist-get args :file)` |
| `surface` + `revision_seen` | `:surface` `:revision_seen` | — | present **exclusively with each other**, and never with `:dialog_id` (§14.4) |
| `dialog_id` | `:dialog_id` | — | present exclusively; a dialog event carries **no** surface/revision |
| `fields` | `:fields` (plist; **omitted when empty**, never null) | no analogue | `(plist-get (plist-get params :fields) :pick)` |
| `occurred_at_ms`, `queued_at_ms` | integers | — | |
| any JSON `false` | `:json-false` — **truthy in elisp** | — | test `(eq v :json-false)`, never `(unless v …)` |
| any JSON array | a **vector** | — | `seq-contains-p` / `(append v nil)` |

**What the shim never has to do**, because `ebp-client--handle-event-action` already did it in §14.4 order: envelope validation (32-hex event_id, dotted action, integer `occurred_at_ms`, context exclusivity) → `-32602`; duplicate EventId → `{status: "duplicate"}` **without invoking the handler**; unregistered action → `{status: "rejected", message: "action not allowlisted"}`. Handlers **MUST NOT** return `duplicate` — ebp synthesizes it.

### 4.5 Status mapping, precisely

| Handler returns | ebp emits | Cost |
|---|---|---|
| `accepted` | `{"status":"accepted"}` | ebp **synchronously durably commits** the EventId receipt (SQLite `synchronous=FULL`, or `write-region` with `write-region-inhibit-fsync` bound to nil) **before the reply leaves**. Commit failure instead answers `1500 event-retry` and calls `ebp-client--force-replay-retry`, so the Companion will redeliver. Return `accepted` only once the effect is durable, and make the handler idempotent (§14.4). |
| `stale` | `{"status":"stale"}` | Free. Use when `revision_seen`/surface context makes the effect unsafe (§14.5). |
| `rejected` | `{"status":"rejected"}` | Free. Use for invalid/unresolvable args (§14.1/§14.4). |
| anything else | `-32603 "handler returned %S"`, kind `internal-error` | **The shim intercepts this and answers `rejected` + `display-warning :error`** — see open question Q3. |
| a signalled `error` or `quit` escaping the shim | jsonrpc replies `-32603 "Internal error"` with **no `data.kind`** — a §8 violation | The shim's `condition-case` prevents this. |

**A blanket-`accepted` wrapper is forbidden** (§2.5-2): it durably commits receipts for events that in fact failed or were replay-unsafe, and the Companion will never redeliver them.

### 4.6 Worked example — all three statuses

```elisp
(with-jetpacs-owner "demo"
  ;; Rename the buffer named by the tapped row.  A row identifies a buffer
  ;; by index into the snapshot that was tapped, so a tap made against an
  ;; older revision may name a row that has since moved: that is `stale',
  ;; not `rejected' -- the Companion may re-present it against the live
  ;; snapshot, whereas `rejected' is terminal.
  (jetpacs-defaction "demo.rename-buffer"
    (lambda (args params)
      (let ((buffer (plist-get args :buffer))
            (name   (plist-get args :name)))
        (cond
         ;; SPEC 14.1/14.4 -- unresolvable arguments are never durable.
         ((not (and (stringp buffer) (stringp name)
                    (not (string-empty-p name))
                    (get-buffer buffer)))
          'rejected)
         ;; SPEC 14.5 -- the event was created against a snapshot below the
         ;; live floor for its surface; the row it named may have moved.
         ((jetpacs-event-stale-p params)
          'stale)
         (t
          (with-current-buffer buffer (rename-buffer name t))
          ;; The effect is durable in Emacs before `accepted' is returned,
          ;; and ebp commits the receipt before the reply leaves the process.
          (jetpacs-shell-push)
          'accepted))))))
```

```elisp
(defun jetpacs-event-stale-p (params)
  "Non-nil when PARAMS' event was created against an outdated snapshot.
Nil for a dialog or global event: SPEC 14.4 gives those no surface or
revision context, so `stale' is not derivable for them.  This is a helper
a handler opts into -- lag alone is not semantic staleness."
  (let ((surface  (plist-get params :surface))
        (seen     (plist-get params :revision_seen))
        (client   (jetpacs-client)))
    (and client surface (integerp seen)
         (< seen (gethash surface (ebp-client-revisions client) -1)))))
```

**Hard constraint on every handler body:** it runs **synchronously inside jsonrpc.el's dispatch extent**, i.e. inside the process filter. It MUST NOT call `y-or-n-p`, `read-string`, `completing-read`, `accept-process-output`, or a nested synchronous `jsonrpc-request` — any of those stalls the connection or deadlocks the filter, and the Companion sees no status until the user answers, which may be never. A handler that needs a dialog must return a status now and drive the prompt from a `run-at-time 0` continuation. **`jetpacs-files.el`'s `files.grep` does exactly the forbidden thing today** (`read-string` inside the handler) — flag it for the JC rung that ports it. See open question Q6.

---

## 5. `jetpacs-shell-push` — full algorithm

```
(cl-defun jetpacs-shell-push (&optional surface
                              &key spec current-view stale-after-s
                                   stale-spec reset-input-ids callback))
```
Zero-arg = "re-render `jetpacs-shell-surface-id`, no navigation" — the meaning `jetpacs-buffer-refresh-function` and `jetpacs-async--flush-push` depend on. **Pin this in the exit gate**: a mis-slimmed signature produces either a `wrong-number-of-arguments` only on the timer-driven async path (rare, easy to miss) or a push of the wrong surface.

**Ordered steps.**

1. **Cancel the pending repush timer.** Any explicit push satisfies a queued registry repush.
2. **Resolve the target.** `SURFACE` defaults to `jetpacs-shell-surface-id`. Look up its entry in `jetpacs-shell--roots`. No entry and no explicit `:spec` → return nil (nothing registered; not an error).
3. **Guard the connection.** `(unless (jetpacs-connected-p) (return nil))`. `ebp-client-notify` / `--request` signal on a nil or dead connection; `ready` is the only state past the §10.3 barrier. *(Exception: when called from `jetpacs-shell--before-replay` the state is `syncing`; that path calls an internal `jetpacs-shell--push-1` that skips this guard, since §10.3 step 3 requires the push to precede `queue.replay`.)*
4. **Pop the snackbar** — `(prog1 jetpacs-shell--snackbar (setq jetpacs-shell--snackbar nil))` — and wrap steps 5-10 in an `unwind-protect` whose cleanup requeues it on any non-local exit (`(setq jetpacs-shell--snackbar (or jetpacs-shell--snackbar snack))`). A failed push showed nothing, so the feedback must survive.
5. **Build, degrading in place.** `(jetpacs-shell--build surface plist)` inside `condition-case`; a builder crash becomes the visible error view (§2.2). If the builder returned a bare root node it is the single-root `app:*` SurfaceSpec as-is; a wrapper plist (`jetpacs-multi-view` / `-notification-surface` / `-widget-surface`) is used verbatim.
6. **GATE 1 — §16.2 node types + §10.2 builtins (plan §2.5-1).** *Runs OUTSIDE the degrade `condition-case` and OUTSIDE any swallow-and-`message` handler: §16.2 is a sender MUST, so a refusal must be loud, not degraded.*
   ```elisp
   (let* ((target  (jetpacs-shell--surface-target surface))   ; :app / :notification / …
          (profile (plist-get (ebp-client-profiles client) target)))
     ;; §10.2: a missing profile is NOT support for everything.
     (unless profile
       (error "jetpacs: no %s surface profile advertised (SPEC 10.2)" target))
     (jetpacs-check-node-types spec (append (plist-get profile :node_types) nil)
                               (substring (symbol-name target) 1))
     ;; §13.5: stale_spec is a complete SurfaceSpec emitted for the same
     ;; target, so the same sender gate applies to it.
     (when stale-spec
       (jetpacs-check-node-types stale-spec (append (plist-get profile :node_types) nil) …))
     ;; §10.2 also mandates gating BUILTINS.  Nothing in jetpacs-widgets
     ;; collects them -- this scanner is new in JC-0.
     (jetpacs-shell--check-builtins spec (append (plist-get profile :builtins) nil)))
   ```
   **`(append … nil)` is mandatory, not cosmetic.** `jetpacs-check-node-types` uses `member`; the welcome arrives through jsonrpc.el so `:node_types` is a **vector**; verified: `(member "text" ["text"])` → `(wrong-type-argument listp ["text"])`. **[corrected]** The plan's §2.5-1 snippet omits the coercion and would crash. `jetpacs-check-profile` must **not** appear on this path.
7. **GATE 2 — §13.4 variant discipline (plan §2.5-4).** Pass `:current-view` **only** when `(plist-member spec :views)` — i.e. only for a multi-view `app:*` spec. Otherwise drop it silently (or error under a strict flag). Also assert `stale-spec` is the **same variant** as `spec` (§13.5) and strip every stateful node (`text_input`, `checkbox`, `switch`, `enum_list`, `slider`) and **every `editor` regardless of `publish_state`** — verified against §13.5: "`stale_spec` MUST NOT contain a stateful node or any `editor`". **No builder or stripper for this exists in `jetpacs-widgets.el`** (grep confirms); JC-0 owns `jetpacs-shell--strip-stateful`, which must honor the `jetpacs--opaque-members` (`:args :meta :value`) skip discipline or it will rewrite application payload data.
8. **GATE 3 — capability discipline (plan §2.5-4).** By prefix: `notification:` requires `"surfaces.notification"`, `widget:` requires `"surfaces.widget"`, `tile:` requires `"surfaces.tile"` in `(ebp-client-granted client)` — a **vector**, so `seq-contains-p`. `app:` is ungated. ebp does **not** enforce this.
9. **GATE 4 — new sender gates from ratified amendments.**
   - **#85 (§14.1):** scan `spec` for any ActionDescriptor with `when_offline` = `"wake"`; if present and `"offline.wake"` is not in `granted`, **refuse** — a `wake` descriptor in an ungranted session is now `1201 content-invalid` and voids the whole surface. `jetpacs-action` validates the ttl coupling but has no client handle, so this can only live here.
   - **#84 (§4.5/§19):** any `editor` node whose document text exceeds `(plist-get (ebp-client-limits client) :max_editor_bytes)` must not be presented. **Verified:** `max_editor_bytes` appears nowhere in `ebp.el` — this is a genuine new gate with no endpoint support.
10. **Send.** Inside a `condition-case` (a transport failure degrades to the snackbar requeue + `message`, matching poc):
    ```elisp
    (jetpacs--claim "surface" surface)
    (setq revision
          (ebp-client-surface-update client surface spec
                                     :stale-after-s stale-after-s
                                     :stale-spec    stale-spec
                                     :current-view  current-view
                                     :reset-input-ids reset-input-ids
                                     :callback (or callback
                                                   #'jetpacs-shell--push-callback)))
    ```
    The default callback treats **`"applied"` and `"stale"` as success** (§13.2) and only `ERROR` non-nil as failure; it checks `ERROR`, not `RESULT` (for a `{}` result both are nil). Note `surface.update` inherits jsonrpc's **10 s** default timeout — `ebp-client--surface-request` passes no `:timeout` and there is no per-call key — so a large spec or a busy device yields a spurious `(nil (:code -32000 :message "timeout"))` even though the Companion may still apply the push.
11. **Run `jetpacs-shell-after-push-hook`** — synchronously, immediately after step 10 returned the revision, success path only. This is the generation-sweep contract (S2).
12. **Return the revision.**

**Gate ownership summary.** Push path (`jetpacs-shell-push`): §2.5-1 (step 6), §2.5-4 (steps 7-8), plus #84/#85 (step 9). Dispatch path (`jetpacs--dispatch`): §2.5-2 (§4.5) and §2.5-3 (the absent confirm gate). §2.5-5 and §2.5-6 belong to JC-1 and JC-3b respectively and are not implemented here.

---

## 6. New sender duties, ratified amendments #67-86

Mapping taken from `ebp/SPEC-CHANGES.md` rows 34-53, **not** from `DRAFT-amendments-*.md` (whose numbering is pre-renumbering and misleading).

### JC-0 must honor now

| # | § | Duty | Where |
|---|---|---|---|
| **85** | §14.1 | A `wake` descriptor without the current session's `offline.wake` grant is `1201 content-invalid` and voids the surface. Emacs must gate authoring on the **live grant**, not on a configured target. | `jetpacs-shell-push` gate 4. Also applies to a trigger's `:policy wake` when a triggers rung lands. |
| **84** | §4.5, §19, §19.4 | Emacs MUST NOT present a synchronized `editor` whose document text exceeds `max_editor_bytes` (REQUIRED in the welcome when `editor.sync` is granted). | `jetpacs-shell-push` gate 4. The `edit.apply` half is ebp.el's (below). |
| **70** | §13.6 | A changed authored `value` alone no longer reseeds a dirty draft, and a local `editor`'s text survives a same-identity snapshot **regardless of `publish_state`**. Reseeding now requires a presentation-identity change (a new `key`/`id`) or `reset_input_ids` — and a `publish_state:false` editor cannot be named in `reset_input_ids` at all. | Push-path discipline: renderers that want to reseed must change the node key. ebp's `:reset-input-ids` plumbing and reset history already exist. |
| **74** | §23.3 | Calendar titles/times, SMS sender identifiers, call numbers and §21.4 sensitive fire data MUST NOT reach normal logs, diagnostics, or crash reports. | The `jetpacs--dispatch` shim must not `message`/echo `PARAMS`. poc `jetpacs-surfaces.el` logged liberally; §4.3 above logs the action name only. |
| **78** | §9.1 | The pairing token and recoverable HMAC key material MUST use keystore-backed encrypted storage where available. | ebp.el takes `:token` in config and never persists it; **no config module exists** to route it to `auth-source`/GPG. JC-0 should at minimum not write a token to disk in plaintext and should document the gap. |

### Belongs to ebp.el (record as endpoint gaps; do not implement above the boundary)

| # | § | Gap |
|---|---|---|
| **71** | §19.3 | `ebp-client--handle-edit-open` blindly `puthash`es the seed over a live mirror. Needs a distinct `:edit-open-function` seam (`ebp-client-register-handler` is single-slot, so an application cannot intercept). The reconcile *decision* needs Emacs's real buffer — a later editor-consumer rung. |
| **84** | §19.4 | `ebp-client-edit-apply` computes the length then sends unconditionally; it must pre-check the resulting length against `max_editor_bytes` and refuse locally. |
| **75** | §21.3, §21.7 | A `when` gate may include only predicate types in `device.state_types` (`time.window` exempt). `ebp-client-triggers-set` passes `:when` through unvalidated and **there is no `state_types` accessor at all** — only `ebp-client-device-trigger-types` and `-device-caps`. **Verified by grep.** |
| **72** | §9.1 | Revocation erasure must be durable and resumable. ebp owns the receipt store (SQLite/append-only) but ships no forget/unpair entry point — add `ebp-client-forget-pairing`. |
| **80** | §4.2, §7.5 | Live path already uses jsonrpc.el integer ids and is conformant; the stale string-only `ebp-valid-request-id-p` helper and its retired §7.2 docstring should be relaxed. |

### Already satisfied — no work

**#68** (§16.1 present-but-invalid optional member): `jetpacs--check-attr` bounds `alpha`/`fill_fraction` 0..1, dims ≥0, `clip` boolean, `max_lines` ≥1. *Caveat: hand-built plists bypass it.* **#69** (§15.3 bounded replay backoff): `ebp-replay-retry-delay`/`-max` + `ebp-client--schedule-replay-retry`. **#82** (§17.1/§17.5 `selected` varies-per-node): `jetpacs-chip` uses `--check-bool`, `jetpacs-month-grid` uses `--check-date`. **#83** (§10.3 flush carries `revision_seen`): `ebp-client--handle-state-changed` + `--state-reset-p`. **#74** endpoint half: `ebp-log-events` defaults nil so the jsonrpc events buffer is `:size 0`; receipts store `event_id` + timestamp only.

### Not an Emacs duty

**#67** (§18.6 at-least-once reminders), **#73** (§20.3 intent allowlist deny-by-default — a later capability rung should surface the 1001/1002 denial rather than retry), **#76** (§21.1 permission-blocked trigger stored unarmed), **#77** (§5.2 Companion accepts a second dial for supersession — makes redial recovery reachable, but `ebp-connect` still leaves reconnection policy to the caller), **#79** (§9.2 equal-work dummy HMAC), **#81** (§15.2 Companion stamps the durable-event clock), **#86** (§17.2/§9.1 image cache license and revocation erasure — the *separate* §17.2 advertise-form sender gate is already tracked as JC-3b in plan §2.5-6).

---

## 7. Exit gate checklist

Byte-compile with `byte-compile-error-on-warn` (three new files added to `test/run-tests.sh` after the existing `ebp.el`/`jetpacs-widgets.el` guards), then the ERT suites, then the smokes. New file: `test/jetpacs-floor-test.el`, slotted in exactly like the widget suite.

**Delineation guard** — unchanged and must stay green: `ebp.el` loads alone and defines no `jetpacs*` symbol. The three new files sit **outside** it (they require `ebp`).

**ERT — async (ported near-verbatim from `llm-poc/test/jetpacs-tests.el:2101+`, ~150 L)**
- [ ] first call → `'(pending)`, loader started exactly once, `jetpacs-async--push-timer` is a `timerp`; `--flush-push` fires exactly one push; second call reads `(ready . V)` without restarting the loader
- [ ] `reject` → `(error . MSG)`; a synchronously-throwing loader → `(error . MSG)` and never takes down the push
- [ ] two completions in one tick coalesce to **one** push
- [ ] `--after-push` sweeps an entry stamped below the generation, runs its cancel exactly once, and advances the generation; a completion for a swept entry causes **no** push and **no** cache write
- [ ] `jetpacs-async-clear-owner` drops only its owner's entries and runs their cancels *(has no production caller at JC-0 — this test is the only thing keeping it from reading as dead code)*
- [ ] `jetpacs-async-reset` clears cache, generation, and timer

**ERT — the defaction shim, with a stubbed client (`ebp-client-create` + no connection, driving `ebp-client--handle-event-action` directly, as `ebp-wire-test.el` does)**
- [ ] arg decode: `(plist-get (plist-get params :args) :k)` reaches the handler; the handler receives the **full** params (asserts `:event_id`, `:surface`, `:revision_seen`, `:fields` are all visible) — §2.5-2
- [ ] `accepted` → `{"status":"accepted"}` **and** the receipt is committed (a second event with the same `event_id` returns `duplicate` without invoking the handler)
- [ ] `stale` → `{"status":"stale"}` — **required by the plan's exit gate, not just `accepted`**
- [ ] `rejected` → `{"status":"rejected"}`
- [ ] a handler returning nil / t / a stray string → `rejected` + a warning, **never** `-32603`
- [ ] a handler signalling `error`, and one signalling `quit`, both → `rejected`; nothing escapes to jsonrpc
- [ ] `jetpacs-attach` replays a top-level-registered action into `(ebp-client-actions client)` — an event for an action registered **before** attach round-trips
- [ ] **no `prompt.*` action and no `"event.action"`/`"state.changed"` handler is registered by jetpacs** (boundary assertion)
- [ ] use a per-client `(make-temp-file)` `:receipt-file` in every test — the default `ebp-receipt-file` is process-wide and a stale receipt silently turns an event into `duplicate`

**ERT — the §16.2 gate against a deliberately under-advertised fixture (§2.5-1)**
- [ ] Reuse `ebp-test--welcome-result`, whose default `surface_profiles.app.node_types` is **already** exactly the 8 Core Node Set types with `:features []` — the perfect under-advertised fixture. Verified in `test/ebp-wire-test.el:295`.
- [ ] a spec containing `card` (or `chart`) is **refused before** `ebp-client-surface-update` is called (assert the companion received **no** `surface.update`)
- [ ] the same spec passes `(jetpacs-check-profile tree 'app)` — proving the reference defconst **cannot** witness this, which is the whole point of the gate
- [ ] a `stale_spec` carrying an unadvertised type is refused too (§13.5)
- [ ] a **missing** profile (`:notification` absent from the welcome) refuses the push rather than skipping the gate (§10.2)
- [ ] the vector→list coercion: passing `["text"]` straight to `jetpacs-check-node-types` errors, the coerced call does not
- [ ] a builtin absent from `profile.builtins` is refused (§10.2)
- [ ] `:current-view` is omitted for a single-root spec and present for a `jetpacs-multi-view` spec (§13.4)
- [ ] a `notification:` push with `"surfaces.notification"` ungranted is refused
- [ ] a `when_offline: "wake"` descriptor with `"offline.wake"` ungranted is refused (#85)

**ERT — ownership + state**
- [ ] `with-jetpacs-owner` + `jetpacs--claim` warns on a cross-owner clash and errors under `jetpacs-strict-namespaces`; same-owner re-registration is silent
- [ ] `jetpacs--owned-names` enumerates for teardown
- [ ] `jetpacs--on-state-changed` fans out to a `jetpacs-on-state-change` subscriber and does **not** double-store; a signalling subscriber does not break the dispatch
- [ ] `jetpacs-on-state-change` has **zero** surviving call sites in the port set (all 4 poc callers are in `jetpacs-minibuffer.el`, deleted by JC-4) — it ships unexercised unless this ERT covers it

**ERT — push mechanics**
- [ ] `(jetpacs-shell-push)` with zero arguments works (arity pin)
- [ ] a builder that signals degrades to the error view and the push still happens; the after-push hook still runs
- [ ] a §16.2 refusal does **not** degrade — it signals out of `jetpacs-shell-push`
- [ ] the snackbar is requeued when the push signals, on both the gate path and the transport path
- [ ] `jetpacs-shell-after-push-hook` runs once per successful push, synchronously (assert against a `cl-letf`'d `ebp-client-surface-update`)

**Live smoke — `test/smoke-floor.el`** (manual / adb harness, not in `run-tests.sh`)
- [ ] `jetpacs-connect 127.0.0.1 8765` with the KAT pairing reaches `ready`
- [ ] a `jetpacs-defaction` handler registered at load time round-trips a device tap to `accepted`
- [ ] `jetpacs-shell-push` reports `"applied"` in its callback
- [ ] wire order on reconnect is `session.hello, auth.response, surface.update, queue.replay, session.ready` — the `:before-replay-function` barrier (assert with the scripted companion, mirroring `ebp-wire-test.el:789`)

---

## 8. Risks and open questions

Each is stated as a decision with options. **None should be resolved by the implementing engineer alone.**

**Q1 — Multi-client. `Recommend: declare single-client.`**
`jetpacs-action-handlers`, `jetpacs--registration-owners`, `jetpacs--state-handlers`, `jetpacs-async--cache`, `--generation` and `--push-timer` are all process globals; `ebp.el` has no client registry and no notion of a "current client" — every `ebp-connect` mints its own. Options: **(a)** document JC-0 as supporting exactly one live client and have `jetpacs-attach` error on a second (recommended — smallest floor, matches every smoke); **(b)** key every registry by client and hold one debounce timer per client (~80 extra lines, and `jetpacs-async` would stop being client-agnostic, which is currently what keeps it free of framework requires).

**Q2 — Surface-id scheme. `Genuinely unresolved.`**
The plan's JC-0 text says "`jetpacs-shell-push` … with **ownership-scoped surface ids**". **Ownership-scoped surface ids do not exist in poc-v1** — the shell pushes one global `"app:dashboard"`, and "ownership" is only (i) `jetpacs--claim`'s warn-on-clash bookkeeping, (ii) a `"<appid>.<view>"` naming *convention* that is mechanically unenforced, and (iii) owner-tagged view/chrome filtering installed by `jetpacs-apps.el`, which is not in the port manifest. This is the single largest spec-vs-source mismatch in the rung. Options: **(a)** one default surface `"app:main"` plus an explicit `SURFACE` argument, ownership tracked only by `jetpacs--claim` (what §2/§5 above assume — smallest, matches poc semantics); **(b)** derive the default as `"app:<jetpacs-current-owner>"`, giving each app its own surface and its own back stack — new design, and interacts with `max_surfaces`/`max_surface_ids`; **(c)** keep a global surface and re-grow the multi-view registry now. Note the §5 design assumed (a); switching to (b) changes `jetpacs-shell-define-root`, `jetpacs-shell-surface-id`, and the reconnect-restore set.

**Q3 — Non-status handler return. `Recommend: rejected + display-warning :error.`**
Options: **(a)** map to `rejected` with a loud warning (recommended — never durably accepts an unknown outcome, and a ported poc body that fell through is almost always a bug); **(b)** let it become ebp's `-32603 "handler returned %S"` (more truthful — "the endpoint broke" rather than "nothing happened" — but a §8 error on `event.action` is a harsher failure mode and gives the Companion nothing to present); **(c)** map nil→`rejected`, non-nil→`accepted` (rejected outright: this is exactly the blanket-accept §2.5-2 forbids, since a ported handler's last form is usually a `message` returning a string). Cost of guessing wrong: (a) can under-report a successful effect; (b) can spam protocol errors during the port.

**Q4 — Which handlers gate on revision lag. `Recommend: opt-in, never automatic.`**
`jetpacs-event-stale-p` is purely mechanical (`revision_seen < floor`). But the floor is claimed at *send* time and only rises, so **any** background push between render and tap makes an otherwise-valid tap look stale — and `jetpacs-async`'s coalesced completion pushes make that common. Blanket-applying it would reject a large fraction of legitimate taps. Options: **(a)** helper only, each handler decides (recommended; the exit gate's `stale` branch is exercised by an index-into-a-snapshot handler like the worked example); **(b)** an automatic gate with a `jetpacs-stale-revision-slack` tolerance — needs a number nobody can justify; **(c)** no `stale` derivation at JC-0 at all, which fails the plan's exit gate.

**Q5 — `jetpacs-on-state-change` keying. `Recommend: bare id, optional surface later.`**
poc keys by bare widget id; ebp keys `input-values` by `(surface . id)` and the hook signature is `(client surface revision id value)`. Options: **(a)** keep bare-id keying — app-side ids are already namespaced, and it keeps the ~4 poc call sites compiling; **(b)** add an optional `SURFACE` and key by the pair, matching ebp. Note this registry has **zero surviving consumers inside the port set** (all 4 poc callers live in `jetpacs-minibuffer.el`, whose JC-4 rebuild deletes them because dialog nodes emit no `state.changed` **by design**, §18.1). It is kept for JC-1..JC-3 app surfaces, so whichever keying is chosen ships untested by any real call site.

**Q6 — Blocking inside an action handler. `Must be settled before the shim is written.`**
This is the JC-0/JC-4 crux. poc's entire reason for `jetpacs--in-action-handler` is that a handler may call `y-or-n-p`/`read-string`/`completing-read` and have it bridged to the phone as a dialog, blocking on `accept-process-output` until the answer arrives. Under ebp the handler runs inside jsonrpc's dispatch extent and its return value **is** the protocol reply. Options: **(a)** forbid blocking outright — the shim documents it, the handler returns a status immediately and drives the prompt from a `run-at-time 0` continuation (recommended; safest, and it makes the `accepted`-means-durable contract honest); **(b)** allow a bounded `accept-process-output` pump inside the handler and accept the reentrancy risk (JC-4's stated bridge design — but a stalled `event.action` reply means the Companion never learns the outcome, possibly forever); **(c)** hybrid — a `jetpacs--inhibit-async-push` flag around the pump so a `run-at-time 0` completion cannot re-enter `jetpacs-shell-push` mid-dialog. Note `jetpacs-files.el`'s `files.grep` currently does the forbidden thing; whichever option wins, that handler needs rewriting when it is ported.

**Q7 — Post-replay refresh has no home.**
poc refreshed on `jetpacs-queue-drained-hook` (replayed taps had just mutated state, so the phone's cached views are behind reality). ebp does §15.3 replay and stores `replay-summary` but exposes **no** replay-complete seam. Options: **(a)** drop it in JC-0 and accept a stale first frame after a reconnect with a backlog; **(b)** add an `:after-replay-function` to `ebp-client-create` (a ~6-line ebp.el change, called where `replay-summary` is set and where the retry timer observes `remaining` reaching 0). Do **not** reimplement replay above the boundary.

**Q8 — `jetpacs-async` re-entrancy with the JC-4 dialog pump.**
`run-at-time 0` fires inside `accept-process-output`, and JC-4 (option Q6b/c) bridges sync-return-over-async with exactly such a pump. A loader completing during a dialog wait therefore re-enters `jetpacs-shell-push` mid-dialog. The poc comment only claims the deferral prevents pushing from within a *build*; it does not cover a nested pump. Decide alongside Q6.

**Owner capture is first-sight-only** (pre-existing poc behavior, port as-is but document): `:owner` is set when the entry is created and never revised, so a KEY first requested under app A and later shared by app B stays owned by A — `jetpacs-async-clear-owner` on B leaves it, on A yanks it from under B.

**Dropping the form layer strands two out-of-tree callers** — `jetpacs-apps.el`'s `jetpacs--forms-of-owner` teardown loop, and `jetpacs-shell.el:623`'s `(setq jetpacs-form-refresh-function #'jetpacs-shell-push)`. Both are outside the JC port set today; whoever ports `apps.el` later must be told the form registry is deliberately absent.

**`ebp-client-theme-set` is broken on the live path** (not JC-0's job, but do not build on it): it emits the *reference* encoder's sentinels (`:false`, `:null`) while sending through jsonrpc.el, whose sentinels are `:json-false` and nil. `(ebp-client-theme-set c :dark :false)` and `:colors 'null` both signal `(wrong-type-argument json-value-p …)`. Only `:dark t`, the default `:dark 'system`, and plist-valued `:colors`/`:syntax` work.

**LOC estimate:** async ~235 (essentially verbatim + ~10 seam lines) + ~150 ERT; surfaces ~330 of which the defaction shim + dispatch wrapper + attach path is ~110 and is the only genuinely hard part; shell ~280 of which the four gates and the stale-spec stripper are ~90 and are entirely new. Total ~845 source + ~400 test.