# AUDIT — JC-0/JC-1 layer conformance (2026-07-24)

6 lenses over the new elisp application layer + today's ebp.el changes,
against SPEC.md with amendments through #86. 58 raw findings -> 10 survivors.
Workflow `wf_a1792c4e-af9`; 7 agents, 0 errors.

**Fixed since this report was written** (commits `c7c8db4`, and the
coding/serializer/durability batch): IMPL 1 (`:coding` regression),
IMPL 4 (volatile-callback `accepted`), IMPL 5 (raw bytes), plus the three
the report lists as already-fixed under Refuted.

**Still open** — IMPL 2 (buffer.act validation), 3 (notification meta
opaque), 6 (strip-stateful invalid specs), 7 (features gate), the 12 P2s
below the cut, and SPEC findings 8-10.

---

All key claims verified empirically. Writing the merged report.

```markdown
## Summary

24 raw findings across 6 lenses → **10 survivors** (7 IMPL, 3 SPEC) after refuting 5 and merging 9 duplicates. Severity: 8 P1, 2 P2.

**Fix first: `ebp.el:1395` `:coding 'binary`.** It is a two-character fix and it silently destroys every inbound frame containing one non-ASCII octet. Verified end-to-end on a real loopback `jsonrpc-process-connection` on Emacs 30.1 — under `:coding binary` a framed `edit.delta` carrying `"café"` is dropped with `Invalid JSON: (1 61 61)`; the identical frame under `:coding 'utf-8-unix` dispatches correctly. Nothing else on the ladder is testable against a real Companion until this is right, and the 33 existing wire tests pass because none sends non-ASCII over the live socket.

Three lens findings were already fixed in `c7c8db4` (aggregate `max_rich_spans`, Core-`text` fallback for unadvertised `rich_text`, `(surface . id)` state keying) — see Refuted.

## IMPL findings

### 1. P1 — `:coding 'binary` drops every inbound frame containing non-ASCII

> §6.2: "The receiver MUST read exactly the declared number of body octets." §6.1: "`Content-Length` MUST equal the number of octets in the UTF-8-encoded JSON body."

`emacs/ebp.el:1393-1395`, `ebp-connect`.

jsonrpc.el creates its process buffer with plain `get-buffer-create` — **multibyte**. `jsonrpc--process-filter` sizes the body with `(- (position-bytes (process-mark proc)) (position-bytes (point)))`. Under `:coding binary` the filter receives a unibyte string; inserting it into a multibyte buffer turns every octet ≥ 0x80 into an eight-bit raw-byte char occupying 2 internal bytes, so `position-bytes` over-counts and the narrowed region ends short. Verified:

```
coding=binary       dispatched=nil     ; + "Invalid JSON: (1 61 61) …{"text":"caf"
coding=utf-8-unix   dispatched=((edit.delta (:text "café")))
```

Failure: any `edit.delta` for a typed em-dash, any `event.action` whose `fields` carry non-ASCII (durable event never answered → Companion re-replays forever), any `state.changed` value, and any **response** — an authenticated welcome with a non-ASCII `server.name`, an `edit.resync` result — which then hits the 10 s/300 s timeout and kills the session. Truncated bodies also leave residue at the head of the parse buffer.

```diff
-                :coding 'binary))
+                ;; NOT `binary': jsonrpc.el's process buffer is multibyte and
+                ;; its Content-Length arithmetic uses `position-bytes', which
+                ;; only matches wire octets when the buffer decodes as UTF-8.
+                :coding 'utf-8-unix))
```
`utf-8-unix` still pins both directions deterministically (the legitimate motive for the change — unset `undecided` could auto-detect a non-UTF-8 charset or DOS eol and mangle the `\r\n` header terminator). Add a regression test driving a real loopback connection with a non-ASCII body.

### 2. P1 — `emacs.buffer.act` runs any command in any live buffer at a wire-chosen offset, and never checks `revision_seen`

> §23.1: "Emacs MUST validate action arguments, text fields, URIs, document IDs, package names, trigger data, and every other received value before use." §23.4: "Emacs MUST validate `revision_seen` and action semantics before accepting an event." §14.5: "it MUST return `stale` when the old context makes the action unsafe or ambiguous."

`emacs/jetpacs-buffer.el:801-810` (handler) → `:747-779` `jetpacs-buffer-invoke-at`.

*(Merges the `security` and `buffer` lenses' two findings — one table fixes both.)*

Total validation is `(and (stringp buffer) (numberp pos) (get-buffer buffer))`. `params` is read only for `:surface`; `:revision_seen` is never touched, and `jetpacs-event-stale-p` — which exists for exactly this ("use this where the action indexes into the snapshot it was tapped against", `jetpacs-surfaces.el:284-295`) — is called from nowhere in the four new files. Nothing records which buffers were ever rendered or which offsets were ever emitted. Contrast the fold path, which *does* have an allowlist (`jetpacs-buffer-fold-commands`, enforced at `:825-840`).

Two failures from one root cause:
- **Unrendered buffer.** `{"action":"emacs.buffer.act","args":{"buffer":"*Customize Group: files*","pos":812}}` → `jetpacs-buffer--widget-at` finds `[Apply and Save]` and `widget-apply-action` writes the user's custom-file. Same primitive reaches every `eww` link (arbitrary URL fetch), `*Help*` file-visiting button, `package-menu` install button.
- **Stale offset.** Tap at offset 812 in revision 41; a `queue` descriptor replays after reconnect; the buffer meanwhile refreshed. `invoke-at` *clamps* 812 into the new buffer and fires whatever now occupies it. Emacs answers `accepted`, so the Companion shows no diagnostic.

Fix — bind the descriptor to the render:
```elisp
(defvar jetpacs-buffer--exposed (make-hash-table :test #'equal)) ; surface -> (rev . hash of (buf . pos))
;; in jetpacs-buffer--render-region: record every emitted (buffer-name . pos)
;; in jetpacs-shell-push: stamp the table with the revision just claimed
(lambda (args params)
  (let ((buffer (plist-get args :buffer)) (pos (plist-get args :pos))
        (surface (plist-get params :surface)))
    (cond
     ((not (and (stringp buffer) (numberp pos) (get-buffer buffer))) 'rejected)
     ((jetpacs-event-stale-p params) 'stale)
     ((not (jetpacs-buffer--exposed-p surface (plist-get params :revision_seen)
                                      buffer pos)) 'rejected)
     (t …))))
```
Keep a `jetpacs-buffer-exposed-buffers` predicate as an independent second gate so an unrendered buffer stays unreachable even on a table-lookup bug.

### 3. P1 — Notification `:meta` is opaque, so §18.5 action descriptors bypass GATE 4 and GATE 1b

> §14.1 (amendment #85): "A Companion that receives a descriptor whose `when_offline` is `wake` in a session that did not grant `offline.wake` MUST reject the containing document with `1201 content-invalid`." §14.2: "Emacs MUST NOT emit a builtin absent from the applicable target's `surface_profiles.<target>.builtins` array." §18.5: "`actions` is an ordered array. Each entry MUST contain `label` and `on_tap`."

`emacs/jetpacs-shell.el:172` (`jetpacs-shell--walk-plists`) + `emacs/jetpacs-widgets.el:1561` (`jetpacs--opaque-members` = `'(:args :meta :value)`).

The opaque-member docstring justifies `:meta` solely as "§17.5 chart-point `meta`" and asserts these members "never contain nodes" — but `jetpacs-notification-surface` (`jetpacs-widgets.el:1487-1492`) emits the §13.4/§18.5 surface metadata under the **same** `:meta` key, and §18.5 meta contains `actions[].on_tap` ActionDescriptors. GATE 4 (`:264`) and GATE 1b (`:181`) both run through that walker. Verified:

```
WALKER saw when_offline values: nil        ; the "wake" descriptor is invisible
```

Failure: a notification with a `wake` snooze action on a session without `offline.wake` sails past GATE 4; per #85 the Companion 1201-rejects the whole document and the notification never renders. Same blindness ships an unadvertised builtin. Notification actions are the *only* place §18.5 puts descriptors, so sender-side enforcement of the security amendment is dead exactly where it matters. `jetpacs-notification-surface` also runs no `jetpacs--check-descriptor` on `meta`, unlike `jetpacs-widget-surface`'s `:header-action`.

Fix: split the opaque set — chart-point `meta` stays opaque, notification-spec `meta` does not. Simplest correct form: in `jetpacs-shell--gate-spec` / `--gate-amendments`, explicitly walk `(plist-get (plist-get spec :meta) :actions)` before the generic walk; and add `jetpacs--check-descriptor` over each entry's `:on_tap` in `jetpacs-notification-surface`.

### 4. P1 — Every `accepted` is a volatile-callback accept; `1500 event-retry` is unreachable

> §14.4: "Before returning `accepted`, Emacs MUST durably commit the EventId together with either the completed application effect or a durable work item that owns that effect. If it cannot make that commitment, it MUST return `1500 event-retry`. **Returning `accepted` merely because a volatile callback was scheduled is not conforming.**"

`emacs/jetpacs-buffer.el:789-797` (`jetpacs-buffer--defer-tap`) and `:801-821`; contract at `emacs/jetpacs-surfaces.el:248-275`.

*(Merges four lenses. This is structural under D2, not a local slip.)*

`--defer-tap` is a bare `(run-at-time 0 nil (lambda () (ignore-errors (funcall effect)) …))`; both handlers call it and return `'accepted`. `ebp.el:962-964` then does its half **correctly** — `ebp-client--receipt-commit` fsyncs the EventId *before* replying, and falls back to a replay-retry when the commit fails. So the receipt is durable while the effect is not: precisely the construction §14.4 names as non-conforming. `jetpacs-defaction`'s docstring simultaneously mandates "MUST NOT block (decision D2)" and "MUST return `accepted` only once the effect is durable", with no durable work-item seam anywhere in the floor — the two sentences are jointly unsatisfiable.

Compounding it: `jetpacs-surfaces.el:222-237` wraps the handler in `condition-case` whose `(error …)` clause catches everything. Verified `(get 'jsonrpc-error 'error-conditions)` = `(jsonrpc-error error)`, so a handler's deliberate `ebp-client--error … 1500 … "event-retry"` is **swallowed and downgraded to `rejected`** — which §14.4's disposition table makes permanent (Companion deletes the record and diagnoses). No jetpacs handler can express retry at all; the documented return vocabulary admits only `accepted`/`stale`/`rejected`.

Failure: user taps a `when_offline: queue` descriptor. Emacs returns `accepted`, Companion deletes its durable record, Emacs is killed before the 0-delay timer fires. The effect never happens, and because the receipt *was* committed, redelivery answers `duplicate` — §14.4 forbids repeating it. Silent, permanent intent loss with a success indication on the phone.

Fix, in order of altitude:
1. Both Tier-0 effects are local, bounded buffer operations. **Run them synchronously in the handler** and defer only `jetpacs-buffer--refresh`. D2's ban targets blocking *on the user*, not on local work.
2. Re-signal `jsonrpc-error` instead of swallowing it:
```diff
       (quit 'rejected)
+      (jsonrpc-error (signal (car err) (cdr err)))
       (error
```
3. Add a fourth return value `retry` to `jetpacs-defaction`'s contract, mapped by `jetpacs--dispatch`/`ebp-client--handle-event-action` onto the existing `1500 event-retry` path.
4. Amend **decision D2** in `docs/SPEC-JC-0-floor.md §0`: a handler that defers its effect to a volatile continuation MUST NOT answer `accepted`.

### 5. P1 — Raw undecodable bytes in buffer text produce an unserializable node

> §4.1: "A sender MUST NOT emit ill-formed Unicode… After JSON escape decoding, every string and member name MUST be a sequence of Unicode scalar values."

`emacs/jetpacs-buffer.el:413` (`jetpacs-buffer--line-spans` → `buffer-substring-no-properties` → `jetpacs-span`), same exposure at `:337` `jetpacs-buffer--string-spans`.

Emacs stores an undecodable octet as a char in `#x3FFF80..#x3FFFFF`, which is not a Unicode scalar value. Verified:

```
chars: (4194248 4194249)
json-serialize: (wrong-type-argument json-value-p "\310\311")
surrogate:      (wrong-type-argument json-value-p "…")
```

Failure: open any file that is not valid UTF-8 (a latin-1 source, a binary, a truncated log, magit's binary-file diff, `*compilation*` with a mid-stream broken sequence). With a real Companion `bytes-left` is non-nil, so `jetpacs-buffer--node-bytes` runs per line and signals inside the builder; `jetpacs-shell--build` catches it and the phone shows the error card instead of the buffer. Called outside a registered builder the signal escapes into `json-serialize` on the live push. **The Core-`text` fallback added in `c7c8db4` does not help** — it hits the same serializer.

Fix — sanitize at span construction, before either node form:
```elisp
(defsubst jetpacs-buffer--scalar-text (s)
  "S with raw-byte and surrogate chars replaced by U+FFFD (SPEC 4.1)."
  (replace-regexp-in-string "[\x3FFF80-\x3FFFFF\xD800-\xDFFF]" "\uFFFD" s t t))
```
Apply in `--line-spans` (:413) and `--string-spans` (:337). Also wrap the two `json-serialize` budget probes (`jetpacs-shell.el:275`, `ebp.el:1130`) in `condition-case` so an unencodable editor value becomes a typed refusal rather than an escaping `wrong-type-argument`.

### 6. P1 — `--strip-stateful` emits a structurally invalid SurfaceSpec, sinking the whole push

> §13.4: widget row "`{title: string, body: Node, empty?: Node, header_action?: ActionDescriptor}`"; "`initial_view` MUST name an existing view." §13.2: "If the content is invalid, it MUST return `1201 content-invalid`, MUST leave the previous snapshot unchanged."

`emacs/jetpacs-shell.el:189-218` `jetpacs-shell--strip-stateful`, consumed at `:332-340`.

Ran the real function against real builder output:
```
widget-surface stripped: (:title "Title")                      ; REQUIRED body GONE
multiview stripped: initial_view="list" keys=("detail")        ; initial_view names no view
notif stripped: nil                                            ; handled by the uncommitted warning
```
A member whose value strips to nil is omitted (`:213`) and a hash key whose value strips to nil is dropped (`:199-202`). The **uncommitted working-tree change covers only the third case** (wholly-nil root → warn + drop). The first two still ship.

Failure: both results are content-invalid. `jetpacs-shell-push` passes them as `:stale-spec`, the Companion 1201-rejects the *entire* request per §13.2, and the correct primary `spec` is discarded with it — the surface keeps the previous snapshot and only a `message` is logged. No gate catches it: GATE 1 checks node types/builtins, not variant shape.

Fix: re-validate after stripping and signal, consistent with GATE 1's "a sender MUST is loud".
```elisp
(let ((stripped (jetpacs-shell--strip-stateful stale-spec)))
  (cond
   ((null stripped) (display-warning …) (setq stale-spec nil))
   ((and (plist-member stale-spec :body) (null (plist-get stripped :body)))
    (error "jetpacs: stale_spec lost its REQUIRED body to 13.5 stripping"))
   ((and (plist-get stripped :views)
         (not (gethash (plist-get stripped :initial_view) (plist-get stripped :views))))
    (error "jetpacs: stale_spec initial_view %S names no surviving view (SPEC 13.4)"
           (plist-get stripped :initial_view)))
   (t (setq stale-spec stripped))))
```
Better still: signal on a stateful node in `stale_spec` rather than silently sanitizing — §13.5 makes it the author's error.

### 7. P1 — GATE 1 never gates the profile `features` array

> §10.2: "Each profile MUST contain distinct `node_types`, `builtins`, and `features` arrays… Emacs MUST gate every emitted node, builtin, **and constraining feature** against the target profile and MUST NOT interpret a missing profile or list as support for everything." §17.2: "an image whose URI form is not advertised in the applicable target's `features` is content-invalid: the Companion MUST reject the containing surface with `1201`." §17.7: "A registered identifier MUST appear as `toolbar.<identifier>` in the applicable profile's `features`; an unknown or unadvertised identifier makes the node invalid."

`emacs/jetpacs-shell.el:234-237` `jetpacs-shell--gate-spec`.

Binds only `:node_types` and `:builtins`. `grep -n feature emacs/*.el` returns exactly one hit — a comment at `jetpacs-widgets.el:289`: *"Only the URI FORM is checked here; per-target feature advertisement is a runtime concern (JW-7)."* The builder explicitly defers the gate to the shell; the shell does not implement it. Third of §10.2's three mandated gates is absent from the whole application layer.

Failure: Companion advertises `image` in `node_types` and `features: ["image.https"]`. A builder emits `(jetpacs-image "data:image/png;base64,…")` — `jetpacs--check-image-url` accepts `data:image/`, GATE 1 accepts `image`. The Companion 1201-rejects the whole `surface.update`; §13.2 leaves the previous snapshot; `--push-callback` only `message`s. Same for `(jetpacs-editor "body" :toolbar "org")` when `toolbar.org` is unadvertised.

```diff
     (let ((types (append (plist-get profile :node_types) nil))
-          (builtins (append (plist-get profile :builtins) nil)))
+          (builtins (append (plist-get profile :builtins) nil))
+          (features (append (plist-get profile :features) nil)))
       (jetpacs-check-node-types spec types what)
       (jetpacs-shell--check-builtins spec builtins what)
+      (jetpacs-shell--check-features spec features what)
```
where `--check-features` walks for `(:t "image" :url U)` requiring `image.https`/`image.data` by prefix, and `(:t "editor" :toolbar S)` with S a string requiring `(concat "toolbar." S)`. See SPEC finding 9 — the SPEC gives you no way to enumerate beyond these two families.

---

**Below the cut — verified P2 IMPL, one line each** (all confirmed against file + SPEC; no writeup to stay within the cap):

| File:line | Defect | SPEC |
|---|---|---|
| `jetpacs-shell.el:242-252` | No `editor.sync` gate anywhere (`grep` finds zero hits in `emacs/`); GATE 4's editor branch is dead when ungranted because it is wrapped in `(when max-bytes …)` and `max_editor_bytes` is REQUIRED only *when* the grant exists | §17.4, §10.2 |
| `jetpacs-shell.el:271-279` | #84 gate sizes `:value` (an optional seed, absent on re-push of an open document), not the document text | §19 preamble, §4.5 |
| `jetpacs-shell.el:147-155` | Builder-crash degrade emits a bare `column` for *every* namespace; illegal as a `notification:`/`widget:` SurfaceSpec, so the error view can never show there | §13.4 |
| `jetpacs-shell.el:121-127` | `surface.remove` issued while disconnected is dropped *after* the registry entry is deleted — lost forever; nothing counts `max_surfaces`; `jetpacs--owned-names` (the "teardown enumerator") has no caller | §13.1, §4.5 |
| `jetpacs-shell.el:306-309` | `jetpacs-shell-push` cancels the debounce timer and clears **all** `--repush-pending` regardless of which surface it is pushing — owner B's pending repush is silently dropped by owner A's push | §13.5 |
| `jetpacs-shell.el:151` | `--build` calls the builder with **no** `jetpacs-current-owner` binding, though the registry entry records `:owner` — so `jetpacs-ui-state` inside a builder resolves to `app:main` on every repush/async-flush path | §14.6 |
| `jetpacs-shell.el:342-343` | `current_view` forwarded without checking membership in `spec.views`, and without checking the namespace is `app:` | §13.4 |
| `jetpacs-surfaces.el` (nowhere) | `view.switched` is never allowlisted — `grep` finds it only in `test/smoke-views.el:39`. `ebp.el:957-958` answers `rejected "action not allowlisted"`, so **every tab tap shows an error toast** | §14.2 |
| `jetpacs-surfaces.el:234-237, 226-232, 341-342` | Three unconditional log sinks format `error-message-string`/`%S`, which embed the offending datum — an SMS body, a calendar title, editor content — into `*Messages*`, contradicting the same file's docstring claim at `:207-209` | §23.3 (#74) |
| `ebp.el:604-620` | `forget-pairing` nils a **private** config copy (verified: client `nil`, caller's plist still `"SECRET"`); swallows `delete-file` failure with `ignore-errors` and reports success; unlinks a *process-global* receipt store shared by every pairing; leaves `input-values`, `editors`, `revisions` populated | §9.1 (#72) |
| `jetpacs-surfaces.el:291-295` | `jetpacs-event-stale-p` compares against `ebp-client-revisions`, which `ebp.el:1186-1188` claims at **send** time and never rolls back on error — so a refused update makes the surface permanently "stale" | §14.5 |
| `jetpacs-buffer.el:503` | Budgets are re-initialized to the full limit on every `--render-region` call; two regions in one spec, or spec + stale_spec, each spend a whole `max_frame_bytes - 2048` | §4.5 |

## SPEC findings

### 8. P1 — §13.4 defines no SurfaceSpec variant for the `tile:*` namespace

> §13.4: "The namespace determines the exact SurfaceSpec variant:" — the table has rows for `app:*`, `notification:*`, and `widget:*` **only**, and closes "Any other combination MUST receive `1201 content-invalid`."

Verified: `grep -n tile ebp/SPEC.md` hits §13.1 (`:1033`), §10.2 (`:874`, `:883`), §22.1 (`:3379`) — and **nothing in §13.4 or §13.7**. Amendment #39 added `tile:*` claiming it is "exactly parallel to notification/widget" but never touched the variant table. `contract.json` has no tile spec shape.

The new code committed to the namespace anyway: `jetpacs-shell.el:93-101` maps prefix `"tile"` → `:tile`, `:242-252` demands the `surfaces.tile` grant — but nothing decides what shape a tile spec is, because the SPEC never says. `:342` also lets a multi-view tile plus `current_view` through, since §13.4's multi-view prohibition names only notification and widget.

Divergence: `(jetpacs-shell-push "tile:battery")` sends a bare root Node. A Companion reading "parallel to notification/widget" validates against a wrapper and answers 1201; one reading "unlisted means app-like" accepts. Same bytes, opposite outcome.

**Amendment.** Add a `tile:*` row to §13.4's table and to §13.7. A Quick-Settings tile is a fixed slot, so either:

> | `tile:*` | `{label: string, body?: Node, state?: enum, on_tap?: ActionDescriptor}`; multi-view is prohibited |

or, minimally: "`tile:*` uses the `widget:*` schema; multi-view is prohibited." Extend the closing sentence to "`current_view` is valid only for a multi-view `app:*` spec; `notification:*`, `widget:*`, and `tile:*` MUST NOT carry `views`. Any other combination MUST receive `1201 content-invalid`." Project the shape into `contract.json` and add a golden. **Until ratified, `jetpacs-shell.el` should refuse a `tile:` push outright rather than guess.**

### 9. P2 — Profile `features` have no registry, yet §10.2/§24.2 require sender-side feature gating

> §10.2: "Emacs MUST gate every emitted node, builtin, and constraining feature against the target profile." §24.2 lists "explicit capability and per-target node, builtin, and feature gating" as an Emacs core-conformance MUST.

Verified: the document never enumerates the feature namespace. `grep -n feature ebp/SPEC.md` finds normative feature *names* in exactly two places — `image.https`/`image.data` (§17.2, `:1900-1907`) and `toolbar.<identifier>` (§17.7, `:2200`). §22.1 is a capability registry, §21.5 a trigger catalog, §20.3 a device-capability catalog; there is **no feature registry**, and `contract.json`'s top-level keys (`capabilities`, `trigger_types`, `state_types`, `theme_roles`, `syntax_roles`) include no `features`.

Consequence: a sender cannot write the gate §24.2 requires — it can only hard-code today's two families (which is exactly what IMPL finding 7's fix must do). Any future or vendor `features` entry is ungatable by construction, and two senders will disagree about whether a given construct is "constraining."

**Amendment.** Add a feature registry section parallel to §22.1 (the amendment-#57 genre — enumerate the vocabulary the spec already relies on). For each entry give the constrained construct and the §25-required sender-side skip rule:

> | Feature | Constrains | Sender rule when absent |
> |---|---|---|
> | `image.https` | `image.url` with an `https:` scheme | omit the `image` node |
> | `image.data` | `image.url` with a `data:image/*` scheme | omit the `image` node |
> | `toolbar.<identifier>` | `editor.toolbar` naming a registered identifier | omit `toolbar`, or supply an inline ToolbarItem array |

Project it as a `features` key in `contract.json` so a validator and a sender can both enumerate it; cross-reference from §10.2's gating sentence and §25's new-feature checklist.

### 10. P2 — §17.6 never defines snackbar presentation lifetime or re-show semantics

> §17.6 defines the member as "`snackbar: string`" and pins exactly one behavior: "The Companion MUST dispatch a snackbar action only on a user tap, never on timeout."

Verified: `grep -n snackbar ebp/SPEC.md` returns **only** lines 2184 and 2187. Nothing states when a snackbar is presented, for how long, or whether an accepted snapshot carrying the same string re-presents it.

The implementation asserts a rule that is not in the SPEC and is *built on it*: `jetpacs-shell.el:388` — "The Companion re-shows a snackbar only when its text changes" — and `:355-356` injects `:snackbar` for one push only, `:370-373` drains the slot immediately after the send, so the very next push omits the member entirely.

Divergence, reachable within one second given the 0.5 s repush debounce (`:129-143`) and `jetpacs-async` completion pushes: Companion A treats snackbar as snapshot state and dismisses it when the next snapshot omits the member — the user never reads the message. Companion B treats each accepted snapshot carrying a non-empty snackbar as a fresh presentation — a builder that hardcodes a string flashes it on every push. Emacs can express neither "present once" nor "dismiss".

**Amendment.** Add to §17.6, in the style of #59/#60:

> The Companion presents `snackbar` when an accepted snapshot introduces a value that differs under Section 4.3 equality from the value in the previously accepted snapshot for that surface. An unchanged value MUST NOT re-present. An absent or empty `snackbar` dismisses any snackbar currently visible for that surface. A presented snackbar SHOULD remain visible for at least 4 seconds and MUST be dismissible by the user; `snackbar` carries no presentation identity under Section 16.1.

## RISK notes

Verified as latent traps rather than current violations — no fix required this rung, but each is an invariant nothing enforces:

- **`max_rich_spans` is absent from the reference Companion's welcome.** `grep -rn 'max_rich_spans\|maxRichSpans' companion/` returns **zero hits**, while `NodeSupport.kt:19` advertises `rich_text`. So `spans-left` is always nil and the entire aggregate-span machinery `c7c8db4` just added is dead code against the only Companion that exists — a 500-line font-locked buffer ships tens of thousands of spans bounded only by the frame. §4.5 makes the limit REQUIRED when `rich_text` is advertised; both sides are non-conforming. Emacs side: fall back to a conservative self-imposed default and `display-warning` that the peer's welcome is incomplete. Companion side: add the limit and thread a document-wide counter through `SpecValidator.Ctx` as `maxChartPoints` already is.
- **The dispatcher's prompt pins are in the wrong dynamic extent.** `jetpacs-surfaces.el:218-221` binds `completing-read-function`/`read-file-name-function`/`read-buffer-function` around the *handler*, but D2 puts the effect in a `run-at-time` continuation that runs after the `let` unwinds — and `jetpacs-buffer--widget-invoke:709` calls `read-string` from exactly there. On a headless `--daemon` nothing answers it: main loop wedged, no further frames read, session dies on timeout. Adopting IMPL finding 4's synchronous-effect fix resolves this for free.
- **`disabled-command-function` is bound to nil** (`:221`) for the whole dispatch extent, with no comment justifying it while the three sibling bindings are justified. It makes a slip *succeed silently* rather than fail — a remote tap resolving to a command the user deliberately disabled runs with no confirmation, from a source §23.1 places outside the trust boundary. Bind it to a function that signals instead.
- **`args` decoding collapses three distinct JSON values.** Verified: `{"a":{}}`, `{"a":null}` and an absent `a` all yield nil from `plist-get`; `plist-member` separates absent from the other two but cannot separate `{}` from `null`. And `false` decodes to `:json-false`, which is **truthy** in Elisp — so `(when (plist-get args :force) (delete-region …))` fires on an explicit `false`. §4.1 forbids coercing among these; §14.1 requires handler validation, but the floor ships no validators and the two handlers hand-roll `stringp`/`numberp`. Add `jetpacs-arg-bool`/`-string`/`-int` and state the three-way collapse in `jetpacs-defaction`'s docstring, which currently says only "nil for null".
- **`jetpacs-ui-state` is the exact store §14.1 forbids handlers from consulting** ("it MUST NOT substitute its newest `state.changed` or welcome `input_state` value"). It is the file's only advertised state accessor, callable from anywhere, with no warning in its docstring — while `jetpacs-in-action-p` exists and would make the guard trivial but is used by nothing. Warn when called inside an action extent; add a `jetpacs-event-field` accessor over `(plist-get params :fields)`.
- **No line node carries a `key` or `id`.** Every node's presentation identity is its tree-path index (§16.1: "Tree-path identity is unstable under insertion"), and the one node carrying retained state — the `scroll_here` anchor — is exactly the one whose index moves. The Companion keys its scroll effect on that index (`LayoutNodes.kt:236-238`), so every fold toggle re-fires the scroll and yanks the user back. Add `:key (format "l%d" ln)` per line.
- **Two further SPEC holes worth queuing** (verified, deferred for cap): §16.5 names `scroll_here` in the attribute table at line 1813 and **nowhere else** in the document — no section says which ancestor honors it, and the reference Companion implements it only for *direct children* of the OPTIONAL `lazy_column`, so wrapping in a Core `column` silently no-ops. And §23.2's MUST-NOT binds command *names*, not commands **resolved from untrusted argument data** — which is why IMPL finding 2 violates no sentence today while `jetpacs.buffer.fold` (allowlisted) and `emacs.buffer.act` (not) are both conformant.

## Refuted

Dropped after checking the real files and SPEC text:

1. **"max_rich_spans is capped per line, not aggregate"** (`spec-holes`, P1) — **already fixed** in commit `c7c8db4`. `jetpacs-buffer.el:525` now binds `spans-left` and spends it down across the whole walk (`:582-589`), stopping with a truncation note. `--cap-spans` was also made exact (it could previously return `max+1`). The lens read the pre-fix file. *The residual — budgets reset per `--render-region` call, so two regions or spec+stale_spec each get a full allowance — is real and is listed below the cut.*
2. **"rich_text has no fallback; Tier-0 renders nothing against a Core-only Companion"** (`buffer`, P1 RISK) — **already fixed** in `c7c8db4`. `jetpacs-buffer--rich-text-advertised-p` (`:485-495`) reads the live `app` profile and `jetpacs-buffer--spans->text` (`:497-503`) emits Core `text` when `rich_text` is unadvertised.
3. **"§16.2 bans emitting unadvertised node types but defines no sender remedy"** (`spec-holes`, P2 SPEC) — the concrete consequence the finding rested on (Tier-0 dead against a Core-only Companion) is gone with #2. The abstract gap is arguable but no longer forces a divergence in this codebase; not worth an amendment slot ahead of the tile hole.
4. **"State fan-out keys subscriptions by bare widget id"** (`surfaces` P2 + `spec-holes` P2 RISK — same defect, two lenses) — **already fixed** in `c7c8db4`. `jetpacs-surfaces.el:320` now does `(puthash (cons (or surface (jetpacs--default-surface)) id) …)`, `:338` looks up `(cons surface id)`, and `-clear` takes an optional surface. The docstring at `:311-316` explicitly retires decision Q5. (The file header comment at `:26-27` still states the old Q5 — editorial, worth deleting.)
5. **"`--strip-stateful` returning nil silently ships a stale_spec-less push"** — the third of that finding's three cases is **fixed in the uncommitted working tree** (`jetpacs-shell.el:332-340` now warns and drops). The other two cases (widget loses REQUIRED `body`; `initial_view` names no surviving view) are unfixed and verified — kept as IMPL finding 6.

Also corrected in merging: the `ebp-changes` lens implied `ebp.el` mishandles the durable-commitment rule. It does **not** — `ebp.el:962-967` correctly returns a replay-retry when `--receipt-commit` fails. The §14.4 defect is entirely in the application layer's volatile effect (finding 4).
```